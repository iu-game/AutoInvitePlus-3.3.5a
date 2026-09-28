# Tank Cast: Multiple Tanks and Per-Tank Picks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Tank Cast window into a list of up to 8 tanks (MT + off-tanks added on demand), each with its own list of up to 4 picks (spells/items) castable on that tank with one click.

**Architecture:** `modules/TankCast.lua` (headless, unit-tested) gets a slot model `tanks = { {name, picks} ... }` with add/remove/pick APIs and a one-time migration from the legacy `mt/ots/spell` shape. `ui/TankCastWindow.lua` is rewritten around 8 pre-created row containers, each holding up to 4 `SecureActionButtonTemplate` pick buttons (all created once at login, out of combat). `ui/TankCastConfig.lua` keeps the spellbook/bag picker but gains a target context (which tank/pick it is filling) and a type-a-name box; the gear strip shrinks to Import/Push.

**Tech Stack:** Lua 5.1, WoW 3.3.5a API, LuaJIT for headless tests, `luaparse` for syntax checks.

**Spec:** `docs/superpowers/specs/2026-09-27-tank-cast-multi-tank-picks-design.md` (Revision 2; supersedes parts of `2026-09-27-tank-cast-window-design.md`). Earlier plan: `docs/superpowers/plans/2026-09-27-tank-cast-window.md` (already executed; this plan modifies its output).

## Global Constraints

- Lua 5.1 only; ASCII only in Lua string literals.
- `TK.MAX_TANKS = 8` (slot 1 = MT, always present; slots 2..8 = off-tanks), `TK.MAX_PICKS = 4` per tank. The secure-button pool is `MAX_TANKS * MAX_PICKS` = 32, created once at `PLAYER_LOGIN` out of combat.
- Picks belong to the **slot**; dedupe moves a *name* between slots, never picks.
- Cast macro: `/cast [target=<Name>] <Pick>` (`target=`, not `@`); names letters-only; pick text sanitised (control chars, `/ ; [ ] |` stripped); macro length <= `TK.MACRO_MAX` (250).
- Anything protected (attributes, Show/Hide/SetPoint/SetSize/creation of the window, the 8 row containers, the 32 pick buttons, `[+]`, `[+ Add off-tank]`) only when `not InCombatLockdown()`; combat edits mutate the saved list, set `TK.dirty`, and flush on `PLAYER_REGEN_ENABLED`. Rows render from the `applied` snapshot so the display always equals what a click casts.
- **No chat output** from this feature (no `SendChatMessage`, no `RT.Send`); feedback via `AIP.Print` only.
- Saved key `AIP.db.tankCast`: the `defaults` table in `core/Core.lua` must **not** contain `tanks` (a pre-created empty `tanks` would block the legacy migration); no `DB_VERSION` bump.
- Cross-module calls stay guarded (`if AIP.TankCast and AIP.TankCast.X then`).
- **Do not `git commit` unless the user asks** (standing rule). Each task ends in a "Checkpoint" of tests + syntax instead of a commit.
- **Client restart caveat:** the three TankCast files are already in the `.toc`; if the user has not yet restarted WoW since they were added, none of this loads. Before any live step, confirm the client was restarted (check `/run UIErrorsFrame:AddMessage(tostring(AutoInvitePlus.TankCast~=nil),1,1,0)` shows `true`); if not, ask the user to restart and wait.
- Syntax check (repo root): `node C:/Users/iuras/AppData/Local/Temp/claude/D--tmp-AutoInvitePlus-3-3-5a/01bb4a72-f1e4-49c9-a03d-c5fe876a0d18/scratchpad/luacheck.js <files>` (ignore the known `break;` false positive). If that script is gone, recreate it: it `require`s `luaparse` (npm-installed in a scratch dir), parses each file with `{luaVersion:'5.1'}` and prints `OK`/`FAIL`.
- Headless tests (repo root): `luajit tools/tests/tankcast_spec.lua`
- Live loop (repo root, PowerShell): `. tools\wow-test-harness\harness.ps1; Sync-Addon; Send-WowChat "/reload"; Start-Sleep 8` (then screenshot with `Screenshot-Wow`; `Run-WowLua 'UIErrorsFrame:AddMessage(...)'` prints on screen where chat spam cannot bury it).

## Review Focus

Failure modes the spec implies that no plain unit test pins, most likely first. Each has its test/check in the owning task.

1. **Legacy saved data:** an existing `tankCast = {mt, ots, spell, shown, showConfig}` must migrate (the defaults merge must not have pre-created `tanks`), and a hand-mangled `tanks` must be repaired, not crash (Task 1 tests).
2. **Slot shifting:** removing a tank shifts later slots down; picks travel with their slot; the window must use snapshot indices consistently (Task 1 test + Task 2 live).
3. **Edits in combat** (add tank, add/remove pick, drop a spell on an icon): saved data changes immediately, display/casting change only after combat, nothing errors (Task 2 live).
4. **Empty-name slot with picks:** icons show but clicking must not cast and must say why (Task 2 live).
5. **The same spell on several tanks / at the pick cap / at 8 tanks:** per-tank duplicate rule only; clear messages at the caps; `[+]` and `[+ Add off-tank]` hide at the caps (Task 1 tests + Task 2 live).

---

### Task 1: Slot/pick data model, migration, slash commands (headless)

**Files:**
- Modify: `AutoInvitePlus/modules/TankCast.lua`
- Modify: `tools/tests/tankcast_spec.lua`
- Modify: `AutoInvitePlus/core/Core.lua` (defaults + help)

**Interfaces:**
- Consumes: `AIP.Utils.NormalizeName`, `AIP.Print`, existing `TK.Sanitize/SanitizeName/ParseSpellInput/BuildMacro/ResolveSpell/GetCooldown/IsFriendlyCastable/ClassifyItem/ListSpells/ListItems/FromCursor/RebuildUnits/UnitFor/GetCandidates/TargetName` (unchanged, keep verbatim).
- Produces (all on `AIP.TankCast` = `TK`): `TK.MAX_TANKS`, `TK.MAX_PICKS`, `TK.Cfg()`, `TK.NumTanks()`, `TK.SlotLabel(i)`, `TK.GetSlot(i)`, `TK.FindSlot(name)`, `TK.SetSlot(i, name) -> ok, err`, `TK.AddTank() -> index | nil, err`, `TK.RemoveTank(i) -> ok, err`, `TK.SetFirstOT(name) -> ok, err`, `TK.GetPicks(i) -> array copy`, `TK.AddPick(i, text) -> ok, err`, `TK.SetPick(i, j, text) -> ok, err`, `TK.RemovePick(i, j) -> ok, err`, `TK.AddPickToAll(text) -> count`, `TK.ClearNames()`, `TK.Reset()`, `TK.TrimEmpty()`, `TK.InRange(name, unit, pick)`, `TK.Status(name) -> "ok"|"away"|"offline"|"dead"`, plus the unchanged `ImportFromBlizzard/CanPush/PushToBlizzard/SlashHandler/Changed/OnChanged/OnRoster/RosterChanged/dirty`. **Removed:** `TK.SLOTS`, `TK.GetSpell`, `TK.SetSpell`, `TK.ClearAll`.

- [ ] **Step 1: Rewrite the test tail (tests first)**

In `tools/tests/tankcast_spec.lua`:

(a) Change the stub DB at the top from `db = { tankCast = { mt = "", ots = { "", "", "" }, spell = "" } },` to `db = { tankCast = {} },`.

(b) Replace the `reset()` function body so it installs a fresh table (the module caches "already repaired" by table identity):

```lua
local function reset()
    AIP.db.tankCast = { tanks = { { name = "", picks = {} } } }
    roster, party, targetName = {}, {}, nil
    isLeader, isOfficer = false, false
    assigned, assignCalls, printed = {}, {}, {}
    TK.units = nil
end
```

(c) Replace everything from the line `-- ---- slots ----...` up to (not including) the line `-- ---- units / candidates ----...` with:

