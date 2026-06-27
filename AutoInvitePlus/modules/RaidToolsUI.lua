-- AutoInvite Plus - Raid Tools (UI: roll window, announcement config, floating bar)

local AIP = AutoInvitePlus
if not AIP then return end
AIP.RaidTools = AIP.RaidTools or {}
local RT = AIP.RaidTools

local ITEM_ROWS = 14
local ROLL_ROWS = 14
local ROW_H = 18

local CHANNELS = { "RAID_WARNING", "RAID", "PARTY", "SAY", "YELL", "GUILD" }

function RT.ItemQualityColor(q)
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]
        return c.r, c.g, c.b
    end
    return 1, 1, 1
end

-- Shared helper: a titled, bordered panel (inset box)
local function MakeBox(parent, w, h)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(w, h)
    box:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    box:SetBackdropColor(0.04, 0.04, 0.05, 0.95)
    box:SetBackdropBorderColor(0.35, 0.35, 0.4)
    return box
end

-- Shared helper: a clean, consistently-styled text input (replaces the stock
-- InputBoxTemplate look). Dark fill, subtle border, proper text padding.
local function MakeInput(parent, w, h)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(w, h or 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetTextColor(1, 1, 1)
    eb:SetTextInsets(6, 6, 0, 0)
    eb:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3},
    })
    eb:SetBackdropColor(0, 0, 0, 0.55)
    eb:SetBackdropBorderColor(0.45, 0.45, 0.5)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    -- brighten the border while focused for clear affordance
    eb:SetScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(1, 0.82, 0) end)
    eb:SetScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(0.45, 0.45, 0.5) end)
    return eb
end

-- ============================================================================
-- ROLL WINDOW
-- ============================================================================

