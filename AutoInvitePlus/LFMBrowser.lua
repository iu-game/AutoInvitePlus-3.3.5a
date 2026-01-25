-- AutoInvite Plus - LFM Browser Module
-- Scans chat for players looking for groups

local AIP = AutoInvitePlus
AIP.LFMBrowser = {}
local LFM = AIP.LFMBrowser

-- Configuration
LFM.Config = {
    enabled = true,
    maxEntries = 200,           -- Max players to track
    expiryTime = 600,           -- 10 minutes until entry expires
    scanChannels = {
        CHAT_MSG_CHANNEL = true,
        CHAT_MSG_SAY = true,
        CHAT_MSG_YELL = true,
    },
}

-- Player database: {name = {class, role, spec, gs, message, time, channel, raids}}
LFM.Players = {}

-- Keywords to detect LFG messages
LFM.Keywords = {
    lfg = {"lfg", "lf raid", "lf group", "looking for group", "looking for raid", "lf icc", "lf toc", "lf voa"},
    lfm = {"lfm", "lf1m", "lf2m", "lf3m", "lf4m", "lf5m", "need", "looking for more", "need healer", "need tank", "need dps"},
}

-- Raid keywords for detection
LFM.RaidKeywords = {
    ["icc"] = "ICC", ["icecrown"] = "ICC",
    ["icc10"] = "ICC10", ["icc25"] = "ICC25",
    ["icc 10"] = "ICC10", ["icc 25"] = "ICC25",
    ["toc"] = "TOC", ["trial"] = "TOC", ["totc"] = "TOC",
    ["toc10"] = "TOC10", ["toc25"] = "TOC25",
    ["togc"] = "TOGC", ["togc10"] = "TOGC10", ["togc25"] = "TOGC25",
    ["ulduar"] = "ULDUAR", ["uld"] = "ULDUAR",
    ["naxx"] = "NAXX", ["naxxramas"] = "NAXX",
    ["voa"] = "VOA", ["vault"] = "VOA", ["archavon"] = "VOA",
    ["onyxia"] = "ONYXIA", ["ony"] = "ONYXIA",
    ["rs"] = "RS", ["ruby"] = "RS", ["sanctum"] = "RS", ["halion"] = "RS",
    ["os"] = "OS", ["sarth"] = "OS", ["obsidian"] = "OS",
    ["eoe"] = "EOE", ["malygos"] = "EOE",
}

-- Role keywords
LFM.RoleKeywords = {
    tank = {"tank", "mt", "ot", "prot", "protection", "bear", "feral tank"},
    healer = {"healer", "heal", "resto", "restoration", "holy", "disc", "discipline", "tree"},
    dps = {"dps", "damage", "dd", "ranged", "melee", "rdps", "mdps", "caster"},
}

