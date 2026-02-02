-- AutoInvite Plus - Blacklist Panel (Enhanced v4.1)
-- Blacklist management panel with search, filter, and export/import

local AIP = AutoInvitePlus
AIP.Panels = AIP.Panels or {}
AIP.Panels.Blacklist = {}
local BP = AIP.Panels.Blacklist

-- Panel state
BP.Frame = nil
BP.Rows = {}
BP.RowsVisible = 14
BP.SearchFilter = ""
BP.SourceFilter = "all"

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

-- Create the blacklist panel
function BP.Create(parent)
    if BP.Frame then return BP.Frame end

    local frame = CreateFrame("Frame", "AIPBlacklistPanel", parent)
    frame:SetAllPoints()

    local y = -10

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, y)
    title:SetText("Blacklist Management")
    title:SetTextColor(1, 0.82, 0)
    y = y - 25

    -- Search and filter row
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 10, y)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", "AIPBlacklistPanelSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            BP.SearchFilter = self:GetText():lower()
            BP.Update()
        end
    end)
    searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    frame.searchBox = searchBox

    local filterLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    filterLabel:SetText("Source:")

    local filterDropdown = CreateFrame("Frame", "AIPBlacklistFilter", frame, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("LEFT", filterLabel, "RIGHT", -5, -3)
    UIDropDownMenu_SetWidth(filterDropdown, 90)
    UIDropDownMenu_SetText(filterDropdown, "All")

    local function FilterDropdown_Initialize()
        -- Build filter list dynamically based on actual sources in blacklist
        local sourceCounts = {}
        local sourceNames = {
            all = "All",
            manual = "Manual",
            queue = "From Queue",
            lfm = "From LFM",
            roster = "From Roster",
            import = "Imported",
        }

        -- Count sources in actual blacklist
        if AIP.db and AIP.db.blacklist then
            for _, entry in pairs(AIP.db.blacklist) do
                local source = entry.source or "manual"
                sourceCounts[source] = (sourceCounts[source] or 0) + 1
            end
        end

        -- Always add "All" first
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All"
        info.value = "all"
        info.func = function(self)
            BP.SourceFilter = "all"
            UIDropDownMenu_SetText(filterDropdown, "All")
            BP.Update()
        end
        info.checked = (BP.SourceFilter == "all")
        UIDropDownMenu_AddButton(info)

        -- Add sources that exist in the blacklist
        local orderedSources = {"manual", "queue", "lfm", "roster", "import"}
        for _, source in ipairs(orderedSources) do
            if sourceCounts[source] and sourceCounts[source] > 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = (sourceNames[source] or source) .. " (" .. sourceCounts[source] .. ")"
                info.value = source
                info.func = function(self)
                    BP.SourceFilter = source
                    UIDropDownMenu_SetText(filterDropdown, sourceNames[source] or source)
                    BP.Update()
                end
                info.checked = (BP.SourceFilter == source)
                UIDropDownMenu_AddButton(info)
            end
        end

        -- Add any other sources that might exist
        for source, count in pairs(sourceCounts) do
            local found = false
            for _, s in ipairs(orderedSources) do
                if s == source then found = true break end
            end
            if not found and count > 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = (sourceNames[source] or source) .. " (" .. count .. ")"
                info.value = source
                info.func = function(self)
                    BP.SourceFilter = source
                    UIDropDownMenu_SetText(filterDropdown, sourceNames[source] or source)
                    BP.Update()
                end
                info.checked = (BP.SourceFilter == source)
                UIDropDownMenu_AddButton(info)
            end
        end
    end
    UIDropDownMenu_Initialize(filterDropdown, FilterDropdown_Initialize)
    FixDropdownStrata(filterDropdown)

    -- Clear History button
    local clearHistoryBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearHistoryBtn:SetSize(85, 20)
    clearHistoryBtn:SetPoint("TOPRIGHT", -10, y)
    clearHistoryBtn:SetText("Clear History")
    clearHistoryBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_BL_HISTORY"] = {
            text = "Clear entire blacklist?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if AIP.ClearBlacklist then AIP.ClearBlacklist() end
                BP.Update()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_BL_HISTORY")
    end)
    y = y - 30

    -- Add new player row
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 10, y)
    addLabel:SetText("ADD:")

    local nameInput = CreateFrame("EditBox", "AIPBlacklistNameInput", frame, "InputBoxTemplate")
    nameInput:SetSize(100, 20)
    nameInput:SetPoint("LEFT", addLabel, "RIGHT", 5, 0)
    nameInput:SetAutoFocus(false)
    frame.nameInput = nameInput

    local namePlaceholder = nameInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    namePlaceholder:SetPoint("LEFT", 5, 0)
    namePlaceholder:SetText("Player name")
    namePlaceholder:SetTextColor(0.5, 0.5, 0.5)
    nameInput:SetScript("OnTextChanged", function(self)
        namePlaceholder:SetShown(self:GetText() == "")
    end)

    local reasonInput = CreateFrame("EditBox", "AIPBlacklistReasonInput", frame, "InputBoxTemplate")
    reasonInput:SetSize(200, 20)
    reasonInput:SetPoint("LEFT", nameInput, "RIGHT", 5, 0)
    reasonInput:SetAutoFocus(false)
    frame.reasonInput = reasonInput

    local reasonPlaceholder = reasonInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    reasonPlaceholder:SetPoint("LEFT", 5, 0)
    reasonPlaceholder:SetText("Reason (optional)")
    reasonPlaceholder:SetTextColor(0.5, 0.5, 0.5)
    reasonInput:SetScript("OnTextChanged", function(self)
        reasonPlaceholder:SetShown(self:GetText() == "")
    end)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(100, 20)
    addBtn:SetPoint("LEFT", reasonInput, "RIGHT", 5, 0)
    addBtn:SetText("Add to Blacklist")
    addBtn:SetScript("OnClick", function()
        local name = nameInput:GetText():trim()
        local reason = reasonInput:GetText():trim()
        if name ~= "" then
            if reason == "" then reason = nil end
            AIP.AddToBlacklist(name, reason, "manual")
            nameInput:SetText("")
            reasonInput:SetText("")
            nameInput:ClearFocus()
            reasonInput:ClearFocus()
            BP.Update()
        end
    end)

    nameInput:SetScript("OnEnterPressed", function(self)
        reasonInput:SetFocus()
    end)
    reasonInput:SetScript("OnEnterPressed", function(self)
        local name = nameInput:GetText():trim()
        local reason = self:GetText():trim()
        if name ~= "" then
            if reason == "" then reason = nil end
            AIP.AddToBlacklist(name, reason, "manual")
            nameInput:SetText("")
            self:SetText("")
            nameInput:ClearFocus()
            self:ClearFocus()
            BP.Update()
        end
    end)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    reasonInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    y = y - 30

    -- Column headers
    local headers = {
        {text = "Player", width = 110, x = 15},
        {text = "Date Added", width = 85, x = 130},
        {text = "Reason", width = 200, x = 220},
        {text = "Source", width = 70, x = 425},
        {text = "Actions", width = 80, x = 500},
    }

    for _, h in ipairs(headers) do
        local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        header:SetPoint("TOPLEFT", h.x, y)
        header:SetWidth(h.width)
        header:SetJustifyH("LEFT")
        header:SetText(h.text)
        header:SetTextColor(1, 0.82, 0)
    end
    y = y - 18

    -- Divider line
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", 10, y)
    divider:SetPoint("TOPRIGHT", -10, y)
    divider:SetTexture(0.5, 0.5, 0.5, 0.5)
    y = y - 5

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "AIPBlacklistPanelScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, y)
    scrollFrame:SetPoint("BOTTOMRIGHT", -28, 40)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 22, BP.Update)
    end)
    frame.scrollFrame = scrollFrame

    -- Create row buttons
    for i = 1, BP.RowsVisible do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(580, 22)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 10, -((i - 1) * 22))

        -- Highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.3)

        -- Player name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetWidth(110)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Added date
        local dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("LEFT", 115, 0)
        dateText:SetWidth(85)
        dateText:SetJustifyH("LEFT")
        dateText:SetTextColor(0.5, 0.5, 0.5)
        row.dateText = dateText

        -- Reason
        local reasonText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        reasonText:SetPoint("LEFT", 205, 0)
        reasonText:SetWidth(200)
        reasonText:SetJustifyH("LEFT")
        reasonText:SetTextColor(0.7, 0.7, 0.7)
        row.reasonText = reasonText

        -- Source
        local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sourceText:SetPoint("LEFT", 410, 0)
        sourceText:SetWidth(70)
        sourceText:SetJustifyH("LEFT")
        sourceText:SetTextColor(0.6, 0.6, 0.6)
        row.sourceText = sourceText

        -- Edit button
        local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        editBtn:SetSize(35, 18)
        editBtn:SetPoint("LEFT", 485, 0)
        editBtn:SetText("Edit")
        editBtn.index = i
        editBtn:SetScript("OnClick", function(self)
            if row.playerName then
                BP.ShowEditDialog(row.playerName)
            end
        end)
        row.editBtn = editBtn

        -- Remove button
        local remBtn = CreateFrame("Button", nil, row, "UIPanelCloseButton")
        remBtn:SetSize(20, 20)
        remBtn:SetPoint("LEFT", editBtn, "RIGHT", 3, 0)
        remBtn.index = i
        remBtn:SetScript("OnClick", function(self)
            if row.playerName then
                StaticPopupDialogs["AIP_REMOVE_BL_" .. i] = {
                    text = "Remove " .. row.playerName .. " from blacklist?",
                    button1 = "Yes",
                    button2 = "No",
                    OnAccept = function()
                        AIP.RemoveFromBlacklist(row.playerName)
                        BP.Update()
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                }
                StaticPopup_Show("AIP_REMOVE_BL_" .. i)
            end
        end)
        row.remBtn = remBtn

        row:Hide()
        BP.Rows[i] = row
    end

    -- Empty state message
    local emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    emptyText:SetText("Blacklist is empty\n\nAdd players to prevent them from being auto-invited")
    emptyText:SetTextColor(0.5, 0.5, 0.5)
    frame.emptyText = emptyText

    -- Bottom status bar
    local statusFrame = CreateFrame("Frame", nil, frame)
    statusFrame:SetHeight(30)
    statusFrame:SetPoint("BOTTOMLEFT", 10, 5)
    statusFrame:SetPoint("BOTTOMRIGHT", -10, 5)

    local statusText = statusFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("LEFT")
    statusText:SetText("Total: 0 players")
    frame.statusText = statusText

    -- Export button
    local exportBtn = CreateFrame("Button", nil, statusFrame, "UIPanelButtonTemplate")
    exportBtn:SetSize(60, 20)
    exportBtn:SetPoint("RIGHT", -140, 0)
    exportBtn:SetText("Export")
    exportBtn:SetScript("OnClick", function()
        BP.ShowExportPopup()
    end)

    -- Import button
    local importBtn = CreateFrame("Button", nil, statusFrame, "UIPanelButtonTemplate")
    importBtn:SetSize(60, 20)
    importBtn:SetPoint("RIGHT", -75, 0)
    importBtn:SetText("Import")
    importBtn:SetScript("OnClick", function()
        BP.ShowImportPopup()
    end)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, statusFrame, "UIPanelButtonTemplate")
    clearBtn:SetSize(60, 20)
    clearBtn:SetPoint("RIGHT", -10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_BL_PANEL"] = {
            text = "Clear entire blacklist?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if AIP.ClearBlacklist then AIP.ClearBlacklist() end
                BP.Update()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_BL_PANEL")
    end)

    BP.Frame = frame
    return frame
