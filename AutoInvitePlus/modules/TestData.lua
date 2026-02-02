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
        local leader = TEST_NAMES[i] .. "Leader"
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

        -- Generate attendees
        local attendees = {}
        local numAttendees = math.random(math.floor(raid.size * 0.8), raid.size)
        for j = 1, numAttendees do
            local player = GenerateRandomPlayer(j)
            attendees[player.name] = {
                class = player.class,
                spec = player.spec,
                role = player.role,
                gs = player.gs,
                joinTime = sessionTime + math.random(0, 600),
                leftTime = sessionTime + duration - math.random(0, 600),
            }
        end

        -- Generate boss kills
        local bossKills = {}
        local bossPrefix = raid.key:match("^(%u+)")
        local bossList = BOSS_NAMES[bossPrefix] or BOSS_NAMES.ICC
        local numBosses = math.random(math.floor(#bossList * 0.5), #bossList)

        for j = 1, numBosses do
            local bossName = bossList[j]
            local killTime = sessionTime + (j * math.floor(duration / numBosses))

            -- Generate loot drops
            local lootDrops = {}
            local numDrops = math.random(2, 4)
            for k = 1, numDrops do
                local item = RandomElement(LOOT_ITEMS)
                local winner = RandomElement(TEST_NAMES) .. tostring(math.random(1, 10))
                table.insert(lootDrops, {
                    itemId = item.id,
                    itemName = item.name,
                    itemLink = "|cffff8000|Hitem:" .. item.id .. "::::::::80:::::|h[" .. item.name .. "]|h|r",
                    winner = winner,
                    rollType = RandomElement({"MS", "OS", "GREED"}),
                    time = killTime + math.random(10, 60),
                })
            end

            table.insert(bossKills, {
                bossName = bossName,
                killTime = killTime,
                loot = lootDrops,
            })
        end

        local session = {
            id = "test_session_" .. i,
            raid = raid.key,
            raidName = raid.name,
            startTime = sessionTime,
            endTime = sessionTime + duration,
            attendees = attendees,
            bossKills = bossKills,
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
        local player = TEST_NAMES[i] .. "Banned"
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
        local player = TEST_NAMES[#TEST_NAMES - i + 1] .. "Blocked"

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
    AIP.db.favorites = AIP.db.favorites or {}

    local notes = {
        "Great tank, very skilled",
        "Reliable healer, always shows up",
        "Top DPS, good attitude",
        "Knows all mechanics",
        "Guild friend",
    }

    for i = 1, count do
        local player = GenerateRandomPlayer(20 + i)

        table.insert(AIP.db.favorites, {
            name = player.name,
            class = player.class,
            note = notes[((i - 1) % #notes) + 1],
            gs = player.gs,
            timestamp = time() - math.random(0, 2592000),
            _testData = true,
        })
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
        favorites = AIP.db and AIP.db.favorites or {},
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
    AIP.db.favorites = AIP.db.favorites or {}

    if AIP.ChatScanner then
        AIP.ChatScanner.Groups = AIP.ChatScanner.Groups or {}
        AIP.ChatScanner.Players = AIP.ChatScanner.Players or {}
    end

    -- Generate all test data
    TD.GenerateRaidSessions(3)
    TD.GenerateLFMGroups(5)
    TD.GenerateLFGPlayers(10)
    TD.GenerateLootBans(5)
    TD.GenerateBlacklist(5)
    TD.GenerateFavorites(5)

    -- Refresh UI
    TD.RefreshAllUI()

    AIP.Print("|cFF00FF00Test data loaded!|r Generated:")
    AIP.Print("  - 3 raid sessions (Loot History)")
    AIP.Print("  - 5 LFM groups (Browser)")
    AIP.Print("  - 10 LFG players (Browser)")
    AIP.Print("  - 5 loot bans (Raid Mgmt)")
    AIP.Print("  - 5 blacklist entries")
    AIP.Print("  - 5 favorites")
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

    -- Remove test entries from arrays
    if AIP.db then
        RemoveTestEntries(AIP.db.raidSessions)
        RemoveTestEntries(AIP.db.lootBans)
        RemoveTestEntries(AIP.db.blacklist)
        RemoveTestEntries(AIP.db.favorites)
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
