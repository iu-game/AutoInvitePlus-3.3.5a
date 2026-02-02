-- AutoInvite Plus - Parsers Module
-- Consolidated parsing logic for chat messages (DRY principle)

local AIP = AutoInvitePlus
AIP.Parsers = {}
local Parsers = AIP.Parsers

-- ============================================================================
-- GEARSCORE PATTERNS
-- ============================================================================

Parsers.GSPatterns = {
    -- Standard formats: "5800 gs", "gs 5800"
    "(%d%d%d%d)%+?%s*gs",
    "gs%s*(%d%d%d%d)%+?",
    "(%d%d%d%d)%+?%s*gearscore",
    "gearscore%s*(%d%d%d%d)%+?",
    "min%s*gs%s*(%d%d%d%d)",
    "gs%s*min%s*(%d%d%d%d)",
    -- K format: "5.8k gs", "gs 5.8k"
    "(%d[%.,]?%d)k%s*gs",
    "gs%s*(%d[%.,]?%d)k",
    "(%d[%.,]?%d)k%+?%s*gearscore",
    -- Requirements: "5800+ gs", "gs: 5800"
    "gs%s*:%s*(%d%d%d%d)",
    "(%d%d%d%d)%s*%+%s*gs",
    -- With separators: "5,800 gs"
    "(%d[%d,]+)%s*gs",
}

-- ============================================================================
-- RAID DETECTION PATTERNS (ordered by specificity - most specific first)
-- ============================================================================

Parsers.RaidPatterns = {
    -- ICC (Icecrown Citadel)
    {pattern = "icc%s*25%s*hc", raid = "ICC25H", category = "ICC"},
    {pattern = "icc%s*25%s*h[^a-z]", raid = "ICC25H", category = "ICC"},
    {pattern = "icc%s*25%s*heroic", raid = "ICC25H", category = "ICC"},
    {pattern = "icc%s*10%s*hc", raid = "ICC10H", category = "ICC"},
    {pattern = "icc%s*10%s*h[^a-z]", raid = "ICC10H", category = "ICC"},
    {pattern = "icc%s*10%s*heroic", raid = "ICC10H", category = "ICC"},
    {pattern = "icc%s*25%s*n", raid = "ICC25N", category = "ICC"},
    {pattern = "icc%s*25%s*normal", raid = "ICC25N", category = "ICC"},
    {pattern = "icc%s*10%s*n", raid = "ICC10N", category = "ICC"},
    {pattern = "icc%s*10%s*normal", raid = "ICC10N", category = "ICC"},
    {pattern = "icc%s*25", raid = "ICC25N", category = "ICC"},
    {pattern = "icc%s*10", raid = "ICC10N", category = "ICC"},
    {pattern = "icc", raid = "ICC", category = "ICC"},
    {pattern = "icecrown", raid = "ICC", category = "ICC"},

    -- RS (Ruby Sanctum)
    {pattern = "rs%s*25%s*h", raid = "RS25H", category = "RS"},
    {pattern = "rs%s*25%s*hc", raid = "RS25H", category = "RS"},
    {pattern = "rs%s*10%s*h", raid = "RS10H", category = "RS"},
    {pattern = "rs%s*10%s*hc", raid = "RS10H", category = "RS"},
    {pattern = "rs%s*25", raid = "RS25N", category = "RS"},
    {pattern = "rs%s*10", raid = "RS10N", category = "RS"},
    {pattern = "ruby%s*sanctum", raid = "RS", category = "RS"},
    {pattern = "halion", raid = "RS", category = "RS"},

    -- TOC/TOGC (Trial of the Crusader)
    {pattern = "togc%s*25", raid = "TOGC25", category = "TOC"},
    {pattern = "togc%s*10", raid = "TOGC10", category = "TOC"},
    {pattern = "toc%s*25%s*h", raid = "TOGC25", category = "TOC"},
    {pattern = "toc%s*10%s*h", raid = "TOGC10", category = "TOC"},
    {pattern = "toc%s*25", raid = "TOC25", category = "TOC"},
    {pattern = "toc%s*10", raid = "TOC10", category = "TOC"},
    {pattern = "trial%s*of%s*the?%s*crusader", raid = "TOC", category = "TOC"},
    {pattern = "trial%s*of%s*the?%s*grand%s*crusader", raid = "TOGC", category = "TOC"},

    -- Ulduar
    {pattern = "uld%s*25", raid = "ULDUAR25", category = "ULDUAR"},
    {pattern = "uld%s*10", raid = "ULDUAR10", category = "ULDUAR"},
    {pattern = "ulduar%s*25", raid = "ULDUAR25", category = "ULDUAR"},
    {pattern = "ulduar%s*10", raid = "ULDUAR10", category = "ULDUAR"},
    {pattern = "ulduar", raid = "ULDUAR", category = "ULDUAR"},

    -- Naxx
    {pattern = "naxx%s*25", raid = "NAXX25", category = "NAXX"},
    {pattern = "naxx%s*10", raid = "NAXX10", category = "NAXX"},
    {pattern = "naxxramas", raid = "NAXX", category = "NAXX"},

    -- VOA
    {pattern = "voa%s*25", raid = "VOA25", category = "VOA"},
    {pattern = "voa%s*10", raid = "VOA10", category = "VOA"},
    {pattern = "voa", raid = "VOA", category = "VOA"},
    {pattern = "vault%s*of%s*archavon", raid = "VOA", category = "VOA"},
    {pattern = "archavon", raid = "VOA", category = "VOA"},
    {pattern = "toravon", raid = "VOA", category = "VOA"},
    {pattern = "koralon", raid = "VOA", category = "VOA"},
    {pattern = "emalon", raid = "VOA", category = "VOA"},

    -- Onyxia
    {pattern = "ony%s*25", raid = "ONYXIA25", category = "ONYXIA"},
    {pattern = "ony%s*10", raid = "ONYXIA10", category = "ONYXIA"},
    {pattern = "onyxia", raid = "ONYXIA", category = "ONYXIA"},

    -- OS (Obsidian Sanctum)
    {pattern = "os%s*3d", raid = "OS3D", category = "OS"},
    {pattern = "os%s*2d", raid = "OS2D", category = "OS"},
    {pattern = "os%s*1d", raid = "OS1D", category = "OS"},
    {pattern = "os%s*0d", raid = "OS0D", category = "OS"},
    {pattern = "os%s*25", raid = "OS25", category = "OS"},
    {pattern = "os%s*10", raid = "OS10", category = "OS"},
    {pattern = "obsidian%s*sanctum", raid = "OS", category = "OS"},
    {pattern = "sarth", raid = "OS", category = "OS"},
    {pattern = "sartharion", raid = "OS", category = "OS"},

    -- EoE
    {pattern = "eoe%s*25", raid = "EOE25", category = "EOE"},
    {pattern = "eoe%s*10", raid = "EOE10", category = "EOE"},
    {pattern = "malygos", raid = "EOE", category = "EOE"},
    {pattern = "eye%s*of%s*eternity", raid = "EOE", category = "EOE"},

    -- Weekly
    {pattern = "weekly", raid = "WEEKLY", category = "WEEKLY"},
}

