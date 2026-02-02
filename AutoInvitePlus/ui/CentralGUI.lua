-- AutoInvite Plus - Central GUI Module
-- Main window controller for the unified interface

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r CentralGUI: AutoInvitePlus namespace not found!")
    return
end

AIP.CentralGUI = {}
local GUI = AIP.CentralGUI

-- Debug: confirm module loaded
-- DEFAULT_CHAT_FRAME:AddMessage("|cFF00FF00[AIP Debug]|r CentralGUI module loaded")

-- Configuration
GUI.Config = {
    defaultWidth = 1000,
    defaultHeight = 650,
    minWidth = 800,
    minHeight = 500,
    minimizedHeight = 45,  -- Height when minimized (just title bar)
}

-- Tab definitions (v5.3 - added raid management and loot history)
GUI.Tabs = {
    {id = "lfm", name = "LFM Browser", tooltip = "LFM groups browser with message composer and queue"},
    {id = "favorites", name = "Favorites", tooltip = "Whitelist/priority players management"},
    {id = "blacklist", name = "Blacklist", tooltip = "Blocked players management"},
    {id = "composition", name = "Composition", tooltip = "Raid composition advisor with templates"},
    {id = "raidmgmt", name = "Raid Mgmt", tooltip = "Raid warnings, loot rules, buff checker, MS/OS tracking"},
    {id = "loothistory", name = "Loot History", tooltip = "Historical loot drops from raids and dungeons"},
    {id = "settings", name = "Settings", tooltip = "Auto-invite and broadcast settings"},
}

-- State
GUI.Frame = nil
GUI.CurrentTab = "lfm"
GUI.TreeView = nil
GUI.InspectionPanel = nil
GUI.IsMinimized = false
GUI.IsMaximized = false
GUI.SavedSize = nil  -- Stores {width, height} before maximize
GUI.SavedPosition = nil  -- Stores {point, relPoint, x, y} before maximize

-- LFG Enrollment tracking (other players looking for groups)
GUI.LfgEnrollments = {}  -- {playerName = {name, class, spec, role, gs, ilvl, raid, time}}
GUI.MyEnrollment = nil   -- Our own enrollment data
GUI.MyGroup = nil        -- Our active LFM data (for matching incoming LFG players)

-- Custom channels for addon communication
GUI.CustomChannels = {
    LFM = "AIPLookingForMore",
    LFG = "AIPLookingForGroup",
}

-- Use AIP.Utils.DelayedCall for WotLK-compatible timers
-- (defined in core/Utils.lua, no need for local fallback)

-- Standardized backdrop templates for consistent appearance
GUI.Backdrops = {
    -- Main panel backdrop (dark, solid)
    Panel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 5, right = 5, top = 5, bottom = 5}
    },
    -- Sub-panel backdrop (slightly lighter)
    SubPanel = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    },
    -- Input field backdrop
    Input = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 10,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    },
    -- Small inset panel
    Inset = {
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = {left = 2, right = 2, top = 2, bottom = 2}
    },
}

-- Helper: Apply standard backdrop to frame
function GUI.ApplyBackdrop(frame, backdropType, bgAlpha, borderAlpha)
    local bd = GUI.Backdrops[backdropType] or GUI.Backdrops.Panel
    frame:SetBackdrop(bd)
    frame:SetBackdropColor(0.05, 0.05, 0.05, bgAlpha or 0.95)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, borderAlpha or 1)
end

-- Helper: Create properly styled edit box for WotLK
function GUI.CreateStyledEditBox(parent, width, height, isNumeric)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width + 10, height + 8)
    container:SetBackdrop(GUI.Backdrops.Input)
    container:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    container:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local editBox = CreateFrame("EditBox", nil, container)
    editBox:SetSize(width, height)
    editBox:SetPoint("CENTER", 0, 0)
    editBox:SetFontObject("GameFontHighlightSmall")
    editBox:SetAutoFocus(false)
    editBox:EnableMouse(true)
    editBox:EnableKeyboard(true)

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
        container:SetBackdropBorderColor(0.6, 0.6, 0.3, 1)
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        container:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    editBox.container = container
    return editBox, container
end

-- Helper: Fix UIDropDownMenu strata issues in WotLK
-- The dropdown list frames need higher strata when parent is HIGH
function GUI.FixDropdownStrata(dropdown)
    if not dropdown then return end
    -- Hook the dropdown button click to set proper strata on the list frame
    local button = _G[dropdown:GetName() .. "Button"]
    if button then
        button:HookScript("OnClick", function()
            -- DropDownList1 is the main dropdown list frame
            for i = 1, UIDROPDOWNMENU_MAXLEVELS or 2 do
                local listFrame = _G["DropDownList" .. i]
                if listFrame then
                    listFrame:SetFrameStrata("TOOLTIP")
                end
            end
        end)
    end
end

-- ============================================================================
-- ACHIEVEMENT TOOLTIP HELPERS
-- ============================================================================

-- Extract achievement ID from an achievement link
-- Format: |cffffff00|Hachievement:ID:...|h[Name]|h|r
function GUI.ExtractAchievementId(link)
    if not link then return nil end
    local id = link:match("|Hachievement:(%d+):")
    return id and tonumber(id)
end

-- Extract all achievement IDs from a text string
function GUI.ExtractAllAchievementIds(text)
    if not text then return {} end
    local ids = {}
    for id in text:gmatch("|Hachievement:(%d+):") do
        local numId = tonumber(id)
        if numId then
            table.insert(ids, numId)
        end
    end
    return ids
end

-- Show achievement tooltip for a given achievement ID
function GUI.ShowAchievementTooltip(achievementId, owner, anchor)
    if not achievementId then return end
    GameTooltip:SetOwner(owner or UIParent, anchor or "ANCHOR_RIGHT")

    -- Try to set the hyperlink directly (this works in WotLK)
    local link = GetAchievementLink(achievementId)
    if link then
        GameTooltip:SetHyperlink(link)
        return true
    end

    -- Fallback: Build tooltip manually from achievement info
    local id, name, points, completed, month, day, year, description, flags, icon = GetAchievementInfo(achievementId)
    if name then
        GameTooltip:AddLine(name, 1, 0.82, 0)
        if description then
            GameTooltip:AddLine(description, 1, 1, 1, true)
        end
        if points and points > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddDoubleLine("Points:", tostring(points), 0.7, 0.7, 0.7, 0, 1, 0)
        end
        if completed then
            local dateStr = ""
            if month and day and year and year > 0 then
                dateStr = string.format("%d/%d/%d", month, day, year)
            end
            GameTooltip:AddLine("|cFF00FF00Completed|r " .. dateStr, 0, 1, 0)
        else
            GameTooltip:AddLine("|cFFFF6666Not completed|r", 1, 0.4, 0.4)
        end
        GameTooltip:Show()
        return true
    end

    return false
end

-- Create a hyperlink-aware text display that shows achievement tooltips on hover
-- This creates an invisible button overlay that detects achievement link clicks
function GUI.CreateAchievementAwareText(parent, fontString, textContent)
    if not parent or not fontString then return end

    -- Store the text content and achievement IDs
    fontString.achievementIds = GUI.ExtractAllAchievementIds(textContent)

    -- If no achievements, just set text and return
    if #fontString.achievementIds == 0 then
        fontString:SetText(textContent)
        return
    end

    fontString:SetText(textContent)

    -- Enable hyperlinks if the font string supports it
    if fontString.SetHyperlinksEnabled then
        fontString:SetHyperlinksEnabled(true)
    end
end

-- Setup message box to show achievement tooltips on hover
-- Call this when creating a message display area
function GUI.SetupMessageBoxAchievementTooltips(msgFrame, msgFontString)
    if not msgFrame then return end

    -- Track if we're hovering over an achievement
    msgFrame.hoveredAchievement = nil

    msgFrame:EnableMouse(true)
    msgFrame:SetScript("OnEnter", function(self)
        local text = msgFontString and msgFontString:GetText() or ""
        local achievementIds = GUI.ExtractAllAchievementIds(text)

        if #achievementIds > 0 then
            -- Show tooltip for the first achievement found
            GUI.ShowAchievementTooltip(achievementIds[1], self, "ANCHOR_RIGHT")
            self.hoveredAchievement = achievementIds[1]
        end
    end)

    msgFrame:SetScript("OnLeave", function(self)
        if self.hoveredAchievement then
            GameTooltip:Hide()
            self.hoveredAchievement = nil
        end
    end)
end

-- Create minimap button
function GUI.CreateMinimapButton()
    local button = CreateFrame("Button", "AIPMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)

    -- Icon texture (centered in the bezel)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\ICONS\\Ability_Warrior_RallyingCry")
    button.icon = icon

    -- Border texture (the MiniMap-TrackingBorder has built-in offset, adjust positioning)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT", button, "TOPLEFT", -1, 1)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button.border = border

    -- Highlight texture
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    -- Position around minimap
    local angle = AIP.db and AIP.db.minimapAngle or 220
    local rad = math.rad(angle)
    local x = math.cos(rad) * 80
    local y = math.sin(rad) * 80
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)

    -- Drag to reposition
    button:EnableMouse(true)
    button:RegisterForDrag("LeftButton")
    button:SetMovable(true)

    button:SetScript("OnDragStart", function(self)
        self.dragging = true
    end)

    button:SetScript("OnDragStop", function(self)
        self.dragging = false
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale

        local dx = cx - mx
        local dy = cy - my
        local angle = math.deg(math.atan2(dy, dx))

        if AIP.db then
            AIP.db.minimapAngle = angle
        end

        local rad = math.rad(angle)
        local x = math.cos(rad) * 80
        local y = math.sin(rad) * 80
        self:ClearAllPoints()
        self:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end)

    button:SetScript("OnUpdate", function(self)
        if self.dragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale

            local dx = cx - mx
            local dy = cy - my
            local angle = math.atan2(dy, dx)

            local x = math.cos(angle) * 80
            local y = math.sin(angle) * 80
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end
    end)

    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            GUI.Toggle()
        elseif button == "RightButton" then
            -- Show quick menu
            GUI.ShowQuickMenu(self)
        end
    end)

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("AutoInvite+")
        GameTooltip:AddLine("|cFF888888by iuGames|r", 0.5, 0.5, 0.5)
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open main window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Quick menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)

    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Ensure button is visible
    button:Show()

    -- Store reference for later access
    GUI.MinimapButton = button

    return button
end

-- Quick menu for minimap button
function GUI.ShowQuickMenu(anchor)
    local menu = CreateFrame("Frame", "AIPQuickMenu", UIParent, "UIDropDownMenuTemplate")

    local menuList = {
        {text = "AutoInvite+", isTitle = true, notCheckable = true},
        {text = "Open Main Window", func = function() GUI.Toggle() end, notCheckable = true},
        {text = "Toggle Auto-Invite", func = function()
            if AIP.db then
                AIP.db.enabled = not AIP.db.enabled
                AIP.Print("Auto-invite " .. (AIP.db.enabled and "ENABLED" or "DISABLED"))
            end
        end, notCheckable = true},
        {text = " ", disabled = true, notCheckable = true},
        {text = "Spam Invite Message", func = function() AIP.SpamInvite() end, notCheckable = true},
        {text = "Invite Guild", func = function() AIP.InviteGuild() end, notCheckable = true},
        {text = "Invite Friends", func = function() AIP.InviteFriends() end, notCheckable = true},
        {text = " ", disabled = true, notCheckable = true},
        {text = "Cancel", notCheckable = true},
    }

    EasyMenu(menuList, menu, anchor, 0, 0, "MENU")
end

-- Create the main frame
function GUI.CreateFrame()
    if GUI.Frame then return GUI.Frame end

    local frame = CreateFrame("Frame", "AIPCentralGUI", UIParent)
    frame:SetSize(GUI.Config.defaultWidth, GUI.Config.defaultHeight)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("HIGH")
    frame:Hide()

    -- Opacity and focus handling
    frame.isFocused = true
    local function UpdateFrameOpacity()
        if not AIP.db then return end
        local baseOpacity = AIP.db.guiOpacity or 1.0
        if AIP.db.guiUnfocusedEnabled and not frame.isFocused then
            frame:SetAlpha(AIP.db.guiUnfocusedOpacity or 0.6)
        else
            frame:SetAlpha(baseOpacity)
        end
    end

    frame:SetScript("OnShow", function(self)
        self.isFocused = true
        UpdateFrameOpacity()
    end)

    frame:HookScript("OnEnter", function(self)
        if not self.isFocused then
            self.isFocused = true
            UpdateFrameOpacity()
        end
    end)

    frame:HookScript("OnLeave", function(self)
        -- Check if mouse is over any child frame
        if not MouseIsOver(self) then
            self.isFocused = false
            UpdateFrameOpacity()
        end
    end)

    -- Expose the update function
    GUI.UpdateFrameOpacity = UpdateFrameOpacity

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    -- Background - solid black backdrop to prevent character showing through
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11}
    })
    frame:SetBackdropColor(0, 0, 0, 1)

    -- Add an additional solid background layer for guaranteed opacity
    local solidBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    solidBg:SetPoint("TOPLEFT", 11, -11)
    solidBg:SetPoint("BOTTOMRIGHT", -11, 11)
    solidBg:SetTexture(0.05, 0.05, 0.05, 1)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetHeight(30)
    titleBar:SetPoint("TOPLEFT", 10, -10)
    titleBar:SetPoint("TOPRIGHT", -10, -10)

    -- Main title
    local titleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", 5, 2)
    titleText:SetText("AutoInvite+")
    titleText:SetTextColor(1, 0.82, 0)

    -- Subtitle (author)
    local subtitleText = titleBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitleText:SetPoint("LEFT", titleText, "RIGHT", 8, -1)
    subtitleText:SetText("by iuGames")
    subtitleText:SetTextColor(0.6, 0.6, 0.6)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Maximize/Restore button
    local maxBtn = CreateFrame("Button", nil, frame)
    maxBtn:SetSize(20, 20)
    maxBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
    maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
    maxBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.maxBtn = maxBtn

    maxBtn:SetScript("OnClick", function()
        GUI.ToggleMaximize()
    end)
    maxBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(GUI.IsMaximized and "Restore" or "Maximize")
        GameTooltip:Show()
    end)
    maxBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Minimize button
    local minBtn = CreateFrame("Button", nil, frame)
    minBtn:SetSize(20, 20)
    minBtn:SetPoint("RIGHT", maxBtn, "LEFT", -2, 0)
    minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
    minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
    minBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    frame.minBtn = minBtn

    minBtn:SetScript("OnClick", function()
        GUI.ToggleMinimize()
    end)
    minBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(GUI.IsMinimized and "Expand" or "Minimize")
        GameTooltip:Show()
    end)
    minBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag to move
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position
        if AIP.db then
            local point, _, relPoint, x, y = self:GetPoint()
            AIP.db.guiPosition = {point = point, relPoint = relPoint, x = x, y = y}
        end
    end)

    -- Tab bar
    local tabBar = CreateFrame("Frame", nil, frame)
    tabBar:SetHeight(30)
    tabBar:SetPoint("TOPLEFT", 10, -40)
    tabBar:SetPoint("TOPRIGHT", -10, -40)
    frame.tabBar = tabBar

    -- Tab bar background
    local tabBarBg = tabBar:CreateTexture(nil, "BACKGROUND")
    tabBarBg:SetAllPoints()
    tabBarBg:SetTexture(0.1, 0.1, 0.1, 1)

    -- Create tab buttons (custom simple buttons for WotLK compatibility)
    frame.tabButtons = {}
    local tabX = 5
    local firstTab = true
    -- Custom widths for each tab to fit text properly with consistent spacing
    local tabWidths = {
        lfm = 90,        -- "LFM Browser"
        favorites = 70,  -- "Favorites"
        blacklist = 68,  -- "Blacklist"
        composition = 85, -- "Composition"
        raidmgmt = 78,   -- "Raid Mgmt"
        loothistory = 82, -- "Loot History"
        settings = 62,   -- "Settings"
    }
    local tabSpacing = 6  -- Gap between tabs (increased for better visual separation)

    for i, tab in ipairs(GUI.Tabs) do
        local tabWidth = tabWidths[tab.id] or 90
        local tabBtn = CreateFrame("Button", "AIPTab" .. tab.id, tabBar)
        tabBtn:SetSize(tabWidth, 24)
        tabBtn:SetPoint("TOPLEFT", tabX, -3)
        tabBtn.tabId = tab.id

        -- Tab background
        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints()
        -- First tab starts selected
        if firstTab then
            tabBg:SetTexture(0.25, 0.25, 0.35, 1)
        else
            tabBg:SetTexture(0.15, 0.15, 0.15, 0.9)
        end
        tabBtn.bg = tabBg

        -- Tab border
        local tabBorder = tabBtn:CreateTexture(nil, "BORDER")
        tabBorder:SetPoint("TOPLEFT", -1, 1)
        tabBorder:SetPoint("BOTTOMRIGHT", 1, -1)
        tabBorder:SetTexture(0.4, 0.4, 0.4, 1)
        tabBtn.border = tabBorder

        -- Tab text
        local tabText = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", 0, 0)
        tabText:SetText(tab.name)
        -- First tab starts selected with gold text
        if firstTab then
            tabText:SetTextColor(1, 0.82, 0)
            firstTab = false
        else
            tabText:SetTextColor(0.8, 0.8, 0.8)
        end
        tabBtn.text = tabText
        tabBtn:SetFontString(tabText)

        -- Highlight texture
        local highlight = tabBtn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture(1, 1, 1, 0.15)

        tabBtn:SetScript("OnClick", function(self)
            GUI.SelectTab(self.tabId)
        end)

        tabBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(tab.tooltip)
            GameTooltip:Show()
        end)

        tabBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        frame.tabButtons[tab.id] = tabBtn
        tabX = tabX + tabWidth + tabSpacing
    end

    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 10, -75)
    content:SetPoint("BOTTOMRIGHT", -10, 40)
    frame.content = content

    -- Create content containers for each tab
    frame.tabContents = {}
    for _, tab in ipairs(GUI.Tabs) do
        local container = CreateFrame("Frame", "AIPContent" .. tab.id, content)
        container:SetAllPoints()

        -- Add background to content area for visibility
        local contentBg = container:CreateTexture(nil, "BACKGROUND")
        contentBg:SetAllPoints()
        contentBg:SetTexture(0.05, 0.05, 0.05, 1)

        container:Hide()
        frame.tabContents[tab.id] = container
    end

    -- Status bar
    local statusBar = CreateFrame("Frame", nil, frame)
    statusBar:SetHeight(30)
    statusBar:SetPoint("BOTTOMLEFT", 10, 5)
    statusBar:SetPoint("BOTTOMRIGHT", -10, 5)
    frame.statusBar = statusBar

    -- Status bar background for visibility
    local statusBarBg = statusBar:CreateTexture(nil, "BACKGROUND")
    statusBarBg:SetAllPoints()
    statusBarBg:SetTexture(0.08, 0.08, 0.08, 0.9)

    local statusText = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT", 5, 0)
    statusText:SetTextColor(0.7, 0.7, 0.7)
    frame.statusText = statusText

    -- GearScore/iLevel display (left side, after status)
    local gsDisplay = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gsDisplay:SetPoint("LEFT", statusText, "RIGHT", 20, 0)
    gsDisplay:SetText("")
    statusBar.gsDisplay = gsDisplay

    -- Chat ban status (center-right of footer)
    local chatBanStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    chatBanStatus:SetPoint("CENTER", 100, 0)
    chatBanStatus:SetText("")
    statusBar.chatBanStatus = chatBanStatus

    -- Mode indicator (left of broadcast status)
    local modeIndicator = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    modeIndicator:SetPoint("RIGHT", -200, 0)
    modeIndicator:SetText("")
    statusBar.modeIndicator = modeIndicator

    -- Peer count display (left of mode indicator)
    local peerCountDisplay = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    peerCountDisplay:SetPoint("RIGHT", modeIndicator, "LEFT", -15, 0)
    peerCountDisplay:SetText("")
    statusBar.peerCountDisplay = peerCountDisplay

    -- Broadcast status (right side of footer)
    local broadcastStatus = statusBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    broadcastStatus:SetPoint("RIGHT", -25, 0)
    broadcastStatus:SetText("")
    statusBar.broadcastStatus = broadcastStatus

    -- Resize grip
    local resizeGrip = CreateFrame("Button", nil, frame)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -5, 5)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    resizeGrip:SetScript("OnMouseDown", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)

    resizeGrip:SetScript("OnMouseUp", function(self)
        frame:StopMovingOrSizing()
        -- Save size
        if AIP.db then
            AIP.db.guiWidth = frame:GetWidth()
            AIP.db.guiHeight = frame:GetHeight()
        end
        -- Force refresh active panel after resize completes
        if GUI.CurrentTab then
            GUI.SelectTab(GUI.CurrentTab)
        end
    end)

    -- Handle frame resize to update tab bar and content
    frame:SetScript("OnSizeChanged", function(self, width, height)
        -- Update tab bar width if needed (tabs stay fixed-position)
        if frame.tabBar then
            -- Tab bar is already using SetPoint anchors, so it auto-resizes
        end
        -- Content panels auto-resize via SetAllPoints
        -- But we should trigger a refresh of the active panel
        if GUI.CurrentTab and AIP.Panels then
            -- Let child frames handle their own OnSizeChanged
        end
    end)

    frame:SetMinResize(GUI.Config.minWidth, GUI.Config.minHeight)

    -- Initialize tab contents
    GUI.InitializeTabs(frame)

    GUI.Frame = frame
    return frame
end

-- Toggle minimize state
function GUI.ToggleMinimize()
    if not GUI.Frame then return end

    GUI.IsMinimized = not GUI.IsMinimized

    if GUI.IsMinimized then
        -- Save current size before minimizing
        GUI.PreMinimizeWidth = GUI.Frame:GetWidth()
        GUI.PreMinimizeHeight = GUI.Frame:GetHeight()

        -- Hide content areas (with nil checks)
        if GUI.Frame.content then GUI.Frame.content:Hide() end
        if GUI.Frame.tabBar then GUI.Frame.tabBar:Hide() end
        if GUI.Frame.statusBar then GUI.Frame.statusBar:Hide() end

        -- Shrink to title bar only
        GUI.Frame:SetHeight(GUI.Config.minimizedHeight)
        GUI.Frame:SetResizable(false)

        -- Update button texture to expand
        if GUI.Frame.minBtn then
            GUI.Frame.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Up")
            GUI.Frame.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-ExpandButton-Down")
        end
    else
        -- Restore size
        GUI.Frame:SetHeight(GUI.PreMinimizeHeight or GUI.Config.defaultHeight)
        GUI.Frame:SetResizable(true)

        -- Show content areas (with nil checks)
        if GUI.Frame.content then GUI.Frame.content:Show() end
        if GUI.Frame.tabBar then GUI.Frame.tabBar:Show() end
        if GUI.Frame.statusBar then GUI.Frame.statusBar:Show() end

        -- Update button texture to collapse
        if GUI.Frame.minBtn then
            GUI.Frame.minBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Up")
            GUI.Frame.minBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-CollapseButton-Down")
        end
    end
end

-- Toggle maximize state
function GUI.ToggleMaximize()
    if not GUI.Frame then return end

    -- If minimized, restore first
    if GUI.IsMinimized then
        GUI.ToggleMinimize()
    end

    GUI.IsMaximized = not GUI.IsMaximized

    if GUI.IsMaximized then
        -- Save current size and position
        GUI.SavedSize = {
            width = GUI.Frame:GetWidth(),
            height = GUI.Frame:GetHeight()
        }
        local point, relativeTo, relativePoint, x, y = GUI.Frame:GetPoint()
        GUI.SavedPosition = {point = point, relPoint = relativePoint, x = x, y = y}

        -- Get screen dimensions
        local screenWidth = GetScreenWidth()
        local screenHeight = GetScreenHeight()

        -- Maximize to screen size (with small margin)
        GUI.Frame:ClearAllPoints()
        GUI.Frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        GUI.Frame:SetSize(screenWidth - 40, screenHeight - 40)

        -- Update button texture to restore
        if GUI.Frame.maxBtn then
            GUI.Frame.maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Up")
            GUI.Frame.maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-SmallerButton-Down")
        end
    else
        -- Restore saved size and position
        if GUI.SavedSize then
            GUI.Frame:SetSize(GUI.SavedSize.width, GUI.SavedSize.height)
        end
        if GUI.SavedPosition then
            GUI.Frame:ClearAllPoints()
            GUI.Frame:SetPoint(GUI.SavedPosition.point, UIParent, GUI.SavedPosition.relPoint,
                              GUI.SavedPosition.x, GUI.SavedPosition.y)
        else
            GUI.Frame:ClearAllPoints()
            GUI.Frame:SetPoint("CENTER")
        end

        -- Update button texture to maximize
        if GUI.Frame.maxBtn then
            GUI.Frame.maxBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Up")
            GUI.Frame.maxBtn:SetPushedTexture("Interface\\Buttons\\UI-Panel-BiggerButton-Down")
        end
    end
end

-- Create placeholder content for missing panels
local function CreatePlaceholder(parent, message)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    text:SetPoint("CENTER")
    text:SetText(message or "Content not available")
    text:SetTextColor(0.5, 0.5, 0.5)
end

-- Initialize tab content panels (v4.1 - redesigned)
function GUI.InitializeTabs(frame)
    -- Ensure AIP.Panels exists
    AIP.Panels = AIP.Panels or {}

    -- Debug: log panel availability
    AIP.Debug("Initializing tabs - Panels: Favorites=" .. tostring(AIP.Panels.Favorites ~= nil) ..
              ", Blacklist=" .. tostring(AIP.Panels.Blacklist ~= nil) ..
              ", RaidMgmt=" .. tostring(AIP.Panels.RaidMgmt ~= nil) ..
              ", LootHistory=" .. tostring(AIP.Panels.LootHistory ~= nil) ..
              ", Settings=" .. tostring(AIP.Panels.Settings ~= nil))

    -- LFM Tab (v4.3: tree view + message composer + 3-tab queue system)
    local lfmContainer = frame.tabContents["lfm"]
    GUI.CreateBrowserTab(lfmContainer, "lfm")

    -- Favorites Tab (v5.2: whitelist/priority players)
    local favoritesContainer = frame.tabContents["favorites"]
    if AIP.Panels.Favorites and type(AIP.Panels.Favorites.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Favorites.Create(favoritesContainer)
        end)
        if not success then
            AIP.Debug("Favorites panel creation failed: " .. tostring(err))
        end
    else
        local title = favoritesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Favorites")

        local info = favoritesContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Favorites list is empty\n\nAdd players to give them priority in queue")
        info:SetTextColor(0.6, 0.6, 0.6)
    end

    -- Blacklist Tab (v4.1: enhanced with search/filter)
    local blacklistContainer = frame.tabContents["blacklist"]
    if AIP.Panels.Blacklist and type(AIP.Panels.Blacklist.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Blacklist.Create(blacklistContainer)
        end)
        if not success then
            AIP.Debug("Blacklist panel creation failed: " .. tostring(err))
        end
    else
        local title = blacklistContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Blacklist")

        local info = blacklistContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Blacklist is empty\n\nAdd players to prevent them from being auto-invited")
        info:SetTextColor(0.6, 0.6, 0.6)
    end

    -- Composition Tab (v4.1: enhanced with categories)
    GUI.CreateCompositionTab(frame.tabContents["composition"])

    -- Raid Management Tab (v5.3: raid warnings, loot rules, buff checker)
    local raidMgmtContainer = frame.tabContents["raidmgmt"]
    if AIP.Panels.RaidMgmt and type(AIP.Panels.RaidMgmt.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.RaidMgmt.Create(raidMgmtContainer)
        end)
        if not success then
            AIP.Debug("RaidMgmt panel creation failed: " .. tostring(err))
            -- Show error to user
            local errorText = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorText:SetPoint("CENTER")
            errorText:SetText("|cFFFF4444Panel Error:|r " .. tostring(err))
        end
    else
        AIP.Debug("RaidMgmt panel not found - AIP.Panels.RaidMgmt=" .. tostring(AIP.Panels.RaidMgmt))
        local title = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Raid Management")

        local info = raidMgmtContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Panel not loaded.\nCheck that RaidManagementPanel.lua is in the addon folder.")
        info:SetTextColor(1, 0.4, 0.4)
    end

    -- Loot History Tab (v5.3: track loot drops)
    local lootHistoryContainer = frame.tabContents["loothistory"]
    if AIP.Panels.LootHistory and type(AIP.Panels.LootHistory.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.LootHistory.Create(lootHistoryContainer)
        end)
        if not success then
            AIP.Debug("LootHistory panel creation failed: " .. tostring(err))
            -- Show error to user
            local errorText = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            errorText:SetPoint("CENTER")
            errorText:SetText("|cFFFF4444Panel Error:|r " .. tostring(err))
        end
    else
        AIP.Debug("LootHistory panel not found - AIP.Panels.LootHistory=" .. tostring(AIP.Panels.LootHistory))
        local title = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Loot History")

        local info = lootHistoryContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Panel not loaded.\nCheck that LootHistoryPanel.lua is in the addon folder.")
        info:SetTextColor(1, 0.4, 0.4)
    end

    -- Settings Tab
    local settingsContainer = frame.tabContents["settings"]
    if AIP.Panels.Settings and type(AIP.Panels.Settings.Create) == "function" then
        local success, err = pcall(function()
            AIP.Panels.Settings.Create(settingsContainer)
        end)
        if not success then
            AIP.Debug("Settings panel creation failed: " .. tostring(err))
        end
    else
        local title = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 10, -10)
        title:SetText("Settings")

        local info = settingsContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        info:SetPoint("CENTER")
        info:SetText("Settings panel not available\n\nUse /aip commands to configure")
        info:SetTextColor(0.6, 0.6, 0.6)
    end
end

