# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository snapshot

This repo contains two separate World of Warcraft 3.3.5a (Wrath of the Lich King, Interface 30300) addons:

- AutoInvitePlus/ — the primary addon under active development. The current addon version is 6.7.1 in both AutoInvitePlus/AutoInvitePlus.toc and AutoInvitePlus/core/Core.lua.
- GearScoreLite/ — a vendored third-party dependency bundled for compatibility with AutoInvitePlus. Treat it as external code; do not refactor it as if it were part of the main addon.

The root also contains release automation in .github/workflows/main.yml, user-facing docs in README.md, and screenshots.

## Working assumptions

- This code targets Lua 5.1 and the WoW client directly. There is no build, test, lint, or package-manager workflow.
- The practical dev loop is: edit a .lua file, /reload in-game, then observe the result and any Lua errors.
- Use /console scriptErrors 1 if you need in-game error output; an addon such as BugSack/BugGrabber can also help.
- Load order is controlled by the .toc file, not by require or module imports. If you add a new .lua file, add it to the relevant .toc so it actually loads.

## AutoInvitePlus architecture

The main addon is organized as a single global namespace, with most files using a local alias such as local AIP = AutoInvitePlus. Cross-module access is done through AIP.* and is usually guarded.

### Layering

The intended structure is:

- core/ — foundational utilities and lifecycle code
  - Utils.lua: shared helpers, event wrapper, delayed-call helper, and namespace setup
  - Parsers.lua: chat parsing and message normalization
  - ChatGate.lua: outbound chat throttling and broadcast pacing
  - DataBus.lua: inter-player addon communication protocol
  - Core.lua: defaults, SavedVariables initialization, central event frame, slash commands, and core invite/queue logic
- data/ — live data acquisition and content databases
  - ChatScanner.lua, InspectionEngine.lua, RaidComposition.lua
  - ItemScore.lua and the BiS/gear/spec data files for the character panel and coaching suite
- modules/ — feature implementations
  - Matchmaking loop: LFMFormat, FitEngine, Applications (listing format, fit verdicts, Apply protocol)
  - Queue, Waitlist, Blacklist, Promote, RosterManager, RaidSessionManager, Integrations, Updater
  - RaidTools and its split files (RaidToolsRoll, RaidToolsUI, RaidToolsEvents) for roll/loot/announcement features — one logical module split across four .toc entries sharing state via AIP.RaidTools; RaidTools.lua must load first
  - DBMBridge, ThreatCoach, Readiness, GearAdvisor, GearHooks, UpgradePath, SpecAdvisor, PostPull, Rotation, LFGWatch, CharacterCard, TestData
- ui/ — presentation layer
  - UIFactory.lua for reusable widgets
  - CentralGUI.lua as the main window controller (the largest file in the addon)
  - TreeBrowser.lua, CompositionUI.lua, and the panels under ui/panels/

### Important implementation conventions

- Keep the single-namespace pattern intact. Do not introduce a separate module system or refactor to a modern package pattern.
- Prefer guarded calls such as if AIP.Foo and AIP.Foo.Bar then ... when a module may be absent or load later.
- Reuse shared helpers from AIP.Utils and AIP.UI rather than duplicating logic.
- For module-local events, prefer AIP.Utils.Events over creating extra frames unless the code genuinely needs a WoW event frame.
- User-facing output should normally go through AIP.Print; debug output should go through AIP.Debug and be gated behind the debug setting.
- Names should be normalized with the addon’s name-normalization helper before comparison.

## SavedVariables and persistence

AutoInvitePlus stores its saved state in AutoInvitePlusDB via the SavedVariables entry in the .toc. The defaults table and DB_VERSION live in Core.lua.

When editing persisted settings:

- Add the new key to the defaults table in Core.lua.
- Only bump DB_VERSION when a structural migration is needed; otherwise keep it stable.
- Be careful when changing existing table shapes because players may already have older saved data in their WTF folder.

