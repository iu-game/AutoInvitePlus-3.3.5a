-- AutoInvite Plus - Core Module
-- Combined and enhanced version for WotLK 3.3.5a
-- Original authors: Martag of Greymane, Matthias Fechner

local ADDON_NAME = "AutoInvitePlus"
local VERSION = "4.3.10"

-- Create main addon namespace
AutoInvitePlus = {}
local AIP = AutoInvitePlus

-- Default saved variables structure
local defaults = {
    enabled = false,
    triggers = "invme-auto",
    spamMessage = 'LFM <raid> <roles> | <gs>+ | Whisper "<key>" for invite',
    maxRaiders = 25,
    useMaxLimit = false,
    autoRaid = true,
    guildOnly = false,
    useQueue = false,

    -- Listening channels
    listenWhisper = true,
    listenGuild = false,
    listenSay = false,
    listenYell = false,
    listenGeneral = false,
    listenTrade = false,
    listenLFG = false,
    listenDefense = false,
    listenCustom = false,
    customChannel = "",

    -- Spam channels
    spamGeneral = false,
    spamSay = false,
    spamTrade = false,
    spamGuild = false,
    spamLFG = false,
    spamCustom = false,
    spamYell = false,
    spamChannels = {},  -- Dynamic custom channels {["ChannelName"] = true/false}

    -- Listen custom channels
    listenChannels = {},  -- Dynamic custom channels {["ChannelName"] = true/false}

    -- Blacklist
    blacklist = {},

    -- Promote system
    promoteEnabled = false,
    promoteKey = "assist",
    promoteAutoAssist = true,

    -- Queue
    queue = {},

    -- Waitlist
    waitlist = {},

    -- Invite history for rate limiting
    inviteHistory = {},

    -- Spam timing configuration (tuned to avoid chat bans)
    spamGlobalCooldown = 5,    -- seconds between any spam messages
    spamChannelCooldown = 15,  -- seconds between messages per channel
    autoSpamInterval = 90,     -- seconds between auto-spam cycles (WoW limits ~1msg/minute per channel)

    -- Response messages
    responseInvite = "[AutoInvite+] You have been invited!",
    responseReject = "[AutoInvite+] Sorry, the raid is full.",
    responseWaitlist = "[AutoInvite+] Added to waitlist, position: #%d",
    responseWaitlistPosition = "[AutoInvite+] Your waitlist position changed to: #%d",

    -- Blacklist mode: "flag" = show indicator only, "reject" = auto-reject
    blacklistMode = "flag",

    -- GUI settings
    guiOpacity = 1.0,           -- Main window opacity (0.3 to 1.0)
    guiUnfocusedOpacity = 0.6,  -- Opacity when window is not focused
    guiUnfocusedEnabled = false, -- Enable unfocused opacity reduction
    minimapAngle = 220,         -- Minimap button angle
}

-- Channel IDs for WotLK (default IDs, actual may vary by server)
local CHANNEL_GENERAL = 1
local CHANNEL_TRADE = 2
local CHANNEL_LFG = 4  -- Looking For Group (might vary by server)
local CHANNEL_DEFENSE = 22

-- Spam cooldown tracking
local spamCooldowns = {}
local lastSpamTime = 0

-- Get configured cooldowns (with fallback to defaults)
local function GetGlobalCooldown()
    return AIP.db and AIP.db.spamGlobalCooldown or 3
end

local function GetChannelCooldown()
    return AIP.db and AIP.db.spamChannelCooldown or 10
end

-- Get all joined channels dynamically
local function GetJoinedChannels()
    local channels = {}
    for i = 1, MAX_CHANNEL_BUTTONS or 20 do
        local id, name = GetChannelName(i)
        if id and id > 0 and name and name ~= "" then
            -- Extract base channel name (remove number prefix if present)
            local baseName = name:match("^%d+%.%s*(.+)$") or name
            channels[i] = {
                id = id,
                name = baseName,
                fullName = name
            }
        end
    end
    return channels
end

AIP.GetJoinedChannels = GetJoinedChannels

