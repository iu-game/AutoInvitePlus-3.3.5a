-- AutoInvite Plus - Loot History Panel (v5.5 Redesign)
-- Multi-panel layout: Raids, Bosses, Boss Attendees, Raid Attendees, Loot

local AIP = AutoInvitePlus
AIP.Panels = AIP.Panels or {}
AIP.Panels.LootHistory = {}
local LH = AIP.Panels.LootHistory

-- Panel state
LH.Frame = nil
LH.SelectedRaid = nil
LH.SelectedBoss = nil
LH.CurrentFilter = "all"
LH.CurrentSearch = ""

-- Item quality colors
LH.QualityColors = {
    [0] = {r = 0.62, g = 0.62, b = 0.62},  -- Poor
    [1] = {r = 1.00, g = 1.00, b = 1.00},  -- Common
    [2] = {r = 0.12, g = 1.00, b = 0.00},  -- Uncommon
    [3] = {r = 0.00, g = 0.44, b = 0.87},  -- Rare
    [4] = {r = 0.64, g = 0.21, b = 0.93},  -- Epic
    [5] = {r = 1.00, g = 0.50, b = 0.00},  -- Legendary
}

-- ============================================================================
-- DATA ACCESS (via RaidSessionManager)
-- ============================================================================

function LH.GetSessions()
    -- Try via RaidSessionManager module
    if AIP.RaidSession and AIP.RaidSession.GetAllSessions then
        local sessions = AIP.RaidSession.GetAllSessions()
        if sessions then return sessions end
    end
    -- Fallback: access db directly
    if AIP.db and AIP.db.raidSessions then
        return AIP.db.raidSessions
    end
    return {}
end

function LH.GetSelectedSession()
    if not LH.SelectedRaid then return nil end
    -- Try via RaidSessionManager module
    if AIP.RaidSession and AIP.RaidSession.GetSession then
        local session = AIP.RaidSession.GetSession(LH.SelectedRaid)
        if session then return session end
    end
    -- Fallback: search db directly
    if AIP.db and AIP.db.raidSessions then
        for _, session in ipairs(AIP.db.raidSessions) do
            if session.id == LH.SelectedRaid then
                return session
            end
        end
    end
    return nil
end

function LH.GetBosses()
    local session = LH.GetSelectedSession()
    if session then
        return session.bosses or {}
    end
    return {}
end

function LH.GetRaidAttendees()
    local session = LH.GetSelectedSession()
    if session then
        return session.attendees or {}
    end
    return {}
end

function LH.GetBossAttendees()
    if not LH.SelectedRaid or not LH.SelectedBoss then return {} end

    -- Try via RaidSessionManager
    if AIP.RaidSession and AIP.RaidSession.GetBossAttendees then
        local attendees = AIP.RaidSession.GetBossAttendees(LH.SelectedRaid, LH.SelectedBoss)
        if attendees and #attendees > 0 then
            return attendees
        end
    end

    -- Fallback: search directly in session data
    local session = LH.GetSelectedSession()
    if session and session.bosses then
        for _, boss in ipairs(session.bosses) do
            if boss.id == LH.SelectedBoss then
                return boss.attendees or {}
            end
        end
    end

    return {}
end

function LH.GetLoot()
    local session = LH.GetSelectedSession()
    if not session then return {} end

    local loot = session.loot or {}

    -- Filter by boss if selected
    if LH.SelectedBoss then
        local filtered = {}
        for _, entry in ipairs(loot) do
            if entry.bossId == LH.SelectedBoss then
                table.insert(filtered, entry)
            end
        end
        loot = filtered
    end

    -- Apply quality filter
    if LH.CurrentFilter ~= "all" then
        local filtered = {}
        for _, entry in ipairs(loot) do
            local include = true
            if LH.CurrentFilter == "epic" and (entry.itemQuality or 0) < 4 then
                include = false
            elseif LH.CurrentFilter == "rare" and (entry.itemQuality or 0) < 3 then
                include = false
            end
            if include then
                table.insert(filtered, entry)
            end
        end
        loot = filtered
    end

    -- Apply search filter
    if LH.CurrentSearch ~= "" then
        local filtered = {}
        local s = LH.CurrentSearch:lower()
        for _, entry in ipairs(loot) do
            local matchName = entry.itemName and entry.itemName:lower():find(s, 1, true)
            local matchWinner = entry.winner and entry.winner:lower():find(s, 1, true)
            if matchName or matchWinner then
                table.insert(filtered, entry)
            end
        end
        loot = filtered
    end

    return loot
end

-- ============================================================================
-- LEGACY DATA MANAGEMENT (for backwards compatibility)
-- ============================================================================

function LH.GetHistory()
    if not AIP.db then return {} end
    if not AIP.db.lootHistory then AIP.db.lootHistory = {} end
    return AIP.db.lootHistory
end

-- Pending items waiting for item info
LH.PendingItems = LH.PendingItems or {}

function LH.AddLootEntry(itemLink, looter, source, zone)
    if not AIP.db then return end
    if not AIP.db.lootHistory then AIP.db.lootHistory = {} end

    local itemName, _, itemQuality, itemLevel = GetItemInfo(itemLink)
    if not itemName then
        -- Item not cached, queue for retry
        table.insert(LH.PendingItems, {
            itemLink = itemLink,
            looter = looter,
            source = source,
            zone = zone or GetRealZoneText() or "Unknown",
            timestamp = time(),
        })
        return
    end
    if itemQuality and itemQuality < 2 then return end  -- Skip gray/white

    local itemId = itemLink:match("item:(%d+)")

    local entry = {
        itemLink = itemLink,
        itemName = itemName,
        itemId = tonumber(itemId),
        itemQuality = itemQuality or 1,
        itemLevel = itemLevel or 0,
        looter = looter,
        source = source or "Unknown",
        zone = zone or GetRealZoneText() or "Unknown",
        timestamp = time(),
        raidStartTimestamp = AIP.db and AIP.db.currentRaidStartTime or nil,
    }

    table.insert(AIP.db.lootHistory, 1, entry)

    -- Keep max 500 entries
    while #AIP.db.lootHistory > 500 do
        table.remove(AIP.db.lootHistory)
    end

    LH.RefreshAll()
end

function LH.ClearHistory()
    if AIP.db then AIP.db.lootHistory = {} end
    LH.RefreshAll()
end

-- ============================================================================
-- UI CREATION
-- ============================================================================