## Event systems

There are two event patterns in the addon, and they should not be conflated:

1. The central dispatcher in Core.lua uses one main event frame and a large OnEvent switch for core addon behavior (ADDON_LOADED, chat messages, roster changes, invite handling, slash commands, etc.).
2. AIP.Utils.Events is the lightweight pub/sub mechanism for module-local subscriptions. Use it when a module needs to react to events without creating its own frame.

## UI conventions

Panels under ui/panels/ follow a simple pattern:

- AIP.Panels = AIP.Panels or {}
- AIP.Panels.<Name> = { Create(container), Update() }

CentralGUI lazily creates these panels and calls Update when switching tabs. New tabs should be wired through the GUI tab table and the switch/init logic in CentralGUI.lua.

## DataBus and inter-player features

The addon has a built-in inter-player protocol via DataBus.lua. It is used for sharing listings, character cards, gear readiness, queue state, and version information with other AutoInvitePlus users. When changing these messages, preserve the existing event names and field shapes unless you are intentionally changing the protocol.

## WotLK and Lua 5.1 constraints

This addon is written for a 2010-era client and must respect the platform constraints:

- No C_Timer; use AIP.Utils.DelayedCall for one-shot delayed work.
- Lua 5.1 syntax only; do not assume newer language features.
- The code relies on WoW globals such as SendChatMessage, InviteUnit, GetChannelName, GetGuildRosterInfo, and IsRaidLeader.
- Channel IDs vary by server and should be resolved by name matching rather than hardcoded values.
- Broadcast code must be mindful of chat throttling and spam protection. Preserve the existing pacing logic when changing chat output.

## Slash commands and testing helpers

Slash commands are registered in Core.lua. Many feature modules also expose subcommands through the /aip dispatcher. Common helpers include:

- /aip testdata and /aip cleartest for browser/queue fixture data
- /aip testloot and /aip cleartestloot for loot-history fixture data
- /aip help for command overview

For UI work, these test commands are often enough to avoid needing live chat traffic.

## Release and versioning

Release automation lives in .github/workflows/main.yml. The workflow is triggered by git tag pushes and archives both AutoInvitePlus/ and GearScoreLite/ as release assets.

To cut a release:

1. Bump the version in AutoInvitePlus/AutoInvitePlus.toc.
2. Bump the VERSION constant in AutoInvitePlus/core/Core.lua so the update checker and peers receive the same version string.
3. Commit and tag the release, then push the tag so CI publishes the assets.

Note that the GearScoreLite release asset name is currently hardcoded in the workflow and should be updated if that dependency is ever version-bumped.

## Where to start for changes

- AutoInvitePlus/AutoInvitePlus.toc for load order and module registration
- AutoInvitePlus/core/Core.lua for defaults, DB setup, slash commands, and central event plumbing
- AutoInvitePlus/core/DataBus.lua for addon-comms protocol changes
- AutoInvitePlus/modules/ for most feature logic
- AutoInvitePlus/ui/ and AutoInvitePlus/ui/panels/ for UI changes
- AutoInvitePlus/CLAUDE.md for the deeper addon-specific architecture notes
- AutoInvitePlus/WIRING.md for the matchmaking/composition wiring map — read it FIRST before changing LFM, applications, waitlist, or class-needs code (it replaces re-reading the large files), and update it whenever that wiring changes
- docs/superpowers/specs/ for design notes for larger features

## Practical guidance for edits

- If you introduce a new Lua file, add it to the relevant .toc file immediately.
- Preserve existing chat and invite safety behavior; this addon is heavily interaction-based and chat-ban avoidance is a real concern.
- Keep current module boundaries intact; the codebase is deliberately split by responsibility and uses guarded cross-module access.
- Avoid rewriting vendored code in GearScoreLite/ unless the change is clearly intended as an upstream patch.
- When changing raid-tools, mechanic announcers, or self-check logic, preserve the existing accuracy guards and channel-selection rules.
