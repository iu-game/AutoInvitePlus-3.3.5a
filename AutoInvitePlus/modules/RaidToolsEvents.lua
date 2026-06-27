-- AutoInvite Plus - Raid Tools (events: roll scanning, bar show, expiry checks)

local AIP = AutoInvitePlus
if not AIP then return end
AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UNIT_AURA")
-- Auto mechanic announcer
frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
frame:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
frame:RegisterEvent("CHAT_MSG_MONSTER_EMOTE")
frame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
frame:RegisterEvent("UNIT_HEALTH")
frame.expElapsed = 0
frame.rhElapsed = 0
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        if RT.OnSystemMessage then RT.OnSystemMessage(...) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RT.UpdateBar then RT.UpdateBar() end
    elseif event == "UNIT_AURA" then
        local unit = ...
        if unit == "player" and RT.ScanSelfDebuffs then RT.ScanSelfDebuffs() end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if RT.OnMechanicCombatLog then RT.OnMechanicCombatLog(...) end
    elseif event == "CHAT_MSG_RAID_BOSS_EMOTE" or event == "CHAT_MSG_MONSTER_EMOTE" or event == "CHAT_MSG_MONSTER_YELL" then
        if RT.OnMechanicEmote then RT.OnMechanicEmote(...) end
    elseif event == "UNIT_HEALTH" then
        if RT.OnMechanicHealth then RT.OnMechanicHealth(...) end
    end
end)

-- Background timers: expiry checker (60s) + raid-health monitor (3s).
frame:SetScript("OnUpdate", function(self, e)
    self.rhElapsed = (self.rhElapsed or 0) + e
    if self.rhElapsed >= 3 then
        self.rhElapsed = 0
        if RT.CheckRaidHealth then RT.CheckRaidHealth() end
    end

    self.expElapsed = (self.expElapsed or 0) + e
    if self.expElapsed < 60 then return end
    self.expElapsed = 0
    if RT.CheckExpirations then RT.CheckExpirations() end
end)
