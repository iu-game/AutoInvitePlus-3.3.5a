-- AutoInvite Plus - Promote Module
-- Handles automatic raid assist promotion via whisper

local AIP = AutoInvitePlus

-- Handle promote request from whisper
-- Usage: player whispers "!promote <key>"
function AIP.HandlePromote(author, key)
    if not AIP.db.promoteEnabled then
        AIP.Debug("Promote system disabled")
        return
    end

    if not author or author == "" then return end

    -- Check if we're raid leader
    if not IsRaidLeader() then
        AIP.Debug("Not raid leader, can't promote")
        return
    end

    -- Check blacklist
    if AIP.IsBlacklisted and AIP.IsBlacklisted(author) then
        AIP.Debug(author .. " is blacklisted for promote")
        return
    end

    -- Check if key matches
    local expectedKey = (AIP.db.promoteKey or ""):trim():lower()
    local providedKey = (key or ""):trim():lower()

    if expectedKey == "" or providedKey == expectedKey then
        if AIP.db.promoteAutoAssist then
            -- Automatically promote to assistant
            PromoteToAssistant(author)
            AIP.Print("Promoted " .. author .. " to raid assistant")
            SendChatMessage("[AutoInvite+] You have been promoted to assistant.", "WHISPER", nil, author)
        else
            -- Just notify the leader
            AIP.Print(author .. " is requesting raid assist (key: " .. (key or "none") .. ")")
        end
    else
        AIP.Debug("Invalid promote key from " .. author .. ": " .. (key or "none"))
        SendChatMessage("[AutoInvite+] Invalid promotion key.", "WHISPER", nil, author)
    end
end

-- Promote UI
local promoteFrame = nil

local function CreatePromoteUI()
    if promoteFrame then return promoteFrame end

    -- Main frame
    local frame = CreateFrame("Frame", "AIPPromoteFrame", UIParent)
    frame:SetSize(300, 200)
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
    title:SetText("Promote Settings")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Enable checkbox
    local enableCheck = CreateFrame("CheckButton", "AIPPromoteEnable", frame, "UICheckButtonTemplate")
    enableCheck:SetPoint("TOPLEFT", 20, -50)
    enableCheck:SetScript("OnClick", function(self)
        AIP.db.promoteEnabled = self:GetChecked()
    end)

    local enableLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    enableLabel:SetPoint("LEFT", enableCheck, "RIGHT", 5, 0)
    enableLabel:SetText("Enable Promote System")

    -- Instructions
    local instrLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    instrLabel:SetPoint("TOPLEFT", 25, -80)
    instrLabel:SetWidth(250)
    instrLabel:SetJustifyH("LEFT")
    instrLabel:SetText("Players can whisper you with:\n|cFFFFFF00!promote <key>|r\nto request raid assistant.")
    instrLabel:SetTextColor(0.8, 0.8, 0.8)

    -- Key input
    local keyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyLabel:SetPoint("TOPLEFT", 25, -120)
    keyLabel:SetText("Promotion Key:")

    local keyInput = CreateFrame("EditBox", "AIPPromoteKeyInput", frame, "InputBoxTemplate")
    keyInput:SetSize(150, 20)
    keyInput:SetPoint("LEFT", keyLabel, "RIGHT", 10, 0)
    keyInput:SetAutoFocus(false)
    keyInput:SetScript("OnEnterPressed", function(self)
        AIP.db.promoteKey = self:GetText():trim()
        self:ClearFocus()
        AIP.Print("Promote key set to: " .. AIP.db.promoteKey)
    end)
    keyInput:SetScript("OnEscapePressed", function(self)
        self:SetText(AIP.db.promoteKey or "")
        self:ClearFocus()
    end)
    frame.keyInput = keyInput

    -- Auto-assist radio button
    local autoAssistCheck = CreateFrame("CheckButton", "AIPPromoteAutoAssist", frame, "UICheckButtonTemplate")
    autoAssistCheck:SetPoint("TOPLEFT", 20, -150)
    autoAssistCheck:SetScript("OnClick", function(self)
        AIP.db.promoteAutoAssist = self:GetChecked()
        _G["AIPPromoteNotifyOnly"]:SetChecked(not self:GetChecked())
    end)

    local autoAssistLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    autoAssistLabel:SetPoint("LEFT", autoAssistCheck, "RIGHT", 5, 0)
    autoAssistLabel:SetText("Auto-promote to assistant")

    -- Notify only radio button
    local notifyCheck = CreateFrame("CheckButton", "AIPPromoteNotifyOnly", frame, "UICheckButtonTemplate")
    notifyCheck:SetPoint("TOPLEFT", 20, -175)
    notifyCheck:SetScript("OnClick", function(self)
        AIP.db.promoteAutoAssist = not self:GetChecked()
        _G["AIPPromoteAutoAssist"]:SetChecked(not self:GetChecked())
    end)

    local notifyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    notifyLabel:SetPoint("LEFT", notifyCheck, "RIGHT", 5, 0)
    notifyLabel:SetText("Notify me only (manual promote)")

    -- Update function
    frame.Update = function()
        enableCheck:SetChecked(AIP.db.promoteEnabled)
        keyInput:SetText(AIP.db.promoteKey or "")
        autoAssistCheck:SetChecked(AIP.db.promoteAutoAssist)
        notifyCheck:SetChecked(not AIP.db.promoteAutoAssist)
    end

    -- Make closeable with Escape
    tinsert(UISpecialFrames, frame:GetName())

    promoteFrame = frame
    return frame
end

-- Toggle promote UI
function AIP.TogglePromoteUI()
    local frame = CreatePromoteUI()

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        frame.Update()
    end
end