-- Create LFM browser tab with 3-frame layout (v4.1)
-- Frame 1: Tree view (left) | Frame 2: Details (right top) | Frame 3: Queue (right bottom)
function GUI.CreateBrowserTab(container, tabType)
    container.searchFilter = ""
    container.raidFilter = "ALL"
    container.tabType = tabType
    container.selectedGroupData = nil

    -- ========================================================================
    -- FRAME 1: LEFT - Tree Browser (340px width)
    -- ========================================================================
    local treePanel = CreateFrame("Frame", nil, container)
    treePanel:SetWidth(340)
    treePanel:SetPoint("TOPLEFT", 0, 0)
    treePanel:SetPoint("BOTTOMLEFT", 0, 0)
    GUI.ApplyBackdrop(treePanel, "Panel", 0.95)
    container.treePanel = treePanel

    -- Header
    local treeHeader = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    treeHeader:SetPoint("TOPLEFT", 10, -8)
    treeHeader:SetText("LFM Groups")
    treeHeader:SetTextColor(1, 0.82, 0)

    -- Refresh button and Hide Locked checkbox - inline at top right
    local refreshBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(60, 18)
    refreshBtn:SetText("Refresh")

    -- Hide Locked checkbox (only for LFM tab) - positioned at top right
    if tabType == "lfm" then
        local hideLockedCheck = CreateFrame("CheckButton", nil, treePanel, "UICheckButtonTemplate")
        hideLockedCheck:SetSize(20, 20)
        hideLockedCheck:SetPoint("TOPRIGHT", -6, -4)
        hideLockedCheck:SetChecked(AIP.TreeBrowser and AIP.TreeBrowser.HideLocked or false)
        hideLockedCheck:SetScript("OnClick", function(self)
            if AIP.TreeBrowser then
                AIP.TreeBrowser.HideLocked = self:GetChecked()
            end
            GUI.RefreshBrowserTab(tabType)
        end)
        hideLockedCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Hide Locked Instances")
            GameTooltip:AddLine("Hide groups for instances you are already saved to", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hideLockedCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local hideLockedLabel = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideLockedLabel:SetPoint("RIGHT", hideLockedCheck, "LEFT", 0, 0)
        hideLockedLabel:SetText("Hide Locked")
        hideLockedLabel:SetTextColor(0.8, 0.8, 0.8)
        container.hideLockedCheck = hideLockedCheck

        -- Position refresh button to the left of Hide Locked label
        refreshBtn:SetPoint("RIGHT", hideLockedLabel, "LEFT", -8, 0)
    else
        refreshBtn:SetPoint("TOPRIGHT", -8, -6)
    end
    refreshBtn:SetScript("OnClick", function()
        GUI.RefreshBrowserTab(tabType)
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Refresh List")
        GameTooltip:AddLine("Update the group list from chat", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Search box
    local searchLabel = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 10, -32)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", "AIPSearch" .. tabType, treePanel, "InputBoxTemplate")
    searchBox:SetSize(100, 18)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    container.searchBox = searchBox

    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            container.searchFilter = self:GetText():lower()
            GUI.RefreshBrowserTab(tabType)
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText("") self:ClearFocus() end)

    -- Filter dropdown
    local filterDropdown = CreateFrame("Frame", "AIPFilter" .. tabType, treePanel, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("LEFT", searchBox, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(filterDropdown, 80)
    UIDropDownMenu_SetText(filterDropdown, "All")
    container.filterDropdown = filterDropdown

    local function FilterInit()
        local info = UIDropDownMenu_CreateInfo()
        local filters = {
            {id = "ALL", name = "All"},
            {id = "ICC", name = "ICC"},
            {id = "RS", name = "RS"},
            {id = "TOC", name = "TOC"},
            {id = "VOA", name = "VOA"},
            {id = "ULDUAR", name = "Ulduar"},
            {id = "NAXX", name = "Naxx"},
        }
        for _, f in ipairs(filters) do
            info = UIDropDownMenu_CreateInfo()
            info.text = f.name
            info.value = f.id
            info.func = function()
                container.raidFilter = f.id
                UIDropDownMenu_SetText(filterDropdown, f.name)
                GUI.RefreshBrowserTab(tabType)
            end
            info.checked = (container.raidFilter == f.id)
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(filterDropdown, FilterInit)
    GUI.FixDropdownStrata(filterDropdown)

    -- Tree view (dynamically sized based on tree panel)
    local treeFrame
    if AIP.TreeBrowser then
        -- Calculate initial size based on tree panel dimensions
        local initialWidth = treePanel:GetWidth() - 16  -- 8px padding each side
        local initialHeight = treePanel:GetHeight() - 55 - 60  -- top offset and bottom buttons
        if initialWidth < 100 then initialWidth = 320 end  -- fallback for initial creation
        if initialHeight < 100 then initialHeight = 430 end  -- fallback for initial creation

        treeFrame = AIP.TreeBrowser.CreateTreeView(treePanel, initialWidth, initialHeight)
        treeFrame:SetPoint("TOPLEFT", 8, -55)
        treeFrame:SetPoint("BOTTOMRIGHT", treePanel, "BOTTOMRIGHT", -8, 60)  -- Anchor to bottom with space for buttons
        container.treeView = treeFrame

        -- Hook OnSizeChanged to resize tree view dynamically
        treePanel:SetScript("OnSizeChanged", function(self, width, height)
            if treeFrame and treeFrame.UpdateSize then
                -- Let tree frame use its anchor-based size (TOPLEFT + BOTTOMRIGHT)
                -- Pass nil to have UpdateSize read dimensions from anchors
                treeFrame:UpdateSize()
            end
        end)

        -- Also hook OnShow to ensure proper sizing when tab becomes visible
        treeFrame:HookScript("OnShow", function(self)
            if self.UpdateSize then
                -- Delayed call to ensure layout is complete
                AIP.Utils.DelayedCall(0.05, function()
                    self:UpdateSize()
                end)
            end
        end)
    end

    -- Empty state text
    local emptyTreeText = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyTreeText:SetPoint("CENTER", treePanel, "CENTER", 0, -20)
    emptyTreeText:SetWidth(280)
    emptyTreeText:SetJustifyH("CENTER")
    emptyTreeText:SetText("No groups found\n\nGroups appear when players\nadvertise in chat channels")
    emptyTreeText:SetTextColor(0.5, 0.5, 0.5)
    emptyTreeText:Hide()
    container.emptyTreeText = emptyTreeText

    -- Counts text
    local countsText = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countsText:SetPoint("BOTTOMLEFT", 10, 35)
    countsText:SetText("Groups: 0")
    container.countsText = countsText

    -- Action buttons at bottom of tree panel
    local addGroupBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    addGroupBtn:SetSize(50, 22)
    addGroupBtn:SetPoint("BOTTOMLEFT", 8, 8)
    addGroupBtn:SetText("LFM")
    addGroupBtn:SetScript("OnClick", function() GUI.ShowAddGroupPopup() end)
    addGroupBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Broadcast LFM")
        GameTooltip:AddLine("Broadcast your group to other addon users", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    addGroupBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local enrollBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    enrollBtn:SetSize(50, 22)
    enrollBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 5, 0)
    enrollBtn:SetText("LFG")
    enrollBtn:SetScript("OnClick", function() GUI.ShowEnrollPopup() end)
    enrollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Broadcast LFG")
        GameTooltip:AddLine("Broadcast that you're looking for a group", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enrollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    clearBtn:SetSize(50, 22)
    clearBtn:SetPoint("LEFT", enrollBtn, "RIGHT", 5, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        if AIP.GroupTracker and AIP.GroupTracker.ClearAll then
            AIP.GroupTracker.ClearAll()
        end
        GUI.RefreshBrowserTab(tabType)
    end)
    clearBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Clear Cache")
        GameTooltip:AddLine("Remove all cached group listings", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Stop Broadcast button (shows when broadcasting)
    local stopBroadcastBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    stopBroadcastBtn:SetSize(90, 22)
    stopBroadcastBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    stopBroadcastBtn:SetText("Stop BC")
    stopBroadcastBtn:Hide()  -- Hidden by default
    stopBroadcastBtn:SetScript("OnClick", function()
        GUI.StopBroadcast()
        stopBroadcastBtn:Hide()
    end)
    stopBroadcastBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Stop Broadcasting")
        if GUI.Broadcast.active then
            GameTooltip:AddLine("Currently broadcasting " .. (GUI.Broadcast.mode == "lfm" and "LFM" or "LFG"), 0, 1, 0)
        end
        GameTooltip:Show()
    end)
    stopBroadcastBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.stopBroadcastBtn = stopBroadcastBtn

    -- ========================================================================
    -- FRAME 2: RIGHT TOP - Details Panel (60% width, ~280px height)
    -- ========================================================================
    local detailsPanel = CreateFrame("Frame", nil, container)
    detailsPanel:SetPoint("TOPLEFT", treePanel, "TOPRIGHT", 5, 0)
    detailsPanel:SetPoint("RIGHT", container, "RIGHT", 0, 0)
    detailsPanel:SetHeight(280)
    GUI.ApplyBackdrop(detailsPanel, "SubPanel", 0.95)
    container.detailsPanel = detailsPanel

    -- Details header
    local detailsHeader = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detailsHeader:SetPoint("TOPLEFT", 10, -8)
    detailsHeader:SetText("Group Details")
    detailsHeader:SetTextColor(1, 0.82, 0)

    -- No selection text
    local noSelectText = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noSelectText:SetPoint("CENTER", detailsPanel, "CENTER", 0, 0)
    noSelectText:SetText("Select a group from the tree to view details")
    noSelectText:SetTextColor(0.5, 0.5, 0.5)
    container.noSelectText = noSelectText

    -- Details content (hidden until selection)
    local detContent = CreateFrame("Frame", nil, detailsPanel)
    detContent:SetPoint("TOPLEFT", 10, -28)
    detContent:SetPoint("BOTTOMRIGHT", -10, 35)
    detContent:Hide()
    container.detContent = detContent

    -- Leader
    local leaderLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leaderLabel:SetPoint("TOPLEFT", 0, 0)
    leaderLabel:SetText("Leader:")
    leaderLabel:SetTextColor(0.7, 0.7, 0.7)
    local leaderValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    leaderValue:SetPoint("LEFT", leaderLabel, "RIGHT", 5, 0)
    container.leaderValue = leaderValue

    -- Raid
    local raidLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 0, -18)
    raidLabel:SetText("Raid:")
    raidLabel:SetTextColor(0.7, 0.7, 0.7)
    local raidValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    raidValue:SetPoint("LEFT", raidLabel, "RIGHT", 5, 0)
    container.raidValue = raidValue

    -- Lockout indicator
    local lockoutIndicator = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockoutIndicator:SetPoint("LEFT", raidValue, "RIGHT", 8, 0)
    lockoutIndicator:SetText("|cFFFF4444[LOCKED]|r")
    lockoutIndicator:Hide()
    container.lockoutIndicator = lockoutIndicator

    -- Message box
    local msgLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgLabel:SetPoint("TOPLEFT", 0, -36)
    msgLabel:SetText("Message:")
    msgLabel:SetTextColor(0.7, 0.7, 0.7)

    local msgBg = CreateFrame("Frame", nil, detContent)
    msgBg:SetPoint("TOPLEFT", 0, -50)
    msgBg:SetPoint("RIGHT", -5, 0)
    msgBg:SetHeight(45)
    GUI.ApplyBackdrop(msgBg, "Inset", 0.7)
    local msgValue = msgBg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msgValue:SetPoint("TOPLEFT", 5, -5)
    msgValue:SetPoint("BOTTOMRIGHT", -5, 5)
    msgValue:SetJustifyH("LEFT")
    msgValue:SetJustifyV("TOP")
    container.msgValue = msgValue
    container.msgBg = msgBg

    -- Setup achievement tooltips for message box
    msgBg:EnableMouse(true)
    msgBg:SetScript("OnEnter", function(self)
        local text = msgValue:GetText() or ""
        local achievementIds = GUI.ExtractAllAchievementIds(text)
        if #achievementIds > 0 then
            -- Show tooltip for achievements in message
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:AddLine("Achievements in message:", 1, 0.82, 0)
            GameTooltip:AddLine(" ")
            for i, achId in ipairs(achievementIds) do
                local _, name, points, completed = GetAchievementInfo(achId)
                if name then
                    local status = completed and "|cFF00FF00\226\156\147|r" or "|cFFFF6666\226\156\151|r"
                    local pointsStr = points and points > 0 and " |cFFFFD700(" .. points .. " pts)|r" or ""
                    GameTooltip:AddLine(status .. " " .. name .. pointsStr, 1, 1, 1)
                end
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Hover over achievement links in chat", 0.5, 0.5, 0.5)
            GameTooltip:AddLine("to see full details", 0.5, 0.5, 0.5)
            GameTooltip:Show()
            self.hasAchievementTooltip = true
        else
            -- Show generic message tooltip
            local fullText = container.selectedGroupData and container.selectedGroupData.message or text
            if fullText and #fullText > 60 then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
                GameTooltip:AddLine("Full Message:", 1, 0.82, 0)
                GameTooltip:AddLine(fullText, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end
    end)
    msgBg:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
        self.hasAchievementTooltip = nil
    end)

    -- Requirements row
    local gsLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gsLabel:SetPoint("TOPLEFT", 0, -100)
    gsLabel:SetText("GearScore:")
    gsLabel:SetTextColor(0.6, 0.6, 0.6)
    local gsValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gsValue:SetPoint("LEFT", gsLabel, "RIGHT", 5, 0)
    container.gsValue = gsValue

    local ilvlLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("LEFT", gsValue, "RIGHT", 20, 0)
    ilvlLabel:SetText("iLvl:")
    ilvlLabel:SetTextColor(0.6, 0.6, 0.6)
    local ilvlValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ilvlValue:SetPoint("LEFT", ilvlLabel, "RIGHT", 5, 0)
    container.ilvlValue = ilvlValue

    -- Total filled (inline with GS/iLvl row)
    local totalFilledLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalFilledLabel:SetPoint("LEFT", ilvlValue, "RIGHT", 20, 0)
    totalFilledLabel:SetText("Filled:")
    totalFilledLabel:SetTextColor(0.6, 0.6, 0.6)
    local totalFilledValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    totalFilledValue:SetPoint("LEFT", totalFilledLabel, "RIGHT", 5, 0)
    container.totalFilledValue = totalFilledValue

    -- Composition
    local compLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    compLabel:SetPoint("TOPLEFT", 0, -118)
    compLabel:SetText("Needs:")
    compLabel:SetTextColor(0.6, 0.6, 0.6)
    local compValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    compValue:SetPoint("LEFT", compLabel, "RIGHT", 5, 0)
    container.compValue = compValue

    -- Achievement requirement
    local achieveLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achieveLabel:SetPoint("TOPLEFT", 0, -136)
    achieveLabel:SetText("Achievement:")
    achieveLabel:SetTextColor(0.6, 0.6, 0.6)
    local achieveValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    achieveValue:SetPoint("LEFT", achieveLabel, "RIGHT", 5, 0)
    achieveValue:SetWidth(200)
    achieveValue:SetJustifyH("LEFT")
    container.achieveValue = achieveValue

    -- Invite keyword
    local keywordLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keywordLabel:SetPoint("TOPLEFT", 0, -154)
    keywordLabel:SetText("Whisper:")
    keywordLabel:SetTextColor(0.6, 0.6, 0.6)
    local keywordValue = detContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    keywordValue:SetPoint("LEFT", keywordLabel, "RIGHT", 5, 0)
    keywordValue:SetTextColor(0.4, 0.8, 1)
    container.keywordValue = keywordValue

    -- Looking For (class/spec preferences) - Interactive display with tooltips
    local lookingForLabel = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lookingForLabel:SetPoint("TOPLEFT", 0, -170)
    lookingForLabel:SetText("Looking for:")
    lookingForLabel:SetTextColor(0.6, 0.6, 0.6)

    -- Container frame for looking for classes (allows tooltips)
    local lookingForFrame = CreateFrame("Frame", nil, detContent)
    lookingForFrame:SetPoint("TOPLEFT", 0, -184)
    lookingForFrame:SetPoint("RIGHT", -5, 0)
    lookingForFrame:SetHeight(36)  -- Room for 2 lines
    container.lookingForFrame = lookingForFrame

    -- Text display (fallback)
    local lookingForValue = lookingForFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lookingForValue:SetPoint("TOPLEFT", 0, 0)
    lookingForValue:SetPoint("RIGHT", -5, 0)
    lookingForValue:SetJustifyH("LEFT")
    lookingForValue:SetWordWrap(true)
    lookingForValue:SetTextColor(0.9, 0.9, 0.9)
    container.lookingForValue = lookingForValue

    -- Store class buttons for reuse
    container.lookingForButtons = {}

    -- Details action buttons - Request Invite (sends whisper with player info)
    local requestInviteBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    requestInviteBtn:SetSize(120, 24)
    requestInviteBtn:SetPoint("BOTTOMLEFT", 10, 8)
    requestInviteBtn:SetText("Request Invite")
    requestInviteBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        if not data or not data.leader then
            AIP.Print("Select a group first")
            return
        end

        -- Build request message with player info
        local _, class = UnitClass("player")
        local spec = GUI.GetPlayerSpecName()
        local role = GUI.DetectPlayerRole()
        local gs = GUI.CalculatePlayerGS()
        local ilvl = GUI.CalculatePlayerIlvl()
        local raidKey = data.raid or "Unknown"

        -- Get best achievement for this raid
        local achieveLink = ""
        local playerAchievements = GUI.GetPlayerAchievementsForRaid(raidKey)
        if playerAchievements and #playerAchievements > 0 then
            achieveLink = GetAchievementLink(playerAchievements[1].id) or ""
        end

        -- Format: "Hi! Invite please ICC25H - Warrior (Arms) DPS, GS: 5200, iLvl: 245 [Achievement]"
        local classDisplay = class:sub(1,1) .. class:sub(2):lower()
        local msg = string.format("Hi! Invite please %s - %s (%s) %s, GS: %d, iLvl: %d %s",
            raidKey, classDisplay, spec, role, gs, ilvl, achieveLink)

        -- Send whisper
        SendChatMessage(msg, "WHISPER", nil, data.leader)
        AIP.Print("Invite request sent to " .. data.leader)
    end)
    requestInviteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Request Invite")
        GameTooltip:AddLine("Send detailed whisper with your class,", 1, 1, 1)
        GameTooltip:AddLine("spec, GS, iLvl, and achievement", 1, 1, 1)
        GameTooltip:Show()
    end)
    requestInviteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.requestInviteBtn = requestInviteBtn

    -- Quick Request button - sends autoinvite keyword
    local quickRequestBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    quickRequestBtn:SetSize(90, 24)
    quickRequestBtn:SetPoint("LEFT", requestInviteBtn, "RIGHT", 5, 0)
    quickRequestBtn:SetText("Quick Req")
    quickRequestBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        if not data or not data.leader then
            AIP.Print("Select a group first")
            return
        end

        -- First check if group has a stored keyword (from Add Group popup)
        local keyword = data.inviteKeyword

        -- If no stored keyword, try to extract from message
        if (not keyword or keyword == "") and data.message then
            local msg = data.message

            -- Comprehensive patterns to detect invite keywords
            -- Ordered by specificity (most specific first)
            local patterns = {
                -- Quoted patterns (highest priority)
                'w/%s*"([^"]+)"',           -- w/ "keyword"
                "w/%s*'([^']+)'",           -- w/ 'keyword'
                'whisper%s*"([^"]+)"',      -- whisper "keyword"
                "whisper%s*'([^']+)'",      -- whisper 'keyword'
                '/w%s*"([^"]+)"',           -- /w "keyword"
                "/w%s*'([^']+)'",           -- /w 'keyword'
                '"([^"]+)"%s*for%s*inv',    -- "keyword" for inv
                "'([^']+)'%s*for%s*inv",    -- 'keyword' for inv

                -- Unquoted patterns
                "w/%s+([%w%-_]+)",           -- w/ keyword
                "whisper%s+([%w%-_]+)",      -- whisper keyword
                "/w%s+([%w%-_]+)",           -- /w keyword
                "pst%s+([%w%-_]+)",          -- pst keyword
                "([%w%-_]+)%s+for%s+inv",    -- keyword for inv
                "([%w%-_]+)%s+to%s+join",    -- keyword to join

                -- AIP protocol pattern
                "{AIP[^}]*}.-w/%s*([%w%-_]+)",  -- {AIP:x.x} ... w/ keyword
            }

            for _, pattern in ipairs(patterns) do
                local found = msg:lower():match(pattern)
                if found and #found >= 2 and #found <= 20 then
                    -- Validate it's not a common word
                    local invalidWords = {["the"]=1, ["and"]=1, ["for"]=1, ["lfm"]=1, ["lf"]=1, ["need"]=1, ["tank"]=1, ["heal"]=1, ["dps"]=1}
                    if not invalidWords[found:lower()] then
                        keyword = found
                        break
                    end
                end
            end
        end

        -- Default to the global trigger keyword
        if not keyword or keyword == "" then
            keyword = AIP.db and AIP.db.triggers and AIP.db.triggers:match("^([^;]+)") or "invme-auto"
        end

        -- Send keyword whisper
        SendChatMessage(keyword, "WHISPER", nil, data.leader)
        AIP.Print("Quick request sent to " .. data.leader .. " with keyword: |cFF00FFFF" .. keyword .. "|r")
    end)
    quickRequestBtn:SetScript("OnEnter", function(self)
        local data = container.selectedGroupData
        local keyword = "invme-auto"
        if data then
            if data.inviteKeyword and data.inviteKeyword ~= "" then
                keyword = data.inviteKeyword
            elseif data.message then
                -- Quick preview of detected keyword
                local msg = data.message:lower()
                for _, pat in ipairs({'w/%s*"([^"]+)"', "w/%s*'([^']+)'", "w/%s+([%w%-_]+)"}) do
                    local found = msg:match(pat)
                    if found and #found <= 20 then keyword = found break end
                end
            end
        end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quick Request")
        GameTooltip:AddLine("Sends the autoinvite keyword to the group leader", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Detected keyword: |cFF00FFFF" .. keyword .. "|r", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    quickRequestBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.quickRequestBtn = quickRequestBtn

    local blacklistBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    blacklistBtn:SetSize(65, 24)
    blacklistBtn:SetPoint("LEFT", quickRequestBtn, "RIGHT", 5, 0)
    blacklistBtn:SetText("Block")
    blacklistBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        if data and data.leader then
            AIP.AddToBlacklist(data.leader, "From LFM browser", "lfm")
            GUI.RefreshBrowserTab(tabType)
        end
    end)
    blacklistBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Blacklist")
        GameTooltip:AddLine("Add this player to your blacklist", 1, 0.3, 0.3)
        GameTooltip:Show()
    end)
    blacklistBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Whisper button (plain whisper to open chat)
    local whisperBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    whisperBtn:SetSize(70, 24)
    whisperBtn:SetPoint("LEFT", blacklistBtn, "RIGHT", 5, 0)
    whisperBtn:SetText("Whisper")
    whisperBtn:SetScript("OnClick", function()
        local leader = container.currentLeader
            or (container.selectedGroupData and (container.selectedGroupData.leader or container.selectedGroupData.name))
        if leader then
            ChatFrame_OpenChat("/w " .. leader .. " ")
        else
            AIP.Print("No player selected to whisper")
        end
    end)
    whisperBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Whisper")
        GameTooltip:AddLine("Open chat to send a custom whisper", 1, 1, 1)
        GameTooltip:Show()
    end)
    whisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.whisperBtn = whisperBtn

    -- ========================================================================
    -- FRAME 3: RIGHT BOTTOM - Queue Panel
    -- ========================================================================
    local queuePanel = CreateFrame("Frame", nil, container)
    queuePanel:SetPoint("TOPLEFT", detailsPanel, "BOTTOMLEFT", 0, -5)
    queuePanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    GUI.ApplyBackdrop(queuePanel, "SubPanel", 0.95)
    container.queuePanel = queuePanel

    -- === Queue Panel Sub-Tabs ===
    container.queueSubTab = "queue"  -- "queue" or "lfg"

    -- Tab buttons
    local queueTabBtn = CreateFrame("Button", nil, queuePanel)
    queueTabBtn:SetSize(70, 20)
    queueTabBtn:SetPoint("TOPLEFT", 8, -6)
    local queueTabBg = queueTabBtn:CreateTexture(nil, "BACKGROUND")
    queueTabBg:SetAllPoints()
    queueTabBg:SetTexture(0.3, 0.3, 0.4, 1)
    queueTabBtn.bg = queueTabBg
    local queueTabText = queueTabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueTabText:SetPoint("CENTER")
    queueTabText:SetText("Queue")
    queueTabText:SetTextColor(1, 0.82, 0)
    queueTabBtn.text = queueTabText
    container.queueTabBtn = queueTabBtn

    local lfgTabBtn = CreateFrame("Button", nil, queuePanel)
    lfgTabBtn:SetSize(70, 20)
    lfgTabBtn:SetPoint("LEFT", queueTabBtn, "RIGHT", 2, 0)
    local lfgTabBg = lfgTabBtn:CreateTexture(nil, "BACKGROUND")
    lfgTabBg:SetAllPoints()
    lfgTabBg:SetTexture(0.15, 0.15, 0.15, 1)
    lfgTabBtn.bg = lfgTabBg
    local lfgTabText = lfgTabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lfgTabText:SetPoint("CENTER")
    lfgTabText:SetText("LFG (0)")
    lfgTabText:SetTextColor(0.8, 0.8, 0.8)
    lfgTabBtn.text = lfgTabText
    container.lfgTabBtn = lfgTabBtn

    -- Waitlist tab button
    local waitlistTabBtn = CreateFrame("Button", nil, queuePanel)
    waitlistTabBtn:SetSize(80, 22)
    waitlistTabBtn:SetPoint("LEFT", lfgTabBtn, "RIGHT", 2, 0)
    local waitlistTabBg = waitlistTabBtn:CreateTexture(nil, "BACKGROUND")
    waitlistTabBg:SetAllPoints()
    waitlistTabBg:SetTexture(0.15, 0.15, 0.15, 1)
    waitlistTabBtn.bg = waitlistTabBg
    local waitlistTabText = waitlistTabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    waitlistTabText:SetPoint("CENTER")
    waitlistTabText:SetText("Waitlist (0)")
    waitlistTabText:SetTextColor(0.8, 0.8, 0.8)
    waitlistTabBtn.text = waitlistTabText
    container.waitlistTabBtn = waitlistTabBtn

    -- Tab switch function
    local function SwitchQueueSubTab(tab)
        container.queueSubTab = tab
        -- Reset all tabs
        queueTabBg:SetTexture(0.15, 0.15, 0.15, 1)
        queueTabText:SetTextColor(0.8, 0.8, 0.8)
        lfgTabBg:SetTexture(0.15, 0.15, 0.15, 1)
        lfgTabText:SetTextColor(0.8, 0.8, 0.8)
        waitlistTabBg:SetTexture(0.15, 0.15, 0.15, 1)
        waitlistTabText:SetTextColor(0.8, 0.8, 0.8)
        if container.queueContent then container.queueContent:Hide() end
        if container.lfgContent then container.lfgContent:Hide() end
        if container.waitlistContent then container.waitlistContent:Hide() end

        -- Hide refresh button by default (shown only on LFG tab)
        if container.refreshLfgBtn then container.refreshLfgBtn:Hide() end

        -- Activate selected tab
        if tab == "queue" then
            queueTabBg:SetTexture(0.3, 0.3, 0.4, 1)
            queueTabText:SetTextColor(1, 0.82, 0)
            if container.queueContent then container.queueContent:Show() end
        elseif tab == "lfg" then
            lfgTabBg:SetTexture(0.3, 0.3, 0.4, 1)
            lfgTabText:SetTextColor(1, 0.82, 0)
            if container.lfgContent then container.lfgContent:Show() end
            -- Show refresh button only on LFG tab
            if container.refreshLfgBtn then container.refreshLfgBtn:Show() end
        elseif tab == "waitlist" then
            waitlistTabBg:SetTexture(0.3, 0.3, 0.4, 1)
            waitlistTabText:SetTextColor(1, 0.82, 0)
            if container.waitlistContent then container.waitlistContent:Show() end
        end
        GUI.UpdateQueuePanel(container)
    end

    queueTabBtn:SetScript("OnClick", function() SwitchQueueSubTab("queue") end)
    lfgTabBtn:SetScript("OnClick", function() SwitchQueueSubTab("lfg") end)
    waitlistTabBtn:SetScript("OnClick", function() SwitchQueueSubTab("waitlist") end)

    -- Invite All button
    local inviteAllBtn = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    inviteAllBtn:SetSize(70, 20)
    inviteAllBtn:SetPoint("TOPRIGHT", -8, -6)
    inviteAllBtn:SetText("Invite All")
    inviteAllBtn:SetScript("OnClick", function()
        if AIP.InviteAllFromQueue then AIP.InviteAllFromQueue() end
    end)

    -- === QUEUE CONTENT (Whisper requests) ===
    local queueContent = CreateFrame("Frame", nil, queuePanel)
    queueContent:SetPoint("TOPLEFT", 5, -30)
    queueContent:SetPoint("BOTTOMRIGHT", -5, 30)
    container.queueContent = queueContent

    -- Queue column headers
    local qHeaders = {
        {text = "#", x = 5, width = 20},
        {text = "Player", x = 25, width = 85},
        {text = "Class", x = 110, width = 55},
        {text = "Message", x = 165, width = 115},
        {text = "Time", x = 285, width = 35},
        {text = "BL?", x = 322, width = 25},
        {text = "Actions", x = 350, width = 140},
    }
    for _, h in ipairs(qHeaders) do
        local label = queueContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, 0)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
    end

    -- Add Player button for queue
    local addQueueBtn = CreateFrame("Button", nil, queueContent, "UIPanelButtonTemplate")
    addQueueBtn:SetSize(70, 18)
    addQueueBtn:SetPoint("TOPRIGHT", -5, 2)
    addQueueBtn:SetText("+ Add")
    addQueueBtn:SetScript("OnClick", function()
        GUI.ShowAddToQueuePopup()
    end)
    addQueueBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Add Player to Queue")
        GameTooltip:AddLine("Manually add a player by name", 1, 1, 1)
        GameTooltip:Show()
    end)
    addQueueBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.addQueueBtn = addQueueBtn

    -- Queue rows (whisper requests)
    container.queueRows = {}
    local ROW_HEIGHT = 20
    local NUM_ROWS = 5
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, queueContent)
        row:SetSize(500, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -18 - ((i - 1) * ROW_HEIGHT))
        row.numText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.numText:SetPoint("LEFT", 5, 0)
        row.numText:SetWidth(20)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("LEFT", 25, 0)
        row.nameText:SetWidth(80)
        row.nameText:SetJustifyH("LEFT")
        row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.classText:SetPoint("LEFT", 110, 0)
        row.classText:SetWidth(50)
        row.classText:SetJustifyH("LEFT")
        row.msgText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.msgText:SetPoint("LEFT", 165, 0)
        row.msgText:SetWidth(115)
        row.msgText:SetJustifyH("LEFT")
        row.msgText:SetTextColor(0.7, 0.7, 0.7)
        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timeText:SetPoint("LEFT", 285, 0)
        row.timeText:SetWidth(35)
        row.timeText:SetJustifyH("CENTER")
        row.timeText:SetTextColor(0.5, 0.5, 0.5)
        row.blText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.blText:SetPoint("LEFT", 322, 0)
        row.blText:SetWidth(25)
        row.invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.invBtn:SetSize(28, 16)
        row.invBtn:SetPoint("LEFT", 350, 0)
        row.invBtn:SetText("Inv")
        row.invBtn.index = i
        row.invBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and entry.name and AIP.InviteFromQueueByName then
                AIP.InviteFromQueueByName(entry.name)
            end
        end)
        row.invBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Invite Player")
            GameTooltip:AddLine("Send raid/party invite to this player", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.invBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.rejBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.rejBtn:SetSize(28, 16)
        row.rejBtn:SetPoint("LEFT", 380, 0)
        row.rejBtn:SetText("Rej")
        row.rejBtn.index = i
        row.rejBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and entry.name and AIP.RejectFromQueueByName then
                AIP.RejectFromQueueByName(entry.name, false)
            end
        end)
        row.rejBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Reject Player")
            GameTooltip:AddLine("Remove from queue and send rejection whisper", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.rejBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.waitBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.waitBtn:SetSize(18, 16)
        row.waitBtn:SetPoint("LEFT", 410, 0)
        row.waitBtn:SetText("W")
        row.waitBtn.index = i
        row.waitBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if not entry or not entry.name then
                AIP.Print("No entry data available")
                return
            end

            -- Ensure waitlist exists
            if not AIP.db then AIP.db = {} end
            if not AIP.db.waitlist then AIP.db.waitlist = {} end

            -- Check if already on waitlist
            local alreadyOnWaitlist = false
            for _, wEntry in ipairs(AIP.db.waitlist) do
                if wEntry.name and wEntry.name:lower() == entry.name:lower() then
                    alreadyOnWaitlist = true
                    break
                end
            end

            if alreadyOnWaitlist then
                AIP.Print(entry.name .. " is already on the waitlist")
                return
            end

            -- Capitalize name properly
            local properName = entry.name:sub(1,1):upper() .. entry.name:sub(2):lower()

            -- Add to waitlist
            local waitlistEntry = {
                name = properName,
                role = entry.role or "DPS",
                addedTime = time(),
                priority = #AIP.db.waitlist + 1,
                note = "Moved from queue",
                class = entry.class,
                gs = entry.gs,
            }
            table.insert(AIP.db.waitlist, waitlistEntry)

            -- Send waitlist response if configured
            if AIP.db.responseWaitlist and AIP.db.responseWaitlist ~= "" then
                local position = #AIP.db.waitlist
                local msg = AIP.db.responseWaitlist
                -- Use pcall with format() for %d pattern, fallback to gsub for other patterns
                local success, formatted = pcall(string.format, msg, position)
                if success then
                    msg = formatted
                else
                    -- Fallback: replace common patterns manually
                    msg = msg:gsub("%%s", tostring(position))
                    msg = msg:gsub("#X", tostring(position))
                end
                SendChatMessage(msg, "WHISPER", nil, properName)
            end

            -- Remove from queue
            if AIP.db.queue then
                for i = #AIP.db.queue, 1, -1 do
                    local qEntry = AIP.db.queue[i]
                    if qEntry.name and qEntry.name:lower() == entry.name:lower() then
                        table.remove(AIP.db.queue, i)
                        break
                    end
                end
            end

            AIP.Print(properName .. " moved to waitlist (position #" .. #AIP.db.waitlist .. ")")

            -- Update UI
            GUI.UpdateQueuePanel(container)
        end)
        row.waitBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move to Waitlist")
            GameTooltip:AddLine("Move player from queue to waitlist", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.waitBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.blBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.blBtn:SetSize(18, 16)
        row.blBtn:SetPoint("LEFT", 430, 0)
        row.blBtn:SetText("B")
        row.blBtn.index = i
        row.blBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and entry.name and AIP.RejectFromQueueByName then
                AIP.RejectFromQueueByName(entry.name, true, "Rejected")
            end
        end)
        row.blBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Blacklist Player")
            GameTooltip:AddLine("Reject and add to blacklist", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.blBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        -- Remove (X) button
        row.remBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remBtn:SetSize(18, 16)
        row.remBtn:SetPoint("LEFT", 450, 0)
        row.remBtn:SetText("X")
        row.remBtn.index = i
        row.remBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and entry.name then
                -- Remove from queue without rejection message
                if AIP.db and AIP.db.queue then
                    for j = #AIP.db.queue, 1, -1 do
                        if AIP.db.queue[j].name and AIP.db.queue[j].name:lower() == entry.name:lower() then
                            table.remove(AIP.db.queue, j)
                            break
                        end
                    end
                end
                AIP.Print("Removed " .. entry.name .. " from queue")
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.remBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Remove")
            GameTooltip:AddLine("Remove from queue (no whisper)", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.remBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:Hide()
        container.queueRows[i] = row
    end

    -- === LFG CONTENT (Enrollment broadcasts) ===
    local lfgContent = CreateFrame("Frame", nil, queuePanel)
    lfgContent:SetPoint("TOPLEFT", 5, -30)
    lfgContent:SetPoint("BOTTOMRIGHT", -5, 30)
    lfgContent:Hide()
    container.lfgContent = lfgContent

    -- LFG column headers
    local lfgHeaders = {
        {text = "#", x = 5, width = 20},
        {text = "Player", x = 25, width = 90},
        {text = "Spec", x = 115, width = 70},
        {text = "Raid", x = 185, width = 80},
        {text = "GS", x = 265, width = 50},
        {text = "Actions", x = 320, width = 180},
    }
    for _, h in ipairs(lfgHeaders) do
        local label = lfgContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, 0)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
    end

    -- LFG rows (enrollment broadcasts)
    container.lfgRows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, lfgContent)
        row:SetSize(500, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -18 - ((i - 1) * ROW_HEIGHT))
        row.numText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.numText:SetPoint("LEFT", 5, 0)
        row.numText:SetWidth(20)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("LEFT", 25, 0)
        row.nameText:SetWidth(85)
        row.nameText:SetJustifyH("LEFT")
        row.specText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.specText:SetPoint("LEFT", 115, 0)
        row.specText:SetWidth(65)
        row.specText:SetJustifyH("LEFT")
        row.raidText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.raidText:SetPoint("LEFT", 185, 0)
        row.raidText:SetWidth(75)
        row.raidText:SetJustifyH("LEFT")
        row.gsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.gsText:SetPoint("LEFT", 265, 0)
        row.gsText:SetWidth(45)

        -- Row tooltip for full player info
        row:EnableMouse(true)
        row.index = i
        row:SetScript("OnEnter", function(self)
            local entry = container.lfgData and container.lfgData[self.index]
            if entry then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- Header with name
                local classColor = RAID_CLASS_COLORS[entry.class] or {r=1, g=1, b=1}
                GameTooltip:AddLine(entry.name or "Unknown", classColor.r, classColor.g, classColor.b)
                GameTooltip:AddLine(" ")

                -- Class and Spec
                local classDisplay = entry.class and (entry.class:sub(1,1) .. entry.class:sub(2):lower()) or "Unknown"
                GameTooltip:AddDoubleLine("Class:", classDisplay, 0.6, 0.6, 0.6, 1, 1, 1)
                if entry.spec then
                    GameTooltip:AddDoubleLine("Spec:", entry.spec, 0.6, 0.6, 0.6, 1, 1, 1)
                end
                if entry.role then
                    GameTooltip:AddDoubleLine("Role:", entry.role, 0.6, 0.6, 0.6, 1, 1, 1)
                end
                GameTooltip:AddLine(" ")

                -- Stats
                if entry.gs and entry.gs > 0 then
                    local r, g, b = 1, 1, 1
                    if AIP.Integrations and AIP.Integrations.GetGSColor then
                        r, g, b = AIP.Integrations.GetGSColor(entry.gs)
                    end
                    GameTooltip:AddDoubleLine("GearScore:", tostring(entry.gs), 0.6, 0.6, 0.6, r, g, b)
                end
                if entry.ilvl and entry.ilvl > 0 then
                    GameTooltip:AddDoubleLine("Item Level:", tostring(entry.ilvl), 0.6, 0.6, 0.6, 1, 0.82, 0)
                end
                if entry.level and entry.level > 0 then
                    GameTooltip:AddDoubleLine("Level:", tostring(entry.level), 0.6, 0.6, 0.6, 0.8, 0.8, 0.8)
                end
                GameTooltip:AddLine(" ")

                -- Looking for
                if entry.raid then
                    GameTooltip:AddDoubleLine("Looking for:", entry.raid, 0.6, 0.6, 0.6, 0.4, 0.8, 1)
                end

                -- Full message
                if entry.message then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Full Message:", 0.6, 0.6, 0.6)
                    GameTooltip:AddLine(entry.message, 1, 1, 1, true)
                end

                -- Self indicator
                if entry.isSelf then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("This is your enrollment", 0, 1, 0)
                end

                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row.invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.invBtn:SetSize(50, 16)
        row.invBtn:SetPoint("LEFT", 320, 0)
        row.invBtn:SetText("Invite")
        row.invBtn.index = i
        row.invBtn:SetScript("OnClick", function(self)
            local entry = container.lfgData and container.lfgData[self.index]
            if entry and entry.name then InviteUnit(entry.name) end
        end)
        row.whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisperBtn:SetSize(40, 16)
        row.whisperBtn:SetPoint("LEFT", 372, 0)
        row.whisperBtn:SetText("W")
        row.whisperBtn.index = i
        row.whisperBtn:SetScript("OnClick", function(self)
            local entry = container.lfgData and container.lfgData[self.index]
            if entry and entry.name then ChatFrame_OpenChat("/w " .. entry.name .. " ") end
        end)
        row.whisperBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Whisper")
            GameTooltip:AddLine("Open whisper to this player", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.whisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Add to Queue button
        row.queueBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.queueBtn:SetSize(40, 16)
        row.queueBtn:SetPoint("LEFT", 414, 0)
        row.queueBtn:SetText("Q+")
        row.queueBtn.index = i
        row.queueBtn:SetScript("OnClick", function(self)
            local entry = container.lfgData and container.lfgData[self.index]
            if entry and entry.name then
                -- Add to queue
                if not AIP.db then AIP.db = {} end
                if not AIP.db.queue then AIP.db.queue = {} end

                -- Check if already in queue
                local alreadyInQueue = false
                for _, qEntry in ipairs(AIP.db.queue) do
                    if qEntry.name and qEntry.name:lower() == entry.name:lower() then
                        alreadyInQueue = true
                        break
                    end
                end

                if alreadyInQueue then
                    AIP.Print(entry.name .. " is already in queue")
                    return
                end

                -- Create queue entry from LFG data
                local queueEntry = {
                    name = entry.name,
                    message = "LFG: " .. (entry.raid or "Unknown") .. " " .. (entry.role or "DPS"),
                    time = time(),
                    class = entry.class,
                    gs = entry.gs,
                    isBlacklisted = AIP.IsBlacklisted and AIP.IsBlacklisted(entry.name) or false,
                }
                table.insert(AIP.db.queue, queueEntry)
                AIP.Print(entry.name .. " added to queue from LFG list")

                -- Update UI
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.queueBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Add to Queue")
            GameTooltip:AddLine("Add this player to your invite queue", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.queueBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Add to Waitlist button
        row.waitlistBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.waitlistBtn:SetSize(40, 16)
        row.waitlistBtn:SetPoint("LEFT", 456, 0)
        row.waitlistBtn:SetText("WL+")
        row.waitlistBtn.index = i
        row.waitlistBtn:SetScript("OnClick", function(self)
            local entry = container.lfgData and container.lfgData[self.index]
            if entry and entry.name then
                -- Ensure waitlist exists
                if not AIP.db then AIP.db = {} end
                if not AIP.db.waitlist then AIP.db.waitlist = {} end

                -- Check if already on waitlist
                local alreadyOnWaitlist = false
                for _, wEntry in ipairs(AIP.db.waitlist) do
                    if wEntry.name and wEntry.name:lower() == entry.name:lower() then
                        alreadyOnWaitlist = true
                        break
                    end
                end

                if alreadyOnWaitlist then
                    AIP.Print(entry.name .. " is already on the waitlist")
                    return
                end

                -- Capitalize name properly
                local properName = entry.name:sub(1,1):upper() .. entry.name:sub(2):lower()

                -- Create waitlist entry from LFG data
                local waitlistEntry = {
                    name = properName,
                    role = entry.role or "DPS",
                    addedTime = time(),
                    priority = #AIP.db.waitlist + 1,
                    note = "From LFG: " .. (entry.raid or "Unknown"),
                    class = entry.class,
                    gs = entry.gs,
                }
                table.insert(AIP.db.waitlist, waitlistEntry)
                AIP.Print(properName .. " added to waitlist from LFG list (position #" .. #AIP.db.waitlist .. ")")

                -- Update UI
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.waitlistBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Add to Waitlist")
            GameTooltip:AddLine("Add this player to your waitlist for future raids", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.waitlistBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Hide()
        container.lfgRows[i] = row
    end

    -- === WAITLIST CONTENT ===
    local waitlistContent = CreateFrame("Frame", nil, queuePanel)
    waitlistContent:SetPoint("TOPLEFT", 5, -30)
    waitlistContent:SetPoint("BOTTOMRIGHT", -5, 30)
    waitlistContent:Hide()
    container.waitlistContent = waitlistContent

    -- Waitlist column headers
    local wlHeaders = {
        {text = "#", x = 5, width = 20},
        {text = "Player", x = 25, width = 90},
        {text = "Role", x = 115, width = 50},
        {text = "Note", x = 170, width = 130},
        {text = "Added", x = 305, width = 50},
        {text = "Actions", x = 360, width = 100},
    }
    for _, h in ipairs(wlHeaders) do
        local label = waitlistContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, 0)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
    end

    -- Add Player button for waitlist
    local addWaitlistBtn = CreateFrame("Button", nil, waitlistContent, "UIPanelButtonTemplate")
    addWaitlistBtn:SetSize(70, 18)
    addWaitlistBtn:SetPoint("TOPRIGHT", -5, 2)
    addWaitlistBtn:SetText("+ Add")
    addWaitlistBtn:SetScript("OnClick", function()
        GUI.ShowAddToWaitlistPopup()
    end)
    addWaitlistBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Add Player to Waitlist")
        GameTooltip:AddLine("Manually add a player with role and note", 1, 1, 1)
        GameTooltip:Show()
    end)
    addWaitlistBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.addWaitlistBtn = addWaitlistBtn

    -- Waitlist rows
    container.waitlistRows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, waitlistContent)
        row:SetSize(480, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -18 - ((i - 1) * ROW_HEIGHT))
        row.numText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.numText:SetPoint("LEFT", 5, 0)
        row.numText:SetWidth(20)
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.nameText:SetPoint("LEFT", 25, 0)
        row.nameText:SetWidth(85)
        row.nameText:SetJustifyH("LEFT")
        row.roleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.roleText:SetPoint("LEFT", 115, 0)
        row.roleText:SetWidth(50)
        row.roleText:SetJustifyH("LEFT")
        row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.noteText:SetPoint("LEFT", 170, 0)
        row.noteText:SetWidth(125)
        row.noteText:SetJustifyH("LEFT")
        row.noteText:SetTextColor(0.7, 0.7, 0.7)
        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.timeText:SetPoint("LEFT", 305, 0)
        row.timeText:SetWidth(45)
        row.timeText:SetTextColor(0.5, 0.5, 0.5)
        row.invBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.invBtn:SetSize(35, 16)
        row.invBtn:SetPoint("LEFT", 360, 0)
        row.invBtn:SetText("Inv")
        row.invBtn.index = i
        row.invBtn:SetScript("OnClick", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local entry = entries[self.index]
            if entry and entry.name then
                -- Invite the player
                InviteUnit(entry.name)
                AIP.Print("Invited " .. entry.name .. " from waitlist")
                -- Remove from waitlist
                table.remove(AIP.db.waitlist, self.index)
                -- Update priorities
                for j, e in ipairs(AIP.db.waitlist) do
                    e.priority = j
                end
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.invBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Invite")
            GameTooltip:AddLine("Invite player and remove from waitlist", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.invBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.upBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.upBtn:SetSize(22, 16)
        row.upBtn:SetPoint("LEFT", 397, 0)
        row.upBtn:SetText("^")
        row.upBtn.index = i
        row.upBtn:SetScript("OnClick", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local idx = self.index
            if idx > 1 and entries[idx] then
                -- Swap with previous entry
                entries[idx], entries[idx - 1] = entries[idx - 1], entries[idx]
                -- Update priorities
                for j, e in ipairs(entries) do
                    e.priority = j
                end
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.upBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move Up")
            GameTooltip:AddLine("Increase priority (move up in list)", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.upBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.downBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.downBtn:SetSize(22, 16)
        row.downBtn:SetPoint("LEFT", 421, 0)
        row.downBtn:SetText("v")
        row.downBtn.index = i
        row.downBtn:SetScript("OnClick", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local idx = self.index
            if idx < #entries and entries[idx] then
                -- Swap with next entry
                entries[idx], entries[idx + 1] = entries[idx + 1], entries[idx]
                -- Update priorities
                for j, e in ipairs(entries) do
                    e.priority = j
                end
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.downBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move Down")
            GameTooltip:AddLine("Decrease priority (move down in list)", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.downBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.remBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.remBtn:SetSize(22, 16)
        row.remBtn:SetPoint("LEFT", 445, 0)
        row.remBtn:SetText("X")
        row.remBtn.index = i
        row.remBtn:SetScript("OnClick", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local entry = entries[self.index]
            if entry and entry.name then
                local removedName = entry.name
                table.remove(AIP.db.waitlist, self.index)
                -- Update priorities
                for j, e in ipairs(AIP.db.waitlist) do
                    e.priority = j
                end
                AIP.Print("Removed " .. removedName .. " from waitlist")
                GUI.UpdateQueuePanel(container)
            end
        end)
        row.remBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Remove")
            GameTooltip:AddLine("Remove player from waitlist", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.remBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Enable mouse for tooltips
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local e = entries[self.invBtn.index]
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(e.name or "Unknown", 1, 0.82, 0)
            GameTooltip:AddLine("Role: " .. (e.role or "DPS"), 0.7, 0.7, 0.7)
            if e.class then GameTooltip:AddLine("Class: " .. e.class, 1, 1, 1) end
            if e.gs then GameTooltip:AddDoubleLine("GearScore:", tostring(e.gs), 0.7, 0.7, 0.7, 0, 1, 0) end
            if e.note and e.note ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Note: " .. e.note, 1, 1, 1, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Hide()
        container.waitlistRows[i] = row
    end

    -- Queue status
    local queueStatus = queuePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueStatus:SetPoint("BOTTOMLEFT", 10, 8)
    queueStatus:SetText("Status: Ready")
    container.queueStatus = queueStatus

    -- Timer refresh for queue/waitlist time displays (every 5 seconds)
    queuePanel.timerElapsed = 0
    queuePanel:SetScript("OnUpdate", function(self, elapsed)
        self.timerElapsed = self.timerElapsed + elapsed
        if self.timerElapsed >= 5 then
            self.timerElapsed = 0
            -- Update time displays for queue rows
            if container.queueRows then
                for _, row in ipairs(container.queueRows) do
                    if row:IsShown() and row.timeText and row.entryData and row.entryData.time then
                        local elapsed = time() - row.entryData.time
                        local timeStr
                        if elapsed < 60 then
                            timeStr = elapsed .. "s"
                        elseif elapsed < 3600 then
                            timeStr = math.floor(elapsed / 60) .. "m"
                        else
                            timeStr = math.floor(elapsed / 3600) .. "h"
                        end
                        row.timeText:SetText(timeStr)
                        if elapsed < 120 then
                            row.timeText:SetTextColor(0.4, 0.8, 0.4)
                        elseif elapsed < 300 then
                            row.timeText:SetTextColor(0.8, 0.8, 0.4)
                        else
                            row.timeText:SetTextColor(0.8, 0.4, 0.4)
                        end
                    end
                end
            end
            -- Update time displays for waitlist rows
            if container.waitlistRows then
                local entries = AIP.db and AIP.db.waitlist or {}
                for i, row in ipairs(container.waitlistRows) do
                    if row:IsShown() and row.timeText and entries[i] and entries[i].addedTime then
                        local elapsed = time() - entries[i].addedTime
                        local timeStr
                        if elapsed < 60 then
                            timeStr = elapsed .. "s"
                        elseif elapsed < 3600 then
                            timeStr = math.floor(elapsed / 60) .. "m"
                        else
                            timeStr = math.floor(elapsed / 3600) .. "h"
                        end
                        row.timeText:SetText(timeStr)
                    end
                end
            end
        end
    end)

    local clearQueueBtn = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    clearQueueBtn:SetSize(50, 20)
    clearQueueBtn:SetPoint("BOTTOMRIGHT", -10, 5)
    clearQueueBtn:SetText("Clear")
    clearQueueBtn:SetScript("OnClick", function()
        local tab = container.queueSubTab
        if tab == "queue" then
            if AIP.ClearQueue then AIP.ClearQueue() end
            AIP.Print("Queue cleared")
        elseif tab == "lfg" then
            GUI.LfgEnrollments = {}
            if AIP.ChatScanner then AIP.ChatScanner.Players = {} end
            AIP.Print("LFG entries cleared")
        elseif tab == "waitlist" then
            if AIP.db then AIP.db.waitlist = {} end
            AIP.Print("Waitlist cleared")
        end
        GUI.UpdateQueuePanel(container)
    end)
    clearQueueBtn:SetScript("OnEnter", function(self)
        local tab = container.queueSubTab
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if tab == "queue" then
            GameTooltip:AddLine("Clear Queue")
            GameTooltip:AddLine("Remove all entries from invite queue", 1, 1, 1, true)
        elseif tab == "lfg" then
            GameTooltip:AddLine("Clear LFG")
            GameTooltip:AddLine("Remove all LFG player entries", 1, 1, 1, true)
        elseif tab == "waitlist" then
            GameTooltip:AddLine("Clear Waitlist")
            GameTooltip:AddLine("Remove all entries from waitlist", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Clear")
        end
        GameTooltip:Show()
    end)
    clearQueueBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.clearQueueBtn = clearQueueBtn

    -- Refresh button for LFG tab (to ping for nearby addon users)
    local refreshLfgBtn = CreateFrame("Button", nil, queuePanel, "UIPanelButtonTemplate")
    refreshLfgBtn:SetSize(60, 20)
    refreshLfgBtn:SetPoint("RIGHT", clearQueueBtn, "LEFT", -5, 0)
    refreshLfgBtn:SetText("Refresh")
    refreshLfgBtn:Hide()  -- Hidden by default, shown when LFG tab active
    refreshLfgBtn:SetScript("OnClick", function()
        -- Trigger DataBus ping to discover nearby addon users
        if AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast then
            local ping = AIP.DataBus.CreateEvent("PING", {version = AIP.Version})
            AIP.DataBus.Broadcast(ping)
            AIP.Print("Scanning for addon users...")
        end
        GUI.UpdateQueuePanel(container)
    end)
    refreshLfgBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Refresh LFG")
        GameTooltip:AddLine("Ping network to discover LFG players from addon users", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    refreshLfgBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.refreshLfgBtn = refreshLfgBtn

    -- Waitlist is now a tab, so button removed
end

-- Create inspection panel content
function GUI.CreateInspectionPanel(panel)
    -- Player header
    local headerFrame = CreateFrame("Frame", nil, panel)
    headerFrame:SetHeight(70)
    headerFrame:SetPoint("TOPLEFT", 10, -10)
    headerFrame:SetPoint("TOPRIGHT", -10, -10)

    -- Class icon placeholder
    local classIcon = headerFrame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(50, 50)
    classIcon:SetPoint("TOPLEFT")
    classIcon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
    panel.classIcon = classIcon

    -- Player name
    local playerName = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    playerName:SetPoint("TOPLEFT", classIcon, "TOPRIGHT", 10, -5)
    playerName:SetText("Select a player")
    panel.playerName = playerName

    -- Class and spec
    local classSpec = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classSpec:SetPoint("TOPLEFT", playerName, "BOTTOMLEFT", 0, -3)
    classSpec:SetTextColor(0.7, 0.7, 0.7)
    panel.classSpec = classSpec

    -- GearScore
    local gsText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    gsText:SetPoint("TOPLEFT", classSpec, "BOTTOMLEFT", 0, -3)
    panel.gsText = gsText

    -- Role icon
    local roleIcon = headerFrame:CreateTexture(nil, "ARTWORK")
    roleIcon:SetSize(24, 24)
    roleIcon:SetPoint("TOPRIGHT", -10, -10)
    panel.roleIcon = roleIcon

    -- Status badges
    local badgeFrame = CreateFrame("Frame", nil, headerFrame)
    badgeFrame:SetSize(200, 20)
    badgeFrame:SetPoint("TOPRIGHT", -10, -40)
    panel.badgeFrame = badgeFrame

    -- Divider
    local divider1 = panel:CreateTexture(nil, "ARTWORK")
    divider1:SetHeight(1)
    divider1:SetPoint("TOPLEFT", 10, -80)
    divider1:SetPoint("TOPRIGHT", -10, -80)
    divider1:SetTexture(0.3, 0.3, 0.3, 1)

    -- Equipment Analysis section
    local equipHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    equipHeader:SetPoint("TOPLEFT", 10, -90)
    equipHeader:SetText("=== Equipment Analysis ===")
    equipHeader:SetTextColor(1, 0.82, 0)

    local enchantText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enchantText:SetPoint("TOPLEFT", equipHeader, "BOTTOMLEFT", 0, -8)
    panel.enchantText = enchantText

    local enchantList = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    enchantList:SetPoint("TOPLEFT", enchantText, "BOTTOMLEFT", 10, -3)
    enchantList:SetTextColor(0.7, 0.7, 0.7)
    panel.enchantList = enchantList

    local gemText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gemText:SetPoint("TOPLEFT", enchantList, "BOTTOMLEFT", -10, -8)
    panel.gemText = gemText

    -- Divider
    local divider2 = panel:CreateTexture(nil, "ARTWORK")
    divider2:SetHeight(1)
    divider2:SetPoint("TOPLEFT", 10, -190)
    divider2:SetPoint("TOPRIGHT", -10, -190)
    divider2:SetTexture(0.3, 0.3, 0.3, 1)

    -- Achievements section
    local achieveHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    achieveHeader:SetPoint("TOPLEFT", 10, -200)
    achieveHeader:SetText("=== Raid Achievements ===")
    achieveHeader:SetTextColor(1, 0.82, 0)

    local achieveText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achieveText:SetPoint("TOPLEFT", achieveHeader, "BOTTOMLEFT", 0, -8)
    achieveText:SetWidth(350)
    achieveText:SetJustifyH("LEFT")
    panel.achieveText = achieveText

    -- Divider
    local divider3 = panel:CreateTexture(nil, "ARTWORK")
    divider3:SetHeight(1)
    divider3:SetPoint("TOPLEFT", 10, -290)
    divider3:SetPoint("TOPRIGHT", -10, -290)
    divider3:SetTexture(0.3, 0.3, 0.3, 1)

    -- Performance estimate section
    local perfHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    perfHeader:SetPoint("TOPLEFT", 10, -300)
    perfHeader:SetText("=== Performance Estimate ===")
    perfHeader:SetTextColor(1, 0.82, 0)

    local perfText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    perfText:SetPoint("TOPLEFT", perfHeader, "BOTTOMLEFT", 0, -8)
    perfText:SetWidth(350)
    perfText:SetJustifyH("LEFT")
    panel.perfText = perfText

    -- Message (original LFM/LFG message)
    local msgHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    msgHeader:SetPoint("BOTTOMLEFT", 10, 60)
    msgHeader:SetText("Message:")
    msgHeader:SetTextColor(1, 0.82, 0)

    local msgText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    msgText:SetPoint("TOPLEFT", msgHeader, "BOTTOMLEFT", 0, -5)
    msgText:SetPoint("BOTTOMRIGHT", -10, 10)
    msgText:SetJustifyH("LEFT")
    msgText:SetJustifyV("TOP")
    msgText:SetTextColor(0.7, 0.7, 0.7)
    panel.msgText = msgText
end

-- Create composition tab (RaidComp-style layout)
function GUI.CreateCompositionTab(container)
    local header = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 10, -10)
    header:SetText("Raid Composition Advisor")
    header:SetTextColor(1, 0.82, 0)

    -- Template category dropdown
    local catLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    catLabel:SetPoint("TOPLEFT", 10, -38)
    catLabel:SetText("Category:")

    local catDropdown = CreateFrame("Frame", "AIPCompCategory", container, "UIDropDownMenuTemplate")
    catDropdown:SetPoint("LEFT", catLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(catDropdown, 100)
    UIDropDownMenu_SetText(catDropdown, "WotLK")
    container.selectedCategory = "WOTLK"

    -- Template selector
    local templateLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    templateLabel:SetPoint("LEFT", catDropdown, "RIGHT", 10, 2)
    templateLabel:SetText("Template:")

    local templateDropdown = CreateFrame("Frame", "AIPCompTemplate", container, "UIDropDownMenuTemplate")
    templateDropdown:SetPoint("LEFT", templateLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(templateDropdown, 150)
    container.templateDropdown = templateDropdown

    local scanBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    scanBtn:SetSize(90, 22)
    scanBtn:SetPoint("LEFT", templateDropdown, "RIGHT", 10, 2)
    scanBtn:SetText("Scan Raid")
    scanBtn:SetScript("OnClick", function()
        if AIP.Composition then
            AIP.Composition.ScanRaid()
            GUI.UpdateCompositionTab()
        end
    end)

    local autoScanCheck = CreateFrame("CheckButton", nil, container, "UICheckButtonTemplate")
    autoScanCheck:SetSize(22, 22)
    autoScanCheck:SetPoint("LEFT", scanBtn, "RIGHT", 5, 0)
    autoScanCheck:SetChecked(true)
    local autoScanLabel = container:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    autoScanLabel:SetPoint("LEFT", autoScanCheck, "RIGHT", 0, 0)
    autoScanLabel:SetText("Auto")

    -- Helper to update template dropdown when category changes
    local function UpdateTemplateDropdown()
        UIDropDownMenu_Initialize(templateDropdown, function()
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Select Template"
            info.isTitle = true
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)

            if AIP.Composition and AIP.Composition.RaidTemplates then
                for key, data in pairs(AIP.Composition.RaidTemplates) do
                    if data.category == container.selectedCategory then
                        info = UIDropDownMenu_CreateInfo()
                        info.text = data.name
                        info.value = key
                        info.func = function()
                            UIDropDownMenu_SetText(templateDropdown, data.name)
                            if AIP.Composition then
                                AIP.Composition.SetTemplate(key)
                                GUI.UpdateCompositionTab()
                            end
                        end
                        info.notCheckable = true
                        UIDropDownMenu_AddButton(info)
                    end
                end
            end
        end)
    end

    -- Initialize category dropdown
    UIDropDownMenu_Initialize(catDropdown, function()
        local categories = {
            {id = "WOTLK", name = "WotLK Raids"},
            {id = "WOTLK_DUNGEON", name = "WotLK Dungeons"},
            {id = "TBC", name = "TBC Raids"},
            {id = "CLASSIC", name = "Classic Raids"},
            {id = "WEEKLY", name = "Weekly/Daily"},
        }
        for _, cat in ipairs(categories) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = cat.name
            info.value = cat.id
            info.func = function()
                container.selectedCategory = cat.id
                UIDropDownMenu_SetText(catDropdown, cat.name)
                UpdateTemplateDropdown()
            end
            info.notCheckable = true
            UIDropDownMenu_AddButton(info)
        end
    end)
    GUI.FixDropdownStrata(catDropdown)
    GUI.FixDropdownStrata(templateDropdown)

    UpdateTemplateDropdown()

    -- ========================================================================
    -- LEFT PANEL: Role Composition Bars (30% width)
    -- ========================================================================
    local leftPanel = CreateFrame("Frame", nil, container)
    leftPanel:SetPoint("TOPLEFT", 10, -70)
    leftPanel:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (30% of container)
    local function UpdateLeftPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            leftPanel:SetWidth(math.floor(containerWidth * 0.30) - 10)
        else
            leftPanel:SetWidth(250)  -- Fallback
        end
    end
    UpdateLeftPanelWidth()
    container:SetScript("OnSizeChanged", function(self, width, height)
        UpdateLeftPanelWidth()
        -- Also update other panels
        if container.UpdatePanelWidths then
            container.UpdatePanelWidths()
        end
    end)
    GUI.ApplyBackdrop(leftPanel, "SubPanel", 0.9)
    container.leftPanel = leftPanel

    local leftTitle = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    leftTitle:SetPoint("TOPLEFT", 8, -6)
    leftTitle:SetText("Composition Status")
    leftTitle:SetTextColor(1, 0.82, 0)

    -- Template name display (inline with title)
    local templateDisplay = leftPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    templateDisplay:SetPoint("LEFT", leftTitle, "RIGHT", 8, 0)
    templateDisplay:SetText("- No template")
    templateDisplay:SetTextColor(0.6, 0.6, 0.6)
    container.templateDisplay = templateDisplay

    -- Role bars - more compact layout
    local roleBarY = -26
    container.roleBars = {}

    local function CreateRoleBar(role, color, yOffset)
        local bar = CreateFrame("Frame", nil, leftPanel)
        bar:SetSize(300, 22)  -- Increased from 272
        bar:SetPoint("TOPLEFT", 8, yOffset)

        local label = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 0, 0)
        label:SetText(role)
        label:SetWidth(50)
        label:SetTextColor(color.r, color.g, color.b)

        local bgBar = bar:CreateTexture(nil, "BACKGROUND")
        bgBar:SetSize(160, 14)
        bgBar:SetPoint("LEFT", 52, 0)
        bgBar:SetTexture(0.15, 0.15, 0.15, 1)

        local fillBar = bar:CreateTexture(nil, "ARTWORK")
        fillBar:SetSize(0, 14)
        fillBar:SetPoint("LEFT", bgBar, "LEFT", 0, 0)
        fillBar:SetTexture(color.r, color.g, color.b, 0.8)
        bar.fillBar = fillBar
        bar.bgBar = bgBar

        local countText = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", bgBar, "RIGHT", 6, 0)
        countText:SetText("0/0")
        bar.countText = countText

        return bar
    end

    container.roleBars.TANK = CreateRoleBar("Tanks", {r=0.4, g=0.6, b=1}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.HEALER = CreateRoleBar("Healers", {r=0.4, g=1, b=0.4}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.DPS = CreateRoleBar("DPS", {r=1, g=0.4, b=0.4}, roleBarY)
    roleBarY = roleBarY - 24
    container.roleBars.TOTAL = CreateRoleBar("Total", {r=0.8, g=0.8, b=0.8}, roleBarY)
    roleBarY = roleBarY - 30

    -- ========================================================================
    -- BUFF/DEBUFF SECTION (Tabbed with categories) - Compact Layout
    -- ========================================================================

    -- Buff section container with border for visual separation
    local buffSection = CreateFrame("Frame", nil, leftPanel)
    buffSection:SetPoint("TOPLEFT", 4, roleBarY)
    buffSection:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(buffSection, "SubPanel", 0.6)
    container.buffSection = buffSection

    local buffSectionLabel = buffSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    buffSectionLabel:SetPoint("TOPLEFT", 6, -4)
    buffSectionLabel:SetText("Raid Buffs & Debuffs")
    buffSectionLabel:SetTextColor(1, 0.82, 0)

    -- Buff category tabs - horizontal row below title (8 tabs)
    local buffTabFrame = CreateFrame("Frame", nil, buffSection)
    buffTabFrame:SetSize(304, 18)  -- Increased from 270 to fit 8 tabs
    buffTabFrame:SetPoint("TOPLEFT", 4, -20)
    container.buffTabFrame = buffTabFrame

    -- Use categories from RaidComposition.lua (full 8 tabs)
    local buffCategories = {"CRITICAL", "STATS", "ATTACK", "SPELLPOWER", "HASTE", "CRIT", "DEBUFFS", "UTILITY"}
    local buffCategoryNames = {
        CRITICAL = "Crit",
        STATS = "Stats",
        ATTACK = "AP",
        SPELLPOWER = "SP",
        HASTE = "Haste",
        CRIT = "Crit%",
        HEALING = "Heal",
        DEBUFFS = "Debuff",
        UTILITY = "Util",
    }
    local buffCategoryColors = {
        CRITICAL = {r=1, g=0.4, b=0.4},
        STATS = {r=0.4, g=0.8, b=1},
        ATTACK = {r=1, g=0.6, b=0.2},
        SPELLPOWER = {r=0.8, g=0.4, b=1},
        HASTE = {r=0.2, g=0.8, b=0.6},
        CRIT = {r=1, g=0.8, b=0.2},
        HEALING = {r=0.4, g=1, b=0.4},
        DEBUFFS = {r=0.9, g=0.3, b=0.9},
        UTILITY = {r=0.7, g=0.7, b=0.7},
    }
    container.buffCategoryTabs = {}
    container.selectedBuffCategory = "CRITICAL"

    local tabX = 0
    local tabWidth = 35  -- Reduced to fit 8 tabs
    for _, catId in ipairs(buffCategories) do
        local tabBtn = CreateFrame("Button", nil, buffTabFrame)
        tabBtn:SetSize(tabWidth, 18)
        tabBtn:SetPoint("LEFT", tabX, 0)

        local tabBg = tabBtn:CreateTexture(nil, "BACKGROUND")
        tabBg:SetAllPoints()
        tabBg:SetTexture(0.12, 0.12, 0.12, 1)
        tabBtn.bg = tabBg

        -- Color indicator line at bottom of tab
        local colorLine = tabBtn:CreateTexture(nil, "ARTWORK")
        colorLine:SetSize(tabWidth - 4, 2)
        colorLine:SetPoint("BOTTOM", 0, 1)
        local catColor = buffCategoryColors[catId]
        colorLine:SetTexture(catColor.r, catColor.g, catColor.b, 0.8)
        tabBtn.colorLine = colorLine

        local tabText = tabBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER", 0, 1)
        tabText:SetText(buffCategoryNames[catId])
        tabBtn.text = tabText

        tabBtn:SetScript("OnClick", function()
            container.selectedBuffCategory = catId
            GUI.UpdateCompositionBuffDisplay(container)
            -- Update tab appearance
            for cid, btn in pairs(container.buffCategoryTabs) do
                local color = buffCategoryColors[cid]
                if cid == catId then
                    btn.bg:SetTexture(0.2, 0.2, 0.25, 1)
                    btn.text:SetTextColor(1, 0.82, 0)
                    btn.colorLine:SetTexture(color.r, color.g, color.b, 1)
                else
                    btn.bg:SetTexture(0.12, 0.12, 0.12, 1)
                    btn.text:SetTextColor(0.6, 0.6, 0.6)
                    btn.colorLine:SetTexture(color.r, color.g, color.b, 0.4)
                end
            end
        end)

        tabBtn:SetScript("OnEnter", function(self)
            if catId ~= container.selectedBuffCategory then
                self.bg:SetTexture(0.18, 0.18, 0.2, 1)
            end
        end)
        tabBtn:SetScript("OnLeave", function(self)
            if catId ~= container.selectedBuffCategory then
                self.bg:SetTexture(0.12, 0.12, 0.12, 1)
            end
        end)

        container.buffCategoryTabs[catId] = tabBtn
        tabX = tabX + tabWidth + 2
    end

    -- Set initial selected tab
    container.buffCategoryTabs["CRITICAL"].bg:SetTexture(0.2, 0.2, 0.25, 1)
    container.buffCategoryTabs["CRITICAL"].text:SetTextColor(1, 0.82, 0)

    -- Buff display frame (shows buffs for selected category) - inside the buff section
    local buffFrame = CreateFrame("Frame", nil, buffSection)
    buffFrame:SetPoint("TOPLEFT", 4, -40)
    buffFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(buffFrame, "Inset", 0.4)
    container.buffFrame = buffFrame

    -- Create buff display rows (icon + status + name + provider count)
    container.buffRows = {}
    local NUM_BUFF_ROWS = 10
    local BUFF_ROW_HEIGHT = 16
    for i = 1, NUM_BUFF_ROWS do
        local row = CreateFrame("Frame", nil, buffFrame)
        row:SetSize(296, BUFF_ROW_HEIGHT)  -- Increased from 268
        row:SetPoint("TOPLEFT", 2, -1 - (i-1) * BUFF_ROW_HEIGHT)

        -- Alternating row background
        local rowBg = row:CreateTexture(nil, "BACKGROUND")
        rowBg:SetAllPoints()
        if i % 2 == 0 then
            rowBg:SetTexture(0.08, 0.08, 0.08, 0.5)
        else
            rowBg:SetTexture(0.12, 0.12, 0.12, 0.3)
        end
        row.bg = rowBg

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", 2, 0)
        row.icon = icon

        local statusIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statusIcon:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        statusIcon:SetWidth(14)
        row.statusIcon = statusIcon

        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameText:SetPoint("LEFT", statusIcon, "RIGHT", 2, 0)
        nameText:SetWidth(190)  -- Increased from 165
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        local providerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        providerText:SetPoint("RIGHT", -4, 0)
        providerText:SetWidth(45)
        providerText:SetJustifyH("RIGHT")
        providerText:SetTextColor(0.5, 0.5, 0.5)
        row.providerText = providerText

        -- Hover highlight and tooltip
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self.bg:SetTexture(0.25, 0.25, 0.3, 0.6)
            if self.buffData then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.buffData.name, 1, 0.82, 0)
                if self.buffData.info.description then
                    GameTooltip:AddLine(self.buffData.info.description, 1, 1, 1, true)
                end
                if self.buffData.info.classes and #self.buffData.info.classes > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Provided by:", 0.7, 0.7, 0.7)
                    GameTooltip:AddLine("  " .. table.concat(self.buffData.info.classes, ", "), 0.6, 0.6, 0.6)
                end
                -- Show required specs if this buff is spec-specific
                if self.buffData.info.specs and #self.buffData.info.specs > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Requires spec:", 1, 0.5, 0.5)
                    GameTooltip:AddLine("  " .. table.concat(self.buffData.info.specs, ", "), 0.8, 0.6, 0.6)
                end
                if self.buffData.info.alternatesWith then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Alternates with:", 0.7, 0.7, 0.7)
                    for _, alt in ipairs(self.buffData.info.alternatesWith) do
                        GameTooltip:AddLine("  " .. alt, 0.5, 0.7, 0.5)
                    end
                end
                -- Show confirmed providers with spec info
                if self.buffData.providerDetails and #self.buffData.providerDetails > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("In raid (confirmed):", 0.4, 1, 0.4)
                    for _, prov in ipairs(self.buffData.providerDetails) do
                        local specStr = prov.spec and (" (" .. prov.spec .. ")") or ""
                        GameTooltip:AddLine("  " .. prov.name .. specStr, 0.4, 0.8, 0.4)
                    end
                elseif #self.buffData.providers > 0 then
                    -- Fallback to simple provider list
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("In raid (" .. #self.buffData.providers .. "):", 0.4, 1, 0.4)
                    for _, name in ipairs(self.buffData.providers) do
                        GameTooltip:AddLine("  " .. name, 0.4, 0.8, 0.4)
                    end
                end
                -- Show potential providers (class match but spec unknown/wrong)
                if self.buffData.potentialProviders and #self.buffData.potentialProviders > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("Potential providers:", 1, 0.8, 0.4)
                    for _, pot in ipairs(self.buffData.potentialProviders) do
                        local reason = ""
                        if pot.reason == "wrong_spec" then
                            reason = " (wrong spec: " .. (pot.spec or "?") .. ")"
                        elseif pot.reason == "spec_unknown" then
                            reason = " (spec unknown)"
                        end
                        GameTooltip:AddLine("  " .. pot.name .. reason, 0.8, 0.6, 0.4)
                    end
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if i % 2 == 0 then
                self.bg:SetTexture(0.08, 0.08, 0.08, 0.5)
            else
                self.bg:SetTexture(0.12, 0.12, 0.12, 0.3)
            end
            GameTooltip:Hide()
        end)

        container.buffRows[i] = row
        row:Hide()
    end

    -- ========================================================================
    -- MIDDLE PANEL: Classes + Raid Groups (50% width)
    -- ========================================================================
    local classPanel = CreateFrame("Frame", nil, container)
    classPanel:SetPoint("TOPLEFT", leftPanel, "TOPRIGHT", 8, 0)
    classPanel:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (50% of container)
    local function UpdateClassPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            classPanel:SetWidth(math.floor(containerWidth * 0.50) - 10)
        else
            classPanel:SetWidth(370)  -- Fallback
        end
    end
    UpdateClassPanelWidth()
    GUI.ApplyBackdrop(classPanel, "SubPanel", 0.9)
    container.classPanel = classPanel

    local classTitle = classPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classTitle:SetPoint("TOPLEFT", 6, -4)
    classTitle:SetText("Classes")
    classTitle:SetTextColor(1, 0.82, 0)

    -- Class icons with counts (single row across top)
    container.classDisplays = {}
    local classOrder = {"WARRIOR", "PALADIN", "DEATHKNIGHT", "DRUID", "PRIEST",
                        "SHAMAN", "MAGE", "WARLOCK", "HUNTER", "ROGUE"}
    local classIcons = {
        WARRIOR = "Interface\\Icons\\ClassIcon_Warrior",
        PALADIN = "Interface\\Icons\\ClassIcon_Paladin",
        DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
        DRUID = "Interface\\Icons\\ClassIcon_Druid",
        PRIEST = "Interface\\Icons\\ClassIcon_Priest",
        SHAMAN = "Interface\\Icons\\ClassIcon_Shaman",
        MAGE = "Interface\\Icons\\ClassIcon_Mage",
        WARLOCK = "Interface\\Icons\\ClassIcon_Warlock",
        HUNTER = "Interface\\Icons\\ClassIcon_Hunter",
        ROGUE = "Interface\\Icons\\ClassIcon_Rogue",
    }

    local classX = 6
    for i, class in ipairs(classOrder) do
        local classFrame = CreateFrame("Frame", nil, classPanel)
        classFrame:SetSize(34, 14)
        classFrame:SetPoint("TOPLEFT", classX, -18)

        local icon = classFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("LEFT", 0, 0)
        icon:SetTexture(classIcons[class] or "Interface\\Icons\\INV_Misc_QuestionMark")

        local classColor = AIP.Composition and AIP.Composition.ClassColors[class] or {r=1, g=1, b=1}

        local countText = classFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        countText:SetPoint("LEFT", icon, "RIGHT", 1, 0)
        countText:SetText("0")
        countText:SetTextColor(classColor.r, classColor.g, classColor.b)

        classFrame:EnableMouse(true)
        classFrame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(class:sub(1,1) .. class:sub(2):lower():gsub("knight", " Knight"), classColor.r, classColor.g, classColor.b)
            GameTooltip:Show()
        end)
        classFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)

        container.classDisplays[class] = {count = countText, icon = icon, frame = classFrame}
        classX = classX + 36
    end

    -- RAID GROUPS (Blizzard style: 8 groups of 5 members, arranged in 2 rows of 4)
    local groupsLabel = classPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupsLabel:SetPoint("TOPLEFT", 6, -36)
    groupsLabel:SetText("Raid Groups")
    groupsLabel:SetTextColor(1, 0.82, 0)

    local groupsFrame = CreateFrame("Frame", nil, classPanel)
    groupsFrame:SetPoint("TOPLEFT", 4, -50)
    groupsFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(groupsFrame, "Inset", 0.5)
    container.groupsFrame = groupsFrame

    -- Create 8 group frames (2 rows x 4 columns)
    container.raidGroups = {}
    local GROUP_WIDTH = 88
    local GROUP_HEIGHT = 90
    local MEMBER_HEIGHT = 24  -- Increased for 2-row display (name + spec)

    -- Dynamic resizing function for group frames
    local function RecalculateGroupLayouts()
        local frameWidth = groupsFrame:GetWidth()
        local frameHeight = groupsFrame:GetHeight()
        if not frameWidth or frameWidth < 50 or not frameHeight or frameHeight < 50 then return end

        -- Calculate dynamic sizes (4 columns, 2 rows)
        local padding = 4
        local hGap = 4
        local vGap = 6
        local dynWidth = math.floor((frameWidth - padding * 2 - hGap * 3) / 4)
        local dynHeight = math.floor((frameHeight - padding * 2 - vGap) / 2)
        local dynMemberHeight = math.floor((dynHeight - 14) / 5)  -- 14px for header

        for g = 1, 8 do
            local gf = container.raidGroups[g]
            if gf then
                local col = (g - 1) % 4
                local row = math.floor((g - 1) / 4)

                gf:ClearAllPoints()
                gf:SetSize(dynWidth, dynHeight)
                gf:SetPoint("TOPLEFT", padding + col * (dynWidth + hGap), -padding - row * (dynHeight + vGap))

                -- Resize member slots
                for m = 1, 5 do
                    local slot = gf.slots[m]
                    if slot then
                        slot:SetSize(dynWidth - 4, dynMemberHeight)
                        slot:ClearAllPoints()
                        slot:SetPoint("TOPLEFT", 2, -14 - (m - 1) * dynMemberHeight)
                        if slot.nameText then
                            slot.nameText:SetWidth(dynWidth - 8)
                        end
                        if slot.specText then
                            slot.specText:SetWidth(dynWidth - 8)
                        end
                    end
                end
            end
        end
    end
    container.RecalculateGroupLayouts = RecalculateGroupLayouts

    -- Register resize handler
    groupsFrame:SetScript("OnSizeChanged", RecalculateGroupLayouts)

    for g = 1, 8 do
        local col = (g - 1) % 4
        local row = math.floor((g - 1) / 4)

        local groupFrame = CreateFrame("Frame", nil, groupsFrame)
        groupFrame:SetSize(GROUP_WIDTH, GROUP_HEIGHT)
        groupFrame:SetPoint("TOPLEFT", 2 + col * (GROUP_WIDTH + 2), -2 - row * (GROUP_HEIGHT + 4))

        -- Group header
        local groupBg = groupFrame:CreateTexture(nil, "BACKGROUND")
        groupBg:SetAllPoints()
        groupBg:SetTexture(0.1, 0.1, 0.15, 0.8)
        groupFrame.bg = groupBg

        local groupHeader = groupFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        groupHeader:SetPoint("TOPLEFT", 2, -1)
        groupHeader:SetText("Group " .. g)
        groupHeader:SetTextColor(0.8, 0.8, 0.4)
        groupFrame.header = groupHeader

        -- 5 member slots per group
        groupFrame.slots = {}
        for m = 1, 5 do
            local slot = CreateFrame("Button", nil, groupFrame)
            slot:SetSize(GROUP_WIDTH - 4, MEMBER_HEIGHT)
            slot:SetPoint("TOPLEFT", 2, -12 - (m - 1) * MEMBER_HEIGHT)
            slot.groupNum = g
            slot.slotNum = m

            local slotBg = slot:CreateTexture(nil, "BACKGROUND")
            slotBg:SetAllPoints()
            slotBg:SetTexture(0.15, 0.15, 0.15, 0.5)
            slot.bg = slotBg

            -- Row 1: Name with role indicator
            local nameText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            nameText:SetPoint("TOPLEFT", 2, -1)
            nameText:SetWidth(GROUP_WIDTH - 8)
            nameText:SetHeight(11)
            nameText:SetJustifyH("LEFT")
            nameText:SetText("")
            slot.nameText = nameText

            -- Row 2: Spec info (smaller font)
            local specText = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            specText:SetPoint("TOPLEFT", 2, -12)
            specText:SetWidth(GROUP_WIDTH - 8)
            specText:SetHeight(10)
            specText:SetJustifyH("LEFT")
            specText:SetFont("Fonts\\FRIZQT__.TTF", 8)
            specText:SetTextColor(0.6, 0.6, 0.6)
            specText:SetText("")
            slot.specText = specText

            -- Drag highlight overlay
            local dragHighlight = slot:CreateTexture(nil, "OVERLAY")
            dragHighlight:SetAllPoints()
            dragHighlight:SetTexture(0.3, 0.6, 1, 0.4)
            dragHighlight:Hide()
            slot.dragHighlight = dragHighlight

            -- Enable drag-and-drop for member movement
            slot:RegisterForDrag("LeftButton")
            slot:SetMovable(false)

            slot:SetScript("OnDragStart", function(self)
                if self.memberData and self.memberData.raidIndex then
                    -- Store drag source info
                    container.dragSource = self
                    container.dragSourceIndex = self.memberData.raidIndex
                    container.dragSourceGroup = self.groupNum
                    -- Visual feedback
                    self.bg:SetTexture(0.5, 0.3, 0.1, 0.8)
                    -- Show drag cursor
                    SetCursor("Interface\\CURSOR\\UI-Cursor-Move")
                end
            end)

            slot:SetScript("OnDragStop", function(self)
                -- Reset visual
                self.bg:SetTexture(0.15, 0.15, 0.15, 0.5)
                ResetCursor()

                -- Find what slot the cursor is over
                local targetSlot = nil
                local targetGroup = nil

                if container.dragSourceIndex then
                    -- Check all slots to find which one the cursor is over
                    for gNum = 1, 8 do
                        local gf = container.raidGroups[gNum]
                        if gf and gf.slots then
                            for sNum = 1, 5 do
                                local s = gf.slots[sNum]
                                if s and s:IsMouseOver() then
                                    targetSlot = s
                                    targetGroup = gNum
                                    break
                                end
                            end
                        end
                        if targetSlot then break end
                    end

                    -- Perform the move if we found a valid target
                    if targetGroup and targetGroup ~= container.dragSourceGroup then
                        local sourceIndex = container.dragSourceIndex
                        if IsRaidLeader() or IsRaidOfficer() then
                            SetRaidSubgroup(sourceIndex, targetGroup)
                            -- Refresh after delay
                            AIP.Utils.DelayedCall(0.3, function()
                                if AIP.Composition then
                                    AIP.Composition.ScanRaid()
                                end
                                GUI.UpdateCompositionTab()
                            end)
                        else
                            AIP.Print("You must be raid leader or assistant to move players.")
                        end
                    end
                end

                -- Clear drag state
                container.dragSource = nil
                container.dragSourceIndex = nil
                container.dragSourceGroup = nil

                -- Hide all drop highlights
                for gNum = 1, 8 do
                    if container.raidGroups[gNum] then
                        for sNum = 1, 5 do
                            local s = container.raidGroups[gNum].slots[sNum]
                            if s and s.dragHighlight then
                                s.dragHighlight:Hide()
                            end
                        end
                    end
                end
            end)

            -- Hover tooltip and drop target highlight
            slot:SetScript("OnEnter", function(self)
                -- Show drop highlight if dragging
                if container.dragSource and container.dragSource ~= self then
                    self.dragHighlight:Show()
                else
                    self.bg:SetTexture(0.3, 0.3, 0.4, 0.6)
                end
                -- Show tooltip
                if self.memberData then
                    local md = self.memberData
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    local classColor = AIP.Composition and AIP.Composition.ClassColors[md.class] or {r=1, g=1, b=1}
                    local colorCode = string.format("|cFF%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)
                    GameTooltip:AddLine(colorCode .. (md.name or "Unknown") .. "|r", 1, 1, 1)
                    GameTooltip:AddLine("Class: " .. colorCode .. (md.class or "Unknown") .. "|r", 0.7, 0.7, 0.7)
                    if md.spec then
                        GameTooltip:AddLine("Spec: |cFF00FF00" .. md.spec .. "|r", 0.7, 0.7, 0.7)
                    end
                    GameTooltip:AddLine("Role: " .. (md.role or "DPS"), 0.7, 0.7, 0.7)
                    if md.gs and md.gs > 0 then
                        GameTooltip:AddLine("GearScore: " .. md.gs, 0.7, 0.7, 0.7)
                    end
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine("|cFF888888Drag to move to another group|r", 0.5, 0.5, 0.5)
                    GameTooltip:Show()
                end
            end)
            slot:SetScript("OnLeave", function(self)
                self.bg:SetTexture(0.15, 0.15, 0.15, 0.5)
                self.dragHighlight:Hide()
                GameTooltip:Hide()
            end)

            groupFrame.slots[m] = slot
        end

        container.raidGroups[g] = groupFrame
    end

    -- Keep memberRows for compatibility with existing update functions
    container.memberRows = {}
    container.memberRowHeight = MEMBER_HEIGHT
    container.numMemberRows = 40  -- 8 groups x 5 members

    -- ========================================================================
    -- RIGHT PANEL: Raid Benefits Stats (20% width)
    -- ========================================================================
    local benefitsSection = CreateFrame("Frame", nil, container)
    benefitsSection:SetPoint("TOPLEFT", classPanel, "TOPRIGHT", 8, 0)
    benefitsSection:SetPoint("BOTTOM", 0, 10)
    -- Use percentage-based width (20% of container)
    local function UpdateBenefitsPanelWidth()
        local containerWidth = container:GetWidth()
        if containerWidth and containerWidth > 100 then
            benefitsSection:SetWidth(math.floor(containerWidth * 0.20) - 15)
        else
            benefitsSection:SetWidth(160)  -- Fallback
        end
    end
    UpdateBenefitsPanelWidth()
    GUI.ApplyBackdrop(benefitsSection, "SubPanel", 0.9)
    container.benefitsSection = benefitsSection

    -- Function to update all panel widths
    container.UpdatePanelWidths = function()
        UpdateLeftPanelWidth()
        UpdateClassPanelWidth()
        UpdateBenefitsPanelWidth()
        -- Trigger group layout recalculation
        if container.RecalculateGroupLayouts then
            container.RecalculateGroupLayouts()
        end
    end

    local benefitsTitle = benefitsSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    benefitsTitle:SetPoint("TOPLEFT", 6, -4)
    benefitsTitle:SetText("Raid Benefits")
    benefitsTitle:SetTextColor(1, 0.82, 0)

    -- Benefits scroll frame
    local benefitsFrame = CreateFrame("Frame", nil, benefitsSection)
    benefitsFrame:SetPoint("TOPLEFT", 4, -18)
    benefitsFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    GUI.ApplyBackdrop(benefitsFrame, "Inset", 0.4)
    container.benefitsFrame = benefitsFrame

    -- Create benefit stat rows
    container.benefitRows = {}
    local BENEFIT_CATEGORIES = {
        {id = "STATS", name = "Stats", color = {r=0.4, g=0.8, b=1}},
        {id = "ATTACK", name = "Attack", color = {r=1, g=0.6, b=0.2}},
        {id = "SPELL", name = "Spell", color = {r=0.8, g=0.4, b=1}},
        {id = "HASTE", name = "Haste", color = {r=0.2, g=0.8, b=0.6}},
        {id = "CRIT", name = "Crit", color = {r=1, g=0.8, b=0.2}},
        {id = "DEBUFF", name = "Debuffs", color = {r=0.9, g=0.3, b=0.9}},
        {id = "UTIL", name = "Utility", color = {r=0.7, g=0.7, b=0.7}},
    }
    container.benefitCategories = BENEFIT_CATEGORIES

    local benefitY = -4
    for _, cat in ipairs(BENEFIT_CATEGORIES) do
        -- Category header
        local catHeader = benefitsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        catHeader:SetPoint("TOPLEFT", 4, benefitY)
        catHeader:SetText(cat.name)
        catHeader:SetTextColor(cat.color.r, cat.color.g, cat.color.b)
        benefitY = benefitY - 12

        -- Stats container for this category
        local catFrame = CreateFrame("Frame", nil, benefitsFrame)
        catFrame:SetPoint("TOPLEFT", 4, benefitY)
        catFrame:SetPoint("RIGHT", -4, 0)
        catFrame:SetHeight(36)

        -- Create stat display rows (2 columns)
        catFrame.statRows = {}
        for j = 1, 4 do
            local col = (j - 1) % 2
            local rowNum = math.floor((j - 1) / 2)

            local statRow = CreateFrame("Frame", nil, catFrame)
            statRow:SetSize(80, 12)
            statRow:SetPoint("TOPLEFT", col * 82, -rowNum * 12)

            local statIcon = statRow:CreateTexture(nil, "ARTWORK")
            statIcon:SetSize(10, 10)
            statIcon:SetPoint("LEFT", 0, 0)
            statRow.icon = statIcon

            local statText = statRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            statText:SetPoint("LEFT", statIcon, "RIGHT", 2, 0)
            statText:SetWidth(66)
            statText:SetJustifyH("LEFT")
            statRow.text = statText

            -- Tooltip
            statRow:EnableMouse(true)
            statRow:SetScript("OnEnter", function(self)
                if self.tooltipText then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.tooltipTitle or "Buff", 1, 0.82, 0)
                    GameTooltip:AddLine(self.tooltipText, 1, 1, 1, true)
                    if self.tooltipProviders then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Provided by:", 0.5, 0.5, 0.5)
                        GameTooltip:AddLine(self.tooltipProviders, 0.4, 0.8, 0.4)
                    end
                    GameTooltip:Show()
                end
            end)
            statRow:SetScript("OnLeave", function() GameTooltip:Hide() end)

            catFrame.statRows[j] = statRow
            statRow:Hide()
        end

        container.benefitRows[cat.id] = catFrame
        benefitY = benefitY - 28
    end

    -- Summary section at bottom
    local summaryFrame = CreateFrame("Frame", nil, benefitsSection)
    summaryFrame:SetPoint("BOTTOMLEFT", 4, 4)
    summaryFrame:SetPoint("BOTTOMRIGHT", -4, 4)
    summaryFrame:SetHeight(40)
    GUI.ApplyBackdrop(summaryFrame, "Inset", 0.3)
    container.summaryFrame = summaryFrame

    local summaryTitle = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryTitle:SetPoint("TOPLEFT", 4, -2)
    summaryTitle:SetText("Coverage")
    summaryTitle:SetTextColor(1, 0.82, 0)

    local summaryText = summaryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summaryText:SetPoint("TOPLEFT", 4, -14)
    summaryText:SetPoint("BOTTOMRIGHT", -4, 2)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetJustifyV("TOP")
    summaryText:SetText("")
    container.summaryText = summaryText

    -- Composition frame reference for text update
    container.compFrame = leftPanel
    container.compText = templateDisplay
end

-- Calculate and display raid benefits based on available buffs
function GUI.UpdateRaidBenefits(container)
    if not container or not container.benefitRows then return end
    if not AIP.Composition then return end

    local raid = AIP.Composition.CurrentRaid
    local buffs = raid.buffsAvailable or {}
    local providers = raid.buffProviders or {}

    -- Define benefit mappings
    local benefits = {
        STATS = {
            {buff = "Blessing of Kings", short = "+10% Stats", icon = "Interface\\Icons\\Spell_Magic_GreaterBlessingofKings"},
            {buff = "Power Word: Fortitude", short = "+165 Stam", icon = "Interface\\Icons\\Spell_Holy_WordFortitude"},
            {buff = "Gift of the Wild", short = "+51 Stats", icon = "Interface\\Icons\\Spell_Nature_Regeneration"},
            {buff = "Arcane Intellect", short = "+60 Int", icon = "Interface\\Icons\\Spell_Holy_ArcaneIntellect"},
        },
        ATTACK = {
            {buff = "Trueshot Aura", alt = {"Abomination's Might", "Unleashed Rage"}, short = "+10% AP", icon = "Interface\\Icons\\Ability_TrueShot"},
            {buff = "Battle Shout", alt = {"Blessing of Might"}, short = "+550 AP", icon = "Interface\\Icons\\Ability_Warrior_BattleShout"},
            {buff = "Ferocious Inspiration", alt = {"Arcane Empowerment", "Sanctified Retribution"}, short = "+3% Dmg", icon = "Interface\\Icons\\Ability_Hunter_FerociousInspiration"},
            {buff = "Horn of Winter", alt = {"Strength of Earth Totem"}, short = "+155 Str/Agi", icon = "Interface\\Icons\\INV_Misc_Horn_02"},
        },
        SPELL = {
            {buff = "Totem of Wrath", alt = {"Flametongue Totem"}, short = "+280 SP", icon = "Interface\\Icons\\Spell_Fire_TotemOfWrath"},
            {buff = "Demonic Pact", short = "+10% SP", icon = "Interface\\Icons\\Spell_Shadow_DemonicPact"},
            {buff = "Focus Magic", short = "+3% Crit", icon = "Interface\\Icons\\Spell_Arcane_StudentOfMagic"},
            {buff = "Moonkin Aura", alt = {"Elemental Oath"}, short = "+5% Crit", icon = "Interface\\Icons\\Spell_Nature_MoonkinForm"},
        },
        HASTE = {
            {buff = "Bloodlust/Heroism", short = "+30% (CD)", icon = "Interface\\Icons\\Spell_Nature_Bloodlust"},
            {buff = "Windfury Totem", alt = {"Icy Talons"}, short = "+16-20% Melee", icon = "Interface\\Icons\\Spell_Nature_Windfury"},
            {buff = "Wrath of Air Totem", short = "+5% Spell", icon = "Interface\\Icons\\Spell_Nature_SlowingTotem"},
            {buff = "Swift Retribution", alt = {"Improved Moonkin Form"}, short = "+3% All", icon = "Interface\\Icons\\Ability_Paladin_SwiftRetribution"},
        },
        CRIT = {
            {buff = "Leader of the Pack", alt = {"Rampage"}, short = "+5% Melee", icon = "Interface\\Icons\\Spell_Nature_UnyeildingStamina"},
            {buff = "Moonkin Aura", alt = {"Elemental Oath"}, short = "+5% Spell", icon = "Interface\\Icons\\Spell_Nature_MoonkinForm"},
            {buff = "Improved Scorch", alt = {"Winter's Chill", "Shadow Mastery"}, short = "+5% Target", icon = "Interface\\Icons\\Spell_Fire_SoulBurn"},
            {buff = "Heart of the Crusader", alt = {"Master Poisoner"}, short = "+3% Target", icon = "Interface\\Icons\\Spell_Holy_HolySmite"},
        },
        DEBUFF = {
            {buff = "Sunder Armor", alt = {"Expose Armor", "Acid Spit"}, short = "-20% Armor", icon = "Interface\\Icons\\Ability_Warrior_Sunder"},
            {buff = "Curse of Elements", alt = {"Earth and Moon", "Ebon Plaguebringer"}, short = "+13% Magic", icon = "Interface\\Icons\\Spell_Shadow_ChillTouch"},
            {buff = "Blood Frenzy", alt = {"Savage Combat"}, short = "+4% Phys", icon = "Interface\\Icons\\Ability_Warrior_BloodFrenzy"},
            {buff = "Misery", alt = {"Improved Faerie Fire"}, short = "+3% Hit", icon = "Interface\\Icons\\Spell_Shadow_MiseryBuff"},
        },
        UTIL = {
            {buff = "Replenishment", short = "Mana Regen", icon = "Interface\\Icons\\Spell_Magic_ManaGain"},
            {buff = "Rebirth", short = "Combat Res", icon = "Interface\\Icons\\Spell_Nature_Reincarnation"},
            {buff = "Misdirection", alt = {"Tricks of the Trade"}, short = "Threat", icon = "Interface\\Icons\\Ability_Hunter_Misdirection"},
            {buff = "Blessing of Wisdom", alt = {"Mana Spring Totem"}, short = "+92 mp5", icon = "Interface\\Icons\\Spell_Holy_SealOfWisdom"},
        },
    }

    local totalBuffs = 0
    local availableBuffs = 0

    for catId, catFrame in pairs(container.benefitRows) do
        local catBenefits = benefits[catId] or {}
        for j, statRow in ipairs(catFrame.statRows) do
            local benefit = catBenefits[j]
            if benefit then
                local hasIt = buffs[benefit.buff]
                local provider = benefit.buff

                -- Check alternates
                if not hasIt and benefit.alt then
                    for _, altBuff in ipairs(benefit.alt) do
                        if buffs[altBuff] then
                            hasIt = true
                            provider = altBuff
                            break
                        end
                    end
                end

                statRow.icon:SetTexture(benefit.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                if hasIt then
                    statRow.text:SetText("|cFF00FF00" .. benefit.short .. "|r")
                    statRow.icon:SetDesaturated(false)
                    availableBuffs = availableBuffs + 1
                else
                    statRow.text:SetText("|cFF666666" .. benefit.short .. "|r")
                    statRow.icon:SetDesaturated(true)
                end

                statRow.tooltipTitle = provider
                statRow.tooltipText = AIP.Composition.RaidBuffs[provider] and AIP.Composition.RaidBuffs[provider].description or ""
                local provList = providers[provider]
                if provList and #provList > 0 then
                    local names = {}
                    for _, p in ipairs(provList) do
                        table.insert(names, type(p) == "table" and p.name or p)
                    end
                    statRow.tooltipProviders = table.concat(names, ", ")
                else
                    statRow.tooltipProviders = nil
                end

                statRow:Show()
                totalBuffs = totalBuffs + 1
            else
                statRow:Hide()
            end
        end
    end

    -- Update summary
    local coverage = totalBuffs > 0 and math.floor((availableBuffs / totalBuffs) * 100) or 0
    local coverageColor = coverage >= 80 and "|cFF00FF00" or (coverage >= 50 and "|cFFFFFF00" or "|cFFFF4444")
    container.summaryText:SetText(coverageColor .. coverage .. "%|r buffs active\n" ..
        availableBuffs .. "/" .. totalBuffs .. " raid benefits")
end

-- Update buff display for selected category
function GUI.UpdateCompositionBuffDisplay(container)
    if not container or not container.buffRows then return end
    if not AIP.Composition then return end

    local buffsByCategory = AIP.Composition.GetBuffsByCategory()
    local catData = buffsByCategory[container.selectedBuffCategory]

    -- Hide all rows first
    for i = 1, #container.buffRows do
        container.buffRows[i]:Hide()
    end

    if not catData or not catData.buffs then return end

    local rowIndex = 1
    for _, buffData in ipairs(catData.buffs) do
        if rowIndex > #container.buffRows then break end

        local row = container.buffRows[rowIndex]
        row.buffData = buffData

        -- Set icon
        row.icon:SetTexture(buffData.info.icon or "Interface\\Icons\\INV_Misc_QuestionMark")

        -- Set status icon based on availability
        -- Green = confirmed available
        -- Yellow = alternate available
        -- Orange = potential provider (class matches but spec unknown/wrong)
        -- Red = not available
        if buffData.available then
            row.statusIcon:SetText("|cFF00FF00✓|r")
        elseif buffData.hasAlternate then
            row.statusIcon:SetText("|cFFFFFF00~|r")  -- Has alternate available
        elseif buffData.hasPotential then
            row.statusIcon:SetText("|cFFFF8800?|r")  -- Has class but spec uncertain
        else
            row.statusIcon:SetText("|cFFFF0000✗|r")
        end

        -- Set name with importance highlight
        local nameColor = buffData.info.important and "|cFFFFD700" or "|cFFFFFFFF"
        -- Add spec indicator for spec-specific buffs
        local specIndicator = ""
        if buffData.requiresSpec then
            specIndicator = "|cFF888888*|r"  -- Asterisk for spec-specific buffs
        end
        row.nameText:SetText(nameColor .. buffData.name .. specIndicator .. "|r")

        -- Show provider count or potential/class hint
        if #buffData.providers > 0 then
            row.providerText:SetText("|cFF00FF00" .. #buffData.providers .. "x|r")
        elseif buffData.potentialProviders and #buffData.potentialProviders > 0 then
            -- Show potential count with orange color
            row.providerText:SetText("|cFFFF8800" .. #buffData.potentialProviders .. "?|r")
        else
            -- Show which classes can provide this
            local classHint = ""
            if buffData.info.classes and #buffData.info.classes > 0 then
                classHint = buffData.info.classes[1]:sub(1, 3)
            end
            row.providerText:SetText("|cFF666666" .. classHint .. "|r")
        end

        row:Show()
        rowIndex = rowIndex + 1
    end
end

-- Update raid groups display (Blizzard-style: 8 groups of 5 members)
function GUI.UpdateCompositionMemberTable(container)
    if not container then return end
    if not AIP.Composition then return end

    local raid = AIP.Composition.CurrentRaid
    local members = raid.members or {}

    -- Clear all group slots first
    if container.raidGroups then
        for g = 1, 8 do
            local groupFrame = container.raidGroups[g]
            if groupFrame and groupFrame.slots then
                for m = 1, 5 do
                    local slot = groupFrame.slots[m]
                    if slot then
                        slot.nameText:SetText("")
                        if slot.specText then
                            slot.specText:SetText("")
                        end
                        slot.memberData = nil
                        slot.bg:SetTexture(0.15, 0.15, 0.15, 0.3)
                    end
                end
            end
        end
    end

    -- Organize members by subgroup (GetRaidRosterInfo returns subgroup)
    local groups = {}
    for i = 1, 8 do groups[i] = {} end

    -- Get actual raid subgroups if in raid, otherwise distribute evenly
    if GetNumRaidMembers() > 0 then
        for i = 1, GetNumRaidMembers() do
            local name, rank, subgroup, level, class, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(i)
            if name and subgroup and subgroup >= 1 and subgroup <= 8 then
                -- Find matching member data
                local memberData = nil
                for _, m in ipairs(members) do
                    if m.name == name then
                        memberData = m
                        break
                    end
                end
                if memberData then
                    -- Include raid index for drag-and-drop
                    memberData.raidIndex = i
                    table.insert(groups[subgroup], memberData)
                else
                    -- Create basic member data with raid index
                    table.insert(groups[subgroup], {
                        name = name,
                        class = fileName or "UNKNOWN",
                        role = role or "DPS",
                        gs = 0,
                        raidIndex = i
                    })
                end
            end
        end
    else
        -- Not in raid - distribute members evenly into groups
        for i, member in ipairs(members) do
            local groupNum = math.ceil(i / 5)
            if groupNum > 8 then groupNum = 8 end
            table.insert(groups[groupNum], member)
        end
    end

    -- Populate group frames
    if container.raidGroups then
        for g = 1, 8 do
            local groupFrame = container.raidGroups[g]
            if groupFrame and groupFrame.slots then
                local groupMembers = groups[g] or {}
                local memberCount = #groupMembers

                -- Update group header with count
                if groupFrame.header then
                    if memberCount > 0 then
                        groupFrame.header:SetText("Group " .. g .. " (" .. memberCount .. ")")
                        groupFrame.header:SetTextColor(0.9, 0.9, 0.6)
                    else
                        groupFrame.header:SetText("Group " .. g)
                        groupFrame.header:SetTextColor(0.5, 0.5, 0.4)
                    end
                end

                -- Fill slots
                for m = 1, 5 do
                    local slot = groupFrame.slots[m]
                    if slot then
                        local member = groupMembers[m]
                        if member then
                            slot.memberData = member

                            local classColor = AIP.Composition and AIP.Composition.ClassColors[member.class] or {r=1, g=1, b=1}
                            local colorStr = string.format("|cFF%02x%02x%02x", classColor.r * 255, classColor.g * 255, classColor.b * 255)

                            -- Display name with role indicator
                            local displayName = member.name or "Unknown"
                            if #displayName > 8 then
                                displayName = displayName:sub(1, 7) .. "."
                            end

                            local roleChar = ""
                            if member.role == "TANK" then
                                roleChar = "|cFF4499FF[T]|r "
                            elseif member.role == "HEALER" then
                                roleChar = "|cFF44FF44[H]|r "
                            end

                            -- Row 1: Name with role indicator
                            slot.nameText:SetText(roleChar .. colorStr .. displayName .. "|r")

                            -- Row 2: Class - Spec (or just Class if no spec)
                            local className = member.class and (member.class:sub(1,1) .. member.class:sub(2):lower():gsub("knight", " Knight")) or ""
                            local specName = member.spec or ""
                            local specLine = className
                            if specName ~= "" then
                                specLine = className .. " - " .. specName
                            end
                            if slot.specText then
                                slot.specText:SetText(specLine)
                            end

                            slot.bg:SetTexture(0.2, 0.2, 0.25, 0.6)
                        else
                            slot.nameText:SetText("")
                            if slot.specText then
                                slot.specText:SetText("")
                            end
                            slot.memberData = nil
                            slot.bg:SetTexture(0.1, 0.1, 0.1, 0.3)
                        end
                    end
                end
            end
        end
    end
end

-- Update filter dropdown with detected raids from tree data
function GUI.UpdateFilterDropdownOptions(container, treeData)
    if not container or not container.filterDropdown then return end

    -- Skip if any dropdown is currently open (prevents closing while user has dropdown open)
    local dropdownList = _G["DropDownList1"]
    if dropdownList and dropdownList:IsShown() then
        return  -- Don't re-init while user has dropdown open
    end

    -- Collect detected raids from tree data
    container.detectedRaids = container.detectedRaids or {}
    local detectedRaids = {}
    detectedRaids["ALL"] = {id = "ALL", name = "All"}

    for _, catNode in ipairs(treeData or {}) do
        if catNode.data and catNode.data.id then
            detectedRaids[catNode.data.id] = {id = catNode.data.id, name = catNode.data.name or catNode.data.id}
        elseif catNode.id then
            -- Extract raid id from node id (e.g., "lfm_ICC" -> "ICC")
            local raidId = catNode.id:match("^lfm_(.+)$") or catNode.id:match("^lfg_(.+)$")
            if raidId and raidId ~= "other" then
                detectedRaids[raidId] = {id = raidId, name = raidId}
            end
        end
    end

    -- Store for dropdown initialization
    container.detectedRaids = detectedRaids

    -- Re-initialize dropdown with new options
    local filterDropdown = container.filterDropdown
    UIDropDownMenu_Initialize(filterDropdown, function()
        local info = UIDropDownMenu_CreateInfo()

        -- Always add "All" first
        info.text = "All"
        info.value = "ALL"
        info.func = function()
            container.raidFilter = "ALL"
            UIDropDownMenu_SetText(filterDropdown, "All")
            GUI.RefreshBrowserTab(container.tabType)
        end
        info.checked = (container.raidFilter == "ALL")
        UIDropDownMenu_AddButton(info)

        -- Add detected raids
        local sortedRaids = {}
        for id, data in pairs(detectedRaids) do
            if id ~= "ALL" then
                table.insert(sortedRaids, data)
            end
        end
        table.sort(sortedRaids, function(a, b) return (a.name or "") < (b.name or "") end)

        for _, raid in ipairs(sortedRaids) do
            info = UIDropDownMenu_CreateInfo()
            info.text = raid.name
            info.value = raid.id
            info.func = function()
                container.raidFilter = raid.id
                UIDropDownMenu_SetText(filterDropdown, raid.name)
                GUI.RefreshBrowserTab(container.tabType)
            end
            info.checked = (container.raidFilter == raid.id)
            UIDropDownMenu_AddButton(info)
        end
    end)
end

-- Filter tree data based on search and raid filter
local function FilterTreeData(treeData, searchFilter, raidFilter)
    if (not searchFilter or searchFilter == "") and (not raidFilter or raidFilter == "ALL") then
        return treeData
    end

    local filtered = {}
    for _, catNode in ipairs(treeData) do
        -- Check if category matches raid filter
        local catMatches = (not raidFilter or raidFilter == "ALL")
        if not catMatches and catNode.data and catNode.data.id then
            catMatches = catNode.data.id == raidFilter or
                         (catNode.id and catNode.id:find(raidFilter))
        end
        -- For "Other" category, always include if no specific raid filter
        if catNode.id and catNode.id:find("other") then
            catMatches = (raidFilter == "ALL")
        end

        if catMatches and catNode.children then
            local filteredChildren = {}
            for _, child in ipairs(catNode.children) do
                local childMatches = true

                -- Apply search filter to player/group name and message
                if searchFilter and searchFilter ~= "" then
                    local searchText = (child.text or ""):lower()
                    local msgText = (child.data and child.data.message or ""):lower()
                    childMatches = searchText:find(searchFilter, 1, true) or
                                   msgText:find(searchFilter, 1, true)
                end

                if childMatches then
                    table.insert(filteredChildren, child)
                end
            end

            -- Only add category if it has children after filtering
            if #filteredChildren > 0 then
                local newCatNode = {}
                for k, v in pairs(catNode) do
                    newCatNode[k] = v
                end
                newCatNode.children = filteredChildren
                newCatNode.text = catNode.data and catNode.data.name or catNode.text:match("^(.-)%s*%(") or catNode.text
                newCatNode.text = newCatNode.text .. " (" .. #filteredChildren .. ")"
                table.insert(filtered, newCatNode)
            end
        end
    end
    return filtered
end

-- Refresh browser tab (preserves scroll position and expand/collapse state)
function GUI.RefreshBrowserTab(tabType, forceReset)
    local container = GUI.Frame.tabContents[tabType]
    if not container then return end

    -- Save current scroll position before refresh
    local savedScrollOffset = 0
    if container.treeView and container.treeView.GetScrollOffset then
        savedScrollOffset = container.treeView:GetScrollOffset()
    end

    -- Build tree data with state preservation (don't auto-expand new categories)
    local treeData
    if tabType == "lfm" then
        treeData = AIP.TreeBrowser and AIP.TreeBrowser.BuildLFMTree(not forceReset) or {}
    else
        treeData = AIP.TreeBrowser and AIP.TreeBrowser.BuildLFGTree(not forceReset) or {}
    end

    -- Update filter dropdown with detected raids
    GUI.UpdateFilterDropdownOptions(container, treeData)

    -- Apply search and raid filters
    local searchFilter = container.searchFilter or ""
    local raidFilter = container.raidFilter or "ALL"
    treeData = FilterTreeData(treeData, searchFilter, raidFilter)

    if container.treeView then
        -- Preserve scroll position during update
        container.treeView:SetTreeData(treeData, not forceReset)
    end

    -- Update counts
    local lfmCount, lfgCount = 0, 0
    if AIP.TreeBrowser then
        lfmCount, lfgCount = AIP.TreeBrowser.GetTotalCounts()
    end

    local count = (tabType == "lfm") and lfmCount or lfgCount

    -- Count filtered items
    local filteredCount = 0
    for _, cat in ipairs(treeData) do
        if cat.children then
            filteredCount = filteredCount + #cat.children
        end
    end

    -- Show/hide empty state message
    if container.emptyTreeText then
        if count == 0 or filteredCount == 0 then
            container.emptyTreeText:Show()
            if count > 0 and filteredCount == 0 then
                container.emptyTreeText:SetText("No matches for current filter\n\nTotal " .. (tabType == "lfm" and "groups" or "players") .. ": " .. count)
            elseif tabType == "lfm" then
                container.emptyTreeText:SetText("No groups found\n\nGroups will appear when players\nadvertise in chat channels")
            else
                container.emptyTreeText:SetText("No players found\n\nPlayers will appear when they\nlook for group in chat channels")
            end
        else
            container.emptyTreeText:Hide()
        end
    end

    if container.countsText then
        local filterNote = (searchFilter ~= "" or raidFilter ~= "ALL") and " (filtered)" or ""
        if tabType == "lfm" then
            container.countsText:SetText("Groups: " .. filteredCount .. "/" .. lfmCount .. filterNote)
        else
            container.countsText:SetText("Players: " .. filteredCount .. "/" .. lfgCount .. filterNote)
        end
    end

    -- Update queue panel
    GUI.UpdateQueuePanel(container)
end

-- Update queue panel display (handles both tabs)
function GUI.UpdateQueuePanel(container)
    if not container then return end

    -- Refresh saved instances for lockout checks
    if AIP.TreeBrowser and AIP.TreeBrowser.UpdateSavedInstances then
        AIP.TreeBrowser.UpdateSavedInstances()
    end

    -- Clean up old LFG enrollments
    GUI.CleanupLfgEnrollments()

    local queue = AIP.db and AIP.db.queue or {}
    local waitlistCount = AIP.GetWaitlistCount and AIP.GetWaitlistCount() or 0

    -- Separate queue entries and LFG enrollments
    local queueEntries = {}
    local lfgEntries = {}
    for _, entry in ipairs(queue) do
        if entry.isLfgEnrollment then
            table.insert(lfgEntries, entry)
        else
            table.insert(queueEntries, entry)
        end
    end

    -- Also add LFG enrollments from our tracking table
    for name, enrollment in pairs(GUI.LfgEnrollments or {}) do
        local found = false
        for _, e in ipairs(lfgEntries) do
            if e.name == name then found = true break end
        end
        if not found then
            table.insert(lfgEntries, enrollment)
        end
    end

    -- Update Queue rows (whisper requests)
    if container.queueRows then
        for i = 1, #container.queueRows do
            local row = container.queueRows[i]
            local entry = queueEntries[i]

            row.invBtn.index = i
            row.rejBtn.index = i
            row.waitBtn.index = i
            row.blBtn.index = i
            if row.remBtn then row.remBtn.index = i end

            if entry then
                row.numText:SetText(i)

                -- Time since added (seconds display)
                if row.timeText and entry.time then
                    local elapsed = time() - entry.time
                    local timeStr
                    if elapsed < 60 then
                        timeStr = elapsed .. "s"
                    elseif elapsed < 3600 then
                        timeStr = math.floor(elapsed / 60) .. "m"
                    else
                        timeStr = math.floor(elapsed / 3600) .. "h"
                    end
                    row.timeText:SetText(timeStr)
                    -- Color based on wait time
                    if elapsed < 120 then
                        row.timeText:SetTextColor(0.4, 0.8, 0.4)  -- Green (recent)
                    elseif elapsed < 300 then
                        row.timeText:SetTextColor(0.8, 0.8, 0.4)  -- Yellow
                    else
                        row.timeText:SetTextColor(0.8, 0.4, 0.4)  -- Red (waiting long)
                    end
                elseif row.timeText then
                    row.timeText:SetText("-")
                end

                -- Show name with favorite/guild indicators
                local displayName = entry.name or "-"
                if entry.isFavorite then
                    displayName = "|cFF00FF80*|r" .. displayName  -- Green star for favorite
                    row.nameText:SetTextColor(0, 1, 0.5)  -- Greenish
                elseif entry.isGuildMember then
                    displayName = "|cFF00CCFF+|r" .. displayName  -- Blue plus for guild
                    row.nameText:SetTextColor(0.4, 0.8, 1)  -- Light blue
                else
                    row.nameText:SetTextColor(1, 1, 1)  -- Default white
                end
                row.nameText:SetText(displayName)

                local class = entry.class or "UNKNOWN"
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
                if classColor then
                    row.classText:SetText(class)
                    row.classText:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    row.classText:SetText(class)
                    row.classText:SetTextColor(1, 1, 1)
                end

                row.msgText:SetText((entry.message or ""):sub(1, 25))

                if entry.isBlacklisted then
                    row.blText:SetText("YES")
                    row.blText:SetTextColor(1, 0.3, 0.3)
                else
                    row.blText:SetText("-")
                    row.blText:SetTextColor(0.5, 0.5, 0.5)
                end

                -- Store entry for tooltip and enable mouse
                row.entryData = entry
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    local e = self.entryData
                    if not e then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(e.name or "Unknown", 1, 0.82, 0)
                    if e.class then GameTooltip:AddLine("Class: " .. e.class, 1, 1, 1) end
                    if e.gs then GameTooltip:AddDoubleLine("GearScore:", tostring(e.gs), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.ilvl then GameTooltip:AddDoubleLine("Item Level:", tostring(e.ilvl), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.message and e.message ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Message:", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(e.message, 1, 1, 1, true)
                    end
                    if e.isFavorite then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFF00FF80FAVORITE|r - Priority player", 0, 1, 0.5)
                    end
                    if e.isGuildMember then
                        GameTooltip:AddLine("|cFF00CCFFGUILD MEMBER|r", 0.4, 0.8, 1)
                    end
                    if e.isBlacklisted then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFFFF3333BLACKLISTED|r", 1, 0.3, 0.3)
                        if e.blacklistReason then GameTooltip:AddLine(e.blacklistReason, 1, 0.5, 0.5) end
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update LFG rows (enrollment broadcasts)
    container.lfgData = lfgEntries  -- Store for button callbacks
    if container.lfgRows then
        for i = 1, #container.lfgRows do
            local row = container.lfgRows[i]
            local entry = lfgEntries[i]

            row.invBtn.index = i
            row.whisperBtn.index = i
            row.queueBtn.index = i
            row.waitlistBtn.index = i

            if entry then
                row.numText:SetText(i)

                local class = entry.class or "UNKNOWN"
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class:upper()]
                if classColor then
                    row.nameText:SetText(entry.name or "-")
                    row.nameText:SetTextColor(classColor.r, classColor.g, classColor.b)
                else
                    row.nameText:SetText(entry.name or "-")
                    row.nameText:SetTextColor(1, 1, 1)
                end

                row.specText:SetText(entry.spec or entry.role or "-")
                -- Check lockout status for the raid
                local isLocked = false
                if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and entry.raid then
                    isLocked = AIP.TreeBrowser.IsLockedToInstance(entry.raid)
                end

                if isLocked then
                    row.raidText:SetText("|cFFFF4444" .. (entry.raid or "-") .. "|r")
                else
                    row.raidText:SetText(entry.raid or "-")
                end
                row.gsText:SetText(entry.gs and tostring(entry.gs) or "-")

                -- Store entry for tooltip and enable mouse
                row.entryData = entry
                row.isLocked = isLocked
                row:EnableMouse(true)
                row:SetScript("OnEnter", function(self)
                    local e = self.entryData
                    if not e then return end
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(e.name or "Unknown", 1, 0.82, 0)
                    if e.class then GameTooltip:AddLine("Class: " .. e.class, 1, 1, 1) end
                    if e.spec then GameTooltip:AddLine("Spec: " .. e.spec, 0.8, 0.8, 0.8) end
                    if e.role then GameTooltip:AddLine("Role: " .. e.role, 0.6, 0.8, 1) end
                    GameTooltip:AddLine(" ")
                    if e.gs then GameTooltip:AddDoubleLine("GearScore:", tostring(e.gs), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.ilvl then GameTooltip:AddDoubleLine("Item Level:", tostring(e.ilvl), 0.7, 0.7, 0.7, 0, 1, 0) end
                    if e.raid then
                        if self.isLocked then
                            GameTooltip:AddDoubleLine("Looking for:", e.raid .. " |cFFFF4444[LOCKED]|r", 0.7, 0.7, 0.7, 1, 0.27, 0.27)
                        else
                            GameTooltip:AddDoubleLine("Looking for:", e.raid, 0.7, 0.7, 0.7, 1, 0.82, 0)
                        end
                    end
                    if e.message and e.message ~= "" then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("Full Message:", 0.7, 0.7, 0.7)
                        GameTooltip:AddLine(e.message, 1, 1, 1, true)
                    end
                    if e.isSelf then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFF00FF00This is your enrollment|r", 0, 1, 0)
                    end
                    if self.isLocked then
                        GameTooltip:AddLine(" ")
                        GameTooltip:AddLine("|cFFFF4444You are saved to this instance|r", 1, 0.27, 0.27)
                    end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update Waitlist rows
    local waitlistEntries = AIP.db and AIP.db.waitlist or {}
    if container.waitlistRows then
        for i = 1, #container.waitlistRows do
            local row = container.waitlistRows[i]
            local entry = waitlistEntries[i]

            row.invBtn.index = i
            row.upBtn.index = i
            row.downBtn.index = i
            row.remBtn.index = i

            if entry then
                row.numText:SetText(i)
                row.nameText:SetText(entry.name or "-")

                -- Color role text
                local roleColors = {
                    TANK = {0.5, 0.5, 1},
                    HEALER = {0.5, 1, 0.5},
                    DPS = {1, 0.5, 0.5},
                }
                local color = roleColors[entry.role] or {1, 1, 1}
                row.roleText:SetText(entry.role or "DPS")
                row.roleText:SetTextColor(color[1], color[2], color[3])

                row.noteText:SetText((entry.note or ""):sub(1, 20))
                row.timeText:SetText(AIP.FormatTimeAgo and AIP.FormatTimeAgo(entry.addedTime) or "-")

                row:Show()
            else
                row:Hide()
            end
        end
    end

    -- Update tab button counts
    if container.queueTabBtn and container.queueTabBtn.text then
        container.queueTabBtn.text:SetText("Queue (" .. #queueEntries .. ")")
    end
    if container.lfgTabBtn and container.lfgTabBtn.text then
        container.lfgTabBtn.text:SetText("LFG (" .. #lfgEntries .. ")")
    end
    if container.waitlistTabBtn and container.waitlistTabBtn.text then
        container.waitlistTabBtn.text:SetText("Waitlist (" .. #waitlistEntries .. ")")
    end

    -- Update status
    if container.queueStatus then
        local statusText = ""
        if GUI.MyEnrollment then
            statusText = "|cFF00FF00LFG: " .. GUI.MyEnrollment.raid .. "|r"
        elseif GUI.MyGroup then
            statusText = "|cFF00FF00LFM: " .. GUI.MyGroup.raid .. "|r"
        else
            statusText = "Ready"
        end
        container.queueStatus:SetText("Status: " .. statusText)
    end
end

-- Update details panel when a group is selected
function GUI.UpdateDetailsPanel(container, data)
    if not container then return end

    container.selectedGroupData = data
    -- Set currentLeader for whisper button
    container.currentLeader = data and (data.leader or data.name) or nil

    if not data then
        if container.detContent then container.detContent:Hide() end
        if container.noSelectText then container.noSelectText:Show() end
        return
    end

    if container.noSelectText then container.noSelectText:Hide() end
    if container.detContent then container.detContent:Show() end

    if container.leaderValue then
        container.leaderValue:SetText(data.leader or data.name or "-")
    end
    if container.raidValue then
        container.raidValue:SetText(data.raid or "-")
        -- Update lockout indicator
        if container.lockoutIndicator then
            local isLocked = false
            if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and data.raid then
                AIP.TreeBrowser.UpdateSavedInstances()
                isLocked = AIP.TreeBrowser.IsLockedToInstance(data.raid)
            end
            if isLocked then
                container.lockoutIndicator:Show()
            else
                container.lockoutIndicator:Hide()
            end
        end
    end
    if container.msgValue then
        container.msgValue:SetText(data.message or "-")
    end

    local gsText = "-"
    if data.gsMin and data.gsMin > 0 then
        gsText = tostring(data.gsMin) .. "+"
    elseif data.gs and data.gs > 0 then
        gsText = tostring(data.gs)
    end
    if container.gsValue then
        container.gsValue:SetText(gsText)
    end

    local ilvlText = "-"
    if data.ilvlMin and data.ilvlMin > 0 then
        ilvlText = tostring(data.ilvlMin) .. "+"
    end
    if container.ilvlValue then
        container.ilvlValue:SetText(ilvlText)
    end

    local compText = "-"
    if data.tanks or data.healers or data.mdps or data.rdps or data.dps then
        local parts = {}
        if data.tanks then
            table.insert(parts, string.format("T:%d/%d", data.tanks.current or 0, data.tanks.needed or 0))
        end
        if data.healers then
            table.insert(parts, string.format("H:%d/%d", data.healers.current or 0, data.healers.needed or 0))
        end
        if data.mdps then
            table.insert(parts, string.format("M:%d/%d", data.mdps.current or 0, data.mdps.needed or 0))
        end
        if data.rdps then
            table.insert(parts, string.format("R:%d/%d", data.rdps.current or 0, data.rdps.needed or 0))
        end
        -- Backwards compatibility for old dps field
        if not data.mdps and not data.rdps and data.dps then
            table.insert(parts, string.format("D:%d/%d", data.dps.current or 0, data.dps.needed or 0))
        end
        compText = table.concat(parts, " ")
    end
    if container.compValue then
        container.compValue:SetText(compText)
    end

    -- Achievement requirement
    local achieveText = "-"
    if data.achievementId then
        local _, achName = GetAchievementInfo(data.achievementId)
        if achName then
            achieveText = achName
        else
            achieveText = "ID: " .. tostring(data.achievementId)
        end
    end
    if container.achieveValue then
        container.achieveValue:SetText(achieveText)
    end

    -- Invite keyword
    local keywordText = "-"
    if data.inviteKeyword and data.inviteKeyword ~= "" then
        keywordText = '"' .. data.inviteKeyword .. '"'
    end
    if container.keywordValue then
        container.keywordValue:SetText(keywordText)
    end

    -- Looking For (interpret roleSpecs array with class colors and tooltips)
    local lookingForText = "-"
    if data.roleSpecs and AIP.Parsers then
        local roleLabels = {
            TANK = {label = "Tanks", color = "00FFFF"},
            HEALER = {label = "Healers", color = "00FF00"},
            MDPS = {label = "Melee", color = "FF6666"},
            RDPS = {label = "Ranged", color = "FFFF00"},
        }
        local roleOrder = {"TANK", "HEALER", "MDPS", "RDPS"}
        local parts = {}

        for _, role in ipairs(roleOrder) do
            local specs = data.roleSpecs[role]
            if specs and #specs > 0 then
                local roleInfo = roleLabels[role]
                -- Group specs by class for cleaner display
                local classCodes = {}  -- {className = {codes}}
                for _, code in ipairs(specs) do
                    local info = AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                    if info then
                        local className = info.class
                        classCodes[className] = classCodes[className] or {}
                        table.insert(classCodes[className], {code = code, spec = info.spec, shortClass = info.shortClass})
                    else
                        -- Unknown code, show as-is
                        classCodes["UNKNOWN"] = classCodes["UNKNOWN"] or {}
                        table.insert(classCodes["UNKNOWN"], {code = code, spec = code, shortClass = code})
                    end
                end

                -- Build class list with colors
                local classStrings = {}
                local sortedClasses = {}
                for className in pairs(classCodes) do
                    table.insert(sortedClasses, className)
                end
                table.sort(sortedClasses)

                for _, className in ipairs(sortedClasses) do
                    local codes = classCodes[className]
                    local color = AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[className]
                    local hex = color and color.hex or "FFFFFF"
                    local shortClass = codes[1].shortClass
                    -- Show class name with spec codes in parentheses
                    local specList = {}
                    for _, c in ipairs(codes) do
                        table.insert(specList, c.code)
                    end
                    table.insert(classStrings, "|cFF" .. hex .. shortClass .. "|r")
                end

                if #classStrings > 0 then
                    table.insert(parts, "|cFF" .. roleInfo.color .. roleInfo.label .. ":|r " .. table.concat(classStrings, ", "))
                end
            end
        end

        if #parts > 0 then
            lookingForText = table.concat(parts, " | ")
        end
    elseif data.lookingForSpecs and #data.lookingForSpecs > 0 then
        -- Fallback to flat list with class colors
        local coloredSpecs = {}
        for _, code in ipairs(data.lookingForSpecs) do
            local info = AIP.Parsers and AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
            if info then
                local color = AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[info.class]
                local hex = color and color.hex or "FFFFFF"
                table.insert(coloredSpecs, "|cFF" .. hex .. code .. "|r")
            else
                table.insert(coloredSpecs, code)
            end
        end
        lookingForText = table.concat(coloredSpecs, ", ")
    end
    if container.lookingForValue then
        container.lookingForValue:SetText(lookingForText)
    end

    -- Store roleSpecs for tooltip access
    container.currentRoleSpecs = data.roleSpecs

    -- Set up tooltip for lookingForFrame
    if container.lookingForFrame then
        container.lookingForFrame:EnableMouse(true)
        container.lookingForFrame:SetScript("OnEnter", function(self)
            if not container.currentRoleSpecs then return end
            local roleSpecs = container.currentRoleSpecs

            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
            GameTooltip:AddLine("Looking For - Specs Needed", 1, 0.82, 0)
            GameTooltip:AddLine(" ")

            local roleLabels = {
                TANK = {label = "Tanks", r = 0, g = 1, b = 1},
                HEALER = {label = "Healers", r = 0, g = 1, b = 0},
                MDPS = {label = "Melee DPS", r = 1, g = 0.4, b = 0.4},
                RDPS = {label = "Ranged DPS", r = 1, g = 1, b = 0},
            }
            local roleOrder = {"TANK", "HEALER", "MDPS", "RDPS"}

            for _, role in ipairs(roleOrder) do
                local specs = roleSpecs[role]
                if specs and #specs > 0 then
                    local roleInfo = roleLabels[role]
                    GameTooltip:AddLine(roleInfo.label .. ":", roleInfo.r, roleInfo.g, roleInfo.b)

                    for _, code in ipairs(specs) do
                        local info = AIP.Parsers and AIP.Parsers.SpecCodeInfo and AIP.Parsers.SpecCodeInfo[code]
                        if info then
                            local color = AIP.Parsers.ClassColors and AIP.Parsers.ClassColors[info.class]
                            local r, g, b = color and color.r or 1, color and color.g or 1, color and color.b or 1
                            GameTooltip:AddLine("  " .. info.shortClass .. " - " .. info.spec, r, g, b)
                        else
                            GameTooltip:AddLine("  " .. code, 0.7, 0.7, 0.7)
                        end
                    end
                end
            end

            GameTooltip:Show()
        end)
        container.lookingForFrame:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end

    -- Total filled (from composition)
    local totalFilledText = "-"
    if data.tanks or data.healers or data.mdps or data.rdps then
        local current = (data.tanks and data.tanks.current or 0) +
                       (data.healers and data.healers.current or 0) +
                       (data.mdps and data.mdps.current or 0) +
                       (data.rdps and data.rdps.current or 0)
        local needed = (data.tanks and data.tanks.needed or 0) +
                      (data.healers and data.healers.needed or 0) +
                      (data.mdps and data.mdps.needed or 0) +
                      (data.rdps and data.rdps.needed or 0)
        if needed > 0 then
            local color = current >= needed and "|cFF00FF00" or "|cFFFFFF00"
            totalFilledText = color .. current .. "/" .. needed .. "|r"
        end
    end
    if container.totalFilledValue then
        container.totalFilledValue:SetText(totalFilledText)
    end
end

-- ============================================================================
-- AUTO-BROADCAST SYSTEM
-- ============================================================================
GUI.Broadcast = {
    active = false,
    mode = nil, -- "lfm" or "lfg"
    message = "",
    interval = 60,
    timer = nil,
    elapsed = 0,
}

-- Join/create our custom channels
function GUI.SetupCustomChannels()
    -- Join LFM channel
    local lfmIndex = GetChannelName(GUI.CustomChannels.LFM)
    if lfmIndex == 0 then
        JoinChannelByName(GUI.CustomChannels.LFM)
    end

    -- Join LFG channel
    local lfgIndex = GetChannelName(GUI.CustomChannels.LFG)
    if lfgIndex == 0 then
        JoinChannelByName(GUI.CustomChannels.LFG)
    end
end

-- Get channel ID for our custom channels
function GUI.GetCustomChannelId(channelName)
    local id = GetChannelName(channelName)
    if id and id > 0 then
        return id
    end
    return nil
end

-- Parse LFG enrollment message from other addon users
-- New format: "LFG <RAID> - <Class> (<Spec>) <Role> | GS:<gs> iL:<ilvl> Lv:<level> {AIP:5.2}"
-- Old format: "LFG <RAID> - <Class> (<Spec>) <Role>, GS: <gs>, iLvl: <ilvl> {AIP:<version>}"
function GUI.ParseLfgEnrollment(message, author)
    -- Try new format first: "LFG ICC25H - War (Arms) DPS | GS:5500 iL:264 Lv:80 {AIP:5.2}"
    local raid, classDisplay, spec, role, gs, ilvl, level = message:match("LFG%s+(%S+)%s+%-%s+(%S+)%s+%(([^)]+)%)%s+(%a+)%s+|%s*GS:(%d+)%s+iL:(%d+)%s+Lv:(%d+)")

    -- Fallback to old format if new format doesn't match
    if not raid then
        raid, classDisplay, spec, role, gs, ilvl = message:match("LFG%s+(%S+)%s+%-%s+(%a+)%s+%(([^)]+)%)%s+(%a+),%s+GS:%s*(%d+),%s+iLvl:%s*(%d+)")
    end

    if raid and classDisplay and author then
        -- Map short class names back to full class names
        local classNameMap = {
            WAR = "WARRIOR", PAL = "PALADIN", DK = "DEATHKNIGHT", DRU = "DRUID",
            PRI = "PRIEST", SHA = "SHAMAN", MAG = "MAGE", LOC = "WARLOCK",
            HUN = "HUNTER", ROG = "ROGUE",
            -- Also handle full names
            WARRIOR = "WARRIOR", PALADIN = "PALADIN", DEATHKNIGHT = "DEATHKNIGHT",
            DRUID = "DRUID", PRIEST = "PRIEST", SHAMAN = "SHAMAN", MAGE = "MAGE",
            WARLOCK = "WARLOCK", HUNTER = "HUNTER", ROGUE = "ROGUE"
        }
        local classKey = classDisplay:upper()
        local fullClass = classNameMap[classKey] or classKey

        local enrollment = {
            name = author,
            raid = raid,
            class = fullClass,
            classShort = classDisplay,
            spec = spec or "Unknown",
            role = role or "DPS",
            gs = tonumber(gs) or 0,
            ilvl = tonumber(ilvl) or 0,
            level = tonumber(level) or 0,
            time = time(),
            message = message,
            isLfgEnrollment = true,  -- Flag to distinguish from regular queue entries
        }

        -- Add/update in our enrollment tracking
        GUI.LfgEnrollments[author] = enrollment

        -- Also add to queue if not already present
        if AIP.db and AIP.db.queue then
            local found = false
            for _, entry in ipairs(AIP.db.queue) do
                if entry.name == author and entry.isLfgEnrollment then
                    -- Update existing
                    for k, v in pairs(enrollment) do entry[k] = v end
                    found = true
                    break
                end
            end
            if not found then
                table.insert(AIP.db.queue, enrollment)
            end
            if AIP.UpdateQueueUI then AIP.UpdateQueueUI() end
        end

        return enrollment
    end
    return nil
end

-- Chat event handler for custom LFG channel
local lfgChatFrame = CreateFrame("Frame")
lfgChatFrame:RegisterEvent("CHAT_MSG_CHANNEL")
lfgChatFrame:SetScript("OnEvent", function(self, event, message, author, _, _, _, _, _, channelNumber, channelName)
    if not channelName then return end

    -- Check if this is our LFG channel
    if channelName == GUI.CustomChannels.LFG then
        -- Don't process our own messages
        if author == UnitName("player") then return end

        -- Parse and track the enrollment
        GUI.ParseLfgEnrollment(message, author)
    end
end)

-- Clean up old LFG enrollments (older than 15 minutes)
function GUI.CleanupLfgEnrollments()
    local now = time()
    local expireTime = 15 * 60  -- 15 minutes

    for name, enrollment in pairs(GUI.LfgEnrollments) do
        if now - enrollment.time > expireTime then
            GUI.LfgEnrollments[name] = nil
            -- Also remove from queue
            if AIP.db and AIP.db.queue then
                for i = #AIP.db.queue, 1, -1 do
                    if AIP.db.queue[i].name == name and AIP.db.queue[i].isLfgEnrollment then
                        table.remove(AIP.db.queue, i)
                    end
                end
            end
        end
    end
end

-- Calculate auto-tuned broadcast interval based on enabled channels to avoid chat bans
function GUI.CalculateAutoTuneInterval()
    local channelCount = 1  -- Custom channel always counts

    if AIP.db then
        -- Count enabled public channels
        if AIP.db.spamTrade then channelCount = channelCount + 1 end
        if AIP.db.spamGeneral then channelCount = channelCount + 1 end
        if AIP.db.spamLFG then channelCount = channelCount + 1 end
        if AIP.db.spamSay then channelCount = channelCount + 1 end
        if AIP.db.spamYell then channelCount = channelCount + 1 end
        if AIP.db.spamGuild then channelCount = channelCount + 1 end
    end

    -- Base interval: 60s minimum, add 15s for each additional public channel
    -- WoW typically allows ~1 message per minute per channel type without penalty
    local baseInterval = 60
    local perChannelDelay = 15
    local autoTunedInterval = baseInterval + (math.max(0, channelCount - 1) * perChannelDelay)

    -- Cap between 60s and 180s
    return math.max(60, math.min(180, autoTunedInterval))
end

-- Start auto-broadcasting
function GUI.StartBroadcast(mode, message, interval)
    -- Ensure custom channels exist
    GUI.SetupCustomChannels()

    GUI.Broadcast.active = true
    GUI.Broadcast.mode = mode
    GUI.Broadcast.message = message

    -- Auto-tune interval if not specified or lower than safe minimum
    local requestedInterval = interval or (AIP.db and AIP.db.autoSpamInterval) or 60
    local autoTunedInterval = GUI.CalculateAutoTuneInterval()

    -- Use the higher of requested vs auto-tuned to be safe
    GUI.Broadcast.interval = math.max(requestedInterval, autoTunedInterval)
    GUI.Broadcast.elapsed = GUI.Broadcast.interval -- Trigger immediately

    if not GUI.Broadcast.timer then
        GUI.Broadcast.timer = CreateFrame("Frame")
    end

    GUI.Broadcast.statusElapsed = 0
    GUI.Broadcast.timer:SetScript("OnUpdate", function(self, elapsed)
        GUI.Broadcast.elapsed = GUI.Broadcast.elapsed + elapsed
        GUI.Broadcast.statusElapsed = (GUI.Broadcast.statusElapsed or 0) + elapsed

        -- Update status display every second
        if GUI.Broadcast.statusElapsed >= 1 then
            GUI.Broadcast.statusElapsed = 0
            GUI.UpdateBroadcastStatus()
        end

        if GUI.Broadcast.elapsed >= GUI.Broadcast.interval then
            GUI.Broadcast.elapsed = 0
            GUI.DoBroadcast()
        end
    end)

    -- Update status display
    GUI.UpdateBroadcastStatus()

    local intervalNote = ""
    local requestedInterval = interval or (AIP.db and AIP.db.autoSpamInterval) or 60
    if GUI.Broadcast.interval > requestedInterval then
        intervalNote = " (auto-tuned from " .. requestedInterval .. "s)"
    end
    AIP.Print("|cFF00FF00Broadcasting started|r - " .. (mode == "lfm" and "LFM" or "LFG") .. " every " .. GUI.Broadcast.interval .. "s" .. intervalNote)
end

-- Stop auto-broadcasting
function GUI.StopBroadcast()
    GUI.Broadcast.active = false
    GUI.Broadcast.mode = nil
    GUI.MyGroup = nil  -- Clear our active LFM data
    GUI.MyEnrollment = nil  -- Clear our active LFG enrollment

    if GUI.Broadcast.timer then
        GUI.Broadcast.timer:SetScript("OnUpdate", nil)
    end

    -- Reset player mode
    if AIP.SetPlayerMode then
        AIP.SetPlayerMode("none")
    end

    GUI.UpdateBroadcastStatus()
    GUI.UpdateStatus()  -- Update footer to reflect mode change
    AIP.Print("|cFFFF0000Broadcasting stopped|r")
end

-- Perform the broadcast (with staggered timing to avoid chat bans)
function GUI.DoBroadcast()
    if not GUI.Broadcast.active or not GUI.Broadcast.message or GUI.Broadcast.message == "" then
        return
    end

    local msg = GUI.Broadcast.message
    local mode = GUI.Broadcast.mode

    -- Queue of messages to send with delays
    local messageQueue = {}
    local delay = 0

    -- Use chat ban system's delay if available, otherwise default to 2s
    local delayIncrement = 2
    if AIP.ChatBan then
        delayIncrement = AIP.ChatBan.channelDelay or 2
        -- If recently banned, use increased delay
        local now = time()
        if AIP.ChatBan.detected and (now - (AIP.ChatBan.lastBanTime or 0)) < 300 then
            delayIncrement = math.min(AIP.ChatBan.maxDelay or 5, delayIncrement + (AIP.ChatBan.banCount or 0))
        end
    end

    -- 1. Send to our custom AIP channel first (primary/default, no delay)
    local customChannel = mode == "lfm" and GUI.CustomChannels.LFM or GUI.CustomChannels.LFG
    local customId = GUI.GetCustomChannelId(customChannel)
    if customId then
        table.insert(messageQueue, {delay = 0, name = "AIP", func = function()
            SendChatMessage(msg, "CHANNEL", nil, customId)
        end})
        delay = delay + delayIncrement
    end

    -- 2. Send to standard LFG channel
    if AIP.FindChannelId then
        local lfgId = AIP.FindChannelId("LookingForGroup")
        if lfgId then
            table.insert(messageQueue, {delay = delay, name = "LFG", func = function()
                SendChatMessage(msg, "CHANNEL", nil, lfgId)
            end})
            delay = delay + delayIncrement
        end
    end

    -- 3. Send to additional channels if configured in settings (with delays)
    if AIP.db then
        if AIP.db.spamTrade and AIP.FindChannelId then
            local tradeId = AIP.FindChannelId("trade")
            if tradeId then
                table.insert(messageQueue, {delay = delay, name = "Trade", func = function()
                    SendChatMessage(msg, "CHANNEL", nil, tradeId)
                end})
                delay = delay + delayIncrement
            end
        end
        if AIP.db.spamGeneral and AIP.FindChannelId then
            local generalId = AIP.FindChannelId("general")
            if generalId then
                table.insert(messageQueue, {delay = delay, name = "General", func = function()
                    SendChatMessage(msg, "CHANNEL", nil, generalId)
                end})
                delay = delay + delayIncrement
            end
        end
        -- Say and Yell can be sent together (different chat types, less throttled)
        local groupDelay = delay
        if AIP.db.spamSay then
            table.insert(messageQueue, {delay = groupDelay, name = "Say", func = function()
                SendChatMessage(msg, "SAY")
            end})
            groupDelay = groupDelay + 0.5
        end
        if AIP.db.spamYell then
            table.insert(messageQueue, {delay = groupDelay, name = "Yell", func = function()
                SendChatMessage(msg, "YELL")
            end})
            groupDelay = groupDelay + 0.5
        end
        if AIP.db.spamGuild and IsInGuild() then
            table.insert(messageQueue, {delay = groupDelay, name = "Guild", func = function()
                SendChatMessage(msg, "GUILD")
            end})
        end
    end

    -- Track how many messages we're sending (for ban detection)
    GUI.Broadcast.pendingMessages = #messageQueue
    GUI.Broadcast.sentMessages = 0

    -- Execute the message queue with delays
    for _, item in ipairs(messageQueue) do
        if item.delay == 0 then
            item.func()
            GUI.Broadcast.sentMessages = (GUI.Broadcast.sentMessages or 0) + 1
        else
            AIP.Utils.DelayedCall(item.delay, function()
                -- Check if broadcast is still active before sending
                if GUI.Broadcast.active then
                    item.func()
                    GUI.Broadcast.sentMessages = (GUI.Broadcast.sentMessages or 0) + 1
                end
            end)
        end
    end

    -- Log the broadcast with timing info if delay is elevated
    if delayIncrement > 2 then
        -- Debug: show that we're using elevated delays
        -- AIP.Print("|cFFFFFF00Broadcast using " .. delayIncrement .. "s delay between channels|r")
    end
end

-- Update broadcast status display
function GUI.UpdateBroadcastStatus()
    -- Update the LFM browser tab controls if available
    local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
    if container then
        if container.stopBroadcastBtn then
            if GUI.Broadcast.active then
                container.stopBroadcastBtn:Show()
            else
                container.stopBroadcastBtn:Hide()
            end
        end
    end

    -- Update the main status bar (footer) with broadcast countdown
    if GUI.Frame and GUI.Frame.statusBar then
        local statusText = GUI.Frame.statusBar.broadcastStatus
        if statusText then
            if GUI.Broadcast.active then
                local remaining = math.max(0, GUI.Broadcast.interval - GUI.Broadcast.elapsed)
                local modeStr = GUI.Broadcast.mode == "lfm" and "Group (LFM)" or "Enroll (LFG)"
                local raidInfo = ""
                -- Show what raid we're broadcasting for
                if GUI.Broadcast.mode == "lfg" and GUI.MyEnrollment then
                    raidInfo = " " .. (GUI.MyEnrollment.raid or "")
                elseif GUI.Broadcast.mode == "lfm" and GUI.MyGroup then
                    raidInfo = " " .. (GUI.MyGroup.raid or "")
                end
                local color = remaining < 5 and "|cFFFFFF00" or "|cFF00FF00"
                statusText:SetText(color .. "Broadcasting " .. modeStr .. raidInfo .. ":|r " .. math.floor(remaining) .. "s")
            else
                statusText:SetText("")
            end
        end

        -- Update chat ban status
        local chatBanStatus = GUI.Frame.statusBar.chatBanStatus
        if chatBanStatus then
            local statusMsg = ""

            -- Check if chat ban detected
            if AIP.ChatBan and AIP.ChatBan.detected then
                local now = time()
                local timeSinceBan = now - (AIP.ChatBan.lastBanTime or 0)
                if timeSinceBan < 300 then  -- Show for 5 minutes after ban
                    local remaining = 300 - timeSinceBan
                    local delayInfo = ""
                    if AIP.ChatBan.channelDelay and AIP.ChatBan.channelDelay > 2 then
                        delayInfo = " | Delay: " .. AIP.ChatBan.channelDelay .. "s"
                    end
                    statusMsg = "|cFFFF6666\226\154\160 THROTTLED|r (" .. math.floor(remaining) .. "s)" .. delayInfo
                end
            end

            -- If broadcasting and no ban, show channel delay info
            if statusMsg == "" and GUI.Broadcast.active then
                local delayIncrement = 2
                if AIP.ChatBan then
                    delayIncrement = AIP.ChatBan.channelDelay or 2
                end
                if delayIncrement > 2 then
                    statusMsg = "|cFFFFFF00Channel delay: " .. delayIncrement .. "s|r"
                end
            end

            chatBanStatus:SetText(statusMsg)
        end
    end
end

-- Update enrollment status display
function GUI.UpdateEnrollmentStatus()
    local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
    if not container then return end

    if container.queueStatus then
        local queue = AIP.db and AIP.db.queue or {}
        local waitlistCount = AIP.GetWaitlistCount and AIP.GetWaitlistCount() or 0

        local statusText = "Queue: " .. #queue .. " | Waitlist: " .. waitlistCount
        if GUI.MyEnrollment then
            statusText = statusText .. " | |cFF00FF00LFG: " .. GUI.MyEnrollment.raid .. "|r"
        end
        container.queueStatus:SetText(statusText)
    end
end

-- Clear enrollment when stopping broadcast
local origStopBroadcast = GUI.StopBroadcast
function GUI.StopBroadcast()
    local wasLfg = GUI.Broadcast.mode == "lfg"
    origStopBroadcast()
    if wasLfg then
        -- Remove our enrollment from LfgEnrollments
        local playerName = UnitName("player")
        if playerName and GUI.LfgEnrollments then
            GUI.LfgEnrollments[playerName] = nil
        end
        GUI.MyEnrollment = nil
        GUI.UpdateEnrollmentStatus()
        -- Update queue panel
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then GUI.UpdateQueuePanel(container) end
    end
end

-- ============================================================================
-- COMPOSITION DEPLETION SYSTEM
-- Updates the broadcast message when group composition changes
-- ============================================================================

-- Get the player's own LFM group listing
function GUI.GetOwnGroup()
    local playerName = UnitName("player")
    if not playerName then return nil end

    -- Check ChatScanner first
    if AIP.ChatScanner and AIP.ChatScanner.Groups then
        local group = AIP.ChatScanner.Groups[playerName]
        if group and group.isOwn then
            return group
        end
    end

    -- Fallback to GroupTracker
    if AIP.GroupTracker and AIP.GroupTracker.Groups then
        local group = AIP.GroupTracker.Groups[playerName]
        if group and group.isOwn then
            return group
        end
    end

    return nil
end

-- Get current raid composition from actual group members
-- Returns: tanks, healers, mdps, rdps
function GUI.GetCurrentGroupComposition()
    local tanks, healers, mdps, rdps = 0, 0, 0, 0
    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    local function CountRole(name, unit)
        local roleGuess = GUI.GuessPlayerRole(name, unit)
        if roleGuess == "TANK" then
            tanks = tanks + 1
        elseif roleGuess == "HEALER" then
            healers = healers + 1
        elseif roleGuess == "MDPS" then
            mdps = mdps + 1
        else  -- RDPS or DPS (default to ranged)
            rdps = rdps + 1
        end
    end

    if numRaid > 0 then
        -- In a raid
        for i = 1, numRaid do
            local name, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
            if name then
                if role == "MAINTANK" or role == "maintank" then
                    tanks = tanks + 1
                else
                    CountRole(name, "raid" .. i)
                end
            end
        end
    elseif numParty > 0 then
        -- In a party (include self)
        for i = 1, numParty do
            local unit = "party" .. i
            local name = UnitName(unit)
            if name then
                CountRole(name, unit)
            end
        end
        -- Add self
        CountRole(UnitName("player"), "player")
    else
        -- Solo - add self
        CountRole(UnitName("player"), "player")
    end

    return tanks, healers, mdps, rdps
end

-- Melee DPS specs by class (for role detection)
GUI.MeleeDPSSpecs = {
    WARRIOR = {["Arms"] = true, ["Fury"] = true},
    PALADIN = {["Retribution"] = true},
    DEATHKNIGHT = {["Frost"] = true, ["Unholy"] = true},  -- DK DPS specs
    ROGUE = {["Assassination"] = true, ["Combat"] = true, ["Subtlety"] = true},
    SHAMAN = {["Enhancement"] = true},
    DRUID = {["Feral Combat"] = true, ["Feral"] = true},
}

-- Guess a player's role based on class/spec or queue data
-- Returns: TANK, HEALER, MDPS, or RDPS
function GUI.GuessPlayerRole(name, unit)
    if not name then return "RDPS" end

    -- Check queue for role info
    if AIP.db and AIP.db.queue then
        for _, entry in ipairs(AIP.db.queue) do
            if entry.name == name and entry.role then
                -- Convert old "DPS" role to MDPS/RDPS based on class
                if entry.role == "DPS" then
                    local class = entry.class
                    if class and GUI.MeleeDPSSpecs[class:upper()] then
                        return "MDPS"
                    end
                    return "RDPS"
                end
                return entry.role
            end
        end
    end

    -- Check inspection cache for role and spec
    if AIP.InspectionEngine and AIP.InspectionEngine.Cache then
        local cached = AIP.InspectionEngine.Cache:get(name)
        if cached then
            if cached.role == "TANK" or cached.role == "HEALER" then
                return cached.role
            end
            if cached.role == "DPS" or cached.role == "MDPS" or cached.role == "RDPS" then
                -- Check if melee spec
                local class = cached.class
                local spec = cached.spec
                if class and spec and GUI.MeleeDPSSpecs[class:upper()] then
                    if GUI.MeleeDPSSpecs[class:upper()][spec] then
                        return "MDPS"
                    end
                end
                return cached.role == "MDPS" and "MDPS" or "RDPS"
            end
        end
    end

    -- Try to guess from unit class
    if unit then
        local _, class = UnitClass(unit)
        if class then
            -- Pure melee classes default to MDPS
            if class == "ROGUE" then return "MDPS" end
            if class == "WARRIOR" then return "MDPS" end  -- Assume Arms/Fury, not tank without more info
        end
    end

    -- Default to ranged DPS
    return "RDPS"
end

-- Regenerate broadcast message with updated composition
function GUI.RegenerateBroadcastMessage()
    local ownGroup = GUI.GetOwnGroup()
    if not ownGroup then return nil end

    -- Get current composition (now returns 4 values: tanks, healers, mdps, rdps)
    local currentTanks, currentHealers, currentMdps, currentRdps = GUI.GetCurrentGroupComposition()

    -- Get needed counts from the original group data
    local neededTanks = ownGroup.tanks and ownGroup.tanks.needed or 2
    local neededHealers = ownGroup.healers and ownGroup.healers.needed or 6
    local neededMdps = ownGroup.mdps and ownGroup.mdps.needed or 8
    local neededRdps = ownGroup.rdps and ownGroup.rdps.needed or 9

    -- Update the group's current counts
    if ownGroup.tanks then ownGroup.tanks.current = currentTanks end
    if ownGroup.healers then ownGroup.healers.current = currentHealers end
    if ownGroup.mdps then ownGroup.mdps.current = currentMdps end
    if ownGroup.rdps then ownGroup.rdps.current = currentRdps end

    -- Build updated message
    local raidKey = ownGroup.raid or "?"
    local inviteKeyword = ownGroup.inviteKeyword or (AIP.db and AIP.db.triggers) or "inv"
    local keywordHint = string.format('w/ "%s"', inviteKeyword)

    local achieveLink = ""
    if ownGroup.achievementId then
        achieveLink = GetAchievementLink(ownGroup.achievementId) or ""
    end

    -- GS and iLvl without rounding
    local gsDisplay = ownGroup.gsMin and ownGroup.gsMin > 0 and (tostring(ownGroup.gsMin) .. "+") or ""
    local ilvlDisplay = ownGroup.ilvlMin and ownGroup.ilvlMin > 0 and (" iLvl:" .. tostring(ownGroup.ilvlMin) .. "+") or ""

    -- Build "LF:" class list if stored
    local lfClassStr = ""
    if ownGroup.lookingForClasses and #ownGroup.lookingForClasses > 0 then
        lfClassStr = " LF: " .. table.concat(ownGroup.lookingForClasses, "/")
    end

    local noteText = ownGroup.note or ""

    local msg = string.format("LFM %s [T:%d/%d H:%d/%d M:%d/%d R:%d/%d] %s%s%s %s %s %s",
        raidKey,
        currentTanks, neededTanks,
        currentHealers, neededHealers,
        currentMdps, neededMdps,
        currentRdps, neededRdps,
        gsDisplay,
        ilvlDisplay,
        lfClassStr,
        keywordHint,
        achieveLink,
        noteText)

    -- Clean up extra spaces
    msg = msg:gsub("%s+", " "):trim()

    return msg
end

-- Update broadcast message after composition change
function GUI.UpdateBroadcastComposition()
    if not GUI.Broadcast.active or GUI.Broadcast.mode ~= "lfm" then
        return
    end

    local newMsg = GUI.RegenerateBroadcastMessage()
    if newMsg then
        GUI.Broadcast.message = newMsg
        AIP.db.spamMessage = newMsg

        -- Update own group's stored message
        local ownGroup = GUI.GetOwnGroup()
        if ownGroup then
            ownGroup.message = newMsg
        end

        -- Refresh the tree to show updated composition
        GUI.RefreshBrowserTab("lfm")
    end
end

-- Track previous group size to detect changes
GUI.PreviousGroupSize = 0

-- Check if player joined a group (to stop LFG broadcast) or if group composition changed (to update LFM)
local broadcastEventFrame = CreateFrame("Frame")
broadcastEventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
broadcastEventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
broadcastEventFrame:SetScript("OnEvent", function(self, event)
    local numParty = GetNumPartyMembers() or 0
    local numRaid = GetNumRaidMembers() or 0
    local currentSize = numRaid > 0 and numRaid or numParty

    -- If broadcasting LFG and we joined a group, stop
    if GUI.Broadcast.active and GUI.Broadcast.mode == "lfg" then
        if numParty > 0 or numRaid > 0 then
            AIP.Print("|cFF00FF00You joined a group! Stopping LFG broadcast.|r")
            -- Remove our enrollment from LfgEnrollments
            local playerName = UnitName("player")
            if playerName and GUI.LfgEnrollments then
                GUI.LfgEnrollments[playerName] = nil
            end
            GUI.MyEnrollment = nil
            GUI.StopBroadcast()
            GUI.UpdateEnrollmentStatus()
            -- Update queue panel
            local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
            if container then GUI.UpdateQueuePanel(container) end
        end
    end

    -- If broadcasting LFM and group size changed, update composition in message
    if GUI.Broadcast.active and GUI.Broadcast.mode == "lfm" then
        if currentSize ~= GUI.PreviousGroupSize then
            -- Small delay to let group info update
            AIP.Utils.DelayedCall(0.5, function()
                GUI.UpdateBroadcastComposition()
            end)
        end
    end

    GUI.PreviousGroupSize = currentSize
end)

-- Show Add Group popup
function GUI.ShowAddGroupPopup()
    if not GUI.AddGroupPopup then
        GUI.CreateAddGroupPopup()
    end
    -- Update size dropdown for current raid selection
    if GUI.AddGroupPopup.UpdateSizeDropdown then
        GUI.AddGroupPopup.UpdateSizeDropdown()
    end
    -- Update raid dropdown text with lockout color
    if GUI.AddGroupPopup.UpdateRaidDropdownText then
        GUI.AddGroupPopup.UpdateRaidDropdownText()
    end
    -- Update reserved items display from DB (read-only)
    if GUI.AddGroupPopup.reservedDisplay then
        local reservedItems = AIP.db and AIP.db.reservedItems or ""
        if reservedItems and reservedItems ~= "" then
            -- Replace newlines with commas for display
            local displayText = reservedItems:gsub("\n", ", "):gsub(", $", "")
            GUI.AddGroupPopup.reservedDisplay:SetText(displayText)
        else
            GUI.AddGroupPopup.reservedDisplay:SetText("|cFF666666(none - edit in Raid Mgmt tab)|r")
        end
    end
    GUI.AddGroupPopup:Show()
end

-- Raid achievements for WotLK content
GUI.RaidAchievements = {
    ICC25H = {
        {id = 4584, name = "The Frozen Throne (25H)"},
        {id = 4621, name = "Been Waiting a Long Time (25H)"},
        {id = 4620, name = "Portal Jockey (25H)"},
        {id = 4619, name = "Neck-Deep in Vile (25H)"},
    },
    ICC25N = {
        {id = 4532, name = "Fall of the Lich King (25)"},
        {id = 4530, name = "The Frostwing Halls (25)"},
        {id = 4528, name = "The Crimson Hall (25)"},
    },
    ICC10H = {
        {id = 4583, name = "The Frozen Throne (10H)"},
        {id = 4601, name = "Been Waiting a Long Time (10H)"},
    },
    ICC10N = {
        {id = 4531, name = "Fall of the Lich King (10)"},
        {id = 4529, name = "The Frostwing Halls (10)"},
    },
    RS25H = {
        {id = 4817, name = "Heroic: Halion (25H)"},
    },
    RS25N = {
        {id = 4818, name = "The Twilight Destroyer (25)"},
    },
    RS10H = {
        {id = 4816, name = "Heroic: Halion (10H)"},
    },
    RS10N = {
        {id = 4815, name = "The Twilight Destroyer (10)"},
    },
    TOC25 = {
        {id = 3917, name = "Call of the Grand Crusade (25)"},
        {id = 3916, name = "Call of the Crusade (25)"},
    },
    TOC10 = {
        {id = 3918, name = "Call of the Grand Crusade (10)"},
        {id = 3808, name = "A Tribute to Skill (10)"},
    },
    ULDUAR25 = {
        {id = 2958, name = "Glory of the Ulduar Raider (25)"},
        {id = 2895, name = "The Secrets of Ulduar (25)"},
    },
    ULDUAR10 = {
        {id = 2957, name = "Glory of the Ulduar Raider (10)"},
        {id = 2894, name = "The Secrets of Ulduar (10)"},
    },
    NAXX25 = {
        {id = 2137, name = "Glory of the Raider (25)"},
        {id = 1658, name = "The Fall of Naxxramas (25)"},
    },
    NAXX10 = {
        {id = 2136, name = "Glory of the Raider (10)"},
        {id = 1657, name = "The Fall of Naxxramas (10)"},
    },
    VOA25 = {
        {id = 4017, name = "Earth, Wind & Fire (25)"},
    },
    VOA10 = {
        {id = 4016, name = "Earth, Wind & Fire (10)"},
    },
}

-- Template defaults for raids (used by Add Group popup)
-- mdps = melee DPS, rdps = ranged DPS
GUI.RaidTemplateDefaults = {
    -- ICC (Icecrown Citadel)
    ICC25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5800, ilvl = 264},
    ICC25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5400, ilvl = 251},
    ICC10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5600, ilvl = 251},
    ICC10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5000, ilvl = 232},
    -- RS (Ruby Sanctum)
    RS25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5900, ilvl = 264},
    RS25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5600, ilvl = 258},
    RS10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5700, ilvl = 258},
    RS10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5300, ilvl = 245},
    -- TOC/TOGC (Trial of the Crusader)
    TOC25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5000, ilvl = 232},
    TOC10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4600, ilvl = 219},
    TOGC25 = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5400, ilvl = 245},
    TOGC10 = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 5000, ilvl = 232},
    -- VOA (Vault of Archavon)
    VOA25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5500, ilvl = 251},
    VOA25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4800, ilvl = 226},
    VOA10H = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 5200, ilvl = 245},
    VOA10N = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 4400, ilvl = 213},
    -- Ulduar
    ULDUAR25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4800, ilvl = 232},
    ULDUAR25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4400, ilvl = 219},
    ULDUAR10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4400, ilvl = 219},
    ULDUAR10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4000, ilvl = 200},
    -- Naxx
    NAXX25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4000, ilvl = 213},
    NAXX25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 3600, ilvl = 200},
    NAXX10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 3600, ilvl = 200},
    NAXX10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 3200, ilvl = 187},
    -- EoE (Eye of Eternity)
    EoE25H = {tanks = 1, healers = 6, mdps = 9, rdps = 9, gs = 4600, ilvl = 226},
    EoE25N = {tanks = 1, healers = 6, mdps = 9, rdps = 9, gs = 4200, ilvl = 213},
    EoE10H = {tanks = 1, healers = 3, mdps = 3, rdps = 3, gs = 4200, ilvl = 213},
    EoE10N = {tanks = 1, healers = 3, mdps = 3, rdps = 3, gs = 3800, ilvl = 200},
    -- OS (Obsidian Sanctum)
    OS25H = {tanks = 3, healers = 6, mdps = 8, rdps = 8, gs = 4600, ilvl = 226},
    OS25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4000, ilvl = 200},
    OS10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4200, ilvl = 213},
    OS10N = {tanks = 2, healers = 2, mdps = 3, rdps = 3, gs = 3600, ilvl = 187},
    -- Onyxia
    Ony25H = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 5000, ilvl = 232},
    Ony25N = {tanks = 2, healers = 6, mdps = 8, rdps = 9, gs = 4600, ilvl = 219},
    Ony10H = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4600, ilvl = 219},
    Ony10N = {tanks = 2, healers = 3, mdps = 2, rdps = 3, gs = 4200, ilvl = 200},
    -- WotLK Heroic Dungeons
    HEROIC5 = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 3200, ilvl = 180},
    -- ICC 5-man Heroics
    FoS5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4200, ilvl = 200},
    PoS5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4600, ilvl = 213},
    HoR5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 5000, ilvl = 219},
    ToC5H = {tanks = 1, healers = 1, mdps = 1, rdps = 2, gs = 4200, ilvl = 200},
    -- Custom (no requirements)
    CUSTOM = {tanks = 0, healers = 0, mdps = 0, rdps = 0, gs = 0, ilvl = 0},
}

