-- AutoInvite Plus - Composition Advisor UI
-- Replaces CompositionUI.xml with DRY Lua code using UIFactory

local AIP = AutoInvitePlus
if not AIP then return end

local UI = AIP.UI
if not UI then return end

-- ============================================================================
-- ROLE BAR CLASS
-- ============================================================================

local RoleBar = {}
RoleBar.__index = RoleBar

function RoleBar:new(parent, label, color)
    local bar = setmetatable({}, self)

    bar.frame = CreateFrame("Frame", nil, parent)
    bar.frame:SetSize(350, 18)

    -- Background bar
    bar.bg = bar.frame:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("LEFT")
    bar.bg:SetSize(200, 14)
    bar.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.bg:SetVertexColor(0.2, 0.2, 0.2, 1)

    -- Fill bar
    bar.fill = bar.frame:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("LEFT")
    bar.fill:SetSize(1, 14)
    bar.fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    bar.fill:SetVertexColor(color.r, color.g, color.b, 1)
    bar.defaultColor = color

    -- Label
    bar.label = bar.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bar.label:SetPoint("LEFT", 210, 0)
    bar.label:SetText(label .. ": 0/0")

    return bar
end

function RoleBar:SetValue(current, needed)
    local percent = math.min(current / math.max(1, needed), 1)
    self.fill:SetWidth(math.max(1, 200 * percent))
    self.label:SetText(string.format("%s: %d/%d",
        self.label:GetText():match("^(%S+):") or "Role", current, needed))

    -- Color based on status
    if current >= needed then
        self.fill:SetVertexColor(0, 0.8, 0)
    elseif current > 0 then
        self.fill:SetVertexColor(1, 0.8, 0)
    else
        self.fill:SetVertexColor(0.8, 0, 0)
    end
end

function RoleBar:SetPoint(...)
    self.frame:SetPoint(...)
end

-- ============================================================================
-- MAIN FRAME CREATION
-- ============================================================================