-- ============================================================================
-- ROLE DETECTION KEYWORDS
-- ============================================================================

Parsers.RoleKeywords = {
    tank = {
        patterns = {"tank", "mt", "ot", "prot", "protection", "bear"},
        lfmPatterns = {
            "lf%d*m?%s*tank",
            "need%s*%d*%s*tank",
            "need%s*mt",
            "need%s*ot",
            "looking%s*for%s*tank",
        },
    },
    healer = {
        patterns = {"healer", "heal", "resto", "restoration", "holy", "disc", "discipline", "tree", "hpala", "hpriest", "rsham"},
        lfmPatterns = {
            "lf%d*m?%s*heal",
            "need%s*%d*%s*heal",
            "looking%s*for%s*heal",
            "lf%d*m?%s*resto",
            "lf%d*m?%s*holy",
            "lf%d*m?%s*disc",
        },
    },
    dps = {
        patterns = {"dps", "damage", "dd", "ranged", "melee", "rdps", "mdps", "caster"},
        lfmPatterns = {
            "lf%d*m?%s*dps",
            "need%s*%d*%s*dps",
            "looking%s*for%s*dps",
            "lf%d*m?%s*ranged",
            "lf%d*m?%s*melee",
            "lf%d*m?%s*caster",
        },
    },
}

-- ============================================================================
-- CLASS DETECTION KEYWORDS
-- ============================================================================

