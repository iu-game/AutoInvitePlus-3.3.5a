-- AutoInvite Plus - DataBus Module
-- Inter-player communication system for addon users
-- Broadcasts and receives structured events over addon channels

local AIP = AutoInvitePlus
AIP.DataBus = {}
local DB = AIP.DataBus

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

DB.Config = {
    prefix = "AIP",                    -- Addon message prefix (max 16 chars)
    version = "1.0",                   -- Protocol version
    channelName = "AIPSync",           -- Custom channel for cross-guild communication
    channelPassword = "aip335",        -- Password to keep channel semi-private
    chatPrefix = "!A:",                -- Prefix for chat channel messages (short to save space)
    maxMessageLength = 255,            -- WoW chat limit
    eventTTL = 600,                    -- Events expire after 10 minutes
    pruneInterval = 60,                -- Prune every 60 seconds
    rateLimitInterval = 2,             -- Min seconds between broadcasts of same type
    channelRateLimit = 5,              -- Min seconds between channel broadcasts (avoid spam)
    enabled = true,
    useChannelFallback = true,         -- Use chat channel for cross-guild communication
}

-- ============================================================================
-- EVENT TYPE DEFINITIONS
-- ============================================================================
-- Each event type defines the structure of data it carries

DB.EventTypes = {
    -- LFM: Group leader advertising for members
    LFM = {
        id = "LFM",
        name = "Looking For More",
        fields = {
            "raid",         -- string: raid identifier (ICC25HC, VOA10, etc.)
            "tanks",        -- table: {current, needed}
            "healers",      -- table: {current, needed}
            "mdps",         -- table: {current, needed} - melee DPS
            "rdps",         -- table: {current, needed} - ranged DPS
            "gsMin",        -- number: minimum GearScore required
            "ilvlMin",      -- number: minimum item level (optional)
            "note",         -- string: custom message/requirements
            "triggerKey",   -- string: whisper keyword for invite
            "achievements", -- string: achievement links (optional)
        },
    },

    -- LFG: Individual player looking for a group
    LFG = {
        id = "LFG",
        name = "Looking For Group",
        fields = {
            "raids",        -- table: list of raid IDs interested in
            "role",         -- string: TANK, HEALER, MDPS, RDPS
            "class",        -- string: player class
            "spec",         -- string: talent spec name
            "gs",           -- number: player's GearScore
            "ilvl",         -- number: player's average item level
            "note",         -- string: custom message
            "achievements", -- string: achievement links (optional)
        },
    },

    -- PING: Heartbeat to discover other addon users
    PING = {
        id = "PING",
        name = "Presence Ping",
        fields = {
            "version",      -- string: addon version
        },
    },

    -- PONG: Response to ping
    PONG = {
        id = "PONG",
        name = "Presence Response",
        fields = {
            "version",      -- string: addon version
        },
    },
}

-- ============================================================================
-- STATE
-- ============================================================================

DB.State = {
    initialized = false,
    channelId = nil,                   -- Custom channel ID if joined
    channelReady = false,              -- True when channel is confirmed joined
    subscribers = {},                  -- {eventType = {callback1, callback2, ...}}
    receivedEvents = {},               -- {senderId = {eventType = eventData}}
    lastBroadcast = {},                -- {eventType = timestamp} for rate limiting
    lastChannelBroadcast = 0,          -- Timestamp of last channel message (separate rate limit)
    onlinePeers = {},                  -- {playerName = {version, lastSeen}}
    channelJoinAttempts = 0,           -- Backoff: number of failed join attempts
    lastChannelJoinAttempt = 0,        -- Backoff: time of last join attempt
}

-- ============================================================================
-- SERIALIZATION (Simple, WoW 3.3.5a chat-safe)
-- Uses ^ as escape character instead of \ (WoW chat rejects backslash escapes)
-- ============================================================================

