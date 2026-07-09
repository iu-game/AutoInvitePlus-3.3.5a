-- AutoInvite Plus - Chat Scanner Module
-- Unified module for scanning chat for LFM groups and LFG players
-- (Merges former GroupTracker and LFMBrowser modules)
-- Now integrated with DataBus for inter-player addon communication

local AIP = AutoInvitePlus
AIP.ChatScanner = {}
local CS = AIP.ChatScanner

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

CS.Config = {
    enabled = true,
    maxGroups = 100,
    maxPlayers = 200,
    expiryTime = 600,       -- 10 minutes
    -- Note: Channel settings now use AIP.db.listen* (unified with auto-invite)
    -- DataBus integration
    useDataBus = true,          -- Use DataBus for addon-to-addon communication
    dataBusAutoPublish = true,  -- Auto-publish our LFM/LFG to other addon users
}

-- ============================================================================
-- DATA STORAGE
-- ============================================================================

-- LFM Groups (group leaders advertising for members)
CS.Groups = {}

-- LFG Players (individual players looking for groups)
CS.Players = {}

-- Runtime per-listing state (keyed by leader:lower()).
-- NOT persisted and NOT stored on the group table: an LFM re-post can replace
-- the group entry, and these must survive that. They are cleared only when the
-- listing itself is pruned (see CS.PruneGroups), so an excluded/requested
-- listing reappears once the leader posts fresh after the cache expires.
CS.Excluded = {}    -- leader:lower() -> time() when excluded
CS.Requested = {}   -- leader:lower() -> time() when we sent an invite request

-- ============================================================================
-- PER-LISTING STATE (exclude / requested)
-- ============================================================================

local function listingKey(leader)
    if not leader or leader == "" then return nil end
    return leader:lower()
end

function CS.MarkExcluded(leader)
    local key = listingKey(leader)
    if not key then return end
    CS.Excluded[key] = time()
end

function CS.ClearExcluded(leader)
    local key = listingKey(leader)
    if not key then return end
    CS.Excluded[key] = nil
end

function CS.IsExcluded(leader)
    local key = listingKey(leader)
    return key ~= nil and CS.Excluded[key] ~= nil
end

function CS.MarkRequested(leader)
    local key = listingKey(leader)
    if not key then return end
    CS.Requested[key] = time()
end

-- Returns the timestamp we requested this leader, or nil.
function CS.GetRequested(leader)
    local key = listingKey(leader)
    if not key then return nil end
    return CS.Requested[key]
end

-- Collect current listings (LFM leaders + LFG players) from favorited players.
-- Used for the minimap tooltip count and the "Favorites Listed" bubble. Skips
-- our own listings and excluded ones.
function CS.GetFavoriteListings()
    local results = {}
    if not AIP.IsPlayerFavorite then return results end
    for leader, group in pairs(CS.Groups) do
        if not group.isOwn and not CS.IsExcluded(leader) and AIP.IsPlayerFavorite(leader) then
            table.insert(results, { name = leader, kind = "lfm" })
        end
    end
    for name in pairs(CS.Players) do
        if AIP.IsPlayerFavorite(name) then
            table.insert(results, { name = name, kind = "lfg" })
        end
    end
    return results
end

-- Collect current VOA listings (for the minimap alert/tooltip).
-- Skips our own listings and any we've excluded. Each result is tagged with
-- isFavorite so the caller can highlight favorited leaders.
function CS.GetVOAListings()
    local results = {}
    for leader, group in pairs(CS.Groups) do
        local isVOA = group.raidCategory == "VOA"
            or (group.raid and tostring(group.raid):upper():find("^VOA"))
        if isVOA and not group.isOwn and not CS.IsExcluded(leader) then
            local isFav = AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(leader) or false
            table.insert(results, {
                leader = leader,
                raid = group.raid,
                group = group,
                isFavorite = isFav,
            })
        end
    end
    return results
end

-- ============================================================================
-- ENTRY MANAGEMENT
-- ============================================================================

