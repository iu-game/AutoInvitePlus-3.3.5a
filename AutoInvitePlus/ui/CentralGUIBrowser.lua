-- AutoInvite Plus - Central GUI Browser Tab
-- Split from CentralGUI.lua: browser/queue-panel creation (CreateBrowserTab, CreateInspectionPanel)

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r CentralGUIBrowser: AutoInvitePlus namespace not found!")
    return
end

AIP.CentralGUI = AIP.CentralGUI or {}
local GUI = AIP.CentralGUI

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
        hideLockedLabel:SetText("Locked")
        hideLockedLabel:SetTextColor(0.8, 0.8, 0.8)
        container.hideLockedCheck = hideLockedCheck

        -- Hide Viewed checkbox - hides listings we've excluded or already requested
        local hideViewedCheck = CreateFrame("CheckButton", nil, treePanel, "UICheckButtonTemplate")
        hideViewedCheck:SetSize(20, 20)
        hideViewedCheck:SetChecked(AIP.TreeBrowser and AIP.TreeBrowser.HideExcluded)
        hideViewedCheck:SetScript("OnClick", function(self)
            if AIP.TreeBrowser then
                AIP.TreeBrowser.HideExcluded = self:GetChecked()
            end
            GUI.RefreshBrowserTab(tabType)
        end)
        hideViewedCheck:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Hide Viewed")
            GameTooltip:AddLine("Hide listings you've excluded or already requested", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hideViewedCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local hideViewedLabel = treePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hideViewedLabel:SetPoint("RIGHT", hideViewedCheck, "LEFT", 0, 0)
        hideViewedLabel:SetText("Viewed")
        hideViewedLabel:SetTextColor(0.8, 0.8, 0.8)
        container.hideViewedCheck = hideViewedCheck

        -- Chain layout right-to-left on the top row: [Refresh] [Viewed check] [Locked check]
        hideViewedCheck:SetPoint("RIGHT", hideLockedLabel, "LEFT", -10, 0)

        -- Refresh sits to the left of the Viewed label, vertically centered on the
        -- same line as the checkboxes (the whole cluster now clears the title).
        refreshBtn:SetPoint("RIGHT", hideViewedLabel, "LEFT", -10, 0)
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
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(searchBox) end
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
        -- Record the anchor insets so UpdateSize can derive the true available
        -- size from the parent panel. The tree frame's own GetHeight() is
        -- unreliable -- it carries an explicit SetSize from creation and keeps
        -- reporting that stale value even though the anchors stretch the frame.
        treeFrame._heightInset = 55 + 60   -- TOPLEFT y -55, BOTTOMRIGHT y +60
        treeFrame._widthInset = 8 + 8      -- TOPLEFT x +8, BOTTOMRIGHT x -8
        container.treeView = treeFrame

        -- Recompute rows when the parent panel resizes. UpdateSize() with no
        -- args derives the size from the parent (reliable), so a single direct
        -- call is enough -- no stale GetHeight, no deferral needed.
        treePanel:SetScript("OnSizeChanged", function(self)
            if treeFrame and treeFrame.UpdateSize then treeFrame:UpdateSize() end
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
    emptyTreeText:SetText("No group listings yet\n\nListings appear from chat scanning\nand AIP peers.\n\n|cFF33CCFFTip:|r enable channels in Settings,\nor click + Post Group to start your own.")
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
    addGroupBtn:SetSize(85, 22)
    addGroupBtn:SetPoint("BOTTOMLEFT", 8, 8)
    addGroupBtn:SetText("+ Post Group")
    addGroupBtn:SetScript("OnClick", function() GUI.ShowAddGroupPopup() end)
    addGroupBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Broadcast LFM")
        GameTooltip:AddLine("Broadcast your group to other addon users", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    addGroupBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local enrollBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    enrollBtn:SetSize(75, 22)
    enrollBtn:SetPoint("LEFT", addGroupBtn, "RIGHT", 5, 0)
    enrollBtn:SetText("Find Group")
    enrollBtn:SetScript("OnClick", function() GUI.ShowEnrollPopup() end)
    enrollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Broadcast LFG")
        GameTooltip:AddLine("Broadcast that you're looking for a group", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    enrollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearBtn = CreateFrame("Button", nil, treePanel, "UIPanelButtonTemplate")
    clearBtn:SetSize(45, 22)
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
    stopBroadcastBtn:SetSize(55, 22)
    stopBroadcastBtn:SetPoint("LEFT", clearBtn, "RIGHT", 5, 0)
    stopBroadcastBtn:SetText("Stop")
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
    detailsPanel:SetHeight(312)  -- room for the 4-row Looking For section (queue panel below is elastic)
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

    -- Weekly raid quest badge (shows which weekly a listing satisfies)
    local weeklyIndicator = detContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    weeklyIndicator:SetPoint("LEFT", lockoutIndicator, "RIGHT", 6, 0)
    weeklyIndicator:Hide()
    container.weeklyIndicator = weeklyIndicator

    -- FontStrings can't receive mouse events in this client - an invisible
    -- frame anchored to the same bounds (SetAllPoints tracks the FontString
    -- live as its text/width changes) is what makes the embedded quest link
    -- show a real tooltip on hover, same idea as the achievement-link hover
    -- in GUI.SetupMessageBoxAchievementTooltips. Only shown/interactive when
    -- GUI.RefreshBrowserTab actually has a real link to offer (see
    -- container.weeklyQuestLink).
    local weeklyHoverFrame = CreateFrame("Frame", nil, detContent)
    weeklyHoverFrame:SetAllPoints(weeklyIndicator)
    weeklyHoverFrame:EnableMouse(true)
    weeklyHoverFrame:Hide()
    weeklyHoverFrame:SetScript("OnEnter", function(self)
        if container.weeklyQuestLink then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(container.weeklyQuestLink)
            GameTooltip:Show()
        end
    end)
    weeklyHoverFrame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.weeklyHoverFrame = weeklyHoverFrame

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
    lookingForFrame:SetHeight(54)  -- four fixed role rows
    container.lookingForFrame = lookingForFrame

    -- Four fixed role sections (Tanks / Heals / Melee / Ranged), each a
    -- single clipped line listing the wanted classes as an array; the hover
    -- tooltip keeps the full per-spec detail
    container.lookingForRoleMeta = {
        {key = "TANK",   label = "Tanks",  hex = "00FFFF"},
        {key = "HEALER", label = "Heals",  hex = "00FF00"},
        {key = "MDPS",   label = "Melee",  hex = "FF6666"},
        {key = "RDPS",   label = "Ranged", hex = "FFFF00"},
    }
    container.lookingForRoleLines = {}
    for idx, r in ipairs(container.lookingForRoleMeta) do
        local line = lookingForFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        line:SetPoint("TOPLEFT", 0, -(idx - 1) * 13)
        line:SetPoint("RIGHT", -5, 0)
        line:SetHeight(12)
        line:SetJustifyH("LEFT")
        if line.SetWordWrap then line:SetWordWrap(false) end
        container.lookingForRoleLines[r.key] = line
    end

    -- Store class buttons for reuse
    container.lookingForButtons = {}

    -- Details action buttons - Apply (structured DataBus application to AIP
    -- peers with status ACKs; detailed whisper to everyone else)
    local requestInviteBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    requestInviteBtn:SetSize(120, 24)
    requestInviteBtn:SetPoint("BOTTOMLEFT", 10, 8)
    requestInviteBtn:SetText("Apply")
    requestInviteBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        -- The details panel shows both leader-keyed group rows AND name-keyed
        -- LFG player rows (see GUI.UpdateDetailsPanel) - guarding on
        -- data.leader alone silently no-ops for the latter.
        local name = data and (data.leader or data.name)
        if not data or not name then
            AIP.Print("Select a group first")
            return
        end

        -- AIP peer: structured application over the DataBus (seen/queued/
        -- invited/declined status comes back automatically)
        if AIP.Apply and AIP.Apply.SendApply and AIP.Apply.SendApply(data) then
            if AIP.ChatScanner and AIP.ChatScanner.MarkRequested then
                AIP.ChatScanner.MarkRequested(name)
                GUI.RefreshBrowserTab(tabType)
            end
            GUI.UpdateApplyStatus(container, data)
            return
        end

        -- Non-peer fallback: detailed whisper with player info
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
        SendChatMessage(msg, "WHISPER", nil, name)
        AIP.Print("Invite request sent to " .. name)
        if AIP.Apply and AIP.Apply.MarkWhispered then
            AIP.Apply.MarkWhispered(name, data.raid)
        end
        GUI.UpdateApplyStatus(container, data)

        -- Track the request so the row can be marked/hidden until it expires
        if AIP.ChatScanner and AIP.ChatScanner.MarkRequested then
            AIP.ChatScanner.MarkRequested(name)
            GUI.RefreshBrowserTab(tabType)
        end
    end)
    requestInviteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Apply")
        GameTooltip:AddLine("AIP leaders: structured application with", 1, 1, 1)
        GameTooltip:AddLine("live status (seen/queued/invited).", 1, 1, 1)
        GameTooltip:AddLine("Others: detailed whisper with your stats.", 1, 1, 1)
        GameTooltip:Show()
    end)
    requestInviteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.requestInviteBtn = requestInviteBtn

    -- Application status line ("Queued #4") above the action buttons
    local applyStatus = detailsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    applyStatus:SetPoint("BOTTOMLEFT", 12, 34)
    applyStatus:SetText("")
    container.applyStatus = applyStatus

    -- Quick Request button - sends autoinvite keyword
    local quickRequestBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    quickRequestBtn:SetSize(90, 24)
    quickRequestBtn:SetPoint("LEFT", requestInviteBtn, "RIGHT", 5, 0)
    quickRequestBtn:SetText("Instant Join")
    quickRequestBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        local name = data and (data.leader or data.name)
        if not data or not name then
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
        SendChatMessage(keyword, "WHISPER", nil, name)
        AIP.Print("Quick request sent to " .. name .. " with keyword: |cFF00FFFF" .. keyword .. "|r")

        -- Track the request so the row can be marked/hidden until it expires
        if AIP.ChatScanner and AIP.ChatScanner.MarkRequested then
            AIP.ChatScanner.MarkRequested(name)
            GUI.RefreshBrowserTab(tabType)
        end
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
        GameTooltip:AddLine("Instant Join")
        GameTooltip:AddLine("Sends the autoinvite keyword to the group leader", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Detected keyword: |cFF00FFFF" .. keyword .. "|r", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    quickRequestBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.quickRequestBtn = quickRequestBtn

    local blacklistBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    blacklistBtn:SetSize(64, 24)
    blacklistBtn:SetPoint("LEFT", quickRequestBtn, "RIGHT", 5, 0)
    blacklistBtn:SetText("Block")
    blacklistBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        local name = data and (data.leader or data.name)
        if name then
            AIP.AddToBlacklist(name, "From LFM browser", "lfm")
            GUI.RefreshBrowserTab(tabType)
        else
            AIP.Print("Select a group first")
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
    whisperBtn:SetSize(64, 24)
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

    -- Hide/Unhide button - exclude a listing we can't join (requested/no reply,
    -- or just not interested). Stays hidden until the listing expires.
    local hideBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    hideBtn:SetSize(64, 24)
    hideBtn:SetPoint("LEFT", whisperBtn, "RIGHT", 5, 0)
    hideBtn:SetText("Hide")
    hideBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        local CS = AIP.ChatScanner
        local name = data and (data.leader or data.name)
        if not name or not CS then
            AIP.Print("Select a group first")
            return
        end
        if CS.IsExcluded(name) then
            CS.ClearExcluded(name)
            AIP.Print("Unhid " .. name .. "'s listing")
        else
            CS.MarkExcluded(name)
            AIP.Print("Hid " .. name .. "'s listing")
        end
        GUI.RefreshBrowserTab(tabType)
    end)
    hideBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local data = container.selectedGroupData
        local hidden = data and data.leader and AIP.ChatScanner
            and AIP.ChatScanner.IsExcluded(data.leader)
        if hidden then
            GameTooltip:AddLine("Unhide")
            GameTooltip:AddLine("Show this listing again", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Hide")
            GameTooltip:AddLine("Hide this listing until it expires (already requested / not interested)", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.hideBtn = hideBtn

    -- Favorite/Unfavorite button - add the leader (or LFG player) to favorites so
    -- their listings are highlighted and they get priority in the queue.
    local favBtn = CreateFrame("Button", nil, detailsPanel, "UIPanelButtonTemplate")
    favBtn:SetSize(64, 24)
    favBtn:SetPoint("LEFT", hideBtn, "RIGHT", 5, 0)
    favBtn:SetText("Fav")
    favBtn:SetScript("OnClick", function()
        local data = container.selectedGroupData
        local name = data and (data.leader or data.name)
        if not name then
            AIP.Print("Select a listing first")
            return
        end
        local isFav = AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(name)
        if isFav then
            if AIP.RemoveFromFavorites then AIP.RemoveFromFavorites(name) end
        else
            if AIP.AddToFavorites then AIP.AddToFavorites(name, "", "browser") end
        end
        GUI.UpdateDetailsPanel(container, data)  -- refresh this button's label
        GUI.RefreshBrowserTab(tabType)           -- refresh row highlight
    end)
    favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        local data = container.selectedGroupData
        local name = data and (data.leader or data.name)
        local isFav = name and AIP.IsPlayerFavorite and AIP.IsPlayerFavorite(name)
        if isFav then
            GameTooltip:AddLine("Remove Favorite")
            GameTooltip:AddLine("Stop highlighting and prioritizing this player", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Add Favorite")
            GameTooltip:AddLine("Highlight this player's listings and give them queue priority", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.favBtn = favBtn

    -- ========================================================================
    -- FRAME 3: RIGHT BOTTOM - Queue Panel
    -- ========================================================================
    local queuePanel = CreateFrame("Frame", nil, container)
    queuePanel:SetPoint("TOPLEFT", detailsPanel, "BOTTOMLEFT", 0, -5)
    queuePanel:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    GUI.ApplyBackdrop(queuePanel, "SubPanel", 0.95)
    container.queuePanel = queuePanel

    -- Elastic lists: when this panel resizes (window resize / maximize /
    -- restore / minimize-expand all propagate down to here), recompute how many
    -- Queue/LFG/Waitlist rows fit and refresh so rows never overflow the panel.
    queuePanel:SetScript("OnSizeChanged", function()
        GUI.LayoutQueueColumns(container)
        GUI.UpdateQueuePanel(container)
    end)

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

    -- === QUEUE CONTENT (Whisper requests) ===
    local queueContent = CreateFrame("Frame", nil, queuePanel)
    queueContent:SetPoint("TOPLEFT", 5, -30)
    queueContent:SetPoint("BOTTOMRIGHT", -5, 30)
    container.queueContent = queueContent

    local queueEmptyText = queueContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    queueEmptyText:SetPoint("CENTER", 0, 0)
    queueEmptyText:SetWidth(360)
    queueEmptyText:SetJustifyH("CENTER")
    queueEmptyText:SetText("Queue is empty\n\n|cFF888888Players who whisper your invite keyword land here.\nStructured applications go to the Waitlist tab by default\n(or here if 'Apply to Waitlist' is off in Settings).|r")
    queueEmptyText:SetTextColor(0.55, 0.55, 0.55)
    queueEmptyText:Hide()
    container.queueEmptyText = queueEmptyText

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
    container.queueHeaderLabels = {}
    for idx, h in ipairs(qHeaders) do
        local label = queueContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, GUI.QUEUE_HEADER_Y)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
        container.queueHeaderLabels[idx] = label
    end

    -- Header control cluster (right-aligned, single row, chained left-to-right):
    -- [Search: label] [search box] [+ Add] [Invite All]. All parented to
    -- queueContent so they track the same right edge as the data area.

    -- Invite All button (rightmost)
    local inviteAllBtn = CreateFrame("Button", nil, queueContent, "UIPanelButtonTemplate")
    inviteAllBtn:SetSize(70, 18)
    inviteAllBtn:SetPoint("TOPRIGHT", -5, 0)
    inviteAllBtn:SetText("Invite All")
    inviteAllBtn:SetScript("OnClick", function()
        if AIP.InviteAllFromQueue then AIP.InviteAllFromQueue() end
    end)
    container.inviteAllBtn = inviteAllBtn

    -- Add Player button for queue
    local addQueueBtn = CreateFrame("Button", nil, queueContent, "UIPanelButtonTemplate")
    addQueueBtn:SetSize(70, 18)
    addQueueBtn:SetPoint("RIGHT", inviteAllBtn, "LEFT", -5, 0)
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

    -- Search box for queue
    local queueSearchBox = CreateFrame("EditBox", "AIPQueueSearch", queueContent, "InputBoxTemplate")
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(queueSearchBox) end
    queueSearchBox:SetSize(100, 16)
    queueSearchBox:SetPoint("RIGHT", addQueueBtn, "LEFT", -12, 0)
    queueSearchBox:SetAutoFocus(false)
    queueSearchBox:SetScript("OnTextChanged", function(self)
        container.queueSearchFilter = self:GetText():lower()
        GUI.UpdateQueuePanel(container)
    end)
    queueSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    queueSearchBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Search Queue")
        GameTooltip:AddLine("Filter by player name or message", 1, 1, 1)
        GameTooltip:Show()
    end)
    queueSearchBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.queueSearchBox = queueSearchBox
    container.queueSearchFilter = ""

    -- "Search:" label (leftmost in the cluster)
    local queueSearchLabel = queueContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    queueSearchLabel:SetPoint("RIGHT", queueSearchBox, "LEFT", -8, 0)
    queueSearchLabel:SetText("Search:")
    queueSearchLabel:SetTextColor(0.8, 0.8, 0.8)

    -- Queue rows (whisper requests)
    -- Pool is created at QUEUE_MAX_ROWS; how many actually render is computed
    -- elastically from the content frame height (see GUI.QueueVisibleRows).
    container.queueRows = {}
    local ROW_HEIGHT = GUI.QUEUE_ROW_HEIGHT
    local NUM_ROWS = GUI.QUEUE_MAX_ROWS
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, queueContent)
        row:SetSize(500, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -GUI.QUEUE_HEADER_INSET - ((i - 1) * ROW_HEIGHT))
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

            -- Route through the queue module: AIP.MoveToWaitlist dedupes,
            -- sends the position whisper, removes the queue entry AND carries
            -- the structured application fields (spec/ilvl/weekly/
            -- isApplication) so the truthful-ACK ladder survives the move.
            if AIP.MoveToWaitlist and AIP.db and AIP.db.queue then
                for qi, qEntry in ipairs(AIP.db.queue) do
                    if qEntry.name and qEntry.name:lower() == entry.name:lower() then
                        AIP.MoveToWaitlist(qi, entry.role, "Moved from queue")
                        break
                    end
                end
            else
                AIP.Print("Queue module not available")
            end

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

        -- Whisper button
        row.whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisperBtn:SetSize(22, 16)
        row.whisperBtn:SetPoint("LEFT", 470, 0)
        row.whisperBtn:SetText("W")
        row.whisperBtn.index = i
        row.whisperBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and entry.name then
                ChatFrame_OpenChat("/w " .. entry.name .. " ", DEFAULT_CHAT_FRAME)
            end
        end)
        row.whisperBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Whisper")
            GameTooltip:AddLine("Open whisper to this player", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.whisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Hide()
        container.queueRows[i] = row
    end

    -- === LFG CONTENT (Enrollment broadcasts) ===
    local lfgContent = CreateFrame("Frame", nil, queuePanel)
    lfgContent:SetPoint("TOPLEFT", 5, -30)
    lfgContent:SetPoint("BOTTOMRIGHT", -5, 30)
    lfgContent:Hide()
    container.lfgContent = lfgContent

    local lfgEmptyText = lfgContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lfgEmptyText:SetPoint("CENTER", 0, 0)
    lfgEmptyText:SetWidth(360)
    lfgEmptyText:SetJustifyH("CENTER")
    lfgEmptyText:SetText("No LFG players seen yet\n\n|cFF888888Players broadcasting LFG - from chat or\nAIP peers - appear here, best fit first.|r")
    lfgEmptyText:SetTextColor(0.55, 0.55, 0.55)
    lfgEmptyText:Hide()
    container.lfgEmptyText = lfgEmptyText

    -- LFG column headers
    local lfgHeaders = {
        {text = "#", x = 5, width = 20},
        {text = "Player", x = 25, width = 90},
        {text = "Spec", x = 115, width = 70},
        {text = "Raid", x = 185, width = 80},
        {text = "GS", x = 265, width = 50},
        {text = "Actions", x = 320, width = 180},
    }
    container.lfgHeaderLabels = {}
    for idx, h in ipairs(lfgHeaders) do
        local label = lfgContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, GUI.QUEUE_HEADER_Y)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
        container.lfgHeaderLabels[idx] = label
    end

    -- Header control cluster (right-aligned, single row): [Search: label]
    -- [search box]. LFG has no +Add or Invite All. Parented to lfgContent.

    -- Search box for LFG (rightmost)
    local lfgSearchBox = CreateFrame("EditBox", "AIPLfgSearch", lfgContent, "InputBoxTemplate")
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(lfgSearchBox) end
    lfgSearchBox:SetSize(100, 16)
    lfgSearchBox:SetPoint("TOPRIGHT", -5, 0)
    lfgSearchBox:SetAutoFocus(false)
    lfgSearchBox:SetScript("OnTextChanged", function(self)
        container.lfgSearchFilter = self:GetText():lower()
        GUI.UpdateQueuePanel(container)
    end)
    lfgSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    lfgSearchBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Search LFG")
        GameTooltip:AddLine("Filter by player name, spec, or raid", 1, 1, 1)
        GameTooltip:Show()
    end)
    lfgSearchBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.lfgSearchBox = lfgSearchBox
    container.lfgSearchFilter = ""

    -- "Search:" label (leftmost in the cluster)
    local lfgSearchLabel = lfgContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lfgSearchLabel:SetPoint("RIGHT", lfgSearchBox, "LEFT", -8, 0)
    lfgSearchLabel:SetText("Search:")
    lfgSearchLabel:SetTextColor(0.8, 0.8, 0.8)

    -- LFG rows (enrollment broadcasts)
    container.lfgRows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, lfgContent)
        row:SetSize(500, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -GUI.QUEUE_HEADER_INSET - ((i - 1) * ROW_HEIGHT))
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

                -- Full shared character card (gear + achievements) if broadcast / self.
                if AIP.CharCard and AIP.CharCard.AppendToTooltip then
                    AIP.CharCard.AppendToTooltip(GameTooltip, entry.name, entry.isSelf)
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

    local waitlistEmptyText = waitlistContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    waitlistEmptyText:SetPoint("CENTER", 0, 0)
    waitlistEmptyText:SetWidth(360)
    waitlistEmptyText:SetJustifyH("CENTER")
    waitlistEmptyText:SetText("Waitlist is empty\n\n|cFF888888Park overflow players here - they are\nwhispered when their turn comes.|r")
    waitlistEmptyText:SetTextColor(0.55, 0.55, 0.55)
    waitlistEmptyText:Hide()
    container.waitlistEmptyText = waitlistEmptyText

    -- Waitlist column headers (order must match WAITLIST_COLS + Actions last)
    local wlHeaders = {
        {text = "#", x = 5, width = 20},
        {text = "Player", x = 25, width = 90},
        {text = "Role", x = 115, width = 50},
        {text = "GS", x = 165, width = 45},
        {text = "Note", x = 210, width = 95},
        {text = "Added", x = 305, width = 50},
        {text = "Actions", x = 360, width = 100},
    }
    container.waitlistHeaderLabels = {}
    for idx, h in ipairs(wlHeaders) do
        local label = waitlistContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", h.x, GUI.QUEUE_HEADER_Y)
        label:SetWidth(h.width)
        label:SetText(h.text)
        label:SetTextColor(0.8, 0.8, 0.8)
        container.waitlistHeaderLabels[idx] = label
    end

    -- Header control cluster (right-aligned, single row, chained):
    -- [Search: label] [search box] [+ Add]. Waitlist has no Invite All.
    -- Parented to waitlistContent so they track the data area's right edge.

    -- Add Player button for waitlist (rightmost)
    local addWaitlistBtn = CreateFrame("Button", nil, waitlistContent, "UIPanelButtonTemplate")
    addWaitlistBtn:SetSize(70, 18)
    addWaitlistBtn:SetPoint("TOPRIGHT", -5, 0)
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

    -- Search box for waitlist
    local waitlistSearchBox = CreateFrame("EditBox", "AIPWaitlistSearch", waitlistContent, "InputBoxTemplate")
    if AIP.UI and AIP.UI.StyleEditBox then AIP.UI.StyleEditBox(waitlistSearchBox) end
    waitlistSearchBox:SetSize(100, 16)
    waitlistSearchBox:SetPoint("RIGHT", addWaitlistBtn, "LEFT", -12, 0)
    waitlistSearchBox:SetAutoFocus(false)
    waitlistSearchBox:SetScript("OnTextChanged", function(self)
        container.waitlistSearchFilter = self:GetText():lower()
        GUI.UpdateQueuePanel(container)
    end)
    waitlistSearchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    waitlistSearchBox:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Search Waitlist")
        GameTooltip:AddLine("Filter by player name, role, or note", 1, 1, 1)
        GameTooltip:Show()
    end)
    waitlistSearchBox:SetScript("OnLeave", function() GameTooltip:Hide() end)
    container.waitlistSearchBox = waitlistSearchBox
    container.waitlistSearchFilter = ""

    -- "Search:" label (leftmost in the cluster)
    local waitlistSearchLabel = waitlistContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    waitlistSearchLabel:SetPoint("RIGHT", waitlistSearchBox, "LEFT", -8, 0)
    waitlistSearchLabel:SetText("Search:")
    waitlistSearchLabel:SetTextColor(0.8, 0.8, 0.8)

    -- Waitlist rows
    container.waitlistRows = {}
    for i = 1, NUM_ROWS do
        local row = CreateFrame("Frame", nil, waitlistContent)
        row:SetSize(480, ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -GUI.QUEUE_HEADER_INSET - ((i - 1) * ROW_HEIGHT))
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
        row.gsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.gsText:SetPoint("LEFT", 165, 0)
        row.gsText:SetWidth(45)
        row.gsText:SetJustifyH("LEFT")
        row.gsText:SetTextColor(0.7, 0.7, 0.7)
        row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.noteText:SetPoint("LEFT", 210, 0)
        row.noteText:SetWidth(95)
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
                -- Route through the waitlist module so the invite whisper and
                -- the truthful APPLYACK ladder (Apply.NotifyInvited) both fire
                if AIP.InviteFromWaitlist then
                    AIP.InviteFromWaitlist(entry.name)
                else
                    InviteUnit(entry.name)
                    AIP.Print("Invited " .. entry.name .. " from waitlist")
                    table.remove(AIP.db.waitlist, self.index)
                    for j, e in ipairs(AIP.db.waitlist) do
                        e.priority = j
                    end
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
            local entry = entries[self.index]
            if not entry then return end
            -- Route through the waitlist module: it renumbers AND whispers the
            -- affected players their new positions (the old inline swap did not)
            if AIP.MoveWaitlistUp then
                AIP.MoveWaitlistUp(entry.name)
            elseif self.index > 1 then
                entries[self.index], entries[self.index - 1] = entries[self.index - 1], entries[self.index]
                if AIP.Utils then AIP.Utils.RenumberPriorities(entries) end
            end
            GUI.UpdateQueuePanel(container)
        end)
        row.upBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move Up")
            GameTooltip:AddLine("Increase priority (move up in list).", 1, 1, 1)
            GameTooltip:AddLine("Both affected players are whispered their new position.", 0.7, 0.7, 0.7)
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
            local entry = entries[self.index]
            if not entry then return end
            if AIP.MoveWaitlistDown then
                AIP.MoveWaitlistDown(entry.name)
            elseif self.index < #entries then
                entries[self.index], entries[self.index + 1] = entries[self.index + 1], entries[self.index]
                if AIP.Utils then AIP.Utils.RenumberPriorities(entries) end
            end
            GUI.UpdateQueuePanel(container)
        end)
        row.downBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Move Down")
            GameTooltip:AddLine("Decrease priority (move down in list).", 1, 1, 1)
            GameTooltip:AddLine("Both affected players are whispered their new position.", 0.7, 0.7, 0.7)
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
                -- Route through the waitlist module so protocol applicants get
                -- their truthful "declined" APPLYACK (Apply.NotifyDeclined)
                if AIP.RemoveFromWaitlist then
                    AIP.RemoveFromWaitlist(entry.name)
                else
                    local removedName = entry.name
                    table.remove(AIP.db.waitlist, self.index)
                    for j, e in ipairs(AIP.db.waitlist) do
                        e.priority = j
                    end
                    AIP.Print("Removed " .. removedName .. " from waitlist")
                end
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

        -- Whisper button
        row.whisperBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        row.whisperBtn:SetSize(22, 16)
        row.whisperBtn:SetPoint("LEFT", 469, 0)
        row.whisperBtn:SetText("W")
        row.whisperBtn.index = i
        row.whisperBtn:SetScript("OnClick", function(self)
            local entries = AIP.db and AIP.db.waitlist or {}
            local entry = entries[self.index]
            if entry and entry.name then
                ChatFrame_OpenChat("/w " .. entry.name .. " ", DEFAULT_CHAT_FRAME)
            end
        end)
        row.whisperBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Whisper")
            GameTooltip:AddLine("Open whisper to this player", 1, 1, 1)
            GameTooltip:Show()
        end)
        row.whisperBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
            if e.spec then GameTooltip:AddDoubleLine("Spec:", e.spec, 0.7, 0.7, 0.7, 0.8, 0.8, 0.8) end
            if e.ilvl then GameTooltip:AddDoubleLine("iLvl:", tostring(e.ilvl), 0.7, 0.7, 0.7, 0.8, 0.8, 0.8) end
            if e.weekly then GameTooltip:AddDoubleLine("Weekly:", e.weekly, 0.7, 0.7, 0.7, 0.2, 0.8, 1) end
            if e.note and e.note ~= "" then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Note: " .. e.note, 1, 1, 1, true)
            end
            if e.isApplication then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("|cFF33CCFFStructured application (AIP peer)|r")
                GameTooltip:AddLine("Invite/remove here sends them a truthful status update.", 0.7, 0.7, 0.7)
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
    queueStatus:SetText("Queue: 0 | Waitlist: 0")
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
                for i, row in ipairs(container.waitlistRows) do
                    if row:IsShown() and row.timeText and row.entryData and row.entryData.addedTime then
                        local elapsed = time() - row.entryData.addedTime
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
            -- Also clear LFG entries from the queue
            if AIP.db and AIP.db.queue then
                for i = #AIP.db.queue, 1, -1 do
                    if AIP.db.queue[i].isLfgEnrollment then
                        table.remove(AIP.db.queue, i)
                    end
                end
            end
            -- Clear DataBus LFG listings if available
            if AIP.DataBus and AIP.DataBus.ClearLFGListings then
                AIP.DataBus.ClearLFGListings()
            end
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

    -- Initial column layout. Deferred so the content frames have their real
    -- (anchor-derived) width before we measure it; also covers the case where
    -- the panel is created while hidden.
    GUI.LayoutQueueColumns(container)
    if AIP.Utils and AIP.Utils.DelayedCall then
        AIP.Utils.DelayedCall(0.1, function() GUI.LayoutQueueColumns(container) end)
    end
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
