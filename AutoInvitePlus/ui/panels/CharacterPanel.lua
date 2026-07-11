-- AutoInvite Plus - Character Panel (gear / upgrade / spec / coaching GUI)
-- Smart layout: a live summary header, a highlighted section nav (Gear /
-- Upgrades / Spec / Readiness), a clean scrolling list of icon rows (item rows
-- show the game tooltip on hover, shift-click to link), and a tidy footer with
-- the import box + coaching toggles.
--
-- IMPORTANT: this panel uses a PLAIN (un-templated) ScrollFrame + mousewheel.
-- The UIFactory CreateScrollList/CreateMultiLineEditBox helpers build their
-- scroll frame with a nil name, and UIPanelScrollBarTemplate's OnLoad then does
-- self:GetName().."ScrollUpButton" -> errors on an unnamed frame. So we avoid
-- those helpers here. CreateButton/CreateEditBox/CreateCheckbox are safe.

local AIP = AutoInvitePlus
if not AIP then return end
AIP.Panels = AIP.Panels or {}

local UI = AIP.UI
local P = {}
AIP.Panels.Character = P
P.section = "Gear"

local frame
local ROWH = 20

local function itemIcon(link) return link and select(10, GetItemInfo(link)) or nil end

-- Resolve an item link from an id, name-guarded (leading %a+ of `name` must match
-- the resolved item's name) so a stale/uncached id degrades to text in the caller,
-- never a wrong item. Shared by the Spec guide + the paperdoll slot detail.
local function linkFromID(id, name)
    if not (id and GetItemInfo) then return nil end
    local iname, ilink = GetItemInfo(id)
    if not (iname and ilink) then return nil end
    if name then
        local fw = name:match("^(%a+)")
        if not (fw and iname:lower():find(fw:lower(), 1, true)) then return nil end
    end
    return ilink
end

-- ============================================================================
-- Section content builders: each returns a list of {text/link/icon/right/rcolor}
-- ============================================================================
-- Which stat caps an item feeds (shown as an info row under each bag upgrade).
local function capContribution(link)
    if not (link and GetItemStats) then return nil end
    local t = {}; GetItemStats(link, t)
    local tags = {}
    if (t.ITEM_MOD_HIT_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "Hit" end
    if (t.ITEM_MOD_EXPERTISE_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "Expertise" end
    if (t.ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "ArP" end
    if (t.ITEM_MOD_DEFENSE_SKILL_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "Defense" end
    if (t.ITEM_MOD_HASTE_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "Haste" end
    if (t.ITEM_MOD_CRIT_RATING_SHORT or 0) > 0 then tags[#tags + 1] = "Crit" end
    if #tags == 0 then return nil end
    return table.concat(tags, ", ")
end

local buildUpgrades   -- forward decl (Gear section appends the progression)
-- PvP helpers (assigned below) - forward-declared so the early section builders
-- (buildGear / buildRotation) can reference them.
local pvpForPlayer, pvpStatLines, pvpGlyphLines

-- Small section header used to give the combined Gear tab structure.
local function header(e, title) e[#e + 1] = { text = "|cffffd100" .. title .. "|r" } end

-- Slots that can carry a permanent enchant (for the quick per-slot enchant flag).
local ENCHANTABLE_SLOTS = { [1]=1,[3]=1,[5]=1,[7]=1,[8]=1,[9]=1,[10]=1,[15]=1,[16]=1 }

local function buildGear()
    local e = {}
    local GA, IS = AIP.GearAdvisor, AIP.ItemScore
    if not (GA and IS) then return { { text = "Gear modules not loaded." } } end

    -- 0) Your current gear - EVERY equipped slot (the complete picture, in paperdoll
    -- order). Enchant flag is read from the item link (cheap); gems/enchant detail per
    -- slot live on the paperdoll icons + the summary below.
    header(e, "YOUR GEAR  (all slots)")
    local ALL_SLOTS = { 1, 2, 3, 15, 5, 9, 10, 6, 7, 8, 11, 12, 13, 14, 16, 17, 18 }
    for _, slot in ipairs(ALL_SLOTS) do
        local sname = (IS.SLOT_NAME and IS.SLOT_NAME[slot]) or ("Slot " .. slot)
        local link = GetInventoryItemLink("player", slot)
        if link then
            local ilvl = select(4, GetItemInfo(link)) or 0
            local flag = ""
            if ENCHANTABLE_SLOTS[slot] and (tonumber(link:match("item:%d+:(%d*)")) or 0) == 0 then
                flag = "  |cffff3030E|r"   -- missing enchant
            end
            e[#e+1] = { link = link, icon = itemIcon(link),
                right = (ilvl > 0 and ("iLvl " .. ilvl) or "?") .. flag, rightColor = {0.78,0.78,0.82} }
        else
            e[#e+1] = { text = "  " .. sname .. ":  |cffff5555EMPTY|r", rcolor = {1,0.5,0.5} }
        end
    end
    e[#e+1] = { text = " " }

    -- PvP mode: the gear recommendations are PvP (Wrathful arena) - resilience,
    -- the arena set, PvP gemming, key items. The all-slots list above still applies.
    if P.pvp then
        local D = pvpForPlayer()
        header(e, "PvP GEAR  (Wrathful arena)")
        if not D then
            e[#e+1] = { text = "  No PvP data for your spec (arena-viable specs only).", rcolor = {0.7,0.7,0.7} }
            return e
        end
        pvpStatLines(e, D)
        if D.setName then e[#e+1] = { text = "  Set: " .. D.setName, rcolor = {0.85,0.7,1} } end
        if D.keyItems then e[#e+1] = { text = "  " .. D.keyItems, rcolor = {0.82,0.82,0.88} } end
        e[#e+1] = { text = " " }
        header(e, "PvP GEMS & ENCHANTS")
        local gplan, gnuance = AIP.PvPData.GemPlanForPlayer and AIP.PvPData.GemPlanForPlayer()
        if gplan then
            e[#e+1] = { text = "  Meta: " .. gplan.meta, rcolor = {0.7,0.85,1} }
            e[#e+1] = { text = "  " .. gplan.gems, rcolor = {0.7,0.85,1} }
            if gnuance then e[#e+1] = { text = "  " .. gnuance, rcolor = {0.78,0.8,0.5} } end
        elseif D.gemNote then
            e[#e+1] = { text = "  " .. D.gemNote, rcolor = {0.7,0.85,1} }
        end
        local eplan = AIP.PvPData.EnchantPlanForPlayer and AIP.PvPData.EnchantPlanForPlayer()
        if eplan then
            e[#e+1] = { text = "  |cffffd100PvP enchants|r  |cff888888([PvP] = differs from PvE)|r", rcolor = {0.9,0.82,0.2} }
            for _, ln in ipairs(eplan) do e[#e+1] = { text = "   " .. ln, rcolor = {0.62,0.7,0.62} } end
        else
            e[#e+1] = { text = "  Enchants: the PvE enchants apply - click a slot for the exact enchant.", rcolor = {0.58,0.6,0.68} }
        end
        e[#e+1] = { text = "  Always slot the on-use PvP trinket (breaks a stun/fear).", rcolor = {0.58,0.6,0.68} }
        return e
    end

    -- 1) Enchants & gems on what you're wearing.
    header(e, "ENCHANTS & GEMS")
    local missing, sockets = GA.Audit()
    e[#e+1] = (#missing > 0) and { text = "  Missing enchants: " .. table.concat(missing, ", "), rcolor = {1,0.45,0.45} }
        or { text = "  All enchantable slots enchanted.", rcolor = {0.45,1,0.45} }
    e[#e+1] = (sockets > 0) and { text = "  Empty gem sockets: " .. sockets, rcolor = {1,0.45,0.45} }
        or { text = "  No empty gem sockets.", rcolor = {0.45,1,0.45} }

    -- 2) Upgrades already sitting in your bags (spec-aware, cap-aware).
    e[#e+1] = { text = " " }
    header(e, "UPGRADES IN YOUR BAGS")
    local finds = GA.BestFromBags()
    if #finds == 0 then
        e[#e+1] = { text = "  Nothing in your bags beats what you're wearing.", rcolor = {0.45,1,0.45} }
    else
        e[#e+1] = { text = "  tick a box to preview the new stats under your model ->", rcolor = {0.55,0.7,0.85} }
        for i = 1, math.min(#finds, 10) do
            local f = finds[i]
            e[#e+1] = { link = f.link, icon = itemIcon(f.link),
                right = string.format("+%.0f%%", f.pct), rightColor = {0.45,1,0.45},
                whatif = { link = f.link, slot = f.slot } }
            local cap = capContribution(f.link)
            if cap then e[#e+1] = { text = "        counts toward: " .. cap, rcolor = {0.6,0.65,0.72} } end
        end
    end
    GA.BroadcastMine(#missing, sockets)

    -- 3) Where to go next: weakest slots + the BiS progression + tier.
    e[#e+1] = { text = " " }
    for _, x in ipairs(buildUpgrades()) do e[#e+1] = x end
    return e
end

function buildUpgrades()
    local e = {}
    local UP = AIP.UpgradePath
    if not UP then return { { text = "UpgradePath not loaded." } } end
    local avg = UP.AvgItemLevel()
    local run, why = UP.RecommendContent(avg)
    header(e, "WHERE TO GO NEXT")
    e[#e+1] = { text = "  Run next: " .. run, rcolor = {0.9,0.85,0.5} }
    e[#e+1] = { text = "  (" .. why .. ")", rcolor = {0.7,0.7,0.7} }
    e[#e+1] = { text = " " }
    e[#e+1] = { text = "Weakest slots (upgrade first):", rcolor = {1,0.85,0.2} }
    for _, r in ipairs(UP.WeakestSlots(6)) do
        if r.link then
            e[#e+1] = { link = r.link, icon = itemIcon(r.link), right = "iLvl " .. r.ilvl, rightColor = {0.8,0.8,0.8} }
        else
            e[#e+1] = { text = "Empty slot!", rcolor = {1,0.45,0.45} }
        end
    end
    -- BiS chase-list: next best-or-better items + where they drop.
    local arch = AIP.ItemScore and AIP.ItemScore.PlayerArchetype()
    local bis = AIP.BiSData and arch and AIP.BiSData.ForArchetype(arch)
    if bis and #bis > 0 then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "BiS progression - get each in order (hover a link for the tooltip):", rcolor = {1,0.85,0.2} }
        local _, classFile = UnitClass("player")
        -- push a link row (name-guarded) or a coloured-text fallback
        local function pushItem(name, id, note)
            local iname, ilink
            if id and GetItemInfo then iname, ilink = GetItemInfo(id) end
            local fw = name:match("^(%a+)")
            if ilink and iname and fw and iname:lower():find(fw:lower(), 1, true) then
                e[#e+1] = { link = ilink, icon = itemIcon(ilink), right = note, rightColor = {0.7,0.6,0.85} }
            else
                e[#e+1] = { text = "  |cffa335ee" .. name .. "|r  (" .. note .. ")", rcolor = {0.75,0.65,0.9} }
            end
        end
        for _, s in ipairs(bis) do
            e[#e+1] = { text = s.slot .. ":", rcolor = {0.55,0.75,1} }
            local tierInfo = s.slot:find("Tier") and AIP.BiSData and AIP.BiSData.TierFor and AIP.BiSData.TierFor(classFile, arch)
            if tierInfo then
                local slotNames = (AIP.BiSData and AIP.BiSData.TierSlots) or { "Helm", "Shoulders", "Chest", "Hands", "Legs" }
                for pi = 1, 5 do
                    if tierInfo[pi + 1] then
                        pushItem(tierInfo[1] .. " " .. slotNames[pi], tierInfo[pi + 1], "T10 " .. slotNames[pi])
                    end
                end
                e[#e+1] = { text = "      " .. tierInfo[1] .. " - Emblems of Frost + ICC tier token (264 -> HC 277)", rcolor = {0.58,0.58,0.58} }
            else
                for _, it in ipairs(s.chain) do
                    pushItem(it[1], it[2], it[4])
                    e[#e+1] = { text = "      " .. it[3], rcolor = {0.58,0.58,0.58} }
                    -- Also list the 25-Heroic version of this drop, when there is one.
                    local hid = it[2] and AIP.BiSData and AIP.BiSData.Heroic and AIP.BiSData.Heroic[it[2]]
                    if hid then
                        pushItem(it[1] .. " (Heroic)", hid, "25 Heroic upgrade")
                    end
                end
            end
        end
    end
    return e
end

-- (buildSpec removed: the Spec section renders the talent graphic + guide sidebar
-- via renderTalents, not a row list, so the old row-builder was dead code.)


local function buildRotation()
    local Rot = AIP.Rotation
    if not Rot then return { { text = "Rotation module not loaded - log out to character select and back in.", rcolor = {1,0.7,0.2} } } end

    -- PvP mode: arena play is situational (comp/target driven), so instead of a fixed
    -- rotation we surface the PvP priorities: stat/glyph reminders + the core tenets.
    local e = {}
    -- PvP mode: prepend the arena priorities (stat/glyph reminders + core tenets), then
    -- fall through so the FULL single-target/AoE damage priority still renders below - the
    -- damage rotation itself is identical in PvP, only the play around it differs.
    if P.pvp then
        local D = pvpForPlayer()
        header(e, "PvP PLAY  (Wrathful arena)")
        if D then
            if D.statPriority then e[#e + 1] = { text = "  Stats: " .. D.statPriority, rcolor = {0.82,0.82,0.88} } end
            e[#e + 1] = { text = " " }
            header(e, "CORE PvP TENETS")
            for _, t in ipairs({
                "Save the on-use PvP trinket to break a key stun/fear (not the first CC).",
                "Line-of-sight casters; use pillars; don't stand in the open vs ranged.",
                "Chain your control (stun/fear/silence) to set up a kill window with your partner.",
                "Pop defensive cooldowns EARLY when focused - don't wait until low.",
                "Peel for your healer; interrupt/CC the enemy healer during your burst.",
            }) do e[#e + 1] = { text = "  - " .. t, rcolor = {0.82,0.82,0.86} } end
            if D.glyphs and #D.glyphs > 0 then
                e[#e + 1] = { text = " " }
                pvpGlyphLines(e, D)
            end
        else
            e[#e + 1] = { text = "  No PvP-specific data for your spec - showing the standard damage priority.", rcolor = {0.7,0.7,0.7} }
        end
        e[#e + 1] = { text = " " }
        header(e, "DAMAGE PRIORITY  (same rotation in PvP)")
    end

    local apl = Rot.CurrentAPL()
    -- Per-group accent colours (also used for the left stripe) so each block reads
    -- as its own scannable lane.
    local ST, AOE, BLUE, GREEN, TEAL, LIVE = {1,0.82,0.2}, {1,0.6,0.2}, {0.4,0.73,1}, {0.4,1,0.5}, {0.5,0.9,0.85}, {0.4,1,0.4}

    -- WHAT TO PRESS NOW: the live callout (active proc jumps the queue, else the pick).
    -- (Must be an if-guard, not `and` - a Lua `and` truncates the call to 1 return.)
    local procBuff, procCast, procTex
    if Rot.ActiveProc then procBuff, procCast, procTex = Rot.ActiveProc() end
    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
    e[#e+1] = { text = "WHAT TO PRESS NOW", header = true, accent = LIVE, rcolor = {0.55,1,0.55},
        right = string.format("%.0f dps", Rot.DPS()), rightColor = {0.5,0.9,0.5} }
    if procBuff and procCast then
        e[#e+1] = { text = "PROC  " .. procBuff .. "  ->  cast " .. procCast .. " NOW!", icon = procTex, accent = GREEN, rcolor = {0.3,1,0.45} }
    end
    if apl and inCombat and hasTarget then
        local nextAb = apl.pick()
        if nextAb then
            local _, _, tex = GetSpellInfo(nextAb)
            e[#e+1] = { text = "-> " .. nextAb, icon = tex, accent = LIVE, rcolor = {1,0.9,0.35} }
        else
            e[#e+1] = { text = "-> pool resources / wait", accent = LIVE, rcolor = {0.7,0.7,0.7} }
        end
    else
        e[#e+1] = { text = (apl and "enter combat on a target to see the live pick" or "no live advisor for this spec"), accent = LIVE, rcolor = {0.6,0.6,0.65} }
    end
    e[#e+1] = { text = "Overlay: " .. ((AIP.db and AIP.db.rotationHelper)
        and "ON - drag the on-screen icon; procs pulse green" or "OFF - tick 'Overlay' below to float it on screen"),
        accent = LIVE, rcolor = (AIP.db and AIP.db.rotationHelper) and {0.45,1,0.45} or {0.8,0.6,0.3} }

    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    -- Resolve the leading spell name of a priority line to its icon.
    local function stepIcon(line)
        local sn = line:match("^([%a][%a%s':]+)")
        if sn then sn = sn:gsub("%s+$", ""); local _, _, t = GetSpellInfo(sn); return t end
    end

    e[#e+1] = { text = " " }
    if apl then
        e[#e+1] = { text = "SINGLE-TARGET  (top = press first)", header = true, accent = ST, rcolor = {1,0.85,0.2},
            right = apl.label, rightColor = {0.6,0.8,1} }
        for i, line in ipairs(apl.priority) do
            e[#e+1] = { text = string.format("%d.  %s", i, line), icon = stepIcon(line), accent = ST }
        end
    else
        e[#e+1] = { text = "No rotation priority for your current spec yet.", rcolor = {1,0.7,0.2} }
    end
    local aoe = key and SG.AoE and SG.AoE[key]
    if aoe then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "AoE / MULTI-TARGET  (2-3+ targets)", header = true, accent = AOE, rcolor = {1,0.62,0.28} }
        for i, line in ipairs(aoe) do e[#e+1] = { text = string.format("%d.  %s", i, line), icon = stepIcon(line), accent = AOE } end
    end
    local dots = key and SG.DoTs and SG.DoTs[key]
    if dots and #dots > 0 then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "KEEP THESE UP  (overlay alerts when they drop)", header = true, accent = BLUE, rcolor = {0.5,0.78,1} }
        for _, d in ipairs(dots) do
            local _, _, t = GetSpellInfo(d[1])
            e[#e+1] = { text = string.format("%s  (~%ds%s)", d[1], d[2], d[3] == "player" and ", on you" or ""), icon = t, accent = BLUE, rcolor = {0.7,0.85,1} }
        end
    end
    local procs = key and SG.Procs and SG.Procs[key]
    if procs and #procs > 0 then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "FREE-INSTANT PROCS to react to", header = true, accent = GREEN, rcolor = {0.5,1,0.6} }
        for _, p in ipairs(procs) do
            local _, _, t = GetSpellInfo(p[1])
            e[#e+1] = { text = string.format("%s  ->  %s", p[1], p[2]), icon = t, accent = GREEN, rcolor = {0.6,1,0.7} }
        end
    end
    local rguide = key and SG.Rotations and SG.Rotations[key]
    if rguide then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "HOW TO RUN IT  (foolproof guide)", header = true, accent = TEAL, rcolor = {0.55,0.95,0.9} }
        for _, g in ipairs(rguide) do e[#e+1] = { text = "  - " .. g, accent = TEAL, rcolor = {0.82,0.82,0.86} } end
    end
    return e
end

-- ============================================================================
-- PvP mode (the PvE/PvP toggle). When P.pvp is set, every section (Gear/Spec/
-- Rotation) renders its PvP variant from PvPData instead of the PvE data.
-- ============================================================================
function pvpForPlayer()
    return AIP.PvPData and AIP.PvPData.ForPlayer and AIP.PvPData.ForPlayer()
end

-- Live resilience vs the arena target + the PvP stat priority (shared by sections).
function pvpStatLines(e, D)
    local resil = (GetCombatRating and CR_CRIT_TAKEN_MELEE) and GetCombatRating(CR_CRIT_TAKEN_MELEE) or 0
    if D.resilTarget then
        local ok = resil >= D.resilTarget
        local col = ok and {0.45,1,0.45} or {1,0.6,0.4}
        e[#e + 1] = { text = string.format("  Resilience  %d / %d", resil, D.resilTarget), rcolor = col,
            right = ok and "ok" or "low", rightColor = col }
    else
        e[#e + 1] = { text = string.format("  Resilience  %d", resil), rcolor = {0.82,0.82,0.88} }
    end
    if D.statPriority then e[#e + 1] = { text = "  Stats: " .. D.statPriority, rcolor = {0.82,0.82,0.88} } end
end

-- PvP glyphs (linked via GlyphData) - shared by Spec + Rotation PvP views.
function pvpGlyphLines(e, D)
    if not (D.glyphs and #D.glyphs > 0) then return end
    e[#e + 1] = { text = "|cffffd100PvP glyphs|r" }
    local GD = AIP.GlyphData
    for _, nm in ipairs(D.glyphs) do
        local link = GD and GD.LinkFor and GD.LinkFor(nm)
        if link then e[#e + 1] = { link = link, icon = itemIcon(link) }
        else e[#e + 1] = { text = "  " .. nm, rcolor = {0.72,0.66,0.9} } end
    end
end

-- Gear (paperdoll) and Spec (talent pane) are special-cased in selectSection/
-- P.Update; only Rotation renders through BUILDERS. buildGear is called directly
-- by the Gear overview. Every builder branches on P.pvp internally.
local BUILDERS = { Rotation = buildRotation }

-- ============================================================================
-- Row pool + rendering into the plain scroll content frame
-- ============================================================================
local function getRow(content, i)
    content.rows = content.rows or {}
    if content.rows[i] then return content.rows[i] end
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(ROWH)
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(i - 1) * ROWH)
    row:SetPoint("RIGHT", content, "RIGHT", -2, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight"); hl:SetBlendMode("ADD")
    -- Group-header bar (entry.header) + per-group left accent stripe (entry.accent):
    -- used to make the Rotation view scannable. Both hidden unless the entry sets them.
    local hb = row:CreateTexture(nil, "BACKGROUND")
    hb:SetPoint("TOPLEFT", 0, 0); hb:SetPoint("BOTTOMRIGHT", 0, 0)
    hb:SetTexture(1, 0.82, 0, 0.10); hb:Hide()
    row.headerBg = hb
    local ac = row:CreateTexture(nil, "ARTWORK")
    ac:SetPoint("TOPLEFT", 0, 0); ac:SetPoint("BOTTOMLEFT", 0, 0); ac:SetWidth(3)
    ac:SetTexture(1, 1, 1); ac:Hide()
    row.accent = ac
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16); icon:SetPoint("LEFT", 4, 0); icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.icon = icon
    local right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    right:SetPoint("RIGHT", -6, 0); right:SetJustifyH("RIGHT"); right:SetWidth(80)
    row.right = right
    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("RIGHT", right, "LEFT", -6, 0); text:SetJustifyH("LEFT")
    row.text = text
    -- what-if selection checkbox (used only on bag-upgrade rows)
    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(18, 18); check:SetPoint("LEFT", 1, 0); check:Hide()
    row.check = check
    content.rows[i] = row
    return row
end

local updateStats   -- forward decl (renderContent toggles it via the what-if checkboxes)

local function renderContent(entries, content, scroll)
    content = content or (frame and frame.content)
    scroll = scroll or (frame and frame.scroll)
    if not content then return end
    for i, e in ipairs(entries) do
        local row = getRow(content, i)
        local xoff = (e.whatif or e.sel) and 20 or 0
        if e.header then row.headerBg:Show() else row.headerBg:Hide() end
        if e.accent then row.accent:SetTexture(e.accent[1], e.accent[2], e.accent[3]); row.accent:Show()
        else row.accent:Hide() end
        if e.icon then row.icon:SetTexture(e.icon); row.icon:Show(); row.icon:SetPoint("LEFT", 4 + xoff, 0); row.text:SetPoint("LEFT", 24 + xoff, 0)
        else row.icon:Hide(); row.text:SetPoint("LEFT", 6 + xoff, 0) end
        if e.whatif and row.check then
            local wl = e.whatif
            row.check:Show()
            row.check:SetChecked(frame.whatif and frame.whatif[wl.link] ~= nil)
            row.check:SetScript("OnClick", function(self)
                frame.whatif = frame.whatif or {}
                frame.whatif[wl.link] = self:GetChecked() and wl or nil
                if updateStats then updateStats() end
            end)
        elseif e.sel and row.check then
            -- Generic slot-detail selection (upgrade item / gem / meta / enchant).
            local s = e.sel
            row.check:Show()
            row.check:SetChecked(frame.detailSel and frame.detailSel[s.key] ~= nil)
            row.check:SetScript("OnClick", function(self)
                frame.detailSel = frame.detailSel or {}
                frame.detailSel[s.key] = self:GetChecked() and s or nil
                if updateStats then updateStats() end
            end)
        elseif row.check then
            row.check:Hide()
        end
        row.text:SetText(e.text or e.link or "")
        local rc = e.rcolor
        row.text:SetTextColor(rc and rc[1] or 1, rc and rc[2] or 1, rc and rc[3] or 1)
        row.right:SetText(e.right or "")
        local gc = e.rightColor
        row.right:SetTextColor(gc and gc[1] or 0.8, gc and gc[2] or 0.8, gc and gc[3] or 0.8)
        local link, hoverWl = e.link, e.whatif or (e.sel and e.sel.link and e.sel.slot and e.sel)
        local action = e.action   -- a click handler for plain interactive rows (e.g. build variations)
        if link or hoverWl or action then
            row:SetScript("OnEnter", function(self)
                if link then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")   -- tooltip near the cursor
                    GameTooltip:SetHyperlink(link); GameTooltip:Show()
                end
                -- Hovering a bag upgrade previews its effect on the stat panel.
                if hoverWl then frame.hoverItem = hoverWl; if updateStats then updateStats() end end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
                if hoverWl and frame.hoverItem == hoverWl then
                    frame.hoverItem = nil; if updateStats then updateStats() end
                end
            end)
            row:SetScript("OnClick", function()
                if link and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link)
                elseif action then action() end
            end)
        else
            row:SetScript("OnEnter", nil); row:SetScript("OnLeave", nil); row:SetScript("OnClick", nil)
        end
        row:Show()
    end
    local pool = content.rows or {}
    for i = #entries + 1, #pool do pool[i]:Hide() end
    content:SetHeight(math.max(1, #entries * ROWH))
    -- Preserve the user's scroll position across re-renders. P.Update() re-renders
    -- periodically (roster/status refresh); forcing scroll to 0 here is what made
    -- the Gear list jump back to the top every few seconds. Only clamp if the
    -- content got shorter; a real section switch resets to top in selectSection.
    if scroll then
        local maxScroll = math.max(0, content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), maxScroll))
    end
end

-- ============================================================================
-- Character stats readout (under the 3D model), role-aware.
-- ============================================================================
function updateStats()
    if not (frame and frame.statsFrame) then return end
    local IS = AIP.ItemScore
    local arch = IS and IS.PlayerArchetype() or ""
    local caster = arch:find("cast") or arch:find("heal") or arch:find("healer")
    local function cr(id) return (GetCombatRating and id) and GetCombatRating(id) or 0 end
    local function crb(id) return (GetCombatRatingBonus and id) and GetCombatRatingBonus(id) or 0 end

    -- What-if: sum stat deltas of the CHECKED bag upgrades plus the currently
    -- HOVERED one (a temporary preview) vs the item each would replace.
    local wdelta, wcount, checkedCount = {}, 0, 0
    local function addItem(link, slot)
        if not (link and GetItemStats) then return end
        wcount = wcount + 1
        local cand = {}; GetItemStats(link, cand)
        for k, v in pairs(cand) do wdelta[k] = (wdelta[k] or 0) + v end
        local equipped = slot and GetInventoryItemLink("player", slot)
        if equipped then local cur = {}; GetItemStats(equipped, cur)
            for k, v in pairs(cur) do wdelta[k] = (wdelta[k] or 0) - v end
        end
    end
    if frame.whatif then
        for link, wl in pairs(frame.whatif) do checkedCount = checkedCount + 1; addItem(link, wl.slot) end
    end
    -- Slot-detail selections: upgrade items diff vs their slot; gems/enchants add
    -- their flat `mods` (already ITEM_MOD_*_SHORT keyed) as an additive projection.
    local function addMods(mods) if not mods then return end
        wcount = wcount + 1
        for k, v in pairs(mods) do wdelta[k] = (wdelta[k] or 0) + v end
    end
    if frame.detailSel then
        for _, s in pairs(frame.detailSel) do
            checkedCount = checkedCount + 1
            if s.link and s.slot then addItem(s.link, s.slot) end
            addMods(s.mods)
        end
    end
    local hv = frame.hoverItem
    local inSel = false
    if hv and hv.link and frame.detailSel then
        for _, s in pairs(frame.detailSel) do if s.link == hv.link then inSel = true; break end end
    end
    local hovering = hv and hv.link and not (frame.whatif and frame.whatif[hv.link]) and not inSel
    if hovering then addItem(hv.link, hv.slot) end
    if frame.statsTitle then
        local suffix = ""
        if hovering then suffix = "  |cff88ccff(hover preview)|r"
        elseif checkedCount > 0 then suffix = "  |cff66ff66(+" .. checkedCount .. " selected)|r" end
        frame.statsTitle:SetText("|cffffd100Character Stats|r" .. suffix)
    end

    -- Live-value helpers (each guarded; return 0 if the API is missing).
    local function stat(i) local s, e = UnitStat("player", i); return math.floor((e and e > 0 and e) or s or 0) end
    local function apTotal() local b, p, n = UnitAttackPower("player"); return math.floor((b or 0) + (p or 0) + (n or 0)) end
    local function rapTotal() if not UnitRangedAttackPower then return 0 end local b, p, n = UnitRangedAttackPower("player"); return math.floor((b or 0) + (p or 0) + (n or 0)) end
    local function spTotal() local m = 0; if GetSpellBonusDamage then for s = 2, 7 do local v = GetSpellBonusDamage(s) or 0; if v > m then m = v end end end return m end
    local function armorTotal() if not UnitArmor then return 0 end local b, e = UnitArmor("player"); return math.floor((e and e > 0 and e) or b or 0) end
    local function mp5() if not GetManaRegen then return 0 end local base = GetManaRegen(); return math.floor((base or 0) * 5) end
    local function spellCrit() local m = 0; if GetSpellCritChance then for s = 2, 7 do local v = GetSpellCritChance(s) or 0; if v > m then m = v end end end return m end

    -- rows: {label, value, deltaKey, isRating, isHeader}. All stats, grouped.
    local rows = {}
    local function hdr(l) rows[#rows + 1] = { l, nil, nil, nil, true } end
    local function add(l, v, key, isR) rows[#rows + 1] = { l, v, key, isR } end

    hdr("Attributes")
    add("Strength", stat(1), "ITEM_MOD_STRENGTH_SHORT")
    add("Agility", stat(2), "ITEM_MOD_AGILITY_SHORT")
    add("Stamina", stat(3), "ITEM_MOD_STAMINA_SHORT")
    add("Intellect", stat(4), "ITEM_MOD_INTELLECT_SHORT")
    add("Spirit", stat(5), "ITEM_MOD_SPIRIT_SHORT")

    hdr("Melee")
    add("Attack Power", apTotal(), "ITEM_MOD_ATTACK_POWER_SHORT")
    add("Crit", string.format("%.2f%%", GetCritChance and GetCritChance() or 0), "ITEM_MOD_CRIT_RATING_SHORT", true)
    add("Hit", string.format("%d (%.2f%%)", cr(CR_HIT_MELEE), crb(CR_HIT_MELEE)), "ITEM_MOD_HIT_RATING_SHORT", true)
    add("Expertise", (GetExpertise and select(1, GetExpertise())) or 0, "ITEM_MOD_EXPERTISE_RATING_SHORT", true)
    add("Haste", string.format("%.2f%%", crb(CR_HASTE_MELEE)), "ITEM_MOD_HASTE_RATING_SHORT", true)
    add("Armor Pen", string.format("%d (%.2f%%)", cr(CR_ARMOR_PENETRATION), crb(CR_ARMOR_PENETRATION)), "ITEM_MOD_ARMOR_PENETRATION_RATING_SHORT", true)

    hdr("Ranged")
    add("Ranged AP", rapTotal())
    add("Ranged Crit", string.format("%.2f%%", GetRangedCritChance and GetRangedCritChance() or 0))
    add("Ranged Hit", string.format("%d (%.2f%%)", cr(CR_HIT_RANGED), crb(CR_HIT_RANGED)))

    hdr("Spell")
    add("Spell Power", spTotal(), "ITEM_MOD_SPELL_POWER")
    add("Spell Crit", string.format("%.2f%%", spellCrit()), "ITEM_MOD_CRIT_RATING_SHORT", true)
    add("Spell Hit", string.format("%d (%.2f%%)", cr(CR_HIT_SPELL), crb(CR_HIT_SPELL)), "ITEM_MOD_HIT_RATING_SHORT", true)
    add("Spell Haste", string.format("%.2f%%", crb(CR_HASTE_SPELL)), "ITEM_MOD_HASTE_RATING_SHORT", true)
    add("MP5", mp5())

    hdr("Defense")
    add("Armor", armorTotal())
    local dba, dmo = 0, 0; if UnitDefense then dba, dmo = UnitDefense("player") end
    add("Defense", (dba or 0) + (dmo or 0), "ITEM_MOD_DEFENSE_SKILL_RATING_SHORT", true)
    add("Dodge", string.format("%.2f%%", GetDodgeChance and GetDodgeChance() or 0), "ITEM_MOD_DODGE_RATING_SHORT", true)
    add("Parry", string.format("%.2f%%", GetParryChance and GetParryChance() or 0), "ITEM_MOD_PARRY_RATING_SHORT", true)
    add("Block", string.format("%.2f%%", GetBlockChance and GetBlockChance() or 0), "ITEM_MOD_BLOCK_RATING_SHORT", true)
    add("Block Value", (GetShieldBlock and GetShieldBlock()) or 0, "ITEM_MOD_BLOCK_VALUE_SHORT")
    add("Resilience", cr(CR_CRIT_TAKEN_MELEE), "ITEM_MOD_RESILIENCE_RATING_SHORT", true)

    hdr("Resources")
    add("Health", UnitHealthMax and UnitHealthMax("player") or 0)
    add("Mana", (UnitManaMax and UnitManaMax("player")) or (UnitPowerMax and UnitPowerMax("player", 0)) or 0)

    frame.statRows = frame.statRows or {}
    for i, r in ipairs(rows) do
        local fs = frame.statRows[i]
        if not fs then
            fs = frame.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", 8, -2 - (i - 1) * 14); fs:SetJustifyH("LEFT")
            fs.val = frame.statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs.val:SetPoint("TOPRIGHT", -8, -2 - (i - 1) * 14); fs.val:SetJustifyH("RIGHT")
            frame.statRows[i] = fs
        end
        if r[5] then   -- section header
            fs:SetText("|cffffd100" .. r[1] .. "|r"); fs.val:SetText("")
        else
            local base, key, isR = r[2], r[3], r[4]
            local d = (wcount > 0 and key) and wdelta[key] or nil
            local valstr
            if d and d ~= 0 then
                -- Colour by sign: a swap can DIMINISH a stat (the replaced item had more of
                -- it) as well as raise one - green = gain, red = loss, so both read honestly.
                local col = d > 0 and "66ff66" or "ff6060"
                if isR then valstr = tostring(base) .. string.format("  |cff%s%+d|r", col, d)
                else valstr = string.format("%d |cff%s-> %d|r", tonumber(base) or 0, col, (tonumber(base) or 0) + d) end
            else
                valstr = tostring(base)
            end
            fs:SetText(r[1]); fs:SetTextColor(0.66, 0.66, 0.72)
            fs.val:SetText(valstr); fs.val:SetTextColor(1, 1, 1)
        end
        fs:Show(); fs.val:Show()
    end
    for i = #rows + 1, #frame.statRows do frame.statRows[i]:Hide(); frame.statRows[i].val:Hide() end
    -- Size the scroll body so every row is reachable, and clamp the current scroll.
    if frame.statsFrame.SetHeight then frame.statsFrame:SetHeight(math.max(1, #rows * 14 + 4)) end
    if frame.statsScroll then
        local maxS = math.max(0, (#rows * 14 + 4) - frame.statsScroll:GetHeight())
        frame.statsScroll:SetVerticalScroll(math.min(frame.statsScroll:GetVerticalScroll(), maxS))
    end
end

-- ============================================================================
-- Header summary
-- ============================================================================
local function updateHeader()
    if not frame then return end
    updateStats()
    local IS, UP = AIP.ItemScore, AIP.UpgradePath
    local name = UnitName("player") or ""
    local arch = IS and IS.PlayerArchetype() or "?"
    local avg = UP and UP.AvgItemLevel() or 0
    -- Use the SAME GS source as the addon's footer/status bar (which matches the
    -- GearScore addon) so the two never disagree.
    local gs = 0
    if AIP.CentralGUI and AIP.CentralGUI.CalculatePlayerGS then
        gs = AIP.CentralGUI.CalculatePlayerGS() or 0
    elseif AIP.Integrations and AIP.Integrations.GetGearScore then
        gs = AIP.Integrations.GetGearScore(name) or 0
    end
    frame.header:SetText(string.format("|cffffd100%s|r   %s   avg iLvl |cffffffff%d|r%s",
        name, arch, avg, gs > 0 and ("   GS |cffffffff" .. gs .. "|r") or ""))

    -- quick status strip
    local bits = {}
    if AIP.GearAdvisor and AIP.GearAdvisor.Audit then
        local m, s = AIP.GearAdvisor.Audit()
        bits[#bits+1] = (#m > 0) and ("|cffff5555" .. #m .. " enchant" .. (#m > 1 and "s" or "") .. "|r") or "|cff55ff55enchants ok|r"
        bits[#bits+1] = (s > 0) and ("|cffff5555" .. s .. " socket" .. (s > 1 and "s" or "") .. "|r") or "|cff55ff55gems ok|r"
    end
    if AIP.Readiness and AIP.Readiness.Scan then
        local n = #AIP.Readiness.Scan()
        bits[#bits+1] = (n > 0) and ("|cffff5555" .. n .. " readiness|r") or "|cff55ff55ready|r"
    end
    frame.status:SetText(table.concat(bits, "   |cff555555|||r   "))
end

-- ============================================================================
-- Talent-tree graphic (Spec screen): 3 trees of real talent icons, positioned
-- by tier/column, showing rank, colored by learned/maxed, with hover tooltips.
-- ============================================================================
local TREE_W, TSPACE = 150, 27

local SPEC_SIDEBAR_X = 3 * TREE_W + 20   -- guide sidebar begins right of the 3 trees

local function ensureTalentPane()
    if frame.talentPane then return frame.talentPane end
    local parent = (frame.scroll and frame.scroll:GetParent()) or frame
    local tp = CreateFrame("Frame", nil, parent)
    if frame.scroll then tp:SetAllPoints(frame.scroll)
    else tp:SetPoint("TOPLEFT", 12, -80); tp:SetPoint("BOTTOMRIGHT", -240, 120) end
    tp:SetFrameLevel(((frame.scroll and frame.scroll:GetFrameLevel()) or 1) + 5)
    tp.icons, tp.titles = {}, {}

    -- Right-hand guide sidebar: a plain (un-templated) scroll of interactive rows
    -- (build/caps/glyph links/consumables/prep checks). Scrolls so it never spills
    -- off the bottom the way the old FontString guide did.
    local gtitle = tp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gtitle:SetPoint("TOPLEFT", SPEC_SIDEBAR_X, -4); gtitle:SetText("|cffffd100Spec Guide|r")
    tp.gtitle = gtitle
    local gs = CreateFrame("ScrollFrame", nil, tp)
    gs:SetPoint("TOPLEFT", SPEC_SIDEBAR_X, -22); gs:SetPoint("BOTTOMRIGHT", tp, "BOTTOMRIGHT", -2, 2)
    local gc = CreateFrame("Frame", nil, gs)
    gc:SetWidth(1); gc:SetHeight(1); gs:SetScrollChild(gc)
    local function gWheel(_, delta)
        local maxS = math.max(0, gc:GetHeight() - gs:GetHeight())
        gs:SetVerticalScroll(math.max(0, math.min(maxS, gs:GetVerticalScroll() - delta * ROWH * 2)))
    end
    gs:EnableMouseWheel(true); gs:SetScript("OnMouseWheel", gWheel)
    gs:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then gc:SetWidth(w) end end)
    tp.gscroll, tp.gcontent = gs, gc

    frame.talentPane = tp
    return tp
end

local function renderTalents()
    local tp = ensureTalentPane()
    tp:Show()
    for _, b in pairs(tp.icons) do b:Hide() end

    -- When a build variation is selected we preview ITS talent tree; in PvP mode the
    -- tree previews the PvP build; otherwise we show the player's live build.
    -- override = decoded {[tab]={[idx]=rank}} or nil.
    local pvp = P.pvp and pvpForPlayer()
    local pvpOverride = pvp and pvp.talentBuild and AIP.SpecAdvisor and AIP.SpecAdvisor.Decode
        and AIP.SpecAdvisor.Decode(pvp.talentBuild) or nil
    -- A clicked variation wins over the default (PvP build in PvP mode, live build in PvE)
    -- so previewing a variation's tree works in both modes.
    local override = P.variantBuild or pvpOverride

    for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
        local tname, _, pts = GetTalentTabInfo(tab)
        if override then pts = 0; for _, r in pairs(override[tab] or {}) do pts = pts + r end end
        local title = tp.titles[tab]
        if not title then title = tp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); tp.titles[tab] = title end
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", (tab - 1) * TREE_W + 10, -4)
        title:SetText((tname or "Tree") .. "  |cffffd100" .. (pts or 0) .. "|r"); title:Show()

        for idx = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
            local name, icon, tier, column, liveRank, maxRank = GetTalentInfo(tab, idx)
            local rank = override and ((override[tab] and override[tab][idx]) or 0) or liveRank
            if name then
                local key = tab .. "_" .. idx
                local b = tp.icons[key]
                if not b then
                    b = CreateFrame("Button", nil, tp)
                    b:SetSize(24, 24)
                    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                    b.tex = b:CreateTexture(nil, "ARTWORK")
                    b.tex:SetPoint("TOPLEFT", 1, -1); b.tex:SetPoint("BOTTOMRIGHT", -1, 1); b.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    b.rt = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
                    b.rt:SetPoint("BOTTOMRIGHT", 2, -1)
                    tp.icons[key] = b
                end
                b.tab, b.idx = tab, idx
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", (tab - 1) * TREE_W + 12 + (column - 1) * TSPACE, -20 - (tier - 1) * TSPACE)
                b.tex:SetTexture(icon); b.rt:SetText((rank or 0) .. "/" .. (maxRank or 0))
                if (rank or 0) == 0 then
                    b:SetBackdropBorderColor(0.3, 0.3, 0.3); if b.tex.SetDesaturated then b.tex:SetDesaturated(true) end; b.rt:SetTextColor(0.6, 0.6, 0.6)
                elseif rank == maxRank then
                    b:SetBackdropBorderColor(0.2, 1, 0.2); if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end; b.rt:SetTextColor(0.4, 1, 0.4)
                else
                    b:SetBackdropBorderColor(1, 0.82, 0); if b.tex.SetDesaturated then b.tex:SetDesaturated(false) end; b.rt:SetTextColor(1, 0.82, 0)
                end
                b:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    if GameTooltip.SetTalent then GameTooltip:SetTalent(self.tab, self.idx) end
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave", function() GameTooltip:Hide() end)
                b:Show()
            end
        end
    end

    -- Guide sidebar (right of the trees): build, glyphs as links, stat caps, prep
    -- checks and consumables as links. Rendered as interactive rows into tp.gscroll.
    local SA = AIP.SpecAdvisor
    local _, classFile = UnitClass("player")
    local tree = AIP.ItemScore and AIP.ItemScore.PrimaryTree() or 1
    local guide = SA and SA.Guide[classFile] and SA.Guide[classFile][tree]
    local SG = AIP.SpecGuides
    local skey = SG and SG.KeyFor and SG.KeyFor()
    local e = {}

    -- PvP mode: the tree shows the PvP build (above) and the sidebar is PvP guidance.
    if pvp then
        if P.variantBuild then
            e[#e + 1] = { text = "|cffb9a7ffPreviewing variant:|r " .. (P.variantName or "?"), rcolor = {0.72,0.66,0.9} }
            e[#e + 1] = { text = "  <- back to the PvP build", rcolor = {0.5,0.8,1},
                action = function() P.variantBuild = nil; P.variantName = nil; renderTalents() end }
            e[#e + 1] = { text = " " }
        else
            e[#e + 1] = { text = "|cffb9a7ffPvP build|r  (Wrathful arena)", rcolor = {0.72,0.66,0.9} }
            if not pvpOverride then
                e[#e + 1] = { text = "  (no verified PvP talent string for this spec - tree shows your live build)", rcolor = {0.6,0.6,0.65} }
            end
        end
        pvpStatLines(e, pvp)
        if pvp.setName then e[#e + 1] = { text = "  Set: " .. pvp.setName, rcolor = {0.85,0.7,1} } end
        local gplan = AIP.PvPData.GemPlanForPlayer and AIP.PvPData.GemPlanForPlayer()
        if gplan then e[#e + 1] = { text = "  Gems: " .. gplan.meta .. " - " .. gplan.gems, rcolor = {0.7,0.85,1} }
        elseif pvp.gemNote then e[#e + 1] = { text = "  Gems: " .. pvp.gemNote, rcolor = {0.7,0.85,1} } end
        if pvp.keyItems then e[#e + 1] = { text = "  " .. pvp.keyItems, rcolor = {0.62,0.64,0.7} } end
        e[#e + 1] = { text = " " }
        pvpGlyphLines(e, pvp)
        if pvp.talentBuild then
            e[#e + 1] = { text = " " }
            e[#e + 1] = { text = "PvP talent string (paste into Import):", rcolor = {0.58,0.58,0.62} }
            e[#e + 1] = { text = "  " .. pvp.talentBuild, rcolor = {0.7,0.75,0.85} }
        end
    end

    -- The rest of this sidebar (build header, recommended glyphs, stat caps, prep,
    -- consumables) is PvE-specific - PvP showed its own guidance above. Build
    -- variations (further below) render in BOTH modes so PvP has variations too.
    if not pvp then
    if P.variantBuild then
        e[#e + 1] = { text = "|cffb9a7ffPreviewing variant:|r " .. (P.variantName or "?"), rcolor = {0.72,0.66,0.9} }
        e[#e + 1] = { text = "  <- back to my live build", rcolor = {0.5,0.8,1},
            action = function() P.variantBuild = nil; P.variantName = nil; renderTalents() end }
    elseif SA then
        local _, split, total = SA.ReadBuild()
        e[#e + 1] = { text = "|cffffffffYour build|r " .. table.concat(split, "/") .. "  (" .. (total or 0) .. " pts)" }
    end
    if guide then
        e[#e + 1] = { text = "|cffffd100Recommended " .. guide[1] .. ":|r " .. guide[2], rcolor = {0.9,0.85,0.5} }
        if guide[4] and guide[4] ~= "" then e[#e + 1] = { text = "|cff88ff88How to play:|r " .. guide[4], rcolor = {0.75,0.85,0.75} } end
    end
    if SA and SA.RecBuild and SA.RecBuild() then
        local m, w = SA.Diff(true)   -- silent: render path, must not spam chat
        e[#e + 1] = { text = "Imported diff: " .. (m or 0) .. " missing, " .. (w or 0) .. " misplaced", rcolor = {1,0.7,0.2} }
    else
        e[#e + 1] = { text = "Paste a Wowhead talent string below + Import.", rcolor = {0.6,0.6,0.65} }
    end

    -- Recommended glyphs as REAL item links (have = green, missing = orange).
    if guide and guide[3] and guide[3] ~= "" then
        e[#e + 1] = { text = " " }
        e[#e + 1] = { text = "|cffffd100Recommended glyphs|r" }
        local majors = (SA and SA.ReadGlyphs and (SA.ReadGlyphs())) or {}
        local function haveGlyph(nm)
            for _, mg in ipairs(majors) do if nm ~= "" and mg:find(nm, 1, true) then return true end end
            return false
        end
        local GD = AIP.GlyphData
        for want in guide[3]:gmatch("[^,]+") do
            local nm = want:gsub("^%s+", ""):gsub("%s+$", "")
            if nm ~= "" then
                local have = haveGlyph(nm)
                local col = have and {0.45,1,0.45} or {1,0.65,0.3}
                local link = GD and GD.LinkFor and GD.LinkFor(nm)
                if link then
                    e[#e + 1] = { link = link, icon = itemIcon(link), right = have and "have" or "need", rightColor = col }
                else
                    e[#e + 1] = { text = "  " .. nm, rcolor = col, right = have and "have" or "need", rightColor = col }
                end
            end
        end
    end

    -- Live stat-cap status (migrated from the removed Readiness section).
    local caps = skey and SG and SG.Caps and SG.Caps[skey]
    if caps then
        e[#e + 1] = { text = " " }
        e[#e + 1] = { text = "|cffffd100Stat caps|r" }
        local function cr(id) return (GetCombatRating and id) and GetCombatRating(id) or 0 end
        local function capline(label, cur, target)
            local ok = cur >= target
            local col = ok and {0.45,1,0.45} or {1,0.5,0.5}
            e[#e + 1] = { text = string.format("  %s %d/%d", label, cur, target), rcolor = col,
                right = ok and "ok" or "UNDER", rightColor = col }
        end
        if caps.hit and caps.hit > 0 then
            local hid = (caps.hitType == "spell" and CR_HIT_SPELL) or (caps.hitType == "ranged" and CR_HIT_RANGED) or CR_HIT_MELEE
            capline("Hit", cr(hid), caps.hit)
        end
        if caps.expertise and caps.expertise > 0 then capline("Expertise", cr(CR_EXPERTISE), caps.expertise) end
        if caps.arp == "yes" then capline("ArP", cr(CR_ARMOR_PENETRATION), 1400) end
        if caps.defense then
            local ba, mo = 0, 0; if UnitDefense then ba, mo = UnitDefense("player") end
            capline("Defense", (ba or 0) + (mo or 0), caps.defense)
        end
        if caps.notes and caps.notes ~= "" then e[#e + 1] = { text = "  " .. caps.notes, rcolor = {0.6,0.6,0.65} } end
    end

    -- Prep checks (migrated from Readiness).
    local R = AIP.Readiness
    if R and R.Scan then
        local issues = R.Scan()
        e[#e + 1] = { text = " " }
        if #issues == 0 then
            e[#e + 1] = { text = "|cff73ff73Ready:|r flask/food, durability, talents, glyphs ok.", rcolor = {0.55,0.9,0.55} }
        else
            e[#e + 1] = { text = "|cffffd100Fix before pulling|r" }
            for _, iss in ipairs(issues) do e[#e + 1] = { text = "  - " .. iss, rcolor = {1,0.5,0.5} } end
        end
    end

    -- Recommended consumables as item links (moved here from Readiness).
    local cons = AIP.Consumables and AIP.Consumables.ForPlayer and AIP.Consumables.ForPlayer()
    if cons then
        e[#e + 1] = { text = " " }
        e[#e + 1] = { text = "|cffffd100Consumables|r" }
        local function consRow(c, label)
            if not c then return end
            local link = linkFromID(c.itemID, c.name)
            if link then e[#e + 1] = { link = link, icon = itemIcon(link), right = label, rightColor = {0.6,0.7,0.85} }
            else e[#e + 1] = { text = "  " .. c.name, rcolor = {0.7,0.85,1}, right = label, rightColor = {0.6,0.7,0.85} } end
            if c.note then e[#e + 1] = { text = "      " .. c.note, rcolor = {0.58,0.58,0.62} } end
        end
        consRow(cons.flask, "flask"); consRow(cons.food, "food"); consRow(cons.drink, "drink")
    end
    end   -- if not pvp

    -- Build variations (rendered in BOTH PvE and PvP modes).
    local variants = skey and SG and SG.Variants and SG.Variants[skey]
    if variants and #variants > 0 then
        e[#e + 1] = { text = " " }
        e[#e + 1] = { text = "|cffffd100Build variations|r  |cff888888(click to preview its tree)|r" }
        -- Which variation is the player currently running? The build with the fewest
        -- points differing from the live build (requires a variant talent string).
        local curIdx, curDiff
        if SA and SA.DiffBuild then
            for i, v in ipairs(variants) do
                if v[3] then
                    local d = SA.DiffBuild(v[3])
                    if d and (not curDiff or d < curDiff) then curDiff, curIdx = d, i end
                end
            end
            -- Only claim "in use" when the live build actually matches closely; a big
            -- diff means the player runs a different (maybe unlisted) variant.
            if curDiff and curDiff > 8 then curIdx = nil end
        end
        for i, v in ipairs(variants) do
            local isCur = (i == curIdx)
            local selName = (P.variantName == v[1])
            local rt = isCur and "in use" or (v[3] and "preview" or "")
            local rtCol = isCur and {0.5,1,0.5} or {0.55,0.6,0.7}
            e[#e + 1] = { text = "  " .. (selName and "> " or "") .. v[1],
                rcolor = selName and {0.9,0.85,0.4} or {0.72,0.66,0.9}, right = rt, rightColor = rtCol,
                action = function()
                    if v[3] and SA and SA.Decode then
                        P.variantBuild = SA.Decode(v[3]); P.variantName = v[1]
                    else
                        P.variantBuild, P.variantName = nil, nil
                        if AIP.Print then AIP.Print("No talent string for '" .. v[1] .. "' yet - paste its Wowhead link in Import to preview.") end
                    end
                    renderTalents()
                end }
            e[#e + 1] = { text = "      " .. (v[2] or ""), rcolor = {0.58,0.58,0.62} }
        end
    end

    renderContent(e, tp.gcontent, tp.gscroll)
end

-- ============================================================================
-- Gear paperdoll (Gear section): equipped-item slot buttons flank the 3D model.
-- Click a slot -> its upgrade / gem / enchant recommendations in a central pane,
-- all driving the live what-if stat projection. No slot selected -> Gear summary.
-- ============================================================================
local SLOT_LEFT   = { "HeadSlot", "NeckSlot", "ShoulderSlot", "BackSlot", "ChestSlot", "WristSlot" }
local SLOT_RIGHT  = { "HandsSlot", "WaistSlot", "LegsSlot", "FeetSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot", "Trinket1Slot" }
local SLOT_WEAPON = { "MainHandSlot", "SecondaryHandSlot", "RangedSlot" }

local renderSlotDetail   -- fwd (assigned below)
local selectSlot         -- fwd
local buildSlotDetail    -- fwd

local function slotTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if GetInventoryItemLink("player", self.slotId) then
        GameTooltip:SetInventoryItem("player", self.slotId)
    else
        local IS = AIP.ItemScore
        GameTooltip:SetText((IS and IS.SLOT_NAME[self.slotId]) or self.slotName or "Slot")
    end
    GameTooltip:Show()
end

local function makeSlotButton(pane, slotName)
    local id, tex = GetInventorySlotInfo(slotName)
    local b = CreateFrame("Button", nil, pane)
    b.slotId, b.emptyTex, b.slotName = id, tex, slotName
    b:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    b:SetBackdropBorderColor(0.35, 0.35, 0.42)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 1, -1); icon:SetPoint("BOTTOMRIGHT", -1, 1)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.iconTex = icon
    local hl = b:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
    local mk = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    mk:SetPoint("BOTTOMRIGHT", 0, 0); mk:SetShadowOffset(1, -1); mk:SetShadowColor(0, 0, 0, 1)
    b.marker = mk
    b:SetScript("OnEnter", slotTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self) selectSlot(self.slotId) end)
    return b
end

-- Position/size the slot columns + weapon row + central detail scroll to the pane's
-- current height (survives the 800x500 min window - buttons shrink gracefully).
local function layoutGearPane()
    local gp = frame.gearPane
    if not gp then return end
    local paneH = gp:GetHeight()
    if not paneH or paneH < 10 then paneH = 300 end
    local P8 = math.max(16, math.min(38, math.floor((paneH - 46) / 8)))
    local S = P8 - 3
    for i, b in ipairs(gp.left) do
        b:SetSize(S, S); b:ClearAllPoints(); b:SetPoint("TOPLEFT", gp, "TOPLEFT", 4, -4 - (i - 1) * P8)
    end
    for i, b in ipairs(gp.right) do
        b:SetSize(S, S); b:ClearAllPoints(); b:SetPoint("TOPRIGHT", gp, "TOPRIGHT", -4, -4 - (i - 1) * P8)
    end
    for j, b in ipairs(gp.weapon) do
        b:SetSize(S, S); b:ClearAllPoints(); b:SetPoint("BOTTOM", gp, "BOTTOM", (j - 2) * (S + 6), 4)
    end
    gp.dscroll:ClearAllPoints()
    gp.dscroll:SetPoint("TOPLEFT", gp, "TOPLEFT", S + 14, -22)
    gp.dscroll:SetPoint("BOTTOMRIGHT", gp, "BOTTOMRIGHT", -(S + 14), S + 10)
    -- Back button + title sit in the strip above the detail scroll (left-aligned so
    -- they never overlap each other the way a shared top-center anchor would).
    if gp.back then gp.back:ClearAllPoints(); gp.back:SetPoint("TOPLEFT", gp, "TOPLEFT", S + 14, -2) end
    if gp.dtitle then gp.dtitle:ClearAllPoints(); gp.dtitle:SetPoint("TOPLEFT", gp, "TOPLEFT", S + 80, -4) end
end

local function ensureGearPane()
    if frame.gearPane then return frame.gearPane end
    local parent = (frame.scroll and frame.scroll:GetParent()) or frame
    local gp = CreateFrame("Frame", nil, parent)
    if frame.scroll then gp:SetAllPoints(frame.scroll)
    else gp:SetPoint("TOPLEFT", 12, -80); gp:SetPoint("BOTTOMRIGHT", -240, 120) end
    gp:SetFrameLevel(((frame.scroll and frame.scroll:GetFrameLevel()) or 1) + 5)
    frame.gearPane = gp
    gp.left, gp.right, gp.weapon = {}, {}, {}
    for _, n in ipairs(SLOT_LEFT)   do gp.left[#gp.left + 1]     = makeSlotButton(gp, n) end
    for _, n in ipairs(SLOT_RIGHT)  do gp.right[#gp.right + 1]   = makeSlotButton(gp, n) end
    for _, n in ipairs(SLOT_WEAPON) do gp.weapon[#gp.weapon + 1] = makeSlotButton(gp, n) end

    -- Back button + slot title (positioned in layoutGearPane, which knows S).
    local back = UI.CreateButton(gp, "< Back", 60, 18, function() selectSlot(nil) end,
        "Back to the paperdoll overview")
    back:Hide()
    gp.back = back
    local dtitle = gp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gp.dtitle = dtitle

    -- Central detail scroll (plain, un-templated -> avoids the unnamed-scrollbar crash).
    local dscroll = CreateFrame("ScrollFrame", nil, gp)
    local dcontent = CreateFrame("Frame", nil, dscroll)
    dcontent:SetWidth(1); dcontent:SetHeight(1)
    dscroll:SetScrollChild(dcontent)
    local function dWheel(_, delta)
        local maxS = math.max(0, dcontent:GetHeight() - dscroll:GetHeight())
        dscroll:SetVerticalScroll(math.max(0, math.min(maxS, dscroll:GetVerticalScroll() - delta * ROWH * 2)))
    end
    dscroll:EnableMouseWheel(true); dscroll:SetScript("OnMouseWheel", dWheel)
    dscroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then dcontent:SetWidth(w) end end)
    gp.dscroll, gp.dcontent = dscroll, dcontent

    gp:SetScript("OnSizeChanged", function() layoutGearPane() end)
    layoutGearPane()
    return gp
end

-- Refresh the paperdoll slot icons + quality borders + E/G markers. NOTE: this runs
-- GA.SlotAudit x17 (hidden-tooltip scans), so it is called ONLY on section-enter,
-- P.Update, and PLAYER_EQUIPMENT_CHANGED - never on the 0.5s ticker.
local function renderPaperdoll()
    local gp = frame.gearPane
    if not gp then return end
    layoutGearPane()
    local GA = AIP.GearAdvisor
    local function upd(list)
        for _, b in ipairs(list) do
            b.iconTex:SetTexture(GetInventoryItemTexture("player", b.slotId) or b.emptyTex)
            local q = GetInventoryItemQuality and GetInventoryItemQuality("player", b.slotId)
            local qc = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            if qc then b:SetBackdropBorderColor(qc.r, qc.g, qc.b) else b:SetBackdropBorderColor(0.35, 0.35, 0.42) end
            local txt = ""
            if GA and GA.SlotAudit then
                local missing, sockets = GA.SlotAudit(b.slotId)
                if missing then txt = txt .. "|cffff3030E|r" end
                if sockets and sockets > 0 then txt = txt .. "|cff40a0ffG|r" end
            end
            b.marker:SetText(txt)
        end
    end
    upd(gp.left); upd(gp.right); upd(gp.weapon)
end

-- Chrome (highlight + back + title) for the current detail slot.
local function applySlotChrome(slotId)
    local gp = frame.gearPane
    if not gp then return end
    local function mark(list) for _, b in ipairs(list) do
        if b.slotId == slotId then b:LockHighlight() else b:UnlockHighlight() end end end
    mark(gp.left); mark(gp.right); mark(gp.weapon)
    if slotId then
        gp.back:Show()
        gp.dtitle:SetText("|cffffd100" .. ((AIP.ItemScore and AIP.ItemScore.SLOT_NAME[slotId]) or "Slot") .. "|r")
    else
        gp.back:Hide()
        gp.dtitle:SetText("|cffffd100Gear overview|r  |cff888888(click a slot for upgrades)|r")
    end
end

-- Build the detail entry list for a slot: equipped -> upgrades -> gems -> enchant.
buildSlotDetail = function(slotId)
    local e = {}
    local IS = AIP.ItemScore
    -- Validation ticks: the ready-check tick/cross textures render inline in the WoW
    -- font (a Unicode check would not). CHECK = condition already satisfied.
    local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
    local CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"
    local GA = AIP.GearAdvisor
    local emptySockets = 0
    if GA and GA.SlotAudit then local _, s = GA.SlotAudit(slotId); emptySockets = s or 0 end
    local function slotEnchanted()
        local l = GetInventoryItemLink("player", slotId)
        return (l and (tonumber(l:match("item:%d+:(%d*)")) or 0) ~= 0) or false
    end

    header(e, "EQUIPPED")
    local eqLink = GetInventoryItemLink("player", slotId)
    if eqLink then
        e[#e + 1] = { link = eqLink, icon = itemIcon(eqLink), right = "current", rightColor = {0.7,0.7,0.7} }
    else
        e[#e + 1] = { text = "  Empty slot!", rcolor = {1,0.45,0.45} }
    end

    -- PvP context for this slot (arena set + resilience emphasis). PvP mode keeps the
    -- SAME rich structure as PvE below: PvP items -> gems -> enchant (gems/enchants are
    -- reused because gemming/enchanting is largely identical in PvP; only the items differ).
    if P.pvp then
        local D = pvpForPlayer()
        e[#e + 1] = { text = " " }
        header(e, "PvP  (this slot)")
        if D and D.setName then e[#e + 1] = { text = "  Arena set: " .. D.setName, rcolor = {0.85,0.7,1} } end
        e[#e + 1] = { text = "  Resilience is the priority on every slot" ..
            (D and D.resilTarget and (" (target ~" .. D.resilTarget .. ")") or "") .. ".", rcolor = {0.82,0.82,0.88} }
    end

    e[#e + 1] = { text = " " }
    if P.pvp then
        -- Recommended PvP items for this slot: real Wrathful/honor links when the
        -- per-slot table has verified ids, else honest set/key-item guidance text.
        header(e, "PvP ITEMS  (tick a box -> preview stats under the model)")
        local plist = AIP.PvPData and AIP.PvPData.ForSlot and AIP.PvPData.ForSlot(slotId)
        if plist and #plist > 0 then
            for _, it in ipairs(plist) do
                local nm, id, ilvl, src = it[1], it[2], it[3], it[4]
                local ilink = linkFromID(id, nm)
                if ilink then
                    e[#e + 1] = { link = ilink, icon = itemIcon(ilink), right = ilvl and ("iLvl " .. ilvl) or "", rightColor = {0.85,0.7,1},
                        sel = { key = "pvp:" .. tostring(id or nm), kind = "item", link = ilink, slot = slotId } }
                else
                    e[#e + 1] = { text = "  |cffa335ee" .. nm .. "|r" .. (ilvl and ("  (iLvl " .. ilvl .. ")") or ""), rcolor = {0.75,0.65,0.9} }
                end
                if src and src ~= "" then e[#e + 1] = { text = "        " .. src, rcolor = {0.58,0.58,0.62} } end
            end
        else
            local D = pvpForPlayer()
            if D and D.setName then e[#e + 1] = { text = "  Wear the " .. D.setName .. " piece for this slot (arena points / honor).", rcolor = {0.8,0.72,0.95} } end
            if D and D.keyItems then e[#e + 1] = { text = "  Key items: " .. D.keyItems, rcolor = {0.72,0.72,0.8} } end
            if not D then e[#e + 1] = { text = "  No PvP data for your spec.", rcolor = {0.7,0.7,0.7} } end
        end
    else
        -- Upgrades: a per-slot progression from an accessible piece up to the server BiS.
        -- "Upgrade" is scoped two ways: green = out-scores your CURRENT item in this slot;
        -- gold "BiS" = the best-in-slot available on the server (end of the chain).
        header(e, "UPGRADES  (tick a box -> preview stats under the model)")
        e[#e + 1] = { text = "  |cff45ff45green|r = upgrade vs your current    |cffffd100gold BiS|r = server best-in-slot", rcolor = {0.6,0.62,0.68} }
        local chain = AIP.GearUpgrades and AIP.GearUpgrades.ForPlayerSlot and AIP.GearUpgrades.ForPlayerSlot(slotId)
        -- Primary-stat guard: never recommend an item whose primary stat conflicts with the
        -- spec (e.g. an Agility ring to a Strength spec). Neutral items (no str/agi/int - most
        -- rings/cloaks/trinkets) suit anyone; cold-cache items pass (stats not known yet).
        local arch = IS and IS.PlayerArchetype and IS.PlayerArchetype()
        local function statMatchOK(link)
            if not (link and GetItemStats and arch) then return true end
            local t = {}; GetItemStats(link, t)
            local str = t.ITEM_MOD_STRENGTH_SHORT or t.ITEM_MOD_STRENGTH or 0
            local agi = t.ITEM_MOD_AGILITY_SHORT or t.ITEM_MOD_AGILITY or 0
            local int = t.ITEM_MOD_INTELLECT_SHORT or t.ITEM_MOD_INTELLECT or 0
            if str == 0 and agi == 0 and int == 0 then return true end     -- neutral - fine for anyone
            if arch == "strDPS" then return str > 0
            elseif arch == "agiDPS" then return agi > 0
            elseif arch == "tank" then return str > 0 or agi > 0            -- druid tank = agi, others str
            else return int > 0 end                                        -- casterDPS / healerCrit / casterHot
        end
        if chain and #chain > 0 then
            local shown = 0
            for i, it in ipairs(chain) do
                local nm, id, ilvl, boss, zone, dc = it[1], it[2], it[3], it[4], it[5], it[6]
                local ilink = linkFromID(id, nm)
                local isBiS = (i == #chain)
                if ilink and not statMatchOK(ilink) then
                    -- off-primary-stat for this spec: skip it (recommending it would be misinformation)
                else
                    shown = shown + 1
                    -- Right tag: upgrade % vs your CURRENT item (else iLvl); final entry = BiS.
                    local rtxt = ilvl and ("iLvl " .. ilvl) or ""
                    local rcol = {0.8,0.8,0.85}
                    local validated = false   -- you already have this item or better in the slot
                    if ilink and IS and IS.UpgradeInfo then
                        local _, _, deltaPct = IS.UpgradeInfo(ilink)
                        if deltaPct and deltaPct > 1 then rtxt = string.format("+%.0f%%", deltaPct); rcol = {0.45,1,0.45}
                        elseif deltaPct and deltaPct >= -1 and deltaPct <= 1 then validated = true; rtxt = "have equal"; rcol = {0.55,0.85,0.55}
                        elseif deltaPct and deltaPct < -1 then validated = true; rtxt = "have better"; rcol = {0.55,0.85,0.55} end
                    end
                    if isBiS then
                        if validated then rtxt = CHECK .. " BiS"; rcol = {0.5,1,0.5}
                        else rtxt = "BiS" .. (rtxt ~= "" and ("  " .. rtxt) or ""); rcol = {1,0.82,0.2} end
                    elseif validated then
                        rtxt = CHECK .. " " .. rtxt
                    end
                    if ilink then
                        e[#e + 1] = { link = ilink, icon = itemIcon(ilink), right = rtxt, rightColor = rcol,
                            sel = { key = "up:" .. tostring(id or nm), kind = "item", link = ilink, slot = slotId } }
                    else
                        e[#e + 1] = { text = "  |cffa335ee" .. nm .. "|r" .. (ilvl and ("  (iLvl " .. ilvl .. ")") or "") .. (isBiS and "  |cffffd100BiS|r" or ""), rcolor = {0.75,0.65,0.9} }
                    end
                    -- Raid-size / difficulty badge (parsed from the zone) so the 10 vs 25 and
                    -- Normal vs Heroic of each drop is scannable at a glance.
                    local badge = ""
                    if zone then
                        local szH = zone:match("(%d+)%s*[Hh]") or zone:match("(%d+)%s*[Hh]eroic")
                        local szN = zone:match("(%d+)")
                        if szH then badge = "|cffff8844[" .. szH .. "H]|r  "
                        elseif szN then badge = "|cff66b0ff[" .. szN .. "N]|r  " end
                    end
                    local src = boss or ""
                    if zone and zone ~= "" then src = (src ~= "" and (src .. " - ") or "") .. zone end
                    if dc then src = src .. "  (" .. dc .. ")" end
                    if src ~= "" or badge ~= "" then e[#e + 1] = { text = "        " .. badge .. src, rcolor = {0.58,0.58,0.62} } end
                end
            end
            if shown == 0 then
                e[#e + 1] = { text = "  Nothing stat-appropriate to list here - your current item is likely already best for your spec.", rcolor = {0.6,0.75,0.6} }
            end
        else
            local UP = AIP.UpgradePath
            local sname = (IS and IS.SLOT_NAME[slotId]) or ""
            local hint = UP and UP.SOURCE_HINTS and UP.SOURCE_HINTS[sname]
            e[#e + 1] = { text = hint and ("  " .. hint) or "  No curated list for this slot yet - see the BiS progression (Back).",
                rcolor = {0.7,0.7,0.75} }
        end
    end

    -- Gems (Warmane best-stat, ignore socket colour; meta shown on the helm).
    e[#e + 1] = { text = " " }
    header(e, "RECOMMENDED GEMS  (best stat - ignore socket colour)")
    if P.pvp then
        local D = pvpForPlayer()
        e[#e + 1] = { text = "  PvP: keep the primary-stat gems below, but move some sockets to Resilience/Stamina for survivability.", rcolor = {0.7,0.85,1} }
        if D and D.gemNote then e[#e + 1] = { text = "  " .. D.gemNote, rcolor = {0.62,0.72,0.9} } end
    end
    if emptySockets > 0 then
        e[#e + 1] = { text = "  " .. CROSS .. " " .. emptySockets .. " empty socket(s) to gem", rcolor = {1,0.6,0.4} }
    else
        e[#e + 1] = { text = "  " .. CHECK .. " no empty sockets on this piece", rcolor = {0.5,0.9,0.5} }
    end
    local GEM = AIP.GemData
    -- Socketing strategy: 1 meta + 1 all-stats activator + rest best-stat gems.
    if GEM and GEM.Strategy then e[#e + 1] = { text = "  " .. GEM.Strategy, rcolor = {0.55,0.7,0.85} } end
    if GEM and GEM.Activator then
        local a = GEM.Activator
        local alink = linkFromID(a.itemID, a.name)
        if alink then
            e[#e + 1] = { link = alink, icon = itemIcon(alink), right = "activator", rightColor = {0.7,0.9,0.7},
                sel = { key = "gemact", kind = "gem", mods = a.mods } }
        else
            e[#e + 1] = { text = "  " .. a.name, rcolor = {0.7,0.9,0.7}, right = "activator", rightColor = {0.7,0.9,0.7},
                sel = { key = "gemact", kind = "gem", mods = a.mods } }
        end
        if a.note then e[#e + 1] = { text = "        " .. a.note, rcolor = {0.58,0.58,0.62} } end
    end
    local gplan = GEM and GEM.ForPlayer and GEM.ForPlayer()
    if gplan then
        local QN = { [2] = "green", [3] = "blue", [4] = "epic" }
        for _, grp in ipairs(gplan.groups or {}) do
            e[#e + 1] = { text = "  " .. (grp.label or "Gem"), rcolor = {0.8,0.8,0.9} }
            for _, t in ipairs(grp.tiers or {}) do
                local nm, id, q, mods = t[1], t[2], t[3], t[4]
                local qc = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q or 2]
                local qcol = qc and { qc.r, qc.g, qc.b } or {0.8,0.8,0.8}
                local ilink = linkFromID(id, nm)
                if ilink then
                    e[#e + 1] = { link = ilink, icon = itemIcon(ilink), right = QN[q or 2] or "", rightColor = qcol,
                        sel = { key = "gem:" .. tostring(id or nm), kind = "gem", mods = mods } }
                else
                    e[#e + 1] = { text = "    " .. nm, rcolor = qcol, right = QN[q or 2] or "", rightColor = qcol,
                        sel = { key = "gem:" .. nm, kind = "gem", mods = mods } }
                end
            end
        end
        if slotId == 1 and gplan.meta then
            local m = gplan.meta
            e[#e + 1] = { text = "  Meta (Helm socket):", rcolor = {0.85,0.7,1} }
            local ilink = linkFromID(m.itemID, m.name)
            if ilink then
                e[#e + 1] = { link = ilink, icon = itemIcon(ilink), right = "meta", rightColor = {0.85,0.7,1},
                    sel = { key = "meta:" .. tostring(m.itemID or m.name), kind = "meta", mods = m.mods } }
            else
                e[#e + 1] = { text = "    |cffa335ee" .. m.name .. "|r", rcolor = {0.85,0.7,1},
                    sel = { key = "meta:" .. m.name, kind = "meta", mods = m.mods } }
            end
            if m.note then e[#e + 1] = { text = "        " .. m.note, rcolor = {0.58,0.58,0.62} } end
        end
    else
        e[#e + 1] = { text = "  No gem data for your spec yet.", rcolor = {0.7,0.7,0.7} }
    end

    -- Enchant (item scroll or applied spell), + where to get it.
    e[#e + 1] = { text = " " }
    header(e, "RECOMMENDED ENCHANT")
    local en = AIP.EnchantData and AIP.EnchantData.ForSlot and AIP.EnchantData.ForSlot(slotId)
    if en then
        local link
        if en.kind == "item" and en.itemID then link = linkFromID(en.itemID, en.name)
        elseif en.kind == "spell" and en.spellID and GetSpellLink then link = GetSpellLink(en.spellID) end
        local sel = en.mods and { key = "ench:" .. slotId, kind = "enchant", mods = en.mods } or nil
        if link then
            local ic = (en.kind == "item") and itemIcon(link) or (en.spellID and select(3, GetSpellInfo(en.spellID)))
            e[#e + 1] = { link = link, icon = ic, sel = sel }
        else
            e[#e + 1] = { text = "  " .. en.name, rcolor = {0.6,0.85,1}, sel = sel }
        end
        if slotEnchanted() then
            e[#e + 1] = { text = "  " .. CHECK .. " this slot is enchanted", rcolor = {0.5,0.9,0.5} }
        else
            e[#e + 1] = { text = "  " .. CROSS .. " not enchanted yet", rcolor = {1,0.6,0.4} }
        end
        if en.source then e[#e + 1] = { text = "        source: " .. en.source, rcolor = {0.58,0.58,0.62} } end
    else
        e[#e + 1] = { text = "  No permanent enchant for this slot.", rcolor = {0.7,0.7,0.7} }
    end
    return e
end

renderSlotDetail = function(slotId)
    local gp = frame.gearPane
    if not gp then return end
    local entries = slotId and buildSlotDetail(slotId) or buildGear()
    renderContent(entries, gp.dcontent, gp.dscroll)
end

selectSlot = function(slotId)
    frame.detailSel = {}          -- selections are per-slot; clear on a slot switch
    P.detailSlot = slotId
    applySlotChrome(slotId)
    renderSlotDetail(slotId)
    if updateStats then updateStats() end   -- drop the previous slot's projection
    if frame.gearPane then frame.gearPane.dscroll:SetVerticalScroll(0) end
end

local function selectSection(name)
    P.section = name
    for n, btn in pairs(frame.sectionBtns) do
        if n == name then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    updateHeader()
    if name == "Gear" then
        if frame.scroll then frame.scroll:Hide() end
        if frame.talentPane then frame.talentPane:Hide() end
        ensureGearPane(); frame.gearPane:Show()
        renderPaperdoll()
        selectSlot(P.detailSlot)
    elseif name == "Spec" then
        if frame.scroll then frame.scroll:Hide() end
        if frame.gearPane then frame.gearPane:Hide() end
        P.variantBuild, P.variantName = nil, nil   -- fresh entry starts on the live build
        renderTalents()
    else
        if frame.talentPane then frame.talentPane:Hide() end
        if frame.gearPane then frame.gearPane:Hide() end
        if frame.scroll then frame.scroll:Show() end
        renderContent((BUILDERS[name] or function() return {} end)())
        if frame.scroll then frame.scroll:SetVerticalScroll(0) end   -- switching section -> top
    end
end

-- ============================================================================
-- Create
-- ============================================================================
function P.Create(container)
    frame = container
    local pad = 12

    -- Header + status strip
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", pad, -10)
    frame.header = header
    local status = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOPLEFT", pad, -32)
    frame.status = status

    -- Section nav (highlighted)
    frame.sectionBtns = {}
    local sections = { "Gear", "Spec", "Rotation" }
    for i, name in ipairs(sections) do
        local b = UI.CreateButton(container, name, 84, 22, function() selectSection(name) end)
        b:SetPoint("TOPLEFT", pad + (i - 1) * 88, -52)
        frame.sectionBtns[name] = b
    end

    -- PvE / PvP mode toggle: recolours every section's recommendations. Persisted.
    P.pvp = (AIP.db and AIP.db.charPvp) and true or false
    frame.modeBtns = {}
    local function setMode(pvp)
        P.pvp = pvp and true or false
        if AIP.db then AIP.db.charPvp = P.pvp end
        for m, b in pairs(frame.modeBtns) do
            if (m == "PvP") == P.pvp then b:LockHighlight() else b:UnlockHighlight() end
        end
        selectSection(P.section)   -- re-render the current section in the new mode
    end
    for i, m in ipairs({ "PvE", "PvP" }) do
        local b = UI.CreateButton(container, m, 46, 22, function() setMode(m == "PvP") end,
            m == "PvP" and "Show PvP (arena) recommendations across Gear / Spec / Rotation"
                or "Show PvE recommendations across Gear / Spec / Rotation")
        b:SetPoint("TOPLEFT", pad + #sections * 88 + 14 + (i - 1) * 48, -52)
        frame.modeBtns[m] = b
        if (m == "PvP") == P.pvp then b:LockHighlight() end
    end
    -- Pull/Break now live on the title bar (visible even when minimized).

    -- Plain scroll region (no template -> can't hit the unnamed-scrollbar crash).
    -- Leaves a column on the right for the 3D character model.
    local border = CreateFrame("Frame", nil, container)
    border:SetPoint("TOPLEFT", pad, -80)
    border:SetPoint("BOTTOMRIGHT", -pad - 224, 120)
    border:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    border:SetBackdropColor(0, 0, 0, 0.4)
    border:SetBackdropBorderColor(0.4, 0.4, 0.45)

    local scroll = CreateFrame("ScrollFrame", nil, border)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(1); content:SetHeight(1)
    scroll:SetScrollChild(content)
    -- Wheel handler shared by the scroll frame AND its border, so scrolling works
    -- anywhere over the box (rows are Buttons that don't consume the wheel, but the
    -- border padding otherwise wouldn't scroll).
    local function gearWheel(_, delta)
        local maxScroll = math.max(0, content:GetHeight() - scroll:GetHeight())
        scroll:SetVerticalScroll(math.max(0, math.min(maxScroll, scroll:GetVerticalScroll() - delta * ROWH * 2)))
    end
    scroll:EnableMouseWheel(true); scroll:SetScript("OnMouseWheel", gearWheel)
    border:EnableMouseWheel(true); border:SetScript("OnMouseWheel", gearWheel)
    -- keep content width synced to the scroll frame
    scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then content:SetWidth(w) end end)
    frame.scroll, frame.content = scroll, content

    -- 3D character model (right column), drag to rotate.
    local mborder = CreateFrame("Frame", nil, container)
    mborder:SetPoint("TOPRIGHT", -pad, -80)
    mborder:SetSize(212, 208)
    mborder:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    mborder:SetBackdropColor(0, 0, 0, 0.5)
    mborder:SetBackdropBorderColor(0.4, 0.4, 0.45)

    local model = CreateFrame("PlayerModel", nil, mborder)
    model:SetPoint("TOPLEFT", 5, -5); model:SetPoint("BOTTOMRIGHT", -5, 5)
    model:EnableMouse(true); model:EnableMouseWheel(true)
    model:SetScript("OnMouseDown", function(self) self.rot0 = self.rot or 0; self.x0 = ({ GetCursorPosition() })[1]; self.dragging = true end)
    model:SetScript("OnMouseUp", function(self) self.dragging = false end)
    model:SetScript("OnMouseWheel", function(self, d)
        self.zoom = math.max(-0.5, math.min(2, (self.zoom or 0) + d * 0.15)); self:SetPosition(self.zoom, 0, 0)
    end)
    model:SetScript("OnUpdate", function(self)
        if self.dragging then
            local x = ({ GetCursorPosition() })[1]
            self.rot = (self.rot0 or 0) + (x - (self.x0 or x)) * 0.012
            self:SetRotation(self.rot)
        end
    end)
    local function loadModel()
        local ok = pcall(function() model:SetUnit("player"); model:SetRotation(model.rot or 0.4) end)
        if not ok then pcall(function() model:SetModelScale(1); model:RefreshUnit() end) end
    end
    loadModel()
    frame.model, frame.loadModel = model, loadModel

    local mlabel = mborder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    mlabel:SetPoint("BOTTOM", 0, 4); mlabel:SetText("drag to rotate · scroll to zoom")

    -- Character stats readout under the model - stretched to the footer so all
    -- rows fit inside the border (no overflow/overlap).
    local sborder = CreateFrame("Frame", nil, container)
    sborder:SetPoint("TOPRIGHT", -pad, -294)
    sborder:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -pad, 116)
    sborder:SetWidth(212)
    sborder:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    sborder:SetBackdropColor(0, 0, 0, 0.5); sborder:SetBackdropBorderColor(0.4, 0.4, 0.45)
    local stitle = sborder:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    stitle:SetPoint("TOPLEFT", 8, -6); stitle:SetText("|cffffd100Character Stats|r")
    -- Scrollable body so the full stat list fits and scrolls (plain ScrollFrame,
    -- no template -> avoids the unnamed-scrollbar crash). Wheel works anywhere in
    -- the box because the border itself forwards the wheel to the scroll frame.
    local sscroll = CreateFrame("ScrollFrame", nil, sborder)
    sscroll:SetPoint("TOPLEFT", 6, -22); sscroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local scontent = CreateFrame("Frame", nil, sscroll)
    scontent:SetWidth(1); scontent:SetHeight(1)
    sscroll:SetScrollChild(scontent)
    local function statsWheel(_, delta)
        local maxS = math.max(0, scontent:GetHeight() - sscroll:GetHeight())
        sscroll:SetVerticalScroll(math.max(0, math.min(maxS, sscroll:GetVerticalScroll() - delta * 28)))
    end
    sscroll:EnableMouseWheel(true); sscroll:SetScript("OnMouseWheel", statsWheel)
    sborder:EnableMouseWheel(true); sborder:SetScript("OnMouseWheel", statsWheel)
    sscroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then scontent:SetWidth(w) end end)
    frame.statsFrame = scontent; frame.statsScroll = sscroll
    frame.statRows = {}; frame.statsTitle = stitle; frame.whatif = {}; frame.detailSel = {}

    -- Footer: one smart Import box (auto-detects Wowhead talent build vs Pawn
    -- stat string) so the player never has to guess which button to press.
    local ilbl = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilbl:SetPoint("BOTTOMLEFT", pad, 98)
    ilbl:SetText("|cffffd100Import|r  paste a Wowhead talent link |cff888888or|r Pawn stat string - it's auto-detected:")
    local importBox = UI.CreateEditBox(container, 300, 22)
    importBox:SetPoint("BOTTOMLEFT", pad, 74)
    frame.importBox = importBox

    local function smartImport()
        local s = importBox:GetText()
        if not s or s == "" then
            if AIP.Print then AIP.Print("Paste a Wowhead talent link or a Pawn string first.") end
            return
        end
        if s:find("Pawn") or s:find("v1:") or s:find(":%s*%a+=%-?%d") then      -- looks like a Pawn scale
            if AIP.ItemScore then
                local ok, arch, n = AIP.ItemScore.ImportPawn(s)
                if AIP.Print then AIP.Print(ok and ("Imported " .. (n or 0) .. " Pawn stat weights for " .. tostring(arch))
                    or "That doesn't look like a valid Pawn string.") end
                selectSection(P.section)
            end
        else                                                                    -- treat as a Wowhead talent build
            if AIP.SpecAdvisor then AIP.SpecAdvisor.SlashHandler("import " .. s); selectSection("Spec") end
        end
    end
    UI.CreateButton(container, "Import", 72, 22, smartImport,
        "Auto-detects: a Wowhead talent build (compare/apply in Spec) or a Pawn stat string (updates your gear weights)")
        :SetPoint("BOTTOMLEFT", pad + 308, 74)
    UI.CreateButton(container, "Apply talents", 96, 22, function()
        if AIP.SpecAdvisor then AIP.SpecAdvisor.Apply(); selectSection("Spec") end
    end, "Learn the missing recommended talent points you can afford"):SetPoint("BOTTOMLEFT", pad + 384, 74)

    local function toggle(label, key, x, y, tip, onChange)
        local c = UI.CreateCheckbox(container, label, function(self, checked)
            local on = checked and true or false
            if AIP.db then AIP.db[key] = on end
            if onChange then onChange(on) end   -- immediate enable/disable action
            if AIP.Print then AIP.Print(label .. ": " .. (on and "|cff55ff55ON|r" or "|cffff5555OFF|r")) end
            updateHeader()
        end, tip)
        c:SetPoint("BOTTOMLEFT", x, y)
        c:SetChecked(AIP.db and AIP.db[key])
        frame["chk_" .. key] = c
    end
    -- Footer options, grouped into two labelled rows. Row 1 = things that act in
    -- combat / on your screen; row 2 = what you share with peers + tooltip helpers.
    -- Every box's tooltip states exactly what it does AND its scope - hover to read.
    local function catLabel(text, y)
        local fs = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOMLEFT", pad, y)
        fs:SetText(text); fs:SetTextColor(1, 0.82, 0)
    end
    local TX = pad + 64   -- toggles start to the right of the row's category label

    catLabel("In combat", 49)
    toggle("Threat coach", "threatCoach", TX, 46,
        "Heads-up BEFORE you pull aggro off the tank (native threat API - no Omen). Scope: inside instances, in combat only. Takes effect immediately.",
        function(on) if on and AIP.ThreatCoach and AIP.ThreatCoach.Check then AIP.ThreatCoach.Check() end end)
    toggle("Post-pull report", "postPull", TX + 132, 46,
        "After each boss: prints your DPS/HPS + avoidable damage taken + interrupts/dispels. Scope: reads Details! / Skada / Recount if installed. On-demand (no overhead).")
    toggle("Overlay", "rotationHelper", TX + 300, 46,
        "On-screen advisor: next ability + active procs + cooldowns + live DPS. Scope: a movable frame, advisory only (never casts). Off hides it instantly.",
        function() if AIP.Rotation then AIP.Rotation.CreateOverlay(); AIP.Rotation.Tick() end
            if P.section == "Rotation" then selectSection("Rotation") end end)
    toggle("DBM timers", "dbmBridge", TX + 396, 46,
        "Show the raid's DBM pull / break / combat-res timers on AIP's own bars (speaks DBM's protocol). Scope: group only. Turning off clears any active bars now.",
        function(on) if not on and AIP.DBMBridge and AIP.DBMBridge.ClearBars then AIP.DBMBridge.ClearBars() end end)

    catLabel("Share / UI", 23)
    toggle("Share gear", "gearShare", TX, 20,
        "Broadcast your enchant/gem/GearScore AUDIT so AIP peers see your status without inspecting. Scope: AIP users in range. Sends now when enabled.",
        function(on) if on and AIP.GearAdvisor and AIP.GearAdvisor.BroadcastMine then AIP.GearAdvisor.BroadcastMine() end end)
    toggle("Share card", "cardShare", TX + 132, 20,
        "Attach your full character CARD (every item with its enchant/gems + key achievements) to your LFG listing, shown on hover - no inspect needed. Scope: AIP peers. Sends now when enabled.",
        function(on) if on and AIP.CharCard and AIP.CharCard.ShareMine then AIP.CharCard.ShareMine() end end)
    toggle("Tooltip score", "tooltipScore", TX + 264, 20,
        "Append an AIP item score + upgrade/downgrade % to EVERY item tooltip (bags, vendor, inspect). Scope: your client only.")
    toggle("Sheet marks", "paperdollAudit", TX + 396, 20,
        "Mark un-enchanted (E) / empty-socket (G) slots on the Blizzard character sheet. Scope: your client only. Updates instantly.",
        function() if AIP.GearHooks then AIP.GearHooks.UpdatePaperdoll() end end)

    -- Keep the paperdoll live: refresh slot icons/markers when gear changes while
    -- the Gear view is showing (NOT on the 0.5s ticker - SlotAudit is a heavy scan).
    local eqf = CreateFrame("Frame")
    eqf:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    eqf:SetScript("OnEvent", function()
        if P.section == "Gear" and frame and frame:IsVisible() and frame.gearPane then
            renderPaperdoll()
            renderSlotDetail(P.detailSlot)
        end
    end)

    -- Live-refresh the Combat section's DPS line while it's the active view.
    container.acc = 0
    container:SetScript("OnUpdate", function(self, e)
        self.acc = self.acc + e
        if self.acc < 0.5 then return end
        self.acc = 0
        if P.section == "Rotation" and self:IsVisible() and self.content and self.content.rows and self.content.rows[1]
            and AIP.Rotation then
            -- Row 1 is the "WHAT TO PRESS NOW" header; live DPS lives in its right column.
            self.content.rows[1].right:SetText(string.format("%.0f dps", AIP.Rotation.DPS()))
        end
    end)

    selectSection(P.section)
end

function P.Update()
    if not frame then return end
    updateHeader()
    if frame.loadModel then frame.loadModel() end
    for _, key in ipairs({ "threatCoach", "postPull", "gearShare", "rotationHelper", "tooltipScore", "paperdollAudit", "dbmBridge" }) do
        local c = frame["chk_" .. key]
        if c then c:SetChecked(AIP.db and AIP.db[key]) end
    end
    -- Re-render the active section (Gear = paperdoll, Spec = talent graphic, else rows).
    if P.section == "Gear" then
        if frame.scroll then frame.scroll:Hide() end
        if frame.talentPane then frame.talentPane:Hide() end
        ensureGearPane(); frame.gearPane:Show()
        renderPaperdoll()
        applySlotChrome(P.detailSlot)
        renderSlotDetail(P.detailSlot)   -- keeps the user's detail scroll position
    elseif P.section == "Spec" then
        if frame.scroll then frame.scroll:Hide() end
        if frame.gearPane then frame.gearPane:Hide() end
        renderTalents()
    else
        if frame.talentPane then frame.talentPane:Hide() end
        if frame.gearPane then frame.gearPane:Hide() end
        if frame.scroll then frame.scroll:Show() end
        renderContent((BUILDERS[P.section] or function() return {} end)())
    end
end