-- Class keywords
LFM.ClassKeywords = {
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

-- GearScore patterns
LFM.GSPatterns = {
    "(%d%d%d%d)%+?%s*gs",
    "gs%s*(%d%d%d%d)",
    "gearscore%s*(%d%d%d%d)",
    "(%d%d%d%d)%+?%s*gearscore",
    "(%d[%d,]+)%s*gs",
}

-- Parse a chat message for player info
function LFM.ParseMessage(message, author, channel)
    local msg = message:lower()
    local info = {
        name = author,
        message = message,
        time = time(),
        channel = channel,
        raids = {},
        role = nil,
        class = nil,
        gs = nil,
        isLFG = false,
        isLFM = false,
    }

    -- Check if it's an LFG or LFM message
    for _, keyword in ipairs(LFM.Keywords.lfg) do
        if msg:find(keyword, 1, true) then
            info.isLFG = true
            break
        end
    end

    for _, keyword in ipairs(LFM.Keywords.lfm) do
        if msg:find(keyword, 1, true) then
            info.isLFM = true
            break
        end
    end

    -- Only process if it's an LFG/LFM message
    if not info.isLFG and not info.isLFM then
        return nil
    end

    -- Detect raids mentioned
    for keyword, raid in pairs(LFM.RaidKeywords) do
        if msg:find(keyword, 1, true) then
            info.raids[raid] = true
        end
    end

    -- Detect role
    for role, keywords in pairs(LFM.RoleKeywords) do
        for _, keyword in ipairs(keywords) do
            if msg:find(keyword, 1, true) then
                info.role = role:upper()
                break
            end
        end
        if info.role then break end
    end

    -- Detect class
    for class, keywords in pairs(LFM.ClassKeywords) do
        for _, keyword in ipairs(keywords) do
            if msg:find(keyword, 1, true) then
                info.class = class
                break
            end
        end
        if info.class then break end
    end

    -- Detect GearScore
    for _, pattern in ipairs(LFM.GSPatterns) do
        local gs = msg:match(pattern)
        if gs then
            gs = gs:gsub(",", "")
            info.gs = tonumber(gs)
            break
        end
    end

    -- Convert raids table to list
    local raidList = {}
    for raid in pairs(info.raids) do
        table.insert(raidList, raid)
    end
    info.raids = raidList

    return info
end

-- Add or update player in database
function LFM.AddPlayer(info)
    if not info or not info.name then return end

    -- Don't track self
    if info.name == UnitName("player") then return end

    -- Check if player already exists
    local existing = LFM.Players[info.name]
    if existing then
        -- Update existing entry
        existing.message = info.message
        existing.time = info.time
        existing.channel = info.channel

        -- Merge raids
        for _, raid in ipairs(info.raids) do
            local found = false
            for _, existingRaid in ipairs(existing.raids) do
                if existingRaid == raid then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(existing.raids, raid)
            end
        end

        -- Update role/class/gs if newly detected
        if info.role then existing.role = info.role end
        if info.class then existing.class = info.class end
        if info.gs then existing.gs = info.gs end
        existing.isLFG = info.isLFG or existing.isLFG
        existing.isLFM = info.isLFM or existing.isLFM
    else
        -- Add new entry
        LFM.Players[info.name] = info

        -- Check if we need to prune old entries
        LFM.PruneOldEntries()
    end

    -- Update UI if open
    if AIP.UpdateLFMBrowserUI then
        AIP.UpdateLFMBrowserUI()
    end
end

-- Remove expired entries
function LFM.PruneOldEntries()
    local now = time()
    local expiry = LFM.Config.expiryTime

    for name, info in pairs(LFM.Players) do
        if now - info.time > expiry then
            LFM.Players[name] = nil
        end
    end

    -- Also limit total entries
    local count = 0
    local oldest = nil
    local oldestTime = now

    for name, info in pairs(LFM.Players) do
        count = count + 1
        if info.time < oldestTime then
            oldestTime = info.time
            oldest = name
        end
    end

    if count > LFM.Config.maxEntries and oldest then
        LFM.Players[oldest] = nil
    end
end

-- Get filtered player list
function LFM.GetFilteredPlayers(filters)
    filters = filters or {}
    local results = {}
    local now = time()

    for name, info in pairs(LFM.Players) do
        local include = true

        -- Filter by type (LFG only, LFM only, or both)
        if filters.lfgOnly and not info.isLFG then
            include = false
        end
        if filters.lfmOnly and not info.isLFM then
            include = false
        end

        -- Filter by role
        if filters.role and info.role ~= filters.role then
            include = false
        end

        -- Filter by class
        if filters.class and info.class ~= filters.class then
            include = false
        end

        -- Filter by raid
        if filters.raid then
            local hasRaid = false
            for _, raid in ipairs(info.raids) do
                if raid:find(filters.raid) then
                    hasRaid = true
                    break
                end
            end
            if not hasRaid then
                include = false
            end
        end

        -- Filter by minimum GearScore
        if filters.minGS and (not info.gs or info.gs < filters.minGS) then
            include = false
        end

        -- Filter by text search
        if filters.search and filters.search ~= "" then
            local searchLower = filters.search:lower()
            if not info.name:lower():find(searchLower, 1, true) and
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

-- Get player count
function LFM.GetPlayerCount()
    local count = 0
    for _ in pairs(LFM.Players) do
        count = count + 1
    end
    return count
end

-- Clear all players
function LFM.ClearAll()
    LFM.Players = {}
    if AIP.UpdateLFMBrowserUI then
        AIP.UpdateLFMBrowserUI()
    end
    AIP.Print("LFM Browser cleared")
end

-- Ignore a player (add to blacklist)
function LFM.IgnorePlayer(name)
    if name then
        LFM.Players[name] = nil
        AIP.AddToBlacklist(name)
        if AIP.UpdateLFMBrowserUI then
            AIP.UpdateLFMBrowserUI()
        end
    end
end

-- Invite a player from LFM browser
function LFM.InvitePlayer(name)
    if name and LFM.Players[name] then
        AIP.InvitePlayer(name)
        -- Keep in browser but mark as invited
        LFM.Players[name].invited = true
        if AIP.UpdateLFMBrowserUI then
            AIP.UpdateLFMBrowserUI()
        end
    end
end

-- Format time ago string
function LFM.FormatTimeAgo(seconds)
    if seconds < 60 then
        return seconds .. "s ago"
    elseif seconds < 3600 then
        return math.floor(seconds / 60) .. "m ago"
    else
        return math.floor(seconds / 3600) .. "h ago"
    end
end

-- Chat event handler
local function OnChatMessage(self, event, message, author, ...)
    if not LFM.Config.enabled then return end
    if not LFM.Config.scanChannels[event] then return end

    -- Get channel info for channel messages
    local channel = event
    if event == "CHAT_MSG_CHANNEL" then
        local _, _, _, _, _, _, _, channelIndex = ...
        channel = "Channel " .. (channelIndex or "?")
    end

    -- Parse the message
    local info = LFM.ParseMessage(message, author, channel)
    if info then
        -- Route to appropriate tracker based on message type
        if info.isLFM and AIP.GroupTracker then
            -- This is an LFM message - track as a group
            local groupInfo = AIP.GroupTracker.ParseLFMMessage(message, author, channel)
            if groupInfo then
                AIP.GroupTracker.AddGroup(groupInfo)
            end
        end

        if info.isLFG then
            -- This is an LFG message - track as a player
            LFM.AddPlayer(info)
        end

        -- If it could be either, add to both
        if not info.isLFM and not info.isLFG then
            LFM.AddPlayer(info)
        end
    end
end

-- Create event frame
local lfmFrame = CreateFrame("Frame", "AIPLFMBrowserFrame")
lfmFrame:RegisterEvent("CHAT_MSG_CHANNEL")
lfmFrame:RegisterEvent("CHAT_MSG_SAY")
lfmFrame:RegisterEvent("CHAT_MSG_YELL")
lfmFrame:RegisterEvent("CHAT_MSG_GUILD")
lfmFrame:SetScript("OnEvent", OnChatMessage)

-- Periodic cleanup
local cleanupElapsed = 0
lfmFrame:SetScript("OnUpdate", function(self, elapsed)
    cleanupElapsed = cleanupElapsed + elapsed
    if cleanupElapsed > 60 then  -- Every minute
        cleanupElapsed = 0
        LFM.PruneOldEntries()
    end
end)

-- LFM Browser UI
local lfmBrowserFrame = nil
local lfmButtons = {}
local LFM_BUTTONS_SHOWN = 12
local lfmFilters = {
    search = "",
    role = nil,
    class = nil,
    raid = nil,
    minGS = nil,
    lfgOnly = false,
}

function LFM.CreateBrowserUI()
    if lfmBrowserFrame then return lfmBrowserFrame end

    local frame = CreateFrame("Frame", "AIPLFMBrowserWindow", UIParent)
    frame:SetSize(650, 500)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("LFM Browser - Chat Scanner")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Search box
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 20, -45)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", "AIPLFMSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        lfmFilters.search = self:GetText()
        AIP.UpdateLFMBrowserUI()
    end)
    frame.searchBox = searchBox

    -- Role filter dropdown
    local roleLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleLabel:SetPoint("LEFT", searchBox, "RIGHT", 20, 0)
    roleLabel:SetText("Role:")

    local roleDropdown = CreateFrame("Frame", "AIPLFMRoleDropdown", frame, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", roleLabel, "RIGHT", -10, -3)
    UIDropDownMenu_SetWidth(roleDropdown, 80)

    local function RoleDropdown_Initialize()
        local info = UIDropDownMenu_CreateInfo()

        info.text = "All Roles"
        info.value = nil
        info.func = function()
            lfmFilters.role = nil
            UIDropDownMenu_SetText(roleDropdown, "All Roles")
            AIP.UpdateLFMBrowserUI()
        end
        UIDropDownMenu_AddButton(info)

        for _, role in ipairs({"TANK", "HEALER", "DPS"}) do
            info.text = role
            info.value = role
            info.func = function()
                lfmFilters.role = role
                UIDropDownMenu_SetText(roleDropdown, role)
                AIP.UpdateLFMBrowserUI()
            end
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(roleDropdown, RoleDropdown_Initialize)
    UIDropDownMenu_SetText(roleDropdown, "All Roles")

    -- LFG Only checkbox
    local lfgCheck = CreateFrame("CheckButton", "AIPLFMLFGOnly", frame, "UICheckButtonTemplate")
    lfgCheck:SetSize(22, 22)
    lfgCheck:SetPoint("LEFT", roleDropdown, "RIGHT", 80, 3)
    lfgCheck:SetScript("OnClick", function(self)
        lfmFilters.lfgOnly = self:GetChecked()
        AIP.UpdateLFMBrowserUI()
    end)

    local lfgLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lfgLabel:SetPoint("LEFT", lfgCheck, "RIGHT", 2, 0)
    lfgLabel:SetText("LFG Only")

    -- Column headers
    local headers = {
        {text = "Player", width = 100, x = 20},
        {text = "Class/Role", width = 80, x = 120},
        {text = "GS", width = 50, x = 200},
        {text = "Raids", width = 100, x = 250},
        {text = "Message", width = 200, x = 350},
        {text = "When", width = 60, x = 550},
    }

    for _, header in ipairs(headers) do
        local h = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        h:SetPoint("TOPLEFT", header.x, -75)
        h:SetText(header.text)
        h:SetTextColor(1, 0.82, 0)
    end

    -- Scrollframe
    local scrollFrame = CreateFrame("ScrollFrame", "AIPLFMScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(590, 300)
    scrollFrame:SetPoint("TOPLEFT", 15, -95)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 25, AIP.UpdateLFMBrowserUI)
    end)

    -- Create entry rows
    for i = 1, LFM_BUTTONS_SHOWN do
        local row = CreateFrame("Button", "AIPLFMEntry"..i, frame)
        row:SetSize(600, 25)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 5, -((i-1) * 25))
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        -- Invite button
        local invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        invBtn:SetSize(30, 20)
        invBtn:SetPoint("LEFT", 0, 0)
        invBtn:SetText("Inv")
        invBtn.index = i
        row.invBtn = invBtn

        -- Player name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 35, 0)
        nameText:SetWidth(80)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Class/Role
        local classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        classText:SetPoint("LEFT", 120, 0)
        classText:SetWidth(75)
        classText:SetJustifyH("LEFT")
        row.classText = classText

        -- GearScore
        local gsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gsText:SetPoint("LEFT", 200, 0)
        gsText:SetWidth(45)
        gsText:SetJustifyH("LEFT")
        row.gsText = gsText

        -- Raids
        local raidText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        raidText:SetPoint("LEFT", 250, 0)
        raidText:SetWidth(95)
        raidText:SetJustifyH("LEFT")
        row.raidText = raidText

        -- Message
        local msgText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        msgText:SetPoint("LEFT", 350, 0)
        msgText:SetWidth(190)
        msgText:SetJustifyH("LEFT")
        msgText:SetTextColor(0.7, 0.7, 0.7)
        row.msgText = msgText

        -- Time
        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("LEFT", 550, 0)
        timeText:SetWidth(55)
        timeText:SetJustifyH("LEFT")
        timeText:SetTextColor(0.5, 0.5, 0.5)
        row.timeText = timeText

        row:Hide()
        lfmButtons[i] = row
    end

    -- Bottom controls
    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("BOTTOMLEFT", 20, 15)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        LFM.ClearAll()
    end)

    local refreshBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 22)
    refreshBtn:SetPoint("LEFT", clearBtn, "RIGHT", 10, 0)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        AIP.UpdateLFMBrowserUI()
    end)

    -- Status text
    local statusText = frame:CreateFontString("AIPLFMStatus", "OVERLAY", "GameFontNormal")
    statusText:SetPoint("BOTTOMRIGHT", -25, 20)
    statusText:SetText("0 players tracked")
    frame.statusText = statusText

    -- Enable/disable toggle
    local enableCheck = CreateFrame("CheckButton", "AIPLFMEnable", frame, "UICheckButtonTemplate")
    enableCheck:SetSize(22, 22)
    enableCheck:SetPoint("BOTTOM", 0, 12)
    enableCheck:SetChecked(LFM.Config.enabled)
    enableCheck:SetScript("OnClick", function(self)
        LFM.Config.enabled = self:GetChecked()
    end)

    local enableLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 2, 0)
    enableLabel:SetText("Enable Chat Scanning")

    tinsert(UISpecialFrames, frame:GetName())

    lfmBrowserFrame = frame
    return frame
