# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository layout

This repo ships **two separate World of Warcraft 3.3.5a (WotLK, Interface `30300`) addons**, each in its own top-level folder:

- **`AutoInvitePlus/`** — the primary addon (v6.1.2). Raid-organization suite: keyword auto-invite, LFM/LFG chat browser, gear-tiered composition advisor, queue/waitlist, blacklist/favorites, loot history, and in-raid assist tools. This is where nearly all development happens.
- **`GearScoreLite/`** — a **vendored third-party addon** (v1.84, by Mirrikat45 & Leo), bundled because it is one of AutoInvitePlus's optional GearScore dependencies (`## OptionalDeps: GearScore, GearScoreLite, PlayerScore`). Treat it as an external dependency — don't refactor it as if it were our code; upstream it only.

Also at the root: `README.md` (user-facing feature/command overview), `Screenshots/`, `LICENSE`, and `.github/workflows/main.yml` (release CI).

## No build/lint/test toolchain

The code is interpreted **Lua 5.1** loaded directly by the WoW client — there is nothing to compile and no test runner. The dev loop is:

1. Edit a `.lua` file.
2. `/reload` in-game (or restart the client).
3. Observe. Lua errors surface in-game — enable with `/console scriptErrors 1`, or use an addon like BugSack/BugGrabber.

Each addon's load order is defined by its `.toc` file (`AutoInvitePlus/AutoInvitePlus.toc`, `GearScoreLite/GearScoreLite.toc`), **not** by `require`. Files load top-to-bottom. **If you add a new `.lua` file you must add it to the `.toc`, or it will never load.**

For UI work without live chat, AutoInvitePlus provides fixtures: `/aip testdata` / `/aip cleartest` (browser/queue) and `/aip testloot` / `/aip cleartestloot` (loot history).

## Releasing

CI is `.github/workflows/main.yml`, triggered on **any git tag push** (`tags: "*"`). It zips both `AutoInvitePlus/` and `GearScoreLite/` and publishes them as GitHub Release assets. To cut a release:

1. Bump `## Version` in the relevant addon's `.toc` (for AutoInvitePlus, `AutoInvitePlus/AutoInvitePlus.toc`).
2. Commit, then `git tag <version>` and push the tag → CI creates the release.

Note: the GearScoreLite release asset name is **hardcoded** in `main.yml` (`GearScoreLite-1.84.zip`) — if you ever bump GSL's version, update that `asset_name` too.

## Where to go next

- **AutoInvitePlus architecture** — the single-global-namespace model (`AIP.*`), the `core → data → modules → ui` layering, the two event systems, the RaidTools suite, the DataBus inter-player protocol, WotLK/Lua 5.1 constraints, slash commands, and the SavedVariables lifecycle are all documented in detail in **`AutoInvitePlus/CLAUDE.md`**. Read that before making non-trivial changes to the main addon.
- **Feature/user docs** — root `README.md` and `AutoInvitePlus/README.md`.
