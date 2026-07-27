# LFM Popup: Minimal / Compact / Detailed Mode Toggle — Design

Date: 2026-07-27 | Target version: 6.8.0 (unreleased) | Builds on the
2026-07-26 LFM<->Composition tandem design.

## Goal

Replace the AddGroupPopup's binary "Detailed" checkbox with a 3-way toggle —
**Minimal / Compact / Detailed** — that changes which section of the popup is
shown, while keeping the underlying composition data (and the broadcast
message it produces) correct and internally consistent no matter which mode
is active:

1. **Minimal**: only the Note field (+ the always-visible Requirements/
   Achievement/Keyword/Broadcast/Reserved-Items rows) is shown. Composition
   row and Class grid are hidden.
2. **Compact**: the Composition row (Tanks/Healers/MDPS/RDPS numeric boxes)
   is shown and editable; the Class grid is hidden. This is today's "vague"
   mode, renamed.
3. **Detailed**: the Class grid (selectable classes/specs with per-spec need
   counts) is shown; the Composition row is hidden — its values are now
   *derived* from the class grid instead of typed directly.
4. Selecting a raid template always populates the underlying composition
   data regardless of which mode is active — hidden fields still get the
   template's numbers.
5. Aggregate role totals and per-class need counts never disagree with each
   other, and both live-update (decrement) as matching players join the
   group, in Detailed mode.
6. The DataBus payload and the chat message both reflect exactly the active
   mode's content, with no leftover fields from a previously-selected mode.

## Non-goals / explicit decisions

- **Popup height/layout stays fixed.** Hidden sections leave their vertical
  space blank rather than reflowing the rows below them (Requirements,
  Achievement, Note, Keyword, Broadcast, Reserved Items keep their existing
  fixed Y offsets in all 3 modes). Dynamic reflow was considered and rejected
  as unnecessary complexity/regression risk for a cosmetic gap.
- **`ApplyRecommendedSpecs`'s recommendation logic is unchanged** — template
  + live raid still drive which specs get auto-checked. A manual Compact-mode
  role-count edit does not feed back into Detailed-mode recommendations (same
  non-goal as the original tandem design).
- **The byte-overflow drop *priority order* is unchanged**
  (reserved -> note -> achieve -> need -> specs). Only the artificial
  `LF.MAX_NEED_PARTS = 5` *display* cap is removed/replaced with graceful
  per-entry trimming (see LFMFormat below) — genuine 255-byte overflow is a
  real WoW chat limit, not something this feature can remove.
- **No 4th message shape for Minimal** — Minimal broadcasts exactly what
  Compact broadcasts (`[x/y]` role counts, no class detail); only the popup
  UI is stripped down for Minimal.
- Renaming `"vague"` -> `"compact"` is a free rename, not a migration: the
  tandem feature (and its wire format) is unreleased, so there's no shipped
  peer/SavedVariables format to stay compatible with.

## Components

### ui/CentralGUI.lua (`GUI.CreateAddGroupPopup`)

- Replace `detailModeCheck` (single CheckButton) with a 3-segment toggle
  (three small buttons, visually consistent with the existing role-label
  toggle buttons) bound to `popup.detailMode` ∈
  `{"minimal", "compact", "detailed"}`. Persists to `AIP.db.lfmDetailMode`
  (default `"detailed"`, unchanged default).
- New `popup.compositionRowWidgets` table (mirrors `popup.classGridWidgets`):
  `compLabel`, `tankLabel/Container`, `healLabel/Container`,
  `mdpsLabel/Container`, `rdpsLabel/Container`.
- `SetClassGridEnabled(enabled)` is replaced by
  `ApplyDetailMode(mode)`, which fully **Show()/Hide()** (not just
  dim/disable) `compositionRowWidgets` and `classGridWidgets` per mode:
  - `"minimal"`: both hidden.
  - `"compact"`: composition shown, class grid hidden.
  - `"detailed"`: composition hidden, class grid shown.
  Also updates `classHint`'s text per mode (extend the existing
  vague-mode-hint pattern to a 3-way message).
- New `SyncCompositionFromClassGrid()`: sums checked `countInput` values in
  `popup.classChecks.TANK`/`.HEALER` directly into `tankInput`/`healInput`.
  `popup.classChecks.DPS` entries are split per-check by `specData.melee`
  (same test `CollectRoleSpecs` already uses to classify a DPS spec as MDPS
  vs RDPS) and summed into `mdpsInput`/`rdpsInput` respectively. Called from
  every per-spec checkbox `OnClick` and `countInput` `OnTextChanged` handler
  (alongside the existing `RefreshPreview()` call), but **only** takes effect
  when `popup.detailMode == "detailed"` — Compact-mode manual edits are not
  overwritten.
- `ApplyTemplateDefaults()` is unchanged in principle (still always sets
  `tankInput`/`healInput`/`mdpsInput`/`rdpsInput` from
  `GUI.RaidTemplateDefaults`) but must run **before** any Detailed-mode
  class-grid sync so a fresh template selection isn't immediately overwritten
  by a stale class-grid sum; `ApplyRecommendedSpecs` (which sets the
  per-spec count boxes from the template's recommendation) already runs
  after the role defaults are set, so `SyncCompositionFromClassGrid()` should
  run once more at the end of `ApplyTemplateDefaults()` when in Detailed mode
  so the composition-row mirror is correct immediately after a template
  change, not just after the next manual edit.
- `BuildConfig()`: unchanged in shape — still reads `tankInput`/etc as the
  `[x/y]` needed source. Correctness now depends on those inputs always being
  kept current (compact = direct edit, detailed = synced from class grid,
  minimal = template default), which the above changes guarantee.
- `RenderNeedsSummary` / `classHint`: extend the existing
  `detailMode == "vague"` branch to also cover `"minimal"`.

### ui/CentralGUI.lua (`GUI.RegenerateBroadcastMessage`)

- Currently reads `neededTanks/Healers/Mdps/Rdps` straight from
  `ownGroup.tanks.needed` etc. (frozen at post time). Change: when the
  listing's `detailMode == "detailed"`, after computing the live-decremented
  `classNeeds` list (existing `classNeedsBase`/`classCountsAtPost` logic,
  unchanged), **also** recompute each role's `needed` total as the sum of
  that role's rows in the just-decremented `classNeeds` list, and use that
  instead of the frozen value for the `BuildLFM` call and for
  `ownGroup.tanks.needed` (etc.) going forward. Minimal/Compact listings keep
  today's frozen-`needed`/live-`current` behavior (no per-class breakdown to
  derive a live total from).