end

-- Show edit dialog
function BP.ShowEditDialog(playerName)
    local entry = AIP.GetBlacklistEntry and AIP.GetBlacklistEntry(playerName)
    local currentReason = entry and entry.reason or ""
    local currentNotes = entry and entry.notes or ""

    StaticPopupDialogs["AIP_EDIT_BL_ENTRY"] = {
        text = "Edit blacklist entry for " .. playerName .. ":\n\nReason:",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        OnShow = function(self)
            self.editBox:SetText(currentReason)
            self.editBox:SetFocus()
        end,
        OnAccept = function(self)
            local newReason = self.editBox:GetText()
            if AIP.UpdateBlacklistEntry then
                AIP.UpdateBlacklistEntry(playerName, newReason, nil)
            end
            BP.Update()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("AIP_EDIT_BL_ENTRY")
end

-- Update the blacklist panel (v4.1 - uses new data structure)
function BP.Update()
    if not BP.Frame then return end

    -- Use new GetBlacklistEntries function with filters
    local entries = {}
    if AIP.GetBlacklistEntries then
        entries = AIP.GetBlacklistEntries(BP.SearchFilter, BP.SourceFilter)
    end

    local numEntries = #entries

    -- Show/hide empty state message
    if BP.Frame.emptyText then
        if numEntries == 0 then
            BP.Frame.emptyText:Show()
        else
            BP.Frame.emptyText:Hide()
        end
    end

    FauxScrollFrame_Update(BP.Frame.scrollFrame, numEntries, BP.RowsVisible, 22)
    local offset = FauxScrollFrame_GetOffset(BP.Frame.scrollFrame)

    for i = 1, BP.RowsVisible do
        local row = BP.Rows[i]
        local index = offset + i

        if index <= numEntries then
            local entry = entries[index]
            row.playerName = entry.name

            row.nameText:SetText(entry.name)

            -- Format date
            local dateStr = "-"
            if entry.addedTime then
                dateStr = AIP.FormatBlacklistDate and AIP.FormatBlacklistDate(entry.addedTime) or
                         date("%Y-%m-%d", entry.addedTime)
            end
            row.dateText:SetText(dateStr)

            -- Reason (truncated)
            local reason = entry.reason or ""
            row.reasonText:SetText(reason:sub(1, 35))

            -- Source with color coding
            local source = entry.source or "manual"
            local sourceColors = {
                manual = {1, 1, 0.5},
                queue = {1, 0.5, 0.5},
                lfm = {0.5, 1, 0.5},
                roster = {0.5, 0.5, 1},
            }
            local color = sourceColors[source] or {0.6, 0.6, 0.6}
            row.sourceText:SetText(source:sub(1, 1):upper() .. source:sub(2))
            row.sourceText:SetTextColor(color[1], color[2], color[3])

            -- Show tooltip with full reason on hover
            row:SetScript("OnEnter", function(self)
                if entry.reason or entry.notes then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    GameTooltip:AddLine(entry.name, 1, 1, 1)
                    if entry.reason then
                        GameTooltip:AddLine("Reason: " .. entry.reason, 1, 1, 1, true)
                    end
                    if entry.notes and entry.notes ~= "" then
                        GameTooltip:AddLine("Notes: " .. entry.notes, 0.7, 0.7, 0.7, true)
                    end
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    -- Update status
    local totalCount = AIP.GetBlacklistCount and AIP.GetBlacklistCount() or 0
    if BP.SearchFilter ~= "" or BP.SourceFilter ~= "all" then
        BP.Frame.statusText:SetText("Showing: " .. numEntries .. " / Total: " .. totalCount .. " players")
    else
        BP.Frame.statusText:SetText("Total: " .. totalCount .. " players")
    end
end

-- Show the panel
function BP.Show()
    if BP.Frame then
        BP.Frame:Show()
        BP.Update()
    end
end

-- Hide the panel
function BP.Hide()
    if BP.Frame then
        BP.Frame:Hide()
    end
end

-- ============================================================================
-- EXPORT POPUP (Enhanced v4.3)
-- ============================================================================
local exportPopup = nil

function BP.ShowExportPopup()
    if not AIP.ExportBlacklist then return end

    if not exportPopup then
        -- Create export popup
        local popup = CreateFrame("Frame", "AIPExportPopup", UIParent)
        popup:SetSize(450, 380)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        -- Title
        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Export Blacklist")
        title:SetTextColor(1, 0.82, 0)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        -- Stats
        local statsText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statsText:SetPoint("TOPLEFT", 20, -42)
        popup.statsText = statsText

        -- Format selection
        local formatLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        formatLabel:SetPoint("TOPLEFT", 20, -60)
        formatLabel:SetText("Format:")

        local formatDropdown = CreateFrame("Frame", "AIPExportFormatDropdown", popup, "UIDropDownMenuTemplate")
        formatDropdown:SetPoint("LEFT", formatLabel, "RIGHT", -5, -2)
        UIDropDownMenu_SetWidth(formatDropdown, 150)
        UIDropDownMenu_SetText(formatDropdown, "Simple (Name;Reason)")
        popup.selectedFormat = "simple"

        UIDropDownMenu_Initialize(formatDropdown, function()
            local formats = {
                {value = "simple", text = "Simple (Name;Reason)", desc = "Basic format, backwards compatible"},
                {value = "full", text = "Full (All Fields)", desc = "Includes source, notes, timestamp"},
                {value = "csv", text = "CSV (Spreadsheet)", desc = "For Excel/Google Sheets"},
            }
            for _, fmt in ipairs(formats) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = fmt.text
                info.value = fmt.value
                info.tooltipTitle = fmt.text
                info.tooltipText = fmt.desc
                info.func = function()
                    popup.selectedFormat = fmt.value
                    UIDropDownMenu_SetText(formatDropdown, fmt.text)
                    BP.UpdateExportData()
                end
                info.checked = (popup.selectedFormat == fmt.value)
                UIDropDownMenu_AddButton(info)
            end
        end)
        FixDropdownStrata(formatDropdown)

        -- Data display (scrollable editbox)
        local scrollFrame = CreateFrame("ScrollFrame", "AIPExportScroll", popup, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -88)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 50)

        local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
        scrollBg:SetAllPoints()
        scrollBg:SetTexture(0, 0, 0, 0.5)

        local editBox = CreateFrame("EditBox", "AIPExportEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(380)
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        scrollFrame:SetScrollChild(editBox)
        popup.editBox = editBox

        -- Copy All button
        local copyBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        copyBtn:SetSize(100, 24)
        copyBtn:SetPoint("BOTTOMLEFT", 100, 15)
        copyBtn:SetText("Select All")
        copyBtn:SetScript("OnClick", function()
            editBox:SetFocus()
            editBox:HighlightText()
        end)

        -- Close button
        local closeBtn2 = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        closeBtn2:SetSize(80, 24)
        closeBtn2:SetPoint("BOTTOMRIGHT", -100, 15)
        closeBtn2:SetText("Close")
        closeBtn2:SetScript("OnClick", function() popup:Hide() end)

        -- Instructions
        local instrText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instrText:SetPoint("BOTTOM", 0, 42)
        instrText:SetText("Select All, then Ctrl+C to copy")
        instrText:SetTextColor(0.6, 0.6, 0.6)

        tinsert(UISpecialFrames, popup:GetName())
        exportPopup = popup
    end

    -- Update stats
    local count, sources = AIP.GetBlacklistStats and AIP.GetBlacklistStats() or 0, {}
    local sourceStr = ""
    for src, cnt in pairs(sources) do
        sourceStr = sourceStr .. src .. ":" .. cnt .. " "
    end
    exportPopup.statsText:SetText("Exporting " .. count .. " players  |  " .. sourceStr)

    -- Generate export data
    BP.UpdateExportData()

    exportPopup:Show()
end

function BP.UpdateExportData()
    if not exportPopup or not exportPopup:IsShown() then return end

    local format = exportPopup.selectedFormat or "simple"
    local data = AIP.ExportBlacklist(format)
    exportPopup.editBox:SetText(data)
    exportPopup.editBox:SetCursorPosition(0)
end

-- ============================================================================
-- IMPORT POPUP (Enhanced v4.3)
-- ============================================================================
local importPopup = nil

function BP.ShowImportPopup()
    if not AIP.ImportBlacklist then return end

    if not importPopup then
        -- Create import popup
        local popup = CreateFrame("Frame", "AIPImportPopup", UIParent)
        popup:SetSize(450, 420)
        popup:SetPoint("CENTER")
        popup:SetFrameStrata("DIALOG")
        popup:SetMovable(true)
        popup:EnableMouse(true)
        popup:RegisterForDrag("LeftButton")
        popup:SetScript("OnDragStart", popup.StartMoving)
        popup:SetScript("OnDragStop", popup.StopMovingOrSizing)

        popup:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 }
        })

        -- Title
        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -15)
        title:SetText("Import Blacklist")
        title:SetTextColor(1, 0.82, 0)

        -- Close button
        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        -- Instructions
        local instrText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        instrText:SetPoint("TOPLEFT", 20, -42)
        instrText:SetText("Paste blacklist data below. Supported formats:")
        instrText:SetTextColor(0.8, 0.8, 0.8)

        local formatInfo = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        formatInfo:SetPoint("TOPLEFT", 20, -56)
        formatInfo:SetText("  Simple: Name;Reason  |  Full: Name|Reason|Source|Notes|Time  |  CSV")
        formatInfo:SetTextColor(0.5, 0.5, 0.5)

        -- Data input (scrollable editbox)
        local scrollFrame = CreateFrame("ScrollFrame", "AIPImportScroll", popup, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT", 20, -75)
        scrollFrame:SetPoint("BOTTOMRIGHT", -35, 120)

        local scrollBg = scrollFrame:CreateTexture(nil, "BACKGROUND")
        scrollBg:SetAllPoints()
        scrollBg:SetTexture(0, 0, 0, 0.5)

        local editBox = CreateFrame("EditBox", "AIPImportEditBox", scrollFrame)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(false)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(380)
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        editBox:SetScript("OnTextChanged", function()
            BP.UpdateImportPreview()
        end)
        scrollFrame:SetScrollChild(editBox)
        popup.editBox = editBox

        -- Preview section
        local previewLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        previewLabel:SetPoint("BOTTOMLEFT", 20, 95)
        previewLabel:SetText("Preview:")
        previewLabel:SetTextColor(1, 0.82, 0)

        local previewText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        previewText:SetPoint("TOPLEFT", previewLabel, "BOTTOMLEFT", 0, -5)
        previewText:SetPoint("RIGHT", -20, 0)
        previewText:SetJustifyH("LEFT")
        previewText:SetHeight(40)
        popup.previewText = previewText

        -- Mode selection
        local modeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        modeLabel:SetPoint("BOTTOMLEFT", 20, 52)
        modeLabel:SetText("Mode:")

        local mergeCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        mergeCheck:SetSize(22, 22)
        mergeCheck:SetPoint("LEFT", modeLabel, "RIGHT", 5, 0)
        mergeCheck:SetChecked(true)
        popup.mergeCheck = mergeCheck

        local mergeLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        mergeLabel:SetPoint("LEFT", mergeCheck, "RIGHT", 0, 0)
        mergeLabel:SetText("Merge (add new only)")

        local replaceCheck = CreateFrame("CheckButton", nil, popup, "UICheckButtonTemplate")
        replaceCheck:SetSize(22, 22)
        replaceCheck:SetPoint("LEFT", mergeLabel, "RIGHT", 15, 0)
        replaceCheck:SetChecked(false)
        popup.replaceCheck = replaceCheck

        local replaceLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        replaceLabel:SetPoint("LEFT", replaceCheck, "RIGHT", 0, 0)
        replaceLabel:SetText("Replace (clear first)")
        replaceLabel:SetTextColor(1, 0.4, 0.4)

        -- Radio button behavior
        mergeCheck:SetScript("OnClick", function()
            mergeCheck:SetChecked(true)
            replaceCheck:SetChecked(false)
        end)
        replaceCheck:SetScript("OnClick", function()
            mergeCheck:SetChecked(false)
            replaceCheck:SetChecked(true)
        end)

        -- Import button
        local importBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        importBtn:SetSize(100, 24)
        importBtn:SetPoint("BOTTOMLEFT", 120, 15)
        importBtn:SetText("Import")
        importBtn:SetScript("OnClick", function()
            local data = editBox:GetText()
            if data and data:trim() ~= "" then
                local mode = replaceCheck:GetChecked() and "replace" or "merge"
                if mode == "replace" then
                    -- Confirm replace
                    StaticPopupDialogs["AIP_CONFIRM_REPLACE_IMPORT"] = {
                        text = "This will REPLACE your entire blacklist. Are you sure?",
                        button1 = "Yes, Replace",
                        button2 = "Cancel",
                        OnAccept = function()
                            AIP.ImportBlacklist(data, "replace")
                            BP.Update()
                            popup:Hide()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                    }
                    StaticPopup_Show("AIP_CONFIRM_REPLACE_IMPORT")
                else
                    AIP.ImportBlacklist(data, "merge")
                    BP.Update()
                    popup:Hide()
                end
            end
        end)

        -- Cancel button
        local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 24)
        cancelBtn:SetPoint("BOTTOMRIGHT", -120, 15)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() popup:Hide() end)

        tinsert(UISpecialFrames, popup:GetName())
        importPopup = popup
    end

    -- Reset state
    importPopup.editBox:SetText("")
    importPopup.previewText:SetText("|cFF666666Paste data above to see preview|r")
    importPopup.mergeCheck:SetChecked(true)
    importPopup.replaceCheck:SetChecked(false)

    importPopup:Show()
    importPopup.editBox:SetFocus()
