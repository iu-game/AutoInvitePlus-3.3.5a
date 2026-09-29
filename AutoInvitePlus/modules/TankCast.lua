-- AutoInvite Plus - Tank Cast (logic layer)
-- A 1 MT + 3 OT list plus one configurable spell/item to cast on them. Kept
-- headless so the window (ui/TankCastWindow.lua) is pure presentation and this
-- file can be unit-tested outside the client (tools/tests/tankcast_spec.lua).
--
-- Casting itself happens in the window's secure buttons with the macro
-- "/cast [target=<Name>] <spell>" (see TK.BuildMacro) - addons cannot cast on
-- a named unit any other way on 3.3.5a. This module never writes to chat.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast

TK.MAX_TANKS = 40       -- slot 1 = Main Tank (always exists), the rest Off-Tanks added on demand (a raid is at most 40)
TK.MAX_PICKS = 8        -- spells/items per tank (the window wraps them 4 per line)
TK.MACRO_MAX = 250      -- macro text limit is 255; keep headroom
TK.dirty = false        -- window has a structural change waiting for combat to end
TK.units = nil          -- lower-case name -> unit token, rebuilt on roster events

TK.TANK_CLASSES = { WARRIOR = true, PALADIN = true, DEATHKNIGHT = true, DRUID = true }

local changedListeners, rosterListeners = {}, {}

local function fire(list)
    for _, fn in ipairs(list) do pcall(fn) end
