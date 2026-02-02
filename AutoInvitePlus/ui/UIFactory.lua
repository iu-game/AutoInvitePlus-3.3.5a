-- AutoInvite Plus - UI Factory Module
-- Consolidated UI creation patterns (DRY principle)

local AIP = AutoInvitePlus
AIP.UI = {}
local UI = AIP.UI

-- ============================================================================
-- STANDARD BACKDROP CONFIGURATIONS
-- ============================================================================

UI.Backdrops = {
    -- Main window backdrop
    Window = {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    },

    -- Panel/section backdrop
    Panel = {
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    },

    -- Dark panel (for nested sections)
    DarkPanel = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    },

    -- Button backdrop
    Button = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    },

    -- No border (just background)
    Flat = {
        bgFile = "Interface\\Buttons\\WHITE8X8",
        tile = false,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    },
}

-- ============================================================================
-- FRAME CREATION
-- ============================================================================

-- Create a basic frame with optional backdrop
function UI.CreateFrame(frameType, name, parent, template)
    local frame = CreateFrame(frameType or "Frame", name, parent, template)
    return frame
end

-- Create a panel with backdrop
function UI.CreatePanel(parent, width, height, backdropType)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width, height)

    local backdrop = UI.Backdrops[backdropType or "Panel"]
    panel:SetBackdrop(backdrop)

    if backdropType == "DarkPanel" then
        panel:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    else
        panel:SetBackdropColor(0, 0, 0, 0.5)
    end
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    return panel
end

-- Create main window frame
function UI.CreateWindow(name, width, height, title, closeable)
    local frame = CreateFrame("Frame", name, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    frame:SetBackdrop(UI.Backdrops.Window)
    frame:SetBackdropColor(0, 0, 0, 1)

    -- Title
    if title then
        local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        titleText:SetPoint("TOP", 0, -15)
        titleText:SetText(title)
        frame.title = titleText
    end

    -- Close button
    if closeable ~= false then
        local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)
        frame.closeBtn = closeBtn
    end

    -- Make closeable with Escape
    if name then
        tinsert(UISpecialFrames, name)
    end

    return frame
end

-- ============================================================================
-- INPUT ELEMENTS
-- ============================================================================

-- Create an edit box
function UI.CreateEditBox(parent, width, height, numeric, maxChars)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, height or 20)
    editBox:SetAutoFocus(false)

    if numeric then
        editBox:SetNumeric(true)
    end

    if maxChars then
        editBox:SetMaxLetters(maxChars)
    end

    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    return editBox
end

-- Create edit box with label
function UI.CreateLabeledEditBox(parent, label, width, height, numeric)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 60, height or 20)

    local labelText = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT", 0, 0)
    labelText:SetText(label .. ":")
    container.label = labelText

    local editBox = UI.CreateEditBox(container, width, height, numeric)
    editBox:SetPoint("LEFT", labelText, "RIGHT", 5, 0)
    container.editBox = editBox

    return container
end

-- Create a multi-line edit box
function UI.CreateMultiLineEditBox(parent, width, height)
    local scrollFrame = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetSize(width, height)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetSize(width - 20, height)
    editBox:SetFontObject(GameFontHighlightSmall)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    scrollFrame:SetScrollChild(editBox)
    scrollFrame.editBox = editBox

    return scrollFrame
end

-- ============================================================================
-- BUTTONS
-- ============================================================================

-- Create a standard button
function UI.CreateButton(parent, text, width, height, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 80, height or 22)
    button:SetText(text)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return button
end

