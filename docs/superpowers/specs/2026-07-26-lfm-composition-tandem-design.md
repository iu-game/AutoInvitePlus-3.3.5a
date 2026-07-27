# LFM <-> Raid Composition Tandem — Design

Date: 2026-07-26 | Target version: 6.8.0 (unreleased)

## Goal

Make the LFM listing flow and the raid-composition engine work in tandem:

1. The LFM create popup drives (and is driven by) the composition template system:
   selecting a template auto-selects the recommended classes/specs and shows
   per-class need counts.
2. Each class shows a count of how many players of that class (and suggested
   spec) are still needed, computed against the LIVE group.
3. Applicants (DataBus APPLY protocol) land on the **waitlist** and receive a
   personalized whisper verdict (GS vs minimum, role full, class position
   already covered, waitlist position).
4. The promotion/broadcast message carries the per-class need counts plus the
   occupied/total count, and both stay live as the raid fills.

## Non-goals / explicit decisions

- The plain **keyword-whisper auto-invite path in Core.lua is unchanged** — it
  is the addon's core promise (whisper keyword -> invite/queue). Only the
  structured APPLY protocol routes to the waitlist. Legacy queue routing stays
  available behind `AIP.db.applyToWaitlist = false`.
- **DataBus protocol shapes are unchanged.** APPLYACK still uses status
  `queued` + position (now the waitlist position). The personalized detail
  travels as a normal whisper, so non-AIP-visible text stays truthful.
- Peer parsing of the new `[Need: ...]` broadcast segment is NOT implemented
  (seekers still match via the existing `[T:...]` roleSpecs block, which is
  kept in the message). Only `Parsers.ParseAchievement` learns to skip the new
  bracket (and the pre-existing `[Res: ...]` bracket, a latent bug).
- Selecting a template in the LFM popup sets `Comp.CurrentRaid.template`
  (quietly) — the Composition tab and the popup intentionally share one active
  template. That IS the tandem.
- If the leader edits the role-count inputs after template selection, the
  class-need suggestions are not recomputed from those inputs; the role inputs
  stay authoritative for the `[T:x/y ...]` block, needs are recomputed from the
  template + live group at broadcast-regeneration time.

## Components

### data/RaidComposition.lua
- `Comp.SetTemplate(templateKey, quiet)` — existing, gains `quiet` flag (no chat print).
- `Comp.TemplateKeyForRaid(raidKey)` — NEW. Maps GUI raid keys (`ICC25H`,
  `EoE10N`, `Ony25H`, `TOGC25`, `FoS5H`, `OS25H`) to template keys
  (`ICC25HC`, `EOE10`, `ONYXIA25`, `TOGC25`, `FOS`, `OS25_3D`). Candidate
  order: exact -> OS `_3D/_0D` -> `TOC->TOGC` heroic -> `base..size..HC` ->
  `base..size` -> `base`. Returns nil for CUSTOM/unknown.
- `Comp.GetClassNeeds(templateKey)` — NEW. Quiet-sets the template if needed,
  runs `Comp.GetRecommendations()` (live ScanRaid), aggregates `rec.slots`
  ({role, class, buff}) into sorted rows `{class, role, count, buffs}`.
  Returns `{ok, list, occupied, total, gaps, full, templateKey}`.
- `Comp.SuggestedSpec(role, class)` — NEW. Display-only role+class -> WotLK
  standard spec name ("Protection", "Restoration", ...).

### modules/LFMFormat.lua
- `LF.NeedCodes[role][class]` + `LF.ClassNeedString(classNeeds)` — NEW.
  `{{class="MAGE", role="DPS", count=2}, ...}` -> `"[Need: 2xMag 1xPP]"`.
- `BuildLFM(cfg)` accepts `cfg.classNeeds`; the need block sits right after the
  counts block. Overflow drop order becomes: reserved -> note -> achievement ->
  specs -> need (need survives longest of the optional blocks).

### core/Parsers.lua
- `ParseAchievement` skips trailing brackets starting with `Need:` or `Res:`.

