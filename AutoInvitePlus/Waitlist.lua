-- AutoInvite Plus - Waitlist Module (v4.1)
-- Manages the player waitlist for future raids

local AIP = AutoInvitePlus

-- ============================================================================
-- DATA STRUCTURE
-- ============================================================================
-- AIP.db.waitlist = {
--     {
--         name = "PlayerName",
--         role = "TANK" | "HEALER" | "DPS",
--         addedTime = timestamp,
--         priority = 1,  -- Lower = higher priority
--         note = "Good tank, bring next time",
--         class = "WARRIOR",
--         gs = 5500,
--     }
-- }
-- ============================================================================

-- Initialize waitlist if needed
local function EnsureWaitlistExists()
    if not AIP.db then return false end
    if not AIP.db.waitlist then
        AIP.db.waitlist = {}
    end
    return true
end

-- Helper: Send waitlist notification message
local function SendWaitlistMessage(playerName, messageTemplate, position)
    -- Validate all inputs
    if not playerName or playerName == "" then
        if AIP.Debug then AIP.Debug("SendWaitlistMessage: No player name") end
        return false
    end
    if not messageTemplate or messageTemplate == "" then
        if AIP.Debug then AIP.Debug("SendWaitlistMessage: No message template") end
        return false
    end
    if not position then
        if AIP.Debug then AIP.Debug("SendWaitlistMessage: No position") end
        return false
    end

    -- Format the message with position
    local msg = messageTemplate
    local posStr = tostring(position)

    -- Try string.format first (for %d pattern)
    local success, formatted = pcall(string.format, messageTemplate, position)
    if success and formatted then
        msg = formatted
    else
        -- Fallback: manual replacement for various patterns
        msg = msg:gsub("%%d", posStr)
        msg = msg:gsub("%%s", posStr)
        msg = msg:gsub("#%%d", "#" .. posStr)
        msg = msg:gsub("#X", "#" .. posStr)
    end

    -- Debug output (always show to help diagnose)
    if AIP.Debug then
        AIP.Debug("SendWaitlistMessage: Sending to " .. playerName .. ": " .. msg)
    end

    -- Send the whisper
    local whisperSuccess, whisperErr = pcall(SendChatMessage, msg, "WHISPER", nil, playerName)
    if not whisperSuccess then
        AIP.Print("|cFFFF0000Failed to send waitlist whisper:|r " .. (whisperErr or "unknown error"))
        return false
    end

    return true
end

-- Helper: Notify player of position change
local function NotifyPositionChange(playerName, newPosition)
    if not AIP.db then
        AIP.Debug("NotifyPositionChange: db not initialized")
        return
    end

    local template = AIP.db.responseWaitlistPosition
    if not template or template == "" then
        AIP.Debug("NotifyPositionChange: No position change template configured")
        return
    end

    AIP.Debug("NotifyPositionChange: Notifying " .. tostring(playerName) .. " of new position " .. tostring(newPosition))
    SendWaitlistMessage(playerName, template, newPosition)
end

-- ============================================================================
-- CORE FUNCTIONS
-- ============================================================================

-- Check if player is on waitlist
function AIP.IsOnWaitlist(name)
    if not AIP.db or not AIP.db.waitlist or not name then return false end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.waitlist) do
        if entry.name:lower() == lowerName then
            return true, entry, i
        end
    end
    return false, nil, nil
end

-- Add player to waitlist
function AIP.AddToWaitlist(name, role, note, class, gs)
    if not EnsureWaitlistExists() then return false end
    if not name or name:trim() == "" then
        AIP.Print("Please specify a player name")
        return false
    end

    name = name:trim()

    -- Check if already on waitlist
    if AIP.IsOnWaitlist(name) then
        AIP.Print(name .. " is already on the waitlist")
        return false
    end

    -- Capitalize name properly
    local properName = name:sub(1,1):upper() .. name:sub(2):lower()

    -- Determine priority (lower = higher priority)
    local priority = #AIP.db.waitlist + 1

    table.insert(AIP.db.waitlist, {
        name = properName,
        role = role or "DPS",
        addedTime = time(),
        priority = priority,
        note = note or "",
        class = class,
        gs = gs,
    })

    AIP.Print("Added " .. properName .. " to waitlist (position #" .. priority .. ")")

    -- Send automatic notification whisper
    local template = AIP.db.responseWaitlist
    if template and template ~= "" then
        AIP.Debug("AddToWaitlist: Sending waitlist notification to " .. properName)
        local sent = SendWaitlistMessage(properName, template, priority)
        if sent then
            AIP.Debug("AddToWaitlist: Notification sent successfully")
        end
    else
        AIP.Debug("AddToWaitlist: No waitlist response template configured")
    end

    -- Update UI if open
    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end

    return true
