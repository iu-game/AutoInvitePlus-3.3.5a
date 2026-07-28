# WIRING.md — Matchmaking / Composition wiring map

Purpose: a compact, always-current map of the LFM/LFG matchmaking loop and the
LFM <-> RaidComposition tandem, so future changes can be planned WITHOUT
re-reading the large files. **Update this file whenever you change any wiring
listed here.** Line numbers are intentionally omitted (they rot); search for
the function names.

## Module inventory (load order = .toc order)

| File | Namespace | Owns |
|---|---|---|
| core/Utils.lua | `AIP.Utils` | Events pub/sub, `DelayedCall`, name normalization (`NormalizeName`), `RenumberPriorities(list)` (queue/waitlist .priority re-stamp), `FoldRole(role)` (MDPS/RDPS/MELEE/RANGED -> DPS) |
| core/Parsers.lua | `AIP.Parsers` | chat parsing: `ParseChatMessage`, `ParseAchievement` (skips `[T:..]`, `[Need:..]`, `[Res:..]` brackets), `ParseLookingFor`, `MatchesLookingFor` |
| core/ChatGate.lua | `AIP.ChatGate` | ALL public/guild outbound chat budget (`CG.Send`). Whispers + DataBus bypass by design |
| core/DataBus.lua | `AIP.DataBus` | peer protocol; `EventTypes` LFM/LFG/PING/PONG/GEAR/APPLY/APPLYACK; `CreateEvent`/`Broadcast(ev, target?)`/`Subscribe` |
| core/Core.lua | `AIP.*` globals | `defaults` (SavedVariables), central event frame, `ProcessMessage` -> keyword invite/queue, `InvitePlayer` (fires `Apply.NotifyInvited`), `SlashHandler` (incl. `/aip needs`, `/aip fit`) |
| data/ChatScanner.lua | `AIP.ChatScanner` | LFM/LFG listing store (`CS.Groups`, `CS.Players`), `MatchesMyLFM` auto-queue gate |
| data/RaidComposition.lua | `AIP.Composition` (`Comp`) | templates, buffs, `ScanRaid`, recommendations, **class-needs tandem engine** |
| modules/LFMFormat.lua | `AIP.LFMFormat` (`LF`) | THE only LFM/LFG string builder (255-byte trim) |
| modules/FitEngine.lua | `AIP.FitEngine` (`Fit`) | THE only fit verdict (`ScoreApplicant`, `ScoreListing`) |
| modules/Applications.lua | `AIP.Apply` | APPLY/APPLYACK transport + state; **waitlist routing + feedback whisper** |
| modules/Queue.lua | `AIP.AddToQueue` etc. | whisper-keyword queue (legacy APPLY routing when `applyToWaitlist=false`) |
| modules/Waitlist.lua | `AIP.AddToWaitlist` etc. | waitlist store + whispers + UI |
| ui/UIFactory.lua | `AIP.UI` | widget builders, `UI.Colors` palette (+ `roleRGB` role tints), `UI.MakeDraggable(frame)` |
| ui/CentralGUI.lua | `AIP.CentralGUI` (`GUI`) | main window/tabs, AddGroupPopup (LFM create), `MyGroup`, broadcast rotor, `RegenerateBroadcastMessage`, `UpdateQueuePanel`, `FilterClassNeedsBySelection`, layout constants + `ApplyColumnLayout` (QUEUE/LFG/WAITLIST_COLS live here) |
| ui/CentralGUIBrowser.lua | `AIP.CentralGUI` (same table) | **split file** (RaidTools precedent): `CreateBrowserTab` (browser tree + queue/LFG/waitlist sub-tab rows and their action buttons), `CreateInspectionPanel`. Loads AFTER CentralGUI.lua; runtime-only calls |
| ui/CentralGUIPopups.lua | `AIP.CentralGUI` (same table) | **split file**: `Show/CreateAddToQueuePopup`, `Show/CreateAddToWaitlistPopup` (frame names `AIPAddToQueuePopup`/`AIPAddToWaitlistPopup`) |

## Key data shapes

- **Listing** (`GUI.MyGroup` and GroupTracker/ChatScanner records):
  `{raid, weekly, gsMin, ilvlMin, tanks/healers/mdps/rdps = {current, needed},
  inviteKeyword, roleSpecs = {TANK={codes},HEALER,MDPS,RDPS}, selectedClasses,
  classNeeds = {{class, role, count, buffs}}, templateKey, note, time}`
  - `classNeeds`/`templateKey` are the tandem fields (6.8): set at Post time by
    the popup, refreshed on every `RegenerateBroadcastMessage`.