-- Add or update a group listing
function CS.AddGroup(info)
    if not info or not info.author then return end

    -- Skip self
    if info.author == UnitName("player") then
        info.isOwn = true
    end

    local existing = CS.Groups[info.author]
    if existing then
        -- Update existing entry
        existing.raid = info.raid or existing.raid
        existing.raidCategory = info.raidCategory or existing.raidCategory
        existing.raids = info.raids or existing.raids
        existing.composition = info.composition or existing.composition
        existing.gs = info.gs or existing.gs
        existing.message = info.message
        existing.time = info.time
        existing.channel = info.channel
        existing.isOwn = info.isOwn or existing.isOwn
        existing.isDataBus = info.isDataBus or existing.isDataBus
        -- Extended group info fields
        existing.gsMin = info.gsMin or existing.gsMin
        existing.ilvlMin = info.ilvlMin or existing.ilvlMin
        existing.tanks = info.tanks or existing.tanks
        existing.healers = info.healers or existing.healers
        existing.mdps = info.mdps or existing.mdps
        existing.rdps = info.rdps or existing.rdps
        -- Backwards compatibility: convert old 'dps' to mdps+rdps if present
        -- Always overwrite when updating from dps format (not using 'or' to avoid data loss)
        if info.dps and not info.mdps and not info.rdps then
            local halfCurrent = math.floor((info.dps.current or 0) / 2)
            local halfNeeded = math.floor((info.dps.needed or 0) / 2)
            existing.mdps = {current = halfCurrent, needed = halfNeeded}
            existing.rdps = {current = (info.dps.current or 0) - halfCurrent, needed = (info.dps.needed or 0) - halfNeeded}
        end
        existing.achievementId = info.achievementId or existing.achievementId
        existing.achievement = info.achievement or existing.achievement
        existing.inviteKeyword = info.inviteKeyword or existing.inviteKeyword
        existing.triggerKey = info.triggerKey or info.inviteKeyword or existing.triggerKey
        existing.selectedClasses = info.selectedClasses or existing.selectedClasses
        existing.lookingForClasses = info.lookingForClasses or existing.lookingForClasses
        existing.roleSpecs = info.roleSpecs or existing.roleSpecs
        existing.lookingForSpecs = info.lookingForSpecs or existing.lookingForSpecs
        existing.note = info.note or existing.note
        existing.ilvl = info.ilvl or existing.ilvl
        existing.filledCurrent = info.filledCurrent or existing.filledCurrent
        existing.filledMax = info.filledMax or existing.filledMax
    else
        -- Handle backwards compatibility for dps -> mdps/rdps
        local mdpsVal = info.mdps
        local rdpsVal = info.rdps
        if info.dps and not info.mdps and not info.rdps then
            local halfCurrent = math.floor((info.dps.current or 0) / 2)
            local halfNeeded = math.floor((info.dps.needed or 0) / 2)
            mdpsVal = {current = halfCurrent, needed = halfNeeded}
            rdpsVal = {current = (info.dps.current or 0) - halfCurrent, needed = (info.dps.needed or 0) - halfNeeded}
        end

        CS.Groups[info.author] = {
            leader = info.author,
            raid = info.raid,
            raidCategory = info.raidCategory,
            raids = info.raids or {},
            composition = info.composition or {},
            gs = info.gs,
            message = info.message,
            channel = info.channel,
            time = info.time,
            isOwn = info.isOwn,
            isDataBus = info.isDataBus,
            isGroup = true,
            -- Extended group info fields
            gsMin = info.gsMin,
            ilvlMin = info.ilvlMin,
            tanks = info.tanks,
            healers = info.healers,
            mdps = mdpsVal,
            rdps = rdpsVal,
            achievementId = info.achievementId,
            achievement = info.achievement,
            inviteKeyword = info.inviteKeyword,
            triggerKey = info.triggerKey or info.inviteKeyword,
            selectedClasses = info.selectedClasses,
            lookingForClasses = info.lookingForClasses,
            roleSpecs = info.roleSpecs,
            lookingForSpecs = info.lookingForSpecs,
            note = info.note,
            ilvl = info.ilvl,
            filledCurrent = info.filledCurrent,
            filledMax = info.filledMax,
        }
        CS.PruneGroups()
    end

    -- Notify UI
    CS.NotifyUpdate("lfm")
end