-- Encode a value to string (chat-safe)
local function EncodeValue(val)
    local t = type(val)
    if t == "nil" then
        return "N"
    elseif t == "boolean" then
        return val and "T" or "F"
    elseif t == "number" then
        return "n" .. tostring(val)
    elseif t == "string" then
        -- Escape special chars using ^ (chat-safe, no backslash)
        local escaped = val:gsub("%^", "^^"):gsub("|", "^P"):gsub("~", "^T"):gsub("\n", "^N")
        return "s" .. escaped
    elseif t == "table" then
        local parts = {}
        local isArray = true
        local maxIndex = 0

        -- Check if it's an array
        for k, v in pairs(val) do
            if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
                isArray = false
                break
            end
            if k > maxIndex then maxIndex = k end
        end

        if isArray and maxIndex > 0 then
            -- Encode as array
            for i = 1, maxIndex do
                table.insert(parts, EncodeValue(val[i]))
            end
            return "a" .. #parts .. "~" .. table.concat(parts, "~")
        else
            -- Encode as dictionary
            for k, v in pairs(val) do
                table.insert(parts, EncodeValue(k) .. "~" .. EncodeValue(v))
            end
            return "d" .. #parts .. "~" .. table.concat(parts, "~")
        end
    end
    return "N"
end