end

-- Update waitlist entry
function AIP.UpdateWaitlistEntry(name, role, note, priority)
    if not AIP.db or not AIP.db.waitlist or not name then return false end

    local _, entry, index = AIP.IsOnWaitlist(name)
    if not entry then
        AIP.Print(name .. " is not on the waitlist")
        return false
    end

    if role then entry.role = role end
    if note then entry.note = note end
    if priority then
        -- Reorder waitlist based on new priority
        local newPriority = math.max(1, math.min(#AIP.db.waitlist, priority))
        if newPriority ~= index then
            -- Track affected players before reordering
            local affectedPlayers = {}
            local oldIndex = index

            table.remove(AIP.db.waitlist, index)
            table.insert(AIP.db.waitlist, newPriority, entry)

            -- Update all priorities and track who changed
            for i, e in ipairs(AIP.db.waitlist) do
                if e.priority ~= i then
                    affectedPlayers[e.name] = i
                end
                e.priority = i
            end

            -- Notify all affected players of their new positions
            for playerName, newPos in pairs(affectedPlayers) do
                NotifyPositionChange(playerName, newPos)
            end
        end
    end

    AIP.Print("Updated waitlist entry for " .. entry.name)

    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end

    return true
end

-- Remove player from waitlist
function AIP.RemoveFromWaitlist(name)
    if not AIP.db or not AIP.db.waitlist or not name then return false end

    local lowerName = name:lower():trim()

    for i, entry in ipairs(AIP.db.waitlist) do
        if entry.name:lower() == lowerName then
            local removedName = entry.name
            table.remove(AIP.db.waitlist, i)

            -- Update priorities
            for j, e in ipairs(AIP.db.waitlist) do
                e.priority = j
            end

            AIP.Print("Removed " .. removedName .. " from waitlist")

            if AIP.UpdateWaitlistUI then
                AIP.UpdateWaitlistUI()
            end

            return true
        end
    end

    AIP.Print(name .. " was not found on waitlist")
    return false
end

-- Move player up in waitlist
function AIP.MoveWaitlistUp(name)
    if not AIP.db or not AIP.db.waitlist or not name then return false end

    local _, entry, index = AIP.IsOnWaitlist(name)
    if not entry or index <= 1 then return false end

    -- Get the entry being swapped down
    local otherEntry = AIP.db.waitlist[index - 1]

    -- Swap with previous entry
    AIP.db.waitlist[index], AIP.db.waitlist[index - 1] = AIP.db.waitlist[index - 1], AIP.db.waitlist[index]

    -- Update priorities
    for i, e in ipairs(AIP.db.waitlist) do
        e.priority = i
    end

    -- Notify both players of their new positions
    NotifyPositionChange(entry.name, index - 1)
    if otherEntry then
        NotifyPositionChange(otherEntry.name, index)
    end

    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end

    return true
end

-- Move player down in waitlist
function AIP.MoveWaitlistDown(name)
    if not AIP.db or not AIP.db.waitlist or not name then return false end

    local _, entry, index = AIP.IsOnWaitlist(name)
    if not entry or index >= #AIP.db.waitlist then return false end

    -- Get the entry being swapped up
    local otherEntry = AIP.db.waitlist[index + 1]

    -- Swap with next entry
    AIP.db.waitlist[index], AIP.db.waitlist[index + 1] = AIP.db.waitlist[index + 1], AIP.db.waitlist[index]

    -- Update priorities
    for i, e in ipairs(AIP.db.waitlist) do
        e.priority = i
    end

    -- Notify both players of their new positions
    NotifyPositionChange(entry.name, index + 1)
    if otherEntry then
        NotifyPositionChange(otherEntry.name, index)
    end

    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end

    return true
end

-- Clear entire waitlist
function AIP.ClearWaitlist()
    if not EnsureWaitlistExists() then return end
    AIP.db.waitlist = {}
    AIP.Print("Waitlist cleared")

    if AIP.UpdateWaitlistUI then
        AIP.UpdateWaitlistUI()
    end
end

-- Get waitlist count
function AIP.GetWaitlistCount()
    if not AIP.db or not AIP.db.waitlist then return 0 end
    return #AIP.db.waitlist
end

-- Get waitlist entries (optionally filtered by role)
function AIP.GetWaitlistEntries(roleFilter)
    local entries = {}
    if not AIP.db or not AIP.db.waitlist then return entries end

    for _, entry in ipairs(AIP.db.waitlist) do
        if not roleFilter or roleFilter == "ALL" or entry.role == roleFilter then
            table.insert(entries, entry)
        end
    end

    return entries
end

-- Invite player from waitlist (and remove from waitlist)
function AIP.InviteFromWaitlist(name)
    local onWaitlist, entry = AIP.IsOnWaitlist(name)
    if not onWaitlist then
        AIP.Print(name .. " is not on the waitlist")
        return false
    end

    -- Attempt to invite
    if AIP.InvitePlayer and AIP.InvitePlayer(entry.name) then
        -- Remove from waitlist after successful invite
        AIP.RemoveFromWaitlist(entry.name)
        return true
    end

    return false
end

-- Invite next player from waitlist by role
function AIP.InviteNextFromWaitlist(role)
    if not AIP.db or not AIP.db.waitlist or #AIP.db.waitlist == 0 then
        AIP.Print("Waitlist is empty")
        return false
    end

    for _, entry in ipairs(AIP.db.waitlist) do
        if not role or role == "ALL" or entry.role == role then
            return AIP.InviteFromWaitlist(entry.name)
        end
    end

    AIP.Print("No players found on waitlist" .. (role and (" for role: " .. role) or ""))
    return false
end

-- Move player from queue to waitlist
function AIP.MoveQueueToWaitlist(name, role, note)
    if not name then return false end

    -- Remove from queue first
    if AIP.RemoveFromQueue then
        AIP.RemoveFromQueue(name)
    end

    -- Add to waitlist
    return AIP.AddToWaitlist(name, role, note)
end

-- Get waitlist position for a player
function AIP.GetWaitlistPosition(name)
    if not AIP.db or not AIP.db.waitlist or not name then return nil end

    local lowerName = name:lower()
    for i, entry in ipairs(AIP.db.waitlist) do
        if entry.name:lower() == lowerName then
            return i
        end
    end

    return nil
end

-- ============================================================================
-- WAITLIST UI
-- ============================================================================
local waitlistFrame = nil
local waitlistButtons = {}
local WAITLIST_BUTTONS_SHOWN = 10

local function CreateWaitlistUI()
    if waitlistFrame then return waitlistFrame end

    -- Main frame
    local frame = CreateFrame("Frame", "AIPWaitlistFrame", UIParent)
    frame:SetSize(500, 400)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()

    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 }
    })

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Waitlist")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Add player section
    local addLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addLabel:SetPoint("TOPLEFT", 15, -40)
    addLabel:SetText("Add:")

    local nameInput = CreateFrame("EditBox", "AIPWaitlistName", frame, "InputBoxTemplate")
    nameInput:SetSize(100, 20)
    nameInput:SetPoint("LEFT", addLabel, "RIGHT", 5, 0)
    nameInput:SetAutoFocus(false)
    frame.nameInput = nameInput

    local roleDropdown = CreateFrame("Frame", "AIPWaitlistRole", frame, "UIDropDownMenuTemplate")
    roleDropdown:SetPoint("LEFT", nameInput, "RIGHT", 0, -3)
    UIDropDownMenu_SetWidth(roleDropdown, 70)
    UIDropDownMenu_SetText(roleDropdown, "DPS")
    frame.roleDropdown = roleDropdown
    frame.selectedRole = "DPS"

    local function RoleDropdown_Initialize()
        local roles = {"TANK", "HEALER", "DPS"}
        for _, role in ipairs(roles) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = role
            info.value = role
            info.func = function(self)
                frame.selectedRole = self.value
                UIDropDownMenu_SetText(roleDropdown, self.value)
            end
            info.checked = (frame.selectedRole == role)
            UIDropDownMenu_AddButton(info)
        end
    end
    UIDropDownMenu_Initialize(roleDropdown, RoleDropdown_Initialize)

    local noteInput = CreateFrame("EditBox", "AIPWaitlistNote", frame, "InputBoxTemplate")
    noteInput:SetSize(120, 20)
    noteInput:SetPoint("LEFT", roleDropdown, "RIGHT", 0, 3)
    noteInput:SetAutoFocus(false)
    frame.noteInput = noteInput

    local notePlaceholder = noteInput:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    notePlaceholder:SetPoint("LEFT", 5, 0)
    notePlaceholder:SetText("Note...")
    notePlaceholder:SetTextColor(0.5, 0.5, 0.5)
    noteInput.placeholder = notePlaceholder
    noteInput:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)

    local addBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    addBtn:SetSize(50, 22)
    addBtn:SetPoint("LEFT", noteInput, "RIGHT", 5, 0)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", function()
        local name = nameInput:GetText()
        local note = noteInput:GetText()
        if note == "" then note = nil end
        AIP.AddToWaitlist(name, frame.selectedRole, note)
        nameInput:SetText("")
        noteInput:SetText("")
        nameInput:ClearFocus()
        noteInput:ClearFocus()
    end)

    nameInput:SetScript("OnEnterPressed", function(self)
        local name = self:GetText()
        local note = noteInput:GetText()
        if note == "" then note = nil end
        AIP.AddToWaitlist(name, frame.selectedRole, note)
        self:SetText("")
        noteInput:SetText("")
        self:ClearFocus()
    end)
    nameInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    noteInput:SetScript("OnEnterPressed", function(self)
        local name = nameInput:GetText()
        local note = self:GetText()
        if note == "" then note = nil end
        AIP.AddToWaitlist(name, frame.selectedRole, note)
        nameInput:SetText("")
        self:SetText("")
        nameInput:ClearFocus()
        self:ClearFocus()
    end)
    noteInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)

    -- Column headers
    local colNum = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNum:SetPoint("TOPLEFT", 20, -70)
    colNum:SetText("#")
    colNum:SetTextColor(1, 0.82, 0)

    local colName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colName:SetPoint("TOPLEFT", 40, -70)
    colName:SetText("Name")
    colName:SetTextColor(1, 0.82, 0)

    local colRole = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colRole:SetPoint("TOPLEFT", 130, -70)
    colRole:SetText("Role")
    colRole:SetTextColor(1, 0.82, 0)

    local colNote = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNote:SetPoint("TOPLEFT", 200, -70)
    colNote:SetText("Note")
    colNote:SetTextColor(1, 0.82, 0)

    -- Scrollframe for list
    local scrollFrame = CreateFrame("ScrollFrame", "AIPWaitlistScrollFrame", frame, "FauxScrollFrameTemplate")
    scrollFrame:SetSize(430, 250)
    scrollFrame:SetPoint("TOPLEFT", 15, -85)
    scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, 25, AIP.UpdateWaitlistUI)
    end)

    -- Create list buttons
    for i = 1, WAITLIST_BUTTONS_SHOWN do
        local btn = CreateFrame("Frame", "AIPWaitlistButton"..i, frame)
        btn:SetSize(420, 25)
        btn:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 5, -((i-1) * 25))

        -- Highlight
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        highlight:SetBlendMode("ADD")

        -- Position number
        local numText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        numText:SetPoint("LEFT", 0, 0)
        numText:SetWidth(20)
        numText:SetJustifyH("CENTER")
        btn.numText = numText

        -- Name
        local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", 25, 0)
        nameText:SetWidth(85)
        nameText:SetJustifyH("LEFT")
        btn.nameText = nameText

        -- Role
        local roleText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        roleText:SetPoint("LEFT", 115, 0)
        roleText:SetWidth(60)
        roleText:SetJustifyH("LEFT")
        btn.roleText = roleText

        -- Note
        local noteText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteText:SetPoint("LEFT", 185, 0)
        noteText:SetWidth(120)
        noteText:SetJustifyH("LEFT")
        noteText:SetTextColor(0.7, 0.7, 0.7)
        btn.noteText = noteText

        -- Up button
        local upBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        upBtn:SetSize(20, 18)
        upBtn:SetPoint("LEFT", 310, 0)
        upBtn:SetText("^")
        upBtn.index = i
        upBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPWaitlistScrollFrame"])
            local entry = AIP.db.waitlist[offset + self.index]
            if entry then
                AIP.MoveWaitlistUp(entry.name)
            end
        end)
        btn.upBtn = upBtn

        -- Down button
        local downBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        downBtn:SetSize(20, 18)
        downBtn:SetPoint("LEFT", 332, 0)
        downBtn:SetText("v")
        downBtn.index = i
        downBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPWaitlistScrollFrame"])
            local entry = AIP.db.waitlist[offset + self.index]
            if entry then
                AIP.MoveWaitlistDown(entry.name)
            end
        end)
        btn.downBtn = downBtn

        -- Invite button
        local invBtn = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
        invBtn:SetSize(35, 18)
        invBtn:SetPoint("LEFT", 355, 0)
        invBtn:SetText("Inv")
        invBtn.index = i
        invBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPWaitlistScrollFrame"])
            local entry = AIP.db.waitlist[offset + self.index]
            if entry then
                AIP.InviteFromWaitlist(entry.name)
            end
        end)
        btn.invBtn = invBtn

        -- Remove button
        local remBtn = CreateFrame("Button", nil, btn, "UIPanelCloseButton")
        remBtn:SetSize(20, 20)
        remBtn:SetPoint("LEFT", 393, 0)
        remBtn.index = i
        remBtn:SetScript("OnClick", function(self)
            local offset = FauxScrollFrame_GetOffset(_G["AIPWaitlistScrollFrame"])
            local entry = AIP.db.waitlist[offset + self.index]
            if entry then
                AIP.RemoveFromWaitlist(entry.name)
            end
        end)
        btn.remBtn = remBtn

        btn:Hide()
        waitlistButtons[i] = btn
    end

    -- Bottom buttons
    local inviteAllBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    inviteAllBtn:SetSize(100, 22)
    inviteAllBtn:SetPoint("BOTTOMLEFT", 20, 15)
    inviteAllBtn:SetText("Invite Next")
    inviteAllBtn:SetScript("OnClick", function()
        AIP.InviteNextFromWaitlist()
    end)

    local clearBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 22)
    clearBtn:SetPoint("LEFT", inviteAllBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Clear")
    clearBtn:SetScript("OnClick", function()
        StaticPopupDialogs["AIP_CLEAR_WAITLIST"] = {
            text = "Clear entire waitlist?",
            button1 = "Yes",
            button2 = "No",
            OnAccept = function()
                AIP.ClearWaitlist()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
        }
        StaticPopup_Show("AIP_CLEAR_WAITLIST")
    end)

    -- Count display
    local countText = frame:CreateFontString("AIPWaitlistCount", "OVERLAY", "GameFontNormal")
    countText:SetPoint("BOTTOMRIGHT", -25, 20)
    countText:SetText("0 players")
    frame.countText = countText

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    waitlistFrame = frame
    return frame
end

-- Update the waitlist UI
function AIP.UpdateWaitlistUI()
    if not waitlistFrame or not waitlistFrame:IsVisible() then return end

    local entries = AIP.db.waitlist or {}
    local numEntries = #entries

    FauxScrollFrame_Update(_G["AIPWaitlistScrollFrame"], numEntries, WAITLIST_BUTTONS_SHOWN, 25)

    local offset = FauxScrollFrame_GetOffset(_G["AIPWaitlistScrollFrame"])

    for i = 1, WAITLIST_BUTTONS_SHOWN do
        local index = offset + i
        local btn = waitlistButtons[i]
        btn.upBtn.index = i
        btn.downBtn.index = i
        btn.invBtn.index = i
        btn.remBtn.index = i

        if index <= numEntries then
            local entry = entries[index]
            btn.numText:SetText(index)
            btn.nameText:SetText(entry.name)

            -- Color role text
            local roleColor = {
                TANK = {0.5, 0.5, 1},
                HEALER = {0.5, 1, 0.5},
                DPS = {1, 0.5, 0.5},
            }
            local color = roleColor[entry.role] or {1, 1, 1}
            btn.roleText:SetText(entry.role)
            btn.roleText:SetTextColor(color[1], color[2], color[3])

            btn.noteText:SetText((entry.note or ""):sub(1, 20))
            btn:Show()
        else
            btn:Hide()
        end
    end

    waitlistFrame.countText:SetText(numEntries .. " players")
end

-- Toggle waitlist UI
function AIP.ToggleWaitlistUI()
    local frame = CreateWaitlistUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.UpdateWaitlistUI()
    end
end