-- Add or update a player listing
function CS.AddPlayer(info)
    if not info or not info.author then return end

    -- Skip self
    if info.author == UnitName("player") then return end

    local existing = CS.Players[info.author]
    if existing then
        -- Update existing entry
        existing.message = info.message
        existing.time = info.time
        existing.channel = info.channel

        -- Merge raids
        if info.raids then
            for _, raid in ipairs(info.raids) do
                local found = false
                for _, r in ipairs(existing.raids or {}) do
                    if r == raid then found = true; break end
                end
                if not found then
                    existing.raids = existing.raids or {}
                    table.insert(existing.raids, raid)
                end
            end
        end

        -- Update if newly detected
        if info.role then existing.role = info.role end
        if info.class then existing.class = info.class end
        if info.gs then existing.gs = info.gs end
        existing.isLFG = info.isLFG or existing.isLFG
        existing.isLFM = info.isLFM or existing.isLFM
    else
        CS.Players[info.author] = {
            name = info.author,
            raids = info.raids or {},
            role = info.role,
            class = info.class,
            gs = info.gs,
            message = info.message,
            channel = info.channel,
            time = info.time,
            isLFG = info.isLFG,
            isLFM = info.isLFM,
        }
        CS.PrunePlayers()

        -- Auto-queue new LFG players from chat that match our active LFM
        -- Only if autoQueueLFG is enabled in settings
        -- (Skip DataBus since those are handled in OnDataBusLFG)
        if AIP.db and AIP.db.autoQueueLFG and info.isLFG and not info.isDataBus and CS.MatchesMyLFM(info) then
            local GUI = AIP.CentralGUI or {}
            if GUI.MyGroup and AIP.AddToQueue then
                local isBlacklisted = AIP.IsBlacklisted and AIP.IsBlacklisted(info.author)
                local isInQueue = AIP.IsInQueue and AIP.IsInQueue(info.author)
                if not isBlacklisted and not isInQueue then
                    AIP.AddToQueue(info.author, info.message, info.role, info.gs, info.class)
                    AIP.Print("|cFF00FF00Auto-queued|r " .. info.author .. " from chat (matched your LFM)")
                end
            end
        end
    end

    -- Notify UI
    CS.NotifyUpdate("lfg")
end

-- Notify UI of updates. Route through the debounced AIP.UpdateCentralGUI only -
-- it refreshes the *current* tab. The old direct RefreshBrowserTab(tab) here fired
-- an immediate tree rebuild on every LFM/LFG chat line (constant on a busy realm),
-- which is what made the tree refresh at random. The other tab refreshes when you
-- switch to it (SelectTab), so nothing is lost.
function CS.NotifyUpdate(tab)
    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end
end

-- ============================================================================
-- LFM/LFG MATCHING
-- Check if an LFG event matches our active LFM
-- ============================================================================

function CS.MatchesMyLFM(lfgInfo)
    local GUI = AIP.CentralGUI or {}
    if not GUI.MyGroup then return false end

    local myLFM = GUI.MyGroup

    -- Check raid match - STRICT matching required
    local targetRaid = lfgInfo.raids and lfgInfo.raids[1] or lfgInfo.raid
    if not targetRaid then return false end

    -- Require exact raid match (ICC25H must match ICC25H, not ICC10N or RS25H)
    if myLFM.raid:lower() ~= targetRaid:lower() then
        return false
    end

    -- Check GS requirement
    if myLFM.gsMin and myLFM.gsMin > 0 then
        if not lfgInfo.gs or lfgInfo.gs < myLFM.gsMin then
            return false
        end
    end

    -- Check iLvl requirement
    if myLFM.ilvlMin and myLFM.ilvlMin > 0 then
        if not lfgInfo.ilvl or lfgInfo.ilvl < myLFM.ilvlMin then
            return false
        end
    end

    -- Check role needs - only queue if we need their role
    if lfgInfo.role and myLFM then
        local role = lfgInfo.role:upper()
        local needed = false

        if role == "TANK" and myLFM.tanks then
            needed = (myLFM.tanks.needed or 0) > (myLFM.tanks.current or 0)
        elseif role == "HEALER" and myLFM.healers then
            needed = (myLFM.healers.needed or 0) > (myLFM.healers.current or 0)
        elseif (role == "MDPS" or role == "MELEE" or role == "DPS") and myLFM.mdps then
            needed = (myLFM.mdps.needed or 0) > (myLFM.mdps.current or 0)
        elseif (role == "RDPS" or role == "RANGED") and myLFM.rdps then
            needed = (myLFM.rdps.needed or 0) > (myLFM.rdps.current or 0)
        else
            -- Unknown role or no role specified - allow if any DPS slot open
            needed = ((myLFM.mdps and (myLFM.mdps.needed or 0) > (myLFM.mdps.current or 0)) or
                     (myLFM.rdps and (myLFM.rdps.needed or 0) > (myLFM.rdps.current or 0)))
        end

        if not needed then
            return false
        end
    end

    -- Check class/spec requirements if roleSpecs defined
    if myLFM.roleSpecs and lfgInfo.class then
        local playerClass = lfgInfo.class:upper()
        local playerRole = lfgInfo.role and lfgInfo.role:upper() or "DPS"

        -- Determine which roles to check based on player's role
        local rolesToCheck = {}
        if playerRole == "TANK" then
            rolesToCheck = {"TANK"}
        elseif playerRole == "HEALER" then
            rolesToCheck = {"HEALER"}
        elseif playerRole == "MDPS" or playerRole == "MELEE" then
            rolesToCheck = {"MDPS"}
        elseif playerRole == "RDPS" or playerRole == "RANGED" then
            rolesToCheck = {"RDPS"}
        else
            rolesToCheck = {"MDPS", "RDPS"}
        end

        -- Check if player's class is wanted for their role
        local classWanted = false
        for _, role in ipairs(rolesToCheck) do
            local specs = myLFM.roleSpecs[role]
            if specs and #specs > 0 then
                for _, code in ipairs(specs) do
                    local info = AIP.Parsers and AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                    if info and info.class == playerClass then
                        classWanted = true
                        break
                    end
                end
            else
                -- No spec requirements for this role, any class accepted
                classWanted = true
            end
            if classWanted then break end
        end

        if not classWanted then
            return false
        end
    end

    return true
