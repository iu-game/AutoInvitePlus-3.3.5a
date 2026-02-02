-- AutoInvite Plus - Raid Composition Module
-- Raid templates, role tracking, buff coverage for WotLK 3.3.5a

local AIP = AutoInvitePlus
AIP.Composition = {}
local Comp = AIP.Composition

-- Class colors for display
Comp.ClassColors = {
    WARRIOR = {r=0.78, g=0.61, b=0.43},
    PALADIN = {r=0.96, g=0.55, b=0.73},
    HUNTER = {r=0.67, g=0.83, b=0.45},
    ROGUE = {r=1.00, g=0.96, b=0.41},
    PRIEST = {r=1.00, g=1.00, b=1.00},
    DEATHKNIGHT = {r=0.77, g=0.12, b=0.23},
    SHAMAN = {r=0.00, g=0.44, b=0.87},
    MAGE = {r=0.41, g=0.80, b=0.94},
    WARLOCK = {r=0.58, g=0.51, b=0.79},
    DRUID = {r=1.00, g=0.49, b=0.04},
}

-- Role icons (using default WoW icons)
Comp.RoleIcons = {
    TANK = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    HEALER = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
    DPS = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES",
}

-- Specs that can fulfill each role
Comp.ClassRoles = {
    WARRIOR = {
        specs = {"Arms", "Fury", "Protection"},
        roles = {DPS = true, TANK = true},
        defaultRole = "DPS",
    },
    PALADIN = {
        specs = {"Holy", "Protection", "Retribution"},
        roles = {HEALER = true, TANK = true, DPS = true},
        defaultRole = "DPS",
    },
    HUNTER = {
        specs = {"Beast Mastery", "Marksmanship", "Survival"},
        roles = {DPS = true},
        defaultRole = "DPS",
    },
    ROGUE = {
        specs = {"Assassination", "Combat", "Subtlety"},
        roles = {DPS = true},
        defaultRole = "DPS",
    },
    PRIEST = {
        specs = {"Discipline", "Holy", "Shadow"},
        roles = {HEALER = true, DPS = true},
        defaultRole = "HEALER",
    },
    DEATHKNIGHT = {
        specs = {"Blood", "Frost", "Unholy"},
        roles = {TANK = true, DPS = true},
        defaultRole = "DPS",
    },
    SHAMAN = {
        specs = {"Elemental", "Enhancement", "Restoration"},
        roles = {DPS = true, HEALER = true},
        defaultRole = "DPS",
    },
    MAGE = {
        specs = {"Arcane", "Fire", "Frost"},
        roles = {DPS = true},
        defaultRole = "DPS",
    },
    WARLOCK = {
        specs = {"Affliction", "Demonology", "Destruction"},
        roles = {DPS = true},
        defaultRole = "DPS",
    },
    DRUID = {
        specs = {"Balance", "Feral Combat", "Restoration"},
        roles = {DPS = true, TANK = true, HEALER = true},
        defaultRole = "DPS",
    },
}

-- Template categories for UI organization
Comp.TemplateCategories = {
    {id = "WOTLK", name = "WotLK Raids", order = 1},
    {id = "WOTLK_DUNGEON", name = "WotLK Dungeons", order = 2},
    {id = "TBC", name = "TBC Raids", order = 3},
    {id = "CLASSIC", name = "Classic Raids", order = 4},
    {id = "WEEKLY", name = "Weekly/Daily", order = 5},
}

-- Raid bosses for loot ban dropdown
Comp.RaidBosses = {
    ["ICC"] = {
        name = "Icecrown Citadel",
        zone = "Icecrown Citadel",
        bosses = {
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
        },
    },
    ["RS"] = {
        name = "Ruby Sanctum",
        zone = "The Ruby Sanctum",
        bosses = {
            "Baltharus the Warborn",
            "Saviana Ragefire",
            "General Zarithrian",
            "Halion",
        },
    },
    ["TOC"] = {
        name = "Trial of the Crusader",
        zone = "Trial of the Crusader",
        bosses = {
            "Northrend Beasts",
            "Lord Jaraxxus",
            "Faction Champions",
            "Twin Val'kyr",
            "Anub'arak",
        },
    },
    ["ULDUAR"] = {
        name = "Ulduar",
        zone = "Ulduar",
        bosses = {
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
        },
    },
    ["NAXX"] = {
        name = "Naxxramas",
        zone = "Naxxramas",
        bosses = {
            "Anub'Rekhan",
            "Grand Widow Faerlina",
            "Maexxna",
            "Noth the Plaguebringer",
            "Heigan the Unclean",
            "Loatheb",
            "Instructor Razuvious",
            "Gothik the Harvester",
            "The Four Horsemen",
            "Patchwerk",
            "Grobbulus",
            "Gluth",
            "Thaddius",
            "Sapphiron",
            "Kel'Thuzad",
        },
    },
    ["EOE"] = {
        name = "Eye of Eternity",
        zone = "The Eye of Eternity",
        bosses = {
            "Malygos",
        },
    },
    ["OS"] = {
        name = "Obsidian Sanctum",
        zone = "The Obsidian Sanctum",
        bosses = {
            "Sartharion",
            "Tenebron",
            "Shadron",
            "Vesperon",
        },
    },
    ["VOA"] = {
        name = "Vault of Archavon",
        zone = "Vault of Archavon",
        bosses = {
            "Archavon the Stone Watcher",
            "Emalon the Storm Watcher",
            "Koralon the Flame Watcher",
            "Toravon the Ice Watcher",
        },
    },
    ["ONYXIA"] = {
        name = "Onyxia's Lair",
        zone = "Onyxia's Lair",
        bosses = {
            "Onyxia",
        },
    },
    ["FOS"] = {
        name = "Forge of Souls",
        zone = "The Forge of Souls",
        bosses = {
            "Bronjahm",
            "Devourer of Souls",
        },
    },
    ["POS"] = {
        name = "Pit of Saron",
        zone = "Pit of Saron",
        bosses = {
            "Forgemaster Garfrost",
            "Ick & Krick",
            "Scourgelord Tyrannus",
        },
    },
    ["HOR"] = {
        name = "Halls of Reflection",
        zone = "Halls of Reflection",
        bosses = {
            "Falric",
            "Marwyn",
            "The Lich King",
        },
    },
}

-- Helper to get boss list for current zone (prioritizes current zone)
function Comp.GetBossListForZone(currentZone)
    local prioritized = {}
    local others = {}

    for key, data in pairs(Comp.RaidBosses) do
        if data.zone and currentZone and data.zone:lower() == currentZone:lower() then
            table.insert(prioritized, {key = key, data = data})
        else
            table.insert(others, {key = key, data = data})
        end
    end

    -- Sort others alphabetically by name
    table.sort(others, function(a, b) return a.data.name < b.data.name end)

    -- Combine: prioritized first, then others
    local result = {}
    for _, v in ipairs(prioritized) do table.insert(result, v) end
    for _, v in ipairs(others) do table.insert(result, v) end

    return result
end