-- Check if we can spam to a channel (cooldown check)
local function CanSpamToChannel(channelKey)
    local now = time()
    local globalCd = GetGlobalCooldown()
    local channelCd = GetChannelCooldown()

    -- Check global cooldown
    if now - lastSpamTime < globalCd then
        return false, globalCd - (now - lastSpamTime)
    end

    -- Check per-channel cooldown
    if spamCooldowns[channelKey] and now - spamCooldowns[channelKey] < channelCd then
        return false, channelCd - (now - spamCooldowns[channelKey])
    end

    return true, 0
end

-- Mark channel as spammed
local function MarkChannelSpammed(channelKey)
    local now = time()
    spamCooldowns[channelKey] = now
    lastSpamTime = now
end

-- Utility functions
local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[AutoInvite+]|r " .. tostring(msg))
end

local function Debug(msg)
    if AIP.db and AIP.db.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFFFF00[AIP Debug]|r " .. tostring(msg))
    end
end

AIP.Print = Print
AIP.Debug = Debug

-- Check if player is in guild
local function IsPlayerInGuild(name)
    if not IsInGuild() then return false end

    local numGuildMembers = GetNumGuildMembers()
    for i = 1, numGuildMembers do
        local guildName = GetGuildRosterInfo(i)
        if guildName and guildName:lower() == name:lower() then
            return true
        end
    end
    return false
end

AIP.IsPlayerInGuild = IsPlayerInGuild

-- Check if message contains any trigger word
local function CheckTriggers(message)
    if not AIP.db or not AIP.db.triggers then return false end

    local msg = message:lower():gsub("%s+", " "):trim()
    local triggers = { strsplit(";", AIP.db.triggers:lower():gsub("%s*;%s*", ";")) }

    for _, trigger in ipairs(triggers) do
        trigger = trigger:trim()
        if trigger ~= "" and msg:find(trigger, 1, true) then
            return true
        end
    end
    return false
end

AIP.CheckTriggers = CheckTriggers

-- Check if we can invite (are leader or no group)
local function CanInvite()
    local numParty = GetNumPartyMembers()
    local numRaid = GetNumRaidMembers()

    if numRaid > 0 then
        return IsRaidLeader() or IsRaidOfficer()
    elseif numParty > 0 then
        return IsPartyLeader()
    end
    return true -- No group, can start one
end

AIP.CanInvite = CanInvite

-- Check if group/raid is full
local function IsGroupFull()
    if not AIP.db.useMaxLimit then return false end

    local current
    if UnitInRaid("player") then
        current = GetNumRaidMembers()
    else
        current = GetNumPartyMembers() + 1
    end

    return current >= AIP.db.maxRaiders
end

AIP.IsGroupFull = IsGroupFull

-- Get current group size
local function GetGroupSize()
    if UnitInRaid("player") then
        return GetNumRaidMembers()
    else
        return GetNumPartyMembers() + 1
    end
end

AIP.GetGroupSize = GetGroupSize

-- Convert to raid if needed
local function ConvertToRaidIfNeeded()
    if not AIP.db.autoRaid then return end
    if UnitInRaid("player") then return end
    if not IsPartyLeader() then return end

    local numParty = GetNumPartyMembers()
    if numParty >= 4 then  -- 5 total players including self
        Print("Converting to raid...")
        ConvertToRaid()
    end
end

AIP.ConvertToRaidIfNeeded = ConvertToRaidIfNeeded

-- Toggle UI (main GUI)
function AIP.ToggleUI()
    if AIP.CentralGUI then
        AIP.CentralGUI.Toggle()
    else
        Print("Central GUI not loaded. Use /aip help for commands.")
    end
end

