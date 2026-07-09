-- AutoInvite Plus - Spec Advisor / Talent Calculator (WotLK 3.3.5a)
-- Reads your current build & glyphs (GetTalentInfo / GetGlyphSocketInfo), shows
-- the verified recommended point-split + glyphs for your detected spec, and can
-- IMPORT a Wowhead-style digit-per-talent build string to diff against and learn
-- the missing points from (advise-by-default; apply only on explicit confirm).
--
-- Data honesty: the recommended SPLITS and GLYPHS below are the 3.3.5a consensus
-- (Icy-Veins/Wowhead) and are verified. Exact per-talent digit strings are NOT
-- fabricated - paste one from wowhead.com/wotlk/talent-calc for full diff/apply.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.SpecAdvisor = AIP.SpecAdvisor or {}
local SA = AIP.SpecAdvisor

-- ============================================================================
-- Verified recommended builds (split + major glyphs + note), by class + primary
-- talent tree index (1/2/3 in standard WotLK order). Text guidance only.
-- ============================================================================
SA.Guide = {
    MAGE = {
        {"Arcane","57/3/11","Arcane Blast, Arcane Missiles, Molten Armor","hit ~8% (Focus+Precision)"},
        {"Fire","18/53/0","Fireball, Living Bomb, Molten Armor","TtW; hit ~14% raid-buffed"},
        {"Frost","18/0/53","Frostbolt, Eternal Water, Molten Armor","haste>crit; hit ~11%"},
    },
    WARLOCK = {
        {"Affliction","56/0/15","Life Tap, Haunt, Quick Decay","hit ~10-11% (Suppression)"},
        {"Demonology","0/56/15","Life Tap, Felguard, Quick Decay","brings Demonic Pact"},
        {"Destruction","0/13/58","Life Tap, Conflagrate, Imp","hit ~13-14%"},
    },
    PRIEST = {
        {"Discipline","57/14/0","Power Word: Shield, Penance, Flash Heal","Rapture; shields must fully absorb"},
        {"Holy","14/57/0","Prayer of Healing, Circle of Healing, Flash Heal","Serendipity -> PoH"},
        {"Shadow","14/0/57","Mind Flay, Shadow, Shadow Word: Death","self-Misery; hit ~10-11%"},
    },
    DRUID = {
        {"Balance","57/0/14","Focus, Starfall, Insect Swarm","hit ~10% (BoP+IFF)"},
        {"Feral","0/55/16","Mangle/Shred, Savage Roar/Maul, Rip","cat DPS or bear tank (Survival of the Fittest)"},
        {"Restoration","18/0/53","Swiftmend, Wild Growth, Nourish","haste breakpoints"},
    },
    SHAMAN = {
        {"Elemental","57/14/0","Lightning Bolt, Flametongue, Totem of Wrath","needs external hit debuff; hit ~10-11%"},
        {"Enhancement","18/53/0","Feral Spirit, Fire Nova, Stormstrike","needs spell hit ~14% too; ArP bad"},
        {"Restoration","0/14/57","Earth Shield, Chain Heal, Earthliving Weapon","Riptide on CD; Mana Tide"},
    },
    PALADIN = {
        {"Holy","51/20/0","Seal of Wisdom, Holy Light, Beacon of Light","Int top stat; Beacon uptime"},
        {"Protection","0/53/18","Divine Plea, Seal of Vengeance, Judgement","540 defense; keep Holy Shield up"},
        {"Retribution","11/5/55","Seal of Vengeance, Judgement, Exorcism","hit 8% #1; SoV glyph +10 exp"},
    },
    WARRIOR = {
        {"Arms","57/14/0","Rending, Mortal Strike, Execution","keep Rend up; exp ~18 w/ Weapon Mastery"},
        {"Fury","18/53/0","Whirlwind, Heroic Strike, Rending","hit 8%, exp 26, ArP 1400 (else crit>ArP)"},
        {"Protection","15/3/53","Blocking, Vigilance, Devastate","540 defense = uncrittable"},
    },
    DEATHKNIGHT = {
        {"Blood","53/18/0","Disease, Death Strike, Dancing Rune Weapon","DPS: Abomination's Might; tank: 540 def"},
        {"Frost","18/53/0","Obliterate, Frost Strike, Disease","DW needs hard hit/exp caps"},
        {"Unholy","17/0/54","The Ghoul, Death and Decay, Icy Touch","flagship; scaling ghoul"},
    },
    ROGUE = {
        {"Assassination","51/13/7","Mutilate, Tricks, Hunger for Blood","do NOT stack ArP (poison dmg)"},
        {"Combat","20/51/0","Killing Spree, Sinister Strike, Tricks","ArP premier stat"},
        {"Subtlety","19/0/52","Hemorrhage, Tricks, Shadow Dance","brings Hemo debuff"},
    },
    HUNTER = {
        {"Beast Mastery","53/13/5","Steady Shot, Kill Shot, Explosive Trap","Devilsaur pet"},
        {"Marksmanship","7/57/7","Steady Shot, Serpent Sting, Explosive Trap","Wolf pet"},
        {"Survival","0/17/54","Explosive Shot, Kill Shot, Explosive Trap","Wolf pet"},
    },
}