```lua
-- ---- slots -----------------------------------------------------------------
reset()
eq(TK.NumTanks(), 1, "starts with just the MT slot")
eq(TK.SlotLabel(1), "MT", "label MT"); eq(TK.SlotLabel(2), "OT1", "label OT1"); eq(TK.SlotLabel(4), "OT3", "label OT3")
eq((TK.SetSlot(2, "bob")), false, "SetSlot on a slot that does not exist yet fails")
eq(TK.AddTank(), 2, "AddTank returns the new index"); eq(TK.NumTanks(), 2, "NumTanks after AddTank")
eq((TK.SetSlot(2, "bob")), true, "SetSlot ok"); eq(TK.GetSlot(2), "Bob", "SetSlot normalises")
TK.SetSlot(1, "BOB")
eq(TK.GetSlot(1), "Bob", "dedupe: MT gets Bob"); eq(TK.GetSlot(2), "", "dedupe: OT1 cleared")
eq(TK.FindSlot("bOb"), 1, "FindSlot case-insensitive"); eq(TK.FindSlot("Nobody"), nil, "FindSlot miss")
local ok2 = TK.SetSlot(1, "/;[]")
eq(ok2, false, "SetSlot rejects junk name"); eq(TK.GetSlot(1), "Bob", "junk leaves slot unchanged")
eq((TK.SetSlot(3, "Bob")), false, "SetSlot rejects a slot beyond NumTanks"); eq((TK.SetSlot(0, "Bob")), false, "SetSlot rejects slot 0")
TK.SetSlot(1, ""); eq(TK.GetSlot(1), "", "SetSlot '' clears the name")

reset()
for i = 2, TK.MAX_TANKS do eq(TK.AddTank(), i, "AddTank fills slot " .. i) end
local noIdx, fullErr = TK.AddTank()
eq(noIdx, nil, "AddTank refuses past the max"); eq(TK.NumTanks(), TK.MAX_TANKS, "NumTanks capped")
eq(fullErr:find(tostring(TK.MAX_TANKS), 1, true) ~= nil, true, "AddTank error mentions the limit")

reset(); TK.AddTank(); TK.AddTank()
TK.SetSlot(2, "A"); TK.SetSlot(3, "B"); TK.AddPick(3, "Innervate")
eq((TK.RemoveTank(1)), false, "the MT slot can't be removed")
eq((TK.RemoveTank(9)), false, "RemoveTank bad slot")
eq((TK.RemoveTank(2)), true, "RemoveTank ok"); eq(TK.NumTanks(), 2, "one slot fewer")
eq(TK.GetSlot(2), "B", "later slots shift down"); eq(TK.GetPicks(2)[1], "Innervate", "picks travel with their slot")

reset(); TK.AddTank(); TK.SetSlot(2, "Bob"); TK.AddPick(2, "Innervate"); TK.SetSlot(1, "bob")
eq(TK.GetSlot(1), "Bob", "dedupe moved the name to the MT"); eq(TK.GetSlot(2), "", "...out of OT1")
eq(#TK.GetPicks(2), 1, "dedupe moves the name, not the picks"); eq(#TK.GetPicks(1), 0, "MT did not inherit the picks")

reset()
eq((TK.SetFirstOT("Aa")), true, "SetFirstOT adds a slot when there is none"); eq(TK.NumTanks(), 2, "one OT slot"); eq(TK.GetSlot(2), "Aa", "OT1=Aa")
TK.SetFirstOT("Bb"); TK.SetFirstOT("Cc")
eq(TK.NumTanks(), 4, "three OT slots"); eq(TK.GetSlot(4), "Cc", "OT3=Cc")
eq((TK.SetFirstOT("aa")), true, "already listed is ok"); eq(TK.NumTanks(), 4, "...and adds no slot")
TK.SetSlot(3, ""); TK.SetFirstOT("Dd"); eq(TK.GetSlot(3), "Dd", "fills a hole before adding a slot"); eq(TK.NumTanks(), 4, "no new slot")
reset()
for _, n in ipairs({ "Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg" }) do TK.SetFirstOT(n) end
eq(TK.NumTanks(), 8, "seven OTs fill the window")
eq((TK.SetFirstOT("Hh")), false, "no room for another OT")

reset(); TK.AddTank(); TK.SetSlot(1, "Aa"); TK.SetSlot(2, "Bb"); TK.AddPick(1, "Innervate")
TK.ClearNames()
eq(TK.GetSlot(1) .. TK.GetSlot(2), "", "ClearNames clears every name"); eq(TK.NumTanks(), 2, "...keeps the slots"); eq(#TK.GetPicks(1), 1, "...and the picks")
TK.Reset(); eq(TK.NumTanks(), 1, "Reset back to the MT slot"); eq(#TK.GetPicks(1), 0, "Reset wipes picks")

reset(); TK.AddTank(); TK.AddTank(); TK.AddPick(2, "Innervate")
TK.TrimEmpty(); eq(TK.NumTanks(), 2, "TrimEmpty drops trailing empty slots but keeps one with picks")

-- ---- picks -----------------------------------------------------------------
reset()
eq((TK.AddPick(1, "Misdirection")), true, "AddPick ok"); eq(TK.GetPicks(1)[1], "Misdirection", "pick stored")
local okd = TK.AddPick(1, "misdirection")
eq(okd, false, "duplicate pick rejected (case-insensitive)"); eq(#TK.GetPicks(1), 1, "no duplicate stored")
eq((TK.AddPick(1, "")), false, "empty pick rejected"); eq((TK.AddPick(1, "  ; / ")), false, "pick that sanitises to empty rejected")
TK.AddPick(1, "Innervate"); TK.AddPick(1, "Hand of Sacrifice"); TK.AddPick(1, "Pain Suppression")
eq(#TK.GetPicks(1), TK.MAX_PICKS, "four picks")
local okc, errc = TK.AddPick(1, "Power Word: Shield")
eq(okc, false, "cap rejects the fifth pick"); eq(errc:find(tostring(TK.MAX_PICKS), 1, true) ~= nil, true, "cap error mentions the limit")
eq((TK.SetPick(1, 2, "Guardian Spirit")), true, "SetPick replaces"); eq(TK.GetPicks(1)[2], "Guardian Spirit", "replaced")
eq((TK.SetPick(1, 2, "Misdirection")), false, "SetPick rejects a duplicate of another pick")
eq((TK.SetPick(1, 2, "Guardian Spirit")), true, "SetPick to the same text is fine")
eq((TK.SetPick(1, 9, "Innervate")), false, "SetPick bad index")
eq((TK.RemovePick(1, 1)), true, "RemovePick ok"); eq(TK.GetPicks(1)[1], "Guardian Spirit", "later picks shift up"); eq(#TK.GetPicks(1), 3, "one fewer")
eq((TK.RemovePick(1, 9)), false, "RemovePick bad index")
eq((TK.AddPick(9, "Innervate")), false, "AddPick bad slot")
reset(); TK.AddPick(1, "|cff71d5ff|Hspell:34477|h[Misdirection]|h|r")
eq(TK.GetPicks(1)[1], "Misdirection", "AddPick accepts a shift-clicked spell link")
reset(); TK.AddPick(1, "Innervate; /run x")
eq(TK.GetPicks(1)[1], "Innervate run x", "AddPick sanitises macro characters")
local copy = TK.GetPicks(1); copy[1] = "Hacked"
eq(TK.GetPicks(1)[1], "Innervate run x", "GetPicks returns a copy")
reset(); TK.AddTank(); TK.AddTank(); TK.AddPick(2, "Innervate")
eq(TK.AddPickToAll("Innervate"), 2, "AddPickToAll skips slots that already have it")
eq(#TK.GetPicks(1) + #TK.GetPicks(2) + #TK.GetPicks(3), 3, "one pick per slot")
eq(TK.AddPickToAll(""), 0, "AddPickToAll ignores empty text")

do -- listeners
    reset(); local n = 0
    TK.OnChanged(function() n = n + 1 end)
    TK.SetSlot(1, "Bob"); eq(n, 1, "Changed fires on SetSlot")
    TK.SetSlot(1, "/"); eq(n, 1, "Changed not fired on rejected SetSlot")
    TK.AddPick(1, "Innervate"); eq(n, 2, "Changed fires on AddPick")
    TK.AddPick(1, ""); eq(n, 2, "Changed not fired on rejected AddPick")
    TK.AddTank(); eq(n, 3, "Changed fires on AddTank")
    TK.RemoveTank(1); eq(n, 3, "Changed not fired on rejected RemoveTank")
end
do -- db missing
    local saved = AIP.db; AIP.db = nil
    eq((TK.SetSlot(1, "Bob")), false, "SetSlot without db"); eq(TK.GetSlot(1), "", "GetSlot without db")
    eq(#TK.GetPicks(1), 0, "GetPicks without db"); eq(TK.NumTanks(), 1, "NumTanks without db")
    eq((TK.AddPick(1, "Innervate")), false, "AddPick without db"); eq(TK.AddTank(), nil, "AddTank without db")
    AIP.db = saved
end
do -- legacy shape migration + repair
    AIP.db.tankCast = { mt = "Old", ots = { "Aa", "", "Bb" }, spell = "Innervate", shown = true }
    eq(TK.NumTanks(), 3, "migration: MT + the non-empty OTs")
    eq(TK.GetSlot(1), "Old", "migration: MT"); eq(TK.GetSlot(2), "Aa", "migration: OT1"); eq(TK.GetSlot(3), "Bb", "migration: holes dropped")
    eq(TK.GetPicks(1)[1] .. TK.GetPicks(2)[1] .. TK.GetPicks(3)[1], "InnervateInnervateInnervate", "migration: shared spell becomes each slot's first pick")
    eq(AIP.db.tankCast.mt, nil, "migration: legacy mt removed"); eq(AIP.db.tankCast.ots, nil, "migration: legacy ots removed"); eq(AIP.db.tankCast.spell, nil, "migration: legacy spell removed")
    eq(AIP.db.tankCast.shown, true, "migration keeps unrelated keys")
    AIP.db.tankCast = { mt = "", ots = { "", "", "" }, spell = "Misdirection" }
    eq(TK.NumTanks(), 1, "migration: empty OTs dropped"); eq(TK.GetPicks(1)[1], "Misdirection", "migration: MT gets the pick even with an empty name")
    AIP.db.tankCast = { mt = "", ots = { "", "", "" }, spell = "" }
    eq(#TK.GetPicks(1), 0, "migration: no legacy spell -> no picks")
    AIP.db.tankCast = { tanks = { "junk", { name = 5, picks = "x" }, { name = "Ok", picks = { "A", "B", "C", "D", "E", 7 } } } }
    eq(TK.NumTanks(), 3, "repair keeps the slot count"); eq(TK.GetSlot(1), "", "repair: junk entry becomes an empty slot")
    eq(TK.GetSlot(2), "", "repair: non-string name"); eq(TK.GetSlot(3), "Ok", "repair keeps valid slots")
    eq(#TK.GetPicks(3), TK.MAX_PICKS, "repair: picks capped, non-strings dropped")
    local many = {}; for i = 1, 12 do many[i] = { name = "", picks = {} } end
    AIP.db.tankCast = { tanks = many }
    eq(TK.NumTanks(), TK.MAX_TANKS, "repair: slot count clamped to the max")
end

```

(d) Replace the block from `-- ---- Blizzard import / push ----...` to the end of file with:

```lua
-- ---- Blizzard import / push ------------------------------------------------
reset(); eq((TK.ImportFromBlizzard()), false, "Import solo fails")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Heal", class = "PRIEST" },
           { name = "Offy", class = "PALADIN", role = "MAINASSIST" }, { name = "Alty", class = "DRUID", role = "MAINASSIST" } }
TK.AddTank(); TK.AddTank(); TK.AddTank(); TK.SetSlot(4, "Old"); TK.AddPick(4, "Innervate")
local iok = TK.ImportFromBlizzard()
eq(iok, true, "Import ok"); eq(TK.GetSlot(1), "Tanky", "Import MT"); eq(TK.GetSlot(2), "Offy", "Import MA1")
eq(TK.GetSlot(3), "Alty", "Import MA2"); eq(TK.GetSlot(4), "", "Import clears leftover names")
eq(TK.NumTanks(), 4, "Import keeps a trailing slot that still has picks"); eq(TK.GetPicks(4)[1], "Innervate", "Import keeps picks")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Offy", class = "PALADIN", role = "MAINASSIST" } }
for _ = 1, 5 do TK.AddTank() end
TK.ImportFromBlizzard(); eq(TK.NumTanks(), 2, "Import trims trailing empty slots")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" } }
for _, n in ipairs({ "Aa", "Bb", "Cc", "Dd", "Ee", "Ff", "Gg", "Hh", "Ii" }) do roster[#roster + 1] = { name = n, class = "PALADIN", role = "MAINASSIST" } end
TK.ImportFromBlizzard()
eq(TK.NumTanks(), TK.MAX_TANKS, "Import adds OT slots up to the max"); eq(TK.GetSlot(TK.MAX_TANKS), "Gg", "Import caps at seven off-tanks")
reset()
roster = { { name = "Heal", class = "PRIEST" } }; TK.SetSlot(1, "Keep")
local nok = TK.ImportFromBlizzard()
eq(nok, false, "Import with no flags fails"); eq(TK.GetSlot(1), "Keep", "Import with no flags changes nothing")

reset()
roster = { { name = "Tanky", class = "WARRIOR" }, { name = "Offy", class = "PALADIN" }, { name = "Alty", class = "DRUID" } }
TK.AddTank(); TK.AddTank(); TK.SetSlot(1, "Tanky"); TK.SetSlot(2, "Offy"); TK.SetSlot(3, "Alty")
eq(TK.CanPush(), false, "CanPush false for plain member")
eq((TK.PushToBlizzard()), false, "Push refused for plain member"); eq(#assignCalls, 0, "Push made no API calls")
isOfficer = true
eq(TK.CanPush(), true, "CanPush true for assist")
eq((TK.PushToBlizzard()), true, "Push ok")
eq(assignCalls[1], "MAINTANK:raid1", "Push MT"); eq(assignCalls[2], "MAINASSIST:raid2", "Push OT1"); eq(assignCalls[3], "MAINASSIST:raid3", "Push OT2")
TK.PushToBlizzard(); eq(#assignCalls, 3, "Push skips flags already set")
reset(); isLeader = true; eq(TK.CanPush(), false, "CanPush false when not in a raid")

-- ---- slash handler ---------------------------------------------------------
reset(); targetName = "Bram"
TK.SlashHandler("mt"); eq(TK.GetSlot(1), "Bram", "slash mt uses the target")
TK.SlashHandler("ot cy"); eq(TK.GetSlot(2), "Cy", "slash ot fills the first OT"); eq(TK.NumTanks(), 2, "slash ot added a slot")
TK.SlashHandler("addot"); eq(TK.NumTanks(), 3, "slash addot")
TK.SlashHandler("pick mt Misdirection"); eq(TK.GetPicks(1)[1], "Misdirection", "slash pick mt")
TK.SlashHandler("pick ot1 Hand of Sacrifice"); eq(TK.GetPicks(2)[1], "Hand of Sacrifice", "slash pick ot1")
TK.SlashHandler("pick 3 Innervate"); eq(TK.GetPicks(3)[1], "Innervate", "slash pick by number")
printed = {}; TK.SlashHandler("pick ot9 Innervate"); eq(#printed > 0, true, "slash pick on a missing slot explains")
TK.SlashHandler("unpick mt misdirection"); eq(#TK.GetPicks(1), 0, "slash unpick is case-insensitive")
TK.SlashHandler("spell Power Word: Shield")
eq(TK.GetPicks(1)[1], "Power Word: Shield", "slash spell adds to the MT"); eq(TK.GetPicks(2)[2], "Power Word: Shield", "...and to every other tank")
TK.SlashHandler("mt Zed"); eq(TK.GetSlot(1), "Zed", "slash mt <name>")
TK.SlashHandler("clear"); eq(TK.GetSlot(1) .. TK.GetSlot(2), "", "slash clear empties the names"); eq(TK.NumTanks(), 3, "...but keeps the slots")
TK.SlashHandler("reset"); eq(TK.NumTanks(), 1, "slash reset"); eq(#TK.GetPicks(1), 0, "slash reset wipes picks")
printed = {}; TK.SlashHandler("list"); eq(#printed >= 1, true, "slash list prints")
printed = {}; TK.SlashHandler("bogus"); eq(#printed > 0, true, "slash unknown prints usage")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tools/tests/tankcast_spec.lua`
Expected: FAIL/error, e.g. `attempt to call field 'NumTanks' (a nil value)`.

- [ ] **Step 3: Replace the constants block in `TankCast.lua`**

Replace
```lua
TK.SLOTS = 4            -- slot 1 = Main Tank, slots 2-4 = Off-Tank 1-3
TK.MACRO_MAX = 250      -- macro text limit is 255; keep headroom
```
with
```lua
TK.MAX_TANKS = 8        -- slot 1 = Main Tank (always exists), slots 2..8 = Off-Tanks added on demand
TK.MAX_PICKS = 4        -- spells/items per tank
TK.MACRO_MAX = 250      -- macro text limit is 255; keep headroom
```

- [ ] **Step 4: Replace the SAVED STATE section (`cfg` and `setRaw`)**

Replace the whole block from `-- AIP.db.tankCast (defaults live in core/Core.lua)...` through `local function setRaw(c, i, value) ... end` with:

```lua
-- AIP.db.tankCast = { tanks = { {name = "", picks = {...}}, ... }, shown, showConfig, pos }.
-- tanks[1] is the MT and always exists. Defaults live in core/Core.lua but must
-- NOT include `tanks` (a pre-created empty table would block the migration below).
-- Picks belong to the SLOT, not the player.

local function newSlot() return { name = "", picks = {} } end

-- One-time migration from the pre-multi-tank shape {mt, ots[3], spell}.
local function migrate(c)
    if c.tanks ~= nil then return end
    local tanks = { { name = type(c.mt) == "string" and c.mt or "", picks = {} } }
    if type(c.ots) == "table" then
        for _, n in ipairs(c.ots) do
            if type(n) == "string" and n ~= "" and #tanks < TK.MAX_TANKS then
                tanks[#tanks + 1] = { name = n, picks = {} }
            end
        end
    end
    local spell = type(c.spell) == "string" and TK.ParseSpellInput(c.spell) or ""
    if spell ~= "" then
        for _, t in ipairs(tanks) do t.picks[1] = spell end
    end
    c.tanks = tanks
    c.mt, c.ots, c.spell = nil, nil, nil
end

local repairedFor    -- the tankCast table we last validated (repair is not free; do it once per table)

-- Returns the (shape-repaired) saved table, or nil before SavedVariables load.
local function cfg()
    local db = AIP.db
    if not db then return nil end
    local c = db.tankCast
    if type(c) ~= "table" then c = {}; db.tankCast = c end
    if repairedFor == c then return c end
    migrate(c)
    if type(c.tanks) ~= "table" then c.tanks = {} end
    local tanks = c.tanks
    for i = 1, #tanks do
        local t = tanks[i]
        if type(t) ~= "table" then t = newSlot(); tanks[i] = t end
        if type(t.name) ~= "string" then t.name = "" end
        local clean = {}
        if type(t.picks) == "table" then
            for _, p in ipairs(t.picks) do
                if type(p) == "string" and p ~= "" and #clean < TK.MAX_PICKS then clean[#clean + 1] = p end
            end
        end
        t.picks = clean
    end
    while #tanks > TK.MAX_TANKS do table.remove(tanks) end
    if #tanks == 0 then tanks[1] = newSlot() end
    repairedFor = c
    return c
end
TK.Cfg = cfg

local function slots()
    local c = cfg()
    return c and c.tanks or nil
end
```

Note: `migrate` calls `TK.ParseSpellInput`, which is defined later in the file; that is fine because `migrate` only runs at call time.

- [ ] **Step 5: Replace the TANK LIST section**

Replace everything from `function TK.SlotLabel(i)` through the end of `function TK.SetSpell(text) ... end` (this removes `GetSlot`, `FindSlot`, `normalize`, `SetSlot`, `SetFirstOT`, `ClearAll`, `GetSpell`, `SetSpell`) with:

```lua
function TK.NumTanks()
    local t = slots()
    return t and #t or 1
end

function TK.SlotLabel(i)
    if i == 1 then return "MT" end
    return "OT" .. tostring((i or 1) - 1)
end

function TK.GetSlot(i)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    return s and s.name or ""
end

function TK.FindSlot(name)
    if type(name) ~= "string" or name == "" then return nil end
    local t = slots()
    if not t then return nil end
    local lname = name:lower()
    for i = 1, #t do
        if t[i].name ~= "" and t[i].name:lower() == lname then return i end
    end
    return nil
end

local function normalize(name)
    if AIP.Utils and AIP.Utils.NormalizeName then return AIP.Utils.NormalizeName(name) end
    return name
end

-- Assign (or clear, with nil/"") the player in a slot. A name already in another
-- slot MOVES (the picks stay with their slots). Returns ok, errorMessage.
function TK.SetSlot(i, name)
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    if type(i) ~= "number" or i < 1 or i > #t or i ~= math.floor(i) then
        return false, "Bad tank slot."
    end
    if name == nil or name == "" then
        t[i].name = ""
        TK.Changed()
        return true
    end
    local clean = TK.SanitizeName(name)
    local norm = clean ~= "" and normalize(clean) or nil
    if not norm then return false, "Invalid player name." end
    for s = 1, #t do
        if s ~= i and t[s].name:lower() == norm:lower() then t[s].name = "" end
    end
    t[i].name = norm
    TK.Changed()
    return true
end

-- Append an empty off-tank slot. Returns its index, or nil + message.
function TK.AddTank()
    local t = slots()
    if not t then return nil, "Settings are not loaded yet." end
    if #t >= TK.MAX_TANKS then
        return nil, "All " .. TK.MAX_TANKS .. " tank slots are in use."
    end
    t[#t + 1] = newSlot()
    TK.Changed()
    return #t
end

-- Remove an off-tank slot (and its picks); later slots shift down.
function TK.RemoveTank(i)
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    if i == 1 then return false, "The main tank slot can't be removed." end
    if type(i) ~= "number" or i < 2 or i > #t or i ~= math.floor(i) then return false, "Bad tank slot." end
    table.remove(t, i)
    TK.Changed()
    return true
end

-- Put a name in the first empty off-tank slot, adding a slot if none is empty
-- (no-op if the player is already listed).
function TK.SetFirstOT(name)
    local clean = TK.SanitizeName(name)
    if clean == "" then return false, "Invalid player name." end
    if TK.FindSlot(clean) then return true end
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    for i = 2, #t do
        if t[i].name == "" then return TK.SetSlot(i, name) end
    end
    local idx, err = TK.AddTank()
    if not idx then return false, err end
    return TK.SetSlot(idx, name)
end

-- Clear every player name (slots and picks stay).
function TK.ClearNames()
    local t = slots()
    if not t then return end
    for i = 1, #t do t[i].name = "" end
    TK.Changed()
end

-- Back to a lone empty MT slot with no picks.
function TK.Reset()
    local c = cfg()
    if not c then return end
    c.tanks = { newSlot() }
    TK.Changed()
end

-- Drop trailing off-tank slots that have neither a player nor picks (no event;
-- callers fire Changed themselves).
function TK.TrimEmpty()
    local t = slots()
    if not t then return end
    while #t > 1 and t[#t].name == "" and #t[#t].picks == 0 do table.remove(t) end
end

-- ---- picks (spells / items cast on a tank) ---------------------------------

local function validPick(text)
    local clean = TK.ParseSpellInput(text)
    if clean == "" then return nil, "Enter a spell or item name." end
    return clean
end

local function hasPick(picks, clean, skip)
    local l = clean:lower()
    for k, p in ipairs(picks) do
        if k ~= skip and p:lower() == l then return true end
    end
    return false
end

function TK.GetPicks(i)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    local out = {}
    if s then for k, p in ipairs(s.picks) do out[k] = p end end
    return out
end

function TK.AddPick(i, text)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    local clean, err = validPick(text)
    if not clean then return false, err end
    if #s.picks >= TK.MAX_PICKS then return false, "That tank already has " .. TK.MAX_PICKS .. " picks." end
    if hasPick(s.picks, clean) then return false, "That tank already has '" .. clean .. "'." end
    s.picks[#s.picks + 1] = clean
    TK.Changed()
    return true
end

function TK.SetPick(i, j, text)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    if type(j) ~= "number" or not s.picks[j] then return false, "Bad pick." end
    local clean, err = validPick(text)
    if not clean then return false, err end
    if hasPick(s.picks, clean, j) then return false, "That tank already has '" .. clean .. "'." end
    s.picks[j] = clean
    TK.Changed()
    return true
end

function TK.RemovePick(i, j)
    local t = slots()
    local s = t and type(i) == "number" and t[i]
    if not s then return false, "Bad tank slot." end
    if type(j) ~= "number" or not s.picks[j] then return false, "Bad pick." end
    table.remove(s.picks, j)
    TK.Changed()
    return true
end

-- Add one pick to every tank that has room and doesn't already have it.
-- Returns how many tanks got it.
function TK.AddPickToAll(text)
    local t = slots()
    if not t then return 0 end
    local clean = validPick(text)
    if not clean then return 0 end
    local n = 0
    for _, s in ipairs(t) do
        if #s.picks < TK.MAX_PICKS and not hasPick(s.picks, clean) then
            s.picks[#s.picks + 1] = clean
            n = n + 1
        end
    end
    if n > 0 then TK.Changed() end
    return n
end
```

