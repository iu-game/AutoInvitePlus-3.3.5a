local GSE = GSE

local Statics = GSE.Static
local L = GSE.L

local ldb = LibStub:GetLibrary("LibDataBroker-1.1")
local dataobj = ldb:NewDataObject(L["GSE"] .." ".. L["GnomeSequencer-Enhanced"], {
  type = "data source",
  text = "GSE",
})
local LibQTip = LibStub('LibQTip-1.0')
-- Optional: LibSharedMedia is not embedded by GSE/GSE_LDB, so a hard LibStub() here aborted the
-- whole file (no tooltip/click handlers) whenever no other addon had loaded it first.
local LibSharedMedia = LibStub('LibSharedMedia-3.0', true)

-- (a named global font object: keep the name specific to GSE)
local baseFont = CreateFont("GSE_LDBFont")

-- Use ElvUI's font when it is available and readable; any problem reading its settings falls back to the
-- default tooltip font instead of aborting this whole file (which would leave the broker with no handlers).
baseFont:SetFont(GameTooltipText:GetFont(), 10)
if not GSE.isEmpty(ElvUI) and LibSharedMedia then
  pcall(function()
    local elvFont = ElvUI[1].db.general.font
    if LibSharedMedia:IsValid('font', elvFont) then
      baseFont:SetFont(LibSharedMedia:Fetch('font', elvFont), 10)
    end
  end)
end

function dataobj:OnEnter()
  -- Acquire a tooltip with 3 columns, respectively aligned to left, center and right
  --local tooltip = LibQTip:Acquire("GSSE", 3, "LEFT", "CENTER", "RIGHT")
  local tooltip = LibQTip:Acquire("GSSE", 3, "LEFT", "CENTER", "RIGHT")
  self.tooltip = tooltip
  tooltip:SetHighlightTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")

  tooltip:Clear()
  tooltip:SetFont(baseFont)
  --tooltip:SetHeaderFont(red17font)
  local y,x = tooltip:AddLine()
  tooltip:SetCell(y, 1, L["GSE: Left Click to open the macro list"],"CENTER", 3)
  y,x = tooltip:AddLine()
  tooltip:SetCell(y, 1, L["GSE: Middle Click to send or receive macros"],"CENTER", 3)
  y,x = tooltip:AddLine()
  tooltip:SetCell(y, 1, L["GSE: Right Click to open the Sequence Debugger"],"CENTER", 3)
  y,x = tooltip:AddLine()
  tooltip:SetCell(y, 1, L["GSE: Type /gseo to open the Options window"],"CENTER", 3)

  -- If in party add other users and their versions
  if not GSE.isEmpty(GSE.UnsavedOptions["PartyUsers"]) and GSEOptions.showGSEUsers then
    tooltip:AddSeparator()
    y,x = tooltip:AddLine()
    tooltip:SetCell(y,1,L["GSE Users"],"CENTER", 3)
    for k,v in pairs(GSE.UnsavedOptions["PartyUsers"]) do
      tooltip:AddLine(k, nil, v)
    end
  end


  -- Show GSE OOCQueue Information
  if GSEOptions.showGSEoocqueue then
    tooltip:AddSeparator()
    y,x = tooltip:AddLine()
    tooltip:SetCell(y, 1, string.format(L["The GSE Out of Combat queue is %s"], GSE.CheckOOCQueueStatus()),"CENTER", 3)
    local OOCStatusline = y
    tooltip:SetLineScript(y, "OnMouseDown", function(obj, button)
      GSE.ToggleOOCQueue()
      tooltip:SetCell(OOCStatusline, 1, string.format(L["The GSE Out of Combat queue is %s"], GSE.CheckOOCQueueStatus()),"CENTER", 3)
    end)
    tooltip:AddSeparator()
    y,x = tooltip:AddLine()
    if table.getn(GSE.OOCQueue) > 0 then
      tooltip:SetCell(y, 1, string.format(L["There are %i events in out of combat queue"], table.getn(GSE.OOCQueue)),"CENTER", 3)
      for k,v in ipairs(GSE.OOCQueue) do
        y,x = tooltip:AddLine()
        GSE.prepareTooltipOOCLine(tooltip, v, y, k)
      end
    else
      -- No Items
      tooltip:SetCell(y, 1, string.format(L["There are no events in out of combat queue"]),"CENTER", 3)
    end
  end

  tooltip:AddSeparator()
  y,x = tooltip:AddLine()
  tooltip:SetCell(y, 1, string.format(L["GSE Version: %s"], GSE.formatModVersion(GSE.VersionString)),"CENTER", 3)
  -- Use smart anchoring code to anchor the tooltip to our frame
  tooltip:SmartAnchorTo(self)
  -- close on its own shortly after the mouse leaves both the icon and the tooltip (the tooltip has to stay
  -- open while the mouse is over it so its rows can be clicked, and nothing closed it afterwards)
  tooltip:SetAutoHideDelay(0.25, self)


  -- Show it, et voil� !
  tooltip:Show()
end

local function dataObject_OnLeave(self)
  -- Dont close the tooltip if mouseover
  if self.tooltip and not MouseIsOver(self.tooltip) then
    -- Release the tooltip
    LibQTip:Release(self.tooltip)
    self.tooltip = nil
  end
end


function dataobj:OnLeave()
  dataObject_OnLeave(self)
end

function dataobj:OnClick(button)
  -- these windows live in GSE_GUI; without it the click used to throw a nil-function error
  if not GSE.GUIShowViewer then
    GSE.Print(L["The GSE window is not loaded. Enable the GSE_GUI addon to use this."])
    return
  end
  if button == "LeftButton" then
    GSE.GUIShowViewer()
  elseif button == "MiddleButton" then
    GSE.GUIShowTransmissionGui()
  elseif button == "RightButton" then
    GSE.GUIShowDebugWindow()
  end
end
