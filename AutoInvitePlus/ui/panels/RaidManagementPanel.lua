-- AutoInvite Plus - Raid Management Panel
-- Raid warnings, loot rules, buff checker, MS/OS tracking

local AIP = AutoInvitePlus
AIP.Panels = AIP.Panels or {}
AIP.Panels.RaidMgmt = {}
local RM = AIP.Panels.RaidMgmt

-- Panel state
RM.Frame = nil
RM.SelectedTemplate = nil
RM.BuffCheckData = {}  -- Stores buff check results
RM.MSOSData = {}       -- Stores MS/OS data for raid members

-- ============================================================================
-- DEFAULT RAID WARNING TEMPLATES
-- ============================================================================
RM.DefaultTemplates = {
    -- Pull & Combat
    {name = "Pull Timer 10s", message = "Pulling in 10 seconds! Get ready!"},
    {name = "Pull Timer 5s", message = "Pulling in 5! 5... 4... 3... 2... 1..."},
    {name = "Bloodlust/Heroism", message = "BL/Hero on pull! Save CDs!"},
    {name = "BL at 30%", message = "Bloodlust/Heroism at 30%! Save it!"},
    {name = "Use CDs NOW", message = "POP ALL COOLDOWNS NOW!"},
    {name = "Hold DPS", message = "STOP DPS! Wait for tank threat!"},

    -- Positioning
    {name = "Spread Out", message = "SPREAD OUT! Stay 10 yards apart!"},
    {name = "Stack Up", message = "STACK ON TANK! Group up tight!"},
    {name = "Stack on Star", message = "STACK ON {star}! Everyone to star marker!"},
    {name = "Move Out", message = "MOVE OUT OF BAD! Check your feet!"},
    {name = "Run Away", message = "RUN AWAY FROM BOSS! Get out!"},
    {name = "Range Spread", message = "RANGED: Spread out! Melee: Stay in!"},
    {name = "Behind Boss", message = "GET BEHIND THE BOSS NOW!"},

    -- Target Switches
    {name = "Switch to Adds", message = "SWITCH TO ADDS NOW! Kill adds first!"},
    {name = "Focus Skull", message = "FOCUS {skull}! Kill skull target!"},
    {name = "Kill Order", message = "Kill order: {skull} > {cross} > {square}"},
    {name = "Interrupt", message = "INTERRUPT NOW! Stop the cast!"},
    {name = "Dispel", message = "DISPEL IMMEDIATELY! Remove debuffs!"},

    -- Tank/Healer Calls
    {name = "Tank Swap", message = "TANK SWAP NOW! Taunt!"},
    {name = "Tank Cooldown", message = "TANK USE COOLDOWN! Big damage incoming!"},
    {name = "Healers Focus Tank", message = "Healers: Focus on tank! Heavy damage!"},
    {name = "Raid Damage", message = "RAID DAMAGE INCOMING! Healers ready!"},

    -- Loot Rules
    {name = "Loot Rules MS>OS", message = "Loot: MS > OS, +1 rule, reserved items announced"},
    {name = "Loot Rules DKP", message = "Loot: DKP system. Whisper bids to ML."},
    {name = "Loot Rules GDKP", message = "Loot: GDKP - Gold bids only. Min bid announced per item."},
    {name = "Roll for Loot", message = "Roll for loot: MS /roll 100, OS /roll 50"},
    {name = "Reserved Items", message = "Reserved: [item link]. All else MS>OS."},

    -- Raid Management
    {name = "AFK Check", message = "AFK check - type 1 if here!"},
    {name = "Bio Break 5min", message = "5 min bio break - be back ready!"},
    {name = "Bio Break 10min", message = "10 min break - bio/snacks. Back at :XX!"},
    {name = "Summons Needed", message = "Summons! Warlocks start summoning ASAP!"},
    {name = "Buff Check", message = "Check buffs! Flask, food, class buffs!"},
    {name = "Repair Warning", message = "Repair up! Next boss is repair-heavy!"},

    -- Wipe/Reset
    {name = "Wipe It", message = "WIPE IT! Stop fighting and die!"},
    {name = "Release and Run", message = "Release and run back! No mass res."},
    {name = "Wait for Res", message = "STAY DEAD! Mass res incoming!"},
    {name = "Reset Boss", message = "Resetting boss - run out and feign/invis!"},

    -- ICC Specific
    {name = "ICC: Bone Storm", message = "BONE STORM! Spread and kite!"},
    {name = "ICC: Defile", message = "DEFILE! Get out of raid! Run to wall!"},
    {name = "ICC: Valks", message = "VALKS! DPS switch! Stun and slow!"},
    {name = "ICC: Infest", message = "INFEST! Get everyone above 90% HP!"},
    {name = "ICC: Spores", message = "SPORES! Stack for inoculation! 8 stacks!"},
    {name = "ICC: Bites", message = "BITE ORDER: [names]. Don't break chain!"},

    -- General Mechanics
    {name = "Avoid Cleave", message = "MELEE: Avoid frontal cleave! Stay behind!"},
    {name = "Decurse", message = "MAGES/DRUIDS: Decurse immediately!"},
    {name = "Remove Poison", message = "Remove poison! Paladins/Druids/Shamans!"},
    {name = "Fear Break", message = "FEAR INCOMING! Use fear break abilities!"},
}

-- Flask buff name patterns for WotLK
RM.FlaskPatterns = {
    "Flask of Stoneblood",
    "Flask of the Frost Wyrm",
    "Flask of Endless Rage",
    "Flask of Pure Mojo",
    "Lesser Flask",
    "Elixir",  -- Catch battle/guardian elixirs
}

-- Food buff patterns
RM.FoodPatterns = {
    "Well Fed",
    "Food",
    "Feast",
    "Fish Feast",
    "Great Feast",
}

-- Raid buff definitions with providers and priority
RM.RaidBuffs = {
    -- Stats buffs (Kings > Wild for most classes)
    {
        name = "Kings",
        pattern = "Blessing of Kings",
        provider = "PALADIN",
        spellName = "Blessing of Kings",
        priority = 1,  -- Higher priority = cast first
    },
    {
        name = "Wild",
        pattern = "of the Wild",
        provider = "DRUID",
        spellName = "Gift of the Wild",
        priority = 2,
    },
    {
        name = "Fortitude",
        pattern = "Fortitude",
        provider = "PRIEST",
        spellName = "Prayer of Fortitude",
        priority = 3,
    },
    {
        name = "Intellect",
        pattern = "Arcane Intellect",
        provider = "MAGE",
        spellName = "Arcane Brilliance",
        priority = 4,
    },
    {
        name = "Spirit",
        pattern = "Divine Spirit",
        provider = "PRIEST",
        spellName = "Prayer of Spirit",
        priority = 5,
    },
    {
        name = "Shadow Prot",
        pattern = "Shadow Protection",
        provider = "PRIEST",
        spellName = "Prayer of Shadow Protection",
        priority = 6,
    },
    -- AP buffs (Battle Shout/Might/Horn)
    {
        name = "Might/AP",
        pattern = "Blessing of Might",
        altPatterns = {"Battle Shout", "Horn of Winter"},
        provider = "PALADIN",
        altProviders = {"WARRIOR", "DEATHKNIGHT"},
        spellName = "Blessing of Might",
        priority = 7,
    },
}

-- Spec detection from talent tree (simplified for WotLK)
RM.SpecDetection = {
    WARRIOR = {
        [1] = "Arms",
        [2] = "Fury",
        [3] = "Protection",
    },
    PALADIN = {
        [1] = "Holy",
        [2] = "Protection",
        [3] = "Retribution",
    },
    HUNTER = {
        [1] = "Beast Mastery",
        [2] = "Marksmanship",
        [3] = "Survival",
    },
    ROGUE = {
        [1] = "Assassination",
        [2] = "Combat",
        [3] = "Subtlety",
    },
    PRIEST = {
        [1] = "Discipline",
        [2] = "Holy",
        [3] = "Shadow",
    },
    DEATHKNIGHT = {
        [1] = "Blood",
        [2] = "Frost",
        [3] = "Unholy",
    },
    SHAMAN = {
        [1] = "Elemental",
        [2] = "Enhancement",
        [3] = "Restoration",
    },
    MAGE = {
        [1] = "Arcane",
        [2] = "Fire",
        [3] = "Frost",
    },
    WARLOCK = {
        [1] = "Affliction",
        [2] = "Demonology",
        [3] = "Destruction",
    },
    DRUID = {
        [1] = "Balance",
        [2] = "Feral",
        [3] = "Restoration",
    },
}

-- ============================================================================
-- TEMPLATE MANAGEMENT
-- ============================================================================

function RM.GetTemplates()
    if not AIP.db then return RM.DefaultTemplates end
    if not AIP.db.raidWarningTemplates or #AIP.db.raidWarningTemplates == 0 then
        AIP.db.raidWarningTemplates = {}
        for _, t in ipairs(RM.DefaultTemplates) do
            table.insert(AIP.db.raidWarningTemplates, {name = t.name, message = t.message})
        end
    end
    return AIP.db.raidWarningTemplates
end

function RM.SaveTemplate(name, message)
    local templates = RM.GetTemplates()
    for _, t in ipairs(templates) do
        if t.name == name then
            t.message = message
            return
        end
    end
    table.insert(templates, {name = name, message = message})
end

function RM.DeleteTemplate(name)
    local templates = RM.GetTemplates()
    for i, t in ipairs(templates) do
        if t.name == name then
            table.remove(templates, i)
            return
        end
    end
