local GSE = GSE
local L = GSE.L
local function myUpdateFix()
  GSE:ProcessOOCQueue()
  GSE.ReloadSequences()

end
--- This function pops up a confirmation dialog.
function GSE.GUIDeleteSequence(currentSeq, iconWidget)
  if InCombatLockdown() then
    -- deleting removes the protected macro too; in combat the library entry would go but the macro stay orphaned
    GSE.Print(L["You cannot do that while in combat."])
    return
  end
  -- Capture now: OnAccept fires later, and the editor may have been switched to another sequence
  -- by then (Accept would delete the wrong one).
  -- Delete what is actually saved (the name the sequence was opened under), not whatever has since been
  -- typed into the name box - typing another macro's name there and pressing Delete removed that one.
  local classid = GSE.GUIEditFrame.ClassID
  local sequenceName = GSE.GUIEditFrame.loadedName or GSE.GUIEditFrame.SequenceName
  if GSE.FindSequenceClassID(sequenceName) then
    classid = GSE.FindSequenceClassID(sequenceName)
  end
  -- StaticPopup runs the text through a format again, so a literal % in a name must be doubled
  StaticPopupDialogs["GSE-DeleteMacroDialog"].text = string.gsub(string.format(L["Are you sure you want to delete %s?  This will delete the macro and all versions.  This action cannot be undone."], sequenceName), "%%", "%%%%")
  StaticPopupDialogs["GSE-DeleteMacroDialog"].OnAccept = function(self, data)
      GSE.GUIConfirmDeleteSequence(classid, sequenceName)
  end
  StaticPopup_Show ("GSE-DeleteMacroDialog")
  
end

--- This function then deletes the macro
function GSE.GUIConfirmDeleteSequence(classid, sequenceName)
  if InCombatLockdown() then
    -- the popup can be accepted after combat started; DeleteMacro is protected
    GSE.Print(L["You cannot do that while in combat."])
    return
  end
  GSE.GUIViewFrame:Hide()
  -- deleting must not trigger the "unsaved changes" prompt for the sequence that is going away
  GSE.GUIEditorMarkClean()
  GSE.GUIEditFrame:Hide()
  GSE.DeleteSequence(classid, sequenceName)
  GSE.GUIShowViewer()
end


--- Format the text against the GSE Sequence Spec.
function GSE.GUIParseText(editbox)
  if GSEOptions.RealtimeParse then
    local text = GSE.UnEscapeString(editbox:GetText())
    local returntext = GSE.TranslateString(text , GetLocale(), GetLocale(), true)
    editbox:SetText(returntext)
    -- editbox is an AceGUI MultiLineEditBox widget; the native cursor API lives on .editBox
    if editbox.editBox then
      editbox.editBox:SetCursorPosition(string.len(returntext)+2)
    end
    -- SetText doesn't fire OnTextChanged, so push the reformatted text back into the data model
    editbox:Fire("OnTextChanged", returntext)
  end
end

