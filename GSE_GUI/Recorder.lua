local GSE = GSE

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L
local libS = LibStub:GetLibrary("AceSerializer-3.0")
local libC = LibStub:GetLibrary("LibCompress")
local libCE = libC:GetAddonEncodeTable()

local recordframe = AceGUI:Create("Frame")
recordframe:Hide()
GSE.GUIRecordFrame = recordframe
local recbuttontext = L["Record"]
local recbutton -- created below; declared here so the OnClose handler can reset it

-- Record Frame

recordframe:SetTitle(L["Record Macro"])
recordframe:SetStatusText(L["Press Record, cast your spells in order, press Stop, then Create Macro."])
recordframe:SetCallback("OnClose", function(widget)
  recordframe:Hide()
  -- closing mid-recording must not leave the recorder capturing casts in the background
  if GSE.RecorderActive then
    GSE.RecorderActive = false
    recbuttontext = L["Record"]
    recbutton:SetText(recbuttontext)
  end
  recordframe:SetStatusText(L["Press Record, cast your spells in order, press Stop, then Create Macro."])
  -- Bring the Viewer back only if opening this window is what hid it (the Viewer's Record Macro
  -- button), and not when Create Macro is handing over to the editor. `/gse record` opens this
  -- window on its own, and closing it must not pop the Viewer up unprompted.
  if recordframe.openingEditor then
    recordframe.openingEditor = false
    recordframe.reopenViewer = false
  elseif recordframe.reopenViewer then
    recordframe.reopenViewer = false
    GSE.GUIShowViewer()
  end
end)
recordframe:SetLayout("List")

local recordsequencebox = AceGUI:Create("MultiLineEditBox")
recordsequencebox:SetLabel(L["Actions"])
recordsequencebox:SetNumLines(20)
recordsequencebox:DisableButton(true)
recordsequencebox:SetFullWidth(true)
recordframe:AddChild(recordsequencebox)
GSE.GUIRecordFrame.RecordSequenceBox = recordsequencebox

local recButtonGroup = AceGUI:Create("SimpleGroup")
recButtonGroup:SetLayout("Flow")


recbutton = AceGUI:Create("Button")
recbutton:SetText(L["Record"])
recbutton:SetWidth(150)
recbutton:SetCallback("OnClick", function() GSE.GUIManageRecord() end)
recButtonGroup:AddChild(recbutton)

local createmacrobutton = AceGUI:Create("Button")
createmacrobutton:SetText(L["Create Macro"])
createmacrobutton:SetWidth(150)
createmacrobutton:SetCallback("OnClick", function()
  -- The record window is hidden by GUILoadEditor: stop capturing so casts don't keep piling into
  -- the hidden box and the button doesn't stay on "Stop".
  GSE.RecorderActive = false
  recbuttontext = L["Record"]
  recbutton:SetText(recbuttontext)
  recordframe:SetStatusText(L["Press Record, cast your spells in order, press Stop, then Create Macro."])
  recordframe.openingEditor = true
  GSE.GUILoadEditor( nil, GSE.GUIRecordFrame, recordsequencebox:GetText())
  -- GUILoadEditor hides this window synchronously; if it bailed out before doing so, don't leave the
  -- flag set to swallow the next ordinary close.
  recordframe.openingEditor = false
end)
createmacrobutton:SetDisabled(true)
recButtonGroup:AddChild(createmacrobutton)

-- The list is meant to be edited or pasted into after Stop: offer Create Macro whenever there is text
-- and a recording is not in progress (Stop with an empty box used to lock it until the next recording).
recordsequencebox:SetCallback("OnTextChanged", function(_, _, value)
  if not GSE.RecorderActive then
    createmacrobutton:SetDisabled(GSE.isEmpty(GSE.TrimWhiteSpace(value or "")))
  end
end)

recordframe:AddChild(recButtonGroup)
GSE.Skin.WalkAceContainer(recordframe)

function GSE.GUIManageRecord()
  if recbuttontext == L["Record"] then
    recbuttontext = L["Stop"]
    -- Otherwise a second recording appends after whatever the previous one
    -- (or a leftover Create Macro pass) left in the box, instead of
    -- starting clean.
    recordsequencebox:SetText("")
    createmacrobutton:SetDisabled(true)
    recordframe:SetStatusText(L["Recording... cast your spells now."])
    GSE.RecorderActive = true
  else
    recbuttontext = L["Record"]
    GSE.RecorderActive = false
    -- only offer Create Macro once something was actually recorded
    createmacrobutton:SetDisabled(GSE.isEmpty(recordsequencebox:GetText()))
    recordframe:SetStatusText(L["Stopped. Edit the list if you like, then press Create Macro."])
  end
  recbutton:SetText(recbuttontext)
end