### modules/FitEngine.lua
- `ScoreApplicant` learns `listing.classNeeds`: applicant class+role on the
  need list with count > 0 -> +15 and reason "2x Mage needed"; class absent
  from a non-empty need list -> -10, soft fail, reason "... position covered".
  Role matching folds MDPS/RDPS/MELEE/RANGED into DPS. Hard role-full check is
  unchanged and still wins.

### modules/Waitlist.lua
- `AIP.AddToWaitlist(name, role, note, class, gs, silent)` — gains `silent`
  (skip the generic `responseWaitlist` whisper so callers can send a richer one).

### modules/Applications.lua (leader side)
- `onApply`: blacklist-decline and favorite/GREEN auto-invite lanes unchanged.
  Otherwise, when `AIP.db.applyToWaitlist` (default true): add to waitlist
  (silent), enrich the entry with spec/ilvl/weekly/isApplication, ACK
  `queued #<waitlist-pos>`, and whisper `Apply.BuildFeedback(...)` — header
  `[AIP] <raid>: waitlist #N` + the top FitEngine reasons joined with "; ",
  capped at 255 bytes. FitEngine stays the single verdict source; the whisper
  never invents its own checks. `applyToWaitlist=false` -> legacy queue path.
- `Apply.SendFeedbackWhisper` gated by `AIP.db.applyFeedbackWhisper` (default
  true); plain `SendChatMessage` WHISPER (whispers bypass ChatGate by design).

### ui/CentralGUI.lua
- `CreateAddGroupPopup`:
  - `ApplyTemplateDefaults` additionally resolves the template key, calls
    `Comp.GetClassNeeds`, stores `popup.classNeeds`/`popup.classNeedsMeta`,
    auto-checks ONLY the recommended classes' spec checkboxes (role-label
    toggles still allow check-all), and renders a colored "Need:" summary line
    (new FontString in the detail frame; layout shifted down 20px,
    EXPANDED_HEIGHT 668 -> 688).
  - `BuildConfig` passes `classNeeds` to `BuildLFM` (live preview shows it).
  - Post button stores `classNeeds` + `templateKey` into both the GroupTracker
    record and `GUI.MyGroup`.
- `RegenerateBroadcastMessage` recomputes `Comp.GetClassNeeds(templateKey)` on
  every regeneration (roster changes) and syncs it into ownGroup/MyGroup before
  building the message — the broadcast's `[x/y]` and `[Need: ...]` stay live.

### core/Core.lua
- defaults: `applyToWaitlist = true`, `applyFeedbackWhisper = true`.
- `/aip needs` slash subcommand: prints the current class-need rows (debug/UX
  helper), documented in `/aip help`.

## Data flow (tandem loop)

```
Template select (popup) -> Comp.SetTemplate(quiet) -> Comp.GetClassNeeds
  -> auto-check recommended specs + "Need:" line + preview [Need:] block
Post -> MyGroup{classNeeds, templateKey} + GroupTracker record + broadcast
Roster change -> RegenerateBroadcastMessage -> Comp.GetClassNeeds (live)
  -> updated [x/y] + [Need:] in the rotor broadcast
APPLY (DataBus) -> FitEngine.ScoreApplicant(applicant, MyGroup w/ classNeeds)
  -> blacklist: declined | favorite/GREEN+opt-in: invited
  -> else: Waitlist (silent) -> APPLYACK queued #pos + feedback whisper
Waitlist invite/decline -> existing Apply.NotifyInvited/Declined ACKs
```

## Error handling

- All cross-module calls guarded (`if AIP.Composition and ... then`) per the
  namespace convention; missing modules degrade to the pre-feature behavior.
- `TemplateKeyForRaid` returning nil (CUSTOM/unknown raid) disables the needs
  features for that listing without touching checkboxes.
- Whisper sends wrapped in pcall (as the existing Waitlist sender does).

## Testing

No toolchain: syntax-validate all touched files with Python `luaparser`;
in-game verification via `/aip testdata`, `/aip needs`, popup preview, and
`/aip fit <name>`. Post-implementation: independent adversarial review agents
(wiring/regression/Lua-5.1 lenses) before calling it done.
