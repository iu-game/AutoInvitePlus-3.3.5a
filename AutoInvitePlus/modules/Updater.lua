-- AutoInvite Plus - Update checker
-- IMPORTANT: WoW addons are sandboxed - there is no HTTP and no file I/O, so an
-- addon physically cannot download or replace its own code in-game. What it CAN
-- do (and what this does): learn the latest version from other AIP users on the
-- DataBus (every peer broadcasts its version via PING/PONG), and notify you
-- inline with a one-click copyable link to the GitHub releases page.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.Updater = {}
local U = AIP.Updater

U.RELEASES_URL = "https://github.com/iu-game/AutoInvitePlus-3.3.5a/releases"

function U.Current()
    return AIP.Version
        or (GetAddOnMetadata and GetAddOnMetadata("AutoInvitePlus", "Version"))
        or "0"
end

-- true if dotted-numeric version `a` is newer than `b` (e.g. "6.1.2" > "6.1.1").
function U.IsNewer(a, b)
    local function nums(v)
        local t = {}
        for n in tostring(v or ""):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = nums(a), nums(b)
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x > y then return true elseif x < y then return false end
    end
    return false
end

-- Highest version seen among online AIP peers (via the DataBus), else our own.
function U.LatestSeen()
    local latest = U.Current()
    if AIP.DataBus and AIP.DataBus.GetOnlinePeers then
        for _, p in ipairs(AIP.DataBus.GetOnlinePeers()) do
            if p.version and p.version ~= "unknown" and U.IsNewer(p.version, latest) then
                latest = p.version
            end
        end
    end
    return latest
end

-- Returns (available:boolean, latestVersion:string)
function U.IsUpdateAvailable()
    local latest = U.LatestSeen()
    return U.IsNewer(latest, U.Current()), latest
end

-- Inline chat notice, shown once per newer version (dismissal persisted in db).
function U.Notify()
    local avail, latest = U.IsUpdateAvailable()
    if not avail then return false end
    if AIP.db and AIP.db.updateNotifiedFor == latest then return true end
    if AIP.db then AIP.db.updateNotifiedFor = latest end

    AIP.Print("|cFF00FF00Update available: v" .. latest .. "|r (you have v" .. U.Current() .. ")")
    AIP.Print("Download: |cFF88CCFF" .. U.RELEASES_URL .. "|r   (or open Settings -> Updates)")

    -- Refresh the Settings panel banner if it exists.
    if AIP.Panels and AIP.Panels.Settings and AIP.Panels.Settings.RefreshUpdateStatus then
        AIP.Panels.Settings.RefreshUpdateStatus()
    end
    return true
end

-- Ask peers for their versions now (refreshes the comparison).
function U.CheckNow()
    if AIP.DataBus and AIP.DataBus.SendPing then
        AIP.DataBus.SendPing()
    end
    -- Give pongs a moment to arrive, then evaluate.
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(2, function()
            U.Notify()
            if AIP.Panels and AIP.Panels.Settings and AIP.Panels.Settings.RefreshUpdateStatus then
                AIP.Panels.Settings.RefreshUpdateStatus()
            end
        end)
    end
end

function U.SlashHandler()
    local avail, latest = U.IsUpdateAvailable()
    AIP.Print("=== AutoInvite+ Updates ===")
    AIP.Print("Installed: v" .. U.Current()
        .. (avail and ("   |cFF00FF00latest seen: v" .. latest .. "|r") or "   |cFF888888(no newer version seen)|r"))
    AIP.Print("Releases: |cFF88CCFF" .. U.RELEASES_URL .. "|r")
    AIP.Print("|cFFFFFF00Note:|r addons can't self-update - download the zip and replace the AutoInvitePlus folder, then /reload.")
    U.CheckNow()
end

-- Periodic background check: peers (and their versions) arrive over time. Cheap
-- and self-silencing (Notify only speaks once per new version).
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f.elapsed = 0
f:SetScript("OnEvent", function()
    -- Slight delay so the DataBus has discovered peers first.
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(20, U.Notify)
    end
end)
f:SetScript("OnUpdate", function(self, e)
    self.elapsed = self.elapsed + e
    if self.elapsed < 60 then return end
    self.elapsed = 0
    U.Notify()
end)
