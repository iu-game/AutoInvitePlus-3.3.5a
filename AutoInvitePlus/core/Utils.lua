-- AutoInvite Plus - Utilities Module
-- Shared utilities used by all modules (DRY principle)

local ADDON_NAME = "AutoInvitePlus"

-- Create main namespace if not exists
AutoInvitePlus = AutoInvitePlus or {}
local AIP = AutoInvitePlus

-- Utils namespace
AIP.Utils = {}
local Utils = AIP.Utils

-- ============================================================================
-- POLYFILLS FOR WOTLK COMPATIBILITY
-- ============================================================================

-- Ensure string.trim exists (some WotLK clients may not have it)
if not string.trim then
    function string.trim(s)
        return strtrim(s)  -- strtrim() is always available in WoW
    end
end

-- ============================================================================
-- STRING UTILITIES
-- ============================================================================

-- Normalize player name: "playername" -> "Playername"
function Utils.NormalizeName(name)
    if not name or name == "" then return nil end
    -- Use gsub for trim since string:trim() may not exist in WotLK
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    -- Handle single-char names safely
    if #name == 1 then
        return name:upper()
    end
    return name:sub(1, 1):upper() .. name:sub(2):lower()
end

-- Format time in seconds to human readable
function Utils.FormatTime(seconds)
    if not seconds or seconds < 0 then return "-" end

    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. "h"
    else
        return math.floor(seconds / 86400) .. "d"
    end
end

-- Format time ago (relative)
function Utils.FormatTimeAgo(timestamp)
    if not timestamp then return "-" end
    local diff = time() - timestamp
    return Utils.FormatTime(diff) .. " ago"
end

-- Format date for display
function Utils.FormatDate(timestamp)
    if not timestamp then return "Unknown" end
    return date("%Y-%m-%d %H:%M", timestamp)
end

-- Escape pattern special characters
function Utils.EscapePattern(str)
    return str:gsub("([%%%.%[%]%^%$%*%+%-%?%(%)%{%}])", "%%%1")
end

-- ============================================================================
-- TABLE UTILITIES
-- ============================================================================

-- Find element in table using predicate function
-- Returns: value, index/key
function Utils.TableFind(tbl, predicate)
    if not tbl then return nil, nil end

    for k, v in pairs(tbl) do
        if predicate(v, k) then
            return v, k
        end
    end
    return nil, nil
end

-- Find index in array using predicate
function Utils.ArrayFind(arr, predicate)
    if not arr then return nil end

    for i, v in ipairs(arr) do
        if predicate(v, i) then
            return i
        end
    end
    return nil
end

-- Count elements in table (including non-numeric keys)
function Utils.TableCount(tbl)
    if not tbl then return 0 end

    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

-- Shallow copy of table
function Utils.TableCopy(tbl)
    if not tbl then return nil end
    if type(tbl) ~= "table" then return tbl end

    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

-- Deep copy of table
function Utils.TableDeepCopy(tbl)
    if not tbl then return nil end
    if type(tbl) ~= "table" then return tbl end

    local copy = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            copy[k] = Utils.TableDeepCopy(v)
        else
            copy[k] = v
        end
    end
    return copy
end

-- Merge source table into target (modifies target)
function Utils.TableMerge(target, source)
    if not source then return target end
    target = target or {}

    for k, v in pairs(source) do
        if target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Check if table contains value
function Utils.TableContains(tbl, value)
    if not tbl then return false end

    for _, v in pairs(tbl) do
        if v == value then
            return true
        end
    end
    return false
end

-- ============================================================================
-- CACHE CLASS
-- ============================================================================

Utils.Cache = {}
Utils.Cache.__index = Utils.Cache

-- Create a new cache with TTL (time to live in seconds)
function Utils.Cache:new(ttl)
    local cache = setmetatable({}, self)
    cache.ttl = ttl or 300  -- Default 5 minutes
    cache.data = {}
    cache.timestamps = {}
    return cache
