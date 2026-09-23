local GNOME,_ = ...

local GSE = GSE
local Statics = GSE.Static

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L
local libS = LibStub:GetLibrary("AceSerializer-3.0")
local libC = LibStub:GetLibrary("LibCompress")
local libCE = libC:GetAddonEncodeTable()
local editkey = ""


local viewframe = AceGUI:Create("Frame")
viewframe:SetTitle(L["Sequence Viewer"])


GSE.GUIViewFrame = viewframe

viewframe:Hide()
local sequenceboxtext = AceGUI:Create("MultiLineEditBox")
local remotesequenceboxtext = AceGUI:Create("MultiLineEditBox")

viewframe.panels = {}
viewframe.SequenceName = ""
viewframe.ClassID = 0

-- Set maximum resize bounds based on screen size
local maxHeight = GetScreenHeight() - 40
local maxWidth = GetScreenWidth() - 40
viewframe.frame:SetMaxResize(maxWidth, maxHeight)
viewframe.frame:SetMinResize(700, 450)

--- Attaches a GameTooltip to any AceGUI widget whose type genuinely fires
--- OnEnter/OnLeave ace-callback events (verified per widget type against the
--- vendored AceGUI-3.0 source rather than assumed - see the identical helper
--- in Editor.lua for the widgets checked). `title` is the tooltip header,
--- `body` a wrapped description line under it.
--- A fixed ANCHOR_RIGHT ran the tooltip off the right edge of the screen for
--- a widget sitting near it. Picking LEFT vs RIGHT by comparing the widget's
--- frame position against half of GetScreenWidth() was still wrong: on a
--- multi-monitor setup (or any window not centred on the primary display)
--- that comparison doesn't reliably track where the widget actually sits
--- relative to the window's own visible bounds, so the same clipping just
--- moved to whichever widgets it now misjudged. Anchoring to the cursor
--- instead sidesteps the whole left/right guess - GameTooltip keeps a
--- cursor-anchored tooltip on-screen on its own, regardless of window
--- position, and this is the standard approach most WoW addons use for
--- exactly this reason.
local function attachTooltip(widget, title, body)
  widget:SetCallback("OnEnter", function(w)
    GameTooltip:SetOwner(w.frame, "ANCHOR_CURSOR")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(body, nil, nil, nil, true)
    GameTooltip:Show()
  end)
  widget:SetCallback("OnLeave", function()
    GameTooltip:Hide()
  end)
end

-- Live height reflow for the listing's scroll area - see the identical
-- pattern (and the fuller explanation of why AceGUI needs this instead of a
-- SetRelativeHeight this bundled library doesn't have) in Editor.lua.
-- Width doesn't need this: scrollcontainer is SetFullWidth(true) with no
-- fixed-width sibling, so it already reflows live via DoLayout() cascading
-- down from viewframe on every OnSizeChanged tick.
viewframe.heightReflow = {}
local function applyContentReflow()
  for _, entry in ipairs(viewframe.heightReflow) do
    if entry.widget and entry.widget.frame then
      pcall(entry.widget.SetHeight, entry.widget, math.max(entry.min or 100, viewframe.Height - entry.offset))
    end
  end
end

-- Add resize constraints to prevent window from going off screen
viewframe.frame:SetScript("OnSizeChanged", function ()
  local Left, Bottom, Width, Height = viewframe.frame:GetBoundsRect()
  viewframe.Width = Width
  viewframe.Height = Height
  local screenHeight = GetScreenHeight()
  local screenWidth = GetScreenWidth()
  local maxHeight = screenHeight - 40  -- Leave some space at top/bottom
  local maxWidth = screenWidth - 40    -- Leave some space at sides
  
  -- Get current position
  local top = viewframe.frame:GetTop()
  local bottom = viewframe.frame:GetBottom()
  local left = viewframe.frame:GetLeft()
  local right = viewframe.frame:GetRight()
  
  -- Check if we need to constrain the size or reposition
  local needsResize = false
  local needsMove = false
  local newHeight = Height
  local newWidth = Width
  
  if Height > maxHeight then
    newHeight = maxHeight
    needsResize = true
  end
  
  if Width > maxWidth then
    newWidth = maxWidth
    needsResize = true
  end
  
  -- Check if window is going off screen edges
  if top and top > screenHeight then
    needsMove = true
  end
  
  if bottom and bottom < 0 then
    needsMove = true
  end
  
  if left and left < 0 then
    needsMove = true
  end
  
  if right and right > screenWidth then
    needsMove = true
  end
  
  -- Apply constraints if needed
  if needsResize then
    viewframe.frame:SetHeight(newHeight)
    viewframe.frame:SetWidth(newWidth)
    viewframe.Height = newHeight
    viewframe.Width = newWidth
  end

  -- Reposition if off screen
  if needsMove then
    local newPoint = {}
    newPoint.x = math.min(math.max(left or 20, 20), screenWidth - newWidth - 20)
    newPoint.y = math.min(math.max(bottom or 20, 20), screenHeight - newHeight - 20)
    viewframe.frame:ClearAllPoints()
    viewframe.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newPoint.x, newPoint.y)
  end

  applyContentReflow()
  viewframe:DoLayout()
end)