end

-- ============================================================================
-- MS/OS DETECTION AND TRACKING
-- ============================================================================

-- Get raid members with their class info
function RM.GetRaidMembers()
    local members = {}
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    if numRaid > 0 then
        for i = 1, numRaid do
            local name, rank, subgroup, level, class, fileName = GetRaidRosterInfo(i)
            if name then
                members[name] = {
                    name = name,
                    class = fileName or class,
                    rank = rank,
                    subgroup = subgroup,
                    level = level,
                    unit = "raid" .. i,
                }
            end
        end
    elseif numParty > 0 then
        -- Add player
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        if playerName then
            members[playerName] = {
                name = playerName,
                class = playerClass,
                unit = "player",
            }
        end
        -- Add party members
        for i = 1, numParty do
            local name = UnitName("party" .. i)
            local _, class = UnitClass("party" .. i)
            if name then
                members[name] = {
                    name = name,
                    class = class,
                    unit = "party" .. i,
                }
            end
        end
    else
        -- Solo player - still add self
        local playerName = UnitName("player")
        local _, playerClass = UnitClass("player")
        if playerName then
            members[playerName] = {
                name = playerName,
                class = playerClass,
                unit = "player",
            }
        end
    end

    return members
end

-- Detect spec from active talent tree (requires player inspection)
function RM.DetectSpecFromTalents(unit)
    if not unit or not UnitExists(unit) then return nil, nil end

    -- For the player, we can directly check talents
    if UnitIsUnit(unit, "player") then
        local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1

        -- Check which tree has most points
        local maxPoints = 0
        local mainTree = 1

        for tree = 1, 3 do
            local _, _, pointsSpent = GetTalentTabInfo(tree, false, false, activeTalentGroup)
            if pointsSpent and pointsSpent > maxPoints then
                maxPoints = pointsSpent
                mainTree = tree
            end
        end

        local _, playerClass = UnitClass("player")
        local specs = RM.SpecDetection[playerClass]
        if specs then
            return specs[mainTree], nil  -- Return MS, OS detection requires more complex logic
        end
    end

    return nil, nil
end

-- Update MS/OS data for all raid members
function RM.UpdateMSOSFromRaid()
    if not AIP.db then return end
    if not AIP.db.msTracking then AIP.db.msTracking = {} end

    local members = RM.GetRaidMembers()

    for name, info in pairs(members) do
        -- Initialize entry if not exists
        if not AIP.db.msTracking[name] then
            AIP.db.msTracking[name] = {
                class = info.class,
                ms = nil,
                os = nil,
                autoDetected = false,
            }
        else
            -- Update class if we have it
            AIP.db.msTracking[name].class = info.class or AIP.db.msTracking[name].class
        end

        -- Try to detect MS from player's own talents
        if info.unit and UnitIsUnit(info.unit, "player") then
            local detectedMS = RM.DetectSpecFromTalents(info.unit)
            if detectedMS and not AIP.db.msTracking[name].ms then
                AIP.db.msTracking[name].ms = detectedMS
                AIP.db.msTracking[name].autoDetected = true
            end
        end
    end

    -- Clean up players no longer in raid
    local inRaid = {}
    for name in pairs(members) do
        inRaid[name] = true
    end

    -- Mark players not in raid (but keep their data)
    for name, data in pairs(AIP.db.msTracking) do
        data.inRaid = inRaid[name] or false
    end
end