- [ ] **Step 6: Replace `InRange` and `Status`**

Replace the `TK.InRange` and `TK.Status` functions (and the comment above `InRange`) with:

```lua
-- Is the tank close enough for THIS pick? Uses the pick's own range when the
-- client can tell, else the 28-yard interact distance.
function TK.InRange(name, unit, pick)
    unit = unit or TK.UnitFor(name)
    if not unit then return false end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    if pick and pick ~= "" then
        local kind = TK.ResolveSpell(pick)
        if kind == "spell" and IsSpellInRange then
            local r = IsSpellInRange(pick, unit)
            if r ~= nil then return r == 1 end
        elseif kind == "item" and IsItemInRange then
            local r = IsItemInRange(pick, unit)
            if r ~= nil then return r == 1 end
        end
    end
    if CheckInteractDistance then return CheckInteractDistance(unit, 4) and true or false end
    return true
end

-- Tank-level state (range is per pick, see InRange):
-- "ok" | "away" (not in group) | "offline" | "dead"
function TK.Status(name)
    local unit = TK.UnitFor(name)
    if not unit then return "away" end
    if UnitIsConnected and not UnitIsConnected(unit) then return "offline" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return "dead" end
    return "ok"
end
```

- [ ] **Step 7: Replace `ImportFromBlizzard` and the loop in `PushToBlizzard`**

Replace the whole `TK.ImportFromBlizzard` function with:

```lua
-- Mirror the raid's flags: MAINTANK -> MT slot, MAINASSIST players -> OT slots
-- (slots are added as needed, up to the max). Names are replaced; picks stay.
function TK.ImportFromBlizzard()
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    if n == 0 then return false, "You are not in a raid." end
    local mt, assists = nil, {}
    for i = 1, n do
        local name, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
        if name then
            if role == "MAINTANK" then mt = name
            elseif role == "MAINASSIST" then assists[#assists + 1] = name end
        end
    end
    if not mt and #assists == 0 then
        return false, "No Main Tank / Main Assist flags are set in this raid."
    end
    local t = slots()
    if not t then return false, "Settings are not loaded yet." end
    for i = 1, #t do t[i].name = "" end
    local nOT = math.min(#assists, TK.MAX_TANKS - 1)
    while #t < 1 + nOT do t[#t + 1] = newSlot() end
    local function put(i, name)
        local norm = normalize(TK.SanitizeName(name))
        if norm and norm ~= "" then t[i].name = norm end
    end
    if mt then put(1, mt) end
    for k = 1, nOT do put(k + 1, assists[k]) end
    TK.TrimEmpty()
    TK.Changed()
    return true, string.format("Imported from the raid flags: MT %s, %d off-tank(s) (from Main Assists).",
        mt or "none", nOT)
end
```

In `TK.PushToBlizzard`, change `for i = 1, TK.SLOTS do` to `for i = 1, TK.NumTanks() do`.

- [ ] **Step 8: Replace the slash handler**

Replace the whole `TK.SlashHandler` function (and its header comment) with:

```lua
-- ============================================================================
-- SLASH: /aip tanks [mt|ot|addot|pick|unpick|spell|clear|reset|sync|push|list]
-- ============================================================================

-- "mt" -> 1, "ot1".."ot7" -> 2..8, "1".."8" -> that slot; nil if unrecognised.
local function parseSlot(sel)
    sel = (sel or ""):lower()
    if sel == "mt" then return 1 end
    local n = sel:match("^ot(%d+)$")
    if n then return tonumber(n) + 1 end
    n = sel:match("^(%d+)$")
    if n then return tonumber(n) end
    return nil
end

local USAGE = "/aip tanks [mt|ot [name]] [addot] [pick|unpick <mt|otN> <name>] [spell <name>] [clear] [reset] [sync] [push] [list]"

function TK.SlashHandler(rest)
    local sub, arg = (rest or ""):match("^(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    arg = arg or ""

    if sub == "" then
        if TK.ToggleWindow then TK.ToggleWindow() else say("The tank window is not loaded.") end
    elseif sub == "mt" then
        local name = (arg ~= "") and arg or TK.TargetName()
        if not name then
            say("Usage: /aip tanks mt <name>  (or target a player and omit the name)")
            return
        end
        local ok, err = TK.SetSlot(1, name)
        say(ok and ("Main tank set to " .. TK.GetSlot(1)) or err)
    elseif sub == "ot" then
        local name = (arg ~= "") and arg or TK.TargetName()
        if not name then
            say("Usage: /aip tanks ot <name>  (or target a player and omit the name)")
            return
        end
        local ok, err = TK.SetFirstOT(name)
        say(ok and ("Off-tank added: " .. name) or err)
    elseif sub == "addot" then
        local idx, err = TK.AddTank()
        say(idx and ("Added an empty slot: " .. TK.SlotLabel(idx)) or err)
    elseif sub == "pick" or sub == "unpick" then
        local sel, text = arg:match("^(%S+)%s*(.-)$")
        local slot = parseSlot(sel)
        if not slot or not text or text == "" then
            say("Usage: /aip tanks " .. sub .. " <mt|ot1..ot7> <spell or item name>")
            return
        end
        if slot < 1 or slot > TK.NumTanks() then
            say("There is no " .. (sel or "?") .. " slot yet (use /aip tanks addot).")
            return
        end
        if sub == "pick" then
            local ok, err = TK.AddPick(slot, text)
            say(ok and (TK.SlotLabel(slot) .. " pick added: " .. TK.ParseSpellInput(text)) or err)
        else
            local want = TK.ParseSpellInput(text):lower()
            local found
            for j, p in ipairs(TK.GetPicks(slot)) do
                if p:lower() == want then found = j; break end
            end
            if not found then say(TK.SlotLabel(slot) .. " has no pick called '" .. text .. "'.") return end
            TK.RemovePick(slot, found)
            say(TK.SlotLabel(slot) .. " pick removed: " .. text)
        end
    elseif sub == "spell" then
        if arg == "" then
            say("Usage: /aip tanks spell <spell or item name>   (adds it to every tank)")
            return
        end
        local n = TK.AddPickToAll(arg)
        say("Added '" .. TK.ParseSpellInput(arg) .. "' to " .. n .. " tank(s).")
    elseif sub == "clear" then
        TK.ClearNames()
        say("Tank names cleared (slots and picks kept; /aip tanks reset wipes everything).")
    elseif sub == "reset" then
        TK.Reset()
        say("Tank list reset.")
    elseif sub == "sync" or sub == "import" then
        local _, msg = TK.ImportFromBlizzard()
        say(msg)
    elseif sub == "push" then
        local _, msg = TK.PushToBlizzard()
        say(msg)
    elseif sub == "list" then
        for i = 1, TK.NumTanks() do
            local n = TK.GetSlot(i)
            local picks = table.concat(TK.GetPicks(i), ", ")
            say(TK.SlotLabel(i) .. ": " .. (n ~= "" and n or "-") .. "  [" .. (picks ~= "" and picks or "no picks") .. "]")
        end
    else
        say(USAGE)
    end
end
```

- [ ] **Step 9: Run the tests to verify they pass**

Run: `luajit tools/tests/tankcast_spec.lua`
Expected: `N passed, 0 failed` (all earlier logic tests for sanitising, units, pickers, ClassifyItem still pass; N will be well over 150). Fix the module, not the test, on any `FAIL` unless the expectation contradicts the spec.

- [ ] **Step 10: Core.lua defaults and help**

In `AutoInvitePlus/core/Core.lua`, replace the `tankCast = { ... }` defaults block (the one added earlier: `mt`, `ots`, `spell`, `shown`, `showConfig`, `pos`) with:

```lua
    -- Tank Cast window (AIP.TankCast). `tanks` ({ {name, picks}, ... }, [1] = MT) is
    -- deliberately NOT a default: TK.Cfg() creates it, migrating any legacy
    -- mt/ots/spell keys first - a pre-created empty table would block that.
    tankCast = {
        shown = false,              -- window visible (persisted across reloads)
        showConfig = false,         -- Import/Push strip expanded
        pos = nil,                  -- {point, relPoint, x, y}
    },
```

and replace the two `/aip tanks` help lines with:

```lua
        Print("  /aip tanks - Toggle the Tank Cast window (tanks + per-tank spell/item picks)")
        Print("  /aip tanks mt|ot [name] | addot | pick|unpick <mt|otN> <name> | spell <name> | clear | reset | sync | push | list")
```

- [ ] **Step 11: Checkpoint**

Run the syntax check on `AutoInvitePlus/modules/TankCast.lua`, `AutoInvitePlus/core/Core.lua`, `tools/tests/tankcast_spec.lua`; run `luajit tools/tests/tankcast_spec.lua` again. Expected: all `OK`, `0 failed`. **Do not commit.**

---