Parsers.ClassKeywords = {
    WARRIOR = {"warrior", "warr", "war", "arms", "fury"},
    PALADIN = {"paladin", "pala", "pally", "ret", "retri", "retribution"},
    HUNTER = {"hunter", "hunt", "mm", "marks", "bm", "sv", "survival"},
    ROGUE = {"rogue", "rog"},
    PRIEST = {"priest", "shadow", "spriest"},
    DEATHKNIGHT = {"dk", "death knight", "deathknight"},
    SHAMAN = {"shaman", "sham", "shammy", "ele", "elemental", "enh", "enhance"},
    MAGE = {"mage", "arcane", "fire", "frost mage"},
    WARLOCK = {"warlock", "lock", "affli", "demo", "destro"},
    DRUID = {"druid", "boomkin", "moonkin", "balance", "feral", "cat"},
}

-- ============================================================================
-- LFG/LFM DETECTION KEYWORDS
-- ============================================================================

Parsers.LFGKeywords = {
    "lfg",
    "lf raid",
    "lf group",
    "looking for group",
    "looking for raid",
    "lf icc",
    "lf toc",
    "lf voa",
    "lf ulduar",
    "want to join",
    "inv me",
    "invite me",
    "can i come",
    "need raid",
}

Parsers.LFMKeywords = {
    "lfm",
    "lf%dm",  -- lf1m, lf2m, etc.
    "need",
    "looking for more",
    "need healer",
    "need tank",
    "need dps",
    "recruiting",
    "spots open",
    "spots left",
    "still need",
    "/w for inv",
    "whisper for",
    "pst for",
}

-- ============================================================================
-- PARSING FUNCTIONS
-- ============================================================================

-- Parse GearScore from message
function Parsers.ParseGearScore(message)
    if not message then return nil end
    local msg = message:lower()

    for _, pattern in ipairs(Parsers.GSPatterns) do
        local gs = msg:match(pattern)
        if gs then
            -- Handle "5.8k" or "5,8k" format
            if gs:match("[%.,]") then
                gs = gs:gsub(",", ".")
                local num = tonumber(gs)
                if num and num < 100 then
                    return math.floor(num * 1000)
                end
            end
            -- Handle comma separator (5,800)
            return tonumber(gs:gsub(",", "")) or nil
        end
    end

    return nil
end

-- Detect raid from message (returns raid ID and category)
function Parsers.DetectRaid(message)
    if not message then return nil, nil end
    local msg = message:lower()

    for _, pattern in ipairs(Parsers.RaidPatterns) do
        if msg:match(pattern.pattern) then
            return pattern.raid, pattern.category
        end
    end

    return nil, nil
end

-- Detect all raids mentioned in message (returns table)
function Parsers.DetectAllRaids(message)
    if not message then return {} end
    local msg = message:lower()
    local raids = {}

    for _, pattern in ipairs(Parsers.RaidPatterns) do
        if msg:match(pattern.pattern) then
            raids[pattern.raid] = true
        end
    end

    -- Convert to list
    local result = {}
    for raid in pairs(raids) do
        table.insert(result, raid)
    end

    return result
end

-- Detect role from message
function Parsers.DetectRole(message)
    if not message then return nil end
    local msg = message:lower()

    for role, data in pairs(Parsers.RoleKeywords) do
        for _, keyword in ipairs(data.patterns) do
            if msg:find(keyword, 1, true) then
                return role:upper()
            end
        end
    end

    return nil
end

-- Detect class from message
function Parsers.DetectClass(message)
    if not message then return nil end
    local msg = message:lower()

    for class, keywords in pairs(Parsers.ClassKeywords) do
        for _, keyword in ipairs(keywords) do
            if msg:find(keyword, 1, true) then
                return class
            end
        end
    end

    return nil
end

-- Parse need count from "lf2m" style patterns
function Parsers.ParseNeedCount(message, role)
    if not message or not role then return 0 end
    local msg = message:lower()

    local roleData = Parsers.RoleKeywords[role:lower()]
    if not roleData then return 0 end

    for _, pattern in ipairs(roleData.lfmPatterns) do
        -- Check for number in pattern like "lf2m"
        local count = msg:match("lf(%d)m")
        if count and msg:match(pattern) then
            return tonumber(count) or 1
        end
        if msg:match(pattern) then
            -- Check for explicit numbers
            local numMatch = msg:match("need%s*(%d)%s*" .. role:lower())
            if numMatch then
                return tonumber(numMatch) or 1
            end
            return 1
        end
    end

    return 0
end

