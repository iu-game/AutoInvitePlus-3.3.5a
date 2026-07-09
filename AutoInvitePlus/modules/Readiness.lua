-- AutoInvite Plus - Pre-pull Readiness Checklist (self, foolproof prep)
-- A cheap self-scan of the mistakes that silently wreck a pull: no flask/food,
-- broken gear, unspent talents, empty glyph slots, and (for tanks) being below
-- the 540 Defense uncrittable gate. Runs on /aip check and auto-fires when a
-- Ready Check starts so you can fix things before clicking Ready.
-- All checks are SELF-only and read-only 3.3.5a API. Spec/cap-match against a
-- recommended build comes later (needs the Phase-3 spec data + cap engine).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.Readiness = AIP.Readiness or {}
local R = AIP.Readiness

-- True if the player has a buff whose name contains `sub` (plain substring).
local function hasBuff(sub)
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if not name then break end
        if name:find(sub, 1, true) then return true end
    end
    return false
end

-- Best-effort "am I tanking right now?" so we only enforce the 540 Defense gate
-- on actual tanks (DPS/healers don't need it). DK tanks aren't auto-detected
-- (Frost Presence is shared with Frost DPS) - documented gap.
local function isTankNow()
    local _, class = UnitClass("player")
    if class == "WARRIOR" then
        return GetShapeshiftForm and GetShapeshiftForm() == 2       -- Defensive Stance
    elseif class == "DRUID" then
        return hasBuff("Bear Form") or hasBuff("Dire Bear Form")
    elseif class == "PALADIN" then
        return hasBuff("Righteous Fury")
    end
    return false
end

-- Returns a list of issue strings (empty = all good).
function R.Scan()
    local issues = {}

    -- Consumables
    if not (hasBuff("Flask") or hasBuff("Elixir")) then
        issues[#issues + 1] = "No flask/elixir active"
    end
    if not hasBuff("Well Fed") then
        issues[#issues + 1] = "No food buff (Well Fed)"
    end

    -- Durability (lowest equipped piece under 20% or broken)
    local worst
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then
            local pct = cur / max
            if pct < 0.20 and (not worst or pct < worst) then worst = pct end
        end
    end
    if worst then
        issues[#issues + 1] = string.format("Low durability (%d%%) - repair!", math.floor(worst * 100))
    end

    -- Unspent talent points
    if GetUnspentTalentPoints then
        local unspent = GetUnspentTalentPoints()
        if unspent and unspent > 0 then
            issues[#issues + 1] = unspent .. " unspent talent point(s)"
        end
    end

    -- Empty glyph sockets. Reuse SpecAdvisor.ReadGlyphs' robust scan (the glyph
    -- spell ID isn't always the same return slot, so guessing slot 4 over-reports
    -- empties on many builds).
    if AIP.SpecAdvisor and AIP.SpecAdvisor.ReadGlyphs then
        local _, _, empty = AIP.SpecAdvisor.ReadGlyphs()
        if empty and empty > 0 then
            issues[#issues + 1] = empty .. " empty glyph slot(s)"
        end
    end

    -- Defense uncrittable gate (tanks only) - 540 skill.
    if isTankNow() and UnitDefense then
        local base, mod = UnitDefense("player")
        local defense = (base or 0) + (mod or 0)
        if defense > 0 and defense < 540 then
            issues[#issues + 1] = string.format("Defense %d < 540 - CRITTABLE!", defense)
        end
    end

    return issues
end

-- Print the checklist. `silent` suppresses the "all good" line (used by the
-- auto Ready Check hook, which only wants to shout on failure).
function R.Check(silent)
    local issues = R.Scan()
    if #issues == 0 then
        if not silent then
            AIP.Print("|cFF00FF00Readiness: all good!|r (flask/food, durability, talents, glyphs"
                .. (isTankNow() and ", defense" or "") .. ")")
        end
        return true
    end
    AIP.Print("|cFFFFAA00Readiness issues:|r")
    for _, iss in ipairs(issues) do
        AIP.Print("  |cFFFF6060*|r " .. iss)
    end
    return false, issues
end

-- Auto-scan when anyone starts a Ready Check; heads-up if you're not ready.
local f = CreateFrame("Frame")
f:RegisterEvent("READY_CHECK")
f:SetScript("OnEvent", function()
    if not (AIP.db and AIP.db.readyCheckScan) then return end
    local ok, issues = R.Check(true)
    if not ok then
        local text = "NOT READY: " .. table.concat(issues, ", ")
        if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
            RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
        end
        if PlaySound then PlaySound("RaidWarning") end
    end
end)
