-- AutoInvite Plus - Integrations Module
-- GearScore, raid lockouts, and other addon integrations

local AIP = AutoInvitePlus
AIP.Integrations = {}
local Int = AIP.Integrations

-- Use AIP.Utils.DelayedCall for WotLK-compatible timers

-- ==========================================
-- GEARSCORE CALCULATION (GearScoreLite Formula)
-- ==========================================

-- Check if GearScore addon is loaded
function Int.HasGearScore()
    return GearScore_GetScore ~= nil or PlayerScore_GetScore ~= nil
end

-- ==========================================
-- GEARSCORE CALCULATION (GearScoreLite Formula)
-- ==========================================

-- Exact slot modifiers from GearScoreLite
local GS_ItemTypes = {
    ["INVTYPE_RELIC"] = { SlotMOD = 0.3164, ItemSlot = 18 },
    ["INVTYPE_TRINKET"] = { SlotMOD = 0.5625, ItemSlot = 33 },
    ["INVTYPE_2HWEAPON"] = { SlotMOD = 2.000, ItemSlot = 16 },
    ["INVTYPE_WEAPONMAINHAND"] = { SlotMOD = 1.0000, ItemSlot = 16 },
    ["INVTYPE_WEAPONOFFHAND"] = { SlotMOD = 1.0000, ItemSlot = 17 },
    ["INVTYPE_RANGED"] = { SlotMOD = 0.3164, ItemSlot = 18 },
    ["INVTYPE_THROWN"] = { SlotMOD = 0.3164, ItemSlot = 18 },
    ["INVTYPE_RANGEDRIGHT"] = { SlotMOD = 0.3164, ItemSlot = 18 },
    ["INVTYPE_SHIELD"] = { SlotMOD = 1.0000, ItemSlot = 17 },
    ["INVTYPE_WEAPON"] = { SlotMOD = 1.0000, ItemSlot = 36 },
    ["INVTYPE_HOLDABLE"] = { SlotMOD = 1.0000, ItemSlot = 17 },
    ["INVTYPE_HEAD"] = { SlotMOD = 1.0000, ItemSlot = 1 },
    ["INVTYPE_NECK"] = { SlotMOD = 0.5625, ItemSlot = 2 },
    ["INVTYPE_SHOULDER"] = { SlotMOD = 0.7500, ItemSlot = 3 },
    ["INVTYPE_CHEST"] = { SlotMOD = 1.0000, ItemSlot = 5 },
    ["INVTYPE_ROBE"] = { SlotMOD = 1.0000, ItemSlot = 5 },
    ["INVTYPE_WAIST"] = { SlotMOD = 0.7500, ItemSlot = 6 },
    ["INVTYPE_LEGS"] = { SlotMOD = 1.0000, ItemSlot = 7 },
    ["INVTYPE_FEET"] = { SlotMOD = 0.75, ItemSlot = 8 },
    ["INVTYPE_WRIST"] = { SlotMOD = 0.5625, ItemSlot = 9 },
    ["INVTYPE_HAND"] = { SlotMOD = 0.7500, ItemSlot = 10 },
    ["INVTYPE_FINGER"] = { SlotMOD = 0.5625, ItemSlot = 31 },
    ["INVTYPE_CLOAK"] = { SlotMOD = 0.5625, ItemSlot = 15 },
    ["INVTYPE_BODY"] = { SlotMOD = 0, ItemSlot = 4 },
}

-- GearScoreLite formula constants
local GS_Formula = {
    ["A"] = {  -- ItemLevel > 120
        [4] = { A = 91.4500, B = 0.6500 },  -- Epic
        [3] = { A = 81.3750, B = 0.8125 },  -- Rare
        [2] = { A = 73.0000, B = 1.0000 },  -- Uncommon
    },
    ["B"] = {  -- ItemLevel <= 120
        [4] = { A = 26.0000, B = 1.2000 },
        [3] = { A = 0.7500, B = 1.8000 },
        [2] = { A = 8.0000, B = 2.0000 },
        [1] = { A = 0.0000, B = 2.2500 },
    }
}

