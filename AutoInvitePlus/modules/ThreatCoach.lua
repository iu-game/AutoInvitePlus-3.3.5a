-- AutoInvite Plus - Threat Coach (advisory; enhance-don't-duplicate)
-- Uses Blizzard's native threat API (UnitDetailedThreatSituation, present since
-- patch 3.0.2 - no Omen/ThreatLib dependency) to warn YOU before you rip a mob
-- off the tank. Opt-in (AIP.db.threatCoach), instance + combat gated, throttled,
-- personal heads-up only (never raid chat). A tank who is correctly tanking is
-- never warned (isTanking short-circuits it).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.ThreatCoach = AIP.ThreatCoach or {}
local TC = AIP.ThreatCoach
TC.lastWarn = 0

local WARN_THRESHOLD = 90       -- scaledPercentage: 100 = you pull aggro
local WARN_INTERVAL  = 4        -- seconds between warnings

local function inInstance()
    if AIP.RaidTools and AIP.RaidTools.InPveInstance then
        return AIP.RaidTools.InPveInstance()
    end
    -- Fallback if RaidTools absent: only in a party/raid instance.
    if IsInInstance then
        local inside, t = IsInInstance()
        return inside and (t == "party" or t == "raid")
    end
    return false
end

function TC.Check()
    if not (AIP.db and AIP.db.threatCoach) then return end
    if not UnitDetailedThreatSituation then return end   -- guard (should exist on 3.3.5a)
    if not inInstance() then return end
    if not UnitAffectingCombat("player") then return end
    if not UnitExists("target") or not UnitCanAttack("player", "target") then return end
    if UnitIsDeadOrGhost("target") then return end

    local isTanking, _, scaled = UnitDetailedThreatSituation("player", "target")
    if isTanking or not scaled then return end          -- tanking correctly = no warning
    if scaled < WARN_THRESHOLD then return end

    local now = GetTime()
    if (now - (TC.lastWarn or 0)) < WARN_INTERVAL then return end
    TC.lastWarn = now

    local text
    if scaled >= 100 then
        text = "THREAT - you have aggro! Drop threat NOW (Fade/MD/Feign/Salv)!"
    else
        text = "High threat (" .. math.floor(scaled) .. "%) on " ..
            (UnitName("target") or "boss") .. " - ease off!"
    end
    if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo["RAID_WARNING"])
    end
    if AIP.Print then AIP.Print("|cFFFF4400[Threat]|r " .. text) end
    if PlaySound then PlaySound("RaidWarning") end
end

-- UNIT_THREAT_SITUATION_UPDATE fires on status (0-3) changes, which can lag the
-- % climb, so poll on a light OnUpdate while it matters. Cheap: the function
-- bails immediately when not in combat / not opted in.
local f = CreateFrame("Frame")
f:SetScript("OnUpdate", function(self, e)
    self.acc = (self.acc or 0) + e
    if self.acc < 0.5 then return end
    self.acc = 0
    TC.Check()
end)