end

-- ============================================================================
-- PRUNING (Remove expired entries)
-- ============================================================================

-- Entry lifetime in seconds, driven by the user's "Cache Duration" setting
-- (minutes), falling back to the built-in default.
function CS.GetExpiry()
    if AIP.db and AIP.db.cacheDuration and AIP.db.cacheDuration > 0 then
        return AIP.db.cacheDuration * 60
    end
    return CS.Config.expiryTime
end

function CS.PruneGroups()
    local now = time()
    local expiry = CS.GetExpiry()

    -- Remove expired (also clear per-listing state so the exclusion/request
    -- expires with the listing and reappears if the leader posts fresh)
    for leader, info in pairs(CS.Groups) do
        if now - info.time > expiry then
            CS.Groups[leader] = nil
            CS.ClearExcluded(leader)
            CS.Requested[listingKey(leader)] = nil
        end
    end

    -- Limit total - remove all excess entries at once
    local count = 0
    local entries = {}
    for leader, info in pairs(CS.Groups) do
        count = count + 1
        table.insert(entries, {leader = leader, time = info.time})
    end

    if count > CS.Config.maxGroups then
        -- Sort by time (oldest first)
        table.sort(entries, function(a, b) return a.time < b.time end)
        -- Remove excess entries
        local toRemove = count - CS.Config.maxGroups
        for i = 1, toRemove do
            local leader = entries[i].leader
            CS.Groups[leader] = nil
            CS.ClearExcluded(leader)
            CS.Requested[listingKey(leader)] = nil
        end
    end
end

function CS.PrunePlayers()
    local now = time()
    local expiry = CS.GetExpiry()

    -- Remove expired
    for name, info in pairs(CS.Players) do
        if now - info.time > expiry then
            CS.Players[name] = nil
        end
    end

    -- Limit total - remove all excess entries at once
    local count = 0
    local entries = {}
    for name, info in pairs(CS.Players) do
        count = count + 1
        table.insert(entries, {name = name, time = info.time})
    end

    if count > CS.Config.maxPlayers then
        -- Sort by time (oldest first)
        table.sort(entries, function(a, b) return a.time < b.time end)
        -- Remove excess entries
        local toRemove = count - CS.Config.maxPlayers
        for i = 1, toRemove do
            CS.Players[entries[i].name] = nil
        end
    end
end

function CS.Prune()
    CS.PruneGroups()
    CS.PrunePlayers()
end

-- ============================================================================
-- QUERY FUNCTIONS
-- ============================================================================

-- Get all groups (optionally filtered)
function CS.GetGroups(filters)
    filters = filters or {}
    local results = {}
    local now = time()

    for leader, info in pairs(CS.Groups) do
        local include = true

        -- Filter by raid
        if filters.raid and info.raid ~= filters.raid and
           not (info.raid and info.raid:find("^" .. filters.raid)) then
            include = false
        end

        -- Filter by GS (exclude players below minimum)
        if filters.minGS and info.gs and info.gs < filters.minGS then
            include = false
        end

        -- Filter by search
        if filters.search and filters.search ~= "" then
            local s = filters.search:lower()
            if not leader:lower():find(s, 1, true) and
               not (info.message and info.message:lower():find(s, 1, true)) then
                include = false
            end
        end

        if include then
            info.age = now - info.time
            info.leader = leader
            table.insert(results, info)
        end
    end

    -- Sort by time (newest first)
    table.sort(results, function(a, b)
        return a.time > b.time
    end)

    return results
