# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

AutoInvite Plus is a **World of Warcraft 3.3.5a (Wrath of the Lich King) addon** — client Interface version `30300`. It is a raid-organization suite: keyword auto-invite, an LFM/LFG chat browser, raid composition advisor, queue/waitlist, blacklist/favorites, loot history, and an inter-player addon-comms layer (DataBus).

There is **no build, compile, lint, or test toolchain**. The code is interpreted Lua 5.1 loaded directly by the WoW client. "Running" the addon means launching WoW and `/reload`-ing the UI.

## Development workflow

- **Edit → `/reload` in-game → observe.** Lua errors surface in-game (use `/console scriptErrors 1` or an addon like BugSack). There is no way to run this outside the WoW client.
- **Load order is defined by `AutoInvitePlus.toc`**, not by `require`. Files load top-to-bottom: `core/` → `data/` → `modules/` → `ui/`. A file may only use sub-namespaces defined by files listed *above* it. If you add a `.lua` file, you **must** add it to the `.toc` or it will never load. `core/Utils.lua` loads first and seeds the global namespace.
- **In-game test data**: `/aip testdata` loads fake LFM/LFG/queue data for UI work without live chat; `/aip cleartest` removes it (preserves real data). `/aip testloot` / `/aip cleartestloot` do the same for loot history. The `modules/TestData.lua` module is the source of this fixture data.
- **Saved state**: `AutoInvitePlusDB` (declared `## SavedVariables` in the `.toc`) persists to the player's `SavedVariables` folder. To reset, delete that file or `/run AutoInvitePlusDB=nil` then `/reload`.

## Architecture

### Single global namespace
Every file shares one global table, `AutoInvitePlus` (aliased `local AIP = AutoInvitePlus` at the top of each file). Each module attaches its own sub-table, e.g. `AIP.Parsers`, `AIP.DataBus`, `AIP.Composition`, `AIP.CentralGUI`, `AIP.Panels.RaidMgmt`. There are no module imports — cross-module access is always `AIP.Something`, and calls are typically **guarded** (`if AIP.Foo and AIP.Foo.Bar then`) because a module may be absent or load later.

### Layers (matches directory + `.toc` order)
- **`core/`** — foundation. `Utils.lua` (string/table helpers, `Utils.Events` pub/sub, `Utils.DelayedCall`), `Parsers.lua` (chat-message parsing: roles, GearScore, raid IDs, spec codes), `DataBus.lua` (inter-addon network protocol), `Core.lua` (DB defaults, central event frame, slash commands, the auto-invite decision logic).
- **`data/`** — live data acquisition. `ChatScanner.lua` (scans chat into LFM/LFG entries; prune lifetime comes from `AIP.db.cacheDuration` via `CS.GetExpiry()`), `InspectionEngine.lua` (player gear inspection + caching), `RaidComposition.lua` (raid templates, role/buff coverage — the largest data file). Composition templates are surfaced through a **gear-tiered variation** system: `Comp.ContentTiers`/`Comp.GetTierInfo` map each template to GS/iLvl ranges, `Comp.GetTemplateVariations` generates Entry/Standard/Farm splits (healers scale inversely with gear), and `Comp.GetRecommendations` couples role gaps with missing raid buffs + mandatory classes. `Comp.RaidBosses` also feeds boss-name → zone detection used by `RaidSessionManager` to stamp accurate loot-history zones (incl. 5-man dungeons).
- **`modules/`** — feature logic, mostly headless: `Queue`, `Waitlist`, `Blacklist`, `Promote`, `MessageComposer`, `RosterManager` (`AIP.Roster`), `RaidSessionManager` (`AIP.RaidSession`), `Integrations` (`AIP.Integrations` — GearScore addon, lockouts, Blizzard Raid Browser), `TestData`, and the **RaidTools** suite.
  - **RaidTools** (`AIP.RaidTools`, alias `RT`) is one logical module deliberately split across four `.toc` entries — `RaidTools.lua` (chat sender + state + most feature logic), `RaidToolsRoll.lua` (roll countdown/capture/winners), `RaidToolsUI.lua` (roll window, announce config, floating bar, countdown timer-bar widget), `RaidToolsEvents.lua` (its own event frame). The split exists so the WoW load phase reports failures per-section. All four files share state via `RT = AIP.RaidTools` (each does `AIP.RaidTools = AIP.RaidTools or {}`), so the `RaidTools.lua` constants/state block must load first. `RT.Send(msg, channel)` is the smart channel-fallback sender (RAID_WARNING→RAID→PARTY→SAY based on group state and leader/officer rank) — route raid-tool chat output through it. Loot trade-window timers use `RT.LOOT_EXPIRE_SECONDS` (2h BoP) / `RT.LOOT_WARN_SECONDS`.
    - Beyond loot/rolls, `RaidTools.lua` hosts the **raid-assist subsystems**, all opt-in via `AIP.db` flags: floating-bar shortcuts (Ready Check, buff delegation), the **buff-delegation** assigner (`RT.ClassBuffDuties` — one distinct buff per same-class caster), the **self debuff/curse announcer** (`RT.KnownDebuffs` + a curse/stacking fallback, fired from `UNIT_AURA`), and the **auto mechanic announcer** (`RT.MechanicSpells` boss casts, `RT.BossEmotes`, target/focus boss-health milestones, raid-health) plus **countdown timer bars** (`RT.AbilityTimers` — DBM-WotLK-verified recast intervals; Bloodlust duration/lockout). `RaidToolsEvents.lua` is what wires these: it registers `CHAT_MSG_SYSTEM` (roll results), `UNIT_AURA` (debuffs), `COMBAT_LOG_EVENT_UNFILTERED` + `CHAT_MSG_RAID_BOSS_EMOTE`/`MONSTER_EMOTE`/`MONSTER_YELL` + `UNIT_HEALTH` (mechanics), and an `OnUpdate` running a 3s raid-health check and 60s loot-expiry check. Note WotLK has **no `boss1` token / `ENCOUNTER_START`** — boss health is read from `target`/`focus` only (this is how DBM-WotLK does it too).