function viewframe:clearpanels(widget, selected)
  GSE.PrintDebugMessage("widget = " .. widget:GetKey(), "GUI")
  for k,v in pairs(viewframe.panels) do
    GSE.PrintDebugMessage("k " .. k, "GUI")
    if k == widget:GetKey() then
      GSE.PrintDebugMessage ("matching key", "GUI")
      local elements = GSE.split(widget:GetKey(), ",")
      if selected then
        -- Store as a number (matching GSE.GUICreateSequencePanels'
        -- tonumber(elements[1]) convention) - GUIConfigureMacroButton
        -- compares this against numeric constants with ==, which never
        -- matches a raw string since Lua's == does no coercion.
        viewframe.ClassID = tonumber(elements[1])
        viewframe.SequenceName = elements[2]
        viewframe.EditButton:SetDisabled(false)
        viewframe.ExportButton:SetDisabled(false)
        editkey = k
      else
        viewframe.ClassID = 0
        viewframe.SequenceName = ""
        viewframe.EditButton:SetDisabled(true)
        viewframe.ExportButton:SetDisabled(true)
        editkey = ""
      end

      viewframe.panels[k]:SetClicked(true)
    else
      GSE.PrintDebugMessage ("other widget key", "GUI")
      GSE.PrintDebugMessage("reprinting k " .. k, "GUI")
      local wid = viewframe.panels[k]
      wid:SetClicked(false)
    end
  end

  GSE.GUIConfigureMacroButton(viewframe.MacroIconButton)

end