-- Valid sizes for each raid/dungeon type
-- Format: {sizes = {list}, defaultSize = "X", hasHeroic = bool}
GUI.RaidSizeInfo = {
    -- WotLK Raids (10/25)
    ICC = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    RS = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    TOC = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    VOA = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    ULDUAR = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    NAXX = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    EoE = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    OS = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = true},
    Ony = {sizes = {"10", "25"}, defaultSize = "25", hasHeroic = false},
    -- WotLK Dungeons (5-man only)
    FoS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    PoS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    HoR = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    ToC5 = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    HEROIC = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    -- TBC Raids
    SWP = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    BT = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    HYJAL = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    TK = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    SSC = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    GRUUL = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    MAG = {sizes = {"25"}, defaultSize = "25", hasHeroic = false},
    KARA = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    ZA = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    -- TBC Dungeons (5-man)
    MGT = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    SH = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    SLABS = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    ARCA = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    MECH = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    BOT = {sizes = {"5"}, defaultSize = "5", hasHeroic = true},
    -- Classic Raids
    MC = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    BWL = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    AQ40 = {sizes = {"40"}, defaultSize = "40", hasHeroic = false},
    AQ20 = {sizes = {"20"}, defaultSize = "20", hasHeroic = false},
    ZG = {sizes = {"20"}, defaultSize = "20", hasHeroic = false},
    -- Classic Dungeons
    UBRS = {sizes = {"10"}, defaultSize = "10", hasHeroic = false},
    LBRS = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    STRAT = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    SCHOLO = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    BRD = {sizes = {"5"}, defaultSize = "5", hasHeroic = false},
    -- Custom
    CUSTOM = {sizes = {"5", "10", "20", "25", "40"}, defaultSize = "25", hasHeroic = false},
}