function GSE.GUILoadEditor(key, incomingframe, recordedstring)
  -- Never replace an editor that holds unsaved edits: /gse or the minimap button can bring the Viewer up
  -- over it, and Edit/New from there used to overwrite the open work without asking.
  if GSE.GUIEditFrame:IsShown() and GSE.GUIEditorIsDirty and GSE.GUIEditorIsDirty() then
    GSE.Print(L["The open editor has unsaved changes. Save or close it first."])
    GSE.GUIEditFrame.frame:Raise()
    return
  end
  local classid
  local sequenceName
  local sequence
  
  if GSE.isEmpty(key) then
    classid = GSE.GetCurrentClassID()
    sequenceName = GSE.getSequenceName()
	GSE.isNewFirstTimeCreated=true
    sequence = {
      ["Author"] = GSE.GetCharacterName(),
      ["Talents"] = GSE.GetCurrentTalents(),
      ["Default"] = 1,
      ["SpecID"] = GSE.GetCurrentSpecID();
      ["MacroVersions"] = {
        [1] = {
          ["PreMacro"] = {},
          ["PostMacro"] = {},
          ["KeyPress"] = {},
          ["KeyRelease"] = {},
          ["StepFunction"] = "Sequential",
          [1] = "/say Hello",
        }
      },
    }
    if not GSE.isEmpty(recordedstring) then
      sequence.MacroVersions[1][1] = nil
      sequence.MacroVersions[1] = GSE.SplitMeIntolines(recordedstring)
    end
  else
    local elements = GSE.split(key, ",")
    classid = tonumber(elements[1])
    sequenceName = elements[2]

    sequence = GSE.CloneSequence(GSELibrary[classid] and GSELibrary[classid][sequenceName], true)
	GSE.isNewFirstTimeCreated=false
    if GSE.isEmpty(sequence) then
      -- key pointed at a class/name pair with no matching entry any more
      -- (e.g. the Viewer's own `editkey` going stale after the list was
      -- rebuilt without a fresh row click) - CloneSequence returns nil for
      -- that, and every field access below it would throw "attempt to
      -- index a nil value". Bailing out here, loudly, is what stopped this
      -- from silently building a broken/blank editor state instead.
      GSE.PrintDebugMessage("GUILoadEditor: no sequence found for key '" .. tostring(key) .. "' - aborting", "GUI")
      return
    end
  end
  -- Reset here, not per-button, so every way to open the editor - New,
  -- Edit, a row's right-click - starts a fresh save-state. This used to
  -- only happen on the "New" path (see the "if GSE.isEmpty(key)" branch
  -- above resetting isNewFirstTimeCreated); the Edit button's own reset
  -- line existed only as a comment, so `editframe.save` stayed stuck at
  -- whatever the LAST editor session left it - once a player saved any
  -- macro once, EVERY later Close (even one where nothing was saved this
  -- time) took OnClose's deferred "queue an openviewer OOC event and wait"
  -- branch instead of reopening the Viewer immediately, and that queue
  -- only drains out of combat - so closing the editor while fighting
  -- (exactly what dummy-testing a rotation looks like) could leave the
  -- Viewer just never reappearing.
  GSE.GUIEditFrame.save = false
  GSE.GUIEditFrame.SequenceName = sequenceName
  -- the name this sequence was opened under; renaming onto another existing name asks before overwriting
  GSE.GUIEditFrame.loadedName = (not GSE.isNewFirstTimeCreated) and sequenceName or nil
  GSE.GUIEditFrame.Sequence = sequence
  GSE.GUIEditFrame.ClassID = classid
  GSE.GUIEditFrame.Default = sequence.Default
  GSE.GUIEditFrame.PVP = sequence.PVP or sequence.Default
  GSE.GUIEditFrame.Mythic = sequence.Mythic or sequence.Default
  GSE.GUIEditFrame.Raid = sequence.Raid or sequence.Default
  GSE.GUIEditFrame.Dungeon = sequence.Dungeon or sequence.Default
  GSE.GUIEditFrame.Heroic = sequence.Heroic or sequence.Default
  GSE.GUIEditFrame.Party = sequence.Party or sequence.Default
  GSE.GUIEditorPerformLayout(GSE.GUIEditFrame)
  GSE.GUIEditFrame.ContentContainer:SelectTab("config")
  -- What was just loaded is the baseline for "unsaved changes" - except a freshly recorded rotation,
  -- which exists nowhere else yet: leave it marked unsaved so closing the editor asks before it is lost.
  if GSE.isEmpty(key) and not GSE.isEmpty(recordedstring) then
    GSE.GUIEditFrame.cleanSnapshot = ""
  else
    GSE.GUIEditorMarkClean()
  end
  incomingframe:Hide()
  -- Show()/Hide() on this plain AceGUI frame isn't a protected action, so it
  -- doesn't need the combat guard - only myUpdateFix()'s queue/reload work
  -- plausibly does. Previously the whole block (Show() included) was gated
  -- on InCombatLockdown(), which meant clicking Edit while in combat (e.g.
  -- fighting a training dummy) hid the Viewer and silently never opened the
  -- Editor - no error, no message, just a window that appeared to vanish.
  -- Show the editor first: an error inside myUpdateFix (queue/reload) used to leave the user with the
  -- Viewer hidden and no editor at all.
  GSE.GUIEditFrame:Show()
  if not InCombatLockdown() then
	myUpdateFix()
  end