end

-- Get all players (optionally filtered)
function CS.GetPlayers(filters)
    filters = filters or {}
    local results = {}
    local now = time()

    for name, info in pairs(CS.Players) do
        local include = true

        -- LFG only filter
        if filters.lfgOnly and not info.isLFG then
            include = false
        end

        -- LFM only filter
        if filters.lfmOnly and not info.isLFM then
            include = false
        end

        -- Role filter
        if filters.role and info.role ~= filters.role then
            include = false
        end

        -- Class filter
        if filters.class and info.class ~= filters.class then
            include = false
        end

        -- Raid filter
        if filters.raid then
            local hasRaid = false
            for _, raid in ipairs(info.raids or {}) do
                if raid:find(filters.raid) then
                    hasRaid = true
                    break
                end
            end
            if not hasRaid then include = false end
        end

        -- Min GS filter
        if filters.minGS and (not info.gs or info.gs < filters.minGS) then
            include = false
        end

        -- Search filter
        if filters.search and filters.search ~= "" then
            local s = filters.search:lower()
            if not name:lower():find(s, 1, true) and
               not (info.message and info.message:lower():find(s, 1, true)) then
                include = false
            end
        end

        if include then
            info.age = now - info.time
            info.name = name
            table.insert(results, info)
        end
    end

    -- Sort by time (newest first)
    table.sort(results, function(a, b)
        return a.time > b.time
    end)

    return results
end

-- Get groups organized by raid hierarchy (for tree view)
function CS.GetGroupsByRaid(filters)
    filters = filters or {}
    local results = {}
    local now = time()
    local hierarchy = AIP.Parsers and AIP.Parsers.RaidHierarchy or {}

    -- Initialize categories
    for _, cat in ipairs(hierarchy) do
        results[cat.id] = {
            category = cat,
            children = {},
        }
        for _, child in ipairs(cat.children) do
            results[cat.id].children[child.id] = {
                raid = child,
                groups = {},
                count = 0,
            }
        end
    end

    -- Distribute groups into categories
    for leader, info in pairs(CS.Groups) do
        local include = true

        -- Apply filters (exclude groups below minimum GS)
        if filters.minGS and info.gs and info.gs < filters.minGS then
            include = false
        end
        if filters.search and filters.search ~= "" then
            local s = filters.search:lower()
            if not leader:lower():find(s, 1, true) and
               not (info.message and info.message:lower():find(s, 1, true)) then
                include = false
            end
        end

        if include then
            info.age = now - info.time
            info.leader = leader

            -- Find category
            local placed = false
            for catId, catData in pairs(results) do
                if info.raid == catId or (info.raid and info.raid:find("^" .. catId)) then
                    -- Find specific child
                    for childId, childData in pairs(catData.children) do
                        if info.raid == childId then
                            table.insert(childData.groups, info)
                            childData.count = childData.count + 1
                            placed = true
                            break
                        end
                    end
                    -- Fallback to first child if no specific match
                    if not placed and info.raid == catId then
                        local firstChild = catData.children[catData.category.children[1].id]
                        if firstChild then
                            table.insert(firstChild.groups, info)
                            firstChild.count = firstChild.count + 1
                            placed = true
                        end
                    end
                    break
                end
            end
        end
    end

    return results
end

-- Get counts
function CS.GetGroupCount()
    local count = 0
    for _ in pairs(CS.Groups) do count = count + 1 end
    return count
end

function CS.GetPlayerCount()
    local count = 0
    for _ in pairs(CS.Players) do count = count + 1 end
    return count
end

-- Get counts by raid
function CS.GetCountsByRaid()
    local counts = {}
    local hierarchy = AIP.Parsers and AIP.Parsers.RaidHierarchy or {}

    for _, cat in ipairs(hierarchy) do
        counts[cat.id] = 0
        for _, child in ipairs(cat.children) do
            counts[child.id] = 0
        end
    end

    for leader, info in pairs(CS.Groups) do
        if counts[info.raid] then
            counts[info.raid] = counts[info.raid] + 1
        end
        -- Also count parent
        for _, cat in ipairs(hierarchy) do
            if info.raid and info.raid:find("^" .. cat.id) then
                counts[cat.id] = counts[cat.id] + 1
                break
            end
        end
    end

    return counts