### Task 2: Window rewrite (rows, pick buttons, add-tank)

**Files:**
- Modify (full rewrite): `AutoInvitePlus/ui/TankCastWindow.lua`

**Interfaces:**
- Consumes: everything from Task 1; `AIP.UI.CreateButton/CreateIconButton`; guarded calls to Task 3's `TK.OpenPicker(slot, pickIndexOrNil)`, `TK.BuildConfigStrip(win)`, `TK.SyncConfigStrip()`; WoW `EasyMenu`, `CooldownFrame_SetTimer`, `RAID_CLASS_COLORS`, `InCombatLockdown`, `GetCursorInfo` (via `TK.FromCursor`), `ClearCursor`.
- Produces: `TK.ShowWindow/HideWindow/ToggleWindow/IsWindowShown`, `TK.LayoutWindow()`, `TK.EnsureMenuFrame()`, constants `TK.WIN_W`, `TK.PAD`, `TK.CFG_H`. Expects Task 3 to set `win.cfg` (Frame of height `TK.CFG_H` anchored to the window bottom).

- [ ] **Step 1: Write the new window file**

Replace the entire contents of `AutoInvitePlus/ui/TankCastWindow.lua` with:

```lua
-- AutoInvite Plus - Tank Cast window (presentation for AIP.TankCast)
-- Floating window with one two-line row per tank (MT + off-tanks). Line 1: role
-- chip, class-coloured name, health bar. Line 2: one icon button per pick (each a
-- secure button that casts that spell/item on that tank via
-- `/cast [target=<Name>] <pick>`) plus a dim [+] to add a pick.
--
-- 3.3.5a secure-frame rules this file obeys:
--  * the 32 pick buttons are SecureActionButtonTemplate (protected): attributes,
--    Show/Hide and SetPoint are ONLY touched when not InCombatLockdown()
--    (see applyStructure);
--  * their parents (the 8 row containers) and the window are therefore
--    implicitly protected too: Show/Hide/SetHeight/StartMoving on them are also
--    blocked in combat, so they are guarded/deferred the same way, and every
--    frame is CREATED out of combat (PLAYER_LOGIN / first ShowWindow);
--  * everything is rendered from the `applied` snapshot, so the window never
--    disagrees with what a click casts even while an edit waits for combat to end.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local WIN_W, PAD, HDR_H = 210, 6, 20
local ROW_W = WIN_W - PAD * 2
local ROW_H, ROW_GAP = 48, 3
local NAME_X = 34
local PICK_SZ, PICK_GAP, PICK_Y = 22, 3, 25
local HP_W = ROW_W - NAME_X - 6
local ADD_H, STATUS_H, CFG_H = 20, 14, 26
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
TK.WIN_W, TK.PAD, TK.CFG_H = WIN_W, PAD, CFG_H

local STATE_TEXT = { away = "Not in your group", offline = "Offline", dead = "Dead" }

local win
local rows = {}
local menuFrame
-- Snapshot of what the secure buttons currently do:
-- applied.count = number of tanks; applied.tanks[i] = { name, picks = { {text, kind, icon, friendly} } }
local applied = { count = 0, tanks = {} }
local refresh, refreshValues                            -- forward declarations

-- ============================================================================
-- SMALL HELPERS
-- ============================================================================

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.85, 0.85, 0.9
end

local function hex(r, g, b)
    return string.format("|cFF%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function TK.EnsureMenuFrame()
    if not menuFrame then
        menuFrame = CreateFrame("Frame", "AIPTankCastMenu", UIParent, "UIDropDownMenuTemplate")
    end
    return menuFrame
end

local function cfgOpen()
    local c = TK.Cfg()
    return win and win.cfg ~= nil and c ~= nil and c.showConfig and true or false
end

local function snapshotName(slot)
    local s = applied.tanks[slot]
    return s and s.name or ""
end

-- ============================================================================
-- MENUS / DROP
-- ============================================================================

-- Tank menu: use my target / clear / remove tank / assign a group member.
local function openTankMenu(slot)
    local current = TK.GetSlot(slot)
    local list = {}
    list[#list + 1] = {
        text = TK.SlotLabel(slot) .. ((current ~= "") and (" - " .. current) or ""),
        isTitle = true, notCheckable = true,
    }
    list[#list + 1] = {
        text = "Use my target", notCheckable = true,
        func = function()
            local n = TK.TargetName()
            if not n then AIP.Print("Target a player first.") return end
            local ok, err = TK.SetSlot(slot, n)
            if not ok then AIP.Print(err) end
        end,
    }
    if current ~= "" then
        list[#list + 1] = { text = "Clear player", notCheckable = true, func = function() TK.SetSlot(slot, "") end }
    end
    if slot >= 2 then
        list[#list + 1] = {
            text = "Remove tank", notCheckable = true,
            func = function()
                local ok, err = TK.RemoveTank(slot)
                if not ok then AIP.Print(err) end
            end,
        }
    end

    local cands = TK.GetCandidates()
    if #cands > 0 then
        list[#list + 1] = { text = "Assign player", isTitle = true, notCheckable = true }
        local sawOthers = false
        for k, cand in ipairs(cands) do
            if k > 40 then break end
            if not cand.tank and not sawOthers then
                sawOthers = true
                list[#list + 1] = { text = "Other classes", isTitle = true, notCheckable = true }
            end
            local text = hex(classColor(cand.class)) .. cand.name .. "|r"
            local at = TK.FindSlot(cand.name)
            if at then text = text .. " |cFF888888(" .. TK.SlotLabel(at) .. ")|r" end
            list[#list + 1] = {
                text = text, notCheckable = true,
                func = function()
                    local ok, err = TK.SetSlot(slot, cand.name)
                    if not ok then AIP.Print(err) end
                end,
            }
        end
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, TK.EnsureMenuFrame(), "cursor", 0, 0, "MENU")
end

-- Pick menu (right-click an icon): change / remove.
local function openPickMenu(btn)
    local slot, idx = btn.slot, btn.idx
    local pk = applied.tanks[slot] and applied.tanks[slot].picks[idx]
    local list = {
        { text = pk and pk.text or "Pick", isTitle = true, notCheckable = true },
        { text = "Change pick...", notCheckable = true,
          func = function() if TK.OpenPicker then TK.OpenPicker(slot, idx) end end },
        { text = "Remove pick", notCheckable = true,
          func = function()
              local ok, err = TK.RemovePick(slot, idx)
              if not ok then AIP.Print(err) end
          end },
        { text = "Cancel", notCheckable = true },
    }
    EasyMenu(list, TK.EnsureMenuFrame(), "cursor", 0, 0, "MENU")
end

-- A spell/item dragged from the spellbook/bags onto an icon (replace) or [+] (add).
-- Returns true if the cursor held one.
local function dropOn(slot, idx)
    local name = TK.FromCursor()
    if not name then return false end
    ClearCursor()
    local ok, err
    if idx then ok, err = TK.SetPick(slot, idx, name) else ok, err = TK.AddPick(slot, name) end
    if not ok then AIP.Print(err) end
    return true
end

-- ============================================================================
-- ROWS
-- ============================================================================

local function createPick(row, i, j)
    local b = CreateFrame("Button", "AIPTankCastPick" .. i .. "_" .. j, row, "SecureActionButtonTemplate")
    b.slot, b.idx = i, j
    b:SetSize(PICK_SZ, PICK_SZ)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:Hide()

    b.border = b:CreateTexture(nil, "BACKGROUND")
    b.border:SetAllPoints(); b.border:SetTexture(0.2, 0.22, 0.3, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1); b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
    b.dim = b:CreateTexture(nil, "OVERLAY", nil, 7)
    b.dim:SetAllPoints(); b.dim:SetTexture(0, 0, 0, 0.55); b.dim:Hide()

    -- Left-click is the secure macro; this non-secure hook handles right-click and
    -- the "why did nothing happen" hints.
    b:HookScript("OnClick", function(self, button)
        if button == "RightButton" then
            openPickMenu(self)
        elseif not self.macroSet then
            if snapshotName(self.slot) == "" then
                AIP.Print("Assign a player to this tank first (click the name).")
            else
                AIP.Print("This pick can't be cast (check the spell or item name).")
            end
        end
    end)
    b:SetScript("OnReceiveDrag", function(self) dropOn(self.slot, self.idx) end)
    b:SetScript("OnEnter", function(self)
        local snap = applied.tanks[self.slot]
        local pk = snap and snap.picks[self.idx]
        if not pk then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(pk.text, 1, 0.82, 0)
        if snap.name ~= "" then
            GameTooltip:AddLine("Left-click: cast on " .. snap.name, 1, 1, 1)
        else
            GameTooltip:AddLine("Assign a player to this tank first.", 1, 0.5, 0.3)
        end
        if not pk.kind then
            GameTooltip:AddLine("Not in your spellbook or bags.", 0.95, 0.3, 0.3)
        elseif pk.friendly == false then
            GameTooltip:AddLine("Can't target a friendly player.", 1, 0.6, 0.2)
        end
        GameTooltip:AddLine("Right-click: change / remove", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function createRow(i)
    local row = CreateFrame("Frame", "AIPTankCastRow" .. i, win)
    row.slot = i
    row.tank = ""
    row:SetSize(ROW_W, ROW_H)
    row:Hide()

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(0.11, 0.12, 0.17, 0.92)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT"); row.accent:SetWidth(2)

    row.chip = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.chip:SetPoint("TOPLEFT", 7, -6); row.chip:SetWidth(26); row.chip:SetJustifyH("LEFT")
    row.chip:SetText(i == 1 and "|cFFFFD700MT|r" or ("|cFFC0C4D0OT" .. (i - 1) .. "|r"))

    -- Name button: click = tank menu.
    row.nameBtn = CreateFrame("Button", nil, row)
    row.nameBtn:SetPoint("TOPLEFT", NAME_X, -2); row.nameBtn:SetSize(HP_W, 18)
    local nhl = row.nameBtn:CreateTexture(nil, "HIGHLIGHT")
    nhl:SetAllPoints(); nhl:SetTexture(1, 0.82, 0, 0.14)
    row.nameFS = row.nameBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", 2, 0); row.nameFS:SetPoint("RIGHT", -2, 0); row.nameFS:SetJustifyH("LEFT")
    row.nameBtn:SetScript("OnClick", function() openTankMenu(i) end)
    row.nameBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local nm = snapshotName(i)
        if nm == "" then
            GameTooltip:AddLine("Set " .. TK.SlotLabel(i), 1, 0.82, 0)
            GameTooltip:AddLine("Click to pick a player.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(nm, 1, 0.82, 0)
            if row.stateText then GameTooltip:AddLine(row.stateText, 1, 0.5, 0.3) end
            GameTooltip:AddLine("Click: change / clear / remove tank", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row.nameBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.hpBg = row:CreateTexture(nil, "ARTWORK")
    row.hpBg:SetPoint("TOPLEFT", NAME_X, -21); row.hpBg:SetSize(HP_W, 3); row.hpBg:SetTexture(0, 0, 0, 0.6)
    row.hp = row:CreateTexture(nil, "OVERLAY")
    row.hp:SetPoint("TOPLEFT", NAME_X, -21); row.hp:SetSize(HP_W, 3); row.hp:SetTexture(0.2, 0.85, 0.3, 1)

    row.picks = {}
    for j = 1, TK.MAX_PICKS do row.picks[j] = createPick(row, i, j) end

    -- [+] add a pick.
    row.plus = CreateFrame("Button", nil, row)
    row.plus:SetSize(PICK_SZ, PICK_SZ); row.plus:Hide()
    local pbg = row.plus:CreateTexture(nil, "BACKGROUND")
    pbg:SetAllPoints(); pbg:SetTexture(0.16, 0.17, 0.24, 0.9)
    local pfs = row.plus:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pfs:SetPoint("CENTER", 0, 1); pfs:SetText("|cFF8A8FA0+|r")
    local phl = row.plus:CreateTexture(nil, "HIGHLIGHT")
    phl:SetAllPoints(); phl:SetTexture(1, 0.82, 0, 0.2)
    row.plus:SetScript("OnClick", function()
        if not dropOn(i, nil) and TK.OpenPicker then TK.OpenPicker(i, nil) end
    end)
    row.plus:SetScript("OnReceiveDrag", function() dropOn(i, nil) end)
    row.plus:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Add a pick", 1, 0.82, 0)
        GameTooltip:AddLine("Click to choose a spell or item, or drag one here.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row.plus:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- ============================================================================
-- LAYOUT / STRUCTURE
-- ============================================================================

-- Window height + status-line position. The window is implicitly protected
-- (parent of protected rows), so resizing in combat is blocked: defer to the
-- post-combat flush (refresh re-runs this).
function TK.LayoutWindow()
    if not win then return end
    if InCombatLockdown() then TK.dirty = true; return end
    local y = win.contentH or (HDR_H + PAD + ROW_H + ROW_GAP)
    win.status:ClearAllPoints()
    win.status:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 2, -y)
    local h = y + STATUS_H + PAD
    if cfgOpen() then
        h = h + CFG_H
        win.cfg:Show()
    elseif win.cfg then
        win.cfg:Hide()
    end
    win:SetHeight(h)
end

-- Out-of-combat only: snapshot the list, (re)write every secure attribute,
-- lay out rows / pick icons / [+] / [+ Add off-tank].
local function applyStructure()
    local n = TK.NumTanks()
    applied.count = n
    local y = HDR_H + PAD
    for i = 1, TK.MAX_TANKS do
        local row = rows[i]
        if i <= n then
            local name = TK.GetSlot(i)
            local picks = TK.GetPicks(i)
            local snap = { name = name, picks = {} }
            applied.tanks[i] = snap
            row.tank = name
            for j = 1, TK.MAX_PICKS do
                local btn, text = row.picks[j], picks[j]
                btn.cdStart, btn.cdDur = nil, nil
                if text then
                    local kind, icon = TK.ResolveSpell(text)
                    snap.picks[j] = { text = text, kind = kind, icon = icon, friendly = TK.IsFriendlyCastable(text) }
                    local macro = TK.BuildMacro(name, text)
                    btn:SetAttribute("type1", macro and "macro" or nil)
                    btn:SetAttribute("macrotext1", macro)
                    btn.macroSet = macro ~= nil
                    btn:ClearAllPoints()
                    btn:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X + (j - 1) * (PICK_SZ + PICK_GAP), -PICK_Y)
                    btn:Show()
                else
                    btn:SetAttribute("type1", nil)
                    btn:SetAttribute("macrotext1", nil)
                    btn.macroSet = false
                    btn:Hide()
                end
            end
            if #picks < TK.MAX_PICKS then
                row.plus:ClearAllPoints()
                row.plus:SetPoint("TOPLEFT", row, "TOPLEFT", NAME_X + #picks * (PICK_SZ + PICK_GAP), -PICK_Y)
                row.plus:Show()
            else
                row.plus:Hide()
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
            row:Show()
            y = y + ROW_H + ROW_GAP
        else
            applied.tanks[i] = nil
            row.tank = ""
            for j = 1, TK.MAX_PICKS do
                local btn = row.picks[j]
                btn:SetAttribute("type1", nil)
                btn:SetAttribute("macrotext1", nil)
                btn.macroSet = false
                btn:Hide()
            end
            row.plus:Hide()
            row:Hide()
        end
    end
    if n < TK.MAX_TANKS then
        win.addBtn:ClearAllPoints()
        win.addBtn:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -y)
        win.addBtn:Show()
        y = y + ADD_H + ROW_GAP
    else
        win.addBtn:Hide()
    end
    win.contentH = y
    TK.LayoutWindow()
end

-- ============================================================================
-- LIVE VALUES (health, range, cooldowns, status line)
-- ============================================================================

local function cooldownFor(pk, cache)
    local c = cache[pk.text]
    if not c then
        local s, d, e = TK.GetCooldown(pk.text, pk.kind)
        if d and d <= 1.5 then s, d = 0, 0 end            -- ignore the global cooldown
        c = { s or 0, d or 0, e or 0 }
        cache[pk.text] = c
    end
    return c
end

local function updateRow(i, cache)
    local row, snap = rows[i], applied.tanks[i]
    if not snap then return end
    local name = snap.name
    local unit, status
    if name == "" then
        row.nameFS:SetText("|cFF7A7F8E+ Set " .. TK.SlotLabel(i) .. "|r")
        row.nameFS:SetAlpha(1)
        row.accent:SetTexture(0.4, 0.42, 0.5, 0.5)
        row.hp:Hide(); row.hpBg:Hide()
        row.stateText = nil
        status = "away"
    else
        unit = TK.UnitFor(name)
        local class
        if unit then local _, cl = UnitClass(unit); class = cl end
        local r, g, b = classColor(class)
        row.nameFS:SetText(hex(r, g, b) .. name .. "|r")
        if i == 1 then row.accent:SetTexture(1, 0.82, 0, 0.7) else row.accent:SetTexture(0.75, 0.78, 0.85, 0.6) end
        local pct = 0
        if unit and UnitExists(unit) then
            local m = UnitHealthMax(unit)
            if m and m > 0 then pct = UnitHealth(unit) / m end
        end
        row.hp:Show(); row.hpBg:Show()
        row.hp:SetWidth(math.max(1, HP_W * pct))
        if pct > 0.5 then row.hp:SetTexture(0.2, 0.85, 0.3, 1)
        elseif pct > 0.25 then row.hp:SetTexture(0.95, 0.8, 0.2, 1)
        else row.hp:SetTexture(0.9, 0.2, 0.2, 1) end
        status = TK.Status(name)
        row.stateText = STATE_TEXT[status]
        row.nameFS:SetAlpha(status == "ok" and 1 or 0.5)
    end
    for j = 1, TK.MAX_PICKS do
        local btn, pk = row.picks[j], snap.picks[j]
        if pk then
            if not pk.kind then     -- an item may not have been cached when applied; retry
                pk.kind, pk.icon = TK.ResolveSpell(pk.text)
                if pk.kind then pk.friendly = TK.IsFriendlyCastable(pk.text) end
            end
            btn.icon:SetTexture(pk.icon or QUESTION)
            if not pk.kind then btn.border:SetTexture(0.9, 0.2, 0.2, 1)
            elseif pk.friendly == false then btn.border:SetTexture(0.95, 0.6, 0.2, 1)
            else btn.border:SetTexture(0.2, 0.22, 0.3, 1) end
            local dim = (status ~= "ok") or not TK.InRange(name, unit, pk.text)
            if dim then btn.dim:Show() else btn.dim:Hide() end
            local cdv = cooldownFor(pk, cache)
            if btn.cdStart ~= cdv[1] or btn.cdDur ~= cdv[2] then
                CooldownFrame_SetTimer(btn.cd, cdv[1], cdv[2], cdv[3])
                btn.cdStart, btn.cdDur = cdv[1], cdv[2]
            end
        end
    end
end

local function updateStatus()
    local anyPick, unknown, notFriendly = false, false, false
    for i = 1, applied.count do
        for _, pk in ipairs(applied.tanks[i].picks) do
            anyPick = true
            if not pk.kind then unknown = true elseif pk.friendly == false then notFriendly = true end
        end
    end
    local text, r, g, b
    if TK.dirty then
        text, r, g, b = "Changes apply after combat", 1, 0.6, 0.2
    elseif not anyPick then
        text, r, g, b = "No picks yet - click + on a tank", 1, 0.5, 0.3
    elseif unknown then
        text, r, g, b = "A pick isn't in your spellbook or bags", 0.95, 0.3, 0.3
    elseif notFriendly then
        text, r, g, b = "A pick can't target a friendly player", 1, 0.6, 0.2
    else
        text, r, g, b = "L-click cast  |  R-click edit", 0.5, 0.52, 0.6
    end
    win.status:SetText(text)
    win.status:SetTextColor(r, g, b)
end

refreshValues = function()
    if not win or not win:IsShown() then return end
    local cache = {}
    for i = 1, applied.count do updateRow(i, cache) end
    updateStatus()
    if TK.SyncConfigStrip then TK.SyncConfigStrip() end
end

-- Structural refresh: everything protected is deferred while in combat.
refresh = function()
    if not win then return end
    if InCombatLockdown() then
        TK.dirty = true
        refreshValues()
        return
    end
    TK.dirty = false
    applyStructure()
    refreshValues()
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function restorePosition()
    local c = TK.Cfg()
    local pos = c and c.pos
    win:ClearAllPoints()
    if pos then
        win:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", -320, 0)
    end
end

local function ensureWindow()
    if win then return win end
    win = CreateFrame("Frame", "AIPTankCastWindow", UIParent)
    win:SetSize(WIN_W, HDR_H + PAD + ROW_H + STATUS_H + PAD)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    win:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    win:SetBackdropColor(0.045, 0.05, 0.072, 0.96)
    win:SetBackdropBorderColor(0.34, 0.37, 0.46)
    local hdr = win:CreateTexture(nil, "BORDER")
    hdr:SetPoint("TOPLEFT", 5, -5); hdr:SetPoint("TOPRIGHT", -5, -5); hdr:SetHeight(HDR_H - 2)
    hdr:SetTexture(0.11, 0.12, 0.18, 0.95)
    local div = win:CreateTexture(nil, "ARTWORK")
    div:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, 0); div:SetPoint("TOPRIGHT", hdr, "BOTTOMRIGHT", 0, 0)
    div:SetHeight(1); div:SetTexture(1, 0.82, 0, 0.4)

    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end       -- implicitly protected: can't move in combat
        self.moving = true
        self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        local c = TK.Cfg()
        if c then c.pos = {point = point, relPoint = relPoint, x = x, y = y} end
    end)
    restorePosition()

    local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("|cFFFFD700Tanks|r")

    local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    close:SetSize(16, 16); close:SetPoint("TOPRIGHT", -6, -4); close:SetText("X")
    close:SetScript("OnClick", function() TK.HideWindow() end)
    close:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Close the tank window"); GameTooltip:Show()
    end)
    close:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local gear = UI.CreateIconButton(win, "Interface\\Icons\\INV_Misc_Gear_01", 14, function()
        local c = TK.Cfg()
        if c then c.showConfig = not c.showConfig end
        TK.LayoutWindow()
        if TK.SyncConfigStrip then TK.SyncConfigStrip() end
    end, "Import / Push the raid's Main Tank flags")
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)

    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.status:SetJustifyH("LEFT"); win.status:SetWidth(WIN_W - PAD * 2 - 4); win.status:SetHeight(STATUS_H)

    for i = 1, TK.MAX_TANKS do rows[i] = createRow(i) end

    win.addBtn = UI.CreateButton(win, "+ Add off-tank", ROW_W, ADD_H, function()
        local idx, err = TK.AddTank()
        if not idx then AIP.Print(err) end
    end, "Add another off-tank slot")
    win.addBtn:Hide()

    if TK.BuildConfigStrip then TK.BuildConfigStrip(win) end

    win:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.25 then return end
        self.acc = 0
        refreshValues()
    end)

    TK.OnChanged(refresh)
    TK.OnRoster(function() refreshValues() end)
    TK.RebuildUnits()
    win:Hide()
    refresh()
    return win
end

function TK.ShowWindow()
    if InCombatLockdown() then
        AIP.Print("The tank window can't be opened during combat - open it before the pull.")
        return
    end
    ensureWindow()
    local c = TK.Cfg()
    if c then c.shown = true end
    win:Show()
    refresh()
end

function TK.HideWindow()
    if InCombatLockdown() then
        AIP.Print("The tank window can't be closed during combat.")
        return
    end
    if win then win:Hide() end
    local c = TK.Cfg()
    if c then c.shown = false end
end

function TK.ToggleWindow()
    if win and win:IsShown() then TK.HideWindow() else TK.ShowWindow() end
end

function TK.IsWindowShown()
    return win ~= nil and win:IsShown()
end

-- Create the (protected) frames out of combat at login, restore visibility. If
-- the UI was reloaded mid-combat, creation waits for PLAYER_REGEN_ENABLED
-- because calls on freshly created secure frames are blocked during lockdown.
local pendingInit = false
local function initWindow()
    if InCombatLockdown() then pendingInit = true; return end
    pendingInit = false
    ensureWindow()
    local c = TK.Cfg()
    if c and c.shown then win:Show(); refresh() end
end

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "TankCastUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function()
        if pendingInit then initWindow() end
    end, "TankCastUI")
end
```