-- Announce MS/OS specs to raid or party chat
function RM.AnnounceMSOS()
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    if numRaid == 0 and numParty == 0 then
        AIP.Print("Not in a group!")
        return
    end

    -- Refresh data first
    RM.UpdateMSOSFromRaid()

    local tracking = AIP.db and AIP.db.msTracking or {}
    local chatType = numRaid > 0 and "RAID" or "PARTY"

    -- Build list of players in raid with MS/OS info
    local playersWithMS = {}
    local playersWithoutMS = {}

    for name, info in pairs(tracking) do
        if info.inRaid then
            if info.ms then
                table.insert(playersWithMS, {
                    name = name,
                    class = info.class,
                    ms = info.ms,
                    os = info.os,
                })
            else
                table.insert(playersWithoutMS, name)
            end
        end
    end

    -- Sort by class then name
    table.sort(playersWithMS, function(a, b)
        if a.class ~= b.class then
            return (a.class or "") < (b.class or "")
        end
        return a.name < b.name
    end)
    table.sort(playersWithoutMS)

    if #playersWithMS == 0 and #playersWithoutMS == 0 then
        AIP.Print("No players tracked. Click 'Scan Raid' first.")
        return
    end

    -- Send header
    SendChatMessage("=== MS/OS Spec Assignments ===", chatType)

    -- Announce players with MS set
    for _, player in ipairs(playersWithMS) do
        local msg = player.name .. ": MS=" .. player.ms
        if player.os then
            msg = msg .. ", OS=" .. player.os
        end
        SendChatMessage(msg, chatType)
    end

    -- Announce players without MS
    if #playersWithoutMS > 0 then
        if #playersWithoutMS <= 5 then
            SendChatMessage("No MS set: " .. table.concat(playersWithoutMS, ", "), chatType)
        else
            SendChatMessage("No MS set: " .. #playersWithoutMS .. " players - whisper 'ms <spec>' to register", chatType)
        end
    end

    AIP.Print("MS/OS announced to " .. chatType:lower() .. " chat. " .. #playersWithMS .. " specs, " .. #playersWithoutMS .. " unset.")
end

-- ============================================================================
-- BUFF CHECKING SYSTEM
-- ============================================================================

-- Map of which buffs each class can provide
RM.ClassBuffs = {
    PALADIN = {
        {buffName = "Kings", spellName = "Blessing of Kings", isGreater = "Greater Blessing of Kings"},
        {buffName = "Might/AP", spellName = "Blessing of Might", isGreater = "Greater Blessing of Might"},
    },
    DRUID = {
        {buffName = "Wild", spellName = "Gift of the Wild"},
    },
    PRIEST = {
        {buffName = "Fortitude", spellName = "Prayer of Fortitude"},
        {buffName = "Spirit", spellName = "Prayer of Spirit"},
        {buffName = "Shadow Prot", spellName = "Prayer of Shadow Protection"},
    },
    MAGE = {
        {buffName = "Intellect", spellName = "Arcane Brilliance"},
    },
    WARRIOR = {
        {buffName = "Might/AP", spellName = "Battle Shout"},
    },
    DEATHKNIGHT = {
        {buffName = "Might/AP", spellName = "Horn of Winter"},
    },
}

-- First pass: scan all units to find available buff providers
function RM.ScanBuffProviders()
    RM.BuffProviders = {}  -- {buffName = {{name = "player", class = "CLASS", spellName = "spell"}, ...}}
    RM.AvailableBuffs = {} -- Set of buff names that have providers

    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    local function ScanUnit(unit)
        if not unit or not UnitExists(unit) then return end
        if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return end

        local name = UnitName(unit)
        local _, class = UnitClass(unit)

        -- Check what buffs this class can provide
        local classBuffs = RM.ClassBuffs[class]
        if classBuffs then
            for _, buffInfo in ipairs(classBuffs) do
                RM.BuffProviders[buffInfo.buffName] = RM.BuffProviders[buffInfo.buffName] or {}
                table.insert(RM.BuffProviders[buffInfo.buffName], {
                    name = name,
                    class = class,
                    spellName = buffInfo.spellName,
                    isGreater = buffInfo.isGreater,
                })
                RM.AvailableBuffs[buffInfo.buffName] = true
            end
        end
    end

    if numRaid > 0 then
        for i = 1, numRaid do
            ScanUnit("raid" .. i)
        end
    elseif numParty > 0 then
        ScanUnit("player")
        for i = 1, numParty do
            ScanUnit("party" .. i)
        end
    else
        ScanUnit("player")
    end
end

-- Check all buffs for a unit (only checks buffs that have available providers)
function RM.CheckUnitBuffs(unit)
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) then return nil end

    local name = UnitName(unit)
    local _, class = UnitClass(unit)

    local result = {
        name = name,
        class = class,
        unit = unit,
        hasFood = false,
        hasFlask = false,
        missingBuffs = {},
        hasBuffs = {},
    }

    -- Scan all buffs on unit
    for i = 1, 40 do
        local buffName = UnitBuff(unit, i)
        if not buffName then break end

        -- Check food
        for _, pattern in ipairs(RM.FoodPatterns) do
            if buffName:find(pattern) then
                result.hasFood = true
                break
            end
        end

        -- Check flask
        for _, pattern in ipairs(RM.FlaskPatterns) do
            if buffName:find(pattern) then
                result.hasFlask = true
                break
            end
        end

        -- Check raid buffs
        for _, buff in ipairs(RM.RaidBuffs) do
            if buffName:find(buff.pattern) then
                result.hasBuffs[buff.name] = true
            end
            -- Check alternate patterns
            if buff.altPatterns then
                for _, altPattern in ipairs(buff.altPatterns) do
                    if buffName:find(altPattern) then
                        result.hasBuffs[buff.name] = true
                    end
                end
            end
        end
    end

    -- Determine missing buffs - ONLY if there's a provider available
    for _, buff in ipairs(RM.RaidBuffs) do
        if not result.hasBuffs[buff.name] then
            -- Only add to missing if someone can cast this buff
            if RM.AvailableBuffs and RM.AvailableBuffs[buff.name] then
                table.insert(result.missingBuffs, buff.name)
            end
        end
    end

    return result
end

-- Check all raid members
function RM.CheckAllRaidBuffs()
    RM.BuffCheckData = {}
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    -- FIRST: Scan for available buff providers
    RM.ScanBuffProviders()

    local function CheckUnit(unit)
        local result = RM.CheckUnitBuffs(unit)
        if result then
            table.insert(RM.BuffCheckData, result)
        end
    end

    if numRaid > 0 then
        for i = 1, numRaid do
            CheckUnit("raid" .. i)
        end
    elseif numParty > 0 then
        CheckUnit("player")
        for i = 1, numParty do
            CheckUnit("party" .. i)
        end
    else
        CheckUnit("player")
    end

    -- Sort by name
    table.sort(RM.BuffCheckData, function(a, b)
        return a.name < b.name
    end)

    return RM.BuffCheckData
end

-- Generate smart buff assignments distributed among available casters
function RM.GetBuffAssignments()
    -- Track assignments per caster: {casterName = {buffs = {{buffName, spellName, targets}, ...}}}
    local casterAssignments = {}
    -- Track which buffs still need assignment
    local buffNeeds = {}  -- {buffName = {missingPlayers = {...}, providers = {...}}}

    -- Build buff needs from current data
    for _, buff in ipairs(RM.RaidBuffs) do
        local providers = RM.BuffProviders[buff.name]
        if providers and #providers > 0 then
            -- Find players missing this buff
            local missingPlayers = {}
            for _, data in ipairs(RM.BuffCheckData) do
                if not data.hasBuffs[buff.name] then
                    table.insert(missingPlayers, data.name)
                end
            end

            if #missingPlayers > 0 then
                buffNeeds[buff.name] = {
                    missingPlayers = missingPlayers,
                    providers = providers,
                    priority = buff.priority,
                }
            end
        end
    end

    -- Sort buffs by priority
    local sortedBuffs = {}
    for buffName, needs in pairs(buffNeeds) do
        table.insert(sortedBuffs, {name = buffName, needs = needs})
    end
    table.sort(sortedBuffs, function(a, b)
        return (a.needs.priority or 99) < (b.needs.priority or 99)
    end)

    -- Assign buffs to casters, distributing workload
    -- Track how many buffs each caster is assigned
    local casterWorkload = {}  -- {casterName = count}

    for _, buffData in ipairs(sortedBuffs) do
        local buffName = buffData.name
        local needs = buffData.needs
        local providers = needs.providers

        -- Find the provider with the least workload
        local bestProvider = nil
        local lowestWorkload = 999

        for _, provider in ipairs(providers) do
            local workload = casterWorkload[provider.name] or 0
            if workload < lowestWorkload then
                lowestWorkload = workload
                bestProvider = provider
            end
        end

        if bestProvider then
            -- Assign this buff to the best provider
            casterAssignments[bestProvider.name] = casterAssignments[bestProvider.name] or {
                class = bestProvider.class,
                buffs = {},
            }

            table.insert(casterAssignments[bestProvider.name].buffs, {
                buffName = buffName,
                spellName = bestProvider.spellName,
                isGreater = bestProvider.isGreater,
                targets = needs.missingPlayers,
                priority = needs.priority,
            })

            casterWorkload[bestProvider.name] = (casterWorkload[bestProvider.name] or 0) + 1
        end
    end

    return casterAssignments
end

-- Announce missing buffs with smart assignments grouped by caster
function RM.AnnounceMissingBuffsSmart()
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    if numRaid == 0 and numParty == 0 then
        AIP.Print("Not in a group!")
        return
    end

    -- Refresh buff data
    RM.CheckAllRaidBuffs()

    -- Get assignments grouped by caster
    local casterAssignments = RM.GetBuffAssignments()

    -- Check consumables
    local missingFood = {}
    local missingFlask = {}
    for _, data in ipairs(RM.BuffCheckData) do
        if not data.hasFood then
            table.insert(missingFood, data.name)
        end
        if not data.hasFlask then
            table.insert(missingFlask, data.name)
        end
    end

    -- Determine chat type
    local chatType = numRaid > 0 and "RAID" or "PARTY"

    -- Build sorted list of casters (by class for consistent ordering)
    local sortedCasters = {}
    for casterName, data in pairs(casterAssignments) do
        table.insert(sortedCasters, {name = casterName, data = data})
    end
    table.sort(sortedCasters, function(a, b)
        -- Sort by class, then by name
        if a.data.class ~= b.data.class then
            return a.data.class < b.data.class
        end
        return a.name < b.name
    end)

    local hasAnnouncements = false

    -- Announce buff assignments per caster
    for _, caster in ipairs(sortedCasters) do
        local casterName = caster.name
        local casterData = caster.data

        -- Sort buffs by priority within each caster
        table.sort(casterData.buffs, function(a, b)
            return (a.priority or 99) < (b.priority or 99)
        end)

        -- Build message for this caster
        if #casterData.buffs == 1 then
            -- Single buff assignment
            local buff = casterData.buffs[1]
            local spellToUse = buff.isGreater or buff.spellName
            local msg = casterName .. ": " .. spellToUse
            if #buff.targets <= 3 then
                msg = msg .. " (missing: " .. table.concat(buff.targets, ", ") .. ")"
            else
                msg = msg .. " (" .. #buff.targets .. " missing)"
            end
            SendChatMessage(msg, chatType)
        else
            -- Multiple buff assignments for same caster
            local spells = {}
            local totalMissing = 0
            for _, buff in ipairs(casterData.buffs) do
                local spellToUse = buff.isGreater or buff.spellName
                table.insert(spells, spellToUse)
                totalMissing = totalMissing + #buff.targets
            end
            local msg = casterName .. ": " .. table.concat(spells, ", ")
            msg = msg .. " (" .. totalMissing .. " buffs needed)"
            SendChatMessage(msg, chatType)
        end
        hasAnnouncements = true
    end

    -- Announce consumables
    if #missingFood > 0 then
        if #missingFood <= 5 then
            SendChatMessage("Missing FOOD: " .. table.concat(missingFood, ", "), chatType)
        else
            SendChatMessage("Missing FOOD: " .. #missingFood .. " players - use feast!", chatType)
        end
        hasAnnouncements = true
    end

    if #missingFlask > 0 then
        if #missingFlask <= 5 then
            SendChatMessage("Missing FLASK: " .. table.concat(missingFlask, ", "), chatType)
        else
            SendChatMessage("Missing FLASK: " .. #missingFlask .. " players!", chatType)
        end
        hasAnnouncements = true
    end

    if not hasAnnouncements then
        SendChatMessage("All buffs, food, and flasks present!", chatType)
    end

    AIP.Print("Buff announcements sent to " .. chatType:lower() .. " chat.")
end

-- ============================================================================
-- MAIN PANEL CREATION
-- ============================================================================

function RM.Create(parent)
    if RM.Frame then return RM.Frame end

    local frame = CreateFrame("Frame", "AIPRaidMgmtPanel", parent)
    frame:SetAllPoints()

    -- Main scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "AIPRaidMgmtScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetHeight(1100)
    scrollFrame:SetScrollChild(content)

    -- Dynamic width tracking
    local function GetContentWidth()
        return math.max(scrollFrame:GetWidth() - 10, 600)
    end

    -- Initialize content width
    content:SetWidth(GetContentWidth())

    -- Hook into scroll frame size changes
    scrollFrame:HookScript("OnSizeChanged", function(self, w, h)
        if content then
            content:SetWidth(math.max(w - 10, 600))
            -- Trigger layout update
            if RM.UpdateLayout then
                RM.UpdateLayout()
            end
        end
    end)

    local y = -10

    -- ========================================================================
    -- TOP ROW: Raid Warning Templates (Left) + Loot Rules (Right)
    -- ========================================================================

    -- === LEFT: RAID WARNING TEMPLATES ===
    local header1 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header1:SetPoint("TOPLEFT", 10, y)
    header1:SetText("Raid Warning Templates")
    header1:SetTextColor(1, 0.82, 0)

    -- === RIGHT: LOOT RULES (at center of panel) ===
    local header2 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header2:SetPoint("TOPLEFT", 480, y)  -- Will be repositioned by UpdateLayout
    header2:SetText("Loot Rules & Reservations")
    header2:SetTextColor(1, 0.82, 0)
    content.lootHeader = header2

    y = y - 22

    -- Template list (left side)
    local listBg = CreateFrame("Frame", nil, content)
    listBg:SetPoint("TOPLEFT", 10, y)
    listBg:SetSize(150, 130)
    content.listBg = listBg
    listBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    listBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    listBg:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local listScroll = CreateFrame("ScrollFrame", "AIPRMTemplateScroll", listBg, "FauxScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 5, -5)
    listScroll:SetPoint("BOTTOMRIGHT", -26, 5)

    content.templateRows = {}
    for i = 1, 6 do
        local row = CreateFrame("Button", nil, listBg)
        row:SetSize(120, 18)
        row:SetPoint("TOPLEFT", 5, -5 - (i-1) * 18)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("LEFT", 5, 0)
        text:SetPoint("RIGHT", -5, 0)
        text:SetJustifyH("LEFT")
        row.text = text

        row:SetScript("OnClick", function(self)
            if self.data then
                RM.SelectedTemplate = self.data
                content.nameInput:SetText(self.data.name or "")
                content.msgInput:SetText(self.data.message or "")
                RM.RefreshTemplateList(content, listScroll)
            end
        end)

        content.templateRows[i] = row
    end

    listScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function()
            RM.RefreshTemplateList(content, listScroll)
        end)
    end)
    content.listScroll = listScroll

    -- Editor (right of template list)
    local editorX = 170

    local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", editorX, y)
    nameLabel:SetText("Template Name:")
    content.nameLabel = nameLabel

    local nameInput = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    nameInput:SetSize(180, 18)
    nameInput:SetPoint("TOPLEFT", editorX, y - 16)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    content.nameInput = nameInput

    local msgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgLabel:SetPoint("TOPLEFT", editorX, y - 38)
    msgLabel:SetText("Message:")
    content.msgLabel = msgLabel

    local msgInputBg = CreateFrame("Frame", nil, content)
    msgInputBg:SetSize(180, 50)
    msgInputBg:SetPoint("TOPLEFT", editorX, y - 54)
    msgInputBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    msgInputBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    msgInputBg:SetBackdropBorderColor(0.4, 0.4, 0.4)
    content.msgInputBg = msgInputBg

    local msgInput = CreateFrame("EditBox", nil, msgInputBg)
    msgInput:SetAllPoints()
    msgInput:SetFontObject("GameFontHighlightSmall")
    msgInput:SetAutoFocus(false)
    msgInput:SetMultiLine(true)
    msgInput:SetTextInsets(5, 5, 5, 5)
    msgInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    content.msgInput = msgInput

    -- Template buttons
    local btnY = y - 110
    local sendBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    sendBtn:SetSize(65, 20)
    sendBtn:SetPoint("TOPLEFT", editorX, btnY)
    sendBtn:SetText("Send RW")
    sendBtn:SetScript("OnClick", function()
        local msg = content.msgInput:GetText()
        if msg and msg ~= "" then
            SendChatMessage(msg, "RAID_WARNING")
            AIP.Print("Raid warning sent!")
        end
    end)
    content.sendBtn = sendBtn

    local saveBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    saveBtn:SetSize(50, 20)
    saveBtn:SetPoint("LEFT", sendBtn, "RIGHT", 5, 0)
    saveBtn:SetText("Save")
    saveBtn:SetScript("OnClick", function()
        local name = content.nameInput:GetText()
        local msg = content.msgInput:GetText()
        if name and name ~= "" and msg and msg ~= "" then
            RM.SaveTemplate(name, msg)
            RM.RefreshTemplateList(content, listScroll)
            AIP.Print("Template saved: " .. name)
        end
    end)

    local deleteBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    deleteBtn:SetSize(50, 20)
    deleteBtn:SetPoint("LEFT", saveBtn, "RIGHT", 5, 0)
    deleteBtn:SetText("Delete")
    deleteBtn:SetScript("OnClick", function()
        if RM.SelectedTemplate then
            RM.DeleteTemplate(RM.SelectedTemplate.name)
            RM.SelectedTemplate = nil
            content.nameInput:SetText("")
            content.msgInput:SetText("")
            RM.RefreshTemplateList(content, listScroll)
        end
    end)

    -- === RIGHT SIDE: Reserved Items & Loot Bans ===

    -- Reserved Items
    local reservedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reservedLabel:SetPoint("TOPLEFT", 480, y)  -- Will be repositioned by UpdateLayout
    reservedLabel:SetText("Reserved Items:")
    reservedLabel:SetTextColor(1, 0.5, 0)
    content.reservedLabel = reservedLabel

    local reservedFrame = CreateFrame("Frame", nil, content)
    reservedFrame:SetSize(150, 80)
    reservedFrame:SetPoint("TOPLEFT", 480, y - 16)  -- Will be repositioned by UpdateLayout
    reservedFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    reservedFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    reservedFrame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    content.reservedFrame = reservedFrame

    local reservedScroll = CreateFrame("ScrollFrame", "AIPRMReservedScroll", reservedFrame, "UIPanelScrollFrameTemplate")
    reservedScroll:SetPoint("TOPLEFT", 6, -6)
    reservedScroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local reservedInput = CreateFrame("EditBox", nil, reservedScroll)
    reservedInput:SetMultiLine(true)
    reservedInput:SetAutoFocus(false)
    reservedInput:SetFontObject(GameFontHighlightSmall)
    reservedInput:SetWidth(120)
    reservedInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    reservedInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.reservedItems = self:GetText()
        end
    end)
    reservedScroll:SetScrollChild(reservedInput)
    content.reservedInput = reservedInput

    local announceResBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    announceResBtn:SetSize(70, 18)
    announceResBtn:SetPoint("TOPLEFT", 480, y - 100)  -- Will be repositioned by UpdateLayout
    announceResBtn:SetText("Announce")
    announceResBtn:SetScript("OnClick", function()
        local items = content.reservedInput:GetText()
        if items and items ~= "" then
            local itemList = items:gsub("\n", ", "):gsub(", $", "")
            SendChatMessage("Reserved items: " .. itemList, "RAID_WARNING")
        end
    end)
    content.announceResBtn = announceResBtn

    -- Loot Bans (right of reserved items)
    local lootBanLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootBanLabel:SetPoint("TOPLEFT", 640, y)  -- Will be repositioned by UpdateLayout
    lootBanLabel:SetText("Loot Bans:")
    lootBanLabel:SetTextColor(1, 0.3, 0.3)
    content.lootBanLabel = lootBanLabel

    local lootBanFrame = CreateFrame("Frame", nil, content)
    lootBanFrame:SetSize(180, 80)
    lootBanFrame:SetPoint("TOPLEFT", 640, y - 16)  -- Will be repositioned by UpdateLayout
    lootBanFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    lootBanFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    lootBanFrame:SetBackdropBorderColor(0.4, 0.4, 0.4)
    content.lootBanFrame = lootBanFrame

    -- Loot ban header
    local lbPlayerHeader = lootBanFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbPlayerHeader:SetPoint("TOPLEFT", 6, -4)
    lbPlayerHeader:SetText("Player")
    lbPlayerHeader:SetTextColor(0.7, 0.7, 0.7)

    local lbBossHeader = lootBanFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbBossHeader:SetPoint("TOPLEFT", 80, -4)
    lbBossHeader:SetText("Boss")
    lbBossHeader:SetTextColor(0.7, 0.7, 0.7)

    content.lootBanRows = {}
    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, lootBanFrame)
        row:SetSize(160, 16)
        row:SetPoint("TOPLEFT", 4, -18 - ((i - 1) * 16))

        row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.playerText:SetPoint("LEFT", 2, 0)
        row.playerText:SetWidth(70)
        row.playerText:SetJustifyH("LEFT")

        row.bossText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.bossText:SetPoint("LEFT", 75, 0)
        row.bossText:SetWidth(100)
        row.bossText:SetJustifyH("LEFT")

        row.deleteBtn = CreateFrame("Button", nil, row)
        row.deleteBtn:SetSize(12, 12)
        row.deleteBtn:SetPoint("RIGHT", -2, 0)
        row.deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        row.deleteBtn:Hide()
        row.deleteBtn:SetScript("OnClick", function()
            if AIP.db and AIP.db.lootBans and AIP.db.lootBans[row.dataIndex] then
                table.remove(AIP.db.lootBans, row.dataIndex)
                RM.RefreshLootBanDisplay(content)
            end
        end)

        row:Hide()
        content.lootBanRows[i] = row
    end

    -- Loot ban buttons
    local addLootBanBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    addLootBanBtn:SetSize(40, 18)
    addLootBanBtn:SetPoint("TOPLEFT", lootBanFrame, "BOTTOMLEFT", 0, -4)
    addLootBanBtn:SetText("Add")
    addLootBanBtn:SetScript("OnClick", function()
        RM.ShowLootBanAddPopup()
    end)
    content.addLootBanBtn = addLootBanBtn

    local clearLootBanBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearLootBanBtn:SetSize(45, 18)
    clearLootBanBtn:SetPoint("LEFT", addLootBanBtn, "RIGHT", 4, 0)
    clearLootBanBtn:SetText("Clear")
    clearLootBanBtn:SetScript("OnClick", function()
        if AIP.db then
            AIP.db.lootBans = {}
            RM.RefreshLootBanDisplay(content)
        end
    end)

    y = y - 145

    -- ========================================================================
    -- MIDDLE: RAID BUFF CHECKER (Full Width Scrollable Table)
    -- ========================================================================
    local header3 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header3:SetPoint("TOPLEFT", 10, y)
    header3:SetText("Raid Buff Checker")
    header3:SetTextColor(1, 0.82, 0)

    -- Buttons
    local checkAllBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    checkAllBtn:SetSize(80, 20)
    checkAllBtn:SetPoint("LEFT", header3, "RIGHT", 20, 0)
    checkAllBtn:SetText("Check All")
    checkAllBtn:SetScript("OnClick", function()
        local data = RM.CheckAllRaidBuffs()
        RM.RefreshBuffTable(RM.Content)
        -- Count available buff types
        local buffTypeCount = 0
        if RM.AvailableBuffs then
            for _ in pairs(RM.AvailableBuffs) do
                buffTypeCount = buffTypeCount + 1
            end
        end
        AIP.Print("Buff check: " .. #data .. " players, " .. buffTypeCount .. " buff types available.")
    end)

    local announceBuffBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    announceBuffBtn:SetSize(120, 20)
    announceBuffBtn:SetPoint("LEFT", checkAllBtn, "RIGHT", 10, 0)
    announceBuffBtn:SetText("Announce Missing")
    announceBuffBtn:SetScript("OnClick", function()
        RM.AnnounceMissingBuffsSmart()
    end)

    local readyCheckBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    readyCheckBtn:SetSize(90, 20)
    readyCheckBtn:SetPoint("LEFT", announceBuffBtn, "RIGHT", 10, 0)
    readyCheckBtn:SetText("Ready Check")
    readyCheckBtn:SetScript("OnClick", function()
        DoReadyCheck()
    end)

    y = y - 25

    -- Buff table frame - uses anchors for dynamic width
    local buffTableBg = CreateFrame("Frame", nil, content)
    buffTableBg:SetPoint("TOPLEFT", 10, y)
    buffTableBg:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    buffTableBg:SetHeight(200)
    buffTableBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    buffTableBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    buffTableBg:SetBackdropBorderColor(0.4, 0.4, 0.4)
    content.buffTableBg = buffTableBg

    -- Buff table headers - proportional columns
    local buffColWidths = {100, 70, 45, 45}  -- Player, Class, Food, Flask (Missing Buffs fills rest)
    local buffHeaders = {"Player", "Class", "Food", "Flask", "Missing Buffs"}
    local headerX = 8
    for i, header in ipairs(buffHeaders) do
        local headerText = buffTableBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("TOPLEFT", headerX, -6)
        if i < 5 then
            headerText:SetWidth(buffColWidths[i])
            headerX = headerX + buffColWidths[i]
        else
            -- Last column stretches to fill remaining space
            headerText:SetPoint("RIGHT", buffTableBg, "RIGHT", -30, 0)
        end
        headerText:SetText(header)
        headerText:SetTextColor(1, 0.82, 0)
        headerText:SetJustifyH("LEFT")
    end
    content.buffColWidths = buffColWidths

    -- Buff table scroll
    local buffTableScroll = CreateFrame("ScrollFrame", "AIPRMBuffTableScroll", buffTableBg, "FauxScrollFrameTemplate")
    buffTableScroll:SetPoint("TOPLEFT", 5, -22)
    buffTableScroll:SetPoint("BOTTOMRIGHT", -26, 5)
    content.buffTableScroll = buffTableScroll

    -- Buff table rows - dynamic width via anchors
    content.buffRows = {}
    local rowHeight = 18
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, buffTableBg)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 5, -22 - ((i - 1) * rowHeight))
        row:SetPoint("RIGHT", buffTableBg, "RIGHT", -30, 0)

        -- Alternating background
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetTexture(1, 1, 1, 0.03)
        else
            rowBg:SetTexture(0, 0, 0, 0)
        end
        row.bg = rowBg

        -- Player name (proportional width)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 3, 0)
        row.nameText:SetWidth(100)
        row.nameText:SetJustifyH("LEFT")

        -- Class
        row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.classText:SetPoint("LEFT", 103, 0)
        row.classText:SetWidth(70)
        row.classText:SetJustifyH("LEFT")

        -- Food status
        row.foodText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.foodText:SetPoint("LEFT", 173, 0)
        row.foodText:SetWidth(45)
        row.foodText:SetJustifyH("CENTER")

        -- Flask status
        row.flaskText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.flaskText:SetPoint("LEFT", 218, 0)
        row.flaskText:SetWidth(45)
        row.flaskText:SetJustifyH("CENTER")

        -- Missing buffs (stretches to fill remaining space)
        row.missingText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.missingText:SetPoint("LEFT", 263, 0)
        row.missingText:SetPoint("RIGHT", -5, 0)
        row.missingText:SetJustifyH("LEFT")

        row:Hide()
        content.buffRows[i] = row
    end

    buffTableScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function()
            RM.RefreshBuffTable(content)
        end)
    end)

    -- Empty state text
    local buffEmptyText = buffTableBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    buffEmptyText:SetPoint("CENTER")
    buffEmptyText:SetText("|cFF888888Click 'Check All' to scan raid buffs...|r")
    content.buffEmptyText = buffEmptyText

    y = y - 210

    -- ========================================================================
    -- BOTTOM: MS/OS TRACKING (Full Width Scrollable Table)
    -- ========================================================================
    local header4 = content:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header4:SetPoint("TOPLEFT", 10, y)
    header4:SetText("MS/OS Tracking")
    header4:SetTextColor(1, 0.82, 0)

    -- MS/OS buttons
    local refreshMSBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    refreshMSBtn:SetSize(100, 20)
    refreshMSBtn:SetPoint("LEFT", header4, "RIGHT", 20, 0)
    refreshMSBtn:SetText("Scan Raid")
    refreshMSBtn:SetScript("OnClick", function()
        RM.UpdateMSOSFromRaid()
        RM.RefreshMSTable(RM.Content)
        -- Count players in tracking
        local count = 0
        if AIP.db and AIP.db.msTracking then
            for _ in pairs(AIP.db.msTracking) do count = count + 1 end
        end
        AIP.Print("MS/OS scan complete: " .. count .. " players tracked.")
    end)

    local clearMSBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearMSBtn:SetSize(70, 20)
    clearMSBtn:SetPoint("LEFT", refreshMSBtn, "RIGHT", 10, 0)
    clearMSBtn:SetText("Clear All")
    clearMSBtn:SetScript("OnClick", function()
        if AIP.db then
            AIP.db.msTracking = {}
            RM.RefreshMSTable(RM.Content)
            AIP.Print("MS/OS tracking data cleared.")
        end
    end)

    local announceMSBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    announceMSBtn:SetSize(80, 20)
    announceMSBtn:SetPoint("LEFT", clearMSBtn, "RIGHT", 10, 0)
    announceMSBtn:SetText("Announce")
    announceMSBtn:SetScript("OnClick", function()
        RM.AnnounceMSOS()
    end)

    local msInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msInfo:SetPoint("LEFT", announceMSBtn, "RIGHT", 15, 0)
    msInfo:SetText("|cFF888888Players can whisper 'ms <spec>' or 'os <spec>' to register|r")

    y = y - 25

    -- MS/OS table frame - uses anchors for dynamic width
    local msTableBg = CreateFrame("Frame", nil, content)
    msTableBg:SetPoint("TOPLEFT", 10, y)
    msTableBg:SetPoint("RIGHT", content, "RIGHT", -10, 0)
    msTableBg:SetHeight(200)
    msTableBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    msTableBg:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    msTableBg:SetBackdropBorderColor(0.4, 0.4, 0.4)
    content.msTableBg = msTableBg

    -- MS/OS table headers - proportional columns
    local msColWidths = {120, 80, 120, 120}  -- Player, Class, Main Spec, Off Spec (Status fills rest)
    local msHeaders = {"Player", "Class", "Main Spec", "Off Spec", "Status"}
    headerX = 8
    for i, header in ipairs(msHeaders) do
        local headerText = msTableBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        headerText:SetPoint("TOPLEFT", headerX, -6)
        if i < 5 then
            headerText:SetWidth(msColWidths[i])
            headerX = headerX + msColWidths[i]
        else
            -- Last column stretches to fill remaining space
            headerText:SetPoint("RIGHT", msTableBg, "RIGHT", -30, 0)
        end
        headerText:SetText(header)
        headerText:SetTextColor(1, 0.82, 0)
        headerText:SetJustifyH("LEFT")
    end
    content.msColWidths = msColWidths

    -- MS/OS table scroll
    local msTableScroll = CreateFrame("ScrollFrame", "AIPRMMSTableScroll", msTableBg, "FauxScrollFrameTemplate")
    msTableScroll:SetPoint("TOPLEFT", 5, -22)
    msTableScroll:SetPoint("BOTTOMRIGHT", -26, 5)
    content.msTableScroll = msTableScroll

    -- MS/OS table rows - dynamic width via anchors
    content.msRows = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, msTableBg)
        row:SetHeight(rowHeight)
        row:SetPoint("TOPLEFT", 5, -22 - ((i - 1) * rowHeight))
        row:SetPoint("RIGHT", msTableBg, "RIGHT", -30, 0)

        -- Alternating background
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetTexture(1, 1, 1, 0.03)
        else
            rowBg:SetTexture(0, 0, 0, 0)
        end
        row.bg = rowBg

        -- Player name (proportional width)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 3, 0)
        row.nameText:SetWidth(120)
        row.nameText:SetJustifyH("LEFT")

        -- Class
        row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.classText:SetPoint("LEFT", 123, 0)
        row.classText:SetWidth(80)
        row.classText:SetJustifyH("LEFT")

        -- Main Spec
        row.msText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.msText:SetPoint("LEFT", 203, 0)
        row.msText:SetWidth(120)
        row.msText:SetJustifyH("LEFT")

        -- Off Spec
        row.osText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.osText:SetPoint("LEFT", 323, 0)
        row.osText:SetWidth(120)
        row.osText:SetJustifyH("LEFT")

        -- Status (stretches to fill remaining space)
        row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.statusText:SetPoint("LEFT", 443, 0)
        row.statusText:SetPoint("RIGHT", -5, 0)
        row.statusText:SetJustifyH("LEFT")

        row:Hide()
        content.msRows[i] = row
    end

    msTableScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, rowHeight, function()
            RM.RefreshMSTable(content)
        end)
    end)

    -- Empty state text
    local msEmptyText = msTableBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msEmptyText:SetPoint("CENTER")
    msEmptyText:SetText("|cFF888888Click 'Scan Raid' to detect specs...|r")
    content.msEmptyText = msEmptyText

    RM.Frame = frame
    RM.Content = content

    -- Hook OnShow to update layout when panel becomes visible
    frame:HookScript("OnShow", function()
        -- Delayed call to ensure dimensions are available
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(0.05, function()
                RM.UpdateLayout()
            end)
        else
            RM.UpdateLayout()
        end
    end)

    return frame