end

-- Get value from cache (returns nil if expired or not found)
function Utils.Cache:get(key)
    if not key then return nil end

    local timestamp = self.timestamps[key]
    if not timestamp then return nil end

    if time() - timestamp > self.ttl then
        self.data[key] = nil
        self.timestamps[key] = nil
        return nil
    end

    return self.data[key]
end

-- Set value in cache
function Utils.Cache:set(key, value)
    if not key then return end

    self.data[key] = value
    self.timestamps[key] = time()
end

-- Remove value from cache
function Utils.Cache:remove(key)
    if not key then return end

    self.data[key] = nil
    self.timestamps[key] = nil
end

-- Clear all cache entries
function Utils.Cache:clear()
    self.data = {}
    self.timestamps = {}
end

-- Remove expired entries
function Utils.Cache:prune()
    local now = time()
    local pruned = 0

    for key, timestamp in pairs(self.timestamps) do
        if now - timestamp > self.ttl then
            self.data[key] = nil
            self.timestamps[key] = nil
            pruned = pruned + 1
        end
    end

    return pruned
end

-- Get count of cached items
function Utils.Cache:count()
    return Utils.TableCount(self.data)
end

-- Check if key exists and is not expired
function Utils.Cache:has(key)
    return self:get(key) ~= nil
end

-- ============================================================================
-- EVENT DISPATCHER (Single frame for all events)
-- ============================================================================

Utils.Events = {
    frame = nil,
    handlers = {},  -- event -> {handler1, handler2, ...}
}

-- Initialize the event frame
function Utils.Events.Init()
    if Utils.Events.frame then return end

    Utils.Events.frame = CreateFrame("Frame", "AIPUtilsEventFrame", UIParent)
    Utils.Events.frame:SetScript("OnEvent", function(self, event, ...)
        Utils.Events.Dispatch(event, ...)
    end)
end

-- Register a handler for an event
function Utils.Events.Register(event, handler, owner)
    if not event or not handler then return end

    Utils.Events.Init()

    if not Utils.Events.handlers[event] then
        Utils.Events.handlers[event] = {}
        Utils.Events.frame:RegisterEvent(event)
    end

    table.insert(Utils.Events.handlers[event], {
        handler = handler,
        owner = owner,
    })
end

-- Unregister a handler for an event
function Utils.Events.Unregister(event, handler)
    if not event or not Utils.Events.handlers[event] then return end

    for i = #Utils.Events.handlers[event], 1, -1 do
        if Utils.Events.handlers[event][i].handler == handler then
            table.remove(Utils.Events.handlers[event], i)
        end
    end

    -- Unregister event if no more handlers
    if #Utils.Events.handlers[event] == 0 then
        Utils.Events.handlers[event] = nil
        if Utils.Events.frame then
            Utils.Events.frame:UnregisterEvent(event)
        end
    end
end

-- Unregister all handlers for an owner
function Utils.Events.UnregisterAll(owner)
    for event, handlers in pairs(Utils.Events.handlers) do
        for i = #handlers, 1, -1 do
            if handlers[i].owner == owner then
                table.remove(handlers, i)
            end
        end

        if #handlers == 0 then
            Utils.Events.handlers[event] = nil
            if Utils.Events.frame then
                Utils.Events.frame:UnregisterEvent(event)
            end
        end
    end
end

-- Dispatch event to all handlers
function Utils.Events.Dispatch(event, ...)
    local handlers = Utils.Events.handlers[event]
    if not handlers then return end

    for _, entry in ipairs(handlers) do
        Utils.SafeCall(entry.handler, event, ...)
    end
end

-- ============================================================================
-- SAFE CALL / ERROR HANDLING
-- ============================================================================

-- Call a function safely, catching errors
function Utils.SafeCall(fn, ...)
    if not fn then return nil end

    local success, result = pcall(fn, ...)
    if not success then
        if AIP.Debug then
            AIP.Debug("SafeCall error: " .. tostring(result))
        end
        return nil
    end
    return result
