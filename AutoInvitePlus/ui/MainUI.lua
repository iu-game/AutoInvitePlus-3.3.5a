-- AutoInvite Plus - Main Configuration UI
-- Replaces UI.xml with DRY Lua code using UIFactory

local AIP = AutoInvitePlus
if not AIP then return end

local UI = AIP.UI
if not UI then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r MainUI: UIFactory not loaded!")
    return
end

-- ============================================================================
-- MAIN FRAME CREATION
-- ============================================================================

local function CreateMainFrame()
    local frame = UI.CreateWindow("AIPMainFrame", 400, 520, "AutoInvite Plus", true)
    frame:SetFrameStrata("DIALOG")

    -- Title border texture
    local titleBorder = frame:CreateTexture(nil, "ARTWORK")
    titleBorder:SetSize(200, 64)
    titleBorder:SetPoint("TOP", 0, 12)
    titleBorder:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBorder:SetTexCoord(0.2, 0.8, 0, 0.6)

    -- Content container
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 15, -35)
    content:SetPoint("BOTTOMRIGHT", -15, 15)

    local yOffset = 0

    -- ========================================
    -- ENABLE CHECKBOX
    -- ========================================
    local enableCheck = UI.CreateCheckbox(content, "Enable Auto-Invite", function(self, checked)
        AIP.db.enabled = checked
        AIP.Print("Auto-invite " .. (checked and "ENABLED" or "DISABLED"))
    end)
    enableCheck:SetPoint("TOPLEFT", 5, yOffset)
    enableCheck.label:SetFontObject("GameFontNormalLarge")
    frame.enableCheck = enableCheck

    yOffset = yOffset - 35

    -- ========================================
    -- TRIGGER KEYWORDS
    -- ========================================
    local trigLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trigLabel:SetPoint("TOPLEFT", 10, yOffset)
    trigLabel:SetText("Trigger Keywords:")

    local trigInput = UI.CreateEditBox(content, 230, 20)
    trigInput:SetPoint("LEFT", trigLabel, "RIGHT", 10, 0)
    trigInput:SetScript("OnEnterPressed", function(self)
        AIP.db.triggers = self:GetText()
        self:ClearFocus()
    end)
    trigInput:SetScript("OnEscapePressed", function(self)
        self:SetText(AIP.db.triggers or "")
        self:ClearFocus()
    end)
    frame.trigInput = trigInput

    yOffset = yOffset - 20

    local trigHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    trigHelp:SetPoint("TOPLEFT", 10, yOffset)
    trigHelp:SetText("(Separate with semicolons: inv;invite;123)")
    trigHelp:SetTextColor(0.7, 0.7, 0.7)

    yOffset = yOffset - 25

    -- ========================================
    -- LISTEN CHANNELS SECTION
    -- ========================================
    local listenHeader = UI.CreateSectionHeader(content, "Listen for triggers in:", 360)
    listenHeader:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 22

    -- Listen checkboxes data
    local listenChannels = {
        {key = "listenWhisper", label = "Whisper", x = 0},
        {key = "listenGuild", label = "Guild", x = 90},
        {key = "listenSay", label = "Say", x = 170},
        {key = "listenYell", label = "Yell", x = 240},
        {key = "listenGeneral", label = "General", x = 0, row = 2},
        {key = "listenTrade", label = "Trade", x = 90, row = 2},
        {key = "listenLFG", label = "LFG", x = 170, row = 2},
        {key = "listenDefense", label = "Defense", x = 240, row = 2},
    }

    frame.listenChecks = {}
    local baseY = yOffset

    for _, ch in ipairs(listenChannels) do
        local y = ch.row == 2 and (baseY - 22) or baseY
        local check = UI.CreateCheckbox(content, ch.label, function(self, checked)
            AIP.db[ch.key] = checked
        end)
        check:SetPoint("TOPLEFT", 10 + ch.x, y)
        check:SetSize(20, 20)
        check.label:SetFontObject("GameFontNormalSmall")
        frame.listenChecks[ch.key] = check
    end

    yOffset = yOffset - 54

    -- ========================================
    -- OPTIONS SECTION
    -- ========================================
    local optHeader = UI.CreateSectionHeader(content, "Options:", 360)
    optHeader:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 22

    -- Options checkboxes
    local optionsDef = {
        {key = "guildOnly", label = "Guild members only", x = 0},
        {key = "autoRaid", label = "Auto-convert to raid", x = 175},
        {key = "useQueue", label = "Use queue (review first)", x = 0, row = 2},
    }

    frame.optionChecks = {}
    baseY = yOffset

    for _, opt in ipairs(optionsDef) do
        local y = opt.row == 2 and (baseY - 22) or baseY
        local check = UI.CreateCheckbox(content, opt.label, function(self, checked)
            AIP.db[opt.key] = checked
        end)
        check:SetPoint("TOPLEFT", 10 + opt.x, y)
        check:SetSize(20, 20)
        check.label:SetFontObject("GameFontNormalSmall")
        frame.optionChecks[opt.key] = check
    end

    yOffset = yOffset - 44

    -- Max raiders
    local maxCheck = UI.CreateCheckbox(content, "Max raiders:", function(self, checked)
        AIP.db.useMaxLimit = checked
    end)
    maxCheck:SetPoint("TOPLEFT", 10, yOffset)
    maxCheck:SetSize(20, 20)
    maxCheck.label:SetFontObject("GameFontNormalSmall")
    frame.optionChecks.useMaxLimit = maxCheck

    local maxInput = UI.CreateEditBox(content, 40, 20, true)
    maxInput:SetPoint("LEFT", maxCheck.label, "RIGHT", 5, 0)
    maxInput:SetScript("OnEnterPressed", function(self)
        local val = math.max(1, math.min(40, tonumber(self:GetText()) or 25))
        AIP.db.maxRaiders = val
        self:SetText(val)
        self:ClearFocus()
    end)
    maxInput:SetScript("OnEscapePressed", function(self)
        self:SetText(AIP.db.maxRaiders or 25)
        self:ClearFocus()
    end)
    frame.maxInput = maxInput

    yOffset = yOffset - 35

    -- ========================================
    -- SPAM MESSAGE
    -- ========================================
    local spamLabel = UI.CreateSectionHeader(content, "Spam Message (<key> = triggers):", 360)
    spamLabel:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 22

    local spamInput = UI.CreateEditBox(content, 350, 20)
    spamInput:SetPoint("TOPLEFT", 10, yOffset)
    spamInput:SetScript("OnEnterPressed", function(self)
        AIP.db.spamMessage = self:GetText()
        self:ClearFocus()
    end)
    spamInput:SetScript("OnEscapePressed", function(self)
        self:SetText(AIP.db.spamMessage or "")
        self:ClearFocus()
    end)
    frame.spamInput = spamInput

    yOffset = yOffset - 30

    -- ========================================
    -- SPAM CHANNELS
    -- ========================================
    local spamHeader = UI.CreateSectionHeader(content, "Spam to channels:", 360)
    spamHeader:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 22

    local spamChannels = {
        {key = "spamGeneral", label = "General", x = 0},
        {key = "spamTrade", label = "Trade", x = 90},
        {key = "spamGuild", label = "Guild", x = 170},
        {key = "spamSay", label = "Say", x = 250},
    }

    frame.spamChecks = {}

    for _, ch in ipairs(spamChannels) do
        local check = UI.CreateCheckbox(content, ch.label, function(self, checked)
            AIP.db[ch.key] = checked
        end)
        check:SetPoint("TOPLEFT", 10 + ch.x, yOffset)
        check:SetSize(20, 20)
        check.label:SetFontObject("GameFontNormalSmall")
        frame.spamChecks[ch.key] = check
    end

    yOffset = yOffset - 35

    -- ========================================
    -- ACTION BUTTONS ROW 1
    -- ========================================
    local btn1 = UI.CreateButton(content, "Spam Now", 90, 25, function()
        AIP.SpamInvite()
    end)
    btn1:SetPoint("TOPLEFT", 5, yOffset)

    local btn2 = UI.CreateButton(content, "Invite Guild", 90, 25, function()
        AIP.InviteGuild()
    end)
    btn2:SetPoint("LEFT", btn1, "RIGHT", 10, 0)

    local btn3 = UI.CreateButton(content, "Invite Friends", 90, 25, function()
        AIP.InviteFriends()
    end)
    btn3:SetPoint("LEFT", btn2, "RIGHT", 10, 0)

    yOffset = yOffset - 35

    -- ========================================
    -- ACTION BUTTONS ROW 2
    -- ========================================
    local btn4 = UI.CreateButton(content, "Queue", 70, 25, function()
        if AIP.ToggleQueueUI then AIP.ToggleQueueUI() end
    end)
    btn4:SetPoint("TOPLEFT", 5, yOffset)

    local btn5 = UI.CreateButton(content, "Blacklist", 70, 25, function()
        if AIP.ToggleBlacklistUI then AIP.ToggleBlacklistUI() end
    end)
    btn5:SetPoint("LEFT", btn4, "RIGHT", 10, 0)

    local btn6 = UI.CreateButton(content, "Promote", 70, 25, function()
        if AIP.TogglePromoteUI then AIP.TogglePromoteUI() end
    end)
    btn6:SetPoint("LEFT", btn5, "RIGHT", 10, 0)

    yOffset = yOffset - 35

    -- ========================================
    -- STATUS DISPLAY
    -- ========================================
    local statusText = content:CreateFontString("AIPStatusText", "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", 5, yOffset)
    statusText:SetTextColor(0.7, 0.7, 0.7)
    frame.statusText = statusText

    return frame
