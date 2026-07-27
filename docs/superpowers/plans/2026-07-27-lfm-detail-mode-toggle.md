# LFM Popup Minimal/Compact/Detailed Mode Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AddGroupPopup's binary "Detailed" checkbox with a 3-way Minimal/Compact/Detailed toggle, keeping composition counters, the broadcast message, and the DataBus wire payload internally consistent and free of leftover fields no matter which mode is active.

**Architecture:** Extend the existing `detailMode` machinery (currently `"vague"`/`"detailed"`) to a 3-value string (`"minimal"`/`"compact"`/`"detailed"`) threaded through the same popup, the same `BuildLFM`/`BuildConfig` functions, and the same DataBus codec — no new files, no new popups. See `docs/superpowers/specs/2026-07-27-lfm-detail-mode-toggle-design.md` for full rationale.

**Tech Stack:** Lua 5.1, WoW 3.3.5a client APIs, no build/test toolchain (see Verification Method below).

## Global Constraints

- Lua 5.1 syntax only (no `bit` library, no goto, `string.trim`/other polyfills live in `core/Utils.lua`).
- Load order is fixed by `AutoInvitePlus.toc` (core -> data -> modules -> ui) — no new files are added in this plan, so no `.toc` changes are needed.
- `AIP.db.lfmDetailMode` default stays `"detailed"` (unchanged default value, only the set of legal strings changes).
- Every cross-module call stays guarded (`if AIP.Foo and AIP.Foo.Bar then`), matching the existing convention in every file this plan touches.
- The tandem feature (and its DataBus wire values) is unreleased — freely rename `"vague"` -> `"compact"` and `"V"` -> `"C"` wire codes; no backward-compat shim needed.
- **Verification method (no test framework in this repo):** every task's "verify" step is (a) a Lua 5.1 syntax check via `luaparse`, and (b) an explicit in-game manual check via `/reload`. For (a), run this from the repo root (idempotent — safe to re-run per task):
  ```bash
  mkdir -p /tmp/aip-luacheck && cd /tmp/aip-luacheck && [ -f node_modules/luaparse/package.json ] || npm init -y >/dev/null 2>&1 && npm install luaparse --no-audit --no-fund >/dev/null 2>&1
  node -e "
    const luaparse = require('/tmp/aip-luacheck/node_modules/luaparse');
    const fs = require('fs');
    const files = process.argv.slice(1);
    let bad = false;
    for (const f of files) {
      try { luaparse.parse(fs.readFileSync(f, 'utf8'), {luaVersion: '5.1', comments: false}); console.log('OK   ' + f); }
      catch (e) { bad = true; console.log('FAIL ' + f + ' -> ' + e.message); }
    }
    process.exit(bad ? 1 : 0);
  " -- <FILE_PATHS_HERE>
  ```
  Replace `<FILE_PATHS_HERE>` with the absolute path(s) of the file(s) touched in that task.

---

### Task 1: 3-way mode toggle widget + section show/hide

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua` (inside `GUI.CreateAddGroupPopup`, the block currently building `detailModeCheck`/`detailModeLabel` around the `-- Composition detail mode` comment, and the `SetClassGridEnabled` function + its `detailModeCheck:SetScript("OnClick", ...)` handler)
- Modify: `AutoInvitePlus/core/Core.lua` (the `lfmDetailMode` default comment, `defaults` table)

**Interfaces:**
- Produces: `popup.detailMode` now ranges over `"minimal"|"compact"|"detailed"` (was `"vague"|"detailed"`).
- Produces: `popup.ApplyDetailMode(mode)` — replaces `popup.SetClassGridEnabled(enabled)`. Shows/hides (not dims) `popup.compositionRowWidgets` and `popup.classGridWidgets` per mode, and updates `classHint`'s text.
- Produces: `popup.compositionRowWidgets` — new table, same role as the existing `popup.classGridWidgets` but for the Tanks/Healers/MDPS/RDPS row.
- Produces: `popup.modeButtons` — table keyed by mode string -> button frame.
- Consumes: nothing new from other tasks (this task is foundational; later tasks call `ApplyDetailMode`/read `popup.detailMode`).

- [ ] **Step 1: Locate and read the exact current block to replace**

Read `AutoInvitePlus/ui/CentralGUI.lua` around the `-- === Composition Row ===` comment (creates `tankLabel`/`tankInput`/`tankContainer`/`healLabel`/`healContainer`/`mdpsLabel`/`mdpsContainer`/`rdpsLabel`/`rdpsContainer`, currently starting right after `compLabel`) through the `-- Composition detail mode` comment and `detailModeCheck:SetScript("OnClick", ...)` block (ends right before `-- === Need summary`). Confirm the exact widget variable names match what's described here before editing — this popup is 8000+ lines into the file and hand-edited around this area recently, so re-grep for `local compLabel = detail:CreateFontString` and `detailModeCheck:SetScript("OnClick"` to get current line numbers rather than trusting stale ones.

- [ ] **Step 2: Add `popup.compositionRowWidgets` tracking**

Immediately after the `compLabel` `SetText("Composition:")` line, add:

```lua
    popup.compositionRowWidgets = { compLabel }
```

Then after each of the four composition widgets is created (`tankContainer`, `healContainer`, `mdpsContainer`, `rdpsContainer` — right after `popup.tankInput = tankInput` etc.), append the label + container to the table. Concretely, change:

```lua
    tankInput:SetText("2")
    popup.tankInput = tankInput
```
to:
```lua
    tankInput:SetText("2")
    popup.tankInput = tankInput
    table.insert(popup.compositionRowWidgets, tankLabel)
    table.insert(popup.compositionRowWidgets, tankContainer)
```
and the same pattern (label + container) for `healInput`/`healContainer`, `mdpsInput`/`mdpsContainer`, `rdpsInput`/`rdpsContainer`.

- [ ] **Step 3: Replace the `detailModeCheck`/`detailModeLabel` block with a 3-way toggle**

Replace this whole block:
```lua
    -- Composition detail mode: DETAILED broadcasts the class list + counts
    -- ([T:PP..] + [Need:..]); VAGUE broadcasts role counts only ([T:x/y]).
    -- The choice persists (AIP.db.lfmDetailMode) and rides the listing so
    -- FitEngine/regen respect it too.
    local detailModeCheck = CreateFrame("CheckButton", nil, detail, "UICheckButtonTemplate")
    detailModeCheck:SetSize(20, 20)
    detailModeCheck:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -20, -124)
    local detailModeLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    detailModeLabel:SetPoint("RIGHT", detailModeCheck, "LEFT", -2, 0)
    detailModeLabel:SetText("Detailed")
    detailModeLabel:SetTextColor(0.4, 0.8, 1)
    popup.detailModeCheck = detailModeCheck
    popup.detailMode = (AIP.db and AIP.db.lfmDetailMode) or "detailed"
    detailModeCheck:SetChecked(popup.detailMode ~= "vague")
    detailModeCheck:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Composition detail")
        GameTooltip:AddLine("Checked: broadcast the class list and per-class counts.", 1, 1, 1)
        GameTooltip:AddLine("Unchecked (vague): broadcast role counts only - any class may apply.", 1, 1, 1)
        GameTooltip:Show()
    end)
    detailModeCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)