-- Calculate GearScore for a single item (exact GearScoreLite formula)
local function CalculateItemGS(itemLink)
    if not itemLink then return 0, 0, nil end

    local ItemName, _, ItemRarity, ItemLevel, _, _, _, _, ItemEquipLoc = GetItemInfo(itemLink)
    if not ItemEquipLoc or not GS_ItemTypes[ItemEquipLoc] then
        return 0, ItemLevel or 0, ItemEquipLoc
    end

    local Scale = 1.8618
    local QualityScale = 1

    -- Quality adjustments (exactly as GearScoreLite)
    if ItemRarity == 5 then
        QualityScale = 1.3
        ItemRarity = 4
    elseif ItemRarity == 1 then
        QualityScale = 0.005
        ItemRarity = 2
    elseif ItemRarity == 0 then
        QualityScale = 0.005
        ItemRarity = 2
    end

    -- Heirloom handling
    if ItemRarity == 7 then
        ItemRarity = 3
        ItemLevel = 187.05
    end

    -- Select formula based on item level
    local Table
    if ItemLevel > 120 then
        Table = GS_Formula["A"]
    else
        Table = GS_Formula["B"]
    end

    -- Calculate score
    if ItemRarity >= 2 and ItemRarity <= 4 and Table[ItemRarity] then
        local GearScore = math.floor(((ItemLevel - Table[ItemRarity].A) / Table[ItemRarity].B) * GS_ItemTypes[ItemEquipLoc].SlotMOD * Scale * QualityScale)
        if GearScore < 0 then GearScore = 0 end

        -- Reset heirloom item level for return
        if ItemLevel == 187.05 then ItemLevel = 0 end

        return GearScore, ItemLevel, ItemEquipLoc
    end

    return 0, ItemLevel or 0, ItemEquipLoc
end

-- Calculate total GearScore for a unit (exact GearScoreLite algorithm)
local function CalculateUnitGS(unit)
    if not unit or not UnitExists(unit) then return nil, nil end
    if not UnitIsPlayer(unit) then return nil, nil end

    local _, PlayerEnglishClass = UnitClass(unit)
    local GearScore = 0
    local ItemCount = 0
    local LevelTotal = 0
    local TitanGrip = 1

    -- Check for Titan's Grip (two 2H weapons)
    local mainHandLink = GetInventoryItemLink(unit, 16)
    local offHandLink = GetInventoryItemLink(unit, 17)

    if mainHandLink and offHandLink then
        local _, _, _, _, _, _, _, _, mainEquipLoc = GetItemInfo(mainHandLink)
        if mainEquipLoc == "INVTYPE_2HWEAPON" then
            TitanGrip = 0.5
        end
    end

    -- Calculate off-hand first (slot 17) with special handling
    if offHandLink then
        local _, _, _, _, _, _, _, _, offEquipLoc = GetItemInfo(offHandLink)
        if offEquipLoc == "INVTYPE_2HWEAPON" then
            TitanGrip = 0.5
        end

        local TempScore, ItemLevel = CalculateItemGS(offHandLink)
        if PlayerEnglishClass == "HUNTER" then
            TempScore = TempScore * 0.3164
        end
        GearScore = GearScore + TempScore * TitanGrip
        ItemCount = ItemCount + 1
        LevelTotal = LevelTotal + (ItemLevel or 0)
    end

    -- Calculate all other slots (1-18, excluding 4 and 17)
    for i = 1, 18 do
        if i ~= 4 and i ~= 17 then  -- Skip shirt and off-hand (already calculated)
            local itemLink = GetInventoryItemLink(unit, i)
            if itemLink then
                local TempScore, ItemLevel, ItemEquipLoc = CalculateItemGS(itemLink)

                -- Hunter special handling
                if i == 16 and PlayerEnglishClass == "HUNTER" then
                    TempScore = TempScore * 0.3164
                end
                if i == 18 and PlayerEnglishClass == "HUNTER" then
                    TempScore = TempScore * 5.3224
                end

                -- Main hand Titan's Grip adjustment
                if i == 16 then
                    TempScore = TempScore * TitanGrip
                end

                GearScore = GearScore + TempScore
                ItemCount = ItemCount + 1
                LevelTotal = LevelTotal + (ItemLevel or 0)
            end
        end
    end

    if GearScore <= 0 then
        return 0, 0
    end

    local avgItemLevel = 0
    if ItemCount > 0 then
        avgItemLevel = math.floor(LevelTotal / ItemCount)
    end

    return math.floor(GearScore), avgItemLevel