-- ============================================================================
-- Read current build as {[tab]={[index]=rank}} and its X/Y/Z split.
-- ============================================================================
function SA.ReadBuild()
    local build, split, total = {}, {}, 0
    if not (GetNumTalentTabs and GetTalentInfo) then return build, split, total end
    for tab = 1, (GetNumTalentTabs() or 3) do
        build[tab] = {}
        local pts = select(3, GetTalentTabInfo(tab)) or 0
        split[tab] = pts
        total = total + pts
        local num = (GetNumTalents and GetNumTalents(tab)) or 0
        for idx = 1, num do
            local rank = select(5, GetTalentInfo(tab, idx)) or 0
            build[tab][idx] = rank
        end
    end
    return build, split, total
end

-- Encode current build to a Wowhead-style digit string (per-tab, trailing zeros
-- trimmed, joined by "-").
function SA.EncodeBuild()
    local build = SA.ReadBuild()
    local parts = {}
    for tab = 1, #build do
        local s = ""
        for idx = 1, #build[tab] do s = s .. tostring(build[tab][idx] or 0) end
        s = s:gsub("0+$", "")   -- trim trailing zeros
        parts[tab] = s
    end
    return table.concat(parts, "-")
end

-- Decode an imported string to {[tab]={[index]=rank}}.
local function decode(str)
    local out = {}
    local tab = 1
    for chunk in (str .. "-"):gmatch("([^%-]*)%-") do
        out[tab] = {}
        for i = 1, #chunk do out[tab][i] = tonumber(chunk:sub(i, i)) or 0 end
        tab = tab + 1
    end
    return out
end

-- Imported builds are stored PER SPEC (class + primary tree) so a build imported
-- for one spec never diffs wrongly against another.
function SA.SpecKey()
    local _, class = UnitClass("player")
    local best, bp = 1, -1
    for t = 1, (GetNumTalentTabs and GetNumTalentTabs() or 3) do
        local p = select(3, GetTalentTabInfo(t)) or 0
        if p > bp then bp, best = p, t end
    end
    return (class or "?") .. "_" .. best
end
function SA.RecBuild()
    return AIP.db and AIP.db.recBuilds and AIP.db.recBuilds[SA.SpecKey()]
end

-- ============================================================================
-- Diff current vs the imported recommended build (for this spec).
-- ============================================================================
-- silent=true returns counts without printing (for UI render paths that must
-- not spam chat every refresh).
function SA.Diff(silent)
    local recStr = SA.RecBuild()
    if not recStr then
        if not silent then AIP.Print("No recommended build imported for this spec. Use /aip spec import <wowhead-string>.") end
        return
    end
    local rec = decode(recStr)
    local build = SA.ReadBuild()
    local missing, wasted = 0, 0
    for tab, talents in pairs(rec) do
        for idx, want in pairs(talents) do
            local have = (build[tab] and build[tab][idx]) or 0
            if want > have then missing = missing + (want - have) end
        end
    end
    for tab, talents in pairs(build) do
        for idx, have in pairs(talents) do
            local want = (rec[tab] and rec[tab][idx]) or 0
            if have > want then wasted = wasted + (have - want) end
        end
    end
    if not silent then
        if missing == 0 and wasted == 0 then
            AIP.Print("|cFF00FF00Your build matches the imported recommendation.|r")
        else
            AIP.Print(string.format("|cFFFFAA00Build diff:|r %d point(s) missing, %d misplaced.", missing, wasted))
            if wasted > 0 then AIP.Print("  Misplaced points need a talent reset at your trainer to fix.") end
            if missing > 0 then AIP.Print("  Use /aip spec apply to learn the missing points you can afford.") end
        end
    end
    return missing, wasted
end

