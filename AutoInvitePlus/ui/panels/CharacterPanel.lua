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

-- Small section header used to give the combined Gear tab structure.
local function header(e, title) e[#e + 1] = { text = "|cffffd100" .. title .. "|r" } end

local function buildGear()
    local e = {}
    local GA, IS = AIP.GearAdvisor, AIP.ItemScore
    if not (GA and IS) then return { { text = "Gear modules not loaded." } } end

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

local function buildSpec()
    local SA = AIP.SpecAdvisor
    if not SA then return { { text = "SpecAdvisor not loaded." } } end
    local _, split, total = SA.ReadBuild()
    local locClass, classFile = UnitClass("player")
    local e = {}
    e[#e+1] = { text = "Build: " .. table.concat(split, "/") .. "  (" .. (total or 0) .. " pts)", rcolor = {0.6,0.8,1} }
    e[#e+1] = { text = "String: " .. SA.EncodeBuild(), rcolor = {0.75,0.75,0.75} }
    local tree = AIP.ItemScore and AIP.ItemScore.PrimaryTree() or 1
    local guide = SA.Guide[classFile] and SA.Guide[classFile][tree]
    if guide then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "Recommended " .. guide[1] .. ": " .. guide[2], rcolor = {1,0.85,0.2} }
        e[#e+1] = { text = "Glyphs: " .. guide[3] }
        if guide[4] ~= "" then e[#e+1] = { text = "Note: " .. guide[4], rcolor = {0.7,0.7,0.7} } end
    end
    local majors, _, empty = SA.ReadGlyphs()
    if empty > 0 then e[#e+1] = { text = empty .. " empty glyph slot(s).", rcolor = {1,0.45,0.45} } end
    if #majors > 0 then e[#e+1] = { text = "Your glyphs: " .. table.concat(majors, ", ") } end
    -- Which recommended glyphs you're missing.
    if guide and guide[3] then
        local missingG = {}
        for want in guide[3]:gmatch("[^,]+") do
            local w = want:gsub("^%s+", ""):gsub("%s+$", "")
            local have = false
            for _, mg in ipairs(majors) do if w ~= "" and mg:find(w, 1, true) then have = true; break end end
            if not have and w ~= "" then missingG[#missingG + 1] = w end
        end
        if #missingG > 0 then
            e[#e+1] = { text = "Missing recommended glyphs: " .. table.concat(missingG, ", "), rcolor = {1,0.6,0.3} }
        end
    end
    if GetUnspentTalentPoints and (GetUnspentTalentPoints() or 0) > 0 then
        e[#e+1] = { text = GetUnspentTalentPoints() .. " unspent talent point(s)!", rcolor = {1,0.45,0.45} }
    end
    e[#e+1] = { text = " " }
    if SA.RecBuild and SA.RecBuild() then
        local m, w = SA.Diff()
        e[#e+1] = { text = string.format("Imported diff: %s missing, %s misplaced points.",
            tostring(m or 0), tostring(w or 0)), rcolor = {1,0.7,0.2} }
    else
        e[#e+1] = { text = "Paste a wowhead talent-calc string below, then Import Build.", rcolor = {0.7,0.7,0.7} }
    end
    -- Stat priority / gearing targets for this spec (what the build wants).
    local SG = AIP.SpecGuides
    local skey = SG and SG.KeyFor and SG.KeyFor()
    local scaps = skey and SG.Caps and SG.Caps[skey]
    if scaps then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "Stat priority / gearing targets:", rcolor = {1,0.85,0.2} }
        if scaps.hit and scaps.hit > 0 then e[#e+1] = { text = string.format("  %s hit -> %d rating", scaps.hitType, scaps.hit), rcolor = {0.82,0.82,0.86} } end
        if scaps.expertise and scaps.expertise > 0 then e[#e+1] = { text = "  Expertise -> " .. scaps.expertise .. " rating", rcolor = {0.82,0.82,0.86} } end
        if scaps.arp == "yes" then e[#e+1] = { text = "  Armor Pen -> 1400 (hard cap)", rcolor = {0.82,0.82,0.86} } end
        if scaps.defense then e[#e+1] = { text = "  Defense -> 540 (crit immunity)", rcolor = {0.82,0.82,0.86} } end
        if scaps.notes and scaps.notes ~= "" then e[#e+1] = { text = "  " .. scaps.notes, rcolor = {0.66,0.66,0.72} } end
    end
    -- Talent build variations (paste one's link below + Import to load/compare it).
    local variants = skey and SG.Variants and SG.Variants[skey]
    e[#e+1] = { text = " " }
    e[#e+1] = { text = "Build variations:", rcolor = {1,0.85,0.2} }
    if variants and #variants > 0 then
        for _, v in ipairs(variants) do
            e[#e+1] = { text = "  - " .. v[1], rcolor = {0.85,0.85,0.92} }
            e[#e+1] = { text = "      when: " .. v[2], rcolor = {0.62,0.62,0.68} }
        end
        e[#e+1] = { text = "  Paste a variant's Wowhead link below + Import to load & compare it.", rcolor = {0.55,0.62,0.72} }
    else
        e[#e+1] = { text = "  Single cookie-cutter build - no major raid variant for this spec.", rcolor = {0.62,0.62,0.68} }
    end
    return e
end

local function buildReadiness()
    local e = {}
    local R = AIP.Readiness
    if R then
        local issues = R.Scan()
        if #issues == 0 then
            e[#e+1] = { text = "Flask/food, durability, talents, glyphs: all good.", rcolor = {0.45,1,0.45} }
        else
            e[#e+1] = { text = "Fix before pulling:", rcolor = {1,0.7,0.2} }
            for _, iss in ipairs(issues) do e[#e+1] = { text = "  - " .. iss, rcolor = {1,0.45,0.45} } end
        end
    end
    -- Stat-cap status for your spec (the unique value Raid Mgmt doesn't have).
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    local caps = key and SG.Caps and SG.Caps[key]
    if caps then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "Stat caps (" .. key:gsub("_", " ") .. "):", rcolor = {1,0.85,0.2} }
        local function cr(id) return (GetCombatRating and id) and GetCombatRating(id) or 0 end
        local function capline(label, cur, target)
            local ok = cur >= target
            local col = ok and {0.45,1,0.45} or {1,0.5,0.5}
            e[#e+1] = { text = string.format("  %s: %d / %d", label, cur, target), rcolor = col,
                right = ok and "capped" or "UNDER", rightColor = col }
        end
        if caps.hit and caps.hit > 0 then
            local hid = (caps.hitType == "spell" and CR_HIT_SPELL) or (caps.hitType == "ranged" and CR_HIT_RANGED) or CR_HIT_MELEE
            capline("Hit rating", cr(hid), caps.hit)
        end
        if caps.expertise and caps.expertise > 0 then capline("Expertise rating", cr(CR_EXPERTISE), caps.expertise) end
        if caps.arp == "yes" then capline("Armor Pen -> 1400", cr(CR_ARMOR_PENETRATION), 1400) end
        if caps.defense then
            local ba, mo = 0, 0; if UnitDefense then ba, mo = UnitDefense("player") end
            capline("Defense (uncrittable)", (ba or 0) + (mo or 0), caps.defense)
        end
        if caps.notes and caps.notes ~= "" then e[#e+1] = { text = "  " .. caps.notes, rcolor = {0.6,0.6,0.62} } end
    end
    if #e == 0 then e[#e+1] = { text = "Readiness not loaded - relog to load new files." } end
    return e
end

local function buildRotation()
    local Rot = AIP.Rotation
    if not Rot then return { { text = "Rotation module not loaded - log out to character select and back in.", rcolor = {1,0.7,0.2} } } end
    local apl = Rot.CurrentAPL()
    local e = {}
    e[#e+1] = { text = string.format("Live DPS: %.0f", Rot.DPS()), rcolor = {0.4,1,0.4}, right = "live", rightColor = {0.5,0.5,0.5} }

    -- Live "what to press now": active proc jumps the queue, else the APL pick.
    -- (Must be an if-guard, not `and` - a Lua `and` truncates the call to 1 return.)
    local procBuff, procCast, procTex
    if Rot.ActiveProc then procBuff, procCast, procTex = Rot.ActiveProc() end
    local inCombat = UnitAffectingCombat("player")
    local hasTarget = UnitExists("target") and UnitCanAttack("player", "target")
    if procBuff and procCast then
        e[#e+1] = { text = "PROC: " .. procBuff .. "  ->  cast " .. procCast .. " NOW!", icon = procTex, rcolor = {0.3,1,0.45} }
    end
    if apl and inCombat and hasTarget then
        local nextAb = apl.pick()
        if nextAb then
            local _, _, tex = GetSpellInfo(nextAb)
            e[#e+1] = { text = "Next ability: " .. nextAb, icon = tex, rcolor = {1,0.9,0.35} }
        else
            e[#e+1] = { text = "Next: pool resources / wait", rcolor = {0.7,0.7,0.7} }
        end
    end

    e[#e+1] = { text = "Overlay: " .. ((AIP.db and AIP.db.rotationHelper)
        and "ON - drag the on-screen icon; procs pulse a green alert" or "OFF - tick 'Overlay' below"),
        rcolor = (AIP.db and AIP.db.rotationHelper) and {0.45,1,0.45} or {1,0.45,0.45} }
    e[#e+1] = { text = " " }
    local SG = AIP.SpecGuides
    local key = SG and SG.KeyFor and SG.KeyFor()
    -- Resolve the leading spell name of a priority line to its icon.
    local function stepIcon(line)
        local sn = line:match("^([%a][%a%s':]+)")
        if sn then sn = sn:gsub("%s+$", ""); local _, _, t = GetSpellInfo(sn); return t end
    end
    if apl then
        e[#e+1] = { text = "Spec: " .. apl.label, rcolor = {0.6,0.8,1} }
        e[#e+1] = { text = "|cffffd100SINGLE-TARGET priority|r (top = press first):" }
        for i, line in ipairs(apl.priority) do e[#e+1] = { text = string.format("%d.  %s", i, line), icon = stepIcon(line) } end
    else
        e[#e+1] = { text = "No rotation priority for your current spec yet.", rcolor = {1,0.7,0.2} }
    end
    -- AoE / multi-target priority.
    local aoe = key and SG.AoE and SG.AoE[key]
    if aoe then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "|cffff9933AoE / multi-target priority|r (2-3+ targets):" }
        for i, line in ipairs(aoe) do e[#e+1] = { text = string.format("%d.  %s", i, line), icon = stepIcon(line) } end
    end
    -- DoTs to keep up (the overlay warns live when they drop).
    local dots = key and SG.DoTs and SG.DoTs[key]
    if dots and #dots > 0 then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "|cff66bbffKeep these up|r (overlay alerts when they drop):" }
        for _, d in ipairs(dots) do
            local _, _, t = GetSpellInfo(d[1])
            e[#e+1] = { text = string.format("%s  (~%ds%s)", d[1], d[2], d[3] == "player" and ", on you" or ""), icon = t, rcolor = {0.7,0.85,1} }
        end
    end
    -- Free-instant procs to react to.
    local procs = key and SG.Procs and SG.Procs[key]
    if procs and #procs > 0 then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "|cff55ff55Free-instant procs to react to|r:" }
        for _, p in ipairs(procs) do
            local _, _, t = GetSpellInfo(p[1])
            e[#e+1] = { text = string.format("%s  ->  %s", p[1], p[2]), icon = t, rcolor = {0.6,1,0.7} }
        end
    end
    -- Foolproof "how to play" guide (community-sourced tips).
    local rguide = key and SG.Rotations and SG.Rotations[key]
    if rguide then
        e[#e+1] = { text = " " }
        e[#e+1] = { text = "|cff40ff8bHow to run it|r (foolproof guide):" }
        for _, g in ipairs(rguide) do e[#e+1] = { text = "  - " .. g, rcolor = {0.82,0.82,0.86} } end
    end
    return e
end

local BUILDERS = { Gear = buildGear, Spec = buildSpec,
    Readiness = buildReadiness, Rotation = buildRotation }

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

local function renderContent(entries)
    if not (frame and frame.content) then return end
    local content = frame.content
    for i, e in ipairs(entries) do
        local row = getRow(content, i)
        local xoff = e.whatif and 20 or 0
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
        elseif row.check then
            row.check:Hide()
        end
        row.text:SetText(e.text or e.link or "")
        local rc = e.rcolor
        row.text:SetTextColor(rc and rc[1] or 1, rc and rc[2] or 1, rc and rc[3] or 1)
        row.right:SetText(e.right or "")
        local gc = e.rightColor
        row.right:SetTextColor(gc and gc[1] or 0.8, gc and gc[2] or 0.8, gc and gc[3] or 0.8)
        local link, hoverWl = e.link, e.whatif
        if link or hoverWl then
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
                if link and IsShiftKeyDown() and ChatEdit_InsertLink then ChatEdit_InsertLink(link) end
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
    if frame.scroll then
        local maxScroll = math.max(0, content:GetHeight() - frame.scroll:GetHeight())
        frame.scroll:SetVerticalScroll(math.min(frame.scroll:GetVerticalScroll(), maxScroll))
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
    local hv = frame.hoverItem
    local hovering = hv and hv.link and not (frame.whatif and frame.whatif[hv.link])
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
                if isR then valstr = tostring(base) .. string.format("  |cff66ff66%+d|r", d)
                else valstr = string.format("%d |cff66ff66-> %d|r", tonumber(base) or 0, (tonumber(base) or 0) + d) end
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

local function ensureTalentPane()
    if frame.talentPane then return frame.talentPane end
    local parent = (frame.scroll and frame.scroll:GetParent()) or frame
    local tp = CreateFrame("Frame", nil, parent)
    if frame.scroll then tp:SetAllPoints(frame.scroll)
    else tp:SetPoint("TOPLEFT", 12, -80); tp:SetPoint("BOTTOMRIGHT", -240, 120) end
    tp:SetFrameLevel(((frame.scroll and frame.scroll:GetFrameLevel()) or 1) + 5)
    tp.icons, tp.titles, tp.guide = {}, {}, {}
    frame.talentPane = tp
    return tp
end

local function renderTalents()
    local tp = ensureTalentPane()
    tp:Show()
    for _, b in pairs(tp.icons) do b:Hide() end

    for tab = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
        local tname, _, pts = GetTalentTabInfo(tab)
        local title = tp.titles[tab]
        if not title then title = tp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall"); tp.titles[tab] = title end
        title:ClearAllPoints(); title:SetPoint("TOPLEFT", (tab - 1) * TREE_W + 10, -4)
        title:SetText((tname or "Tree") .. "  |cffffd100" .. (pts or 0) .. "|r"); title:Show()

        for idx = 1, (GetNumTalents and GetNumTalents(tab) or 0) do
            local name, icon, tier, column, rank, maxRank = GetTalentInfo(tab, idx)
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

    -- Build + recommendation guide below the trees.
    local SA = AIP.SpecAdvisor
    local _, classFile = UnitClass("player")
    local tree = AIP.ItemScore and AIP.ItemScore.PrimaryTree() or 1
    local guide = SA and SA.Guide[classFile] and SA.Guide[classFile][tree]
    local lines = {}
    if SA then
        local _, split, total = SA.ReadBuild()
        lines[#lines + 1] = "|cffffffffYour build:|r " .. table.concat(split, "/") .. "  (" .. (total or 0) .. " pts)   String: " .. SA.EncodeBuild()
    end
    if guide then
        lines[#lines + 1] = "|cffffd100Recommended " .. guide[1] .. ":|r " .. guide[2] .. "    Glyphs: " .. guide[3]
        if guide[4] ~= "" then lines[#lines + 1] = "|cff88ff88How to play:|r " .. guide[4] end
    end
    if SA and SA.RecBuild and SA.RecBuild() then
        local m, w = SA.Diff(true)   -- silent: this is a render path, must not spam chat
        lines[#lines + 1] = "|cffffaa00Imported diff:|r " .. (m or 0) .. " missing, " .. (w or 0) .. " misplaced (Apply learns what you can afford)"
    else
        lines[#lines + 1] = "|cff888888Paste a wowhead talent string below + Import to compare/apply.|r"
    end
    -- Stat targets + build variations for this spec (from SpecGuides).
    local SG = AIP.SpecGuides
    local skey = SG and SG.KeyFor and SG.KeyFor()
    local scaps = skey and SG.Caps and SG.Caps[skey]
    if scaps then
        local parts = {}
        if scaps.hit and scaps.hit > 0 then parts[#parts + 1] = scaps.hitType .. " hit " .. scaps.hit end
        if scaps.expertise and scaps.expertise > 0 then parts[#parts + 1] = "expertise " .. scaps.expertise end
        if scaps.arp == "yes" then parts[#parts + 1] = "ArP 1400" end
        if scaps.defense then parts[#parts + 1] = "Defense 540" end
        if #parts > 0 then lines[#lines + 1] = "|cff66ccffStat targets:|r " .. table.concat(parts, ", ") end
    end
    local variants = skey and SG.Variants and SG.Variants[skey]
    if variants and #variants > 0 then
        lines[#lines + 1] = "|cffffd100Build variations|r (paste a variant's link below + Import):"
        for _, v in ipairs(variants) do lines[#lines + 1] = "   |cffb9a7ff" .. v[1] .. "|r - " .. v[2] end
    end
    local shown = #lines
    for i = 1, math.max(shown, #tp.guide) do
        local g = tp.guide[i]
        if not g then g = tp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); g:SetJustifyH("LEFT"); tp.guide[i] = g end
        if i <= shown then
            g:ClearAllPoints()
            g:SetPoint("TOPLEFT", 10, -22 - 12 * TSPACE - (i - 1) * 15)
            g:SetWidth(math.max(80, (tp:GetWidth() or 400) - 20)); g:SetText(lines[i]); g:Show()
        else
            g:Hide()
        end
    end
end

local function selectSection(name)
    P.section = name
    for n, btn in pairs(frame.sectionBtns) do
        if n == name then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    updateHeader()
    if name == "Spec" then
        if frame.scroll then frame.scroll:Hide() end
        renderTalents()
    else
        if frame.talentPane then frame.talentPane:Hide() end
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
    local sections = { "Gear", "Spec", "Readiness", "Rotation" }
    for i, name in ipairs(sections) do
        local b = UI.CreateButton(container, name, 84, 22, function() selectSection(name) end)
        b:SetPoint("TOPLEFT", pad + (i - 1) * 88, -52)
        frame.sectionBtns[name] = b
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
    mborder:SetSize(212, 174)
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
    sborder:SetPoint("TOPRIGHT", -pad, -260)
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
    frame.statRows = {}; frame.statsTitle = stitle; frame.whatif = {}

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
            if AIP.db then AIP.db[key] = checked and true or false end
            if onChange then onChange() end
            updateHeader()
        end, tip)
        c:SetPoint("BOTTOMLEFT", x, y)
        c:SetChecked(AIP.db and AIP.db[key])
        frame["chk_" .. key] = c
    end
    toggle("Threat coach", "threatCoach", pad, 46, "Warn before you pull aggro")
    toggle("Post-pull report", "postPull", pad + 132, 46, "DPS/mistakes summary after boss fights")
    toggle("Share gear", "gearShare", pad + 300, 46, "Broadcast my gear audit so peers needn't inspect me")
    toggle("Overlay", "rotationHelper", pad + 430, 46, "Show the live next-ability + proc + DPS overlay on screen",
        function() if AIP.Rotation then AIP.Rotation.CreateOverlay(); AIP.Rotation.Tick() end
            if P.section == "Rotation" then selectSection("Rotation") end end)
    toggle("Tooltip score", "tooltipScore", pad, 20, "Show item score + upgrade % on every tooltip")
    toggle("Sheet marks", "paperdollAudit", pad + 132, 20,
        "Mark un-enchanted (E) / un-gemmed (G) slots on the character sheet",
        function() if AIP.GearHooks then AIP.GearHooks.UpdatePaperdoll() end end)
    toggle("DBM timers", "dbmBridge", pad + 300, 20, "Show DBM pull/break/CR timers on AIP bars")

    -- Live-refresh the Combat section's DPS line while it's the active view.
    container.acc = 0
    container:SetScript("OnUpdate", function(self, e)
        self.acc = self.acc + e
        if self.acc < 0.5 then return end
        self.acc = 0
        if P.section == "Rotation" and self:IsVisible() and self.content and self.content.rows and self.content.rows[1]
            and AIP.Rotation then
            self.content.rows[1].text:SetText(string.format("Live DPS: %.0f", AIP.Rotation.DPS()))
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
    -- Re-render the active section (Spec = talent graphic, others = row list).
    if P.section == "Spec" then
        if frame.scroll then frame.scroll:Hide() end
        renderTalents()
    else
        if frame.talentPane then frame.talentPane:Hide() end
        if frame.scroll then frame.scroll:Show() end
        renderContent((BUILDERS[P.section] or function() return {} end)())
    end
end