-- Create an icon button
function UI.CreateIconButton(parent, icon, size, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(size or 24, size or 24)

    local texture = button:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture(icon)
    button.icon = texture

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    highlight:SetBlendMode("ADD")

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    if tooltip then
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return button
end

-- Create a close button (X)
function UI.CreateCloseButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    button:SetSize(24, 24)

    if onClick then
        button:SetScript("OnClick", onClick)
    end

    return button
end

-- ============================================================================
-- CHECKBOXES
-- ============================================================================

-- Create a checkbox with label
function UI.CreateCheckbox(parent, label, onClick, tooltip)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(22, 22)

    local labelText = check:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    labelText:SetPoint("LEFT", check, "RIGHT", 2, 0)
    labelText:SetText(label)
    check.label = labelText

    if onClick then
        check:SetScript("OnClick", function(self)
            onClick(self, self:GetChecked())
        end)
    end

    if tooltip then
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tooltip)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    return check
end

-- ============================================================================
-- DROPDOWNS
-- ============================================================================

-- Create a dropdown menu
function UI.CreateDropdown(parent, width, items, onSelect, defaultText)
    local dropdown = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropdown, width or 100)
    UIDropDownMenu_SetText(dropdown, defaultText or "Select...")

    dropdown.selectedValue = nil

    local function Initialize()
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.func = function(self)
                dropdown.selectedValue = self.value
                UIDropDownMenu_SetText(dropdown, item.text)
                if onSelect then
                    onSelect(self.value, item.text)
                end
            end
            info.checked = (dropdown.selectedValue == item.value)
            UIDropDownMenu_AddButton(info)
        end
    end

    UIDropDownMenu_Initialize(dropdown, Initialize)

    return dropdown
end

-- Fix dropdown strata issues (single implementation)
function UI.FixDropdownStrata(dropdown)
    if not dropdown then return end

    local button = _G[dropdown:GetName() .. "Button"]
    if button then
        button:SetScript("OnClick", function(self)
            local dropdownMenu = _G["DropDownList1"]
            if dropdownMenu then
                dropdownMenu:SetFrameStrata("FULLSCREEN_DIALOG")
            end
            ToggleDropDownMenu(1, nil, dropdown, dropdown, 0, 0)
        end)
    end
end

-- ============================================================================
-- SCROLL LISTS
-- ============================================================================

-- Create a scroll list with rows
function UI.CreateScrollList(parent, rowCount, rowHeight, width, createRowFunc)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, rowCount * rowHeight)

    -- Create scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(width - 20, rowCount * rowHeight)
    scrollFrame:SetPoint("TOPLEFT", 0, 0)

    container.scrollFrame = scrollFrame
    container.rows = {}
    container.rowHeight = rowHeight
    container.rowCount = rowCount

    -- Create rows
    for i = 1, rowCount do
        local row = createRowFunc(container, i)
        row:SetSize(width - 20, rowHeight)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -((i - 1) * rowHeight))
        row:Hide()
        container.rows[i] = row
    end

    -- Update function
    container.Update = function(self, data, displayFunc)
        local numEntries = #data
        FauxScrollFrame_Update(self.scrollFrame, numEntries, self.rowCount, self.rowHeight)

        local offset = FauxScrollFrame_GetOffset(self.scrollFrame)

        for i = 1, self.rowCount do
            local index = offset + i
            local row = self.rows[i]

            if index <= numEntries then
                displayFunc(row, data[index], index)
                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Set scroll handler
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, container.rowHeight, function()
            -- This will be replaced by caller
        end)
    end)

    return container
end

-- Create a simple list row
function UI.CreateListRow(parent, columns)
    local row = CreateFrame("Button", nil, parent)

    -- Highlight
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    highlight:SetBlendMode("ADD")
    row.highlight = highlight

    -- Create column texts
    row.columns = {}
    local xOffset = 5

    for i, col in ipairs(columns) do
        local text = row:CreateFontString(nil, "OVERLAY", col.font or "GameFontNormal")
        text:SetPoint("LEFT", xOffset, 0)
        text:SetWidth(col.width)
        text:SetJustifyH(col.justify or "LEFT")

        if col.color then
            text:SetTextColor(col.color.r, col.color.g, col.color.b)
        end

        row.columns[i] = text
        xOffset = xOffset + col.width + 5
    end

    return row
