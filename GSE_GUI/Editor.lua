local GNOME,_ = ...
local Statics = GSE.Static
local GSE = GSE

local AceGUI = LibStub("AceGUI-3.0")
local L = GSE.L
local libS = LibStub:GetLibrary("AceSerializer-3.0")
local libC = LibStub:GetLibrary("LibCompress")
local libCE = libC:GetAddonEncodeTable()

local otherversionlistboxvalue = ""
local default = 1
local raid = 1
local pvp = 1
local mythic = 1
local classid = GSE.GetCurrentClassID()

-- ============================================================================
-- ICON PICKER - a simple grid-of-icons popup, backed by the client's own
-- built-in GetNumMacroIcons()/GetMacroIconInfo(i) (3.3.5a has no bulk
-- GetMacroIcons() - that's a later-expansion convenience function; this is
-- the classic index-based pattern, same shape as GetSpellInfo/GetItemInfo).
-- GSE previously had no way to change a macro's icon at all: it was always
-- created with WoW's default icon index 1 and never touched again (see the
-- GSE.CreateMacroIcon fix in Storage.lua). This is the missing picker UI.
--
-- Deliberately kept inside Editor.lua rather than its own IconPicker.lua
-- file: a brand-new file added to an addon folder mid-session was found,
-- live, to never actually load via /reload alone (its own very first
-- statement - even a bare print() - never ran, while every statement worked
-- fine when replayed by hand via /run) - this WoW client only appears to
-- pick up a NEW file the addon's .toc didn't already reference at the
-- client's last full launch, not on a UI-only reload. Folding this into an
-- already-loaded file sidesteps that entirely.
-- ============================================================================
local iconPickerFrame = AceGUI:Create("Frame")
iconPickerFrame:Hide()
iconPickerFrame:SetTitle(L["Select Macro Icon"])
iconPickerFrame:SetStatusText(L["Click an icon to use it for this macro."])
iconPickerFrame:SetLayout("List")
iconPickerFrame:SetWidth(430)
iconPickerFrame:SetHeight(500)
iconPickerFrame:SetCallback("OnClose", function(widget) widget:Hide() end)
GSE.GUIIconPickerFrame = iconPickerFrame

local iconFilterBox = AceGUI:Create("EditBox")
iconFilterBox:SetLabel(L["Filter (e.g. fire, holy, sword)"])
iconFilterBox:SetFullWidth(true)
iconPickerFrame:AddChild(iconFilterBox)

local iconScrollContainer = AceGUI:Create("SimpleGroup")
iconScrollContainer:SetFullWidth(true)
iconScrollContainer:SetHeight(400)
iconScrollContainer:SetLayout("Fill")
iconPickerFrame:AddChild(iconScrollContainer)

local iconGrid = AceGUI:Create("ScrollFrame")
iconGrid:SetLayout("Flow")
iconScrollContainer:AddChild(iconGrid)

local iconPickerCallback = nil
local allMacroIcons = nil

local function LoadAllMacroIcons()
  if allMacroIcons then return allMacroIcons end
  allMacroIcons = {}
  for i = 1, GetNumMacroIcons() do
    allMacroIcons[i] = GetMacroIconInfo(i)
  end
  return allMacroIcons
end

-- GetNumMacroIcons() is 1000+ (every item/spell-derived icon the client
-- knows, not just the ~230-icon curated macro set) - building that many
-- AceGUI Icon widgets at once on every open would be a noticeable hitch, so
-- the unfiltered view is capped; typing a filter searches the full list.
local ICON_DISPLAY_CAP = 150

local function BuildIconPickerGrid(filterText)
  iconGrid:ReleaseChildren()
  LoadAllMacroIcons()
  filterText = filterText and filterText:lower() or ""
  local shown = 0
  for _, path in ipairs(allMacroIcons) do
    if filterText == "" and shown >= ICON_DISPLAY_CAP then break end
    if filterText == "" or tostring(path):lower():find(filterText, 1, true) then
      shown = shown + 1
      local btn = AceGUI:Create("Icon")
      btn:SetImage(path)
      btn:SetImageSize(30, 30)
      btn:SetWidth(38)
      btn:SetCallback("OnClick", function()
        if iconPickerCallback then iconPickerCallback(path) end
        iconPickerFrame:Hide()
      end)
      btn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
        GameTooltip:SetText(tostring(path), 1, 1, 1)
        GameTooltip:Show()
      end)
      btn:SetCallback("OnLeave", function() GameTooltip:Hide() end)
      iconGrid:AddChild(btn)
    end
  end
  GSE.Skin.WalkAceContainer(iconPickerFrame)
end

iconFilterBox:SetCallback("OnTextChanged", function(widget, event, text)
  BuildIconPickerGrid(text)
end)

--- Opens the icon picker. `callback(iconPath)` is called once, with the
--- chosen icon's texture path, when the player clicks an icon.
function GSE.GUIShowIconPicker(callback)
  iconPickerCallback = callback
  iconFilterBox:SetText("")
  BuildIconPickerGrid("")
  iconPickerFrame:Show()
end

local editframe = AceGUI:Create("Frame")
editframe:Hide()
GSE.GUIEditFrame = editframe
editframe.Sequence = {}
editframe.Sequence.MacroVersions = {}
editframe.SequenceName = ""
editframe.Default = 1
editframe.Raid = 1
editframe.PVP = 1
editframe.Mythic = 1
editframe.Dungeon = 1
editframe.Heroic = 1
editframe.Party = 1
editframe.ClassID = classid
editframe.save = false
editframe.SelectedTab = "group"

local fleft, fbottom, fwidth, fheight = editframe.frame:GetBoundsRect()
editframe.Left = fleft
editframe.Bottom = fbottom
editframe.Width = fwidth
editframe.Height = fheight

editframe:SetTitle(L["Sequence Editor"])
--editframe:SetStatusText(L["Gnome Sequencer: Sequence Editor."])
editframe:SetCallback("OnClose", function (self)
  editframe:Hide();
  if editframe.save then
    local event = {}
    event.action = "openviewer"
    table.insert(GSE.OOCQueue, event)
  else
    GSE.GUIShowViewer()
  end
end)
editframe:SetLayout("List")
-- Set resize bounds based on screen size
local maxHeight = GetScreenHeight() - 40
local maxWidth = GetScreenWidth() - 40
editframe.frame:SetMaxResize(maxWidth, maxHeight)
-- Set minimum size to prevent content overflow
editframe.frame:SetMinResize(600, 500)

-- Reset to a reasonable default size every time the editor is (re)built.
-- GSEOptions.editorWidth/Height (700x500 - see API/OneOffEvents.lua) is the
-- addon's own saved size for this window; fall back to the same 700x500 if
-- unset. Applied from GUIEditorPerformLayout, not an "OnShow" AceGUI
-- callback: the AceGUI-3.0 "Frame" widget type never fires an OnShow event
-- (only AceGUIContainer-BlizOptionsGroup and TabGroup tabs do), so a
-- callback registered under that name is silently never invoked.
local function resetEditorSize()
  local sizeWidth = math.min(GSEOptions.editorWidth or 700, maxWidth)
  local sizeHeight = math.min(GSEOptions.editorHeight or 500, maxHeight)
  editframe.frame:SetWidth(sizeWidth)
  editframe.frame:SetHeight(sizeHeight)
  editframe.Width = sizeWidth
  editframe.Height = sizeHeight
end