function RT.CreateRollWindow()
    if RT.Window then return RT.Window end

    local win = CreateFrame("Frame", "AIPRollWindow", UIParent)
    win:SetSize(670, 452)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    })
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true)
    win:Hide()

    -- Title
    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cFFFFD700Loot Roll|r")

    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Status / countdown banner
    local statusBg = MakeBox(win, 622, 24)
    statusBg:SetPoint("TOP", 0, -38)
    local status = statusBg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("CENTER")
    status:SetText("Select an item, then click |cFF40FF40Roll!|r")
    win.status = status

    -- ---- LEFT: items ----
    local itemHeader = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    itemHeader:SetPoint("TOPLEFT", 22, -72)
    itemHeader:SetText("|cFFFFD700Items in current raid|r")
    win.itemHeader = itemHeader

    local itemBg = MakeBox(win, 300, ITEM_ROWS * ROW_H + 8)
    itemBg:SetPoint("TOPLEFT", itemHeader, "BOTTOMLEFT", 0, -4)

    local emptyText = itemBg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    emptyText:SetPoint("TOPLEFT", 8, -8)
    emptyText:SetPoint("BOTTOMRIGHT", -8, 8)
    emptyText:SetJustifyH("CENTER"); emptyText:SetJustifyV("MIDDLE")
    emptyText:SetText("No raid loot yet.\nItems looted in your raid appear here.\nShift-click an item (or type a name) below to add one.")
    win.emptyText = emptyText

    win.itemRows = {}
    for i = 1, ITEM_ROWS do
        local row = CreateFrame("Button", nil, itemBg)
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", itemBg, "RIGHT", -5, 0)
        row:SetHeight(ROW_H)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        row.hl:SetTexture(0.25, 0.45, 0.85, 0.5)
        row.hl:Hide()
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetTexture(1, 0.82, 0, 0.25)
        row.sel:Hide()
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", 6, 0)
        row.name:SetWidth(212); row.name:SetJustifyH("LEFT")
        row.exp = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.exp:SetPoint("RIGHT", -6, 0)
        row.exp:SetWidth(64); row.exp:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            if self.itemData then RT.selectedKey = self.itemData.key; RT.RefreshRollWindow() end
        end)
        row:SetScript("OnEnter", function(self)
            self.hl:Show()
            if self.itemData and self.itemData.link then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemData.link)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        win.itemRows[i] = row
    end

    -- Add-item row (shift-click inserts the item link)
    local addInput = MakeInput(win, 224, 22)
    addInput:SetPoint("TOPLEFT", itemBg, "BOTTOMLEFT", 6, -12)
    addInput:SetScript("OnEnterPressed", function(self)
        RT.AddManualItem(self:GetText()); self:SetText(""); self:ClearFocus()
    end)
    addInput:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Add item", 1, 0.82, 0)
        GameTooltip:AddLine("Shift-click an item in your bags to insert it,", 1, 1, 1, true)
        GameTooltip:AddLine("or type a name, then press Enter / Add.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    addInput:SetScript("OnLeave", function() GameTooltip:Hide() end)
    win.addInput = addInput
    local addPrompt = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    addPrompt:SetPoint("BOTTOMLEFT", addInput, "TOPLEFT", 0, 1)
    addPrompt:SetText("Add item (shift-click or type):")

    local addBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 20)
    addBtn:SetPoint("LEFT", addInput, "RIGHT", 6, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        RT.AddManualItem(addInput:GetText()); addInput:SetText("")
    end)

    -- ---- RIGHT: rolls ----
    local rollHeader = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollHeader:SetPoint("TOPLEFT", itemHeader, "TOPLEFT", 324, 0)
    rollHeader:SetText("|cFFFFD700Rolls|r")
    win.rollHeader = rollHeader

    local rollBg = MakeBox(win, 296, ROLL_ROWS * ROW_H + 8)
    rollBg:SetPoint("TOPLEFT", rollHeader, "BOTTOMLEFT", 0, -4)

    win.rollRows = {}
    for i = 1, ROLL_ROWS do
        local row = CreateFrame("Frame", nil, rollBg)
        row:SetPoint("TOPLEFT", 5, -5 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", rollBg, "RIGHT", -5, 0)
        row:SetHeight(ROW_H)
        row.rank = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.rank:SetPoint("LEFT", 5, 0)
        row.rank:SetWidth(26); row.rank:SetJustifyH("LEFT")
        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", 34, 0)
        row.name:SetWidth(196); row.name:SetJustifyH("LEFT")
        row.val = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.val:SetPoint("RIGHT", -8, 0)
        row.val:SetWidth(48); row.val:SetJustifyH("RIGHT")
        win.rollRows[i] = row
    end

    -- ---- BOTTOM action bar ----
    -- left group: secs + roll + cancel
    local durLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    durLabel:SetPoint("BOTTOMLEFT", 24, 26)
    durLabel:SetText("Timer (s):")
    local durInput = MakeInput(win, 42, 22)
    durInput:SetPoint("LEFT", durLabel, "RIGHT", 8, 0)
    durInput:SetNumeric(true); durInput:SetJustifyH("CENTER")
    durInput:SetText(tostring((AIP.db and AIP.db.rollDuration) or 10))
    durInput:SetScript("OnTextChanged", function(self)
        local v = tonumber(self:GetText())
        if v and AIP.db then AIP.db.rollDuration = math.max(3, math.min(60, v)) end
    end)

    local rollBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    rollBtn:SetSize(80, 24)
    rollBtn:SetPoint("LEFT", durInput, "RIGHT", 12, 0)
    rollBtn:SetText("Roll!")
    rollBtn:SetScript("OnClick", function()
        local items = RT.GetRollItems()
        local sel
        for _, it in ipairs(items) do if it.key == RT.selectedKey then sel = it break end end
        if sel then RT.StartRoll(sel.name, sel.link)
        else AIP.Print("Select an item to roll for first (or add one).") end
    end)
    local cancelBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    cancelBtn:SetSize(64, 24)
    cancelBtn:SetPoint("LEFT", rollBtn, "RIGHT", 6, 0)
    cancelBtn:SetText("Cancel")
    cancelBtn:SetScript("OnClick", function() RT.CancelRoll() end)

    -- right group: top N + announce + trade
    local tradeBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    tradeBtn:SetSize(116, 24)
    tradeBtn:SetPoint("BOTTOMRIGHT", -22, 26)
    tradeBtn:SetText("Trade Winner")
    tradeBtn:SetScript("OnClick", function() RT.TradeWinner() end)

    local announceBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    announceBtn:SetSize(130, 24)
    announceBtn:SetPoint("RIGHT", tradeBtn, "LEFT", -6, 0)
    announceBtn:SetText("Announce Top")
    local topInput = MakeInput(win, 36, 22)
    topInput:SetPoint("RIGHT", announceBtn, "LEFT", -8, 0)
    topInput:SetNumeric(true); topInput:SetJustifyH("CENTER"); topInput:SetText("1")
    win.topInput = topInput
    announceBtn:SetScript("OnClick", function()
        RT.AnnounceWinners(tonumber(topInput:GetText()) or 1)
    end)
    local topLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    topLabel:SetPoint("RIGHT", topInput, "LEFT", -4, 0)
    topLabel:SetText("Top")

    -- Throttled updater: countdown ~0.3s, expiry refresh ~5s
    win.cd = 0; win.expAcc = 0
    win:SetScript("OnUpdate", function(self, e)
        if RT.rollActive and RT.rollEndTime then
            self.cd = self.cd + e
            if self.cd >= 0.3 then
                self.cd = 0
                local left = math.max(0, RT.rollEndTime - time())
                self.status:SetText("|cFFFFD700Rolling:|r " .. (RT.rollItemLink or tostring(RT.rollItem)) ..
                    "   |cFF40FF40" .. left .. "s|r   (" .. #RT.GetSortedRolls() .. " rolls)")
            end
        end
        self.expAcc = self.expAcc + e
        if self.expAcc >= 5 then self.expAcc = 0; RT.RefreshItemList() end
    end)

    RT.Window = win
    return win
end

function RT.RefreshItemList()
    local win = RT.Window
    if not win or not win:IsShown() then return end
    local items = RT.GetRollItems()
    if win.itemHeader then win.itemHeader:SetText("|cFFFFD700Items in current raid|r (" .. #items .. ")") end
    if win.emptyText then if #items == 0 then win.emptyText:Show() else win.emptyText:Hide() end end
    for i = 1, ITEM_ROWS do
        local row = win.itemRows[i]
        local it = items[i]
        if it then
            row.itemData = it
            local prefix = it.winner and "|cFF888888[won]|r " or ""
            row.name:SetText(prefix .. it.name)
            local r, g, b = RT.ItemQualityColor(it.quality)
            row.name:SetTextColor(r, g, b)
            row.exp:SetText(RT.FormatRemaining(it.remaining))
            if it.expiring then row.exp:SetTextColor(1, 0.3, 0.3) else row.exp:SetTextColor(0.55, 0.85, 0.55) end
            if it.key == RT.selectedKey then row.sel:Show() else row.sel:Hide() end
            row:Show()
        else
            row.itemData = nil; row.sel:Hide(); row:Hide()
        end
    end
end

function RT.RefreshRollWindow()
    local win = RT.Window
    if not win or not win:IsShown() then return end
    RT.RefreshItemList()

    local sorted = RT.GetSortedRolls()
    if win.rollHeader then win.rollHeader:SetText("|cFFFFD700Rolls|r (" .. #sorted .. ")") end
    local medal = { {1,0.84,0}, {0.75,0.75,0.78}, {0.8,0.5,0.2} }
    for i = 1, ROLL_ROWS do
        local row = win.rollRows[i]
        local r = sorted[i]
        if r then
            row.rank:SetText(i .. ".")
            row.name:SetText(r.name)
            row.val:SetText(tostring(r.value))
            local c = medal[i] or {0.9, 0.9, 0.9}
            row.rank:SetTextColor(c[1], c[2], c[3])
            row.name:SetTextColor(c[1], c[2], c[3])
            row.val:SetTextColor(c[1], c[2], c[3])
            row:Show()
        else
            row:Hide()
        end
    end

    if not RT.rollActive and win.status then
        if sorted[1] then
            win.status:SetText("Winner so far: |cFFFFD700" .. sorted[1].name .. "|r (" .. sorted[1].value .. ")")
        else
            win.status:SetText("Select an item, then click |cFF40FF40Roll!|r")
        end
    end
end

function RT.ToggleRollWindow()
    RT.CreateRollWindow()
    if RT.Window:IsShown() then RT.Window:Hide()
    else RT.Window:Show(); RT.RefreshRollWindow() end
end

-- ============================================================================
-- ANNOUNCEMENT BAR CONFIG WINDOW (friendly row editor)
-- ============================================================================

local AC_ROWS = 12

function RT.CreateAnnounceConfig()
    if RT.ConfigWin then return RT.ConfigWin end

    local win = CreateFrame("Frame", "AIPAnnounceConfig", UIParent)
    win:SetSize(560, 420)
    win:SetPoint("CENTER", 120, 0)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = {left = 11, right = 12, top = 12, bottom = 11},
    })
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true); win:Hide()

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cFFFFD700Floating Bar Buttons|r")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local help = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOP", title, "BOTTOM", 0, -4)
    help:SetText("Each row is a button on the floating bar. Click the channel to cycle it.")

    -- Column headers
    local hLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hLabel:SetPoint("TOPLEFT", 24, -56); hLabel:SetText("|cFFFFD700Button label|r")
    local hMsg = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hMsg:SetPoint("TOPLEFT", 150, -56); hMsg:SetText("|cFFFFD700Message|r")
    local hChan = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hChan:SetPoint("TOPLEFT", 400, -56); hChan:SetText("|cFFFFD700Channel|r")

    local listBg = MakeBox(win, 516, AC_ROWS * 26 + 8)
    listBg:SetPoint("TOPLEFT", 22, -72)

    win.acRows = {}
    for i = 1, AC_ROWS do
        local y = -6 - (i - 1) * 26
        local row = CreateFrame("Frame", nil, listBg)
        row:SetPoint("TOPLEFT", 6, y); row:SetPoint("RIGHT", listBg, "RIGHT", -6, 0)
        row:SetHeight(24)

        local labelBox = MakeInput(row, 110, 22)
        labelBox:SetPoint("LEFT", 6, 0)
        labelBox:SetScript("OnTextChanged", function(self)
            if row.entry then row.entry.label = self:GetText() end
        end)
        row.labelBox = labelBox

        local msgBox = MakeInput(row, 228, 22)
        msgBox:SetPoint("LEFT", labelBox, "RIGHT", 12, 0)
        msgBox:SetScript("OnTextChanged", function(self)
            if row.entry then row.entry.message = self:GetText() end
        end)
        row.msgBox = msgBox

        local chanBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        chanBtn:SetPoint("LEFT", msgBox, "RIGHT", 14, 0); chanBtn:SetSize(96, 20)
        chanBtn:SetScript("OnClick", function(self)
            if not row.entry then return end
            local cur = row.entry.channel or "RAID_WARNING"
            local idx = 1
            for k, v in ipairs(CHANNELS) do if v == cur then idx = k break end end
            row.entry.channel = CHANNELS[(idx % #CHANNELS) + 1]
            self:SetText(row.entry.channel)
            if RT.RefreshBar then RT.RefreshBar() end
        end)
        row.chanBtn = chanBtn

        local sendBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        sendBtn:SetPoint("LEFT", chanBtn, "RIGHT", 4, 0); sendBtn:SetSize(20, 20); sendBtn:SetText(">")
        sendBtn:SetScript("OnClick", function()
            if row.entry then RT.Send(row.entry.message, row.entry.channel or "RAID_WARNING") end
        end)
        sendBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Test (send now)"); GameTooltip:Show()
        end)
        sendBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        delBtn:SetPoint("LEFT", sendBtn, "RIGHT", 2, 0); delBtn:SetSize(20, 20); delBtn:SetText("X")
        delBtn:SetScript("OnClick", function()
            local list = RT.GetAnnouncements()
            if row.dbIndex and list[row.dbIndex] then
                table.remove(list, row.dbIndex)
                RT.RefreshAnnounceConfig()
                if RT.RefreshBar then RT.RefreshBar() end
            end
        end)
        delBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine("Remove this button", 1, 0.4, 0.4); GameTooltip:Show()
        end)
        delBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        row:Hide()
        win.acRows[i] = row
    end

    local addBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    addBtn:SetSize(140, 24)
    addBtn:SetPoint("BOTTOMLEFT", 24, 24)
    addBtn:SetText("+ Add Button")
    addBtn:SetScript("OnClick", function()
        local list = RT.GetAnnouncements()
        if #list >= AC_ROWS then
            AIP.Print("Bar button limit reached (" .. AC_ROWS .. ").")
            return
        end
        table.insert(list, { label = "New Button", message = "Type your message", channel = "RAID_WARNING" })
        RT.RefreshAnnounceConfig()
        if RT.RefreshBar then RT.RefreshBar() end
    end)

    local doneBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    doneBtn:SetSize(120, 24)
    doneBtn:SetPoint("BOTTOMRIGHT", -24, 24)
    doneBtn:SetText("Done")
    doneBtn:SetScript("OnClick", function()
        if RT.RefreshBar then RT.RefreshBar() end
        win:Hide()
    end)

    RT.ConfigWin = win
    return win