-- Send invite to player
local function InvitePlayer(name)
    if not name or name == "" then return false end
    if name:lower() == UnitName("player"):lower() then return false end

    -- Check blacklist
    if AIP.IsBlacklisted and AIP.IsBlacklisted(name) then
        Debug("Player " .. name .. " is blacklisted")
        return false
    end

    -- Check guild only
    if AIP.db.guildOnly and not IsPlayerInGuild(name) then
        Print(name .. " denied: Guild members only")
        return false
    end

    -- Check if group is full
    if IsGroupFull() then
        SendChatMessage("[AutoInvite+] Sorry, no spots available.", "WHISPER", nil, name)
        return false
    end

    -- Check if we can invite
    if not CanInvite() then
        Debug("Cannot invite - not leader")
        return false
    end

    -- Convert to raid if needed before inviting
    ConvertToRaidIfNeeded()

    -- Send the invite
    InviteUnit(name)
    SendChatMessage("[AutoInvite+] Sending invite!", "WHISPER", nil, name)
    Print("Invited: " .. name)

    return true
end

AIP.InvitePlayer = InvitePlayer

-- Process incoming message for invite triggers
local function ProcessMessage(author, message, channel)
    if not AIP.db then
        Debug("ProcessMessage: db not initialized")
        return
    end
    if not AIP.db.enabled then
        Debug("ProcessMessage: auto-invite disabled")
        return
    end
    if not author or author == "" then return end
    if author:lower() == UnitName("player"):lower() then return end

    -- Check if message contains trigger
    if not CheckTriggers(message) then
        Debug("ProcessMessage: no trigger in '" .. message .. "'")
        return
    end

    Print("Trigger matched from " .. author .. " via " .. channel)

    -- Queue or direct invite
    if AIP.db.useQueue and AIP.AddToQueue then
        AIP.AddToQueue(author, message)
    else
        InvitePlayer(author)
    end
end

AIP.ProcessMessage = ProcessMessage

-- Helper to find channel by partial name match
local function FindChannelId(...)
    local searchNames = {...}
    for i = 1, MAX_CHANNEL_BUTTONS or 20 do
        local id, name = GetChannelName(i)
        if id and id > 0 and name then
            local nameLower = name:lower()
            for _, search in ipairs(searchNames) do
                if nameLower:find(search:lower(), 1, true) then
                    return id
                end
            end
        end
    end
    return nil
end

AIP.FindChannelId = FindChannelId

-- Chat ban detection state
AIP.ChatBan = {
    detected = false,
    lastBanTime = 0,
    banCount = 0,
    channelDelay = 2,  -- Base delay between channels (seconds)
    maxDelay = 5,      -- Max delay after bans detected
}

-- Timer helper for delayed execution (WotLK compatible)
local function DelayedCall(delay, func)
    local frame = CreateFrame("Frame")
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            func()
        end
    end)
end