- Extend the existing "vague guard" (which nils `classNeeds`/`roleSpecs`/
  `selectedClasses` on every regen for vague listings) to also cover
  `detailMode == "minimal"`, so a Minimal listing can never accumulate stale
  class detail from a template's recommendation engine on regeneration.

### modules/LFMFormat.lua

- `LF.MAX_NEED_PARTS` display cap removed. The `[Need: ...]` segment is now
  built from the *entire* `classNeeds` list by default.
- `BuildLFM`'s overflow handling for the `need` segment gains graceful
  per-entry trimming (mirroring what `DB.BroadcastLFM`'s wire-format ladder
  already does for the DataBus payload): if the full need list doesn't fit
  under the 255-byte cap even after the existing whole-segment drop order
  (reserved -> note -> achieve) has run, trim need entries from the tail one
  at a time (appending "+N" for the dropped remainder, same convention the
  popup's live preview already uses) instead of dropping the whole `[Need:]`
  block outright. `specs` (`[T:...]`) keeps its existing higher survival
  priority per the current invariant.

### core/DataBus.lua

- No new fields. Audit-and-fix pass on `DB.BroadcastLFM`/`DB.CreateEvent` to
  confirm `comp`/`specs`/`need` are genuinely *absent* from the serialized
  wire string (not just empty-string/empty-table) whenever the posted
  listing's mode is Minimal or Compact — i.e. the omission already documented
  as "empty optionals are omitted" must hold for all 3 modes, verified rather
  than assumed.
- `dm` wire value: `"D"` (detailed) / `"C"` (compact) / `"M"` (minimal),
  replacing `"D"`/`"V"`.

### data/ChatScanner.lua (`CS.AddGroup` merge rules)

- Verify (add a regression note to WIRING.md if a real gap is found) that
  the "authoritative overwrite" merge path — used both for the leader's own
  Post and for a DataBus full-state snapshot — actually replaces
  `roleSpecs`/`selectedClasses`/`classNeeds`/`detailMode` when a listing is
  **re-posted in a different, less-detailed mode** than its previous record
  (e.g. Detailed -> re-posted as Compact), not only in the already-documented
  "needs hit zero" case. This is what "no leftovers" means at the storage
  layer, complementing the wire-format check above.

### FitEngine / Applications / Waitlist / Queue

- No changes. All class/spec/need scoring is already nil-guarded per the
  existing vague-mode pattern; Minimal and Compact both score identically
  (role-open/GS checks only, no class-specific scoring), Detailed scores as
  today.

## Data flow (mode-driven)

```
Toggle click -> popup.detailMode = "minimal"|"compact"|"detailed"
  -> ApplyDetailMode(mode): show/hide Composition row + Class grid
  -> AIP.db.lfmDetailMode persisted
  -> RefreshPreview() (existing)

Template select -> ApplyTemplateDefaults() -> role-count inputs set from
  template -> ApplyRecommendedSpecs() (detailed: pre-checks specs) ->
  SyncCompositionFromClassGrid() (detailed only: mirrors class-grid sums
  back into the now-authoritative composition inputs)

Class-grid edit (detailed mode) -> SyncCompositionFromClassGrid() ->
  composition inputs updated -> RefreshPreview()

Post -> BuildConfig() reads composition inputs (now correct for any mode)
  + classNeeds (nil for minimal/compact) -> MyGroup/GroupTracker record
  stores detailMode + only the fields that mode implies -> BuildLFM ->
  DataBus broadcast (comp always; specs/need/dm omitted for minimal/compact)

Roster change -> RegenerateBroadcastMessage():
  detailed -> decrement classNeeds (existing) -> derive role `needed` totals
    from the decremented classNeeds sums (NEW) -> BuildLFM
  minimal/compact -> classNeeds cleared (vague-guard, extended to minimal)
    -> role `needed` stays at the frozen posted value, `current` live -> BuildLFM

Group Details panel (self view + peer view via ChatScanner/DataBus record)
  -> renders class breakdown when classNeeds present (detailed listings,
     now uncapped), else the truthful role-count-only row (minimal/compact)
```

## Error handling

- All new cross-module calls follow the existing guarded-call convention
  (`if AIP.Composition and ... then`).
- `SyncCompositionFromClassGrid()` no-ops safely if `popup.classChecks` is
  empty (shouldn't happen post-construction, but matches the codebase's
  defensive style elsewhere in this file).
- Mode toggle clicks are idempotent — clicking the already-active mode is a
  no-op (matches `SetExpanded`'s existing style).

## Testing

No toolchain: syntax-validate all touched files (this session already set up
`luaparse` via a throwaway npm install — reuse that for a pre-commit check).
In-game verification via `/aip testdata`, the popup's live PREVIEW box in all
3 modes, `/aip needs`, `/aip fit <name>`, and inspecting a peer's received
listing (via `/aip testdata` group records or a second client) to confirm the
Group Details panel and the actual chat text match the posted mode with no
leftover fields.
