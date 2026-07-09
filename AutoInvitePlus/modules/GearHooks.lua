-- AutoInvite Plus - Gear Hooks (seamless Blizzard-UI integration)
-- 1) Appends an AutoInvite+ score + upgrade/downgrade verdict to EVERY item
--    tooltip (bags, vendor, bank, inspect, chat links) - the Pawn-style
--    "is this an upgrade for me?" line, computed from AIP.ItemScore.
-- 2) Marks equipped slots on the Blizzard character sheet that are missing an
--    enchant (E) or have an empty gem socket (G).
-- Both are opt-out via AIP.db.tooltipScore / AIP.db.paperdollAudit (default on).

local AIP = AutoInvitePlus
if not AIP then return end
AIP.GearHooks = AIP.GearHooks or {}
local GH = AIP.GearHooks

-- ============================================================================
-- 1) Tooltip score line
-- ============================================================================
local function addTooltipScore(tip)
    if not (AIP.db and AIP.db.tooltipScore) then return end
    local IS = AIP.ItemScore
    if not IS then return end
    local _, link = tip:GetItem()
    if not link then return end
    if tip._aipScored == link then return end   -- avoid double-adding on refresh
    tip._aipScored = link

    local score, eqScore, delta, slotName = IS.UpgradeInfo(link)
    if not score or score <= 0 then return end

    tip:AddLine(" ")
    tip:AddDoubleLine("AutoInvite+ score", string.format("%.0f", score), 0.4, 0.75, 1, 1, 1, 1)
    if delta then
        if delta > 1 then
            tip:AddLine(string.format("|cff20ff20Upgrade for your %s: +%.0f%%|r", slotName or "slot", delta))
        elseif delta < -1 then
            tip:AddLine(string.format("|cffff5555Downgrade vs equipped: %.0f%%|r", delta))
        else
            tip:AddLine("|cffdddd44Sidegrade (about equal to equipped)|r")
        end
    end
    tip:Show()   -- re-fit the tooltip to the added lines
end

local function hookTip(tip)
    if not tip then return end
    tip:HookScript("OnTooltipSetItem", addTooltipScore)
    tip:HookScript("OnHide", function(self) self._aipScored = nil end)
end
hookTip(GameTooltip)
hookTip(ItemRefTooltip)

-- ============================================================================
-- 2) Character-sheet enchant/gem markers
-- ============================================================================
local SLOT_FRAME = {
    [1]="CharacterHeadSlot", [2]="CharacterNeckSlot", [3]="CharacterShoulderSlot",
    [5]="CharacterChestSlot", [6]="CharacterWaistSlot", [7]="CharacterLegsSlot",
    [8]="CharacterFeetSlot", [9]="CharacterWristSlot", [10]="CharacterHandsSlot",
    [11]="CharacterFinger0Slot", [12]="CharacterFinger1Slot", [13]="CharacterTrinket0Slot",
    [14]="CharacterTrinket1Slot", [15]="CharacterBackSlot", [16]="CharacterMainHandSlot",
    [17]="CharacterSecondaryHandSlot", [18]="CharacterRangedSlot",
}
GH.markers = {}

local function getMarker(fname)
    if GH.markers[fname] ~= nil then return GH.markers[fname] end
    local slotFrame = _G[fname]
    if not slotFrame then GH.markers[fname] = false; return false end
    local fs = slotFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    fs:SetPoint("BOTTOMRIGHT", slotFrame, "BOTTOMRIGHT", -1, 1)
    fs:SetShadowOffset(1, -1); fs:SetShadowColor(0, 0, 0, 1)
    fs:Hide()
    GH.markers[fname] = fs
    return fs
end

function GH.UpdatePaperdoll()
    local GA = AIP.GearAdvisor
    if not (GA and GA.SlotAudit) then return end
    local show = (AIP.db and AIP.db.paperdollAudit)
    for slot, fname in pairs(SLOT_FRAME) do
        local fs = getMarker(fname)
        if fs then
            if not show then
                fs:Hide()
            else
                local missing, sockets = GA.SlotAudit(slot)
                local txt = ""
                if missing then txt = txt .. "|cffff3030E|r" end
                if sockets and sockets > 0 then txt = txt .. "|cff40a0ffG|r" end
                if txt ~= "" then fs:SetText(txt); fs:Show() else fs:Hide() end
            end
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function() GH.UpdatePaperdoll() end)
-- Refresh whenever the character sheet opens (frames exist by then).
if CharacterFrame then CharacterFrame:HookScript("OnShow", GH.UpdatePaperdoll) end