-- Check if message is LFG (player looking for group)
function Parsers.IsLFG(message)
    if not message then return false end
    local msg = message:lower()

    for _, keyword in ipairs(Parsers.LFGKeywords) do
        if msg:find(keyword, 1, true) then
            return true
        end
    end

    return false
end

-- Check if message is LFM (group looking for members)
function Parsers.IsLFM(message)
    if not message then return false end
    local msg = message:lower()

    for _, keyword in ipairs(Parsers.LFMKeywords) do
        if msg:find(keyword, 1, true) then
            return true
        end
    end

    -- Also check for "lf1m", "lf2m" patterns (one or more digits required)
    if msg:match("lf%d+m") then
        return true
    end

    return false
end

-- ============================================================================
-- UNIFIED CHAT MESSAGE PARSER
-- ============================================================================

-- Parse a chat message and return unified info structure
-- Parse Looking For specs from message format: [T:BD,BDK H:HPal,RS M:Ret,Rog R:Mag,Hun]
-- Returns: roleSpecs = {TANK = {codes}, HEALER = {codes}, MDPS = {codes}, RDPS = {codes}}
--          lookingForSpecs = flat array of all codes
function Parsers.ParseLookingFor(message)
    if not message then return nil, nil end

    local roleSpecs = {TANK = {}, HEALER = {}, MDPS = {}, RDPS = {}}
    local lookingForSpecs = {}

    -- Pattern to find [T:xxx H:xxx M:xxx R:xxx] section
    -- This section contains class/spec codes, NOT the slot counts [T:0/2 H:0/6 ...]
    -- Look for bracket sections that have letter codes after the role prefix
    local lfSection = message:match("%[T:[A-Za-z,]+[^%]]*%]")
    if not lfSection then
        -- Try alternate: might start with H, M, or R if no tanks
        lfSection = message:match("%[H:[A-Za-z,]+[^%]]*%]")
    end
    if not lfSection then
        lfSection = message:match("%[M:[A-Za-z,]+[^%]]*%]")
    end
    if not lfSection then
        lfSection = message:match("%[R:[A-Za-z,]+[^%]]*%]")
    end

    if not lfSection then return nil, nil end

    -- Parse each role section within the brackets
    -- T:BD,BDK,PP,PW
    local tankCodes = lfSection:match("T:([A-Za-z,]+)")
    if tankCodes then
        for code in tankCodes:gmatch("([A-Za-z]+)") do
            table.insert(roleSpecs.TANK, code)
            table.insert(lookingForSpecs, code)
        end
    end

    -- H:HPal,RS,HP,DP,RD
    local healerCodes = lfSection:match("H:([A-Za-z,]+)")
    if healerCodes then
        for code in healerCodes:gmatch("([A-Za-z]+)") do
            table.insert(roleSpecs.HEALER, code)
            table.insert(lookingForSpecs, code)
        end
    end

    -- M:Df,Ret,Rog,FD,WA,Enh (Melee DPS)
    local meleeCodes = lfSection:match("M:([A-Za-z,]+)")
    if meleeCodes then
        for code in meleeCodes:gmatch("([A-Za-z]+)") do
            table.insert(roleSpecs.MDPS, code)
            table.insert(lookingForSpecs, code)
        end
    end

    -- R:Mag,SP,Ele,Hun,Boom,Loc (Ranged DPS)
    local rangedCodes = lfSection:match("R:([A-Za-z,]+)")
    if rangedCodes then
        for code in rangedCodes:gmatch("([A-Za-z]+)") do
            table.insert(roleSpecs.RDPS, code)
            table.insert(lookingForSpecs, code)
        end
    end

    -- Return nil if nothing found
    local hasAny = #roleSpecs.TANK > 0 or #roleSpecs.HEALER > 0 or
                   #roleSpecs.MDPS > 0 or #roleSpecs.RDPS > 0
    if not hasAny then
        return nil, nil
    end

    return roleSpecs, lookingForSpecs
end

