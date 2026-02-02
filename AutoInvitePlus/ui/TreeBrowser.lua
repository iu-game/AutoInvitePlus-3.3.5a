-- AutoInvite Plus - Tree Browser Module
-- Tree view implementation for raid hierarchy navigation

local AIP = AutoInvitePlus
AIP.TreeBrowser = {}
local TB = AIP.TreeBrowser

-- Tree node states
TB.NodeState = {
    COLLAPSED = 0,
    EXPANDED = 1,
}

-- Tree data structure
TB.TreeData = {
    nodes = {},           -- Root nodes
    expandedNodes = {},   -- {nodeId = true} for expanded nodes
    selectedNode = nil,   -- Currently selected node ID
    selectedPlayer = nil, -- Currently selected player name
}

-- Configuration
TB.Config = {
    indentWidth = 16,
    rowHeight = 32,  -- Increased from 20 to accommodate two lines (name + composition)
    iconSize = 16,
    maxVisibleRows = 20,
}

-- Icons for tree elements
TB.Icons = {
    collapsed = "Interface\\Buttons\\UI-PlusButton-UP",
    expanded = "Interface\\Buttons\\UI-MinusButton-UP",
    raid = "Interface\\TARGETINGFRAME\\UI-RaidTargetingIcon_8",  -- Skull icon
    player = "Interface\\ICONS\\INV_Misc_Head_Human_01",
    group = "Interface\\ICONS\\Ability_Warrior_RallyingCry",
}

