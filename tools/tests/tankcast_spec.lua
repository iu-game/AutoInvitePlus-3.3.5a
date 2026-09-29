-- Headless tests for AutoInvitePlus/modules/TankCast.lua (pure logic; no WoW client).
-- Run from the repo root:  luajit tools/tests/tankcast_spec.lua

local printed = {}
local currentCharKey = "TestRealm-Me"
AutoInvitePlus = {
    db = { tankCast = {} },
    Print = function(msg) printed[#printed + 1] = msg end,
    Utils = {
        NormalizeName = function(name)
            if not name or name == "" then return nil end
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return nil end
            return name:sub(1, 1):upper() .. name:sub(2):lower()
        end,
        CharKey = function() return currentCharKey end,
    },
}
local AIP = AutoInvitePlus

-- ---- WoW API stubs ---------------------------------------------------------
local roster, party = {}, {}
local targetName, isLeader, isOfficer = nil, false, false
local soloPet, now = nil, 100
local assigned, assignCalls = {}, {}
local lfdRoles = {}   -- unit -> "TANK"|"HEALER"|"DAMAGER"|"NONE", set per test
UnitGroupRolesAssigned = function(unit) return lfdRoles[unit] end

local function entryFor(unit)
    if unit == "player" then return { name = "Me", class = "PRIEST" } end
    if unit == "pet" then return soloPet end
    local kind, idx = unit:match("^(%a+)(%d+)$")
    idx = tonumber(idx)
    if kind == "raid" then return roster[idx] end
    if kind == "party" then return party[idx] end
    if kind == "raidpet" then local e = roster[idx]; return e and e.pet end
    if kind == "partypet" then local e = party[idx]; return e and e.pet end
end
GetNumRaidMembers = function() return #roster end
GetNumPartyMembers = function() return #party end
UnitName = function(unit)
    if unit == "target" then return targetName end
    local e = entryFor(unit); return e and e.name
end
UnitClass = function(unit)
    local e = entryFor(unit); if e then return e.class, e.class end
end
UnitExists = function(unit) if unit == "target" then return targetName ~= nil end return entryFor(unit) ~= nil end
UnitIsPlayer = function() return true end
GetRaidRosterInfo = function(i)
    local r = roster[i]; if not r then return nil end
    return r.name, 0, 1, 80, r.class, r.class, "Zone", true, false, r.role
end
GetTime = function() return now end
local debuffs = {}
UnitDebuff = function(unit, i)
    local d = debuffs[unit] and debuffs[unit][i]
    if d then return d[1], "", d[2], d[3], d[4], 0, d[5], "player" end
end
IsRaidLeader = function() return isLeader and 1 or nil end
IsRaidOfficer = function() return isOfficer and 1 or nil end
GetPartyAssignment = function(a, u) return assigned[a .. ":" .. u] and 1 or nil end
SetPartyAssignment = function(a, u) assigned[a .. ":" .. u] = true; assignCalls[#assignCalls + 1] = a .. ":" .. u end
GetSpellInfo = function(n)
    if n == "Misdirection" or n == "Righteous Fury" then return n, "", "icon1" end
end

-- Spellbook: 2 tabs (General idx 1-2, Class idx 3-7). h/r (helpful/range)
-- flags are unused by TK.ListSpells itself (no longer filters on them) but
-- stay on the fixture since TK.IsFriendlyCastable still reads them.
local book = {
    { n = "Attack" },                                   -- 1: not helpful
    { n = "Misdirection", h = true, r = true },         -- 2: friendly + range
    { n = "Power Word: Shield", h = true, r = true },   -- 3: friendly + range
    { n = "Righteous Fury", h = true },                 -- 4: helpful, self-only (no range)
    { n = "Fireball" },                                 -- 5: harmful
    { n = "Toughness", passive = true, h = true, r = true }, -- 6: passive -> dropped
    { n = "Misdirection", h = true, r = true },         -- 7: duplicate rank -> dropped
}
local function bookEntry(a)
    if type(a) == "number" then return book[a] end
    for _, e in ipairs(book) do if e.n == a then return e end end
end
GetNumSpellTabs = function() return 2 end
GetSpellTabInfo = function(t) if t == 1 then return "General", "t", 0, 2 end return "Class", "t", 2, 5 end
GetSpellName = function(i) local e = book[i]; if e then return e.n, "Rank 1" end end
GetSpellTexture = function(i) return "tex" .. i end
IsPassiveSpell = function(a) local e = bookEntry(a); return e and e.passive and 1 or nil end
IsHelpfulSpell = function(a) local e = bookEntry(a); return e and e.h and 1 or nil end
SpellHasRange = function(a) local e = bookEntry(a); return e and e.r and 1 or nil end

-- Items / bags.
-- {name, link, icon, itemType, subType}
local function L(id, name) return "|cffffffff|Hitem:" .. id .. ":0|h[" .. name .. "]|h|r" end
local itemDB = {
    Hearthstone = { "Hearthstone", L(6948, "Hearthstone"), "icon2" },
    ["Linen Bandage"] = { "Linen Bandage", L(1, "Linen Bandage"), "iconB", "Consumable", "Bandage" },
    ["Healing Potion"] = { "Healing Potion", L(2, "Healing Potion"), "iconP", "Consumable", "Potion" },
    Junk = { "Junk", L(3, "Junk"), "iconJ", "Junk", "Junk" },
    ["Runed Talisman"] = { "Runed Talisman", L(4, "Runed Talisman"), "iconR", "Miscellaneous", "Other" },
    ["Scroll of Stamina V"] = { "Scroll of Stamina V", L(5, "Scroll of Stamina V"), "iconS", "Consumable", "Consumable" },
    ["Blasting Vial"] = { "Blasting Vial", L(6, "Blasting Vial"), "iconV", "Consumable", "Other" },
    ["Cursed Vial"] = { "Cursed Vial", L(7, "Cursed Vial"), "iconC", "Consumable", "Other" },
    ["Mender Doll"] = { "Mender Doll", L(8, "Mender Doll"), "iconM", "Miscellaneous", "Other" },
    ["Odd Gadget"] = { "Odd Gadget", L(9, "Odd Gadget"), "iconO", "Miscellaneous", "Other" },
    ["Mixed Charm"] = { "Mixed Charm", L(10, "Mixed Charm"), "iconX", "Miscellaneous", "Other" },
    ["Master Soulstone"] = { "Master Soulstone", L(11, "Master Soulstone"), "iconZ", "Consumable", "Other" },
    ["Battle Trinket"] = { "Battle Trinket", L(12, "Battle Trinket"), "iconTr", "Miscellaneous", "Other" },
    -- Consumable-class item that matches none of the hand-named kinds
    -- (Bandage/Soulstone/Scroll/Potion/Elixir-Flask/Food) and has no use-text
    -- at all - exercises the broad "Consumable item class" catch-all path
    -- distinctly from the named-kind path.
    ["Mystery Draft"] = { "Mystery Draft", L(13, "Mystery Draft"), "iconD", "Consumable", "Other" },
}
local itemById = { [6948] = "Hearthstone" }
GetItemInfo = function(n)
    local key
    if type(n) == "number" then key = itemById[n] else key = n:match("%[(.-)%]") or n end
    local e = key and itemDB[key]
    if e then return e[1], e[2], 1, 1, 1, e[4] or "", e[5] or "", 1, "", e[3] end
end
local helpfulItems = { ["Linen Bandage"] = true, ["Healing Potion"] = true, ["Cursed Vial"] = true, ["Mender Doll"] = true, ["Battle Trinket"] = true }
local rangedItems = { ["Linen Bandage"] = true, ["Cursed Vial"] = true }
local harmfulItems = { ["Cursed Vial"] = true }
local function itemKey(x) return type(x) == "string" and (x:match("%[(.-)%]") or x) or nil end
IsHelpfulItem = function(x) return helpfulItems[itemKey(x)] and 1 or nil end
ItemHasRange = function(x) return rangedItems[itemKey(x)] and 1 or nil end
IsHarmfulItem = function(x) return harmfulItems[itemKey(x)] and 1 or nil end
local bags = {
    [0] = { itemDB["Linen Bandage"][2], itemDB["Healing Potion"][2], nil, itemDB["Linen Bandage"][2] },
    [1] = { itemDB.Junk[2], itemDB["Runed Talisman"][2], itemDB["Scroll of Stamina V"][2], itemDB["Blasting Vial"][2] },
}
GetContainerNumSlots = function(b) if b == 0 then return 4 elseif b == 1 then return 4 end return 0 end
GetContainerItemLink = function(b, s) return bags[b] and bags[b][s] end
local cursor
GetCursorInfo = function() if cursor then return cursor[1], cursor[2], cursor[3] end end
GetSpellCooldown = function() return 10, 30, 1 end
GetItemCooldown = function(id) if id == 6948 then return 5, 60, 1 end return 0, 0, 0 end

dofile("AutoInvitePlus/modules/TankCast.lua")
local TK = AIP.TankCast

-- The real ItemUseText reads a hidden tooltip; tests substitute canned "Use:" text.
local useText = {
    ["Runed Talisman"] = "Grants target friendly player 300 armor for 10 sec.",
    ["Blasting Vial"] = "Hurls a vial at target enemy dealing 100 fire damage.",
    ["Mender Doll"] = "Restores 500 health to target.",
    ["Odd Gadget"] = "Teleports the target to a nearby location.",
    ["Mixed Charm"] = "Damages target enemy and heals friendly target.",
    ["Linen Bandage"] = "Heals 400 damage over 6 sec.",
    ["Battle Trinket"] = "Reduces damage taken from your current target by 20% for 10 sec.",
}
TK.ItemUseText = function(link) return useText[link and link:match("%[(.-)%]")] end

-- ---- tiny test framework ---------------------------------------------------
local pass, fail = 0, 0
local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else fail = fail + 1; print("FAIL " .. label .. ": expected [" .. tostring(expected) .. "], got [" .. tostring(actual) .. "]") end
end
local function nm(i) return string.char(65 + (i % 26)) .. string.char(97 + (math.floor(i / 26) % 26)) end   -- unique letters-only names
local function reset()
    soloPet = nil
    currentCharKey = "TestRealm-Me"
    AIP.db.tankCast = nil
    AIP.db.tankCastByChar = { [currentCharKey] = { tanks = { { name = "", picks = {} } } } }
    roster, party, targetName = {}, {}, nil
    isLeader, isOfficer = false, false
    assigned, assignCalls, printed = {}, {}, {}
    lfdRoles = {}
    TK.units = nil
    TK.wasGrouped = nil
end

-- ---- sanitising / macro ----------------------------------------------------
eq(TK.Sanitize("Hand of Sacrifice; /run x [a]\n"), "Hand of Sacrifice run x a", "Sanitize strips macro chars")
eq(TK.Sanitize("  Power   Word: Shield  "), "Power Word: Shield", "Sanitize collapses spaces, keeps colon")
eq(TK.Sanitize(nil), "", "Sanitize nil")
eq(TK.SanitizeName("Bob; /run"), "Bobrun", "SanitizeName letters only")
eq(TK.ParseSpellInput("|cff71d5ff|Hspell:34477|h[Misdirection]|h|r"), "Misdirection", "ParseSpellInput spell link")
eq(TK.ParseSpellInput("|cff1eff00|Hitem:6948:0|h[Hearthstone]|h|r"), "Hearthstone", "ParseSpellInput item link")
eq(TK.ParseSpellInput("Innervate"), "Innervate", "ParseSpellInput plain")
eq(TK.BuildMacro("Bob", "Misdirection"), "/cast [target=Bob] Misdirection", "BuildMacro basic")
eq(TK.BuildMacro("Bob", "Misdirection; /run x"), "/cast [target=Bob] Misdirection run x", "BuildMacro neutralises injection")
eq(TK.BuildMacro("", "Misdirection"), nil, "BuildMacro no name")
eq(TK.BuildMacro("Bob", ""), nil, "BuildMacro no spell")
eq(TK.BuildMacro("Bob", string.rep("a", 300)), nil, "BuildMacro too long")

-- ---- slots -----------------------------------------------------------------
reset()
eq(TK.NumTanks(), 1, "starts with just the MT slot")
eq(TK.SlotLabel(1), "MT", "label MT"); eq(TK.SlotLabel(2), "OT1", "label OT1"); eq(TK.SlotLabel(4), "OT3", "label OT3")
eq((TK.SetSlot(2, "bob")), false, "SetSlot on a slot that does not exist yet fails")
eq(TK.AddTank(), 2, "AddTank returns the new index"); eq(TK.NumTanks(), 2, "NumTanks after AddTank")
eq((TK.SetSlot(2, "bob")), true, "SetSlot ok"); eq(TK.GetSlot(2), "Bob", "SetSlot normalises")
TK.SetSlot(1, "BOB")
eq(TK.GetSlot(1), "Bob", "dedupe: MT gets Bob"); eq(TK.GetSlot(2), "", "dedupe: OT1 cleared")
eq(TK.FindSlot("bOb"), 1, "FindSlot case-insensitive"); eq(TK.FindSlot("Nobody"), nil, "FindSlot miss")
local ok2 = TK.SetSlot(1, "/;[]")
eq(ok2, false, "SetSlot rejects junk name"); eq(TK.GetSlot(1), "Bob", "junk leaves slot unchanged")
eq((TK.SetSlot(3, "Bob")), false, "SetSlot rejects a slot beyond NumTanks"); eq((TK.SetSlot(0, "Bob")), false, "SetSlot rejects slot 0")
TK.SetSlot(1, ""); eq(TK.GetSlot(1), "", "SetSlot '' clears the name")

reset()
for i = 2, TK.MAX_TANKS do eq(TK.AddTank(), i, "AddTank fills slot " .. i) end
local noIdx, fullErr = TK.AddTank()
eq(noIdx, nil, "AddTank refuses past the max"); eq(TK.NumTanks(), TK.MAX_TANKS, "NumTanks capped")
eq(fullErr:find(tostring(TK.MAX_TANKS), 1, true) ~= nil, true, "AddTank error mentions the limit")

reset(); TK.AddTank(); TK.AddTank()
TK.SetSlot(2, "A"); TK.SetSlot(3, "B"); TK.AddPick(3, "Innervate")
eq((TK.RemoveTank(1)), false, "the MT slot can't be removed")
eq((TK.RemoveTank(9)), false, "RemoveTank bad slot")
eq((TK.RemoveTank(2)), true, "RemoveTank ok"); eq(TK.NumTanks(), 2, "one slot fewer")
eq(TK.GetSlot(2), "B", "later slots shift down"); eq(TK.GetPicks(2)[1], "Innervate", "picks travel with their slot")

reset(); TK.AddTank(); TK.SetSlot(2, "Bob"); TK.AddPick(2, "Innervate"); TK.SetSlot(1, "bob")
eq(TK.GetSlot(1), "Bob", "dedupe moved the name to the MT"); eq(TK.GetSlot(2), "", "...out of OT1")
eq(#TK.GetPicks(2), 1, "dedupe moves the name, not the picks"); eq(#TK.GetPicks(1), 0, "MT did not inherit the picks")

reset()
eq((TK.SetFirstOT("Aa")), true, "SetFirstOT adds a slot when there is none"); eq(TK.NumTanks(), 2, "one OT slot"); eq(TK.GetSlot(2), "Aa", "OT1=Aa")
TK.SetFirstOT("Bb"); TK.SetFirstOT("Cc")
eq(TK.NumTanks(), 4, "three OT slots"); eq(TK.GetSlot(4), "Cc", "OT3=Cc")
eq((TK.SetFirstOT("aa")), true, "already listed is ok"); eq(TK.NumTanks(), 4, "...and adds no slot")
TK.SetSlot(3, ""); TK.SetFirstOT("Dd"); eq(TK.GetSlot(3), "Dd", "fills a hole before adding a slot"); eq(TK.NumTanks(), 4, "no new slot")
reset()
for k = 1, TK.MAX_TANKS - 1 do TK.SetFirstOT(nm(k)) end
eq(TK.NumTanks(), TK.MAX_TANKS, "off-tanks fill every slot")
eq((TK.SetFirstOT(nm(999))), false, "no room for another OT")

reset(); TK.AddTank(); TK.SetSlot(1, "Aa"); TK.SetSlot(2, "Bb"); TK.AddPick(1, "Innervate")
TK.ClearNames()
eq(TK.GetSlot(1) .. TK.GetSlot(2), "", "ClearNames clears every name"); eq(TK.NumTanks(), 2, "...keeps the slots"); eq(#TK.GetPicks(1), 1, "...and the picks")
TK.Reset(); eq(TK.NumTanks(), 1, "Reset back to the MT slot"); eq(#TK.GetPicks(1), 0, "Reset wipes picks")

reset(); TK.AddTank(); TK.AddTank(); TK.AddPick(2, "Innervate")
TK.TrimEmpty(); eq(TK.NumTanks(), 2, "TrimEmpty drops trailing empty slots but keeps one with picks")

-- ---- picks -----------------------------------------------------------------
reset()
eq((TK.AddPick(1, "Misdirection")), true, "AddPick ok"); eq(TK.GetPicks(1)[1], "Misdirection", "pick stored")
local okd = TK.AddPick(1, "misdirection")
eq(okd, false, "duplicate pick rejected (case-insensitive)"); eq(#TK.GetPicks(1), 1, "no duplicate stored")
eq((TK.AddPick(1, "")), false, "empty pick rejected"); eq((TK.AddPick(1, "  ; / ")), false, "pick that sanitises to empty rejected")
TK.AddPick(1, "Innervate"); TK.AddPick(1, "Hand of Sacrifice"); TK.AddPick(1, "Pain Suppression")
for k = 5, TK.MAX_PICKS do TK.AddPick(1, "Filler " .. k) end
eq(#TK.GetPicks(1), TK.MAX_PICKS, "picks fill up to the cap")
local okc, errc = TK.AddPick(1, "Power Word: Shield")
eq(okc, false, "cap rejects the pick past the limit"); eq(errc:find(tostring(TK.MAX_PICKS), 1, true) ~= nil, true, "cap error mentions the limit")
eq((TK.SetPick(1, 2, "Guardian Spirit")), true, "SetPick replaces"); eq(TK.GetPicks(1)[2], "Guardian Spirit", "replaced")
eq((TK.SetPick(1, 2, "Misdirection")), false, "SetPick rejects a duplicate of another pick")
eq((TK.SetPick(1, 2, "Guardian Spirit")), true, "SetPick to the same text is fine")
eq((TK.SetPick(1, 9, "Innervate")), false, "SetPick bad index")
eq((TK.RemovePick(1, 1)), true, "RemovePick ok"); eq(TK.GetPicks(1)[1], "Guardian Spirit", "later picks shift up"); eq(#TK.GetPicks(1), TK.MAX_PICKS - 1, "one fewer")
eq((TK.RemovePick(1, 9)), false, "RemovePick bad index")
eq((TK.AddPick(9, "Innervate")), false, "AddPick bad slot")
reset(); TK.AddPick(1, "|cff71d5ff|Hspell:34477|h[Misdirection]|h|r")
eq(TK.GetPicks(1)[1], "Misdirection", "AddPick accepts a shift-clicked spell link")
reset(); TK.AddPick(1, "Innervate; /run x")
eq(TK.GetPicks(1)[1], "Innervate run x", "AddPick sanitises macro characters")
local copy = TK.GetPicks(1); copy[1] = "Hacked"
eq(TK.GetPicks(1)[1], "Innervate run x", "GetPicks returns a copy")
reset(); TK.AddTank(); TK.AddTank(); TK.AddPick(2, "Innervate")
eq(TK.AddPickToAll("Innervate"), 2, "AddPickToAll skips slots that already have it")
eq(#TK.GetPicks(1) + #TK.GetPicks(2) + #TK.GetPicks(3), 3, "one pick per slot")
eq(TK.AddPickToAll(""), 0, "AddPickToAll ignores empty text")

do -- listeners
    reset(); local n = 0
    TK.OnChanged(function() n = n + 1 end)
    TK.SetSlot(1, "Bob"); eq(n, 1, "Changed fires on SetSlot")
    TK.SetSlot(1, "/"); eq(n, 1, "Changed not fired on rejected SetSlot")
    TK.AddPick(1, "Innervate"); eq(n, 2, "Changed fires on AddPick")
    TK.AddPick(1, ""); eq(n, 2, "Changed not fired on rejected AddPick")
    TK.AddTank(); eq(n, 3, "Changed fires on AddTank")
    TK.RemoveTank(1); eq(n, 3, "Changed not fired on rejected RemoveTank")
end
do -- db missing
    local saved = AIP.db; AIP.db = nil
    eq((TK.SetSlot(1, "Bob")), false, "SetSlot without db"); eq(TK.GetSlot(1), "", "GetSlot without db")
    eq(#TK.GetPicks(1), 0, "GetPicks without db"); eq(TK.NumTanks(), 1, "NumTanks without db")
    eq((TK.AddPick(1, "Innervate")), false, "AddPick without db"); eq(TK.AddTank(), nil, "AddTank without db")
    AIP.db = saved
end
do -- legacy shape migration + repair
    -- Each reassignment below simulates "here's what was on disk" and must be
    -- picked up fresh - but the new per-character migration only ever reads the
    -- old account-wide db.tankCast ONCE (when this character's own slot doesn't
    -- exist yet), so every line here also clears that per-character slot first,
    -- forcing a fresh migration each time (a real player only ever gets the
    -- one-time migration, on whichever character happens to load first).
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { mt = "Old", ots = { "Aa", "", "Bb" }, spell = "Innervate", shown = true }
    eq(TK.NumTanks(), 3, "migration: MT + the non-empty OTs")
    eq(TK.GetSlot(1), "Old", "migration: MT"); eq(TK.GetSlot(2), "Aa", "migration: OT1"); eq(TK.GetSlot(3), "Bb", "migration: holes dropped")
    eq(TK.GetPicks(1)[1] .. TK.GetPicks(2)[1] .. TK.GetPicks(3)[1], "InnervateInnervateInnervate", "migration: shared spell becomes each slot's first pick")
    eq(AIP.db.tankCast, nil, "migration: the old account-wide key is cleared once claimed")
    local claimed = AIP.db.tankCastByChar[currentCharKey]
    eq(claimed.mt, nil, "migration: legacy mt removed"); eq(claimed.ots, nil, "migration: legacy ots removed"); eq(claimed.spell, nil, "migration: legacy spell removed")
    eq(claimed.shown, true, "migration keeps unrelated keys")
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { mt = "", ots = { "", "", "" }, spell = "Misdirection" }
    eq(TK.NumTanks(), 1, "migration: empty OTs dropped"); eq(TK.GetPicks(1)[1], "Misdirection", "migration: MT gets the pick even with an empty name")
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { mt = "", ots = { "", "", "" }, spell = "" }
    eq(#TK.GetPicks(1), 0, "migration: no legacy spell -> no picks")
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { tanks = { "junk", { name = 5, picks = "x" }, { name = "Ok", picks = { "A", "B", "C", "D", "E", 7 } } } }
    eq(TK.NumTanks(), 3, "repair keeps the slot count"); eq(TK.GetSlot(1), "", "repair: junk entry becomes an empty slot")
    eq(TK.GetSlot(2), "", "repair: non-string name"); eq(TK.GetSlot(3), "Ok", "repair keeps valid slots")
    eq(#TK.GetPicks(3), 5, "repair: non-string picks dropped, valid ones kept")
    local lots = {}; for k = 1, TK.MAX_PICKS + 3 do lots[k] = "P" .. k end
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { tanks = { { name = "", picks = lots } } }
    eq(#TK.GetPicks(1), TK.MAX_PICKS, "repair: picks capped at the max")
    local many = {}; for i = 1, TK.MAX_TANKS + 4 do many[i] = { name = "", picks = {} } end
    AIP.db.tankCastByChar = nil
    AIP.db.tankCast = { tanks = many }
    eq(TK.NumTanks(), TK.MAX_TANKS, "repair: slot count clamped to the max")
end

do -- per-character scoping: two "characters" get independent tank lists
    reset()
    TK.SetSlot(1, "Alice"); TK.AddPick(1, "Innervate")
    currentCharKey = "TestRealm-Alt"
    eq(TK.NumTanks(), 1, "a different character starts with a clean list")
    eq(TK.GetSlot(1), "", "...no name carried over")
    eq(#TK.GetPicks(1), 0, "...and no picks carried over (this is the bug being fixed)")
    TK.SetSlot(1, "Bob")
    currentCharKey = "TestRealm-Me"
    eq(TK.GetSlot(1), "Alice", "switching back: the first character's own data is untouched")
    eq(TK.GetPicks(1)[1], "Innervate", "...including its picks")
end

-- ---- units / candidates ----------------------------------------------------
reset()
local solo = TK.GetCandidates()
eq(#solo, 1, "solo: one candidate"); eq(solo[1].name, "Me", "solo: the player"); eq(TK.UnitFor("me"), "player", "solo UnitFor")
reset()
roster = { { name = "Zed", class = "MAGE" }, { name = "Bram", class = "WARRIOR" }, { name = "Ann", class = "DRUID" }, { name = "Cy", class = "PRIEST" } }
local c = TK.GetCandidates()
eq(c[1].name .. c[2].name .. c[3].name .. c[4].name, "AnnBramCyZed", "candidates: tank classes first, then alpha")
eq(c[1].tank, true, "Ann tank-capable"); eq(c[3].tank, false, "Cy not tank-capable")
eq(TK.UnitFor("bram"), "raid2", "UnitFor case-insensitive"); eq(TK.UnitFor("nobody"), nil, "UnitFor miss")

-- ---- spell resolution / cooldown / presets ---------------------------------
local kind, icon, dn = TK.ResolveSpell("Misdirection")
eq(kind, "spell", "Resolve spell kind"); eq(icon, "icon1", "Resolve spell icon"); eq(dn, "Misdirection", "Resolve spell name")
kind, icon = TK.ResolveSpell("Hearthstone"); eq(kind, "item", "Resolve item kind"); eq(icon, "icon2", "Resolve item icon")
eq(TK.ResolveSpell("Nope"), nil, "Resolve unknown"); eq(TK.ResolveSpell(""), nil, "Resolve empty")
local s, d = TK.GetCooldown("Misdirection", "spell"); eq(s .. "/" .. d, "10/30", "cooldown spell")
s, d = TK.GetCooldown("Hearthstone", "item"); eq(s .. "/" .. d, "5/60", "cooldown item")
s, d = TK.GetCooldown("", nil); eq(s .. "/" .. d, "0/0", "cooldown empty")

-- ---- spellbook / bag pickers (whole spellbook; bag items usable on a friendly target) --
local function names(list) local t = {}; for _, e in ipairs(list) do t[#t + 1] = e.name end; return table.concat(t, ",") end
local sp, filtered = TK.ListSpells()
eq(names(sp), "Attack,Fireball,Misdirection,Power Word: Shield,Righteous Fury",
    "ListSpells lists the whole spellbook unfiltered - only passives/dupes dropped (helpful+range filtering was removed: it left too few spells for some classes to be usable)")
eq(filtered, true, "ListSpells reports its list as complete")
eq(sp[1].icon, "tex1", "ListSpells icon (Attack, alphabetically first)")
eq(sp[1].index, 1, "ListSpells index of first entry")
local it, ifiltered = TK.ListItems()
eq(names(it), "Linen Bandage,Runed Talisman,Healing Potion,Scroll of Stamina V",
    "ListItems: API-positive + text-positive + known-kind items (now incl. potions/food/consumables); drops junk/enemy-text; dedupes; sorted by kind")
eq(ifiltered, true, "ListItems reports API filtering active")
eq(it[1].icon, "iconB", "ListItems icon")
eq(it[1].kind, "Bandage", "ListItems kind: bandage")
eq(it[2].kind, "Helpful item", "ListItems kind: generic helpful item")
eq(it[2].effect, "Grants target friendly player 300 armor for 10 sec.", "ListItems carries the Use effect")
eq(it[3].kind, "Potion", "ListItems kind: potion (self-only consumables are now valid quick-cast picks)")
eq(it[4].kind, "Scroll", "ListItems kind: scroll")
do
    local saved = ItemHasRange; ItemHasRange = nil
    local all = TK.ListItems()
    eq(names(all), "Linen Bandage,Runed Talisman,Junk,Healing Potion,Scroll of Stamina V",
        "ListItems fallback: undecidable items included when an API is missing; enemy-text still excluded")
    ItemHasRange = saved
end

-- ---- ClassifyItem: what an item is and whether it can target a friendly ----
local function cls(name) return TK.ClassifyItem(itemDB[name][2]) end
local cc = cls("Linen Bandage")
eq(cc.castable, true, "classify: bandage castable"); eq(cc.kind, "Bandage", "classify: bandage kind"); eq(cc.why, "api", "classify: bandage via API")
cc = cls("Healing Potion")
eq(cc.castable, true, "classify: potion is self-only but still a valid quick-cast pick")
eq(cc.kind, "Potion", "classify: potion kind"); eq(cc.why, "kind", "classify: potion via named kind")
cc = cls("Mystery Draft")
eq(cc.castable, true, "classify: unnamed Consumable-class item with no enemy signal included via the broad catch-all")
eq(cc.why, "consumable", "classify: via the Consumable item-class catch-all, not a named kind")
cc = cls("Runed Talisman")
eq(cc.castable, true, "classify: strong friendly text wins over silent API"); eq(cc.why, "text", "classify: via text")
cc = cls("Mender Doll")
eq(cc.castable, true, "classify: weak 'target' text + helpful API"); eq(cc.why, "text", "classify: Mender Doll via text")
eq(cls("Odd Gadget").castable, false, "classify: weak 'target' text without helpful API is not enough")
eq(cls("Blasting Vial").castable, false, "classify: enemy text excluded")
eq(cls("Mixed Charm").castable, false, "classify: mixed enemy+friendly text excluded")
cc = cls("Cursed Vial")
eq(cc.castable, false, "classify: harmful API beats helpful+range"); eq(cc.why, "harmful", "classify: harmful reason")
cc = cls("Scroll of Stamina V")
eq(cc.castable, true, "classify: scroll by kind"); eq(cc.kind, "Scroll", "classify: scroll kind"); eq(cc.why, "kind", "classify: scroll via kind")
cc = cls("Master Soulstone")
eq(cc.castable, true, "classify: soulstone by kind"); eq(cc.kind, "Soulstone", "classify: soulstone kind")
cc = cls("Battle Trinket")
eq(cc.castable, false, "classify: 'your current target' is self-referential, not a friendly-cast signal, even though the API says helpful")
eq(cls("Junk").castable, nil, "classify: no info -> nil")
eq(TK.ClassifyItem(nil).castable, nil, "classify: nil link is safe")
eq(TK.IsFriendlyCastable("Mender Doll"), true, "friendly: text-detected item by name")
eq(TK.IsFriendlyCastable("Blasting Vial"), false, "friendly: enemy-text item by name")

eq(TK.IsFriendlyCastable("Misdirection"), true, "friendly: ranged helpful spell")
eq(TK.IsFriendlyCastable("Righteous Fury"), false, "friendly: self-only spell rejected")
eq(TK.IsFriendlyCastable("Linen Bandage"), true, "friendly: bandage item")
eq(TK.IsFriendlyCastable("Healing Potion"), true, "friendly: self-only potion is a valid pick even though it can't literally be cast ON someone else")
eq(TK.IsFriendlyCastable("Nope"), nil, "friendly: unknown text -> nil (no verdict)")
do
    local saved = SpellHasRange; SpellHasRange = nil
    eq(TK.IsFriendlyCastable("Misdirection"), nil, "friendly: API missing -> nil (no verdict)")
    SpellHasRange = saved
end

cursor = { "spell", 2, "spell" }; eq(TK.FromCursor(), "Misdirection", "FromCursor spell")
cursor = { "item", 6948 };        eq(TK.FromCursor(), "Hearthstone", "FromCursor item")
cursor = { "macro", 1 };          eq(TK.FromCursor(), nil, "FromCursor ignores macros")
cursor = nil;                     eq(TK.FromCursor(), nil, "FromCursor empty cursor")

-- ---- Blizzard import / push ------------------------------------------------
reset(); eq((TK.ImportFromBlizzard()), false, "Import solo fails")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Heal", class = "PRIEST" },
           { name = "Offy", class = "PALADIN", role = "MAINASSIST" }, { name = "Alty", class = "DRUID", role = "MAINASSIST" } }
TK.AddTank(); TK.AddTank(); TK.AddTank(); TK.SetSlot(4, "Old"); TK.AddPick(4, "Innervate")
local iok = TK.ImportFromBlizzard()
eq(iok, true, "Import ok"); eq(TK.GetSlot(1), "Tanky", "Import MT"); eq(TK.GetSlot(2), "Offy", "Import MA1")
eq(TK.GetSlot(3), "Alty", "Import MA2"); eq(TK.GetSlot(4), "", "Import clears leftover names")
eq(TK.NumTanks(), 4, "Import keeps a trailing slot that still has picks"); eq(TK.GetPicks(4)[1], "Innervate", "Import keeps picks")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Offy", class = "PALADIN", role = "MAINASSIST" } }
for _ = 1, 5 do TK.AddTank() end
TK.ImportFromBlizzard(); eq(TK.NumTanks(), 2, "Import trims trailing empty slots")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" } }
for k = 1, TK.MAX_TANKS + 2 do roster[#roster + 1] = { name = nm(k), class = "PALADIN", role = "MAINASSIST" } end
TK.ImportFromBlizzard()
eq(TK.NumTanks(), TK.MAX_TANKS, "Import adds OT slots up to the max"); eq(TK.GetSlot(TK.MAX_TANKS), nm(TK.MAX_TANKS - 1), "Import caps at MAX_TANKS - 1 off-tanks")
reset()
roster = { { name = "Heal", class = "PRIEST" } }; TK.SetSlot(1, "Keep")
local nok = TK.ImportFromBlizzard()
eq(nok, false, "Import with no flags fails"); eq(TK.GetSlot(1), "Keep", "Import with no flags changes nothing")

-- ---- RDF-assigned tank role (UnitGroupRolesAssigned - a Dungeon Finder
-- PARTY, not a raid, so the old MAINTANK/MAINASSIST-only import could never
-- find a tank there at all) ---------------------------------------------------
reset()
party = { { name = "Tanky", class = "WARRIOR" }, { name = "Heal", class = "PRIEST" }, { name = "Dps", class = "MAGE" } }
lfdRoles["party1"] = "TANK"
local rok, rmsg = TK.ImportFromBlizzard()
eq(rok, true, "RDF party import ok (no raid at all - this used to be impossible)")
eq(TK.GetSlot(1), "Tanky", "RDF import: the LFD-assigned TANK role wins the MT slot")
eq(rmsg:find("LFD", 1, true) ~= nil, true, "RDF import: message says how the tank was found")

reset()
party = { { name = "Me", class = "DRUID" }, { name = "Tanky2", class = "WARRIOR" } }
lfdRoles.player = "TANK"
eq(TK.ImportFromBlizzard(), true, "RDF import: the player's own party unit ('player') is checked too, not just partyN")
eq(TK.GetSlot(1), "Me", "RDF import: self as the LFD tank")

-- A manually-formed raid reports NONE for everyone (UnitGroupRolesAssigned
-- is populated by the Dungeon Finder tool specifically) - falls through to
-- the existing MAINTANK/MAINASSIST flag path with no special-casing needed.
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Offy", class = "PALADIN", role = "MAINASSIST" } }
for i = 1, #roster do lfdRoles["raid" .. i] = "NONE" end
local fok, fmsg = TK.ImportFromBlizzard()
eq(fok, true, "Fallback to raid flags when nobody has an LFD role")
eq(TK.GetSlot(1), "Tanky", "Fallback: MT from the raid flag, not LFD")
eq(fmsg:find("LFD", 1, true), nil, "Fallback: message does not claim an LFD source")

-- ---- Pet auto-fill on import (Hunter/Warlock/etc with an active pet get a
-- second slot for the pet, not just themselves) ------------------------------
reset()
roster = { { name = "Hunty", class = "HUNTER", role = "MAINTANK", pet = { name = "Wolfy", class = "WARRIOR" } },
           { name = "Offy", class = "PALADIN", role = "MAINASSIST" } }
local pok, pmsg = TK.ImportFromBlizzard()
eq(pok, true, "Import with a pet-class tank ok")
eq(TK.GetSlot(1), "Hunty", "Import: MT is the player, not the pet")
eq(TK.FindSlot("Wolfy") ~= nil, true, "Import: the pet got its own slot")
eq(TK.GetSlot(2), "Offy", "Import: the off-tank from Main Assist still got its own slot (pet appended after)")
eq(TK.GetSlot(3), "Wolfy", "Import: the pet slot is appended after the flag-based slots")
eq(pmsg:find("pet", 1, true) ~= nil, true, "Import: message mentions the auto-added pet slot")

reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" } }   -- no pet field: not a pet class
TK.ImportFromBlizzard()
eq(TK.NumTanks(), 1, "Import: no pet slot added for a class with no active pet")

reset()
roster = { { name = "Hunty", class = "HUNTER", role = "MAINTANK", pet = { name = "Wolfy", class = "WARRIOR" } } }
TK.AddTank(); TK.SetSlot(2, "Wolfy")   -- the pet is already manually slotted
TK.ImportFromBlizzard()
eq(TK.NumTanks(), 2, "Import: AutoFillPets does not duplicate a pet that already has a slot")

reset()
roster = { { name = "Hunty", class = "HUNTER", pet = { name = "Wolfy Junior", class = "WARRIOR" } } }
TK.SetSlot(1, "Hunty")
local added = TK.AutoFillPets()
eq(added, 0, "AutoFillPets: a pet name with a space can't go in a target/cast macro, so it's skipped")
eq(TK.NumTanks(), 1, "...and no slot was added for it")

reset()
roster = { { name = "Tanky", class = "WARRIOR" }, { name = "Offy", class = "PALADIN" }, { name = "Alty", class = "DRUID" } }
TK.AddTank(); TK.AddTank(); TK.SetSlot(1, "Tanky"); TK.SetSlot(2, "Offy"); TK.SetSlot(3, "Alty")
eq(TK.CanPush(), false, "CanPush false for plain member")
eq((TK.PushToBlizzard()), false, "Push refused for plain member"); eq(#assignCalls, 0, "Push made no API calls")
isOfficer = true
eq(TK.CanPush(), true, "CanPush true for assist")
eq((TK.PushToBlizzard()), true, "Push ok")
eq(assignCalls[1], "MAINTANK:raid1", "Push MT"); eq(assignCalls[2], "MAINASSIST:raid2", "Push OT1"); eq(assignCalls[3], "MAINASSIST:raid3", "Push OT2")
TK.PushToBlizzard(); eq(#assignCalls, 3, "Push skips flags already set")
reset(); isLeader = true; eq(TK.CanPush(), false, "CanPush false when not in a raid")

-- ---- slash handler ---------------------------------------------------------
reset(); targetName = "Bram"
TK.SlashHandler("mt"); eq(TK.GetSlot(1), "Bram", "slash mt uses the target")
TK.SlashHandler("ot cy"); eq(TK.GetSlot(2), "Cy", "slash ot fills the first OT"); eq(TK.NumTanks(), 2, "slash ot added a slot")
TK.SlashHandler("addot"); eq(TK.NumTanks(), 3, "slash addot")
TK.SlashHandler("pick mt Misdirection"); eq(TK.GetPicks(1)[1], "Misdirection", "slash pick mt")
TK.SlashHandler("pick ot1 Hand of Sacrifice"); eq(TK.GetPicks(2)[1], "Hand of Sacrifice", "slash pick ot1")
TK.SlashHandler("pick 3 Innervate"); eq(TK.GetPicks(3)[1], "Innervate", "slash pick by number")
printed = {}; TK.SlashHandler("pick ot9 Innervate"); eq(#printed > 0, true, "slash pick on a missing slot explains")
TK.SlashHandler("unpick mt misdirection"); eq(#TK.GetPicks(1), 0, "slash unpick is case-insensitive")
TK.SlashHandler("spell Power Word: Shield")
eq(TK.GetPicks(1)[1], "Power Word: Shield", "slash spell adds to the MT"); eq(TK.GetPicks(2)[2], "Power Word: Shield", "...and to every other tank")
TK.SlashHandler("mt Zed"); eq(TK.GetSlot(1), "Zed", "slash mt <name>")
TK.SlashHandler("clear"); eq(TK.GetSlot(1) .. TK.GetSlot(2), "", "slash clear empties the names"); eq(TK.NumTanks(), 3, "...but keeps the slots")
TK.SlashHandler("reset"); eq(TK.NumTanks(), 1, "slash reset"); eq(#TK.GetPicks(1), 0, "slash reset wipes picks")
printed = {}; TK.SlashHandler("list"); eq(#printed >= 1, true, "slash list prints")
printed = {}; TK.SlashHandler("bogus"); eq(#printed > 0, true, "slash unknown prints usage")

-- ---- restyle helpers -------------------------------------------------------
eq(TK.FormatCooldown(nil), "", "cooldown text: nil"); eq(TK.FormatCooldown(0), "", "cooldown text: zero"); eq(TK.FormatCooldown(-3), "", "cooldown text: negative")
eq(TK.FormatCooldown(0.3), "1", "cooldown text: sub-second rounds up"); eq(TK.FormatCooldown(12), "12", "cooldown text: seconds")
eq(TK.FormatCooldown(12.2), "13", "cooldown text: rounds up like a countdown")
eq(TK.FormatCooldown(59.5), "1:00", "cooldown text: 60 flips to m:ss"); eq(TK.FormatCooldown(65), "1:05", "cooldown text: m:ss")
eq(TK.FormatCooldown(600), "10m", "cooldown text: minutes"); eq(TK.FormatCooldown(3600), "1h", "cooldown text: hours")
local function rgb(r, g, b) return string.format("%.2f,%.2f,%.2f", r, g, b) end
eq(rgb(TK.HealthColor(1)), "0.20,0.85,0.30", "health colour: full = green")
eq(rgb(TK.HealthColor(0.5)), "0.95,0.80,0.20", "health colour: half = amber")
eq(rgb(TK.HealthColor(0)), "0.90,0.20,0.20", "health colour: empty = red")
eq(rgb(TK.HealthColor(0.6)), "0.80,0.81,0.22", "health colour: ramps between amber and green")
eq(rgb(TK.HealthColor(2)), rgb(TK.HealthColor(1)), "health colour: clamped high")
eq(rgb(TK.HealthColor(-1)), rgb(TK.HealthColor(0)), "health colour: clamped low")
eq(rgb(TK.HealthColor(nil)), rgb(TK.HealthColor(0)), "health colour: nil = empty")
eq(TK.ListItems()[1].quality, 1, "ListItems carries the item quality (for the picker border)")

TK.dirty = false; eq(TK.EditsAllowed(), true, "edits allowed when nothing is pending")
TK.dirty = true;  eq(TK.EditsAllowed(), false, "edits refused while a structural change is pending (display != live list)")
TK.dirty = false
-- ---- range / usability (per pick) -------------------------------------------
IsSpellInRange = function(spell, unit) return unit == "raid1" and 1 or 0 end
eq(TK.InRange("X", "raid1", "Not In Book", "spell"), true, "InRange uses a caller-supplied kind (no re-resolve): in range")
eq(TK.InRange("X", "raid2", "Not In Book", "spell"), false, "InRange uses a caller-supplied kind (no re-resolve): out of range")
eq(TK.InRange("X", nil, "Misdirection"), false, "InRange: unknown unit is out of range")
IsSpellInRange = nil
IsUsableSpell = function(n) if n == "Misdirection" then return 1, nil elseif n == "Innervate" then return nil, 1 end return nil, nil end
IsUsableItem = function(n) if n == "Linen Bandage" then return 1, nil end return nil, 1 end
local u, noMana = TK.Usability("Misdirection", "spell"); eq(tostring(u) .. tostring(noMana), "truefalse", "usability: castable spell")
u, noMana = TK.Usability("Innervate", "spell"); eq(tostring(u) .. tostring(noMana), "falsetrue", "usability: out of mana")
u, noMana = TK.Usability("Whatever", "spell"); eq(tostring(u) .. tostring(noMana), "falsefalse", "usability: not usable")
u, noMana = TK.Usability("Linen Bandage", "item"); eq(tostring(u) .. tostring(noMana), "truefalse", "usability: usable item")
u, noMana = TK.Usability("Whatever", nil); eq(tostring(u) .. tostring(noMana), "truefalse", "usability: unknown kind assumes usable")
IsUsableSpell = nil
u, noMana = TK.Usability("Misdirection", "spell"); eq(tostring(u) .. tostring(noMana), "truefalse", "usability: API missing assumes usable")

eq(TK.SlotBadge(1), "MT", "badge: main tank"); eq(TK.SlotBadge(2), "1", "badge: first off-tank"); eq(TK.SlotBadge(8), "7", "badge: last off-tank")
eq(TK.SlotBadge(nil), "?", "badge: nil slot"); eq(TK.SlotBadge(0), "?", "badge: slot 0")
-- ---- pets as tanks ---------------------------------------------------------
reset()
roster = { { name = "Hunty", class = "HUNTER", pet = { name = "Wolfy", class = "WARRIOR" } },
           { name = "Lockx", class = "WARLOCK", pet = { name = "Fire Elemental", class = "MAGE" } } }
local pcs = TK.GetCandidates()
eq(pcs[1].name .. pcs[2].name .. pcs[3].name, "HuntyLockxWolfy", "candidates: players first, then pets")
eq(#pcs, 3, "a pet whose name has spaces is left out"); eq(pcs[3].pet, true, "pet candidate is flagged"); eq(pcs[1].pet, false, "player candidate is not")
eq(TK.UnitFor("wolfy"), "raidpet1", "UnitFor resolves a pet by name")
eq(TK.IsPetUnit("raidpet1"), true, "IsPetUnit raidpet"); eq(TK.IsPetUnit("partypet2"), true, "IsPetUnit partypet"); eq(TK.IsPetUnit("pet"), true, "IsPetUnit pet")
eq(TK.IsPetUnit("raid1"), false, "IsPetUnit raid"); eq(TK.IsPetUnit(nil), false, "IsPetUnit nil")
reset()
roster = { { name = "Aa", class = "HUNTER", pet = { name = "Wolfy" } }, { name = "Bb", class = "HUNTER", pet = { name = "Wolfy" } } }
eq(TK.UnitFor("wolfy"), "raidpet1", "duplicate pet names: the first wins"); eq(TK.IsAmbiguousName("wolfy"), true, "duplicate pet names are flagged")
eq(TK.IsAmbiguousName("aa"), false, "a unique name is not ambiguous")
reset()
roster = { { name = "Aa", class = "HUNTER", pet = { name = "Wolfy" } }, { name = "Wolfy", class = "MAGE" } }
eq(TK.UnitFor("wolfy"), "raid2", "a player beats a pet with the same name"); eq(TK.IsAmbiguousName("wolfy"), true, "...and the clash is flagged")
reset(); soloPet = { name = "Kitty" }
eq(TK.UnitFor("kitty"), "pet", "solo: your own pet resolves")

-- ---- debuff listing / formatting -------------------------------------------
reset()
debuffs.raid1 = { { "Sunder Armor", "iconSA", 5, nil, 112 }, { "Curse of Weakness", "iconCW", 1, "Curse", 220 }, { "Deep Wound", "iconDW", nil, nil, 0 } }
local dl, dtotal = TK.ListDebuffs("raid1", 2)
eq(#dl, 2, "ListDebuffs honours the limit"); eq(dtotal, 3, "...but reports the real total")
eq(dl[1].name, "Sunder Armor", "debuff name"); eq(dl[1].icon, "iconSA", "debuff icon"); eq(dl[1].count, 5, "debuff stacks"); eq(dl[1].timeLeft, 12, "time left = expiration - now")
eq(dl[2].dtype, "Curse", "debuff dispel type"); eq(dl[2].timeLeft, 120, "long timer")
local dl3 = TK.ListDebuffs("raid1", 12)
eq(#dl3, 3, "all three listed under a big limit"); eq(dl3[3].timeLeft, nil, "no expiration = no timer")
eq(#TK.ListDebuffs(nil, 5), 0, "ListDebuffs nil unit"); eq(#TK.ListDebuffs("raid9", 5), 0, "ListDebuffs unit with none")
eq(TK.FormatDebuff({ name = "Sunder Armor", count = 5, timeLeft = 12 }), "Sunder Armor x5 (12s)", "debuff line: stacks + seconds")
eq(TK.FormatDebuff({ name = "Curse of Weakness", count = 1, timeLeft = 65 }), "Curse of Weakness (1:05)", "debuff line: one stack hidden, m:ss")
eq(TK.FormatDebuff({ name = "Deep Wound" }), "Deep Wound", "debuff line: bare")

-- ---- spec lookup (players via the inspection cache, pets n/a) --------------
reset()
roster = { { name = "Prot", class = "PALADIN" }, { name = "Nospec", class = "WARRIOR" }, { name = "Faraway", class = "DRUID" } }
local asked, specs = {}, { raid1 = "Protection" }
AIP.Composition = { GetSpecName = function(u) return specs[u] end, RequestInspect = function(u) asked[#asked + 1] = u end }
CanInspect = function() return true end
CheckInteractDistance = function(u) return u ~= "raid3" and 1 or nil end
local sp, st = TK.TankSpec("raid1"); eq(sp .. "/" .. st, "Protection/ok", "spec: cached")
sp, st = TK.TankSpec("raid2"); eq(tostring(sp) .. "/" .. st, "nil/inspecting", "spec: not cached -> inspecting"); eq(#asked, 1, "an inspect was requested")
TK.TankSpec("raid2"); eq(#asked, 1, "...but only once inside the throttle window")
now = 200; TK.TankSpec("raid2"); eq(#asked, 2, "...and again after it")
sp, st = TK.TankSpec("raid3"); eq(tostring(sp) .. "/" .. st, "nil/range", "spec: too far to inspect"); eq(#asked, 2, "no inspect requested out of range")
sp, st = TK.TankSpec("raidpet1"); eq(tostring(sp) .. "/" .. st, "nil/pet", "spec: pets have none")
sp, st = TK.TankSpec(nil); eq(tostring(sp) .. "/" .. st, "nil/unavailable", "spec: no unit")
AIP.Composition = nil
sp, st = TK.TankSpec("raid1"); eq(tostring(sp) .. "/" .. st, "nil/unavailable", "spec: composition module absent")
CanInspect, CheckInteractDistance = nil, nil; now = 100

-- ---- selector (target) macro -----------------------------------------------
eq(TK.BuildTargetMacro("Bob"), "/target Bob", "target macro"); eq(TK.BuildTargetMacro(""), nil, "target macro: no name")
eq(TK.BuildTargetMacro("Bob; /run"), "/target Bobrun", "target macro is sanitised")

-- ---- lock position / "is there anything to clear" ---------------------------
reset()
eq(TK.IsLocked(), false, "window starts unlocked")
eq(TK.ToggleLocked(), true, "toggle locks"); eq(TK.IsLocked(), true, "locked")
eq(AIP.db.tankCastByChar[currentCharKey].locked, true, "the lock is stored per-character (survives a reload)")
eq(TK.ToggleLocked(), false, "toggle unlocks"); eq(TK.IsLocked(), false, "unlocked")
TK.SetLocked(true); eq(TK.IsLocked(), true, "SetLocked(true)"); TK.SetLocked(false); eq(TK.IsLocked(), false, "SetLocked(false)")
do
    local saved = AIP.db; AIP.db = nil
    eq(TK.IsLocked(), false, "IsLocked without db"); eq(TK.ToggleLocked(), false, "ToggleLocked without db")
    AIP.db = saved
end
reset()
TK.SlashHandler("lock"); eq(TK.IsLocked(), true, "slash lock toggles on"); TK.SlashHandler("lock"); eq(TK.IsLocked(), false, "slash lock toggles off")
TK.SlashHandler("lock"); TK.SlashHandler("unlock"); eq(TK.IsLocked(), false, "slash unlock")
reset()
eq(TK.IsEmpty(), true, "a fresh list is empty")
TK.AddPick(1, "Innervate"); eq(TK.IsEmpty(), false, "a pick makes it non-empty"); TK.Reset(); eq(TK.IsEmpty(), true, "Reset empties it")
TK.SetSlot(1, "Bob"); eq(TK.IsEmpty(), false, "a named tank makes it non-empty"); TK.Reset()
TK.AddTank(); eq(TK.IsEmpty(), false, "an extra slot makes it non-empty"); TK.Reset()
eq(TK.IsEmpty(), true, "empty again after Reset")

-- ---- title-bar context menu model -------------------------------------------
reset()
local function menuItem(list, id) for _, it in ipairs(list) do if it.id == id then return it end end end
local tm = TK.TitleMenu()
eq(menuItem(tm, "add").text:find("1/" .. TK.MAX_TANKS, 1, true) ~= nil, true, "menu: add shows current/max")
eq(menuItem(tm, "add").enabled, true, "menu: add enabled below the cap")
eq(menuItem(tm, "push").enabled, false, "menu: push disabled without raid permission")
eq(menuItem(tm, "lock").text, "Lock position", "menu: lock label when unlocked")
eq(menuItem(tm, "clear").enabled, false, "menu: clear disabled when the list is already empty")
eq(menuItem(tm, "import").enabled, true, "menu: import always clickable (it reports its own failure)")
eq(menuItem(tm, "close").text, "Close", "menu: close is listed")

TK.AddPick(1, "Innervate")
tm = TK.TitleMenu(); eq(menuItem(tm, "clear").enabled, true, "menu: clear enables once there is something to clear")

TK.SetLocked(true)
tm = TK.TitleMenu(); eq(menuItem(tm, "lock").text, "Unlock position", "menu: lock label flips when locked")

reset(); isOfficer = true; roster = { { name = "Aa", class = "WARRIOR" } }
tm = TK.TitleMenu(); eq(menuItem(tm, "push").enabled, true, "menu: push enables for an officer in a raid")

reset()
for k = 1, TK.MAX_TANKS - 1 do TK.SetFirstOT(nm(k)) end
tm = TK.TitleMenu(); eq(menuItem(tm, "add").enabled, false, "menu: add disabled at the cap")

reset()
eq(TK.JustFormedGroup(), false, "solo: not just-formed")
roster = { { name = "Aa", class = "Warrior" } }
eq(TK.JustFormedGroup(), true, "solo -> raid: fires once")
eq(TK.JustFormedGroup(), false, "...but not again while still grouped")
roster[#roster + 1] = { name = "Bb", class = "Mage" }
eq(TK.JustFormedGroup(), false, "adding another member is not a fresh formation")
roster = {}
eq(TK.JustFormedGroup(), false, "leaving the group is not a formation")
eq(TK.JustFormedGroup(), false, "back to solo: still not just-formed")
party = { [1] = { name = "Cc", class = "Priest" } }
eq(TK.JustFormedGroup(), true, "solo -> party: fires once too")

-- The very first evaluation this session (fresh /reload or login) must only
-- SEED the latch, never fire it, even if the player is already grouped at
-- that point - otherwise every /reload mid-raid would re-open a window the
-- player had deliberately closed (TK.wasGrouped starts nil, not false, to
-- distinguish "never checked yet" from "checked and was solo").
reset()
roster = { { name = "Aa", class = "Warrior" } }
eq(TK.JustFormedGroup(), false, "first-ever check while ALREADY grouped (e.g. reload mid-raid) does not fire")
eq(TK.JustFormedGroup(), false, "...nor does the next check while nothing changed")
roster = {}
eq(TK.JustFormedGroup(), false, "leaving afterward is still not a formation")
party = { [1] = { name = "Cc", class = "Priest" } }
eq(TK.JustFormedGroup(), true, "a REAL solo -> party transition after that still fires")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)