end
function TK.OnChanged(fn) changedListeners[#changedListeners + 1] = fn end
function TK.OnRoster(fn) rosterListeners[#rosterListeners + 1] = fn end
function TK.Changed() fire(changedListeners) end
function TK.RosterChanged() TK.RebuildUnits(); fire(rosterListeners) end

TK.wasGrouped = nil    -- nil = "never evaluated yet this session", distinct from false
-- True exactly once: the instant the player's group goes from empty to
-- non-empty (solo -> party/raid). Used to auto-open the window on
-- joining/forming a group without re-opening it on every later roster tick.
function TK.JustFormedGroup()
    local grouped = ((GetNumRaidMembers and GetNumRaidMembers() or 0) > 0)
        or ((GetNumPartyMembers and GetNumPartyMembers() or 0) > 0)
    if TK.wasGrouped == nil then
        -- First-ever check (fresh login/reload) only seeds the latch - it must
        -- never fire just because the player happens to already be grouped at
        -- that point, or every /reload during an ongoing raid would re-open a
        -- window the player had deliberately closed.
        TK.wasGrouped = grouped
        return false
    end
    local justFormed = grouped and not TK.wasGrouped
    TK.wasGrouped = grouped
    return justFormed
end

local function say(msg)
    if AIP.Print then AIP.Print(msg) end
end

-- ============================================================================
-- SAVED STATE
-- ============================================================================

-- AIP.db.tankCastByChar[<realm>-<char>] = { tanks = {...}, shown, pos }, keyed by
-- AIP.Utils.CharKey(). Per-character: AutoInvitePlusDB itself is account-wide
-- SavedVariables, so without this every character on the account would share the
-- exact same tank list and picks (a warlock's self-only pick would show up
-- "unknown" on a priest alt - this is that bug, fixed). tanks[1] is the MT and
-- always exists. Defaults live in core/Core.lua but must NOT include `tanks` (a
-- pre-created empty table would block the migration below). Picks belong to the
-- SLOT, not the player.

local function newSlot() return { name = "", picks = {} } end
local function charKey() return (AIP.Utils and AIP.Utils.CharKey and AIP.Utils.CharKey()) or "?" end

-- One-time migration from the pre-multi-tank shape {mt, ots[3], spell}.
local function migrate(c)
    if c.tanks ~= nil then return end
    local tanks = { { name = type(c.mt) == "string" and c.mt or "", picks = {} } }
    if type(c.ots) == "table" then
        for _, n in ipairs(c.ots) do
            if type(n) == "string" and n ~= "" and #tanks < TK.MAX_TANKS then
                tanks[#tanks + 1] = { name = n, picks = {} }
            end
        end
    end
    local spell = type(c.spell) == "string" and TK.ParseSpellInput(c.spell) or ""
    if spell ~= "" then
        for _, t in ipairs(tanks) do t.picks[1] = spell end
    end
    c.tanks = tanks
    c.mt, c.ots, c.spell = nil, nil, nil
end

local repairedFor    -- the per-character table we last validated (repair is not free; do it once per table)

-- Returns this character's (shape-repaired) saved table, or nil before
-- SavedVariables load. The first character to load after this per-character
-- split ships inherits whatever was in the old, account-wide db.tankCast (that
-- data was never really "theirs" - it was shared account-wide by a bug); every
-- other character then starts with a clean list, one time only.
local function cfg()
    local db = AIP.db
    if not db then return nil end
    if type(db.tankCastByChar) ~= "table" then db.tankCastByChar = {} end
    local key = charKey()
    local c = db.tankCastByChar[key]
    if type(c) ~= "table" then
        c = {}
        if type(db.tankCast) == "table" then
            for k, v in pairs(db.tankCast) do c[k] = v end
            db.tankCast = nil
        end
        db.tankCastByChar[key] = c
    end
    if repairedFor == c then return c end
    migrate(c)
    if type(c.tanks) ~= "table" then c.tanks = {} end
    local tanks = c.tanks
    for i = 1, #tanks do
        local t = tanks[i]
        if type(t) ~= "table" then t = newSlot(); tanks[i] = t end
        if type(t.name) ~= "string" then t.name = "" end
        local clean = {}
        if type(t.picks) == "table" then
            for _, p in ipairs(t.picks) do
                if type(p) == "string" and p ~= "" and #clean < TK.MAX_PICKS then clean[#clean + 1] = p end
            end
        end
        t.picks = clean
    end
    while #tanks > TK.MAX_TANKS do table.remove(tanks) end
    if #tanks == 0 then tanks[1] = newSlot() end
    repairedFor = c
    return c
end
TK.Cfg = cfg

local function slots()
    local c = cfg()
    return c and c.tanks or nil
end

-- ============================================================================
-- SANITISING / MACRO TEXT
-- ============================================================================

-- Make free text safe to interpolate into a macro line: no control chars, no
-- macro-structural characters (/ ; [ ]) and no |-escapes; whitespace collapsed.
function TK.Sanitize(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("%c", " ")
    text = text:gsub("[/;%[%]|]", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Player names are letters only (plus UTF-8 bytes for accented names).
function TK.SanitizeName(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("[^%a\128-\255]", ""))
end

-- Accepts a plain name or a shift-clicked spell/item link and returns the
-- sanitised display name ("|cff71d5ff|Hspell:34477|h[Misdirection]|h|r" -> "Misdirection").
function TK.ParseSpellInput(text)
    if type(text) ~= "string" then return "" end
    local linked = text:match("|H%a+:[^|]*|h%[(.-)%]|h")
    if linked then text = linked end
    return TK.Sanitize(text)
end

-- The secure macro a tank row runs on left-click, or nil if it can't be built.
-- "target=" (not "@") for 3.3.5a; /cast resolves both spells and items.
function TK.BuildMacro(name, spell)
    name = TK.SanitizeName(name)
    spell = TK.Sanitize(spell)
    if name == "" or spell == "" then return nil end
    local text = "/cast [target=" .. name .. "] " .. spell
    if #text > TK.MACRO_MAX then return nil end
    return text
end

-- ============================================================================
-- TANK LIST
-- ============================================================================

function TK.NumTanks()
    local t = slots()
    return t and #t or 1
end

function TK.SlotLabel(i)
    if i == 1 then return "MT" end
    return "OT" .. tostring((i or 1) - 1)
end

-- Short label for the row badge: "MT", then "1", "2"... for the off-tanks.
function TK.SlotBadge(i)
    if i == 1 then return "MT" end
    if type(i) == "number" and i >= 2 then return tostring(i - 1) end
    return "?"
end

function TK.GetSlot(i)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    return s and s.name or ""
end

function TK.FindSlot(name)
    if type(name) ~= "string" or name == "" then return nil end
    local t = slots()
    if not t then return nil end
    local lname = name:lower()
    for i = 1, #t do
        if t[i].name ~= "" and t[i].name:lower() == lname then return i end
    end
    return nil
end

local function normalize(name)
    if AIP.Utils and AIP.Utils.NormalizeName then return AIP.Utils.NormalizeName(name) end
    return name
end

-- Assign (or clear, with nil/"") the player in a slot. A name already in another
-- slot MOVES (the picks stay with their slots). Returns ok, errorMessage.
function TK.SetSlot(i, name)
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    if type(i) ~= "number" or i < 1 or i > #t or i ~= math.floor(i) then
        return false, "Bad tank slot."
    end
    if name == nil or name == "" then
        t[i].name = ""
        TK.Changed()
        return true
    end
    local clean = TK.SanitizeName(name)
    local norm = clean ~= "" and normalize(clean) or nil
    if not norm then return false, "Invalid player name." end
    for s = 1, #t do
        if s ~= i and t[s].name:lower() == norm:lower() then t[s].name = "" end
    end
    t[i].name = norm
    TK.Changed()
    return true
end

-- Append an empty off-tank slot. Returns its index, or nil + message.
function TK.AddTank()
    local t = slots()
    if not t then return nil, "Settings are not loaded yet." end
    if #t >= TK.MAX_TANKS then
        return nil, "All " .. TK.MAX_TANKS .. " tank slots are in use."
    end
    t[#t + 1] = newSlot()
    TK.Changed()
    return #t
end

-- Remove an off-tank slot (and its picks); later slots shift down.
function TK.RemoveTank(i)
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    if i == 1 then return false, "The main tank slot can't be removed." end
    if type(i) ~= "number" or i < 2 or i > #t or i ~= math.floor(i) then return false, "Bad tank slot." end
    table.remove(t, i)
    TK.Changed()
    return true
end

-- Put a name in the first empty off-tank slot, adding a slot if none is empty
-- (no-op if the player is already listed).
function TK.SetFirstOT(name)
    local clean = TK.SanitizeName(name)
    if clean == "" then return false, "Invalid player name." end
    if TK.FindSlot(clean) then return true end
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    for i = 2, #t do
        if t[i].name == "" then return TK.SetSlot(i, name) end
    end
    local idx, err = TK.AddTank()
    if not idx then return false, err end
    return TK.SetSlot(idx, name)
end

-- Clear every player name (slots and picks stay).
function TK.ClearNames()
    local t = slots()
    if not t then return end
    for i = 1, #t do t[i].name = "" end
    TK.Changed()
end

-- Back to a lone empty MT slot with no picks.
function TK.Reset()
    local c = cfg()
    if not c then return end
    c.tanks = { newSlot() }
    TK.Changed()
end

-- Nothing to clear: just the empty MT slot with no picks.
function TK.IsEmpty()
    local t = slots()
    if not t then return true end
    return #t == 1 and t[1].name == "" and #t[1].picks == 0
end

-- Window position lock (stored with the rest of the window state; no rebuild needed).
function TK.IsLocked()
    local c = cfg()
    return (c and c.locked) and true or false
end

function TK.SetLocked(on)
    local c = cfg()
    if not c then return false end
    c.locked = on and true or false
    return true
end

-- Flip the lock and return the new state.
function TK.ToggleLocked()
    TK.SetLocked(not TK.IsLocked())
    return TK.IsLocked()
end

-- Drop trailing off-tank slots that have neither a player nor picks (no event;
-- callers fire Changed themselves).
function TK.TrimEmpty()
    local t = slots()
    if not t then return end
    while #t > 1 and t[#t].name == "" and #t[#t].picks == 0 do table.remove(t) end
end

-- ---- picks (spells / items cast on a tank) ---------------------------------

local function validPick(text)
    local clean = TK.ParseSpellInput(text)
    if clean == "" then return nil, "Enter a spell or item name." end
    return clean
end

local function hasPick(picks, clean, skip)
    local l = clean:lower()
    for k, p in ipairs(picks) do
        if k ~= skip and p:lower() == l then return true end
    end
    return false
end

function TK.GetPicks(i)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    local out = {}
    if s then for k, p in ipairs(s.picks) do out[k] = p end end
    return out
end

function TK.AddPick(i, text)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    local clean, err = validPick(text)
    if not clean then return false, err end
    if #s.picks >= TK.MAX_PICKS then return false, "That tank already has " .. TK.MAX_PICKS .. " picks." end
    if hasPick(s.picks, clean) then return false, "That tank already has '" .. clean .. "'." end
    s.picks[#s.picks + 1] = clean
    TK.Changed()
    return true
end

function TK.SetPick(i, j, text)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    if type(j) ~= "number" or not s.picks[j] then return false, "Bad pick." end
    local clean, err = validPick(text)
    if not clean then return false, err end
    if hasPick(s.picks, clean, j) then return false, "That tank already has '" .. clean .. "'." end
    s.picks[j] = clean
    TK.Changed()
    return true
end

function TK.RemovePick(i, j)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    if type(j) ~= "number" or not s.picks[j] then return false, "Bad pick." end
    table.remove(s.picks, j)
    TK.Changed()
    return true
end

-- Add one pick to every tank that has room and doesn't already have it.
-- Returns how many tanks got it.
function TK.AddPickToAll(text)
    local t = slots()
    if not t then return 0 end
    local clean = validPick(text)
    if not clean then return 0 end
    local n = 0
    for _, s in ipairs(t) do
        if #s.picks < TK.MAX_PICKS and not hasPick(s.picks, clean) then
            s.picks[#s.picks + 1] = clean
            n = n + 1
        end
    end
    if n > 0 then TK.Changed() end
    return n
end

-- ============================================================================
-- UNITS / CANDIDATES / STATUS
-- ============================================================================

-- name -> unit token for everyone in the group INCLUDING pets (players are added
-- first, so a player beats a pet with the same name). Used for class colour, health,
-- range, debuffs and the selector; the cast macros target by NAME so they survive
-- raid roster reshuffles. nameCounts feeds IsAmbiguousName: two units sharing a name
-- make a "by name" macro hit whichever the game finds first.
function TK.RebuildUnits()
    local map, counts = {}, {}
    local function add(unit)
        local n = UnitName(unit)
        if not n then return end
        local l = n:lower()
        counts[l] = (counts[l] or 0) + 1
        if not map[l] then map[l] = unit end
    end
    local nRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if nRaid > 0 then
        for i = 1, nRaid do add("raid" .. i) end
        for i = 1, nRaid do add("raidpet" .. i) end
    else
        add("player")
        local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, nParty do add("party" .. i) end
        add("pet")
        for i = 1, nParty do add("partypet" .. i) end
    end
    TK.units, TK.nameCounts = map, counts
end

function TK.UnitFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not TK.units then TK.RebuildUnits() end
    return TK.units[name:lower()]
end

function TK.IsPetUnit(unit)
    if type(unit) ~= "string" then return false end
    return unit == "pet" or unit:find("^raidpet%d+$") ~= nil or unit:find("^partypet%d+$") ~= nil
end

-- The pet unit token for a given PLAYER unit ("raid5" -> "raidpet5",
-- "party2" -> "partypet2", "player" -> "pet"), or nil for anything else (a
-- pet unit passed in, "target", etc). WoW indexes a raid/party pet's unit
-- token to match its owner's own index (verified via web search, not
-- guessed) - TK.RebuildUnits above already relies on this exact pairing.
function TK.PetUnitFor(unit)
    if type(unit) ~= "string" then return nil end
    if unit == "player" then return "pet" end
    local n = unit:match("^raid(%d+)$")
    if n then return "raidpet" .. n end
    n = unit:match("^party(%d+)$")
    if n then return "partypet" .. n end
    return nil
end

-- True when more than one unit in the group carries this name.
function TK.IsAmbiguousName(name)
    if type(name) ~= "string" or name == "" then return false end
    if not TK.nameCounts then TK.RebuildUnits() end
    return (TK.nameCounts[name:lower()] or 0) > 1
end

-- Everyone in the group: players first (tank-capable classes first, then
-- alphabetical), then pets. A pet is only offered when its name is letters-only,
-- because the cast/target macros can't carry a name with spaces.
function TK.GetCandidates()
    if not TK.units then TK.RebuildUnits() end
    local list = {}
    for _, unit in pairs(TK.units) do
        local name = UnitName(unit)
        if name then
            if TK.IsPetUnit(unit) then
                if TK.SanitizeName(name) == name then
                    list[#list + 1] = { name = name, class = nil, tank = false, pet = true }
                end
            else
                local _, class = UnitClass(unit)
                list[#list + 1] = { name = name, class = class, tank = TK.TANK_CLASSES[class or ""] and true or false, pet = false }
            end
        end
    end
    table.sort(list, function(x, y)
        if x.pet ~= y.pet then return not x.pet end
        if x.tank ~= y.tank then return x.tank end
        return x.name < y.name
    end)
    return list
end

function TK.TargetName()
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
        return (UnitName("target"))
    end
    return nil
end

-- What the configured text is: "spell" (in your spellbook), "item" (cached
-- item) or nil. Also returns the icon texture and canonical name.
function TK.ResolveSpell(text)
    if type(text) ~= "string" or text == "" then return nil end
    if GetSpellInfo then
        local n, _, icon = GetSpellInfo(text)
        if n then return "spell", icon, n end
    end
    if GetItemInfo then
        local n, _, _, _, _, _, _, _, _, icon = GetItemInfo(text)
        if n then return "item", icon, n end
    end
    return nil
end

function TK.GetCooldown(spell, kind)
    if type(spell) ~= "string" or spell == "" then return 0, 0, 0 end
    if kind == "spell" and GetSpellCooldown then
        local s, d, e = GetSpellCooldown(spell)
        return s or 0, d or 0, e or 0
    elseif kind == "item" and GetItemInfo and GetItemCooldown then
        local _, link = GetItemInfo(spell)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local s, d, e = GetItemCooldown(id)
            return s or 0, d or 0, e or 0
        end
    end
    return 0, 0, 0
end

-- ============================================================================
-- PICKERS: any spell of yours / any item of yours that can target a friendly
-- ============================================================================
-- "Friendly-targetable" = helpful AND has a range. Helpful alone would also list
-- self-only buffs (Righteous Fury, party auras) which ignore [target=Tank]; the
-- range check is what separates "cast this ON someone" from "cast this".
-- If a client lacks one of the filter APIs, the pickers list everything rather
-- than nothing (the second return value says whether filtering was applied).

local BOOK = BOOKTYPE_SPELL or "spell"

local function byName(a, b) return a.name < b.name end

-- Your whole spellbook: {name, icon, index, book}, only passives and
-- duplicate ranks dropped (a passive can't be cast at all, so it's never a
-- valid pick), sorted by name. No castability filtering - the
-- IsHelpfulSpell+SpellHasRange heuristic used here previously excluded most
-- of a class's real spellbook for many classes/specs (e.g. only 2-3 spells
-- survived it for a Death Knight), which made the picker useless for them.
-- Showing everything and letting TK.IsFriendlyCastable warn post-pick is
-- simpler and actually usable. Second return is always true (kept for the
-- caller's "filtered vs not" note - see ui/TankCastConfig.lua).
function TK.ListSpells()
    local out = {}
    if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellName) then return out, false end
    local seen = {}
    for tab = 1, GetNumSpellTabs() do
        local _, _, offset, num = GetSpellTabInfo(tab)
        for i = (offset or 0) + 1, (offset or 0) + (num or 0) do
            local name = GetSpellName(i, BOOK)
            if name and not seen[name] and not (IsPassiveSpell and IsPassiveSpell(i, BOOK)) then
                seen[name] = true
                out[#out + 1] = {
                    name = name, index = i, book = BOOK,
                    icon = GetSpellTexture and GetSpellTexture(i, BOOK) or nil,
                }
            end
        end
    end
    local filtered = true
    table.sort(out, byName)
    return out, filtered
end

-- ---- item detection & identification --------------------------------------
-- The two item APIs (IsHelpfulItem / ItemHasRange) are a good signal but not a
-- complete one, so an item is judged from three:
--   1. API      helpful AND has a range              -> castable ("api")
--   2. Use text the item's own "Use:" line names a friendly recipient and no
--               enemy                                 -> castable ("text")
--   3. Kind     a type that is friendly-targeted by nature (bandage, soulstone,
--               scroll)                               -> castable ("kind")
-- and IsHarmfulItem / enemy wording vetoes. The text patterns are English; other
-- locales still get the API and kind paths.

local scanTip

-- The effect text after "Use:" on an item, read from a hidden tooltip. The
-- "Use:" prefix is the client's own localised global.
function TK.ItemUseText(link)
    if not (link and CreateFrame and link:find("|Hitem:", 1, true)) then return nil end
    if not scanTip then
        scanTip = CreateFrame("GameTooltip", "AIPTankCastScanTip", UIParent, "GameTooltipTemplate")
    end
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
    scanTip:ClearLines()
    scanTip:SetHyperlink(link)
    local prefix = ITEM_SPELL_TRIGGER_ONUSE or "Use:"
    for i = 2, scanTip:NumLines() do
        local fs = _G["AIPTankCastScanTipTextLeft" .. i]
        local text = fs and fs:GetText()
        if text and text:sub(1, #prefix) == prefix then
            return (text:sub(#prefix + 1):gsub("^%s+", ""))
        end
    end
    return nil
end

local function hasWord(s, w) return s:find("%f[%a]" .. w .. "%f[%A]") ~= nil end

local function safeCall(fn, arg)
    if not fn then return nil end
    local ok, v = pcall(fn, arg)
    return ok and v or nil
end

-- A short label for what the item is, from its name / subtype (nil = unknown).
local function itemKind(name, subType)
    local n, st = (name or ""):lower(), (subType or ""):lower()
    if st == "bandage" or n:find("bandage", 1, true) then return "Bandage" end
    if n:find("soulstone", 1, true) then return "Soulstone" end
    if n:find("healthstone", 1, true) then return "Healthstone" end
    if n:find("scroll of", 1, true) == 1 or st == "scroll" then return "Scroll" end
    if n:find("potion", 1, true) or st == "potion" then return "Potion" end
    if n:find("flask", 1, true) or n:find("elixir", 1, true) or st == "elixir" or st == "flask" then return "Elixir/Flask" end
    if st:find("food", 1, true) then return "Food" end
    return nil
end
-- Bandage/Soulstone/Scroll are genuinely castable ON someone else. Potion/
-- Elixir-Flask/Food are NOT - they're self-only consumables - but the user
-- asked for them as quick-cast picks anyway: a tank's own row is exactly
-- where you'd want one-click access to your own health potion/flask/food,
-- and the macro's [target=] condition is simply irrelevant to a self-only
-- consumable's actual effect (same as clicking your own MT row already
-- does today for e.g. Righteous Fury - it just uses on you regardless of
-- who the row names).
local FRIENDLY_KINDS = { Bandage = true, Soulstone = true, Scroll = true, Potion = true, ["Elixir/Flask"] = true, Food = true }

-- {castable = true|false|nil, kind = label, effect = Use text|nil, why = "api"|"text"|"kind"|"consumable"|"harmful"|nil}
-- castable nil = not enough information to say either way.
function TK.ClassifyItem(link)
    local res = { castable = nil, kind = "Item", effect = nil, why = nil }
    if not (link and GetItemInfo) then return res end
    local name, _, _, _, _, itemType, subType = GetItemInfo(link)
    if not name then return res end

    local effect = TK.ItemUseText(link)
    res.effect = effect
    local kind = itemKind(name, subType)
    local apiFull = (IsHelpfulItem ~= nil) and (ItemHasRange ~= nil)
    local helpful = safeCall(IsHelpfulItem, link) and true or false
    local ranged = safeCall(ItemHasRange, link) and true or false
    local harmful = safeCall(IsHarmfulItem, link) and true or false

    local lower = effect and effect:lower()
    local enemy = lower and (hasWord(lower, "enemy") or hasWord(lower, "enemies")
        or hasWord(lower, "hostile") or hasWord(lower, "opponent"))
    local strong = lower and (hasWord(lower, "friendly") or lower:find("party member", 1, true)
        or lower:find("raid member", 1, true) or hasWord(lower, "ally") or hasWord(lower, "allies"))
    -- "target" alone is too weak a signal: many self-only trinkets/procs say
    -- things like "reduces damage taken from YOUR CURRENT target" - describing
    -- what the effect is relative to (an enemy you're fighting), not naming a
    -- friendly recipient the item can be cast ON. Only trust a bare "target" as
    -- the object of the effect (e.g. "restores health to target"), not when it's
    -- a possessive reference to the wielder's own target.
    local possessive = lower and (lower:find("your target", 1, true) or lower:find("current target", 1, true)
        or lower:find("target's", 1, true))
    local weak = lower and hasWord(lower, "target") and not possessive

    if harmful then
        res.castable, res.why = false, "harmful"
    elseif helpful and ranged then
        res.castable, res.why = true, "api"
    elseif lower and not enemy and (strong or (weak and (helpful or not IsHelpfulItem))) then
        res.castable, res.why = true, "text"
    elseif kind and FRIENDLY_KINDS[kind] then
        res.castable, res.why = true, "kind"
    elseif itemType == "Consumable" and not enemy then
        -- Broader safety net beyond the hand-named kinds above: WoW's own
        -- "Consumable" item class covers potions/flasks/elixirs/food/drink/
        -- bandages/scrolls/etc as a whole (verified via GetItemInfo's own
        -- itemType return, index 6 - English client only, same accepted
        -- tradeoff as TK.ItemUseText's English-only "Use:" parsing above).
        -- Anything in this class that doesn't match a named kind AND has no
        -- enemy-directed use text is still a reasonable quick-cast pick for
        -- a tank's own row. The `not enemy` guard matters: some Consumable-
        -- class items are offensive throwables (a "vial"/grenade with
        -- "hurls...at target enemy" text), which must stay excluded even
        -- though they share the same item class as a health potion.
        res.castable, res.why = true, "consumable"
    elseif effect or (apiFull and helpful) then
        res.castable = false                      -- has an effect, but not one aimed at a friendly
    end

    if kind then res.kind = kind
    elseif res.castable then res.kind = "Helpful item"
    elseif subType and subType ~= "" then res.kind = subType end
    return res
end

local function byKind(a, b)
    if a.kind ~= b.kind then return a.kind < b.kind end
    return a.name < b.name
end

-- Items in your bags that can be cast on a friendly player: {name, icon, link,
-- kind, effect, why}, deduped by name, sorted by kind then name. Returns list,
-- apiComplete(bool). If an item API is missing, items we can't rule out are
-- included too (so the list is never empty for lack of an API).
function TK.ListItems()
    local out = {}
    if not (GetContainerNumSlots and GetContainerItemLink and GetItemInfo) then return out, false end
    local apiFull = (IsHelpfulItem ~= nil) and (ItemHasRange ~= nil)
    local seen = {}
    for bag = 0, 4 do
        for slot = 1, (GetContainerNumSlots(bag) or 0) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local name, _, quality, _, _, _, _, _, _, icon = GetItemInfo(link)
                if name and not seen[name] then
                    local c = TK.ClassifyItem(link)
                    if c.castable == true or (c.castable == nil and not apiFull) then
                        seen[name] = true
                        out[#out + 1] = { name = name, icon = icon, link = link, quality = quality,
                                          kind = c.kind, effect = c.effect, why = c.why }
                    end
                end
            end
        end
    end
    table.sort(out, byKind)
    return out, apiFull
end

-- Can the configured text be cast ON a friendly player? true / false, or nil
-- when we can't tell (unknown text, or the client lacks the API) - callers
-- warn only on an explicit false.
function TK.IsFriendlyCastable(text)
    local kind = TK.ResolveSpell(text)
    if kind == "spell" then
        if not (IsHelpfulSpell and SpellHasRange) then return nil end
        local ok1, helpful = pcall(IsHelpfulSpell, text)
        local ok2, ranged = pcall(SpellHasRange, text)
        if not (ok1 and ok2) then return nil end
        return (helpful and ranged) and true or false
    elseif kind == "item" then
        local _, link = GetItemInfo(text)
        return TK.ClassifyItem(link or text).castable
    end
    return nil
end

-- Name of the spell/item currently held on the mouse cursor (dragged from the
-- spellbook or a bag), or nil.
function TK.FromCursor()
    if not GetCursorInfo then return nil end
    local kind, a, b = GetCursorInfo()
    if kind == "spell" and GetSpellName then
        local name = GetSpellName(a, b or BOOK)
        if name then return name end
    elseif kind == "item" and GetItemInfo then
        local name = GetItemInfo(a)
        if name then return name end
    end
    return nil
end

-- Is the tank close enough for THIS pick? Uses the pick's own range when the
-- client can tell, else the 28-yard interact distance. `kind` (optional) is the
-- pick's already-resolved kind ("spell"/"item") to avoid a per-tick re-lookup.
function TK.InRange(name, unit, pick, kind)
    unit = unit or TK.UnitFor(name)
    if not unit then return false end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    if pick and pick ~= "" then
        kind = kind or TK.ResolveSpell(pick)      -- callers that already know the kind skip the lookup
        if kind == "spell" and IsSpellInRange then
            local r = IsSpellInRange(pick, unit)
            if r ~= nil then return r == 1 end
        elseif kind == "item" and IsItemInRange then
            local r = IsItemInRange(pick, unit)
            if r ~= nil then return r == 1 end
        end
    end
    if CheckInteractDistance then return CheckInteractDistance(unit, 4) and true or false end
    return true
end

-- Tank-level state (range is per pick, see InRange):
-- "ok" | "away" (not in group) | "offline" | "dead"
function TK.Status(name)
    local unit = TK.UnitFor(name)
    if not unit then return "away" end
    if UnitIsConnected and not UnitIsConnected(unit) then return "offline" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return "dead" end
    return "ok"
end

-- ============================================================================
-- DISPLAY HELPERS (pure; the window uses them, tests pin them)
-- ============================================================================

-- Remaining cooldown as short text: 12 -> "12", 65 -> "1:05", 600 -> "10m", 3600 -> "1h".
function TK.FormatCooldown(sec)
    if type(sec) ~= "number" or sec <= 0 then return "" end
    local s = math.ceil(sec)
    if s < 60 then return tostring(s) end
    if s < 600 then return string.format("%d:%02d", math.floor(s / 60), s % 60) end
    if s < 3600 then return math.ceil(s / 60) .. "m" end
    return math.ceil(s / 3600) .. "h"
end

local function lerp(a, b, t) return a + (b - a) * t end

-- Continuous health colour: red (0%) -> amber (50%) -> green (100%).
function TK.HealthColor(pct)
    pct = (type(pct) == "number") and math.max(0, math.min(1, pct)) or 0
    if pct >= 0.5 then
        local t = (pct - 0.5) / 0.5
        return lerp(0.95, 0.2, t), lerp(0.80, 0.85, t), lerp(0.20, 0.30, t)
    end
    local t = pct / 0.5
    return lerp(0.90, 0.95, t), lerp(0.20, 0.80, t), 0.20
end

-- Action-bar style usability of a pick: returns usable, noMana (both booleans).
-- Unknown kind / missing API assumes "usable" so nothing is tinted wrongly.
function TK.Usability(text, kind)
    if kind == "spell" and IsUsableSpell then
        local usable, noMana = IsUsableSpell(text)
        return usable and true or false, noMana and true or false
    elseif kind == "item" and IsUsableItem then
        local usable, noMana = IsUsableItem(text)
        return usable and true or false, noMana and true or false
    end
    return true, false
end

-- Debuffs currently on a unit, for the tooltip: array of {name, icon, count,
-- dtype, timeLeft} (up to `limit`), plus the real total. timeLeft is nil for a
-- debuff with no expiration.
function TK.ListDebuffs(unit, limit)
    local out, total = {}, 0
    if not unit or not UnitDebuff then return out, 0 end
    limit = limit or 12
    for i = 1, 40 do
        local name, _, icon, count, dtype, _, expires = UnitDebuff(unit, i)
        if not name then break end
        total = total + 1
        if #out < limit then
            local left = (type(expires) == "number" and expires > 0) and (expires - GetTime()) or nil
            out[#out + 1] = { name = name, icon = icon, count = count, dtype = dtype, timeLeft = left }
        end
    end
    return out, total
end

-- "Sunder Armor x5 (12s)" / "Curse of Weakness (1:05)" / "Deep Wound".
function TK.FormatDebuff(d)
    local text = d.name or "?"
    if d.count and d.count > 1 then text = text .. " x" .. d.count end
    local t = TK.FormatCooldown(d.timeLeft)
    if t ~= "" then
        if tonumber(t) then t = t .. "s" end
        text = text .. " (" .. t .. ")"
    end
    return text
end

TK.specAsked = TK.specAsked or {}

-- A unit's spec via the inspection cache in RaidComposition (your own talents are
-- read directly; others need an inspect). Returns spec, state where state is
-- "ok" | "inspecting" (requested, will appear in the cache) | "range" (too far to
-- inspect) | "pet" | "unavailable". Inspect requests are throttled per player.
function TK.TankSpec(unit)
    if not unit then return nil, "unavailable" end
    if TK.IsPetUnit(unit) then return nil, "pet" end
    local Comp = AIP.Composition
    if not (Comp and Comp.GetSpecName) then return nil, "unavailable" end
    local spec = Comp.GetSpecName(unit)
    if spec then return spec, "ok" end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return nil, "unavailable" end
    if not (CanInspect and CanInspect(unit) and CheckInteractDistance and CheckInteractDistance(unit, 1)) then
        return nil, "range"
    end
    local name = UnitName(unit)
    local t = GetTime()
    if name and (not TK.specAsked[name] or t - TK.specAsked[name] >= 30) then
        TK.specAsked[name] = t
        if Comp.RequestInspect then Comp.RequestInspect(unit) end
    end
    return nil, "inspecting"
end

-- The selector's secure macro: target this tank by name.
function TK.BuildTargetMacro(name)
    name = TK.SanitizeName(name)
    if name == "" then return nil end
    return "/target " .. name
end


-- False while a structural change is waiting for combat to end: the window still
-- shows the OLD list, so index-based edit actions would hit the wrong slot.
function TK.EditsAllowed()
    return not TK.dirty
end

-- ============================================================================
-- BLIZZARD SYNC (WotLK only has MAINTANK / MAINASSIST raid flags)
-- ============================================================================

-- For every currently-named tank slot, if that player has a real active pet
-- (Hunter/Warlock/DK-with-ghoul/etc - detected live via a real matching pet
-- unit, not a hardcoded class list, so it only fires when a pet is actually
-- out), give the pet its own slot too (if it doesn't already have one, and
-- its name is letters-only - the cast/target macros can't carry a name with
-- spaces, same rule TK.GetCandidates already applies). Used by
-- TK.ImportFromBlizzard so importing a tank with a pet gives the pet its
-- own quick-cast row too, not just the player - the user's own ask ("one
-- slot filled by the pet and one by self"). Returns how many pet slots were
-- filled. Uses TK.SetFirstOT (reuse an empty slot before adding a new one)
-- rather than always appending - Import itself clears every slot's NAME
-- before repopulating (see TK.ImportFromBlizzard above), so a slot that
-- held this exact pet before a re-import is empty-but-present at this point
-- and should be reused, not left as permanent debris while a duplicate gets
-- appended after it.
function TK.AutoFillPets()
    local t = slots()
    if not t then return 0 end
    if not TK.units then TK.RebuildUnits() end
    -- Snapshot owner names before filling slots below, so the loop doesn't
    -- also process the pet slots it just added.
    local owners = {}
    for i = 1, #t do
        if t[i].name ~= "" then owners[#owners + 1] = t[i].name end
    end
    local added = 0
    for _, ownerName in ipairs(owners) do
        local ownerUnit = TK.UnitFor(ownerName)
        if ownerUnit and not TK.IsPetUnit(ownerUnit) then
            local petUnit = TK.PetUnitFor(ownerUnit)
            local petName = petUnit and UnitName(petUnit)
            if petName and TK.SanitizeName(petName) == petName and not TK.FindSlot(petName) then
                if TK.SetFirstOT(petName) then added = added + 1 end
            end
        end
    end
    return added
end

-- Mirror the group's tank(s) into the tank list. Tries two sources, in order:
--  1. The LFD-assigned TANK role (UnitGroupRolesAssigned, added patch 3.3.0
--     for the Dungeon Finder tool - verified via web search, not guessed).
--     This is the ONLY way to find a tank in a 5-man RDF PARTY, since
--     MAINTANK/MAINASSIST flags are a raid-only concept and a Dungeon
--     Finder group is a party, not a raid. A manually-formed group reports
--     "NONE" (or nil) for everyone here, so this naturally falls through to
--     source 2 without a separate "is this really an RDF group" check.
--  2. The raid's MAINTANK/MAINASSIST flags (previous/existing behaviour,
--     raid-only).
-- Either way, every imported tank that has a real active pet also gets the
-- pet appended as its own slot (TK.AutoFillPets) - the user's other ask.
-- Names are replaced; picks stay with their slots.
function TK.ImportFromBlizzard()
    local nRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    if nRaid == 0 and nParty == 0 then return false, "You are not in a group." end

    local mt, assists, viaLFD = nil, {}, false
    if UnitGroupRolesAssigned then
        local units = {}
        if nRaid > 0 then
            for i = 1, nRaid do units[#units + 1] = "raid" .. i end
        else
            units[1] = "player"
            for i = 1, nParty do units[#units + 1] = "party" .. i end
        end
        for _, unit in ipairs(units) do
            if UnitGroupRolesAssigned(unit) == "TANK" then
                local n = UnitName(unit)
                if n then mt, viaLFD = n, true; break end
            end
        end
    end

    if not mt and nRaid > 0 then
        for i = 1, nRaid do
            local name, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
            if name then
                if role == "MAINTANK" then mt = name
                elseif role == "MAINASSIST" then assists[#assists + 1] = name end
            end
        end
    end

    if not mt and #assists == 0 then
        return false, "No LFD tank role or Main Tank/Main Assist flags were found."
    end

    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    for i = 1, #t do t[i].name = "" end
    local nOT = math.min(#assists, TK.MAX_TANKS - 1)
    while #t < 1 + nOT do t[#t + 1] = newSlot() end
    local function put(i, name)
        local norm = normalize(TK.SanitizeName(name))
        if norm and norm ~= "" then t[i].name = norm end
    end
    if mt then put(1, mt) end
    for k = 1, nOT do put(k + 1, assists[k]) end

    local petsAdded = TK.AutoFillPets()

    TK.TrimEmpty()
    TK.Changed()
    local msg
    if viaLFD then
        msg = "Imported the LFD-assigned tank: " .. (mt or "none")
    else
        msg = string.format("Imported from the raid flags: MT %s, %d off-tank(s) (from Main Assists)",
            mt or "none", nOT)
    end
    if petsAdded > 0 then msg = msg .. string.format(", +%d pet slot(s)", petsAdded) end
    return true, msg .. "."
end

function TK.CanPush()
    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then return false end
    return ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())) and true or false
end

-- Set the raid's MAINTANK / MAINASSIST flags to match the list. Leader/assist
-- only; skips flags that are already set. Explicit user action only.
function TK.PushToBlizzard()
    if not TK.CanPush() then
        return false, "You must be raid leader or assistant in a raid to set the raid flags."
    end
    if not (SetPartyAssignment and GetPartyAssignment) then
        return false, "This client cannot set raid assignments."
    end
    local set, missing = 0, 0
    for i = 1, TK.NumTanks() do
        local name = TK.GetSlot(i)
        if name ~= "" then
            local unit = TK.UnitFor(name)
            if not unit then
                missing = missing + 1
            else
                local assignment = (i == 1) and "MAINTANK" or "MAINASSIST"
                if not GetPartyAssignment(assignment, unit) then
                    SetPartyAssignment(assignment, unit)
                    set = set + 1
                end
            end
        end
    end
    local msg = string.format("Raid flags updated (%d set", set)
    if missing > 0 then msg = msg .. string.format(", %d not in your raid", missing) end
    return true, msg .. ")."
end

-- Ordered model for the title bar's right-click menu: everything that used to be
-- a row of icon buttons. {id, text, enabled}; the window maps ids to actions and
-- builds the EasyMenu, so wording/enabling lives in one tested place.
function TK.TitleMenu()
    local n = TK.NumTanks()
    return {
        { id = "add", text = "Add off-tank (" .. n .. "/" .. TK.MAX_TANKS .. ")", enabled = n < TK.MAX_TANKS },
        { id = "import", text = "Import tank (LFD role / raid flags)", enabled = true },
        { id = "push", text = "Push to raid", enabled = TK.CanPush() },
        { id = "lock", text = TK.IsLocked() and "Unlock position" or "Lock position", enabled = true },
        { id = "clear", text = "Clear all tanks and picks...", enabled = not TK.IsEmpty() },
        { id = "close", text = "Close", enabled = true },
    }
end

-- ============================================================================
-- SLASH: /aip tanks [mt|ot|addot|pick|unpick|spell|clear|reset|sync|push|list]
-- ============================================================================

-- "mt" -> 1, "ot1".."ot7" -> 2..8, "1".."8" -> that slot; nil if unrecognised.
local function parseSlot(sel)
    sel = (sel or ""):lower()
    if sel == "mt" then return 1 end
    local n = sel:match("^ot(%d+)$")
    if n then return tonumber(n) + 1 end
    n = sel:match("^(%d+)$")
    if n then return tonumber(n) end
    return nil
end

local USAGE = "/aip tanks [mt|ot [name]] [addot] [pick|unpick <mt|otN> <name>] [spell <name>] [clear] [reset] [lock] [sync] [push] [list]"

function TK.SlashHandler(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    arg = arg or ""

    if sub == "" then
        if TK.ToggleWindow then TK.ToggleWindow() else say("The tank window is not loaded.") end
    elseif sub == "mt" then
        local name = (arg ~= "") and arg or TK.TargetName()
        if not name then
            say("Usage: /aip tanks mt <name>  (or target a player and omit the name)")
            return
        end
        local ok, err = TK.SetSlot(1, name)
        say(ok and ("Main tank set to " .. TK.GetSlot(1)) or err)
    elseif sub == "ot" then
        local name = (arg ~= "") and arg or TK.TargetName()
        if not name then
            say("Usage: /aip tanks ot <name>  (or target a player and omit the name)")
            return
        end
        local ok, err = TK.SetFirstOT(name)
        say(ok and ("Off-tank added: " .. name) or err)
    elseif sub == "addot" then
        local idx, err = TK.AddTank()
        say(idx and ("Added an empty slot: " .. TK.SlotLabel(idx)) or err)
    elseif sub == "pick" or sub == "unpick" then
        local sel, text = arg:match("^(%S+)%s*(.-)$")
        local slot = parseSlot(sel)
        if not slot or not text or text == "" then
            say("Usage: /aip tanks " .. sub .. " <mt|ot1..ot7> <spell or item name>")
            return
        end
        if slot < 1 or slot > TK.NumTanks() then
            say("There is no " .. (sel or "?") .. " slot yet (use /aip tanks addot).")
            return
        end
        if sub == "pick" then
            local ok, err = TK.AddPick(slot, text)
            say(ok and (TK.SlotLabel(slot) .. " pick added: " .. TK.ParseSpellInput(text)) or err)
        else
            local want = TK.ParseSpellInput(text):lower()
            local found
            for j, p in ipairs(TK.GetPicks(slot)) do
                if p:lower() == want then found = j; break end
            end
            if not found then say(TK.SlotLabel(slot) .. " has no pick called '" .. text .. "'.") return end
            TK.RemovePick(slot, found)
            say(TK.SlotLabel(slot) .. " pick removed: " .. text)
        end
    elseif sub == "spell" then
        if arg == "" then
            say("Usage: /aip tanks spell <spell or item name>   (adds it to every tank)")
            return
        end
        local n = TK.AddPickToAll(arg)
        say("Added '" .. TK.ParseSpellInput(arg) .. "' to " .. n .. " tank(s).")
    elseif sub == "clear" then
        TK.ClearNames()
        say("Tank names cleared (slots and picks kept; /aip tanks reset wipes everything).")
    elseif sub == "reset" then
        TK.Reset()
        say("Tank list reset.")
    elseif sub == "lock" then
        say(TK.ToggleLocked() and "Tank window locked." or "Tank window unlocked.")
    elseif sub == "unlock" then
        TK.SetLocked(false)
        say("Tank window unlocked.")
    elseif sub == "sync" or sub == "import" then
        local _, msg = TK.ImportFromBlizzard()
        say(msg)
    elseif sub == "push" then
        local _, msg = TK.PushToBlizzard()
        say(msg)
    elseif sub == "list" then
        for i = 1, TK.NumTanks() do
            local n = TK.GetSlot(i)
            local picks = table.concat(TK.GetPicks(i), ", ")
            say(TK.SlotLabel(i) .. ": " .. (n ~= "" and n or "-") .. "  [" .. (picks ~= "" and picks or "no picks") .. "]")
        end
    else
        say(USAGE)
    end
end

-- ============================================================================
-- EVENTS (module-local pub/sub, not a new frame)
-- ============================================================================

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    local E = AIP.Utils.Events
    local function onRoster() TK.RosterChanged() end
    E.Register("RAID_ROSTER_UPDATE", onRoster, "TankCast")
    E.Register("PARTY_MEMBERS_CHANGED", onRoster, "TankCast")
    E.Register("PLAYER_ENTERING_WORLD", onRoster, "TankCast")
    -- Combat ended: apply any tank/spell edit that was deferred by lockdown,
    -- and re-run the roster check unconditionally. This is also what lets
    -- TK.JustFormedGroup()'s one-shot auto-show latch retry when the group
    -- formed WHILE the player was still in combat - the window's OnRoster
    -- callback deliberately skips JustFormedGroup() during lockdown (it can't
    -- open the window then anyway), so without this the latch would only get
    -- another chance on the next unrelated roster change, if any.
    E.Register("PLAYER_REGEN_ENABLED", function()
        if TK.dirty then TK.Changed() end
        TK.RosterChanged()
    end, "TankCast")
end