local function CreateCompositionFrame()
    local frame = UI.CreateWindow("AIPCompositionFrame", 450, 500, "Raid Composition Advisor", true)
    frame:SetFrameStrata("DIALOG")

    -- Title border
    local titleBorder = frame:CreateTexture(nil, "ARTWORK")
    titleBorder:SetSize(220, 64)
    titleBorder:SetPoint("TOP", 0, 12)
    titleBorder:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    titleBorder:SetTexCoord(0.2, 0.8, 0, 0.6)

    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", 20, -40)
    content:SetPoint("BOTTOMRIGHT", -20, 50)

    local yOffset = 0

    -- ========================================
    -- TEMPLATE DROPDOWN
    -- ========================================
    local tempLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    tempLabel:SetPoint("TOPLEFT", 0, yOffset)
    tempLabel:SetText("Template:")

    local dropdown = CreateFrame("Frame", "AIPCompTemplateDropdown", content, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", tempLabel, "RIGHT", -10, -3)
    UIDropDownMenu_SetWidth(dropdown, 140)
    frame.templateDropdown = dropdown

    local scanBtn = UI.CreateButton(content, "Scan Raid", 80, 22, function()
        if AIP.Composition then
            AIP.Composition.ScanRaid()
            AIP.UpdateCompositionUI()
        end
    end)
    scanBtn:SetPoint("LEFT", dropdown, "RIGHT", 10, 3)

    yOffset = yOffset - 40

    -- ========================================
    -- ROLE DISTRIBUTION
    -- ========================================
    local roleHeader = UI.CreateSectionHeader(content, "Role Distribution", 400)
    roleHeader:SetPoint("TOPLEFT", 0, yOffset)

    yOffset = yOffset - 25

    frame.tankBar = RoleBar:new(content, "Tanks", {r = 0, g = 0.5, b = 1})
    frame.tankBar:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 20

    frame.healerBar = RoleBar:new(content, "Healers", {r = 0, g = 0.8, b = 0})
    frame.healerBar:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 20

    frame.dpsBar = RoleBar:new(content, "DPS", {r = 0.8, g = 0, b = 0})
    frame.dpsBar:SetPoint("TOPLEFT", 5, yOffset)

    yOffset = yOffset - 35

    -- ========================================
    -- CLASS DISTRIBUTION
    -- ========================================
    local classHeader = UI.CreateSectionHeader(content, "Class Distribution", 400)
    classHeader:SetPoint("TOPLEFT", 0, yOffset)

    yOffset = yOffset - 20

    local classText = content:CreateFontString("AIPCompClassText", "OVERLAY", "GameFontNormalSmall")
    classText:SetPoint("TOPLEFT", 5, yOffset)
    classText:SetSize(400, 60)
    classText:SetJustifyH("LEFT")
    classText:SetJustifyV("TOP")
    frame.classText = classText

    yOffset = yOffset - 70

    -- ========================================
    -- BUFF COVERAGE
    -- ========================================
    local buffHeader = UI.CreateSectionHeader(content, "Buff Coverage", 400)
    buffHeader:SetPoint("TOPLEFT", 0, yOffset)

    yOffset = yOffset - 20

    local buffText = content:CreateFontString("AIPCompBuffText", "OVERLAY", "GameFontNormalSmall")
    buffText:SetPoint("TOPLEFT", 5, yOffset)
    buffText:SetSize(400, 80)
    buffText:SetJustifyH("LEFT")
    buffText:SetJustifyV("TOP")
    frame.buffText = buffText

    yOffset = yOffset - 90

    -- ========================================
    -- MISSING BUFFS
    -- ========================================
    local missingHeader = UI.CreateSectionHeader(content, "Missing Buffs", 400)
    missingHeader:SetPoint("TOPLEFT", 0, yOffset)
    missingHeader.label:SetTextColor(1, 0.3, 0.3)
    frame.missingHeader = missingHeader

    yOffset = yOffset - 20

    local missingText = content:CreateFontString("AIPCompMissingText", "OVERLAY", "GameFontNormalSmall")
    missingText:SetPoint("TOPLEFT", 5, yOffset)
    missingText:SetSize(400, 40)
    missingText:SetJustifyH("LEFT")
    missingText:SetJustifyV("TOP")
    missingText:SetTextColor(1, 0.5, 0.5)
    frame.missingText = missingText

    -- ========================================
    -- BOTTOM BUTTONS
    -- ========================================
    local btnLFM = UI.CreateButton(frame, "Open LFM Browser", 120, 25, function()
        if AIP.ToggleLFMBrowserUI then AIP.ToggleLFMBrowserUI() end
    end)
    btnLFM:SetPoint("BOTTOMLEFT", 20, 15)

    local btnRoster = UI.CreateButton(frame, "Roster Manager", 110, 25, function()
        if AIP.ToggleRosterUI then AIP.ToggleRosterUI() end
    end)
    btnRoster:SetPoint("LEFT", btnLFM, "RIGHT", 10, 0)

    local btnQueue = UI.CreateButton(frame, "Open Queue", 90, 25, function()
        if AIP.ToggleQueueUI then AIP.ToggleQueueUI() end
    end)
    btnQueue:SetPoint("LEFT", btnRoster, "RIGHT", 10, 0)

    return frame
end

-- ============================================================================
-- INITIALIZE DROPDOWN
-- ============================================================================

function AIP.InitCompositionUI()
    local dropdown = _G["AIPCompTemplateDropdown"]
    if not dropdown then return end

    local function Initialize()
        local info = UIDropDownMenu_CreateInfo()

        -- No template option
        info.text = "No Template"
        info.value = nil
        info.func = function()
            if AIP.Composition then
                AIP.Composition.CurrentRaid.template = nil
            end
            UIDropDownMenu_SetText(dropdown, "No Template")
            AIP.UpdateCompositionUI()
        end
        UIDropDownMenu_AddButton(info)

        -- Template options
        if AIP.Composition and AIP.Composition.RaidTemplates then
            for key, data in pairs(AIP.Composition.RaidTemplates) do
                info = UIDropDownMenu_CreateInfo()
                info.text = data.name
                info.value = key
                info.func = function()
                    AIP.Composition.SetTemplate(key)
                    UIDropDownMenu_SetText(dropdown, data.name)
                    AIP.UpdateCompositionUI()
                end
                UIDropDownMenu_AddButton(info)
            end
        end
    end

    UIDropDownMenu_Initialize(dropdown, Initialize)

    -- Set current text
    local current = AIP.Composition and AIP.Composition.CurrentRaid.template
    if current and AIP.Composition.RaidTemplates[current] then
        UIDropDownMenu_SetText(dropdown, AIP.Composition.RaidTemplates[current].name)
    else
        UIDropDownMenu_SetText(dropdown, "No Template")
    end
end

-- ============================================================================
-- UPDATE UI
-- ============================================================================

function AIP.UpdateCompositionUI()
    local frame = _G["AIPCompositionFrame"]
    if not frame or not frame:IsVisible() then return end
    if not AIP.Composition then return end

    local Comp = AIP.Composition
    Comp.ScanRaid()

    local status = Comp.GetCompositionStatus()
    local raid = Comp.CurrentRaid

    -- Role counts
    local tankCurrent = raid.roleCounts.TANK or 0
    local healerCurrent = raid.roleCounts.HEALER or 0
    local dpsCurrent = raid.roleCounts.DPS or 0

    local tankNeeded = status and status.tanks.needed or 2
    local healerNeeded = status and status.healers.needed or 2
    local dpsNeeded = status and status.dps.needed or 6

    -- Update bars
    if frame.tankBar then
        frame.tankBar:SetValue(tankCurrent, tankNeeded)
    end
    if frame.healerBar then
        frame.healerBar:SetValue(healerCurrent, healerNeeded)
    end
    if frame.dpsBar then
        frame.dpsBar:SetValue(dpsCurrent, dpsNeeded)
    end

    -- Class distribution
    if frame.classText then
        local classStr = ""
        for class, count in pairs(raid.classCounts or {}) do
            if count > 0 then
                local coloredName = Comp.ColoredClassName and Comp.ColoredClassName(class) or class
                classStr = classStr .. coloredName .. ": " .. count .. "  "
            end
        end
        frame.classText:SetText(classStr ~= "" and classStr or "No players in group")
    end

    -- Buff coverage
    if frame.buffText then
        local buffStr = ""
        local importantBuffs = {"Bloodlust/Heroism", "Replenishment", "Blessing of Kings", "Power Word: Fortitude"}
        for _, buffName in ipairs(importantBuffs) do
            local available = raid.buffsAvailable and raid.buffsAvailable[buffName]
            local color = available and "|cFF00FF00" or "|cFFFF0000"
            local status = available and "YES" or "NO"
            buffStr = buffStr .. buffName .. ": " .. color .. status .. "|r\n"
        end
        frame.buffText:SetText(buffStr)
    end

    -- Missing buffs
    if frame.missingText and Comp.GetMissingBuffs then
        local missing = Comp.GetMissingBuffs()
        if #missing > 0 then
            frame.missingText:SetText(table.concat(missing, ", "))
            frame.missingText:SetTextColor(1, 0.5, 0.5)
        else
            frame.missingText:SetText("All required buffs covered!")
            frame.missingText:SetTextColor(0, 1, 0)
        end
    end
end

-- ============================================================================
-- TOGGLE
-- ============================================================================

function AIP.ToggleCompositionUI()
    local frame = _G["AIPCompositionFrame"]
    if not frame then
        frame = CreateCompositionFrame()
    end

    if frame:IsVisible() then
        frame:Hide()
    else
        frame:Show()
        AIP.InitCompositionUI()
        AIP.UpdateCompositionUI()
    end
end

-- Initialize on load
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    if not _G["AIPCompositionFrame"] then
        CreateCompositionFrame()
    end
    self:UnregisterAllEvents()
end)