function LH.Create(parent)
    if LH.Frame then return LH.Frame end

    local frame = CreateFrame("Frame", "AIPLootHistoryPanel", parent)
    frame:SetAllPoints()

    local PANEL_PADDING = 5
    local TOP_ROW_HEIGHT = 180
    local BOTTOM_ROW_HEIGHT = 220
    local PANEL_WIDTH_THIRD = 215
    local PANEL_WIDTH_HALF = 215
    local PANEL_WIDTH_LOOT = 440

    local y = -5

    -- ========================================================================
    -- TOP ROW: Raids List | Bosses | Boss Attendees
    -- ========================================================================

    -- === RAIDS LIST PANEL ===
    local raidsPanel = LH.CreatePanelFrame(frame, "Raids", PANEL_WIDTH_THIRD, TOP_ROW_HEIGHT)
    raidsPanel:SetPoint("TOPLEFT", PANEL_PADDING, y)

    -- Raids list header
    local raidsHeader = raidsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidsHeader:SetPoint("TOPLEFT", 8, -25)
    raidsHeader:SetText("|cFFFFCC00#|r | |cFFFFCC00Date|r | |cFFFFCC00Raid/Dungeon|r")

    -- Raids scroll
    local raidsScroll = CreateFrame("ScrollFrame", "AIPRaidsScroll", raidsPanel, "FauxScrollFrameTemplate")
    raidsScroll:SetPoint("TOPLEFT", 5, -40)
    raidsScroll:SetPoint("BOTTOMRIGHT", -26, 35)
    raidsScroll:EnableMouse(false)  -- Don't intercept mouse clicks meant for rows
    frame.raidsScroll = raidsScroll

    frame.raidRows = {}
    for i = 1, 7 do
        local row = LH.CreateSelectableRow(raidsPanel, PANEL_WIDTH_THIRD - 30, 18)
        row:SetPoint("TOPLEFT", 5, -40 - (i-1) * 18)
        row.index = i

        row.numText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.numText:SetPoint("LEFT", 3, 0)
        row.numText:SetWidth(20)

        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dateText:SetPoint("LEFT", 23, 0)
        row.dateText:SetWidth(55)

        row.zoneText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.zoneText:SetPoint("LEFT", 80, 0)
        row.zoneText:SetWidth(100)
        row.zoneText:SetJustifyH("LEFT")

        row:SetScript("OnClick", function(self)
            if self.data then
                LH.SelectRaid(self.data.id)
            end
        end)

        row:Hide()  -- Start hidden until data populates
        frame.raidRows[i] = row
    end

    raidsScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function() LH.RefreshRaids() end)
    end)

    -- Initialize scroll frame state
    FauxScrollFrame_Update(raidsScroll, 0, 7, 18)

    -- Raids buttons
    local deleteRaidBtn = CreateFrame("Button", nil, raidsPanel, "UIPanelButtonTemplate")
    deleteRaidBtn:SetSize(50, 18)
    deleteRaidBtn:SetPoint("BOTTOMLEFT", 5, 8)
    deleteRaidBtn:SetText("Delete")
    deleteRaidBtn:SetScript("OnClick", function()
        if not LH.SelectedRaid then
            AIP.Print("Select a raid session to delete.")
            return
        end
        StaticPopup_Show("AIP_CONFIRM_DELETE_RAID")
    end)

    -- === BOSSES PANEL ===
    local bossesPanel = LH.CreatePanelFrame(frame, "Bosses", PANEL_WIDTH_THIRD, TOP_ROW_HEIGHT)
    bossesPanel:SetPoint("TOPLEFT", raidsPanel, "TOPRIGHT", PANEL_PADDING, 0)

    local bossesHeader = bossesPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossesHeader:SetPoint("TOPLEFT", 8, -25)
    bossesHeader:SetText("|cFFFFCC00#|r | |cFFFFCC00Boss Name|r | |cFFFFCC00Time|r")

    local bossesScroll = CreateFrame("ScrollFrame", "AIPBossesScroll", bossesPanel, "FauxScrollFrameTemplate")
    bossesScroll:SetPoint("TOPLEFT", 5, -40)
    bossesScroll:SetPoint("BOTTOMRIGHT", -26, 35)
    bossesScroll:EnableMouse(false)  -- Don't intercept mouse clicks meant for rows
    frame.bossesScroll = bossesScroll

    frame.bossRows = {}
    for i = 1, 7 do
        local row = LH.CreateSelectableRow(bossesPanel, PANEL_WIDTH_THIRD - 30, 18)
        row:SetPoint("TOPLEFT", 5, -40 - (i-1) * 18)
        row.index = i

        row.numText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.numText:SetPoint("LEFT", 3, 0)
        row.numText:SetWidth(20)

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 23, 0)
        row.nameText:SetWidth(100)
        row.nameText:SetJustifyH("LEFT")

        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.timeText:SetPoint("LEFT", 125, 0)
        row.timeText:SetWidth(55)

        row:SetScript("OnClick", function(self)
            if self.data then
                LH.SelectBoss(self.data.id)
            end
        end)

        row:Hide()  -- Start hidden until data populates
        frame.bossRows[i] = row
    end

    bossesScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function() LH.RefreshBosses() end)
    end)

    -- === BOSS ATTENDEES PANEL ===
    local bossAttPanel = LH.CreatePanelFrame(frame, "Boss Attendees", PANEL_WIDTH_THIRD, TOP_ROW_HEIGHT)
    bossAttPanel:SetPoint("TOPLEFT", bossesPanel, "TOPRIGHT", PANEL_PADDING, 0)

    local bossAttHeader = bossAttPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossAttHeader:SetPoint("TOPLEFT", 8, -25)
    bossAttHeader:SetText("|cFFFFCC00Player Name|r")

    local bossAttScroll = CreateFrame("ScrollFrame", "AIPBossAttScroll", bossAttPanel, "FauxScrollFrameTemplate")
    bossAttScroll:SetPoint("TOPLEFT", 5, -40)
    bossAttScroll:SetPoint("BOTTOMRIGHT", -26, 35)
    bossAttScroll:EnableMouse(false)  -- Don't intercept mouse clicks meant for rows
    frame.bossAttScroll = bossAttScroll

    frame.bossAttRows = {}
    for i = 1, 7 do
        local row = LH.CreateSelectableRow(bossAttPanel, PANEL_WIDTH_THIRD - 30, 18)
        row:SetPoint("TOPLEFT", 5, -40 - (i-1) * 18)
        row.index = i

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 5, 0)
        row.nameText:SetWidth(PANEL_WIDTH_THIRD - 40)
        row.nameText:SetJustifyH("LEFT")

        row:SetScript("OnClick", function(self)
            if self.data then
                -- Could add to loot ban or other action
                LH.ShowPlayerContextMenu(self, self.data)
            end
        end)

        row:Hide()  -- Start hidden until data populates
        frame.bossAttRows[i] = row
    end

    bossAttScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function() LH.RefreshBossAttendees() end)
    end)

    -- Boss attendees count
    local bossAttCount = bossAttPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bossAttCount:SetPoint("BOTTOMLEFT", 8, 12)
    bossAttCount:SetTextColor(0.7, 0.7, 0.7)
    frame.bossAttCount = bossAttCount

    -- ========================================================================
    -- BOTTOM ROW: Raid Attendees | Raid Loot
    -- ========================================================================

    local bottomY = y - TOP_ROW_HEIGHT - PANEL_PADDING

    -- === RAID ATTENDEES PANEL ===
    local raidAttPanel = LH.CreatePanelFrame(frame, "Raid Attendees", PANEL_WIDTH_HALF, BOTTOM_ROW_HEIGHT)
    raidAttPanel:SetPoint("TOPLEFT", PANEL_PADDING, bottomY)

    local raidAttHeader = raidAttPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidAttHeader:SetPoint("TOPLEFT", 8, -25)
    raidAttHeader:SetText("|cFFFFCC00Name|r | |cFFFFCC00Join|r | |cFFFFCC00Leave|r")

    local raidAttScroll = CreateFrame("ScrollFrame", "AIPRaidAttScroll", raidAttPanel, "FauxScrollFrameTemplate")
    raidAttScroll:SetPoint("TOPLEFT", 5, -40)
    raidAttScroll:SetPoint("BOTTOMRIGHT", -26, 35)
    raidAttScroll:EnableMouse(false)  -- Don't intercept mouse clicks meant for rows
    frame.raidAttScroll = raidAttScroll

    frame.raidAttRows = {}
    for i = 1, 9 do
        local row = LH.CreateSelectableRow(raidAttPanel, PANEL_WIDTH_HALF - 30, 18)
        row:SetPoint("TOPLEFT", 5, -40 - (i-1) * 18)
        row.index = i

        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.nameText:SetPoint("LEFT", 5, 0)
        row.nameText:SetWidth(80)
        row.nameText:SetJustifyH("LEFT")

        row.joinText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.joinText:SetPoint("LEFT", 90, 0)
        row.joinText:SetWidth(50)

        row.leaveText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.leaveText:SetPoint("LEFT", 145, 0)
        row.leaveText:SetWidth(50)

        row:Hide()  -- Start hidden until data populates
        frame.raidAttRows[i] = row
    end

    raidAttScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function() LH.RefreshRaidAttendees() end)
    end)

    -- Raid attendees count
    local raidAttCount = raidAttPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidAttCount:SetPoint("BOTTOMLEFT", 8, 12)
    raidAttCount:SetTextColor(0.7, 0.7, 0.7)
    frame.raidAttCount = raidAttCount

    -- === RAID LOOT PANEL ===
    local lootPanel = LH.CreatePanelFrame(frame, "Raid Loot", PANEL_WIDTH_LOOT, BOTTOM_ROW_HEIGHT)
    lootPanel:SetPoint("TOPLEFT", raidAttPanel, "TOPRIGHT", PANEL_PADDING, 0)

    -- Filter and search row
    local filterLabel = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", 8, -22)
    filterLabel:SetText("Filter:")

    local filterDropdown = CreateFrame("Frame", "AIPLootFilter", lootPanel, "UIDropDownMenuTemplate")
    filterDropdown:SetPoint("TOPLEFT", 35, -17)
    UIDropDownMenu_SetWidth(filterDropdown, 65)
    UIDropDownMenu_SetText(filterDropdown, "All")

    UIDropDownMenu_Initialize(filterDropdown, function()
        local filters = {
            {text = "All", value = "all"},
            {text = "Rare+", value = "rare"},
            {text = "Epic+", value = "epic"},
        }
        for _, f in ipairs(filters) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = f.text
            info.value = f.value
            info.func = function()
                LH.CurrentFilter = f.value
                UIDropDownMenu_SetText(filterDropdown, f.text)
                LH.RefreshLoot()
            end
            info.checked = (LH.CurrentFilter == f.value)
            UIDropDownMenu_AddButton(info)
        end
    end)

    local searchLabel = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    searchLabel:SetPoint("LEFT", filterDropdown, "RIGHT", 15, 2)
    searchLabel:SetText("Search:")

    local searchBox = CreateFrame("EditBox", nil, lootPanel, "InputBoxTemplate")
    searchBox:SetSize(100, 16)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 5, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetScript("OnTextChanged", function(self)
        LH.CurrentSearch = self:GetText() or ""
        LH.RefreshLoot()
    end)
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    frame.searchBox = searchBox

    -- Loot stats
    local lootStats = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootStats:SetPoint("LEFT", searchBox, "RIGHT", 15, 0)
    lootStats:SetTextColor(0.7, 0.7, 0.7)
    frame.lootStats = lootStats

    -- Loot headers (individual FontStrings for proper alignment)
    frame.lootHeaders = {}

    local lootHeaderItem = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootHeaderItem:SetPoint("TOPLEFT", 8, -42)
    lootHeaderItem:SetText("|cFFFFCC00Item|r")
    frame.lootHeaders.item = lootHeaderItem

    local lootHeaderSource = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootHeaderSource:SetPoint("TOPLEFT", 165, -42)
    lootHeaderSource:SetText("|cFFFFCC00Source|r")
    frame.lootHeaders.source = lootHeaderSource

    local lootHeaderWinner = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootHeaderWinner:SetPoint("TOPLEFT", 250, -42)
    lootHeaderWinner:SetText("|cFFFFCC00Winner|r")
    frame.lootHeaders.winner = lootHeaderWinner

    local lootHeaderTime = lootPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lootHeaderTime:SetPoint("TOPLEFT", 325, -42)
    lootHeaderTime:SetText("|cFFFFCC00Time|r")
    frame.lootHeaders.time = lootHeaderTime

    -- Loot scroll
    local lootScroll = CreateFrame("ScrollFrame", "AIPLootScroll", lootPanel, "FauxScrollFrameTemplate")
    lootScroll:SetPoint("TOPLEFT", 5, -55)
    lootScroll:SetPoint("BOTTOMRIGHT", -26, 35)
    lootScroll:EnableMouse(false)  -- Don't intercept mouse clicks meant for rows
    frame.lootScroll = lootScroll

    frame.lootRows = {}
    for i = 1, 8 do
        local row = CreateFrame("Button", nil, lootPanel)
        row:SetSize(PANEL_WIDTH_LOOT - 30, 18)
        row:SetPoint("TOPLEFT", 5, -55 - (i-1) * 18)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

        if i % 2 == 0 then
            local bg = row:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture("Interface\\Buttons\\WHITE8X8")
            bg:SetVertexColor(0.1, 0.1, 0.1, 0.3)
        end

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("LEFT", 3, 0)
        row.icon = icon

        local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        itemText:SetPoint("LEFT", 22, 0)
        itemText:SetWidth(140)
        itemText:SetJustifyH("LEFT")
        row.itemText = itemText

        local sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        sourceText:SetPoint("LEFT", 165, 0)
        sourceText:SetWidth(80)
        sourceText:SetJustifyH("LEFT")
        row.sourceText = sourceText

        local winnerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        winnerText:SetPoint("LEFT", 250, 0)
        winnerText:SetWidth(70)
        winnerText:SetJustifyH("LEFT")
        row.winnerText = winnerText

        local timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        timeText:SetPoint("LEFT", 325, 0)
        timeText:SetWidth(70)
        row.timeText = timeText

        row:SetScript("OnEnter", function(self)
            if self.data then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.data.itemLink and self.data.itemLink:match("|Hitem:") then
                    -- Real item link - show full tooltip
                    GameTooltip:SetHyperlink(self.data.itemLink)
                else
                    -- Fake link or name only - show basic info
                    local itemName = self.data.itemName or "Unknown Item"
                    local quality = self.data.itemQuality or 1
                    local color = LH.QualityColors[quality] or {r=1, g=1, b=1}
                    GameTooltip:AddLine(itemName, color.r, color.g, color.b)
                    local qualityName = (quality == 5 and "Legendary") or (quality == 4 and "Epic") or (quality == 3 and "Rare") or (quality == 2 and "Uncommon") or "Common"
                    GameTooltip:AddLine("Quality: " .. qualityName, 0.7, 0.7, 0.7)
                    if self.data.winner then
                        GameTooltip:AddLine("Winner: " .. self.data.winner, 0.5, 0.8, 0.5)
                    end
                    if self.data.source then
                        GameTooltip:AddLine("Source: " .. self.data.source, 0.5, 0.5, 0.8)
                    end
                end
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        row:SetScript("OnClick", function(self)
            if self.data and self.data.itemLink and IsShiftKeyDown() then
                if ChatFrame1EditBox:IsVisible() then
                    ChatFrame1EditBox:Insert(self.data.itemLink)
                end
            end
        end)

        row:Hide()  -- Start hidden until data populates
        frame.lootRows[i] = row
    end

    lootScroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 18, function() LH.RefreshLoot() end)
    end)

    -- Chat export buttons (post selected boss loot to chat)
    local postSayBtn = CreateFrame("Button", nil, lootPanel, "UIPanelButtonTemplate")
    postSayBtn:SetSize(50, 18)
    postSayBtn:SetPoint("BOTTOMLEFT", 5, 8)
    postSayBtn:SetText("Say")
    postSayBtn:SetScript("OnClick", function()
        LH.PostBossLootToChat("SAY")
    end)

    local postPartyBtn = CreateFrame("Button", nil, lootPanel, "UIPanelButtonTemplate")
    postPartyBtn:SetSize(50, 18)
    postPartyBtn:SetPoint("LEFT", postSayBtn, "RIGHT", 3, 0)
    postPartyBtn:SetText("Party")
    postPartyBtn:SetScript("OnClick", function()
        LH.PostBossLootToChat("PARTY")
    end)

    local postRaidBtn = CreateFrame("Button", nil, lootPanel, "UIPanelButtonTemplate")
    postRaidBtn:SetSize(50, 18)
    postRaidBtn:SetPoint("LEFT", postPartyBtn, "RIGHT", 3, 0)
    postRaidBtn:SetText("Raid")
    postRaidBtn:SetScript("OnClick", function()
        LH.PostBossLootToChat("RAID")
    end)

    -- ========================================================================
    -- DYNAMIC RESIZING
    -- ========================================================================

    -- Store panel references for resizing
    frame.panels = {
        raids = raidsPanel,
        bosses = bossesPanel,
        bossAtt = bossAttPanel,
        raidAtt = raidAttPanel,
        loot = lootPanel,
    }

    -- Resize function to recalculate panel sizes
    local function ResizePanels()
        local frameWidth = frame:GetWidth()
        local frameHeight = frame:GetHeight()
        -- Need minimum 400x300 for proper layout (3 panels wide, 2 rows tall)
        if not frameWidth or frameWidth < 400 or not frameHeight or frameHeight < 300 then return end

        local padding = PANEL_PADDING
        local topRowHeight = math.floor(frameHeight * 0.42)  -- ~42% for top row
        local bottomRowHeight = frameHeight - topRowHeight - padding * 2

        -- Calculate widths for 3-panel top row (equal thirds)
        local topPanelWidth = math.floor((frameWidth - padding * 4) / 3)

        -- Calculate widths for 2-panel bottom row (1/3 for attendees, 2/3 for loot)
        local bottomAttWidth = math.floor((frameWidth - padding * 3) / 3)
        local bottomLootWidth = frameWidth - bottomAttWidth - padding * 3

        local bottomY = -padding - topRowHeight - padding

        -- Resize top row panels
        raidsPanel:SetSize(topPanelWidth, topRowHeight)
        raidsPanel:ClearAllPoints()
        raidsPanel:SetPoint("TOPLEFT", padding, -padding)

        bossesPanel:SetSize(topPanelWidth, topRowHeight)
        bossesPanel:ClearAllPoints()
        bossesPanel:SetPoint("TOPLEFT", raidsPanel, "TOPRIGHT", padding, 0)

        bossAttPanel:SetSize(topPanelWidth, topRowHeight)
        bossAttPanel:ClearAllPoints()
        bossAttPanel:SetPoint("TOPLEFT", bossesPanel, "TOPRIGHT", padding, 0)

        -- Resize bottom row panels
        raidAttPanel:SetSize(bottomAttWidth, bottomRowHeight)
        raidAttPanel:ClearAllPoints()
        raidAttPanel:SetPoint("TOPLEFT", padding, bottomY)

        lootPanel:SetSize(bottomLootWidth, bottomRowHeight)
        lootPanel:ClearAllPoints()
        lootPanel:SetPoint("TOPLEFT", raidAttPanel, "TOPRIGHT", padding, 0)

        -- Update row widths in each panel
        local topRowWidth = topPanelWidth - 30
        for i = 1, 7 do
            if frame.raidRows[i] then frame.raidRows[i]:SetWidth(topRowWidth) end
            if frame.bossRows[i] then frame.bossRows[i]:SetWidth(topRowWidth) end
            if frame.bossAttRows[i] then frame.bossAttRows[i]:SetWidth(topRowWidth) end
        end

        local bottomAttRowWidth = bottomAttWidth - 30
        for i = 1, 9 do
            if frame.raidAttRows[i] then frame.raidAttRows[i]:SetWidth(bottomAttRowWidth) end
        end

        local lootRowWidth = bottomLootWidth - 30
        for i = 1, 8 do
            if frame.lootRows[i] then frame.lootRows[i]:SetWidth(lootRowWidth) end
        end

        -- ====================================================================
        -- DYNAMIC COLUMN SIZING
        -- ====================================================================

        -- Raids panel columns (3 columns: #, Date, Zone)
        -- Proportions: 12%, 30%, 58%
        local raidsPanelWidth = topRowWidth
        local raidsNumW = math.floor(raidsPanelWidth * 0.12)
        local raidsDateW = math.floor(raidsPanelWidth * 0.30)
        local raidsZoneW = raidsPanelWidth - raidsNumW - raidsDateW - 10

        for i = 1, 7 do
            local row = frame.raidRows[i]
            if row then
                row.numText:SetWidth(raidsNumW)
                row.dateText:ClearAllPoints()
                row.dateText:SetPoint("LEFT", raidsNumW + 3, 0)
                row.dateText:SetWidth(raidsDateW)
                row.zoneText:ClearAllPoints()
                row.zoneText:SetPoint("LEFT", raidsNumW + raidsDateW + 6, 0)
                row.zoneText:SetWidth(raidsZoneW)
            end
        end

        -- Bosses panel columns (3 columns: #, Name, Time)
        -- Proportions: 12%, 58%, 30%
        local bossNumW = math.floor(topRowWidth * 0.12)
        local bossNameW = math.floor(topRowWidth * 0.58)
        local bossTimeW = topRowWidth - bossNumW - bossNameW - 10

        for i = 1, 7 do
            local row = frame.bossRows[i]
            if row then
                row.numText:SetWidth(bossNumW)
                row.nameText:ClearAllPoints()
                row.nameText:SetPoint("LEFT", bossNumW + 3, 0)
                row.nameText:SetWidth(bossNameW)
                row.timeText:ClearAllPoints()
                row.timeText:SetPoint("LEFT", bossNumW + bossNameW + 6, 0)
                row.timeText:SetWidth(bossTimeW)
            end
        end

        -- Boss Attendees panel (1 column: Name - 100%)
        local bossAttNameW = topRowWidth - 10
        for i = 1, 7 do
            local row = frame.bossAttRows[i]
            if row then
                row.nameText:SetWidth(bossAttNameW)
            end
        end

        -- Raid Attendees panel columns (3 columns: Name, Join, Leave)
        -- Proportions: 45%, 27%, 28%
        local attNameW = math.floor(bottomAttRowWidth * 0.45)
        local attJoinW = math.floor(bottomAttRowWidth * 0.27)
        local attLeaveW = bottomAttRowWidth - attNameW - attJoinW - 10

        for i = 1, 9 do
            local row = frame.raidAttRows[i]
            if row then
                row.nameText:SetWidth(attNameW)
                row.joinText:ClearAllPoints()
                row.joinText:SetPoint("LEFT", attNameW + 5, 0)
                row.joinText:SetWidth(attJoinW)
                row.leaveText:ClearAllPoints()
                row.leaveText:SetPoint("LEFT", attNameW + attJoinW + 10, 0)
                row.leaveText:SetWidth(attLeaveW)
            end
        end

        -- Loot panel columns (4 columns: Icon+Item, Source, Winner, Time)
        -- Proportions: 40%, 20%, 22%, 18%
        local lootItemW = math.floor(lootRowWidth * 0.40)
        local lootSourceW = math.floor(lootRowWidth * 0.20)
        local lootWinnerW = math.floor(lootRowWidth * 0.22)
        local lootTimeW = lootRowWidth - lootItemW - lootSourceW - lootWinnerW - 5

        for i = 1, 8 do
            local row = frame.lootRows[i]
            if row then
                -- Item text is after the 16px icon + 6px padding
                row.itemText:SetWidth(lootItemW - 22)
                row.sourceText:ClearAllPoints()
                row.sourceText:SetPoint("LEFT", lootItemW, 0)
                row.sourceText:SetWidth(lootSourceW)
                row.winnerText:ClearAllPoints()
                row.winnerText:SetPoint("LEFT", lootItemW + lootSourceW, 0)
                row.winnerText:SetWidth(lootWinnerW)
                row.timeText:ClearAllPoints()
                row.timeText:SetPoint("LEFT", lootItemW + lootSourceW + lootWinnerW, 0)
                row.timeText:SetWidth(lootTimeW)
            end
        end

        -- Reposition loot headers to match column positions
        if frame.lootHeaders then
            -- Item header stays at left (offset 8 for panel padding)
            frame.lootHeaders.item:ClearAllPoints()
            frame.lootHeaders.item:SetPoint("TOPLEFT", lootPanel, "TOPLEFT", 8, -42)

            -- Source header aligns with sourceText column
            frame.lootHeaders.source:ClearAllPoints()
            frame.lootHeaders.source:SetPoint("TOPLEFT", lootPanel, "TOPLEFT", 5 + lootItemW, -42)

            -- Winner header aligns with winnerText column
            frame.lootHeaders.winner:ClearAllPoints()
            frame.lootHeaders.winner:SetPoint("TOPLEFT", lootPanel, "TOPLEFT", 5 + lootItemW + lootSourceW, -42)

            -- Time header aligns with timeText column
            frame.lootHeaders.time:ClearAllPoints()
            frame.lootHeaders.time:SetPoint("TOPLEFT", lootPanel, "TOPLEFT", 5 + lootItemW + lootSourceW + lootWinnerW, -42)
        end
    end

    frame:SetScript("OnSizeChanged", ResizePanels)
    frame.ResizePanels = ResizePanels

    -- Create a single delayed update frame (reused for OnShow)
    local delayFrame = CreateFrame("Frame")
    delayFrame:Hide()
    delayFrame.elapsed = 0
    delayFrame:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.1 then
            self:Hide()
            self.elapsed = 0
            ResizePanels()
            LH.RefreshAll()
        end
    end)

    -- Initial resize after a small delay to ensure proper dimensions
    frame:SetScript("OnShow", function()
        -- Reset and start the delay timer
        delayFrame.elapsed = 0
        delayFrame:Show()
    end)

    LH.Frame = frame

    -- Create static popups
    LH.CreatePopups()

    return frame
end

-- ============================================================================
-- HELPER UI CREATION
-- ============================================================================

function LH.CreatePanelFrame(parent, title, width, height)
    local panel = CreateFrame("Frame", nil, parent)
    panel:SetSize(width, height)
    panel:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.9)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", 8, -6)
    titleText:SetText(title)
    titleText:SetTextColor(1, 0.82, 0)
    panel.title = titleText

    return panel
