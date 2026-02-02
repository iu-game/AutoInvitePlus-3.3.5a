-- AutoInvite Plus - Favorites Panel (v5.2)
-- Whitelist/Favorites management panel with priority player tracking

local AIP = AutoInvitePlus
AIP.Panels = AIP.Panels or {}
AIP.Panels.Favorites = {}
local FP = AIP.Panels.Favorites

-- Panel state
FP.Frame = nil
FP.Rows = {}
FP.RowsVisible = 15  -- Increased for larger scroll area
FP.SearchFilter = ""
FP.SourceFilter = "all"
FP.ScrollOffset = 0

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

-- Get filtered favorites list
local function GetFilteredFavorites()
    local results = {}
    if not AIP.db or not AIP.db.whitelist then return results end

    for name, entry in pairs(AIP.db.whitelist) do
        local match = true

        -- Apply search filter
        if FP.SearchFilter and FP.SearchFilter ~= "" then
            local searchLower = FP.SearchFilter:lower()
            local nameLower = name:lower()
            local noteLower = (entry.note or ""):lower()
            if not nameLower:find(searchLower, 1, true) and not noteLower:find(searchLower, 1, true) then
                match = false
            end
        end

        -- Apply source filter
        if match and FP.SourceFilter ~= "all" then
            if (entry.source or "manual") ~= FP.SourceFilter then
                match = false
            end
        end

        if match then
            table.insert(results, {
                name = name,
                note = entry.note or "",
                source = entry.source or "manual",
                addedTime = entry.addedTime or 0,
            })
        end
    end

    -- Sort by name
    table.sort(results, function(a, b) return a.name < b.name end)

    return results
end