```
with:
```lua
    -- Composition detail mode: MINIMAL shows only the Note (role counts still
    -- come from the template, just not shown/editable); COMPACT broadcasts
    -- role counts only ([T:x/y]); DETAILED broadcasts the class list + counts
    -- ([T:PP..] + [Need:..]). The choice persists (AIP.db.lfmDetailMode) and
    -- rides the listing so FitEngine/regen/DataBus all respect it too.
    local MODE_LABEL = { minimal = "Minimal", compact = "Compact", detailed = "Detailed" }
    local MODE_TOOLTIP = {
        minimal = "Only the note is customized here - role counts still come from the selected template, they're just not shown.",
        compact = "Broadcast role counts only ([T:x/y]) - any class may apply.",
        detailed = "Broadcast the class list and per-class counts ([Need:...]).",
    }
    popup.modeButtons = {}
    local function updateModeButtonHighlight()
        for mode, btn in pairs(popup.modeButtons) do
            if mode == popup.detailMode then
                btn.text:SetTextColor(0.4, 0.8, 1)
            else
                btn.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    end
    popup.UpdateModeButtonHighlight = updateModeButtonHighlight
    local function makeModeButton(mode, xOffset)
        local btn = CreateFrame("Button", nil, detail)
        btn:SetSize(58, 18)
        btn:SetPoint("TOPRIGHT", detail, "TOPRIGHT", xOffset, -124)
        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("CENTER", 0, 0)
        fs:SetText(MODE_LABEL[mode])
        btn.text = fs
        btn:SetScript("OnClick", function()
            popup.detailMode = mode
            if AIP.db then AIP.db.lfmDetailMode = mode end
            if popup.ApplyDetailMode then popup.ApplyDetailMode(mode) end
            updateModeButtonHighlight()
            if RefreshPreview then RefreshPreview() end
        end)
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Composition detail: " .. MODE_LABEL[mode])
            GameTooltip:AddLine(MODE_TOOLTIP[mode], 1, 1, 1)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        popup.modeButtons[mode] = btn
        return btn
    end
    makeModeButton("detailed", -20)
    makeModeButton("compact", -84)
    makeModeButton("minimal", -148)
    popup.detailMode = (AIP.db and AIP.db.lfmDetailMode) or "detailed"
    if popup.detailMode == "vague" then popup.detailMode = "compact" end -- legacy SavedVariables value
```

Note the last line: a player's `AIP.db.lfmDetailMode` may already hold the old `"vague"` string from before this change (SavedVariables persist across `/reload`); normalize it to `"compact"` at read time so existing saved data doesn't produce an unrecognized mode.

- [ ] **Step 4: Replace `SetClassGridEnabled` with `ApplyDetailMode`**

Replace:
```lua
    -- Dim + deactivate the whole class grid in vague mode (role counts only)
    local function SetClassGridEnabled(enabled)
        for _, w in ipairs(popup.classGridWidgets) do
            w:SetAlpha(enabled and 1 or 0.35)
            if w.Disable and w.Enable then
                if enabled then w:Enable() else w:Disable() end
            end
            if w.EnableMouse then w:EnableMouse(enabled) end
        end
        classHint:SetText(enabled
            and "|cFF888888(box = how many needed; role name toggles all)|r"
            or "|cFFFF8800vague mode - role counts only, class list not broadcast|r")
    end
    popup.SetClassGridEnabled = SetClassGridEnabled

    detailModeCheck:SetScript("OnClick", function(self)
        popup.detailMode = self:GetChecked() and "detailed" or "vague"
        if AIP.db then AIP.db.lfmDetailMode = popup.detailMode end
        SetClassGridEnabled(popup.detailMode ~= "vague")
        if RefreshPreview then RefreshPreview() end
    end)
```
with:
```lua
    -- Fully show/hide (not just dim) the Composition row and Class grid per
    -- mode - Minimal hides both, Compact shows only Composition, Detailed
    -- shows only the Class grid (its counts drive the composition totals,
    -- see SyncCompositionFromClassGrid in the next task).
    local function ApplyDetailMode(mode)
        local showComposition = (mode == "compact")
        local showClassGrid = (mode == "detailed")
        for _, w in ipairs(popup.compositionRowWidgets) do
            if showComposition then w:Show() else w:Hide() end
        end
        for _, w in ipairs(popup.classGridWidgets) do
            if showClassGrid then w:Show() else w:Hide() end
            w:SetAlpha(1)
            if w.Disable and w.Enable then w:Enable() end
            if w.EnableMouse then w:EnableMouse(true) end
        end
        if mode == "minimal" then
            classHint:SetText("|cFFFF8800minimal mode - only the note is broadcast beyond the template's role counts|r")
        elseif mode == "compact" then
            classHint:SetText("|cFFFF8800compact mode - role counts only, class list not broadcast|r")
        else
            classHint:SetText("|cFF888888(box = how many needed; role name toggles all)|r")
        end
    end
    popup.ApplyDetailMode = ApplyDetailMode