-- Raid categories for dropdown organization (with submenu support)
GUI.RaidCategories = {
    {id = "WOTLK_RAID", header = "WotLK Raids", items = {"ICC", "RS", "TOC", "VOA", "ULDUAR", "NAXX", "EoE", "OS", "Ony"}},
    {id = "WOTLK_DUNG", header = "WotLK Dungeons", items = {"FoS", "PoS", "HoR", "ToC5", "HEROIC"}},
    {id = "TBC_RAID", header = "TBC Raids", items = {"SWP", "BT", "HYJAL", "TK", "SSC", "GRUUL", "MAG", "KARA", "ZA"}},
    {id = "TBC_DUNG", header = "TBC Dungeons", items = {"MGT", "SH", "SLABS", "ARCA", "MECH", "BOT"}},
    {id = "CLASSIC_RAID", header = "Classic Raids", items = {"MC", "BWL", "AQ40", "AQ20", "ZG"}},
    {id = "CLASSIC_DUNG", header = "Classic Dungeons", items = {"UBRS", "LBRS", "STRAT", "SCHOLO", "BRD"}},
    {id = "OTHER", header = "Other", items = {"CUSTOM"}},
}

-- Class/spec options for recruitment
-- melee = true for melee DPS specs, false/nil for ranged
GUI.ClassSpecs = {
    TANK = {
        {class = "WARRIOR", spec = "Protection", icon = "Interface\\Icons\\Ability_Warrior_DefensiveStance"},
        {class = "PALADIN", spec = "Protection", icon = "Interface\\Icons\\Spell_Holy_DevotionAura"},
        {class = "DEATHKNIGHT", spec = "Blood", icon = "Interface\\Icons\\Spell_Deathknight_BloodPresence"},
        {class = "DRUID", spec = "Feral (Bear)", icon = "Interface\\Icons\\Ability_Racial_BearForm"},
    },
    HEALER = {
        {class = "PRIEST", spec = "Holy", icon = "Interface\\Icons\\Spell_Holy_GuardianSpirit"},
        {class = "PRIEST", spec = "Discipline", icon = "Interface\\Icons\\Spell_Holy_PowerWordShield"},
        {class = "PALADIN", spec = "Holy", icon = "Interface\\Icons\\Spell_Holy_HolyBolt"},
        {class = "DRUID", spec = "Restoration", icon = "Interface\\Icons\\Spell_Nature_HealingTouch"},
        {class = "SHAMAN", spec = "Restoration", icon = "Interface\\Icons\\Spell_Nature_MagicImmunity"},
    },
    DPS = {
        -- Melee DPS
        {class = "WARRIOR", spec = "Arms/Fury", icon = "Interface\\Icons\\Ability_Warrior_BattleShout", melee = true},
        {class = "PALADIN", spec = "Retribution", icon = "Interface\\Icons\\Spell_Holy_AuraOfLight", melee = true},
        {class = "DEATHKNIGHT", spec = "Frost/Unholy", icon = "Interface\\Icons\\Spell_Deathknight_FrostPresence", melee = true},
        {class = "ROGUE", spec = "All", icon = "Interface\\Icons\\Ability_BackStab", melee = true},
        {class = "DRUID", spec = "Feral (Cat)", icon = "Interface\\Icons\\Ability_Druid_CatForm", melee = true},
        {class = "SHAMAN", spec = "Enhancement", icon = "Interface\\Icons\\Spell_Nature_LightningShield", melee = true},
        -- Ranged DPS
        {class = "MAGE", spec = "All", icon = "Interface\\Icons\\Spell_Holy_MagicalSentry", melee = false},
        {class = "WARLOCK", spec = "All", icon = "Interface\\Icons\\Spell_Shadow_DeathCoil", melee = false},
        {class = "HUNTER", spec = "All", icon = "Interface\\Icons\\Ability_Hunter_SteadyShot", melee = false},
        {class = "DRUID", spec = "Balance", icon = "Interface\\Icons\\Spell_Nature_Starfall", melee = false},
        {class = "SHAMAN", spec = "Elemental", icon = "Interface\\Icons\\Spell_Nature_Lightning", melee = false},
        {class = "PRIEST", spec = "Shadow", icon = "Interface\\Icons\\Spell_Shadow_ShadowWordPain", melee = false},
    },
}

