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
    -- Allow shift-clicking items/quests/etc. into these fields.
    if AIP.UI and AIP.UI.MakeEditBoxLinkable then AIP.UI.MakeEditBoxLinkable(eb) end
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

    -- Personal-roll shortcut: rolls 1-100 for YOU, exactly like typing /roll.
    local myRollBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    myRollBtn:SetSize(90, 22)
    myRollBtn:SetPoint("TOPLEFT", 14, -12)
    myRollBtn:SetText("Roll 1-100")
    myRollBtn:SetScript("OnClick", function()
        if RandomRoll then RandomRoll(1, 100) else DEFAULT_CHAT_FRAME.editBox:SetText("/roll") end
    end)
    myRollBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Roll 1-100")
        GameTooltip:AddLine("Same as typing /roll - counts toward the active roll.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    myRollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    -- Height fits: header(72) + rows + footer(scroll hint + buttons + margins).
    win:SetSize(560, 72 + (AC_ROWS * 26 + 8) + 64)
    win:SetPoint("CENTER", 120, 0)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    if AIP.CentralGUI and AIP.CentralGUI.StylePopup then
        AIP.CentralGUI.StylePopup(win)   -- theme-matched: dark navy, solid backing, gold title strip
    else
        win:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = {left = 5, right = 5, top = 5, bottom = 5},
        })
        win:SetBackdropColor(0.05, 0.055, 0.085, 1)
    end
    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", win.StopMovingOrSizing)
    win:SetClampedToScreen(true); win:Hide()

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText("|cFFFFD700Bar Buttons / Raid-Warning Templates|r")
    local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local help = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOP", title, "BOTTOM", 0, -4)
    help:SetWidth(516)            -- constrain so it wraps inside the window
    help:SetJustifyH("CENTER")
    help:SetText("Each row is a raid-warning template and a floating-bar button. Click a channel to cycle it.")

    -- Column headers
    local hLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hLabel:SetPoint("TOPLEFT", 24, -56); hLabel:SetText("|cFFFFD700Name|r")
    local hMsg = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hMsg:SetPoint("TOPLEFT", 150, -56); hMsg:SetText("|cFFFFD700Message|r")
    local hChan = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hChan:SetPoint("TOPLEFT", 400, -56); hChan:SetText("|cFFFFD700Channel|r")

    local listBg = MakeBox(win, 516, AC_ROWS * 26 + 8)
    listBg:SetPoint("TOPLEFT", 22, -72)

    -- Visible draggable scrollbar (works alongside the mouse wheel).
    local sb = CreateFrame("Slider", nil, listBg)
    sb:SetOrientation("VERTICAL")
    sb:SetWidth(16)
    sb:SetPoint("TOPRIGHT", listBg, "TOPRIGHT", -5, -10)
    sb:SetPoint("BOTTOMRIGHT", listBg, "BOTTOMRIGHT", -5, 10)
    sb:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = {left = 3, right = 3, top = 6, bottom = 6},
    })
    sb:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = sb:GetThumbTexture()
    if thumb then thumb:SetSize(18, 24) end
    sb:SetMinMaxValues(0, 0)
    sb:SetValueStep(1)
    sb:SetValue(0)
    win.acScrollBar = sb
    sb:SetScript("OnValueChanged", function(self, value)
        local v = math.floor(value + 0.5)
        if v ~= (win.acOffset or 0) then
            win.acOffset = v
            RT.RefreshAnnounceConfig()
        end
    end)

    win.acRows = {}
    for i = 1, AC_ROWS do
        local y = -6 - (i - 1) * 26
        local row = CreateFrame("Frame", nil, listBg)
        row:SetPoint("TOPLEFT", 6, y); row:SetPoint("RIGHT", listBg, "RIGHT", -26, 0)
        row:SetHeight(24)

        local labelBox = MakeInput(row, 110, 22)
        labelBox:SetPoint("LEFT", 6, 0)
        labelBox:SetScript("OnTextChanged", function(self)
            if row.entry then row.entry.name = self:GetText() end
        end)
        row.labelBox = labelBox

        local msgBox = MakeInput(row, 200, 22)
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

    -- Mouse-wheel scrolling through the (now unbounded) template list.
    win.acOffset = 0
    win:EnableMouseWheel(true)
    win:SetScript("OnMouseWheel", function(self, delta)
        local total = #RT.GetAnnouncements()
        local maxOff = math.max(0, total - AC_ROWS)
        self.acOffset = math.min(maxOff, math.max(0, (self.acOffset or 0) - delta))
        RT.RefreshAnnounceConfig()
    end)

    -- Footer anchored to the LIST bottom so it always sits below the rows,
    -- never overlapping them regardless of window/row count.
    local scrollHint = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scrollHint:SetPoint("TOP", listBg, "BOTTOM", 0, -6)
    scrollHint:SetTextColor(0.6, 0.6, 0.6)
    scrollHint:Hide()
    win.scrollHint = scrollHint

    local addBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    addBtn:SetSize(140, 24)
    addBtn:SetPoint("TOPLEFT", listBg, "BOTTOMLEFT", 0, -26)
    addBtn:SetText("+ Add Template")
    addBtn:SetScript("OnClick", function()
        local list = RT.GetAnnouncements()
        table.insert(list, { name = "New Warning", message = "Type your message", channel = "RAID_WARNING" })
        win.acOffset = math.max(0, #list - AC_ROWS)  -- scroll to reveal the new row
        RT.RefreshAnnounceConfig()
        if RT.RefreshBar then RT.RefreshBar() end
    end)

    local doneBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    doneBtn:SetSize(120, 24)
    doneBtn:SetPoint("TOPRIGHT", listBg, "BOTTOMRIGHT", 0, -26)
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
    local total = #list
    local maxOff = math.max(0, total - AC_ROWS)
    local offset = math.min(maxOff, math.max(0, win.acOffset or 0))
    win.acOffset = offset

    -- Sync the visible scrollbar (guarding against its OnValueChanged recursing).
    if win.acScrollBar then
        win.acScrollBar:SetMinMaxValues(0, maxOff)
        win.acScrollBar:SetValue(offset)
        if maxOff > 0 then win.acScrollBar:Show() else win.acScrollBar:Hide() end
    end

    for i = 1, AC_ROWS do
        local row = win.acRows[i]
        local entry = list[offset + i]
        if entry then
            row.entry = entry
            row.dbIndex = offset + i
            row.labelBox:SetText(entry.name or entry.label or "")
            row.msgBox:SetText(entry.message or "")
            -- Reset cursor to the start so the box shows the BEGINNING of long
            -- text (SetText leaves the cursor at the end, scrolling it off-view).
            row.labelBox:SetCursorPosition(0)
            row.msgBox:SetCursorPosition(0)
            row.chanBtn:SetText(entry.channel or "RAID_WARNING")
            row:Show()
        else
            row.entry = nil; row.dbIndex = nil; row:Hide()
        end
    end

    if win.scrollHint then
        if total > AC_ROWS then
            win.scrollHint:SetText(string.format("Showing %d-%d of %d  -  scroll for more",
                offset + 1, math.min(offset + AC_ROWS, total), total))
            win.scrollHint:Show()
        else
            win.scrollHint:Hide()
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
local BAR_VISIBLE = 6   -- message buttons shown at once; the rest scroll (wheel)

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
    bar:SetBackdropColor(0.045, 0.05, 0.072, 0.96)
    bar:SetBackdropBorderColor(0.34, 0.37, 0.46)
    -- Solid backing + gold-accented header strip (theme-matched, like the window).
    local barBg = bar:CreateTexture(nil, "BACKGROUND", nil, -8)
    barBg:SetPoint("TOPLEFT", 4, -4); barBg:SetPoint("BOTTOMRIGHT", -4, 4)
    barBg:SetTexture(0.045, 0.05, 0.072, 1)
    local hdr = bar:CreateTexture(nil, "BORDER")
    hdr:SetPoint("TOPLEFT", 5, -5); hdr:SetPoint("TOPRIGHT", -5, -5); hdr:SetHeight(18)
    hdr:SetTexture(0.11, 0.12, 0.18, 0.95)
    local hdrDiv = bar:CreateTexture(nil, "ARTWORK")
    hdrDiv:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0); hdrDiv:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    hdrDiv:SetHeight(1); hdrDiv:SetTexture(1, 0.82, 0, 0.4)
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

    -- Close button - hides the bar (and remembers it's off across reloads).
    local closeBtn = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -6, -4)
    closeBtn:SetText("X")
    closeBtn:SetScript("OnClick", function() RT.ToggleBar() end)
    closeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Close the bar"); GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.closeBtn = closeBtn

    -- Edit (+) button to open the friendly config (left of the close button)
    local edit = CreateFrame("Button", nil, bar, "UIPanelButtonTemplate")
    edit:SetSize(16, 16)
    edit:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
    edit:SetText("+")
    edit:SetScript("OnClick", function() RT.ToggleAnnounceConfig() end)
    edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Configure bar buttons (wired to raid-warning templates)"); GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    bar.editBtn = edit

    -- Fixed-size bar: the message buttons scroll with the mouse wheel.
    bar.scrollOffset = 0
    bar:EnableMouseWheel(true)
    bar:SetScript("OnMouseWheel", function(self, delta)
        local total = #RT.GetAnnouncements()
        local maxOff = math.max(0, total - BAR_VISIBLE)
        self.scrollOffset = math.min(maxOff, math.max(0, (self.scrollOffset or 0) - delta))
        RT.RefreshBar()
    end)

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

    -- Scroll position indicator at the bottom (shown only when the list overflows)
    local scrollInfo = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scrollInfo:SetPoint("BOTTOM", 0, 5)
    scrollInfo:Hide()
    bar.scrollInfo = scrollInfo

    bar.buttons = {}
    RT.Bar = bar
    return bar