-- Create the favorites panel
function FP.Create(parent)
    if FP.Frame then return FP.Frame end

    local frame = CreateFrame("Frame", "AIPFavoritesPanel", parent)
    frame:SetAllPoints()

    local y = -10

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, y)
    title:SetText("Favorites / Whitelist")
    title:SetTextColor(0, 1, 0.5)

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 15, 0)
    subtitle:SetText("|cFF888888Priority players who skip queue and bypass some filters|r")
    y = y - 25

    -- Search and filter row
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("TOPLEFT", 10, y)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", "AIPFavoritesPanelSearch", frame, "InputBoxTemplate")
    searchBox:SetSize(150, 20)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            FP.SearchFilter = self:GetText():lower()
            FP.Update()
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

    local filterDropdown = CreateFrame("Frame", "AIPFavoritesFilter", frame, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("LEFT", filterLabel, "RIGHT", -5, -3)
    UIDropDownMenu_SetWidth(filterDropdown, 100)
    UIDropDownMenu_SetText(filterDropdown, "All")

    local function FilterDropdown_Initialize()
        local sourceCounts = {}
        local sourceNames = {
            all = "All",
            manual = "Manual",
            guild = "Guild Import",
            friends = "Friends Import",
            roster = "From Roster",
            queue = "From Queue",
        }

        -- Count sources
        if AIP.db and AIP.db.whitelist then
            for _, entry in pairs(AIP.db.whitelist) do
                local source = entry.source or "manual"
                sourceCounts[source] = (sourceCounts[source] or 0) + 1
            end
        end

        -- Always add "All" first
        local info = UIDropDownMenu_CreateInfo()
        info.text = "All"
        info.value = "all"
        info.func = function(self)
            FP.SourceFilter = "all"
            UIDropDownMenu_SetText(filterDropdown, "All")
            FP.Update()
        end
        info.checked = (FP.SourceFilter == "all")
        UIDropDownMenu_AddButton(info)

        -- Add sources that exist
        local orderedSources = {"manual", "guild", "friends", "roster", "queue"}
        for _, source in ipairs(orderedSources) do
            if sourceCounts[source] and sourceCounts[source] > 0 then
                local info = UIDropDownMenu_CreateInfo()
                info.text = (sourceNames[source] or source) .. " (" .. sourceCounts[source] .. ")"
                info.value = source
                info.func = function(self)
                    FP.SourceFilter = source
                    UIDropDownMenu_SetText(filterDropdown, sourceNames[source] or source)
                    FP.Update()
                end
                info.checked = (FP.SourceFilter == source)
                UIDropDownMenu_AddButton(info)
            end
        end
    end
    UIDropDownMenu_Initialize(filterDropdown, FilterDropdown_Initialize)
    FixDropdownStrata(filterDropdown)
    y = y - 30

    -- Add new favorite row
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 10, y)
    addLabel:SetText("Add Player:")

    local addNameBox = CreateFrame("EditBox", "AIPFavoritesAddName", frame, "InputBoxTemplate")
    addNameBox:SetSize(120, 20)
    addNameBox:SetPoint("LEFT", addLabel, "RIGHT", 5, 0)
    addNameBox:SetAutoFocus(false)
    frame.addNameBox = addNameBox

    local noteLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noteLabel:SetPoint("LEFT", addNameBox, "RIGHT", 10, 0)
    noteLabel:SetText("Note:")

    local addNoteBox = CreateFrame("EditBox", "AIPFavoritesAddNote", frame, "InputBoxTemplate")
    addNoteBox:SetSize(200, 20)
    addNoteBox:SetPoint("LEFT", noteLabel, "RIGHT", 5, 0)
    addNoteBox:SetAutoFocus(false)
    frame.addNoteBox = addNoteBox

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetPoint("LEFT", addNoteBox, "RIGHT", 10, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = addNameBox:GetText():trim()
        local note = addNoteBox:GetText():trim()
        if name ~= "" then
            if AIP.AddToFavorites then
                AIP.AddToFavorites(name, note ~= "" and note or nil, "manual")
                addNameBox:SetText("")
                addNoteBox:SetText("")
                FP.Update()
            end
        else
            AIP.Print("Please enter a player name")
        end
    end)

    addNameBox:SetScript("OnEnterPressed", function()
        addBtn:Click()
    end)
    addNoteBox:SetScript("OnEnterPressed", function()
        addBtn:Click()
    end)
    y = y - 30

    -- Column headers (full width layout)
    local headerY = y
    local colName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colName:SetPoint("TOPLEFT", 10, headerY)
    colName:SetText("Player Name")
    colName:SetTextColor(1, 0.82, 0)

    local colNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNote:SetPoint("TOPLEFT", 140, headerY)
    colNote:SetText("Note")
    colNote:SetTextColor(1, 0.82, 0)

    local colSource = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colSource:SetPoint("TOPLEFT", 420, headerY)
    colSource:SetText("Source")
    colSource:SetTextColor(1, 0.82, 0)

    local colActions = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colActions:SetPoint("TOPLEFT", 520, headerY)
    colActions:SetText("Actions")
    colActions:SetTextColor(1, 0.82, 0)
    y = y - 18

    -- Separator line (full width)
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", 10, y)
    separator:SetPoint("TOPRIGHT", -25, y)
    separator:SetHeight(1)
    separator:SetTexture(1, 0.82, 0, 0.3)
    y = y - 8

    -- Scroll frame for list (full width, fills between header and buttons)
    local scrollFrame = CreateFrame("ScrollFrame", "AIPFavoritesPanelScroll", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 10, y)
    scrollFrame:SetPoint("RIGHT", -25, 0)
    scrollFrame:SetPoint("BOTTOM", 0, 40)  -- Leave space for bottom buttons
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 26, FP.Update)
    end)
    frame.scrollFrame = scrollFrame

    -- Create row frames
    for i = 1, FP.RowsVisible do
        local row = CreateFrame("Frame", "AIPFavoritesRow"..i, frame)
        row:SetHeight(24)
        row:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, -((i-1) * 26))
        row:SetPoint("RIGHT", scrollFrame, "RIGHT", 0, 0)

        -- Highlight on hover
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")
        highlight:SetAlpha(0.3)

        -- Player name
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 0, 0)
        nameText:SetWidth(125)
        nameText:SetJustifyH("LEFT")
        row.nameText = nameText

        -- Note
        local noteText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteText:SetPoint("LEFT", 130, 0)
        noteText:SetWidth(270)
        noteText:SetJustifyH("LEFT")
        noteText:SetTextColor(0.8, 0.8, 0.8)
        row.noteText = noteText

        -- Source
        local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sourceText:SetPoint("LEFT", 410, 0)
        sourceText:SetWidth(90)
        sourceText:SetJustifyH("LEFT")
        sourceText:SetTextColor(0.6, 0.6, 0.6)
        row.sourceText = sourceText

        -- Edit button
        local editBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        editBtn:SetSize(40, 20)
        editBtn:SetPoint("LEFT", 510, 0)
        editBtn:SetText("Edit")
        editBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry then
                FP.ShowEditDialog(entry.name, entry.note)
            end
        end)
        row.editBtn = editBtn

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        removeBtn:SetSize(25, 20)
        removeBtn:SetPoint("LEFT", editBtn, "RIGHT", 5, 0)
        removeBtn:SetText("X")
        removeBtn:SetScript("OnClick", function(self)
            local entry = self:GetParent().entryData
            if entry and AIP.RemoveFromFavorites then
                AIP.RemoveFromFavorites(entry.name)
                FP.Update()
            end
        end)
        removeBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Remove from favorites")
            GameTooltip:Show()
        end)
        removeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row.removeBtn = removeBtn

        row:Hide()
        FP.Rows[i] = row
    end

    -- Bottom buttons (anchored to bottom of frame)
    local importGuildBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importGuildBtn:SetSize(100, 22)
    importGuildBtn:SetPoint("BOTTOMLEFT", 10, 10)
    importGuildBtn:SetText("Import Guild")
    importGuildBtn:SetScript("OnClick", function()
        FP.ImportGuild()
    end)
    importGuildBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Import Guild Members")
        GameTooltip:AddLine("Add all online guild members to favorites", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    importGuildBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local importFriendsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    importFriendsBtn:SetSize(100, 22)
    importFriendsBtn:SetPoint("LEFT", importGuildBtn, "RIGHT", 10, 0)
    importFriendsBtn:SetText("Import Friends")
    importFriendsBtn:SetScript("OnClick", function()
        FP.ImportFriends()
    end)
    importFriendsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Import Friends")
        GameTooltip:AddLine("Add all online friends to favorites", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    importFriendsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", importFriendsBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_FAVORITES"] = {
            text = "Clear ALL favorites?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                if AIP.db then
                    AIP.db.whitelist = {}
                    FP.Update()
                    AIP.Print("Favorites cleared")
                end
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_FAVORITES")
    end)

    -- Count display (anchored to bottom right)
    local countText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -25, 15)
    countText:SetText("0 favorites")
    frame.countText = countText

    FP.Frame = frame
    return frame
