# Matchmaking Loop — FitEngine + Apply Protocol (6.6.0)

Approved design: full matchmaking loop, "one-click everything, auto only on
pre-approved green". Builds on the 6.5.0 LFM/LFG v2 architecture (ChatGate,
rotor, LFMFormat, WeeklyQuests) — see 2026-07-12-lfm-lfg-v2-design.md.

## 1. FitEngine (`modules/FitEngine.lua`) — one verdict everywhere

`Fit.ScoreApplicant(applicant, listing)` and `Fit.ScoreListing(listing, me)`
return `{score 0-100, verdict "GREEN"|"YELLOW"|"RED", reasons {strings}}`.

Hard fails (RED, score 0-25): blacklisted; GS below listing minimum; role slots
for their role already full; raid mismatch (when both sides name one); seeker
saved to the listing's instance (ScoreListing only).
Boosts: role needed +20, GS meets min +15 (+5 comfortably above), spec in the
listing's roleSpecs +10 (absent roleSpecs = neutral), favorite +15, guildmate
+10, weekly overlap (+10 applicant side; +15 seeker side when the listing runs
a weekly the seeker still needs). Missing data never hard-fails — it caps the
verdict at YELLOW with a "no GS info" style reason.
GREEN = score >= 75 and no soft fails; RED = any hard fail; else YELLOW.

Alignment: `CheckSmartConditions` (Core) and `CS.MatchesMyLFM` (ChatScanner)
delegate their fit checks to FitEngine (user-preference gates like
requireRole/acceptTanks stay in Core — they are policy, not fit). The UI
computes chips at render time so they always reflect live composition counts.
`/aip fit <name>` prints the verdict + reasons for a queued/scanned player.

## 2. Apply protocol (`modules/Applications.lua` + DataBus events)

New DataBus event types, both DIRECTED (addon-whisper to one player, which
bypasses the channel rate limits by design and never touches ChatGate):
- `APPLY {raid, role, class, spec, gs, ilvl, weekly, note}` seeker -> leader
- `APPLYACK {applicant, status, position}` leader -> seeker;
  status: `seen | queued | invited | declined`

`AIP.Apply` state: `Apply.mine[leader] = {raid, status, position, time}`
(seeker side); incoming applications land in `AIP.db.queue` shaped like
whisper entries plus `isApplication = true` (leader side), so every existing
queue consumer works unchanged.

Leader receive flow: blacklist -> ACK declined; else queue + ACK "queued #N";
favorites (existing prioritize) and, when `db.autoInviteGreen`, GREEN verdicts
are invited immediately + ACK invited. `Core.InvitePlayer` success and queue
reject paths call guarded `Apply.NotifyInvited/NotifyDeclined` so ACKs stay
truthful no matter which UI path acted.

Non-AIP fallback: applying to a listing without `isDataBus` sends the existing
Quick-Req whisper; status shows `whispered` (no ACKs possible).
Auto-apply (`db.autoApplyGreen`, default off) fires only for AIP-peer
listings — auto-whispering non-addon strangers reads as botting and was
explicitly rejected with the "maximum automation" option.

## 3. Leader pipeline (evolved Queue panel)

- Queue + LFG rows get a **fit chip** prepended to the name
  (`|cFF00FF00[85]|r Name`), reasons appended to the row tooltip. Rendered
  only while `GUI.MyGroup` exists (no listing = nothing to fit against).
- Rows sort by fit score (desc) while a listing is active; by time otherwise.
- **Needs strip**: the existing queueStatus line gains
  `Need: 1T 2R | N matching LFG` when a listing is active — the LFG sub-tab,
  now fit-sorted, IS the suggestion list. (A separate suggestions row was
  YAGNI-cut.)
- One-click actions stay the existing row buttons; decline also ACKs.

## 4. Seeker cockpit

- While enrolled (`GUI.MyEnrollment`), LFM tree leaves get the same fit chip
  via `TB.ApplyListingDecor` using `Fit.ScoreListing`.
- The details-panel "Request Invite" button becomes **Apply**: structured
  DataBus APPLY for AIP-peer listings, Quick-Req whisper otherwise; a status
  line under it shows `Applied - queued #4` etc. from `Apply.mine`.
- **Match alerts** (`db.matchAlerts`, default on): when a NEW listing scores
  GREEN against your enrollment, minimap bubble + chat line; a listing running
  a weekly you still need gets the weekly-specific wording. Throttled to once
  per leader per 10 minutes.

## 5. Persistence / fixtures / commands

New defaults: `matchAlerts = true`, `autoInviteGreen = false`,
`autoApplyGreen = false` (additive; no DB_VERSION bump).
`/aip testdata` sets a fake `GUI.MyGroup` (tagged, removed by cleartest) so
fit chips and the needs strip render offline. `/aip fit <name>`; help updated.
Version 6.6.0 in `.toc` + `Core.lua` VERSION.

## 6. Verification

luaparser pass over all files, toc parity, dangling-ref sweep, and a Python
fixture harness mirroring FitEngine's scoring table to assert verdict
boundaries (blacklist=RED, below-GS=RED, favorite+needed-role reaches GREEN,
missing GS caps at YELLOW). In-game: `/aip testdata` -> chips + needs strip;
apply from a second AIP client -> ACK ladder; `/aip fit`.