end

function RT.RefreshBar()
    if not RT.Bar then return end
    local anns = RT.GetAnnouncements()
    local total = #anns

    -- Clamp the scroll window to the current list.
    local maxOff = math.max(0, total - BAR_VISIBLE)
    local offset = math.min(maxOff, math.max(0, RT.Bar.scrollOffset or 0))
    RT.Bar.scrollOffset = offset

    -- Render only the visible window into a fixed pool of BAR_VISIBLE buttons.
    for i = 1, BAR_VISIBLE do
        local ann = anns[offset + i]
        local btn = RT.Bar.buttons[i]
        if not btn then
            -- Flat list row (not a chunky red button): dark fill, gold left-accent,
            -- gold hover, left-aligned label - reads as a clean announcement list.
            btn = CreateFrame("Button", nil, RT.Bar)
            btn:SetSize(BTN_W, BTN_H)
            btn:SetPoint("TOP", RT.Bar, "TOP", 0, -46 - (i - 1) * BTN_SPACING)
            local bg = btn:CreateTexture(nil, "BACKGROUND"); bg:SetAllPoints(); bg:SetTexture(0.11, 0.12, 0.17, 0.92)
            local accent = btn:CreateTexture(nil, "ARTWORK"); accent:SetPoint("TOPLEFT"); accent:SetPoint("BOTTOMLEFT"); accent:SetWidth(2); accent:SetTexture(1, 0.82, 0, 0.5)
            local hl = btn:CreateTexture(nil, "HIGHLIGHT"); hl:SetAllPoints(); hl:SetTexture(1, 0.82, 0, 0.16)
            local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            txt:SetPoint("LEFT", 8, 0); txt:SetPoint("RIGHT", -6, 0); txt:SetJustifyH("LEFT"); txt:SetTextColor(0.92, 0.92, 0.96)
            btn.txt = txt
            RT.Bar.buttons[i] = btn
        end
        if ann then
            btn.txt:SetText(ann.name or ann.label or ann.message or "?")
            btn:SetScript("OnClick", function() RT.Send(ann.message, ann.channel or "RAID_WARNING") end)
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ann.name or ann.label or "Announcement", 1, 0.82, 0)
                GameTooltip:AddLine(ann.message or "", 1, 1, 1, true)
                GameTooltip:AddLine("-> " .. (ann.channel or "RAID_WARNING"), 0.6, 0.8, 1)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
            btn:Show()
        else
            btn:Hide()
        end
    end

    -- Compact scroll position shown under the row when the list overflows.
    if RT.Bar.scrollInfo then
        if total > BAR_VISIBLE then
            RT.Bar.scrollInfo:SetText(string.format("|cFF888888%d-%d / %d  (scroll)|r",
                offset + 1, math.min(offset + BAR_VISIBLE, total), total))
            RT.Bar.scrollInfo:Show()
        else
            RT.Bar.scrollInfo:Hide()
        end
    end

    -- Fixed height: always sized for BAR_VISIBLE rows regardless of list length.
    RT.Bar:SetHeight(46 + BAR_VISIBLE * BTN_SPACING + 14)
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