```

- [ ] **Step 5: Call `ApplyDetailMode` and the highlight update once at construction time, after the class grid widgets exist**

Find the line `ApplyTemplateDefaults()` near the end of `GUI.CreateAddGroupPopup` (in the "Apply initial defaults, start collapsed" block, after `popup:Hide()`). Immediately after `SetClassGridEnabled(popup.detailMode ~= "vague")` — which Step 4 already removed — there should be no leftover call; instead add, right after the `ApplyTemplateDefaults()` call in that same block:

```lua
    if popup.ApplyDetailMode then popup.ApplyDetailMode(popup.detailMode) end
    if popup.UpdateModeButtonHighlight then popup.UpdateModeButtonHighlight() end
```

Also search the file for any other remaining call to `SetClassGridEnabled` (there is one more near the very end of `GUI.CreateAddGroupPopup`, in the same "Apply initial defaults" block, e.g. `SetClassGridEnabled(popup.detailMode ~= "vague")`) and replace it with the two lines above (don't duplicate — there should end up being exactly one call site for `ApplyDetailMode`/`UpdateModeButtonHighlight` in the construction sequence, right after `ApplyTemplateDefaults()`).

- [ ] **Step 6: Update the `core/Core.lua` defaults comment**

Change:
```lua
    lfmDetailMode = "detailed",   -- "detailed" = classes+counts broadcast; "vague" = role counts only
```
to:
```lua
    lfmDetailMode = "detailed",   -- "detailed" = classes+counts; "compact" = role counts only; "minimal" = note only (role counts still from template)