end

-- ============================================================================
-- REFRESH FUNCTIONS
-- ============================================================================

function RM.RefreshTemplateList(content, scrollFrame)
    content = content or RM.Content
    if not content or not content.templateRows then return end
    scrollFrame = scrollFrame or content.listScroll

    local templates = RM.GetTemplates()
    local numRows = #content.templateRows
    local offset = scrollFrame and FauxScrollFrame_GetOffset(scrollFrame) or 0

    if scrollFrame then
        FauxScrollFrame_Update(scrollFrame, #templates, numRows, 18)
    end

    for i = 1, numRows do
        local row = content.templateRows[i]
        if row then
            local index = offset + i

            if index <= #templates then
                local t = templates[index]
                row.data = t
                local color = (RM.SelectedTemplate and RM.SelectedTemplate.name == t.name) and "|cFF00FF00" or ""
                row.text:SetText(color .. (t.name or ""))
                row:Show()
            else
                row.data = nil
                row:Hide()
            end
        end
    end
end

function RM.RefreshBuffTable(content)
    content = content or RM.Content
    if not content or not content.buffRows then return end

    local data = RM.BuffCheckData or {}
    local offset = content.buffTableScroll and FauxScrollFrame_GetOffset(content.buffTableScroll) or 0

    if content.buffTableScroll then
        FauxScrollFrame_Update(content.buffTableScroll, #data, 10, 18)
    end

    -- Show/hide empty state
    if content.buffEmptyText then
        if #data == 0 then
            content.buffEmptyText:Show()
        else
            content.buffEmptyText:Hide()
        end
    end

    -- Class colors
    local classColors = {
        WARRIOR = {0.78, 0.61, 0.43},
        PALADIN = {0.96, 0.55, 0.73},
        HUNTER = {0.67, 0.83, 0.45},
        ROGUE = {1, 0.96, 0.41},
        PRIEST = {1, 1, 1},
        DEATHKNIGHT = {0.77, 0.12, 0.23},
        SHAMAN = {0, 0.44, 0.87},
        MAGE = {0.41, 0.8, 0.94},
        WARLOCK = {0.58, 0.51, 0.79},
        DRUID = {1, 0.49, 0.04},
    }

    for i = 1, 10 do
        local row = content.buffRows[i]
        local index = offset + i

        if index <= #data then
            local entry = data[index]

            -- Player name with class color
            local color = classColors[entry.class] or {1, 1, 1}
            row.nameText:SetText(entry.name)
            row.nameText:SetTextColor(color[1], color[2], color[3])

            -- Class name
            local className = entry.class and (entry.class:sub(1, 1) .. entry.class:sub(2):lower()) or "?"
            row.classText:SetText(className)
            row.classText:SetTextColor(color[1], color[2], color[3])

            -- Food status
            if entry.hasFood then
                row.foodText:SetText("|cFF00FF00OK|r")
            else
                row.foodText:SetText("|cFFFF4444X|r")
            end

            -- Flask status
            if entry.hasFlask then
                row.flaskText:SetText("|cFF00FF00OK|r")
            else
                row.flaskText:SetText("|cFFFF4444X|r")
            end

            -- Missing buffs (only shows buffs that have available casters)
            if #entry.missingBuffs > 0 then
                row.missingText:SetText("|cFFFF8800" .. table.concat(entry.missingBuffs, ", ") .. "|r")
            else
                -- Count how many buff types are available
                local availableCount = 0
                if RM.AvailableBuffs then
                    for _ in pairs(RM.AvailableBuffs) do
                        availableCount = availableCount + 1
                    end
                end
                if availableCount > 0 then
                    row.missingText:SetText("|cFF00FF00OK (" .. availableCount .. " buff types)|r")
                else
                    row.missingText:SetText("|cFF888888No buff providers|r")
                end
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

function RM.RefreshMSTable(content)
    content = content or RM.Content
    if not content or not content.msRows then return end

    -- Build sorted list from tracking data
    local data = {}
    local tracking = AIP.db and AIP.db.msTracking or {}

    for name, info in pairs(tracking) do
        table.insert(data, {
            name = name,
            class = info.class,
            ms = info.ms,
            os = info.os,
            inRaid = info.inRaid,
            autoDetected = info.autoDetected,
        })
    end

    -- Sort: in-raid first, then alphabetically
    table.sort(data, function(a, b)
        if a.inRaid ~= b.inRaid then
            return a.inRaid and not b.inRaid
        end
        return a.name < b.name
    end)

    local offset = content.msTableScroll and FauxScrollFrame_GetOffset(content.msTableScroll) or 0

    if content.msTableScroll then
        FauxScrollFrame_Update(content.msTableScroll, #data, 10, 18)
    end

    -- Show/hide empty state
    if content.msEmptyText then
        if #data == 0 then
            content.msEmptyText:Show()
        else
            content.msEmptyText:Hide()
        end
    end

    -- Class colors
    local classColors = {
        WARRIOR = {0.78, 0.61, 0.43},
        PALADIN = {0.96, 0.55, 0.73},
        HUNTER = {0.67, 0.83, 0.45},
        ROGUE = {1, 0.96, 0.41},
        PRIEST = {1, 1, 1},
        DEATHKNIGHT = {0.77, 0.12, 0.23},
        SHAMAN = {0, 0.44, 0.87},
        MAGE = {0.41, 0.8, 0.94},
        WARLOCK = {0.58, 0.51, 0.79},
        DRUID = {1, 0.49, 0.04},
    }

    for i = 1, 10 do
        local row = content.msRows[i]
        local index = offset + i

        if index <= #data then
            local entry = data[index]

            -- Player name with class color
            local color = classColors[entry.class] or {0.7, 0.7, 0.7}
            local namePrefix = entry.inRaid and "" or "|cFF666666"
            local nameSuffix = entry.inRaid and "" or "|r"
            row.nameText:SetText(namePrefix .. entry.name .. nameSuffix)
            if entry.inRaid then
                row.nameText:SetTextColor(color[1], color[2], color[3])
            else
                row.nameText:SetTextColor(0.4, 0.4, 0.4)
            end

            -- Class name
            local className = entry.class and (entry.class:sub(1, 1) .. entry.class:sub(2):lower()) or "?"
            row.classText:SetText(className)
            if entry.inRaid then
                row.classText:SetTextColor(color[1], color[2], color[3])
            else
                row.classText:SetTextColor(0.4, 0.4, 0.4)
            end

            -- Main Spec
            if entry.ms then
                local msColor = entry.autoDetected and "|cFF88FFFF" or "|cFF00FF00"
                row.msText:SetText(msColor .. entry.ms .. "|r")
            else
                row.msText:SetText("|cFF666666Not set|r")
            end

            -- Off Spec
            if entry.os then
                row.osText:SetText("|cFFFFFF00" .. entry.os .. "|r")
            else
                row.osText:SetText("|cFF666666Not set|r")
            end

            -- Status
            if entry.inRaid then
                if entry.ms then
                    row.statusText:SetText("|cFF00FF00In Raid|r")
                else
                    row.statusText:SetText("|cFFFF8800In Raid - No MS|r")
                end
            else
                row.statusText:SetText("|cFF666666Not in raid|r")
            end

            row:Show()
        else
            row:Hide()
        end
    end
end

function RM.RefreshLootBanDisplay(content)
    content = content or RM.Content
    if not content or not content.lootBanRows then return end

    local data = AIP.db and AIP.db.lootBans or {}

    for i, row in ipairs(content.lootBanRows) do
        local entry = data[i]
        if entry then
            row.playerText:SetText(entry.player or "")
            row.bossText:SetText(entry.boss or "")
            row.dataIndex = i
            row.deleteBtn:Show()
            row:Show()
        else
            row:Hide()
            row.deleteBtn:Hide()
        end
    end
end

-- ============================================================================
-- UPDATE FUNCTION
-- ============================================================================

function RM.Update()
    if not RM.Frame or not RM.Content then return end

    local content = RM.Content

    -- Update layout first to ensure proper sizing
    RM.UpdateLayout()

    RM.RefreshTemplateList(content, content.listScroll)

    if content.reservedInput and AIP.db then
        content.reservedInput:SetText(AIP.db.reservedItems or "")
    end

    RM.RefreshLootBanDisplay(content)
    RM.RefreshBuffTable(content)
    RM.RefreshMSTable(content)
end

-- ============================================================================
-- DYNAMIC LAYOUT UPDATE
-- ============================================================================

function RM.UpdateLayout()
    if not RM.Content then return end
    local content = RM.Content

    -- Get current content width
    local contentWidth = content:GetWidth()
    if contentWidth < 100 then return end  -- Not yet laid out

    local halfWidth = contentWidth / 2
    local leftSectionWidth = halfWidth - 20
    local rightSectionStart = halfWidth + 10

    -- === LEFT SIDE: Template List + Editor ===
    local templateListWidth = math.min(150, leftSectionWidth * 0.4)
    local editorWidth = leftSectionWidth - templateListWidth - 10

    -- Update template list
    if content.listBg then
        content.listBg:SetWidth(templateListWidth)
        if content.templateRows then
            for _, row in ipairs(content.templateRows) do
                row:SetWidth(templateListWidth - 30)
            end
        end
    end

    -- Update editor elements
    local editorX = templateListWidth + 20
    if content.nameLabel then
        content.nameLabel:ClearAllPoints()
        content.nameLabel:SetPoint("TOPLEFT", editorX, -32)
    end
    if content.nameInput then
        content.nameInput:ClearAllPoints()
        content.nameInput:SetPoint("TOPLEFT", editorX, -48)
        content.nameInput:SetWidth(editorWidth)
    end
    if content.msgLabel then
        content.msgLabel:ClearAllPoints()
        content.msgLabel:SetPoint("TOPLEFT", editorX, -70)
    end
    if content.msgInputBg then
        content.msgInputBg:ClearAllPoints()
        content.msgInputBg:SetPoint("TOPLEFT", editorX, -86)
        content.msgInputBg:SetSize(editorWidth, 50)
    end
    if content.sendBtn then
        content.sendBtn:ClearAllPoints()
        content.sendBtn:SetPoint("TOPLEFT", editorX, -142)
    end

    -- === RIGHT SIDE: Reserved Items + Loot Bans ===
    local rightQuarterWidth = (contentWidth - rightSectionStart - 10) / 2

    -- Update loot header position
    if content.lootHeader then
        content.lootHeader:ClearAllPoints()
        content.lootHeader:SetPoint("TOPLEFT", rightSectionStart, -10)
    end

    -- Reserved items
    if content.reservedLabel then
        content.reservedLabel:ClearAllPoints()
        content.reservedLabel:SetPoint("TOPLEFT", rightSectionStart, -32)
    end
    if content.reservedFrame then
        content.reservedFrame:ClearAllPoints()
        content.reservedFrame:SetPoint("TOPLEFT", rightSectionStart, -48)
        content.reservedFrame:SetSize(rightQuarterWidth - 5, 80)
        if content.reservedInput then
            content.reservedInput:SetWidth(rightQuarterWidth - 40)
        end
    end
    if content.announceResBtn then
        content.announceResBtn:ClearAllPoints()
        content.announceResBtn:SetPoint("TOPLEFT", rightSectionStart, -132)
    end

    -- Loot bans
    local lootBanX = rightSectionStart + rightQuarterWidth + 5
    if content.lootBanLabel then
        content.lootBanLabel:ClearAllPoints()
        content.lootBanLabel:SetPoint("TOPLEFT", lootBanX, -32)
    end
    if content.lootBanFrame then
        content.lootBanFrame:ClearAllPoints()
        content.lootBanFrame:SetPoint("TOPLEFT", lootBanX, -48)
        content.lootBanFrame:SetSize(rightQuarterWidth - 5, 80)
    end
    if content.addLootBanBtn then
        content.addLootBanBtn:ClearAllPoints()
        content.addLootBanBtn:SetPoint("TOPLEFT", lootBanX, -132)
    end

    -- Refresh table displays
    RM.RefreshBuffTable(content)
    RM.RefreshMSTable(content)
end

-- ============================================================================
-- MS/OS WHISPER DETECTION
-- ============================================================================

local msEventFrame = CreateFrame("Frame")
msEventFrame:RegisterEvent("CHAT_MSG_WHISPER")
msEventFrame:SetScript("OnEvent", function(self, event, message, author)
    if not AIP.db then return end
    if not AIP.db.msTracking then AIP.db.msTracking = {} end

    local msgLower = message:lower()

    local msSpec = msgLower:match("^ms%s+(.+)$")
    if msSpec then
        AIP.db.msTracking[author] = AIP.db.msTracking[author] or {}
        AIP.db.msTracking[author].ms = msSpec:sub(1,1):upper() .. msSpec:sub(2)
        AIP.db.msTracking[author].inRaid = true
        AIP.Print(author .. " set MS to: " .. AIP.db.msTracking[author].ms)
        if RM.Content then RM.RefreshMSTable(RM.Content) end
        return
    end

    local osSpec = msgLower:match("^os%s+(.+)$")
    if osSpec then
        AIP.db.msTracking[author] = AIP.db.msTracking[author] or {}
        AIP.db.msTracking[author].os = osSpec:sub(1,1):upper() .. osSpec:sub(2)
        AIP.db.msTracking[author].inRaid = true
        AIP.Print(author .. " set OS to: " .. AIP.db.msTracking[author].os)
        if RM.Content then RM.RefreshMSTable(RM.Content) end
        return
    end
end)

-- ============================================================================
-- LOOT BAN POPUP
-- ============================================================================

-- List of raid bosses for dropdown
RM.BossList = {
    -- Special options
    "(None)",
    "<Custom Boss>",
    -- ICC
    "Lord Marrowgar",
    "Lady Deathwhisper",
    "Gunship Battle",
    "Deathbringer Saurfang",
    "Festergut",
    "Rotface",
    "Professor Putricide",
    "Blood Prince Council",
    "Blood-Queen Lana'thel",
    "Valithria Dreamwalker",
    "Sindragosa",
    "The Lich King",
    -- RS
    "Halion",
    -- TOC
    "Northrend Beasts",
    "Lord Jaraxxus",
    "Faction Champions",
    "Twin Val'kyr",
    "Anub'arak",
    -- Ulduar
    "Flame Leviathan",
    "Ignis the Furnace Master",
    "Razorscale",
    "XT-002 Deconstructor",
    "Assembly of Iron",
    "Kologarn",
    "Auriaya",
    "Hodir",
    "Thorim",
    "Freya",
    "Mimiron",
    "General Vezax",
    "Yogg-Saron",
    "Algalon the Observer",
    -- Naxx
    "Anub'Rekhan",
    "Grand Widow Faerlina",
    "Maexxna",
    "Noth the Plaguebringer",
    "Heigan the Unclean",
    "Loatheb",
    "Instructor Razuvious",
    "Gothik the Harvester",
    "Four Horsemen",
    "Patchwerk",
    "Grobbulus",
    "Gluth",
    "Thaddius",
    "Sapphiron",
    "Kel'Thuzad",
    -- VoA
    "Archavon",
    "Emalon",
    "Koralon",
    "Toravon",
    -- Onyxia
    "Onyxia",
    -- OS
    "Sartharion",
    -- EoE
    "Malygos",
}

-- Helper to create a dropdown menu
local function CreateDropdownMenu(parent, width, items, onSelect, placeholder)
    local dropdown = CreateFrame("Frame", nil, parent)
    dropdown:SetSize(width, 24)
    dropdown:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    dropdown:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    dropdown:SetBackdropBorderColor(0.5, 0.5, 0.5)

    local text = dropdown:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", 8, 0)
    text:SetPoint("RIGHT", -20, 0)
    text:SetJustifyH("LEFT")
    text:SetText(placeholder or "Select...")
    text:SetTextColor(0.7, 0.7, 0.7)
    dropdown.text = text

    local arrow = dropdown:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -5, 0)
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")

    dropdown.selectedValue = nil
    dropdown.items = items or {}
    dropdown.onSelect = onSelect

    -- Menu frame
    local menu = CreateFrame("Frame", nil, dropdown)
    menu:SetPoint("TOPLEFT", dropdown, "BOTTOMLEFT", 0, -2)
    menu:SetWidth(width)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    menu:SetBackdropColor(0.1, 0.1, 0.1, 0.95)
    menu:SetBackdropBorderColor(0.4, 0.4, 0.4)
    menu:Hide()
    dropdown.menu = menu

    -- Function to populate menu
    function dropdown:SetItems(newItems)
        self.items = newItems or {}
        -- Clear existing rows
        if self.menuRows then
            for _, row in ipairs(self.menuRows) do
                row:Hide()
            end
        end
        self.menuRows = {}

        local maxVisible = math.min(#self.items, 12)
        self.menu:SetHeight(maxVisible * 16 + 10)

        for i, item in ipairs(self.items) do
            if i > 12 then break end  -- Limit visible items
            local row = CreateFrame("Button", nil, self.menu)
            row:SetSize(width - 10, 16)
            row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 16)

            local rowText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rowText:SetPoint("LEFT", 3, 0)
            rowText:SetPoint("RIGHT", -3, 0)
            rowText:SetJustifyH("LEFT")

            -- Style based on item type
            if item == "<Custom Name>" or item == "<Custom Boss>" then
                rowText:SetText("|cFFFFFF00" .. item .. "|r")
            elseif item == "(None)" then
                rowText:SetText("|cFF888888" .. item .. "|r")
            elseif item:match("^%-%-") then
                rowText:SetText("|cFF00FFFF" .. item .. "|r")
            else
                rowText:SetText(item)
            end

            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

            row:SetScript("OnClick", function()
                if self.onSelect then
                    self.onSelect(item)
                end
                self.selectedValue = item
                if item == "(None)" then
                    self.text:SetText("|cFF888888(None)|r")
                elseif item == "<Custom Name>" or item == "<Custom Boss>" then
                    self.text:SetText("|cFFFFFF00" .. item .. "|r")
                else
                    self.text:SetText(item)
                    self.text:SetTextColor(1, 1, 1)
                end
                self.menu:Hide()
            end)

            table.insert(self.menuRows, row)
        end
    end

    -- Toggle menu
    dropdown:EnableMouse(true)
    dropdown:SetScript("OnMouseDown", function(self)
        if self.menu:IsShown() then
            self.menu:Hide()
        else
            self.menu:Show()
        end
    end)

    -- Hide menu when clicking elsewhere
    menu:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function()
            if not dropdown:IsMouseOver() and not self:IsMouseOver() then
                self:Hide()
            end
        end)
    end)
    menu:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return dropdown