-- Class colors for display
Parsers.ClassColors = {
    WARRIOR = {r = 0.78, g = 0.61, b = 0.43, hex = "C79C6E"},
    PALADIN = {r = 0.96, g = 0.55, b = 0.73, hex = "F58CBA"},
    HUNTER = {r = 0.67, g = 0.83, b = 0.45, hex = "ABD473"},
    ROGUE = {r = 1.00, g = 0.96, b = 0.41, hex = "FFF569"},
    PRIEST = {r = 1.00, g = 1.00, b = 1.00, hex = "FFFFFF"},
    DEATHKNIGHT = {r = 0.77, g = 0.12, b = 0.23, hex = "C41F3B"},
    SHAMAN = {r = 0.00, g = 0.44, b = 0.87, hex = "0070DE"},
    MAGE = {r = 0.41, g = 0.80, b = 0.94, hex = "69CCF0"},
    WARLOCK = {r = 0.58, g = 0.51, b = 0.79, hex = "9482C9"},
    DRUID = {r = 1.00, g = 0.49, b = 0.04, hex = "FF7D0A"},
}

-- Comprehensive spec code mapping with class and spec info
Parsers.SpecCodeInfo = {
    -- Tanks
    BD   = {class = "DRUID", spec = "Feral (Bear)", shortClass = "Druid"},
    BDK  = {class = "DEATHKNIGHT", spec = "Blood", shortClass = "DK"},
    PP   = {class = "PALADIN", spec = "Protection", shortClass = "Paladin"},
    PW   = {class = "WARRIOR", spec = "Protection", shortClass = "Warrior"},
    -- Healers
    HPal = {class = "PALADIN", spec = "Holy", shortClass = "Paladin"},
    RS   = {class = "SHAMAN", spec = "Restoration", shortClass = "Shaman"},
    HP   = {class = "PRIEST", spec = "Holy", shortClass = "Priest"},
    DP   = {class = "PRIEST", spec = "Discipline", shortClass = "Priest"},
    RD   = {class = "DRUID", spec = "Restoration", shortClass = "Druid"},
    -- Melee DPS
    AW   = {class = "WARRIOR", spec = "Arms", shortClass = "Warrior"},
    FW   = {class = "WARRIOR", spec = "Fury", shortClass = "Warrior"},
    Ret  = {class = "PALADIN", spec = "Retribution", shortClass = "Paladin"},
    Rog  = {class = "ROGUE", spec = "Any", shortClass = "Rogue"},
    FD   = {class = "DRUID", spec = "Feral (Cat)", shortClass = "Druid"},
    Enh  = {class = "SHAMAN", spec = "Enhancement", shortClass = "Shaman"},
    FDK  = {class = "DEATHKNIGHT", spec = "Frost", shortClass = "DK"},
    UDK  = {class = "DEATHKNIGHT", spec = "Unholy", shortClass = "DK"},
    Df   = {class = "DEATHKNIGHT", spec = "DPS", shortClass = "DK"},
    DK   = {class = "DEATHKNIGHT", spec = "Any", shortClass = "DK"},
    -- Ranged DPS
    Mag  = {class = "MAGE", spec = "Any", shortClass = "Mage"},
    SP   = {class = "PRIEST", spec = "Shadow", shortClass = "Priest"},
    Ele  = {class = "SHAMAN", spec = "Elemental", shortClass = "Shaman"},
    Hun  = {class = "HUNTER", spec = "Any", shortClass = "Hunter"},
    Boom = {class = "DRUID", spec = "Balance", shortClass = "Druid"},
    Loc  = {class = "WARLOCK", spec = "Any", shortClass = "Warlock"},
    Aff  = {class = "WARLOCK", spec = "Affliction", shortClass = "Warlock"},
    Demo = {class = "WARLOCK", spec = "Demonology", shortClass = "Warlock"},
    Dest = {class = "WARLOCK", spec = "Destruction", shortClass = "Warlock"},
}

-- Get spec info for a code
function Parsers.GetSpecInfo(code)
    return Parsers.SpecCodeInfo[code]
end

-- Get class color for a class name
function Parsers.GetClassColor(className)
    return Parsers.ClassColors[className] or {r = 1, g = 1, b = 1, hex = "FFFFFF"}
end