```

- [ ] **Step 7: Syntax-check**

Run the Global Constraints verification command against:
```
d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/ui/CentralGUI.lua d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/core/Core.lua
```
Expected: `OK` for both files.

- [ ] **Step 8: In-game manual check**

`/reload`, open the LFM popup (`/aip` -> Browser tab -> "+ Post Group", or however it's currently invoked), click each of the three mode buttons in turn and confirm: Detailed shows the class grid and hides the Tanks/Healers/MDPS/RDPS row; Compact shows the row and hides the class grid; Minimal hides both. Confirm the active button is visually highlighted (lighter blue text) and the other two are dimmed.

- [ ] **Step 9: Commit**

```bash
git add AutoInvitePlus/ui/CentralGUI.lua AutoInvitePlus/core/Core.lua
git commit -m "Add Minimal/Compact/Detailed 3-way mode toggle to LFM popup"
```

---

### Task 2: Class-grid-driven composition sync (Detailed mode)

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua` (`makeSpecCheck`'s `check:SetScript("OnClick", ...)` and `countInput:HookScript("OnTextChanged", ...)` handlers; `ApplyTemplateDefaults`; `RenderNeedsSummary`)

**Interfaces:**
- Consumes: `popup.detailMode`, `popup.classChecks` (`TANK`/`HEALER`/`DPS` tables of spec checkboxes with `.countInput` and `.specData.melee`), `popup.tankInput`/`healInput`/`mdpsInput`/`rdpsInput` (all from Task 1 / pre-existing code).
- Produces: `popup.SyncCompositionFromClassGrid()` — new function, no return value. Called by later tasks' verification only; not consumed by other tasks' code.

- [ ] **Step 1: Add `SyncCompositionFromClassGrid`**

Add this new local function right after the `CollectRoleSpecs` function definition (which already knows how to fold DPS specs into MDPS/RDPS via `check.specData.melee` — reuse the identical test here so the two functions can never disagree):

```lua
    -- While Detailed mode is active, the class grid's checked per-spec counts
    -- are authoritative: mirror their sums into the (hidden) composition-row
    -- inputs so BuildConfig's [x/y] segment can never disagree with the
    -- [Need:] block, and so switching back to Compact shows correct numbers.
    -- No-ops outside Detailed mode - Compact-mode manual edits are untouched.
    local function SyncCompositionFromClassGrid()
        if popup.detailMode ~= "detailed" then return end
        local tankSum, healSum, mdpsSum, rdpsSum = 0, 0, 0, 0
        for _, check in pairs(popup.classChecks.TANK or {}) do
            if check:GetChecked() and check.countInput then
                tankSum = tankSum + (tonumber(check.countInput:GetText()) or 0)
            end
        end
        for _, check in pairs(popup.classChecks.HEALER or {}) do
            if check:GetChecked() and check.countInput then
                healSum = healSum + (tonumber(check.countInput:GetText()) or 0)
            end
        end
        for _, check in pairs(popup.classChecks.DPS or {}) do
            if check:GetChecked() and check.countInput and check.specData then
                local n = tonumber(check.countInput:GetText()) or 0
                if check.specData.melee then mdpsSum = mdpsSum + n else rdpsSum = rdpsSum + n end
            end
        end
        popup.tankInput:SetText(tostring(tankSum))
        popup.healInput:SetText(tostring(healSum))
        popup.mdpsInput:SetText(tostring(mdpsSum))
        popup.rdpsInput:SetText(tostring(rdpsSum))
    end
    popup.SyncCompositionFromClassGrid = SyncCompositionFromClassGrid
```

- [ ] **Step 2: Call it from the per-spec checkbox and count-box handlers**

In `makeSpecCheck`, find:
```lua
        check:SetScript("OnClick", function(self)
            if self.countInput then
                if self:GetChecked() then
                    if (tonumber(self.countInput:GetText()) or 0) <= 0 then
                        self.countInput:SetText("1")
                    end
                else
                    self.countInput:SetText("0")
                end
            end
            if RefreshPreview then RefreshPreview() end
        end)
```
and add the sync call right before `RefreshPreview`:
```lua
        check:SetScript("OnClick", function(self)
            if self.countInput then
                if self:GetChecked() then
                    if (tonumber(self.countInput:GetText()) or 0) <= 0 then
                        self.countInput:SetText("1")
                    end
                else
                    self.countInput:SetText("0")
                end
            end
            if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
            if RefreshPreview then RefreshPreview() end
        end)
```

Also find `countInput:HookScript("OnTextChanged", ...)` a few lines above (inside the same `makeSpecCheck`):
```lua
        countInput:HookScript("OnTextChanged", function(self, isUser)
            if isUser then
                local n = tonumber(self:GetText()) or 0
                if n > 0 and not check:GetChecked() then check:SetChecked(true) end
                if RefreshPreview then RefreshPreview() end
            end
        end)
```
and add the sync call the same way:
```lua
        countInput:HookScript("OnTextChanged", function(self, isUser)
            if isUser then
                local n = tonumber(self:GetText()) or 0
                if n > 0 and not check:GetChecked() then check:SetChecked(true) end
                if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
                if RefreshPreview then RefreshPreview() end
            end
        end)
```

Also find `makeRoleToggle`'s `btn:SetScript("OnClick", ...)` handler (the role-label all/none toggle), which currently ends with `if RefreshPreview then RefreshPreview() end` — add the sync call there too, same pattern, since it changes multiple counts at once:
```lua
            if popup.SyncCompositionFromClassGrid then popup.SyncCompositionFromClassGrid() end
            if RefreshPreview then RefreshPreview() end
```

- [ ] **Step 3: Sync once after a template applies its recommendations, while in Detailed mode**

In `ApplyTemplateDefaults`, find the tail:
```lua
        UpdateWeeklyStrip()
        UpdateClassNeeds(true)
        RefreshPreview()
    end
    popup.ApplyTemplateDefaults = ApplyTemplateDefaults
```
and change to:
```lua
        UpdateWeeklyStrip()
        UpdateClassNeeds(true)
        if popup.detailMode == "detailed" and popup.SyncCompositionFromClassGrid then
            popup.SyncCompositionFromClassGrid()
        end
        RefreshPreview()
    end
    popup.ApplyTemplateDefaults = ApplyTemplateDefaults
```

(`UpdateClassNeeds(true)` is what calls `ApplyRecommendedSpecs`, which sets the per-spec count boxes from the template's recommendation — the sync must run after that, which this ordering already guarantees.)

- [ ] **Step 4: Extend `RenderNeedsSummary`'s vague-mode branch to minimal too**

Find:
```lua
    local function RenderNeedsSummary(classNeeds)
        if popup.detailMode == "vague" then
            local vagueTxt = "|cFF888888Vague listing: role counts only - any class can apply.|r"
            needsText:SetText(vagueTxt)
            if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(vagueTxt) end
            return
        end
```
and change to:
```lua
    local function RenderNeedsSummary(classNeeds)
        if popup.detailMode == "minimal" then
            local minimalTxt = "|cFF888888Minimal listing: only the note is broadcast.|r"
            needsText:SetText(minimalTxt)
            if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(minimalTxt) end
            return
        end
        if popup.detailMode == "compact" then
            local compactTxt = "|cFF888888Compact listing: role counts only - any class can apply.|r"
            needsText:SetText(compactTxt)
            if popup.collapsedNeedsText then popup.collapsedNeedsText:SetText(compactTxt) end
            return
        end
```

- [ ] **Step 5: Find and update `BuildConfig`'s mode check**

Find:
```lua
    local function BuildConfig()
        local roleSpecs, lookingForSpecs, selectedClasses, classNeeds = CollectRoleSpecs()
        if popup.detailMode == "vague" then
            roleSpecs, lookingForSpecs, selectedClasses, classNeeds = nil, {}, nil, nil
        end
```
and change to:
```lua
    local function BuildConfig()
        local roleSpecs, lookingForSpecs, selectedClasses, classNeeds = CollectRoleSpecs()
        if popup.detailMode ~= "detailed" then
            roleSpecs, lookingForSpecs, selectedClasses, classNeeds = nil, {}, nil, nil
        end
```

- [ ] **Step 6: Syntax-check**

Run the verification command against:
```
d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/ui/CentralGUI.lua
```
Expected: `OK`.

- [ ] **Step 7: In-game manual check**

`/reload`, open the popup, select a raid template, switch to Detailed mode, check a couple of extra spec boxes and bump their count boxes. Confirm the live PREVIEW text's `[T:x/y ...]` counts update to match the sum of what's checked (you can temporarily switch to Compact mode to see the now-hidden-but-synced Tanks/Healers/MDPS/RDPS numbers directly, then switch back to Detailed).

- [ ] **Step 8: Commit**

```bash
git add AutoInvitePlus/ui/CentralGUI.lua
git commit -m "Sync composition-row totals from the class grid in Detailed mode"
```

---

### Task 3: Live-decrementing role totals in Detailed mode (`RegenerateBroadcastMessage`)

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua` (`GUI.RegenerateBroadcastMessage`)

**Interfaces:**
- Consumes: `ownGroup.detailMode`, `GUI.MyGroup.detailMode`, `GUI.MyGroup.classNeedsBase`/`classCountsAtPost` (all pre-existing fields; `detailMode` now carries `"minimal"|"compact"|"detailed"` after Task 1/2).
- Produces: no new public interface — this task changes internal behavior of an existing function only.

- [ ] **Step 1: Extend the vague-guard to minimal, and derive live role totals from decremented classNeeds in Detailed mode**

Find:
```lua
    local Comp = AIP.Composition
    local vague = (ownGroup.detailMode == "vague")
        or (GUI.MyGroup and GUI.MyGroup.detailMode == "vague")
    local base = GUI.MyGroup and GUI.MyGroup.classNeedsBase
    local snap = GUI.MyGroup and GUI.MyGroup.classCountsAtPost
    if vague then
        -- Vague listing: never inject class-level detail on regeneration
        -- (belt-and-braces: also clear any stale detailed fields on the record)
        ownGroup.classNeeds = nil
        ownGroup.roleSpecs = nil
        ownGroup.selectedClasses = nil
        if GUI.MyGroup then
            GUI.MyGroup.classNeeds = nil
            GUI.MyGroup.roleSpecs = nil
            GUI.MyGroup.selectedClasses = nil
        end
    elseif base and snap and Comp and Comp.ScanRaid then
        local raid = Comp.ScanRaid()
        local joined = {}
        for class, n in pairs((raid and raid.classCounts) or {}) do
            joined[class] = math.max(0, n - (snap[class] or 0))
        end
        local remaining = {}
        for _, row in ipairs(base) do
            local take = math.min(row.count or 0, joined[row.class] or 0)
            joined[row.class] = (joined[row.class] or 0) - take
            local left = (row.count or 0) - take
            if left > 0 then
                table.insert(remaining, {class = row.class, role = row.role, count = left})
            end
        end
        ownGroup.classNeeds = remaining
        if GUI.MyGroup then GUI.MyGroup.classNeeds = remaining end
    else
```
and change the guard condition and add the role-total derivation branch:
```lua
    local Comp = AIP.Composition
    local mode = ownGroup.detailMode or (GUI.MyGroup and GUI.MyGroup.detailMode)
    local notDetailed = (mode ~= "detailed")
    local base = GUI.MyGroup and GUI.MyGroup.classNeedsBase
    local snap = GUI.MyGroup and GUI.MyGroup.classCountsAtPost
    if notDetailed then
        -- Minimal/Compact listing: never inject class-level detail on
        -- regeneration (belt-and-braces: also clear any stale detailed
        -- fields on the record).
        ownGroup.classNeeds = nil
        ownGroup.roleSpecs = nil
        ownGroup.selectedClasses = nil
        if GUI.MyGroup then
            GUI.MyGroup.classNeeds = nil
            GUI.MyGroup.roleSpecs = nil
            GUI.MyGroup.selectedClasses = nil
        end
    elseif base and snap and Comp and Comp.ScanRaid then
        local raid = Comp.ScanRaid()
        local joined = {}
        for class, n in pairs((raid and raid.classCounts) or {}) do
            joined[class] = math.max(0, n - (snap[class] or 0))
        end
        local remaining = {}
        for _, row in ipairs(base) do
            local take = math.min(row.count or 0, joined[row.class] or 0)
            joined[row.class] = (joined[row.class] or 0) - take
            local left = (row.count or 0) - take
            if left > 0 then
                table.insert(remaining, {class = row.class, role = row.role, count = left})
            end
        end
        ownGroup.classNeeds = remaining
        if GUI.MyGroup then GUI.MyGroup.classNeeds = remaining end

        -- Detailed listings: the aggregate [x/y] role totals are derived
        -- from the SAME live-decremented list, not the frozen posted value,
        -- so the header count and the [Need:] breakdown can never disagree
        -- (and both shrink together as recruits join).
        local liveNeeded = {TANK = 0, HEALER = 0, DPS = 0}
        for _, row in ipairs(remaining) do
            liveNeeded[row.role] = (liveNeeded[row.role] or 0) + (row.count or 0)
        end
        if ownGroup.tanks then ownGroup.tanks.needed = liveNeeded.TANK end
        if ownGroup.healers then ownGroup.healers.needed = liveNeeded.HEALER end
        -- classNeeds folds MDPS/RDPS into "DPS" (see CollectRoleSpecs) - split
        -- the live DPS total back across mdps/rdps proportionally to their
        -- CURRENT posted needed split so neither role silently zeroes out.
        local mdpsNeeded, rdpsNeeded = ownGroup.mdps and ownGroup.mdps.needed or 0, ownGroup.rdps and ownGroup.rdps.needed or 0
        local dpsSplitTotal = mdpsNeeded + rdpsNeeded
        if dpsSplitTotal > 0 then
            local mdpsShare = math.floor(liveNeeded.DPS * mdpsNeeded / dpsSplitTotal + 0.5)
            if ownGroup.mdps then ownGroup.mdps.needed = mdpsShare end
            if ownGroup.rdps then ownGroup.rdps.needed = liveNeeded.DPS - mdpsShare end
        end
    else
```

- [ ] **Step 2: Update `neededTanks`/`neededHealers`/`neededMdps`/`neededRdps` to read AFTER the block above runs**

Find, earlier in the same function:
```lua
    -- Get needed counts from the original group data
    local neededTanks = ownGroup.tanks and ownGroup.tanks.needed or 2
    local neededHealers = ownGroup.healers and ownGroup.healers.needed or 6
    local neededMdps = ownGroup.mdps and ownGroup.mdps.needed or 8
    local neededRdps = ownGroup.rdps and ownGroup.rdps.needed or 9
```
This currently runs BEFORE the classNeeds-decrement block (which now also mutates `ownGroup.tanks.needed` etc. for Detailed listings). Move these four lines to immediately AFTER the `if notDetailed then ... elseif base and snap ... else ... end` block ends (i.e. after the closing `end` that follows the `templateKey`-fallback `else` branch, right before `local msg = AIP.LFMFormat.BuildLFM({`), deleting them from their original earlier position. This ensures they pick up the just-derived live totals for Detailed listings, while still reading the frozen posted value for Minimal/Compact listings (untouched by this task).

- [ ] **Step 3: Syntax-check**

Run the verification command against:
```
d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/ui/CentralGUI.lua
```
Expected: `OK`.

- [ ] **Step 4: In-game manual check**

`/reload`, use `/aip testdata` to get fixture roster/group data if needed, post a Detailed-mode listing with a couple of class needs set (e.g. 2x Mage), then simulate a matching player joining (via test data or an actual invite) and confirm via the popup preview / `/aip needs` / the broadcast chat text that BOTH the `[x/y]` DPS total and the `[Need: ...]` Mage count decrease together, not just the individual need count.

- [ ] **Step 5: Commit**

```bash
git add AutoInvitePlus/ui/CentralGUI.lua
git commit -m "Derive live role totals from decremented class needs in Detailed mode"
```

---

### Task 4: Remove the artificial 5-entry need cap; trim gracefully instead

**Files:**
- Modify: `AutoInvitePlus/modules/LFMFormat.lua` (`LF.ClassNeedString`, `LF.BuildLFM`)

**Interfaces:**
- Produces: `LF.ClassNeedString(classNeeds, maxParts)` — gains an optional second parameter (`nil` = unlimited, was previously always capped at `LF.MAX_NEED_PARTS`).
- `LF.MAX_NEED_PARTS` constant is removed (no other file references it — verified via repo-wide grep before writing this plan).

- [ ] **Step 1: Make `ClassNeedString` support an optional cap instead of a hardcoded one**

Find:
```lua
-- classNeeds {{class="MAGE", role="DPS", count=2}, ...} (Comp.GetClassNeeds
-- list shape) -> "[Need: 2xMag 1xPP]" or "" when empty/all filled.
-- Capped: a fresh 25-man aggregates 10+ class rows (~120 bytes) which would
-- starve the note/achievement/specs segments out of the 255-byte budget, so
-- only the first MAX_NEED_PARTS rows render and the rest collapse to "+N".
LF.MAX_NEED_PARTS = 5

function LF.ClassNeedString(classNeeds)
    if not classNeeds or #classNeeds == 0 then return "" end
    local parts, overflow = {}, 0
    for _, n in ipairs(classNeeds) do
        if (n.count or 0) > 0 then
            if #parts < LF.MAX_NEED_PARTS then
                parts[#parts + 1] = tostring(n.count) .. "x" .. LF.NeedCode(n.class, n.role)
            else
                overflow = overflow + n.count
            end
        end
    end
    if #parts == 0 then return "" end
    if overflow > 0 then
        parts[#parts + 1] = "+" .. overflow
    end
    return "[Need: " .. table.concat(parts, " ") .. "]"
end
```
and replace with:
```lua
-- classNeeds {{class="MAGE", role="DPS", count=2}, ...} (Comp.GetClassNeeds
-- list shape) -> "[Need: 2xMag 1xPP]" or "" when empty/all filled.
-- maxParts: nil = show every row (default - detailed listings should show
-- the entire counter set); a number caps display, collapsing the rest to
-- "+N" - used by BuildLFM's overflow ladder to shrink gracefully under
-- real byte pressure instead of dropping the whole block at once.
function LF.ClassNeedString(classNeeds, maxParts)
    if not classNeeds or #classNeeds == 0 then return "" end
    if maxParts and maxParts <= 0 then return "" end
    local parts, overflow = {}, 0
    for _, n in ipairs(classNeeds) do
        if (n.count or 0) > 0 then
            if not maxParts or #parts < maxParts then
                parts[#parts + 1] = tostring(n.count) .. "x" .. LF.NeedCode(n.class, n.role)
            else
                overflow = overflow + n.count
            end
        end
    end
    if #parts == 0 then return "" end
    if overflow > 0 then
        parts[#parts + 1] = "+" .. overflow
    end
    return "[Need: " .. table.concat(parts, " ") .. "]"
end
```

- [ ] **Step 2: Give `BuildLFM`'s overflow ladder entry-by-entry graceful trimming for the need segment**

Find:
```lua
    local gs = (cfg.gsMin and cfg.gsMin > 0) and (tostring(cfg.gsMin) .. "+") or ""
    local ilvl = (cfg.ilvlMin and cfg.ilvlMin > 0) and ("iLvl:" .. tostring(cfg.ilvlMin) .. "+") or ""
    local specs = LF.RoleSpecString(cfg.roleSpecs)
    local need = LF.ClassNeedString(cfg.classNeeds)
    local kw = (cfg.keyword and cfg.keyword ~= "") and string.format('w/ "%s"', cfg.keyword) or ""
```
and change the `need` line only:
```lua
    local gs = (cfg.gsMin and cfg.gsMin > 0) and (tostring(cfg.gsMin) .. "+") or ""
    local ilvl = (cfg.ilvlMin and cfg.ilvlMin > 0) and ("iLvl:" .. tostring(cfg.ilvlMin) .. "+") or ""
    local specs = LF.RoleSpecString(cfg.roleSpecs)
    local need = LF.ClassNeedString(cfg.classNeeds)  -- full fidelity by default; shrunk below only if it doesn't fit
    local kw = (cfg.keyword and cfg.keyword ~= "") and string.format('w/ "%s"', cfg.keyword) or ""
```
(unchanged line, just confirming its new full-fidelity default — the real change is in the drop loop below.)

Then find:
```lua
    local msg = assemble()
    for _, name in ipairs(dropOrder) do
        if #msg <= LF.MAX_LEN then break end
        if segments[name] ~= "" then
            segments[name] = ""
            trimmed[#trimmed + 1] = name
            msg = assemble()
        end
    end
```
and replace with:
```lua
    local needRowCount = 0
    for _, n in ipairs(cfg.classNeeds or {}) do
        if (n.count or 0) > 0 then needRowCount = needRowCount + 1 end
    end

    local msg = assemble()
    for _, name in ipairs(dropOrder) do
        if #msg <= LF.MAX_LEN then break end
        if name == "need" and segments.need ~= "" then
            -- Graceful degrade: shrink one entry at a time (mirrors what the
            -- DataBus wire codec already does for the `need` field) instead
            -- of dropping the whole [Need:] block in one step.
            local n = needRowCount - 1
            while n >= 0 do
                segments.need = LF.ClassNeedString(cfg.classNeeds, n)
                msg = assemble()
                if #msg <= LF.MAX_LEN or n == 0 then break end
                n = n - 1
            end
            trimmed[#trimmed + 1] = "need"
        elseif segments[name] ~= "" then
            segments[name] = ""
            trimmed[#trimmed + 1] = name
            msg = assemble()
        end
    end
```

- [ ] **Step 3: Repo-wide check for other `MAX_NEED_PARTS` references**

Run: `grep -rn "MAX_NEED_PARTS" AutoInvitePlus/` — expected: no matches remain in `.lua` files (only `WIRING.md` may still mention it in prose, which Task 6 updates).

- [ ] **Step 4: Syntax-check**

Run the verification command against:
```
d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/modules/LFMFormat.lua
```
Expected: `OK`.

- [ ] **Step 5: In-game manual check**

`/reload`, open the popup, switch to Detailed, template-select a 25-man raid, check 6+ different class/spec boxes with counts > 0. Confirm the live PREVIEW shows all of them in `[Need: ...]` (no "+N" collapse) as long as the message still fits under 255 chars; if you deliberately pad the Note field to force overflow, confirm the need list now shrinks entry-by-entry (dropping from the tail, adding "+N" for the remainder) rather than vanishing entirely while Note/Achievement are still present.

- [ ] **Step 6: Commit**

```bash
git add AutoInvitePlus/modules/LFMFormat.lua
git commit -m "Remove the 5-entry need cap; trim gracefully under real byte pressure"
```

---

### Task 5: DataBus wire hygiene — 3-way `dm` codes, verify no leftover fields

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua` (`GUI.MaybeDataBusBroadcast`)
- Modify: `AutoInvitePlus/data/ChatScanner.lua` (the `OnDataBusLFM` receiver — the block starting `local detailMode = (data.dm == "V" ...`)
- Modify: `AutoInvitePlus/core/DataBus.lua` (the `dm` field's doc comment in `DB.EventTypes`)

**Interfaces:**
- Produces: wire value `dm` ∈ `{"D", "C", "M"}` (was `{"D", "V"}`).
- Consumes: `popup.detailMode`/`GUI.MyGroup.detailMode` ∈ `{"minimal","compact","detailed"}` (from Task 1).

- [ ] **Step 1: Update the sender (`GUI.MaybeDataBusBroadcast`)**

Find:
```lua
        local MyG = GUI.MyGroup
        local LF = AIP.LFMFormat
        local vague = (MyG.detailMode == "vague")
        local specsStr = (not vague) and LF and LF.EncodeRoleSpecs(MyG.roleSpecs) or ""
        local needStr = (not vague) and LF and LF.EncodeNeeds(MyG.classNeeds) or ""
        AIP.DataBus.BroadcastLFM({
            raid = MyG.raid,
            comp = LF and LF.EncodeComp(MyG) or nil,
            tanks = MyG.tanks,
            healers = MyG.healers,
            mdps = MyG.mdps,
            rdps = MyG.rdps,
            gsMin = (MyG.gsMin and MyG.gsMin > 0) and MyG.gsMin or nil,
            ilvlMin = (MyG.ilvlMin and MyG.ilvlMin > 0) and MyG.ilvlMin or nil,
            triggerKey = MyG.inviteKeyword,
            specs = specsStr ~= "" and specsStr or nil,
            need = needStr ~= "" and needStr or nil,
            dm = MyG.detailMode and (vague and "V" or "D") or nil,
            note = (MyG.note and MyG.note ~= "") and MyG.note or nil,
            weekly = (MyG.weekly and MyG.weekly ~= "") and MyG.weekly or nil,
        })
```
and replace with:
```lua
        local MyG = GUI.MyGroup
        local LF = AIP.LFMFormat
        local detailed = (MyG.detailMode == "detailed")
        local specsStr = detailed and LF and LF.EncodeRoleSpecs(MyG.roleSpecs) or ""
        local needStr = detailed and LF and LF.EncodeNeeds(MyG.classNeeds) or ""
        local dmCode
        if MyG.detailMode == "detailed" then dmCode = "D"
        elseif MyG.detailMode == "minimal" then dmCode = "M"
        elseif MyG.detailMode then dmCode = "C"
        end
        AIP.DataBus.BroadcastLFM({
            raid = MyG.raid,
            comp = LF and LF.EncodeComp(MyG) or nil,
            tanks = MyG.tanks,
            healers = MyG.healers,
            mdps = MyG.mdps,
            rdps = MyG.rdps,
            gsMin = (MyG.gsMin and MyG.gsMin > 0) and MyG.gsMin or nil,
            ilvlMin = (MyG.ilvlMin and MyG.ilvlMin > 0) and MyG.ilvlMin or nil,
            triggerKey = MyG.inviteKeyword,
            specs = specsStr ~= "" and specsStr or nil,
            need = needStr ~= "" and needStr or nil,
            dm = dmCode,
            note = (MyG.note and MyG.note ~= "") and MyG.note or nil,
            weekly = (MyG.weekly and MyG.weekly ~= "") and MyG.weekly or nil,
        })
```

- [ ] **Step 2: Update the receiver (`data/ChatScanner.lua`)**

Find:
```lua
    local detailMode = (data.dm == "V" and "vague") or (data.dm == "D" and "detailed") or nil
```
and replace with:
```lua
    local detailMode = (data.dm == "D" and "detailed") or (data.dm == "C" and "compact")
        or (data.dm == "M" and "minimal") or nil
```

- [ ] **Step 3: Update the `DB.EventTypes` doc comment**

Find:
```lua
            "dm",           -- string: "D" detailed / "V" vague listing mode
```
and replace with:
```lua
            "dm",           -- string: "D" detailed / "C" compact / "M" minimal listing mode
```

- [ ] **Step 4: Verify no leftover fields — read, don't guess**

Re-read `AutoInvitePlus/core/DataBus.lua`'s `DB.BroadcastLFM` function (the oversize-shedding ladder) and confirm `event.data.specs`/`event.data.need` are only ever populated when the sender actually set them (Step 1 above already guarantees `specsStr`/`needStr` are empty strings, and therefore `nil` in the payload table, for Minimal/Compact) — no code change expected here, this step is a read-and-confirm, not a blind edit. If you find `specs`/`need` populated for a non-Detailed mode, stop and report it rather than silently patching around it — it would mean Step 1 has a bug.

- [ ] **Step 5: Syntax-check**

Run the verification command against:
```
d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/ui/CentralGUI.lua d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/data/ChatScanner.lua d:/tmp/AutoInvitePlus-3.3.5a/AutoInvitePlus/core/DataBus.lua
```
Expected: `OK` for all three.

- [ ] **Step 6: In-game manual check (requires two AIP clients, or `/aip testdata` + reading SavedVariables)**

Post a listing in each of the 3 modes in turn with broadcasting enabled, and on a second client (or via `/aip databus` debug output if available) confirm: Minimal/Compact listings never carry `specs`/`need` in the received event data, and Detailed listings do. Confirm the Group Details panel (browser) on the receiving side shows the class breakdown only for the Detailed listing.

- [ ] **Step 7: Commit**

```bash
git add AutoInvitePlus/ui/CentralGUI.lua AutoInvitePlus/data/ChatScanner.lua AutoInvitePlus/core/DataBus.lua
git commit -m "3-way DataBus dm wire codes (D/C/M) for Minimal/Compact/Detailed"
```

---

### Task 6: Update WIRING.md

**Files:**
- Modify: `AutoInvitePlus/WIRING.md`

**Interfaces:** None (documentation only).

- [ ] **Step 1: Rewrite the "Vague vs detailed listings (composition detail mode)" section**

Find the section starting `## Vague vs detailed listings (composition detail mode)` (it documents `AIP.db.lfmDetailMode`, the "Detailed" checkbox, `BuildConfig` nilling fields, and `CS.AddGroup`'s merge rules) and rewrite it as `## Minimal/Compact/Detailed listings (composition detail mode)`, covering:
- The three modes and what UI section each shows (Composition row vs Class grid; both hidden for Minimal).
- `ApplyDetailMode(mode)` replaces the old `SetClassGridEnabled`.
- `SyncCompositionFromClassGrid()` makes the class grid authoritative for role totals while Detailed is active.
- `BuildConfig` nils `roleSpecs`/`selectedClasses`/`classNeeds` for any mode other than `"detailed"` (was: only for `"vague"`).
- `RegenerateBroadcastMessage` now derives live `needed` totals from the decremented `classNeeds` list for Detailed listings (not just `current`), while Minimal/Compact keep the frozen-`needed`/live-`current` behavior.
- `CS.AddGroup`'s authoritative-overwrite merge rule already correctly clears stale detail fields on a mode downgrade (verified in Task 5, no code change was needed there).

- [ ] **Step 2: Update the "DataBus LFM wire format" section's `dm` line**

Find:
```
  "comp" "1/2,4/6,3/8,4/9" (T,H,M,R cur/needed), `specs`
  "T:PW,BDK H:HP ..." (RoleSpecString minus brackets), `need` "2xMag,1xPP"
  (uncapped), `dm` "D"/"V", plus note/weekly; empty optionals are omitted.
```
and change to:
```
  "comp" "1/2,4/6,3/8,4/9" (T,H,M,R cur/needed), `specs`
  "T:PW,BDK H:HP ..." (RoleSpecString minus brackets), `need` "2xMag,1xPP"
  (uncapped), `dm` "D"/"C"/"M" (detailed/compact/minimal), plus note/weekly;
  empty optionals are omitted (specs/need only sent for detailed listings).
```

- [ ] **Step 3: Update the `LF.ClassNeedString`/`MAX_NEED_PARTS` mention**

Find (in the "Segment order..." bullet under the tandem flow section):
```
   `LF.NeedCodes[role][class]`, `LF.ClassNeedString`, capped at
   `LF.MAX_NEED_PARTS = 5` rows + "+N").
```
and change to:
```
   `LF.NeedCodes[role][class]`, `LF.ClassNeedString(classNeeds, maxParts)` -
   full fidelity by default; `BuildLFM`'s overflow ladder shrinks it entry-
   by-entry ("+N" remainder) only under genuine 255-byte pressure).
```

- [ ] **Step 4: Commit**

```bash
git add AutoInvitePlus/WIRING.md
git commit -m "Update WIRING.md for the Minimal/Compact/Detailed mode toggle"
```

---

### Task 7: Full-repo syntax validation and final end-to-end check

**Files:** None modified — validation only.

- [ ] **Step 1: Full-repo syntax check**

Run the Global Constraints verification command, but pass every `.lua` file under `AutoInvitePlus/` (reuse the file-walking approach: list files with `find AutoInvitePlus -name '*.lua'` and pass them all as arguments). Expected: `OK` for all files, zero `FAIL` lines.

- [ ] **Step 2: End-to-end in-game walkthrough**

`/reload`, then in order:
1. Open the popup, confirm it defaults to whatever `AIP.db.lfmDetailMode` was last set to (or Detailed on a fresh profile).
2. Cycle Minimal -> Compact -> Detailed -> Minimal, confirming each mode's section visibility from Task 1's check still holds.
3. In Compact mode, manually edit the Tanks count, switch to Detailed, switch back to Compact — confirm the manual edit wasn't clobbered (Detailed-mode sync must not run while Compact is active).
4. In Detailed mode, check several spec boxes with counts, Post the listing.
5. Confirm the Group Details panel for your own posted listing (self-view) shows the full class breakdown.
6. If a second client/account is available, confirm the peer sees the same breakdown via DataBus, and that a Minimal or Compact repost of the same listing clears that breakdown on both ends (no leftovers).
7. Use `/aip testdata` to simulate a roster join matching one of the needed classes and confirm both the aggregate role count and the individual class-need count in the broadcast/preview shrink together (Task 3's behavior).

- [ ] **Step 3: Final commit (only if the walkthrough surfaced fixups)**

If Step 2 surfaces any bug, fix it in the relevant file, re-run the syntax check for that file, and commit with a message describing the specific fixup (not a generic "fixes"). If the walkthrough passes clean, no commit is needed for this task.

## Self-Review Notes

- **Spec coverage:** Section 1 (mode semantics/data model) -> Task 1 + Task 6. Section 2 (counter sync) -> Task 2 + Task 3. Section 3 (message composition + Group Details) -> Task 4 (message); Group Details panel was investigated during plan-writing and found to have **no artificial cap** (it renders the full `order` array onto a single clipped FontString line — the only limit is physical frame width, not a count), so no code task exists for it; this finding is folded into Task 7's walkthrough (Step 2.5) instead of a phantom fix. Section 4 (DataBus wire hygiene + non-goals) -> Task 5; the `CS.AddGroup` merge-rule concern was also investigated during plan-writing and found to already handle a mode downgrade correctly (the `authoritative` branch unconditionally overwrites with `info.X`, which is `nil` for a less-detailed repost) — Task 5 Step 4 verifies this by reading rather than re-implementing it.
- **Placeholder scan:** no TBD/TODO; every step has literal code or a literal grep/manual-check command.
- **Type consistency:** `popup.detailMode` values (`"minimal"|"compact"|"detailed"`), `dm` wire codes (`"D"|"C"|"M"`), and function names (`ApplyDetailMode`, `SyncCompositionFromClassGrid`, `UpdateModeButtonHighlight`) are used identically across Tasks 1-6.