-- Decode a value from string, returns value and next position
local function DecodeValue(str, pos)
    pos = pos or 1
    if pos > #str then return nil, pos end

    local prefix = str:sub(pos, pos)
    pos = pos + 1

    if prefix == "N" then
        return nil, pos
    elseif prefix == "T" then
        return true, pos
    elseif prefix == "F" then
        return false, pos
    elseif prefix == "n" then
        local endPos = str:find("~", pos) or (#str + 1)
        local numStr = str:sub(pos, endPos - 1)
        return tonumber(numStr), endPos + 1
    elseif prefix == "s" then
        local result = ""
        local i = pos
        while i <= #str do
            local c = str:sub(i, i)
            if c == "~" then
                break
            elseif c == "^" and i < #str then
                -- Chat-safe escape sequences using ^
                local next = str:sub(i + 1, i + 1)
                if next == "^" then result = result .. "^"
                elseif next == "P" then result = result .. "|"
                elseif next == "T" then result = result .. "~"
                elseif next == "N" then result = result .. "\n"
                else result = result .. next
                end
                i = i + 2
            elseif c == "\\" and i < #str then
                -- Legacy backslash escapes (for backwards compatibility)
                local next = str:sub(i + 1, i + 1)
                if next == "\\" then result = result .. "\\"
                elseif next == "p" then result = result .. "|"
                elseif next == "t" then result = result .. "~"
                elseif next == "n" then result = result .. "\n"
                else result = result .. next
                end
                i = i + 2
            else
                result = result .. c
                i = i + 1
            end
        end
        return result, i
    elseif prefix == "a" then
        -- Array
        local countEnd = str:find("~", pos)
        if not countEnd then return {}, pos end
        local count = tonumber(str:sub(pos, countEnd - 1)) or 0
        pos = countEnd + 1
        local arr = {}
        for i = 1, count do
            local val
            val, pos = DecodeValue(str, pos)
            arr[i] = val
            if str:sub(pos, pos) == "~" then pos = pos + 1 end
        end
        return arr, pos
    elseif prefix == "d" then
        -- Dictionary
        local countEnd = str:find("~", pos)
        if not countEnd then return {}, pos end
        local count = tonumber(str:sub(pos, countEnd - 1)) or 0
        pos = countEnd + 1
        local dict = {}
        for i = 1, count do
            local key, val
            key, pos = DecodeValue(str, pos)
            if str:sub(pos, pos) == "~" then pos = pos + 1 end
            val, pos = DecodeValue(str, pos)
            if str:sub(pos, pos) == "~" then pos = pos + 1 end
            if key ~= nil then
                dict[key] = val
            end
        end
        return dict, pos
    end

    return nil, pos
end

-- Serialize an event to a transmittable string
function DB.Serialize(event)
    if not event or not event.type then return nil end

    -- Format: VERSION;TYPE;TIMESTAMP;DATA (using ; instead of | for chat safety)
    local parts = {
        DB.Config.version,
        event.type,
        tostring(event.timestamp or time()),
        EncodeValue(event.data or {}),
    }

    return table.concat(parts, ";")
end

-- Deserialize a string back to an event
function DB.Deserialize(str, sender)
    if not str then return nil end

    -- Try new format with ; separator first
    local version, eventType, timestamp, dataStr = strsplit(";", str, 4)

    -- Fallback to legacy | separator for backwards compatibility
    if not eventType or eventType == "" then
        version, eventType, timestamp, dataStr = strsplit("|", str, 4)
    end

    if not version or not eventType then return nil end

    -- Version check (allow same major version)
    local majorVer = version:match("^(%d+)")
    local ourMajor = DB.Config.version:match("^(%d+)")
    if majorVer ~= ourMajor then
        return nil -- Incompatible version
    end

    -- Decode data
    local data = nil
    if dataStr then
        data = DecodeValue(dataStr, 1)
    end

    return {
        type = eventType,
        version = version,
        sender = sender,
        timestamp = tonumber(timestamp) or time(),
        data = data or {},
    }
end

-- ============================================================================
-- EVENT MANAGEMENT
-- ============================================================================

-- Subscribe to an event type
function DB.Subscribe(eventType, callback, owner)
    if not eventType or not callback then return false end

    if not DB.State.subscribers[eventType] then
        DB.State.subscribers[eventType] = {}
    end

    table.insert(DB.State.subscribers[eventType], {
        callback = callback,
        owner = owner,
    })

    return true
end

-- Unsubscribe from an event type
function DB.Unsubscribe(eventType, callback)
    if not eventType or not DB.State.subscribers[eventType] then return false end

    for i = #DB.State.subscribers[eventType], 1, -1 do
        if DB.State.subscribers[eventType][i].callback == callback then
            table.remove(DB.State.subscribers[eventType], i)
            return true
        end
    end

    return false
end

-- Unsubscribe all callbacks for an owner
function DB.UnsubscribeAll(owner)
    for eventType, subs in pairs(DB.State.subscribers) do
        for i = #subs, 1, -1 do
            if subs[i].owner == owner then
                table.remove(subs, i)
            end
        end
    end
end

-- Dispatch event to all subscribers
local function DispatchEvent(event)
    if not event or not event.type then return end

    local subs = DB.State.subscribers[event.type]
    if not subs then return end

    for _, sub in ipairs(subs) do
        local success, err = pcall(sub.callback, event)
        if not success and AIP.Debug then
            AIP.Debug("DataBus dispatch error: " .. tostring(err))
        end
    end

    -- Also dispatch to wildcard subscribers
    local wildcardSubs = DB.State.subscribers["*"]
    if wildcardSubs then
        for _, sub in ipairs(wildcardSubs) do
            local success, err = pcall(sub.callback, event)
            if not success and AIP.Debug then
                AIP.Debug("DataBus wildcard dispatch error: " .. tostring(err))
            end
        end
    end
end

-- Store received event
local function StoreEvent(event)
    if not event or not event.sender or not event.type then return end

    local sender = event.sender
    if not DB.State.receivedEvents[sender] then
        DB.State.receivedEvents[sender] = {}
    end

    DB.State.receivedEvents[sender][event.type] = event
end

-- ============================================================================
-- BROADCASTING
-- ============================================================================

-- Create an event with proper structure
function DB.CreateEvent(eventType, data)
    if not DB.EventTypes[eventType] then
        AIP.Debug("DataBus: Unknown event type: " .. tostring(eventType))
        return nil
    end

    return {
        type = eventType,
        timestamp = time(),
        data = data or {},
    }
end

-- Broadcast an event to all addon users
function DB.Broadcast(event, target)
    if not DB.Config.enabled then return false end
    if not event or not event.type then return false end

    -- Rate limiting
    local now = GetTime()
    local lastTime = DB.State.lastBroadcast[event.type] or 0
    if now - lastTime < DB.Config.rateLimitInterval then
        return false, "rate_limited"
    end
    DB.State.lastBroadcast[event.type] = now

    -- Serialize
    local message = DB.Serialize(event)
    if not message then return false, "serialize_failed" end

    -- Check message length
    if #message > DB.Config.maxMessageLength then
        AIP.Debug("DataBus: Message too long (" .. #message .. " chars)")
        return false, "message_too_long"
    end

    -- Send via appropriate channels
    local sent = false

    -- Send to raid/party if in one
    if GetNumRaidMembers() > 0 then
        SendAddonMessage(DB.Config.prefix, message, "RAID")
        sent = true
    elseif GetNumPartyMembers() > 0 then
        SendAddonMessage(DB.Config.prefix, message, "PARTY")
        sent = true
    end

    -- Send to guild if in one
    if IsInGuild() then
        SendAddonMessage(DB.Config.prefix, message, "GUILD")
        sent = true
    end

    -- Send via custom chat channel for cross-guild communication (3.3.5a compatible)
    -- This uses regular chat messages with a prefix, not addon messages
    if DB.Config.useChannelFallback and DB.State.channelReady then
        local channelSent = DB.SendChannelMessage(message)
        if channelSent then
            sent = true
        end
    end

    -- Send to specific target (whisper)
    if target then
        SendAddonMessage(DB.Config.prefix, message, "WHISPER", target)
        sent = true
    end

    if sent and AIP.Debug then
        AIP.Debug("DataBus: Broadcast " .. event.type)
    end

    return sent
end

-- Convenience: Broadcast LFM event
function DB.BroadcastLFM(lfmData)
    local event = DB.CreateEvent("LFM", lfmData)
    if not event then return false end

    -- Add defaults
    event.data.triggerKey = event.data.triggerKey or (AIP.db and AIP.db.triggers) or "inv"

    return DB.Broadcast(event)
end

-- Convenience: Broadcast LFG event
function DB.BroadcastLFG(lfgData)
    local event = DB.CreateEvent("LFG", lfgData)
    if not event then return false end

    -- Add player info defaults
    local _, playerClass = UnitClass("player")
    event.data.class = event.data.class or playerClass

    -- Try to get GS from integrations
    if AIP.Integrations and AIP.Integrations.GetPlayerGS then
        event.data.gs = event.data.gs or AIP.Integrations.GetPlayerGS(UnitName("player"))
    end

    return DB.Broadcast(event)
end

-- ============================================================================
-- RECEIVING
-- ============================================================================

-- Handle incoming addon message
local function OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= DB.Config.prefix then return end
    if not message or message == "" then return end

    -- Don't process our own messages
    if sender == UnitName("player") then return end

    -- Deserialize
    local event = DB.Deserialize(message, sender)
    if not event then
        AIP.Debug("DataBus: Failed to deserialize from " .. sender)
        return
    end

    -- Store and dispatch
    StoreEvent(event)
    DispatchEvent(event)

    -- Track peer for all event types (they're all addon users)
    local peerVersion = event.data and event.data.version or event.version or "unknown"
    DB.State.onlinePeers[sender] = {
        version = peerVersion,
        lastSeen = time(),
    }

    -- Respond to PING with PONG
    if event.type == "PING" then
        local pong = DB.CreateEvent("PONG", {version = AIP.Version or "5.0"})
        DB.Broadcast(pong, sender)
    end
end

-- ============================================================================
-- QUERY FUNCTIONS
-- ============================================================================

-- Get all received LFM events
function DB.GetLFMListings()
    local results = {}
    local now = time()

    for sender, events in pairs(DB.State.receivedEvents) do
        local lfm = events.LFM
        if lfm and (now - lfm.timestamp) < DB.Config.eventTTL then
            lfm.sender = sender
            table.insert(results, lfm)
        end
    end

    -- Sort by timestamp (newest first)
    table.sort(results, function(a, b)
        return a.timestamp > b.timestamp
    end)

    return results
end

-- Get all received LFG events
function DB.GetLFGListings()
    local results = {}
    local now = time()

    for sender, events in pairs(DB.State.receivedEvents) do
        local lfg = events.LFG
        if lfg and (now - lfg.timestamp) < DB.Config.eventTTL then
            lfg.sender = sender
            table.insert(results, lfg)
        end
    end

    -- Sort by timestamp (newest first)
    table.sort(results, function(a, b)
        return a.timestamp > b.timestamp
    end)

    return results
end

-- Get online peers
function DB.GetOnlinePeers()
    local results = {}
    local now = time()

    for name, info in pairs(DB.State.onlinePeers) do
        if (now - info.lastSeen) < 300 then -- 5 min timeout
            table.insert(results, {
                name = name,
                version = info.version,
                lastSeen = info.lastSeen,
            })
        end
    end

    return results
end

-- Get count of online peers
function DB.GetPeerCount()
    local count = 0
    local now = time()

    for name, info in pairs(DB.State.onlinePeers) do
        if (now - info.lastSeen) < 300 then
            count = count + 1
        end
    end

    return count
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

-- Prune expired events
function DB.Prune()
    local now = time()
    local pruned = 0

    for sender, events in pairs(DB.State.receivedEvents) do
        for eventType, event in pairs(events) do
            if (now - event.timestamp) > DB.Config.eventTTL then
                events[eventType] = nil
                pruned = pruned + 1
            end
        end

        -- Remove sender if no events left
        local hasEvents = false
        for _ in pairs(events) do
            hasEvents = true
            break
        end
        if not hasEvents then
            DB.State.receivedEvents[sender] = nil
        end
    end

    -- Prune offline peers
    for name, info in pairs(DB.State.onlinePeers) do
        if (now - info.lastSeen) > 300 then
            DB.State.onlinePeers[name] = nil
        end
    end

    return pruned
end

-- ============================================================================
-- CUSTOM CHANNEL MANAGEMENT
-- ============================================================================

-- Join the addon communication channel
-- Uses regular chat channel (not addon messages) for cross-guild communication in 3.3.5a
function DB.JoinChannel()
    if not DB.Config.useChannelFallback then return false end

    -- Check if already joined
    local id = GetChannelName(DB.Config.channelName)
    if id and id > 0 then
        DB.State.channelId = id
        DB.State.channelReady = true
        AIP.Debug("DataBus: Already on channel " .. DB.Config.channelName .. " (id: " .. id .. ")")
        return true
    end

    -- Join with password to keep semi-private
    JoinTemporaryChannel(DB.Config.channelName, DB.Config.channelPassword)

    -- Schedule verification (JoinTemporaryChannel is async)
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(1, function()
            local retryId = GetChannelName(DB.Config.channelName)
            if retryId and retryId > 0 then
                DB.State.channelId = retryId
                DB.State.channelReady = true
                DB.State.channelJoinAttempts = 0
                AIP.Debug("DataBus: Joined channel " .. DB.Config.channelName .. " (id: " .. retryId .. ")")
                -- Send initial ping after joining
                DB.SendPing()
            else
                DB.State.channelJoinAttempts = (DB.State.channelJoinAttempts or 0) + 1
                AIP.Debug("DataBus: Failed to join channel, attempt " .. DB.State.channelJoinAttempts)
            end
        end)
    end

    return false  -- Will be true after async verification
end

-- Leave the addon communication channel
function DB.LeaveChannel()
    if DB.State.channelId then
        LeaveChannelByName(DB.Config.channelName)
        DB.State.channelId = nil
        DB.State.channelReady = false
    end
end

-- Send a message via the chat channel (for cross-guild communication)
function DB.SendChannelMessage(message)
    if not DB.Config.useChannelFallback then return false end
    if not DB.State.channelReady or not DB.State.channelId then return false end

    -- Rate limit channel messages more strictly to avoid spam
    local now = GetTime()
    if now - (DB.State.lastChannelBroadcast or 0) < DB.Config.channelRateLimit then
        return false, "channel_rate_limited"
    end
    DB.State.lastChannelBroadcast = now

    -- Prefix with our marker so we can identify addon messages
    local fullMessage = DB.Config.chatPrefix .. message

    -- Check length
    if #fullMessage > DB.Config.maxMessageLength then
        AIP.Debug("DataBus: Channel message too long")
        return false, "message_too_long"
    end

    -- Send via chat channel
    SendChatMessage(fullMessage, "CHANNEL", nil, DB.State.channelId)
    return true
end

-- Send a PING to discover peers
function DB.SendPing()
    local ping = DB.CreateEvent("PING", {version = AIP.Version or "5.0"})
    if ping then
        DB.Broadcast(ping)
    end
end

-- Handle incoming chat channel message (for cross-guild communication)
local function OnChannelMessage(message, sender, _, _, _, _, _, _, channelName)
    -- Check if this is our addon message (starts with our prefix)
    if not message or not DB.Config.chatPrefix then return end
    if not message:find("^" .. DB.Config.chatPrefix:gsub("([^%w])", "%%%1")) then return end

    -- Check if it's from our channel
    if channelName and not channelName:lower():find(DB.Config.channelName:lower()) then return end

    -- Don't process our own messages
    if sender == UnitName("player") then return end

    -- Extract the actual message (remove prefix)
    local addonMessage = message:sub(#DB.Config.chatPrefix + 1)
    if not addonMessage or addonMessage == "" then return end

    -- Process as if it were an addon message
    local event = DB.Deserialize(addonMessage, sender)
    if not event then
        AIP.Debug("DataBus: Failed to deserialize channel message from " .. tostring(sender))
        return
    end

    -- Store and dispatch
    StoreEvent(event)
    DispatchEvent(event)

    -- Track peer
    local peerVersion = event.data and event.data.version or event.version or "unknown"
    DB.State.onlinePeers[sender] = {
        version = peerVersion,
        lastSeen = time(),
    }

    -- Respond to PING with PONG
    if event.type == "PING" then
        local pong = DB.CreateEvent("PONG", {version = AIP.Version or "5.0"})
        DB.Broadcast(pong, sender)
    end
end

-- Chat filter to hide our addon messages from chat frames
local function ChatFilter(self, event, message, sender, ...)
    if message and DB.Config.chatPrefix then
        if message:find("^" .. DB.Config.chatPrefix:gsub("([^%w])", "%%%1")) then
            return true  -- Hide this message
        end
    end
    return false
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local eventFrame = CreateFrame("Frame", "AIPDataBusFrame")

local function OnEvent(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        OnAddonMessage(prefix, message, channel, sender)

    elseif event == "CHAT_MSG_CHANNEL" then
        local message, sender, _, _, _, _, _, _, channelName = ...
        OnChannelMessage(message, sender, nil, nil, nil, nil, nil, nil, channelName)

    elseif event == "PLAYER_LOGIN" then
        -- Register addon prefix (if available in this client version)
        if RegisterAddonMessagePrefix then
            RegisterAddonMessagePrefix(DB.Config.prefix)
        end

        -- Join custom channel for cross-guild communication
        AIP.Utils.DelayedCall(3, function()
            DB.JoinChannel()
        end)

        -- Send initial ping after channel has time to connect
        AIP.Utils.DelayedCall(6, function()
            DB.SendPing()
        end)

        DB.State.initialized = true

    elseif event == "PLAYER_LOGOUT" then
        DB.LeaveChannel()

    elseif event == "CHANNEL_UI_UPDATE" or event == "CHAT_MSG_CHANNEL_NOTICE" then
        -- Channel state may have changed, verify our channel
        if DB.State.initialized and DB.Config.useChannelFallback then
            local currentId = GetChannelName(DB.Config.channelName)
            if currentId and currentId > 0 then
                DB.State.channelId = currentId
                DB.State.channelReady = true
            else
                DB.State.channelReady = false
                -- Try to rejoin if lost
                DB.JoinChannel()
            end
        end
    end
end

eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_LOGOUT")
eventFrame:RegisterEvent("CHANNEL_UI_UPDATE")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL_NOTICE")
eventFrame:SetScript("OnEvent", OnEvent)

-- Install chat filter to hide our messages (do this early)
ChatFrame_AddMessageEventFilter("CHAT_MSG_CHANNEL", ChatFilter)

-- Periodic cleanup, channel health check, and heartbeat
local pruneElapsed = 0
local heartbeatElapsed = 0
local channelCheckElapsed = 0
local HEARTBEAT_INTERVAL = 120     -- Send PING every 2 minutes to maintain peer awareness
local CHANNEL_CHECK_INTERVAL = 30  -- Check channel health every 30 seconds

eventFrame:SetScript("OnUpdate", function(self, elapsed)
    pruneElapsed = pruneElapsed + elapsed
    heartbeatElapsed = heartbeatElapsed + elapsed
    channelCheckElapsed = channelCheckElapsed + elapsed

    -- Prune expired events
    if pruneElapsed >= DB.Config.pruneInterval then
        pruneElapsed = 0
        DB.Prune()
    end

    -- Periodic heartbeat PING to maintain peer awareness
    if heartbeatElapsed >= HEARTBEAT_INTERVAL then
        heartbeatElapsed = 0
        if DB.State.initialized and DB.Config.enabled then
            DB.SendPing()
        end
    end

    -- Channel health check
    if channelCheckElapsed >= CHANNEL_CHECK_INTERVAL then
        channelCheckElapsed = 0
        if DB.State.initialized and DB.Config.useChannelFallback then
            local currentId = GetChannelName(DB.Config.channelName)
            if not currentId or currentId == 0 then
                -- Channel lost, try to rejoin with backoff
                local now = time()
                local backoffTime = math.min(300, 10 * (2 ^ (DB.State.channelJoinAttempts or 0)))
                if (now - (DB.State.lastChannelJoinAttempt or 0)) >= backoffTime then
                    DB.State.lastChannelJoinAttempt = now
                    DB.JoinChannel()
                end
            elseif currentId ~= DB.State.channelId then
                -- Channel ID changed, update it
                DB.State.channelId = currentId
                DB.State.channelReady = true
                DB.State.channelJoinAttempts = 0
            end
        end
    end
end)

-- ============================================================================
-- JOINED CHANNELS DETECTION
-- ============================================================================

-- Get all currently joined channels (for dynamic channel detection)
function DB.GetJoinedChannels()
    local channels = {}
    for i = 1, MAX_CHANNEL_BUTTONS or 20 do
        local id, name = GetChannelName(i)
        if id and id > 0 and name and name ~= "" then
            -- Extract base channel name (remove number prefix if present)
            local baseName = name:match("^%d+%.%s*(.+)$") or name
            -- Skip the DataBus channel
            if baseName:lower() ~= DB.Config.channelName:lower() then
                table.insert(channels, {
                    id = id,
                    index = i,
                    name = baseName,
                    fullName = name,
                })
            end
        end
    end
    return channels
end

-- Check if a channel is joined
function DB.IsChannelJoined(channelName)
    local channels = DB.GetJoinedChannels()
    local lowerName = channelName:lower()
    for _, ch in ipairs(channels) do
        if ch.name:lower():find(lowerName) then
            return true, ch.id
        end
    end
    return false, nil
end

-- ============================================================================
-- DEBUG / UTILITY
-- ============================================================================

-- Print DataBus status
function DB.PrintStatus()
    AIP.Print("=== DataBus Status ===")
    AIP.Print("Enabled: " .. (DB.Config.enabled and "Yes" or "No"))

    -- Channel status
    local channelStatus = "Disabled"
    if DB.Config.useChannelFallback then
        if DB.State.channelReady and DB.State.channelId then
            channelStatus = DB.Config.channelName .. " (#" .. DB.State.channelId .. ") - Connected"
        else
            channelStatus = DB.Config.channelName .. " - Connecting..."
        end
    end
    AIP.Print("Channel: " .. channelStatus)
    AIP.Print("Peers online: " .. DB.GetPeerCount())
    AIP.Print("LFM listings: " .. #DB.GetLFMListings())
    AIP.Print("LFG listings: " .. #DB.GetLFGListings())

    local subCount = 0
    for _, subs in pairs(DB.State.subscribers) do
        subCount = subCount + #subs
    end
    AIP.Print("Subscribers: " .. subCount)
end

-- Slash command handler
function DB.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "status" then
        DB.PrintStatus()
    elseif msg == "peers" then
        local peers = DB.GetOnlinePeers()
        if #peers == 0 then
            AIP.Print("No peers online")
        else
            AIP.Print("Online peers (" .. #peers .. "):")
            for _, peer in ipairs(peers) do
                AIP.Print("  " .. peer.name .. " (v" .. peer.version .. ")")
            end
        end
    elseif msg == "ping" then
        DB.SendPing()
        local channels = {}
        if IsInGuild() then table.insert(channels, "guild") end
        if GetNumRaidMembers() > 0 then table.insert(channels, "raid") end
        if GetNumPartyMembers() > 0 then table.insert(channels, "party") end
        if DB.State.channelReady then table.insert(channels, DB.Config.channelName) end
        local channelStr = #channels > 0 and table.concat(channels, ", ") or "none"
        AIP.Print("Ping sent via: " .. channelStr)
    elseif msg == "enable" then
        DB.Config.enabled = true
        AIP.Print("DataBus enabled")
    elseif msg == "disable" then
        DB.Config.enabled = false
        AIP.Print("DataBus disabled")
    else
        AIP.Print("DataBus commands:")
        AIP.Print("  /aip databus - Show status")
        AIP.Print("  /aip databus peers - List online peers")
        AIP.Print("  /aip databus ping - Send presence ping")
        AIP.Print("  /aip databus enable/disable - Toggle")
    end
end