-- Convert roleSpecs to a structured format grouped by class
-- Returns: {className = {specs = {spec1, spec2}, codes = {code1, code2}}, ...}
function Parsers.GroupSpecsByClass(roleSpecs)
    if not roleSpecs then return nil end

    local byClass = {}

    local function addSpec(code, role)
        local info = Parsers.SpecCodeInfo[code]
        if info then
            local className = info.class
            if not byClass[className] then
                byClass[className] = {
                    shortClass = info.shortClass,
                    specs = {},
                    codes = {},
                    roles = {},
                }
            end
            -- Avoid duplicate specs
            local found = false
            for _, existingSpec in ipairs(byClass[className].specs) do
                if existingSpec == info.spec then found = true break end
            end
            if not found then
                table.insert(byClass[className].specs, info.spec)
                table.insert(byClass[className].codes, code)
            end
            -- Track roles
            if role and not byClass[className].roles[role] then
                byClass[className].roles[role] = true
            end
        end
    end

    -- Process all roles
    if roleSpecs.TANK then
        for _, code in ipairs(roleSpecs.TANK) do addSpec(code, "TANK") end
    end
    if roleSpecs.HEALER then
        for _, code in ipairs(roleSpecs.HEALER) do addSpec(code, "HEALER") end
    end
    if roleSpecs.MDPS then
        for _, code in ipairs(roleSpecs.MDPS) do addSpec(code, "MDPS") end
    end
    if roleSpecs.RDPS then
        for _, code in ipairs(roleSpecs.RDPS) do addSpec(code, "RDPS") end
    end

    return byClass
end

-- Check if a player's class/spec matches the looking for requirements
-- playerClass: uppercase class name (e.g., "WARRIOR")
-- playerSpec: spec name or nil
-- playerRole: "TANK", "HEALER", "MDPS", "RDPS", or "DPS"
-- roleSpecs: the group's roleSpecs table
function Parsers.MatchesLookingFor(playerClass, playerSpec, playerRole, roleSpecs)
    if not roleSpecs then return true end  -- No requirements = anyone welcome

    -- Normalize role
    local rolesToCheck = {}
    if playerRole == "TANK" then
        rolesToCheck = {"TANK"}
    elseif playerRole == "HEALER" then
        rolesToCheck = {"HEALER"}
    elseif playerRole == "DPS" or playerRole == "MDPS" or playerRole == "RDPS" then
        rolesToCheck = {"MDPS", "RDPS"}  -- Check both DPS types
    else
        rolesToCheck = {"TANK", "HEALER", "MDPS", "RDPS"}  -- Check all
    end

    -- Check if player's class matches any of the wanted specs in applicable roles
    for _, role in ipairs(rolesToCheck) do
        local specs = roleSpecs[role]
        if specs then
            for _, code in ipairs(specs) do
                local info = Parsers.SpecCodeInfo[code]
                if info and info.class == playerClass then
                    return true  -- Class matches
                end
            end
        end
    end

    -- If no roleSpecs defined for checked roles, allow
    local hasAnyRequirements = false
    for _, role in ipairs(rolesToCheck) do
        if roleSpecs[role] and #roleSpecs[role] > 0 then
            hasAnyRequirements = true
            break
        end
    end

    return not hasAnyRequirements  -- No requirements for this role = allowed
end

function Parsers.ParseChatMessage(message, author, channel)
    if not message or not author then return nil end

    local info = {
        author = author,
        message = message,
        channel = channel,
        time = time(),

        -- Message type
        isLFG = Parsers.IsLFG(message),
        isLFM = Parsers.IsLFM(message),

        -- Detected content
        raid = nil,
        raidCategory = nil,
        raids = {},
        role = nil,
        class = nil,
        gs = nil,

        -- Role composition needs (for LFM)
        composition = {
            tanks = {needed = 0},
            healers = {needed = 0},
            dps = {needed = 0},
        },

        -- Looking for specs (parsed from [T:BD,BDK H:HPal M:Ret R:Mag] format)
        roleSpecs = nil,
        lookingForSpecs = nil,
    }

    -- Detect raids
    info.raid, info.raidCategory = Parsers.DetectRaid(message)
    info.raids = Parsers.DetectAllRaids(message)

    -- Detect role and class
    info.role = Parsers.DetectRole(message)
    info.class = Parsers.DetectClass(message)

    -- Detect GearScore
    info.gs = Parsers.ParseGearScore(message)

    -- If LFM, parse composition needs and looking for specs
    if info.isLFM then
        info.composition.tanks.needed = Parsers.ParseNeedCount(message, "tank")
        info.composition.healers.needed = Parsers.ParseNeedCount(message, "healer")
        info.composition.dps.needed = Parsers.ParseNeedCount(message, "dps")

        -- If no specific needs detected but it's LFM, assume general
        if info.composition.tanks.needed == 0 and
           info.composition.healers.needed == 0 and
           info.composition.dps.needed == 0 then
            info.composition.dps.needed = 1  -- Assume at least 1 spot
        end

        -- Parse looking for specs (class/spec preferences)
        info.roleSpecs, info.lookingForSpecs = Parsers.ParseLookingFor(message)
    end

    -- Only return if it's a relevant message (has raid or is LFG/LFM)
    if info.raid or info.isLFG or info.isLFM then
        return info
    end

    return nil