end

-- ============================================================================
-- TOOLTIPS
-- ============================================================================

-- Show tooltip at owner
function UI.ShowTooltip(owner, title, lines, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

    if title then
        GameTooltip:AddLine(title, 1, 1, 1)
    end

    if lines then
        for _, line in ipairs(lines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line.text, line.r or 1, line.g or 1, line.b or 1, line.wrap)
            else
                GameTooltip:AddLine(line, 1, 1, 1, true)
            end
        end
    end

    GameTooltip:Show()
end

-- Show double-column tooltip
function UI.ShowDoubleLine(owner, title, leftRight, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")

    if title then
        GameTooltip:AddLine(title, 1, 1, 1)
    end

    if leftRight then
        for _, pair in ipairs(leftRight) do
            GameTooltip:AddDoubleLine(pair[1], pair[2], 1, 1, 1, 1, 1, 1)
        end
    end

    GameTooltip:Show()
end

-- Hide tooltip
function UI.HideTooltip()
    GameTooltip:Hide()
end

-- ============================================================================
-- TABS
-- ============================================================================

-- Create tab buttons
function UI.CreateTabs(parent, tabs, contentFrame, onTabSelected)
    local tabButtons = {}
    local tabWidth = 80

    for i, tabInfo in ipairs(tabs) do
        local tab = CreateFrame("Button", nil, parent)
        tab:SetSize(tabWidth, 25)
        tab:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", (i - 1) * tabWidth + 10, -2)

        -- Background
        local bg = tab:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        bg:SetVertexColor(0.15, 0.15, 0.15, 1)
        tab.bg = bg

        -- Text
        local text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(tabInfo.text)
        tab.text = text

        tab.id = tabInfo.id
        tab.index = i

        tab:SetScript("OnClick", function(self)
            -- Update visual state of all tabs
            for _, btn in ipairs(tabButtons) do
                if btn == self then
                    btn.bg:SetVertexColor(0.3, 0.3, 0.4, 1)
                    btn.text:SetTextColor(1, 0.82, 0)
                else
                    btn.bg:SetVertexColor(0.15, 0.15, 0.15, 1)
                    btn.text:SetTextColor(0.8, 0.8, 0.8)
                end
            end

            if onTabSelected then
                onTabSelected(self.id, self.index)
            end
        end)

        tabButtons[i] = tab
    end

    -- Select first tab by default
    if #tabButtons > 0 then
        tabButtons[1]:GetScript("OnClick")(tabButtons[1])
    end

    return tabButtons
end

-- ============================================================================
-- SLIDERS (WotLK Compatible)
-- ============================================================================

-- Unique ID counter for slider names
local sliderCounter = 0

-- Create a slider (WotLK compatible - no SetObeyStepOnDrag)
function UI.CreateSlider(parent, width, min, max, step, label, onValueChanged)
    -- OptionsSliderTemplate requires a unique name in WotLK
    sliderCounter = sliderCounter + 1
    local sliderName = "AIPSlider" .. sliderCounter

    local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    slider:SetSize(width, 17)
    slider:SetMinMaxValues(min, max)
    slider:SetValueStep(step or 1)

    -- SetObeyStepOnDrag doesn't exist in WotLK, handle manually
    local stepVal = step or 1

    -- Hide the default low/high text from template
    local lowText = _G[sliderName .. "Low"]
    local highText = _G[sliderName .. "High"]
    local textLabel = _G[sliderName .. "Text"]
    if lowText then lowText:SetText("") end
    if highText then highText:SetText("") end
    if textLabel then textLabel:SetText(label or "") end

    -- Custom label above slider
    slider.label = textLabel

    -- Value display below
    local valueText = slider:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("TOP", slider, "BOTTOM", 0, -2)
    slider.valueText = valueText

    -- WotLK: Manually snap to step on mouse up
    slider:SetScript("OnMouseUp", function(self)
        local value = self:GetValue()
        local snapped = math.floor(value / stepVal + 0.5) * stepVal
        -- Only set if actually different to avoid double-update flicker
        if math.abs(value - snapped) > 0.001 then
            self:SetValue(snapped)
        end
    end)

    slider:SetScript("OnValueChanged", function(self, value)
        self.valueText:SetText(string.format("%.1f", value))
        if onValueChanged then
            onValueChanged(value)
        end
    end)

    return slider
end

-- ============================================================================
-- STATUS BAR
-- ============================================================================

-- Create a status bar
function UI.CreateStatusBar(parent, width, height, texture, color)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture(texture or "Interface\\TargetingFrame\\UI-StatusBar")

    if color then
        bar:SetStatusBarColor(color.r, color.g, color.b, color.a or 1)
    end

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(texture or "Interface\\TargetingFrame\\UI-StatusBar")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    bar.bg = bg

    -- Text
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    bar.text = text

    return bar
end

-- ============================================================================
-- SEPARATOR / DIVIDER
-- ============================================================================

-- Create a horizontal separator line
function UI.CreateSeparator(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetSize(width, 1)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.4, 0.4, 0.4, 1)
    return line
end

-- Create a section header with separator
function UI.CreateSectionHeader(parent, text, width)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 20)

    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 0, 0)
    label:SetText(text)
    label:SetTextColor(1, 0.82, 0)
    container.label = label

    local line = container:CreateTexture(nil, "ARTWORK")
    line:SetSize(width - label:GetStringWidth() - 10, 1)
    line:SetPoint("LEFT", label, "RIGHT", 5, 0)
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetVertexColor(0.4, 0.4, 0.4, 1)
    container.line = line

    return container
