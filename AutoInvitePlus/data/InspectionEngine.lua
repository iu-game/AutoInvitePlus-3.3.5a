-- AutoInvite Plus - Inspection Engine Module
-- Player inspection, gear analysis, and performance estimation

local AIP = AutoInvitePlus
AIP.InspectionEngine = {}
local IE = AIP.InspectionEngine

-- Cache configuration
IE.Config = {
    cacheDuration = 1800,  -- 30 minutes cache
    inspectCooldown = 1.5, -- Seconds between inspects
    maxQueueSize = 20,
}

-- Inspection cache
IE.Cache = {}

-- Inspection queue
IE.Queue = {
    pending = {},
    inProgress = nil,
    lastInspect = 0,
}

-- Equipment slot IDs
IE.SlotIDs = {
    [1] = "Head",
    [2] = "Neck",
    [3] = "Shoulder",
    [5] = "Chest",
    [6] = "Waist",
    [7] = "Legs",
    [8] = "Feet",
    [9] = "Wrist",
    [10] = "Hands",
    [11] = "Finger0",
    [12] = "Finger1",
    [13] = "Trinket0",
    [14] = "Trinket1",
    [15] = "Back",
    [16] = "MainHand",
    [17] = "OffHand",
    [18] = "Ranged",
}

-- Slots that can be enchanted (WotLK)
IE.EnchantableSlots = {
    [1] = true,   -- Head (arcanum)
    [3] = true,   -- Shoulder (inscription)
    [5] = true,   -- Chest
    [6] = true,   -- Waist (belt buckle = gem, not enchant)
    [7] = true,   -- Legs (spellthread/armor kit)
    [8] = true,   -- Feet
    [9] = true,   -- Wrist
    [10] = true,  -- Hands
    [15] = true,  -- Back
    [16] = true,  -- MainHand
    [17] = true,  -- OffHand (some)
}

-- Belt buckle is a gem slot, not enchant
IE.BeltBuckleSlot = 6

-- Slots with gem sockets typically
IE.GemSlots = {1, 3, 5, 6, 7, 8, 9, 10, 15, 16, 17}

-- Raid achievements for checking
IE.RaidAchievements = {
    ICC10 = {4530},      -- Fall of the Lich King 10
    ICC25 = {4597},      -- Fall of the Lich King 25
    ICC10H = {4583},     -- Heroic: Fall of the Lich King 10
    ICC25H = {4584, 4601}, -- Heroic: Fall of the Lich King 25
    GloryICC10 = {4602}, -- Glory of the Icecrown Raider 10
    GloryICC25 = {4603}, -- Glory of the Icecrown Raider 25
    TOC10 = {3917},      -- Call of the Crusade 10
    TOC25 = {3916},      -- Call of the Crusade 25
    TOGC10 = {3918},     -- Call of the Grand Crusade 10
    TOGC25 = {3812},     -- Call of the Grand Crusade 25
    ULDUAR10 = {2894},   -- Observed 10
    ULDUAR25 = {2895},   -- Observed 25
    GloryUlduar10 = {2957},
    GloryUlduar25 = {2958},
    Undying = {2187},
    Immortal = {2186},
}

-- DPS baseline estimates by class/spec (GS 5000 baseline)
IE.DPSBaselines = {
    WARRIOR = {Arms = 6000, Fury = 6200, Protection = 3000},
    PALADIN = {Retribution = 6100, Holy = 0, Protection = 3000},
    HUNTER = {["Beast Mastery"] = 5800, Marksmanship = 6300, Survival = 6100},
    ROGUE = {Assassination = 6500, Combat = 6300, Subtlety = 5500},
    PRIEST = {Shadow = 6000, Holy = 0, Discipline = 0},
    DEATHKNIGHT = {Blood = 5800, Frost = 6200, Unholy = 6400},
    SHAMAN = {Elemental = 5900, Enhancement = 6100, Restoration = 0},
    MAGE = {Arcane = 6500, Fire = 6200, Frost = 5500},
    WARLOCK = {Affliction = 6300, Demonology = 5800, Destruction = 6400},
    DRUID = {Balance = 6000, ["Feral Combat"] = 6200, Restoration = 0},
}