- **Class-need row** (from `Comp.GetClassNeeds().list`):
  `{class = "MAGE", role = "TANK"|"HEALER"|"DPS", count = n, buffs = {names}}`
- **Applicant** (APPLY event data): `{raid, role, class, spec, gs, ilvl, weekly, note}`
- **Waitlist entry**: `{name, role, addedTime, priority, note, class, gs,
  isBlacklisted, blacklistReason}` + (protocol applicants) `{spec, ilvl,
  weekly, isApplication = true}`. `AIP.MoveToWaitlist` (queue -> waitlist)
  folds role via `AIP.Utils.FoldRole` and carries isBlacklisted/blacklistReason
  over; `AIP.AddToWaitlist` self-checks blacklist status (mirrors
  `AIP.AddToQueue`) rather than requiring the caller to pass it.
- **Fit result**: `{score 0-100, verdict = "RED"|"YELLOW"|"GREEN", reasons = {}}`

## Tandem flow: template -> popup -> broadcast

1. `GUI.CreateAddGroupPopup` raid/size/heroic/preset select ->
   `ApplyTemplateDefaults()` ->
   - `GUI.RaidTemplateDefaults[raidKey]` fills role counts / GS / iLvl inputs
   - `UpdateClassNeeds(true)`:
     - `Comp.TemplateKeyForRaid(raidKey)` maps "ICC25H" -> "ICC25HC"
       (OS -> `_3D/_0D`, ToC heroic -> TOGC, no-HC raids fall back to normal,
       5-mans "FoS5H" -> "FOS", digit-run raid types "ToC55H"/"AQ4040N" ->
       "TOC5"/"AQ40" via digit-split candidates; CUSTOM/unknown -> nil =
       feature off)
     - `Comp.GetClassNeeds(templateKey)`: quiet template swap that
       **saves/restores** the Composition tab's template + gear variation
       (browsing the popup never hijacks the tab; only Post syncs it),
       `Comp.GetRecommendations()` (live `ScanRaid`; `pickRoleClass` uses
       simulated `simCounts` so recommended slots stay class-diverse;
       `firstWantedBuffForClass(class, role)` gates spec-restricted buffs
       (`Comp.RaidBuffs[x].specs`) against `Comp.SpecRole[class][spec]` so a
       role only gets credited with a buff a compatible spec actually brings -
       e.g. Replenishment/Retribution never attributed to a Paladin
       recommended as HEALER/Holy),
       aggregates `rec.slots` -> sorted class rows
     - `ApplyRecommendedSpecs(needs)`: auto-checks recommended classes' spec
       checkboxes AND prefills their **count boxes** (`check.countInput`; the
       class's count lands on its first spec, other specs stay checked at 0 =
       spec-flexible) — fires only when `popup.lastAutoSelectKey` changes
       (heroic/size re-toggles never wipe manual counts); role-label buttons
       still toggle all (counts 1/0)
     - `RenderNeedsSummary(cfg.classNeeds)` (called from `RefreshPreview`):
       single CLIPPED "Need (x/y): 2xMag 1xPP +3" line (`popup.needsText`,
       detail y -276, wrap off) mirrored into the collapsed one-line hint
       (`popup.collapsedNeedsText`, y -168, wrap off) — neither may ever wrap
       (they used to overlap the Note row / PREVIEW section)
   `GUI.ShowAddGroupPopup` also calls `UpdateClassNeeds(false)` on every open
   so re-opened popups never post stale needs. Popup width is 500 (per-spec
   count boxes need the room; `specSpacing = 76`).