end

function LH.CreateSelectableRow(parent, width, height)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(width, height)
    row:EnableMouse(true)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Ensure row is above scroll frames
    row:SetFrameLevel((parent:GetFrameLevel() or 1) + 5)

    local highlight = row:CreateTexture(nil, "BACKGROUND")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.1)
    highlight:SetBlendMode("ADD")
    highlight:Hide()
    row.highlight = highlight

    row.selected = false

    row:SetScript("OnEnter", function(self)
        self.highlight:Show()
    end)

    row:SetScript("OnLeave", function(self)
        if not self.selected then
            self.highlight:Hide()
        end
    end)

    function row:SetSelected(selected)
        self.selected = selected
        if selected then
            self.highlight:Show()
            self.highlight:SetVertexColor(0.3, 0.5, 0.8, 0.4)
        else
            self.highlight:SetVertexColor(1, 1, 1, 0.1)
            self.highlight:Hide()
        end
    end

    return row
end

-- ============================================================================
-- SELECTION HANDLERS
-- ============================================================================

function LH.SelectRaid(id)
    LH.SelectedRaid = id
    LH.SelectedBoss = nil

    -- Update DB selection
    if AIP.db then
        AIP.db.selectedRaidSessionId = id
        AIP.db.selectedBossId = nil
    end

    LH.RefreshAll()