end

-- ============================================================================
-- CLEAR FUNCTIONS
-- ============================================================================

-- Clear IN PLACE (wipe) rather than reassigning: the GroupTracker/LFMBrowser
-- compat aliases point at these same table objects, so replacing them would
-- orphan the aliases and permanently diverge the two views.
function CS.ClearGroups()
    wipe(CS.Groups)
    CS.NotifyUpdate("lfm")
    AIP.Print("Group listings cleared")
end

function CS.ClearPlayers()
    wipe(CS.Players)
    CS.NotifyUpdate("lfg")
    AIP.Print("Player listings cleared")
end

function CS.ClearAll()
    wipe(CS.Groups)
    wipe(CS.Players)
    CS.NotifyUpdate("lfm")
    CS.NotifyUpdate("lfg")
    AIP.Print("Chat scanner cleared")
end

-- Alias for compatibility
CS.ClearAllGroups = CS.ClearGroups

-- ============================================================================
-- PLAYER ACTIONS
-- ============================================================================

-- Invite a player from scanner
function CS.InvitePlayer(name)
    if name and CS.Players[name] then
        if AIP.InvitePlayer then
            AIP.InvitePlayer(name)
        end
        CS.Players[name].invited = true
        CS.NotifyUpdate("lfg")
    end
end

-- Ignore a player (add to blacklist)
function CS.IgnorePlayer(name)
    if name then
        CS.Players[name] = nil
        if AIP.AddToBlacklist then
            AIP.AddToBlacklist(name, "Ignored from chat scanner", "lfg")
        end
        CS.NotifyUpdate("lfg")
    end
end

-- ============================================================================
-- CHAT MESSAGE HANDLER (Single handler for all chat)
-- ============================================================================

function CS.OnChatMessage(message, author, channel)
    if not CS.Config.enabled then return end
    if not message or not author then return end

    -- Use Parsers module for parsing
    local info = nil
    if AIP.Parsers and AIP.Parsers.ParseChatMessage then
        info = AIP.Parsers.ParseChatMessage(message, author, channel)
    end

    if not info then return end

    -- Route to appropriate storage
    if info.isLFM then
        CS.AddGroup(info)
    end

    if info.isLFG then
        CS.AddPlayer(info)
    end
end

-- ============================================================================
-- EVENT HANDLING (Single frame for all events)
-- ============================================================================

local eventFrame = CreateFrame("Frame", "AIPChatScannerFrame")

local function OnEvent(self, event, message, author, ...)
    -- Use unified listen settings from AIP.db (same as auto-invite)
    local db = AIP.db or {}
    local shouldScan = false

    if event == "CHAT_MSG_CHANNEL" then
        -- Channel messages - check listenGlobal, listenAllJoined, or specific channel settings
        shouldScan = db.listenGlobal or db.listenAllJoined
    elseif event == "CHAT_MSG_SAY" then
        shouldScan = db.listenSay
    elseif event == "CHAT_MSG_YELL" then
        shouldScan = db.listenYell
    elseif event == "CHAT_MSG_GUILD" then
        shouldScan = db.listenGuild
    end

    if not shouldScan then return end

    -- Get channel info for channel messages
    local channel = event
    if event == "CHAT_MSG_CHANNEL" then
        -- CHAT_MSG_CHANNEL: within ... (arg3+), channelIndex is the 6th value.
        local _, _, _, _, _, channelIndex = ...
        channel = "Channel " .. (channelIndex or "?")
    end

    CS.OnChatMessage(message, author, channel)
end

eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:RegisterEvent("CHAT_MSG_SAY")
eventFrame:RegisterEvent("CHAT_MSG_YELL")
eventFrame:RegisterEvent("CHAT_MSG_GUILD")
eventFrame:SetScript("OnEvent", OnEvent)

-- Periodic cleanup (every 60 seconds)
local cleanupElapsed = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    cleanupElapsed = cleanupElapsed + elapsed
    if cleanupElapsed > 60 then
        cleanupElapsed = 0
        CS.Prune()
    end
end)

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Format time ago
function CS.FormatTimeAgo(seconds)
    if not seconds then return "-" end
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    else
        return math.floor(seconds / 3600) .. "h"
    end
end

-- ============================================================================
-- DATABUS INTEGRATION
-- Receive LFM/LFG events from other AutoInvite Plus users
-- ============================================================================