- [ ] **Step 2: Syntax check and headless tests**

Run the syntax check on `AutoInvitePlus/ui/TankCastWindow.lua` and `luajit tools/tests/tankcast_spec.lua`. Expected: `OK`, `0 failed`.

- [ ] **Step 3: Checkpoint**

(Live verification of Tasks 2-3 happens together in Task 4 because the window depends on the picker; do not sync yet.) **Do not commit.**

---

### Task 3: Picker with target context, type box, Import/Push strip

**Files:**
- Modify (full rewrite): `AutoInvitePlus/ui/TankCastConfig.lua`

**Interfaces:**
- Consumes: from Task 2 `TK.WIN_W`, `TK.PAD`, `TK.CFG_H`, `TK.EnsureMenuFrame()`; from Task 1 `TK.AddPick/SetPick/GetSlot/SlotLabel/GetPicks/ListSpells/ListItems/ParseSpellInput/FromCursor/ImportFromBlizzard/PushToBlizzard/CanPush`; `AIP.UI.CreateButton/CreateEditBox`.
- Produces: `TK.OpenPicker(slot, pickIndexOrNil)` (nil = add), `TK.TogglePicker()` is **removed**, `TK.BuildConfigStrip(win)` (creates `win.cfg`, hidden, height `TK.CFG_H`, anchored to the window bottom, holding Import + Push), `TK.SyncConfigStrip()`.

