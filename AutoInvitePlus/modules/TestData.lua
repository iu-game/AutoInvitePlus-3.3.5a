-- AutoInvite Plus - Test Data Module
-- Generates mock data for UI testing without requiring live game data

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r TestData: AutoInvitePlus namespace not found!")
    return
end

AIP.TestData = {}
local TD = AIP.TestData

-- Flag to track test data state
TD.testDataActive = false
TD.originalData = {}

-- Sample player names (lore-friendly)
local TEST_NAMES = {
    "Arthas", "Thrall", "Jaina", "Sylvanas", "Varian",
    "Tirion", "Garrosh", "Saurfang", "Bolvar", "Darion",
    "Koltira", "Thassarian", "Fordring", "Mograine", "Uther",
    "Muradin", "Magni", "Brann", "Rhonin", "Krasus",
    "Alexstrasza", "Ysera", "Malygos", "Nozdormu", "Deathwing",
    "Illidan", "Malfurion", "Tyrande", "Cenarius", "Furion",
    "Cairne", "Baine", "Voljin", "Zekhan", "Rastakhan"
}

-- Class data
local CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID"
}

local CLASS_SPECS = {
    WARRIOR = {"Arms", "Fury", "Protection"},
    PALADIN = {"Holy", "Protection", "Retribution"},
    HUNTER = {"Beast Mastery", "Marksmanship", "Survival"},
    ROGUE = {"Assassination", "Combat", "Subtlety"},
    PRIEST = {"Discipline", "Holy", "Shadow"},
    DEATHKNIGHT = {"Blood", "Frost", "Unholy"},
    SHAMAN = {"Elemental", "Enhancement", "Restoration"},
    MAGE = {"Arcane", "Fire", "Frost"},
    WARLOCK = {"Affliction", "Demonology", "Destruction"},
    DRUID = {"Balance", "Feral Combat", "Restoration"}
}

local SPEC_ROLES = {
    -- Tanks
    ["WARRIORProtection"] = "TANK",
    ["PALADINProtection"] = "TANK",
    ["DEATHKNIGHTBlood"] = "TANK",
    ["DRUIDFeral Combat"] = "TANK",  -- Can be DPS too
    -- Healers
    ["PALADINHoly"] = "HEALER",
    ["PRIESTDiscipline"] = "HEALER",
    ["PRIESTHoly"] = "HEALER",
    ["SHAMANRestoration"] = "HEALER",
    ["DRUIDRestoration"] = "HEALER",
}

local RAIDS = {
    {key = "ICC25H", name = "Icecrown Citadel 25 Heroic", size = 25},
    {key = "ICC25N", name = "Icecrown Citadel 25 Normal", size = 25},
    {key = "ICC10H", name = "Icecrown Citadel 10 Heroic", size = 10},
    {key = "TOC25H", name = "Trial of the Grand Crusader 25", size = 25},
    {key = "RS25H", name = "Ruby Sanctum 25 Heroic", size = 25},
    {key = "VoA25", name = "Vault of Archavon 25", size = 25},
    {key = "Ony25", name = "Onyxia's Lair 25", size = 25},
}

local BOSS_NAMES = {
    ICC = {"Lord Marrowgar", "Lady Deathwhisper", "Gunship Battle", "Deathbringer Saurfang",
           "Festergut", "Rotface", "Professor Putricide", "Blood Prince Council",
           "Blood-Queen Lana'thel", "Valithria Dreamwalker", "Sindragosa", "The Lich King"},
    TOC = {"Northrend Beasts", "Lord Jaraxxus", "Faction Champions", "Twin Val'kyr", "Anub'arak"},
    RS = {"Baltharus", "Saviana", "Zarithrian", "Halion"},
    VoA = {"Archavon", "Emalon", "Koralon", "Toravon"},
}

local LOOT_ITEMS = {
    -- ICC items
    {id = 50274, name = "Shadowfrost Shard"},
    {id = 50226, name = "Festergut's Acidic Blood"},
    {id = 50231, name = "Rotface's Acidic Blood"},
    {id = 50454, name = "Deathbringer's Will"},
    {id = 50363, name = "Havoc's Call"},
    {id = 50732, name = "Glorenzelg"},
    {id = 50761, name = "Sindragosa's Cruel Claw"},
    {id = 50365, name = "Protector of the Frigid Maw"},
    -- Generic test items
    {id = 49623, name = "Shadowmourne"},
    {id = 50708, name = "Invincible's Reins"},
}