end

-- Update LFM Browser UI
function AIP.UpdateLFMBrowserUI()
    if not lfmBrowserFrame then
        LFM.CreateBrowserUI()
    end

    if not lfmBrowserFrame:IsVisible() then return end

    local players = LFM.GetFilteredPlayers(lfmFilters)
    local numEntries = #players

    FauxScrollFrame_Update(_G["AIPLFMScrollFrame"], numEntries, LFM_BUTTONS_SHOWN, 25)

    local offset = FauxScrollFrame_GetOffset(_G["AIPLFMScrollFrame"])

    for i = 1, LFM_BUTTONS_SHOWN do
        local index = offset + i
        local row = lfmButtons[i]

        if index <= numEntries then
            local info = players[index]

            -- Set up invite button
            row.invBtn:SetScript("OnClick", function()
                LFM.InvitePlayer(info.name)
            end)

            -- Player name (with class color if known)
            local nameColor = "|cFFFFFFFF"
            if info.class and AIP.Composition and AIP.Composition.ClassColors[info.class] then
                local c = AIP.Composition.ClassColors[info.class]
                nameColor = string.format("|cFF%02x%02x%02x", c.r*255, c.g*255, c.b*255)
            end
            row.nameText:SetText(nameColor .. info.name .. "|r")

            -- Class/Role
            local classRole = ""
            if info.class then
                classRole = info.class:sub(1,1) .. info.class:sub(2):lower()
            end
            if info.role then
                classRole = classRole .. (classRole ~= "" and "/" or "") .. info.role
            end
            row.classText:SetText(classRole)

            -- GearScore
            row.gsText:SetText(info.gs and tostring(info.gs) or "-")

            -- Raids
            row.raidText:SetText(table.concat(info.raids, ", "))

            -- Message (truncated)
            row.msgText:SetText(info.message:sub(1, 40))

            -- Time ago
            row.timeText:SetText(LFM.FormatTimeAgo(info.age or 0))

            -- Highlight if invited
            if info.invited then
                row.nameText:SetTextColor(0.5, 0.5, 0.5)
            end

            row:Show()
        else
            row:Hide()
        end
    end

    lfmBrowserFrame.statusText:SetText(LFM.GetPlayerCount() .. " players tracked")
end

-- Toggle LFM Browser
function AIP.ToggleLFMBrowserUI()
    local frame = LFM.CreateBrowserUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.UpdateLFMBrowserUI()
    end
end

-- Slash command handler
function LFM.SlashHandler(msg)
    msg = (msg or ""):lower():trim()

    if msg == "" or msg == "show" then
        AIP.ToggleLFMBrowserUI()
    elseif msg == "clear" then
        LFM.ClearAll()
    elseif msg == "count" then
        AIP.Print("LFM Browser tracking " .. LFM.GetPlayerCount() .. " players")
    elseif msg == "enable" then
        LFM.Config.enabled = true
        AIP.Print("LFM Browser scanning enabled")
    elseif msg == "disable" then
        LFM.Config.enabled = false
        AIP.Print("LFM Browser scanning disabled")
    else
        AIP.Print("LFM Browser commands:")
        AIP.Print("  /aip lfm - Show LFM browser")
        AIP.Print("  /aip lfm clear - Clear all tracked players")
        AIP.Print("  /aip lfm enable/disable - Toggle scanning")
    end
end
