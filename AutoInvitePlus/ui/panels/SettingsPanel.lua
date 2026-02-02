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

-- Tooltip definitions - Comprehensive help for all settings
SP.Tooltips = {
    -- Section 1: Auto-Invite System
    autoInvite = "When enabled, players who whisper you with trigger keywords will be automatically invited.\n\nNote: If 'Use Queue' is enabled, players go to queue instead for manual review.\n\nExample: If your trigger is 'inv', anyone whispering 'inv' to you will be invited.\n\n|cFF00FF00Enable when:|r You're forming a group and want hands-free invites.",

    triggerKeywords = "Words that trigger an auto-invite when whispered to you.\n\nSeparate multiple keywords with semicolons (;).\n\nExamples:\n- 'inv' - Common trigger\n- 'inv;invite;123' - Multiple triggers\n- 'icc;rs' - Raid-specific triggers\n\n|cFF00FF00Tip:|r Short keywords like 'inv' are easiest for players to type.",

    maxGroupSize = "Maximum number of players allowed in your group.\n\n- Set to 5 for dungeons\n- Set to 10 for 10-man raids\n- Set to 25 for 25-man raids\n- Set to 40 for world events\n\nOnce this limit is reached, new whispers go to the waitlist instead.",

    autoRaid = "Automatically converts your party to a raid when the 6th player joins.\n\n|cFF00FF00Enable when:|r You're forming a raid and don't want to manually convert.\n\n|cFFFFFF00Note:|r Only works if you're the party leader.",

    guildOnly = "Only accept invites from players in your guild.\n\n|cFF00FF00Enable when:|r You're running a guild-only event and want to filter out non-guildies automatically.\n\nPlayers not in your guild who whisper the trigger will be ignored.",

    useQueue = "When enabled, players who whisper you with trigger keywords will be added to the QUEUE for manual review instead of being auto-invited.\n\nThis works independently - you don't need to enable 'Enable Auto-Invite'.\n\nThe queue panel will automatically open when someone joins.\n\n|cFF00FF00Enable when:|r You want to review players before inviting (check GS, class, etc.).",

    blacklistMode = "Controls how blacklisted players are handled:\n\n|cFFFFFFFFFlag Only:|r Shows blacklisted players in queue with a warning indicator. You can still manually invite them.\n\n|cFFFF4444Auto-Reject:|r Automatically rejects blacklisted players and sends them the rejection whisper.\n\n|cFF00FF00Tip:|r Use 'Flag Only' if you want to give players a second chance.",

    -- Section 2: Smart Auto-Invite Conditions
    smartConditions = "Advanced filtering for incoming invite requests.\n\nWhen enabled, you can set requirements for:\n- Minimum GearScore\n- Specific roles (Tank/Healer/DPS)\n- Role-based raid needs\n- Priority invites for favorites/guild\n\n|cFF00FF00Enable when:|r You want to automatically filter unqualified players.",

    minGearScore = "Minimum GearScore required to be invited.\n\nPlayers below this threshold will be rejected with a whisper.\n\n|cFFFFFFFFSet to 0:|r No minimum requirement\n|cFFFFFFFFExample values:|r\n- 4000: Heroic dungeons\n- 5000: Entry-level raids\n- 5500: ICC Normal\n- 6000: ICC Heroic\n\n|cFFFFFF00Note:|r Requires GearScore addon to be installed.",

    acceptRoles = "Filter invites by role.\n\nOnly players whose role matches your selection will be invited.\n\nRoles are detected from the player's talent spec when they're inspected.\n\n|cFF00FF00Tip:|r Uncheck roles you don't need (e.g., uncheck Tanks if full on tanks).",

    roleMatching = "Only invite players whose role AND class match your needs.\n\n|cFFFFFFFFHow it works:|r\n1. Checks if role slots are available (Tank/Healer/DPS)\n2. If you have 'Looking For' specs defined in your LFM, only those classes will be accepted\n\n|cFF00FFFFExample:|r If your LFM specifies 'Looking for: Paladin, Druid healers', a Shaman healer will be rejected.\n\n|cFF00FF00Enable when:|r You're recruiting specific classes/specs and want automatic filtering.\n\n|cFFFFFF00Note:|r Define your Looking For specs in the LFM popup to enable class filtering.",

    prioritySkipQueue = "Favorites and/or Guild members will bypass the queue and be invited immediately.\n\n- |cFFFFFFFFPrioritize Favorites:|r Players on your Favorites list skip queue\n- |cFFFFFFFFPrioritize Guild:|r Guild members skip queue\n\n|cFF00FF00Enable when:|r You want trusted players to get in faster.",

    -- Section 3: Queue Improvements
    queueSettings = "Configure how the invite queue behaves.\n\nThe queue holds players waiting to be invited, allowing you to review and accept/reject them manually.\n\n|cFF00FF00Tip:|r Combine with Smart Conditions for powerful filtering.",

    queueTimeout = "How long (in minutes) before players are automatically removed from the queue.\n\n|cFFFFFFFFSet to 0:|r Players stay in queue forever (until manually removed)\n|cFFFFFFFFRecommended:|r 10-15 minutes for pugs\n\n|cFF00FF00Tip:|r Set higher for progression raids where you need a bigger pool.",

    queueAutoProcess = "Automatically invite the next player from the queue when a raid slot opens up (someone leaves).\n\n|cFF00FF00Enable when:|r You want the queue to process itself without your input.\n\n|cFFFFFF00Note:|r Respects role filtering if Smart Conditions are enabled.",

    queueNotifyPosition = "Send players a whisper when they're added to the queue, telling them their position.\n\nAlso sends updates when their position changes (someone ahead of them left).\n\n|cFF00FF00Enable when:|r You want to keep players informed while they wait.",

    -- Section 4: Listen Channels
    listenChannels = "Select which chat channels to monitor.\n\nUsed for BOTH:\n- Detecting invite trigger keywords (auto-invite)\n- Scanning for LFM/LFG messages (browser)\n\n|cFFFFFFFFWhisper:|r Recommended for auto-invite triggers\n|cFFFFFFFFGlobal/World:|r Common on private servers\n|cFFFFFFFFFAll Joined:|r Auto-detect any custom channel\n\n|cFF00FF00Tip:|r Enable Trade/LFG for the best LFM/LFG scanning coverage.",

    -- Section 5: Broadcast Settings
    broadcastSettings = "Configure how and where your LFM messages are broadcast.\n\nMessages are sent to ALL selected channels simultaneously (not sequentially).\n\n|cFFFFFF00Warning:|r Be mindful of server spam rules. Most servers enforce minimum 60s between messages.",

    spamMessage = "The message that will be broadcast when you click 'Broadcast Now' or use Auto-Spam.\n\n|cFFFFFFFFSpecial tags:|r\n<key> - Replaced with your trigger keywords\n\n|cFFFFFFFFExample:|r\n'LFM ICC25 HC need healers! Whisper <key> for invite |AIP|'\n\n|cFF00FF00Tip:|r Keep it concise. Include GS requirements and trigger word.",

    spamCooldown = "Minimum seconds between broadcasts to the same channel.\n\nPrevents accidental spam if you click the button multiple times.\n\n|cFFFFFFFFRecommended:|r 15-30 seconds\n\n|cFFFFFF00Note:|r This is per-channel, not global.",

    autoSpamInterval = "How often (in seconds) Auto-Spam will broadcast your LFM message.\n\n|cFFFFFFFFMinimum:|r 60 seconds (to avoid chat bans)\n|cFFFFFFFFRecommended:|r 90-120 seconds\n\n|cFFFFFF00Warning:|r Some servers may still flag you for spam at 60s. Adjust based on your server's rules.",

    -- Section 6: LFM/LFG Scanner
    lfmScanner = "Scans chat for other players' LFM/LFG messages and displays them in the browser.\n\nUses the same Listen Channels settings from section 4.\n\nCache duration controls how long entries are kept.\n\n|cFF00FF00Enable when:|r You want to browse available groups instead of forming your own.",

    cacheDuration = "How long (in minutes) to keep scanned LFM/LFG messages in memory.\n\nOlder entries will be automatically removed.\n\n|cFFFFFFFFRecommended:|r 10-15 minutes\n|cFFFFFFFFShorter:|r Shows only very recent groups\n|cFFFFFFFFLonger:|r May show stale/filled groups",

    treeViewTimeout = "How long (in minutes) before entries in the LFM/LFG browser are marked as stale and hidden.\n\nStale entries appear grayed out before being removed.\n\n|cFFFFFFFFRecommended:|r 3-5 minutes\n\n|cFF00FF00Tip:|r Set shorter if you only want to see very active groups.",

    lootHistoryRetention = "How many days to keep loot history records.\n\nOlder records are automatically deleted on login.\n\n|cFFFFFFFFSet to 0:|r Keep forever (may use more memory)\n|cFFFFFFFFRecommended:|r 30-90 days\n\n|cFF00FF00Tip:|r Export important loot records before they expire.",

    -- Section 7: Response Messages
    responses = "Customize the automatic whisper messages sent when:\n- Inviting a player from queue\n- Rejecting a player\n- Adding to waitlist\n- Waitlist position changes\n\n|cFFFFFFFFUse %d|r for position number.\n|cFFFFFFFFLeave empty|r to disable that whisper.\n\n|cFF00FF00Tip:|r Keep messages professional. They represent you to other players.",

    -- Section 8: GUI Appearance
    guiAppearance = "Customize how the main AutoInvite+ window looks.\n\n|cFFFFFFFFOpacity:|r Controls window transparency (30-100%)\n|cFFFFFFFFUnfocused:|r Reduces opacity when not clicking on the window\n\n|cFF00FF00Tip:|r Set unfocused opacity lower if you want the window to fade into the background.",

    windowOpacity = "How transparent the main window is.\n\n|cFFFFFFFF100%:|r Fully solid (default)\n|cFFFFFFFF30%:|r Very transparent\n\n|cFF00FF00Tip:|r Lower opacity lets you see the game world behind the window.",

    unfocusedOpacity = "When 'Reduce opacity when unfocused' is enabled, this sets how transparent the window becomes when you're not actively using it.\n\n|cFFFFFFFFRecommended:|r 40-60%\n\nThe window returns to full opacity when you hover or click on it.",

    -- Section 9: Debug & Data
    debugMode = "Enable verbose debug messages in chat.\n\nShows detailed information about:\n- Incoming whispers and how they're processed\n- Auto-invite decisions\n- Scanner detections\n- Internal errors\n\n|cFF00FF00Enable when:|r Something isn't working and you need to troubleshoot.\n\n|cFFFF4444Warning:|r Can spam your chat. Disable when not debugging.",

    clearAllData = "Completely resets AutoInvite+ to a fresh installation state.\n\n|cFFFF4444Deletes EVERYTHING:|r\n- All settings\n- Blacklist\n- Favorites\n- Queue & Waitlist\n- Loot history\n- Saved templates\n\n|cFFFFFF00Use only when:|r You want a completely fresh start or encounter persistent bugs.",

    resetToDefaults = "Resets all settings to their default values while keeping your data.\n\n|cFF00FF00Preserves:|r Blacklist, Favorites, Loot History, Templates\n|cFFFFFF00Resets:|r All configuration options\n\nSafer than 'Clear All Data' if you just want default settings.",

    quickActions = "Quickly invite all online guild members or friends.\n\n|cFFFFFFFFInvite Guild:|r Sends invite to all online guildies\n|cFFFFFFFFInvite Friends:|r Sends invite to all online friends\n\n|cFFFFFF00Note:|r Respects your Max Group Size setting.",

    -- Section 10: Test Mode
    testMode = "Populate all panels with dummy test data to preview how the UI looks when filled.\n\n|cFF00FF00Use when:|r You want to see the layout with data without being in an actual raid.\n\n|cFFFFFFFFPopulate:|r Adds fake players, groups, loot, etc.\n|cFFFFFFFFClear:|r Removes all test data\n\n|cFFFFFF00Note:|r Test data is NOT saved. It's cleared on logout.",
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

-- Helper: Create section header (uses dynamic width via right anchor)
local function CreateSectionHeader(parent, x, y, num, text)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", x, y)
    frame:SetPoint("RIGHT", parent, "RIGHT", -10, 0)  -- Dynamic width
    frame:SetHeight(22)

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
    content:SetHeight(1500)  -- Height for all sections including test mode
    scrollFrame:SetScrollChild(content)

    -- Dynamic width - initially set and updated on resize
    local function UpdateContentWidth()
        local scrollWidth = scrollFrame:GetWidth() or 620
        local newWidth = math.max(scrollWidth - 10, 580)
        content:SetWidth(newWidth)
    end

    -- Initial width setup
    content:SetWidth(620)

    -- Hook into scroll frame size changes for dynamic width
    scrollFrame:HookScript("OnSizeChanged", function(self, w, h)
        if content then
            local newWidth = math.max(w - 10, 580)
            content:SetWidth(newWidth)
        end
    end)

    -- Parent frame resize handler
    frame:SetScript("OnSizeChanged", function(self, width, height)
        SP.OnResize(width, height)
    end)

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

    local triggerTooltip = CreateTooltipButton(content, "triggerKeywords")
    triggerTooltip:SetPoint("LEFT", triggerLabel, "RIGHT", 2, 0)

    local triggerInput, triggerContainer = CreateStyledEditBox(content, 160, 16, false)
    triggerContainer:SetPoint("LEFT", triggerTooltip, "RIGHT", 2, 0)
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

    local maxTooltip = CreateTooltipButton(content, "maxGroupSize")
    maxTooltip:SetPoint("LEFT", maxLabel, "RIGHT", 2, 0)

    local maxInput, maxContainer = CreateStyledEditBox(content, 30, 16, true)
    maxContainer:SetPoint("LEFT", maxTooltip, "RIGHT", 2, 0)
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
    local autoRaidCheck, autoRaidLabel = CreateCheckbox(content, 160, y, "autoRaid", "Auto-convert to raid")
    frame.checks.autoRaid = autoRaidCheck
    local autoRaidTooltip = CreateTooltipButton(content, "autoRaid")
    autoRaidTooltip:SetPoint("LEFT", autoRaidLabel, "RIGHT", 2, 0)

    local guildOnlyCheck, guildOnlyLabel = CreateCheckbox(content, 345, y, "guildOnly", "Guild only")
    frame.checks.guildOnly = guildOnlyCheck
    local guildOnlyTooltip = CreateTooltipButton(content, "guildOnly")
    guildOnlyTooltip:SetPoint("LEFT", guildOnlyLabel, "RIGHT", 2, 0)
    y = y - 26

    -- Queue mode
    local useQueueCheck, useQueueLabel = CreateCheckbox(content, 15, y, "useQueue", "Use Queue (require manual approval before invite)")
    frame.checks.useQueue = useQueueCheck
    local useQueueTooltip = CreateTooltipButton(content, "useQueue")
    useQueueTooltip:SetPoint("LEFT", useQueueLabel, "RIGHT", 5, 0)
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
    -- [2] SMART AUTO-INVITE CONDITIONS
    -- ========================================================================
    local section2 = CreateSectionHeader(content, 5, y, "2", "SMART AUTO-INVITE CONDITIONS")
    local tooltip2 = CreateTooltipButton(content, "smartConditions")
    tooltip2:SetPoint("LEFT", section2, "RIGHT", 5, 0)
    y = y - 28

    local smartEnableCheck = CreateCheckbox(content, 15, y, nil, "Enable Smart Conditions", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.enabled = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.smartInviteEnabled = smartEnableCheck

    local smartHelp = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    smartHelp:SetPoint("LEFT", smartEnableCheck, "RIGHT", 180, 0)
    smartHelp:SetText("|cFF888888(filter invites by GS, role, class)|r")
    y = y - 26

    -- Min GS threshold
    local minGSLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minGSLabel:SetPoint("TOPLEFT", 35, y)
    minGSLabel:SetText("Min GearScore:")

    local minGSTooltip = CreateTooltipButton(content, "minGearScore")
    minGSTooltip:SetPoint("LEFT", minGSLabel, "RIGHT", 2, 0)

    local minGSInput, minGSContainer = CreateStyledEditBox(content, 45, 16, true)
    minGSContainer:SetPoint("LEFT", minGSTooltip, "RIGHT", 2, 0)
    minGSInput:SetScript("OnEnterPressed", function(self)
        if AIP.db and AIP.db.smartInvite then
            local val = tonumber(self:GetText()) or 0
            AIP.db.smartInvite.minGS = math.max(0, math.min(10000, val))
            self:SetText(AIP.db.smartInvite.minGS)
        end
        self:ClearFocus()
    end)
    frame.minGSInput = minGSInput

    local minGSNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    minGSNote:SetPoint("LEFT", minGSContainer, "RIGHT", 10, 0)
    minGSNote:SetText("|cFF888888(0 = no minimum)|r")
    y = y - 26

    -- Role filtering
    local roleFilterLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleFilterLabel:SetPoint("TOPLEFT", 35, y)
    roleFilterLabel:SetText("Accept Roles:")

    local acceptRolesTooltip = CreateTooltipButton(content, "acceptRoles")
    acceptRolesTooltip:SetPoint("LEFT", roleFilterLabel, "RIGHT", 2, 0)

    local acceptTanksCheck = CreateCheckbox(content, 145, y, nil, "Tanks", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.acceptTanks = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.acceptTanks = acceptTanksCheck

    local acceptHealersCheck = CreateCheckbox(content, 215, y, nil, "Healers", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.acceptHealers = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.acceptHealers = acceptHealersCheck

    local acceptDPSCheck = CreateCheckbox(content, 310, y, nil, "DPS", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.acceptDPS = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.acceptDPS = acceptDPSCheck
    y = y - 26

    -- Role matching
    local roleMatchCheck, roleMatchLabel = CreateCheckbox(content, 35, y, nil, "Role matching (only accept players whose role matches raid needs)", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.roleMatching = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.roleMatching = roleMatchCheck
    local roleMatchTooltip = CreateTooltipButton(content, "roleMatching")
    roleMatchTooltip:SetPoint("LEFT", roleMatchLabel, "RIGHT", 2, 0)
    y = y - 26

    -- Priority options
    local priorityLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    priorityLabel:SetPoint("TOPLEFT", 35, y)
    priorityLabel:SetText("Priority Skip Queue:")

    local priorityTooltip = CreateTooltipButton(content, "prioritySkipQueue")
    priorityTooltip:SetPoint("LEFT", priorityLabel, "RIGHT", 2, 0)

    local prioritizeFavCheck = CreateCheckbox(content, 160, y, nil, "Favorites", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.prioritizeFavorites = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.prioritizeFavorites = prioritizeFavCheck

    local prioritizeGuildCheck = CreateCheckbox(content, 270, y, nil, "Guild Members", function(self)
        if AIP.db and AIP.db.smartInvite then
            AIP.db.smartInvite.prioritizeGuild = self:GetChecked() == 1 or self:GetChecked() == true
        end
    end)
    frame.checks.prioritizeGuild = prioritizeGuildCheck
    y = y - 35

    -- ========================================================================
    -- [3] QUEUE IMPROVEMENTS
    -- ========================================================================
    local section3 = CreateSectionHeader(content, 5, y, "3", "QUEUE IMPROVEMENTS")
    local tooltip3 = CreateTooltipButton(content, "queueSettings")
    tooltip3:SetPoint("LEFT", section3, "RIGHT", 5, 0)
    y = y - 28

    -- Queue timeout
    local timeoutLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeoutLabel:SetPoint("TOPLEFT", 15, y)
    timeoutLabel:SetText("Queue Timeout:")

    local timeoutTooltip = CreateTooltipButton(content, "queueTimeout")
    timeoutTooltip:SetPoint("LEFT", timeoutLabel, "RIGHT", 2, 0)

    local timeoutInput, timeoutContainer = CreateStyledEditBox(content, 30, 16, true)
    timeoutContainer:SetPoint("LEFT", timeoutTooltip, "RIGHT", 2, 0)
    timeoutInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 0
            AIP.db.queueTimeout = math.max(0, math.min(120, val))
            self:SetText(AIP.db.queueTimeout)
        end
        self:ClearFocus()
    end)
    frame.timeoutInput = timeoutInput

    local timeoutSuffix = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timeoutSuffix:SetPoint("LEFT", timeoutContainer, "RIGHT", 5, 0)
    timeoutSuffix:SetText("minutes |cFF888888(0 = no timeout)|r")
    y = y - 26

    -- Auto-process queue
    local autoProcessCheck, autoProcessLabel = CreateCheckbox(content, 15, y, "queueAutoProcess", "Auto-process queue when raid slots open")
    frame.checks.queueAutoProcess = autoProcessCheck
    local autoProcessTooltip = CreateTooltipButton(content, "queueAutoProcess")
    autoProcessTooltip:SetPoint("LEFT", autoProcessLabel, "RIGHT", 2, 0)
    y = y - 26

    -- Notify position
    local notifyPosCheck, notifyPosLabel = CreateCheckbox(content, 15, y, "queueNotifyPosition", "Notify players of their queue position via whisper")
    frame.checks.queueNotifyPosition = notifyPosCheck
    local notifyPosTooltip = CreateTooltipButton(content, "queueNotifyPosition")
    notifyPosTooltip:SetPoint("LEFT", notifyPosLabel, "RIGHT", 2, 0)
    y = y - 35

    -- ========================================================================
    -- [4] LISTEN CHANNELS
    -- ========================================================================
    local section4 = CreateSectionHeader(content, 5, y, "4", "LISTEN CHANNELS")
    local tooltip4 = CreateTooltipButton(content, "listenChannels")
    tooltip4:SetPoint("LEFT", section4, "RIGHT", 5, 0)
    y = y - 20

    local section4Subtitle = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    section4Subtitle:SetPoint("TOPLEFT", 15, y)
    section4Subtitle:SetText("|cFF888888Used for auto-invite triggers and LFM/LFG browser scanning|r")
    y = y - 18

    -- Row 1: Basic channels
    local listenChannelsRow1 = {
        {key = "listenWhisper", text = "Whisper"},
        {key = "listenSay", text = "Say"},
        {key = "listenYell", text = "Yell"},
        {key = "listenGuild", text = "Guild"},
    }

    local col = 0
    for _, ch in ipairs(listenChannelsRow1) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 24

    -- Row 2: Public channels
    local listenChannelsRow2 = {
        {key = "listenGeneral", text = "General"},
        {key = "listenTrade", text = "Trade"},
        {key = "listenLFG", text = "LFG"},
        {key = "listenDefense", text = "Defense"},
    }

    col = 0
    for _, ch in ipairs(listenChannelsRow2) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 24

    -- Row 3: Custom channels (common on private servers)
    local listenChannelsRow3 = {
        {key = "listenGlobal", text = "Global"},
        {key = "listenWorld", text = "World"},
        {key = "listenAllJoined", text = "All Joined"},
    }

    col = 0
    for _, ch in ipairs(listenChannelsRow3) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end

    -- Add tooltip for "All Joined"
    local allJoinedTooltip = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    allJoinedTooltip:SetPoint("TOPLEFT", 320, y + 2)
    allJoinedTooltip:SetText("|cFF888888(auto-detect all channels)|r")
    y = y - 30

    -- ========================================================================
    -- [5] BROADCAST SETTINGS
    -- ========================================================================
    local section5 = CreateSectionHeader(content, 5, y, "5", "BROADCAST SETTINGS - Spam your LFM message")
    local tooltip5 = CreateTooltipButton(content, "broadcastSettings")
    tooltip5:SetPoint("LEFT", section5, "RIGHT", 5, 0)
    y = y - 28

    -- Spam channels Row 1: Basic channels (matching listen layout)
    local spamChannelsRow1 = {
        {key = "spamSay", text = "Say"},
        {key = "spamYell", text = "Yell"},
        {key = "spamGuild", text = "Guild"},
    }

    col = 0
    for _, ch in ipairs(spamChannelsRow1) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 24

    -- Spam channels Row 2: Public channels (matching listen layout)
    local spamChannelsRow2 = {
        {key = "spamGeneral", text = "General"},
        {key = "spamTrade", text = "Trade"},
        {key = "spamLFG", text = "LFG"},
        {key = "spamDefense", text = "Defense"},
    }

    col = 0
    for _, ch in ipairs(spamChannelsRow2) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end
    y = y - 24

    -- Spam channels Row 3: Private server channels (matching listen layout)
    local spamChannelsRow3 = {
        {key = "spamGlobal", text = "Global"},
        {key = "spamWorld", text = "World"},
        {key = "spamAllJoined", text = "All Joined"},
    }

    col = 0
    for _, ch in ipairs(spamChannelsRow3) do
        local check = CreateCheckbox(content, 15 + col * 100, y, ch.key, ch.text)
        frame.checks[ch.key] = check
        col = col + 1
    end

    -- Add tooltip for "All Joined" broadcast
    local spamAllJoinedTooltip = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    spamAllJoinedTooltip:SetPoint("TOPLEFT", 320, y + 2)
    spamAllJoinedTooltip:SetText("|cFF888888(broadcast to all channels)|r")
    y = y - 26

    -- Spam message
    local msgLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgLabel:SetPoint("TOPLEFT", 15, y)
    msgLabel:SetText("Message:")

    local msgTooltip = CreateTooltipButton(content, "spamMessage")
    msgTooltip:SetPoint("LEFT", msgLabel, "RIGHT", 2, 0)

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

    local cdTooltip = CreateTooltipButton(content, "spamCooldown")
    cdTooltip:SetPoint("LEFT", cdLabel, "RIGHT", 2, 0)

    local cdInput, cdContainer = CreateStyledEditBox(content, 30, 16, true)
    cdContainer:SetPoint("LEFT", cdTooltip, "RIGHT", 2, 0)
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

    local intervalTooltip = CreateTooltipButton(content, "autoSpamInterval")
    intervalTooltip:SetPoint("LEFT", intervalSuffix, "RIGHT", 5, 0)

    local autoStatus = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoStatus:SetPoint("LEFT", intervalTooltip, "RIGHT", 10, 0)
    autoStatus:SetText("")
    frame.autoStatus = autoStatus
    y = y - 40

    -- ========================================================================
    -- [6] LFM/LFG SCANNER
    -- ========================================================================
    local section6 = CreateSectionHeader(content, 5, y, "6", "LFM/LFG SCANNER")
    local tooltip6 = CreateTooltipButton(content, "lfmScanner")
    tooltip6:SetPoint("LEFT", section6, "RIGHT", 5, 0)
    y = y - 28

    local scanCheck = CreateCheckbox(content, 15, y, nil, "Enable chat scanning for LFM/LFG browser", function(self)
        if AIP.LFMBrowser then
            AIP.LFMBrowser.Config.enabled = self:GetChecked()
        end
    end)
    frame.checks.chatScan = scanCheck

    local scanNote = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scanNote:SetPoint("LEFT", scanCheck, "RIGHT", 150, 0)
    scanNote:SetText("|cFF888888(Uses Listen Channels from section 4)|r")
    y = y - 26

    -- Cache duration
    local cacheLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cacheLabel:SetPoint("TOPLEFT", 15, y)
    cacheLabel:SetText("Cache Duration:")

    local cacheTooltip = CreateTooltipButton(content, "cacheDuration")
    cacheTooltip:SetPoint("LEFT", cacheLabel, "RIGHT", 2, 0)

    local cacheInput, cacheContainer = CreateStyledEditBox(content, 30, 16, true)
    cacheContainer:SetPoint("LEFT", cacheTooltip, "RIGHT", 2, 0)
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
    y = y - 26

    -- Tree view stale timeout
    local staleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    staleLabel:SetPoint("TOPLEFT", 15, y)
    staleLabel:SetText("Tree View Timeout:")

    local staleTooltip = CreateTooltipButton(content, "treeViewTimeout")
    staleTooltip:SetPoint("LEFT", staleLabel, "RIGHT", 2, 0)

    local staleInput, staleContainer = CreateStyledEditBox(content, 30, 16, true)
    staleContainer:SetPoint("LEFT", staleTooltip, "RIGHT", 2, 0)
    staleInput:SetText(AIP.TreeBrowser and AIP.TreeBrowser.StaleTimeout and math.floor(AIP.TreeBrowser.StaleTimeout / 60) or 3)
    staleInput:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText()) or 3
        val = math.max(1, math.min(30, val))  -- 1-30 minutes
        self:SetText(val)
        if AIP.TreeBrowser then
            AIP.TreeBrowser.StaleTimeout = val * 60  -- Convert to seconds
        end
        if AIP.db then
            AIP.db.treeStaleTimeout = val * 60
        end
        self:ClearFocus()
        -- Refresh browser tabs
        if AIP.CentralGUI and AIP.CentralGUI.RefreshBrowserTab then
            AIP.CentralGUI.RefreshBrowserTab("lfm")
            AIP.CentralGUI.RefreshBrowserTab("lfg")
        end
    end)
    frame.staleInput = staleInput

    local staleSuffix = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    staleSuffix:SetPoint("LEFT", staleContainer, "RIGHT", 5, 0)
    staleSuffix:SetText("minutes  |cFF888888(hide entries older than this)|r")
    y = y - 26

    -- Loot History Retention
    local lootRetLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootRetLabel:SetPoint("TOPLEFT", 15, y)
    lootRetLabel:SetText("Loot History Retention:")

    local lootRetTooltip = CreateTooltipButton(content, "lootHistoryRetention")
    lootRetTooltip:SetPoint("LEFT", lootRetLabel, "RIGHT", 2, 0)

    local lootRetInput, lootRetContainer = CreateStyledEditBox(content, 30, 16, true)
    lootRetContainer:SetPoint("LEFT", lootRetTooltip, "RIGHT", 2, 0)
    lootRetInput:SetScript("OnEnterPressed", function(self)
        if AIP.db then
            local val = tonumber(self:GetText()) or 30
            AIP.db.lootHistoryRetentionDays = math.max(0, math.min(365, val))
            self:SetText(AIP.db.lootHistoryRetentionDays)
        end
        self:ClearFocus()
    end)
    frame.lootRetInput = lootRetInput

    local lootRetSuffix = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootRetSuffix:SetPoint("LEFT", lootRetContainer, "RIGHT", 5, 0)
    lootRetSuffix:SetText("days |cFF888888(0 = keep forever)|r")
    y = y - 40

    -- ========================================================================
    -- [7] RESPONSE MESSAGES
    -- ========================================================================
    local section7 = CreateSectionHeader(content, 5, y, "7", "RESPONSE MESSAGES")
    local tooltip7 = CreateTooltipButton(content, "responses")
    tooltip7:SetPoint("LEFT", section7, "RIGHT", 5, 0)
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
    -- [8] GUI APPEARANCE
    -- ========================================================================
    local section8 = CreateSectionHeader(content, 5, y, "8", "GUI APPEARANCE")
    local tooltip8 = CreateTooltipButton(content, "guiAppearance")
    tooltip8:SetPoint("LEFT", section8, "RIGHT", 5, 0)
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

    -- Set initial value (clamp to 0-100 range)
    local initOpacity = (AIP.db and AIP.db.guiOpacity) and math.min(100, math.max(0, AIP.db.guiOpacity * 100)) or 100
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
    -- [9] DEBUG & DATA
    -- ========================================================================
    local section9 = CreateSectionHeader(content, 5, y, "9", "DEBUG & DATA")
    local tooltip9 = CreateTooltipButton(content, "debugMode")
    tooltip9:SetPoint("LEFT", section9, "RIGHT", 5, 0)
    y = y - 28

    local debugCheck, debugLabel = CreateCheckbox(content, 15, y, "debug", "Enable debug messages")
    frame.checks.debug = debugCheck
    local debugTooltip = CreateTooltipButton(content, "debugMode")
    debugTooltip:SetPoint("LEFT", debugLabel, "RIGHT", 2, 0)

    local clearDataBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearDataBtn:SetSize(100, 22)
    clearDataBtn:SetPoint("LEFT", debugCheck, "RIGHT", 170, 0)
    clearDataBtn:SetText("Clear All Data")
    clearDataBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_DATA"] = {
            text = "FULL RESET: Clear ALL AutoInvite+ data?\n\n|cFFFF4444This will remove:|r\n- All settings\n- Blacklist\n- Favorites\n- Queue & Waitlist\n- Loot history\n- Raid sessions\n- Saved templates\n\nThe addon will reload as if freshly installed.",
            button1 = "Yes, Reset Everything",
            button2 = "Cancel",
            OnAccept = function()
                -- Clear the entire saved variables
                AutoInvitePlusDB = nil
                AIP.db = nil
                -- Clear any cached UI state
                if AIP.ChatScanner then
                    AIP.ChatScanner.Groups = {}
                    AIP.ChatScanner.Players = {}
                end
                if AIP.CentralGUI then
                    AIP.CentralGUI.LfgEnrollments = {}
                    AIP.CentralGUI.MyEnrollment = nil
                    AIP.CentralGUI.MyGroup = nil
                end
                if AIP.TreeBrowser then
                    AIP.TreeBrowser.TreeData = {expandedNodes = {}, selectedNode = nil}
                end
                -- Reload the UI to reinitialize everything
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
            text = "Reset settings to defaults?\n\n|cFF00FF00This keeps:|r Blacklist, Favorites, Loot History\n|cFFFFFF00This resets:|r All settings to default values",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                -- Only reset settings, keep data lists
                local savedBlacklist = AIP.db.blacklist
                local savedFavorites = AIP.db.favorites
                local savedQueue = AIP.db.queue
                local savedWaitlist = AIP.db.waitlist
                local savedLootHistory = AIP.db.lootHistory
                local savedRaidSessions = AIP.db.raidSessions
                local savedLfmTemplates = AIP.db.lfmTemplates
                local savedRaidWarningTemplates = AIP.db.raidWarningTemplates

                -- Reset to defaults
                if AIP.ResetDefaults then
                    AIP.ResetDefaults()
                end

                -- Restore data lists
                AIP.db.blacklist = savedBlacklist or {}
                AIP.db.favorites = savedFavorites or {}
                AIP.db.queue = savedQueue or {}
                AIP.db.waitlist = savedWaitlist or {}
                AIP.db.lootHistory = savedLootHistory or {}
                AIP.db.raidSessions = savedRaidSessions or {}
                AIP.db.lfmTemplates = savedLfmTemplates
                AIP.db.raidWarningTemplates = savedRaidWarningTemplates

                SP.Update()
                AIP.Print("Settings reset to defaults. Data preserved.")
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

    local quickTooltip = CreateTooltipButton(content, "quickActions")
    quickTooltip:SetPoint("LEFT", quickLabel, "RIGHT", 2, 0)

    local invGuildBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    invGuildBtn:SetSize(90, 22)
    invGuildBtn:SetPoint("LEFT", quickTooltip, "RIGHT", 5, 0)
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
    y = y - 40

    -- ========================================================================
    -- [10] TEST MODE
    -- ========================================================================
    local section10 = CreateSectionHeader(content, 5, y, "10", "TEST MODE")
    local tooltip10 = CreateTooltipButton(content, "testMode")
    tooltip10:SetPoint("LEFT", section10, "RIGHT", 5, 0)
    y = y - 28

    local testModeInfo = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    testModeInfo:SetPoint("TOPLEFT", 15, y)
    testModeInfo:SetText("Populate all sections with dummy data for testing UI layouts.")
    testModeInfo:SetTextColor(0.6, 0.6, 0.6)
    y = y - 22

    local populateTestBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    populateTestBtn:SetSize(140, 22)
    populateTestBtn:SetPoint("TOPLEFT", 15, y)
    populateTestBtn:SetText("Populate Test Data")
    populateTestBtn:SetScript("OnClick", function()
        SP.PopulateTestData()
        AIP.Print("|cFF00FF00Test data populated!|r Check all tabs.")
    end)

    local clearTestBtn = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    clearTestBtn:SetSize(120, 22)
    clearTestBtn:SetPoint("LEFT", populateTestBtn, "RIGHT", 10, 0)
    clearTestBtn:SetText("Clear Test Data")
    clearTestBtn:SetScript("OnClick", function()
        SP.ClearTestData()
        AIP.Print("|cFFFF6666Test data cleared!|r")
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

    -- Update smart invite settings (nested in smartInvite table)
    if db.smartInvite then
        if SP.Frame.checks.smartInviteEnabled then
            SP.Frame.checks.smartInviteEnabled:SetChecked(db.smartInvite.enabled)
        end
        if SP.Frame.checks.acceptTanks then
            SP.Frame.checks.acceptTanks:SetChecked(db.smartInvite.acceptTanks)
        end
        if SP.Frame.checks.acceptHealers then
            SP.Frame.checks.acceptHealers:SetChecked(db.smartInvite.acceptHealers)
        end
        if SP.Frame.checks.acceptDPS then
            SP.Frame.checks.acceptDPS:SetChecked(db.smartInvite.acceptDPS)
        end
        if SP.Frame.checks.roleMatching then
            SP.Frame.checks.roleMatching:SetChecked(db.smartInvite.roleMatching)
        end
        if SP.Frame.checks.prioritizeFavorites then
            SP.Frame.checks.prioritizeFavorites:SetChecked(db.smartInvite.prioritizeFavorites)
        end
        if SP.Frame.checks.prioritizeGuild then
            SP.Frame.checks.prioritizeGuild:SetChecked(db.smartInvite.prioritizeGuild)
        end
        if SP.Frame.minGSInput and not SP.Frame.minGSInput:HasFocus() then
            SP.Frame.minGSInput:SetText(db.smartInvite.minGS or 0)
        end
    end

    -- Update queue improvement settings
    if SP.Frame.timeoutInput and not SP.Frame.timeoutInput:HasFocus() then
        SP.Frame.timeoutInput:SetText(db.queueTimeout or 0)
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
    if SP.Frame.staleInput and not SP.Frame.staleInput:HasFocus() then
        local staleMin = (db.treeStaleTimeout or 180) / 60
        SP.Frame.staleInput:SetText(math.floor(staleMin))
    end
    if SP.Frame.lootRetInput and not SP.Frame.lootRetInput:HasFocus() then
        SP.Frame.lootRetInput:SetText(db.lootHistoryRetentionDays or 30)
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

-- ============================================================================
-- TEST MODE FUNCTIONS
-- ============================================================================

-- Populate all sections with dummy test data
function SP.PopulateTestData()
    if not AIP.db then return end

    AIP.Print("|cFF00FF00Populating test data...|r")

    -- ========================================================================
    -- RAID MGMT TAB - Reserved Items
    -- ========================================================================
    AIP.db.reservedItems = "Shadowmourne\nInvincible's Reins\nDeathbringer's Will\nHeroic Trinkets"

    -- ========================================================================
    -- RAID MGMT TAB - Loot Bans
    -- ========================================================================
    AIP.db.lootBans = {
        {player = "Ninjaplayer", boss = "Lich King", item = "Shadowmourne", itemLink = nil},
        {player = "Guildalt", boss = "Sindragosa", item = "Phylactery", itemLink = nil},
        {player = "Pug", boss = "Blood Queen", item = "Bloodfall", itemLink = nil},
        {player = "Raidmember", boss = "Festergut", item = "Unidentifiable Organ", itemLink = nil},
    }

    -- ========================================================================
    -- RAID MGMT TAB - MS/OS Tracking
    -- ========================================================================
    AIP.db.msTracking = {
        ["Tankadin"] = {ms = "Protection", os = "Retribution"},
        ["Holypally"] = {ms = "Holy", os = "Protection"},
        ["Furywar"] = {ms = "Fury", os = "Arms"},
        ["Shadowpriest"] = {ms = "Shadow", os = "Holy"},
        ["Arcanemage"] = {ms = "Arcane", os = "Fire"},
        ["Restodruid"] = {ms = "Restoration", os = "Balance"},
        ["Dkfrost"] = {ms = "Frost", os = "Unholy"},
        ["Huntermark"] = {ms = "Marksmanship", os = "Survival"},
    }

    -- ========================================================================
    -- BLACKLIST TAB
    -- ========================================================================
    if AIP.Blacklist and AIP.Blacklist.Add then
        AIP.Blacklist.Add("Ninjalooter", "Stole guild bank items")
        AIP.Blacklist.Add("Afkguy", "AFK during boss fights, wiped raid")
        AIP.Blacklist.Add("Toxicplayer", "Harassed raid members")
        AIP.Blacklist.Add("Botkiller", "Left during progression, ragequit")
        AIP.Blacklist.Add("Scammer", "Sold fake GDKP items")
    end

    -- ========================================================================
    -- FAVORITES TAB
    -- ========================================================================
    if AIP.Favorites and AIP.Favorites.Add then
        AIP.Favorites.Add("Bestpriest", "Amazing disc priest, 6.2k GS, never dies")
        AIP.Favorites.Add("Maintank", "Guild MT, knows all fights perfectly")
        AIP.Favorites.Add("Prolock", "Top DPS warlock, has summons ready")
        AIP.Favorites.Add("Clutchhealer", "Saves raids with quick heals")
        AIP.Favorites.Add("Guildmaster", "Always helpful, great leader")
    end

    -- ========================================================================
    -- LFM BROWSER TAB - Queue
    -- ========================================================================
    if AIP.Queue and AIP.Queue.Add then
        AIP.Queue.Add("Queuedwarrior", {gs = 5800, role = "DPS", class = "WARRIOR", spec = "Fury"})
        AIP.Queue.Add("Queuedpriest", {gs = 5600, role = "HEALER", class = "PRIEST", spec = "Holy"})
        AIP.Queue.Add("Queueddk", {gs = 6000, role = "TANK", class = "DEATHKNIGHT", spec = "Blood"})
        AIP.Queue.Add("Queuedmage", {gs = 5700, role = "DPS", class = "MAGE", spec = "Arcane"})
        AIP.Queue.Add("Queuedrogue", {gs = 5500, role = "DPS", class = "ROGUE", spec = "Combat"})
    end

    -- ========================================================================
    -- LFM BROWSER TAB - Waitlist
    -- ========================================================================
    if AIP.Waitlist and AIP.Waitlist.Add then
        AIP.Waitlist.Add("Waitingshaman", {gs = 5400, role = "HEALER", class = "SHAMAN"})
        AIP.Waitlist.Add("Waitingdruid", {gs = 5300, role = "DPS", class = "DRUID"})
    end

    -- ========================================================================
    -- LFM BROWSER TAB - LFM Groups
    -- ========================================================================
    if AIP.GroupTracker then
        AIP.GroupTracker.Groups = {}  -- Clear first
        if AIP.GroupTracker.AddGroup then
            -- ICC 25 Heroic
            AIP.GroupTracker.AddGroup({
                leader = "Iccleader",
                raid = "ICC25H",
                message = "LFM ICC25 HC [T:1/2 H:4/6 M:5/8 R:6/9] 5800+ [T:BD,BDK H:HPal,RS,RD M:Ret,Rog,Enh R:Mag,SP,Ele] w/ \"inv\" - LK exp req",
                gsMin = 5800,
                tanks = {current = 1, needed = 2},
                healers = {current = 4, needed = 6},
                mdps = {current = 5, needed = 8},
                rdps = {current = 6, needed = 9},
                roleSpecs = {
                    TANK = {"BD", "BDK"},
                    HEALER = {"HPal", "RS", "RD"},
                    MDPS = {"Ret", "Rog", "Enh"},
                    RDPS = {"Mag", "SP", "Ele"},
                },
                inviteKeyword = "inv",
                time = time(),
            })
            -- ICC 25 Normal
            AIP.GroupTracker.AddGroup({
                leader = "Casualraider",
                raid = "ICC25N",
                message = "LFM ICC25 Normal [T:2/2 H:3/6 M:4/8 R:4/9] 5000+ [T:PP,PW H:HP,DP M:DK,FW R:Hun,Loc] w/ \"123\"",
                gsMin = 5000,
                tanks = {current = 2, needed = 2},
                healers = {current = 3, needed = 6},
                mdps = {current = 4, needed = 8},
                rdps = {current = 4, needed = 9},
                roleSpecs = {
                    TANK = {"PP", "PW"},
                    HEALER = {"HP", "DP"},
                    MDPS = {"DK", "FW"},
                    RDPS = {"Hun", "Loc"},
                },
                inviteKeyword = "123",
                time = time() - 120,
            })
            -- ICC 10 Heroic
            AIP.GroupTracker.AddGroup({
                leader = "Smallgroup",
                raid = "ICC10H",
                message = "LFM ICC10 HC [T:1/2 H:2/3 M:2/3 R:2/2] 5500+ [H:HPal M:Ret R:Boom] LK kill achiev",
                gsMin = 5500,
                tanks = {current = 1, needed = 2},
                healers = {current = 2, needed = 3},
                mdps = {current = 2, needed = 3},
                rdps = {current = 2, needed = 2},
                roleSpecs = {
                    TANK = {},
                    HEALER = {"HPal"},
                    MDPS = {"Ret"},
                    RDPS = {"Boom"},
                },
                time = time() - 180,
            })
            -- Ruby Sanctum
            AIP.GroupTracker.AddGroup({
                leader = "Rsleader",
                raid = "RS25H",
                message = "LFM RS25 Heroic [T:0/2 H:2/6 M:3/8 R:4/9] 5700+ [T:BD,PP,PW H:RS,RD M:Enh R:Ele] need tanks!",
                gsMin = 5700,
                tanks = {current = 0, needed = 2},
                healers = {current = 2, needed = 6},
                mdps = {current = 3, needed = 8},
                rdps = {current = 4, needed = 9},
                roleSpecs = {
                    TANK = {"BD", "PP", "PW"},
                    HEALER = {"RS", "RD"},
                    MDPS = {"Enh"},
                    RDPS = {"Ele"},
                },
                time = time() - 60,
            })
            -- TOC 25
            AIP.GroupTracker.AddGroup({
                leader = "Tochost",
                raid = "TOGC25",
                message = "LFM TOGC25 [T:2/2 H:5/6 M:6/8 R:7/9] 5200+ Insanity run!",
                gsMin = 5200,
                tanks = {current = 2, needed = 2},
                healers = {current = 5, needed = 6},
                mdps = {current = 6, needed = 8},
                rdps = {current = 7, needed = 9},
                time = time() - 300,
            })
            -- VoA
            AIP.GroupTracker.AddGroup({
                leader = "Voafast",
                raid = "VoA25",
                message = "LFM VoA25 [T:1/1 H:2/4 M:5/10 R:7/10] all welcome, quick run",
                gsMin = 4500,
                tanks = {current = 1, needed = 1},
                healers = {current = 2, needed = 4},
                mdps = {current = 5, needed = 10},
                rdps = {current = 7, needed = 10},
                time = time() - 240,
            })
            -- Onyxia
            AIP.GroupTracker.AddGroup({
                leader = "Onyhost",
                raid = "Ony25",
                message = "LFM Ony25 quick kill, need DPS",
                gsMin = 4000,
                tanks = {current = 2, needed = 2},
                healers = {current = 4, needed = 5},
                mdps = {current = 6, needed = 9},
                rdps = {current = 8, needed = 9},
                time = time() - 400,
            })
        end
    end

    -- ========================================================================
    -- LFM BROWSER TAB - LFG Players
    -- ========================================================================
    if AIP.ChatScanner and AIP.ChatScanner.Players then
        AIP.ChatScanner.Players = {}  -- Clear first
        AIP.ChatScanner.Players["Arcanemage"] = {
            name = "Arcanemage",
            class = "MAGE",
            role = "RDPS",
            gs = 5800,
            raid = "ICC25H",
            message = "LFG ICC25 HC, 5.8k GS Arcane Mage, have LK achiev",
            time = time(),
        }
        AIP.ChatScanner.Players["Holypriest"] = {
            name = "Holypriest",
            class = "PRIEST",
            role = "HEALER",
            gs = 5600,
            raid = "ICC25H",
            message = "LFG ICC25 HC, Holy Priest 5.6k GS, experienced healer",
            time = time() - 30,
        }
        AIP.ChatScanner.Players["Blooddk"] = {
            name = "Blooddk",
            class = "DEATHKNIGHT",
            role = "TANK",
            gs = 6000,
            raid = "ICC25H",
            message = "LFG ICC25 HC tank, 6k GS Blood DK, full clear exp",
            time = time() - 60,
        }
        AIP.ChatScanner.Players["Furywarrior"] = {
            name = "Furywarrior",
            class = "WARRIOR",
            role = "MDPS",
            gs = 5700,
            raid = "ICC25N",
            message = "LFG ICC25, Fury Warrior 5.7k GS",
            time = time() - 90,
        }
        AIP.ChatScanner.Players["Combatrog"] = {
            name = "Combatrog",
            class = "ROGUE",
            role = "MDPS",
            gs = 5500,
            raid = "RS25H",
            message = "LFG RS25 HC, Combat Rogue 5.5k",
            time = time() - 120,
        }
        AIP.ChatScanner.Players["Boomkin"] = {
            name = "Boomkin",
            class = "DRUID",
            role = "RDPS",
            gs = 5400,
            raid = "ICC10H",
            message = "LFG ICC10 HC, Balance Druid 5.4k",
            time = time() - 150,
        }
        AIP.ChatScanner.Players["Enhsham"] = {
            name = "Enhsham",
            class = "SHAMAN",
            role = "MDPS",
            gs = 5300,
            raid = "TOGC25",
            message = "LFG TOGC25, Enhance Shaman",
            time = time() - 180,
        }
        AIP.ChatScanner.Players["Affilock"] = {
            name = "Affilock",
            class = "WARLOCK",
            role = "RDPS",
            gs = 5600,
            raid = "ICC25H",
            message = "LFG ICC25 HC, Affliction Lock 5.6k, have summons",
            time = time() - 200,
        }
    end

    -- ========================================================================
    -- LOOT HISTORY TAB - Use LootHistoryPanel's built-in test data
    -- ========================================================================
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.LoadTestData then
        AIP.Panels.LootHistory.LoadTestData()
    end

    -- ========================================================================
    -- REFRESH ALL UIs
    -- ========================================================================
    -- Refresh LFM Browser
    if AIP.CentralGUI then
        if AIP.CentralGUI.RefreshBrowserTab then
            AIP.CentralGUI.RefreshBrowserTab("lfm")
        end
    end
    -- Refresh Raid Management
    if AIP.Panels and AIP.Panels.RaidMgmt and AIP.Panels.RaidMgmt.Update then
        AIP.Panels.RaidMgmt.Update()
    end
    -- Refresh Blacklist
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end
    -- Refresh Favorites
    if AIP.Panels and AIP.Panels.Favorites and AIP.Panels.Favorites.Update then
        AIP.Panels.Favorites.Update()
    end
    -- Refresh Loot History
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.RefreshList then
        AIP.Panels.LootHistory.RefreshList()
    end
    -- Refresh Queue
    if AIP.Queue and AIP.Queue.RefreshUI then
        AIP.Queue.RefreshUI()
    end

    AIP.Print("|cFF00FF00Test data populated!|r Check all tabs.")
end

-- Clear all test data
function SP.ClearTestData()
    if not AIP.db then return end

    AIP.Print("|cFFFF6666Clearing test data...|r")

    -- ========================================================================
    -- RAID MGMT TAB
    -- ========================================================================
    AIP.db.reservedItems = ""
    AIP.db.lootBans = {}
    AIP.db.msTracking = {}

    -- ========================================================================
    -- BLACKLIST TAB - Remove test entries
    -- ========================================================================
    if AIP.Blacklist and AIP.Blacklist.Remove then
        local testBlacklist = {"Ninjalooter", "Afkguy", "Toxicplayer", "Botkiller", "Scammer"}
        for _, name in ipairs(testBlacklist) do
            AIP.Blacklist.Remove(name)
        end
    end

    -- ========================================================================
    -- FAVORITES TAB - Remove test entries
    -- ========================================================================
    if AIP.Favorites and AIP.Favorites.Remove then
        local testFavorites = {"Bestpriest", "Maintank", "Prolock", "Clutchhealer", "Guildmaster"}
        for _, name in ipairs(testFavorites) do
            AIP.Favorites.Remove(name)
        end
    end

    -- ========================================================================
    -- LFM BROWSER TAB - Queue
    -- ========================================================================
    if AIP.Queue and AIP.Queue.Clear then
        AIP.Queue.Clear()
    end

    -- ========================================================================
    -- LFM BROWSER TAB - Waitlist
    -- ========================================================================
    if AIP.Waitlist and AIP.Waitlist.Clear then
        AIP.Waitlist.Clear()
    end

    -- ========================================================================
    -- LFM BROWSER TAB - LFM Groups
    -- ========================================================================
    if AIP.GroupTracker then
        AIP.GroupTracker.Groups = {}
    end

    -- ========================================================================
    -- LFM BROWSER TAB - LFG Players
    -- ========================================================================
    if AIP.ChatScanner then
        AIP.ChatScanner.Players = {}
    end

    -- ========================================================================
    -- LOOT HISTORY TAB - Use LootHistoryPanel's clear function
    -- ========================================================================
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.ClearTestData then
        AIP.Panels.LootHistory.ClearTestData()
    end

    -- ========================================================================
    -- REFRESH ALL UIs
    -- ========================================================================
    -- Refresh LFM Browser
    if AIP.CentralGUI then
        if AIP.CentralGUI.RefreshBrowserTab then
            AIP.CentralGUI.RefreshBrowserTab("lfm")
        end
    end
    -- Refresh Raid Management
    if AIP.Panels and AIP.Panels.RaidMgmt and AIP.Panels.RaidMgmt.Update then
        AIP.Panels.RaidMgmt.Update()
    end
    -- Refresh Blacklist
    if AIP.Panels and AIP.Panels.Blacklist and AIP.Panels.Blacklist.Update then
        AIP.Panels.Blacklist.Update()
    end
    -- Refresh Favorites
    if AIP.Panels and AIP.Panels.Favorites and AIP.Panels.Favorites.Update then
        AIP.Panels.Favorites.Update()
    end
    -- Refresh Loot History
    if AIP.Panels and AIP.Panels.LootHistory and AIP.Panels.LootHistory.RefreshList then
        AIP.Panels.LootHistory.RefreshList()
    end
    -- Refresh Queue
    if AIP.Queue and AIP.Queue.RefreshUI then
        AIP.Queue.RefreshUI()
    end

    AIP.Print("|cFFFF6666Test data cleared!|r")
end

-- Handle panel resize
function SP.OnResize(width, height)
    local scrollFrame = _G["AIPSettingsScroll"]
    if scrollFrame then
        local content = scrollFrame:GetScrollChild()
        if content then
            local newWidth = math.max(width - 40, 580)
            content:SetWidth(newWidth)
        end
    end
end

-- Cleanup on logout
local cleanupFrame = CreateFrame("Frame")
cleanupFrame:RegisterEvent("PLAYER_LOGOUT")
cleanupFrame:SetScript("OnEvent", function()
    SP.StopAutoSpam()
end)