- [ ] **Step 1: Write the new config/picker file**

Replace the entire contents of `AutoInvitePlus/ui/TankCastConfig.lua` with:

```lua
-- AutoInvite Plus - Tank Cast window: picker popup + Import/Push strip
-- The picker fills ONE pick of ONE tank (target context set by TK.OpenPicker):
--   * Spells tab: YOUR spellbook spells that can target a friendly player
--   * Items tab : bag items detected as castable on a friendly player
--   * type a name (or shift-click a spellbook link) into the box and press Enter
-- Dragging a spell/item onto a pick icon or [+] in the window also works (see
-- TankCastWindow.lua). The gear strip under the tank rows holds Import / Push.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local strip                                   -- Import/Push strip widgets

StaticPopupDialogs["AIP_TANKCAST_PUSH"] = {
    text = "Add Main Tank / Main Assist flags for the players in your Tanks list?\n\nThis is visible to the whole raid. Flags already on other players are not removed.",
    button1 = YES,
    button2 = NO,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnAccept = function()
        local _, msg = TK.PushToBlizzard()
        AIP.Print(msg)
    end,
}

-- ============================================================================
-- PICKER POPUP
-- ============================================================================

local COLS, MAXROWS, CELL = 8, 8, 26
local PICK_W = COLS * CELL + 16
local HDR, TAB_H, NOTE_H, EDIT_H = 22, 26, 34, 26
local picker
local pickerTab = "spells"
local target = { slot = nil, idx = nil }       -- which tank / pick the picker is filling

local function pickerTitle()
    local slot = target.slot
    if not slot then return "|cFFFFD700Choose a pick|r" end
    local nm = TK.GetSlot(slot)
    local who = TK.SlotLabel(slot) .. ((nm ~= "") and (" " .. nm) or "")
    return "|cFFFFD700" .. (target.idx and "Change pick" or "Add pick") .. " - " .. who .. "|r"
end

local function acceptChoice(name)
    if not name or name == "" or not target.slot then return end
    local ok, err
    if target.idx then ok, err = TK.SetPick(target.slot, target.idx, name) else ok, err = TK.AddPick(target.slot, name) end
    if not ok then AIP.Print(err) return end
    picker:Hide()
end

local function makeCell(i)
    local cell = CreateFrame("Button", nil, picker)
    cell:SetSize(CELL - 2, CELL - 2)
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    cell:SetPoint("TOPLEFT", picker, "TOPLEFT", 8 + col * CELL, -(HDR + TAB_H + row * CELL))
    cell.tex = cell:CreateTexture(nil, "ARTWORK")
    cell.tex:SetAllPoints(); cell.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local hl = cell:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square"); hl:SetBlendMode("ADD")
    cell:SetScript("OnClick", function(self) acceptChoice(self.entry and self.entry.name) end)
    cell:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if e.link then
            GameTooltip:SetHyperlink(e.link)
            -- What we identified: kind + how we knew it can target a friendly.
            local how = ({ api = "flagged helpful with a range", text = "its Use text names a friendly target",
                           kind = "this kind of item targets friendlies" })[e.why]
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Cast on friendly: " .. (e.kind or "Item") .. (how and (" (" .. how .. ")") or ""), 0.4, 1, 0.4, true)
        elseif e.index then
            GameTooltip:SetSpell(e.index, e.book)
        else
            GameTooltip:AddLine(e.name)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    picker.cells[i] = cell
    return cell
end

local function populatePicker()
    if not picker then return end
    picker.title:SetText(pickerTitle())
    local spells, sFiltered = TK.ListSpells()
    local items, iFiltered = TK.ListItems()
    picker.tabSpells:SetText("Spells (" .. #spells .. ")")
    picker.tabItems:SetText("Items (" .. #items .. ")")
    if pickerTab == "spells" then picker.tabSpells:Disable(); picker.tabItems:Enable()
    else picker.tabItems:Disable(); picker.tabSpells:Enable() end

    local list, filtered = spells, sFiltered
    if pickerTab == "items" then list, filtered = items, iFiltered end
    local n = math.min(#list, COLS * MAXROWS)
    for i = 1, n do
        local cell = picker.cells[i] or makeCell(i)
        cell.entry = list[i]
        cell.tex:SetTexture(list[i].icon or QUESTION)
        cell:Show()
    end
    for i = n + 1, #picker.cells do picker.cells[i].entry = nil; picker.cells[i]:Hide() end

    local rows = math.max(1, math.ceil(n / COLS))
    picker:SetHeight(HDR + TAB_H + rows * CELL + NOTE_H + EDIT_H + 8)
    local what = (pickerTab == "spells") and "spells" or "items"
    local note
    if #list == 0 then
        note = "Nothing here can target a friendly player. Type a name below, or drag one onto a pick."
    elseif not filtered then
        note = "Detection API missing on this client - showing " .. what .. " that might qualify."
    elseif #list > n then
        note = "Showing the first " .. n .. ". Type a name below for the rest."
    elseif pickerTab == "items" then
        note = "Bag items detected as castable on a friendly player (grouped by kind). Hover for details."
    else
        note = "Your spells that can be cast on a friendly player. Not listed? Type it below."
    end
    picker.note:SetText(note)
end

local function ensurePicker()
    if picker then return picker end
    picker = CreateFrame("Frame", "AIPTankCastPicker", UIParent)
    picker:SetSize(PICK_W, 120)
    picker:SetFrameStrata("DIALOG")
    picker:SetClampedToScreen(true)
    picker:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    picker:SetBackdropColor(0.045, 0.05, 0.072, 0.97)
    picker:SetBackdropBorderColor(0.34, 0.37, 0.46)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    picker:SetMovable(true); picker:EnableMouse(true); picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    picker.cells = {}

    picker.title = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    picker.title:SetPoint("TOPLEFT", 8, -6)
    local close = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    close:SetSize(16, 16); close:SetPoint("TOPRIGHT", -6, -4); close:SetText("X")
    close:SetScript("OnClick", function() picker:Hide() end)

    local function tab(text, key, anchorX)
        local b = UI.CreateButton(picker, text, 92, 20, function()
            pickerTab = key
            populatePicker()
        end)
        b:SetPoint("TOPLEFT", picker, "TOPLEFT", anchorX, -HDR)
        return b
    end
    picker.tabSpells = tab("Spells", "spells", 8)
    picker.tabItems = tab("Items", "items", 104)

    -- Type a spell/item name (or shift-click a spellbook link) and press Enter.
    picker.edit = UI.CreateEditBox(picker, PICK_W - 16, 22, false, 120)
    picker.edit:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 8, 6)
    picker.edit:SetScript("OnEnterPressed", function(self)
        local clean = TK.ParseSpellInput(self:GetText())
        self:ClearFocus()
        if clean ~= "" then self:SetText(""); acceptChoice(clean) end
    end)
    picker.edit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    picker.edit:SetScript("OnReceiveDrag", function()
        local name = TK.FromCursor()
        if name then ClearCursor(); acceptChoice(name) end
    end)
    picker.edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Type a spell or item name, then Enter", 1, 0.82, 0)
        GameTooltip:AddLine("You can also shift-click a spellbook spell here, or drag a spell/item onto it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    picker.edit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    picker.note = picker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    picker.note:SetPoint("BOTTOMLEFT", picker.edit, "TOPLEFT", 0, 4)
    picker.note:SetWidth(PICK_W - 16); picker.note:SetHeight(NOTE_H - 4)
    picker.note:SetJustifyH("LEFT"); picker.note:SetJustifyV("TOP")
    picker.note:SetTextColor(0.6, 0.62, 0.7)

    picker:SetScript("OnShow", populatePicker)
    picker:Hide()
    tinsert(UISpecialFrames, "AIPTankCastPicker")       -- Esc closes it
    return picker
end

-- Open the picker to fill one pick: pickIndex = the pick to replace, nil = add a new one.
function TK.OpenPicker(slot, pickIndex)
    ensurePicker()
    target.slot, target.idx = slot, pickIndex
    picker:Show()
    populatePicker()                               -- OnShow only fires on a hidden -> shown change
end

-- ============================================================================
-- IMPORT / PUSH STRIP (under the tank rows, toggled by the gear icon)
-- ============================================================================

function TK.BuildConfigStrip(win)
    if strip then return end
    local w = TK.WIN_W - TK.PAD * 2
    local cfg = CreateFrame("Frame", nil, win)
    cfg:SetHeight(TK.CFG_H)
    cfg:SetPoint("BOTTOMLEFT", win, "BOTTOMLEFT", TK.PAD, TK.PAD)
    cfg:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -TK.PAD, TK.PAD)
    cfg:Hide()
    win.cfg = cfg

    local sep = cfg:CreateTexture(nil, "ARTWORK")
    sep:SetPoint("TOPLEFT", 0, 2); sep:SetPoint("TOPRIGHT", 0, 2); sep:SetHeight(1)
    sep:SetTexture(1, 0.82, 0, 0.25)

    local half = math.floor((w - 4) / 2)
    local importBtn = UI.CreateButton(cfg, "Import", half, 20, function()
        local _, msg = TK.ImportFromBlizzard()
        AIP.Print(msg)
    end, "Copy the raid's Main Tank / Main Assist flags into this list (Main Assists become off-tanks; your picks are kept)")
    importBtn:SetPoint("BOTTOMLEFT", 0, 2)

    local pushBtn = UI.CreateButton(cfg, "Push", half, 20, function()
        StaticPopup_Show("AIP_TANKCAST_PUSH")
    end, "Add Main Tank / Main Assist flags for this list (raid leader or assistant only; existing flags are not removed)")
    pushBtn:SetPoint("BOTTOMRIGHT", 0, 2)

    strip = { frame = cfg, pushBtn = pushBtn }
end

-- Cheap; safe to call every refresh tick.
function TK.SyncConfigStrip()
    if not strip or not strip.frame:IsShown() then return end
    if TK.CanPush() then strip.pushBtn:Enable() else strip.pushBtn:Disable() end
end
```