end

-- ============================================================================
-- TEMPLATE FACTORIES (replaces CentralGUI.xml templates)
-- ============================================================================

-- Create a tree row (for hierarchical lists)
function UI.CreateTreeRow(parent, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width or 250, height or 20)

    -- Highlight
    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.1)
    highlight:SetBlendMode("ADD")
    highlight:Hide()
    row.Highlight = highlight

    row.selected = false

    row:SetScript("OnEnter", function(self)
        self.Highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        if not self.selected then
            self.Highlight:Hide()
        end
    end)

    function row:SetSelected(selected)
        self.selected = selected
        if selected then
            self.Highlight:Show()
            self.Highlight:SetVertexColor(0.3, 0.5, 0.8, 0.3)
        else
            self.Highlight:SetVertexColor(1, 1, 1, 0.1)
            self.Highlight:Hide()
        end
    end

    return row
end

-- Create a player row (for queue/blacklist)
function UI.CreatePlayerRow(parent, width, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width or 600, height or 22)

    -- Columns container
    row.columns = {}

    -- Invite button
    local invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    invBtn:SetSize(35, 18)
    invBtn:SetPoint("LEFT", 0, 0)
    row.inviteBtn = invBtn

    return row
end

-- Create tab button
function UI.CreateTabButton(parent, width, height, text, tabId)
    local tab = CreateFrame("Button", nil, parent)
    tab:SetSize(width or 90, height or 24)

    -- Background
    local bg = tab:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
    tab.bg = bg

    -- Text
    local label = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "Tab")
    tab.text = label

    tab.tabId = tabId
    tab.selected = false

    function tab:SetSelected(selected)
        self.selected = selected
        if selected then
            self.bg:SetVertexColor(0.3, 0.3, 0.4, 1)
            self.text:SetTextColor(1, 0.82, 0)
        else
            self.bg:SetVertexColor(0.15, 0.15, 0.15, 0.9)
            self.text:SetTextColor(0.8, 0.8, 0.8)
        end
    end

    return tab
end