-- Spam invite message with staggered channel sends
function AIP.SpamInvite()
    if not AIP.db.enabled then
        Print("Enable the addon first!")
        return
    end

    -- Check global cooldown
    local now = time()
    if now - lastSpamTime < GetGlobalCooldown() then
        local remaining = GetGlobalCooldown() - (now - lastSpamTime)
        Print("Spam on cooldown. Wait " .. remaining .. " seconds.")
        return
    end

    local msg = AIP.db.spamMessage
    msg = msg:gsub("<key>", AIP.db.triggers:gsub(";", " or "))

    -- Build message queue with staggered delays
    local messageQueue = {}
    local delay = 0
    local delayIncrement = AIP.ChatBan.channelDelay

    -- If recently banned, increase delay
    if AIP.ChatBan.detected and (now - AIP.ChatBan.lastBanTime) < 300 then
        delayIncrement = math.min(AIP.ChatBan.maxDelay, AIP.ChatBan.channelDelay + AIP.ChatBan.banCount)
    end

    -- Queue channel messages with delays
    if AIP.db.spamLFG then
        local id = FindChannelId("lookingforgroup", "lfg")
        if id then
            table.insert(messageQueue, {delay = delay, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "LFG"})
            delay = delay + delayIncrement
        end
    end

    if AIP.db.spamTrade then
        local id = FindChannelId("trade")
        if id then
            table.insert(messageQueue, {delay = delay, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "Trade"})
            delay = delay + delayIncrement
        end
    end

    if AIP.db.spamGeneral then
        local id = FindChannelId("general")
        if id then
            table.insert(messageQueue, {delay = delay, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "General"})
            delay = delay + delayIncrement
        end
    end

    -- Custom channels from db.spamChannels list
    if AIP.db.spamChannels then
        for channelName, enabled in pairs(AIP.db.spamChannels) do
            if enabled then
                local id = GetChannelName(channelName)
                if id and id > 0 then
                    table.insert(messageQueue, {delay = delay, func = function()
                        SendChatMessage(msg, "CHANNEL", nil, id)
                    end, name = channelName})
                    delay = delay + delayIncrement
                end
            end
        end
    end

    -- Legacy custom channel support
    if AIP.db.spamCustom and AIP.db.customChannel and AIP.db.customChannel ~= "" then
        local id = GetChannelName(AIP.db.customChannel)
        if id and id > 0 then
            table.insert(messageQueue, {delay = delay, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = AIP.db.customChannel})
            delay = delay + delayIncrement
        end
    end

    -- SAY/YELL/GUILD can be grouped together (different chat types, less throttled)
    local groupDelay = delay
    if AIP.db.spamSay then
        table.insert(messageQueue, {delay = groupDelay, func = function()
            SendChatMessage(msg, "SAY")
        end, name = "Say"})
        groupDelay = groupDelay + 0.5
    end

    if AIP.db.spamYell then
        table.insert(messageQueue, {delay = groupDelay, func = function()
            SendChatMessage(msg, "YELL")
        end, name = "Yell"})
        groupDelay = groupDelay + 0.5
    end

    if AIP.db.spamGuild and IsInGuild() then
        table.insert(messageQueue, {delay = groupDelay, func = function()
            SendChatMessage(msg, "GUILD")
        end, name = "Guild"})
    end

    -- Execute message queue
    local sentCount = #messageQueue
    if sentCount == 0 then
        Print("No channels configured for spam!")
        return
    end

    -- Reset ban detection for this batch
    AIP.ChatBan.pendingCount = sentCount
    AIP.ChatBan.sentThisBatch = 0

    for _, item in ipairs(messageQueue) do
        if item.delay == 0 then
            item.func()
            AIP.ChatBan.sentThisBatch = AIP.ChatBan.sentThisBatch + 1
        else
            DelayedCall(item.delay, function()
                item.func()
                AIP.ChatBan.sentThisBatch = AIP.ChatBan.sentThisBatch + 1
            end)
        end
    end

    -- Update cooldown
    lastSpamTime = now

    local totalTime = delay > 0 and string.format(" (over %.1fs)", delay) or ""
    Print("Broadcasting to " .. sentCount .. " channel(s)" .. totalTime)
end

-- Check for chat ban messages and auto-tune
function AIP.OnChatBanDetected(message)
    local now = time()
    AIP.ChatBan.detected = true
    AIP.ChatBan.lastBanTime = now
    AIP.ChatBan.banCount = AIP.ChatBan.banCount + 1

    -- Increase channel delay (up to max)
    AIP.ChatBan.channelDelay = math.min(AIP.ChatBan.maxDelay, AIP.ChatBan.channelDelay + 1)

    -- Auto-tune the broadcast interval if GUI system is active
    if AIP.CentralGUI and AIP.CentralGUI.Broadcast and AIP.CentralGUI.Broadcast.active then
        local newInterval = AIP.CentralGUI.Broadcast.interval + 30
        newInterval = math.min(300, newInterval)  -- Cap at 5 minutes
        AIP.CentralGUI.Broadcast.interval = newInterval
        Print("|cFFFF6666Chat throttled!|r Auto-tuning interval to " .. newInterval .. "s, delay to " .. AIP.ChatBan.channelDelay .. "s")
    else
        Print("|cFFFF6666Chat throttled!|r Increasing channel delay to " .. AIP.ChatBan.channelDelay .. "s")
    end

    -- Decay ban count over time
    DelayedCall(300, function()
        if AIP.ChatBan.banCount > 0 then
            AIP.ChatBan.banCount = AIP.ChatBan.banCount - 1
        end
        if AIP.ChatBan.banCount == 0 then
            AIP.ChatBan.detected = false
            AIP.ChatBan.channelDelay = 2  -- Reset to base
        end
    end)