-- HPS baselines by class/spec (GS 5000 baseline)
IE.HPSBaselines = {
    PALADIN = {Holy = 5500},
    PRIEST = {Holy = 5200, Discipline = 4500},
    SHAMAN = {Restoration = 5400},
    DRUID = {Restoration = 5800},
}

-- Tank EHP baselines by class (GS 5000)
IE.TankBaselines = {
    WARRIOR = {ehp = 42000, armor = 28000},
    PALADIN = {ehp = 40000, armor = 26000},
    DEATHKNIGHT = {ehp = 45000, armor = 24000},
    DRUID = {ehp = 50000, armor = 32000},
}

-- Get item level from item link
local function GetItemLevel(link)
    if not link then return 0 end

    local _, _, _, itemLevel = GetItemInfo(link)
    return itemLevel or 0
end

-- Check if item is enchanted (enchantID is in position 2 of item string)
local function IsItemEnchanted(link)
    if not link then return false end

    local enchantID = link:match("item:%d+:(%d+)")
    return enchantID and tonumber(enchantID) > 0
end

-- Count gem slots and filled gems from tooltip
local function AnalyzeGems(link)
    if not link then return 0, 0 end

    local tooltip = AIP.InspectionEngine.ScanTooltip
    if not tooltip then
        tooltip = CreateFrame("GameTooltip", "AIPInspectionTooltip", nil, "GameTooltipTemplate")
        AIP.InspectionEngine.ScanTooltip = tooltip
    end

    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()
    tooltip:SetHyperlink(link)

    local emptySlots = 0
    local filledSlots = 0
    local socketTypes = {"Red Socket", "Yellow Socket", "Blue Socket", "Meta Socket", "Prismatic Socket"}

    for i = 1, tooltip:NumLines() do
        local line = _G[tooltip:GetName() .. "TextLeft" .. i]
        if line then
            local text = line:GetText() or ""

            -- Check for empty socket
            for _, socketType in ipairs(socketTypes) do
                if text:find(socketType) then
                    emptySlots = emptySlots + 1
                    break
                end
            end

            -- Check for filled gem (has stats like "+20 Strength" but not socket bonus)
            if text:match("^%+%d+") and not text:find("Socket Bonus") then
                filledSlots = filledSlots + 1
            end
        end
    end

    -- Total slots = empty + filled
    local totalSlots = emptySlots + filledSlots

    tooltip:Hide()
    return totalSlots, filledSlots
end

-- Inspect a unit and cache results
function IE.InspectUnit(unit)
    if not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
    if not CanInspect(unit) then return nil end

    local name = UnitName(unit)
    local _, class = UnitClass(unit)

    local data = {
        name = name,
        class = class,
        timestamp = time(),
        gearScore = 0,
        avgItemLevel = 0,
        equipment = {},
        analysis = {
            missingEnchants = 0,
            enchantableSlots = {},
            emptyGemSlots = 0,
            totalGemSlots = 0,
            gemQuality = "Unknown",
        },
        achievements = {},
        performanceEstimate = {},
        dataSource = "Inspect",
    }

    -- Get equipment info
    local totalILvl = 0
    local slotCount = 0

    for slotID, slotName in pairs(IE.SlotIDs) do
        local link = GetInventoryItemLink(unit, slotID)
        if link then
            local itemLevel = GetItemLevel(link)
            local enchanted = IsItemEnchanted(link)
            local emptyGems, totalGems = AnalyzeGems(link)

            data.equipment[slotID] = {
                link = link,
                itemLevel = itemLevel,
                enchanted = enchanted,
                gems = {empty = emptyGems, total = totalGems},
            }

            totalILvl = totalILvl + itemLevel
            slotCount = slotCount + 1

            -- Check enchantable slots
            if IE.EnchantableSlots[slotID] and not enchanted then
                data.analysis.missingEnchants = data.analysis.missingEnchants + 1
                table.insert(data.analysis.enchantableSlots, slotName)
            end

            data.analysis.emptyGemSlots = data.analysis.emptyGemSlots + emptyGems
            data.analysis.totalGemSlots = data.analysis.totalGemSlots + totalGems
        end
    end

    -- Calculate averages
    if slotCount > 0 then
        data.avgItemLevel = math.floor(totalILvl / slotCount)
    end

    -- Get GearScore using Integrations module (handles fallback calculation)
    if AIP.Integrations and AIP.Integrations.GetGearScore then
        local gs = AIP.Integrations.GetGearScore(name)
        data.gearScore = gs or 0
    elseif GearScore_GetScore then
        data.gearScore = GearScore_GetScore(name) or 0
    elseif PlayerScore_GetScore then
        data.gearScore = PlayerScore_GetScore(name) or 0
    else
        -- Fallback: estimate from average iLvl (rough approximation)
        -- Formula calibrated: iLvl 264 (ICC gear) ~= 5500 GS
        data.gearScore = math.floor(data.avgItemLevel * 20.8)
    end

    -- Calculate performance estimate
    data.performanceEstimate = IE.EstimatePerformance(data)

    -- Cache the data
    IE.Cache[name] = data

    return data
