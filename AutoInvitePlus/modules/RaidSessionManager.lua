-- AutoInvite Plus - Raid Session Manager
-- Tracks raid sessions, boss kills, attendees, and loot for WotLK 3.3.5a

local AIP = AutoInvitePlus
AIP.RaidSession = {}
local RSM = AIP.RaidSession

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Boss name patterns for detection (combat log)
RSM.BossPatterns = {}

-- Build boss patterns from RaidComposition data
local function BuildBossPatterns()
    if not AIP.Composition or not AIP.Composition.RaidBosses then return end
    for raidKey, raidData in pairs(AIP.Composition.RaidBosses) do
        for _, bossName in ipairs(raidData.bosses or {}) do
            RSM.BossPatterns[bossName:lower()] = {
                name = bossName,
                raid = raidKey,
                zone = raidData.zone,
            }
        end
    end
end

-- ============================================================================
-- SESSION MANAGEMENT
-- ============================================================================

-- Get all sessions
function RSM.GetAllSessions()
    if not AIP.db then return {} end
    if not AIP.db.raidSessions then AIP.db.raidSessions = {} end
    return AIP.db.raidSessions
end

-- Get session by ID
function RSM.GetSession(id)
    if not id then return nil end
    local sessions = RSM.GetAllSessions()
    for _, session in ipairs(sessions) do
        if session.id == id then
            return session
        end
    end
    return nil
end

-- Get current active session
function RSM.GetCurrentSession()
    if not AIP.db or not AIP.db.currentRaidSessionId then return nil end
    return RSM.GetSession(AIP.db.currentRaidSessionId)
end

-- Start a new raid session
function RSM.StartSession(zone, size, mode)
    if not AIP.db then return nil end

    -- End any existing session first
    RSM.EndSession()

    local id = AIP.db.nextRaidSessionId or 1
    AIP.db.nextRaidSessionId = id + 1

    local session = {
        id = id,
        startTime = time(),
        endTime = nil,
        zone = zone or GetRealZoneText() or "Unknown",
        size = size or RSM.GetRaidSize(),
        mode = mode or RSM.GetDifficultyMode(),
        bosses = {},
        attendees = {},
        loot = {},
    }

    if not AIP.db.raidSessions then AIP.db.raidSessions = {} end
    table.insert(AIP.db.raidSessions, 1, session)  -- Insert at beginning (newest first)

    AIP.db.currentRaidSessionId = id
    AIP.Debug("RaidSession: Started session #" .. id .. " in " .. session.zone)

    -- Snapshot current raid roster as initial attendees
    RSM.SnapshotCurrentRoster(session)

    return session
end

-- End current session
function RSM.EndSession()
    local session = RSM.GetCurrentSession()
    if session and not session.endTime then
        session.endTime = time()
        AIP.Debug("RaidSession: Ended session #" .. session.id)
    end
    AIP.db.currentRaidSessionId = nil
end

-- Delete a session
function RSM.DeleteSession(id)
    if not AIP.db or not AIP.db.raidSessions then return false end

    for i, session in ipairs(AIP.db.raidSessions) do
        if session.id == id then
            table.remove(AIP.db.raidSessions, i)
            AIP.Debug("RaidSession: Deleted session #" .. id)
            return true
        end
    end
    return false
end

-- Set selected session for UI viewing
function RSM.SetSelectedSession(id)
    if AIP.db then
        AIP.db.selectedRaidSessionId = id
        AIP.db.selectedBossId = nil  -- Reset boss selection
    end
end

-- Get selected session
function RSM.GetSelectedSession()
    if not AIP.db or not AIP.db.selectedRaidSessionId then return nil end
    return RSM.GetSession(AIP.db.selectedRaidSessionId)
end

-- ============================================================================
-- BOSS KILL TRACKING
-- ============================================================================

