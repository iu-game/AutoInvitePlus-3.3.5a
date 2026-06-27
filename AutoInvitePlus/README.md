# AutoInvite Plus

A complete **raid-organization suite for World of Warcraft 3.3.5a (Wrath of the Lich King)**.
Keyword auto-invite, an LFM/LFG chat browser, a gear-aware composition advisor, queue/waitlist
management, blacklist/favorites, loot history, and a set of in-raid assist tools (rolls,
announcements, ready check, buff/mechanic call-outs).

- **Interface:** 30300 (WotLK 3.3.5a)
- **Saved variables:** `AutoInvitePlusDB`
- **Optional deps:** GearScore / GearScoreLite / PlayerScore (for GS-based filtering)

## Installation

1. Copy the `AutoInvitePlus` folder into `Interface\AddOns\`.
2. Restart the client (or `/reload` if it was already running).
3. Type `/aip` to open the main window.

## Quick start

| Command | What it does |
|---|---|
| `/aip` | Open/close the main window |
| `/aip help` | List all commands |
| `/aip status` | Show current auto-invite settings |
| `/aip testdata` / `/aip cleartest` | Load / clear fake browser/queue data (UI testing) |
| `/aip testloot` / `/aip cleartestloot` | Load / clear fake loot-history data |

## Features

### Auto-invite & queue
- Keyword auto-invite from whispers/channels, with optional **guild-only**, **auto-convert to raid**, and a manual-approval **queue**.
- **Smart conditions**: minimum GearScore, role filtering (Tank/Healer/DPS), role/class matching to your LFM, and priority skip-queue for favorites/guild.
- **Waitlist** with position whispers; **blacklist** (flag or auto-reject) and **favorites**.

### LFM/LFG browser
- Scans chat (and other AIP users via the **DataBus**) for groups and players; browse, filter, and invite.
- Cache lifetime is controlled by the **Cache Duration** setting.

### Composition advisor (gear-tiered)
- Pick an instance template; the advisor shows live Tank/Healer/DPS coverage and raid-buff coverage.
- **Numbered variation buttons** offer gear-banded splits (Entry / Standard / Farm) — healers scale inversely with gear — each with its own **GearScore & item-level range** (verified against WotLK PUG norms).
- **Recommend** (`/aip comp recommend`) analyzes the current raid and suggests which classes to recruit, prioritizing missing roles **and** missing raid buffs, and flags missing mandatory classes (Shaman/Paladin/…).

### Loot history
- Per-raid sessions with boss kills, attendees, and loot — including accurate **dungeon** bosses and corrected instance zones.

### Raid tools (`/aip bar` floating bar)
- **Loot rolls** with a countdown roll window (`/aip roll`).
- **Predefined raid-warning buttons** + a friendly editor.
- **Ready Check** (`/aip rc`).
- **Buff delegation** (`/aip buffs`) — assigns one distinct buff per same-class caster (e.g. 3 Paladins → Kings/Might/Wisdom; 2 Mages → one casts Brilliance, the other backup).
- **Self debuff/curse announcer** *(opt-in)* — `/say`s important raid debuffs on you with stack count + what to do (e.g. `Mutated Infection x3 - spread + dispel me!`). Covers ~80 named encounter debuffs plus a curse/stacking fallback.
- **Auto mechanic announcer** *(opt-in, mini-DBM)* — reactive call-outs for boss casts, boss-health milestones, boss emotes/yells, and low raid health. Output defaults to a personal center-screen heads-up (no chat spam).
- **Countdown timer bars** — Bloodlust/Heroism duration + lockout, plus signature boss abilities with **DBM-verified recast intervals** across ICC, Ulduar, ToC/ToGC, RS, VoA, EoE, Onyxia, and Naxxramas. Preview with `/aip timertest`.

## Settings

Open `/aip` → **Settings** tab. Highlights: trigger keywords, max group size, smart conditions,
listen/broadcast channels, queue behavior, LFM/LFG scanning, GUI opacity, and the opt-in
**debuff** and **mechanic** announcers (each with a channel selector). All settings persist in
`AutoInvitePlusDB`.

## Notes

- There is **no build/test toolchain** — the addon is interpreted Lua loaded by the client. Edit, then `/reload`.
- To reset everything: delete the `AutoInvitePlusDB.lua` saved-variables file, or `/run AutoInvitePlusDB=nil` then `/reload`.
- Lua errors surface in-game; enable them with `/console scriptErrors 1` or use BugSack.

See `CLAUDE.md` for architecture/contributor notes.