- **`ui/`** — presentation. `UIFactory.lua` (`AIP.UI` — reusable widget builders, use these instead of hand-rolling frames), `TreeBrowser.lua`, `CentralGUI.lua` (the main window controller — by far the biggest file), `CompositionUI`, `MainUI`, and `ui/panels/*` which register into `AIP.Panels.*`.

### Two event systems — know which to use
1. **Central dispatcher in `core/Core.lua`**: one `CreateFrame` event frame with a big `OnEvent` switch handling `ADDON_LOADED`, `CHAT_MSG_*`, roster changes, etc. This is where chat triggers flow into `ProcessMessage` → smart-condition checks → `InvitePlayer`/`AddToQueue`. Core chat/invite behavior lives here.
2. **`AIP.Utils.Events` pub/sub** (`Register`/`Unregister`/`UnregisterAll(owner)`/`Dispatch`): a lightweight wrapper letting any module subscribe to WoW events without its own frame. Prefer this for module-local event needs; pass an `owner` so `UnregisterAll` can clean up.

### Saved-variables lifecycle
`core/Core.lua` owns the `defaults` table and `DB_VERSION`. On `ADDON_LOADED` it deep-merges `defaults` into `AutoInvitePlusDB` (only filling missing keys, preserving user settings), bumps `dbVersion`, and assigns `AIP.db = AutoInvitePlusDB`. **When you add a persisted setting, add it to `defaults` in `Core.lua`**; bump `DB_VERSION` only when a structural migration is required (the comment on the `DB_VERSION` line tracks the history).

### UI panel convention
Panels in `ui/panels/` set `AIP.Panels = AIP.Panels or {}` then define `AIP.Panels.<Name> = { Create(container), Update() }`. `CentralGUI` lazily calls `Create` once per tab into a container frame and calls `Update` on tab switch. New tabs are wired in `GUI.Tabs` and the init/switch logic in `CentralGUI.lua`.

### DataBus (inter-player comms)
`core/DataBus.lua` is a small protocol over WoW addon messages + a hidden chat channel (`AIPSync`) for cross-guild reach. It defines typed events (`LFM`, `LFG`, `PING`, `PONG`) with fixed field lists in `DB.EventTypes`, serializes them under the `!A:` chat prefix, and rate-limits/prunes. Other addon users running AIP see each other's LFM/LFG broadcasts. Messages on the DataBus channel are filtered out of normal chat processing in `Core.lua`.

## WotLK / Lua 5.1 constraints (important)

This targets a 2010-era client. Modern WoW/Lua APIs do **not** exist:
- **No `C_Timer`** — use `AIP.Utils.DelayedCall(delay, func)` (a one-shot `OnUpdate` frame). This pattern recurs throughout for staggered/delayed sends.
- **Lua 5.1 only** — no `goto`, no integer division operators, etc. Use `strsplit`, `strtrim`, `string.format`, `table.insert`.
- **Polyfills** live at the top of `core/Utils.lua` (e.g. `string.trim`). Don't assume newer string methods exist.
- **WoW global API** (`SendChatMessage`, `InviteUnit`, `GetChannelName`, `GetGuildRosterInfo`, `IsRaidLeader`, …) is the standard library here. Channel IDs vary by server, so the code resolves channels by name match (`FindChannelId`) rather than hardcoded IDs.
- **Chat throttle avoidance is a real design concern**: spam sends are staggered with per-channel cooldowns, and `Core.lua` watches `CHAT_MSG_SYSTEM` for squelch/throttle messages (`OnChatBanDetected`) to auto-back-off. Preserve this when touching broadcast code.

## Slash commands

Registered in `core/Core.lua`: `/aip`, `/autoinvite`, `/ai`. `/aip help` lists everything; `/aip` alone opens the central GUI. Subcommands dispatch to module `SlashHandler` functions (e.g. `/aip comp`, `/aip roster`, `/aip databus`). RaidTools is driven by its own subcommands handled inline in `SlashHandler` rather than a module `SlashHandler`: `/aip roll [item]` (start a roll, or toggle the roll window with no arg), `/aip rollwindow`/`/aip rolls`, `/aip rw`/`/aip announceloot` (announce reserved loot), `/aip bar`/`/aip announcebar` (toggle the floating announcement bar), `/aip readycheck`/`/aip rc`, `/aip buffs`/`/aip delegate` (announce buff assignments), `/aip timertest` (preview the countdown timer bars). Composition adds `/aip comp recommend`. Add new subcommands to `SlashHandler` and document them in the `help` branch.

## Conventions

- User-facing output goes through `AIP.Print(msg)`; gated debug output through `AIP.Debug(msg)` (only shows when `AIP.db.debug` is set).
- Player names: normalize with `AIP.Utils.NormalizeName` and compare case-insensitively (`:lower()`) — chat delivers inconsistent casing.
- Roles use the four-way split `TANK / HEALER / MDPS / RDPS` (melee/ranged DPS) in composition and DataBus; spec codes and class mapping live in `Parsers.SpecCodeInfo`.
- The codebase favors guarded cross-module calls and reusing `AIP.Utils` / `AIP.UI` helpers (the headers cite "DRY principle" and OOP-ish namespacing) — match that rather than duplicating helpers.