-- Add a boss kill to current session
function RSM.AddBossKill(bossName, mode)
    local session = RSM.GetCurrentSession()
    if not session then
        -- Auto-start session if in raid
        local numRaid = GetNumRaidMembers() or 0
        if numRaid > 0 then
            session = RSM.StartSession()
        end
        if not session then return nil end
    end

    local bossId = #session.bosses + 1
    local attendees = RSM.GetCurrentRosterNames()

    local bossKill = {
        id = bossId,
        name = bossName,
        killTime = time(),
        mode = mode or session.mode,
        attendees = attendees,
    }

    table.insert(session.bosses, bossKill)
    AIP.Debug("RaidSession: Boss kill recorded - " .. bossName .. " with " .. #attendees .. " attendees")

    -- Notify UI to refresh
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.RefreshAll then
        AIP.Panels.LootHistory.RefreshAll()
    end

    return bossKill
end

-- Get boss by ID from session
function RSM.GetBoss(sessionId, bossId)
    local session = RSM.GetSession(sessionId)
    if not session or not session.bosses then return nil end

    for _, boss in ipairs(session.bosses) do
        if boss.id == bossId then
            return boss
        end
    end
    return nil
end

-- Get boss attendees
function RSM.GetBossAttendees(sessionId, bossId)
    local boss = RSM.GetBoss(sessionId, bossId)
    if boss then
        return boss.attendees or {}
    end
    return {}
end

-- ============================================================================
-- ATTENDEE TRACKING
-- ============================================================================

-- Snapshot current raid roster
function RSM.SnapshotCurrentRoster(session)
    if not session then session = RSM.GetCurrentSession() end
    if not session then return end

    local now = time()
    local currentNames = RSM.GetCurrentRosterNames()
    local existingNames = {}

    -- Mark existing attendees
    for _, att in ipairs(session.attendees) do
        existingNames[att.name:lower()] = att
    end

    -- Add new attendees
    for _, name in ipairs(currentNames) do
        if not existingNames[name:lower()] then
            table.insert(session.attendees, {
                name = name,
                joinTime = now,
                leaveTime = nil,
            })
        end
    end
end

-- Track player join
function RSM.TrackPlayerJoin(name)
    local session = RSM.GetCurrentSession()
    if not session then return end

    -- Check if already tracked
    for _, att in ipairs(session.attendees) do
        if att.name:lower() == name:lower() then
            if att.leaveTime then
                -- Rejoined - clear leave time
                att.leaveTime = nil
            end
            return
        end
    end

    -- New attendee
    table.insert(session.attendees, {
        name = name,
        joinTime = time(),
        leaveTime = nil,
    })
    AIP.Debug("RaidSession: " .. name .. " joined")
end

-- Track player leave
function RSM.TrackPlayerLeave(name)
    local session = RSM.GetCurrentSession()
    if not session then return end

    for _, att in ipairs(session.attendees) do
        if att.name:lower() == name:lower() and not att.leaveTime then
            att.leaveTime = time()
            AIP.Debug("RaidSession: " .. name .. " left")
            return
        end
    end
end

-- Get session attendees
function RSM.GetSessionAttendees(sessionId)
    local session = RSM.GetSession(sessionId)
    if session then
        return session.attendees or {}
    end
    return {}
end

-- ============================================================================
-- LOOT TRACKING
-- ============================================================================

-- Add loot to current session
function RSM.AddLoot(itemLink, looter, source)
    local session = RSM.GetCurrentSession()
    if not session then return nil end

    local itemName, _, itemQuality, itemLevel = GetItemInfo(itemLink)
    if not itemName then
        -- Item info not cached, will be handled by pending system
        return nil
    end

    -- Check quality threshold
    local threshold = AIP.db and AIP.db.lootTrackThreshold or 2
    if itemQuality and itemQuality < threshold then return nil end

    local itemId = itemLink:match("item:(%d+)")

    -- Find matching boss
    local bossId = nil
    if source and #session.bosses > 0 then
        -- Match to most recent boss with similar name
        for i = #session.bosses, 1, -1 do
            local boss = session.bosses[i]
            if boss.name:lower():find(source:lower(), 1, true) or
               source:lower():find(boss.name:lower(), 1, true) then
                bossId = boss.id
                break
            end
        end
        -- If no match, assign to most recent boss
        if not bossId and #session.bosses > 0 then
            bossId = session.bosses[#session.bosses].id
        end
    end

    local entry = {
        itemLink = itemLink,
        itemName = itemName,
        itemId = tonumber(itemId),
        itemQuality = itemQuality or 1,
        itemLevel = itemLevel or 0,
        bossId = bossId,
        winner = looter or "Unknown",
        timestamp = time(),
        source = source or "Unknown",
    }

    table.insert(session.loot, entry)
    AIP.Debug("RaidSession: Loot recorded - " .. itemName .. " to " .. (looter or "Unknown"))

    -- Notify UI to refresh
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.RefreshAll then
        AIP.Panels.LootHistory.RefreshAll()
    end

    return entry
end

-- Get session loot
function RSM.GetSessionLoot(sessionId, bossId)
    local session = RSM.GetSession(sessionId)
    if not session then return {} end

    local loot = session.loot or {}

    -- Filter by boss if specified
    if bossId then
        local filtered = {}
        for _, entry in ipairs(loot) do
            if entry.bossId == bossId then
                table.insert(filtered, entry)
            end
        end
        return filtered
    end

    return loot
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get current raid size
function RSM.GetRaidSize()
    local numRaid = GetNumRaidMembers() or 0
    if numRaid > 0 then
        return numRaid <= 10 and 10 or 25
    end
    return 0
end

-- Get difficulty mode (WotLK)
function RSM.GetDifficultyMode()
    local diff = GetInstanceDifficulty() or 1
    -- 1 = 10N, 2 = 25N, 3 = 10HC, 4 = 25HC
    if diff == 3 or diff == 4 then
        return "heroic"
    end
    return "normal"
end

-- Get current roster as name array
function RSM.GetCurrentRosterNames()
    local names = {}
    local numRaid = GetNumRaidMembers() or 0

    if numRaid > 0 then
        for i = 1, numRaid do
            local name = UnitName("raid" .. i)
            if name then
                table.insert(names, name)
            end
        end
    else
        local numParty = GetNumPartyMembers() or 0
        local playerName = UnitName("player")
        if playerName then
            table.insert(names, playerName)
        end
        for i = 1, numParty do
            local name = UnitName("party" .. i)
            if name then
                table.insert(names, name)
            end
        end
    end

    return names
end

-- ============================================================================
-- MIGRATION FROM OLD LOOT HISTORY
-- ============================================================================

function RSM.MigrateOldLootHistory()
    if not AIP.db then return end
    if not AIP.db.lootHistory or #AIP.db.lootHistory == 0 then return end

    -- Check if already migrated
    if AIP.db.lootHistoryMigrated then return end

    AIP.Print("Migrating old loot history to new raid sessions format...")

    -- Group old entries by date and zone
    local groups = {}
    for _, entry in ipairs(AIP.db.lootHistory) do
        local date = entry.timestamp and date("%Y-%m-%d", entry.timestamp) or "unknown"
        local zone = entry.zone or "Unknown"
        local key = date .. "|" .. zone

        if not groups[key] then
            groups[key] = {
                date = date,
                zone = zone,
                timestamp = entry.timestamp or time(),
                loot = {},
            }
        end
        table.insert(groups[key].loot, entry)
    end

    -- Create sessions from groups
    if not AIP.db.raidSessions then AIP.db.raidSessions = {} end
    local sessionId = AIP.db.nextRaidSessionId or 1

    for key, group in pairs(groups) do
        local session = {
            id = sessionId,
            startTime = group.timestamp,
            endTime = group.timestamp + 3600,  -- Assume 1 hour
            zone = group.zone,
            size = 25,  -- Assume 25-man
            mode = "normal",
            bosses = {},
            attendees = {},
            loot = {},
        }

        -- Convert loot entries
        local bossesFound = {}
        for _, entry in ipairs(group.loot) do
            local bossName = entry.source or "Unknown"

            -- Create boss entry if new
            if not bossesFound[bossName] then
                local bossId = #session.bosses + 1
                table.insert(session.bosses, {
                    id = bossId,
                    name = bossName,
                    killTime = entry.timestamp or group.timestamp,
                    mode = "normal",
                    attendees = {},
                })
                bossesFound[bossName] = bossId
            end

            -- Add loot entry
            table.insert(session.loot, {
                itemLink = entry.itemLink,
                itemName = entry.itemName,
                itemId = entry.itemId,
                itemQuality = entry.itemQuality,
                itemLevel = entry.itemLevel,
                bossId = bossesFound[bossName],
                winner = entry.looter or "Unknown",
                timestamp = entry.timestamp,
                source = entry.source,
            })

            -- Track looter as attendee
            if entry.looter then
                local found = false
                for _, att in ipairs(session.attendees) do
                    if att.name:lower() == entry.looter:lower() then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(session.attendees, {
                        name = entry.looter,
                        joinTime = group.timestamp,
                        leaveTime = nil,
                    })
                end
            end
        end

        table.insert(AIP.db.raidSessions, session)
        sessionId = sessionId + 1
    end

    AIP.db.nextRaidSessionId = sessionId
    AIP.db.lootHistoryMigrated = true

    AIP.Print("Migration complete. Created " .. #AIP.db.raidSessions .. " raid sessions from old history.")
end

-- ============================================================================
-- EXPORT
-- ============================================================================

function RSM.ExportSession(sessionId)
    local session = RSM.GetSession(sessionId)
    if not session then return nil end

    local lines = {}
    table.insert(lines, "=== Raid Session Export ===")
    table.insert(lines, "Zone: " .. (session.zone or "Unknown"))
    table.insert(lines, "Date: " .. date("%Y-%m-%d %H:%M", session.startTime or time()))
    table.insert(lines, "Size: " .. (session.size or "?") .. "-man " .. (session.mode or "normal"))
    table.insert(lines, "")

    if session.bosses and #session.bosses > 0 then
        table.insert(lines, "--- Boss Kills ---")
        for _, boss in ipairs(session.bosses) do
            table.insert(lines, boss.name .. " (" .. #(boss.attendees or {}) .. " present)")
        end
        table.insert(lines, "")
    end

    if session.attendees and #session.attendees > 0 then
        table.insert(lines, "--- Attendees (" .. #session.attendees .. ") ---")
        local names = {}
        for _, att in ipairs(session.attendees) do
            table.insert(names, att.name)
        end
        table.insert(lines, table.concat(names, ", "))
        table.insert(lines, "")
    end

    if session.loot and #session.loot > 0 then
        table.insert(lines, "--- Loot (" .. #session.loot .. " items) ---")
        for _, entry in ipairs(session.loot) do
            local bossName = "Unknown"
            if entry.bossId and session.bosses then
                for _, b in ipairs(session.bosses) do
                    if b.id == entry.bossId then
                        bossName = b.name
                        break
                    end
                end
            end
            table.insert(lines, (entry.itemName or "?") .. " - " .. (entry.winner or "?") .. " (" .. bossName .. ")")
        end
    end

    return table.concat(lines, "\n")
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local eventFrame = CreateFrame("Frame")
local previousRoster = {}

-- Track roster changes
local function OnRosterUpdate()
    if not AIP.db then return end

    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    -- Check if we should have an active session
    if numRaid > 0 then
        -- In raid - ensure session exists
        if not RSM.GetCurrentSession() then
            RSM.StartSession()
        end

        -- Track join/leave
        local currentNames = {}
        for i = 1, numRaid do
            local name = UnitName("raid" .. i)
            if name then
                currentNames[name:lower()] = true
                if not previousRoster[name:lower()] then
                    RSM.TrackPlayerJoin(name)
                end
            end
        end

        -- Check for leaves
        for name in pairs(previousRoster) do
            if not currentNames[name] then
                -- Player left
                local properName = name:sub(1,1):upper() .. name:sub(2)
                RSM.TrackPlayerLeave(properName)
            end
        end

        previousRoster = currentNames
    elseif numParty > 0 then
        -- In party but not raid - could be pre-raid
        previousRoster = {}
    else
        -- Not in group - end session if active
        if RSM.GetCurrentSession() then
            RSM.EndSession()
        end
        previousRoster = {}
    end
end

-- Boss kill detection via combat log
local function OnCombatLogEvent(...)
    local timestamp, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags = CombatLogGetCurrentEventInfo
        and CombatLogGetCurrentEventInfo()
        or select(1, ...)

    -- WotLK uses different argument order
    if not event then
        timestamp, event, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags =
            select(2, ...), select(3, ...), select(4, ...), select(5, ...),
            select(6, ...), select(7, ...), select(8, ...), select(9, ...)
    end

    if event == "UNIT_DIED" and dstName then
        -- Build patterns if needed
        if next(RSM.BossPatterns) == nil then
            BuildBossPatterns()
        end

        -- Check if it's a boss
        local bossInfo = RSM.BossPatterns[dstName:lower()]
        if bossInfo then
            RSM.AddBossKill(bossInfo.name, RSM.GetDifficultyMode())
        else
            -- Fallback: check unit classification if targetable
            local classification = UnitClassification("target")
            if classification == "worldboss" or classification == "rareelite" then
                RSM.AddBossKill(dstName, RSM.GetDifficultyMode())
            end
        end
    end
end

-- Zone change detection
local function OnZoneChange()
    local session = RSM.GetCurrentSession()
    local currentZone = GetRealZoneText() or ""

    -- If in raid and zone changed to different raid zone, might want to start new session
    local numRaid = GetNumRaidMembers() or 0
    if numRaid > 0 then
        if not session then
            RSM.StartSession(currentZone)
        elseif session.zone ~= currentZone then
            -- Zone changed - update session zone
            session.zone = currentZone
            AIP.Debug("RaidSession: Zone changed to " .. currentZone)
        end
    end
end

eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        OnRosterUpdate()
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLogEvent(...)
    elseif event == "ZONE_CHANGED_NEW_AREA" then
        OnZoneChange()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Build boss patterns
        BuildBossPatterns()
        -- Run migration if needed
        RSM.MigrateOldLootHistory()
        -- Check if we should resume a session
        OnRosterUpdate()
    end
end)

-- ============================================================================
-- INTEGRATE WITH EXISTING LOOT TRACKING
-- ============================================================================

-- Hook into existing loot event system
local function HookLootTracking()
    local LH = AIP.Panels and AIP.Panels.LootHistory
    if LH and LH.AddLootEntry then
        local originalAddLoot = LH.AddLootEntry
        LH.AddLootEntry = function(itemLink, looter, source, zone)
            -- Call original
            originalAddLoot(itemLink, looter, source, zone)
            -- Also add to session
            RSM.AddLoot(itemLink, looter, source)
        end
    end
end

-- Hook after panels load
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_LOGIN")
hookFrame:SetScript("OnEvent", function()
    -- Delay hook to ensure panels are loaded
    local frame = CreateFrame("Frame")
    frame.elapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed > 2 then
            self:SetScript("OnUpdate", nil)
            HookLootTracking()
        end
    end)
end)