-- Live width/height reflow for the currently-drawn tab content.
--
-- AceGUI's Flow/List layout only recomputes a *relative*-width child's pixel
-- width on demand (WidgetBase:SetRelativeWidth), so plain SetFullWidth(true)
-- containers with SetRelativeWidth(...) children already reflow for free
-- whenever DoLayout() cascades down from editframe (see the OnSizeChanged
-- handler below). Height can't be expressed that way at all: this bundled
-- AceGUI-3.0 has no SetRelativeHeight (commented out in the library itself).
-- GUIDrawMetadataEditor/GUIDrawMacroEditor register their scrollable
-- containers in heightReflow (cleared and re-populated on every tab draw) so
-- a live resize can adjust them without a full ReleaseChildren()/rebuild.
-- widthReflow is kept for the same purpose in case a future tab needs a
-- fixed-width-sibling layout relative width can't express (see wrapRelative
-- below for the one case - Dropdown - that already needed a similar escape
-- hatch for a different reason).
editframe.widthReflow = {}
editframe.heightReflow = {}
local function applyContentReflow()
  for _, entry in ipairs(editframe.widthReflow) do
    if entry.widget and entry.widget.frame then
      pcall(entry.widget.SetWidth, entry.widget, math.max(entry.min or 100, editframe.Width - entry.offset))
    end
  end
  for _, entry in ipairs(editframe.heightReflow) do
    if entry.widget and entry.widget.frame then
      pcall(entry.widget.SetHeight, entry.widget, math.max(entry.min or 100, editframe.Height - entry.offset))
    end
  end
end

editframe.frame:SetScript("OnSizeChanged", function ()
  editframe.Left, editframe.Bottom, editframe.Width, editframe.Height = editframe.frame:GetBoundsRect()
  local screenHeight = GetScreenHeight()
  local screenWidth = GetScreenWidth()
  local maxHeight = screenHeight - 40  -- Leave some space at top/bottom
  local maxWidth = screenWidth - 40    -- Leave some space at sides
  
  -- Get current position
  local top = editframe.frame:GetTop()
  local bottom = editframe.frame:GetBottom()
  local left = editframe.frame:GetLeft()
  local right = editframe.frame:GetRight()
  
  -- Check if we need to constrain the size or reposition
  local needsResize = false
  local needsMove = false
  local newHeight = editframe.Height
  local newWidth = editframe.Width
  
  if editframe.Height > maxHeight then
    newHeight = maxHeight
    needsResize = true
  end
  
  if editframe.Width > maxWidth then
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
    editframe.frame:SetHeight(newHeight)
    editframe.frame:SetWidth(newWidth)
    editframe.Height = newHeight
    editframe.Width = newWidth
  end
  
  -- Reposition if off screen
  if needsMove then
    local newPoint = {}
    newPoint.x = math.min(math.max(left or 20, 20), screenWidth - newWidth - 20)
    newPoint.y = math.min(math.max(bottom or 20, 20), screenHeight - newHeight - 20)
    editframe.frame:ClearAllPoints()
    editframe.frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", newPoint.x, newPoint.y)
  end
  
  -- Update TabGroup height and layout
  if editframe.updateTabGroupHeight then
    editframe.updateTabGroupHeight()
  end
  applyContentReflow()
  editframe:DoLayout()

  -- Trigger a layout refresh on the TabGroup's content
  if editframe.ContentContainer and editframe.ContentContainer.LayoutFinished then
    editframe.ContentContainer:Fire("OnHeightSet")
  end

  -- Remember the settled size so the next GUIEditorPerformLayout (a new
  -- editor open, or switching to the "new version" tab) restores it instead
  -- of snapping back to whatever GSEOptions.editorWidth/Height held before
  -- this resize - resetEditorSize() and this persistence are two halves of
  -- the same behaviour, not a contradiction: without this, a manual resize
  -- would be silently discarded the next time the layout rebuilds.
  if GSEOptions then
    GSEOptions.editorWidth = editframe.Width
    GSEOptions.editorHeight = editframe.Height
  end
end)


local specdropdownvalue = editframe.SpecID

--- Attaches a GameTooltip to any AceGUI widget whose type genuinely fires
--- OnEnter/OnLeave ace-callback events (CheckBox, Button, Icon, etc. all do,
--- via their own Control_OnEnter/Control_OnLeave - verified per widget type
--- in the vendored AceGUI-3.0 source rather than assumed, since some other
--- AceGUI callback names are registered but never actually fired). `title`
--- is the tooltip header, `body` a wrapped description line under it.
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

--- Wraps a widget that has its own intrinsic native width - currently only
--- used for Dropdown - in a SetRelativeWidth Fill-layout SimpleGroup. Plain
--- SetRelativeWidth on a Dropdown itself stretches the widget's outer frame
--- but not the UIDropDownMenuTemplate innards it wraps (the selected-value
--- text and the dropdown arrow keep their own template-relative anchors), so
--- a wide relative-width Dropdown ends up with its label at the row's left
--- edge and its actual value/arrow control stranded far to the right. This
--- keeps the dropdown control itself at a comfortable, readable fixed width
--- while the wrapper - and so the column's position within the row - still
--- tracks the row's width elastically on resize.
local function wrapRelative(widget, fraction, fixedWidth)
  local wrapper = AceGUI:Create("SimpleGroup")
  -- Must be "Flow", not "Fill": Fill's layout handler (AceGUI-3.0.lua)
  -- force-overrides the child to content:GetWidth()/GetHeight() and
  -- SetAllPoints(content) - and content's own height is still undetermined
  -- at that point (this wrapper has no other layout pass to establish it
  -- first), so the dropdown's frame - and everything anchored off it, like
  -- its label and its native UIDropDownMenu innards - gets pinned to
  -- garbage bounds. Flow's non-relative-width branch just anchors the
  -- child TOPLEFT at its own SetWidth() size, with no resize, which is what
  -- this helper actually needs.
  wrapper:SetLayout("Flow")
  wrapper:SetRelativeWidth(fraction)
  widget:SetWidth(fixedWidth)
  wrapper:AddChild(widget)
  return wrapper
end

--- Flow's row layout aligns siblings by "alignoffset" (default: half of
--- each widget's own frame height - see AceGUI-3.0.lua's Flow layout
--- function), NOT a shared baseline. Dropdown/EditBox/MultiLineEditBox
--- reserve 18px above their own control for a label; Button/CheckBox don't.
--- Trusting Flow's own height-based default is fragile even between two
--- widgets of the SAME type, since their computed heights can differ for
--- reasons that have nothing to do with a label (text wrapping, a wrapper
--- group's own layout pass, pool-recycled widgets carrying a stale cached
--- height) - this is why the bug kept resurfacing one row at a time
--- (Playback Options' controls landing at different heights, then Use in
--- KeyRelease's checkboxes doing the same, even though every checkbox
--- there is the same widget type). Every widget added to one of this
--- editor's Flow rows should get an explicit alignoffset from HERE - by
--- type, never left for Flow to guess - so this is fixed for the row
--- itself, not just the specific widget that happened to visibly drift.
local ROW_ALIGNOFFSET_BY_TYPE = {
  Dropdown = 18,
  EditBox = 18,
  MultiLineEditBox = 18,
}
local function rowAlign(widget)
  widget.alignoffset = ROW_ALIGNOFFSET_BY_TYPE[widget.type] or 0
  return widget
end

--- Same safe wrapper pattern as wrapRelative (a Flow-layout SimpleGroup,
--- never Fill - see wrapRelative's own comment for why Dropdown needs this
--- at all), but FIXED-width instead of relative - keeps two dropdowns
--- packed snugly side by side at every window size instead of leaving an
--- ever-growing gap between them as the window widens. `pad` is the small
--- trailing margin (default 24px) kept after the dropdown. The wrapper
--- always carries a Dropdown, so its own alignoffset is always the
--- Dropdown/EditBox value from rowAlign above, regardless of the wrapper's
--- own (SimpleGroup) type.
local function wrapFixed(widget, widgetWidth, pad)
  local wrapper = AceGUI:Create("SimpleGroup")
  wrapper:SetLayout("Flow")
  wrapper:SetWidth(widgetWidth + (pad or 24))
  widget:SetWidth(widgetWidth)
  wrapper:AddChild(widget)
  wrapper.alignoffset = ROW_ALIGNOFFSET_BY_TYPE.Dropdown
  return wrapper
