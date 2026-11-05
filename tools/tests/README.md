# Headless specs

Self-contained Lua 5.1 specs that stub the WoW API and run under LuaJIT; no client needed.

    luajit tools/tests/<name>_spec.lua            # one spec, from the repo root
    powershell -File tools\tests\run_all.ps1      # every *_spec.lua + `luajit -bl` syntax check of AutoInvitePlus\**\*.lua

Each spec prints `N passed, M failed` and exits non-zero on failure; `run_all.ps1` picks up whatever `*_spec.lua` files exist
and exits non-zero if any spec or any file's syntax fails.

- `databus_spec.lua` - DataBus serialize/deserialize round trip and hostile payloads (huge counts, deep nesting, scalars, bad versions).
- `parsers_spec.lua` - chat parsing: GS, raid ids, roles/classes, composition, spec codes.
- `chatscanner_spec.lua` - listing store, prune, `MatchesMyLFM`, DataBus LFM/LFG intake with untrusted payloads.
- `settings_gating_spec.lua` - Windows & Bars switches; extracts the real gated functions/conditions from the source files.
- `raidgroups_spec.lua`, `tankcast_spec.lua` - pure logic of those modules.

New pure-logic specs: stub globals inline (see existing specs), `loadfile` the real source, keep it standalone.
