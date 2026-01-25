-- AutoInvite Plus - Settings Panel (Enhanced v4.1)
-- Redesigned settings with clear sections and tooltips

local AIP = AutoInvitePlus
AIP.Panels = AIP.Panels or {}
AIP.Panels.Settings = {}
local SP = AIP.Panels.Settings

-- Panel state
SP.Frame = nil
SP.AutoSpamActive = false
SP.AutoSpamTimer = nil

-- Tooltip definitions
SP.Tooltips = {
    autoInvite = "When enabled, players who whisper you with trigger keywords will be automatically invited (or added to queue if queue mode is enabled).\n\nExample: If your trigger is 'inv', anyone whispering 'inv' to you will be invited.",
    listenChannels = "Select which chat channels to monitor for invite requests.\n\nWhisper is recommended for most use cases. Say/Yell can be used in cities.",
    broadcastSettings = "Configure how and where your LFM messages are broadcast.\n\nMessages are sent to ALL selected channels simultaneously (not sequentially).",
    lfmScanner = "Scans chat channels for other players' LFM/LFG messages and displays them in the browser.\n\nCache duration controls how long entries are kept.",
    responses = "Customize the automatic whisper messages sent when:\n- Inviting a player from queue\n- Rejecting a player\n- Adding to waitlist\n- Waitlist position changes\n\nUse %d for position number. Leave empty to disable.",
    blacklistMode = "Flag Only: Shows blacklisted players in queue with indicator, but allows manual invite.\n\nAuto-Reject: Automatically rejects and whispers blacklisted players.",
    guiAppearance = "Customize how the main window looks.\n\nOpacity: Controls the transparency of the window.\n\nUnfocused: Reduces opacity when the window doesn't have focus.",
}

-- Helper: Fix UIDropDownMenu strata issues in WotLK
local function FixDropdownStrata(dropdown)
    if not dropdown then return end
    local button = _G[dropdown:GetName() .. "Button"]
    if button then
        button:HookScript("OnClick", function()
            for i = 1, UIDROPDOWNMENU_MAXLEVELS or 2 do
                local listFrame = _G["DropDownList" .. i]
                if listFrame then
                    listFrame:SetFrameStrata("TOOLTIP")
                end
            end
        end)
    end
end

-- Helper: Create styled edit box (WotLK compatible)
local function CreateStyledEditBox(parent, width, height, isNumeric)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(width + 10, height + 8)

    -- Background using WotLK-compatible textures
    frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local editBox = CreateFrame("EditBox", nil, frame)
    editBox:SetSize(width, height)
    editBox:SetPoint("LEFT", 5, 0)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:EnableKeyboard(true)
    editBox:SetTextInsets(2, 2, 0, 0)

    if isNumeric then
        editBox:SetNumeric(true)
    else
        editBox:SetMaxLetters(255)
    end

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    editBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
        frame:SetBackdropBorderColor(0.8, 0.8, 0.3, 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        frame:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    end)

    -- Store reference to container for positioning
    editBox.container = frame

    return editBox, frame
end