2. **Each spec checkbox has a count box** (`makeSpecCheck` -> `check.countInput`,
   16px numeric): >0 auto-checks the box, unchecking zeroes it.
   `CollectRoleSpecs()` returns a 4th value `classNeeds` aggregated from the
   boxes (per class+role, MDPS/RDPS folded to DPS, sorted T/H/D) and
   `selectedClasses` entries carry `count`. `SyncCompositionFromClassGrid()`
   keeps the Tanks/Healers/MDPS/RDPS composition inputs summed from the SAME
   checked boxes whenever the grid changes or the mode switches to Detailed,
   so the composition totals and the class grid can never disagree.
   `BuildConfig()` passes classNeeds straight to `LF.BuildLFM(cfg)` ->
   `[Need: 2xMag 1xPP]` (codes: `LF.NeedCodes[role][class]`,
   `LF.ClassNeedString` — shows every row by default; only collapses tail
   entries into "+N" if the message doesn't fit under 255 bytes even after
   dropping reserved/note/achieve — see the overflow ladder below).
   Segment order: head, WQ, `[x/y][T:..]` counts, **need**, gs, ilvl, specs,
   keyword, achieve, note, res.
   Overflow drop order: reserved -> note -> achieve -> **need** -> specs
   (need drops BEFORE specs: `[T:..]` is the machine-readable peer signal).
3. Post button stores `cfg.classNeeds` + `templateKey` into the GroupTracker
   record (ChatScanner `CS.AddGroup` whitelists both fields — keep them when
   editing it) AND `GUI.MyGroup`, plus the live-decrement baseline:
   `MyGroup.classNeedsBase` (= posted counts) and `MyGroup.classCountsAtPost`
   (Comp.ScanRaid class snapshot); does ONE deliberate
   `Comp.SetTemplate(templateKey, quiet)` sync of the Composition tab, then
   `GUI.StartBroadcast("lfm", msg)` (ChatGate rotor).
4. Roster changes -> `GUI.RegenerateBroadcastMessage()`:
   - updates role `current` counts (ownGroup + MyGroup)
   - **decrements the POSTED counts**: joined-since-post classes (live
     `Comp.ScanRaid().classCounts` minus `classCountsAtPost`) are subtracted
     from `classNeedsBase` rows (class-level approximation — joiners' specs
     aren't inspectable); result -> `ownGroup.classNeeds` /
     `GUI.MyGroup.classNeeds`. Legacy listings without a baseline fall back to
     `Comp.GetClassNeeds` + `GUI.FilterClassNeedsBySelection`.
   - rebuilds the message via `LF.BuildLFM` -> `[x/y]` + `[Need:]` stay live.
5. Group Details (browser, ui/CentralGUIBrowser.lua + updater in
   CentralGUI.lua): "Looking for" renders as FOUR fixed role rows
   (`container.lookingForRoleLines` keyed TANK/HEALER/MDPS/RDPS, single
   clipped line each) listing the wanted classes as colored arrays, prefixed
   with the per-class counts when `data.classNeeds` is present; the hover
   tooltip keeps the full per-spec detail. `detailsPanel` height is 312 (the
   queue panel below is elastically anchored).

## Tandem flow: APPLY -> verdict -> waitlist -> whisper

`Applications.onApply` (DataBus `APPLY` subscriber), in order:
1. No `GUI.MyGroup` -> ACK `seen`.
2. Blacklisted -> ACK `declined`.
3. `Fit.ScoreApplicant(applicant, GUI.MyGroup)` — the ONLY judge. Inputs used:
   gsMin/ilvlMin, role slots (hard-fail when full), roleSpecs list,
   **`listing.classNeeds`** (+15 "2x Mage needed" / -5 informational
   "no open Mage need right now - position covered" — deliberately NOT a
   softFail because needs derive from the template and may lag hand-edited
   role counts; MDPS/RDPS fold into DPS), favorite/guild/weekly bonuses.
4. Favorite lane (smartInvite.prioritizeFavorites) or GREEN + `autoInviteGreen`
   -> `AIP.InvitePlayer` -> ACK `invited`.
5. Default (`AIP.db.applyToWaitlist ~= false`): role normalized
   MDPS/RDPS/MELEE/RANGED -> DPS (waitlist store/UI only knows T/H/D), then
   `AIP.AddToWaitlist(name, role, "[Apply] ...", class, gs, silent=true)`
   (silent skips both the generic whisper AND the "Added to waitlist" print) ->
   enrich entry (spec/ilvl/weekly/gs/class/isApplication) ->
   ACK `queued #<waitlist-pos>` (protocol shape unchanged) ->
   `Apply.SendFeedbackWhisper` (gated `applyFeedbackWhisper`; message =
   `Apply.BuildFeedback` = "[AIP] <raid>: queued #N (reason; ...)" - wording
   matches the `queued` ACK status the applicant's client just printed, first 4
   FitEngine reasons, <=255 bytes, plain `SendChatMessage` WHISPER). The
   favorite/GREEN fast lane relies on `AIP.InvitePlayer` -> `Apply.NotifyInvited`
   for its ACK (never sends one directly - would double-ACK).
6. `applyToWaitlist = false` -> legacy `AIP.AddToQueue` path, which now also
   sends the FitEngine feedback whisper (previously silently skipped it);
   `AIP.MoveToWaitlist` (queue -> waitlist) folds role via `AIP.Utils.FoldRole`
   and carries spec/ilvl/weekly/isApplication/isBlacklisted/blacklistReason
   over so the ACK wiring and blacklist indicator survive the move.

Truthful ACK ladder (must not regress): `Core.InvitePlayer` ->
`Apply.NotifyInvited`; queue reject -> `Apply.NotifyDeclined`;
**`AIP.RemoveFromWaitlist` and `AIP.ClearWaitlist` -> `Apply.NotifyDeclined`
for `isApplication` entries** — both skip players currently in the group
(out-of-band `/invite` case) and invited players (InvitePlayer clears
`Apply.incoming` first). `AIP.InviteFromWaitlist` -> `InvitePlayer` ->
invited ACK. The queue-panel waitlist rows' action buttons (in
ui/CentralGUIBrowser.lua) route through the modules — Inv/X via
`AIP.InviteFromWaitlist` / `AIP.RemoveFromWaitlist`, up/down via
`AIP.MoveWaitlistUp/Down` (position whispers), and the queue rows' "W" button
via `AIP.MoveToWaitlist` (field carry). Never re-add raw `InviteUnit` +
`table.remove` there: it silently breaks the ACK ladder.