end

-- Get GearScore for a player
function Int.GetGearScore(name)
    if not name then return nil end

    -- Try GearScore addon first (most accurate)
    -- GearScore_GetScore expects (unitId) as parameter, not player name
    if GearScore_GetScore then
        local gs, ilvl = nil, nil

        -- Find the unit ID for this player
        local unit = nil
        if UnitExists("target") and UnitName("target") == name then
            unit = "target"
        elseif UnitExists("mouseover") and UnitName("mouseover") == name then
            unit = "mouseover"
        elseif UnitName("player") == name then
            unit = "player"
        else
            -- Check party/raid
            local numRaid = GetNumRaidMembers()
            if numRaid > 0 then
                for i = 1, numRaid do
                    if UnitName("raid" .. i) == name then
                        unit = "raid" .. i
                        break
                    end
                end
            else
                local numParty = GetNumPartyMembers()
                for i = 1, numParty do
                    if UnitName("party" .. i) == name then
                        unit = "party" .. i
                        break
                    end
                end
            end
        end

        if unit then
            gs, ilvl = GearScore_GetScore(unit)
        end

        if gs and gs > 0 then
            return gs, "GearScore", ilvl
        end
    end

    -- Try PlayerScore addon
    if PlayerScore_GetScore then
        local ps = PlayerScore_GetScore(name)
        if ps and ps > 0 then
            return ps, "PlayerScore"
        end
    end

    -- Fallback: Calculate ourselves using GearScoreLite formula
    local unit = nil
    local myName = UnitName("player")

    if name:lower() == myName:lower() then
        unit = "player"
    elseif UnitExists("target") and UnitName("target") and UnitName("target"):lower() == name:lower() then
        unit = "target"
    elseif UnitExists("mouseover") and UnitName("mouseover") and UnitName("mouseover"):lower() == name:lower() then
        unit = "mouseover"
    end

    if unit then
        local gs, ilvl = CalculateUnitGS(unit)
        if gs and gs > 0 then
            return gs, "Calculated", ilvl
        end
    end

    return nil
end

-- Get my GearScore and item level
function Int.GetMyGearScore()
    return Int.GetGearScore(UnitName("player"))
end

-- Calculate average item level for a unit
function Int.GetAverageItemLevel(unit)
    if not unit or not UnitExists(unit) then return nil end

    local totalILvl = 0
    local itemCount = 0

    for i = 1, 18 do
        if i ~= 4 then  -- Skip shirt
            local itemLink = GetInventoryItemLink(unit, i)
            if itemLink then
                local _, _, _, itemLevel = GetItemInfo(itemLink)
                if itemLevel and itemLevel > 0 then
                    totalILvl = totalILvl + itemLevel
                    itemCount = itemCount + 1
                end
            end
        end
    end

    if itemCount < 10 then return nil end

    return math.floor(totalILvl / itemCount)
end

-- Get GearScore color based on score
function Int.GetGSColor(gs)
    if not gs then return 1, 1, 1 end

    if gs >= 6000 then
        return 1, 0.5, 0      -- Orange (legendary tier)
    elseif gs >= 5500 then
        return 0.64, 0.21, 0.93  -- Purple (epic tier)
    elseif gs >= 5000 then
        return 0, 0.44, 0.87  -- Blue (rare tier)
    elseif gs >= 4500 then
        return 0, 1, 0        -- Green (uncommon tier)
    else
        return 1, 1, 1        -- White (common tier)
    end