function GSE.GUICreateSequencePanels(frame, container, key)
  local elements = GSE.split(key, ",")
  local classid = tonumber(elements[1])
  local sequencename = elements[2]
  local fontName, fontHeight, fontFlags = GameFontNormal:GetFont()
  local font = GameFontNormal:GetFontObject()
  local origjustifyV = font:GetJustifyV()
  font:SetJustifyV("BOTTOM")

  local seq = GSELibrary[classid] and GSELibrary[classid][sequencename]

  -- One compact row per macro: icon | name + talents (+ help link if set).
  -- SelectablePanel auto-sizes its own height to fit whatever this lays out
  -- (see AceGUI-3.0-Selectable-Panel.lua's LayoutFinished), so there's no
  -- fixed height to fight with here - the old SetHeight(300) card is why the
  -- listing only ever showed ~1 entry at a time.
  local selpanel = AceGUI:Create("SelectablePanel")
  selpanel:SetKey(key)
  selpanel:SetFullWidth(true)
  selpanel:SetLayout("Flow")
  viewframe.panels[key] = selpanel
  selpanel:SetCallback("OnClick", function(widget, _, selected, button)
    viewframe:clearpanels(widget, true)
    if button == "RightButton" then
      GSE.GUILoadEditor(widget:GetKey(), viewframe)
    end
  end)

  -- Icon: fixed width, with an explicit drag cue so "drag this onto your
  -- action bar" doesn't require a guide to discover.
  local viewiconpicker = AceGUI:Create("Icon")
  viewiconpicker.frame:RegisterForDrag("LeftButton")
  viewiconpicker.frame:SetScript("OnDragStart", function()
    PickupMacro(sequencename)
  end)
  selpanel.Icon = viewiconpicker
  viewiconpicker:SetImage(GSE.GetMacroIcon(classid, sequencename))
  viewiconpicker:SetImageSize(36, 36)
  viewiconpicker:SetWidth(44)
  attachTooltip(viewiconpicker, sequencename, L["Drag to your action bar to create a macro button."])
  selpanel:AddChild(viewiconpicker)

  -- Info column: the only other child in this Flow row, so a plain relative
  -- width (no wrapRelative wrapper needed - that's only for widgets like
  -- Dropdown whose *own* internal template has its own fixed anchors) is
  -- enough to have it fill the rest of the row and reflow with it live.
  local infocolumn = AceGUI:Create("SimpleGroup")
  infocolumn:SetRelativeWidth(0.88)
  infocolumn:SetLayout("List")

  local label = AceGUI:Create("Label")
  label:SetText(sequencename)
  label:SetFont(fontName, fontHeight + 4 , fontFlags)
  label:SetColor(GSE.GUIGetColour(GSEOptions.KEYWORD))
  label:SetFullWidth(true)
  infocolumn:AddChild(label)

  local row2 = AceGUI:Create("SimpleGroup")
  row2:SetLayout("Flow")
  row2:SetFullWidth(true)

  local talentsHead = AceGUI:Create("Label")
  talentsHead:SetFont(fontName, fontHeight + 2 , fontFlags)
  talentsHead:SetText(L["Talents"] ..":")
  talentsHead:SetColor(GSE.GUIGetColour(GSEOptions.KEYWORD))
  talentsHead:SetWidth(60)
  row2:AddChild(talentsHead)

  local talentslabel = AceGUI:Create("Label")
  if seq and not GSE.isEmpty(seq.Talents) then
    talentslabel:SetText(seq.Talents)
  end
  -- Talents is free-typed text (Editor.lua's talentseditbox), not a fixed-
  -- length code - the old 90px width was too narrow for a typical entry
  -- (e.g. "5/3/0/2/3/1"), so AceGUI's Label wrapped it internally and grew
  -- taller than this Flow row's siblings expected, visually overlapping the
  -- NEXT macro's row below. Widened to fit realistic entries on one line,
  -- and word-wrap disabled on the underlying FontString so a still-too-long
  -- entry clips at the row's own width instead of corrupting row height
  -- again - a clipped tail is a far less jarring failure than one row's
  -- text bleeding into the next row's space.
  talentslabel:SetWidth(260)
  talentslabel:SetFontObject(font)
  talentslabel.label:SetWordWrap(false)
  row2:AddChild(talentslabel)

  -- Only show a Help URL field when this sequence actually has one - a
  -- generic placeholder link on every single row was noise, not information.
  if seq and not GSE.isEmpty(seq.Helplink) then
    local urlHead = AceGUI:Create("Label")
    urlHead:SetFont(fontName, fontHeight + 2 , fontFlags)
    urlHead:SetText(L["Help URL"] ..":")
    urlHead:SetColor(GSE.GUIGetColour(GSEOptions.EmphasisColour))
    urlHead:SetWidth(70)
    row2:AddChild(urlHead)

    local urllabel = AceGUI:Create("InteractiveLabel")
    urllabel:SetFontObject(font)
    urllabel:SetText(seq.Helplink)
    urllabel:SetCallback("OnClick", function()
      StaticPopupDialogs['GSE_SEQUENCEHELP'].url = seq.Helplink
      StaticPopup_Show('GSE_SEQUENCEHELP')
    end)
    urllabel:SetColor(GSE.GUIGetColour(GSEOptions.WOWSHORTCUTS))
    urllabel:SetRelativeWidth(0.5)
    row2:AddChild(urllabel)
  end

  infocolumn:AddChild(row2)

  -- Likewise, only show help text when there is any - "No Help Information
  -- Available" on every row was filler, not information.
  if seq and not GSE.isEmpty(seq.Help) then
    local helplabel = AceGUI:Create("Label")
    helplabel:SetFullWidth(true)
    helplabel:SetFontObject(font)
    helplabel:SetText(seq.Help)
    infocolumn:AddChild(helplabel)
  end

  selpanel:AddChild(infocolumn)

  container:AddChild(selpanel)
  font:SetJustifyV(origjustifyV)
end

function GSE.GUIViewerToolbar(container)


  local buttonGroup = AceGUI:Create("SimpleGroup")
  buttonGroup:SetFullWidth(true)
  buttonGroup:SetLayout("Flow")

  -- 8 buttons, 4 per row at this window's min width - relative-width
  -- (rather than the old fixed 150px) so each row's buttons stretch to
  -- fill it evenly instead of packing left with dead space on the right.
  -- Buttons (unlike Dropdowns) have no internal template that breaks under
  -- SetRelativeWidth, so no wrapFixed/wrapRelative wrapper is needed here.
  local newbutton = AceGUI:Create("Button")
  newbutton:SetText(L["New"])
  newbutton:SetRelativeWidth(0.25)
  newbutton:SetCallback("OnClick", function() GSE.isNewFirstTimeCreated=true; GSE.GUILoadEditor(nil, viewframe) end)
  attachTooltip(newbutton, L["New"], L["Creates a new, empty macro for your current spec and opens it in the editor."])
  buttonGroup:AddChild(newbutton)

  local updbutton = AceGUI:Create("Button")
  updbutton:SetText(L["Edit"])
  updbutton:SetRelativeWidth(0.25)
  updbutton:SetCallback("OnClick", function()
    GSE.GUIEditFrame:SetStatusText("")
	GSE.GUILoadEditor(editkey, viewframe)
  end)
  updbutton:SetDisabled(true)
  attachTooltip(updbutton, L["Edit"], L["Opens the selected macro in the editor. Select a macro from the list above first."])
  buttonGroup:AddChild(updbutton)
  viewframe.EditButton = updbutton

  local impbutton = AceGUI:Create("Button")
  impbutton:SetText(L["Import"])
  impbutton:SetRelativeWidth(0.25)
  impbutton:SetCallback("OnClick", function() GSE.GUIViewFrame:Hide(); GSE.GUIImportFrame:Show() end)
  attachTooltip(impbutton, L["Import"], L["Imports a macro from a shared export string."])
  buttonGroup:AddChild(impbutton)

  local expbutton = AceGUI:Create("Button")
  expbutton:SetText(L["Export"])
  expbutton:SetRelativeWidth(0.25)
  expbutton:SetCallback("OnClick", function()
    GSE.GUIExportSequence(viewframe.ClassID, viewframe.SequenceName)
  end)
  attachTooltip(expbutton, L["Export"], L["Exports the selected macro as a text string you can share. Select a macro from the list above first."])
  buttonGroup:AddChild(expbutton)
  expbutton:SetDisabled(true)
  viewframe.ExportButton = expbutton

  local tranbutton = AceGUI:Create("Button")
  tranbutton:SetText(L["Send"])
  tranbutton:SetRelativeWidth(0.25)
  tranbutton:SetCallback("OnClick", function() GSE.GUIShowTransmissionGui(viewframe.ClassID .. "," .. viewframe.SequenceName) end)
  attachTooltip(tranbutton, L["Send"], L["Sends the selected macro to another player directly over the addon channel."])
  buttonGroup:AddChild(tranbutton)

  local disableSeqbutton = AceGUI:Create("Button")
  disableSeqbutton:SetDisabled(true)
  disableSeqbutton:SetText(L["Create Macro Button"])
  disableSeqbutton:SetRelativeWidth(0.25)
  attachTooltip(disableSeqbutton, L["Create Macro Button"], L["Creates a real WoW macro for the selected macro, so it can be dragged onto an action bar. Select a macro from the list above first."])


  buttonGroup:AddChild(disableSeqbutton)
  viewframe.MacroIconButton = disableSeqbutton
  local eOptionsbutton = AceGUI:Create("Button")
  eOptionsbutton:SetText(L["Options"])
  eOptionsbutton:SetRelativeWidth(0.25)
  eOptionsbutton:SetCallback("OnClick", function() GSE.OpenOptionsPanel() end)
  attachTooltip(eOptionsbutton, L["Options"], L["Opens the Gnome Sequencer options panel (colours, defaults, and other addon-wide settings)."])
  buttonGroup:AddChild(eOptionsbutton)

  local recordwindowbutton = AceGUI:Create("Button")
  recordwindowbutton:SetText(L["Record Macro"])
  recordwindowbutton:SetRelativeWidth(0.25)
  recordwindowbutton:SetCallback("OnClick", function() GSE.GUIViewFrame:Hide(); GSE.GUIRecordFrame:Show() end)
  attachTooltip(recordwindowbutton, L["Record Macro"], L["Opens the macro recorder, which captures your spell casts in real time to build a sequence automatically."])
  buttonGroup:AddChild(recordwindowbutton)

  container:AddChild(buttonGroup)

  sequenceboxtext = sequencebox
end



function GSE.GUIViewerLayout(mcontainer)
  mcontainer:SetStatusText(L["Gnome Sequencer: Sequence Viewer"])
  mcontainer:SetCallback("OnClose", function(widget) viewframe:Hide() end)
  mcontainer:SetLayout("List")


  local scrollcontainer = AceGUI:Create("SimpleGroup")
  scrollcontainer:SetFullWidth(true)
  -- Leaves room for the title bar, the toolbar button row below the list,
  -- and the status bar. Kept live on resize via viewframe.heightReflow
  -- (applyContentReflow, near the top of this file) since this bundled
  -- AceGUI-3.0 has no SetRelativeHeight.
  -- Measured live: title bar ~39, the button toolbar's own real height
  -- ~54 (2 rows), status bar/close-button row the rest - 140 fits all of
  -- that plus a small intentional gap above the status bar. The previous
  -- 190 reserved 60 units nobody used, showing as a large dead gap between
  -- the button row and the window's bottom edge.
  scrollcontainer:SetHeight(math.max(200, (viewframe.Height or 500) - 140))
  scrollcontainer:SetLayout("Fill")
  table.insert(viewframe.heightReflow, { widget = scrollcontainer, offset = 140, min = 200 })

  mcontainer:AddChild(scrollcontainer)
  local contentcontainer = AceGUI:Create("ScrollFrame")
  contentcontainer:SetLayout("list")
  scrollcontainer:AddChild(contentcontainer)
  viewframe.ScrollContainer = contentcontainer

  GSE.GUIViewerToolbar(mcontainer)

end

function GSE.GUIShowViewer()
  local names = GSE.GetSequenceNames()

  viewframe:ReleaseChildren()
  -- The widget this referenced belongs to the content just released above;
  -- GUIViewerLayout repopulates it fresh below.
  wipe(viewframe.heightReflow)
  GSE.GUIViewerLayout(viewframe)
  local cclassid = -1
  for k,v in GSE.pairsByKeys(names) do
    local elements = GSE.split(k, ",")
    local tclassid = tonumber(elements[1])
    if tclassid ~= cclassid then
      cclassid = tclassid
      local fontName, fontHeight, fontFlags = GameFontNormal:GetFont()
      local sectionspacer1 = AceGUI:Create("Label")
      sectionspacer1:SetText(" ")
      sectionspacer1:SetFont(fontName, 4 , fontFlags)
      viewframe.ScrollContainer:AddChild(sectionspacer1)
      local sectionheader = AceGUI:Create("Label")
      sectionheader:SetText(Statics.wotlkSpecIDList[cclassid])
      sectionheader:SetFont(fontName, fontHeight + 6 , fontFlags)
      sectionheader:SetColor(GSE.GUIGetColour(GSEOptions.COMMENT))
      viewframe.ScrollContainer:AddChild(sectionheader)
      local sectionspacer2 = AceGUI:Create("Label")
      sectionspacer2:SetText(" ")
      sectionspacer2:SetFont(fontName, 2 , fontFlags)
      viewframe.ScrollContainer:AddChild(sectionspacer2)
    end
    GSE.GUICreateSequencePanels(viewframe,viewframe.ScrollContainer, k)
  end
  GSE.Skin.WalkAceContainer(viewframe)
  viewframe:Show()
end

-- This button creates/removes the actual WoW macro (the thing you drag onto
-- your action bar) for the selected sequence - "Create/Delete Icon" was
-- confusing wording (it sounds like it only changes a picture, not that it
-- creates or deletes a real macro).
function GSE.GUIConfigureMacroButton(button)
  if GSE.OOCCheckMacroCreated(GSE.GUIViewFrame.SequenceName) then
    button:SetText(L["Remove Macro Button"])
    attachTooltip(button, L["Remove Macro Button"], L["Deletes the actual WoW macro for this sequence, so it can no longer be dragged onto an action bar. The sequence itself is kept and can have its macro button recreated later."])
    button:SetCallback("OnClick", function()
      -- Deletes directly rather than going through DeleteMacroStub's
      -- fuzzy body-text match (comparing the macro's current body against
      -- what GSE would generate for it right now). That match exists to
      -- guard CleanOrphanSequences' automatic background cleanup, which
      -- only has the macro's NAME to go on and needs to avoid deleting an
      -- unrelated macro that just happens to share it. Here that guard is
      -- redundant - OOCCheckMacroCreated above already confirmed this exact
      -- macro is GSE's for this exact sequence via its own bookkeeping, not
      -- a name/body guess - and it was actively harmful: any drift between
      -- the macro's real body and what CreateMacroString generates right
      -- now (e.g. after changing the macro's icon, which re-saves the
      -- macro via EditMacro) made the match silently fail, leaving the
      -- macro in place while GSE still printed a false success message.
      local sequenceName = GSE.GUIViewFrame.SequenceName
      if GetMacroInfo(sequenceName) == sequenceName then
        DeleteMacro(sequenceName)
        GSE.Print(L[" Removed Macro Button for "] .. sequenceName, GNOME)
      end
      GSE.GUIConfigureMacroButton(button)
      GSE.GUIViewFrame.panels[viewframe.ClassID .."," .. GSE.GUIViewFrame.SequenceName].Icon:SetImage(GSE.GetMacroIcon(tonumber(viewframe.ClassID), GSE.GUIViewFrame.SequenceName))
    end)
  else
    button:SetText(L["Create Macro Button"])
    attachTooltip(button, L["Create Macro Button"], L["Creates a real WoW macro for this sequence, so it can be dragged onto an action bar."])
    button:SetCallback("OnClick", function()
      GSE.OOCCheckMacroCreated(GSE.GUIViewFrame.SequenceName, true)
      GSE.GUIConfigureMacroButton(button)
      GSE.GUIViewFrame.panels[viewframe.ClassID .."," .. GSE.GUIViewFrame.SequenceName].Icon:SetImage(GSE.GetMacroIcon(tonumber(viewframe.ClassID), GSE.GUIViewFrame.SequenceName))
    end)
  end
  if GSE.isEmpty(GSE.GUIViewFrame.SequenceName) then
    button:SetDisabled(true)
  else
    button:SetDisabled(false)
  end
  -- ClassID == 0 means nothing is actually selected (clearpanels' deselected
  -- branch sets it to 0), not a real "Global" category - keep disabling
  -- there. The removed `or ClassID == GSE.GetCurrentClassID()` clause was
  -- backwards: it disabled this button specifically when viewing a sequence
  -- for the player's OWN class - the one case a macro button is obviously
  -- wanted (to drag onto your own action bar) - making the button look
  -- broken for the single most common browsing case.
  if GSE.GUIViewFrame.ClassID == 0 then
    button:SetDisabled(true)
  end

end