end

--- Friendly default name for a brand-new macro: "<Spec>_<n>", e.g. Blood_1, Blood_2. Short (WoW macro names
--- are limited to 16 characters), free of spaces and unique across every class. It used to be built from
--- the spec, a count and GetTime(), giving names like "newblood1325584 197" - unreadable, with a space
--- that later broke the library key - and it rewrote every Global sequence as a side effect.
function GSE.getSequenceName()
  local _, specname = GSE.GetCurrentSpecID()
  local base = string.sub((string.gsub(specname or "", "[^%w]", "")), 1, 8)
  -- the spec name comes back in capitals: "Blood", not "BLOOD"
  base = string.upper(string.sub(base, 1, 1)) .. string.lower(string.sub(base, 2))
  if GSE.isEmpty(base) then
    base = "Macro"
  end
  local n = 1
  while GSE.FindSequenceClassID(base .. "_" .. n) or GetMacroIndexByName(base .. "_" .. n) > 0 do
    n = n + 1
  end
  return base .. "_" .. n
end

function GSE.GUIUpdateSequenceList()
  local names = GSE.GetSequenceNames()
  GSE.GUIViewFrame.SequenceListbox:SetList(names)
end

function GSE.GUIToggleClasses(buttonname)
  if not classradio or not specradio then
    return
  end
  if buttonname == "class" then
    classradio:SetValue(true)
    specradio:SetValue(false)
  else
    classradio:SetValue(false)
    specradio:SetValue(true)
  end
end


function GSE.GUIUpdateSequenceDefinition(classid, SequenceName, sequence)

  -- Changes have been made so save them
  for k,v in ipairs(sequence.MacroVersions) do
    sequence.MacroVersions[k] = GSE.TranslateSequenceFromTo(v, GetLocale(), "enUS", SequenceName)
    sequence.MacroVersions[k] = GSE.UnEscapeSequence(sequence.MacroVersions[k])
  end

  if not GSE.isEmpty(SequenceName) then
    if GSE.isEmpty(classid) then
      classid = GSE.GetCurrentClassID()
    end
    if not GSE.isEmpty(SequenceName) then
      -- Library keys never contain spaces/commas; keep the open editor pointing at the real key
      local cleanName = string.gsub(string.gsub(SequenceName, " ", "_"), ",", "_")
      if cleanName ~= SequenceName then
        SequenceName = cleanName
        if GSE.GUIEditFrame then
          GSE.GUIEditFrame.SequenceName = cleanName
          if GSE.GUIEditFrame.nameeditbox then
            GSE.GUIEditFrame.nameeditbox:SetText(cleanName)
          end
        end
      end
      local vals = {}
      vals.action = "Replace"
      vals.sequencename = SequenceName
      -- Queue a copy so later unsaved edits in the editor don't mutate the live library entry
      vals.sequence = GSE.CloneSequence(sequence, true) or sequence
      vals.classid = classid
      table.insert(GSE.OOCQueue, vals)
      GSE.GUIEditFrame:SetStatusText(string.format(L["Sequence %s saved."], SequenceName))
    end
  end
end


function GSE.GUIGetColour(option)
  return tonumber("0x".. string.sub(option,5,6))/255, tonumber("0x"..string.sub(option,7,8))/255, tonumber("0x"..string.sub(option,9,10))/255
end

--- Builds a WoW `|cAARRGGBB` colour escape string from 0-1 RGB components.
--- Callers must assign the return value to the relevant GSEOptions.* colour
--- key themselves (e.g. `GSEOptions.KEYWORD = GSE.GUISetColour(r, g, b)`) -
--- this function has no way to know which option it's being called for.
function GSE.GUISetColour(r, g, b)
  return string.format("|c%02x%02x%02x%02x", 255 , r*255, g*255, b*255)