function GUI.CreateAddGroupPopup()
    local popup = CreateFrame("Frame", "AIPAddGroupPopup", UIParent)
    popup:SetSize(400, 620)  -- Increased height for reserved items section
    popup:SetPoint("CENTER", -220, 0)  -- Offset left so it doesn't overlap with Enroll popup
    popup:SetFrameStrata("DIALOG")
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
        insets = {left = 8, right = 8, top = 8, bottom = 8}
    })

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Create New Group Listing")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local y = -45

    -- === Raid Selection Row ===
    local raidLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidLabel:SetPoint("TOPLEFT", 20, y)
    raidLabel:SetText("Raid:")

    -- Raid Type dropdown
    local raidTypeDropdown = CreateFrame("Frame", "AIPAddGroupRaidType", popup, "UIDropDownMenuTemplate")
    raidTypeDropdown:SetPoint("LEFT", raidLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(raidTypeDropdown, 100)
    UIDropDownMenu_SetText(raidTypeDropdown, "ICC")
    popup.raidType = "ICC"

    -- Size dropdown (10/25)
    local sizeDropdown = CreateFrame("Frame", "AIPAddGroupSize", popup, "UIDropDownMenuTemplate")
    sizeDropdown:SetPoint("LEFT", raidTypeDropdown, "RIGHT", -15, 0)
    UIDropDownMenu_SetWidth(sizeDropdown, 50)
    UIDropDownMenu_SetText(sizeDropdown, "25")
    popup.raidSize = "25"

    -- Heroic checkbox
    local heroicCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    heroicCheck:SetSize(22, 22)
    heroicCheck:SetPoint("LEFT", sizeDropdown, "RIGHT", 5, 2)
    heroicCheck:SetChecked(true)
    popup.heroicCheck = heroicCheck
    local heroicLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroicLabel:SetPoint("LEFT", heroicCheck, "RIGHT", 0, 0)
    heroicLabel:SetText("Heroic")

    -- Helper to build raid key
    local function GetRaidKey()
        local raidType = popup.raidType or "ICC"
        -- Handle custom text
        if raidType == "CUSTOM" then
            local customText = popup.customInput and popup.customInput:GetText() or ""
            if customText ~= "" then
                return customText
            end
            return "Custom"
        end
        local size = popup.raidSize or "25"
        local heroic = popup.heroicCheck:GetChecked() and "H" or "N"
        -- Handle TOC/TOGC naming
        if raidType == "TOC" and heroic == "H" then
            return "TOGC" .. size
        end
        return raidType .. size .. heroic
    end

    -- Apply template defaults when raid changes
    local function ApplyTemplateDefaults()
        local raidKey = GetRaidKey()
        local defaults = GUI.RaidTemplateDefaults[raidKey]
        if defaults then
            popup.tankInput:SetText(tostring(defaults.tanks))
            popup.healInput:SetText(tostring(defaults.healers))
            -- Handle mdps/rdps (with backwards compat for old dps field)
            local mdps = defaults.mdps or math.floor((defaults.dps or 0) / 2)
            local rdps = defaults.rdps or math.ceil((defaults.dps or 0) / 2)
            popup.mdpsInput:SetText(tostring(mdps))
            popup.rdpsInput:SetText(tostring(rdps))
            popup.gsInput:SetText(tostring(defaults.gs))
            popup.ilvlInput:SetText(tostring(defaults.ilvl))
        end
        -- Update achievement dropdown
        GUI.UpdateAchievementDropdown(popup, raidKey)
        popup.selectedRaid = raidKey
    end

    -- Function to update size dropdown based on selected raid
    local function UpdateSizeDropdown()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType]
        if raidInfo then
            -- Set default size for this raid if current size is not valid
            local currentSizeValid = false
            for _, validSize in ipairs(raidInfo.sizes) do
                if validSize == popup.raidSize then
                    currentSizeValid = true
                    break
                end
            end
            if not currentSizeValid then
                popup.raidSize = raidInfo.defaultSize
                UIDropDownMenu_SetText(sizeDropdown, raidInfo.defaultSize)
            end
            -- Update heroic checkbox visibility
            if raidInfo.hasHeroic then
                heroicCheck:Show()
                heroicLabel:Show()
            else
                heroicCheck:Hide()
                heroicLabel:Hide()
                heroicCheck:SetChecked(false)
            end
            -- Enable/disable size dropdown based on available sizes
            if #raidInfo.sizes == 1 then
                UIDropDownMenu_DisableDropDown(sizeDropdown)
            else
                UIDropDownMenu_EnableDropDown(sizeDropdown)
            end
        end
    end
    popup.UpdateSizeDropdown = UpdateSizeDropdown

    -- Helper to update raid dropdown text with lockout color
    local function UpdateRaidDropdownText()
        local raidType = popup.raidType or "ICC"
        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(raidType)
        if isLocked then
            UIDropDownMenu_SetText(raidTypeDropdown, "|cFFFF6666" .. raidType .. "|r")
        else
            UIDropDownMenu_SetText(raidTypeDropdown, raidType)
        end
    end
    popup.UpdateRaidDropdownText = UpdateRaidDropdownText

    -- Initialize raid type dropdown with nested submenus
    UIDropDownMenu_Initialize(raidTypeDropdown, function(self, level, menuList)
        level = level or 1

        if level == 1 then
            -- Main level: show categories with arrows
            for _, cat in ipairs(GUI.RaidCategories) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cat.header
                info.hasArrow = true
                info.menuList = cat.id
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 then
            -- Submenu: show raids in category
            for _, cat in ipairs(GUI.RaidCategories) do
                if cat.id == menuList then
                    for _, rt in ipairs(cat.items) do
                        local info = UIDropDownMenu_CreateInfo()
                        -- Show lockout indicator (red text, no label)
                        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(rt)
                        if isLocked then
                            info.text = "|cFFFF6666" .. rt .. "|r"
                        else
                            info.text = rt
                        end
                        info.value = rt
                        info.func = function()
                            popup.raidType = rt
                            UpdateRaidDropdownText()
                            UpdateSizeDropdown()
                            ApplyTemplateDefaults()
                            CloseDropDownMenus()
                        end
                        info.checked = (popup.raidType == rt)
                        UIDropDownMenu_AddButton(info, level)
                    end
                    break
                end
            end
        end
    end)

    -- Initialize size dropdown (will be dynamically updated)
    UIDropDownMenu_Initialize(sizeDropdown, function()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
        for _, size in ipairs(raidInfo.sizes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = size .. " players"
            info.value = size
            info.func = function()
                popup.raidSize = size
                UIDropDownMenu_SetText(sizeDropdown, size)
                ApplyTemplateDefaults()
            end
            info.checked = (popup.raidSize == size)
            UIDropDownMenu_AddButton(info)
        end
    end)
    GUI.FixDropdownStrata(raidTypeDropdown)
    GUI.FixDropdownStrata(sizeDropdown)

    -- Apply initial size dropdown update
    UpdateSizeDropdown()
    UpdateRaidDropdownText()  -- Apply initial lockout color

    heroicCheck:SetScript("OnClick", function() ApplyTemplateDefaults() end)
    y = y - 35

    -- === Custom Text Input (shown only when CUSTOM is selected) ===
    local customLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", 20, y)
    customLabel:SetText("Custom Name:")
    customLabel:Hide()
    popup.customLabel = customLabel

    local customInput, customContainer = GUI.CreateStyledEditBox(popup, 180, 16, false)
    customContainer:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
    customContainer:Hide()
    popup.customInput = customInput
    popup.customContainer = customContainer

    -- Update custom field visibility
    local function UpdateCustomFieldVisibility()
        if popup.raidType == "CUSTOM" then
            popup.customLabel:Show()
            if popup.customContainer then popup.customContainer:Show() end
            popup.heroicCheck:Hide()
            heroicLabel:Hide()
        else
            popup.customLabel:Hide()
            if popup.customContainer then popup.customContainer:Hide() end
            popup.heroicCheck:Show()
            heroicLabel:Show()
        end
    end
    popup.UpdateCustomFieldVisibility = UpdateCustomFieldVisibility

    -- Lockout warning indicator (red dot instead of text label)
    local lockoutWarning = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockoutWarning:SetPoint("LEFT", heroicLabel, "RIGHT", 10, 0)
    lockoutWarning:SetText("|cFFFF4444\226\151\143|r")  -- Red circle indicator
    lockoutWarning:Hide()
    popup.lockoutWarning = lockoutWarning

    -- Update lockout warning based on selected raid
    local function UpdateLockoutWarning()
        local raidKey = GetRaidKey()
        if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance then
            -- Refresh saved instances
            AIP.TreeBrowser.UpdateSavedInstances()
            local isLocked = AIP.TreeBrowser.IsLockedToInstance(raidKey)
            if isLocked then
                lockoutWarning:Show()
            else
                lockoutWarning:Hide()
            end
        else
            lockoutWarning:Hide()
        end
    end
    popup.UpdateLockoutWarning = UpdateLockoutWarning

    -- Hook into raid type selection
    local origApplyDefaults = ApplyTemplateDefaults
    ApplyTemplateDefaults = function()
        origApplyDefaults()
        UpdateCustomFieldVisibility()
        UpdateLockoutWarning()
    end

    y = y - 25

    -- === Composition Row ===
    local compLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    compLabel:SetPoint("TOPLEFT", 20, y)
    compLabel:SetText("Composition:")
    y = y - 20

    local tankLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankLabel:SetPoint("TOPLEFT", 30, y)
    tankLabel:SetText("Tanks:")
    tankLabel:SetTextColor(0.5, 0.5, 1)
    local tankInput, tankContainer = GUI.CreateStyledEditBox(popup, 30, 14, true)
    tankContainer:SetPoint("LEFT", tankLabel, "RIGHT", 5, 0)
    tankInput:SetText("2")
    popup.tankInput = tankInput

    local healLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    healLabel:SetPoint("LEFT", tankContainer, "RIGHT", 10, 0)
    healLabel:SetText("Healers:")
    healLabel:SetTextColor(0.5, 1, 0.5)
    local healInput, healContainer = GUI.CreateStyledEditBox(popup, 30, 14, true)
    healContainer:SetPoint("LEFT", healLabel, "RIGHT", 5, 0)
    healInput:SetText("6")
    popup.healInput = healInput

    local mdpsLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mdpsLabel:SetPoint("LEFT", healContainer, "RIGHT", 10, 0)
    mdpsLabel:SetText("MDPS:")
    mdpsLabel:SetTextColor(1, 0.5, 0)  -- Orange for melee
    local mdpsInput, mdpsContainer = GUI.CreateStyledEditBox(popup, 25, 14, true)
    mdpsContainer:SetPoint("LEFT", mdpsLabel, "RIGHT", 3, 0)
    mdpsInput:SetText("8")
    popup.mdpsInput = mdpsInput

    local rdpsLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rdpsLabel:SetPoint("LEFT", mdpsContainer, "RIGHT", 8, 0)
    rdpsLabel:SetText("RDPS:")
    rdpsLabel:SetTextColor(1, 0.8, 0)  -- Yellow for ranged
    local rdpsInput, rdpsContainer = GUI.CreateStyledEditBox(popup, 25, 14, true)
    rdpsContainer:SetPoint("LEFT", rdpsLabel, "RIGHT", 3, 0)
    rdpsInput:SetText("9")
    popup.rdpsInput = rdpsInput
    y = y - 28

    -- === Requirements Row ===
    local reqLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reqLabel:SetPoint("TOPLEFT", 20, y)
    reqLabel:SetText("Requirements:")
    y = y - 20

    local gsLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gsLabel:SetPoint("TOPLEFT", 30, y)
    gsLabel:SetText("Min GS:")
    local gsInput, gsContainer = GUI.CreateStyledEditBox(popup, 45, 14, true)
    gsContainer:SetPoint("LEFT", gsLabel, "RIGHT", 5, 0)
    gsInput:SetText("5800")
    popup.gsInput = gsInput

    local ilvlLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlLabel:SetPoint("LEFT", gsContainer, "RIGHT", 15, 0)
    ilvlLabel:SetText("Min iLvl:")
    local ilvlInput, ilvlContainer = GUI.CreateStyledEditBox(popup, 35, 14, true)
    ilvlContainer:SetPoint("LEFT", ilvlLabel, "RIGHT", 5, 0)
    ilvlInput:SetText("264")
    popup.ilvlInput = ilvlInput
    y = y - 28

    -- === Achievement Row ===
    local achieveLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    achieveLabel:SetPoint("TOPLEFT", 30, y)
    achieveLabel:SetText("Require Achievement:")

    local achieveDropdown = CreateFrame("Frame", "AIPAddGroupAchieve", popup, "UIDropDownMenuTemplate")
    achieveDropdown:SetPoint("LEFT", achieveLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(achieveDropdown, 180)
    UIDropDownMenu_SetText(achieveDropdown, "None")
    popup.achieveDropdown = achieveDropdown
    popup.selectedAchievement = nil
    GUI.FixDropdownStrata(achieveDropdown)
    y = y - 35

    -- === Class/Spec Selection ===
    local classLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classLabel:SetPoint("TOPLEFT", 20, y)
    classLabel:SetText("Looking For Classes:")
    y = y - 18

    popup.classChecks = {}

    -- Tank classes (4 specs)
    local tankClassLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tankClassLabel:SetPoint("TOPLEFT", 25, y)
    tankClassLabel:SetText("Tanks:")
    tankClassLabel:SetTextColor(0.5, 0.5, 1)
    popup.classChecks.TANK = {}
    local tankX = 80
    local specSpacing = 55  -- Increased spacing to fit icons properly
    for _, spec in ipairs(GUI.ClassSpecs.TANK) do
        local check = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", tankX, y + 2)
        check:SetChecked(true)
        local icon = check:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", check, "RIGHT", -2, 0)
        icon:SetTexture(spec.icon)
        check.specData = spec
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(spec.class .. " - " .. spec.spec)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        popup.classChecks.TANK[spec.class .. spec.spec] = check
        tankX = tankX + specSpacing
    end
    y = y - 26

    -- Healer classes (5 specs)
    local healClassLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    healClassLabel:SetPoint("TOPLEFT", 25, y)
    healClassLabel:SetText("Heals:")
    healClassLabel:SetTextColor(0.5, 1, 0.5)
    popup.classChecks.HEALER = {}
    local healX = 80
    for _, spec in ipairs(GUI.ClassSpecs.HEALER) do
        local check = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", healX, y + 2)
        check:SetChecked(true)
        local icon = check:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", check, "RIGHT", -2, 0)
        icon:SetTexture(spec.icon)
        check.specData = spec
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(spec.class .. " - " .. spec.spec)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        popup.classChecks.HEALER[spec.class .. spec.spec] = check
        healX = healX + specSpacing
    end
    y = y - 26

    -- DPS classes (12 specs, split into rows of 5)
    local dpsClassLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dpsClassLabel:SetPoint("TOPLEFT", 25, y)
    dpsClassLabel:SetText("DPS:")
    dpsClassLabel:SetTextColor(1, 0.5, 0.5)
    popup.classChecks.DPS = {}
    local dpsX = 80
    local dpsCount = 0
    local specsPerRow = 5
    for _, spec in ipairs(GUI.ClassSpecs.DPS) do
        -- Start new row every 5 specs
        if dpsCount > 0 and dpsCount % specsPerRow == 0 then
            y = y - 26
            dpsX = 80
        end
        local check = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        check:SetSize(20, 20)
        check:SetPoint("TOPLEFT", dpsX, y + 2)
        check:SetChecked(true)
        local icon = check:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", check, "RIGHT", -2, 0)
        icon:SetTexture(spec.icon)
        check.specData = spec
        check:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(spec.class .. " - " .. spec.spec)
            GameTooltip:Show()
        end)
        check:SetScript("OnLeave", function() GameTooltip:Hide() end)
        popup.classChecks.DPS[spec.class .. spec.spec] = check
        dpsX = dpsX + specSpacing
        dpsCount = dpsCount + 1
    end
    y = y - 32

    -- === Note Row ===
    local noteLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", 20, y)
    noteLabel:SetText("Note:")
    local noteInput, noteContainer = GUI.CreateStyledEditBox(popup, 300, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 5, 0)
    popup.noteInput = noteInput
    y = y - 30

    -- === Auto-Invite Keyword Row ===
    local keywordLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keywordLabel:SetPoint("TOPLEFT", 20, y)
    keywordLabel:SetText("Invite Keyword:")
    keywordLabel:SetTextColor(0.4, 0.8, 1)
    local keywordInput, keywordContainer = GUI.CreateStyledEditBox(popup, 110, 18, false)
    keywordContainer:SetPoint("LEFT", keywordLabel, "RIGHT", 5, 0)
    keywordInput:SetText(AIP.db and AIP.db.triggers or "invme-auto")
    popup.keywordInput = keywordInput

    local keywordHint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    keywordHint:SetPoint("LEFT", keywordContainer, "RIGHT", 5, 0)
    keywordHint:SetText("(whisper to join)")
    keywordHint:SetTextColor(0.5, 0.5, 0.5)
    y = y - 30

    -- === Broadcast checkbox ===
    local broadcastCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    broadcastCheck:SetSize(22, 22)
    broadcastCheck:SetPoint("TOPLEFT", 20, y)
    broadcastCheck:SetChecked(true)
    popup.broadcastCheck = broadcastCheck
    local broadcastLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    broadcastLabel:SetPoint("LEFT", broadcastCheck, "RIGHT", 2, 0)
    broadcastLabel:SetText("Broadcast to chat channels")
    y = y - 28

    -- === Reserved Items Section (read-only display from DB) ===
    local reservedLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    reservedLabel:SetPoint("TOPLEFT", 20, y)
    reservedLabel:SetText("Reserved Items:")
    reservedLabel:SetTextColor(1, 0.5, 0)  -- Orange

    local reservedEditHint = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reservedEditHint:SetPoint("LEFT", reservedLabel, "RIGHT", 10, 0)
    reservedEditHint:SetText("|cFF888888(edit in Raid Mgmt tab)|r")
    y = y - 18

    -- Reserved Items display (read-only)
    local reservedFrame = CreateFrame("Frame", nil, popup)
    reservedFrame:SetSize(350, 50)
    reservedFrame:SetPoint("TOPLEFT", 20, y)
    GUI.ApplyBackdrop(reservedFrame, "Inset", 0.9)

    local reservedDisplay = reservedFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    reservedDisplay:SetPoint("TOPLEFT", 8, -8)
    reservedDisplay:SetPoint("BOTTOMRIGHT", -8, 8)
    reservedDisplay:SetJustifyH("LEFT")
    reservedDisplay:SetJustifyV("TOP")
    reservedDisplay:SetText("|cFF666666(none)|r")
    popup.reservedDisplay = reservedDisplay

    y = y - 58

    -- === Buttons ===
    local createBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    createBtn:SetSize(90, 24)
    createBtn:SetPoint("BOTTOMLEFT", 100, 40)
    createBtn:SetText("Create")
    createBtn:SetScript("OnClick", function()
        local raidKey = GetRaidKey()
        if not raidKey then
            AIP.Print("Please configure raid settings")
            return
        end

        -- Get the invite keyword
        local inviteKeyword = popup.keywordInput:GetText()
        if not inviteKeyword or inviteKeyword == "" then
            inviteKeyword = AIP.db and AIP.db.triggers or "invme-auto"
        end

        -- Build LFM message
        local achieveLink = ""
        if popup.selectedAchievement then
            achieveLink = GetAchievementLink(popup.selectedAchievement) or ""
        end

        -- Include keyword hint in the broadcast message
        local noteText = popup.noteInput:GetText() or ""
        local keywordHint = string.format('w/ "%s"', inviteKeyword)

        -- Get GS and iLvl without rounding
        local gsValue = tonumber(popup.gsInput:GetText()) or 5500
        local ilvlValue = tonumber(popup.ilvlInput:GetText()) or 0

        -- Build "LF:" class/spec list based on CHECKED specs (what we're looking for)
        -- Ultra-short 2-3 letter codes for compact display
        local specCodes = {
            -- Tanks: class initial + spec initial
            WARRIOR_Protection = "PW",      -- Prot Warrior
            PALADIN_Protection = "PP",      -- Prot Paladin
            DEATHKNIGHT_Blood = "BDK",      -- Blood DK
            DRUID_FeralBear = "BD",         -- Bear Druid
            -- Healers
            PRIEST_Holy = "HP",             -- Holy Priest
            PRIEST_Discipline = "DP",       -- Disc Priest
            PALADIN_Holy = "HPal",          -- Holy Paladin
            DRUID_Restoration = "RD",       -- Resto Druid
            SHAMAN_Restoration = "RS",      -- Resto Shaman
            -- Melee DPS
            WARRIOR_Arms = "AW",            -- Arms Warrior
            PALADIN_Retribution = "Ret",    -- Ret Paladin
            DEATHKNIGHT_Frost = "FDK",      -- Frost DK
            ROGUE_All = "Rog",              -- Rogue
            DRUID_FeralCat = "FD",          -- Feral Druid (cat)
            SHAMAN_Enhancement = "Enh",     -- Enh Shaman
            -- Ranged DPS
            MAGE_All = "Mag",               -- Mage
            WARLOCK_All = "Loc",            -- Warlock
            HUNTER_All = "Hun",             -- Hunter
            DRUID_Balance = "Boom",         -- Boomkin
            SHAMAN_Elemental = "Ele",       -- Ele Shaman
            PRIEST_Shadow = "SP",           -- Shadow Priest
        }
        -- Map specData to code key
        local function getSpecCodeKey(specData)
            local specKey = specData.spec:gsub("%s+", ""):gsub("[%(%)/-]", "")
            return specData.class .. "_" .. specKey
        end

        -- Organize by role for array format [T:PP,BDK H:HP,RD M:AW,Ret R:Mag,Hun]
        local roleSpecs = {TANK = {}, HEALER = {}, MDPS = {}, RDPS = {}}
        local lookingForSpecs = {}  -- For backwards compat

        if popup.classChecks then
            for role, roleChecks in pairs(popup.classChecks) do
                for specKey, check in pairs(roleChecks) do
                    if check:GetChecked() and check.specData then
                        local codeKey = getSpecCodeKey(check.specData)
                        local code = specCodes[codeKey] or (check.specData.class:sub(1,1) .. check.specData.spec:sub(1,1))

                        -- Determine target role
                        local targetRole = role
                        if role == "DPS" then
                            targetRole = check.specData.melee and "MDPS" or "RDPS"
                        end

                        -- Avoid duplicates per role
                        local found = false
                        for _, existing in ipairs(roleSpecs[targetRole] or {}) do
                            if existing == code then found = true break end
                        end
                        if not found then
                            roleSpecs[targetRole] = roleSpecs[targetRole] or {}
                            table.insert(roleSpecs[targetRole], code)
                            table.insert(lookingForSpecs, code)
                        end
                    end
                end
            end
        end

        -- Build the LF array string: [T:PP,BDK H:HP,RD M:AW R:Mag]
        local lfParts = {}
        if #(roleSpecs.TANK or {}) > 0 then
            table.insert(lfParts, "T:" .. table.concat(roleSpecs.TANK, ","))
        end
        if #(roleSpecs.HEALER or {}) > 0 then
            table.insert(lfParts, "H:" .. table.concat(roleSpecs.HEALER, ","))
        end
        if #(roleSpecs.MDPS or {}) > 0 then
            table.insert(lfParts, "M:" .. table.concat(roleSpecs.MDPS, ","))
        end
        if #(roleSpecs.RDPS or {}) > 0 then
            table.insert(lfParts, "R:" .. table.concat(roleSpecs.RDPS, ","))
        end

        local lfClassStr = ""
        if #lfParts > 0 then
            lfClassStr = "[" .. table.concat(lfParts, " ") .. "] "
        end

        -- Build message with GS value (not rounded) and iLvl
        local gsDisplay = tostring(gsValue) .. "+"
        local ilvlDisplay = ilvlValue > 0 and (" iLvl:" .. tostring(ilvlValue) .. "+") or ""
        local mdpsNeeded = tonumber(popup.mdpsInput:GetText()) or 8
        local rdpsNeeded = tonumber(popup.rdpsInput:GetText()) or 9

        -- Calculate total slots
        local tanksNeeded = tonumber(popup.tankInput:GetText()) or 2
        local healersNeeded = tonumber(popup.healInput:GetText()) or 6
        local totalNeeded = tanksNeeded + healersNeeded + mdpsNeeded + rdpsNeeded
        local totalFilled = 0  -- Start with 0, will be updated when members join

        local msg = string.format("LFM %s [%d/%d] [T:0/%d H:0/%d M:0/%d R:0/%d] %s%s %s%s %s %s",
            raidKey,
            totalFilled, totalNeeded,
            tanksNeeded,
            healersNeeded,
            mdpsNeeded,
            rdpsNeeded,
            gsDisplay,
            ilvlDisplay,
            lfClassStr,
            keywordHint,
            achieveLink,
            noteText)

        -- Store selected classes for the group data
        local selectedClasses = {TANK = {}, HEALER = {}, MDPS = {}, RDPS = {}}
        if popup.classChecks then
            for role, roleChecks in pairs(popup.classChecks) do
                -- Map DPS to MDPS/RDPS based on spec
                local targetRole = role
                if role == "DPS" then
                    targetRole = "MDPS"  -- Default, will be refined
                end
                for specKey, check in pairs(roleChecks) do
                    if check:GetChecked() and check.specData then
                        -- Determine if melee or ranged
                        local isMelee = check.specData.melee
                        if role == "DPS" then
                            targetRole = isMelee and "MDPS" or "RDPS"
                        end
                        selectedClasses[targetRole] = selectedClasses[targetRole] or {}
                        table.insert(selectedClasses[targetRole], {
                            class = check.specData.class,
                            spec = check.specData.spec,
                        })
                    end
                end
            end
        end

        -- Get reserved items from DB (editing happens in Raid Mgmt tab)
        local reservedItems = AIP.db and AIP.db.reservedItems or ""
        -- Format reserved items for message (replace newlines with commas)
        local reservedItemsMsg = ""
        if reservedItems and reservedItems ~= "" then
            local itemList = reservedItems:gsub("\n", ", "):gsub(", $", "")
            if itemList ~= "" then
                reservedItemsMsg = " [Res: " .. itemList .. "]"
            end
        end

        -- Add reserved items to the message if present
        if reservedItemsMsg ~= "" then
            msg = msg .. reservedItemsMsg
        end

        -- Get loot ban data from DB (managed in Raid Mgmt tab)
        local lootBans = AIP.db and AIP.db.lootBans or {}

        if AIP.GroupTracker and AIP.GroupTracker.AddGroup then
            AIP.GroupTracker.AddGroup({
                leader = UnitName("player"),
                raid = raidKey,
                message = msg,
                gsMin = gsValue,
                ilvlMin = ilvlValue,
                tanks = {current = 0, needed = tonumber(popup.tankInput:GetText()) or 2},
                healers = {current = 0, needed = tonumber(popup.healInput:GetText()) or 6},
                mdps = {current = 0, needed = mdpsNeeded},
                rdps = {current = 0, needed = rdpsNeeded},
                achievementId = popup.selectedAchievement,
                inviteKeyword = inviteKeyword,  -- Store the keyword for Quick Req
                selectedClasses = selectedClasses,  -- Store class preferences
                lookingForSpecs = lookingForSpecs,  -- Store for message regeneration (class/spec short names)
                roleSpecs = roleSpecs,  -- Store organized by role: {TANK={codes}, HEALER={codes}, ...}
                note = noteText,  -- Store note for message regeneration
                reservedItems = reservedItems,  -- Store reserved items
                lootBans = lootBans,  -- Store loot bans (from DB)
                isOwn = true,
                time = time(),
            })
        end

        -- Store our active LFM data for matching incoming LFG players
        GUI.MyGroup = {
            raid = raidKey,
            gsMin = gsValue,
            ilvlMin = ilvlValue,
            tanks = {current = 0, needed = tonumber(popup.tankInput:GetText()) or 2},
            healers = {current = 0, needed = tonumber(popup.healInput:GetText()) or 6},
            mdps = {current = 0, needed = mdpsNeeded},
            rdps = {current = 0, needed = rdpsNeeded},
            inviteKeyword = inviteKeyword,
            selectedClasses = selectedClasses,
            roleSpecs = roleSpecs,  -- Store organized by role
            time = time(),
        }

        -- Set player mode to LFM
        if AIP.SetPlayerMode then
            AIP.SetPlayerMode("lfm")
        end

        if popup.broadcastCheck:GetChecked() then
            -- Store message and start auto-broadcast
            AIP.db.spamMessage = msg
            GUI.StartBroadcast("lfm", msg, AIP.db.autoSpamInterval or 60)
        end

        popup:Hide()
        GUI.RefreshBrowserTab("lfm")
        AIP.Print("Group listing created for " .. raidKey .. "! |cFF00FF00Auto-broadcasting started.|r")
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", createBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Apply initial defaults
    ApplyTemplateDefaults()

    popup:Hide()
    tinsert(UISpecialFrames, "AIPAddGroupPopup")
    GUI.AddGroupPopup = popup
end

-- Update achievement dropdown based on selected raid
function GUI.UpdateAchievementDropdown(popup, raidKey)
    if not popup or not popup.achieveDropdown then return end

    local achievements = GUI.RaidAchievements[raidKey] or {}

    UIDropDownMenu_Initialize(popup.achieveDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "None"
        info.value = nil
        info.func = function()
            popup.selectedAchievement = nil
            UIDropDownMenu_SetText(popup.achieveDropdown, "None")
        end
        UIDropDownMenu_AddButton(info)

        for _, achieve in ipairs(achievements) do
            info = UIDropDownMenu_CreateInfo()
            info.text = achieve.name
            info.value = achieve.id
            info.func = function()
                popup.selectedAchievement = achieve.id
                UIDropDownMenu_SetText(popup.achieveDropdown, achieve.name)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    UIDropDownMenu_SetText(popup.achieveDropdown, "None")
    popup.selectedAchievement = nil
end

-- Show Enroll popup
function GUI.ShowEnrollPopup()
    if not GUI.EnrollPopup then
        GUI.CreateEnrollPopup()
    end
    -- Update size dropdown for current raid selection
    if GUI.EnrollPopup.UpdateSizeDropdown then
        GUI.EnrollPopup.UpdateSizeDropdown()
    end
    -- Update raid dropdown text with lockout color
    if GUI.EnrollPopup.UpdateRaidDropdownText then
        GUI.EnrollPopup.UpdateRaidDropdownText()
    end
    GUI.EnrollPopup:Show()
end

-- Spec names by class for WotLK 3.3.5a (fallback)
GUI.ClassSpecNames = {
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

-- Get player's spec name with improved WotLK 3.3.5a dual spec support
function GUI.GetPlayerSpecName()
    local _, playerClass = UnitClass("player")
    local specNames = GUI.ClassSpecNames[playerClass] or {"Unknown", "Unknown", "Unknown"}

    -- WotLK 3.3.5a dual spec: Get active talent group first (1 = Primary, 2 = Secondary)
    local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1

    -- Check which tree has most points in the ACTIVE talent group
    local maxPoints = 0
    local specIndex = 1
    local specName = nil

    local numTabs = GetNumTalentTabs() or 3
    if numTabs and numTabs > 0 then
        for i = 1, numTabs do
            -- GetTalentTabInfo(tabIndex, inspect, pet, talentGroup)
            -- In WotLK 3.3.5a, passing the talentGroup parameter gets the correct spec
            local name, iconTexture, pointsSpent
            if activeTalentGroup then
                name, iconTexture, pointsSpent = GetTalentTabInfo(i, false, false, activeTalentGroup)
            else
                name, iconTexture, pointsSpent = GetTalentTabInfo(i)
            end

            if pointsSpent and pointsSpent > maxPoints then
                maxPoints = pointsSpent
                specIndex = i
                -- Verify name is valid (not an icon path or empty)
                if name and name ~= "" and not name:find("Interface") and not name:find("\\") then
                    specName = name
                end
            end
        end
    end

    -- If we found a valid spec name from the API, return it
    if specName then
        return specName
    end

    -- Fallback: Use spec names lookup based on spec index
    if specIndex >= 1 and specIndex <= 3 then
        return specNames[specIndex]
    end

    -- Final fallback: Try GetPrimaryTalentTree (should return tree index for highest points)
    if GetPrimaryTalentTree then
        -- GetPrimaryTalentTree(isInspect, talentGroup) - get for active group
        local primaryTree = GetPrimaryTalentTree(false, activeTalentGroup)
        if primaryTree and primaryTree >= 1 and primaryTree <= 3 then
            return specNames[primaryTree]
        end
    end

    return specNames[1] or "Unknown"
end

-- Get player's spec index (1, 2, or 3 corresponding to talent tree)
function GUI.GetPlayerSpecIndex()
    local activeTalentGroup = GetActiveTalentGroup and GetActiveTalentGroup() or 1
    local maxPoints = 0
    local specIndex = 1

    local numTabs = GetNumTalentTabs() or 3
    for i = 1, numTabs do
        local _, _, pointsSpent = GetTalentTabInfo(i, false, false, activeTalentGroup)
        if pointsSpent and pointsSpent > maxPoints then
            maxPoints = pointsSpent
            specIndex = i
        end
    end

    return specIndex
end

-- Auto-detect player's role based on class and talent spec
function GUI.DetectPlayerRole()
    local _, class = UnitClass("player")

    -- Get active talent spec (WotLK API)
    local specName = GUI.GetPlayerSpecName()

    -- Map class/spec to role
    local roleMap = {
        WARRIOR = {["Protection"] = "TANK", ["Arms"] = "DPS", ["Fury"] = "DPS"},
        PALADIN = {["Protection"] = "TANK", ["Holy"] = "HEALER", ["Retribution"] = "DPS"},
        DEATHKNIGHT = {["Blood"] = "TANK", ["Frost"] = "DPS", ["Unholy"] = "DPS"},
        DRUID = {["Feral Combat"] = "TANK", ["Restoration"] = "HEALER", ["Balance"] = "DPS"},
        PRIEST = {["Holy"] = "HEALER", ["Discipline"] = "HEALER", ["Shadow"] = "DPS"},
        SHAMAN = {["Restoration"] = "HEALER", ["Elemental"] = "DPS", ["Enhancement"] = "DPS"},
        MAGE = "DPS",
        WARLOCK = "DPS",
        HUNTER = "DPS",
        ROGUE = "DPS",
    }

    local classRole = roleMap[class]
    if type(classRole) == "string" then
        return classRole
    elseif type(classRole) == "table" then
        return classRole[specName] or "DPS"
    end

    return "DPS"
end

-- Calculate player's GearScore (using GearScore addon if available)
function GUI.CalculatePlayerGS()
    local playerName = UnitName("player")

    -- Try GearScore addon first (same as GearScoreLite uses)
    if GearScore_GetScore then
        local gs, ilvl = GearScore_GetScore(playerName, "player")
        if gs and gs > 0 then
            return gs, ilvl
        end
    end

    -- Try PlayerScore addon
    if PlayerScore_GetScore then
        local ps = PlayerScore_GetScore(playerName)
        if ps and ps > 0 then
            return ps
        end
    end

    -- Fallback: Use Integrations module if available
    if AIP.Integrations and AIP.Integrations.GetGearScore then
        local gs, source, ilvl = AIP.Integrations.GetGearScore(playerName)
        if gs and gs > 0 then
            return gs, ilvl
        end
    end

    -- Final fallback: estimate from equipped item levels
    local totalIlvl = 0
    local slotCount = 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18}

    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl then
                totalIlvl = totalIlvl + ilvl
                slotCount = slotCount + 1
            end
        end
    end

    if slotCount > 0 then
        local avgIlvl = totalIlvl / slotCount
        -- Rough GS estimate: avgIlvl * 25 (approximate conversion)
        return math.floor(avgIlvl * 25), math.floor(avgIlvl)
    end

    return 4000, 200 -- Default fallback
end

-- Calculate player's average item level
function GUI.CalculatePlayerIlvl()
    local totalIlvl = 0
    local slotCount = 0
    local slots = {1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17}

    for _, slot in ipairs(slots) do
        local link = GetInventoryItemLink("player", slot)
        if link then
            local _, _, _, ilvl = GetItemInfo(link)
            if ilvl then
                totalIlvl = totalIlvl + ilvl
                slotCount = slotCount + 1
            end
        end
    end

    if slotCount > 0 then
        return math.floor(totalIlvl / slotCount)
    end

    return 200 -- Default fallback
end

-- Get player's achievements for a raid
function GUI.GetPlayerAchievementsForRaid(raidKey)
    local achievements = GUI.RaidAchievements[raidKey] or {}
    local playerHas = {}

    for _, achieve in ipairs(achievements) do
        local _, name, _, completed = GetAchievementInfo(achieve.id)
        if completed then
            table.insert(playerHas, {id = achieve.id, name = name or achieve.name})
        end
    end

    return playerHas
end

function GUI.CreateEnrollPopup()
    local popup = CreateFrame("Frame", "AIPEnrollPopup", UIParent)
    popup:SetSize(400, 480)  -- Optimized size for content
    popup:SetPoint("CENTER", 220, 0)  -- Offset right so it doesn't overlap with Add Group popup
    popup:SetFrameStrata("DIALOG")
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
        insets = {left = 8, right = 8, top = 8, bottom = 8}
    })

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Enroll as Looking for Group")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    local y = -45

    -- === Player Info Section ===
    local playerLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    playerLabel:SetPoint("TOPLEFT", 20, y)
    playerLabel:SetText("Your Character:")

    local _, class = UnitClass("player")
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    local playerName = UnitName("player")

    local playerInfo = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    playerInfo:SetPoint("LEFT", playerLabel, "RIGHT", 10, 0)
    if classColor then
        playerInfo:SetTextColor(classColor.r, classColor.g, classColor.b)
    end
    playerInfo:SetText(playerName .. " (" .. (class or "Unknown") .. ")")
    y = y - 25

    -- Auto-detected stats display
    local statsFrame = CreateFrame("Frame", nil, popup)
    statsFrame:SetSize(360, 40)
    statsFrame:SetPoint("TOPLEFT", 20, y)
    GUI.ApplyBackdrop(statsFrame, "Inset", 0.8)

    local gsDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    gsDisplayLabel:SetPoint("TOPLEFT", 10, -8)
    gsDisplayLabel:SetText("GearScore:")
    gsDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local gsDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gsDisplayValue:SetPoint("LEFT", gsDisplayLabel, "RIGHT", 5, 0)
    popup.gsDisplayValue = gsDisplayValue

    local ilvlDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ilvlDisplayLabel:SetPoint("LEFT", gsDisplayValue, "RIGHT", 20, 0)
    ilvlDisplayLabel:SetText("Avg iLvl:")
    ilvlDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local ilvlDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    ilvlDisplayValue:SetPoint("LEFT", ilvlDisplayLabel, "RIGHT", 5, 0)
    popup.ilvlDisplayValue = ilvlDisplayValue

    local roleDisplayLabel = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleDisplayLabel:SetPoint("TOPLEFT", 10, -24)
    roleDisplayLabel:SetText("Detected Role:")
    roleDisplayLabel:SetTextColor(0.7, 0.7, 0.7)

    local roleDisplayValue = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    roleDisplayValue:SetPoint("LEFT", roleDisplayLabel, "RIGHT", 5, 0)
    popup.roleDisplayValue = roleDisplayValue
    y = y - 48  -- Account for stats frame

    -- === Raid Selection Section ===
    local raidSelectLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    raidSelectLabel:SetPoint("TOPLEFT", 20, y)
    raidSelectLabel:SetText("Looking for Raid:")
    y = y - 22

    -- Raid type dropdown
    local raidTypeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidTypeLabel:SetPoint("TOPLEFT", 30, y)
    raidTypeLabel:SetText("Raid:")

    local raidTypeDropdown = CreateFrame("Frame", "AIPEnrollRaidType", popup, "UIDropDownMenuTemplate")
    raidTypeDropdown:SetPoint("LEFT", raidTypeLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(raidTypeDropdown, 100)
    popup.raidType = "ICC"

    -- Size dropdown
    local sizeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sizeLabel:SetPoint("LEFT", raidTypeDropdown, "RIGHT", 0, 2)
    sizeLabel:SetText("Size:")

    local sizeDropdown = CreateFrame("Frame", "AIPEnrollSize", popup, "UIDropDownMenuTemplate")
    sizeDropdown:SetPoint("LEFT", sizeLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(sizeDropdown, 45)
    popup.raidSize = "25"

    -- Heroic checkbox
    local heroicCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    heroicCheck:SetSize(22, 22)
    heroicCheck:SetPoint("LEFT", sizeDropdown, "RIGHT", 10, 2)
    heroicCheck:SetChecked(false)
    popup.heroicCheck = heroicCheck
    local heroicLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    heroicLabel:SetPoint("LEFT", heroicCheck, "RIGHT", 0, 0)
    heroicLabel:SetText("Heroic")

    -- Lockout warning indicator (red dot instead of text label)
    local lockoutWarning = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lockoutWarning:SetPoint("LEFT", heroicLabel, "RIGHT", 8, 0)
    lockoutWarning:SetText("|cFFFF4444\226\151\143|r")  -- Red circle indicator
    lockoutWarning:Hide()
    popup.lockoutWarning = lockoutWarning

    -- Custom text input (shown when CUSTOM is selected) - on separate line
    y = y - 28
    local customLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    customLabel:SetPoint("TOPLEFT", 30, y)
    customLabel:SetText("Custom Name:")
    customLabel:Hide()
    popup.customLabel = customLabel

    local customInput, customContainer = GUI.CreateStyledEditBox(popup, 280, 16, false)
    customContainer:SetPoint("LEFT", customLabel, "RIGHT", 5, 0)
    customContainer:Hide()
    popup.customInput = customInput
    popup.customContainer = customContainer
    popup.customY = y  -- Store for layout adjustment

    -- Helper to build raid key
    local function GetRaidKey()
        local raidType = popup.raidType or "ICC"
        -- Handle custom text
        if raidType == "CUSTOM" then
            local customText = popup.customInput and popup.customInput:GetText() or ""
            if customText ~= "" then
                return customText
            end
            return "Custom"
        end
        local size = popup.raidSize or "25"
        local heroic = popup.heroicCheck:GetChecked() and "H" or "N"
        if raidType == "TOC" and heroic == "H" then
            return "TOGC" .. size
        end
        return raidType .. size .. heroic
    end

    -- Update custom field visibility
    local function UpdateCustomFieldVisibility()
        local isCustom = popup.raidType == "CUSTOM"
        if isCustom then
            popup.customLabel:Show()
            if popup.customContainer then popup.customContainer:Show() end
        else
            popup.customLabel:Hide()
            if popup.customContainer then popup.customContainer:Hide() end
        end
    end

    -- Update achievements when raid changes
    -- Update lockout warning based on selected raid
    local function UpdateLockoutWarning()
        local raidKey = GetRaidKey()
        if AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance then
            AIP.TreeBrowser.UpdateSavedInstances()
            local isLocked = AIP.TreeBrowser.IsLockedToInstance(raidKey)
            if isLocked then
                lockoutWarning:Show()
            else
                lockoutWarning:Hide()
            end
        else
            lockoutWarning:Hide()
        end
    end
    popup.UpdateLockoutWarning = UpdateLockoutWarning

    local function UpdateAchievementsList()
        local raidKey = GetRaidKey()
        local achievements = GUI.GetPlayerAchievementsForRaid(raidKey)

        -- Clear previous messages (ScrollingMessageFrame)
        popup.achieveList:Clear()

        if #achievements > 0 then
            for _, a in ipairs(achievements) do
                -- Get actual achievement link for display
                local link = GetAchievementLink(a.id)
                if link then
                    popup.achieveList:AddMessage("|cFF00FF00+|r " .. link)
                else
                    popup.achieveList:AddMessage("|cFF00FF00+|r " .. a.name)
                end
            end
        else
            popup.achieveList:AddMessage("|cFFFF6666No achievements for this raid|r")
        end

        popup.playerAchievements = achievements
        UpdateLockoutWarning()
    end

    -- Function to update size dropdown based on selected raid
    local function UpdateSizeDropdown()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType]
        if raidInfo then
            -- Set default size for this raid if current size is not valid
            local currentSizeValid = false
            for _, validSize in ipairs(raidInfo.sizes) do
                if validSize == popup.raidSize then
                    currentSizeValid = true
                    break
                end
            end
            if not currentSizeValid then
                popup.raidSize = raidInfo.defaultSize
                UIDropDownMenu_SetText(sizeDropdown, raidInfo.defaultSize)
            end
            -- Update heroic checkbox visibility
            if raidInfo.hasHeroic then
                heroicCheck:Show()
                heroicLabel:Show()
            else
                heroicCheck:Hide()
                heroicLabel:Hide()
                heroicCheck:SetChecked(false)
            end
            -- Enable/disable size dropdown based on available sizes
            if #raidInfo.sizes == 1 then
                UIDropDownMenu_DisableDropDown(sizeDropdown)
            else
                UIDropDownMenu_EnableDropDown(sizeDropdown)
            end
        end
        -- Refresh dropdown display
        UIDropDownMenu_Initialize(sizeDropdown, function()
            local info = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
            for _, size in ipairs(info.sizes) do
                local sizeInfo = UIDropDownMenu_CreateInfo()
                sizeInfo.text = size .. " players"
                sizeInfo.value = size
                sizeInfo.func = function()
                    popup.raidSize = size
                    UIDropDownMenu_SetText(sizeDropdown, size)
                    UpdateAchievementsList()
                end
                sizeInfo.checked = (popup.raidSize == size)
                UIDropDownMenu_AddButton(sizeInfo)
            end
        end)
    end
    popup.UpdateSizeDropdown = UpdateSizeDropdown

    -- Helper to update raid dropdown text with lockout color
    local function UpdateRaidDropdownText()
        local raidType = popup.raidType or "ICC"
        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(raidType)
        if isLocked then
            UIDropDownMenu_SetText(raidTypeDropdown, "|cFFFF6666" .. raidType .. "|r")
        else
            UIDropDownMenu_SetText(raidTypeDropdown, raidType)
        end
    end
    popup.UpdateRaidDropdownText = UpdateRaidDropdownText

    -- Initialize raid type dropdown with nested submenus
    UIDropDownMenu_Initialize(raidTypeDropdown, function(self, level, menuList)
        level = level or 1

        if level == 1 then
            -- Main level: show categories with arrows
            for _, cat in ipairs(GUI.RaidCategories) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = cat.header
                info.hasArrow = true
                info.menuList = cat.id
                info.notCheckable = true
                info.keepShownOnClick = true
                UIDropDownMenu_AddButton(info, level)
            end
        elseif level == 2 then
            -- Submenu: show raids in category
            for _, cat in ipairs(GUI.RaidCategories) do
                if cat.id == menuList then
                    for _, rt in ipairs(cat.items) do
                        local info = UIDropDownMenu_CreateInfo()
                        -- Show lockout indicator (red text, no label)
                        local isLocked = AIP.TreeBrowser and AIP.TreeBrowser.IsLockedToInstance and AIP.TreeBrowser.IsLockedToInstance(rt)
                        if isLocked then
                            info.text = "|cFFFF6666" .. rt .. "|r"
                        else
                            info.text = rt
                        end
                        info.value = rt
                        info.func = function()
                            popup.raidType = rt
                            UpdateRaidDropdownText()
                            UpdateSizeDropdown()
                            UpdateCustomFieldVisibility()
                            UpdateAchievementsList()
                            CloseDropDownMenus()
                        end
                        info.checked = (popup.raidType == rt)
                        UIDropDownMenu_AddButton(info, level)
                    end
                    break
                end
            end
        end
    end)

    -- Initialize size dropdown
    UIDropDownMenu_Initialize(sizeDropdown, function()
        local raidInfo = GUI.RaidSizeInfo[popup.raidType] or {sizes = {"5", "10", "25"}}
        for _, size in ipairs(raidInfo.sizes) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = size .. " players"
            info.value = size
            info.func = function()
                popup.raidSize = size
                UIDropDownMenu_SetText(sizeDropdown, size)
                UpdateAchievementsList()
            end
            info.checked = (popup.raidSize == size)
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(sizeDropdown, "25")
    GUI.FixDropdownStrata(raidTypeDropdown)
    GUI.FixDropdownStrata(sizeDropdown)

    -- Apply initial size dropdown update
    UpdateSizeDropdown()
    UpdateRaidDropdownText()  -- Apply initial lockout color

    heroicCheck:SetScript("OnClick", UpdateAchievementsList)
    y = y - 32

    -- === Role Override ===
    local roleLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    roleLabel:SetPoint("TOPLEFT", 30, y)
    roleLabel:SetText("Role (override):")

    local roleDropdown = CreateFrame("Frame", "AIPEnrollRoleDrop", popup, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", roleLabel, "RIGHT", -5, -2)
    UIDropDownMenu_SetWidth(roleDropdown, 80)
    popup.roleDropdown = roleDropdown
    popup.selectedRole = nil -- nil means auto-detect

    UIDropDownMenu_Initialize(roleDropdown, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = "Auto-detect"
        info.value = nil
        info.func = function()
            popup.selectedRole = nil
            UIDropDownMenu_SetText(roleDropdown, "Auto-detect")
        end
        UIDropDownMenu_AddButton(info)

        for _, role in ipairs({"TANK", "HEALER", "DPS"}) do
            info = UIDropDownMenu_CreateInfo()
            info.text = role
            info.value = role
            info.func = function()
                popup.selectedRole = role
                UIDropDownMenu_SetText(roleDropdown, role)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_SetText(roleDropdown, "Auto-detect")
    GUI.FixDropdownStrata(roleDropdown)
    y = y - 32

    -- === Your Achievements Section ===
    local achieveHeader = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    achieveHeader:SetPoint("TOPLEFT", 20, y)
    achieveHeader:SetText("Your Achievements for this Raid:")
    y = y - 20

    local achieveFrame = CreateFrame("Frame", nil, popup)
    achieveFrame:SetSize(360, 70)
    achieveFrame:SetPoint("TOPLEFT", 20, y)
    GUI.ApplyBackdrop(achieveFrame, "Inset", 0.9)

    -- Use ScrollingMessageFrame for achievement display with hyperlink support
    local achieveScroll = CreateFrame("ScrollingMessageFrame", nil, achieveFrame)
    achieveScroll:SetPoint("TOPLEFT", 8, -6)
    achieveScroll:SetPoint("BOTTOMRIGHT", -8, 6)
    achieveScroll:SetFontObject(GameFontNormalSmall)
    achieveScroll:SetJustifyH("LEFT")
    achieveScroll:SetInsertMode("TOP")  -- Messages appear from top-left
    achieveScroll:SetFading(false)
    achieveScroll:SetMaxLines(50)
    achieveScroll:EnableMouseWheel(true)
    achieveScroll:SetHyperlinksEnabled(true)
    achieveScroll:SetScript("OnHyperlinkEnter", function(self, link, text)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetHyperlink(link)
        GameTooltip:Show()
    end)
    achieveScroll:SetScript("OnHyperlinkLeave", function(self)
        GameTooltip:Hide()
    end)
    achieveScroll:SetScript("OnHyperlinkClick", function(self, link, text, button)
        SetItemRef(link, text, button)
    end)
    achieveScroll:SetScript("OnMouseWheel", function(self, delta)
        if delta > 0 then
            self:ScrollUp()
        else
            self:ScrollDown()
        end
    end)
    popup.achieveList = achieveScroll
    popup.achieveListIsHTML = false  -- Using ScrollingMessageFrame now
    y = y - 78

    -- === Include Achievement checkbox ===
    local includeAchieveCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
    includeAchieveCheck:SetSize(22, 22)
    includeAchieveCheck:SetPoint("TOPLEFT", 20, y)
    includeAchieveCheck:SetChecked(true)
    popup.includeAchieveCheck = includeAchieveCheck
    local includeAchieveLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    includeAchieveLabel:SetPoint("LEFT", includeAchieveCheck, "RIGHT", 2, 0)
    includeAchieveLabel:SetText("Link best achievement in message")
    y = y - 28

    -- === Custom note ===
    local noteLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("TOPLEFT", 20, y)
    noteLabel:SetText("Note:")

    local noteInput, noteContainer = GUI.CreateStyledEditBox(popup, 280, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 5, 0)
    popup.noteInput = noteInput
    y = y - 28

    -- === Buttons ===
    local enrollBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    enrollBtn:SetSize(90, 24)
    enrollBtn:SetPoint("BOTTOMLEFT", 80, 15)
    enrollBtn:SetText("Enroll")
    enrollBtn:SetScript("OnClick", function()
        local raidKey = GetRaidKey()
        local role = popup.selectedRole or GUI.DetectPlayerRole()
        local gs = GUI.CalculatePlayerGS()
        local ilvl = GUI.CalculatePlayerIlvl()
        local _, class = UnitClass("player")

        -- Build achievement link
        local achieveLink = ""
        if popup.includeAchieveCheck:GetChecked() and popup.playerAchievements and #popup.playerAchievements > 0 then
            achieveLink = GetAchievementLink(popup.playerAchievements[1].id) or ""
        end

        local note = popup.noteInput:GetText() or ""

        -- Enhanced LFG message with all player stats
        -- Format: "LFG <RAID> - <Class> (<Spec>) <Role> | GS:<gs> iL:<ilvl> {AIP:5.2} [Achievement] note"
        local spec = GUI.GetPlayerSpecName()
        local classDisplay = class:sub(1,1) .. class:sub(2):lower()  -- Capitalize first letter only
        local level = UnitLevel("player")

        -- Short class codes for compact display
        local classShortCodes = {
            WARRIOR = "War", PALADIN = "Pal", DEATHKNIGHT = "DK", DRUID = "Dru",
            PRIEST = "Pri", SHAMAN = "Sha", MAGE = "Mag", WARLOCK = "Loc",
            HUNTER = "Hun", ROGUE = "Rog"
        }
        local classShort = classShortCodes[class] or classDisplay

        -- Build message with all stats
        local msg = string.format("LFG %s - %s (%s) %s | GS:%d iL:%d Lv:%d {AIP:5.2}",
            raidKey, classShort, spec, role, gs, ilvl, level)
        if achieveLink ~= "" then
            msg = msg .. " " .. achieveLink
        end
        if note ~= "" then
            msg = msg .. " " .. note
        end

        -- Store enrollment data with all stats
        local playerName = UnitName("player")
        GUI.MyEnrollment = {
            name = playerName,
            raid = raidKey,
            class = class,
            classShort = classShort,
            spec = spec,
            role = role,
            gs = gs,
            ilvl = ilvl,
            level = level,
            message = msg,
            time = time(),
            isLfgEnrollment = true,
            isSelf = true,  -- Flag to indicate this is our own enrollment
        }

        -- Also add to LfgEnrollments for display in LFG tab
        GUI.LfgEnrollments[playerName] = GUI.MyEnrollment

        -- Set player mode to LFG
        if AIP.SetPlayerMode then
            AIP.SetPlayerMode("lfg")
        end

        -- Start auto-broadcast for LFG (will auto-stop when joining group)
        GUI.StartBroadcast("lfg", msg, AIP.db and AIP.db.autoSpamInterval or 60)

        popup:Hide()

        -- Ensure main GUI exists before updating
        if not GUI.Frame then
            GUI.CreateFrame()
        end

        -- Update queue panel to show our enrollment and switch to LFG sub-tab
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then
            -- Switch to LFG sub-tab FIRST so content is visible
            if container.queueSubTab ~= "lfg" then
                container.queueSubTab = "lfg"
                -- Update tab visuals
                if container.queueTabBtn and container.queueTabBtn.bg then
                    container.queueTabBtn.bg:SetTexture(0.15, 0.15, 0.15, 1)
                    if container.queueTabBtn.text then container.queueTabBtn.text:SetTextColor(0.8, 0.8, 0.8) end
                end
                if container.lfgTabBtn and container.lfgTabBtn.bg then
                    container.lfgTabBtn.bg:SetTexture(0.3, 0.3, 0.4, 1)
                    if container.lfgTabBtn.text then container.lfgTabBtn.text:SetTextColor(1, 0.82, 0) end
                end
                if container.queueContent then container.queueContent:Hide() end
                if container.lfgContent then container.lfgContent:Show() end
            end
            -- Then update the panel data
            GUI.UpdateQueuePanel(container)
        end

        -- Show main window so user can see their enrollment
        GUI.Show("lfm")

        -- Update queue status to show enrollment
        GUI.UpdateEnrollmentStatus()

        AIP.Print("Enrolled as LFG for " .. raidKey .. " (" .. role .. ")! |cFF00FF00Auto-broadcasting until you join a group.|r")
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", enrollBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Update stats when shown
    popup:SetScript("OnShow", function()
        local gs = GUI.CalculatePlayerGS()
        local ilvl = GUI.CalculatePlayerIlvl()
        local role = GUI.DetectPlayerRole()

        popup.gsDisplayValue:SetText(tostring(gs))
        popup.ilvlDisplayValue:SetText(tostring(ilvl))
        popup.roleDisplayValue:SetText(role)

        -- Update raid dropdown with lockout color
        UpdateRaidDropdownText()
        UpdateAchievementsList()
    end)

    popup:Hide()
    tinsert(UISpecialFrames, "AIPEnrollPopup")
    GUI.EnrollPopup = popup
end

-- ============================================================================
-- ADD TO QUEUE POPUP
-- ============================================================================
function GUI.ShowAddToQueuePopup()
    if not GUI.AddToQueuePopup then
        GUI.CreateAddToQueuePopup()
    end
    -- Clear fields
    if GUI.AddToQueuePopup.nameInput then
        GUI.AddToQueuePopup.nameInput:SetText("")
    end
    if GUI.AddToQueuePopup.noteInput then
        GUI.AddToQueuePopup.noteInput:SetText("")
    end
    GUI.AddToQueuePopup:Show()
    GUI.AddToQueuePopup.nameInput:SetFocus()
end

function GUI.CreateAddToQueuePopup()
    local popup = CreateFrame("Frame", "AIPAddToQueuePopup", UIParent)
    popup:SetSize(280, 140)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
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
        insets = {left = 8, right = 8, top = 8, bottom = 8}
    })

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Add to Queue")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Player name
    local nameLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 20, -45)
    nameLabel:SetText("Player Name:")

    local nameInput, nameContainer = GUI.CreateStyledEditBox(popup, 150, 18, false)
    nameContainer:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    popup.nameInput = nameInput

    -- Note/message
    local noteLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 20, -75)
    noteLabel:SetText("Note (optional):")

    local noteInput, noteContainer = GUI.CreateStyledEditBox(popup, 140, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 10, 0)
    popup.noteInput = noteInput

    -- Buttons
    local addBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 24)
    addBtn:SetPoint("BOTTOMLEFT", 50, 15)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = popup.nameInput:GetText():trim()
        if name == "" then
            AIP.Print("Please enter a player name")
            return
        end

        local note = popup.noteInput:GetText():trim()
        if note == "" then note = "Manual add" end

        -- Ensure queue db exists
        if not AIP.db then AIP.db = {} end
        if not AIP.db.queue then AIP.db.queue = {} end

        -- Check if already in queue
        local alreadyInQueue = false
        for _, entry in ipairs(AIP.db.queue) do
            if entry.name and entry.name:lower() == name:lower() then
                alreadyInQueue = true
                break
            end
        end

        if alreadyInQueue then
            AIP.Print(name .. " is already in queue")
            return
        end

        -- Capitalize name
        local properName = name:sub(1,1):upper() .. name:sub(2):lower()

        -- Add to queue directly
        local entry = {
            name = properName,
            message = note,
            time = time(),
            isBlacklisted = AIP.IsBlacklisted and AIP.IsBlacklisted(name) or false,
        }
        table.insert(AIP.db.queue, entry)
        AIP.Print(properName .. " added to queue manually")

        -- Update UI
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then
            GUI.UpdateQueuePanel(container)
        end

        popup:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Enter key submits
    popup.nameInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    popup.noteInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    popup:Hide()
    tinsert(UISpecialFrames, "AIPAddToQueuePopup")
    GUI.AddToQueuePopup = popup
end

-- ============================================================================
-- ADD TO WAITLIST POPUP
-- ============================================================================
function GUI.ShowAddToWaitlistPopup()
    if not GUI.AddToWaitlistPopup then
        GUI.CreateAddToWaitlistPopup()
    end
    -- Clear fields
    if GUI.AddToWaitlistPopup.nameInput then
        GUI.AddToWaitlistPopup.nameInput:SetText("")
    end
    if GUI.AddToWaitlistPopup.noteInput then
        GUI.AddToWaitlistPopup.noteInput:SetText("")
    end
    GUI.AddToWaitlistPopup:Show()
    GUI.AddToWaitlistPopup.nameInput:SetFocus()
end

function GUI.CreateAddToWaitlistPopup()
    local popup = CreateFrame("Frame", "AIPAddToWaitlistPopup", UIParent)
    popup:SetSize(300, 170)
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("DIALOG")
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
        insets = {left = 8, right = 8, top = 8, bottom = 8}
    })

    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Add to Waitlist")
    title:SetTextColor(1, 0.82, 0)

    local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Player name
    local nameLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetPoint("TOPLEFT", 20, -45)
    nameLabel:SetText("Player Name:")

    local nameInput, nameContainer = GUI.CreateStyledEditBox(popup, 150, 18, false)
    nameContainer:SetPoint("LEFT", nameLabel, "RIGHT", 10, 0)
    popup.nameInput = nameInput

    -- Role dropdown
    local roleLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", 20, -75)
    roleLabel:SetText("Role:")

    local roleDropdown = CreateFrame("Frame", "AIPWaitlistRoleDropdown", popup, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", roleLabel, "RIGHT", -10, -2)
    UIDropDownMenu_SetWidth(roleDropdown, 100)
    UIDropDownMenu_SetText(roleDropdown, "DPS")
    popup.selectedRole = "DPS"

    UIDropDownMenu_Initialize(roleDropdown, function()
        for _, role in ipairs({"TANK", "HEALER", "DPS"}) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = role
            info.value = role
            info.func = function()
                popup.selectedRole = role
                UIDropDownMenu_SetText(roleDropdown, role)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    GUI.FixDropdownStrata(roleDropdown)

    -- Note
    local noteLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    noteLabel:SetPoint("TOPLEFT", 20, -105)
    noteLabel:SetText("Note:")

    local noteInput, noteContainer = GUI.CreateStyledEditBox(popup, 180, 18, false)
    noteContainer:SetPoint("LEFT", noteLabel, "RIGHT", 10, 0)
    popup.noteInput = noteInput

    -- Buttons
    local addBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    addBtn:SetSize(80, 24)
    addBtn:SetPoint("BOTTOMLEFT", 60, 15)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = popup.nameInput:GetText():trim()
        if name == "" then
            AIP.Print("Please enter a player name")
            return
        end

        local role = popup.selectedRole or "DPS"
        local note = popup.noteInput:GetText():trim()

        -- Ensure waitlist db exists
        if not AIP.db then AIP.db = {} end
        if not AIP.db.waitlist then AIP.db.waitlist = {} end

        -- Check if already on waitlist
        local alreadyOnWaitlist = false
        for _, entry in ipairs(AIP.db.waitlist) do
            if entry.name and entry.name:lower() == name:lower() then
                alreadyOnWaitlist = true
                break
            end
        end

        if alreadyOnWaitlist then
            AIP.Print(name .. " is already on the waitlist")
            return
        end

        -- Capitalize name
        local properName = name:sub(1,1):upper() .. name:sub(2):lower()

        -- Add to waitlist directly
        local entry = {
            name = properName,
            role = role,
            note = note,
            addedTime = time(),
            priority = #AIP.db.waitlist + 1,
        }
        table.insert(AIP.db.waitlist, entry)
        AIP.Print(properName .. " added to waitlist as " .. role)

        -- Update the waitlist panel
        local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
        if container then
            GUI.UpdateQueuePanel(container)
        end

        popup:Hide()
    end)

    local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
    cancelBtn:SetSize(80, 24)
    cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 20, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() popup:Hide() end)

    -- Enter key submits
    popup.nameInput:SetScript("OnEnterPressed", function() addBtn:Click() end)
    popup.noteInput:SetScript("OnEnterPressed", function() addBtn:Click() end)

    popup:Hide()
    tinsert(UISpecialFrames, "AIPAddToWaitlistPopup")
    GUI.AddToWaitlistPopup = popup