## Settings added by the tandem (Core.lua defaults)

- `applyToWaitlist = true` — APPLY applicants -> waitlist (false = queue)
- `applyFeedbackWhisper = true` — send the verdict whisper

## Slash commands

- `/aip needs` — prints `Comp.GetClassNeeds` for `MyGroup.templateKey` (or the
  composition tab's active template), with suggested specs + buff notes.
- `/aip fit <name>` — FitEngine verdict debug (now includes class-need reasons).
- No top-level `/aip waitlist`/`/aip wait` — the real matchmaking waitlist is
  GUI-only (Queue panel Waitlist tab). `RosterManager`'s separate, vestigial
  waitlist store is reachable only via `/aip roster waitlist` so it can't be
  mistaken for the primary one (see core/Core.lua SlashHandler comment).

## Invariants (do not regress)

1. LFM/LFG strings are built ONLY by `AIP.LFMFormat` builders.
2. All public/guild chat via `AIP.ChatGate.Send`; whispers/DataBus stay ungated.
3. `AIP.FitEngine` is the only fit judge — the feedback whisper only words its
   `reasons`, never adds checks.
4. DataBus event fields are additive-only (LFM gained comp/specs/need/dm in
   6.8 — see the wire-format section); APPLYACK still `queued`/position. ALL
   payload length checks go through `DB.EffectiveLimit()`, never a raw 255.
5. `ParseAchievement` must skip `[Need:]`/`[Res:]`/`[T:..]` brackets — a new
   trailing bracket segment in BuildLFM needs a skip rule there.
6. Popup external contract: frame names `AIPAddGroupPopup`/`AIPAddGroupRaidType/
   Size/Achieve` and `popup.*` fields are used by `ShowAddGroupPopup` /
   `GUI.UpdateAchievementDropdown`.
7. New persisted settings go into `defaults` in Core.lua; DB_VERSION only bumps
   on structural migrations.

## Minimal / Compact / Detailed listings (composition detail mode)

- `AIP.db.lfmDetailMode` ∈ `"minimal" | "compact" | "detailed"` ("detailed"
  default), toggled by the 3-way mode row at the top of the AddGroupPopup
  detail frame (`popup.modeButtons[mode]`, built by `makeModeButton`;
  `ApplyDetailMode(mode)` shows/hides the Composition row and Class grid per
  mode and calls `ReflowDetailRows(mode)`). The choice persists and rides the
  listing as `MyGroup.detailMode` / GroupTracker `detailMode`. Legacy saved
  values normalize on load: `"vague"` -> `"compact"` (both in memory and
  written back to `AIP.db.lfmDetailMode`).
  - **Minimal**: only the Note field is shown/editable; Composition row and
    Class grid are both hidden. `classHint` reads "(note only)".
  - **Compact**: the Composition row (Tanks/Healers/MDPS/RDPS counters) is
    shown; the Class grid is hidden. `classHint` reads "(role counts only)".
  - **Detailed**: the Class grid is shown (per-class/spec checkboxes + count
    boxes); the Composition row is hidden — `SyncCompositionFromClassGrid()`
    keeps the (hidden) composition totals summed from the checked boxes so
    the numbers underneath stay correct even though the row isn't visible.
    `classHint` reads "(box = count)". `ApplyDetailMode` calls this sync on
    EVERY switch into Detailed, so a manual Compact-mode composition edit is
    intentionally overwritten by the grid's numbers on a Compact -> Detailed
    -> Compact round trip — the grid is the single source of truth whenever
    Detailed is (or has been) active during that popup session.
  - All other fields (Requirements, Achievement, Note, Invite Keyword,
    Broadcast checkbox, Reserved Items) are always visible in all 3 modes.
    `ReflowDetailRows(mode)` repositions every row below the mode-specific
    section per mode (`ROW_Y`/`CONTENT_BOTTOM` tables) and resizes the popup
    (`popup.expandedHeightForMode`) so hiding a section reclaims its space
    instead of leaving dead space — there is no per-mode fixed layout, only
    this one dynamic reflow.
- Minimal/Compact: `BuildConfig` nils roleSpecs/selectedClasses/classNeeds ->
  the message carries ONLY `[x/y] [T:x/y ...]` (Minimal's note-only intent
  and Compact's role-counts-only intent are both satisfied by the SAME
  stripped payload — they differ only in what the popup UI itself shows/
  lets the leader edit, not in what gets broadcast); FitEngine skips all
  class/spec scoring (its checks are nil-guarded); `RegenerateBroadcastMessage`
  never re-injects class detail for either mode (the guard checks
  `detailMode ~= "detailed"`, not a single "vague" value, and clears
  classNeeds AND roleSpecs/selectedClasses on the record + MyGroup).
- Detailed: `RegenerateBroadcastMessage` derives the aggregate `[x/y]` role
  totals (Tanks/Healers/MDPS/RDPS `.needed`) from the SAME live-decremented
  `classNeeds` list that drives `[Need:]`, instead of the frozen posted
  value — so the header count and the per-class breakdown shrink together as
  recruits join and can never disagree. DPS splits back across mdps/rdps
  proportionally to their current posted ratio.
- `CS.AddGroup` merge rules (three-way, in this order):
  1. **Authoritative overwrite** — caller passed `isOwn=true` (GroupTracker
     Post path) OR the update is a DataBus event carrying `detailMode`
     (6.8+ full-state snapshot): the five class-detail fields
     (selectedClasses/roleSpecs/lookingForSpecs/classNeeds/detailMode) are
     REPLACED, so a Minimal/Compact re-post / needs-hit-zero clears stale
     detail. Exception: `info.specsTrimmed` (detailed DataBus event whose
     specs were shed by the length ladder) keeps the fuller chat-learned
     roleSpecs/lookingForSpecs and count-merges classNeeds instead of wiping.
  2. **Peer chat scan** — or-merge (chat segments can be trimmed).
  3. **Own chat ECHO** (author == player but caller did NOT set isOwn) —
     detail fields untouched: the echo is lossy (capped [Need:], no
     detailMode/selection) and must never clobber the precise record.

## DataBus LFM wire format (6.8)

- The legacy payload (four `{current,needed}` dicts + nested roleSpecs table)
  serialized past the message cap for ANY detailed listing — every one was
  silently dropped. Senders now ALSO emit compact strings via the LFMFormat
  codec: `comp` "1/2,4/6,3/8,4/9" (T,H,M,R cur/needed), `specs`
  "T:PW,BDK H:HP ..." (RoleSpecString minus brackets), `need` "2xMag,1xPP"
  (uncapped), `dm` "D" detailed / "C" compact / "M" minimal, plus note/weekly;
  empty optionals are omitted. `specs`/`need` are only ever encoded when
  `detailMode == "detailed"` (`GUI.MaybeDataBusBroadcast`) — Minimal and
  Compact broadcasts never carry class detail on the wire, matching what
  they show in chat.
- Codec lives in modules/LFMFormat.lua: `EncodeNeeds/DecodeNeeds` (via the
  `LF.NeedCodeInfo` reverse map — NeedCodes are globally unique across
  roles), `EncodeComp/DecodeComp`, `EncodeRoleSpecs/DecodeRoleSpecs`
  (decode = wrap in brackets -> `Parsers.ParseLookingFor`).
- `DB.EffectiveLimit()` = maxMessageLength − transport overhead (prefix+tab
  on SendAddonMessage / "!A:" on the channel) — the old raw-255 check let
  252-255-byte messages pass and then die at the transport. Used by ALL
  length checks (incl. `DB.SendChannelMessage`, checked pre-prefix — it used
  to compare the post-prefix `fullMessage` against a raw `maxMessageLength`).
  `DB.Broadcast` only stamps `DB.State.lastBroadcast[type]` (the per-type rate
  gate) AFTER the length check succeeds, so a dropped oversized broadcast
  doesn't burn the rate-limit window for a subsequent valid one.
- `ChatFilter` (hides our `!A:`-prefixed messages from chat frames) checks the
  channel name matches `DB.Config.channelName` before hiding — it used to hide
  ANY channel message starting with the literal prefix text, addon-wide.
- `DB.BroadcastLFM` oversize ladder: shed legacy role dicts (mirrored by
  `comp`) -> trim `need` tail entries -> drop note -> drop specs -> drop
  need. Receiver (`OnDataBusLFM`) prefers explicit dicts, falls back to
  `comp`; decodes specs/need/dm and flags `specsTrimmed` when a detailed
  event carries need but no specs.
- Chat side: `Parsers.ParseClassNeeds` decodes the `[Need: 2xMag 1xPP +3]`
  block (same codec; "+N" overflow ignored) into `info.classNeeds` for peer
  LFM chat — chat trims need BEFORE specs, DataBus sheds specs before need,
  so the two transports complement each other on receivers.
- Group Details role rows (CentralGUI updater): spec-code classes first, then
  classes present only in classNeeds (pure-ranged -> Ranged row, others ->
  Melee; skipped when the class already has DPS spec codes on either row);
  a row with no class detail falls back to the truthful role count
  ("N more"/"full"/"-") — that's what a Minimal/Compact listing shows.

## Template binding (LFM popup <-> Composition)

- Popup raid/size/heroic select -> `UpdateClassNeeds` PERSISTENTLY
  `Comp.SetTemplate`s and refreshes `GUI.UpdateCompositionTab` — but ONLY
  while the popup `IsShown()` (creating/re-opening it computes needs
  non-destructively via GetClassNeeds save/restore, so the tab is never
  hijacked by a popup the user didn't interact with). `Comp.GetClassNeeds`
  keeps its save/restore for other callers (regen fallback, /aip needs).
- Composition tab dropdown + standalone CompositionUI dropdown ->
  `GUI.SyncPopupToTemplate(key)`: reverse-maps via `GUI.RaidKeyForTemplate`
  (brute-forces RaidSizeInfo with GetRaidKey's rules) and re-points the popup;
  custom templates map to raidType CUSTOM with the template name in the
  custom-name box. Recursion-safe: both directions no-op when already bound.

## Custom templates

- `Comp.RegisterCustomTemplate/DeleteCustomTemplate/LoadCustomTemplates/
  SaveCurrentAsTemplate` (data/RaidComposition.lua) — registered into the same
  `Comp.RaidTemplates` registry (category `CUSTOMTPL`, `custom = true`,
  key `CT_<SLUG>`), persisted in `AIP.db.customCompTemplates`, re-registered
  by Core on ADDON_LOADED (data file loads before the DB).
  `Comp.RegisterCustomTemplate` returns `(key, err)`: a fresh save (`skipSave`
  falsy) that would slug-collide with a differently-named existing custom
  template is rejected with an error message instead of silently overwriting;
  `Comp.LoadCustomTemplates`'s own re-registration (`skipSave = true`) is
  exempt. `Comp.GetTierInfo` buckets a `CUSTOMTPL` template's GS/iLvl display
  range by its own saved `minGS` against `Comp.ContentTiers` (or shows "no GS
  requirement set" if `minGS` is 0) instead of defaulting to a fabricated
  T10N/ICC-tier range.
- `AIP.ResetDefaults` (core/Core.lua)'s `preserve` allow-list includes
  `customCompTemplates` — Settings > "Reset to Defaults" must never wipe
  saved custom templates.
- `Comp.TemplateKeyForRaid` matches custom templates by NAME (the popup's
  CUSTOM raid key is free text), so the whole tandem works on them.
- `Comp.GetTemplateVariations` returns a single "Saved" variation for custom
  templates (their saved tanks/healers/dps verbatim) — the generic gear-plan
  would override the snapshot's role split.
- UI: composition tab "Save Group" button (StaticPopup `AIP_SAVE_COMP_TEMPLATE`)
  snapshots the CURRENT group via `Comp.SaveCurrentAsTemplate` (works as a
  member of someone else's raid); `/aip comp savetpl <name>` / `deltpl <name>`.

## Loot database (AIP.LootDB, data/LootDB.lua)

- Atlas-style `LDB.Instances` -> bosses -> items {id, name, slot, hc, rate,
  note}; accessors `GetInstance(key)` (strips HC suffix), `FindItem(itemID)`
  (lazy id index — returns only the FIRST boss for an item; some tier tokens
  drop from several bosses in the same raid), `LDB.FindItemAll(itemID)`
  (returns every `{item, boss, inst}` hit — use this when a caller must be
  honest about a multi-source item, e.g. LootHistoryPanel's tooltip),
  `Link(item)` (name-guarded GetItemInfo link, text
  fallback); GetItemInfo warm-cache walker on login. `LDB.Request(id)` force-
  caches an item via a hidden-tooltip SetHyperlink (once per id, on-demand
  ONLY — visible browser rows/tooltips, never a mass sweep; a wrong id would
  be a 3.3.5a disconnect vector, which is why nil-id rows never call it).
- Reserved Items screen (RaidManagementPanel): "Browse" button ->
  `RM.ShowLootBrowser()` dialog (instance/boss dropdowns + item rows; click
  adds the link to the reserved editbox — OnTextChanged persists it;
  shift-click inserts into chat). Unresolved rows call `LDB.Request` and a
  1s repoll (budgeted: 6 tries, reset on progress/dropdown/scroll, armed
  only while `IsShown()` — Show() must precede the first Refresh) re-renders
  until real links appear. Row tooltips show the full item stats
  (SetHyperlink) + Drops from/Slot/Drop rate/note.
- Loot history: row tooltips cross-reference `LDB.FindItem` -> "Drops from:
  <boss> - <instance> (~rate%)".
- `rate` is honest-only (nil unless genuinely known); item names are the
  name-guard — never ship a guessed id with a real-looking name.

## Refactor notes (DRY + split, this changeset)

- **CentralGUI split** follows the RaidTools multi-file precedent: all three
  ui/CentralGUI*.lua files share ONE `AIP.CentralGUI` table; the later files
  contain only function definitions (no load-time execution). New .lua files
  are NOT picked up by `/reload` on 3.3.5a — `InitializeTabs` guards the
  `CreateBrowserTab` call with a "log out and back in" hint for in-place
  updates. Layout constants + column specs stayed in CentralGUI.lua.
- **Shared helpers — use these, don't re-inline:** `AIP.Utils.NormalizeName`
  (name trim+Propercase), `AIP.Utils.RenumberPriorities`, `AIP.Utils.FoldRole`,
  `AIP.UI.MakeDraggable`, `AIP.UI.Colors` (incl. `roleRGB`),
  `GUI.FilterClassNeedsBySelection`.
- Waitlist rows in the queue panel show fit chips (`FitEngine.Chip` on
  `isApplication` entries vs `GUI.MyGroup`), class-colored names, and a GS
  column; the status footer appends the first 3 class-need rows; the
  AddGroupPopup shows a one-line needs hint in collapsed mode
  (`popup.collapsedNeedsText`).

## Extension points

- Peer-side `[Need:]` parsing IS implemented (`Parsers.ParseClassNeeds`,
  wired into `ParseChatMessage`); `Fit.ScoreListing` now also scores
  `listing.classNeeds` symmetrically with `ScoreApplicant` (class-level: "they
  need Nx your class" +15 / informational -5) - spec-level need matching on
  the seeker side remains an extension point.
- Browser "Locked" filter (`TreeBrowser.HideLocked`) defaults ON (own
  listings stay exempt in both filter paths).
- `Comp.SuggestedSpec(role, class)` is display-only; enforcement would belong
  in FitEngine (spec-level need matching).
- Waitlist auto-invite by class need (invite the waitlisted player who closes
  the biggest need) would hook `AIP.InviteNextFromWaitlist(role)`.