-- Handle incoming LFM event from DataBus
local function OnDataBusLFM(event)
    if not CS.Config.useDataBus then return end
    if not event or not event.sender or not event.data then return end

    local data = event.data

    -- Create group info from DataBus event
    -- Note: tanks/healers/mdps/rdps must be at top level for tree view display
    local info = {
        author = event.sender,
        raid = data.raid,
        raidCategory = data.raidCategory,
        -- Role composition at top level (required for tree view)
        tanks = data.tanks,
        healers = data.healers,
        mdps = data.mdps,
        rdps = data.rdps,
        dps = data.dps,  -- Backwards compatibility (will be converted to mdps/rdps if needed)
        -- Also store in composition for backwards compatibility
        composition = {
            tanks = data.tanks,
            healers = data.healers,
            mdps = data.mdps,
            rdps = data.rdps,
            dps = data.dps,
        },
        gs = data.gsMin,
        gsMin = data.gsMin,
        ilvlMin = data.ilvlMin,
        message = data.note or "",
        note = data.note,
        channel = "DataBus",
        time = event.timestamp,
        isLFM = true,
        isDataBus = true,           -- Mark as coming from DataBus
        triggerKey = data.triggerKey,
        inviteKeyword = data.triggerKey,
        version = event.version,
    }

    -- Add to groups (same as regular chat)
    CS.AddGroup(info)
end

-- Handle incoming LFG event from DataBus
local function OnDataBusLFG(event)
    if not CS.Config.useDataBus then return end
    if not event or not event.sender or not event.data then return end

    -- Skip own events
    if event.sender == UnitName("player") then return end

    -- Create player info from DataBus event
    local info = {
        author = event.sender,
        name = event.sender,
        raids = event.data.raids or {},
        raid = event.data.raids and event.data.raids[1] or nil,
        role = event.data.role,
        class = event.data.class,
        spec = event.data.spec,
        gs = event.data.gs,
        ilvl = event.data.ilvl,
        message = event.data.note or "",
        channel = "DataBus",
        time = event.timestamp,
        isLFG = true,
        isDataBus = true,           -- Mark as coming from DataBus
        version = event.version,
    }

    -- Add to players (same as regular chat)
    CS.AddPlayer(info)

    -- Auto-queue if autoQueueLFG is enabled and matches our active LFM
    if AIP.db and AIP.db.autoQueueLFG and CS.MatchesMyLFM(info) then
        local GUI = AIP.CentralGUI or {}
        if GUI.MyGroup and AIP.AddToQueue then
            local isBlacklisted = AIP.IsBlacklisted and AIP.IsBlacklisted(info.author)
            local isInQueue = AIP.IsInQueue and AIP.IsInQueue(info.author)
            if not isBlacklisted and not isInQueue then
                AIP.AddToQueue(info.author, info.message, info.role, info.gs, info.class)
                AIP.Print("|cFF00FF00Auto-queued|r " .. info.author .. " (matched your LFM)")
            end
        end
    end
end

-- Subscribe to DataBus events
function CS.InitDataBus()
    if not AIP.DataBus then
        -- DataBus not loaded yet, try again later
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(2, CS.InitDataBus)
        end
        return
    end

    -- Subscribe to LFM events
    AIP.DataBus.Subscribe("LFM", OnDataBusLFM, CS)

    -- Subscribe to LFG events
    AIP.DataBus.Subscribe("LFG", OnDataBusLFG, CS)

    AIP.Debug("ChatScanner: DataBus integration initialized")
end

-- Publish our LFM listing to DataBus
function CS.PublishLFM(lfmData)
    if not CS.Config.useDataBus then return false end
    if not AIP.DataBus then return false end

    return AIP.DataBus.BroadcastLFM(lfmData)
end

-- Publish our LFG listing to DataBus
function CS.PublishLFG(lfgData)
    if not CS.Config.useDataBus then return false end
    if not AIP.DataBus then return false end

    return AIP.DataBus.BroadcastLFG(lfgData)
end

-- Get groups from DataBus only
function CS.GetDataBusGroups(filters)
    local groups = CS.GetGroups(filters)
    local dataBusGroups = {}

    for _, group in ipairs(groups) do
        if group.isDataBus then
            table.insert(dataBusGroups, group)
        end
    end

    return dataBusGroups
end

-- Get players from DataBus only
function CS.GetDataBusPlayers(filters)
    local players = CS.GetPlayers(filters)
    local dataBusPlayers = {}

    for _, player in ipairs(players) do
        if player.isDataBus then
            table.insert(dataBusPlayers, player)
        end
    end

    return dataBusPlayers