end

-- Section-divider heading for the Configuration tab. AceGUI's stock Heading
-- widget renders its label in plain white (GameFontNormal) - recoloured gold
-- to match every other section header already used throughout this addon
-- (e.g. the Options panel's "General Options"/"Editor Colours" headers), via
-- direct FontString access since Heading exposes no SetColor method of its
-- own (same pattern as Viewer.lua's talentslabel.label:SetWordWrap fix).
local function sectionHeading(text)
  local heading = AceGUI:Create("Heading")
  heading:SetText(text)
  heading:SetFullWidth(true)
  heading.label:SetTextColor(GSE.GUIGetColour(GSEOptions.EmphasisColour))
  return heading
end

function GSE.GUICreateEditorTabs()
  local tabl = {
    {
      text=L["Configuration"],
      value="config"
    },
  }
  for k,v in ipairs(editframe.Sequence.MacroVersions) do
    local insline = {}
    insline.text = tostring(k)
    insline.value = tostring(k)
    table.insert(tabl, insline)
  end
  table.insert(tabl,   {
      text=L["New"],
      value="new"
    }  )
  return tabl
end

function GSE.GUIEditorPerformLayout(frame)
  resetEditorSize()
  frame:ReleaseChildren()
  local headerGroup = AceGUI:Create("SimpleGroup")
  headerGroup:SetFullWidth(true)
  headerGroup:SetLayout("Flow")


  -- Icon comes BEFORE the name box, small and unlabelled, so the two read
  -- as one compound "identity" control (icon + name) rather than two
  -- separate, unrelated header widgets - the label text is dropped in
  -- favour of the tooltip below, same as every other field in this editor.
  -- Icon's own OnAcquire defaults to a 64x64 image (~89px tall frame with a
  -- label) - much taller than the name EditBox next to it, which was
  -- pushing the header row's real height past what callers of this
  -- function (e.g. updateTabGroupHeight's fixed offset) assumed, letting
  -- the icon's bottom edge bleed down into the first row of tab content.
  local iconpicker = AceGUI:Create("Icon")
  iconpicker:SetImageSize(24, 24)
  iconpicker:SetWidth(30)
  iconpicker.frame:RegisterForDrag("LeftButton")
  iconpicker.frame:SetScript("OnDragStart", function()
    if not GSE.isEmpty(editframe.SequenceName) then
      PickupMacro(editframe.SequenceName)
    end
  end)
  -- Click to choose a new icon. GSE.CreateMacroIcon (Storage.lua) already
  -- applies editframe.Sequence.Icon to the underlying macro on save/re-save
  -- - this click handler is the only piece that was actually missing.
  iconpicker:SetCallback("OnClick", function()
    if GSE.GUIShowIconPicker then
      GSE.GUIShowIconPicker(function(chosenIcon)
        editframe.Sequence.Icon = chosenIcon
        iconpicker:SetImage(chosenIcon)
      end)
    end
  end)
  iconpicker:SetImage(GSEOptions.DefaultDisabledMacroIcon)
  headerGroup:AddChild(iconpicker)
  editframe.iconpicker = iconpicker
  attachTooltip(iconpicker, L["Macro Icon"], L["Click to choose a new icon. Drag to your action bar to create a macro button."])

  local iconnamespacer = AceGUI:Create("Label")
  iconnamespacer:SetWidth(6)
  headerGroup:AddChild(iconnamespacer)

  local nameeditbox = AceGUI:Create("EditBox")
  nameeditbox:SetLabel(L["Sequence Name"])
  nameeditbox:SetWidth(250)
  nameeditbox:SetCallback("OnTextChanged", function() editframe.SequenceName = nameeditbox:GetText(); end)
  nameeditbox:DisableButton( true)
  nameeditbox:SetText(editframe.SequenceName)
  editframe.nameeditbox = nameeditbox
  headerGroup:AddChild(nameeditbox)
  attachTooltip(nameeditbox, L["Sequence Name"], L["The macro's internal name in Gnome Sequencer. Renaming it here creates a new entry on Save rather than renaming the existing one."])

  frame:AddChild(headerGroup)

  local tabgrp =  AceGUI:Create("TabGroup")
  tabgrp:SetLayout("Flow")
  tabgrp:SetTabs(GSE.GUICreateEditorTabs())
  editframe.ContentContainer = tabgrp


  tabgrp:SetCallback("OnGroupSelected",  function (container, event, group)
    GSE.GUISelectEditorTab(container, event, group)
  end)
  tabgrp:SetFullWidth(true)
  -- Don't use SetFullHeight(true) as it causes unbounded growth
  -- Instead, calculate available height after accounting for header and buttons
  local function updateTabGroupHeight()
    local availableHeight = editframe.Height - 150 -- Account for header, buttons, and padding
    tabgrp:SetHeight(math.max(300, availableHeight)) -- Minimum height of 300
  end
  updateTabGroupHeight()
  editframe.updateTabGroupHeight = updateTabGroupHeight

  tabgrp:SelectTab("config")
  frame:AddChild(tabgrp)



  local editOptionsbutton = AceGUI:Create("Button")
  editOptionsbutton:SetText(L["Options"])
  editOptionsbutton:SetWidth(150)
  editOptionsbutton:SetCallback("OnClick", function() GSE.OpenOptionsPanel() end)
  attachTooltip(editOptionsbutton, L["Options"], L["Opens the Gnome Sequencer options panel (colours, defaults, and other addon-wide settings)."])

  local transbutton = AceGUI:Create("Button")
  transbutton:SetText(L["Send"])
  transbutton:SetWidth(150)
  transbutton:SetCallback("OnClick", function() GSE.GUIShowTransmissionGui(editframe.ClassID.. "," ..editframe.SequenceName) end)
  attachTooltip(transbutton, L["Send"], L["Sends this macro to another player directly over the addon channel."])

  local editButtonGroup = AceGUI:Create("SimpleGroup")
  editButtonGroup:SetFullWidth(true)
  editButtonGroup:SetLayout("Flow")
  editButtonGroup:SetHeight(15)

  local savebutton = AceGUI:Create("Button")
  savebutton:SetText(L["Save"])
  savebutton:SetWidth(150)
  savebutton:SetCallback("OnClick", function()
    editframe.Sequence.ManualIntervention = true
    nameeditbox:SetText(nameeditbox:GetText())
    editframe.SequenceName = nameeditbox:GetText()
    GSE.GUIUpdateSequenceDefinition(editframe.ClassID, editframe.SequenceName, editframe.Sequence)
    editframe.save = true
  end)
  attachTooltip(savebutton, L["Save"], L["Saves this macro (all versions) and closes the editor."])
  editButtonGroup:AddChild(savebutton)

  local delbutton = AceGUI:Create("Button")
  delbutton:SetText(L["Delete"])
  delbutton:SetWidth(150)
  delbutton:SetCallback("OnClick", function() GSE.GUIDeleteSequence(editframe.ClassID, editframe.SequenceName) end)
  attachTooltip(delbutton, L["Delete"], L["Permanently deletes this entire macro, all versions included. This cannot be undone."])
  editButtonGroup:AddChild(delbutton)

  editButtonGroup:AddChild(transbutton)
  editButtonGroup:AddChild(editOptionsbutton)
  frame:AddChild(editButtonGroup)

  GSE.Skin.WalkAceContainer(frame)
end

function GSE.GetVersionList()
  local tabl = {}
  classid = tonumber(classid)
  for k,v in ipairs(editframe.Sequence.MacroVersions) do
    tabl[tostring(k)] = tostring(k)
  end
  return tabl
end

function GSE:GUIDrawMetadataEditor(container)
  -- Default frame size = 700 w x 500 h

  editframe.iconpicker:SetImage(GSE.GetMacroIcon(editframe.ClassID, editframe.SequenceName))


  local scrollcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
  scrollcontainer:SetFullWidth(true)
  -- Better height calculation that accounts for minimum space needed
  local availableHeight = math.max(100, editframe.Height - 280) -- Ensure minimum height
  scrollcontainer:SetHeight(availableHeight)
  scrollcontainer:SetLayout("Fill") -- important!

  local contentcontainer = AceGUI:Create("ScrollFrame")
  -- Ensure the scroll frame doesn't grow beyond available space
  contentcontainer:SetAutoAdjustHeight(false)
  scrollcontainer:AddChild(contentcontainer)
  table.insert(editframe.heightReflow, { widget = scrollcontainer, offset = 280, min = 100 })

  -- Layout, top to bottom: Identity (what this macro is) -> Version
  -- Assignments (the actual functional configuration - which macro version
  -- plays in which content, the thing edited most often) -> Documentation
  -- (author/help notes, auxiliary metadata). Each section gets its own
  -- Heading divider so the tab reads as organised sections instead of one
  -- undifferentiated wall of fields, and every row is either a matched pair
  -- or a single full-width field - never one dropdown stranded alone next
  -- to dead space (the old layout's Party row did exactly that).

  contentcontainer:AddChild(sectionHeading(L["Identity"]))

  local metasimplegroup = AceGUI:Create("SimpleGroup")
  metasimplegroup:SetLayout("Flow")
  metasimplegroup:SetFullWidth(true)

  local speciddropdown = AceGUI:Create("Dropdown")
  speciddropdown:SetLabel(L["Specialisation / Class ID"])
  speciddropdown:SetList(GSE.GetSpecNames())
  speciddropdown:SetCallback("OnValueChanged", function (obj,event,key)
    local sid = Statics.SpecIDHashList[key]
    specdropdownvalue = key;
    editframe.SpecID = sid
    editframe.Sequence.SpecID = sid

    if tonumber(sid) > 12 then
      editframe.ClassID = GSE.GetClassIDforSpec(tonumber(sid))
    else
      editframe.ClassID = tonumber(sid)
    end
  end)
  metasimplegroup:AddChild(wrapFixed(speciddropdown, 200))
  speciddropdown:SetValue(Statics.wotlkSpecIDList[editframe.Sequence.SpecID])
  attachTooltip(speciddropdown, L["Specialisation / Class ID"], L["Which class and spec this macro is written for. Also determines the default archetype used elsewhere in this addon."])

  -- Talents was previously 48% of the FULL row width (very wide on a
  -- resized window, badly unbalanced against Specialisation's fixed ~220px
  -- neighbour) - fixed width instead, same wrapFixed-style snug pairing as
  -- the dropdown rows below. Consistent with the numbered tab's rows: a
  -- fixed-width field plus a tooltip, no permanent inline description text.
  local talentseditbox = AceGUI:Create("EditBox")
  talentseditbox:SetLabel(L["Talents"])
  talentseditbox:SetWidth(360)
  talentseditbox:DisableButton( true)
  metasimplegroup:AddChild(rowAlign(talentseditbox))
  talentseditbox:SetText(editframe.Sequence.Talents)
  talentseditbox:SetCallback("OnTextChanged", function (obj,event,key)
    editframe.Sequence.Talents = key
  end)
  attachTooltip(talentseditbox, L["Talents"], L["A short note on the talent build this macro assumes (e.g. a Wowhead link or point spread). Shown under the macro's name in the Sequence Viewer - free text, not read by the game."])

  contentcontainer:AddChild(metasimplegroup)

  contentcontainer:AddChild(sectionHeading(L["Version Assignments"]))

  -- Default stands alone, full-width: it's the fallback every other slot
  -- below either overrides or defers to, not a peer of equal weight - the
  -- extra visual emphasis communicates that.
  local defgroup1 = AceGUI:Create("SimpleGroup")
  defgroup1:SetLayout("Flow")
  defgroup1:SetFullWidth(true)

  local defaultdropdown = AceGUI:Create("Dropdown")
  defaultdropdown:SetLabel(L["Default Version"])
  defaultdropdown:SetList(GSE.GetVersionList())
  defaultdropdown:SetValue(tostring(editframe.Default))
  defgroup1:AddChild(wrapFixed(defaultdropdown, 80))
  defaultdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    editframe.Sequence.Default = tonumber(key)
    editframe.Default = tonumber(key)
  end)
  attachTooltip(defaultdropdown, L["Default Version"], L["The macro version used whenever none of the more specific overrides below apply."])
  contentcontainer:AddChild(defgroup1)

  -- Dungeon/Heroic: same content, two difficulties - a natural pair.
  local defgroup2 = AceGUI:Create("SimpleGroup")
  defgroup2:SetLayout("Flow")
  defgroup2:SetFullWidth(true)

  local dungeondropdown = AceGUI:Create("Dropdown")
  dungeondropdown:SetLabel(L["Dungeon"])
  dungeondropdown:SetList(GSE.GetVersionList())
  dungeondropdown:SetValue(tostring(editframe.Dungeon))
  defgroup2:AddChild(wrapFixed(dungeondropdown, 80))
  dungeondropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Dungeon = nil
    else
      editframe.Sequence.Dungeon = tonumber(key)
      editframe.Dungeon = tonumber(key)
    end
  end)
  attachTooltip(dungeondropdown, L["Dungeon"], L["Version used while inside a 5-player dungeon. Leave on the Default Version to not override it."])

  local heroicdropdown = AceGUI:Create("Dropdown")
  heroicdropdown:SetLabel(L["Heroic"])
  heroicdropdown:SetList(GSE.GetVersionList())
  heroicdropdown:SetValue(tostring(editframe.Heroic))
  defgroup2:AddChild(wrapFixed(heroicdropdown, 80))
  heroicdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Heroic = nil
    else
      editframe.Sequence.Heroic = tonumber(key)
      editframe.Heroic = tonumber(key)
    end
  end)
  attachTooltip(heroicdropdown, L["Heroic"], L["Version used while inside a Heroic-difficulty dungeon. Leave on the Default Version to not override it."])
  contentcontainer:AddChild(defgroup2)

  -- Raid/Mythic: both raid-tier content - the other natural pair.
  local defgroup3 = AceGUI:Create("SimpleGroup")
  defgroup3:SetLayout("Flow")
  defgroup3:SetFullWidth(true)

  local raiddropdown = AceGUI:Create("Dropdown")
  raiddropdown:SetLabel(L["Raid"])
  raiddropdown:SetList(GSE.GetVersionList())
  raiddropdown:SetValue(tostring(editframe.Raid))
  defgroup3:AddChild(wrapFixed(raiddropdown, 80))
  raiddropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Raid = nil
    else
      editframe.Sequence.Raid = tonumber(key)
      editframe.Raid = tonumber(key)
    end
  end)
  attachTooltip(raiddropdown, L["Raid"], L["Version used while inside a raid instance. Leave on the Default Version to not override it."])

  local mythicdropdown = AceGUI:Create("Dropdown")
  mythicdropdown:SetLabel(L["Mythic"])
  mythicdropdown:SetList(GSE.GetVersionList())
  mythicdropdown:SetValue(tostring(editframe.Mythic))
  mythicdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Mythic = nil
    else
      editframe.Sequence.Mythic = tonumber(key)
      editframe.Mythic = tonumber(key)
    end
  end)
  defgroup3:AddChild(wrapFixed(mythicdropdown, 80))
  attachTooltip(mythicdropdown, L["Mythic"], L["Version used for Mythic-difficulty content. Leave on the Default Version to not override it."])
  contentcontainer:AddChild(defgroup3)

  -- PVP/Party: neither is PvE raid/dungeon content - the remaining pair.
  local defgroup4 = AceGUI:Create("SimpleGroup")
  defgroup4:SetLayout("Flow")
  defgroup4:SetFullWidth(true)

  local pvpdropdown = AceGUI:Create("Dropdown")
  pvpdropdown:SetLabel(L["PVP"])
  pvpdropdown:SetList(GSE.GetVersionList())
  pvpdropdown:SetValue(tostring(editframe.PVP))
  defgroup4:AddChild(wrapFixed(pvpdropdown, 80))
  pvpdropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.PVP = nil
    else
      editframe.Sequence.PVP = tonumber(key)
      editframe.PVP = tonumber(key)
    end
  end)
  attachTooltip(pvpdropdown, L["PVP"], L["Version used while in a Battleground or Arena. Leave on the Default Version to not override it."])

  local partydropdown = AceGUI:Create("Dropdown")
  partydropdown:SetLabel(L["Party"])
  partydropdown:SetList(GSE.GetVersionList())
  partydropdown:SetValue(tostring(editframe.Party))
  defgroup4:AddChild(wrapFixed(partydropdown, 80))
  partydropdown:SetCallback("OnValueChanged", function (obj,event,key)
    if editframe.Sequence.Default == tonumber(key) then
      editframe.Sequence.Party = nil
    else
      editframe.Sequence.Party = tonumber(key)
      editframe.Party = tonumber(key)
    end
  end)
  attachTooltip(partydropdown, L["Party"], L["Version used while in a normal party outside a dungeon. Leave on the Default Version to not override it."])
  contentcontainer:AddChild(defgroup4)

  contentcontainer:AddChild(sectionHeading(L["Documentation"]))

  -- Freed-up vertical space (Party no longer wastes half a row, and this
  -- section moved after the version dropdowns instead of splitting them in
  -- two) goes toward a taller notes box - 6 lines instead of the old 4.
  local helpeditbox = AceGUI:Create("MultiLineEditBox")
  helpeditbox:SetLabel(L["Help Information"])
  helpeditbox:SetWidth(250)
  helpeditbox:DisableButton( true)
  helpeditbox:SetNumLines(6)
  helpeditbox:SetFullWidth(true)
  if not GSE.isEmpty(editframe.Sequence.Help) then
    helpeditbox:SetText(editframe.Sequence.Help)
  end
  helpeditbox:SetCallback("OnTextChanged", function (obj,event,key)
    editframe.Sequence.Help = key
  end)
  attachTooltip(helpeditbox, L["Help Information"], L["Free-form notes on what this macro does and how to use it. Shown under its name in the Sequence Viewer."])
  contentcontainer:AddChild(helpeditbox)

  local helpgroup1 = AceGUI:Create("SimpleGroup")
  helpgroup1:SetLayout("Flow")
  helpgroup1:SetFullWidth(true)

  local helplinkeditbox = AceGUI:Create("EditBox")
  helplinkeditbox:SetLabel(L["Help Link"])
  -- 0.49 + a 0.02-relative divider (below) + Author's 0.49 sum to exactly
  -- 1.0, so this row's own right edge lines up with the full-width Help
  -- Information box above it - the old 0.48+0.48 (summing to 0.96) left
  -- this row visibly narrower than the box above it. Same pattern already
  -- used for KeyPress/PreMacro in the numbered tab.
  helplinkeditbox:SetRelativeWidth(0.49)
  helplinkeditbox:DisableButton( true)
  if not GSE.isEmpty(editframe.Sequence.Helplink) then
    helplinkeditbox:SetText(editframe.Sequence.Helplink)
  end
  helplinkeditbox:SetCallback("OnTextChanged", function (obj,event,key)
    editframe.Sequence.Helplink = key
  end)
  attachTooltip(helplinkeditbox, L["Help Link"], L["An optional web link with more information. Click it in the Sequence Viewer to open it."])
  helpgroup1:AddChild(helplinkeditbox)

  local helplinkauthorspacer = AceGUI:Create("Label")
  helplinkauthorspacer:SetRelativeWidth(0.02)
  helpgroup1:AddChild(helplinkauthorspacer)

  local authoreditbox = AceGUI:Create("EditBox")
  authoreditbox:SetLabel(L["Author"])
  authoreditbox:SetRelativeWidth(0.49)
  authoreditbox:DisableButton( true)
  if not GSE.isEmpty(editframe.Sequence.Author) then
    authoreditbox:SetText(editframe.Sequence.Author)
  end
  authoreditbox:SetCallback("OnTextChanged", function (obj,event,key)
    editframe.Sequence.Author = key
  end)
  attachTooltip(authoreditbox, L["Author"], L["Who wrote this macro. For credit/reference only - has no effect on how it runs."])
  helpgroup1:AddChild(authoreditbox)

  contentcontainer:AddChild(helpgroup1)

  -- Defensive: ScrollFrame's own OnAcquire already resets scroll to 0, but
  -- switching tabs/sequences has been observed leaving this tab's first row
  -- clipped behind the top of the scroll clip region on some paths - an
  -- explicit reset here costs nothing and closes off that whole class of
  -- stale-scroll-position bug regardless of the exact trigger.
  contentcontainer:SetScroll(0)

  container:AddChild(scrollcontainer)