-- Learn the missing recommended points you can afford (multi-pass, respects
-- prereqs, out of combat only). Cannot remove misplaced points (needs a reset).
function SA.Apply()
    if InCombatLockdown and InCombatLockdown() then AIP.Print("Can't change talents in combat."); return end
    local recStr = SA.RecBuild()
    if not recStr then AIP.Print("Import a build for this spec first (/aip spec import)."); return end
    if not LearnTalent then AIP.Print("LearnTalent unavailable."); return end
    local rec = decode(recStr)
    local learned, guard = 0, 0
    repeat
        local progressed = false
        guard = guard + 1
        local unspent = (GetUnspentTalentPoints and GetUnspentTalentPoints()) or 0
        if unspent <= 0 then break end
        for tab, talents in pairs(rec) do
            for idx, want in pairs(talents) do
                -- GetTalentInfo: name,icon,tier,column,rank(5),maxRank,isExceptional,meetsPrereq(8)
                local _, _, _, _, cur, _, _, meets = GetTalentInfo(tab, idx)
                cur = cur or 0
                if want > cur and meets then
                    LearnTalent(tab, idx)
                    learned = learned + 1
                    progressed = true
                end
            end
        end
    until not progressed or guard > 60
    AIP.Print(learned > 0 and ("Learned " .. learned .. " talent point(s) toward the recommended build.")
        or "No affordable missing points to learn (or misplaced points block the path - reset at trainer).")
end

-- ============================================================================
-- Glyphs
-- ============================================================================
function SA.ReadGlyphs()
    local majors, minors, empty = {}, {}, 0
    if not (GetNumGlyphSockets and GetGlyphSocketInfo) then return majors, minors, empty end
    for i = 1, GetNumGlyphSockets() do
        -- Return order varies by client (glyph spell ID is not always the same
        -- slot, and one of the returns is the icon path). Find the numeric return
        -- that actually resolves to a glyph spell name instead of guessing a slot.
        local rets = { GetGlyphSocketInfo(i) }
        local enabled, gtype = rets[1], rets[2]
        if enabled then
            local name
            for j = 3, #rets do
                local v = rets[j]
                if type(v) == "number" and v > 1000 then
                    local n = GetSpellInfo(v)
                    if n then name = n; break end
                end
            end
            if not name then empty = empty + 1
            elseif gtype == 2 then minors[#minors + 1] = name
            else majors[#majors + 1] = name end
        end
    end
    return majors, minors, empty
end

-- ============================================================================
-- Report
-- ============================================================================
local function primaryTree()
    if AIP.ItemScore and AIP.ItemScore.PrimaryTree then return AIP.ItemScore.PrimaryTree() end
    return 1
end

function SA.Report()
    local _, class = UnitClass("player")
    local _, split, total = SA.ReadBuild()
    local tree = primaryTree()
    local guide = SA.Guide[class] and SA.Guide[class][tree]

    AIP.Print("|cFF66CCFFSpec Advisor|r - " .. (UnitClass("player") or class))
    AIP.Print(string.format("  Your build: %s (%d pts) | current string: |cFFFFFFFF%s|r",
        table.concat(split, "/"), total or 0, SA.EncodeBuild()))
    if guide then
        AIP.Print(string.format("  |cFFFFFF00Recommended %s:|r %s", guide[1], guide[2]))
        AIP.Print("    Glyphs: " .. guide[3])
        if guide[4] and guide[4] ~= "" then AIP.Print("    Note: " .. guide[4]) end
    end

    local unspent = (GetUnspentTalentPoints and GetUnspentTalentPoints()) or 0
    if unspent > 0 then AIP.Print("  |cFFFF6060" .. unspent .. " unspent talent point(s)!|r") end

    local majors, minors, empty = SA.ReadGlyphs()
    if empty > 0 then AIP.Print("  |cFFFF6060" .. empty .. " empty glyph slot(s).|r") end
    if #majors > 0 then AIP.Print("  Major glyphs: " .. table.concat(majors, ", ")) end

    if SA.RecBuild() then SA.Diff() end
end

-- ============================================================================
-- Slash entry: /aip spec [import <str> | apply | diff]
-- ============================================================================
function SA.SlashHandler(rest)
    rest = rest or ""
    local sub, arg = rest:match("^(%S*)%s*(.*)$")
    sub = (sub or ""):lower()
    if sub == "import" and arg ~= "" then
        AIP.db.recBuilds = AIP.db.recBuilds or {}
        AIP.db.recBuilds[SA.SpecKey()] = arg:gsub("%s", "")
        AIP.Print("Recommended build imported for " .. SA.SpecKey() .. ". /aip spec diff to compare, /aip spec apply to learn missing points.")
    elseif sub == "apply" then
        SA.Apply()
    elseif sub == "diff" then
        SA.Diff()
    else
        SA.Report()
    end
end
