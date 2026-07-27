-- AutoInvite Plus - Central GUI Add-Player Popups
-- Split from CentralGUI.lua: standalone add-to-queue / add-to-waitlist popups

local AIP = AutoInvitePlus
if not AIP then
    DEFAULT_CHAT_FRAME:AddMessage("|cFFFF0000[AIP Error]|r CentralGUIPopups: AutoInvitePlus namespace not found!")
    return
end

AIP.CentralGUI = AIP.CentralGUI or {}
local GUI = AIP.CentralGUI

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
    AIP.UI.MakeDraggable(popup)
    popup:SetClampedToScreen(true)
    GUI.StylePopup(popup)

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

        -- Route through the canonical AIP.AddToQueue: it already handles the
        -- dedupe check, name normalization, GS lookup, favorite/guild priority
        -- insertion, the reject-mode auto-decline whisper, and the queue
        -- position notification whisper - a hand-rolled table.insert here
        -- skipped all of that and always left GS/class blank.
        if AIP.AddToQueue and AIP.AddToQueue(name, note) then
            -- Update UI
            local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
            if container then
                GUI.UpdateQueuePanel(container)
            end
            popup:Hide()
        end
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
    AIP.UI.MakeDraggable(popup)
    popup:SetClampedToScreen(true)
    GUI.StylePopup(popup)

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

        -- Route through the canonical AIP.AddToWaitlist: it already handles
        -- the dedupe check, name normalization, blacklist tagging, and the
        -- configured notification whisper - a hand-rolled table.insert here
        -- skipped all of that.
        if AIP.AddToWaitlist and AIP.AddToWaitlist(name, role, note) then
            -- Update the waitlist panel
            local container = GUI.Frame and GUI.Frame.tabContents and GUI.Frame.tabContents["lfm"]
            if container then
                GUI.UpdateQueuePanel(container)
            end
            popup:Hide()
        end
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