end

function RT.RefreshAnnounceConfig()
    local win = RT.ConfigWin
    if not win then return end
    local list = RT.GetAnnouncements()
    for i = 1, AC_ROWS do
        local row = win.acRows[i]
        local entry = list[i]
        if entry then
            row.entry = entry
            row.dbIndex = i
            row.labelBox:SetText(entry.label or "")
            row.msgBox:SetText(entry.message or "")
            row.chanBtn:SetText(entry.channel or "RAID_WARNING")
            row:Show()
        else
            row.entry = nil; row.dbIndex = nil; row:Hide()
        end
    end
end

function RT.ToggleAnnounceConfig()
    RT.CreateAnnounceConfig()
    if RT.ConfigWin:IsShown() then
        RT.ConfigWin:Hide()
    else
        RT.ConfigWin:Show()
        RT.RefreshAnnounceConfig()
    end
end

-- ============================================================================
-- FLOATING ANNOUNCEMENT BAR
-- ============================================================================

local BTN_W = 150
local BTN_H = 20
local BTN_SPACING = 22

function RT.CreateBar()
    if RT.Bar then return RT.Bar end

    local bar = CreateFrame("Frame", "AIPAnnounceBar", UIParent)
    bar:SetSize(BTN_W + 16, 60)
    bar:SetFrameStrata("MEDIUM")
    bar:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    bar:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    bar:SetBackdropBorderColor(0.4, 0.4, 0.4)
    bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", bar.StartMoving)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if AIP.db then AIP.db.floatingBarPos = {point = point, relPoint = relPoint, x = x, y = y} end
    end)

    local pos = AIP.db and AIP.db.floatingBarPos
    bar:ClearAllPoints()
    if pos then bar:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 300, pos.y or 0)
    else bar:SetPoint("CENTER", UIParent, "CENTER", 350, 0) end

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -5)
    title:SetText("|cFFFFD700Announcements|r")
    bar.title = title

    -- Edit (gear) button to open the friendly config
    local edit = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    edit:SetSize(16, 16)
    edit:SetPoint("TOPRIGHT", -6, -4)
    edit:SetText("+")
    edit:SetScript("OnClick", function() RT.ToggleAnnounceConfig() end)
    edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Configure bar buttons"); GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.editBtn = edit

    -- Action row: persistent raid-tool shortcuts beneath the title.
    local function actionBtn(text, w, tip, onClick)
        local b = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
        b:SetSize(w, 18)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine(tip, 1, 1, 1, true); GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end

    local ready = actionBtn("Ready", 48, "Start a ready check", function() RT.StartReadyCheck() end)
    ready:SetPoint("TOPLEFT", bar, "TOPLEFT", 8, -22)
    local buffs = actionBtn("Buffs", 52, "Announce buff assignments - delegates one buff per same-class caster", function() RT.AnnounceBuffDelegation() end)
    buffs:SetPoint("LEFT", ready, "RIGHT", 2, 0)
    local roll = actionBtn("Roll", 44, "Open the Loot Roll window", function() RT.ToggleRollWindow() end)
    roll:SetPoint("LEFT", buffs, "RIGHT", 2, 0)
    bar.actionButtons = {ready, buffs, roll}

    bar.buttons = {}
    RT.Bar = bar
    return bar