end

-- Estimate performance based on gear and class
function IE.EstimatePerformance(data)
    if not data or not data.class then
        return {role = "Unknown", confidence = "None"}
    end

    local estimate = {
        role = "DPS",
        confidence = "Low",
    }

    local gs = data.gearScore or 5000
    local gsModifier = (gs - 5000) / 100  -- Per 100 GS

    -- Try to detect role from gear (simplified)
    -- In a full implementation, we'd check talents

    local class = data.class

    -- Tank detection (look for defense gear, shield, etc.)
    if class == "WARRIOR" or class == "PALADIN" or class == "DEATHKNIGHT" or class == "DRUID" then
        -- Check for tank gear indicators
        local mainHand = data.equipment[16]
        local offHand = data.equipment[17]

        -- Shield check for warrior/paladin
        if offHand and offHand.link then
            local _, _, _, _, _, itemType, itemSubType = GetItemInfo(offHand.link)
            if itemSubType and itemSubType:find("Shield") then
                estimate.role = "Tank"
            end
        end

        if estimate.role == "Tank" then
            local baseline = IE.TankBaselines[class]
            if baseline then
                local ehpModifier = 1 + (gsModifier * 0.06)
                estimate.estimatedEHP = math.floor(baseline.ehp * ehpModifier)
                estimate.estimatedArmor = math.floor(baseline.armor * ehpModifier)
                estimate.defense = 540  -- Assume defense capped
                estimate.confidence = gs > 5000 and "Medium" or "Low"
            end
        end
    end

    -- Healer detection
    if class == "PRIEST" or class == "PALADIN" or class == "SHAMAN" or class == "DRUID" then
        -- Check for healing-oriented gear (spirit, mp5, etc.)
        -- Simplified: assume role based on class likelihood
        local healBaselines = IE.HPSBaselines[class]
        if healBaselines then
            -- Could be healer
            estimate.possibleHealer = true
        end
    end

    -- DPS estimate (default)
    if estimate.role == "DPS" then
        local dpsBaselines = IE.DPSBaselines[class]
        if dpsBaselines then
            -- Use average of specs as estimate
            local total = 0
            local count = 0
            for spec, baseline in pairs(dpsBaselines) do
                if baseline > 0 then
                    total = total + baseline
                    count = count + 1
                end
            end
            if count > 0 then
                local baselineDPS = total / count
                local dpsModifier = 1 + (gsModifier * 0.08)
                estimate.estimatedDPS = math.floor(baselineDPS * dpsModifier)
                estimate.confidence = gs > 5000 and "Medium" or "Low"
            end
        end
    end

    return estimate
end

-- Get cached inspection data
function IE.GetCachedData(name)
    local cached = IE.Cache[name]
    if not cached then return nil end

    -- Check if cache is still valid
    if time() - cached.timestamp > IE.Config.cacheDuration then
        IE.Cache[name] = nil
        return nil
    end

    return cached
end

-- Queue a player for inspection
function IE.QueueInspection(name, priority)
    if not name then return end

    -- Check if already cached and fresh
    local cached = IE.GetCachedData(name)
    if cached then return cached end

    -- Check if already queued
    for _, entry in ipairs(IE.Queue.pending) do
        if entry.name == name then
            return nil
        end
    end

    -- Add to queue
    table.insert(IE.Queue.pending, {
        name = name,
        priority = priority or 1,
        time = time(),
    })

    -- Sort by priority (higher first)
    table.sort(IE.Queue.pending, function(a, b)
        return a.priority > b.priority
    end)

    -- Trim queue if too large
    while #IE.Queue.pending > IE.Config.maxQueueSize do
        table.remove(IE.Queue.pending)
    end

    return nil