end

-- Format GearScore with color
function Int.FormatGS(gs)
    if not gs then return "|cFFFFFFFF-|r" end

    local r, g, b = Int.GetGSColor(gs)
    return string.format("|cFF%02x%02x%02x%d|r", r*255, g*255, b*255, gs)
end

-- ==========================================
-- RAID LOCKOUT CHECKING
-- ==========================================

-- Instance IDs for WotLK raids
Int.RaidInstances = {
    ["Icecrown Citadel"] = {mapID = 631, size10 = true, size25 = true},
    ["Trial of the Crusader"] = {mapID = 649, size10 = true, size25 = true},
    ["Ulduar"] = {mapID = 603, size10 = true, size25 = true},
    ["Naxxramas"] = {mapID = 533, size10 = true, size25 = true},
    ["Vault of Archavon"] = {mapID = 624, size10 = true, size25 = true},
    ["Onyxia's Lair"] = {mapID = 249, size10 = true, size25 = true},
    ["Ruby Sanctum"] = {mapID = 724, size10 = true, size25 = true},
    ["The Eye of Eternity"] = {mapID = 616, size10 = true, size25 = true},
    ["The Obsidian Sanctum"] = {mapID = 615, size10 = true, size25 = true},
}

-- Get player's raid lockouts (only active, non-expired lockouts)
function Int.GetMyLockouts()
    local lockouts = {}

    -- Request fresh raid info from server
    RequestRaidInfo()

    local numSaved = GetNumSavedInstances()
    for i = 1, numSaved do
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)

        -- Only count as locked if: locked flag is true AND reset time is positive (not expired)
        -- reset is the number of seconds until the lockout expires; if <= 0, it's expired
        if isRaid and locked and reset and reset > 0 then
            table.insert(lockouts, {
                name = name,
                id = id,
                reset = reset,
                difficulty = difficultyName or (maxPlayers .. " Player"),
                progress = (encounterProgress or 0) .. "/" .. (numEncounters or 0),
                maxPlayers = maxPlayers,
            })
        end
    end

    return lockouts
end

-- Check if player has a specific lockout
function Int.HasLockout(raidName, size)
    local lockouts = Int.GetMyLockouts()

    for _, lockout in ipairs(lockouts) do
        if lockout.name:lower():find(raidName:lower(), 1, true) then
            if not size or lockout.maxPlayers == size then
                return true, lockout
            end
        end
    end

    return false
end

-- Format reset time
function Int.FormatResetTime(seconds)
    if seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    elseif seconds < 86400 then
        return math.floor(seconds / 3600) .. "h"
    else
        return math.floor(seconds / 86400) .. "d"
    end
end

-- Print lockout summary
function Int.PrintLockouts()
    local lockouts = Int.GetMyLockouts()

    if #lockouts == 0 then
        AIP.Print("No raid lockouts")
        return
    end

    AIP.Print("=== Raid Lockouts ===")
    for _, lockout in ipairs(lockouts) do
        AIP.Print(string.format("  %s (%s): %s - Resets in %s",
            lockout.name,
            lockout.difficulty,
            lockout.progress,
            Int.FormatResetTime(lockout.reset)))
    end
end

-- ==========================================
-- SUMMON COORDINATION
-- ==========================================

Int.SummonStatus = {
    warlocks = {},      -- {name = true}
    needsSummon = {},   -- {name = zone}
    meetingStone = nil, -- "zone name"
}

-- Find warlocks in raid
function Int.FindWarlocks()
    Int.SummonStatus.warlocks = {}

    local numRaid = GetNumRaidMembers()
    if numRaid == 0 then return {} end

    for i = 1, numRaid do
        local name, _, _, _, _, class = GetRaidRosterInfo(i)
        if class == "Warlock" then
            Int.SummonStatus.warlocks[name] = true
        end
    end

    return Int.SummonStatus.warlocks
end