-- Helper: Create tooltip help button
local function CreateTooltipButton(parent, tooltipKey, x, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(16, 16)
    if x and y then
        btn:SetPoint("TOPLEFT", x, y)
    end

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetText("[?]")
    text:SetTextColor(0.6, 0.8, 1)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Information", 1, 0.82, 0)
        GameTooltip:AddLine(SP.Tooltips[tooltipKey] or "No information available.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return btn
end

-- Helper: Create section header
local function CreateSectionHeader(parent, x, y, num, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetSize(600, 22)

    -- Background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(0.15, 0.15, 0.15, 0.8)

    -- Number badge
    local numText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    numText:SetPoint("LEFT", 5, 0)
    numText:SetText("[" .. num .. "]")
    numText:SetTextColor(0.5, 0.8, 1)

    -- Title
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", numText, "RIGHT", 8, 0)
    titleText:SetText(text)
    titleText:SetTextColor(1, 0.82, 0)

    return frame
end

-- Helper: Create checkbox with label
local function CreateCheckbox(parent, x, y, key, labelText, onClick)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(22, 22)
    check:SetPoint("TOPLEFT", x, y)
    check.key = key

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(labelText)

    check:SetScript("OnClick", function(self)
        if onClick then
            onClick(self)
        elseif AIP.db and self.key then
            AIP.db[self.key] = self:GetChecked() == 1 or self:GetChecked() == true
            if AIP.CentralGUI and AIP.CentralGUI.UpdateStatus then
                AIP.CentralGUI.UpdateStatus()
            end
        end
    end)

    return check, label
end

-- Create the settings panel
function SP.Create(parent)
    if SP.Frame then return SP.Frame end

    local frame = CreateFrame("Frame", "AIPSettingsPanel", parent)
    frame:SetAllPoints()

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "AIPSettingsScroll", frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 5)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(620, 950)  -- Increased height for all sections
    scrollFrame:SetScrollChild(content)

    local y = -10
    frame.checks = {}

    -- ========================================================================
    -- [1] AUTO-INVITE SYSTEM
    -- ========================================================================
    local section1 = CreateSectionHeader(content, 5, y, "1", "AUTO-INVITE SYSTEM")
    local tooltip1 = CreateTooltipButton(content, "autoInvite")
    tooltip1:SetPoint("LEFT", section1, "RIGHT", 5, 0)
    y = y - 30

    local enableCheck, enableLabel = CreateCheckbox(content, 15, y, "enabled", "Enable Auto-Invite")
    enableLabel:SetFontObject("GameFontNormal")
    frame.checks.enabled = enableCheck
    y = y - 28

    -- Trigger keywords
    local triggerLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    triggerLabel:SetPoint("TOPLEFT", 15, y)
    triggerLabel:SetText("Trigger Keywords:")

    local triggerInput, triggerContainer = CreateStyledEditBox(content, 180, 16, false)
    triggerContainer:SetPoint("LEFT", triggerLabel, "RIGHT", 5, 0)
    triggerInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.triggers = self:GetText() end
        self:ClearFocus()
    end)
    triggerInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.triggers = self:GetText()
        end
    end)
    frame.triggerInput = triggerInput

    local triggerHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    triggerHelp:SetPoint("LEFT", triggerContainer, "RIGHT", 10, 0)
    triggerHelp:SetText("(separate with ;)")
    triggerHelp:SetTextColor(0.5, 0.5, 0.5)
    y = y - 28

    -- Max group size
    local maxLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    maxLabel:SetPoint("TOPLEFT", 15, y)
    maxLabel:SetText("Max Group Size:")

    local maxInput, maxContainer = CreateStyledEditBox(content, 30, 16, true)
    maxContainer:SetPoint("LEFT", maxLabel, "RIGHT", 5, 0)
    maxInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 25
            AIP.db.maxRaiders = math.max(1, math.min(40, val))
            self:SetText(AIP.db.maxRaiders)
        end
        self:ClearFocus()
    end)
    frame.maxInput = maxInput

    -- Options on same line
    local autoRaidCheck = CreateCheckbox(content, 150, y, "autoRaid", "Auto-convert to raid")
    frame.checks.autoRaid = autoRaidCheck

    local guildOnlyCheck = CreateCheckbox(content, 330, y, "guildOnly", "Guild only")
    frame.checks.guildOnly = guildOnlyCheck
    y = y - 26

    -- Queue mode
    local useQueueCheck = CreateCheckbox(content, 15, y, "useQueue", "Use Queue (require manual approval before invite)")
    frame.checks.useQueue = useQueueCheck
    y = y - 26

    -- Blacklist mode
    local blModeLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    blModeLabel:SetPoint("TOPLEFT", 15, y)
    blModeLabel:SetText("Blacklist Mode:")

    local blModeDropdown = CreateFrame("Frame", "AIPBlacklistModeDropdown", content, "UIDropDownMenuTemplate")
    blModeDropdown:SetPoint("LEFT", blModeLabel, "RIGHT", -5, -3)
    UIDropDownMenu_SetWidth(blModeDropdown, 100)
    UIDropDownMenu_SetText(blModeDropdown, "Flag Only")
    frame.blModeDropdown = blModeDropdown

    local function BlModeDropdown_Initialize()
        local modes = {
            {id = "flag", name = "Flag Only"},
            {id = "reject", name = "Auto-Reject"},
        }
        for _, m in ipairs(modes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = m.name
            info.value = m.id
            info.func = function(self)
                if AIP.db then AIP.db.blacklistMode = m.id end
                UIDropDownMenu_SetText(blModeDropdown, m.name)
            end
            info.checked = (AIP.db and AIP.db.blacklistMode == m.id)
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(blModeDropdown, BlModeDropdown_Initialize)
    FixDropdownStrata(blModeDropdown)

    local blModeTooltip = CreateTooltipButton(content, "blacklistMode")
    blModeTooltip:SetPoint("LEFT", blModeDropdown, "RIGHT", 5, 3)
    y = y - 35

    -- ========================================================================
    -- [2] LISTEN CHANNELS
    -- ========================================================================
    local section2 = CreateSectionHeader(content, 5, y, "2", "LISTEN CHANNELS - Where to detect invite requests")
    local tooltip2 = CreateTooltipButton(content, "listenChannels")
    tooltip2:SetPoint("LEFT", section2, "RIGHT", 5, 0)
    y = y - 28

    local listenChannels = {
        {key = "listenWhisper", text = "Whisper"},
        {key = "listenSay", text = "Say"},
        {key = "listenYell", text = "Yell"},
        {key = "listenGuild", text = "Guild"},
    }

    local col = 0
    for _, ch in ipairs(listenChannels) do
        local check = CreateCheckbox(content, 15 + col * 110, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 35

    -- ========================================================================
    -- [3] BROADCAST SETTINGS
    -- ========================================================================
    local section3 = CreateSectionHeader(content, 5, y, "3", "BROADCAST SETTINGS - Spam your LFM message")
    local tooltip3 = CreateTooltipButton(content, "broadcastSettings")
    tooltip3:SetPoint("LEFT", section3, "RIGHT", 5, 0)
    y = y - 28

    -- Spam channels
    local spamChannels = {
        {key = "spamSay", text = "Say"},
        {key = "spamYell", text = "Yell"},
        {key = "spamGuild", text = "Guild"},
        {key = "spamGeneral", text = "General"},
        {key = "spamTrade", text = "Trade"},
        {key = "spamLFG", text = "LFG"},
    }

    col = 0
    for _, ch in ipairs(spamChannels) do
        local check = CreateCheckbox(content, 15 + col * 90, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
        if col >= 6 then
            col = 0
            y = y - 24
        end
    end
    if col > 0 then y = y - 24 end
    y = y - 5

    -- Spam message
    local msgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgLabel:SetPoint("TOPLEFT", 15, y)
    msgLabel:SetText("Message:")

    local msgInput, msgContainer = CreateStyledEditBox(content, 420, 16, false)
    msgContainer:SetPoint("LEFT", msgLabel, "RIGHT", 5, 0)
    msgInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.spamMessage = self:GetText() end
        self:ClearFocus()
    end)
    msgInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.spamMessage = self:GetText()
        end
    end)
    frame.msgInput = msgInput
    y = y - 24

    local msgHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgHelp:SetPoint("TOPLEFT", 80, y)
    msgHelp:SetText("Use <key> for trigger keywords. Example: Whisper \"<key>\" for invite! |AIP|")
    msgHelp:SetTextColor(0.5, 0.5, 0.5)
    y = y - 22

    -- Cooldown
    local cdLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cdLabel:SetPoint("TOPLEFT", 15, y)
    cdLabel:SetText("Cooldown (sec):")

    local cdInput, cdContainer = CreateStyledEditBox(content, 30, 16, true)
    cdContainer:SetPoint("LEFT", cdLabel, "RIGHT", 5, 0)
    cdInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 15
            AIP.db.spamChannelCooldown = math.max(15, math.min(300, val))
            self:SetText(AIP.db.spamChannelCooldown)
        end
        self:ClearFocus()
    end)
    frame.cdInput = cdInput
    y = y - 28

    -- Spam buttons
    local spamOnceBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    spamOnceBtn:SetSize(100, 24)
    spamOnceBtn:SetPoint("TOPLEFT", 15, y)
    spamOnceBtn:SetText("Broadcast Now")
    spamOnceBtn:SetScript("OnClick", function()
        if AIP.SpamInvite then AIP.SpamInvite() end
    end)

    local autoSpamBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    autoSpamBtn:SetSize(120, 24)
    autoSpamBtn:SetPoint("LEFT", spamOnceBtn, "RIGHT", 10, 0)
    autoSpamBtn:SetText("Start Auto-Spam")
    autoSpamBtn:SetScript("OnClick", function()
        SP.ToggleAutoSpam()
    end)
    frame.autoSpamBtn = autoSpamBtn

    local intervalLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intervalLabel:SetPoint("LEFT", autoSpamBtn, "RIGHT", 10, 0)
    intervalLabel:SetText("every")

    local intervalInput, intervalContainer = CreateStyledEditBox(content, 30, 16, true)
    intervalContainer:SetPoint("LEFT", intervalLabel, "RIGHT", 5, 0)
    intervalInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 90
            -- Minimum 60s to avoid chat bans on most servers
            AIP.db.autoSpamInterval = math.max(60, math.min(600, val))
            self:SetText(AIP.db.autoSpamInterval)
        end
        self:ClearFocus()
    end)
    frame.intervalInput = intervalInput

    local intervalSuffix = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    intervalSuffix:SetPoint("LEFT", intervalContainer, "RIGHT", 5, 0)
    intervalSuffix:SetText("seconds")

    local autoStatus = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoStatus:SetPoint("LEFT", intervalSuffix, "RIGHT", 20, 0)
    autoStatus:SetText("")
    frame.autoStatus = autoStatus
    y = y - 40

    -- ========================================================================
    -- [4] LFM/LFG SCANNER
    -- ========================================================================
    local section4 = CreateSectionHeader(content, 5, y, "4", "LFM/LFG SCANNER")
    local tooltip4 = CreateTooltipButton(content, "lfmScanner")
    tooltip4:SetPoint("LEFT", section4, "RIGHT", 5, 0)
    y = y - 28

    local scanCheck = CreateCheckbox(content, 15, y, nil, "Enable chat scanning for LFM/LFG browser", function(self)
        if AIP.LFMBrowser then
            AIP.LFMBrowser.Config.enabled = self:GetChecked()
        end
    end)
    frame.checks.chatScan = scanCheck
    y = y - 26

    -- Scan channels
    local scanChannelsLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanChannelsLabel:SetPoint("TOPLEFT", 15, y)
    scanChannelsLabel:SetText("Scan:")

    local scanChannels = {
        {key = "scanTrade", text = "Trade"},
        {key = "scanLFG", text = "LFG"},
        {key = "scanGeneral", text = "General"},
        {key = "scanSay", text = "Say"},
        {key = "scanYell", text = "Yell"},
    }

    col = 0
    for _, ch in ipairs(scanChannels) do
        local check = CreateCheckbox(content, 55 + col * 85, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 26

    -- Cache duration
    local cacheLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheLabel:SetPoint("TOPLEFT", 15, y)
    cacheLabel:SetText("Cache Duration:")

    local cacheInput, cacheContainer = CreateStyledEditBox(content, 30, 16, true)
    cacheContainer:SetPoint("LEFT", cacheLabel, "RIGHT", 5, 0)
    cacheInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 15
            AIP.db.cacheDuration = math.max(1, math.min(60, val))
            self:SetText(AIP.db.cacheDuration)
        end
        self:ClearFocus()
    end)
    frame.cacheInput = cacheInput

    local cacheSuffix = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheSuffix:SetPoint("LEFT", cacheContainer, "RIGHT", 5, 0)
    cacheSuffix:SetText("minutes")

    local clearCacheBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearCacheBtn:SetSize(100, 20)
    clearCacheBtn:SetPoint("LEFT", cacheSuffix, "RIGHT", 20, 0)
    clearCacheBtn:SetText("Clear Cache")
    clearCacheBtn:SetScript("OnClick", function()
        if AIP.GroupTracker and AIP.GroupTracker.ClearCache then
            AIP.GroupTracker.ClearCache()
            AIP.Print("LFM/LFG cache cleared")
        end
    end)
    y = y - 40

    -- ========================================================================
    -- [5] RESPONSE MESSAGES
    -- ========================================================================
    local section5 = CreateSectionHeader(content, 5, y, "5", "RESPONSE MESSAGES")
    local tooltip5 = CreateTooltipButton(content, "responses")
    tooltip5:SetPoint("LEFT", section5, "RIGHT", 5, 0)
    y = y - 28

    -- Invite response
    local invRespLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    invRespLabel:SetPoint("TOPLEFT", 15, y)
    invRespLabel:SetText("Invite Accepted:")

    local invRespInput, invRespContainer = CreateStyledEditBox(content, 350, 16, false)
    invRespContainer:SetPoint("LEFT", invRespLabel, "RIGHT", 5, 0)
    invRespInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.responseInvite = self:GetText() end
        self:ClearFocus()
    end)
    invRespInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.responseInvite = self:GetText()
        end
    end)
    frame.invRespInput = invRespInput
    y = y - 26

    -- Reject response
    local rejRespLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rejRespLabel:SetPoint("TOPLEFT", 15, y)
    rejRespLabel:SetText("Invite Rejected:")

    local rejRespInput, rejRespContainer = CreateStyledEditBox(content, 350, 16, false)
    rejRespContainer:SetPoint("LEFT", rejRespLabel, "RIGHT", 5, 0)
    rejRespInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.responseReject = self:GetText() end
        self:ClearFocus()
    end)
    rejRespInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.responseReject = self:GetText()
        end
    end)
    frame.rejRespInput = rejRespInput
    y = y - 26

    -- Waitlist response
    local waitRespLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    waitRespLabel:SetPoint("TOPLEFT", 15, y)
    waitRespLabel:SetText("Added to Waitlist:")

    local waitRespInput, waitRespContainer = CreateStyledEditBox(content, 350, 16, false)
    waitRespContainer:SetPoint("LEFT", waitRespLabel, "RIGHT", 5, 0)
    waitRespInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.responseWaitlist = self:GetText() end
        self:ClearFocus()
    end)
    waitRespInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.responseWaitlist = self:GetText()
        end
    end)
    frame.waitRespInput = waitRespInput

    local waitRespHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    waitRespHelp:SetPoint("LEFT", waitRespContainer, "RIGHT", 5, 0)
    waitRespHelp:SetText("(%d = position)")
    waitRespHelp:SetTextColor(0.5, 0.5, 0.5)
    y = y - 26

    -- Position changed response
    local posRespLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posRespLabel:SetPoint("TOPLEFT", 15, y)
    posRespLabel:SetText("Position Changed:")

    local posRespInput, posRespContainer = CreateStyledEditBox(content, 350, 16, false)
    posRespContainer:SetPoint("LEFT", posRespLabel, "RIGHT", 5, 0)
    posRespInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then AIP.db.responseWaitlistPosition = self:GetText() end
        self:ClearFocus()
    end)
    posRespInput:SetScript("OnTextChanged", function(self, userInput)
        if userInput and AIP.db then
            AIP.db.responseWaitlistPosition = self:GetText()
        end
    end)
    frame.posRespInput = posRespInput

    local posRespHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    posRespHelp:SetPoint("LEFT", posRespContainer, "RIGHT", 5, 0)
    posRespHelp:SetText("(%d = position)")
    posRespHelp:SetTextColor(0.5, 0.5, 0.5)
    y = y - 40

    -- ========================================================================
    -- [6] GUI APPEARANCE
    -- ========================================================================
    local section6 = CreateSectionHeader(content, 5, y, "6", "GUI APPEARANCE")
    local tooltip6 = CreateTooltipButton(content, "guiAppearance")
    tooltip6:SetPoint("LEFT", section6, "RIGHT", 5, 0)
    y = y - 28

    -- Opacity slider (WotLK 3.3.5a compatible - manual slider creation)
    local opacityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("TOPLEFT", 15, y)
    opacityLabel:SetText("Window Opacity:")

    -- Create a custom slider frame for WotLK compatibility
    local opacitySlider = CreateFrame("Slider", "AIPOpacitySlider", content)
    opacitySlider:SetPoint("LEFT", opacityLabel, "RIGHT", 15, 0)
    opacitySlider:SetSize(150, 16)
    opacitySlider:SetOrientation("HORIZONTAL")
    opacitySlider:SetMinMaxValues(30, 100)
    opacitySlider:SetValueStep(5)
    opacitySlider:EnableMouseWheel(true)

    -- Slider background
    local sliderBg = opacitySlider:CreateTexture(nil, "BACKGROUND")
    sliderBg:SetAllPoints()
    sliderBg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")

    -- Slider thumb
    opacitySlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = opacitySlider:GetThumbTexture()
    thumb:SetSize(32, 32)

    -- Low/High labels
    local opacityLow = opacitySlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    opacityLow:SetPoint("TOPLEFT", opacitySlider, "BOTTOMLEFT", 0, 0)
    opacityLow:SetText("30%")

    local opacityHigh = opacitySlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    opacityHigh:SetPoint("TOPRIGHT", opacitySlider, "BOTTOMRIGHT", 0, 0)
    opacityHigh:SetText("100%")

    local opacityValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    opacityValue:SetPoint("LEFT", opacitySlider, "RIGHT", 15, 0)
    opacityValue:SetText("100%")
    frame.opacityValue = opacityValue

    -- Set initial value
    local initOpacity = (AIP.db and AIP.db.guiOpacity) and (AIP.db.guiOpacity * 100) or 100
    opacitySlider:SetValue(initOpacity)
    opacityValue:SetText(math.floor(initOpacity) .. "%")

    opacitySlider:SetScript("OnValueChanged", function(self, value)
        local actualValue = value / 100
        if AIP.db then
            AIP.db.guiOpacity = actualValue
        end
        opacityValue:SetText(math.floor(value) .. "%")
        -- Apply to main GUI frame
        if AIP.CentralGUI and AIP.CentralGUI.Frame then
            AIP.CentralGUI.Frame:SetAlpha(actualValue)
        end
    end)

    opacitySlider:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetValue()
        local step = self:GetValueStep() or 5
        self:SetValue(current + (delta * step))
    end)

    frame.opacitySlider = opacitySlider
    y = y - 40

    -- Unfocused opacity
    local unfocusedCheck = CreateCheckbox(content, 15, y, "guiUnfocusedEnabled", "Reduce opacity when unfocused")
    frame.checks.guiUnfocusedEnabled = unfocusedCheck
    y = y - 26

    local unfocusedLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    unfocusedLabel:SetPoint("TOPLEFT", 35, y)
    unfocusedLabel:SetText("Unfocused Opacity:")

    -- Unfocused opacity slider (WotLK compatible)
    local unfocusedSlider = CreateFrame("Slider", "AIPUnfocusedOpacitySlider", content)
    unfocusedSlider:SetPoint("LEFT", unfocusedLabel, "RIGHT", 15, 0)
    unfocusedSlider:SetSize(120, 16)
    unfocusedSlider:SetOrientation("HORIZONTAL")
    unfocusedSlider:SetMinMaxValues(20, 90)
    unfocusedSlider:SetValueStep(5)
    unfocusedSlider:EnableMouseWheel(true)

    -- Slider background
    local unfocusedBg = unfocusedSlider:CreateTexture(nil, "BACKGROUND")
    unfocusedBg:SetAllPoints()
    unfocusedBg:SetTexture("Interface\\Buttons\\UI-SliderBar-Background")

    -- Slider thumb
    unfocusedSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local unfocusedThumb = unfocusedSlider:GetThumbTexture()
    unfocusedThumb:SetSize(32, 32)

    -- Low/High labels
    local unfocusedLow = unfocusedSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    unfocusedLow:SetPoint("TOPLEFT", unfocusedSlider, "BOTTOMLEFT", 0, 0)
    unfocusedLow:SetText("20%")

    local unfocusedHigh = unfocusedSlider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    unfocusedHigh:SetPoint("TOPRIGHT", unfocusedSlider, "BOTTOMRIGHT", 0, 0)
    unfocusedHigh:SetText("90%")

    local unfocusedValue = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    unfocusedValue:SetPoint("LEFT", unfocusedSlider, "RIGHT", 15, 0)
    unfocusedValue:SetText("60%")
    frame.unfocusedValue = unfocusedValue

    -- Set initial value
    local initUnfocused = (AIP.db and AIP.db.guiUnfocusedOpacity) and (AIP.db.guiUnfocusedOpacity * 100) or 60
    unfocusedSlider:SetValue(initUnfocused)
    unfocusedValue:SetText(math.floor(initUnfocused) .. "%")

    unfocusedSlider:SetScript("OnValueChanged", function(self, value)
        local actualValue = value / 100
        if AIP.db then
            AIP.db.guiUnfocusedOpacity = actualValue
        end
        unfocusedValue:SetText(math.floor(value) .. "%")
    end)

    unfocusedSlider:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetValue()
        local step = self:GetValueStep() or 5
        self:SetValue(current + (delta * step))
    end)

    frame.unfocusedSlider = unfocusedSlider
    y = y - 40

    -- ========================================================================
    -- [7] DEBUG & DATA
    -- ========================================================================
    local section7 = CreateSectionHeader(content, 5, y, "7", "DEBUG & DATA")
    y = y - 28

    local debugCheck = CreateCheckbox(content, 15, y, "debug", "Enable debug messages")
    frame.checks.debug = debugCheck

    local clearDataBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearDataBtn:SetSize(100, 22)
    clearDataBtn:SetPoint("LEFT", debugCheck, "RIGHT", 150, 0)
    clearDataBtn:SetText("Clear All Data")
    clearDataBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_DATA"] = {
            text = "Clear ALL AutoInvite+ data?\n\nThis includes blacklist, queue, waitlist, and settings.",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                AIP.db = nil
                ReloadUI()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_DATA")
    end)

    local resetBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetBtn:SetSize(110, 22)
    resetBtn:SetPoint("LEFT", clearDataBtn, "RIGHT", 10, 0)
    resetBtn:SetText("Reset to Defaults")
    resetBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_RESET_DEFAULTS"] = {
            text = "Reset all settings to defaults?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if AIP.ResetDefaults then
                    AIP.ResetDefaults()
                    SP.Update()
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_RESET_DEFAULTS")
    end)
    y = y - 30

    -- Quick actions
    local quickLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    quickLabel:SetPoint("TOPLEFT", 15, y)
    quickLabel:SetText("Quick Actions:")

    local invGuildBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    invGuildBtn:SetSize(90, 22)
    invGuildBtn:SetPoint("LEFT", quickLabel, "RIGHT", 10, 0)
    invGuildBtn:SetText("Invite Guild")
    invGuildBtn:SetScript("OnClick", function()
        if AIP.InviteGuild then AIP.InviteGuild() end
    end)

    local invFriendsBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    invFriendsBtn:SetSize(100, 22)
    invFriendsBtn:SetPoint("LEFT", invGuildBtn, "RIGHT", 10, 0)
    invFriendsBtn:SetText("Invite Friends")
    invFriendsBtn:SetScript("OnClick", function()
        if AIP.InviteFriends then AIP.InviteFriends() end
    end)

    SP.Frame = frame
    return frame