end

function RM.ShowLootBanAddPopup(prefilledPlayer)
    if not RM.LootBanAddPopup then
        local popup = CreateFrame("Frame", "AIPRMLootBanAddPopup", UIParent)
        popup:SetSize(280, 170)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")
        popup:SetFrameLevel(100)
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)
        popup:SetClampedToScreen(true)
        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = {left = 11, right = 12, top = 12, bottom = 11}
        })
        popup:SetBackdropColor(0, 0, 0, 1)

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -16)
        title:SetText("Add Loot Ban")
        title:SetTextColor(1, 0.3, 0.3)

        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local y = -45

        -- Player dropdown
        local playerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        playerLabel:SetPoint("TOPLEFT", 20, y)
        playerLabel:SetText("Player:")
        playerLabel:SetTextColor(1, 1, 1)

        local playerDropdown = CreateDropdownMenu(popup, 170, {}, function(item)
            if item == "<Custom Name>" then
                -- Show custom input
                popup.customPlayerInput:Show()
                popup.customPlayerInput:SetFocus()
            else
                popup.customPlayerInput:Hide()
                popup.customPlayerInput:SetText("")
            end
        end, "Select Player...")
        playerDropdown:SetPoint("TOPLEFT", 75, y + 4)
        popup.playerDropdown = playerDropdown

        -- Custom player input (hidden by default)
        local customPlayerInput = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        customPlayerInput:SetSize(170, 20)
        customPlayerInput:SetPoint("TOPLEFT", 75, y - 20)
        customPlayerInput:SetAutoFocus(false)
        customPlayerInput:Hide()
        popup.customPlayerInput = customPlayerInput

        y = y - 45

        -- Boss dropdown
        local bossLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bossLabel:SetPoint("TOPLEFT", 20, y)
        bossLabel:SetText("Boss:")
        bossLabel:SetTextColor(1, 1, 1)

        local bossDropdown = CreateDropdownMenu(popup, 170, RM.BossList, function(item)
            if item == "<Custom Boss>" then
                popup.customBossInput:Show()
                popup.customBossInput:SetFocus()
            else
                popup.customBossInput:Hide()
                popup.customBossInput:SetText("")
            end
        end, "Select Boss...")
        bossDropdown:SetPoint("TOPLEFT", 75, y + 4)
        bossDropdown:SetItems(RM.BossList)
        popup.bossDropdown = bossDropdown

        -- Custom boss input (hidden by default)
        local customBossInput = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        customBossInput:SetSize(170, 20)
        customBossInput:SetPoint("TOPLEFT", 75, y - 20)
        customBossInput:SetAutoFocus(false)
        customBossInput:Hide()
        popup.customBossInput = customBossInput

        -- Buttons
        local addBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        addBtn:SetSize(80, 22)
        addBtn:SetPoint("BOTTOMLEFT", 40, 18)
        addBtn:SetText("Add")
        addBtn:SetScript("OnClick", function()
            -- Get player
            local player = nil
            local selectedPlayer = popup.playerDropdown.selectedValue
            if selectedPlayer == "<Custom Name>" then
                player = popup.customPlayerInput:GetText()
            elseif selectedPlayer and selectedPlayer ~= "" and not selectedPlayer:match("^%-%-") then
                player = selectedPlayer
            end

            if not player or strtrim(player) == "" then
                AIP.Print("Please select a player")
                return
            end
            player = strtrim(player)
            player = player:sub(1, 1):upper() .. player:sub(2):lower()

            -- Get boss
            local boss = nil
            local selectedBoss = popup.bossDropdown.selectedValue
            if selectedBoss == "<Custom Boss>" then
                boss = popup.customBossInput:GetText()
                if boss then boss = strtrim(boss) end
                if boss == "" then boss = nil end
            elseif selectedBoss and selectedBoss ~= "(None)" and selectedBoss ~= "" then
                boss = selectedBoss
            end

            local entry = {
                player = player,
                boss = boss,
            }

            if not AIP.db.lootBans then AIP.db.lootBans = {} end
            table.insert(AIP.db.lootBans, entry)
            if RM.Content then RM.RefreshLootBanDisplay(RM.Content) end

            AIP.Print("Loot ban added: " .. player .. (entry.boss and (" for " .. entry.boss) or " (all bosses)"))

            -- Reset
            popup.playerDropdown.selectedValue = nil
            popup.playerDropdown.text:SetText("Select Player...")
            popup.playerDropdown.text:SetTextColor(0.7, 0.7, 0.7)
            popup.bossDropdown.selectedValue = nil
            popup.bossDropdown.text:SetText("Select Boss...")
            popup.bossDropdown.text:SetTextColor(0.7, 0.7, 0.7)
            popup.customPlayerInput:SetText("")
            popup.customPlayerInput:Hide()
            popup.customBossInput:SetText("")
            popup.customBossInput:Hide()
            popup:Hide()
        end)

        local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 20, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:Hide()
        tinsert(UISpecialFrames, "AIPRMLootBanAddPopup")
        RM.LootBanAddPopup = popup
    end

    local popup = RM.LootBanAddPopup

    -- Build player list from group members
    local playerItems = {"<Custom Name>", "-- Group Members --"}
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    if numRaid > 0 then
        for i = 1, numRaid do
            local name = GetRaidRosterInfo(i)
            if name and name ~= UnitName("player") then
                table.insert(playerItems, name)
            end
        end
    elseif numParty > 0 then
        for i = 1, numParty do
            local name = UnitName("party" .. i)
            if name then
                table.insert(playerItems, name)
            end
        end
    end

    -- Sort player names (after the header)
    if #playerItems > 2 then
        local header1 = table.remove(playerItems, 1)
        local header2 = table.remove(playerItems, 1)
        table.sort(playerItems)
        table.insert(playerItems, 1, header2)
        table.insert(playerItems, 1, header1)
    end

    popup.playerDropdown:SetItems(playerItems)

    -- Reset state
    popup.playerDropdown.selectedValue = nil
    popup.playerDropdown.text:SetText("Select Player...")
    popup.playerDropdown.text:SetTextColor(0.7, 0.7, 0.7)
    popup.bossDropdown.selectedValue = nil
    popup.bossDropdown.text:SetText("Select Boss...")
    popup.bossDropdown.text:SetTextColor(0.7, 0.7, 0.7)
    popup.customPlayerInput:SetText("")
    popup.customPlayerInput:Hide()
    popup.customBossInput:SetText("")
    popup.customBossInput:Hide()

    -- Pre-fill if provided
    if prefilledPlayer and prefilledPlayer ~= "" then
        popup.playerDropdown.selectedValue = prefilledPlayer
        popup.playerDropdown.text:SetText(prefilledPlayer)
        popup.playerDropdown.text:SetTextColor(1, 1, 1)
    end

    popup:Show()