end

-- ============================================================================
-- RAID HIERARCHY (for UI organization)
-- ============================================================================

Parsers.RaidHierarchy = {
    {
        id = "ICC",
        name = "Icecrown Citadel",
        shortName = "ICC",
        children = {
            {id = "ICC10N", name = "ICC 10 Normal", size = 10, heroic = false},
            {id = "ICC10H", name = "ICC 10 Heroic", size = 10, heroic = true},
            {id = "ICC25N", name = "ICC 25 Normal", size = 25, heroic = false},
            {id = "ICC25H", name = "ICC 25 Heroic", size = 25, heroic = true},
        },
    },
    {
        id = "RS",
        name = "Ruby Sanctum",
        shortName = "RS",
        children = {
            {id = "RS10N", name = "RS 10 Normal", size = 10, heroic = false},
            {id = "RS10H", name = "RS 10 Heroic", size = 10, heroic = true},
            {id = "RS25N", name = "RS 25 Normal", size = 25, heroic = false},
            {id = "RS25H", name = "RS 25 Heroic", size = 25, heroic = true},
        },
    },
    {
        id = "TOC",
        name = "Trial of Crusader",
        shortName = "TOC",
        children = {
            {id = "TOC10", name = "TOC 10", size = 10, heroic = false},
            {id = "TOGC10", name = "TOGC 10 (Heroic)", size = 10, heroic = true},
            {id = "TOC25", name = "TOC 25", size = 25, heroic = false},
            {id = "TOGC25", name = "TOGC 25 (Heroic)", size = 25, heroic = true},
        },
    },
    {
        id = "ULDUAR",
        name = "Ulduar",
        shortName = "ULD",
        children = {
            {id = "ULDUAR10", name = "Ulduar 10", size = 10, heroic = false},
            {id = "ULDUAR25", name = "Ulduar 25", size = 25, heroic = false},
        },
    },
    {
        id = "NAXX",
        name = "Naxxramas",
        shortName = "NAXX",
        children = {
            {id = "NAXX10", name = "Naxx 10", size = 10, heroic = false},
            {id = "NAXX25", name = "Naxx 25", size = 25, heroic = false},
        },
    },
    {
        id = "VOA",
        name = "Vault of Archavon",
        shortName = "VOA",
        children = {
            {id = "VOA10", name = "VOA 10", size = 10, heroic = false},
            {id = "VOA25", name = "VOA 25", size = 25, heroic = false},
        },
    },
    {
        id = "ONYXIA",
        name = "Onyxia's Lair",
        shortName = "ONY",
        children = {
            {id = "ONYXIA10", name = "Onyxia 10", size = 10, heroic = false},
            {id = "ONYXIA25", name = "Onyxia 25", size = 25, heroic = false},
        },
    },
    {
        id = "OS",
        name = "Obsidian Sanctum",
        shortName = "OS",
        children = {
            {id = "OS10", name = "OS 10", size = 10, heroic = false},
            {id = "OS25", name = "OS 25", size = 25, heroic = false},
        },
    },
    {
        id = "EOE",
        name = "Eye of Eternity",
        shortName = "EOE",
        children = {
            {id = "EOE10", name = "EoE 10", size = 10, heroic = false},
            {id = "EOE25", name = "EoE 25", size = 25, heroic = false},
        },
    },
}

-- Get parent category for a raid ID
function Parsers.GetRaidCategory(raidId)
    if not raidId then return nil end

    for _, category in ipairs(Parsers.RaidHierarchy) do
        if raidId == category.id then
            return category.id
        end
        for _, child in ipairs(category.children) do
            if raidId == child.id then
                return category.id
            end
        end
    end

    -- Try matching by prefix
    for _, category in ipairs(Parsers.RaidHierarchy) do
        if raidId:find("^" .. category.id) then
            return category.id
        end
    end

    return nil
end

-- Get raid display name
function Parsers.GetRaidName(raidId)
    if not raidId then return "Unknown" end

    for _, category in ipairs(Parsers.RaidHierarchy) do
        if raidId == category.id then
            return category.name
        end
        for _, child in ipairs(category.children) do
            if raidId == child.id then
                return child.name
            end
        end
    end

    return raidId
end