end

-- Import guild members
function FP.ImportGuild()
    if not IsInGuild() then
        AIP.Print("You are not in a guild")
        return
    end

    local added = 0
    local numMembers = GetNumGuildMembers()

    for i = 1, numMembers do
        local name, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if name and online then
            -- Remove realm suffix if present
            local cleanName = name:match("^([^-]+)") or name
            if AIP.AddToFavorites then
                if AIP.AddToFavorites(cleanName, "Guild member", "guild") then
                    added = added + 1
                end
            end
        end
    end

    AIP.Print("Imported " .. added .. " online guild members to favorites")
    FP.Update()
end

-- Import friends
function FP.ImportFriends()
    local added = 0
    local numFriends = GetNumFriends()

    for i = 1, numFriends do
        local name, _, _, _, connected = GetFriendInfo(i)
        if name and connected then
            if AIP.AddToFavorites then
                if AIP.AddToFavorites(name, "Friend", "friends") then
                    added = added + 1
                end
            end
        end
    end

    AIP.Print("Imported " .. added .. " online friends to favorites")
    FP.Update()
end

-- Show edit dialog
function FP.ShowEditDialog(name, currentNote)
    StaticPopupDialogs["AIP_EDIT_FAVORITE"] = {
        text = "Edit note for " .. name .. ":",
        button1 = "Save",
        button2 = "Cancel",
        hasEditBox = true,
        editBoxWidth = 300,
        OnShow = function(self)
            self.editBox:SetText(currentNote or "")
            self.editBox:SetFocus()
        end,
        OnAccept = function(self)
            local newNote = self.editBox:GetText()
            if AIP.db and AIP.db.whitelist and AIP.db.whitelist[name] then
                AIP.db.whitelist[name].note = newNote
                FP.Update()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
    StaticPopup_Show("AIP_EDIT_FAVORITE")
end

-- Update the panel
function FP.Update()
    if not FP.Frame then return end

    local favorites = GetFilteredFavorites()
    local numEntries = #favorites

    FauxScrollFrame_Update(FP.Frame.scrollFrame, numEntries, FP.RowsVisible, 26)

    local offset = FauxScrollFrame_GetOffset(FP.Frame.scrollFrame) or 0

    local sourceColors = {
        manual = {1, 1, 1},
        guild = {0.4, 1, 0.4},
        friends = {0.4, 0.8, 1},
        roster = {1, 0.8, 0.4},
        queue = {0.8, 0.6, 1},
    }

    for i = 1, FP.RowsVisible do
        local row = FP.Rows[i]
        local index = offset + i

        if index <= numEntries then
            local entry = favorites[index]
            row.entryData = entry

            row.nameText:SetText(entry.name)
            row.nameText:SetTextColor(0, 1, 0.5)  -- Greenish for favorites

            row.noteText:SetText(entry.note ~= "" and entry.note or "-")

            local sourceDisplay = entry.source or "manual"
            row.sourceText:SetText(sourceDisplay)
            local color = sourceColors[sourceDisplay] or {0.6, 0.6, 0.6}
            row.sourceText:SetTextColor(unpack(color))

            row:Show()
        else
            row:Hide()
        end
    end

    -- Update count
    local totalCount = 0
    if AIP.db and AIP.db.whitelist then
        for _ in pairs(AIP.db.whitelist) do
            totalCount = totalCount + 1
        end
    end
    FP.Frame.countText:SetText(numEntries .. " shown / " .. totalCount .. " total")
end

-- Show/Hide
function FP.Show()
    if FP.Frame then
        FP.Frame:Show()
        FP.Update()
    end
end

function FP.Hide()
    if FP.Frame then
        FP.Frame:Hide()
    end
end
