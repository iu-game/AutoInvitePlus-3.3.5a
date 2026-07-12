# LFM/LFG v2 — Unblockable Broadcasting, Weekly Quests, Preset-First Popups (6.5.0)

Design spec for the AutoInvitePlus 6.5.0 release. Validated by three adversarial
verification passes (bug verification, design red-team, UI/API audit) before
implementation; every numbered bug below was CONFIRMED against the code.

## 1. ChatGate (`core/ChatGate.lua`) — never get chat-muted again

One choke point for all non-whisper outbound chat. Lanes:

- **group** (RAID/RAID_WARNING/PARTY/BG): bypasses entirely — mechanic
  call-outs and loot dumps are time-critical and must never queue behind an
  LFM line (red-team blocker).
- **public** (CHANNEL/SAY/YELL) and **guild**: queued, budgeted. Warmane-safe
  `safe` profile: ≥6s between any two public sends, ≥90s per channel, max
  6/min, guild ≥60s. `relaxed`/`paranoid` variants via `db.chatGateProfile`.

Hard-won invariants (each traces to a red-team blocker):

- Queue records store the channel **name**, id resolved at **drain** time —
  positional channel ids shift when the user joins/leaves channels; a stale id
  would post into the wrong channel.
- Records carry `owner` + `staleAfter` + `validate()`; `CancelOwner` is called
  by StopBroadcast so a queued LFM can never fire after the user joined a group.
- Throttle detection only counts a `CHAT_MSG_SYSTEM` squelch pattern within
  10s of **our own** send ("you must wait" false-trips on summon messages),
  patterns tightened to chat-specific wording. Backoff ×1.5 (cap ×4), 60s
  public blackout, decay after 5 quiet minutes.
- Whispers (`Utils.WhisperQueue`) and DataBus/AIPSync (own 5s limiter) stay
  OFF the gate: invites, queue updates and peer discovery are never blocked
  by LFM pacing. This is the "promotion chat never blocked" guarantee.
- 255-byte hard refuse (builders trim first — see §3).

`/aip gate` prints the live budget; `/aip gate profile <p>` switches.

## 2. Broadcaster rotor (CentralGUI)

`GUI.StartBroadcast` now posts to exactly **one** channel per tick, rotating
through the enabled targets (`GUI.BuildBroadcastTargets`). Enabling more
channels spreads sends; it never multiplies them — bursts are structurally
impossible. Tick spacing = `interval / #targets` (floor 15s); ineligible
targets are skipped; if everything is cooling down the rotor idles (never
busy-spins). First send delayed 2s (JoinChannelByName is async — the first
custom-channel LFM used to be silently lost). Auto-stop: group full, 60 min
(`db.broadcastMaxMinutes`), joined-a-group (LFG). Single `GUI.StopBroadcast`
(was two definitions) cancels queued gate messages. DataBus companion
broadcast once per repost period, un-gated. `/aip broadcast dryrun` logs the
schedule for 5 minutes without sending. `/aip spam` reuses the same gate
(owner `spam`). `playerMode` is reset to `none` on load — broadcast state
never survives /reload, so a persisted mode was a lie.

## 3. Single message builder (`modules/LFMFormat.lua`)

The LFM string used to be built in two divergent places; the regenerated
message lost the spec block and `[x/y]` counter the moment anyone joined
(B-1/B-2). Now popup Create, live preview, regeneration and fixtures all call
`LFMFormat.BuildLFM/BuildLFG`. Length-aware: over 255 bytes it drops
`[Res:]` → note → achievement → spec array, never the raid key/counts/keyword,
never mid-hyperlink. Spec-code table single-sourced here.

## 4. Weekly raid quests (`data/WeeklyQuests.lua`)