end

-- ============================================================================
-- UPDATE UI FROM SAVED VARIABLES
-- ============================================================================

function AIP.UpdateUI()
    local frame = _G["AIPMainFrame"]
    if not frame or not AIP.db then return end

    -- Enable checkbox
    if frame.enableCheck then
        frame.enableCheck:SetChecked(AIP.db.enabled)
    end

    -- Trigger input
    if frame.trigInput then
        frame.trigInput:SetText(AIP.db.triggers or "")
    end

    -- Listen checkboxes
    if frame.listenChecks then
        for key, check in pairs(frame.listenChecks) do
            check:SetChecked(AIP.db[key])
        end
    end

    -- Option checkboxes
    if frame.optionChecks then
        for key, check in pairs(frame.optionChecks) do
            check:SetChecked(AIP.db[key])
        end
    end

    -- Max raiders
    if frame.maxInput then
        frame.maxInput:SetText(AIP.db.maxRaiders or 25)
    end

    -- Spam input
    if frame.spamInput then
        frame.spamInput:SetText(AIP.db.spamMessage or "")
    end

    -- Spam checkboxes
    if frame.spamChecks then
        for key, check in pairs(frame.spamChecks) do
            check:SetChecked(AIP.db[key])
        end
    end

    -- Status
    if frame.statusText then
        local status = AIP.db.enabled and "|cFF00FF00ENABLED|r" or "|cFFFF0000DISABLED|r"
        local groupSize = AIP.GetGroupSize and AIP.GetGroupSize() or 0
        local queueCount = AIP.GetQueueCount and AIP.GetQueueCount() or 0
        frame.statusText:SetText("Status: " .. status .. "  |  Group: " .. groupSize .. "  |  Queue: " .. queueCount)
    end
end

-- ============================================================================
-- TOGGLE FUNCTIONS
-- ============================================================================

function AIP.ToggleOldUI()
    local frame = _G["AIPMainFrame"]
    if not frame then
        frame = CreateMainFrame()
    end

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.UpdateUI()
    end
end

-- Initialize on load (defer to allow db to load)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    -- Create the frame but keep it hidden
    if not _G["AIPMainFrame"] then
        CreateMainFrame()
    end
    self:UnregisterAllEvents()
end)