end

function LH.SelectBoss(id)
    LH.SelectedBoss = id

    -- Update DB selection
    if AIP.db then
        AIP.db.selectedBossId = id
    end

    LH.RefreshBosses()
    LH.RefreshBossAttendees()
    LH.RefreshLoot()
end

-- ============================================================================
-- REFRESH FUNCTIONS
-- ============================================================================

function LH.RefreshAll()
    -- Safe debug function that handles missing AIP.Debug
    local function safeDebug(msg)
        if AIP and AIP.Debug then
            AIP.Debug(msg)
        end
    end

    if not LH.Frame then
        safeDebug("LH.RefreshAll: LH.Frame is nil, skipping")
        return
    end
    if not LH.Frame.raidRows then
        safeDebug("LH.RefreshAll: raidRows not initialized, skipping")
        return
    end

    -- Verify data source is available
    local sessions = LH.GetSessions()
    safeDebug("LH.RefreshAll: Found " .. #sessions .. " sessions")

    LH.RefreshRaids()
    LH.RefreshBosses()
    LH.RefreshBossAttendees()
    LH.RefreshRaidAttendees()
    LH.RefreshLoot()
end

function LH.RefreshRaids()
    if not LH.Frame or not LH.Frame.raidRows then
        return
    end

    local sessions = LH.GetSessions() or {}
    local scrollFrame = LH.Frame.raidsScroll
    if not scrollFrame then return end

    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    FauxScrollFrame_Update(scrollFrame, #sessions, 7, 18)

    for i = 1, 7 do
        local row = LH.Frame.raidRows[i]
        local index = offset + i

        if index <= #sessions then
            local session = sessions[index]
            row.data = session

            row.numText:SetText(index)
            row.dateText:SetText(session.startTime and date("%m/%d %H:%M", session.startTime) or "?")

            -- Shorten zone name
            local zoneName = session.zone or "?"
            if #zoneName > 14 then
                zoneName = zoneName:sub(1, 12) .. ".."
            end
            row.zoneText:SetText(zoneName)

            row:SetSelected(LH.SelectedRaid == session.id)
            row:Show()
        else
            row.data = nil
            row:SetSelected(false)
            row:Hide()
        end
    end
end

function LH.RefreshBosses()
    if not LH.Frame or not LH.Frame.bossRows then return end

    local bosses = LH.GetBosses() or {}
    local scrollFrame = LH.Frame.bossesScroll
    if not scrollFrame then return end
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    FauxScrollFrame_Update(scrollFrame, #bosses, 7, 18)

    for i = 1, 7 do
        local row = LH.Frame.bossRows[i]
        local index = offset + i

        if index <= #bosses then
            local boss = bosses[index]
            row.data = boss

            row.numText:SetText(index)

            local bossName = boss.name or "?"
            if #bossName > 14 then
                bossName = bossName:sub(1, 12) .. ".."
            end
            row.nameText:SetText(bossName)
            row.timeText:SetText(boss.killTime and date("%H:%M", boss.killTime) or "?")

            row:SetSelected(LH.SelectedBoss == boss.id)
            row:Show()
        else
            row.data = nil
            row:SetSelected(false)
            row:Hide()
        end
    end
end

function LH.RefreshBossAttendees()
    if not LH.Frame or not LH.Frame.bossAttRows then return end

    local attendees = LH.GetBossAttendees() or {}
    local scrollFrame = LH.Frame.bossAttScroll
    if not scrollFrame then return end
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    FauxScrollFrame_Update(scrollFrame, #attendees, 7, 18)

    for i = 1, 7 do
        local row = LH.Frame.bossAttRows[i]
        local index = offset + i

        if index <= #attendees then
            local name = attendees[index]
            row.data = name
            row.nameText:SetText(name)
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end

    if LH.Frame.bossAttCount then
        LH.Frame.bossAttCount:SetText(#attendees .. " players")
    end
end

function LH.RefreshRaidAttendees()
    if not LH.Frame or not LH.Frame.raidAttRows then return end

    local attendees = LH.GetRaidAttendees() or {}
    local scrollFrame = LH.Frame.raidAttScroll
    if not scrollFrame then return end
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    FauxScrollFrame_Update(scrollFrame, #attendees, 9, 18)

    for i = 1, 9 do
        local row = LH.Frame.raidAttRows[i]
        local index = offset + i

        if index <= #attendees then
            local att = attendees[index]
            row.data = att

            row.nameText:SetText(att.name or "?")
            row.joinText:SetText(att.joinTime and date("%H:%M", att.joinTime) or "-")
            row.leaveText:SetText(att.leaveTime and date("%H:%M", att.leaveTime) or "-")
            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end

    if LH.Frame.raidAttCount then
        LH.Frame.raidAttCount:SetText(#attendees .. " attendees")
    end
end

function LH.RefreshLoot()
    if not LH.Frame or not LH.Frame.lootRows then return end

    local loot = LH.GetLoot() or {}
    local scrollFrame = LH.Frame.lootScroll
    if not scrollFrame then return end
    local offset = FauxScrollFrame_GetOffset(scrollFrame) or 0

    FauxScrollFrame_Update(scrollFrame, #loot, 8, 18)

    if LH.Frame.lootStats then
        LH.Frame.lootStats:SetText(#loot .. " items")
    end

    for i = 1, 8 do
        local row = LH.Frame.lootRows[i]
        local index = offset + i

        if index <= #loot then
            local entry = loot[index]
            row.data = entry

            local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(entry.itemLink or "")
            if texture then
                row.icon:SetTexture(texture)
                row.icon:Show()
            else
                row.icon:Hide()
            end

            -- Use itemLink if available (includes color codes), otherwise fall back to itemName
            if entry.itemLink then
                row.itemText:SetText(entry.itemLink)
            else
                local color = LH.QualityColors[entry.itemQuality] or LH.QualityColors[1]
                row.itemText:SetText(entry.itemName or "?")
                row.itemText:SetTextColor(color.r, color.g, color.b)
            end

            -- Get boss name from session
            local sourceName = entry.source or "?"
            if entry.bossId and LH.SelectedRaid then
                local session = LH.GetSelectedSession()
                if session and session.bosses then
                    for _, boss in ipairs(session.bosses) do
                        if boss.id == entry.bossId then
                            sourceName = boss.name
                            break
                        end
                    end
                end
            end
            if #sourceName > 12 then
                sourceName = sourceName:sub(1, 10) .. ".."
            end
            row.sourceText:SetText(sourceName)

            row.winnerText:SetText(entry.winner or "?")

            local timeStr = "-"
            if entry.timestamp then
                local age = time() - entry.timestamp
                if age < 3600 then
                    timeStr = math.floor(age / 60) .. "m ago"
                elseif age < 86400 then
                    timeStr = math.floor(age / 3600) .. "h ago"
                else
                    timeStr = date("%m/%d", entry.timestamp)
                end
            end
            row.timeText:SetText(timeStr)

            row:Show()
        else
            row.data = nil
            row:Hide()
        end
    end
end

function LH.Update()
    LH.RefreshAll()
end

-- ============================================================================
-- POPUPS AND DIALOGS
-- ============================================================================

function LH.CreatePopups()
    -- Delete raid confirmation
    StaticPopupDialogs["AIP_CONFIRM_DELETE_RAID"] = {
        text = "Delete this raid session and all its data?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            if LH.SelectedRaid and AIP.RaidSession then
                AIP.RaidSession.DeleteSession(LH.SelectedRaid)
                LH.SelectedRaid = nil
                LH.SelectedBoss = nil
                LH.RefreshAll()
                AIP.Print("Raid session deleted.")
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Clear bosses confirmation
    StaticPopupDialogs["AIP_CONFIRM_CLEAR_BOSSES"] = {
        text = "Clear all boss kills from this session?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            local session = LH.GetSelectedSession()
            if session then
                session.bosses = {}
                LH.SelectedBoss = nil
                LH.RefreshAll()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    -- Clear loot confirmation
    StaticPopupDialogs["AIP_CONFIRM_CLEAR_LOOT"] = {
        text = "Clear all loot from this session?",
        button1 = "Yes",
        button2 = "No",
        OnAccept = function()
            local session = LH.GetSelectedSession()
            if session then
                session.loot = {}
                LH.RefreshLoot()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

function LH.ShowAddBossPopup()
    if not LH.SelectedRaid then
        AIP.Print("Select a raid session first.")
        return
    end

    if not LH.AddBossPopup then
        local popup = CreateFrame("Frame", "AIPAddBossPopup", UIParent)
        popup:SetSize(280, 130)
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
            insets = {left = 8, right = 8, top = 8, bottom = 8}
        })

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Add Boss Kill")
        title:SetTextColor(1, 0.82, 0)

        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local nameLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameLabel:SetPoint("TOPLEFT", 20, -40)
        nameLabel:SetText("Boss Name:")

        local nameInput = CreateFrame("EditBox", nil, popup, "InputBoxTemplate")
        nameInput:SetSize(180, 20)
        nameInput:SetPoint("TOPLEFT", 90, -38)
        nameInput:SetAutoFocus(false)
        popup.nameInput = nameInput

        local addBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        addBtn:SetSize(80, 24)
        addBtn:SetPoint("BOTTOMLEFT", 50, 15)
        addBtn:SetText("Add")
        addBtn:SetScript("OnClick", function()
            local bossName = strtrim(popup.nameInput:GetText() or "")
            if bossName == "" then
                AIP.Print("Please enter a boss name.")
                return
            end
            if not LH.SelectedRaid then
                AIP.Print("Select a raid session first.")
                popup:Hide()
                return
            end
            if AIP.RaidSession then
                -- Manually add boss to current selected session
                local session = LH.GetSelectedSession()
                if session then
                    -- Ensure bosses table exists
                    if not session.bosses then session.bosses = {} end
                    local bossId = #session.bosses + 1
                    local attendees = AIP.RaidSession.GetCurrentRosterNames and AIP.RaidSession.GetCurrentRosterNames() or {}
                    table.insert(session.bosses, {
                        id = bossId,
                        name = bossName,
                        killTime = time(),
                        mode = session.mode or "normal",
                        attendees = attendees,
                    })
                    LH.RefreshAll()
                    AIP.Print("Boss added: " .. bossName)
                else
                    AIP.Print("Could not find the selected raid session.")
                end
            end
            popup.nameInput:SetText("")
            popup:Hide()
        end)

        local cancelBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 24)
        cancelBtn:SetPoint("LEFT", addBtn, "RIGHT", 20, 0)
        cancelBtn:SetText("Cancel")
        cancelBtn:SetScript("OnClick", function() popup:Hide() end)

        popup:Hide()
        tinsert(UISpecialFrames, "AIPAddBossPopup")
        LH.AddBossPopup = popup
    end

    LH.AddBossPopup.nameInput:SetText("")
    LH.AddBossPopup:Show()
end

function LH.ShowExportPopup(text)
    if not LH.ExportPopup then
        local popup = CreateFrame("Frame", "AIPExportPopup", UIParent)
        popup:SetSize(400, 300)
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
            insets = {left = 8, right = 8, top = 8, bottom = 8}
        })

        local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -12)
        title:SetText("Export Session")
        title:SetTextColor(1, 0.82, 0)

        local closeBtn = CreateFrame("Button", nil, popup, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -5, -5)

        local scroll = CreateFrame("ScrollFrame", "AIPExportScroll", popup, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 15, -40)
        scroll:SetPoint("BOTTOMRIGHT", -35, 50)

        local editBox = CreateFrame("EditBox", nil, scroll)
        editBox:SetMultiLine(true)
        editBox:SetAutoFocus(true)
        editBox:SetFontObject(GameFontHighlightSmall)
        editBox:SetWidth(340)
        editBox:SetScript("OnEscapePressed", function() popup:Hide() end)
        scroll:SetScrollChild(editBox)
        popup.editBox = editBox

        local copyBtn = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
        copyBtn:SetSize(80, 24)
        copyBtn:SetPoint("BOTTOM", 0, 15)
        copyBtn:SetText("Select All")
        copyBtn:SetScript("OnClick", function()
            popup.editBox:HighlightText()
            popup.editBox:SetFocus()
        end)

        popup:Hide()
        tinsert(UISpecialFrames, "AIPExportPopup")
        LH.ExportPopup = popup
    end

    LH.ExportPopup.editBox:SetText(text)
    LH.ExportPopup.editBox:HighlightText()
    LH.ExportPopup:Show()
end

function LH.ShowPlayerContextMenu(row, playerName)
    if not playerName then return end

    -- Simple context menu via dropdown
    local menu = CreateFrame("Frame", "AIPPlayerContextMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(menu, function()
        local info = UIDropDownMenu_CreateInfo()
        info.text = playerName
        info.isTitle = true
        info.notCheckable = true
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Add to Loot Ban"
        info.notCheckable = true
        info.func = function()
            -- Open loot ban popup with this player
            if AIP.Panels and AIP.Panels.RaidMgmt and AIP.Panels.RaidMgmt.ShowLootBanAddPopup then
                AIP.Panels.RaidMgmt.ShowLootBanAddPopup(playerName)
            end
        end
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Add to Blacklist"
        info.notCheckable = true
        info.func = function()
            if AIP.AddToBlacklist then
                AIP.AddToBlacklist(playerName, "Added from loot history")
            end
        end
        UIDropDownMenu_AddButton(info)

        info = UIDropDownMenu_CreateInfo()
        info.text = "Add to Favorites"
        info.notCheckable = true
        info.func = function()
            if AIP.AddToFavorites then
                AIP.AddToFavorites(playerName, "Added from loot history")
            end
        end
        UIDropDownMenu_AddButton(info)
    end, "MENU")

    ToggleDropDownMenu(1, nil, menu, row, 0, 0)
end

function LH.ExportLootToChat()
    if not LH.SelectedRaid then
        AIP.Print("Select a raid session first.")
        return
    end
    local session = LH.GetSelectedSession()
    if not session then
        AIP.Print("Could not find the selected raid session.")
        return
    end
    if not session.loot or #session.loot == 0 then
        AIP.Print("No loot to export in this session.")
        return
    end

    AIP.Print("Exporting " .. #session.loot .. " items to raid chat...")

    -- Send to raid or party
    local chatType = GetNumRaidMembers() > 0 and "RAID" or "PARTY"

    SendChatMessage("=== Loot Distribution (" .. (session.zone or "Unknown") .. ") ===", chatType)

    for _, entry in ipairs(session.loot) do
        local msg = (entry.itemLink or entry.itemName or "?") .. " - " .. (entry.winner or "?")
        SendChatMessage(msg, chatType)
    end
end

function LH.PostBossLootToChat(chatType)
    if not LH.SelectedRaid then
        AIP.Print("Select a raid session first.")
        return
    end
    if not LH.SelectedBoss then
        AIP.Print("Select a boss first.")
        return
    end

    local session = LH.GetSelectedSession()
    if not session then
        AIP.Print("Could not find the selected session.")
        return
    end

    -- Get boss name
    local bossName = "Unknown Boss"
    if session.bosses then
        for _, boss in ipairs(session.bosses) do
            if boss.id == LH.SelectedBoss then
                bossName = boss.name
                break
            end
        end
    end

    -- Filter loot for selected boss
    local bossLoot = {}
    if session.loot then
        for _, entry in ipairs(session.loot) do
            if entry.bossId == LH.SelectedBoss then
                table.insert(bossLoot, entry)
            end
        end
    end

    if #bossLoot == 0 then
        AIP.Print("No loot recorded for this boss.")
        return
    end

    -- Send header
    SendChatMessage("=== " .. bossName .. " Loot ===", chatType)

    -- Send each item
    for _, entry in ipairs(bossLoot) do
        local msg = (entry.itemLink or entry.itemName or "?") .. " -> " .. (entry.winner or "?")
        SendChatMessage(msg, chatType)
    end

    AIP.Print("Posted " .. #bossLoot .. " items to " .. chatType .. " chat.")
end

-- ============================================================================
-- LOOT EVENT TRACKING (Legacy integration)
-- ============================================================================

local lastSource = nil
local lastSourceTime = 0

local lootFrame = CreateFrame("Frame")
lootFrame:RegisterEvent("CHAT_MSG_LOOT")
lootFrame:RegisterEvent("CHAT_MSG_MONSTER_YELL")
lootFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
lootFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
lootFrame:SetScript("OnEvent", function(self, event, ...)
    -- Handle pending items when item info becomes available
    if event == "GET_ITEM_INFO_RECEIVED" then
        if LH.PendingItems and #LH.PendingItems > 0 then
            local pending = LH.PendingItems
            LH.PendingItems = {}
            local now = time()
            local PENDING_TIMEOUT = 300  -- 5 minutes max wait for item info
            for _, item in ipairs(pending) do
                -- Skip items that have been pending too long
                if item.timestamp and (now - item.timestamp) < PENDING_TIMEOUT then
                    LH.AddLootEntry(item.itemLink, item.looter, item.source, item.zone)
                end
            end
        end
        return
    end
    if event == "CHAT_MSG_MONSTER_YELL" then
        local _, sender = ...
        if sender then
            lastSource = sender
            lastSourceTime = time()
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        if UnitExists("target") and UnitIsDead("target") then
            local name = UnitName("target")
            local classification = UnitClassification("target")
            if name and (classification == "worldboss" or classification == "rareelite" or classification == "elite") then
                lastSource = name
                lastSourceTime = time()
            end
        end
        return
    end

    if event == "CHAT_MSG_LOOT" then
        local message = ...

        local numRaid = GetNumRaidMembers() or 0
        local numParty = GetNumPartyMembers() or 0
        if numRaid == 0 and numParty == 0 then return end

        local itemLink = message:match("|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r")
        if not itemLink then return end

        local looter = nil
        if message:find("You receive loot") then
            looter = UnitName("player")
        else
            looter = message:match("^(%S+) receive") or message:match("^(%S+) won")
        end
        looter = looter or "Unknown"

        local source = "Trash"
        if lastSource and lastSourceTime and (time() - lastSourceTime) < 120 then
            source = lastSource
        end

        LH.AddLootEntry(itemLink, looter, source, GetRealZoneText())
    end
end)

-- ============================================================================
-- CLEANUP OLD ENTRIES
-- ============================================================================

function LH.CleanupOldEntries()
    if not AIP.db then return end
    local retentionDays = AIP.db.lootHistoryRetentionDays or 30
    if retentionDays == 0 then return end  -- 0 = keep forever

    local history = AIP.db.lootHistory
    if not history or #history == 0 then return end

    local cutoffTime = time() - (retentionDays * 24 * 60 * 60)
    local removed = 0

    -- Iterate backwards to safely remove entries
    for i = #history, 1, -1 do
        local entry = history[i]
        if entry.timestamp and entry.timestamp < cutoffTime then
            table.remove(history, i)
            removed = removed + 1
        end
    end

    if removed > 0 then
        AIP.Debug("Loot History: Cleaned up " .. removed .. " entries older than " .. retentionDays .. " days")
    end

    -- Also cleanup old raid sessions
    local sessions = AIP.db.raidSessions
    if sessions then
        for i = #sessions, 1, -1 do
            local session = sessions[i]
            if session.startTime and session.startTime < cutoffTime then
                table.remove(sessions, i)
            end
        end
    end
end

-- ============================================================================
-- RAID SESSION TRACKING (Legacy)
-- ============================================================================

local raidTrackingFrame = CreateFrame("Frame")
raidTrackingFrame:RegisterEvent("RAID_ROSTER_UPDATE")
raidTrackingFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
raidTrackingFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
raidTrackingFrame:SetScript("OnEvent", function(self, event, ...)
    if not AIP.db then return end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Cleanup old entries on login
        LH.CleanupOldEntries()

        -- Restore selection from DB
        if AIP.db.selectedRaidSessionId then
            LH.SelectedRaid = AIP.db.selectedRaidSessionId
        end
        if AIP.db.selectedBossId then
            LH.SelectedBoss = AIP.db.selectedBossId
        end

        -- Check if we're in a group and set raid start time (legacy)
        local numRaid = GetNumRaidMembers() or 0
        local numParty = GetNumPartyMembers() or 0
        if numRaid > 0 or numParty > 0 then
            if not AIP.db.currentRaidStartTime then
                AIP.db.currentRaidStartTime = time()
            end
        else
            AIP.db.currentRaidStartTime = nil
        end
        return
    end

    local numRaid = GetNumRaidMembers() or 0
    local numParty = GetNumPartyMembers() or 0

    if numRaid > 0 or numParty > 0 then
        -- In a group: set raid start time if not already set (legacy)
        if not AIP.db.currentRaidStartTime then
            AIP.db.currentRaidStartTime = time()
            AIP.Debug("Loot History: Raid session started")
        end
    else
        -- Not in a group: clear raid start time (legacy)
        if AIP.db.currentRaidStartTime then
            AIP.db.currentRaidStartTime = nil
            AIP.Debug("Loot History: Raid session ended")
        end
    end
end)

-- ============================================================================
-- TEST DATA FUNCTION
-- ============================================================================

function LH.LoadTestData()
    if not AIP.db then
        AIP.Print("Database not initialized.")
        return
    end

    -- First, clear any existing test data (IDs 9001-9999)
    LH.ClearTestData()

    -- Ensure raidSessions table exists
    if not AIP.db.raidSessions then
        AIP.db.raidSessions = {}
    end

    -- Test player roster
    local testPlayers = {
        "Tankadin", "Bearform", "Shieldwall",                    -- Tanks
        "Holylight", "Treeheals", "Circleofheal", "Chainbounce", "Discpriest", "Shamanheal", -- Healers
        "Firemage", "Frostnova", "Arcanemiss",                   -- Mages
        "Hunterpet", "Steadyshot", "Multishot",                  -- Hunters
        "Sinisterstrike", "Mutilate", "Shadowstep",              -- Rogues
        "Chaosbolt", "Shadowbolt", "Felguard",                   -- Warlocks
        "Stormstrike", "Lavaburst",                              -- Enhancement/Elemental Shaman
        "Mortalstrike", "Bloodthirst",                           -- Warriors DPS
        "Howlingblast", "Scourgestrike",                         -- DKs
        "Moonfire", "Starfall",                                  -- Boomkins
        "Crusaderstrike",                                        -- Ret Paladin
    }

    -- Test loot with REAL item IDs from ICC/RS (WotLK 3.3.5)
    -- Format: |cffCOLOR|Hitem:ID:0:0:0:0:0:0:0:80|h[Name]|h|r
    local testLoot = {
        -- Lord Marrowgar drops
        {itemId = 50274, itemName = "Shadowvault Slayer's Cloak", itemQuality = 4},
        {itemId = 50415, itemName = "Bryntroll, the Bone Arbiter", itemQuality = 4},
        {itemId = 50339, itemName = "Marrowgar's Frigid Eye", itemQuality = 4},
        -- Lady Deathwhisper drops
        {itemId = 50411, itemName = "Frost Needle", itemQuality = 4},
        {itemId = 50414, itemName = "Nibelung", itemQuality = 4},
        -- Gunship Battle drops
        {itemId = 50791, itemName = "Gunship Captain's Mittens", itemQuality = 4},
        -- Deathbringer Saurfang drops
        {itemId = 50362, itemName = "Deathbringer's Will", itemQuality = 4},
        {itemId = 50412, itemName = "Bloodvenom Blade", itemQuality = 4},
        -- Festergut drops
        {itemId = 50966, itemName = "Festergut's Acidic Blood", itemQuality = 4},
        -- Rotface drops
        {itemId = 50967, itemName = "Rotface's Acidic Blood", itemQuality = 4},
        -- Professor Putricide drops
        {itemId = 50351, itemName = "Tiny Abomination in a Jar", itemQuality = 4},
        -- Blood Prince Council drops
        {itemId = 50172, itemName = "Sanguine Silk Robes", itemQuality = 4},
        -- Blood-Queen Lana'thel drops
        {itemId = 50182, itemName = "Blood Queen's Crimson Choker", itemQuality = 4},
        -- Sindragosa drops
        {itemId = 50424, itemName = "Memory of Malygos", itemQuality = 4},
        -- Lich King drops
        {itemId = 50818, itemName = "Invincible's Reins", itemQuality = 4},  -- Mount
        {itemId = 50428, itemName = "Royal Scepter of Terenas II", itemQuality = 4},
    }

    -- Quality colors for item links (standard WoW colors)
    local qualityColors = {
        [2] = "1eff00",  -- Uncommon (green)
        [3] = "0070dd",  -- Rare (blue)
        [4] = "a335ee",  -- Epic (purple)
        [5] = "ff8000",  -- Legendary (orange)
    }

    -- Helper function to create a proper WoW item link
    local function MakeItemLink(itemId, itemName, itemQuality)
        local color = qualityColors[itemQuality] or "ffffff"
        -- Format: |cffCOLOR|Hitem:ID:enchant:gem1:gem2:gem3:gem4:suffixID:uniqueID:level|h[Name]|h|r
        return string.format("|cff%s|Hitem:%d:0:0:0:0:0:0:0:80|h[%s]|h|r", color, itemId, itemName)
    end

    -- ICC boss list
    local iccBosses = {
        "Lord Marrowgar",
        "Lady Deathwhisper",
        "Gunship Battle",
        "Deathbringer Saurfang",
        "Festergut",
        "Rotface",
        "Professor Putricide",
        "Blood Prince Council",
        "Blood-Queen Lana'thel",
        "Valithria Dreamwalker",
        "Sindragosa",
        "The Lich King",
    }

    -- Ruby Sanctum bosses
    local rsBosses = {
        "Saviana Ragefire",
        "Baltharus the Warborn",
        "General Zarithrian",
        "Halion",
    }

    -- Create test sessions
    local now = time()

    -- Session 1: ICC 25 Heroic - 2 days ago
    local session1Start = now - (86400 * 2)
    local session1 = {
        id = 9001,
        zone = "Icecrown Citadel",
        size = 25,
        mode = "25H",
        startTime = session1Start,
        endTime = session1Start + 14400,  -- 4 hours later
        bosses = {},
        attendees = {},
        loot = {},
    }

    -- Add bosses for session 1
    local bossTime = session1Start
    for i, bossName in ipairs(iccBosses) do
        bossTime = bossTime + 600 + math.random(300)  -- 10-15 min per boss
        local bossAttendees = {}
        for j = 1, math.min(25, #testPlayers) do
            table.insert(bossAttendees, testPlayers[j])
        end
        table.insert(session1.bosses, {
            id = i,
            name = bossName,
            killTime = bossTime,
            mode = "25H",
            attendees = bossAttendees,
        })
    end

    -- Add attendees for session 1
    for i = 1, 25 do
        if i <= #testPlayers then
            local leaveOffset = (i <= 20) and 14400 or (7200 + math.random(3600))  -- Most stay, some leave early
            table.insert(session1.attendees, {
                name = testPlayers[i],
                joinTime = session1Start + (i <= 20 and 0 or math.random(1800)),
                leaveTime = session1Start + leaveOffset,
            })
        end
    end

    -- Add loot for session 1
    local lootTime = session1Start + 700
    for i = 1, 12 do
        local lootEntry = testLoot[i] or testLoot[1]
        local bossIdx = math.min(i, #iccBosses)
        local winnerIdx = math.random(1, math.min(25, #testPlayers))
        table.insert(session1.loot, {
            itemLink = MakeItemLink(lootEntry.itemId, lootEntry.itemName, lootEntry.itemQuality),
            itemId = lootEntry.itemId,
            itemName = lootEntry.itemName,
            itemQuality = lootEntry.itemQuality,
            winner = testPlayers[winnerIdx],
            bossId = bossIdx,
            source = iccBosses[bossIdx],
            timestamp = lootTime,
        })
        lootTime = lootTime + 600 + math.random(300)
    end

    -- Insert at beginning (newest first)
    table.insert(AIP.db.raidSessions, 1, session1)

    -- Session 2: Ruby Sanctum 25 - 1 day ago
    local session2Start = now - 86400
    local session2 = {
        id = 9002,
        zone = "The Ruby Sanctum",
        size = 25,
        mode = "25N",
        startTime = session2Start,
        endTime = session2Start + 3600,  -- 1 hour
        bosses = {},
        attendees = {},
        loot = {},
    }

    local bossTime2 = session2Start
    for i, bossName in ipairs(rsBosses) do
        bossTime2 = bossTime2 + 600 + math.random(300)
        local bossAttendees = {}
        for j = 1, math.min(25, #testPlayers) do
            table.insert(bossAttendees, testPlayers[j])
        end
        table.insert(session2.bosses, {
            id = i,
            name = bossName,
            killTime = bossTime2,
            mode = "25N",
            attendees = bossAttendees,
        })
    end

    for i = 1, math.min(25, #testPlayers) do
        table.insert(session2.attendees, {
            name = testPlayers[i],
            joinTime = session2Start,
            leaveTime = session2Start + 3600,
        })
    end

    -- Add some loot for RS (Halion drops - real item IDs)
    table.insert(session2.loot, {
        itemLink = MakeItemLink(54572, "Charred Twilight Scale", 4),
        itemId = 54572,
        itemName = "Charred Twilight Scale",
        itemQuality = 4,
        winner = testPlayers[5],
        bossId = 4,
        source = "Halion",
        timestamp = session2Start + 3000,
    })
    table.insert(session2.loot, {
        itemLink = MakeItemLink(54569, "Sharpened Twilight Scale", 4),
        itemId = 54569,
        itemName = "Sharpened Twilight Scale",
        itemQuality = 4,
        winner = testPlayers[12],
        bossId = 4,
        source = "Halion",
        timestamp = session2Start + 3100,
    })

    table.insert(AIP.db.raidSessions, 1, session2)

    -- Session 3: ICC 10 - 5 days ago
    local session3Start = now - (86400 * 5)
    local session3 = {
        id = 9003,
        zone = "Icecrown Citadel",
        size = 10,
        mode = "10N",
        startTime = session3Start,
        endTime = session3Start + 10800,  -- 3 hours
        bosses = {},
        attendees = {},
        loot = {},
    }

    local bossTime3 = session3Start
    for i = 1, 6 do  -- Only first 6 bosses
        local bossName = iccBosses[i]
        bossTime3 = bossTime3 + 900 + math.random(600)
        local bossAttendees = {}
        for j = 1, math.min(10, #testPlayers) do
            table.insert(bossAttendees, testPlayers[j])
        end
        table.insert(session3.bosses, {
            id = i,
            name = bossName,
            killTime = bossTime3,
            mode = "10N",
            attendees = bossAttendees,
        })
    end

    for i = 1, math.min(10, #testPlayers) do
        table.insert(session3.attendees, {
            name = testPlayers[i],
            joinTime = session3Start,
            leaveTime = session3Start + 10800,
        })
    end

    -- Add some loot for session 3 (ICC 10 - real item IDs)
    table.insert(session3.loot, {
        itemLink = MakeItemLink(50415, "Bryntroll, the Bone Arbiter", 4),
        itemId = 50415,
        itemName = "Bryntroll, the Bone Arbiter",
        itemQuality = 4,
        winner = testPlayers[8],
        bossId = 1,
        source = "Lord Marrowgar",
        timestamp = session3Start + 1000,
    })

    table.insert(AIP.db.raidSessions, 1, session3)

    -- Select first raid and refresh
    LH.SelectedRaid = 9001
    LH.SelectedBoss = nil
    AIP.db.selectedRaidSessionId = 9001
    AIP.db.selectedBossId = nil

    LH.RefreshAll()
    AIP.Print("Test data loaded: 3 raid sessions with bosses, attendees, and loot.")
end

function LH.ClearTestData()
    if not AIP.db then return end

    -- Remove test sessions (IDs 9001-9999)
    if AIP.db.raidSessions then
        local filtered = {}
        for _, session in ipairs(AIP.db.raidSessions) do
            if session.id < 9001 or session.id > 9999 then
                table.insert(filtered, session)
            end
        end
        AIP.db.raidSessions = filtered
    end

    LH.SelectedRaid = nil
    LH.SelectedBoss = nil
    AIP.db.selectedRaidSessionId = nil
    AIP.db.selectedBossId = nil

    LH.RefreshAll()
    AIP.Print("Test data cleared.")
end

-- Alias for backward compatibility with SettingsPanel
LH.RefreshList = LH.RefreshAll