-- Check who needs summons (not in same zone as leader)
function Int.CheckNeedsSummons()
    Int.SummonStatus.needsSummon = {}

    local myZone = GetRealZoneText()
    local numRaid = GetNumRaidMembers()

    if numRaid == 0 then return {} end

    for i = 1, numRaid do
        local name, _, _, _, _, _, zone, online = GetRaidRosterInfo(i)
        if online and zone ~= myZone then
            Int.SummonStatus.needsSummon[name] = zone
        end
    end

    return Int.SummonStatus.needsSummon
end

-- Print summon status
function Int.PrintSummonStatus()
    Int.FindWarlocks()
    Int.CheckNeedsSummons()

    local warlockCount = 0
    for _ in pairs(Int.SummonStatus.warlocks) do
        warlockCount = warlockCount + 1
    end

    local needsCount = 0
    for _ in pairs(Int.SummonStatus.needsSummon) do
        needsCount = needsCount + 1
    end

    AIP.Print("=== Summon Status ===")
    AIP.Print("Warlocks available: " .. warlockCount)
    AIP.Print("Players needing summon: " .. needsCount)

    if needsCount > 0 then
        for name, zone in pairs(Int.SummonStatus.needsSummon) do
            AIP.Print("  " .. name .. " - " .. zone)
        end
    end
end

-- ==========================================
-- READY CHECK ENHANCEMENT
-- ==========================================

Int.ReadyCheckResults = {}

-- Hook ready check events
local readyFrame = CreateFrame("Frame")
readyFrame:RegisterEvent("READY_CHECK")
readyFrame:RegisterEvent("READY_CHECK_CONFIRM")
readyFrame:RegisterEvent("READY_CHECK_FINISHED")

readyFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "READY_CHECK" then
        Int.ReadyCheckResults = {}
        AIP.Debug("Ready check started")

    elseif event == "READY_CHECK_CONFIRM" then
        local unit, ready = ...
        local name = UnitName(unit)
        if name then
            Int.ReadyCheckResults[name] = ready
        end

    elseif event == "READY_CHECK_FINISHED" then
        -- Summarize results
        local ready = 0
        local notReady = 0
        local noResponse = 0

        local numRaid = GetNumRaidMembers()
        for i = 1, numRaid do
            local name = GetRaidRosterInfo(i)
            if name then
                if Int.ReadyCheckResults[name] == true then
                    ready = ready + 1
                elseif Int.ReadyCheckResults[name] == false then
                    notReady = notReady + 1
                else
                    noResponse = noResponse + 1
                end
            end
        end

        AIP.Print(string.format("Ready Check: %d ready, %d not ready, %d no response",
            ready, notReady, noResponse))
    end
end)

-- ==========================================
-- ACHIEVEMENT CHECKING
-- ==========================================

-- Common WotLK raid achievements
Int.RaidAchievements = {
    -- ICC
    ["Fall of the Lich King (10)"] = 4530,
    ["Fall of the Lich King (25)"] = 4597,
    ["Heroic: Fall of the Lich King (10)"] = 4583,
    ["Heroic: Fall of the Lich King (25)"] = 4601,
    ["Glory of the Icecrown Raider (10)"] = 4602,
    ["Glory of the Icecrown Raider (25)"] = 4603,
    ["Bane of the Fallen King"] = 4580,
    ["The Light of Dawn"] = 4584,

    -- ToC
    ["Call of the Grand Crusade (10)"] = 3918,
    ["Call of the Grand Crusade (25)"] = 3812,

    -- Ulduar
    ["Glory of the Ulduar Raider (10)"] = 2957,
    ["Glory of the Ulduar Raider (25)"] = 2958,
    ["Observed (10)"] = 3036,
    ["Observed (25)"] = 3037,

    -- Naxx
    ["Glory of the Raider (10)"] = 2137,
    ["Glory of the Raider (25)"] = 2138,
    ["The Undying"] = 2187,
    ["The Immortal"] = 2186,
}