-- Create action button bar
function UI.CreateActionBar(parent, width, height, buttons)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 640, height or 40)

    bar.buttons = {}
    local xOffset = 5

    for _, btnDef in ipairs(buttons or {}) do
        local btn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        btn:SetSize(btnDef.width or 80, 24)
        btn:SetPoint("LEFT", xOffset, 0)
        btn:SetText(btnDef.text or "Button")
        if btnDef.onClick then
            btn:SetScript("OnClick", btnDef.onClick)
        end
        bar.buttons[btnDef.id or btnDef.text] = btn
        xOffset = xOffset + (btnDef.width or 80) + 5
    end

    return bar
end

-- Create status bar frame
function UI.CreateStatusBarFrame(parent, width, height)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetSize(width or 980, height or 30)

    -- Background
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0, 0, 0, 0.3)

    -- Text
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 10, 0)
    text:SetTextColor(0.7, 0.7, 0.7)
    bar.text = text

    return bar
end

-- Create inspection panel
function UI.CreateInspectionPanel(parent, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width or 400, height or 500)

    panel:SetBackdrop(UI.Backdrops.Panel)
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    return panel
end

-- ============================================================================
-- FADE ANIMATIONS
-- ============================================================================

-- Fade frame in
function UI.FadeIn(frame, duration, targetAlpha)
    if not frame then return end

    duration = duration or 0.3
    targetAlpha = targetAlpha or 1

    -- Cancel any existing fade animation to prevent memory leaks
    if frame._fadeInTicker then
        frame._fadeInTicker:SetScript("OnUpdate", nil)
        frame._fadeInTicker:Hide()
    end
    if frame._fadeOutTicker then
        frame._fadeOutTicker:SetScript("OnUpdate", nil)
        frame._fadeOutTicker:Hide()
    end

    frame:SetAlpha(0)
    frame:Show()

    local elapsed = 0
    -- Reuse existing ticker frame or create new one
    local ticker = frame._fadeInTicker or CreateFrame("Frame")
    frame._fadeInTicker = ticker
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = math.min(1, elapsed / duration)
        frame:SetAlpha(progress * targetAlpha)

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
        end
    end)
    ticker:Show()
end

-- Fade frame out
function UI.FadeOut(frame, duration, hideOnComplete)
    if not frame then return end

    duration = duration or 0.3
    local startAlpha = frame:GetAlpha()

    -- Cancel any existing fade animation to prevent memory leaks
    if frame._fadeInTicker then
        frame._fadeInTicker:SetScript("OnUpdate", nil)
        frame._fadeInTicker:Hide()
    end
    if frame._fadeOutTicker then
        frame._fadeOutTicker:SetScript("OnUpdate", nil)
        frame._fadeOutTicker:Hide()
    end

    local elapsed = 0
    -- Reuse existing ticker frame or create new one
    local ticker = frame._fadeOutTicker or CreateFrame("Frame")
    frame._fadeOutTicker = ticker
    ticker:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = math.min(1, elapsed / duration)
        frame:SetAlpha(startAlpha * (1 - progress))

        if progress >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if hideOnComplete then
                frame:Hide()
            end
        end
    end)
    ticker:Show()
end

-- ============================================================================
-- GLOBAL HELPER FUNCTIONS (replaces CentralGUI.xml script block)
-- ============================================================================

-- Toggle Central GUI
function AIP_ToggleCentralGUI()
    local AIP = AutoInvitePlus
    if AIP and AIP.CentralGUI then
        AIP.CentralGUI.Toggle()
    end
end

-- Show LFM Tab
function AIP_ShowLFMTab()
    local AIP = AutoInvitePlus
    if AIP and AIP.CentralGUI then
        AIP.CentralGUI.Show("lfm")
    end
end

-- Show LFG Tab
function AIP_ShowLFGTab()
    local AIP = AutoInvitePlus
    if AIP and AIP.CentralGUI then
        AIP.CentralGUI.Show("lfg")
    end
end
