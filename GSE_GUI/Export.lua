local GSE = GSE

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L
local libS = LibStub:GetLibrary("AceSerializer-3.0")
local libC = LibStub:GetLibrary("LibCompress")
local libCE = libC:GetAddonEncodeTable()

local exportsequencebox -- created below; declared here so the OnClose handler can release its focus
local exportframe = AceGUI:Create("Frame")
exportframe:Hide()


exportframe:SetTitle(L["Gnome Sequencer: Export a Sequence String."])
exportframe:SetStatusText(L["Ctrl+C to copy the highlighted text, then paste it to share."])
exportframe:SetCallback("OnClose", function(widget)
  -- give up keyboard focus with the window, or a hidden edit box keeps eating movement keys and Enter
  if exportsequencebox and exportsequencebox.editBox then exportsequencebox.editBox:ClearFocus() end
  exportframe:Hide()
end)
exportframe:SetLayout("List")

exportsequencebox = AceGUI:Create("MultiLineEditBox")
exportsequencebox:SetLabel(L["Copy this text"])
exportsequencebox:SetNumLines(29)
exportsequencebox:DisableButton(true)
exportsequencebox:SetFullWidth(true)
exportframe:AddChild(exportsequencebox)

GSE.GUIExportframe = exportframe

exportframe.ExportSequenceBox = exportsequencebox
GSE.Skin.WalkAceContainer(exportframe)

function GSE.GUIExportSequence(classid, sequencename)
  GSE.GUIExportframe.ExportSequenceBox:SetText(GSE.ExportSequence(GSELibrary[tonumber(classid)][sequencename], sequencename))
  GSE.GUIExportframe:Show()
  -- Pre-select everything so Ctrl+C works straight away, without clicking and pressing Ctrl+A first
  local editBox = GSE.GUIExportframe.ExportSequenceBox.editBox
  if editBox then
    editBox:SetFocus()
    editBox:HighlightText()
  end
end
