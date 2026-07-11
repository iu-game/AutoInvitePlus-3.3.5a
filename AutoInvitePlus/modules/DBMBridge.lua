-- AutoInvite Plus - DBM Bridge (INTEROP, not a rebuild)
-- Enhance-don't-duplicate: instead of building a competing boss-timer engine, we
-- speak Deadly Boss Mods' addon-message protocol (prefix "D4", tab-delimited
-- body). We LISTEN for the raid's pull / break / combat-res countdowns and render
-- them on AIP's own timer bars (so AIP users see them even without DBM), and we
-- can DRIVE a pull/break by broadcasting the same D4 format, which any raider's
-- DBM will pick up on its native bar.
--
-- Verified wire format (DBM-WotLK): SendAddonMessage("D4", type.."\t"..args, "RAID")
--   PT \t <seconds> \t <mapId>   -- pull timer (0 seconds = cancel)
--   BT \t <seconds>              -- break timer (some builds send minutes)
--   CR \t <seconds>              -- combat-res available
-- We do NOT guard received timers on mapId, so a groupmate's pull always shows.

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r DBMBridge: namespace not found!")
    return
end

AIP.DBMBridge = AIP.DBMBridge or {}
local Bridge = AIP.DBMBridge

local function RT() return AIP.RaidTools end  -- reuse the timer-bar widget (loads first)

-- ----------------------------------------------------------------------------
-- RECEIVE: parse a D4 body and render the matching AIP timer bar.
-- ----------------------------------------------------------------------------
function Bridge.OnD4(msg, sender)
    if not (AIP.db and AIP.db.dbmBridge) then return end
    if not msg or msg == "" then return end
    local rt = RT()
    if not (rt and rt.StartTimer) then return end

    local cmd, a = strsplit("\t", msg)
    sender = sender or "?"

    if cmd == "PT" then
        local secs = tonumber(a)
        if secs == nil then return end
        if secs <= 0 then
            -- A pull timer of 0 is DBM's "cancel" signal.
            if rt.timers then rt.timers["pull"] = nil end
            return
        end
        if secs <= 120 then
            rt.StartTimer("pull", "Pull (" .. sender .. ")", secs, 1, 0.4, 0.1,
                "PULL!", "Interface\\Icons\\Ability_Warrior_BattleShout")
        end

    elseif cmd == "BT" then
        local n = tonumber(a)
        if not n or n <= 0 then return end
        -- BT is normally seconds, but a few builds send minutes. Anything <= 15
        -- is far more likely a minute count than a 15-second break.
        local secs = (n <= 15) and (n * 60) or n
        if secs <= 3600 then
            rt.StartTimer("break", "Break (" .. sender .. ")", secs, 0.2, 0.7, 1,
                "Break ending - get ready!", "Interface\\Icons\\Spell_Nature_TimeStop")
        end

    elseif cmd == "CR" then
        local secs = tonumber(a)
        if secs and secs > 0 and secs <= 60 then
            rt.StartTimer("combatres", "Combat Res ready", secs, 0.6, 0.9, 0.3,
                nil, "Interface\\Icons\\Spell_Nature_Reincarnation")
        end
    end
end

-- Tear down any DBM-driven bars now (so toggling the feature OFF takes visible
-- effect immediately instead of waiting for the bars to expire).
function Bridge.ClearBars()
    local rt = RT()
    if rt and rt.timers then
        rt.timers["pull"] = nil
        rt.timers["break"] = nil
        rt.timers["combatres"] = nil
    end
end

-- ----------------------------------------------------------------------------
-- SEND: drive a pull / break in DBM's format (leader/assist only, to avoid two
-- people fighting to drive the same bar). Renders locally too.
-- ----------------------------------------------------------------------------
local function groupChannel()
    if (GetNumRaidMembers() or 0) > 0 then return "RAID"
    elseif (GetNumPartyMembers() or 0) > 0 then return "PARTY" end
    return nil
end

local function canDrive()
    local rt = RT()
    if rt and rt.CanBroadcast then return rt.CanBroadcast() end
    return true
end

function Bridge.SendPull(seconds)
    seconds = tonumber(seconds)
    if seconds == nil then seconds = 10 end
    if seconds < 0 then seconds = 0 end
    if seconds > 120 then seconds = 120 end
    if not canDrive() then
        AIP.Print("Only the raid leader/assistant can start a pull timer.")
        return
    end
    local mapId = (GetCurrentMapAreaID and GetCurrentMapAreaID()) or 0
    local body = "PT\t" .. seconds .. "\t" .. mapId
    local ch = groupChannel()
    if ch then SendAddonMessage("D4", body, ch) end
    Bridge.OnD4(body, UnitName("player"))  -- render our own bar immediately
    if seconds > 0 then
        AIP.Print("Pull timer: " .. seconds .. "s (visible to DBM users too).")
    else
        AIP.Print("Pull timer cancelled.")
    end
end

function Bridge.SendBreak(minutes)
    local n = tonumber(minutes)
    if n == nil then n = 5 end
    if n < 0 then n = 0 end
    if n > 60 then n = 60 end
    if not canDrive() then
        AIP.Print("Only the raid leader/assistant can start a break timer.")
        return
    end
    local secs = n * 60
    local body = "BT\t" .. secs
    local ch = groupChannel()
    if ch then SendAddonMessage("D4", body, ch) end
    Bridge.OnD4(body, UnitName("player"))
    AIP.Print("Break timer: " .. n .. "m (visible to DBM users too).")
end

-- ----------------------------------------------------------------------------
-- EVENTS
-- ----------------------------------------------------------------------------
-- RegisterAddonMessagePrefix does not exist on 3.3.5a (messages are received
-- without it); the guard keeps us forward-compatible.
if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix("D4") end

local f = CreateFrame("Frame")
f:RegisterEvent("CHAT_MSG_ADDON")
f:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
    if prefix ~= "D4" then return end
    -- Skip our own broadcasts; SendPull/SendBreak already render locally.
    if sender and sender == UnitName("player") then return end
    Bridge.OnD4(message, sender)
end)
