-- AutoInvite Plus - Core Module
-- Combined and enhanced version for WotLK 3.3.5a
-- Original authors: Martag of Greymane, Matthias Fechner
-- Refactored with DRY principle and OOP patterns

local ADDON_NAME = "AutoInvitePlus"
local VERSION = "5.5.0"
local DB_VERSION = 5  -- Increment when saved variables structure changes (5.5: raid sessions, 5.4: mdps/rdps split, 4: loot history retention)

-- Create main addon namespace (may already exist from Utils.lua)
AutoInvitePlus = AutoInvitePlus or {}
local AIP = AutoInvitePlus

-- Store version info
AIP.Version = VERSION
AIP.DBVersion = DB_VERSION

-- Default saved variables structure
local defaults = {
    dbVersion = DB_VERSION,
    enabled = false,
    triggers = "invme-auto",
    spamMessage = 'LFM <raid> <roles> | <gs>+ | Whisper "<key>" for invite',
    maxRaiders = 25,
    useMaxLimit = false,
    autoRaid = true,
    guildOnly = false,
    useQueue = false,

    -- Auto-queue LFG players that match your LFM listing
    -- When enabled, players broadcasting LFG for your exact raid will be auto-queued
    -- (respects GS, iLvl, role needs, and class/spec requirements)
    autoQueueLFG = false,

    -- Player mode: "none", "lfm" (looking for members), "lfg" (looking for group)
    playerMode = "none",

    -- Listening channels
    listenWhisper = true,
    listenGuild = false,
    listenSay = false,
    listenYell = false,
    listenGeneral = false,
    listenTrade = false,
    listenLFG = false,
    listenDefense = false,
    listenGlobal = false,       -- Global channel (common on private servers)
    listenWorld = false,        -- World channel (common on private servers)
    listenCustom = false,
    customChannel = "",
    listenAllJoined = false,    -- Auto-listen to all joined channels

    -- Spam channels
    spamGeneral = false,
    spamSay = false,
    spamTrade = false,
    spamGuild = false,
    spamLFG = false,
    spamDefense = false,        -- Defense channel (LocalDefense)
    spamGlobal = false,         -- Global channel
    spamWorld = false,          -- World channel
    spamAllJoined = false,      -- Broadcast to all joined channels
    spamCustom = false,
    spamYell = false,
    spamChannels = {},  -- Dynamic custom channels {["ChannelName"] = true/false}

    -- Listen custom channels
    listenChannels = {},  -- Dynamic custom channels {["ChannelName"] = true/false}

    -- Blacklist
    blacklist = {},

    -- Whitelist/Favorites (priority players)
    whitelist = {},  -- {name = {name, note, addedTime, source}}

    -- Smart Auto-Invite Conditions
    smartInvite = {
        enabled = false,            -- Enable smart conditions (beyond just keyword)
        minGS = 0,                  -- Minimum GearScore (0 = no minimum)
        minIlvl = 0,                -- Minimum item level (0 = no minimum)
        requireRole = false,        -- Only invite if they specify a role
        roleMatching = false,       -- Only invite if we need their role
        acceptTanks = true,         -- Accept tank role
        acceptHealers = true,       -- Accept healer role
        acceptDPS = true,           -- Accept DPS role
        acceptClasses = {},         -- Empty = all classes, or specific: {WARRIOR = true, PALADIN = true}
        prioritizeFavorites = true, -- Favorites skip queue and get invited directly
        prioritizeGuild = false,    -- Guild members skip queue
    },

    -- Promote system
    promoteEnabled = false,
    promoteKey = "assist",
    promoteAutoAssist = true,

    -- Queue
    queue = {},
    queueTimeout = 0,               -- Auto-remove from queue after X minutes (0 = disabled)
    queueAutoProcess = false,       -- Auto-invite from queue when slots open
    queuePersist = true,            -- Save queue across reload/relog
    queueNotifyPosition = true,     -- Whisper position updates

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

    -- LFM/LFG Browser settings
    treeStaleTimeout = 180,     -- Hide tree entries older than this (seconds). Default: 3 min

    -- Raid Management (v5.3)
    raidWarningTemplates = {},      -- Custom raid warning templates
    reservedItems = "",             -- Reserved items list (multi-line)
    lootBans = {},                  -- Loot bans: {player, boss, item, itemLink}
    lootBannedPlayers = "",         -- (deprecated) Players banned from loot
    autoAnnounceReserved = false,   -- Auto-announce reserved items
    reservedAnnounceInterval = 5,   -- Minutes between announcements
    msTracking = {},                -- MS/OS tracking per player

    -- Loot History (v5.3)
    lootHistory = {},               -- Historical loot drops (legacy, migrated to raidSessions)
    lootTrackThreshold = 2,         -- Min item quality to track (2 = Green)
    lootHistoryRetentionDays = 30,  -- Days to keep loot history (0 = forever)
    currentRaidStartTime = nil,     -- Track when current raid session started (legacy)

    -- Raid Sessions (v5.5) - Enhanced loot tracking with boss kills and attendees
    raidSessions = {},              -- Array of raid session objects
    currentRaidSessionId = nil,     -- ID of active session
    nextRaidSessionId = 1,          -- Auto-increment ID for new sessions
    selectedRaidSessionId = nil,    -- Currently selected session in UI
    selectedBossId = nil,           -- Currently selected boss in UI
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
    if not AIP.db or not AIP.db.useMaxLimit then return false end

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

-- Check if player is in favorites/whitelist
local function IsPlayerFavorite(name)
    if not AIP.db or not AIP.db.whitelist or not name then return false, nil end
    local entry = AIP.db.whitelist[name:lower()]
    return entry ~= nil, entry
end

AIP.IsPlayerFavorite = IsPlayerFavorite

-- ============================================================================
-- PLAYER MODE FUNCTIONS (LFM vs LFG)
-- ============================================================================

-- Set the player's current mode
function AIP.SetPlayerMode(mode)
    if not AIP.db then return end
    local validModes = {none = true, lfm = true, lfg = true}
    if validModes[mode] then
        AIP.db.playerMode = mode
        Debug("Player mode set to: " .. mode)
        -- Update UI if available
        if AIP.CentralGUI and AIP.CentralGUI.UpdateModeIndicator then
            AIP.CentralGUI.UpdateModeIndicator()
        end
    end
end

-- Get the player's current mode
function AIP.GetPlayerMode()
    return AIP.db and AIP.db.playerMode or "none"
end

-- Check if in LFM mode (looking for members / leading)
function AIP.IsLFMMode()
    return AIP.GetPlayerMode() == "lfm"
end

-- Check if in LFG mode (looking for group / joining)
function AIP.IsLFGMode()
    return AIP.GetPlayerMode() == "lfg"
end

-- Add player to favorites/whitelist
function AIP.AddToFavorites(name, note, source)
    if not AIP.db then return false end
    if not AIP.db.whitelist then AIP.db.whitelist = {} end
    if not name or name:trim() == "" then return false end

    local properName = name:sub(1,1):upper() .. name:sub(2):lower()
    local lowerName = name:lower()

    AIP.db.whitelist[lowerName] = {
        name = properName,
        note = note or "",
        addedTime = time(),
        source = source or "manual",
    }

    Print("Added " .. properName .. " to favorites")
    return true
end

-- Remove player from favorites
function AIP.RemoveFromFavorites(name)
    if not AIP.db or not AIP.db.whitelist or not name then return false end
    local lowerName = name:lower()
    if AIP.db.whitelist[lowerName] then
        AIP.db.whitelist[lowerName] = nil
        Print("Removed " .. name .. " from favorites")
        return true
    end
    return false
end

-- Get player info from message (role, class, GS)
local function ParsePlayerInfo(author, message)
    local info = {
        name = author,
        message = message,
        role = nil,
        class = nil,
        gs = nil,
    }

    -- Try to detect role from message using Parsers
    if AIP.Parsers and AIP.Parsers.DetectRole then
        info.role = AIP.Parsers.DetectRole(message)
    end

    -- Try to detect GearScore from message
    if AIP.Parsers and AIP.Parsers.ParseGearScore then
        info.gs = AIP.Parsers.ParseGearScore(message)
    end

    -- Try to get GS from GearScore addon if available
    if not info.gs and AIP.Integrations and AIP.Integrations.GetPlayerGS then
        info.gs = AIP.Integrations.GetPlayerGS(author)
    end

    return info
end

-- Check if player meets smart invite conditions
local function CheckSmartConditions(playerInfo)
    local smart = AIP.db.smartInvite
    if not smart or not smart.enabled then
        return true, nil  -- Smart conditions disabled, allow all
    end

    -- Check minimum GearScore
    if smart.minGS and smart.minGS > 0 then
        if not playerInfo.gs or playerInfo.gs < smart.minGS then
            return false, "GearScore too low (need " .. smart.minGS .. "+)"
        end
    end

    -- Check if role is required
    if smart.requireRole and not playerInfo.role then
        return false, "No role specified in message"
    end

    -- Check role acceptance
    if playerInfo.role then
        local roleUpper = playerInfo.role:upper()
        if roleUpper == "TANK" and not smart.acceptTanks then
            return false, "Not accepting tanks"
        elseif roleUpper == "HEALER" and not smart.acceptHealers then
            return false, "Not accepting healers"
        elseif roleUpper == "DPS" and not smart.acceptDPS then
            return false, "Not accepting DPS"
        end
    end

    -- Check role matching (only invite if we need that role)
    if smart.roleMatching and playerInfo.role then
        if AIP.Composition and AIP.Composition.GetRoleNeeds then
            local needs = AIP.Composition.GetRoleNeeds()
            local roleUpper = playerInfo.role:upper()
            if roleUpper == "TANK" and (needs.tanks or 0) <= 0 then
                return false, "No tank slots available"
            elseif roleUpper == "HEALER" and (needs.healers or 0) <= 0 then
                return false, "No healer slots available"
            elseif roleUpper == "DPS" and (needs.dps or 0) <= 0 then
                return false, "No DPS slots available"
            end
        end
    end

    -- Check class/spec matching against Looking For preferences
    -- Only check if we have an active LFM with roleSpecs defined
    if smart.roleMatching then
        local GUI = AIP.CentralGUI or {}
        local myGroup = GUI.MyGroup
        if myGroup and myGroup.roleSpecs then
            local hasAnySpecs = false
            for role, specs in pairs(myGroup.roleSpecs) do
                if specs and #specs > 0 then
                    hasAnySpecs = true
                    break
                end
            end

            -- Only enforce if roleSpecs are defined
            if hasAnySpecs and playerInfo.class then
                local playerClass = playerInfo.class:upper()
                local playerRole = playerInfo.role and playerInfo.role:upper() or nil

                -- Use the parser's matching function
                if AIP.Parsers and AIP.Parsers.MatchesLookingFor then
                    local matches = AIP.Parsers.MatchesLookingFor(playerClass, nil, playerRole, myGroup.roleSpecs)
                    if not matches then
                        -- Build helpful rejection message
                        local wantedClasses = {}
                        local rolesToCheck = {}
                        if playerRole == "TANK" then
                            rolesToCheck = {"TANK"}
                        elseif playerRole == "HEALER" then
                            rolesToCheck = {"HEALER"}
                        elseif playerRole == "DPS" then
                            rolesToCheck = {"MDPS", "RDPS"}
                        else
                            rolesToCheck = {"TANK", "HEALER", "MDPS", "RDPS"}
                        end

                        for _, role in ipairs(rolesToCheck) do
                            local specs = myGroup.roleSpecs[role]
                            if specs then
                                for _, code in ipairs(specs) do
                                    local info = AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                                    if info then
                                        wantedClasses[info.shortClass] = true
                                    end
                                end
                            end
                        end

                        local wantedList = {}
                        for cls in pairs(wantedClasses) do
                            table.insert(wantedList, cls)
                        end

                        if #wantedList > 0 then
                            return false, "Looking for: " .. table.concat(wantedList, ", ")
                        else
                            return false, "Class/spec not in Looking For list"
                        end
                    end
                end
            end
        end
    end

    -- Check class restrictions
    if smart.acceptClasses and next(smart.acceptClasses) then
        if playerInfo.class then
            local classUpper = playerInfo.class:upper()
            if not smart.acceptClasses[classUpper] then
                return false, "Class not accepted"
            end
        end
    end

    return true, nil
end

-- Process incoming message for invite triggers
local function ProcessMessage(author, message, channel)
    if not AIP.db then
        Debug("ProcessMessage: db not initialized")
        return
    end

    -- Check player mode - in LFG mode, don't auto-invite anyone (we're looking for a group)
    local mode = AIP.GetPlayerMode()
    if mode == "lfg" then
        Debug("ProcessMessage: skipped - in LFG mode (looking for group, not inviting)")
        return
    end

    -- Check if either auto-invite or queue mode is active
    local autoInviteActive = AIP.db.enabled
    local queueModeActive = AIP.db.useQueue

    -- If neither mode is active, skip processing
    if not autoInviteActive and not queueModeActive then
        Debug("ProcessMessage: both auto-invite and queue mode disabled")
        return
    end

    if not author or author == "" then return end
    if author:lower() == UnitName("player"):lower() then return end

    -- Skip LFM messages - they contain trigger keywords as advertisement, not as request
    -- Check for common LFM patterns to avoid adding raid leaders to queue
    local msgLower = message:lower()
    if msgLower:match("^lfm%s") or msgLower:match("%slfm%s") or
       msgLower:match("lf%d+m") or msgLower:match('w/%s*"') or
       msgLower:match("%[t:%d+/%d+") then
        Debug("ProcessMessage: skipping LFM message from " .. author)
        return
    end

    -- Check if message contains trigger
    if not CheckTriggers(message) then
        Debug("ProcessMessage: no trigger in '" .. message .. "'")
        return
    end

    Print("Trigger matched from " .. author .. " via " .. channel)

    -- Parse player info from message
    local playerInfo = ParsePlayerInfo(author, message)

    -- Check if player is a favorite (priority handling)
    local isFavorite, favoriteEntry = IsPlayerFavorite(author)
    local isGuildMember = IsPlayerInGuild(author)
    local smart = AIP.db.smartInvite or {}

    -- Check smart invite conditions
    local meetsConditions, rejectReason = CheckSmartConditions(playerInfo)

    if not meetsConditions then
        -- Player doesn't meet conditions
        Debug("ProcessMessage: " .. author .. " rejected - " .. (rejectReason or "unknown"))
        if AIP.db.responseReject and AIP.db.responseReject ~= "" then
            local msg = rejectReason and ("[AutoInvite+] " .. rejectReason) or AIP.db.responseReject
            SendChatMessage(msg, "WHISPER", nil, author)
        end
        return
    end

    -- Determine if player should skip queue (priority players)
    local skipQueue = false
    if smart.prioritizeFavorites and isFavorite then
        skipQueue = true
        Debug("ProcessMessage: " .. author .. " is a favorite, skipping queue")
    elseif smart.prioritizeGuild and isGuildMember then
        skipQueue = true
        Debug("ProcessMessage: " .. author .. " is a guild member, skipping queue")
    end

    -- Process based on mode
    if queueModeActive and not skipQueue and AIP.AddToQueue then
        -- Add to queue with player info
        AIP.AddToQueue(author, message, playerInfo.role, playerInfo.gs, playerInfo.class)
    elseif autoInviteActive or skipQueue then
        -- Direct invite (priority players or auto-invite mode)
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
    -- Escape special pattern characters in triggers to avoid gsub errors
    local triggers = AIP.db.triggers:gsub(";", " or ")
    -- Use plain string replacement to avoid pattern interpretation
    msg = msg:gsub("<key>", function() return triggers end)

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
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "LFG"})
            delay = delay + delayIncrement
        end
    end

    if AIP.db.spamTrade then
        local id = FindChannelId("trade")
        if id then
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "Trade"})
            delay = delay + delayIncrement
        end
    end

    if AIP.db.spamGeneral then
        local id = FindChannelId("general")
        if id then
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "General"})
            delay = delay + delayIncrement
        end
    end

    if AIP.db.spamDefense then
        local id = FindChannelId("localdefense", "defense")
        if id then
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "Defense"})
            delay = delay + delayIncrement
        end
    end

    -- Global channel (common on private servers)
    if AIP.db.spamGlobal then
        local id = FindChannelId("global")
        if id then
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "Global"})
            delay = delay + delayIncrement
        end
    end

    -- World channel (common on private servers)
    if AIP.db.spamWorld then
        local id = FindChannelId("world")
        if id then
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
                SendChatMessage(msg, "CHANNEL", nil, id)
            end, name = "World"})
            delay = delay + delayIncrement
        end
    end

    -- All Joined channels (broadcast to every channel we're in)
    if AIP.db.spamAllJoined then
        -- Track which channel IDs we've already added to avoid duplicates
        local addedIds = {}
        for _, entry in ipairs(messageQueue) do
            if entry.channelId then
                addedIds[entry.channelId] = true
            end
        end

        -- Iterate through all joined channels
        for i = 1, 20 do
            local id, name = GetChannelName(i)
            if id and id > 0 and name and name ~= "" then
                -- Skip if already added by specific channel settings
                if not addedIds[id] then
                    local channelId = id
                    local channelName = name
                    table.insert(messageQueue, {delay = delay, func = function()
                        SendChatMessage(msg, "CHANNEL", nil, channelId)
                    end, name = channelName, channelId = channelId})
                    delay = delay + delayIncrement
                    addedIds[id] = true
                end
            end
        end
    end

    -- Custom channels from db.spamChannels list
    if AIP.db.spamChannels then
        for channelName, enabled in pairs(AIP.db.spamChannels) do
            if enabled then
                local id = GetChannelName(channelName)
                if id and id > 0 then
                    table.insert(messageQueue, {delay = delay, channelId = id, func = function()
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
            table.insert(messageQueue, {delay = delay, channelId = id, func = function()
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
            -- Check DB version and handle migration
            local needsReset = false
            if AutoInvitePlusDB then
                local savedVersion = AutoInvitePlusDB.dbVersion or 1
                if savedVersion < DB_VERSION then
                    Print("|cFFFFFF00Upgrading saved data from v" .. savedVersion .. " to v" .. DB_VERSION .. "|r")
                    -- Perform migrations here if needed
                    -- For now, just merge new defaults
                    AutoInvitePlusDB.dbVersion = DB_VERSION
                end
            else
                AutoInvitePlusDB = {}
            end

            -- Deep copy function for nested tables
            local function deepCopy(orig)
                if type(orig) ~= "table" then return orig end
                local copy = {}
                for k, v in pairs(orig) do
                    copy[k] = deepCopy(v)
                end
                return copy
            end

            -- Merge defaults with saved data (preserves user settings)
            for k, v in pairs(defaults) do
                if AutoInvitePlusDB[k] == nil then
                    AutoInvitePlusDB[k] = deepCopy(v)
                end
            end

            AIP.db = AutoInvitePlusDB

            -- Initialize Utils event system if available
            if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Init then
                AIP.Utils.Events.Init()
            end

            -- Apply saved tree browser settings
            if AIP.TreeBrowser then
                if AIP.db.treeStaleTimeout then
                    AIP.TreeBrowser.StaleTimeout = AIP.db.treeStaleTimeout
                end
            end

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

        -- Skip DataBus addon channel (it's for addon communication only)
        if AIP.DataBus and AIP.DataBus.Config and channelLower:find(AIP.DataBus.Config.channelName:lower()) then
            return
        end

        local processed = false

        -- Standard channels
        if channelLower:find("general") and AIP.db.listenGeneral then
            ProcessMessage(author, message, "general")
            processed = true
        elseif channelLower:find("trade") and AIP.db.listenTrade then
            ProcessMessage(author, message, "trade")
            processed = true
        elseif (channelLower:find("lookingforgroup") or channelLower:find("lfg")) and AIP.db.listenLFG then
            ProcessMessage(author, message, "lfg")
            processed = true
        elseif (channelLower:find("localdefense") or channelLower:find("defense")) and AIP.db.listenDefense then
            ProcessMessage(author, message, "defense")
            processed = true
        -- Global channel (common on private servers)
        elseif (channelLower:find("global") or channelLower == "global") and AIP.db.listenGlobal then
            ProcessMessage(author, message, "global")
            processed = true
        -- World channel (common on private servers)
        elseif (channelLower:find("world") or channelLower == "world") and AIP.db.listenWorld then
            ProcessMessage(author, message, "world")
            processed = true
        end

        -- If not processed by standard channels, check custom channels
        if not processed then
            -- Check custom listen channels
            if AIP.db.listenChannels then
                for chName, enabled in pairs(AIP.db.listenChannels) do
                    if enabled and channelLower:find(chName:lower()) then
                        ProcessMessage(author, message, "custom:" .. chName)
                        processed = true
                        break
                    end
                end
            end

            -- Legacy custom channel support
            if not processed and AIP.db.listenCustom and AIP.db.customChannel and AIP.db.customChannel ~= "" then
                if channelLower:find(AIP.db.customChannel:lower()) then
                    ProcessMessage(author, message, "custom")
                    processed = true
                end
            end

            -- Listen to all joined channels option
            if not processed and AIP.db.listenAllJoined then
                ProcessMessage(author, message, "channel:" .. channelName)
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

    -- DataBus (addon-to-addon communication)
    elseif cmd == "databus" or cmd == "db" or cmd == "net" then
        if AIP.DataBus then
            AIP.DataBus.SlashHandler(rest)
        else
            AIP.Print("DataBus module not loaded")
        end

    -- Test Data (for UI development/testing)
    elseif cmd == "testdata" or cmd == "test" then
        if AIP.TestData then
            AIP.TestData.LoadTestData()
        else
            Print("TestData module not loaded")
        end
    elseif cmd == "cleartest" or cmd == "cleartestdata" then
        if AIP.TestData then
            AIP.TestData.ClearTestData()
        else
            Print("TestData module not loaded")
        end
    elseif cmd == "testloot" then
        if AIP.Panels and AIP.Panels.LootHistory then
            AIP.Panels.LootHistory.LoadTestData()
        else
            Print("LootHistory panel not loaded")
        end
    elseif cmd == "cleartestloot" then
        if AIP.Panels and AIP.Panels.LootHistory then
            AIP.Panels.LootHistory.ClearTestData()
        else
            Print("LootHistory panel not loaded")
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
        Print("|cFFFFFF00DataBus (Addon Network):|r")
        Print("  /aip databus - Show network status")
        Print("  /aip databus peers - List online addon users")
        Print("  /aip databus ping - Discover nearby users")
        Print("|cFFFFFF00Development:|r")
        Print("  /aip testdata - Load test data for UI preview")
        Print("  /aip cleartest - Clear test data (preserves real data)")
        Print("  /aip testloot - Load loot history test data")
        Print("  /aip cleartestloot - Clear loot history test data")

    else
        Print("Unknown command. Type /aip help for options.")
    end
end

SlashCmdList["AUTOINVITEPLUS"] = SlashHandler
SLASH_AUTOINVITEPLUS1 = "/aip"
SLASH_AUTOINVITEPLUS2 = "/autoinvite"
SLASH_AUTOINVITEPLUS3 = "/ai"