end

-- Hook into tree selection to update details panel
local origSelectNode = AIP.TreeBrowser and AIP.TreeBrowser.SelectNode
if AIP.TreeBrowser then
    -- Extended SelectNode that accepts optional data parameter
    AIP.TreeBrowser.SelectNode = function(nodeId, playerName, nodeData)
        if origSelectNode then origSelectNode(nodeId, playerName) end

        -- Get data - prefer passed nodeData, then try lookups
        local data = nodeData
        if not data and playerName then
            -- Try GroupTracker (indexed by leader name)
            if AIP.GroupTracker and AIP.GroupTracker.Groups then
                data = AIP.GroupTracker.Groups[playerName]
            end
            -- Try LFMBrowser (indexed by player name)
            if not data and AIP.LFMBrowser and AIP.LFMBrowser.Players then
                data = AIP.LFMBrowser.Players[playerName]
            end
            -- Try ChatScanner directly
            if not data and AIP.ChatScanner then
                if AIP.ChatScanner.Groups then
                    data = AIP.ChatScanner.Groups[playerName]
                end
                if not data and AIP.ChatScanner.Players then
                    data = AIP.ChatScanner.Players[playerName]
                end
            end
        end

        -- Determine which tab container to update
        local container = nil
        if GUI.Frame and GUI.Frame.tabContents then
            -- Check current tab or node type to pick correct container
            if nodeId and nodeId:find("^lfg_") then
                container = GUI.Frame.tabContents["favorites"]  -- LFG uses favorites tab
            else
                container = GUI.Frame.tabContents["lfm"]
            end
        end

        if container then
            GUI.UpdateDetailsPanel(container, data)
        end
    end