end

function BP.UpdateImportPreview()
    if not importPopup or not importPopup:IsShown() then return end

    local data = importPopup.editBox:GetText()
    if not data or data:trim() == "" then
        importPopup.previewText:SetText("|cFF666666Paste data above to see preview|r")
        return
    end

    if AIP.ParseImportData then
        local entries, errors, format = AIP.ParseImportData(data)

        local previewStr = ""
        if #entries > 0 then
            previewStr = "|cFF00FF00Found " .. #entries .. " entries|r (format: " .. format .. ")"

            -- Count how many are new vs duplicates
            local newCount = 0
            local dupCount = 0
            for _, entry in ipairs(entries) do
                if AIP.IsBlacklisted and AIP.IsBlacklisted(entry.name) then
                    dupCount = dupCount + 1
                else
                    newCount = newCount + 1
                end
            end

            previewStr = previewStr .. "\n|cFF44FF44" .. newCount .. " new|r, |cFFFFFF44" .. dupCount .. " duplicates|r"

            -- Show first few names
            local names = {}
            for i = 1, math.min(5, #entries) do
                table.insert(names, entries[i].name)
            end
            if #entries > 5 then
                previewStr = previewStr .. "\n" .. table.concat(names, ", ") .. ", ..."
            elseif #names > 0 then
                previewStr = previewStr .. "\n" .. table.concat(names, ", ")
            end
        else
            previewStr = "|cFFFF4444No valid entries found|r"
        end

        if #errors > 0 then
            previewStr = previewStr .. "\n|cFFFF8800" .. #errors .. " errors|r"
        end

        importPopup.previewText:SetText(previewStr)
    else
        importPopup.previewText:SetText("|cFFFF4444Parser not available|r")
    end
end