end

-- Register for chat ban detection
local chatBanFrame = CreateFrame("Frame")
chatBanFrame:RegisterEvent("CHAT_MSG_SYSTEM")
chatBanFrame:SetScript("OnEvent", function(self, event, message)
    if event == "CHAT_MSG_SYSTEM" then
        -- Common chat throttle/ban messages (varies by server/locale)
        local banPatterns = {
            "you have been squelched",
            "you are being ignored",
            "you cannot send",
            "chat has been disabled",
            "you are not permitted",
            "throttled",
            "too many messages",
            "wait before sending",
            "you must wait",
            "chat is currently disabled",
        }
        local lowerMsg = message:lower()
        for _, pattern in ipairs(banPatterns) do
            if lowerMsg:find(pattern) then
                AIP.OnChatBanDetected(message)
                break
            end
        end
    end
end)

-- Invite all online guild members
function AIP.InviteGuild()
    if not IsInGuild() then
        Print("You are not in a guild!")
        return
    end

    AIP.db.enabled = true
    GuildRoster()
    SetGuildRosterShowOffline(false)

    local numMembers, numOnline = GetNumGuildMembers()
    local invited = 0

    for i = 1, numOnline do
        local name = GetGuildRosterInfo(i)
        if name and name ~= UnitName("player") then
            if not UnitInRaid(name) and not UnitInParty(name) then
                if AIP.db.useQueue and AIP.AddToQueue then
                    AIP.AddToQueue(name, "Guild invite")
                    invited = invited + 1
                else
                    if InvitePlayer(name) then
                        invited = invited + 1
                    end
                end
            end
        end
    end

    Print("Added " .. invited .. " guild members to " .. (AIP.db.useQueue and "queue" or "invites"))
end

-- Invite all online friends
function AIP.InviteFriends()
    AIP.db.enabled = true
    local invited = 0

    for i = 1, GetNumFriends() do
        local name, level, class, area, connected = GetFriendInfo(i)
        if connected and name then
            if not UnitInRaid(name) and not UnitInParty(name) then
                if AIP.db.useQueue and AIP.AddToQueue then
                    AIP.AddToQueue(name, "Friend invite")
                    invited = invited + 1
                else
                    if InvitePlayer(name) then
                        invited = invited + 1
                    end
                end
            end
        end
    end

    Print("Added " .. invited .. " friends to " .. (AIP.db.useQueue and "queue" or "invites"))
end

