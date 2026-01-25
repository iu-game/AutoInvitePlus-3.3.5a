-- AutoInvite Plus - Group Tracker Module
-- Tracks LFM groups (leaders advertising for members)

local AIP = AutoInvitePlus
AIP.GroupTracker = {}
local GT = AIP.GroupTracker

-- Configuration
GT.Config = {
    enabled = true,
    maxEntries = 100,
    expiryTime = 900, -- 15 minutes
}

-- Group database: tracks LFM group leaders and their needs
GT.Groups = {}

-- Raid hierarchy structure for tree view
GT.RaidHierarchy = {
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

-- Raid detection patterns (more specific for LFM vs LFG distinction)
GT.RaidPatterns = {
    -- ICC patterns
    {pattern = "icc%s*25%s*h", raid = "ICC25H"},
    {pattern = "icc%s*25%s*hc", raid = "ICC25H"},
    {pattern = "icc%s*25%s*heroic", raid = "ICC25H"},
    {pattern = "icc%s*10%s*h", raid = "ICC10H"},
    {pattern = "icc%s*10%s*hc", raid = "ICC10H"},
    {pattern = "icc%s*10%s*heroic", raid = "ICC10H"},
    {pattern = "icc%s*25%s*n", raid = "ICC25N"},
    {pattern = "icc%s*25%s*normal", raid = "ICC25N"},
    {pattern = "icc%s*10%s*n", raid = "ICC10N"},
    {pattern = "icc%s*10%s*normal", raid = "ICC10N"},
    {pattern = "icc%s*25", raid = "ICC25N"},
    {pattern = "icc%s*10", raid = "ICC10N"},
    {pattern = "icc", raid = "ICC"},
    {pattern = "icecrown", raid = "ICC"},

    -- RS patterns
    {pattern = "rs%s*25%s*h", raid = "RS25H"},
    {pattern = "rs%s*10%s*h", raid = "RS10H"},
    {pattern = "rs%s*25", raid = "RS25N"},
    {pattern = "rs%s*10", raid = "RS10N"},
    {pattern = "ruby%s*sanctum", raid = "RS"},
    {pattern = "halion", raid = "RS"},

    -- TOC patterns
    {pattern = "togc%s*25", raid = "TOGC25"},
    {pattern = "togc%s*10", raid = "TOGC10"},
    {pattern = "toc%s*25%s*h", raid = "TOGC25"},
    {pattern = "toc%s*10%s*h", raid = "TOGC10"},
    {pattern = "toc%s*25", raid = "TOC25"},
    {pattern = "toc%s*10", raid = "TOC10"},
    {pattern = "trial%s*of%s*crusader", raid = "TOC"},
    {pattern = "trial%s*of%s*the%s*crusader", raid = "TOC"},

    -- Ulduar
    {pattern = "uld%s*25", raid = "ULDUAR25"},
    {pattern = "uld%s*10", raid = "ULDUAR10"},
    {pattern = "ulduar%s*25", raid = "ULDUAR25"},
    {pattern = "ulduar%s*10", raid = "ULDUAR10"},
    {pattern = "ulduar", raid = "ULDUAR"},

    -- Naxx
    {pattern = "naxx%s*25", raid = "NAXX25"},
    {pattern = "naxx%s*10", raid = "NAXX10"},
    {pattern = "naxxramas", raid = "NAXX"},

    -- VOA
    {pattern = "voa%s*25", raid = "VOA25"},
    {pattern = "voa%s*10", raid = "VOA10"},
    {pattern = "voa", raid = "VOA"},
    {pattern = "vault%s*of%s*archavon", raid = "VOA"},
    {pattern = "archavon", raid = "VOA"},

    -- Onyxia
    {pattern = "ony%s*25", raid = "ONYXIA25"},
    {pattern = "ony%s*10", raid = "ONYXIA10"},
    {pattern = "onyxia", raid = "ONYXIA"},

    -- OS
    {pattern = "os%s*3d", raid = "OS"},
    {pattern = "os%s*25", raid = "OS25"},
    {pattern = "os%s*10", raid = "OS10"},
    {pattern = "obsidian%s*sanctum", raid = "OS"},
    {pattern = "sarth", raid = "OS"},

    -- EoE
    {pattern = "eoe%s*25", raid = "EOE25"},
    {pattern = "eoe%s*10", raid = "EOE10"},
    {pattern = "malygos", raid = "EOE"},
}

-- Composition need patterns
GT.NeedPatterns = {
    tanks = {
        "lf%d*m?%s*tank",
        "need%s*%d*%s*tank",
        "need%s*mt",
        "need%s*ot",
        "looking%s*for%s*tank",
    },
    healers = {
        "lf%d*m?%s*heal",
        "need%s*%d*%s*heal",
        "looking%s*for%s*heal",
        "lf%d*m?%s*resto",
        "lf%d*m?%s*holy",
        "lf%d*m?%s*disc",
    },
    dps = {
        "lf%d*m?%s*dps",
        "need%s*%d*%s*dps",
        "looking%s*for%s*dps",
        "lf%d*m?%s*ranged",
        "lf%d*m?%s*melee",
        "lf%d*m?%s*caster",
    },
}

-- GS requirement patterns
GT.GSPatterns = {
    "(%d%d%d%d)%+?%s*gs",
    "gs%s*(%d%d%d%d)%+?",
    "(%d%d%d%d)%+?%s*gearscore",
    "gearscore%s*(%d%d%d%d)%+?",
    "min%s*gs%s*(%d%d%d%d)",
    "(%d[%.,]?%d)k%s*gs",
    "gs%s*(%d[%.,]?%d)k",
}

-- Parse count from "lf2m" style patterns
local function ParseNeedCount(message, role)
    local patterns = GT.NeedPatterns[role]
    if not patterns then return 0 end

    for _, pattern in ipairs(patterns) do
        -- Check for number in pattern like "lf2m"
        local count = message:match("lf(%d)m")
        if count and message:match(pattern) then
            return tonumber(count) or 1
        end
        if message:match(pattern) then
            -- Check for explicit numbers
            local numMatch = message:match("need%s*(%d)%s*" .. role)
            if numMatch then
                return tonumber(numMatch) or 1
            end
            return 1
        end
    end
    return 0
end

-- Parse GS requirement (handle "5.8k" and "5800" formats)
local function ParseGSRequirement(message)
    for _, pattern in ipairs(GT.GSPatterns) do
        local gs = message:match(pattern)
        if gs then
            -- Handle "5.8k" or "5,8k" format
            if gs:match("[%.,]") then
                gs = gs:gsub(",", ".")
                local num = tonumber(gs)
                if num and num < 100 then
                    return math.floor(num * 1000)
                end
            end
            return tonumber(gs:gsub(",", ""))
        end
    end
    return nil
end

-- Detect raid from message
local function DetectRaid(message)
    local msg = message:lower()
    for _, pattern in ipairs(GT.RaidPatterns) do
        if msg:match(pattern.pattern) then
            return pattern.raid
        end
    end
    return nil
end

-- Parse LFM message for group info
function GT.ParseLFMMessage(message, leader, channel)
    local msg = message:lower()

    -- Detect raids
    local raid = DetectRaid(msg)
    if not raid then return nil end

    local info = {
        leader = leader,
        raid = raid,
        composition = {
            tanks = {current = 0, needed = ParseNeedCount(msg, "tanks")},
            healers = {current = 0, needed = ParseNeedCount(msg, "healers")},
            dps = {current = 0, needed = ParseNeedCount(msg, "dps")},
        },
        gsRequirement = ParseGSRequirement(msg),
        message = message,
        channel = channel,
        time = time(),
        isGroup = true,
    }

    -- If no specific needs detected, assume general LFM
    if info.composition.tanks.needed == 0 and
       info.composition.healers.needed == 0 and
       info.composition.dps.needed == 0 then
        -- Check for general "lfm" or "lf more"
        if msg:match("lfm") or msg:match("lf%s*more") or msg:match("looking%s*for%s*more") then
            info.composition.dps.needed = 1  -- Assume at least 1 spot
        else
            return nil  -- Not an LFM message
        end
    end

    return info
end

-- Add or update group in database
function GT.AddGroup(info)
    if not info or not info.leader then return end

    -- Mark if this is the player's own listing
    local isOwnListing = (info.leader == UnitName("player"))
    if isOwnListing then
        info.isOwn = true
    end

    local existing = GT.Groups[info.leader]
    if existing then
        -- Update existing entry
        existing.raid = info.raid
        existing.composition = info.composition or existing.composition
        existing.gsRequirement = info.gsRequirement or existing.gsRequirement
        existing.gsMin = info.gsMin or existing.gsMin
        existing.ilvlMin = info.ilvlMin or existing.ilvlMin
        existing.message = info.message
        existing.time = info.time
        existing.isOwn = info.isOwn or existing.isOwn
        existing.tanks = info.tanks or existing.tanks
        existing.healers = info.healers or existing.healers
        existing.dps = info.dps or existing.dps
    else
        GT.Groups[info.leader] = info
        GT.PruneOldEntries()
    end

    -- Notify UI
    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end

    -- Also refresh the browser tab
    if AIP.CentralGUI and AIP.CentralGUI.RefreshBrowserTab then
        AIP.CentralGUI.RefreshBrowserTab("lfm")
    end
end

-- Remove expired entries
function GT.PruneOldEntries()
    local now = time()
    local expiry = GT.Config.expiryTime

    for leader, info in pairs(GT.Groups) do
        if now - info.time > expiry then
            GT.Groups[leader] = nil
        end
    end

    -- Limit total entries
    local count = 0
    local oldest = nil
    local oldestTime = now

    for leader, info in pairs(GT.Groups) do
        count = count + 1
        if info.time < oldestTime then
            oldestTime = info.time
            oldest = leader
        end
    end

    if count > GT.Config.maxEntries and oldest then
        GT.Groups[oldest] = nil
    end
end

-- Get groups filtered and organized by raid hierarchy
function GT.GetGroupsByRaid(filters)
    filters = filters or {}
    local results = {}
    local now = time()

    -- Initialize raid categories
    for _, raidCategory in ipairs(GT.RaidHierarchy) do
        results[raidCategory.id] = {
            category = raidCategory,
            children = {},
        }
        for _, child in ipairs(raidCategory.children) do
            results[raidCategory.id].children[child.id] = {
                raid = child,
                groups = {},
                count = 0,
            }
        end
    end

    -- Distribute groups into categories
    for leader, info in pairs(GT.Groups) do
        local include = true

        -- Apply filters
        if filters.minGS and (not info.gsRequirement or info.gsRequirement > filters.minGS) then
            include = false
        end

        if filters.search and filters.search ~= "" then
            local searchLower = filters.search:lower()
            if not info.leader:lower():find(searchLower, 1, true) and
               not info.message:lower():find(searchLower, 1, true) then
                include = false
            end
        end

        if include then
            info.age = now - info.time

            -- Find the right category
            for catId, catData in pairs(results) do
                if info.raid == catId or info.raid:find("^" .. catId) then
                    -- Find specific raid size/mode
                    for childId, childData in pairs(catData.children) do
                        if info.raid == childId then
                            table.insert(childData.groups, info)
                            childData.count = childData.count + 1
                            break
                        end
                    end
                    -- If no specific match, add to first matching category
                    if info.raid == catId then
                        local firstChild = catData.children[catData.category.children[1].id]
                        if firstChild then
                            table.insert(firstChild.groups, info)
                            firstChild.count = firstChild.count + 1
                        end
                    end
                    break
                end
            end
        end
    end

    return results
end

-- Get flat list of all groups
function GT.GetAllGroups(filters)
    filters = filters or {}
    local results = {}
    local now = time()

    for leader, info in pairs(GT.Groups) do
        local include = true

        if filters.raid and info.raid ~= filters.raid then
            include = false
        end

        if filters.minGS and info.gsRequirement and info.gsRequirement > filters.minGS then
            include = false
        end

        if filters.search and filters.search ~= "" then
            local searchLower = filters.search:lower()
            if not info.leader:lower():find(searchLower, 1, true) and
               not info.message:lower():find(searchLower, 1, true) then
                include = false
            end
        end

        if include then
            info.age = now - info.time
            table.insert(results, info)
        end
    end

    -- Sort by time (most recent first)
    table.sort(results, function(a, b)
        return a.time > b.time
    end)

    return results
end

-- Get group count
function GT.GetGroupCount()
    local count = 0
    for _ in pairs(GT.Groups) do
        count = count + 1
    end
    return count
end

-- Get counts per raid
function GT.GetCountsByRaid()
    local counts = {}

    for _, raidCategory in ipairs(GT.RaidHierarchy) do
        counts[raidCategory.id] = 0
        for _, child in ipairs(raidCategory.children) do
            counts[child.id] = 0
        end
    end

    for leader, info in pairs(GT.Groups) do
        if counts[info.raid] then
            counts[info.raid] = counts[info.raid] + 1
        end
        -- Also count parent category
        for _, cat in ipairs(GT.RaidHierarchy) do
            if info.raid:find("^" .. cat.id) then
                counts[cat.id] = counts[cat.id] + 1
                break
            end
        end
    end

    return counts
end

-- Clear all groups
function GT.ClearAll()
    GT.Groups = {}
    if AIP.UpdateCentralGUI then
        AIP.UpdateCentralGUI()
    end
    AIP.Print("Group tracker cleared")
end

-- Alias for ClearAll (used by LFM panel)
GT.ClearAllGroups = GT.ClearAll

-- Format time ago string
function GT.FormatTimeAgo(seconds)
    if seconds < 60 then
        return seconds .. "s"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m"
    else
        return math.floor(seconds / 3600) .. "h"
    end
end

-- Periodic cleanup
local cleanupFrame = CreateFrame("Frame")
local cleanupElapsed = 0
cleanupFrame:SetScript("OnUpdate", function(self, elapsed)
    cleanupElapsed = cleanupElapsed + elapsed
    if cleanupElapsed > 60 then
        cleanupElapsed = 0
        GT.PruneOldEntries()
    end
end)