-- Check if player has an achievement (only works for inspected players or self)
function Int.HasAchievement(achievementID)
    local _, _, _, completed = GetAchievementInfo(achievementID)
    return completed
end

-- ==========================================
-- SLASH COMMANDS
-- ==========================================

function Int.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "help" then
        AIP.Print("Integration commands:")
        AIP.Print("  /aip lockouts - Show your raid lockouts")
        AIP.Print("  /aip summons - Check summon status")
        AIP.Print("  /aip gs <player> - Check player's GearScore")

    elseif msg == "lockouts" or msg == "locks" then
        Int.PrintLockouts()

    elseif msg == "summons" or msg == "summon" then
        Int.PrintSummonStatus()

    elseif msg:find("^gs ") then
        local name = msg:sub(4):trim()
        local gs, source = Int.GetGearScore(name)
        if gs then
            AIP.Print(name .. "'s " .. source .. ": " .. Int.FormatGS(gs))
        else
            AIP.Print("Could not get GearScore for " .. name)
        end
    end
end

-- ==========================================
-- TOOLTIP ENHANCEMENTS
-- ==========================================

-- Add info to player tooltips
local function OnTooltipSetUnit(tooltip)
    if not AIP.db then return end

    local _, unit = tooltip:GetUnit()
    if not unit or not UnitIsPlayer(unit) then return end

    local name = UnitName(unit)
    if not name then return end

    -- Add GearScore
    local gs = Int.GetGearScore(name)
    if gs then
        tooltip:AddLine("GearScore: " .. Int.FormatGS(gs))
    end

    -- Add player notes if available
    if AIP.Roster and AIP.Roster.GetPlayerNote then
        local note = AIP.Roster.GetPlayerNote(name)
        if note and note ~= "" then
            tooltip:AddLine("Note: " .. note, 1, 0.82, 0)
        end

        local rating = AIP.Roster.GetPlayerRating(name)
        if rating then
            tooltip:AddLine("Rating: " .. rating .. "/5", 0.7, 0.7, 0.7)
        end

        local attPercent = AIP.Roster.GetAttendancePercent(name)
        if attPercent then
            tooltip:AddLine("Attendance: " .. attPercent .. "%", 0.7, 0.7, 0.7)
        end
    end

    tooltip:Show()
end

-- Hook tooltips
GameTooltip:HookScript("OnTooltipSetUnit", OnTooltipSetUnit)

-- ==========================================
-- BLIZZARD RAID BROWSER INTEGRATION
-- ==========================================

-- Storage for Raid Browser listings
Int.RaidBrowserListings = {}
Int.LastRaidBrowserUpdate = 0