end

-- ============================================================================
-- THROTTLED FUNCTIONS
-- ============================================================================

Utils.Throttle = {}
Utils.Throttle.lastCalls = {}

-- Create a throttled version of a function
function Utils.Throttle.Create(key, cooldown)
    return function(fn, ...)
        local now = GetTime()
        local lastCall = Utils.Throttle.lastCalls[key] or 0

        if now - lastCall < cooldown then
            return false, cooldown - (now - lastCall)
        end

        Utils.Throttle.lastCalls[key] = now
        return true, Utils.SafeCall(fn, ...)
    end
end

-- Check if we can call (without calling)
function Utils.Throttle.CanCall(key, cooldown)
    local now = GetTime()
    local lastCall = Utils.Throttle.lastCalls[key] or 0
    return now - lastCall >= cooldown
end

-- Reset throttle for a key
function Utils.Throttle.Reset(key)
    Utils.Throttle.lastCalls[key] = nil
end

-- ============================================================================
-- WHISPER QUEUE (throttle-aware)
-- ============================================================================

Utils.WhisperQueue = {
    queue = {},
    processing = false,
    minDelay = 0.3,  -- Minimum delay between whispers
    lastWhisper = 0,
}

-- Add whisper to queue
function Utils.WhisperQueue.Add(recipient, message)
    if not recipient or not message then return end

    table.insert(Utils.WhisperQueue.queue, {
        recipient = recipient,
        message = message,
        time = time(),
    })

    Utils.WhisperQueue.Process()
end

-- Process the whisper queue
function Utils.WhisperQueue.Process()
    if Utils.WhisperQueue.processing then return end
    if #Utils.WhisperQueue.queue == 0 then return end

    Utils.WhisperQueue.processing = true

    local frame = Utils.WhisperQueue.frame
    if not frame then
        frame = CreateFrame("Frame")
        Utils.WhisperQueue.frame = frame
    end

    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed

        local now = GetTime()
        local timeSince = now - Utils.WhisperQueue.lastWhisper

        if timeSince < Utils.WhisperQueue.minDelay then
            return
        end

        if #Utils.WhisperQueue.queue == 0 then
            Utils.WhisperQueue.processing = false
            self:SetScript("OnUpdate", nil)
            return
        end

        local entry = table.remove(Utils.WhisperQueue.queue, 1)
        SendChatMessage(entry.message, "WHISPER", nil, entry.recipient)
        Utils.WhisperQueue.lastWhisper = now
    end)
end

-- Send whisper with throttling
function Utils.SendWhisper(recipient, message)
    Utils.WhisperQueue.Add(recipient, message)
end

-- ============================================================================
-- DELAYED CALL (WotLK compatible timer)
-- ============================================================================

-- Call function after delay (in seconds)
function Utils.DelayedCall(delay, fn, ...)
    if not fn then return end

    local args = {...}
    local frame = CreateFrame("Frame")
    frame.elapsed = 0

    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            Utils.SafeCall(fn, unpack(args))
        end
    end)

    return frame  -- Return frame so caller can cancel if needed
end

-- Cancel a delayed call
function Utils.CancelDelayedCall(frame)
    if frame and frame.SetScript then
        frame:SetScript("OnUpdate", nil)
    end
end

-- ============================================================================
-- CLASS COLORS
-- ============================================================================

Utils.ClassColors = {
    WARRIOR = {r = 0.78, g = 0.61, b = 0.43},
    PALADIN = {r = 0.96, g = 0.55, b = 0.73},
    HUNTER = {r = 0.67, g = 0.83, b = 0.45},
    ROGUE = {r = 1.00, g = 0.96, b = 0.41},
    PRIEST = {r = 1.00, g = 1.00, b = 1.00},
    DEATHKNIGHT = {r = 0.77, g = 0.12, b = 0.23},
    SHAMAN = {r = 0.00, g = 0.44, b = 0.87},
    MAGE = {r = 0.41, g = 0.80, b = 0.94},
    WARLOCK = {r = 0.58, g = 0.51, b = 0.79},
    DRUID = {r = 1.00, g = 0.49, b = 0.04},
}