end

-- Toggle auto-spam
function SP.ToggleAutoSpam()
    if SP.AutoSpamActive then
        SP.StopAutoSpam()
    else
        SP.StartAutoSpam()
    end
end

-- Start auto-spam
function SP.StartAutoSpam()
    if SP.AutoSpamActive then return end
    SP.AutoSpamActive = true

    if not SP.AutoSpamTimer then
        SP.AutoSpamTimer = CreateFrame("Frame")
    end

    local interval = AIP.db and AIP.db.autoSpamInterval or 60
    SP.AutoSpamTimer.elapsed = interval  -- Trigger immediately
    SP.AutoSpamTimer.statusElapsed = 0

    SP.AutoSpamTimer:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        self.statusElapsed = self.statusElapsed + elapsed

        if self.statusElapsed >= 1 then
            self.statusElapsed = 0
            SP.UpdateAutoSpamStatus()
        end

        local currentInterval = AIP.db and AIP.db.autoSpamInterval or 60
        if self.elapsed >= currentInterval then
            self.elapsed = 0
            if AIP.SpamInvite then AIP.SpamInvite() end
        end
    end)

    if SP.Frame and SP.Frame.autoSpamBtn then
        SP.Frame.autoSpamBtn:SetText("Stop Auto-Spam")
    end
    SP.UpdateAutoSpamStatus()
    AIP.Print("Auto-spam started (interval: " .. interval .. "s)")