end

-- Update composition tab (RaidComp-style)
function GUI.UpdateCompositionTab()
    local container = GUI.Frame.tabContents["composition"]
    if not container then return end

    if not AIP.Composition then
        if container.templateDisplay then
            container.templateDisplay:SetText("Composition module not available")
        end
        return
    end

    local status = AIP.Composition.GetCompositionStatus()
    local raid = AIP.Composition.CurrentRaid

    -- Update template display
    if container.templateDisplay then
        if status then
            container.templateDisplay:SetText(status.template)
        else
            container.templateDisplay:SetText("No template selected (using current raid)")
        end
    end

    -- Update role bars
    local function UpdateRoleBar(bar, current, needed)
        if not bar then return end
        local ratio = needed > 0 and math.min(current / needed, 1) or 0
        local fillWidth = ratio * 150

        bar.fillBar:SetWidth(math.max(1, fillWidth))
        bar.countText:SetText(current .. "/" .. needed)

        -- Color based on status
        if current >= needed then
            bar.countText:SetTextColor(0, 1, 0)
        elseif current > 0 then
            bar.countText:SetTextColor(1, 1, 0)
        else
            bar.countText:SetTextColor(1, 0.3, 0.3)
        end
    end

    if status then
        UpdateRoleBar(container.roleBars.TANK, status.tanks.current, status.tanks.needed)
        UpdateRoleBar(container.roleBars.HEALER, status.healers.current, status.healers.needed)
        UpdateRoleBar(container.roleBars.DPS, status.dps.current, status.dps.needed)
        UpdateRoleBar(container.roleBars.TOTAL, status.size.current, status.size.needed)
    else
        UpdateRoleBar(container.roleBars.TANK, raid.roleCounts.TANK, 0)
        UpdateRoleBar(container.roleBars.HEALER, raid.roleCounts.HEALER, 0)
        UpdateRoleBar(container.roleBars.DPS, raid.roleCounts.DPS, 0)
        UpdateRoleBar(container.roleBars.TOTAL, #raid.members, 0)
    end

    -- Update buff/debuff display (new tabbed system)
    GUI.UpdateCompositionBuffDisplay(container)

    -- Update class counts
    if container.classDisplays then
        for class, display in pairs(container.classDisplays) do
            local count = raid.classCounts[class] or 0
            display.count:SetText(tostring(count))
            if count > 0 then
                display.count:SetAlpha(1)
                display.icon:SetAlpha(1)
                if display.frame then display.frame:SetAlpha(1) end
            else
                display.count:SetAlpha(0.4)
                display.icon:SetAlpha(0.4)
                if display.frame then display.frame:SetAlpha(0.5) end
            end
        end
    end

    -- Update raid member table (new scrollable table)
    GUI.UpdateCompositionMemberTable(container)

    -- Update raid benefits stats panel
    GUI.UpdateRaidBenefits(container)
end

-- Select a tab
function GUI.SelectTab(tabId)
    GUI.CurrentTab = tabId

    for id, container in pairs(GUI.Frame.tabContents) do
        local tabBtn = GUI.Frame.tabButtons[id]
        if id == tabId then
            container:Show()
            -- Highlight selected tab with custom styling
            if tabBtn then
                if tabBtn.bg then
                    tabBtn.bg:SetTexture(0.25, 0.25, 0.35, 1)
                end
                if tabBtn.text then
                    tabBtn.text:SetTextColor(1, 0.82, 0)  -- Gold color for selected
                end
            end
        else
            container:Hide()
            -- Deselect tab with custom styling
            if tabBtn then
                if tabBtn.bg then
                    tabBtn.bg:SetTexture(0.15, 0.15, 0.15, 0.9)
                end
                if tabBtn.text then
                    tabBtn.text:SetTextColor(0.8, 0.8, 0.8)  -- Gray for unselected
                end
            end
        end
    end

    -- Update the selected tab
    GUI.UpdateCurrentTab()
end

-- Update current tab content
function GUI.UpdateCurrentTab()
    local tabId = GUI.CurrentTab

    if tabId == "lfm" or tabId == "lfg" then
        GUI.RefreshBrowserTab(tabId)
    elseif tabId == "favorites" and AIP.Panels and AIP.Panels.Favorites then
        AIP.Panels.Favorites.Update()
    elseif tabId == "blacklist" and AIP.Panels and AIP.Panels.Blacklist then
        AIP.Panels.Blacklist.Update()
    elseif tabId == "composition" then
        GUI.UpdateCompositionTab()
    elseif tabId == "raidmgmt" and AIP.Panels and AIP.Panels.RaidMgmt then
        AIP.Panels.RaidMgmt.Update()
    elseif tabId == "loothistory" and AIP.Panels and AIP.Panels.LootHistory then
        AIP.Panels.LootHistory.Update()
    elseif tabId == "settings" and AIP.Panels and AIP.Panels.Settings then
        AIP.Panels.Settings.Update()
    end

    -- Update status bar
    GUI.UpdateStatus()
end

-- Get LFG enrollment count (same logic as LFG tab)
function GUI.GetLfgEnrollmentCount()
    local count = 0
    for _ in pairs(GUI.LfgEnrollments or {}) do
        count = count + 1
    end
    return count
end

-- Update status bar
function GUI.UpdateStatus()
    if not GUI.Frame then return end

    local status = ""
    if AIP.db and AIP.db.enabled then
        status = status .. "|cFF00FF00Auto-Invite: ON|r"
    else
        status = status .. "|cFFFF0000Auto-Invite: OFF|r"
    end

    local groupSize = AIP.GetGroupSize and AIP.GetGroupSize() or 1
    status = status .. "  |  Group: " .. groupSize

    local queueCount = AIP.GetQueueCount and AIP.GetQueueCount() or 0
    status = status .. "  |  Queue: " .. queueCount

    local lfmCount = AIP.GroupTracker and AIP.GroupTracker.GetGroupCount() or 0
    local lfgCount = GUI.GetLfgEnrollmentCount()
    status = status .. "  |  LFM: " .. lfmCount .. "  |  LFG: " .. lfgCount

    -- Add peer count to main status line
    local peerCount = AIP.DataBus and AIP.DataBus.GetPeerCount and AIP.DataBus.GetPeerCount() or 0
    local peerColor = peerCount > 0 and "|cFF00FF00" or "|cFF888888"
    status = status .. "  |  " .. peerColor .. "Peers: " .. peerCount .. "|r"

    -- Add mode to main status line (check broadcast state first, then db)
    local modeText, modeColor
    if GUI.Broadcast and GUI.Broadcast.active then
        -- Use active broadcast mode
        if GUI.Broadcast.mode == "lfm" then
            modeText = "LFM"
            modeColor = "|cFF00FFFF"
        elseif GUI.Broadcast.mode == "lfg" then
            modeText = "LFG"
            modeColor = "|cFFFFFF00"
        else
            modeText = "BC"
            modeColor = "|cFF00FF00"
        end
    else
        local mode = AIP.GetPlayerMode and AIP.GetPlayerMode() or "none"
        if mode == "lfm" then
            modeText = "LFM"
            modeColor = "|cFF00FFFF"
        elseif mode == "lfg" then
            modeText = "LFG"
            modeColor = "|cFFFFFF00"
        else
            modeText = "Off"
            modeColor = "|cFF888888"
        end
    end
    status = status .. "  |  " .. modeColor .. "Mode: " .. modeText .. "|r"

    GUI.Frame.statusText:SetText(status)

    -- Clear the separate displays (now consolidated)
    if GUI.Frame.statusBar.peerCountDisplay then
        GUI.Frame.statusBar.peerCountDisplay:SetText("")
    end
    if GUI.Frame.statusBar.modeIndicator then
        GUI.Frame.statusBar.modeIndicator:SetText("")
    end
end

-- Update peer count display in status bar (now handled by UpdateStatus)
function GUI.UpdatePeerCount()
    -- Consolidated into UpdateStatus for consistent formatting
end

-- Update mode indicator in status bar (now handled by UpdateStatus)
function GUI.UpdateModeIndicator()
    -- Consolidated into UpdateStatus for consistent formatting
end

-- Toggle the main window
function GUI.Toggle()
    if not GUI.Frame then
        GUI.CreateFrame()
    end

    if GUI.Frame:IsVisible() then
        GUI.Frame:Hide()
    else
        -- Restore position if saved (with nil checks and screen bounds clamping)
        if AIP.db and AIP.db.guiPosition then
            local pos = AIP.db.guiPosition
            if pos.point and pos.relPoint and pos.x and pos.y then
                -- Clamp position to screen bounds
                local screenW, screenH = UIParent:GetWidth(), UIParent:GetHeight()
                local frameW, frameH = GUI.Frame:GetWidth(), GUI.Frame:GetHeight()
                local x = math.max(-screenW + 100, math.min(pos.x, screenW - 100))
                local y = math.max(-screenH + 100, math.min(pos.y, screenH - 100))
                GUI.Frame:ClearAllPoints()
                GUI.Frame:SetPoint(pos.point, UIParent, pos.relPoint, x, y)
            end
        end

        -- Restore size if saved
        if AIP.db and AIP.db.guiWidth and AIP.db.guiHeight then
            GUI.Frame:SetSize(AIP.db.guiWidth, AIP.db.guiHeight)
        end

        GUI.Frame:Show()
        GUI.SelectTab(GUI.CurrentTab)
    end
end

-- Show the main window (called by /lfm, /lfg)
function GUI.Show(tabId)
    if not GUI.Frame then
        GUI.CreateFrame()
    end

    GUI.Frame:Show()
    if tabId then
        GUI.SelectTab(tabId)
    else
        GUI.SelectTab(GUI.CurrentTab)
    end

    -- Update GS display when showing
    GUI.UpdateGearScoreDisplay()
end

-- Update function called when data changes
function AIP.UpdateCentralGUI()
    if GUI.Frame and GUI.Frame:IsVisible() then
        GUI.UpdateCurrentTab()
        GUI.UpdateGearScoreDisplay()
    end
end

-- Update the GearScore/iLevel display in the footer
function GUI.UpdateGearScoreDisplay()
    if not GUI.Frame or not GUI.Frame.statusBar or not GUI.Frame.statusBar.gsDisplay then
        return
    end

    local gsDisplay = GUI.Frame.statusBar.gsDisplay
    local gs, ilvl

    -- Use the same function as Enroll popup for consistency
    gs, ilvl = GUI.CalculatePlayerGS()

    -- If no ilvl, calculate it separately
    if not ilvl then
        ilvl = GUI.CalculatePlayerIlvl()
    end

    -- Format the display with consistent separator style
    if gs and gs > 0 then
        local r, g, b = 1, 1, 1
        if AIP.Integrations and AIP.Integrations.GetGSColor then
            r, g, b = AIP.Integrations.GetGSColor(gs)
        end
        local gsStr = string.format("|cFF%02x%02x%02xGS: %d|r", r*255, g*255, b*255, gs)

        if ilvl and ilvl > 0 then
            gsDisplay:SetText(gsStr .. "  |  |cFFAAAAAAiLvl: " .. ilvl .. "|r")
        else
            gsDisplay:SetText(gsStr)
        end
    else
        -- No GS available, show just iLvl if we have it
        if ilvl and ilvl > 0 then
            gsDisplay:SetText("|cFFAAAAAAiLvl: " .. ilvl .. "|r")
        else
            gsDisplay:SetText("")
        end
    end
end

-- Hook equipment changes to update GS display
local gsUpdateFrame = CreateFrame("Frame")
gsUpdateFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
gsUpdateFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
gsUpdateFrame:SetScript("OnEvent", function(self, event)
    -- Delay slightly to ensure item info is loaded (WotLK compatible)
    AIP.Utils.DelayedCall(0.5, function()
        if GUI.Frame and GUI.Frame:IsVisible() then
            GUI.UpdateGearScoreDisplay()
        end
    end)
end)

-- Tree selection changed handler
function AIP.OnTreeSelectionChanged(nodeId, playerName)
    if not GUI.Frame then return end

    local currentTab = GUI.CurrentTab
    if currentTab ~= "lfm" and currentTab ~= "lfg" then return end

    local container = GUI.Frame.tabContents[currentTab]
    if not container or not container.inspectPanel then return end

    local panel = container.inspectPanel

    if not playerName then
        -- No selection
        panel.playerName:SetText("Select a player")
        panel.classSpec:SetText("")
        panel.gsText:SetText("")
        panel.enchantText:SetText("")
        panel.enchantList:SetText("")
        panel.gemText:SetText("")
        panel.achieveText:SetText("")
        panel.perfText:SetText("")
        panel.msgText:SetText("")
        return
    end

    -- Get player data - try direct lookup and also check TreeBrowser's selected node
    local data
    if currentTab == "lfm" and AIP.GroupTracker then
        data = AIP.GroupTracker.Groups[playerName]
    elseif currentTab == "lfg" and AIP.LFMBrowser then
        data = AIP.LFMBrowser.Players[playerName]
    end

    -- Fallback: get data from TreeBrowser's selected node
    if not data and AIP.TreeBrowser then
        local selectedData = AIP.TreeBrowser.GetSelectedPlayerData()
        if selectedData then
            data = selectedData
        end
    end

    if not data then
        panel.playerName:SetText(playerName)
        panel.classSpec:SetText("No data available")
        panel.gsText:SetText("")
        panel.enchantText:SetText("")
        panel.enchantList:SetText("")
        panel.gemText:SetText("")
        panel.achieveText:SetText("")
        panel.perfText:SetText("")
        panel.msgText:SetText("")
        return
    end

    -- Update display
    panel.playerName:SetText(playerName)

    -- For LFM groups, show raid info instead of class
    local classText, roleText
    if currentTab == "lfm" and data.raid then
        classText = data.raid
        roleText = ""
        -- Show composition needs
        if data.composition then
            local needs = {}
            if data.composition.tanks and data.composition.tanks.needed > 0 then
                table.insert(needs, data.composition.tanks.needed .. " Tank(s)")
            end
            if data.composition.healers and data.composition.healers.needed > 0 then
                table.insert(needs, data.composition.healers.needed .. " Healer(s)")
            end
            if data.composition.mdps and data.composition.mdps.needed > 0 then
                table.insert(needs, data.composition.mdps.needed .. " Melee")
            end
            if data.composition.rdps and data.composition.rdps.needed > 0 then
                table.insert(needs, data.composition.rdps.needed .. " Ranged")
            end
            -- Backwards compatibility
            if not data.composition.mdps and not data.composition.rdps and data.composition.dps and data.composition.dps.needed > 0 then
                table.insert(needs, data.composition.dps.needed .. " DPS")
            end
            if #needs > 0 then
                roleText = "LF: " .. table.concat(needs, ", ")
            end
        end
    else
        classText = data.class and (data.class:sub(1, 1) .. data.class:sub(2):lower()) or "Unknown"
        roleText = data.role or ""
    end
    panel.classSpec:SetText(classText .. (roleText ~= "" and ("\n" .. roleText) or ""))

    -- GearScore display - show requirement for groups, actual GS for players
    local gs = data.gs or data.gearScore or data.gsRequirement
    if gs then
        local gsFormatted = AIP.InspectionEngine and AIP.InspectionEngine.FormatGS(gs) or tostring(gs)
        if currentTab == "lfm" and data.gsRequirement then
            panel.gsText:SetText("GS Requirement: " .. gsFormatted .. "+")
        else
            panel.gsText:SetText("GearScore: " .. gsFormatted)
        end
    else
        panel.gsText:SetText("")
    end

    -- Check for inspection data
    local inspectData = AIP.InspectionEngine and AIP.InspectionEngine.GetCachedData(playerName)
    if inspectData then
        panel.enchantText:SetText("Missing Enchants: " .. inspectData.analysis.missingEnchants)
        if #inspectData.analysis.enchantableSlots > 0 then
            panel.enchantList:SetText("- " .. table.concat(inspectData.analysis.enchantableSlots, ", "))
        else
            panel.enchantList:SetText("")
        end

        panel.gemText:SetText("Empty Gem Slots: " .. inspectData.analysis.emptyGemSlots .. " / " .. inspectData.analysis.totalGemSlots)

        if inspectData.performanceEstimate then
            local perf = inspectData.performanceEstimate
            local perfStr = "Role: " .. (perf.role or "Unknown")
            if perf.estimatedDPS then
                perfStr = perfStr .. "\nEst. DPS: " .. perf.estimatedDPS
            end
            if perf.estimatedEHP then
                perfStr = perfStr .. "\nEst. EHP: " .. perf.estimatedEHP
            end
            perfStr = perfStr .. "\nConfidence: " .. (perf.confidence or "Low")
            panel.perfText:SetText(perfStr)
        end

        container.sourceText:SetText("Data: " .. (inspectData.dataSource or "Cache"))
    else
        panel.enchantText:SetText("Missing Enchants: -")
        panel.enchantList:SetText("")
        panel.gemText:SetText("Empty Gem Slots: - / -")
        panel.perfText:SetText("No inspection data available")
        container.sourceText:SetText("Data: Chat")

        -- Queue for inspection if in range
        if AIP.InspectionEngine then
            AIP.InspectionEngine.QueueInspection(playerName, 2)
        end
    end

    -- Message
    panel.msgText:SetText(data.message or "")
end

-- Hook into AIP.UpdateQueueUI to also refresh GUI queue panel
local origUpdateQueueUI = AIP.UpdateQueueUI
AIP.UpdateQueueUI = function()
    if origUpdateQueueUI then origUpdateQueueUI() end

    -- Also update the CentralGUI queue panel
    if GUI.Frame and GUI.Frame:IsVisible() and GUI.Frame.tabContents then
        local container = GUI.Frame.tabContents["lfm"]
        if container then
            GUI.UpdateQueuePanel(container)
        end
    end
end

-- Initialize on addon load (delayed to ensure db is available)
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame.initialized = false
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "AutoInvitePlus" then
        -- Create minimap button after a short delay to ensure db is ready
        local delayFrame = CreateFrame("Frame")
        delayFrame.elapsed = 0
        delayFrame:SetScript("OnUpdate", function(df, elapsed)
            df.elapsed = df.elapsed + elapsed
            if df.elapsed >= 0.5 then
                if AIP.db and not initFrame.initialized then
                    GUI.CreateMinimapButton()
                    initFrame.initialized = true
                end
                df:SetScript("OnUpdate", nil)
                df:Hide()
            end
        end)
    elseif event == "PLAYER_LOGIN" then
        -- Fallback: create minimap button if not already done
        if AIP.db and not initFrame.initialized then
            GUI.CreateMinimapButton()
            initFrame.initialized = true
        end
    end
end)