end

function RT.RefreshBar()
    if not RT.Bar then return end
    local anns = RT.GetAnnouncements()

    for i, ann in ipairs(anns) do
        local btn = RT.Bar.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, RT.Bar, "UIPanelButtonTemplate")
            btn:SetSize(BTN_W, BTN_H)
            RT.Bar.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOP", RT.Bar, "TOP", 0, -46 - (i - 1) * BTN_SPACING)
        btn:SetText(ann.label or ann.message or "?")
        btn:SetScript("OnClick", function() RT.Send(ann.message, ann.channel or "RAID_WARNING") end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ann.label or "Announcement", 1, 0.82, 0)
            GameTooltip:AddLine(ann.message or "", 1, 1, 1, true)
            GameTooltip:AddLine("-> " .. (ann.channel or "RAID_WARNING"), 0.6, 0.8, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        btn:Show()
    end
    for i = #anns + 1, #RT.Bar.buttons do
        if RT.Bar.buttons[i] then RT.Bar.buttons[i]:Hide() end
    end

    -- 46px reserves the title + action row above the message buttons.
    RT.Bar:SetHeight(math.max(58, 46 + #anns * BTN_SPACING + 6))
    RT.Bar:SetWidth(BTN_W + 16)
end

function RT.UpdateBar()
    local enabled = AIP.db and AIP.db.floatingBarEnabled
    if enabled then
        RT.CreateBar(); RT.RefreshBar(); RT.Bar:Show()
    elseif RT.Bar then
        RT.Bar:Hide()
    end
end

function RT.ToggleBar()
    if AIP.db then
        AIP.db.floatingBarEnabled = not AIP.db.floatingBarEnabled
        RT.UpdateBar()
        AIP.Print("Announcement bar " .. (AIP.db.floatingBarEnabled and "shown" or "hidden"))
    end
end