end

function GSE:GUIDrawMacroEditor(container, version)
  version = tonumber(version)
  if GSE.isEmpty(editframe.Sequence.MacroVersions[version]) then
    editframe.Sequence.MacroVersions[version] = {}
    editframe.Sequence.MacroVersions[version].PreMacro = {}
    editframe.Sequence.MacroVersions[version].PostMacro = {}
    editframe.Sequence.MacroVersions[version].KeyPress = {}
    editframe.Sequence.MacroVersions[version].KeyRelease = {}
    editframe.Sequence.MacroVersions[version].StepFunction = "Sequential"
    editframe.Sequence.MacroVersions[version][1] = "/say Hello"
  end

  editframe.Sequence.MacroVersions[version] = GSE.TranslateSequence(editframe.Sequence.MacroVersions[version], "From Editor")

  local layoutcontainer = AceGUI:Create("SimpleGroup")
  layoutcontainer:SetFullWidth(true)
  -- Use same height calculation as scrollcontainer to ensure consistency
  local availableHeight = math.max(100, editframe.Height - 280) -- Ensure minimum height
  layoutcontainer:SetHeight(availableHeight)
  layoutcontainer:SetLayout("Flow") -- important!

  local scrollcontainer = AceGUI:Create("SimpleGroup") -- "InlineGroup" is also good
  -- The Use/Resets checkboxes used to live in a separate fixed-width side
  -- column here, which forced this to reserve room instead of tracking the
  -- window width directly. They're now inlined into the rows they actually
  -- affect (see linegroup1 and the "Use in KeyRelease" group below), so this
  -- can just be a normal full-width, live-reflowing container.
  scrollcontainer:SetFullWidth(true)
  -- 50 less than layoutcontainer's own budget (below), reserving room for
  -- the "Use in KeyRelease" row that sits below this scroll area, outside
  -- it - see the comment above usegroup for why it can't live inside the
  -- ScrollFrame with everything else. usegroup is one Heading (~18px) plus
  -- one row of checkboxes (~24px) once it's allowed to auto-size instead of
  -- sitting at SimpleGroup's fixed 100px default (see its own comment) - 50
  -- covers that with a little margin instead of reserving for the old,
  -- much taller default and leaving the scroll area shorter than it needs
  -- to be.
  local scrollHeight = math.max(100, editframe.Height - 330)
  scrollcontainer:SetHeight(scrollHeight)
  scrollcontainer:SetLayout("Fill") -- important!
  table.insert(editframe.heightReflow, { widget = scrollcontainer, offset = 330, min = 100 })
  table.insert(editframe.heightReflow, { widget = layoutcontainer, offset = 280, min = 100 })

  local contentcontainer = AceGUI:Create("ScrollFrame")
  -- Ensure the scroll frame doesn't grow beyond available space
  contentcontainer:SetAutoAdjustHeight(false)
  scrollcontainer:AddChild(contentcontainer)

  contentcontainer:AddChild(sectionHeading(L["Playback Options"]))

  local linegroup1 = AceGUI:Create("SimpleGroup")
  linegroup1:SetLayout("Flow")
  linegroup1:SetFullWidth(true)
  linegroup1:SetAutoAdjustHeight(false)

  local stepdropdown = AceGUI:Create("Dropdown")
  stepdropdown:SetLabel(L["Step Function"])
  stepdropdown:SetList({
    ["Sequential"] = L["Sequential (1 2 3 4)"],
    ["Priority"] = L["Priority List (1 12 123 1234)"],
    ["Random"] = L["Random (unpredictable order)"],
  })
  if GSE.isEmpty(editframe.Sequence.MacroVersions[version].StepFunction) then
    editframe.Sequence.MacroVersions[version].StepFunction = "Sequential"
  end
  stepdropdown:SetValue(editframe.Sequence.MacroVersions[version].StepFunction)
  stepdropdown:SetCallback("OnValueChanged", function (sel, object, value)
      editframe.Sequence.MacroVersions[version].StepFunction = value
    end)
  linegroup1:AddChild(wrapFixed(stepdropdown, 230))
  attachTooltip(stepdropdown, L["Step Function"], L["Controls the order spells in the Sequence box are cast: Sequential plays them 1, 2, 3... in order; Priority List re-checks from the top each time and casts the first one available; Random picks an available spell unpredictably."])

  local spacerlabel1 = AceGUI:Create("Label")
  spacerlabel1:SetWidth(5)
  linegroup1:AddChild(rowAlign(spacerlabel1))

  local looplimit = AceGUI:Create("EditBox")
  looplimit:SetLabel(L["Inner Loop Limit"])
  looplimit:DisableButton(true)
  looplimit:SetMaxLetters(4)
  looplimit:SetWidth(100)

  linegroup1:AddChild(rowAlign(looplimit))
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].LoopLimit) then
    looplimit:SetText(tonumber(editframe.Sequence.MacroVersions[version].LoopLimit))
  end
  looplimit.editbox:SetNumeric()
  looplimit:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].LoopLimit = value
  end)
  attachTooltip(looplimit, L["Inner Loop Limit"], L["Optional cap on how many times an inner /loop block repeats before moving on. Leave blank for unlimited."])

  local spacerlabel7 = AceGUI:Create("Label")
  spacerlabel7:SetWidth(5)
  linegroup1:AddChild(rowAlign(spacerlabel7))

  -- Button and CheckBox have no label reserved above them (unlike
  -- Dropdown/EditBox's 18px), so their own top IS their clickable area -
  -- rowAlign's default (alignoffset 0) lands that 18px below the row's
  -- start, level with the Dropdown/EditBox controls rather than their
  -- labels.
  local delversionbutton = AceGUI:Create("Button")
  delversionbutton:SetText(L["Delete Version"])
  delversionbutton:SetWidth(150)
  delversionbutton:SetCallback("OnClick", function()
    GSE.GUIDeleteVersion(version)
  end)
  linegroup1:AddChild(rowAlign(delversionbutton))
  attachTooltip(delversionbutton, L["Delete Version"], L["Permanently deletes this macro version. This cannot be undone."])

  -- Combat governs whether *this whole macro version* resets when you leave
  -- combat, i.e. it's a property of the step/sequence behaviour controlled
  -- by the rest of this row - not of any one text box below - so it lives
  -- here rather than off in its own side panel.
  local RESET_TOOLTIP_BODY = L["Checked: always reset. Unchecked: never reset. Grey (default): use the global 'Reset Macro when out of combat' option."]
  local combatresetcheckbox = AceGUI:Create("CheckBox")
  combatresetcheckbox:SetType("checkbox")
  combatresetcheckbox:SetWidth(90)
  combatresetcheckbox:SetTriState(true)
  combatresetcheckbox:SetLabel(L["Combat"])
  combatresetcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Combat)
  combatresetcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Combat = value
  end)
  rowAlign(combatresetcheckbox)
  attachTooltip(combatresetcheckbox, L["Combat"],
    L["Reset this macro version's sequence position when you leave combat."] .. "\n" .. RESET_TOOLTIP_BODY)
  linegroup1:AddChild(combatresetcheckbox)

  contentcontainer:AddChild(linegroup1)

  contentcontainer:AddChild(sectionHeading(L["Macro Content"]))

  local linegroup2 = AceGUI:Create("SimpleGroup")
  linegroup2:SetLayout("Flow")
  linegroup2:SetFullWidth(true)
  -- SimpleGroup defaults to a fixed 100px height on acquire and only ever
  -- corrects that from its real (Flow-computed) content height when
  -- noAutoHeight is unset (see AceGUIContainer-SimpleGroup.lua's
  -- LayoutFinished). KeyPress/PreMacro are 6-line MultiLineEditBoxes -
  -- taller than 100px - so disabling auto-height here (as this used to do)
  -- left the group stuck at 100px while its content rendered taller,
  -- and the Sequence box/label right below it got positioned on top of
  -- KeyPress's own bottom lines. Leaving auto-height on lets Flow report
  -- this row's true height instead.

  local KeyPressbox = AceGUI:Create("MultiLineEditBox")
  KeyPressbox:SetLabel(L["KeyPress"])
  KeyPressbox:SetNumLines(6)
  KeyPressbox:DisableButton(true)
  -- 0.49 + a 0.02-relative divider (below) + PreMacro's 0.49 sum to exactly
  -- 1.0, so this pair's own right edge (PreMacro's) lines up with the
  -- full-width Sequence box's right edge below.
  KeyPressbox:SetRelativeWidth(0.49)
  KeyPressbox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(KeyPressbox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].KeyPress) then
    KeyPressbox:SetText(table.concat(editframe.Sequence.MacroVersions[version].KeyPress, "\n"))
  end
  KeyPressbox:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].KeyPress = GSE.SplitMeIntolines(value)
  end)
  linegroup2:AddChild(KeyPressbox)
  attachTooltip(KeyPressbox, L["KeyPress"], L["Spells or commands cast once when the key is first pressed, before the main Sequence below. Most macros leave this empty."])

  -- Relative, not a fixed pixel width: AceGUI-3.0's Flow layout computes
  -- each "relative" child's width independently as fraction * row width, so
  -- KeyPress(0.49) + divider + PreMacro(0.49) must sum to exactly 1.0 of the
  -- row width for their combined right edge to match the full-width Sequence
  -- box below. A fixed-pixel divider left them short by a growing amount as
  -- the window widened; a relative divider keeps the sum exact at any size.
  local spacerlabel2 = AceGUI:Create("Label")
  spacerlabel2:SetRelativeWidth(0.02)
  linegroup2:AddChild(spacerlabel2)

  local PreMacro = AceGUI:Create("MultiLineEditBox")
  PreMacro:SetLabel(L["PreMacro"])
  PreMacro:SetNumLines(6)
  PreMacro:DisableButton(true)
  PreMacro:SetRelativeWidth(0.49)
  PreMacro.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(PreMacro) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].PreMacro) then
    PreMacro:SetText(table.concat(editframe.Sequence.MacroVersions[version].PreMacro, "\n"))
  end
  PreMacro:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].PreMacro = GSE.SplitMeIntolines(value)
  end)
  linegroup2:AddChild(PreMacro)
  attachTooltip(PreMacro, L["PreMacro"], L["Commands run once before every cast in the Sequence below, such as target checks. Rarely needed."])

  contentcontainer:AddChild(linegroup2)

  -- A little breathing room before the Sequence box, matching the gap the
  -- section headings already give the rows around them.
  local vspacer1 = AceGUI:Create("Label")
  vspacer1:SetFullWidth(true)
  vspacer1:SetHeight(6)
  contentcontainer:AddChild(vspacer1)

  local spellbox = AceGUI:Create("MultiLineEditBox")
  spellbox:SetLabel(L["Sequence"])
  spellbox:SetNumLines(14)
  spellbox:DisableButton(true)
  spellbox:SetFullWidth(true)
  spellbox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(KeyPressbox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version]) then
    spellbox:SetText(table.concat(editframe.Sequence.MacroVersions[version], "\n"))
  end
  spellbox:SetCallback("OnTextChanged", function (sel, object, value)
    for k,v in ipairs(editframe.Sequence.MacroVersions[version]) do
      editframe.Sequence.MacroVersions[version][k] = nil
    end
    local newpairs = GSE.SplitMeIntolines(value)
    for k,v in ipairs(newpairs) do
      editframe.Sequence.MacroVersions[version][k] = v
    end
  end)
  contentcontainer:AddChild(spellbox)
  attachTooltip(spellbox, L["Sequence"], L["The macro's main spell rotation - one entry per line, played back in the order set by Step Function above. This is the core of the macro."])

  local linegroup3 = AceGUI:Create("SimpleGroup")
  linegroup3:SetLayout("Flow")
  linegroup3:SetFullWidth(true)
  -- See the matching comment on linegroup2 above - same fix, same reason
  -- (KeyRelease/PostMacro are also 6-line MultiLineEditBoxes).

  local KeyReleasebox = AceGUI:Create("MultiLineEditBox")
  KeyReleasebox:SetLabel(L["KeyRelease"])
  KeyReleasebox:SetNumLines(6)
  KeyReleasebox:DisableButton(true)
  KeyReleasebox:SetRelativeWidth(0.49)
  KeyReleasebox.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(KeyPressbox) end)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].KeyRelease) then
    KeyReleasebox:SetText(table.concat(editframe.Sequence.MacroVersions[version].KeyRelease, "\n"))
  end
  KeyReleasebox:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].KeyRelease = GSE.SplitMeIntolines(value)
  end)
  linegroup3:AddChild(KeyReleasebox)
  attachTooltip(KeyReleasebox, L["KeyRelease"], L["Spells or commands cast when the key is released, such as trinkets or equipment swaps enabled by the checkboxes below. Most macros leave this empty."])

  local spacerlabel3 = AceGUI:Create("Label")
  spacerlabel3:SetRelativeWidth(0.02)
  linegroup3:AddChild(spacerlabel3)

  local PostMacro = AceGUI:Create("MultiLineEditBox")
  PostMacro:SetLabel(L["PostMacro"])
  PostMacro:SetNumLines(6)
  PostMacro:DisableButton(true)
  PostMacro:SetRelativeWidth(0.49)
  PostMacro.editBox:SetScript( "OnLeave",  function() GSE.GUIParseText(PostMacro) end)
  linegroup3:AddChild(PostMacro)
  if not GSE.isEmpty(editframe.Sequence.MacroVersions[version].PostMacro) then
    PostMacro:SetText(table.concat(editframe.Sequence.MacroVersions[version].PostMacro, "\n"))
  end
  PostMacro:SetCallback("OnTextChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].PostMacro = GSE.SplitMeIntolines(value)
  end)
  attachTooltip(PostMacro, L["PostMacro"], L["Commands run once after every cast in the Sequence above. Rarely needed."])
  contentcontainer:AddChild(linegroup3)

  -- These checkboxes control which equipment slots get folded into the
  -- KeyRelease line directly above (see their tooltip text), so the group
  -- lives right under it instead of in an unrelated side panel far away.
  -- Added to layoutcontainer below, NOT contentcontainer/scrollcontainer:
  -- putting it inside the ScrollFrame with everything else meant it was
  -- scrolled out of view at the default window size (700x500 has no room
  -- left after KeyPress/Sequence/KeyRelease) - a real regression, not just
  -- "needs scrolling", since a whole checkbox group with no visible trace
  -- of its own existence isn't discoverable. Living below the scroll area
  -- keeps it always visible while staying directly under KeyRelease.
  local USE_TOOLTIP_BODY = L["Checked: always include. Unchecked: never include. Grey (default): use this slot's global 'Use ... in KeyRelease' option."]

  local usegroup = AceGUI:Create("SimpleGroup")
  usegroup:SetLayout("Flow")
  usegroup:SetFullWidth(true)
  -- Same fixed-100px-default issue as linegroup2/3 above (see their
  -- comments) - disabling auto-height with no explicit SetHeight() left
  -- this whole section reserving a flat 100px no matter how tall its
  -- actual content (one heading + one row of checkboxes, ~50px) really is.
  -- Leaving auto-height on shrinks it to fit exactly.

  usegroup:AddChild(sectionHeading(L["Use in KeyRelease"]))

  local headcheckbox = AceGUI:Create("CheckBox")
  headcheckbox:SetType("checkbox")
  headcheckbox:SetWidth(90)
  headcheckbox:SetTriState(true)
  headcheckbox:SetLabel(L["Head"])
  headcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Head = value
  end)
  headcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Head)
  attachTooltip(headcheckbox, L["Head"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(headcheckbox))

  local neckcheckbox = AceGUI:Create("CheckBox")
  neckcheckbox:SetType("checkbox")
  neckcheckbox:SetWidth(90)
  neckcheckbox:SetTriState(true)
  neckcheckbox:SetLabel(L["Neck"])
  neckcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Neck = value
  end)
  neckcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Neck)
  attachTooltip(neckcheckbox, L["Neck"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(neckcheckbox))

  local beltcheckbox = AceGUI:Create("CheckBox")
  beltcheckbox:SetType("checkbox")
  beltcheckbox:SetWidth(90)
  beltcheckbox:SetTriState(true)
  beltcheckbox:SetLabel(L["Belt"])
  beltcheckbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Belt = value
  end)
  beltcheckbox:SetValue(editframe.Sequence.MacroVersions[version].Belt)
  attachTooltip(beltcheckbox, L["Belt"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(beltcheckbox))

  local ring1checkbox = AceGUI:Create("CheckBox")
  ring1checkbox:SetType("checkbox")
  ring1checkbox:SetWidth(90)
  ring1checkbox:SetTriState(true)
  ring1checkbox:SetLabel(L["Ring 1"])
  ring1checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Ring1 = value
  end)
  ring1checkbox:SetValue(editframe.Sequence.MacroVersions[version].Ring1)
  attachTooltip(ring1checkbox, L["Ring 1"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(ring1checkbox))

  local ring2checkbox = AceGUI:Create("CheckBox")
  ring2checkbox:SetType("checkbox")
  ring2checkbox:SetWidth(90)
  ring2checkbox:SetTriState(true)
  ring2checkbox:SetLabel(L["Ring 2"])
  ring2checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Ring2 = value
  end)
  ring2checkbox:SetValue(editframe.Sequence.MacroVersions[version].Ring2)
  attachTooltip(ring2checkbox, L["Ring 2"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(ring2checkbox))

  local trinket1checkbox = AceGUI:Create("CheckBox")
  trinket1checkbox:SetType("checkbox")
  trinket1checkbox:SetWidth(90)
  trinket1checkbox:SetTriState(true)
  trinket1checkbox:SetLabel(L["Trinket 1"])
  trinket1checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Trinket1 = value
  end)
  trinket1checkbox:SetValue(editframe.Sequence.MacroVersions[version].Trinket1)
  attachTooltip(trinket1checkbox, L["Trinket 1"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(trinket1checkbox))

  local trinket2checkbox = AceGUI:Create("CheckBox")
  trinket2checkbox:SetType("checkbox")
  trinket2checkbox:SetWidth(90)
  trinket2checkbox:SetTriState(true)
  trinket2checkbox:SetLabel(L["Trinket 2"])
  trinket2checkbox:SetCallback("OnValueChanged", function (sel, object, value)
    editframe.Sequence.MacroVersions[version].Trinket2 = value
  end)
  trinket2checkbox:SetValue(editframe.Sequence.MacroVersions[version].Trinket2)
  attachTooltip(trinket2checkbox, L["Trinket 2"],
    L["Include this equipment slot in this macro version's KeyRelease line (equivalent to /use [combat] N)."] .. "\n" .. USE_TOOLTIP_BODY)
  usegroup:AddChild(rowAlign(trinket2checkbox))

  -- Defensive: see the matching comment in GUIDrawMetadataEditor - resets
  -- scroll to the top of this tab's content every time it's (re)drawn, so
  -- switching versions/sequences can never leave the Step Function row
  -- clipped behind a stale scroll offset from whatever was open before.
  contentcontainer:SetScroll(0)

  layoutcontainer:AddChild(scrollcontainer)
  layoutcontainer:AddChild(usegroup)
  container:AddChild(layoutcontainer)
end

function GSE.GUISelectEditorTab(container, event, group)
  container:ReleaseChildren()
  -- Widgets registered for live resize reflow belong to the tab content
  -- that was just released; drop them so applyContentReflow() never touches
  -- a stale/dead widget while the new tab's draw function repopulates these.
  wipe(editframe.widthReflow)
  wipe(editframe.heightReflow)
  editframe.SelectedTab = group
  editframe.nameeditbox:SetText(GSE.GUIEditFrame.SequenceName)
  editframe.iconpicker:SetImage(GSE.GetMacroIcon(editframe.ClassID, editframe.SequenceName))
  if group == "config" then
    GSE:GUIDrawMetadataEditor(container)
  elseif group == "new" then
	  if(GSE.isNewFirstTimeCreated) then
		GSE.GUIUpdateSequenceDefinition(editframe.ClassID, editframe.SequenceName, editframe.Sequence)
		editframe.save = true
		-- One-shot: only the sequence's very first "New" (add version) tab
		-- visit needs this auto-save (it's what actually creates the brand
		-- new sequence in GSELibrary in the first place). Never clearing
		-- the flag left it armed for every later "New" tab click, on any
		-- macro, for the rest of the session.
		GSE.isNewFirstTimeCreated = false
	  end
    -- Copy the Default to a new version
    table.insert(editframe.Sequence.MacroVersions, GSE.CloneMacroVersion(editframe.Sequence.MacroVersions[editframe.Sequence.Default]))

    GSE.GUIEditorPerformLayout(editframe)
    GSE.GUISelectEditorTab(container, event, table.getn(editframe.Sequence.MacroVersions))
  else
    GSE:GUIDrawMacroEditor(container, group)
  end

  GSE.Skin.WalkAceContainer(container)
end

function GSE.GUIDeleteVersion(version)
  version = tonumber(version)
  local sequence = editframe.Sequence
  if table.getn(sequence.MacroVersions) <= 1 then
    GSE.Print(L["This is the only version of this macro.  Delete the entire macro to delete this version."])
    return
  end
  if sequence.Default == version then
    GSE.Print(L["You cannot delete the Default version of this macro.  Please choose another version to be the Default on the Configuration tab."])
    return
  end
  local printtext = L["Macro Version %d deleted."]
  if sequence.PVP == version then
    sequence.PVP = sequence.Default
    printtext = printtext .. " " .. L["PVP setting changed to Default."]
  end
  if sequence.Raid == version then
    sequence.Raid = sequence.Default
    printtext = printtext .. " " .. L["Raid setting changed to Default."]
  end
  if sequence.Mythic == version then
    sequence.Mythic = sequence.Default
    printtext = printtext .. " " .. L["Mythic setting changed to Default."]
  end
  if sequence.Heroic == version then
    sequence.Heroic = sequence.Default
    printtext = printtext .. " " .. L["Heroic setting changed to Default."]
  end
  if sequence.Dungeon == version then
    sequence.Dungeon = sequence.Default
    printtext = printtext .. " " .. L["Dungeon setting changed to Default."]
  end
  if sequence.Party == version then
    sequence.Party = sequence.Default
    printtext = printtext .. " " .. L["Party setting changed to Default."]
  end

  -- table.remove(sequence.MacroVersions, version) below shifts every
  -- version index AFTER the deleted one down by 1, and leaves indexes
  -- BEFORE the deleted one untouched. Each index-tracking field must
  -- only be decremented when it actually points past the deleted
  -- version - not unconditionally - otherwise deleting a later version
  -- silently repoints an earlier Default/PVP/Raid/etc at the wrong
  -- macro version. A field that was just redirected to sequence.Default
  -- a few lines above is handled correctly here too: it now holds the
  -- same (not-yet-shifted) value as Default, so it shifts in lockstep
  -- with Default below and ends up pointing at the same, correct index.
  if sequence.Default > version then
    sequence.Default = tonumber(sequence.Default) - 1
  end
  if not GSE.isEmpty(sequence.PVP) and tonumber(sequence.PVP) > version then
    sequence.PVP = tonumber(sequence.PVP) - 1
  end
  if not GSE.isEmpty(sequence.Raid) and tonumber(sequence.Raid) > version then
    sequence.Raid = tonumber(sequence.Raid) - 1
  end
  if not GSE.isEmpty(sequence.Mythic) and tonumber(sequence.Mythic) > version then
    sequence.Mythic = tonumber(sequence.Mythic) - 1
  end
  if not GSE.isEmpty(sequence.Heroic) and tonumber(sequence.Heroic) > version then
    sequence.Heroic = tonumber(sequence.Heroic) - 1
  end
  if not GSE.isEmpty(sequence.Dungeon) and tonumber(sequence.Dungeon) > version then
    sequence.Dungeon = tonumber(sequence.Dungeon) - 1
  end
  if not GSE.isEmpty(sequence.Party) and tonumber(sequence.Party) > version then
    sequence.Party = tonumber(sequence.Party) - 1
  end
  table.remove(sequence.MacroVersions, version)
  printtext = printtext .. " " .. L["This change will not come into effect until you save this macro."]
  GSE.GUIEditorPerformLayout(editframe)
  GSE.GUIEditFrame.ContentContainer:SelectTab("config")
  GSE.GUIEditFrame:SetStatusText(string.format(printtext, version))
end