-- Get class color as hex string
function Utils.GetClassColorHex(class)
    local color = Utils.ClassColors[class]
    if not color then return "FFFFFF" end
    return string.format("%02X%02X%02X", color.r * 255, color.g * 255, color.b * 255)
end

-- Format name with class color
function Utils.ColorByClass(name, class)
    if not class then return name end
    local hex = Utils.GetClassColorHex(class)
    return "|cFF" .. hex .. name .. "|r"
end

-- ============================================================================
-- WOW API HELPERS (WotLK 3.3.5a compatible)
-- ============================================================================

-- Get group size
function Utils.GetGroupSize()
    if UnitInRaid("player") then
        return GetNumRaidMembers()
    else
        return GetNumPartyMembers() + 1
    end
end

-- Check if player is group leader
function Utils.IsGroupLeader()
    local numRaid = GetNumRaidMembers()
    if numRaid > 0 then
        return IsRaidLeader() or IsRaidOfficer()
    elseif GetNumPartyMembers() > 0 then
        return IsPartyLeader()
    end
    return true  -- Solo = leader
end

-- Check if in raid
function Utils.IsInRaid()
    return GetNumRaidMembers() > 0
end

-- Check if in party (but not raid)
function Utils.IsInParty()
    return GetNumPartyMembers() > 0 and GetNumRaidMembers() == 0
end

-- Check if in any group
function Utils.IsInGroup()
    return GetNumRaidMembers() > 0 or GetNumPartyMembers() > 0
end

-- Iterate group members (yields unit, name, class)
function Utils.IterateGroup(includePlayer)
    local results = {}
    local numRaid = GetNumRaidMembers()

    if numRaid > 0 then
        for i = 1, numRaid do
            local name, _, _, _, class = GetRaidRosterInfo(i)
            if name then
                local unit = "raid" .. i
                if includePlayer or not UnitIsUnit(unit, "player") then
                    table.insert(results, {unit = unit, name = name, class = class})
                end
            end
        end
    else
        if includePlayer then
            local name = UnitName("player")
            local _, class = UnitClass("player")
            table.insert(results, {unit = "player", name = name, class = class})
        end

        for i = 1, GetNumPartyMembers() do
            local unit = "party" .. i
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            if name then
                table.insert(results, {unit = unit, name = name, class = class})
            end
        end
    end

    return results
end

-- ============================================================================
-- PLAYER LIST BASE CLASS (OOP pattern for Queue, Waitlist, Blacklist)
-- ============================================================================

Utils.PlayerList = {}
Utils.PlayerList.__index = Utils.PlayerList

-- Create a new player list instance
-- @param dbKey: The key in AIP.db where this list is stored
-- @param useArray: true for array-based (Queue, Waitlist), false for keyed table (Blacklist)
function Utils.PlayerList:new(dbKey, useArray)
    local list = setmetatable({}, self)
    list.dbKey = dbKey
    list.useArray = useArray or false
    list.updateCallbacks = {}
    return list
end

-- Get the data table from AIP.db
function Utils.PlayerList:getData()
    local AIP = AutoInvitePlus
    if not AIP or not AIP.db then return nil end
    return AIP.db[self.dbKey]
end

-- Ensure the data table exists
function Utils.PlayerList:ensureData()
    local AIP = AutoInvitePlus
    if not AIP or not AIP.db then return nil end
    if not AIP.db[self.dbKey] then
        AIP.db[self.dbKey] = {}
    end
    return AIP.db[self.dbKey]
end

-- Register a callback for when list changes
function Utils.PlayerList:onUpdate(callback)
    table.insert(self.updateCallbacks, callback)
end