end

-- ============================================================================
-- LOOT BAN ROLL WARNING SYSTEM
-- ============================================================================

-- Check if a player is banned from loot (optionally for a specific boss)
function RM.IsPlayerLootBanned(playerName, bossName)
    if not AIP.db or not AIP.db.lootBans then return false end

    local normalizedPlayer = playerName:sub(1, 1):upper() .. playerName:sub(2):lower()

    for _, ban in ipairs(AIP.db.lootBans) do
        if ban.player == normalizedPlayer then
            -- If no boss specified in ban, it applies to all
            if not ban.boss then
                return true, "(all bosses)"
            end
            -- If boss specified, check if it matches
            if bossName and ban.boss:lower() == bossName:lower() then
                return true, ban.boss
            end
            -- If no bossName provided but ban has one, still flag it
            if not bossName then
                return true, ban.boss
            end
        end
    end

    return false
end

-- Track current boss for roll warnings
RM.CurrentBoss = nil

-- Roll detection event handler
local rollEventFrame = CreateFrame("Frame")
rollEventFrame:RegisterEvent("CHAT_MSG_SYSTEM")
rollEventFrame:SetScript("OnEvent", function(self, event, message)
    if not AIP.db or not AIP.db.lootBans or #AIP.db.lootBans == 0 then return end

    -- Pattern for roll messages: "PlayerName rolls X (1-100)"
    local playerName, roll = message:match("^(.+) rolls (%d+) %(1%-100%)")
    if not playerName or not roll then return end

    -- Check if player is loot banned
    local isBanned, banBoss = RM.IsPlayerLootBanned(playerName, RM.CurrentBoss)
    if isBanned then
        local rollNum = tonumber(roll)
        if rollNum and rollNum >= 50 then  -- Only warn for decent rolls
            local warnMsg = "|cFFFF0000WARNING:|r " .. playerName .. " rolled " .. roll .. " but is |cFFFF4444LOOT BANNED|r"
            if banBoss then
                warnMsg = warnMsg .. " (" .. banBoss .. ")"
            end
            -- Print warning
            AIP.Print(warnMsg)
            -- Also show raid warning style alert
            RaidNotice_AddMessage(RaidWarningFrame, warnMsg, ChatTypeInfo["RAID_WARNING"])
        end
    end
end)

-- Boss kill detection to track current boss
local bossEventFrame = CreateFrame("Frame")
bossEventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
bossEventFrame:SetScript("OnEvent", function(self, event, timestamp, subevent, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags)
    -- WotLK 3.3.5a passes combat log args directly to the handler
    if subevent == "UNIT_DIED" and dstName then
        -- Check if it's a known boss
        for _, bossName in ipairs(RM.BossList) do
            if bossName ~= "(None)" and bossName ~= "<Custom Boss>" and dstName:find(bossName) then
                RM.CurrentBoss = bossName
                if AIP.Debug then AIP.Debug("Boss killed: " .. bossName .. " - tracking for loot ban warnings") end
                break
            end
        end
    end
end)