-- Role icons (using LFG icons)
TB.RoleIcons = {
    TANK = {icon = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", coords = {0, 0.26, 0.26, 0.52}},
    HEALER = {icon = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", coords = {0.26, 0.52, 0, 0.26}},
    DPS = {icon = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES", coords = {0.26, 0.52, 0.26, 0.52}},
}

-- Class colors (reference from Composition module)
local function GetClassColor(class)
    if AIP.Composition and AIP.Composition.ClassColors[class] then
        local c = AIP.Composition.ClassColors[class]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- Track known categories to avoid resetting expand state
TB.KnownCategories = {}

-- Settings for hiding locked instances
TB.HideLocked = false

-- Stale entry timeout (seconds) - entries older than this are hidden from tree
-- Default: 180 seconds (3 minutes). Set to 0 to disable filtering.
TB.StaleTimeout = 180

-- Instance name to saved instance mapping for WotLK 3.3.5a (+ TBC and Classic)
TB.InstanceMapping = {
    -- =====================
    -- WOTLK RAIDS
    -- =====================
    -- ICC variants
    ["ICC"] = {"Icecrown Citadel"},
    ["ICC10"] = {"Icecrown Citadel"},
    ["ICC25"] = {"Icecrown Citadel"},
    ["ICC10N"] = {"Icecrown Citadel"},
    ["ICC10H"] = {"Icecrown Citadel"},
    ["ICC25N"] = {"Icecrown Citadel"},
    ["ICC25H"] = {"Icecrown Citadel"},
    ["ICC10HC"] = {"Icecrown Citadel"},
    ["ICC25HC"] = {"Icecrown Citadel"},
    ["ICECROWN"] = {"Icecrown Citadel"},
    -- Ruby Sanctum
    ["RS"] = {"The Ruby Sanctum"},
    ["RS10"] = {"The Ruby Sanctum"},
    ["RS25"] = {"The Ruby Sanctum"},
    ["RS10N"] = {"The Ruby Sanctum"},
    ["RS10H"] = {"The Ruby Sanctum"},
    ["RS25N"] = {"The Ruby Sanctum"},
    ["RS25H"] = {"The Ruby Sanctum"},
    ["RUBY"] = {"The Ruby Sanctum"},
    ["RUBYSANCTUM"] = {"The Ruby Sanctum"},
    -- TOC/TOGC
    ["TOC"] = {"Trial of the Crusader"},
    ["TOC10"] = {"Trial of the Crusader"},
    ["TOC25"] = {"Trial of the Crusader"},
    ["TOGC"] = {"Trial of the Crusader"},
    ["TOGC10"] = {"Trial of the Crusader"},
    ["TOGC25"] = {"Trial of the Crusader"},
    ["TGOC"] = {"Trial of the Crusader"},
    ["TOTC"] = {"Trial of the Crusader"},
    ["CRUSADER"] = {"Trial of the Crusader"},
    -- Onyxia
    ["ONY"] = {"Onyxia's Lair"},
    ["ONY10"] = {"Onyxia's Lair"},
    ["ONY25"] = {"Onyxia's Lair"},
    ["ONYXIA"] = {"Onyxia's Lair"},
    -- VOA
    ["VOA"] = {"Vault of Archavon"},
    ["VOA10"] = {"Vault of Archavon"},
    ["VOA25"] = {"Vault of Archavon"},
    ["ARCHAVON"] = {"Vault of Archavon"},
    ["VAULT"] = {"Vault of Archavon"},
    -- Ulduar
    ["ULDUAR"] = {"Ulduar"},
    ["ULD"] = {"Ulduar"},
    ["ULD10"] = {"Ulduar"},
    ["ULD25"] = {"Ulduar"},
    ["ULDUAR10"] = {"Ulduar"},
    ["ULDUAR25"] = {"Ulduar"},
    -- Naxxramas
    ["NAXX"] = {"Naxxramas"},
    ["NAXX10"] = {"Naxxramas"},
    ["NAXX25"] = {"Naxxramas"},
    ["NAXXRAMAS"] = {"Naxxramas"},
    -- OS
    ["OS"] = {"The Obsidian Sanctum"},
    ["OS10"] = {"The Obsidian Sanctum"},
    ["OS25"] = {"The Obsidian Sanctum"},
    ["OS0D"] = {"The Obsidian Sanctum"},
    ["OS1D"] = {"The Obsidian Sanctum"},
    ["OS2D"] = {"The Obsidian Sanctum"},
    ["OS3D"] = {"The Obsidian Sanctum"},
    ["SARTH"] = {"The Obsidian Sanctum"},
    ["SARTHARION"] = {"The Obsidian Sanctum"},
    ["OBSIDIAN"] = {"The Obsidian Sanctum"},
    -- EoE
    ["EOE"] = {"The Eye of Eternity"},
    ["EOE10"] = {"The Eye of Eternity"},
    ["EOE25"] = {"The Eye of Eternity"},
    ["MALYGOS"] = {"The Eye of Eternity"},
    ["MALY"] = {"The Eye of Eternity"},
    ["EYE"] = {"The Eye of Eternity"},

    -- =====================
    -- WOTLK HEROIC DUNGEONS
    -- =====================
    ["HOL"] = {"Halls of Lightning"},
    ["HOS"] = {"Halls of Stone"},
    ["HOLIGHTNING"] = {"Halls of Lightning"},
    ["HOSTONE"] = {"Halls of Stone"},
    ["GD"] = {"Gundrak"},
    ["GUNDRAK"] = {"Gundrak"},
    ["DTK"] = {"Drak'Tharon Keep"},
    ["DRAKTHARONKEEP"] = {"Drak'Tharon Keep"},
    ["VH"] = {"The Violet Hold"},
    ["VIOLETHOLD"] = {"The Violet Hold"},
    ["AN"] = {"Azjol-Nerub"},
    ["AZJOL"] = {"Azjol-Nerub"},
    ["AZJOLNERUB"] = {"Azjol-Nerub"},
    ["OK"] = {"Ahn'kahet: The Old Kingdom"},
    ["AHNKAHET"] = {"Ahn'kahet: The Old Kingdom"},
    ["OLDKINGDOM"] = {"Ahn'kahet: The Old Kingdom"},
    ["UK"] = {"Utgarde Keep"},
    ["UTGARDEKEEP"] = {"Utgarde Keep"},
    ["UP"] = {"Utgarde Pinnacle"},
    ["UTGARDEPINNACLE"] = {"Utgarde Pinnacle"},
    ["NEXUS"] = {"The Nexus"},
    ["OCULUS"] = {"The Oculus"},
    ["COS"] = {"The Culling of Stratholme"},
    ["COT"] = {"The Culling of Stratholme"},
    ["CULLING"] = {"The Culling of Stratholme"},
    ["STRATHOLME"] = {"The Culling of Stratholme"},
    -- ICC 5-man dungeons
    ["FOS"] = {"The Forge of Souls"},
    ["FORGEOFSOULS"] = {"The Forge of Souls"},
    ["POS"] = {"Pit of Saron"},
    ["PITOFSARON"] = {"Pit of Saron"},
    ["HOR"] = {"Halls of Reflection"},
    ["HALLSOFREFLECTION"] = {"Halls of Reflection"},
    -- Trial of the Champion
    ["TOC5"] = {"Trial of the Champion"},
    ["TOTC5"] = {"Trial of the Champion"},
    ["TRIALOFTHECHAMPION"] = {"Trial of the Champion"},

    -- =====================
    -- TBC RAIDS
    -- =====================
    ["SWP"] = {"Sunwell Plateau"},
    ["SUNWELL"] = {"Sunwell Plateau"},
    ["SUNWELLPLATEAU"] = {"Sunwell Plateau"},
    ["BT"] = {"Black Temple"},
    ["BLACKTEMPLE"] = {"Black Temple"},
    ["HYJAL"] = {"Hyjal Summit"},
    ["MH"] = {"Hyjal Summit"},
    ["MOUNTHYJAL"] = {"Hyjal Summit"},
    ["TK"] = {"Tempest Keep"},
    ["TEMPESTKEEP"] = {"Tempest Keep"},
    ["THEYE"] = {"Tempest Keep"},
    ["SSC"] = {"Serpentshrine Cavern"},
    ["SERPENTSHRINE"] = {"Serpentshrine Cavern"},
    ["GRUUL"] = {"Gruul's Lair"},
    ["GRUULS"] = {"Gruul's Lair"},
    ["GRUULSLAIR"] = {"Gruul's Lair"},
    ["MAG"] = {"Magtheridon's Lair"},
    ["MAGTHERIDON"] = {"Magtheridon's Lair"},
    ["MAGTHERIDONSLAIR"] = {"Magtheridon's Lair"},
    ["KARA"] = {"Karazhan"},
    ["KZ"] = {"Karazhan"},
    ["KARAZHAN"] = {"Karazhan"},
    ["ZA"] = {"Zul'Aman"},
    ["ZULAMAN"] = {"Zul'Aman"},

    -- =====================
    -- TBC HEROIC DUNGEONS
    -- =====================
    ["SH"] = {"The Shattered Halls"},
    ["SHATTEREDHALLS"] = {"The Shattered Halls"},
    ["SV"] = {"The Steamvault"},
    ["STEAMVAULT"] = {"The Steamvault"},
    ["SL"] = {"Shadow Labyrinth"},
    ["SLABS"] = {"Shadow Labyrinth"},
    ["SHADOWLAB"] = {"Shadow Labyrinth"},
    ["SHADOWLABYRINTH"] = {"Shadow Labyrinth"},
    ["ARCA"] = {"The Arcatraz"},
    ["ARCATRAZ"] = {"The Arcatraz"},
    ["MECH"] = {"The Mechanar"},
    ["MECHANAR"] = {"The Mechanar"},
    ["BOT"] = {"The Botanica"},
    ["BOTANICA"] = {"The Botanica"},
    ["MT"] = {"Mana-Tombs"},
    ["MANATOMBS"] = {"Mana-Tombs"},
    ["AC"] = {"Auchenai Crypts"},
    ["CRYPTS"] = {"Auchenai Crypts"},
    ["AUCHENAI"] = {"Auchenai Crypts"},
    ["SETH"] = {"Sethekk Halls"},
    ["SETHEKK"] = {"Sethekk Halls"},
    ["SP"] = {"The Slave Pens"},
    ["SLAVEPENS"] = {"The Slave Pens"},
    ["UB"] = {"The Underbog"},
    ["UNDERBOG"] = {"The Underbog"},
    ["BF"] = {"The Blood Furnace"},
    ["BLOODFURNACE"] = {"The Blood Furnace"},
    ["RAMPS"] = {"Hellfire Ramparts"},
    ["RAMPARTS"] = {"Hellfire Ramparts"},
    ["HELLFIRE"] = {"Hellfire Ramparts"},
    ["MGT"] = {"Magisters' Terrace"},
    ["MAGISTERSTERRACE"] = {"Magisters' Terrace"},

    -- =====================
    -- CLASSIC RAIDS
    -- =====================
    ["MC"] = {"Molten Core"},
    ["MOLTENCORE"] = {"Molten Core"},
    ["BWL"] = {"Blackwing Lair"},
    ["BLACKWINGLAIR"] = {"Blackwing Lair"},
    ["AQ40"] = {"Temple of Ahn'Qiraj"},
    ["AQ"] = {"Temple of Ahn'Qiraj"},
    ["TEMPLEOFAHNQIRAJ"] = {"Temple of Ahn'Qiraj"},
    ["AQ20"] = {"Ruins of Ahn'Qiraj"},
    ["RUINSOFAHNQIRAJ"] = {"Ruins of Ahn'Qiraj"},
    ["ZG"] = {"Zul'Gurub"},
    ["ZULGURUB"] = {"Zul'Gurub"},
    ["ONYXIASLAIR"] = {"Onyxia's Lair"},

    -- =====================
    -- CLASSIC DUNGEONS (High Level)
    -- =====================
    ["UBRS"] = {"Upper Blackrock Spire"},
    ["UPPERBLACKROCK"] = {"Upper Blackrock Spire"},
    ["LBRS"] = {"Lower Blackrock Spire"},
    ["LOWERBLACKROCK"] = {"Lower Blackrock Spire"},
    ["BRS"] = {"Upper Blackrock Spire", "Lower Blackrock Spire"},
    ["BLACKROCK"] = {"Upper Blackrock Spire", "Lower Blackrock Spire"},
    ["STRAT"] = {"Stratholme"},
    ["STRATHOLMELIVE"] = {"Stratholme"},
    ["STRATHOLMEUD"] = {"Stratholme"},
    ["SCHOLO"] = {"Scholomance"},
    ["SCHOLOMANCE"] = {"Scholomance"},
    ["DM"] = {"Dire Maul"},
    ["DIREMAUL"] = {"Dire Maul"},
    ["DME"] = {"Dire Maul"},
    ["DMN"] = {"Dire Maul"},
    ["DMW"] = {"Dire Maul"},
    ["BRD"] = {"Blackrock Depths"},
    ["BLACKROCKDEPTHS"] = {"Blackrock Depths"},
}

-- Cache for player's saved instances (refreshed periodically)
TB.SavedInstances = {}
TB.SavedInstancesLastUpdate = 0

-- Get player's saved instance lockouts
function TB.UpdateSavedInstances()
    TB.SavedInstances = {}

    -- Request fresh raid info from server
    RequestRaidInfo()

    -- GetNumSavedInstances returns the number of saved instances
    local numSaved = GetNumSavedInstances and GetNumSavedInstances() or 0

    for i = 1, numSaved do
        -- GetSavedInstanceInfo(index) returns: name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
        -- Only count as locked if: locked flag is true AND reset time is positive (not expired)
        -- reset is the number of seconds until the lockout expires; if <= 0, it's expired
        if name and locked and reset and reset > 0 then
            -- Store by name and size/difficulty
            local key = name .. "_" .. (maxPlayers or 0) .. "_" .. (difficulty or 0)
            TB.SavedInstances[key] = {
                name = name,
                id = id,
                reset = reset,
                difficulty = difficulty,
                maxPlayers = maxPlayers,
                difficultyName = difficultyName,
            }
            -- Also store just by name for simpler lookups
            TB.SavedInstances[name] = TB.SavedInstances[name] or {}
            table.insert(TB.SavedInstances[name], {
                maxPlayers = maxPlayers,
                difficulty = difficulty,
                difficultyName = difficultyName,
                reset = reset,
            })
        end
    end

    TB.SavedInstancesLastUpdate = time()
end

-- Extract raid size from raid string (returns 10, 25, or nil if not specified)
local function ExtractRaidSize(raidStr)
    if not raidStr then return nil end

    -- Look for size indicators in common raid string formats
    -- Valid patterns: ICC10, ICC25, ICC10N, ICC10H, ICC10HC, ICC25HC, VOA10, TOC25, etc.
    -- The number should be followed by end-of-string, H, N, M, or HC (difficulty indicators)

    -- Check for 10-man: number 10 followed by end or difficulty letter (not another digit)
    if raidStr:match("10$") or raidStr:match("10[HNM]") then
        return 10
    end

    -- Check for 25-man: number 25 followed by end or difficulty letter (not another digit)
    if raidStr:match("25$") or raidStr:match("25[HNM]") then
        return 25
    end

    return nil  -- Size not specified
end

-- Check if player is locked to an instance based on raid string
function TB.IsLockedToInstance(raidStr)
    if not raidStr then return false end

    -- Refresh saved instances if stale (older than 30 seconds)
    if time() - TB.SavedInstancesLastUpdate > 30 then
        TB.UpdateSavedInstances()
    end

    local raidUpper = raidStr:upper():gsub("%s+", "")
    local requestedSize = ExtractRaidSize(raidUpper)

    -- Helper function to check if a lock matches the requested size
    local function LockMatchesSize(lock, wantedSize)
        if not wantedSize then
            -- No size specified in raid string - don't mark as locked
            -- (player might be doing the other size which isn't locked)
            return false
        end
        return lock.maxPlayers == wantedSize
    end

    -- Helper function to check locks for an instance name
    local function CheckLocksForInstance(instName)
        local locks = TB.SavedInstances[instName]
        if not locks then return false end

        for _, lock in ipairs(locks) do
            -- Verify lock is still active (reset > 0)
            if lock.reset and lock.reset > 0 then
                if LockMatchesSize(lock, requestedSize) then
                    return true
                end
            end
        end
        return false
    end

    -- Try direct mapping first (most accurate)
    local instanceNames = TB.InstanceMapping[raidUpper]
    if instanceNames then
        for _, instName in ipairs(instanceNames) do
            if CheckLocksForInstance(instName) then
                return true
            end
        end
        -- If we had a direct mapping but no matching lock, return false
        -- Don't fall through to partial matching
        return false
    end

    -- Try partial matching only if no direct mapping exists
    -- This is less accurate so we're more conservative
    for mapKey, instNames in pairs(TB.InstanceMapping) do
        -- Only match if the map key is contained in the raid string
        -- AND extract size from the map key to compare
        if raidUpper:find(mapKey, 1, true) then
            local mapKeySize = ExtractRaidSize(mapKey)
            -- Only use this mapping if sizes are compatible
            if not requestedSize or not mapKeySize or requestedSize == mapKeySize then
                for _, instName in ipairs(instNames) do
                    if CheckLocksForInstance(instName) then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Build tree structure for LFM groups
-- preserveState: if true, don't auto-expand new categories
function TB.BuildLFMTree(preserveState)
    local tree = {}

    if not AIP.GroupTracker then
        return tree
    end

    -- Get all groups
    local allGroups = AIP.GroupTracker.GetAllGroups()

    -- If no groups, return empty tree
    if #allGroups == 0 then
        return tree
    end

    -- Filter out stale entries if timeout is set
    local now = time()
    local staleTimeout = TB.StaleTimeout or 180  -- Default 3 min
    if staleTimeout > 0 then
        local freshGroups = {}
        for _, group in ipairs(allGroups) do
            local age = group.time and (now - group.time) or 0
            -- Keep if fresh OR if it's our own listing
            if age <= staleTimeout or group.isOwn then
                table.insert(freshGroups, group)
            end
        end
        allGroups = freshGroups
    end

    -- If no fresh groups remain, return empty tree
    if #allGroups == 0 then
        return tree
    end

    -- Organize groups by category
    local groupsByCategory = {}  -- {categoryId = {groups}}
    local unmatchedGroups = {}   -- Groups that don't match any category

    for _, group in ipairs(allGroups) do
        local raid = group.raid or ""
        local matched = false

        -- Try to match to a category
        for _, cat in ipairs(AIP.GroupTracker.RaidHierarchy) do
            -- Check if raid starts with category id or equals it
            if raid == cat.id or raid:find("^" .. cat.id) then
                groupsByCategory[cat.id] = groupsByCategory[cat.id] or {}
                table.insert(groupsByCategory[cat.id], group)
                matched = true
                break
            end
        end

        if not matched then
            table.insert(unmatchedGroups, group)
        end
    end

    -- Update saved instances before building tree
    TB.UpdateSavedInstances()

    -- Build tree from categories
    for _, category in ipairs(AIP.GroupTracker.RaidHierarchy) do
        local catGroups = groupsByCategory[category.id] or {}

        if #catGroups > 0 then
            -- Filter out locked groups if HideLocked is enabled
            local filteredGroups = {}
            local lockedCount = 0
            for _, group in ipairs(catGroups) do
                local isLocked = TB.IsLockedToInstance(group.raid)
                if isLocked then lockedCount = lockedCount + 1 end
                if not TB.HideLocked or not isLocked or group.isOwn then
                    group.isLocked = isLocked  -- Store lock state for coloring
                    table.insert(filteredGroups, group)
                end
            end

            if #filteredGroups > 0 then
                local catNode = {
                    id = "lfm_" .. category.id,
                    type = "category",
                    text = category.name .. " (" .. #filteredGroups .. ")",
                    count = #filteredGroups,
                    icon = TB.Icons.raid,
                    children = {},
                    data = category,
                }

                -- Only auto-expand if this is a NEW category we haven't seen before
                -- and we're not in preserveState mode
                if not preserveState and not TB.KnownCategories[catNode.id] then
                    TB.TreeData.expandedNodes[catNode.id] = true
                    TB.KnownCategories[catNode.id] = true
                end

                -- Add each group as a direct child
                for _, group in ipairs(filteredGroups) do
                    local displayName = group.leader .. " - " .. (group.raid or "?")

                    -- Build composition text for second line
                    local compText = ""
                    if group.tanks or group.healers or group.mdps or group.rdps or group.dps then
                        local compParts = {}
                        if group.tanks then
                            local tc = group.tanks.current or 0
                            local tn = group.tanks.needed or 0
                            table.insert(compParts, string.format("|cFF00FF00T|r:%d/%d", tc, tn))
                        end
                        if group.healers then
                            local hc = group.healers.current or 0
                            local hn = group.healers.needed or 0
                            table.insert(compParts, string.format("|cFF00D1FFH|r:%d/%d", hc, hn))
                        end
                        if group.mdps then
                            local mc = group.mdps.current or 0
                            local mn = group.mdps.needed or 0
                            table.insert(compParts, string.format("|cFFFF6600M|r:%d/%d", mc, mn))
                        end
                        if group.rdps then
                            local rc = group.rdps.current or 0
                            local rn = group.rdps.needed or 0
                            table.insert(compParts, string.format("|cFFFFCC00R|r:%d/%d", rc, rn))
                        end
                        -- Backwards compatibility: show old dps field if mdps/rdps not present
                        if not group.mdps and not group.rdps and group.dps then
                            local dc = group.dps.current or 0
                            local dn = group.dps.needed or 0
                            table.insert(compParts, string.format("D:%d/%d", dc, dn))
                        end
                        if #compParts > 0 then
                            compText = table.concat(compParts, "  ")
                        end
                    end

                    local textColor = nil

                    -- Highlight player's own listing (green)
                    if group.isOwn then
                        displayName = "|cFF00FF00(You)|r " .. displayName
                        textColor = {r = 0, g = 1, b = 0}
                    -- Mark locked instances with red color (no label)
                    elseif group.isLocked then
                        textColor = {r = 1, g = 0.4, b = 0.4}
                    -- Mark DataBus entries (cyan indicator)
                    elseif group.isDataBus then
                        displayName = "|cFF00CCFF[AIP]|r " .. displayName
                    end

                    local groupNode = {
                        id = "lfm_group_" .. group.leader,
                        type = "group",
                        text = displayName,
                        compText = compText,  -- Composition on second line
                        textColor = textColor,
                        icon = TB.Icons.group,
                        isLeaf = true,
                        data = group,
                        isLocked = group.isLocked,
                    }
                    table.insert(catNode.children, groupNode)
                end

                table.insert(tree, catNode)
            end
        end
    end

    -- Add unmatched groups to "Other" category
    if #unmatchedGroups > 0 then
        -- Filter out locked groups if HideLocked is enabled
        local filteredUnmatched = {}
        for _, group in ipairs(unmatchedGroups) do
            local isLocked = TB.IsLockedToInstance(group.raid)
            if not TB.HideLocked or not isLocked or group.isOwn then
                group.isLocked = isLocked
                table.insert(filteredUnmatched, group)
            end
        end

        if #filteredUnmatched > 0 then
            local otherNode = {
                id = "lfm_other",
                type = "category",
                text = "Other (" .. #filteredUnmatched .. ")",
                count = #filteredUnmatched,
                icon = TB.Icons.raid,
                children = {},
            }

            -- Only auto-expand if this is a NEW category
            if not preserveState and not TB.KnownCategories[otherNode.id] then
                TB.TreeData.expandedNodes[otherNode.id] = true
                TB.KnownCategories[otherNode.id] = true
            end

            for _, group in ipairs(filteredUnmatched) do
                local displayName = group.leader .. " - " .. (group.raid or "Unknown")

                -- Build composition text for second line
                local compText = ""
                if group.tanks or group.healers or group.mdps or group.rdps or group.dps then
                    local compParts = {}
                    if group.tanks then
                        local tc = group.tanks.current or 0
                        local tn = group.tanks.needed or 0
                        table.insert(compParts, string.format("|cFF00FF00T|r:%d/%d", tc, tn))
                    end
                    if group.healers then
                        local hc = group.healers.current or 0
                        local hn = group.healers.needed or 0
                        table.insert(compParts, string.format("|cFF00D1FFH|r:%d/%d", hc, hn))
                    end
                    if group.mdps then
                        local mc = group.mdps.current or 0
                        local mn = group.mdps.needed or 0
                        table.insert(compParts, string.format("|cFFFF6600M|r:%d/%d", mc, mn))
                    end
                    if group.rdps then
                        local rc = group.rdps.current or 0
                        local rn = group.rdps.needed or 0
                        table.insert(compParts, string.format("|cFFFFCC00R|r:%d/%d", rc, rn))
                    end
                    -- Backwards compatibility
                    if not group.mdps and not group.rdps and group.dps then
                        local dc = group.dps.current or 0
                        local dn = group.dps.needed or 0
                        table.insert(compParts, string.format("D:%d/%d", dc, dn))
                    end
                    if #compParts > 0 then
                        compText = table.concat(compParts, "  ")
                    end
                end

                local textColor = nil

                -- Highlight player's own listing (green)
                if group.isOwn then
                    displayName = "|cFF00FF00(You)|r " .. displayName
                    textColor = {r = 0, g = 1, b = 0}
                -- Mark locked instances with red color (no label)
                elseif group.isLocked then
                    textColor = {r = 1, g = 0.4, b = 0.4}
                -- Mark DataBus entries (cyan indicator)
                elseif group.isDataBus then
                    displayName = "|cFF00CCFF[AIP]|r " .. displayName
                end

                local groupNode = {
                    id = "lfm_group_" .. group.leader,
                    type = "group",
                    text = displayName,
                    compText = compText,  -- Composition on second line
                    textColor = textColor,
                    icon = TB.Icons.group,
                    isLeaf = true,
                    data = group,
                    isLocked = group.isLocked,
                }
                table.insert(otherNode.children, groupNode)
            end

            table.insert(tree, otherNode)
        end
    end

    return tree
end

-- Build tree structure for LFG players
-- preserveState: if true, don't auto-expand new categories
function TB.BuildLFGTree(preserveState)
    local tree = {}

    if not AIP.LFMBrowser then return tree end

    -- Get all players (both LFG and LFM for now)
    local allPlayers = AIP.LFMBrowser.GetFilteredPlayers({})

    if #allPlayers == 0 then
        return tree
    end

    -- Filter out stale entries if timeout is set
    local now = time()
    local staleTimeout = TB.StaleTimeout or 180  -- Default 3 min
    if staleTimeout > 0 then
        local freshPlayers = {}
        for _, player in ipairs(allPlayers) do
            local age = player.time and (now - player.time) or 0
            if age <= staleTimeout then
                table.insert(freshPlayers, player)
            end
        end
        allPlayers = freshPlayers
    end

    -- If no fresh players remain, return empty tree
    if #allPlayers == 0 then
        return tree
    end

    -- Organize by category based on raids they're looking for
    local playersByCategory = {}  -- {categoryId = {players}}
    local unmatchedPlayers = {}   -- Players without raid preference

    for _, player in ipairs(allPlayers) do
        local matched = false

        if player.raids and #player.raids > 0 then
            for _, raidId in ipairs(player.raids) do
                -- Try to match to a category
                for _, cat in ipairs(AIP.GroupTracker.RaidHierarchy) do
                    if raidId:upper() == cat.id or raidId:upper():find("^" .. cat.id) then
                        playersByCategory[cat.id] = playersByCategory[cat.id] or {}
                        -- Avoid duplicates
                        local found = false
                        for _, p in ipairs(playersByCategory[cat.id]) do
                            if p.name == player.name then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(playersByCategory[cat.id], player)
                        end
                        matched = true
                        break
                    end
                end
            end
        end

        if not matched then
            table.insert(unmatchedPlayers, player)
        end
    end

    -- Build tree from categories
    for _, category in ipairs(AIP.GroupTracker.RaidHierarchy) do
        local catPlayers = playersByCategory[category.id] or {}

        if #catPlayers > 0 then
            local catNode = {
                id = "lfg_" .. category.id,
                type = "category",
                text = category.name .. " (" .. #catPlayers .. ")",
                count = #catPlayers,
                icon = TB.Icons.raid,
                children = {},
                data = category,
            }

            -- Only auto-expand if this is a NEW category
            if not preserveState and not TB.KnownCategories[catNode.id] then
                TB.TreeData.expandedNodes[catNode.id] = true
                TB.KnownCategories[catNode.id] = true
            end

            -- Add players as direct children
            for _, player in ipairs(catPlayers) do
                local r, g, b = GetClassColor(player.class or "UNKNOWN")
                local roleStr = player.role and (" [" .. player.role .. "]") or ""
                local displayName = player.name .. roleStr
                -- Mark DataBus entries (cyan indicator)
                if player.isDataBus then
                    displayName = "|cFF00CCFF[AIP]|r " .. displayName
                end
                local playerNode = {
                    id = "lfg_player_" .. player.name,
                    type = "player",
                    text = displayName,
                    textColor = {r = r, g = g, b = b},
                    role = player.role,
                    icon = TB.Icons.player,
                    isLeaf = true,
                    data = player,
                    isDataBus = player.isDataBus,
                }
                table.insert(catNode.children, playerNode)
            end

            table.insert(tree, catNode)
        end
    end

    -- Add unmatched players to "Other" category
    if #unmatchedPlayers > 0 then
        local otherNode = {
            id = "lfg_other",
            type = "category",
            text = "Other (" .. #unmatchedPlayers .. ")",
            count = #unmatchedPlayers,
            icon = TB.Icons.raid,
            children = {},
        }

        -- Only auto-expand if this is a NEW category
        if not preserveState and not TB.KnownCategories[otherNode.id] then
            TB.TreeData.expandedNodes[otherNode.id] = true
            TB.KnownCategories[otherNode.id] = true
        end

        for _, player in ipairs(unmatchedPlayers) do
            local r, g, b = GetClassColor(player.class or "UNKNOWN")
            local roleStr = player.role and (" [" .. player.role .. "]") or ""
            local displayName = player.name .. roleStr
            -- Mark DataBus entries (cyan indicator)
            if player.isDataBus then
                displayName = "|cFF00CCFF[AIP]|r " .. displayName
            end
            local playerNode = {
                id = "lfg_player_" .. player.name,
                type = "player",
                text = displayName,
                textColor = {r = r, g = g, b = b},
                role = player.role,
                icon = TB.Icons.player,
                isLeaf = true,
                data = player,
                isDataBus = player.isDataBus,
            }
            table.insert(otherNode.children, playerNode)
        end

        table.insert(tree, otherNode)
    end

    return tree
end

-- Toggle node expansion
function TB.ToggleNode(nodeId)
    if TB.TreeData.expandedNodes[nodeId] then
        TB.TreeData.expandedNodes[nodeId] = nil
    else
        TB.TreeData.expandedNodes[nodeId] = true
    end
end

-- Check if node is expanded
function TB.IsNodeExpanded(nodeId)
    return TB.TreeData.expandedNodes[nodeId] == true
end

-- Select a node
function TB.SelectNode(nodeId, playerName)
    TB.TreeData.selectedNode = nodeId
    TB.TreeData.selectedPlayer = playerName

    -- Notify UI
    if AIP.OnTreeSelectionChanged then
        AIP.OnTreeSelectionChanged(nodeId, playerName)
    end
end

-- Get selected player data
function TB.GetSelectedPlayerData()
    if not TB.TreeData.selectedPlayer then return nil end

    -- Try LFG players first
    if AIP.LFMBrowser and AIP.LFMBrowser.Players then
        local player = AIP.LFMBrowser.Players[TB.TreeData.selectedPlayer]
        if player then return player end
    end

    -- Try LFM groups
    if AIP.GroupTracker and AIP.GroupTracker.Groups then
        local group = AIP.GroupTracker.Groups[TB.TreeData.selectedPlayer]
        if group then return group end
    end

    return nil
end

-- Flatten tree for display (respecting expansion state)
function TB.FlattenTree(nodes, depth)
    depth = depth or 0
    local result = {}

    if not nodes then
        return result
    end

    for _, node in ipairs(nodes) do
        table.insert(result, {
            node = node,
            depth = depth,
        })

        if node.children and #node.children > 0 and TB.IsNodeExpanded(node.id) then
            local childResults = TB.FlattenTree(node.children, depth + 1)
            for _, child in ipairs(childResults) do
                table.insert(result, child)
            end
        end
    end

    return result
end

-- Expand all nodes
function TB.ExpandAll(nodes)
    nodes = nodes or TB.TreeData.nodes

    for _, node in ipairs(nodes) do
        if node.children and #node.children > 0 then
            TB.TreeData.expandedNodes[node.id] = true
            TB.ExpandAll(node.children)
        end
    end
end

-- Collapse all nodes
function TB.CollapseAll()
    TB.TreeData.expandedNodes = {}
end

-- Search/filter tree
function TB.FilterTree(nodes, searchText)
    if not searchText or searchText == "" then
        return nodes
    end

    local searchLower = searchText:lower()
    local filtered = {}

    for _, node in ipairs(nodes) do
        local matches = false
        local filteredChildren = {}

        -- Check if this node matches
        if node.text and node.text:lower():find(searchLower, 1, true) then
            matches = true
        end

        -- Check children
        if node.children then
            filteredChildren = TB.FilterTree(node.children, searchText)
            if #filteredChildren > 0 then
                matches = true
            end
        end

        if matches then
            local filteredNode = {}
            for k, v in pairs(node) do
                filteredNode[k] = v
            end
            filteredNode.children = filteredChildren
            table.insert(filtered, filteredNode)

            -- Auto-expand matching parent nodes
            if #filteredChildren > 0 then
                TB.TreeData.expandedNodes[node.id] = true
            end
        end
    end

    return filtered
end

-- Create tree view widget
function TB.CreateTreeView(parent, width, height)
    local frameName = "AIPTreeView" .. tostring(math.random(10000, 99999))
    local frame = CreateFrame("Frame", frameName, parent)
    frame:SetSize(width, height)

    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0.1, 0.1, 0.1, 1)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Content frame for rows (sits above backdrop, clips children to prevent overflow)
    local content = CreateFrame("Frame", frameName.."Content", frame)
    content:SetPoint("TOPLEFT", 5, -5)
    content:SetPoint("BOTTOMRIGHT", -22, 5)
    content:SetFrameLevel(frame:GetFrameLevel() + 2)

    -- Enable clipping if available (not in all WotLK versions)
    if content.SetClipsChildren then
        content:SetClipsChildren(true)
    end

    -- Add solid background to content area
    local contentBg = content:CreateTexture(nil, "BACKGROUND")
    contentBg:SetAllPoints()
    contentBg:SetTexture(0.1, 0.1, 0.1, 1)

    -- Scroll frame
    local scrollName = frameName .. "Scroll"
    local scrollFrame = CreateFrame("ScrollFrame", scrollName, frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 5)

    -- Calculate rows
    local numRows = math.floor((height - 10) / TB.Config.rowHeight)
    frame.rows = {}
    frame.scrollFrame = scrollFrame
    frame.numRows = numRows
    frame.content = content

    -- Create row buttons
    for i = 1, numRows do
        local row = CreateFrame("Button", frameName.."Row"..i, content)
        row:SetSize(width - 35, TB.Config.rowHeight)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * TB.Config.rowHeight))
        row:SetFrameLevel(content:GetFrameLevel() + 1)

        -- Row background for better visibility
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        rowBg:SetTexture(0, 0, 0, 0)
        row.bg = rowBg

        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Expand button
        local expandBtn = CreateFrame("Button", nil, row)
        expandBtn:SetSize(14, 14)
        expandBtn:SetPoint("LEFT", 2, 0)
        expandBtn:SetNormalTexture(TB.Icons.collapsed)
        expandBtn:Hide()
        row.expandBtn = expandBtn

        -- Icon (fixed position from left)
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(TB.Config.iconSize, TB.Config.iconSize)
        icon:SetPoint("LEFT", expandBtn, "RIGHT", 2, 0)
        row.icon = icon

        -- Role icon (fixed position after icon)
        local roleIcon = row:CreateTexture(nil, "ARTWORK")
        roleIcon:SetSize(TB.Config.iconSize, TB.Config.iconSize)
        roleIcon:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        roleIcon:Hide()
        row.roleIcon = roleIcon

        -- Text - anchored to row with fixed left offset (not to icons)
        -- This ensures text position is stable regardless of icon visibility
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", row, "LEFT", 56, 5)  -- Offset up for two-line layout
        text:SetPoint("RIGHT", row, "RIGHT", -5, 5)
        text:SetJustifyH("LEFT")
        row.text = text

        -- Composition text (second line, smaller font)
        local compText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        compText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
        compText:SetPoint("RIGHT", row, "RIGHT", -40, 0)  -- Leave room for timer
        compText:SetJustifyH("LEFT")
        compText:SetTextColor(0.7, 0.7, 0.7)  -- Slightly dimmer
        compText:Hide()
        row.compText = compText

        -- Timer text (right side, shows seconds since detected)
        local timerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timerText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
        timerText:SetWidth(35)
        timerText:SetJustifyH("RIGHT")
        timerText:SetTextColor(0.5, 0.5, 0.5)
        timerText:Hide()
        row.timerText = timerText

        row:Hide()
        frame.rows[i] = row
    end

    -- Update function
    function frame:Update(treeData, scrollOffset)
        scrollOffset = scrollOffset or 0
        local flatList = TB.FlattenTree(treeData or {})
        local numItems = #flatList

        FauxScrollFrame_Update(self.scrollFrame, numItems, self.numRows, TB.Config.rowHeight)

        for i = 1, self.numRows do
            local row = self.rows[i]
            local index = scrollOffset + i

            if index <= numItems then
                local item = flatList[index]
                local node = item.node

                -- Indent based on depth
                local indent = 2 + (item.depth * TB.Config.indentWidth)
                row.expandBtn:ClearAllPoints()
                row.expandBtn:SetPoint("LEFT", indent, 0)

                -- Expand button
                if node.children and #node.children > 0 then
                    row.expandBtn:Show()
                    row.expandBtn:SetNormalTexture(TB.IsNodeExpanded(node.id) and TB.Icons.expanded or TB.Icons.collapsed)
                    row.expandBtn:SetScript("OnClick", function()
                        TB.ToggleNode(node.id)
                        self:Update(treeData, FauxScrollFrame_GetOffset(self.scrollFrame))
                    end)
                else
                    row.expandBtn:Hide()
                end

                -- Icon (positioned after expand button with indent)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", indent + 18, 0)
                if node.icon then
                    row.icon:SetTexture(node.icon)
                    row.icon:Show()
                else
                    row.icon:Hide()
                end

                -- Role icon (positioned after main icon)
                row.roleIcon:ClearAllPoints()
                row.roleIcon:SetPoint("LEFT", row, "LEFT", indent + 36, 0)
                local roleShown = false
                if node.role and TB.RoleIcons[node.role] then
                    local ri = TB.RoleIcons[node.role]
                    row.roleIcon:SetTexture(ri.icon)
                    row.roleIcon:SetTexCoord(unpack(ri.coords))
                    row.roleIcon:Show()
                    roleShown = true
                else
                    row.roleIcon:Hide()
                end

                -- Update text position based on indent and visible icons
                local textOffset = indent + 18  -- Base offset after expand button
                if node.icon then textOffset = textOffset + 18 end  -- Icon space
                if roleShown then textOffset = textOffset + 18 end  -- Role icon space

                -- Check if this node has composition data (groups/players with role info)
                local hasComp = node.compText and node.compText ~= ""
                local vertOffset = hasComp and 5 or 0  -- Shift up if we have a second line

                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", textOffset, vertOffset)
                row.text:SetPoint("RIGHT", row, "RIGHT", -5, vertOffset)

                -- Text with highlight color for categories
                row.text:SetText(node.text or "")
                if node.textColor then
                    row.text:SetTextColor(node.textColor.r, node.textColor.g, node.textColor.b)
                elseif node.type == "category" then
                    row.text:SetTextColor(1, 0.82, 0)  -- Gold for categories
                else
                    row.text:SetTextColor(1, 1, 1)
                end

                -- Composition text (second line for groups)
                if hasComp then
                    row.compText:ClearAllPoints()
                    row.compText:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -1)
                    row.compText:SetPoint("RIGHT", row, "RIGHT", -40, 0)  -- Leave room for timer
                    row.compText:SetText(node.compText)
                    row.compText:Show()
                else
                    row.compText:Hide()
                end

                -- Timer display (seconds since detected/synced)
                row.nodeData = node  -- Store for timer refresh
                if node.data and node.data.time and (node.type == "group" or node.type == "player") then
                    local elapsed = time() - node.data.time
                    local timerStr
                    if elapsed < 60 then
                        timerStr = elapsed .. "s"
                    elseif elapsed < 3600 then
                        timerStr = math.floor(elapsed / 60) .. "m"
                    else
                        timerStr = math.floor(elapsed / 3600) .. "h"
                    end
                    row.timerText:SetText(timerStr)
                    -- Color based on age (green=fresh, yellow=aging, red=stale)
                    if elapsed < 120 then
                        row.timerText:SetTextColor(0.4, 0.8, 0.4)  -- Green
                    elseif elapsed < 300 then
                        row.timerText:SetTextColor(0.8, 0.8, 0.4)  -- Yellow
                    else
                        row.timerText:SetTextColor(0.8, 0.4, 0.4)  -- Red
                    end
                    row.timerText:Show()
                else
                    row.timerText:Hide()
                end

                -- Alternating row background
                if index % 2 == 0 then
                    row.bg:SetTexture(1, 1, 1, 0.03)
                else
                    row.bg:SetTexture(0, 0, 0, 0)
                end

                -- Click handlers
                row:SetScript("OnClick", function()
                    local playerName = nil
                    local nodeData = nil
                    if node.type == "player" or node.type == "group" then
                        playerName = node.data and (node.data.name or node.data.leader)
                        nodeData = node.data  -- Pass the actual data
                    end
                    TB.SelectNode(node.id, playerName, nodeData)
                    self:Update(treeData, FauxScrollFrame_GetOffset(self.scrollFrame))
                end)

                row:SetScript("OnDoubleClick", function()
                    if node.children and #node.children > 0 then
                        TB.ToggleNode(node.id)
                        self:Update(treeData, FauxScrollFrame_GetOffset(self.scrollFrame))
                    end
                end)

                -- Tooltip for composition display
                row:SetScript("OnEnter", function(self)
                    local n = self.nodeData
                    if not n or not n.data then return end
                    if n.type == "group" or n.type == "player" then
                        local group = n.data
                        if group.tanks or group.healers or group.mdps or group.rdps or group.dps then
                            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                            GameTooltip:AddLine(group.leader or group.name or "Group", 1, 0.82, 0)
                            GameTooltip:AddLine(" ")
                            GameTooltip:AddLine("Composition (Filled/Needed):", 0.8, 0.8, 0.8)

                            if group.tanks then
                                local tc = group.tanks.current or 0
                                local tn = group.tanks.needed or 0
                                local color = tc >= tn and {0, 1, 0} or {1, 0.5, 0}
                                GameTooltip:AddDoubleLine("|cFF00FF00T|r = Tanks", string.format("%d / %d", tc, tn), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end
                            if group.healers then
                                local hc = group.healers.current or 0
                                local hn = group.healers.needed or 0
                                local color = hc >= hn and {0, 1, 0} or {1, 0.5, 0}
                                GameTooltip:AddDoubleLine("|cFF00D1FFH|r = Healers", string.format("%d / %d", hc, hn), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end
                            if group.mdps then
                                local mc = group.mdps.current or 0
                                local mn = group.mdps.needed or 0
                                local color = mc >= mn and {0, 1, 0} or {1, 0.5, 0}
                                GameTooltip:AddDoubleLine("|cFFFF6600M|r = Melee DPS", string.format("%d / %d", mc, mn), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end
                            if group.rdps then
                                local rc = group.rdps.current or 0
                                local rn = group.rdps.needed or 0
                                local color = rc >= rn and {0, 1, 0} or {1, 0.5, 0}
                                GameTooltip:AddDoubleLine("|cFFFFCC00R|r = Ranged DPS", string.format("%d / %d", rc, rn), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end
                            -- Backwards compat
                            if not group.mdps and not group.rdps and group.dps then
                                local dc = group.dps.current or 0
                                local dn = group.dps.needed or 0
                                local color = dc >= dn and {0, 1, 0} or {1, 0.5, 0}
                                GameTooltip:AddDoubleLine("D = DPS", string.format("%d / %d", dc, dn), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end

                            -- Total filled
                            local totalCurrent = (group.tanks and group.tanks.current or 0) +
                                               (group.healers and group.healers.current or 0) +
                                               (group.mdps and group.mdps.current or 0) +
                                               (group.rdps and group.rdps.current or 0)
                            local totalNeeded = (group.tanks and group.tanks.needed or 0) +
                                              (group.healers and group.healers.needed or 0) +
                                              (group.mdps and group.mdps.needed or 0) +
                                              (group.rdps and group.rdps.needed or 0)
                            if totalNeeded > 0 then
                                GameTooltip:AddLine(" ")
                                local color = totalCurrent >= totalNeeded and {0, 1, 0} or {1, 0.82, 0}
                                GameTooltip:AddDoubleLine("Total Filled:", string.format("%d / %d", totalCurrent, totalNeeded), 0.7, 0.7, 0.7, color[1], color[2], color[3])
                            end

                            if group.gsMin then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddDoubleLine("Min GS:", tostring(group.gsMin) .. "+", 0.7, 0.7, 0.7, 1, 1, 0)
                            end
                            if group.ilvlMin and group.ilvlMin > 0 then
                                GameTooltip:AddDoubleLine("Min iLvl:", tostring(group.ilvlMin) .. "+", 0.7, 0.7, 0.7, 1, 0.82, 0)
                            end

                            -- Looking For classes/specs
                            if group.roleSpecs then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine("Looking For:", 0.8, 0.8, 0.8)
                                if group.roleSpecs.TANK and #group.roleSpecs.TANK > 0 then
                                    GameTooltip:AddLine("  |cFF00FFFFTanks:|r " .. table.concat(group.roleSpecs.TANK, ", "), 0.9, 0.9, 0.9)
                                end
                                if group.roleSpecs.HEALER and #group.roleSpecs.HEALER > 0 then
                                    GameTooltip:AddLine("  |cFF00FF00Healers:|r " .. table.concat(group.roleSpecs.HEALER, ", "), 0.9, 0.9, 0.9)
                                end
                                if group.roleSpecs.MDPS and #group.roleSpecs.MDPS > 0 then
                                    GameTooltip:AddLine("  |cFFFF6600Melee:|r " .. table.concat(group.roleSpecs.MDPS, ", "), 0.9, 0.9, 0.9)
                                end
                                if group.roleSpecs.RDPS and #group.roleSpecs.RDPS > 0 then
                                    GameTooltip:AddLine("  |cFFFFCC00Ranged:|r " .. table.concat(group.roleSpecs.RDPS, ", "), 0.9, 0.9, 0.9)
                                end
                            elseif group.lookingForSpecs and #group.lookingForSpecs > 0 then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine("Looking For: " .. table.concat(group.lookingForSpecs, ", "), 0.9, 0.9, 0.9)
                            end

                            if group.note and group.note ~= "" then
                                GameTooltip:AddLine(" ")
                                GameTooltip:AddLine("Note: " .. group.note, 0.7, 0.7, 0.7, true)
                            end
                            GameTooltip:Show()
                        end
                    end
                end)

                row:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)

                -- Highlight selected
                if node.id == TB.TreeData.selectedNode then
                    row:LockHighlight()
                else
                    row:UnlockHighlight()
                end

                row.nodeData = node
                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Scroll handler
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, TB.Config.rowHeight, function()
            frame:Update(frame.currentTreeData, FauxScrollFrame_GetOffset(self))
        end)
    end)

    -- Store tree data reference
    -- preserveScroll: if true, maintain current scroll position
    function frame:SetTreeData(data, preserveScroll)
        frame.currentTreeData = data
        local offset = 0
        if preserveScroll and self.scrollFrame then
            offset = FauxScrollFrame_GetOffset(self.scrollFrame)
        end
        self:Update(data, offset)
    end

    -- Get current scroll offset
    function frame:GetScrollOffset()
        if self.scrollFrame then
            return FauxScrollFrame_GetOffset(self.scrollFrame)
        end
        return 0
    end

    -- Update size dynamically (for window resize handling)
    -- If width/height are nil, use the frame's actual dimensions (from anchors)
    function frame:UpdateSize(newWidth, newHeight)
        -- If using anchor-based sizing, get dimensions from frame itself
        if not newWidth or not newHeight then
            newWidth = self:GetWidth()
            newHeight = self:GetHeight()
        end

        -- Skip update if dimensions are too small (frame not yet visible/laid out)
        if newWidth < 50 or newHeight < 50 then
            return
        end

        -- Only call SetSize if not using opposite-corner anchors
        -- (When TOPLEFT+BOTTOMRIGHT anchors are set, size is determined by anchors)
        -- Check if we have anchor-based sizing by seeing if we have a BOTTOMRIGHT point
        local _, relativeTo = self:GetPoint(2)
        if not relativeTo then
            -- No second anchor point, use explicit size
            self:SetSize(newWidth, newHeight)
        end

        -- Calculate new number of rows
        local newNumRows = math.floor((newHeight - 10) / TB.Config.rowHeight)
        if newNumRows < 1 then newNumRows = 1 end
        if newNumRows > 50 then newNumRows = 50 end  -- Sanity limit

        -- Update content area
        if self.content then
            self.content:SetPoint("TOPLEFT", 5, -5)
            self.content:SetPoint("BOTTOMRIGHT", -22, 5)
        end

        -- Create additional rows if needed
        local rowWidth = newWidth - 35
        for i = #self.rows + 1, newNumRows do
            local row = CreateFrame("Button", self:GetName().."Row"..i, self.content)
            row:SetSize(rowWidth, TB.Config.rowHeight)
            row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -((i - 1) * TB.Config.rowHeight))
            row:SetFrameLevel(self.content:GetFrameLevel() + 1)

            local rowBg = row:CreateTexture(nil, "BACKGROUND")
            rowBg:SetAllPoints()
            rowBg:SetTexture(0, 0, 0, 0)
            row.bg = rowBg

            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

            local expandBtn = CreateFrame("Button", nil, row)
            expandBtn:SetSize(14, 14)
            expandBtn:SetPoint("LEFT", 2, 0)
            expandBtn:SetNormalTexture(TB.Icons.collapsed)
            expandBtn:Hide()
            row.expandBtn = expandBtn

            local icon = row:CreateTexture(nil, "ARTWORK")
            icon:SetSize(TB.Config.iconSize, TB.Config.iconSize)
            icon:SetPoint("LEFT", expandBtn, "RIGHT", 2, 0)
            row.icon = icon

            local roleIcon = row:CreateTexture(nil, "ARTWORK")
            roleIcon:SetSize(TB.Config.iconSize, TB.Config.iconSize)
            roleIcon:SetPoint("LEFT", icon, "RIGHT", 2, 0)
            roleIcon:Hide()
            row.roleIcon = roleIcon

            local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", row, "LEFT", 56, 5)
            text:SetPoint("RIGHT", row, "RIGHT", -5, 5)
            text:SetJustifyH("LEFT")
            row.text = text

            local compText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            compText:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -1)
            compText:SetPoint("RIGHT", row, "RIGHT", -40, 0)  -- Leave room for timer
            compText:SetJustifyH("LEFT")
            compText:SetTextColor(0.7, 0.7, 0.7)
            compText:Hide()
            row.compText = compText

            -- Timer text (right side, shows seconds since detected)
            local timerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            timerText:SetPoint("RIGHT", row, "RIGHT", -5, 0)
            timerText:SetWidth(35)
            timerText:SetJustifyH("RIGHT")
            timerText:SetTextColor(0.5, 0.5, 0.5)
            timerText:Hide()
            row.timerText = timerText

            row:Hide()
            self.rows[i] = row
        end

        -- Update existing row widths
        for i = 1, #self.rows do
            self.rows[i]:SetSize(rowWidth, TB.Config.rowHeight)
            self.rows[i]:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -((i - 1) * TB.Config.rowHeight))
        end

        self.numRows = newNumRows

        -- Refresh display with current data
        if self.currentTreeData then
            local offset = 0
            if self.scrollFrame then
                offset = FauxScrollFrame_GetOffset(self.scrollFrame)
            end
            self:Update(self.currentTreeData, offset)
        end
    end

    -- Timer refresh mechanism - update timer displays every 5 seconds
    frame.timerElapsed = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.timerElapsed = self.timerElapsed + elapsed
        if self.timerElapsed >= 5 then
            self.timerElapsed = 0
            -- Only update timer text, not full refresh (performance)
            if self.rows and self.currentTreeData then
                local offset = 0
                if self.scrollFrame then
                    offset = FauxScrollFrame_GetOffset(self.scrollFrame)
                end
                -- Update timer displays for visible rows
                for i, row in ipairs(self.rows) do
                    if row:IsShown() and row.timerText and row.nodeData then
                        local node = row.nodeData
                        if node and node.data and node.data.time then
                            local elapsed = time() - node.data.time
                            local timerStr
                            if elapsed < 60 then
                                timerStr = elapsed .. "s"
                            elseif elapsed < 3600 then
                                timerStr = math.floor(elapsed / 60) .. "m"
                            else
                                timerStr = math.floor(elapsed / 3600) .. "h"
                            end
                            row.timerText:SetText(timerStr)
                            -- Color based on age
                            if elapsed < 120 then
                                row.timerText:SetTextColor(0.4, 0.8, 0.4)
                            elseif elapsed < 300 then
                                row.timerText:SetTextColor(0.8, 0.8, 0.4)
                            else
                                row.timerText:SetTextColor(0.8, 0.4, 0.4)
                            end
                        end
                    end
                end
            end
        end
    end)

    return frame
end

-- Get total counts for display
function TB.GetTotalCounts()
    local lfmCount = 0
    local lfgCount = 0

    if AIP.GroupTracker then
        lfmCount = AIP.GroupTracker.GetGroupCount()
    end

    if AIP.LFMBrowser then
        lfgCount = AIP.LFMBrowser.GetPlayerCount()
    end

    return lfmCount, lfgCount
end
