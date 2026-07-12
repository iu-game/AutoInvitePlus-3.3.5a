-- AutoInvite Plus - Weekly Raid Quests (WotLK 3.3.5a)
-- The rotating weekly raid quest from Archmage Lan'dalock (Dalaran).
--
-- 3.3.5a has NO quest IDs in GetQuestLogTitle, so detection is by TITLE
-- string match (same name-guarded philosophy as BiSData). The `token` is the
-- single-word tag that rides in LFM/LFG chat messages as "WQ:<token>" -
-- camel case, no spaces or apostrophes, so it survives %S+ tokenization.
-- Raid keys use the GUI casing (EoE, not the Composition table's EOE).

local AIP = AutoInvitePlus
AIP.Weekly = AIP.Weekly or {}
local W = AIP.Weekly

W.Quests = {
    { title = "Lord Marrowgar Must Die!",              token = "Marrowgar",      raid = "ICC",    boss = "Lord Marrowgar" },
    { title = "Lord Jaraxxus Must Die!",               token = "Jaraxxus",       raid = "TOC",    boss = "Lord Jaraxxus" },
    { title = "Flame Leviathan Must Die!",             token = "FlameLeviathan", raid = "ULDUAR", boss = "Flame Leviathan" },
    { title = "Ignis the Furnace Master Must Die!",    token = "Ignis",          raid = "ULDUAR", boss = "Ignis the Furnace Master" },
    { title = "Razorscale Must Die!",                  token = "Razorscale",     raid = "ULDUAR", boss = "Razorscale" },
    { title = "XT-002 Deconstructor Must Die!",        token = "XT002",          raid = "ULDUAR", boss = "XT-002 Deconstructor" },
    { title = "Anub'Rekhan Must Die!",                 token = "AnubRekhan",     raid = "NAXX",   boss = "Anub'Rekhan" },
    { title = "Instructor Razuvious Must Die!",        token = "Razuvious",      raid = "NAXX",   boss = "Instructor Razuvious" },
    { title = "Noth the Plaguebringer Must Die!",      token = "Noth",           raid = "NAXX",   boss = "Noth the Plaguebringer" },
    { title = "Patchwerk Must Die!",                   token = "Patchwerk",      raid = "NAXX",   boss = "Patchwerk" },
    { title = "Malygos Must Die!",                     token = "Malygos",        raid = "EoE",    boss = "Malygos" },
    { title = "Sartharion Must Die!",                  token = "Sartharion",     raid = "OS",     boss = "Sartharion" },
}

-- Fast lookups
W.ByToken = {}
W.ByTitle = {}
for _, q in ipairs(W.Quests) do
    W.ByToken[q.token:lower()] = q
    W.ByTitle[q.title] = q
end

-- Test hook: /aip testdata sets this so weekly badges render without a real
-- quest log entry (fixtures cannot inject quests into the client).
W.testActive = nil  -- set to a token string, e.g. "Marrowgar"

-- ============================================================================
-- QUEST LOG DETECTION
-- ============================================================================

local cache = nil          -- {quest = <entry>, complete = bool} or false (scanned, none held)

local function scanQuestLog()
    local numEntries = GetNumQuestLogEntries and GetNumQuestLogEntries() or 0
    for i = 1, numEntries do
        -- 3.3.5a returns: title, level, questTag, suggestedGroup, isHeader,
        -- isCollapsed, isComplete, isDaily  (no quest ID on this client)
        local title, _, _, _, isHeader, _, isComplete = GetQuestLogTitle(i)
        if not isHeader and title then
            local q = W.ByTitle[title]
            if q then
                return { quest = q, complete = (isComplete and isComplete > 0) and true or false }
            end
        end
    end
    return false
end

-- Returns { quest = {title, token, raid, boss}, complete = bool } for the
-- weekly quest currently in the player's quest log, or nil if they don't
-- hold one (either not picked up, or a different reset week).
function W.Current()
    if W.testActive then
        local q = W.ByToken[W.testActive:lower()]
        if q then return { quest = q, complete = false } end
    end
    if cache == nil then
        cache = scanQuestLog()
    end
    if cache == false then return nil end
    return cache
end

function W.Invalidate()
    cache = nil
end

-- Resolve a chat token ("WQ:Marrowgar" carries "Marrowgar") to its quest entry
function W.ForToken(token)
    if not token then return nil end
    return W.ByToken[token:lower()]
end

-- Human status line for the popups' weekly strip.
-- targetToken: which weekly a listing is for (defaults to whatever is current)
function W.StatusText(targetToken)
    local held = W.Current()
    if targetToken then
        local q = W.ForToken(targetToken)
        if not q then return "|cFF888888Unknown weekly|r" end
        if held and held.quest.token == q.token then
            if held.complete then
                return "|cFF00FF00Complete - turn it in to Archmage Lan'dalock|r"
            end
            return "|cFF00FF00You have this quest|r"
        end
        return "|cFFFFAA00You don't have this quest - Archmage Lan'dalock, Dalaran|r"
    end
    if not held then
        return "|cFF888888No weekly raid quest in your log - pick it up in Dalaran|r"
    end
    local status = held.complete and "|cFF00FF00complete|r" or "|cFFFFAA00in progress|r"
    return string.format("This week: |cFF33CCFF%s|r (%s, %s)", held.quest.boss, held.quest.raid, status)
end

-- Is this listing's weekly still useful to ME? (drives badge coloring)
function W.IsWanted(token)
    local held = W.Current()
    if not held then return false end       -- can't tell / not holding it
    if held.quest.token:lower() ~= (token or ""):lower() then return false end
    return not held.complete
end

-- ============================================================================
-- EVENTS
-- ============================================================================

if AIP.Utils and AIP.Utils.Events then
    AIP.Utils.Events.Register("QUEST_LOG_UPDATE", function() W.Invalidate() end, W)
    AIP.Utils.Events.Register("PLAYER_ENTERING_WORLD", function() W.Invalidate() end, W)
end
