local GSE = GSE

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L


local importsequencebox -- created below; declared here so the OnClose handler can release its focus
local compressframe = AceGUI:Create("Frame")
compressframe.AutoCreateIcon = true

compressframe:Hide()


compressframe:SetTitle(L["Gnome Sequencer: Compress a Sequence String."])
compressframe:SetStatusText(L["Paste a full macro above and press Compress to get a short string that is easy to share."])
compressframe:SetCallback("OnClose", function(widget)
  -- release keyboard focus with the window so a hidden edit box can't swallow movement keys/Enter
  if importsequencebox and importsequencebox.editBox then importsequencebox.editBox:ClearFocus() end
  compressframe:Hide()
end)
compressframe:SetLayout("List")

importsequencebox = AceGUI:Create("MultiLineEditBox")
importsequencebox:SetLabel(L["Paste the full macro text here (it starts with Sequences['Name'] = {)."])
importsequencebox:SetNumLines(20)
importsequencebox:DisableButton(true)
importsequencebox:SetFullWidth(true)
compressframe:AddChild(importsequencebox)

local recButtonGroup = AceGUI:Create("SimpleGroup")
recButtonGroup:SetLayout("Flow")


local recbutton = AceGUI:Create("Button")
recbutton:SetText(L["Compress"])
recbutton:SetWidth(150)
recbutton:SetCallback("OnClick", function()
  if GSE.isEmpty(GSE.TrimWhiteSpace(importsequencebox:GetText())) then
    compressframe:SetStatusText(L["Paste a full macro above first."])
    return
  end
  local compressed = GSE.CompressSequenceFromString(importsequencebox:GetText())
  -- On a parse/run failure it returns "": keep the user's pasted text instead of wiping it
  if not GSE.isEmpty(compressed) then
    importsequencebox:SetText(compressed)
    compressframe:SetStatusText(L["Done. Press Ctrl+C to copy the compressed string."])
    if importsequencebox.editBox then
      importsequencebox.editBox:SetFocus()
      importsequencebox.editBox:HighlightText()
    end
  else
    compressframe:SetStatusText(L["Could not read that macro. Check it was copied completely."])
  end
end)
recButtonGroup:AddChild(recbutton)

compressframe:AddChild(recButtonGroup)
GSE.GUICompressFrame = compressframe
GSE.Skin.WalkAceContainer(compressframe)