-- Helper: Get random element from table
local function RandomElement(tbl)
    return tbl[math.random(1, #tbl)]
end

-- Helper: Generate random GS (5000-6500 range for ICC)
local function RandomGS()
    return math.random(5000, 6500)
end

-- Helper: Generate random iLvl (232-277 range for ICC)
local function RandomIlvl()
    return math.random(232, 277)
end

-- Helper: Generate random player data
local function GenerateRandomPlayer(index)
    local name = TEST_NAMES[((index - 1) % #TEST_NAMES) + 1]
    local class = RandomElement(CLASSES)
    local spec = RandomElement(CLASS_SPECS[class])
    local roleKey = class .. spec
    local role = SPEC_ROLES[roleKey] or "DPS"

    return {
        name = name .. tostring(index),
        class = class,
        spec = spec,
        role = role,
        gs = RandomGS(),
        ilvl = RandomIlvl(),
        online = math.random(1, 10) > 2,  -- 80% online
        level = 80,
    }
end

-- Generate test LFM groups
function TD.GenerateLFMGroups(count)
    count = count or 5

    if AIP.ChatScanner then
        AIP.ChatScanner.Groups = AIP.ChatScanner.Groups or {}
    end

    for i = 1, count do
        local raid = RandomElement(RAIDS)
        local leader = TEST_NAMES[((i - 1) % #TEST_NAMES) + 1] .. "Leader" .. i
        local gsMin = math.random(5200, 6000)
        local tanksNeeded = raid.size == 25 and math.random(2, 3) or math.random(1, 2)
        local healersNeeded = raid.size == 25 and math.random(5, 7) or math.random(2, 3)
        local dpsNeeded = raid.size - tanksNeeded - healersNeeded

        local groupData = {
            leader = leader,
            raid = raid.key,
            message = string.format("LFM %s [T:0/%d H:0/%d D:0/%d] %d+ GS w/ \"inv\"",
                raid.key, tanksNeeded, healersNeeded, dpsNeeded, gsMin),
            gsMin = gsMin,
            ilvlMin = math.floor(gsMin / 24),
            tanks = {current = math.random(0, tanksNeeded - 1), needed = tanksNeeded},
            healers = {current = math.random(0, healersNeeded - 1), needed = healersNeeded},
            dps = {current = math.random(0, dpsNeeded - 5), needed = dpsNeeded},
            time = time() - math.random(0, 600),  -- Within last 10 minutes
            isOwn = false,
            inviteKeyword = "inv",
            _testData = true,
        }

        if AIP.ChatScanner then
            AIP.ChatScanner.Groups[leader] = groupData
        end

        -- Also add to GroupTracker for compatibility
        if AIP.GroupTracker and AIP.GroupTracker.Groups then
            AIP.GroupTracker.Groups[leader] = groupData
        end
    end
end

-- Generate test LFG players
function TD.GenerateLFGPlayers(count)
    count = count or 10

    if AIP.ChatScanner then
        AIP.ChatScanner.Players = AIP.ChatScanner.Players or {}
    end

    for i = 1, count do
        local player = GenerateRandomPlayer(i)
        local raid = RandomElement(RAIDS)

        local playerData = {
            name = player.name,
            class = player.class,
            spec = player.spec,
            role = player.role,
            gs = player.gs,
            ilvl = player.ilvl,
            raid = raid.key,
            message = string.format("LFG %s %s (%s) %s %d GS",
                raid.key, player.class, player.spec, player.role, player.gs),
            time = time() - math.random(0, 600),
            _testData = true,
        }

        if AIP.ChatScanner then
            AIP.ChatScanner.Players[player.name] = playerData
        end
    end
end

-- Generate test raid sessions for Loot History
function TD.GenerateRaidSessions(count)
    count = count or 3
    AIP.db = AIP.db or {}
    AIP.db.raidSessions = AIP.db.raidSessions or {}

    for i = 1, count do
        local raid = RAIDS[((i - 1) % #RAIDS) + 1]
        local sessionTime = time() - (i * 86400) - math.random(0, 43200)  -- Days ago
        local duration = math.random(7200, 14400)  -- 2-4 hours

        -- Attendees: array of {name, joinTime, leaveTime} (matches RaidSessionManager)
        local attendees = {}
        local attendeeNames = {}
        local numAttendees = math.random(math.floor(raid.size * 0.8), raid.size)
        for j = 1, numAttendees do
            local player = GenerateRandomPlayer(j)
            attendeeNames[j] = player.name
            table.insert(attendees, {
                name = player.name,
                joinTime = sessionTime + math.random(0, 600),
                leaveTime = nil,
            })
        end

        -- Bosses: array of {id, name, killTime, attendees=[names]}; loot is at session level
        local bosses = {}
        local loot = {}
        local bossPrefix = raid.key:match("^(%u+)")
        local bossList = BOSS_NAMES[bossPrefix] or BOSS_NAMES.ICC
        local numBosses = math.random(math.floor(#bossList * 0.5), #bossList)

        for b = 1, numBosses do
            local bossName = bossList[b]
            local killTime = sessionTime + (b * math.floor(duration / numBosses))

            table.insert(bosses, {
                id = b,
                name = bossName,
                killTime = killTime,
                attendees = attendeeNames,  -- array of name strings
            })

            -- Loot drops for this boss (session.loot array, with bossId link)
            local numDrops = math.random(1, 3)
            for k = 1, numDrops do
                local item = RandomElement(LOOT_ITEMS)
                local winner = RandomElement(TEST_NAMES) .. tostring(math.random(1, 99))
                table.insert(loot, {
                    itemId = item.id,
                    itemName = item.name,
                    itemLink = "|cffff8000|Hitem:" .. item.id .. "::::::::80:::::|h[" .. item.name .. "]|h|r",
                    itemQuality = 4,
                    itemLevel = math.random(245, 284),
                    bossId = b,
                    winner = winner,
                    source = bossName,
                    timestamp = killTime + math.random(10, 60),
                })
            end
        end

        local session = {
            id = 900000 + i,  -- high id, won't collide with real (incrementing) session ids
            zone = raid.name,
            mode = (raid.key:find("H") and (raid.size .. " Heroic")) or (raid.size .. " Normal"),
            startTime = sessionTime,
            endTime = sessionTime + duration,
            bosses = bosses,
            attendees = attendees,
            loot = loot,
            _testData = true,
        }

        table.insert(AIP.db.raidSessions, 1, session)  -- Insert at beginning (most recent first)
    end
end

-- Generate test loot bans
function TD.GenerateLootBans(count)
    count = count or 5
    AIP.db = AIP.db or {}
    AIP.db.lootBans = AIP.db.lootBans or {}

    local bossList = {"Festergut", "Rotface", "Sindragosa", "The Lich King", "Professor Putricide"}
    local bossDropTypes = {"All Loot", "Tokens", "Weapons", "Trinkets"}

    for i = 1, count do
        local player = TEST_NAMES[((i - 1) % #TEST_NAMES) + 1] .. "Banned" .. i
        local boss = bossList[((i - 1) % #bossList) + 1]
        local dropType = bossDropTypes[((i - 1) % #bossDropTypes) + 1]

        table.insert(AIP.db.lootBans, {
            player = player,
            boss = boss,
            dropType = dropType,
            reason = "Test ban reason " .. i,
            addedBy = UnitName("player") or "TestLeader",
            timestamp = time() - math.random(0, 604800),  -- Within last week
            _testData = true,
        })
    end
end

-- Generate test blacklist entries
function TD.GenerateBlacklist(count)
    count = count or 5
    AIP.db = AIP.db or {}
    AIP.db.blacklist = AIP.db.blacklist or {}

    local reasons = {
        "Ninja looted",
        "Left raid early",
        "Refused to follow mechanics",
        "AFK during boss fights",
        "Toxic behavior",
    }

    for i = 1, count do
        local player = TEST_NAMES[((i - 1) % #TEST_NAMES) + 1] .. "Blocked" .. i

        table.insert(AIP.db.blacklist, {
            name = player,
            reason = reasons[((i - 1) % #reasons) + 1],
            source = "manual",
            timestamp = time() - math.random(0, 2592000),  -- Within last month
            _testData = true,
        })
    end
end

-- Generate test favorites
function TD.GenerateFavorites(count)
    count = count or 5
    AIP.db = AIP.db or {}
    -- Favorites live in `whitelist`, keyed by lowercase name (see Core.AddToFavorites
    -- and FavoritesPanel). Writing to a separate `favorites` array meant test
    -- favorites never appeared in the UI.
    AIP.db.whitelist = AIP.db.whitelist or {}

    local notes = {
        "Great tank, very skilled",
        "Reliable healer, always shows up",
        "Top DPS, good attitude",
        "Knows all mechanics",
        "Guild friend",
    }

    for i = 1, count do
        local player = GenerateRandomPlayer(20 + i)

        AIP.db.whitelist[player.name:lower()] = {
            name = player.name,
            class = player.class,
            note = notes[((i - 1) % #notes) + 1],
            gs = player.gs,
            source = "manual",
            addedTime = time() - math.random(0, 2592000),
            _testData = true,
        }
    end
end

-- Generate test queue entries (LFM Browser > Queue sub-tab)
function TD.GenerateQueue(count)
    count = count or 30
    AIP.db = AIP.db or {}
    AIP.db.queue = AIP.db.queue or {}
    for i = 1, count do
        local p = GenerateRandomPlayer(i)
        table.insert(AIP.db.queue, {
            name = p.name,
            class = p.class,
            spec = p.spec,
            role = p.role,
            gs = p.gs,
            ilvl = p.ilvl,
            message = "inv " .. p.role .. " " .. p.gs .. "gs",
            time = time() - math.random(0, 1800),
            isLfgEnrollment = false,
            _testData = true,
        })
    end
end

-- Generate test waitlist entries (LFM Browser > Waitlist sub-tab)
function TD.GenerateWaitlist(count)
    count = count or 30
    AIP.db = AIP.db or {}
    AIP.db.waitlist = AIP.db.waitlist or {}
    for i = 1, count do
        local p = GenerateRandomPlayer(i + 400)
        table.insert(AIP.db.waitlist, {
            name = p.name,
            class = p.class,
            role = p.role,
            gs = p.gs,
            addedTime = time() - math.random(0, 3600),
            priority = #AIP.db.waitlist + 1,
            note = "Test waitlist",
            _testData = true,
        })
    end
end

-- Generate Raid Mgmt extras: reserved items + MS/OS tracking
-- (reservedItems is a single string; the original is backed up in LoadTestData
--  and restored by ClearTestData. MS/OS entries are keyed and marked _testData.)
function TD.GenerateRaidMgmt(count)
    count = count or 30
    AIP.db = AIP.db or {}

    AIP.db.reservedItems = "Shadowmourne\nInvincible's Reins\nDeathbringer's Will\nHeroic Trinket\nFragment of Val'anyr"

    AIP.db.msTracking = AIP.db.msTracking or {}
    for i = 1, count do
        local p = GenerateRandomPlayer(i + 800)
        local specs = CLASS_SPECS[p.class] or {p.spec}
        AIP.db.msTracking[p.name] = {
            ms = p.spec,
            os = specs[(i % #specs) + 1],
            _testData = true,
        }
    end
end

-- Generate test data for the Loot Roll window (RaidTools):
-- a live "current" raid session with fresh, rollable loot (some near expiry so
-- the expiration warnings show), a couple of manual items, and a sample set of
-- captured rolls so the Rolls / winners column is populated.
function TD.GenerateRollData()
    AIP.db = AIP.db or {}
    AIP.db.raidSessions = AIP.db.raidSessions or {}

    local now = time()

    -- Roster snapshot
    local attendees, names = {}, {}
    for j = 1, 25 do
        local p = GenerateRandomPlayer(j)
        names[j] = p.name
        table.insert(attendees, { name = p.name, joinTime = now - 3600, leaveTime = nil })
    end

    local bosses = {
        { id = 1, name = "Lord Marrowgar",   killTime = now - 1800, attendees = names },
        { id = 2, name = "Lady Deathwhisper", killTime = now - 900,  attendees = names },
    }

    -- Fresh, un-won loot. Ages span the 2h trade window; the last few are within
    -- 15m of expiry (>6300s old) so they render red with a warning.
    local ages = { 90, 600, 1500, 2700, 3900, 5100, 6000, 6450, 6750, 7050 }
    local loot = {}
    for k = 1, #ages do
        local it = LOOT_ITEMS[((k - 1) % #LOOT_ITEMS) + 1]
        table.insert(loot, {
            itemId = it.id,
            itemName = it.name,
            itemLink = "|cffa335ee|Hitem:" .. it.id .. "::::::::80:::::|h[" .. it.name .. "]|h|r",
            itemQuality = 4,
            itemLevel = 264,
            bossId = ((k - 1) % 2) + 1,
            winner = nil,           -- nil = still rollable
            source = bosses[((k - 1) % 2) + 1].name,
            timestamp = now - ages[k],
            _testData = true,
        })
    end

    local session = {
        id = 999999,
        zone = "Icecrown Citadel (Test Roll)",
        mode = "25 Heroic",
        startTime = now - 3600,
        endTime = nil,             -- nil = active/current
        bosses = bosses,
        attendees = attendees,
        loot = loot,
        _testData = true,
    }
    table.insert(AIP.db.raidSessions, 1, session)
    AIP.db.currentRaidSessionId = 999999

    -- Roll window state: manual items + a finished sample roll set
    local RT = AIP.RaidTools
    if RT then
        RT.manualItems = RT.manualItems or {}
        table.insert(RT.manualItems, { name = "Shadowmourne", quality = 5,
            link = "|cffe6cc80|Hitem:49623::::::::80:::::|h[Shadowmourne]|h|r", timestamp = now })
        table.insert(RT.manualItems, { name = "Invincible's Reins", quality = 5,
            link = "|cffe6cc80|Hitem:50818::::::::80:::::|h[Invincible's Reins]|h|r", timestamp = now })

        RT.rolls = {}
        for j = 1, 9 do
            RT.rolls[names[j]] = math.random(1, 100)
        end
        RT.rollItem = "Deathbringer's Will"
        RT.rollItemLink = "|cffa335ee|Hitem:50709::::::::80:::::|h[Deathbringer's Will]|h|r"
        RT.rollActive = false
        if RT.RefreshRollWindow then RT.RefreshRollWindow() end
    end
end

-- Helper to refresh all UI panels
function TD.RefreshAllUI()
    -- Refresh CentralGUI tabs
    if AIP.CentralGUI then
        if AIP.CentralGUI.RefreshBrowserTab then
            AIP.CentralGUI.RefreshBrowserTab("lfm")
            AIP.CentralGUI.RefreshBrowserTab("lfg")
        end
        if AIP.CentralGUI.UpdateCompositionTab then
            AIP.CentralGUI.UpdateCompositionTab()
        end
    end

    -- Refresh individual panels
    if AIP.BlacklistPanel and AIP.BlacklistPanel.Refresh then
        AIP.BlacklistPanel.Refresh()
    end
    if AIP.FavoritesPanel and AIP.FavoritesPanel.Refresh then
        AIP.FavoritesPanel.Refresh()
    end
    if AIP.LootHistoryPanel and AIP.LootHistoryPanel.Refresh then
        AIP.LootHistoryPanel.Refresh()
    end
    if AIP.RaidManagementPanel and AIP.RaidManagementPanel.RefreshLootBans then
        AIP.RaidManagementPanel.RefreshLootBans()
    end

    -- Force update main UI
    if AIP.UpdateUI then
        AIP.UpdateUI()
    end
end

-- Load all test data
function TD.LoadTestData()
    if TD.testDataActive then
        AIP.Print("|cFFFFFF00Test data already active.|r Use |cFF00FFFF/aip cleartest|r to remove it first.")
        return
    end

    TD.testDataActive = true

    -- Backup original data
    TD.originalData = {
        raidSessions = AIP.db and AIP.db.raidSessions or {},
        lootBans = AIP.db and AIP.db.lootBans or {},
        blacklist = AIP.db and AIP.db.blacklist or {},
        whitelist = AIP.db and AIP.db.whitelist or {},
        queue = AIP.db and AIP.db.queue or {},
        waitlist = AIP.db and AIP.db.waitlist or {},
        msTracking = AIP.db and AIP.db.msTracking or {},
        reservedItems = AIP.db and AIP.db.reservedItems or "",
        currentRaidSessionId = AIP.db and AIP.db.currentRaidSessionId,
        chatScannerGroups = AIP.ChatScanner and AIP.ChatScanner.Groups or {},
        chatScannerPlayers = AIP.ChatScanner and AIP.ChatScanner.Players or {},
    }

    -- Deep copy original data to prevent reference issues
    local function DeepCopy(orig)
        local copy = {}
        for k, v in pairs(orig) do
            if type(v) == "table" then
                copy[k] = DeepCopy(v)
            else
                copy[k] = v
            end
        end
        return copy
    end
    TD.originalData = DeepCopy(TD.originalData)

    -- Initialize empty tables if needed
    AIP.db = AIP.db or {}
    AIP.db.raidSessions = AIP.db.raidSessions or {}
    AIP.db.lootBans = AIP.db.lootBans or {}
    AIP.db.blacklist = AIP.db.blacklist or {}
    AIP.db.whitelist = AIP.db.whitelist or {}
    AIP.db.queue = AIP.db.queue or {}
    AIP.db.waitlist = AIP.db.waitlist or {}
    AIP.db.msTracking = AIP.db.msTracking or {}

    if AIP.ChatScanner then
        AIP.ChatScanner.Groups = AIP.ChatScanner.Groups or {}
        AIP.ChatScanner.Players = AIP.ChatScanner.Players or {}
    end

    -- Generate all test data (100+ records per section for scroll/layout testing)
    local N = 120
    TD.GenerateRaidSessions(N)
    TD.GenerateLFMGroups(N)
    TD.GenerateLFGPlayers(N)
    TD.GenerateLootBans(N)
    TD.GenerateBlacklist(N)
    TD.GenerateFavorites(N)
    TD.GenerateQueue(N)
    TD.GenerateWaitlist(N)
    TD.GenerateRaidMgmt(N)
    TD.GenerateRollData()

    -- Refresh UI
    TD.RefreshAllUI()

    AIP.Print("|cFF00FF00Test data loaded!|r Generated " .. N .. " records each for:")
    AIP.Print("  - Raid sessions (Loot History), LFM groups, LFG players")
    AIP.Print("  - Loot bans (Raid Mgmt), Blacklist, Favorites")
    AIP.Print("  - Loot Roll window: live raid loot + sample rolls (Raid Mgmt -> Open Roll Window)")
    AIP.Print("Use |cFF00FFFF/aip cleartest|r to remove test data.")
end

-- Clear test data only (restore originals)
function TD.ClearTestData()
    if not TD.testDataActive then
        AIP.Print("|cFFFFFF00No test data active.|r")
        return
    end

    TD.testDataActive = false

    -- Helper to remove test entries from a table
    local function RemoveTestEntries(tbl)
        if not tbl then return end
        local i = 1
        while i <= #tbl do
            if tbl[i] and tbl[i]._testData then
                table.remove(tbl, i)
            else
                i = i + 1
            end
        end
    end

    -- Helper to remove test entries from a keyed table
    local function RemoveTestEntriesKeyed(tbl)
        if not tbl then return end
        local keysToRemove = {}
        for k, v in pairs(tbl) do
            if v and v._testData then
                table.insert(keysToRemove, k)
            end
        end
        for _, k in ipairs(keysToRemove) do
            tbl[k] = nil
        end
    end

    -- Remove test entries from arrays / keyed tables
    if AIP.db then
        RemoveTestEntries(AIP.db.raidSessions)
        RemoveTestEntries(AIP.db.lootBans)
        RemoveTestEntries(AIP.db.blacklist)
        RemoveTestEntries(AIP.db.queue)
        RemoveTestEntries(AIP.db.waitlist)
        RemoveTestEntriesKeyed(AIP.db.whitelist)
        RemoveTestEntriesKeyed(AIP.db.msTracking)
        -- Reserved items is a single string; restore the pre-test value
        if TD.originalData then
            AIP.db.reservedItems = TD.originalData.reservedItems or ""
            -- Restore the active raid session pointer (test data set a fake one)
            AIP.db.currentRaidSessionId = TD.originalData.currentRaidSessionId
        end
    end

    -- Clear the roll-window test state
    if AIP.RaidTools then
        AIP.RaidTools.manualItems = {}
        AIP.RaidTools.rolls = {}
        AIP.RaidTools.rollItem = nil
        AIP.RaidTools.rollItemLink = nil
        AIP.RaidTools.rollActive = false
        AIP.RaidTools.warnedItems = {}
        if AIP.RaidTools.RefreshRollWindow then AIP.RaidTools.RefreshRollWindow() end
    end

    -- Remove test entries from ChatScanner (keyed tables)
    if AIP.ChatScanner then
        RemoveTestEntriesKeyed(AIP.ChatScanner.Groups)
        RemoveTestEntriesKeyed(AIP.ChatScanner.Players)
    end

    -- Remove from GroupTracker if it exists
    if AIP.GroupTracker and AIP.GroupTracker.Groups then
        RemoveTestEntriesKeyed(AIP.GroupTracker.Groups)
    end

    TD.originalData = {}

    -- Refresh UI
    TD.RefreshAllUI()

    AIP.Print("|cFF00FF00Test data cleared!|r Real data preserved.")
end

-- Check if test data is active
function TD.IsActive()
    return TD.testDataActive
end