end


function GSE:OnInitialize()
    GSE.GUIRecordFrame:Hide()
    GSE.GUIVersionFrame:Hide()
    GSE.GUIEditFrame:Hide()
    GSE.GUIViewFrame:Hide()
end


--- Applies GSE's ElvUI-aware skin to the GSE options window specifically.
--- AceConfigDialog-3.0's `:Open(appName)` is a shared library call, but the
--- Frame widget it creates/reuses (`config.OpenFrames[appName]`) is a
--- distinct per-appName instance - skinning THIS ONE FRAME (not hooking
--- :Open or FeedGroup themselves) can't affect any other addon's options
--- window sharing the same AceConfigDialog-3.0 via LibStub, same principle
--- as GSE_GUI's own windows (see GSE_GUI/Skin.lua).
local function SkinGSEOptionsFrame(config)
  local f = config.OpenFrames and config.OpenFrames["GSE"]
  if not f then return end
  GSE.Skin.WalkAceContainer(f)
  -- Clicking a category in the left-hand nav tree (General/Macro
  -- Reset/Colour/Plugins/Debug) doesn't go through GSE.OpenOptionsPanel() -
  -- AceConfigDialog wires that tree's own OnGroupSelected internally to
  -- rebuild just the right-hand content pane. Wrap (not replace) that
  -- callback so every category switch gets re-skinned too, same as
  -- Editor.lua's GUISelectEditorTab re-skinning each tab. The tree widget
  -- itself is destroyed and recreated by ReleaseChildren() on every :Open()
  -- call, so this has to run every time, not just once.
  for _, child in ipairs(f.children or {}) do
    if (child.type == "TreeGroup" or child.type == "TabGroup" or child.type == "DropdownGroup")
        and child.SetCallback then
      local original = child.events and child.events["OnGroupSelected"]
      child:SetCallback("OnGroupSelected", function(...)
        if original then original(...) end
        GSE.Skin.WalkAceContainer(f)
      end)
    end
  end
end

-- A file-load-time hooksecurefunc(config, "Open", ...) was tried here first
-- and empirically does NOT reliably fire: AceConfigDialog-3.0 is a shared
-- LibStub library, and this client has several other addons that embed
-- their own copy - if any of them registers a newer minor revision after
-- GSE_GUI has already hooked it, LibStub's "upgrade" reassigns the
-- library's methods (including Open) to fresh closures, silently discarding
-- a hook installed on the old ones. Confirmed live: the hook fired on some
-- opens and not others depending on addon load order, not just always
-- discarding one Open callsite that's easy to spot. A direct call at the
-- end of GSE.OpenOptionsPanel() below doesn't have this problem - it always
-- runs against whatever :Open() implementation is current *this call*.
-- /gseo (wired via AceConfigCmd-3.0, calls :Open("GSE") directly) is not
-- covered by this direct call and can still show up unskinned - a much
-- smaller gap than the button-click path being unreliable every time.
function GSE.OpenOptionsPanel()
  local config = LibStub:GetLibrary("AceConfigDialog-3.0")
  config:Open("GSE")
  --config:SelectGroup("GSSE", "Debug")
  SkinGSEOptionsFrame(config)
  -- The very first :Open("GSE") in a session (the frame is freshly acquired
  -- from AceGUI's widget pool, not reused) empirically leaves the native
  -- Close button unskinned even though this same SkinGSEOptionsFrame call
  -- fixes it correctly on every later Open() - confirmed live: an identical
  -- second call, moments later, always takes effect. Something involved
  -- (most likely ElvUI's own HandleButton, which this addon calls into and
  -- doesn't control) defers its real effect by a tick the very first time it
  -- sees a given button. A cheap, harmless repeat pass shortly after covers
  -- that first-open case without needing to fully root-cause a dependency
  -- this addon doesn't own.
  if GSE.ScheduleTimer then
    GSE:ScheduleTimer(function() SkinGSEOptionsFrame(config) end, 0.1)
  end
end