-- Raid templates for all content
Comp.RaidTemplates = {
    -- ========================================================================
    -- WOTLK RAIDS
    -- ========================================================================

    -- Icecrown Citadel
    ["ICC10"] = {
        name = "Icecrown Citadel 10",
        shortName = "ICC10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 5000,
        recommended = {
            {role = "TANK", note = "Main Tank (high armor)"},
            {role = "TANK", note = "Off Tank (DK/Paladin preferred for adds)"},
            {role = "HEALER", note = "Raid Healer"},
            {role = "HEALER", note = "Tank Healer"},
            {role = "DPS", note = "Ranged DPS", ranged = true},
            {role = "DPS", note = "Ranged DPS", ranged = true},
            {role = "DPS", note = "Ranged/Melee DPS"},
            {role = "DPS", note = "Ranged/Melee DPS"},
            {role = "DPS", note = "Melee DPS"},
            {role = "DPS", note = "Melee DPS"},
        },
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism", "Battle Shout", "Blessing of Kings"},
    },
    ["ICC25"] = {
        name = "Icecrown Citadel 25",
        shortName = "ICC25",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        minGS = 5200,
        recommended = {
            {role = "TANK", note = "Main Tank"},
            {role = "TANK", note = "Off Tank 1"},
            {role = "TANK", note = "Off Tank 2 (for adds)"},
        },
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism", "Battle Shout", "Blessing of Kings", "Gift of the Wild"},
    },
    ["ICC10HC"] = {
        name = "ICC 10 Heroic",
        shortName = "ICC10HC",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 3,
        dps = 5,
        minGS = 5800,
        recommended = {},
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },
    ["ICC25HC"] = {
        name = "ICC 25 Heroic",
        shortName = "ICC25HC",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        minGS = 6000,
        recommended = {},
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism", "Battle Shout", "Blessing of Kings"},
    },

    -- Ruby Sanctum
    ["RS10"] = {
        name = "Ruby Sanctum 10",
        shortName = "RS10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 5500,
        requiredBuffs = {"Replenishment"},
    },
    ["RS25"] = {
        name = "Ruby Sanctum 25",
        shortName = "RS25",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        minGS = 5800,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },
    ["RS10HC"] = {
        name = "Ruby Sanctum 10 Heroic",
        shortName = "RS10HC",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 3,
        dps = 5,
        minGS = 5800,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },
    ["RS25HC"] = {
        name = "Ruby Sanctum 25 Heroic",
        shortName = "RS25HC",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        minGS = 6000,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },

    -- Trial of the Crusader
    ["TOC10"] = {
        name = "Trial of the Crusader 10",
        shortName = "TOC10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 4500,
        requiredBuffs = {"Replenishment"},
    },
    ["TOC25"] = {
        name = "Trial of the Crusader 25",
        shortName = "TOC25",
        category = "WOTLK",
        size = 25,
        tanks = 2,
        healers = 5,
        dps = 18,
        minGS = 4800,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },
    ["TOGC10"] = {
        name = "Trial of the Grand Crusader 10",
        shortName = "TOGC10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 3,
        dps = 5,
        minGS = 5200,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },
    ["TOGC25"] = {
        name = "Trial of the Grand Crusader 25",
        shortName = "TOGC25",
        category = "WOTLK",
        size = 25,
        tanks = 2,
        healers = 6,
        dps = 17,
        minGS = 5500,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },

    -- Ulduar
    ["ULDUAR10"] = {
        name = "Ulduar 10",
        shortName = "ULD10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 4000,
        requiredBuffs = {"Replenishment"},
    },
    ["ULDUAR25"] = {
        name = "Ulduar 25",
        shortName = "ULD25",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        minGS = 4500,
        requiredBuffs = {"Replenishment", "Bloodlust/Heroism"},
    },

    -- Naxxramas
    ["NAXX10"] = {
        name = "Naxxramas 10",
        shortName = "NAXX10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 3500,
        requiredBuffs = {},
    },
    ["NAXX25"] = {
        name = "Naxxramas 25",
        shortName = "NAXX25",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        minGS = 4000,
        requiredBuffs = {},
    },

    -- Eye of Eternity
    ["EOE10"] = {
        name = "Eye of Eternity 10",
        shortName = "EOE10",
        category = "WOTLK",
        size = 10,
        tanks = 1,
        healers = 2,
        dps = 7,
        minGS = 3800,
        requiredBuffs = {},
    },
    ["EOE25"] = {
        name = "Eye of Eternity 25",
        shortName = "EOE25",
        category = "WOTLK",
        size = 25,
        tanks = 1,
        healers = 5,
        dps = 19,
        minGS = 4200,
        requiredBuffs = {},
    },

    -- Obsidian Sanctum
    ["OS10_0D"] = {
        name = "Obsidian Sanctum 10 (0D)",
        shortName = "OS10",
        category = "WOTLK",
        size = 10,
        tanks = 1,
        healers = 2,
        dps = 7,
        minGS = 3500,
        requiredBuffs = {},
    },
    ["OS10_3D"] = {
        name = "Obsidian Sanctum 10 (3D)",
        shortName = "OS10+3",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 3,
        dps = 5,
        minGS = 4500,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["OS25_0D"] = {
        name = "Obsidian Sanctum 25 (0D)",
        shortName = "OS25",
        category = "WOTLK",
        size = 25,
        tanks = 1,
        healers = 5,
        dps = 19,
        minGS = 3800,
        requiredBuffs = {},
    },
    ["OS25_3D"] = {
        name = "Obsidian Sanctum 25 (3D)",
        shortName = "OS25+3",
        category = "WOTLK",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        minGS = 4800,
        requiredBuffs = {"Bloodlust/Heroism"},
    },

    -- Single boss raids
    ["VOA10"] = {
        name = "Vault of Archavon 10",
        shortName = "VOA10",
        category = "WOTLK",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 4000,
        requiredBuffs = {},
    },
    ["VOA25"] = {
        name = "Vault of Archavon 25",
        shortName = "VOA25",
        category = "WOTLK",
        size = 25,
        tanks = 2,
        healers = 5,
        dps = 18,
        minGS = 4500,
        requiredBuffs = {},
    },
    ["ONYXIA10"] = {
        name = "Onyxia's Lair 10",
        shortName = "ONY10",
        category = "WOTLK",
        size = 10,
        tanks = 1,
        healers = 2,
        dps = 7,
        minGS = 4000,
        requiredBuffs = {},
    },
    ["ONYXIA25"] = {
        name = "Onyxia's Lair 25",
        shortName = "ONY25",
        category = "WOTLK",
        size = 25,
        tanks = 2,
        healers = 5,
        dps = 18,
        minGS = 4500,
        requiredBuffs = {},
    },

    -- ========================================================================
    -- WOTLK DUNGEONS (5-man)
    -- ========================================================================
    ["HEROIC5"] = {
        name = "Heroic 5-man (Generic)",
        shortName = "HC",
        category = "WOTLK_DUNGEON",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 3000,
        requiredBuffs = {},
    },
    ["TOC5"] = {
        name = "Trial of the Champion",
        shortName = "TOC5",
        category = "WOTLK_DUNGEON",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 4000,
        requiredBuffs = {},
    },
    ["FOS"] = {
        name = "Forge of Souls",
        shortName = "FOS",
        category = "WOTLK_DUNGEON",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 4500,
        requiredBuffs = {},
    },
    ["POS"] = {
        name = "Pit of Saron",
        shortName = "POS",
        category = "WOTLK_DUNGEON",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 4800,
        requiredBuffs = {},
    },
    ["HOR"] = {
        name = "Halls of Reflection",
        shortName = "HOR",
        category = "WOTLK_DUNGEON",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 5000,
        requiredBuffs = {},
    },

    -- ========================================================================
    -- TBC RAIDS
    -- ========================================================================
    ["SWP"] = {
        name = "Sunwell Plateau",
        shortName = "SWP",
        category = "TBC",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["BT"] = {
        name = "Black Temple",
        shortName = "BT",
        category = "TBC",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["HYJAL"] = {
        name = "Mount Hyjal",
        shortName = "HYJAL",
        category = "TBC",
        size = 25,
        tanks = 3,
        healers = 7,
        dps = 15,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["TK"] = {
        name = "Tempest Keep",
        shortName = "TK",
        category = "TBC",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["SSC"] = {
        name = "Serpentshrine Cavern",
        shortName = "SSC",
        category = "TBC",
        size = 25,
        tanks = 3,
        healers = 6,
        dps = 16,
        requiredBuffs = {"Bloodlust/Heroism"},
    },
    ["GRUUL"] = {
        name = "Gruul's Lair",
        shortName = "GRUUL",
        category = "TBC",
        size = 25,
        tanks = 2,
        healers = 6,
        dps = 17,
        requiredBuffs = {},
    },
    ["MAG"] = {
        name = "Magtheridon's Lair",
        shortName = "MAG",
        category = "TBC",
        size = 25,
        tanks = 2,
        healers = 6,
        dps = 17,
        requiredBuffs = {},
    },
    ["KARA"] = {
        name = "Karazhan",
        shortName = "KARA",
        category = "TBC",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        requiredBuffs = {},
    },
    ["ZA"] = {
        name = "Zul'Aman",
        shortName = "ZA",
        category = "TBC",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        requiredBuffs = {"Bloodlust/Heroism"},
    },

    -- ========================================================================
    -- CLASSIC RAIDS
    -- ========================================================================
    ["MC"] = {
        name = "Molten Core",
        shortName = "MC",
        category = "CLASSIC",
        size = 40,
        tanks = 4,
        healers = 10,
        dps = 26,
        requiredBuffs = {},
    },
    ["BWL"] = {
        name = "Blackwing Lair",
        shortName = "BWL",
        category = "CLASSIC",
        size = 40,
        tanks = 4,
        healers = 12,
        dps = 24,
        requiredBuffs = {},
    },
    ["AQ40"] = {
        name = "Temple of Ahn'Qiraj",
        shortName = "AQ40",
        category = "CLASSIC",
        size = 40,
        tanks = 4,
        healers = 12,
        dps = 24,
        requiredBuffs = {},
    },
    ["AQ20"] = {
        name = "Ruins of Ahn'Qiraj",
        shortName = "AQ20",
        category = "CLASSIC",
        size = 20,
        tanks = 2,
        healers = 5,
        dps = 13,
        requiredBuffs = {},
    },
    ["NAXX40"] = {
        name = "Naxxramas (Classic)",
        shortName = "NAXX40",
        category = "CLASSIC",
        size = 40,
        tanks = 4,
        healers = 12,
        dps = 24,
        requiredBuffs = {},
    },
    ["ONY40"] = {
        name = "Onyxia's Lair (Classic)",
        shortName = "ONY40",
        category = "CLASSIC",
        size = 40,
        tanks = 2,
        healers = 10,
        dps = 28,
        requiredBuffs = {},
    },
    ["ZG"] = {
        name = "Zul'Gurub",
        shortName = "ZG",
        category = "CLASSIC",
        size = 20,
        tanks = 2,
        healers = 5,
        dps = 13,
        requiredBuffs = {},
    },

    -- ========================================================================
    -- WEEKLY/DAILY
    -- ========================================================================
    ["WEEKLY_RAID"] = {
        name = "Weekly Raid Quest",
        shortName = "WEEKLY",
        category = "WEEKLY",
        size = 10,
        tanks = 2,
        healers = 2,
        dps = 6,
        minGS = 4000,
        requiredBuffs = {},
    },
    ["DAILY_HEROIC"] = {
        name = "Daily Heroic",
        shortName = "DAILY",
        category = "WEEKLY",
        size = 5,
        tanks = 1,
        healers = 1,
        dps = 3,
        minGS = 3500,
        requiredBuffs = {},
    },
    ["WG_WEEKLY"] = {
        name = "Wintergrasp Weekly",
        shortName = "WG",
        category = "WEEKLY",
        size = 25,
        tanks = 2,
        healers = 5,
        dps = 18,
        minGS = 4000,
        requiredBuffs = {},
    },
}

-- Get templates by category
function Comp.GetTemplatesByCategory(categoryId)
    local templates = {}
    for key, template in pairs(Comp.RaidTemplates) do
        if template.category == categoryId then
            templates[key] = template
        end
    end
    return templates
end

-- Get all templates sorted by category
function Comp.GetAllTemplatesSorted()
    local result = {}

    for _, category in ipairs(Comp.TemplateCategories) do
        local catTemplates = {}
        for key, template in pairs(Comp.RaidTemplates) do
            if template.category == category.id then
                table.insert(catTemplates, {key = key, template = template})
            end
        end
        -- Sort by name within category
        table.sort(catTemplates, function(a, b)
            return a.template.name < b.template.name
        end)
        result[category.id] = {
            category = category,
            templates = catTemplates,
        }
    end

    return result
end

-- Get template count
function Comp.GetTemplateCount()
    local count = 0
    for _ in pairs(Comp.RaidTemplates) do
        count = count + 1
    end
    return count
end

-- ========================================================================
-- COMPREHENSIVE RAID BUFFS AND DEBUFFS FOR WOTLK 3.3.5a
-- ========================================================================

-- Buff categories for organized display
Comp.BuffCategories = {
    {id = "CRITICAL", name = "Critical Buffs", icon = "Interface\\Icons\\Spell_Nature_Bloodlust", color = {r=1, g=0.4, b=0.4}},
    {id = "STATS", name = "Stat Buffs", icon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings", color = {r=0.4, g=0.8, b=1}},
    {id = "ATTACK", name = "Attack Power", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", color = {r=1, g=0.6, b=0.2}},
    {id = "SPELLPOWER", name = "Spell Power", icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath", color = {r=0.8, g=0.4, b=1}},
    {id = "HASTE", name = "Haste Buffs", icon = "Interface\\Icons\\Spell_Nature_Windfury", color = {r=0.2, g=0.8, b=0.6}},
    {id = "CRIT", name = "Crit Buffs", icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina", color = {r=1, g=0.8, b=0.2}},
    {id = "HEALING", name = "Healing/Mana", icon = "Interface\\Icons\\Spell_Magic_ManaGain", color = {r=0.4, g=1, b=0.4}},
    {id = "DEBUFFS", name = "Target Debuffs", icon = "Interface\\Icons\\Ability_Warrior_Sunder", color = {r=0.9, g=0.3, b=0.9}},
    {id = "UTILITY", name = "Utility", icon = "Interface\\Icons\\Spell_Nature_Invisibilty", color = {r=0.7, g=0.7, b=0.7}},
}

-- Raid buffs and which classes provide them
Comp.RaidBuffs = {
    -- ========================================================================
    -- CRITICAL BUFFS (High priority - should always have)
    -- ========================================================================
    ["Bloodlust/Heroism"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_Bloodlust",
        category = "CRITICAL",
        description = "+30% Haste for 40 sec",
        important = true,
    },
    ["Replenishment"] = {
        classes = {"PALADIN", "PRIEST", "WARLOCK", "HUNTER"},
        specs = {"Retribution", "Shadow", "Destruction", "Survival"},
        icon = "Interface\\Icons\\Spell_Magic_ManaGain",
        category = "CRITICAL",
        description = "Restores 0.25% max mana/sec",
        important = true,
    },

    -- ========================================================================
    -- STAT BUFFS (Core stats - Stamina, Intellect, Spirit, Str/Agi)
    -- ========================================================================
    ["Blessing of Kings"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings",
        category = "STATS",
        description = "+10% all stats",
        important = true,
    },
    ["Gift of the Wild"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_Regeneration",
        category = "STATS",
        description = "+51 all stats, +750 armor, +54 resists",
        important = true,
    },
    ["Power Word: Fortitude"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Holy_WordFortitude",
        category = "STATS",
        description = "+165 Stamina",
        important = true,
    },
    ["Arcane Intellect"] = {
        classes = {"MAGE"},
        icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",
        category = "STATS",
        description = "+60 Intellect",
    },
    ["Divine Spirit"] = {
        classes = {"PRIEST"},
        specs = {"Discipline", "Holy"},
        icon = "Interface\\Icons\\Spell_Holy_DivineSpirit",
        category = "STATS",
        description = "+80 Spirit",
    },
    ["Fel Intelligence"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_FelIntelligence",
        category = "STATS",
        description = "+48 Int/Spirit (Felhunter)",
        alternatesWith = {"Arcane Intellect", "Divine Spirit"},
    },
    ["Horn of Winter"] = {
        classes = {"DEATHKNIGHT"},
        icon = "Interface\\Icons\\INV_Misc_Horn_02",
        category = "STATS",
        description = "+155 Str/Agi",
    },
    ["Strength of Earth Totem"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_EarthBindTotem",
        category = "STATS",
        description = "+155 Str/Agi",
        alternatesWith = {"Horn of Winter"},
    },
    ["Commanding Shout"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\Ability_Warrior_RallyingCry",
        category = "STATS",
        description = "+2255 Health",
    },
    ["Blood Pact"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_BloodBoil",
        category = "STATS",
        description = "+1330 Health (Imp)",
        alternatesWith = {"Commanding Shout"},
    },
    ["Shadow Protection"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Shadow_AntiShadow",
        category = "STATS",
        description = "+130 Shadow Resistance",
    },

    -- ========================================================================
    -- ATTACK POWER BUFFS
    -- ========================================================================
    ["Battle Shout"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\Ability_Warrior_BattleShout",
        category = "ATTACK",
        description = "+548 AP",
    },
    ["Blessing of Might"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_FistOfJustice",
        category = "ATTACK",
        description = "+550 AP, +110 mp5 (improved)",
        alternatesWith = {"Battle Shout"},
    },
    ["Trueshot Aura"] = {
        classes = {"HUNTER"},
        specs = {"Marksmanship"},
        icon = "Interface\\Icons\\Ability_TrueShot",
        category = "ATTACK",
        description = "+10% AP",
        important = true,
    },
    ["Abomination's Might"] = {
        classes = {"DEATHKNIGHT"},
        specs = {"Blood"},
        icon = "Interface\\Icons\\Ability_Warrior_IntensifyRage",
        category = "ATTACK",
        description = "+10% AP",
        alternatesWith = {"Trueshot Aura", "Unleashed Rage"},
    },
    ["Unleashed Rage"] = {
        classes = {"SHAMAN"},
        specs = {"Enhancement"},
        icon = "Interface\\Icons\\Spell_Nature_UnleashedRage",
        category = "ATTACK",
        description = "+10% AP",
        alternatesWith = {"Trueshot Aura", "Abomination's Might"},
    },

    -- ========================================================================
    -- SPELL POWER BUFFS
    -- ========================================================================
    ["Totem of Wrath"] = {
        classes = {"SHAMAN"},
        specs = {"Elemental"},
        icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath",
        category = "SPELLPOWER",
        description = "+280 SP, +3% crit to target",
        important = true,
    },
    ["Flametongue Totem"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_GuardianWard",
        category = "SPELLPOWER",
        description = "+144 SP",
        alternatesWith = {"Totem of Wrath"},
    },
    ["Demonic Pact"] = {
        classes = {"WARLOCK"},
        specs = {"Demonology"},
        icon = "Interface\\Icons\\Spell_Shadow_DemonicPact",
        category = "SPELLPOWER",
        description = "+10% SP (based on pet SP)",
        important = true,
    },
    ["Focus Magic"] = {
        classes = {"MAGE"},
        specs = {"Arcane"},
        icon = "Interface\\Icons\\Spell_Arcane_StudentOfMagic",
        category = "SPELLPOWER",
        description = "+3% spell crit (single target)",
    },

    -- ========================================================================
    -- DAMAGE MULTIPLIER BUFFS
    -- ========================================================================
    ["Ferocious Inspiration"] = {
        classes = {"HUNTER"},
        specs = {"Beast Mastery"},
        icon = "Interface\\Icons\\Ability_Hunter_FerociousInspiration",
        category = "ATTACK",
        description = "+3% all damage",
        important = true,
    },
    ["Arcane Empowerment"] = {
        classes = {"MAGE"},
        specs = {"Arcane"},
        icon = "Interface\\Icons\\Spell_Arcane_Starfire",
        category = "ATTACK",
        description = "+3% all damage",
        alternatesWith = {"Ferocious Inspiration", "Sanctified Retribution"},
    },
    ["Sanctified Retribution"] = {
        classes = {"PALADIN"},
        specs = {"Retribution"},
        icon = "Interface\\Icons\\Spell_Holy_MindVision",
        category = "ATTACK",
        description = "+3% all damage",
        alternatesWith = {"Ferocious Inspiration", "Arcane Empowerment"},
    },

    -- ========================================================================
    -- HASTE BUFFS
    -- ========================================================================
    ["Windfury Totem"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_Windfury",
        category = "HASTE",
        description = "+16% melee haste",
        important = true,
    },
    ["Icy Talons"] = {
        classes = {"DEATHKNIGHT"},
        specs = {"Frost"},
        icon = "Interface\\Icons\\Spell_DeathKnight_IcyTalons",
        category = "HASTE",
        description = "+20% melee haste",
        alternatesWith = {"Windfury Totem"},
    },
    ["Improved Moonkin Form"] = {
        classes = {"DRUID"},
        specs = {"Balance"},
        icon = "Interface\\Icons\\Spell_Nature_ForceOfNature",
        category = "HASTE",
        description = "+3% spell haste",
    },
    ["Swift Retribution"] = {
        classes = {"PALADIN"},
        specs = {"Retribution"},
        icon = "Interface\\Icons\\Ability_Paladin_SwiftRetribution",
        category = "HASTE",
        description = "+3% melee/ranged/spell haste",
        alternatesWith = {"Improved Moonkin Form"},
    },
    ["Wrath of Air Totem"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_SlowingTotem",
        category = "HASTE",
        description = "+5% spell haste",
        important = true,
    },

    -- ========================================================================
    -- CRIT BUFFS
    -- ========================================================================
    ["Leader of the Pack"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina",
        category = "CRIT",
        description = "+5% melee/ranged crit",
        important = true,
    },
    ["Rampage"] = {
        classes = {"WARRIOR"},
        specs = {"Fury"},
        icon = "Interface\\Icons\\Ability_Warrior_Rampage",
        category = "CRIT",
        description = "+5% melee/ranged crit",
        alternatesWith = {"Leader of the Pack"},
    },
    ["Moonkin Aura"] = {
        classes = {"DRUID"},
        specs = {"Balance"},
        icon = "Interface\\Icons\\Spell_Nature_MoonkinForm",
        category = "CRIT",
        description = "+5% spell crit",
        important = true,
    },
    ["Elemental Oath"] = {
        classes = {"SHAMAN"},
        specs = {"Elemental"},
        icon = "Interface\\Icons\\Spell_Shaman_ElementalOath",
        category = "CRIT",
        description = "+5% spell crit",
        alternatesWith = {"Moonkin Aura"},
    },

    -- ========================================================================
    -- HEALING/MANA BUFFS
    -- ========================================================================
    ["Blessing of Wisdom"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom",
        category = "HEALING",
        description = "+92 mp5",
    },
    ["Mana Spring Totem"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_ManaRegenTotem",
        category = "HEALING",
        description = "+91 mp5",
        alternatesWith = {"Blessing of Wisdom"},
    },
    ["Vampiric Embrace"] = {
        classes = {"PRIEST"},
        specs = {"Shadow"},
        icon = "Interface\\Icons\\Spell_Shadow_UnsummonBuilding",
        category = "HEALING",
        description = "Shadow dmg heals party (15%/3%)",
    },
    ["Judgement of Light"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_HealingAura",
        category = "HEALING",
        description = "Melee attacks heal attacker",
    },
    ["Judgement of Wisdom"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_RighteousnessAura",
        category = "HEALING",
        description = "Attacks restore 2% base mana",
    },
    ["Revitalize"] = {
        classes = {"DRUID"},
        specs = {"Restoration"},
        icon = "Interface\\Icons\\Ability_Druid_Flourish",
        category = "HEALING",
        description = "Rejuv ticks restore mana/energy/rage/RP",
    },
    ["Hunting Party"] = {
        classes = {"HUNTER"},
        specs = {"Survival"},
        icon = "Interface\\Icons\\Ability_Hunter_HuntingParty",
        category = "HEALING",
        description = "Crits restore 1% mana to party",
        alternatesWith = {"Replenishment"},
    },
    ["Improved Leader of the Pack"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Spell_Nature_RegenerateHealing",
        category = "HEALING",
        description = "Crits heal 4% HP, restore mana",
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Armor Reduction
    -- ========================================================================
    ["Sunder Armor"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\Ability_Warrior_Sunder",
        category = "DEBUFFS",
        description = "-20% armor (5 stacks)",
        debuff = true,
        important = true,
    },
    ["Expose Armor"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\Ability_Warrior_Riposte",
        category = "DEBUFFS",
        description = "-20% armor",
        debuff = true,
        alternatesWith = {"Sunder Armor", "Acid Spit"},
    },
    ["Acid Spit"] = {
        classes = {"HUNTER"},
        icon = "Interface\\Icons\\Spell_Nature_Acid_01",
        category = "DEBUFFS",
        description = "-20% armor (Worm pet)",
        debuff = true,
        alternatesWith = {"Sunder Armor", "Expose Armor"},
    },
    ["Faerie Fire"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
        category = "DEBUFFS",
        description = "-5% armor",
        debuff = true,
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Magic Damage Increase
    -- ========================================================================
    ["Curse of Elements"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_ChillTouch",
        category = "DEBUFFS",
        description = "+13% magic dmg taken, -165 resists",
        debuff = true,
        important = true,
    },
    ["Earth and Moon"] = {
        classes = {"DRUID"},
        specs = {"Balance"},
        icon = "Interface\\Icons\\Ability_Druid_EarthandMoon",
        category = "DEBUFFS",
        description = "+13% magic dmg taken",
        debuff = true,
        alternatesWith = {"Curse of Elements", "Ebon Plaguebringer"},
    },
    ["Ebon Plaguebringer"] = {
        classes = {"DEATHKNIGHT"},
        specs = {"Unholy"},
        icon = "Interface\\Icons\\Ability_Creature_Cursed_03",
        category = "DEBUFFS",
        description = "+13% magic dmg taken",
        debuff = true,
        alternatesWith = {"Curse of Elements", "Earth and Moon"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Physical Damage Increase
    -- ========================================================================
    ["Blood Frenzy"] = {
        classes = {"WARRIOR"},
        specs = {"Arms"},
        icon = "Interface\\Icons\\Ability_Warrior_BloodFrenzy",
        category = "DEBUFFS",
        description = "+4% physical dmg taken",
        debuff = true,
        important = true,
    },
    ["Savage Combat"] = {
        classes = {"ROGUE"},
        specs = {"Combat"},
        icon = "Interface\\Icons\\Ability_Creature_Disease_03",
        category = "DEBUFFS",
        description = "+4% physical dmg taken",
        debuff = true,
        alternatesWith = {"Blood Frenzy"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Bleed Damage Increase
    -- ========================================================================
    ["Mangle"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Ability_Druid_Mangle2",
        category = "DEBUFFS",
        description = "+30% bleed dmg",
        debuff = true,
        important = true,
    },
    ["Trauma"] = {
        classes = {"WARRIOR"},
        specs = {"Arms"},
        icon = "Interface\\Icons\\Ability_Warrior_Trauma",
        category = "DEBUFFS",
        description = "+30% bleed dmg",
        debuff = true,
        alternatesWith = {"Mangle", "Stampede"},
    },
    ["Stampede"] = {
        classes = {"HUNTER"},
        icon = "Interface\\Icons\\Ability_Hunter_Pet_Rhino",
        category = "DEBUFFS",
        description = "+25% bleed dmg (Rhino pet)",
        debuff = true,
        alternatesWith = {"Mangle", "Trauma"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Crit Chance Increase
    -- ========================================================================
    ["Heart of the Crusader"] = {
        classes = {"PALADIN"},
        specs = {"Retribution"},
        icon = "Interface\\Icons\\Spell_Holy_HolySmite",
        category = "DEBUFFS",
        description = "+3% crit chance on target",
        debuff = true,
    },
    ["Master Poisoner"] = {
        classes = {"ROGUE"},
        specs = {"Assassination"},
        icon = "Interface\\Icons\\Ability_Creature_Poison_06",
        category = "DEBUFFS",
        description = "+3% crit chance on target",
        debuff = true,
        alternatesWith = {"Heart of the Crusader"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Spell Crit Increase
    -- ========================================================================
    ["Improved Scorch"] = {
        classes = {"MAGE"},
        specs = {"Fire"},
        icon = "Interface\\Icons\\Spell_Fire_SoulBurn",
        category = "DEBUFFS",
        description = "+5% spell crit on target",
        debuff = true,
        important = true,
    },
    ["Winter's Chill"] = {
        classes = {"MAGE"},
        specs = {"Frost"},
        icon = "Interface\\Icons\\Spell_Frost_ChillingBlast",
        category = "DEBUFFS",
        description = "+5% spell crit on target",
        debuff = true,
        alternatesWith = {"Improved Scorch", "Shadow Mastery"},
    },
    ["Shadow Mastery"] = {
        classes = {"WARLOCK"},
        specs = {"Affliction"},
        icon = "Interface\\Icons\\Spell_Shadow_CurseOfAchimonde",
        category = "DEBUFFS",
        description = "+5% spell crit on target",
        debuff = true,
        alternatesWith = {"Improved Scorch", "Winter's Chill"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Hit Chance Increase
    -- ========================================================================
    ["Misery"] = {
        classes = {"PRIEST"},
        specs = {"Shadow"},
        icon = "Interface\\Icons\\Spell_Shadow_MiseryBuff",
        category = "DEBUFFS",
        description = "+3% hit on target",
        debuff = true,
        important = true,
    },
    ["Improved Faerie Fire"] = {
        classes = {"DRUID"},
        specs = {"Balance"},
        icon = "Interface\\Icons\\Spell_Nature_FaerieFire",
        category = "DEBUFFS",
        description = "+3% hit on target",
        debuff = true,
        alternatesWith = {"Misery"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Attack Speed Reduction
    -- ========================================================================
    ["Thunder Clap"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\Spell_Nature_ThunderClap",
        category = "DEBUFFS",
        description = "-20% attack speed",
        debuff = true,
        important = true,
    },
    ["Frost Fever"] = {
        classes = {"DEATHKNIGHT"},
        icon = "Interface\\Icons\\Spell_DeathKnight_IceBoundFortitude",
        category = "DEBUFFS",
        description = "-20% attack speed",
        debuff = true,
        alternatesWith = {"Thunder Clap", "Infected Wounds", "Judgements of the Just"},
    },
    ["Infected Wounds"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Ability_Druid_InfectedWound",
        category = "DEBUFFS",
        description = "-20% attack speed",
        debuff = true,
        alternatesWith = {"Thunder Clap", "Frost Fever", "Judgements of the Just"},
    },
    ["Judgements of the Just"] = {
        classes = {"PALADIN"},
        specs = {"Protection"},
        icon = "Interface\\Icons\\Ability_Paladin_JudgementRed",
        category = "DEBUFFS",
        description = "-20% attack speed",
        debuff = true,
        alternatesWith = {"Thunder Clap", "Frost Fever", "Infected Wounds"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Attack Power Reduction
    -- ========================================================================
    ["Demoralizing Shout"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\Ability_Warrior_WarCry",
        category = "DEBUFFS",
        description = "-411 AP on target",
        debuff = true,
        important = true,
    },
    ["Demoralizing Roar"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Ability_Druid_DemoralizingRoar",
        category = "DEBUFFS",
        description = "-408 AP on target",
        debuff = true,
        alternatesWith = {"Demoralizing Shout", "Vindication", "Curse of Weakness"},
    },
    ["Vindication"] = {
        classes = {"PALADIN"},
        specs = {"Retribution", "Protection"},
        icon = "Interface\\Icons\\Spell_Holy_Vindication",
        category = "DEBUFFS",
        description = "-574 AP on target",
        debuff = true,
        alternatesWith = {"Demoralizing Shout", "Demoralizing Roar", "Curse of Weakness"},
    },
    ["Curse of Weakness"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_CurseOfMannoroth",
        category = "DEBUFFS",
        description = "-478 AP on target",
        debuff = true,
        alternatesWith = {"Demoralizing Shout", "Demoralizing Roar", "Vindication"},
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Cast Speed Reduction
    -- ========================================================================
    ["Curse of Tongues"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_CurseOfTounable",
        category = "DEBUFFS",
        description = "+30% cast time on target",
        debuff = true,
    },
    ["Mind-numbing Poison"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\Spell_Nature_NullifyDisease",
        category = "DEBUFFS",
        description = "+30% cast time on target",
        debuff = true,
        alternatesWith = {"Curse of Tongues"},
    },
    ["Slow"] = {
        classes = {"MAGE"},
        specs = {"Arcane"},
        icon = "Interface\\Icons\\Spell_Nature_Slow",
        category = "DEBUFFS",
        description = "+60% cast time, -60% move speed",
        debuff = true,
    },

    -- ========================================================================
    -- TARGET DEBUFFS - Healing Reduction
    -- ========================================================================
    ["Mortal Strike"] = {
        classes = {"WARRIOR"},
        specs = {"Arms"},
        icon = "Interface\\Icons\\Ability_Warrior_SavageBlow",
        category = "DEBUFFS",
        description = "-50% healing received",
        debuff = true,
    },
    ["Wound Poison"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\INV_Misc_Herb_16",
        category = "DEBUFFS",
        description = "-50% healing received",
        debuff = true,
        alternatesWith = {"Mortal Strike", "Aimed Shot"},
    },
    ["Aimed Shot"] = {
        classes = {"HUNTER"},
        specs = {"Marksmanship"},
        icon = "Interface\\Icons\\INV_Spear_07",
        category = "DEBUFFS",
        description = "-50% healing received",
        debuff = true,
        alternatesWith = {"Mortal Strike", "Wound Poison"},
    },

    -- ========================================================================
    -- UTILITY - Threat Management
    -- ========================================================================
    ["Misdirection"] = {
        classes = {"HUNTER"},
        icon = "Interface\\Icons\\Ability_Hunter_Misdirection",
        category = "UTILITY",
        description = "Redirect threat to target",
        important = true,
    },
    ["Tricks of the Trade"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\Ability_Rogue_TricksOftheTrade",
        category = "UTILITY",
        description = "Redirect threat + 15% dmg",
        important = true,
        alternatesWith = {"Misdirection"},
    },

    -- ========================================================================
    -- UTILITY - Combat Resurrection / Recovery
    -- ========================================================================
    ["Rebirth"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
        category = "UTILITY",
        description = "Combat resurrection (20min CD)",
        important = true,
    },
    ["Soulstone"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_SoulGem",
        category = "UTILITY",
        description = "Self-resurrection",
    },
    ["Reincarnation"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_Reincarnation",
        category = "UTILITY",
        description = "Self-resurrection (30min CD)",
    },
    ["Divine Intervention"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Nature_TimeStop",
        category = "UTILITY",
        description = "Save target, wipe recovery (20min CD)",
    },

    -- ========================================================================
    -- UTILITY - Damage Reduction
    -- ========================================================================
    ["Blessing of Sanctuary"] = {
        classes = {"PALADIN"},
        specs = {"Protection"},
        icon = "Interface\\Icons\\Spell_Nature_LightningShield",
        category = "UTILITY",
        description = "-3% damage taken, +10% Str/Stam",
    },
    ["Renewed Hope"] = {
        classes = {"PRIEST"},
        specs = {"Discipline"},
        icon = "Interface\\Icons\\Spell_Holy_HolyProtection",
        category = "UTILITY",
        description = "-3% damage taken (raid-wide)",
        alternatesWith = {"Blessing of Sanctuary"},
    },
    ["Pain Suppression"] = {
        classes = {"PRIEST"},
        specs = {"Discipline"},
        icon = "Interface\\Icons\\Spell_Holy_PainSuppression",
        category = "UTILITY",
        description = "-40% damage taken (single target)",
    },
    ["Hand of Sacrifice"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
        category = "UTILITY",
        description = "Transfer 30% damage to Paladin",
    },

    -- ========================================================================
    -- UTILITY - Emergency Abilities
    -- ========================================================================
    ["Innervate"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_Lightning",
        category = "UTILITY",
        description = "Restore 450% of caster's mp5 for 20sec",
    },
    ["Lay on Hands"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_LayOnHands",
        category = "UTILITY",
        description = "Full heal + mana (20min CD)",
    },
    ["Divine Shield"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_DivineIntervention",
        category = "UTILITY",
        description = "Immunity for 12 sec",
    },
    ["Hand of Protection"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_SealOfProtection",
        category = "UTILITY",
        description = "Physical immunity for 10 sec",
    },
    ["Ice Block"] = {
        classes = {"MAGE"},
        icon = "Interface\\Icons\\Spell_Frost_Frost",
        category = "UTILITY",
        description = "Immunity for 10 sec",
    },

    -- ========================================================================
    -- UTILITY - Crowd Control
    -- ========================================================================
    ["Polymorph"] = {
        classes = {"MAGE"},
        icon = "Interface\\Icons\\Spell_Nature_Polymorph",
        category = "UTILITY",
        description = "CC Humanoid/Beast/Critter",
    },
    ["Hex"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Shaman_Hex",
        category = "UTILITY",
        description = "CC Humanoid/Beast",
    },
    ["Sap"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\Ability_Sap",
        category = "UTILITY",
        description = "CC Humanoid/Beast/Demon/Dragonkin",
    },
    ["Freezing Trap"] = {
        classes = {"HUNTER"},
        icon = "Interface\\Icons\\Spell_Frost_ChainsOfIce",
        category = "UTILITY",
        description = "CC any mob",
    },
    ["Fear"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_Possession",
        category = "UTILITY",
        description = "CC any mob (moves)",
    },
    ["Banish"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_Cripple",
        category = "UTILITY",
        description = "CC Demon/Elemental",
    },
    ["Shackle Undead"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Nature_Slow",
        category = "UTILITY",
        description = "CC Undead",
    },
    ["Hibernate"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_Sleep",
        category = "UTILITY",
        description = "CC Beast/Dragonkin",
    },
    ["Cyclone"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_EarthBind",
        category = "UTILITY",
        description = "CC any mob (short)",
    },
    ["Entangling Roots"] = {
        classes = {"DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_StrangleVines",
        category = "UTILITY",
        description = "Root any mob",
    },
    ["Mind Control"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Shadow_ShadowWordDominate",
        category = "UTILITY",
        description = "Control Humanoid",
    },
    ["Turn Evil"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_TurnUndead",
        category = "UTILITY",
        description = "Fear Undead/Demon",
    },
    ["Repentance"] = {
        classes = {"PALADIN"},
        specs = {"Retribution"},
        icon = "Interface\\Icons\\Spell_Holy_PrayerOfHealing",
        category = "UTILITY",
        description = "CC Humanoid/Demon/Dragon/Giant/Undead",
    },

    -- ========================================================================
    -- UTILITY - Interrupts
    -- ========================================================================
    ["Counterspell"] = {
        classes = {"MAGE"},
        icon = "Interface\\Icons\\Spell_Frost_IceShock",
        category = "UTILITY",
        description = "8 sec lockout",
    },
    ["Kick"] = {
        classes = {"ROGUE"},
        icon = "Interface\\Icons\\Ability_Kick",
        category = "UTILITY",
        description = "5 sec lockout",
    },
    ["Pummel"] = {
        classes = {"WARRIOR"},
        icon = "Interface\\Icons\\INV_Gauntlets_04",
        category = "UTILITY",
        description = "4 sec lockout",
    },
    ["Mind Freeze"] = {
        classes = {"DEATHKNIGHT"},
        icon = "Interface\\Icons\\Spell_DeathKnight_MindFreeze",
        category = "UTILITY",
        description = "4 sec lockout",
    },
    ["Skull Bash"] = {
        classes = {"DRUID"},
        specs = {"Feral Combat"},
        icon = "Interface\\Icons\\Ability_Druid_Bash",
        category = "UTILITY",
        description = "5 sec lockout",
    },
    ["Wind Shear"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_Cyclone",
        category = "UTILITY",
        description = "2 sec lockout (6 sec CD)",
    },
    ["Silencing Shot"] = {
        classes = {"HUNTER"},
        specs = {"Marksmanship"},
        icon = "Interface\\Icons\\Ability_TheBlackArrow",
        category = "UTILITY",
        description = "3 sec silence",
    },
    ["Strangulate"] = {
        classes = {"DEATHKNIGHT"},
        icon = "Interface\\Icons\\Spell_Shadow_SoulLeech_3",
        category = "UTILITY",
        description = "5 sec silence",
    },
    ["Silence"] = {
        classes = {"PRIEST"},
        specs = {"Shadow"},
        icon = "Interface\\Icons\\Spell_Shadow_Impphaseshift",
        category = "UTILITY",
        description = "5 sec silence",
    },
    ["Spell Lock"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Shadow_MindRot",
        category = "UTILITY",
        description = "6 sec lockout (Felhunter)",
    },

    -- ========================================================================
    -- UTILITY - Dispels
    -- ========================================================================
    ["Cleanse"] = {
        classes = {"PALADIN"},
        icon = "Interface\\Icons\\Spell_Holy_Purify",
        category = "UTILITY",
        description = "Remove Poison/Disease/Magic",
    },
    ["Abolish Disease"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Nature_NullifyDisease_02",
        category = "UTILITY",
        description = "Remove Disease",
    },
    ["Dispel Magic"] = {
        classes = {"PRIEST"},
        icon = "Interface\\Icons\\Spell_Holy_DispelMagic",
        category = "UTILITY",
        description = "Remove Magic (friendly/enemy)",
    },
    ["Remove Curse"] = {
        classes = {"MAGE", "DRUID"},
        icon = "Interface\\Icons\\Spell_Nature_RemoveCurse",
        category = "UTILITY",
        description = "Remove Curse",
    },
    ["Cleanse Spirit"] = {
        classes = {"SHAMAN"},
        specs = {"Restoration"},
        icon = "Interface\\Icons\\Ability_Shaman_CleanseToxins",
        category = "UTILITY",
        description = "Remove Poison/Disease/Curse/Magic",
    },
    ["Purge"] = {
        classes = {"SHAMAN"},
        icon = "Interface\\Icons\\Spell_Nature_Purge",
        category = "UTILITY",
        description = "Remove enemy Magic buff",
    },
    ["Spellsteal"] = {
        classes = {"MAGE"},
        icon = "Interface\\Icons\\Spell_Arcane_Arcane02",
        category = "UTILITY",
        description = "Steal enemy Magic buff",
    },
    ["Devour Magic"] = {
        classes = {"WARLOCK"},
        icon = "Interface\\Icons\\Spell_Nature_NullifyPosion_02",
        category = "UTILITY",
        description = "Remove enemy Magic buff (Felhunter)",
    },

    -- ========================================================================
    -- UTILITY - Racial Abilities
    -- ========================================================================
    ["Heroic Presence"] = {
        classes = {"DRAENEI"},
        icon = "Interface\\Icons\\INV_Helmet_21",
        category = "UTILITY",
        description = "+1% hit (party)",
        raceOnly = true,
    },
    ["Gift of the Naaru"] = {
        classes = {"DRAENEI"},
        icon = "Interface\\Icons\\Spell_Holy_HolyProtection",
        category = "UTILITY",
        description = "HoT based on AP/SP",
        raceOnly = true,
    },
    ["Every Man for Himself"] = {
        classes = {"HUMAN"},
        icon = "Interface\\Icons\\Spell_Shadow_Charm",
        category = "UTILITY",
        description = "PvP trinket effect",
        raceOnly = true,
    },
    ["Shadowmeld"] = {
        classes = {"NIGHTELF"},
        icon = "Interface\\Icons\\Ability_Ambush",
        category = "UTILITY",
        description = "Drop threat out of combat",
        raceOnly = true,
    },
}

-- Current raid state
Comp.CurrentRaid = {
    template = nil,
    members = {},  -- {name, class, role, spec, gs}
    roleCounts = {TANK = 0, HEALER = 0, DPS = 0},
    classCounts = {},
    buffsAvailable = {},
}

-- Initialize class counts
for class in pairs(Comp.ClassColors) do
    Comp.CurrentRaid.classCounts[class] = 0
end

-- Scan current raid/party composition
function Comp.ScanRaid()
    local raid = Comp.CurrentRaid
    raid.members = {}
    raid.roleCounts = {TANK = 0, HEALER = 0, DPS = 0}
    for class in pairs(Comp.ClassColors) do
        raid.classCounts[class] = 0
    end
    raid.buffsAvailable = {}

    local numMembers = GetNumRaidMembers()
    local isRaid = numMembers > 0

    if not isRaid then
        numMembers = GetNumPartyMembers()
    end

    -- Add self
    local playerName = UnitName("player")
    local _, playerClass = UnitClass("player")
    local playerRole = Comp.DetectRole("player")

    table.insert(raid.members, {
        name = playerName,
        class = playerClass,
        role = playerRole,
        spec = Comp.GetSpecName("player"),
        gs = Comp.GetGearScore(playerName),
        unit = "player",
    })

    raid.classCounts[playerClass] = (raid.classCounts[playerClass] or 0) + 1
    raid.roleCounts[playerRole] = (raid.roleCounts[playerRole] or 0) + 1

    -- Scan group members
    local prefix = isRaid and "raid" or "party"
    local count = isRaid and numMembers or (numMembers + 1)

    for i = 1, count do
        local unit = prefix .. i
        if UnitExists(unit) and not UnitIsUnit(unit, "player") then
            local name = UnitName(unit)
            local _, class = UnitClass(unit)
            local role = Comp.DetectRole(unit)

            if name and class then
                table.insert(raid.members, {
                    name = name,
                    class = class,
                    role = role,
                    spec = Comp.GetSpecName(unit),
                    gs = Comp.GetGearScore(name),
                    unit = unit,
                })

                raid.classCounts[class] = (raid.classCounts[class] or 0) + 1
                raid.roleCounts[role] = (raid.roleCounts[role] or 0) + 1
            end
        end
    end

    -- Check available buffs
    Comp.CheckBuffCoverage()

    -- Queue inspection requests for members with unknown specs
    -- (only for buffs that require specific specs)
    Comp.QueueInspections()

    return raid
end

-- Queue inspection requests for raid members with unknown specs
-- Only inspects members whose spec matters for buff coverage
Comp.InspectQueue = {}
Comp.LastInspectTime = 0
Comp.InspectInterval = 2  -- Seconds between inspect requests

function Comp.QueueInspections()
    local raid = Comp.CurrentRaid
    Comp.InspectQueue = {}

    -- Find members whose spec is unknown and matters for buffs
    for _, member in ipairs(raid.members) do
        if not member.spec and member.unit and member.unit ~= "player" then
            -- Check if this class provides any spec-specific buffs
            local needsInspect = false
            for _, buffInfo in pairs(Comp.RaidBuffs) do
                if buffInfo.specs then
                    for _, buffClass in ipairs(buffInfo.classes) do
                        if member.class == buffClass then
                            needsInspect = true
                            break
                        end
                    end
                end
                if needsInspect then break end
            end

            if needsInspect then
                table.insert(Comp.InspectQueue, member)
            end
        end
    end

    -- Start processing queue if not empty
    if #Comp.InspectQueue > 0 then
        Comp.ProcessInspectQueue()
    end
end

function Comp.ProcessInspectQueue()
    if #Comp.InspectQueue == 0 then return end

    local now = GetTime()
    if now - Comp.LastInspectTime < Comp.InspectInterval then
        -- Schedule next attempt (WotLK compatible)
        local delay = Comp.InspectInterval - (now - Comp.LastInspectTime) + 0.1
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(delay, Comp.ProcessInspectQueue)
        end
        return
    end

    -- Get next member to inspect
    local member = table.remove(Comp.InspectQueue, 1)
    if member and member.unit and UnitExists(member.unit) then
        Comp.RequestInspect(member.unit)
        Comp.LastInspectTime = now
    end

    -- Continue processing queue
    if #Comp.InspectQueue > 0 then
        if AIP.Utils and AIP.Utils.DelayedCall then
            AIP.Utils.DelayedCall(Comp.InspectInterval, Comp.ProcessInspectQueue)
        end
    end
end

-- Detect player role based on talents and gear
function Comp.DetectRole(unit)
    if not UnitExists(unit) then return "DPS" end

    local _, class = UnitClass(unit)
    if not class then return "DPS" end

    -- Check if they have tank role assigned (in raid)
    if UnitInRaid(unit) then
        local name = UnitName(unit)
        for i = 1, GetNumRaidMembers() do
            local raidName, _, _, _, _, _, _, _, _, raidRole = GetRaidRosterInfo(i)
            if raidName == name and (raidRole == "MAINTANK" or raidRole == "OFFTANK") then
                return "TANK"
            end
        end
    end

    -- Simple detection based on class and common behaviors
    -- In a full implementation, we'd inspect talents

    -- Check for tank-like behavior (has Righteous Fury, Defensive Stance, Bear Form, etc.)
    -- This is a simplified version

    local classInfo = Comp.ClassRoles[class]
    if classInfo then
        return classInfo.defaultRole
    end

    return "DPS"
end

-- Spec detection mapping: maps class + talent tree index to spec name
Comp.TalentTreeSpecs = {
    WARRIOR = {"Arms", "Fury", "Protection"},
    PALADIN = {"Holy", "Protection", "Retribution"},
    HUNTER = {"Beast Mastery", "Marksmanship", "Survival"},
    ROGUE = {"Assassination", "Combat", "Subtlety"},
    PRIEST = {"Discipline", "Holy", "Shadow"},
    DEATHKNIGHT = {"Blood", "Frost", "Unholy"},
    SHAMAN = {"Elemental", "Enhancement", "Restoration"},
    MAGE = {"Arcane", "Fire", "Frost"},
    WARLOCK = {"Affliction", "Demonology", "Destruction"},
    DRUID = {"Balance", "Feral Combat", "Restoration"},
}

-- Cache for inspected player specs (name -> {spec, timestamp})
Comp.InspectedSpecs = {}
Comp.InspectCacheDuration = 300  -- 5 minutes cache

-- Get spec name for a unit
function Comp.GetSpecName(unit)
    if not unit or not UnitExists(unit) then return nil end

    local _, class = UnitClass(unit)
    if not class or not Comp.TalentTreeSpecs[class] then return nil end

    local isPlayer = UnitIsUnit(unit, "player")
    local unitName = UnitName(unit)

    -- For the player, we can directly read talents
    if isPlayer then
        return Comp.GetPlayerSpec()
    end

    -- For other players, check our inspection cache first
    if unitName and Comp.InspectedSpecs[unitName] then
        local cached = Comp.InspectedSpecs[unitName]
        if time() - cached.timestamp < Comp.InspectCacheDuration then
            return cached.spec
        end
    end

    -- Try to get spec from inspection data if available
    local spec = Comp.GetInspectedSpec(unit)
    if spec and unitName then
        Comp.InspectedSpecs[unitName] = {spec = spec, timestamp = time()}
    end

    return spec
end

-- Get the player's active spec based on talent points
function Comp.GetPlayerSpec()
    local _, class = UnitClass("player")
    if not class or not Comp.TalentTreeSpecs[class] then return nil end

    -- Get active talent group (1 or 2 for dual spec)
    local activeGroup = 1
    if GetActiveTalentGroup then
        activeGroup = GetActiveTalentGroup()
    end

    local maxPoints = 0
    local primaryTree = 1

    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i, false, false, activeGroup)
        if pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent
            primaryTree = i
        end
    end

    return Comp.TalentTreeSpecs[class][primaryTree]
end

-- Try to get spec from inspection data (if player was recently inspected)
function Comp.GetInspectedSpec(unit)
    if not unit or not UnitExists(unit) then return nil end
    if UnitIsUnit(unit, "player") then return Comp.GetPlayerSpec() end

    local _, class = UnitClass(unit)
    if not class or not Comp.TalentTreeSpecs[class] then return nil end

    -- Check if we can read inspection talent data
    -- This only works if the inspection frame is open for this unit
    -- or if we have cached data from a recent inspection
    if not CanInspect(unit) then return nil end

    -- Try to read talent data from inspection cache
    -- Note: GetTalentTabInfo with inspect=true only works during active inspection
    local maxPoints = 0
    local primaryTree = 1
    local hasData = false

    for i = 1, 3 do
        local _, _, pointsSpent = GetTalentTabInfo(i, true, false)  -- inspect = true
        if pointsSpent and pointsSpent > 0 then
            hasData = true
            if pointsSpent > maxPoints then
                maxPoints = pointsSpent
                primaryTree = i
            end
        end
    end

    if hasData and maxPoints > 0 then
        return Comp.TalentTreeSpecs[class][primaryTree]
    end

    return nil
end

-- Request inspection for a unit (async operation)
function Comp.RequestInspect(unit)
    if not unit or not UnitExists(unit) then return end
    if UnitIsUnit(unit, "player") then return end  -- Don't inspect self
    if not CanInspect(unit) then return end
    if not CheckInteractDistance(unit, 1) then return end  -- Must be in range

    NotifyInspect(unit)
end

-- Handle inspection data received
local inspectFrame = CreateFrame("Frame")
inspectFrame:RegisterEvent("INSPECT_TALENT_READY")
inspectFrame:SetScript("OnEvent", function(self, event)
    if event == "INSPECT_TALENT_READY" then
        -- Get the inspected unit's spec and cache it
        local unit = "target"  -- Inspection is usually on target
        if InspectFrame and InspectFrame.unit then
            unit = InspectFrame.unit
        end

        if UnitExists(unit) then
            local unitName = UnitName(unit)
            local _, class = UnitClass(unit)

            if unitName and class and Comp.TalentTreeSpecs[class] then
                local spec = Comp.GetInspectedSpec(unit)
                if spec then
                    Comp.InspectedSpecs[unitName] = {spec = spec, timestamp = time()}

                    -- Trigger a raid rescan if we're tracking composition
                    if Comp.CurrentRaid.template then
                        -- Delay slightly to avoid spamming (WotLK compatible)
                        if AIP.Utils and AIP.Utils.DelayedCall then
                            AIP.Utils.DelayedCall(0.5, Comp.CheckBuffCoverage)
                        end
                    end
                end
            end
        end
    end
end)

-- Get GearScore if addon is available
function Comp.GetGearScore(name)
    -- Check for GearScore addon
    if GearScore_GetScore then
        local gs = GearScore_GetScore(name)
        if gs and gs > 0 then
            return gs
        end
    end

    -- Check for PlayerScore addon
    if PlayerScore_GetScore then
        local ps = PlayerScore_GetScore(name)
        if ps and ps > 0 then
            return ps
        end
    end

    return nil
end

-- Check if a member's spec matches any of the required specs for a buff
function Comp.SpecMatchesBuff(memberSpec, requiredSpecs)
    if not memberSpec or not requiredSpecs then return false end

    for _, reqSpec in ipairs(requiredSpecs) do
        if memberSpec == reqSpec then
            return true
        end
    end

    return false
end

-- Check which buffs are covered by current composition
function Comp.CheckBuffCoverage()
    local raid = Comp.CurrentRaid
    raid.buffsAvailable = {}
    raid.buffProviders = {}  -- Track who provides each buff
    raid.buffPotentialProviders = {}  -- Track class matches without spec confirmation

    for buffName, buffInfo in pairs(Comp.RaidBuffs) do
        local hasBuff = false
        local providers = {}
        local potentialProviders = {}  -- Have class but spec unknown/wrong

        for _, member in ipairs(raid.members) do
            if buffInfo.raceOnly then
                -- Skip race-based buffs for now (would need race detection)
            else
                for _, buffClass in ipairs(buffInfo.classes) do
                    if member.class == buffClass then
                        -- Check if spec matters for this buff
                        if buffInfo.specs then
                            -- Buff requires specific spec(s)
                            if member.spec then
                                -- We know the member's spec, verify it matches
                                if Comp.SpecMatchesBuff(member.spec, buffInfo.specs) then
                                    hasBuff = true
                                    table.insert(providers, {
                                        name = member.name,
                                        spec = member.spec,
                                        confirmed = true
                                    })
                                else
                                    -- Has class but wrong spec
                                    table.insert(potentialProviders, {
                                        name = member.name,
                                        spec = member.spec,
                                        reason = "wrong_spec"
                                    })
                                end
                            else
                                -- Spec unknown - add as potential provider
                                -- Don't count as confirmed since we can't verify
                                table.insert(potentialProviders, {
                                    name = member.name,
                                    spec = nil,
                                    reason = "spec_unknown"
                                })
                            end
                        else
                            -- No spec requirement - any player of this class can provide
                            hasBuff = true
                            table.insert(providers, {
                                name = member.name,
                                spec = member.spec,
                                confirmed = true
                            })
                        end
                        break
                    end
                end
            end
        end

        raid.buffsAvailable[buffName] = hasBuff
        raid.buffProviders[buffName] = providers
        raid.buffPotentialProviders[buffName] = potentialProviders
    end

    return raid.buffsAvailable
end

-- Get buffs organized by category with coverage status
function Comp.GetBuffsByCategory()
    local result = {}
    local raid = Comp.CurrentRaid

    for _, category in ipairs(Comp.BuffCategories) do
        local categoryBuffs = {}
        for buffName, buffInfo in pairs(Comp.RaidBuffs) do
            if buffInfo.category == category.id then
                local hasIt = raid.buffsAvailable[buffName] or false
                local hasAlternate = false
                local hasPotential = false
                local potentialProviders = raid.buffPotentialProviders and raid.buffPotentialProviders[buffName] or {}

                -- Check if we have potential providers (class match but spec unknown/wrong)
                if not hasIt and #potentialProviders > 0 then
                    hasPotential = true
                end

                -- Check if an alternate buff is available
                if not hasIt and buffInfo.alternatesWith then
                    for _, altName in ipairs(buffInfo.alternatesWith) do
                        if raid.buffsAvailable[altName] then
                            hasAlternate = true
                            break
                        end
                    end
                end

                -- Build provider names list (for backwards compatibility)
                local providerNames = {}
                local providers = raid.buffProviders[buffName] or {}
                for _, p in ipairs(providers) do
                    if type(p) == "table" then
                        table.insert(providerNames, p.name)
                    else
                        table.insert(providerNames, p)
                    end
                end

                table.insert(categoryBuffs, {
                    name = buffName,
                    info = buffInfo,
                    available = hasIt,
                    hasAlternate = hasAlternate,
                    hasPotential = hasPotential,
                    providers = providerNames,  -- Simple name list for backwards compat
                    providerDetails = providers,  -- Full details with spec info
                    potentialProviders = potentialProviders,  -- Players who might provide if spec changes
                    requiresSpec = buffInfo.specs ~= nil,  -- Flag if this buff requires specific spec
                })
            end
        end

        -- Sort by importance, then alphabetically
        table.sort(categoryBuffs, function(a, b)
            if (a.info.important or false) ~= (b.info.important or false) then
                return a.info.important or false
            end
            return a.name < b.name
        end)

        result[category.id] = {
            category = category,
            buffs = categoryBuffs,
        }
    end

    return result
end

-- Get important missing buffs (for quick summary)
function Comp.GetImportantMissingBuffs()
    local missing = {}
    local raid = Comp.CurrentRaid

    for buffName, buffInfo in pairs(Comp.RaidBuffs) do
        if buffInfo.important and not raid.buffsAvailable[buffName] then
            -- Check if an alternate is available
            local hasAlternate = false
            if buffInfo.alternatesWith then
                for _, altName in ipairs(buffInfo.alternatesWith) do
                    if raid.buffsAvailable[altName] then
                        hasAlternate = true
                        break
                    end
                end
            end

            if not hasAlternate then
                table.insert(missing, buffName)
            end
        end
    end

    return missing
end

-- Get missing buffs for current template
function Comp.GetMissingBuffs()
    local template = Comp.CurrentRaid.template
    if not template then return {} end

    local templateData = Comp.RaidTemplates[template]
    if not templateData or not templateData.requiredBuffs then return {} end

    local missing = {}
    for _, buffName in ipairs(templateData.requiredBuffs) do
        if not Comp.CurrentRaid.buffsAvailable[buffName] then
            table.insert(missing, buffName)
        end
    end

    return missing
end

-- Get composition status vs template
function Comp.GetCompositionStatus()
    local template = Comp.CurrentRaid.template
    if not template then
        return nil
    end

    local templateData = Comp.RaidTemplates[template]
    if not templateData then return nil end

    local status = {
        template = templateData.name,
        size = {current = #Comp.CurrentRaid.members, needed = templateData.size},
        tanks = {current = Comp.CurrentRaid.roleCounts.TANK, needed = templateData.tanks},
        healers = {current = Comp.CurrentRaid.roleCounts.HEALER, needed = templateData.healers},
        dps = {current = Comp.CurrentRaid.roleCounts.DPS, needed = templateData.dps},
        missingBuffs = Comp.GetMissingBuffs(),
        minGS = templateData.minGS,
    }

    return status
end

-- Set current raid template
function Comp.SetTemplate(templateKey)
    if Comp.RaidTemplates[templateKey] then
        Comp.CurrentRaid.template = templateKey
        Comp.ScanRaid()
        AIP.Print("Raid template set to: " .. Comp.RaidTemplates[templateKey].name)
        return true
    end
    return false
end

-- Get list of classes that can fill a role
function Comp.GetClassesForRole(role)
    local classes = {}
    for class, info in pairs(Comp.ClassRoles) do
        if info.roles[role] then
            table.insert(classes, class)
        end
    end
    return classes
end

-- Format class name with color
function Comp.ColoredClassName(class)
    local color = Comp.ClassColors[class]
    if color then
        return string.format("|cFF%02x%02x%02x%s|r",
            color.r * 255, color.g * 255, color.b * 255,
            class:sub(1,1) .. class:sub(2):lower())
    end
    return class
end

-- Print raid composition summary
function Comp.PrintSummary()
    Comp.ScanRaid()

    local status = Comp.GetCompositionStatus()

    AIP.Print("=== Raid Composition ===")

    if status then
        AIP.Print("Template: " .. status.template)
        AIP.Print(string.format("Size: %d/%d", status.size.current, status.size.needed))
        AIP.Print(string.format("Tanks: %d/%d | Healers: %d/%d | DPS: %d/%d",
            status.tanks.current, status.tanks.needed,
            status.healers.current, status.healers.needed,
            status.dps.current, status.dps.needed))

        if #status.missingBuffs > 0 then
            AIP.Print("|cFFFF0000Missing buffs:|r " .. table.concat(status.missingBuffs, ", "))
        else
            AIP.Print("|cFF00FF00All required buffs covered!|r")
        end
    else
        AIP.Print(string.format("Members: %d", #Comp.CurrentRaid.members))
        AIP.Print(string.format("Tanks: %d | Healers: %d | DPS: %d",
            Comp.CurrentRaid.roleCounts.TANK,
            Comp.CurrentRaid.roleCounts.HEALER,
            Comp.CurrentRaid.roleCounts.DPS))
    end

    -- Class breakdown
    local classStr = ""
    for class, count in pairs(Comp.CurrentRaid.classCounts) do
        if count > 0 then
            classStr = classStr .. Comp.ColoredClassName(class) .. ":" .. count .. " "
        end
    end
    if classStr ~= "" then
        AIP.Print("Classes: " .. classStr)
    end
end

-- Slash command handler for composition
function Comp.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "status" then
        Comp.PrintSummary()
    elseif msg == "scan" then
        Comp.ScanRaid()
        AIP.Print("Raid scanned: " .. #Comp.CurrentRaid.members .. " members")
    elseif msg == "templates" or msg == "list" then
        AIP.Print("Available raid templates:")
        for key, data in pairs(Comp.RaidTemplates) do
            AIP.Print("  " .. key .. " - " .. data.name .. " (" .. data.size .. " players)")
        end
    elseif msg:find("^set ") then
        local template = msg:sub(5):upper():gsub("%s", "")
        if Comp.SetTemplate(template) then
            Comp.PrintSummary()
        else
            AIP.Print("Unknown template: " .. template)
        end
    elseif msg == "buffs" then
        Comp.ScanRaid()
        AIP.Print("=== Buff Coverage ===")
        for buffName, available in pairs(Comp.CurrentRaid.buffsAvailable) do
            local status = available and "|cFF00FF00YES|r" or "|cFFFF0000NO|r"
            AIP.Print("  " .. buffName .. ": " .. status)
        end
    else
        AIP.Print("Composition commands:")
        AIP.Print("  /aip comp - Show current composition")
        AIP.Print("  /aip comp templates - List raid templates")
        AIP.Print("  /aip comp set ICC10 - Set raid template")
        AIP.Print("  /aip comp buffs - Show buff coverage")
    end
end

-- Register events for auto-scanning
local compFrame = CreateFrame("Frame")
compFrame:RegisterEvent("RAID_ROSTER_UPDATE")
compFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
compFrame:SetScript("OnEvent", function(self, event)
    -- Auto-scan when roster changes
    if Comp.CurrentRaid.template then
        Comp.ScanRaid()
        if AIP.UpdateCompositionUI then
            AIP.UpdateCompositionUI()
        end
    end
end)