-- Event handler
local function OnEvent(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == ADDON_NAME then
            -- Initialize saved variables
            if not AutoInvitePlusDB then
                AutoInvitePlusDB = {}
            end

            -- Merge defaults with saved data
            for k, v in pairs(defaults) do
                if AutoInvitePlusDB[k] == nil then
                    AutoInvitePlusDB[k] = v
                end
            end

            AIP.db = AutoInvitePlusDB

            Print("v" .. VERSION .. " loaded. Type /aip or /autoinvite for options.")
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Refresh guild roster
        if IsInGuild() then
            GuildRoster()
        end

    elseif event == "CHAT_MSG_WHISPER" then
        local message, author = ...
        Debug("Whisper received from " .. tostring(author) .. ": " .. tostring(message))

        -- Check for promote command first
        if AIP.db and AIP.db.promoteEnabled then
            local cmd, key = strsplit(" ", message, 2)
            if cmd and cmd:lower() == "!promote" then
                if AIP.HandlePromote then
                    AIP.HandlePromote(author, key)
                end
                return
            end
        end

        -- Regular invite trigger
        if AIP.db and AIP.db.listenWhisper then
            ProcessMessage(author, message, "whisper")
        else
            Debug("Whisper ignored: listenWhisper=" .. tostring(AIP.db and AIP.db.listenWhisper))
        end

    elseif event == "CHAT_MSG_GUILD" then
        if AIP.db.listenGuild then
            local message, author = ...
            ProcessMessage(author, message, "guild")
        end

    elseif event == "CHAT_MSG_SAY" then
        if AIP.db.listenSay then
            local message, author = ...
            ProcessMessage(author, message, "say")
        end

    elseif event == "CHAT_MSG_YELL" then
        if AIP.db.listenYell then
            local message, author = ...
            ProcessMessage(author, message, "yell")
        end

    elseif event == "CHAT_MSG_CHANNEL" then
        local message, author, _, _, _, _, _, channelIndex, channelName = ...
        channelIndex = tonumber(channelIndex) or 0

        -- Check standard channels
        local channelLower = channelName and channelName:lower() or ""

        if channelLower:find("general") and AIP.db.listenGeneral then
            ProcessMessage(author, message, "general")
        elseif channelLower:find("trade") and AIP.db.listenTrade then
            ProcessMessage(author, message, "trade")
        elseif (channelLower:find("lookingforgroup") or channelLower:find("lfg")) and AIP.db.listenLFG then
            ProcessMessage(author, message, "lfg")
        elseif (channelLower:find("localdefense") or channelLower:find("defense")) and AIP.db.listenDefense then
            ProcessMessage(author, message, "defense")
        else
            -- Check custom listen channels
            if AIP.db.listenChannels then
                for chName, enabled in pairs(AIP.db.listenChannels) do
                    if enabled and channelLower:find(chName:lower()) then
                        ProcessMessage(author, message, "custom:" .. chName)
                        break
                    end
                end
            end
            -- Legacy custom channel support
            if AIP.db.listenCustom and AIP.db.customChannel and AIP.db.customChannel ~= "" then
                if channelLower:find(AIP.db.customChannel:lower()) then
                    ProcessMessage(author, message, "custom")
                end
            end
        end

    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        ConvertToRaidIfNeeded()
    end
end

-- Create main event frame
local eventFrame = CreateFrame("Frame", "AutoInvitePlusFrame", UIParent)
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:RegisterEvent("CHAT_MSG_SAY")
eventFrame:RegisterEvent("CHAT_MSG_YELL")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", OnEvent)

-- Slash commands
local function SlashHandler(msg)
    local cmd, rest = strsplit(" ", msg, 2)
    cmd = (cmd or ""):lower():trim()
    rest = rest or ""

    -- Main UI
    if cmd == "" or cmd == "show" or cmd == "config" then
        AIP.ToggleUI()

    -- Enable/disable
    elseif cmd == "enable" or cmd == "on" then
        AIP.db.enabled = true
        Print("Auto-invite ENABLED")
    elseif cmd == "disable" or cmd == "off" then
        AIP.db.enabled = false
        Print("Auto-invite DISABLED")
    elseif cmd == "toggle" then
        AIP.db.enabled = not AIP.db.enabled
        Print("Auto-invite " .. (AIP.db.enabled and "ENABLED" or "DISABLED"))

    -- Basic features
    elseif cmd == "spam" then
        AIP.SpamInvite()
    elseif cmd == "guild" then
        AIP.InviteGuild()
    elseif cmd == "friends" then
        AIP.InviteFriends()
    elseif cmd == "queue" or cmd == "list" then
        if AIP.ToggleQueueUI then
            AIP.ToggleQueueUI()
        end
    elseif cmd == "bl" or cmd == "blacklist" then
        if AIP.ToggleBlacklistUI then
            AIP.ToggleBlacklistUI()
        end
    elseif cmd == "promote" then
        if AIP.TogglePromoteUI then
            AIP.TogglePromoteUI()
        end

    -- Raid Composition (new)
    elseif cmd == "comp" or cmd == "composition" then
        if AIP.Composition and AIP.Composition.SlashHandler then
            AIP.Composition.SlashHandler(rest)
        end

    -- LFM Browser (new - Central GUI)
    elseif cmd == "lfm" or cmd == "browser" or cmd == "scan" then
        if AIP.CentralGUI then
            AIP.CentralGUI.Show("lfm")
        elseif AIP.LFMBrowser and AIP.LFMBrowser.SlashHandler then
            AIP.LFMBrowser.SlashHandler(rest)
        else
            AIP.ToggleLFMBrowserUI()
        end

    -- LFG Tab (new)
    elseif cmd == "lfg" or cmd == "players" then
        if AIP.CentralGUI then
            AIP.CentralGUI.Show("lfg")
        end

    -- Central GUI (new)
    elseif cmd == "gui" or cmd == "central" or cmd == "main" then
        if AIP.CentralGUI then
            AIP.CentralGUI.Toggle()
        end

    -- Roster Manager (new)
    elseif cmd == "roster" or cmd == "rosters" then
        if AIP.Roster and AIP.Roster.SlashHandler then
            AIP.Roster.SlashHandler(rest)
        end
    elseif cmd == "waitlist" or cmd == "wait" then
        if AIP.Roster then
            AIP.Roster.SlashHandler("waitlist " .. rest)
        end

    -- Integrations (new)
    elseif cmd == "lockouts" or cmd == "locks" then
        if AIP.Integrations then
            AIP.Integrations.PrintLockouts()
        end
    elseif cmd == "summons" or cmd == "summon" then
        if AIP.Integrations then
            AIP.Integrations.PrintSummonStatus()
        end
    elseif cmd == "gs" then
        if AIP.Integrations then
            AIP.Integrations.SlashHandler("gs " .. rest)
        end

    -- Raid Browser integration
    elseif cmd == "rb" or cmd == "raidbrowser" then
        if AIP.Integrations then
            AIP.Integrations.RaidBrowserSlashHandler(rest)
        end

    -- Status
    elseif cmd == "status" then
        Print("=== AutoInvite Plus Status ===")
        Print("Auto-invite: " .. (AIP.db.enabled and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r"))
        Print("Triggers: " .. AIP.db.triggers)
        Print("Max raiders: " .. (AIP.db.useMaxLimit and AIP.db.maxRaiders or "unlimited"))
        Print("Current size: " .. GetGroupSize())
        if AIP.GetQueueCount then
            Print("Queue: " .. AIP.GetQueueCount() .. " players")
        end
        if AIP.LFMBrowser then
            Print("LFM Browser: " .. AIP.LFMBrowser.GetPlayerCount() .. " players tracked")
        end

    -- Help
    elseif cmd == "help" then
        Print("=== AutoInvite Plus v" .. VERSION .. " Commands ===")
        Print("|cFFFFFF00Basic:|r")
        Print("  /aip or /aip gui - Open central GUI")
        Print("  /aip enable/disable - Toggle auto-invite")
        Print("  /aip spam - Send invite spam")
        Print("  /aip guild/friends - Invite guild or friends")
        Print("  /aip queue - Invite queue")
        Print("  /aip blacklist - Manage blacklist")
        Print("|cFFFFFF00LFM/LFG Browser:|r")
        Print("  /aip lfm - LFM groups browser")
        Print("  /aip lfg - LFG players browser")
        Print("|cFFFFFF00Raid Organization:|r")
        Print("  /aip comp - Raid composition advisor")
        Print("  /aip roster - Roster manager (save/load)")
        Print("  /aip waitlist - Waitlist management")
        Print("|cFFFFFF00Utilities:|r")
        Print("  /aip lockouts - Your raid lockouts")
        Print("  /aip summons - Summon status")
        Print("  /aip gs <name> - Check GearScore")
        Print("  /aip rb import - Import from Blizzard Raid Browser")
        Print("  /aip status - Current status")

    else
        Print("Unknown command. Type /aip help for options.")
    end
end

SlashCmdList["AUTOINVITEPLUS"] = SlashHandler
SLASH_AUTOINVITEPLUS1 = "/aip"
SLASH_AUTOINVITEPLUS2 = "/autoinvite"
SLASH_AUTOINVITEPLUS3 = "/ai"