end

-- Stop auto-spam
function SP.StopAutoSpam()
    SP.AutoSpamActive = false
    if SP.AutoSpamTimer then
        SP.AutoSpamTimer:SetScript("OnUpdate", nil)
    end
    if SP.Frame and SP.Frame.autoSpamBtn then
        SP.Frame.autoSpamBtn:SetText("Start Auto-Spam")
    end
    if SP.Frame and SP.Frame.autoStatus then
        SP.Frame.autoStatus:SetText("|cFFFF0000Stopped|r")
    end
    AIP.Print("Auto-spam stopped")
end

-- Update auto-spam status
function SP.UpdateAutoSpamStatus()
    if not SP.Frame or not SP.Frame.autoStatus then return end
    if SP.AutoSpamActive and SP.AutoSpamTimer then
        local interval = AIP.db and AIP.db.autoSpamInterval or 60
        local remaining = math.max(0, interval - SP.AutoSpamTimer.elapsed)
        SP.Frame.autoStatus:SetText("|cFF00FF00Active|r - " .. math.floor(remaining) .. "s")
    else
        SP.Frame.autoStatus:SetText("|cFFFF0000Stopped|r")
    end
end

-- Update the settings panel
function SP.Update()
    if not SP.Frame or not AIP.db then return end

    local db = AIP.db

    -- Update checkboxes
    for key, check in pairs(SP.Frame.checks) do
        if key == "chatScan" then
            if AIP.LFMBrowser then
                check:SetChecked(AIP.LFMBrowser.Config.enabled)
            end
        elseif db[key] ~= nil then
            check:SetChecked(db[key])
        end
    end

    -- Update inputs (only if not focused)
    if SP.Frame.triggerInput and not SP.Frame.triggerInput:HasFocus() then
        SP.Frame.triggerInput:SetText(db.triggers or "")
    end
    if SP.Frame.msgInput and not SP.Frame.msgInput:HasFocus() then
        SP.Frame.msgInput:SetText(db.spamMessage or "")
    end
    if SP.Frame.cdInput and not SP.Frame.cdInput:HasFocus() then
        SP.Frame.cdInput:SetText(db.spamChannelCooldown or 10)
    end
    if SP.Frame.intervalInput and not SP.Frame.intervalInput:HasFocus() then
        SP.Frame.intervalInput:SetText(db.autoSpamInterval or 60)
    end
    if SP.Frame.maxInput and not SP.Frame.maxInput:HasFocus() then
        SP.Frame.maxInput:SetText(db.maxRaiders or 25)
    end
    if SP.Frame.cacheInput and not SP.Frame.cacheInput:HasFocus() then
        SP.Frame.cacheInput:SetText(db.cacheDuration or 15)
    end

    -- Response messages
    if SP.Frame.invRespInput and not SP.Frame.invRespInput:HasFocus() then
        SP.Frame.invRespInput:SetText(db.responseInvite or "")
    end
    if SP.Frame.rejRespInput and not SP.Frame.rejRespInput:HasFocus() then
        SP.Frame.rejRespInput:SetText(db.responseReject or "")
    end
    if SP.Frame.waitRespInput and not SP.Frame.waitRespInput:HasFocus() then
        SP.Frame.waitRespInput:SetText(db.responseWaitlist or "")
    end
    if SP.Frame.posRespInput and not SP.Frame.posRespInput:HasFocus() then
        SP.Frame.posRespInput:SetText(db.responseWaitlistPosition or "")
    end

    -- Update blacklist mode dropdown
    if SP.Frame.blModeDropdown then
        local modeText = (db.blacklistMode == "reject") and "Auto-Reject" or "Flag Only"
        UIDropDownMenu_SetText(SP.Frame.blModeDropdown, modeText)
    end

    -- Update auto-spam button
    if SP.Frame.autoSpamBtn then
        SP.Frame.autoSpamBtn:SetText(SP.AutoSpamActive and "Stop Auto-Spam" or "Start Auto-Spam")
    end
    SP.UpdateAutoSpamStatus()

    -- Update opacity sliders (values are in 0-100 range)
    if SP.Frame.opacitySlider then
        local opacityVal = (db.guiOpacity or 1.0) * 100
        SP.Frame.opacitySlider:SetValue(opacityVal)
        if SP.Frame.opacityValue then
            SP.Frame.opacityValue:SetText(math.floor(opacityVal) .. "%")
        end
    end
    if SP.Frame.unfocusedSlider then
        local unfocusedVal = (db.guiUnfocusedOpacity or 0.6) * 100
        SP.Frame.unfocusedSlider:SetValue(unfocusedVal)
        if SP.Frame.unfocusedValue then
            SP.Frame.unfocusedValue:SetText(math.floor(unfocusedVal) .. "%")
        end
    end
end

-- Show/Hide
function SP.Show()
    if SP.Frame then
        SP.Frame:Show()
        SP.Update()
    end
end

function SP.Hide()
    if SP.Frame then
        SP.Frame:Hide()
    end
end

-- Cleanup on logout
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:RegisterEvent("PLAYER_LOGOUT")
cleanupFrame:SetScript("OnEvent", function()
    SP.StopAutoSpam()
end)