end

-- Process inspection queue
local function ProcessInspectionQueue()
    if not IE.Queue.pending or #IE.Queue.pending == 0 then return end

    -- Check cooldown
    local now = GetTime()
    if now - IE.Queue.lastInspect < IE.Config.inspectCooldown then return end

    -- Check if we're already inspecting
    if IE.Queue.inProgress then return end

    -- Get next in queue
    local next = table.remove(IE.Queue.pending, 1)
    if not next then return end

    -- Find the unit
    local unit = nil
    if UnitName("target") == next.name then
        unit = "target"
    elseif UnitName("mouseover") == next.name then
        unit = "mouseover"
    else
        -- Check raid/party
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for i = 1, numRaid do
                if UnitName("raid" .. i) == next.name then
                    unit = "raid" .. i
                    break
                end
            end
        else
            for i = 1, GetNumPartyMembers() do
                if UnitName("party" .. i) == next.name then
                    unit = "party" .. i
                    break
                end
            end
        end
    end

    if not unit or not CanInspect(unit) then
        -- Can't inspect, move on
        return
    end

    -- Start inspection
    IE.Queue.inProgress = next.name
    IE.Queue.lastInspect = now
    NotifyInspect(unit)
end

-- Handle inspection ready event
local function OnInspectReady()
    if not IE.Queue.inProgress then return end

    -- Find the unit we were inspecting
    local name = IE.Queue.inProgress
    local unit = nil

    if UnitName("target") == name then
        unit = "target"
    else
        local numRaid = GetNumRaidMembers()
        if numRaid > 0 then
            for i = 1, numRaid do
                if UnitName("raid" .. i) == name then
                    unit = "raid" .. i
                    break
                end
            end
        end
    end

    -- Validate unit still exists and is connected before processing
    if unit and UnitExists(unit) and UnitIsConnected(unit) then
        IE.InspectUnit(unit)
    end

    IE.Queue.inProgress = nil
    ClearInspectPlayer()

    -- Notify UI
    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end
end

-- Store data from addon communication
function IE.StoreAddonData(name, data)
    if not name or not data then return end

    data.timestamp = time()
    data.dataSource = "Addon"
    data.name = name

    IE.Cache[name] = data

    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end
end

-- Get data source indicator
function IE.GetDataSource(name)
    local cached = IE.Cache[name]
    if not cached then return "None" end

    return cached.dataSource or "Unknown"
end

-- Check if player has AutoInvitePlus addon
function IE.HasAddon(name)
    local cached = IE.Cache[name]
    return cached and cached.dataSource == "Addon"
end

-- Format GearScore with color
function IE.FormatGS(gs)
    if not gs or gs == 0 then return "|cFFFFFFFF-|r" end

    local r, g, b
    if gs >= 6000 then
        r, g, b = 1, 0.5, 0       -- Orange
    elseif gs >= 5500 then
        r, g, b = 0.64, 0.21, 0.93 -- Purple
    elseif gs >= 5000 then
        r, g, b = 0, 0.44, 0.87   -- Blue
    elseif gs >= 4500 then
        r, g, b = 0, 1, 0         -- Green
    else
        r, g, b = 1, 1, 1         -- White
    end

    return string.format("|cFF%02x%02x%02x%d|r", r*255, g*255, b*255, gs)
end

-- Get GS tier name
function IE.GetGSTier(gs)
    if not gs or gs == 0 then return "Unknown" end

    if gs >= 6000 then return "Legendary"
    elseif gs >= 5500 then return "Epic"
    elseif gs >= 5000 then return "Rare"
    elseif gs >= 4500 then return "Uncommon"
    else return "Common"
    end
end

-- Clear cache for a player
function IE.ClearCache(name)
    if name then
        IE.Cache[name] = nil
    else
        IE.Cache = {}
    end
end

-- Event frame for inspection
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("INSPECT_READY")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "INSPECT_READY" then
        OnInspectReady()
    end
end)

-- OnUpdate for queue processing
local queueElapsed = 0
eventFrame:SetScript("OnUpdate", function(self, elapsed)
    queueElapsed = queueElapsed + elapsed
    if queueElapsed > 0.5 then
        queueElapsed = 0
        ProcessInspectionQueue()
    end
end)
