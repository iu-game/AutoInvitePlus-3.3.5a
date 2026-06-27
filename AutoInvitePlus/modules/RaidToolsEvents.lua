-- AutoInvite Plus - Raid Tools (events: roll scanning, bar show, expiry checks)

local AIP = AutoInvitePlus
if not AIP then return end
AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_SYSTEM")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame.expElapsed = 0
frame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_SYSTEM" then
        if RT.OnSystemMessage then RT.OnSystemMessage(...) end
    elseif event == "PLAYER_ENTERING_WORLD" then
        if RT.UpdateBar then RT.UpdateBar() end
    end
end)

-- Background expiration checker (every 60s)
frame:SetScript("OnUpdate", function(self, e)
    self.expElapsed = (self.expElapsed or 0) + e
    if self.expElapsed < 60 then return end
    self.expElapsed = 0
    if RT.CheckExpirations then RT.CheckExpirations() end
end)