-- Trigger update callbacks
function Utils.PlayerList:triggerUpdate()
    for _, callback in ipairs(self.updateCallbacks) do
        Utils.SafeCall(callback)
    end
end

-- Add entry to list (base implementation)
function Utils.PlayerList:add(name, data)
    if not name or name == "" then return false end
    local storage = self:ensureData()
    if not storage then return false end

    name = Utils.NormalizeName(name)
    local key = self.useArray and nil or name:lower()

    if self.useArray then
        -- Check for duplicates in array (both names are already normalized)
        for _, entry in ipairs(storage) do
            if entry.name == name then
                return false  -- Already exists
            end
        end
        data = data or {}
        data.name = name
        data.time = data.time or time()
        table.insert(storage, data)
    else
        -- Keyed table
        if storage[key] then
            return false  -- Already exists
        end
        data = data or {}
        data.name = name
        storage[key] = data
    end

    self:triggerUpdate()
    return true
end

-- Remove entry from list
function Utils.PlayerList:remove(name)
    if not name then return false end
    local storage = self:getData()
    if not storage then return false end

    local lowerName = name:lower()

    if self.useArray then
        for i, entry in ipairs(storage) do
            if entry.name:lower() == lowerName then
                table.remove(storage, i)
                self:triggerUpdate()
                return true
            end
        end
    else
        if storage[lowerName] then
            storage[lowerName] = nil
            self:triggerUpdate()
            return true
        end
    end

    return false
end

-- Find entry in list
-- Returns: entry, index/key
function Utils.PlayerList:find(name)
    if not name then return nil, nil end
    local storage = self:getData()
    if not storage then return nil, nil end

    local lowerName = name:lower()

    if self.useArray then
        for i, entry in ipairs(storage) do
            if entry.name:lower() == lowerName then
                return entry, i
            end
        end
    else
        local entry = storage[lowerName]
        if entry then
            return entry, lowerName
        end
    end

    return nil, nil
end

-- Check if entry exists
function Utils.PlayerList:has(name)
    local entry = self:find(name)
    return entry ~= nil
end

-- Get all entries (optionally with filter)
function Utils.PlayerList:getAll(filterFn)
    local storage = self:getData()
    if not storage then return {} end

    local results = {}

    if self.useArray then
        for i, entry in ipairs(storage) do
            if not filterFn or filterFn(entry) then
                table.insert(results, entry)
            end
        end
    else
        for key, entry in pairs(storage) do
            if not filterFn or filterFn(entry) then
                table.insert(results, entry)
            end
        end
    end

    return results
end

-- Get count
function Utils.PlayerList:count()
    local storage = self:getData()
    if not storage then return 0 end

    if self.useArray then
        return #storage
    else
        return Utils.TableCount(storage)
    end
end

-- Clear all entries
function Utils.PlayerList:clear()
    local AIP = AutoInvitePlus
    if not AIP or not AIP.db then return end

    AIP.db[self.dbKey] = {}
    self:triggerUpdate()
end

-- ============================================================================
-- MUTEX / LOCK UTILITY (for preventing race conditions)
-- ============================================================================

Utils.Mutex = {}
Utils.Mutex.locks = {}

-- Acquire a lock (returns true if acquired, false if already locked)
function Utils.Mutex.Acquire(key)
    if Utils.Mutex.locks[key] then
        return false
    end
    Utils.Mutex.locks[key] = true
    return true
end

-- Release a lock
function Utils.Mutex.Release(key)
    Utils.Mutex.locks[key] = nil
end

-- Check if locked
function Utils.Mutex.IsLocked(key)
    return Utils.Mutex.locks[key] == true
end

-- Execute function with lock (auto-releases on completion)
function Utils.Mutex.WithLock(key, fn, ...)
    if not Utils.Mutex.Acquire(key) then
        return false, "locked"
    end

    local result = {Utils.SafeCall(fn, ...)}
    Utils.Mutex.Release(key)

    return true, unpack(result)
end