-- WotLK Raid IDs (from Blizzard's LFR system)
Int.RaidBrowserRaidInfo = {
    -- ICC
    [279] = {name = "ICC 10", shortName = "ICC10N", size = 10, heroic = false},
    [280] = {name = "ICC 25", shortName = "ICC25N", size = 25, heroic = false},
    -- TOC
    [249] = {name = "TOC 10", shortName = "TOC10", size = 10, heroic = false},
    [250] = {name = "TOC 25", shortName = "TOC25", size = 25, heroic = false},
    -- VOA
    [239] = {name = "VOA 10", shortName = "VOA10", size = 10, heroic = false},
    [240] = {name = "VOA 25", shortName = "VOA25", size = 25, heroic = false},
    -- Onyxia
    [257] = {name = "Onyxia 10", shortName = "ONY10", size = 10, heroic = false},
    [258] = {name = "Onyxia 25", shortName = "ONY25", size = 25, heroic = false},
    -- Ruby Sanctum
    [294] = {name = "RS 10", shortName = "RS10N", size = 10, heroic = false},
    [295] = {name = "RS 25", shortName = "RS25N", size = 25, heroic = false},
    -- Naxxramas
    [159] = {name = "Naxx 10", shortName = "NAXX10", size = 10, heroic = false},
    [160] = {name = "Naxx 25", shortName = "NAXX25", size = 25, heroic = false},
    -- Ulduar
    [243] = {name = "Ulduar 10", shortName = "ULD10", size = 10, heroic = false},
    [244] = {name = "Ulduar 25", shortName = "ULD25", size = 25, heroic = false},
    -- EoE
    [223] = {name = "EoE 10", shortName = "EOE10", size = 10, heroic = false},
    [224] = {name = "EoE 25", shortName = "EOE25", size = 25, heroic = false},
    -- OS
    [237] = {name = "OS 10", shortName = "OS10", size = 10, heroic = false},
    [238] = {name = "OS 25", shortName = "OS25", size = 25, heroic = false},
}

-- Scan the Blizzard Raid Browser for listings
function Int.ScanRaidBrowser()
    local listings = {}

    -- Check if SearchLFG functions exist (WotLK 3.3.5)
    if not SearchLFGGetResults or not SearchLFGGetNumResults then
        AIP.Debug("RaidBrowser: SearchLFG functions not available")
        return listings
    end

    -- Try to get results from the Raid Browser
    local numResults = SearchLFGGetNumResults()
    if not numResults or numResults == 0 then
        return listings
    end

    AIP.Debug("RaidBrowser: Found " .. numResults .. " listings")

    for i = 1, numResults do
        local name, level, areaName, className, comment, partyMembers, status, class, encountersTotal, encountersComplete, isIneligible, leader, tank, healer, damage = SearchLFGGetResults(i)

        if name and name ~= "" then
            -- Determine raid from areaName or comment
            local raidId = nil
            local raidShortName = "UNKNOWN"

            -- Try to match area name to our raid info
            if areaName then
                local areaLower = areaName:lower()
                if areaLower:find("icecrown") then
                    raidShortName = partyMembers > 10 and "ICC25N" or "ICC10N"
                elseif areaLower:find("trial") or areaLower:find("crusader") then
                    raidShortName = partyMembers > 10 and "TOC25" or "TOC10"
                elseif areaLower:find("vault") or areaLower:find("archavon") then
                    raidShortName = partyMembers > 10 and "VOA25" or "VOA10"
                elseif areaLower:find("onyxia") then
                    raidShortName = partyMembers > 10 and "ONY25" or "ONY10"
                elseif areaLower:find("ruby") or areaLower:find("sanctum") or areaLower:find("halion") then
                    raidShortName = partyMembers > 10 and "RS25N" or "RS10N"
                elseif areaLower:find("naxx") then
                    raidShortName = partyMembers > 10 and "NAXX25" or "NAXX10"
                elseif areaLower:find("ulduar") then
                    raidShortName = partyMembers > 10 and "ULD25" or "ULD10"
                elseif areaLower:find("malygos") or areaLower:find("eternity") then
                    raidShortName = partyMembers > 10 and "EOE25" or "EOE10"
                elseif areaLower:find("obsidian") or areaLower:find("sarth") then
                    raidShortName = partyMembers > 10 and "OS25" or "OS10"
                end
            end

            table.insert(listings, {
                name = name,
                level = level,
                class = class or className,
                raid = raidShortName,
                raidName = areaName or "Unknown",
                comment = comment or "",
                partySize = partyMembers or 1,
                progress = encountersComplete and encountersTotal and (encountersComplete .. "/" .. encountersTotal) or "",
                isLeader = leader,
                wantsTank = tank,
                wantsHealer = healer,
                wantsDPS = damage,
                time = time(),
                source = "RaidBrowser",
            })
        end
    end

    Int.RaidBrowserListings = listings
    Int.LastRaidBrowserUpdate = time()

    return listings
end

-- Get Raid Browser listings (with optional auto-refresh)
function Int.GetRaidBrowserListings(forceRefresh)
    local now = time()

    -- Auto-refresh if data is stale (older than 30 seconds)
    if forceRefresh or (now - Int.LastRaidBrowserUpdate > 30) then
        Int.ScanRaidBrowser()
    end

    return Int.RaidBrowserListings
end

-- Import Raid Browser listings into our LFG system
function Int.ImportRaidBrowserToLFG()
    local listings = Int.ScanRaidBrowser()
    local imported = 0

    if not AIP.CentralGUI then return 0 end

    for _, listing in ipairs(listings) do
        -- Create LFG enrollment entry
        local entry = {
            name = listing.name,
            class = listing.class,
            level = listing.level,
            raid = listing.raid,
            message = listing.comment,
            time = listing.time,
            source = "RaidBrowser",
            isLeader = listing.isLeader,
            partySize = listing.partySize,
            wantsTank = listing.wantsTank,
            wantsHealer = listing.wantsHealer,
            wantsDPS = listing.wantsDPS,
        }

        -- Add to our LFG enrollments if not already present
        if AIP.CentralGUI.LfgEnrollments then
            local existing = AIP.CentralGUI.LfgEnrollments[listing.name]
            if not existing or (existing.source ~= "RaidBrowser" and existing.time < listing.time - 60) then
                AIP.CentralGUI.LfgEnrollments[listing.name] = entry
                imported = imported + 1
            end
        end
    end

    -- Update UI if open
    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end

    if imported > 0 then
        AIP.Print("Imported " .. imported .. " listings from Raid Browser")
    end

    return imported
end

-- Hook into Raid Browser frame to auto-import on update
local raidBrowserHooked = false
local function HookRaidBrowser()
    if raidBrowserHooked then return end

    -- Try to hook LFRBrowseFrame if it exists
    if LFRBrowseFrame then
        LFRBrowseFrame:HookScript("OnShow", function()
            -- Delay to allow Blizzard UI to populate (WotLK compatible)
            AIP.Utils.DelayedCall(0.5, Int.ImportRaidBrowserToLFG)
        end)

        -- Also hook the Refresh button if it exists
        if LFRBrowseFrameRefreshButton then
            LFRBrowseFrameRefreshButton:HookScript("OnClick", function()
                AIP.Utils.DelayedCall(1, Int.ImportRaidBrowserToLFG)
            end)
        end

        raidBrowserHooked = true
        AIP.Debug("RaidBrowser: Hooked successfully")
    end
end

-- Try to hook when addon loads
local raidBrowserFrame = CreateFrame("Frame")
raidBrowserFrame:RegisterEvent("ADDON_LOADED")
raidBrowserFrame:RegisterEvent("LFG_UPDATE")
raidBrowserFrame:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
raidBrowserFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == "Blizzard_LookingForGroupUI" or arg1 == "AutoInvitePlus" then
            HookRaidBrowser()
        end
    elseif event == "LFG_UPDATE" or event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        -- Auto-import when LFG data updates
        if AIP.CentralGUI and AIP.CentralGUI.Frame and AIP.CentralGUI.Frame:IsVisible() then
            Int.ImportRaidBrowserToLFG()
        end
    end
end)

-- Add command to manually import from Raid Browser
function Int.RaidBrowserSlashHandler(msg)
    if msg == "import" or msg == "scan" then
        local count = Int.ImportRaidBrowserToLFG()
        if count == 0 then
            AIP.Print("No new listings found in Raid Browser. Open the Raid Browser (Social -> Raid) first.")
        end
    elseif msg == "list" then
        local listings = Int.GetRaidBrowserListings()
        if #listings == 0 then
            AIP.Print("No Raid Browser listings cached")
        else
            AIP.Print("=== Raid Browser Listings ===")
            for i, listing in ipairs(listings) do
                if i <= 10 then
                    AIP.Print(string.format("  %s (%s) - %s: %s",
                        listing.name, listing.class or "?", listing.raid, listing.comment:sub(1, 30)))
                end
            end
            if #listings > 10 then
                AIP.Print("  ... and " .. (#listings - 10) .. " more")
            end
        end
    else
        AIP.Print("Raid Browser commands:")
        AIP.Print("  /aip rb import - Import listings from Blizzard Raid Browser")
        AIP.Print("  /aip rb list - Show cached listings")
    end
end