end

-- Initialize DataBus connection after a delay
if AIP.Utils and AIP.Utils.DelayedCall then
    AIP.Utils.DelayedCall(3, CS.InitDataBus)
else
    -- Fallback: use a frame for delayed init
    local initFrame = CreateFrame("Frame")
    initFrame:RegisterEvent("PLAYER_LOGIN")
    initFrame:SetScript("OnEvent", function(self)
        self:SetScript("OnEvent", nil)
        -- Delay 3 seconds after login
        local delayFrame = CreateFrame("Frame")
        delayFrame.elapsed = 0
        delayFrame:SetScript("OnUpdate", function(df, elapsed)
            df.elapsed = df.elapsed + elapsed
            if df.elapsed >= 3 then
                df:SetScript("OnUpdate", nil)
                CS.InitDataBus()
            end
        end)
    end)
end

-- ============================================================================
-- COMPATIBILITY ALIASES
-- (For modules that still reference old GroupTracker/LFMBrowser)
-- ============================================================================

-- GroupTracker compatibility
AIP.GroupTracker = AIP.GroupTracker or {}
AIP.GroupTracker.Groups = CS.Groups
AIP.GroupTracker.GetGroupsByRaid = CS.GetGroupsByRaid
AIP.GroupTracker.GetAllGroups = CS.GetGroups
AIP.GroupTracker.GetGroupCount = CS.GetGroupCount
AIP.GroupTracker.GetCountsByRaid = CS.GetCountsByRaid
AIP.GroupTracker.ClearAll = CS.ClearGroups
AIP.GroupTracker.ClearAllGroups = CS.ClearGroups
AIP.GroupTracker.FormatTimeAgo = CS.FormatTimeAgo
AIP.GroupTracker.AddGroup = function(info)
    if info and info.leader then
        info.author = info.leader
    end
    CS.AddGroup(info)
end
AIP.GroupTracker.ParseLFMMessage = function(message, leader, channel)
    if AIP.Parsers and AIP.Parsers.ParseChatMessage then
        local info = AIP.Parsers.ParseChatMessage(message, leader, channel)
        if info and info.isLFM then
            info.leader = leader
            return info
        end
    end
    return nil
end
AIP.GroupTracker.Config = CS.Config
AIP.GroupTracker.RaidHierarchy = AIP.Parsers and AIP.Parsers.RaidHierarchy or {}

-- LFMBrowser compatibility
AIP.LFMBrowser = AIP.LFMBrowser or {}
AIP.LFMBrowser.Players = CS.Players
AIP.LFMBrowser.GetFilteredPlayers = CS.GetPlayers
AIP.LFMBrowser.GetPlayerCount = CS.GetPlayerCount
AIP.LFMBrowser.ClearAll = CS.ClearPlayers
AIP.LFMBrowser.InvitePlayer = CS.InvitePlayer
AIP.LFMBrowser.IgnorePlayer = CS.IgnorePlayer
AIP.LFMBrowser.FormatTimeAgo = CS.FormatTimeAgo
AIP.LFMBrowser.AddPlayer = function(info)
    if info and info.name then
        info.author = info.name
    end
    CS.AddPlayer(info)
end
AIP.LFMBrowser.ParseMessage = function(message, author, channel)
    if AIP.Parsers and AIP.Parsers.ParseChatMessage then
        local info = AIP.Parsers.ParseChatMessage(message, author, channel)
        if info then
            info.name = author
            return info
        end
    end
    return nil
end
AIP.LFMBrowser.Config = CS.Config

-- ============================================================================
-- SLASH COMMAND HANDLER
-- ============================================================================

function CS.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "show" then
        if AIP.CentralGUI then
            AIP.CentralGUI.Show("lfm")
        end
    elseif msg == "clear" then
        CS.ClearAll()
    elseif msg == "groups" then
        AIP.Print("Groups: " .. CS.GetGroupCount())
    elseif msg == "players" then
        AIP.Print("Players: " .. CS.GetPlayerCount())
    elseif msg == "enable" then
        CS.Config.enabled = true
        AIP.Print("Chat scanning enabled")
    elseif msg == "disable" then
        CS.Config.enabled = false
        AIP.Print("Chat scanning disabled")
    else
        AIP.Print("Chat Scanner commands:")
        AIP.Print("  /aip scan - Show browser")
        AIP.Print("  /aip scan clear - Clear all data")
        AIP.Print("  /aip scan enable/disable - Toggle scanning")
    end
end