The 12 Lan'dalock weeklies, mapped to GUI raid keys (OS/EoE/NAXX/ULDUAR/TOC/
ICC). Detection is **title-string** match over `GetQuestLogTitle` (3.3.5a has
no quest ids), cached, invalidated on `QUEST_LOG_UPDATE`. Wire format:
unbracketed `WQ:<CamelToken>` right after the raid key (a bracketed form would
be misread as an achievement by `ParseAchievement`'s trailing-[...] rule); LFG
side appends after `{AIP:5.2}` (all three peer regexes ignore trailing text).
`ParseChatMessage` extracts `info.weekly` and strips the token before raid
detection so `WQ:Sartharion` can't pollute `DetectAllRaids`. Carried through
ChatScanner (both AddGroup branches + AddPlayer), DataBus LFM/LFG, and the
enrollment parser. Surfaced as: Weekly category in both popups' raid pickers
(this week's quest pinned + quest-log status strip), `[W]` badges in the
browser trees and details panel (green when *you* still need that weekly),
`/aip weekly`, weekly test fixtures + `AIP.Weekly.testActive` hook.

## 5. Preset-first popups

AddGroupPopup: collapsed mode = 3 Quick Post tiles (Last used /
this week's Weekly / ICC25H default) + live preview of the exact broadcast
line + a schedule line derived from the real rotor math; `[+] Customize`
expands the full form (composition, requirements, achievement, class checks
with click-role-label-to-toggle-all, note, keyword, reserved). External
contract preserved: same global frame names, same `popup.*` fields/methods.
EnrollPopup: weekly picker + status strip, `LFMFormat.BuildLFG`, reopens on
the last-used config. Both persist to `db.lastListingConfig` /
`db.lastEnrollConfig`.

## 6. Wiring repairs (all independently confirmed)

- **B-1/B-2** regeneration format divergence → single builder (§3)
- **B-3** `GUI.MyGroup.*.current` frozen at 0 → synced in
  `RegenerateBroadcastMessage`, so auto-queue role-full checks work
- **B-4** scanner ignored `listenLFG/Trade/General/...` → shared
  `AIP.IsListenChannel` used by both Core and ChatScanner
- **B-5** scanner ingested `!A:` DataBus payloads as fake LFM groups → prefix skip
- **B-6** peer listings showed "Looking for: -" → `OnDataBusLFM` reads `roleSpecs`
- **B-7** popup's custom invite keyword never invited → `CheckTriggers` also
  matches the active listing's keyword
- **B-8** public-channel LFG players invisible in the queue panel → panel also
  merges `CS.Players`
- **B-9** double `StopBroadcast` definition → folded into one
- **B-10** CharacterCard pages dropped cross-guild (2.2s < 5s channel limit)
  → 5.5s stagger + stale `pending` buffer prune
- **B-11** RaidBrowser imports lacked role/isLfgEnrollment → shaped like real
  enrollments
- `smartInvite.minIlvl` wired (existed since v5, never read)
- Dead code removed: `modules/MessageComposer.lua` (655 lines, zero callers),
  `CanSpamToChannel`/`MarkChannelSpammed`, `CHANNEL_*` constants,
  `lookingForClasses` slots, duplicate `AIP.Version` assignment.

## 7. Verification

No test runner exists (WoW-client Lua). Performed: full-repo `luaparser`
syntax pass (54/54 files), toc↔disk parity, dangling-reference sweep,
gated-send sweep (remaining direct `SendChatMessage` calls are all group-lane
by design), and a Python reimplementation of the wire format asserting:
worst-case listing trims under 255 bytes in the right priority order; built
messages round-trip through `ParseFilledCount` / `ParseAIPComposition` /
keyword / weekly patterns; `WQ:` never false-positives the achievement rule;
the LFG enrollment regex tolerates the appended weekly token. In-game smoke
checklist: `/aip testdata` → `[W]` listings; popup presets/preview; post →
rotor countdown in footer; `/aip gate`; join a group mid-broadcast → zero
further lines; `/aip timertest` unaffected.