- [ ] **Step 2: Syntax check**

Run the syntax check on `AutoInvitePlus/ui/TankCastConfig.lua`, `AutoInvitePlus/ui/TankCastWindow.lua`, `AutoInvitePlus/modules/TankCast.lua`; run `luajit tools/tests/tankcast_spec.lua`. Expected: all `OK`, `0 failed`.

- [ ] **Step 3: Checkpoint**

**Do not commit.** (Live verification is Task 4.)

---

### Task 4: Docs, deploy, live verification, final review

**Files:**
- Modify: `AutoInvitePlus/CLAUDE.md` (the `TankCast` bullet)
- Modify: `docs/superpowers/specs/2026-09-27-tank-cast-window-design.md` (one-line pointer to Revision 2)

- [ ] **Step 1: Update the module documentation**

In `AutoInvitePlus/CLAUDE.md`, in the `TankCast` bullet: replace "a 1 MT + 3 OT list (`AIP.db.tankCast`, AIP-local ..." with "a list of up to 8 tanks (`AIP.db.tankCast.tanks`, each `{name, picks}`: slot 1 = MT, the rest off-tanks added with `+ Add off-tank`; up to 4 picks per tank; **picks belong to the slot, not the player**; AIP-local ...", replace "plus one configurable spell/item cast on a tank with a click" with "each pick is a spell/item cast on that tank with one click", and replace "`ui/TankCastConfig.lua` (spell box, the \"Pick\" popup, drag-and-drop, Import/Push)" with "`ui/TankCastConfig.lua` (the Pick popup - it fills one pick of one tank via `TK.OpenPicker(slot, pickIndex)` - plus a type-a-name box and the Import/Push strip; spells/items can also be dragged onto a pick icon or `[+]`)". Add: "Legacy `{mt, ots, spell}` data is migrated by `TK.Cfg()`; `tanks` must never be a `Core.lua` default."

At the top of `docs/superpowers/specs/2026-09-27-tank-cast-window-design.md` add the line: `> Sections 1 and 3 and the single-spell / 1+3 tank decisions are superseded by 2026-09-27-tank-cast-multi-tank-picks-design.md.`

- [ ] **Step 2: Syntax check and headless tests**

Run the syntax check on every touched Lua file (`TankCast.lua`, `TankCastWindow.lua`, `TankCastConfig.lua`, `CentralGUI.lua`, `Core.lua`, `tools/tests/tankcast_spec.lua`) and `luajit tools/tests/tankcast_spec.lua`. Expected: all `OK`, `0 failed`.

- [ ] **Step 3: Deploy and confirm the client has the module**

Run the live loop (`Sync-Addon`, `/reload`). Then `Run-WowLua 'UIErrorsFrame:AddMessage("TK="..tostring(AutoInvitePlus.TankCast~=nil).." win="..tostring(AIPTankCastWindow~=nil),1,1,0)'` and screenshot. Expected: `TK=true win=true`. If `TK=false`, the client has not been restarted since the TankCast files were added to the `.toc`: **stop and ask the user to quit WoW to the desktop and relaunch**, then continue.

- [ ] **Step 4: Live checks (solo; note each result)**

With `/console scriptErrors 1`:
1. `/run UIErrorsFrame:AddMessage(tostring(AIPTankCastWindow:IsProtected()),1,1,0)` - record the two values (expect `true` if the window is implicitly protected; confirms the combat guards are warranted).
2. `/aip tanks` -> a 210px window with one **MT** row ("+ Set MT"), a `[+]` under it, a **+ Add off-tank** button, and the status "No picks yet - click + on a tank". Screenshot.
3. Click the MT name -> menu; choose your own name. Click `[+]` -> the picker opens titled "Add pick - MT <you>"; pick a self-castable spell (you are solo: any friendly buff) -> an icon appears, `[+]` moves right. Left-click the icon -> the spell is cast on you (check the buff via `/run UIErrorsFrame:AddMessage(tostring((UnitBuff("player",1))),1,1,0)`), the cooldown sweep shows.
4. Add three more picks (4 total) -> `[+]` disappears; trying `/aip tanks pick mt Innervate` prints the cap message. Right-click an icon -> *Change pick...* opens the picker titled "Change pick - ...", choosing replaces it; *Remove pick* removes it.
5. Click **+ Add off-tank** repeatedly -> rows OT1..OT7 appear, then the button hides at 8; screenshot at 8 rows (window fits on screen). Name menu on OT rows has *Remove tank*; MT does not.
6. Drag a spell from the spellbook onto an icon (replace) and onto `[+]` (add); drag a bag item likewise. Type a name in the picker box + Enter.
7. Gear icon -> Import/Push strip appears (Push disabled solo); Import prints "You are not in a raid."
8. `/aip tanks list`, `/aip tanks spell <spell>`, `/aip tanks reset` behave as described in the spec.
9. Migration: `/run AutoInvitePlusDB.tankCast={mt="Xx",ots={"Yy","","Zz"},spell="Innervate"}` then `/reload` -> window shows MT Xx, OT1 Yy, OT2 Zz each with an Innervate pick (icons red/question if not in your spellbook).
10. Combat (needs a target dummy or mob): with a tank + pick set, enter combat and click **+ Add off-tank**, add a pick via drag, and try `/aip tanks` toggle -> no `ADDON_ACTION_BLOCKED`, status shows "Changes apply after combat", the window keeps showing/casting the OLD list, and everything applies when combat ends. If no combat target is available, state that this was not live-verified.
11. Title bar (Full and Simplified) still shows the **Tanks** button; no overlap at minimum width.

Fix any defect found (systematic-debugging), re-running Steps 2-4.

- [ ] **Step 5: Final whole-branch review**

Dispatch a fresh reviewer on the most capable model (`Agent`, `model: "fable"`) with: the spec (`...multi-tank-picks-design.md`) and this plan, the file list (`TankCast.lua`, `TankCastWindow.lua`, `TankCastConfig.lua`, the test file, the `Core.lua`/`CentralGUI.lua` diffs), this plan's **Review Focus** section verbatim, and the instruction to be read-only and rank findings Critical/Important/Minor with a concrete failure scenario, checking especially: combat lockdown correctness of every new frame/button, snapshot-vs-live index consistency after `RemoveTank`, the migration + defaults-merge interaction, drag-and-drop paths, and 3.3.5a API validity. Re-grade its findings by effect; fix Critical/Important with a test where headless-testable (or a live check otherwise); ledger Minors as deferred in the final message.

- [ ] **Step 6: Final report**

Summarise: files changed, what was live-verified vs not (in particular: raid Import/Push and cross-player `[target=Name]` casting if no group was available, and combat behaviour if no combat target), the rulings made, the deferred minors, and that nothing is committed (offer to commit).
