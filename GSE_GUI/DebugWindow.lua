local GSE = GSE
local GNOME, _ = ...

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L

local onpause = false

local DebugFrame = AceGUI:Create("Frame")
GSE.GUIDebugFrame = DebugFrame
DebugFrame.DebugOutputTextbox = AceGUI:Create("MultiLineEditBox")
GSE.GUIDebugFrame.DebugEnableViewButton = AceGUI:Create("Button")
GSE.GUIDebugFrame.DebugPauseViewButton = AceGUI:Create("Button")



function GSE.GUIShowDebugWindow()
  DebugFrame:Show()
end


-- The output box grows every second while enabled; keep only the most recent text so a long
-- session can't make the window (and every timer tick) slower and slower.
local MAX_DEBUG_CHARS = 30000

function GSE.GUIUpdateOutput()
  -- Nothing new: leave the box alone (rewriting it every tick also snapped the scroll position).
  if GSE.isEmpty(GSE.DebugOutput) then
    return
  end
  local text = GSE.GUIDebugFrame.DebugOutputTextbox:GetText() .. GSE.DebugOutput
  if string.len(text) > MAX_DEBUG_CHARS then
    text = string.sub(text, string.len(text) - MAX_DEBUG_CHARS + 1)
    -- start on a whole line
    local firstBreak = string.find(text, "\n", 1, true)
    if firstBreak then
      text = string.sub(text, firstBreak + 1)
    end
  end
  GSE.GUIDebugFrame.DebugOutputTextbox:SetText(text)
  GSE.DebugOutput = ""
end

function GSE.GUIEnableDebugView()
  if GSE.UnsavedOptions["DebugSequenceExecution"] then
    --Disable
    GSE.UnsavedOptions["DebugSequenceExecution"] = false
    GSE.GUIDebugFrame.DebugEnableViewButton:SetText(L["Enable"])
    GSE.GUIDebugFrame.DebugPauseViewButton:SetText(L["Pause"])
    GSE.GUIDebugFrame.DebugPauseViewButton:SetDisabled(true)
    -- silent: after Pause the timer is already cancelled and a non-silent CancelTimer raises an error
    GSE:CancelTimer(GSE.GUIUpdateTimer, true)
    onpause = false
  else
    --enable
    GSE.UnsavedOptions["DebugSequenceExecution"] = true
    GSE.GUIDebugFrame.DebugEnableViewButton:SetText(L["Disable"])
    GSE.GUIUpdateTimer = GSE:ScheduleRepeatingTimer("GUIUpdateOutput", 1)
    GSE.GUIDebugFrame.DebugPauseViewButton:SetDisabled(false)
  end
end

function GSE.GUIPauseDebugView()
  if onpause then
    GSE.GUIDebugFrame.DebugPauseViewButton:SetText(L["Pause"])
    GSE.GUIUpdateTimer = GSE:ScheduleRepeatingTimer("GUIUpdateOutput", 1)
    onpause = false
  else
    GSE.GUIDebugFrame.DebugPauseViewButton:SetText(L["Resume"])
    GSE:CancelTimer(GSE.GUIUpdateTimer)
    onpause = true
  end
end

DebugFrame:SetTitle(L["Sequence Debugger"])
-- (The old "GCD: n" here was read once at load and never updated, so it only ever showed a stale number.)
DebugFrame:SetStatusText(L["Press Enable, then press one of your GSE macros to see each step it runs."])
DebugFrame:SetCallback("OnClose", function(widget) DebugFrame:Hide()  end)
DebugFrame:SetLayout("List")
DebugFrame:Hide()


GSE.GUIDebugFrame.DebugOutputTextbox:SetLabel(L["Output"])
GSE.GUIDebugFrame.DebugOutputTextbox:SetNumLines(25)
GSE.GUIDebugFrame.DebugOutputTextbox:DisableButton(true)
GSE.GUIDebugFrame.DebugOutputTextbox:SetFullWidth(true)
DebugFrame:AddChild(GSE.GUIDebugFrame.DebugOutputTextbox)

local buttonGroup = AceGUI:Create("SimpleGroup")
buttonGroup:SetFullWidth(true)
buttonGroup:SetLayout("Flow")


GSE.GUIDebugFrame.DebugEnableViewButton:SetWidth(150)
GSE.GUIDebugFrame.DebugEnableViewButton:SetCallback("OnClick", function() GSE.GUIEnableDebugView() end)
buttonGroup:AddChild(GSE.GUIDebugFrame.DebugEnableViewButton)

GSE.GUIDebugFrame.DebugPauseViewButton:SetText(L["Pause"])
GSE.GUIDebugFrame.DebugPauseViewButton:SetWidth(150)
GSE.GUIDebugFrame.DebugPauseViewButton:SetCallback("OnClick", function() GSE.GUIPauseDebugView() end)
buttonGroup:AddChild(GSE.GUIDebugFrame.DebugPauseViewButton)

if GSE.UnsavedOptions["DebugSequenceExecution"] then
  GSE.GUIDebugFrame.DebugEnableViewButton:SetText(L["Disable"])
  GSE.GUIDebugFrame.DebugPauseViewButton:SetDisabled(false)
else
  GSE.GUIDebugFrame.DebugEnableViewButton:SetText(L["Enable"])
  GSE.GUIDebugFrame.DebugPauseViewButton:SetDisabled(true)
end

GSE.GUIDebugFrame.DebugClearViewButton = AceGUI:Create("Button")
GSE.GUIDebugFrame.DebugClearViewButton:SetText(L["Clear"])
GSE.GUIDebugFrame.DebugClearViewButton:SetWidth(150)
GSE.GUIDebugFrame.DebugClearViewButton:SetCallback("OnClick", function() GSE.GUIDebugFrame.DebugOutputTextbox:SetText('') end)
buttonGroup:AddChild(GSE.GUIDebugFrame.DebugClearViewButton)

GSE.GUIDebugFrame.DebugOptionsViewButton = AceGUI:Create("Button")
GSE.GUIDebugFrame.DebugOptionsViewButton:SetText(L["Options"])
GSE.GUIDebugFrame.DebugOptionsViewButton:SetWidth(150)
GSE.GUIDebugFrame.DebugOptionsViewButton:SetCallback("OnClick", function() GSE.OpenOptionsPanel() end)
buttonGroup:AddChild(GSE.GUIDebugFrame.DebugOptionsViewButton)

DebugFrame:AddChild(buttonGroup)
GSE.Skin.WalkAceContainer(DebugFrame)
