# Tank Cast Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Tanks" title-bar button that opens a floating window where the player sets 1 main tank + 3 off-tanks and casts one configurable spell/item on any of them with a click.

**Architecture:** A headless logic module (`modules/TankCast.lua`, `AIP.TankCast`) owns the tank list, sanitising, macro text, unit lookup, Blizzard import/push and `/aip tanks`. Two UI files build on it: `ui/TankCastWindow.lua` (window + one `SecureActionButtonTemplate` row per tank) and `ui/TankCastConfig.lua` (spell box, presets, Import/Push strip). Casting is a secure macro `/cast [target=<Name>] <spell>`; everything protected is only touched out of combat.

**Tech Stack:** Lua 5.1, WoW 3.3.5a API (`SecureActionButtonTemplate`, `EasyMenu`, `CooldownFrameTemplate`, `SetPartyAssignment`), LuaJIT for headless tests, `luaparse` for syntax checks.

**Spec:** `docs/superpowers/specs/2026-09-27-tank-cast-window-design.md`

## Global Constraints

- Lua 5.1 only; ASCII only inside Lua string literals (WoW default fonts lack many glyphs).
- Load order is the `.toc`: new files must be listed (`modules\TankCast.lua` after `modules\Rotation.lua`; `ui\TankCastWindow.lua` then `ui\TankCastConfig.lua` after `ui\CompositionUI.lua`).
- Slots: **1 MT + 3 OT** (`TK.SLOTS = 4`; slot 1 = MT, slots 2-4 = OT1-3). Names normalised with `AIP.Utils.NormalizeName`, compared with `:lower()`.
- Casting macro uses `target=` (not `@`): `/cast [target=<Name>] <Spell>`; spell/name sanitised (newlines, `/ ; [ ] |` stripped; names letters-only); total macro length capped below 255 (`TK.MACRO_MAX = 250`).
- Secure rows: attributes, `Show`/`Hide`, `SetPoint` **only when `not InCombatLockdown()`**; combat edits set `TK.dirty = true` and flush on `PLAYER_REGEN_ENABLED`. The window container is a plain `Frame`, so Show/Hide/move work in combat.
- **No chat output** from this module (no `SendChatMessage`, no `RT.Send`); user feedback only via `AIP.Print`.
- New saved key `AIP.db.tankCast` goes in the `defaults` table in `core/Core.lua`; **do not bump `DB_VERSION`**.
- Cross-module calls stay guarded (`if AIP.TankCast and AIP.TankCast.ToggleWindow then ...`).
- **Do not `git commit` unless the user asks** (standing repo rule; work stays uncommitted). Each task ends with a "Checkpoint" of tests + syntax check instead of a commit.
- Syntax-check command (run from repo root; `luaparse` is already installed at `C:/Users/iuras/AppData/Local/Temp/aip-luacheck`; ignore the known `break;` false positive):
  ```bash
  node -e "
    const luaparse = require('C:/Users/iuras/AppData/Local/Temp/aip-luacheck/node_modules/luaparse');
    const fs = require('fs'); let bad = false;
    for (const f of process.argv.slice(1)) {
      try { luaparse.parse(fs.readFileSync(f, 'utf8'), {luaVersion: '5.1', comments: false}); console.log('OK   ' + f); }
      catch (e) { bad = true; console.log('FAIL ' + f + ' -> ' + e.message); }
    }
    process.exit(bad ? 1 : 0);
  " -- <FILES>
  ```
- Headless test command (repo root): `luajit tools/tests/tankcast_spec.lua`
- Live-test loop (repo root, PowerShell): `. tools\wow-test-harness\harness.ps1; Sync-Addon; Send-WowChat "/reload"; Start-Sleep 6`

## Deviations from the spec (intentional, small)

1. The window lives in its own file `ui/TankCastWindow.lua` (+ `ui/TankCastConfig.lua`) instead of inside `modules/TankCast.lua`, so the logic is headless-testable and each file stays focused.
2. Row health / range / cooldown refresh with a 0.25 s `OnUpdate` throttle **only while the window is shown**, instead of `UNIT_HEALTH` / `SPELL_UPDATE_COOLDOWN` subscriptions (unit tokens change on roster shuffles; 4 rows is trivial work). Roster/combat changes still use `AIP.Utils.Events`.
3. An empty slot is a muted "+ Set MT" row (WoW 3.3.5 has no dashed-border texture).
4. **Push** shows a Yes/No confirmation popup first (it changes raid-visible flags).
5. The assign menu is flat (tank-capable classes first, then the rest, capped at 40 entries); nested `EasyMenu` submenus are unreliable on 3.3.5a.

## Review Focus

Failure modes the spec implies that a player is most likely to hit, most likely first (each is pinned by a test in the owning task):

1. **Same player in two slots** (e.g. assigning the MT as OT1): must move, never duplicate (Task 1 test).
2. **Hostile/odd text in the spell box or a name** (`;`, `/run`, brackets, newline, pasted spell link): must never reach `macrotext` verbatim (Task 1 tests).
3. **Solo / not in a group**: candidates are just the player, window opens without errors, self-cast works (Task 1 test + Task 4 live test).
4. **Editing during combat**: display must keep showing what the buttons actually do until the flush (Task 2 manual test).
5. **Import/Push in the wrong context** (not in a raid, no flags set, not leader/assist): clear message, no state change / no API call (Task 1 tests).

---

### Task 1: TankCast logic module, defaults, slash command, headless tests

**Files:**
- Create: `AutoInvitePlus/modules/TankCast.lua`
- Create: `tools/tests/tankcast_spec.lua`
- Modify: `AutoInvitePlus/core/Core.lua` (defaults near line 195; slash branch near line 1487; help near line 1856)
- Modify: `AutoInvitePlus/AutoInvitePlus.toc` (after `modules\Rotation.lua`)

**Interfaces:**
- Consumes: `AIP.Utils.NormalizeName(name) -> string|nil`, `AIP.Print(msg)`, optional `AIP.Utils.Events.Register(event, handler, owner)`.
- Produces (all on `AIP.TankCast` = `TK`):
  - constants `TK.SLOTS` (4), `TK.MACRO_MAX` (250), `TK.TANK_CLASSES`, `TK.PRESET_SPELLS`
  - `TK.Cfg() -> table|nil` (the `AIP.db.tankCast` table, shape-repaired)
  - `TK.SlotLabel(i) -> "MT"|"OT1"|"OT2"|"OT3"`, `TK.GetSlot(i) -> string` ("" = empty), `TK.SetSlot(i, name) -> ok, err`, `TK.FindSlot(name) -> i|nil`, `TK.SetFirstOT(name) -> ok, err`, `TK.ClearAll()`
  - `TK.GetSpell() -> string`, `TK.SetSpell(text) -> cleanString`
  - `TK.Sanitize(text)`, `TK.SanitizeName(text)`, `TK.ParseSpellInput(text)`, `TK.BuildMacro(name, spell) -> string|nil`
  - `TK.RebuildUnits()`, `TK.UnitFor(name) -> unitToken|nil`, `TK.GetCandidates() -> {{name,class,tank}...}`, `TK.TargetName() -> string|nil`
  - `TK.ResolveSpell(text) -> kind("spell"|"item"|nil), icon, displayName`, `TK.GetCooldown(spell, kind) -> start, duration, enable`, `TK.KnownPresets() -> {names}`
  - `TK.InRange(name, unit, spell)`, `TK.Status(name, spell) -> "ok"|"away"|"offline"|"dead"|"range"`
  - `TK.ImportFromBlizzard() -> ok, msg`, `TK.CanPush() -> bool`, `TK.PushToBlizzard() -> ok, msg`
  - `TK.OnChanged(fn)`, `TK.OnRoster(fn)`, `TK.Changed()`, `TK.RosterChanged()`, `TK.dirty` (bool)
  - `TK.SlashHandler(rest)`; the window (Task 2) provides `TK.ToggleWindow` which the handler calls if present.

- [ ] **Step 1: Write the failing test file**

Create `tools/tests/tankcast_spec.lua`:

```lua
-- Headless tests for AutoInvitePlus/modules/TankCast.lua (pure logic; no WoW client).
-- Run from the repo root:  luajit tools/tests/tankcast_spec.lua

local printed = {}
AutoInvitePlus = {
    db = { tankCast = { mt = "", ots = { "", "", "" }, spell = "" } },
    Print = function(msg) printed[#printed + 1] = msg end,
    Utils = {
        NormalizeName = function(name)
            if not name or name == "" then return nil end
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then return nil end
            return name:sub(1, 1):upper() .. name:sub(2):lower()
        end,
    },
}
local AIP = AutoInvitePlus

-- ---- WoW API stubs ---------------------------------------------------------
local roster, party = {}, {}
local targetName, isLeader, isOfficer = nil, false, false
local assigned, assignCalls = {}, {}

local function entryFor(unit)
    if unit == "player" then return { name = "Me", class = "PRIEST" } end
    local kind, idx = unit:match("^(%a+)(%d+)$")
    idx = tonumber(idx)
    if kind == "raid" then return roster[idx] end
    if kind == "party" then return party[idx] end
end
GetNumRaidMembers = function() return #roster end
GetNumPartyMembers = function() return #party end
UnitName = function(unit)
    if unit == "target" then return targetName end
    local e = entryFor(unit); return e and e.name
end
UnitClass = function(unit)
    local e = entryFor(unit); if e then return e.class, e.class end
end
UnitExists = function(unit) if unit == "target" then return targetName ~= nil end return entryFor(unit) ~= nil end
UnitIsPlayer = function() return true end
GetRaidRosterInfo = function(i)
    local r = roster[i]; if not r then return nil end
    return r.name, 0, 1, 80, r.class, r.class, "Zone", true, false, r.role
end
IsRaidLeader = function() return isLeader and 1 or nil end
IsRaidOfficer = function() return isOfficer and 1 or nil end
GetPartyAssignment = function(a, u) return assigned[a .. ":" .. u] and 1 or nil end
SetPartyAssignment = function(a, u) assigned[a .. ":" .. u] = true; assignCalls[#assignCalls + 1] = a .. ":" .. u end
GetSpellInfo = function(n) if n == "Misdirection" then return "Misdirection", "", "icon1" end end
GetItemInfo = function(n)
    if n == "Hearthstone" then return "Hearthstone", "|cffffffff|Hitem:6948:0|h[Hearthstone]|h|r", 1, 1, 1, "", "", 1, "", "icon2" end
end
GetSpellCooldown = function() return 10, 30, 1 end
GetItemCooldown = function(id) if id == 6948 then return 5, 60, 1 end return 0, 0, 0 end

dofile("AutoInvitePlus/modules/TankCast.lua")
local TK = AIP.TankCast

-- ---- tiny test framework ---------------------------------------------------
local pass, fail = 0, 0
local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else fail = fail + 1; print("FAIL " .. label .. ": expected [" .. tostring(expected) .. "], got [" .. tostring(actual) .. "]") end
end
local function reset()
    local c = AIP.db.tankCast
    c.mt, c.ots, c.spell = "", { "", "", "" }, ""
    roster, party, targetName = {}, {}, nil
    isLeader, isOfficer = false, false
    assigned, assignCalls, printed = {}, {}, {}
    TK.units = nil
end

-- ---- sanitising / macro ----------------------------------------------------
eq(TK.Sanitize("Hand of Sacrifice; /run x [a]\n"), "Hand of Sacrifice run x a", "Sanitize strips macro chars")
eq(TK.Sanitize("  Power   Word: Shield  "), "Power Word: Shield", "Sanitize collapses spaces, keeps colon")
eq(TK.Sanitize(nil), "", "Sanitize nil")
eq(TK.SanitizeName("Bob; /run"), "Bobrun", "SanitizeName letters only")
eq(TK.ParseSpellInput("|cff71d5ff|Hspell:34477|h[Misdirection]|h|r"), "Misdirection", "ParseSpellInput spell link")
eq(TK.ParseSpellInput("|cff1eff00|Hitem:6948:0|h[Hearthstone]|h|r"), "Hearthstone", "ParseSpellInput item link")
eq(TK.ParseSpellInput("Innervate"), "Innervate", "ParseSpellInput plain")
eq(TK.BuildMacro("Bob", "Misdirection"), "/cast [target=Bob] Misdirection", "BuildMacro basic")
eq(TK.BuildMacro("Bob", "Misdirection; /run x"), "/cast [target=Bob] Misdirection run x", "BuildMacro neutralises injection")
eq(TK.BuildMacro("", "Misdirection"), nil, "BuildMacro no name")
eq(TK.BuildMacro("Bob", ""), nil, "BuildMacro no spell")
eq(TK.BuildMacro("Bob", string.rep("a", 300)), nil, "BuildMacro too long")

-- ---- slots -----------------------------------------------------------------
reset()
eq(TK.SlotLabel(1), "MT", "label MT"); eq(TK.SlotLabel(2), "OT1", "label OT1"); eq(TK.SlotLabel(4), "OT3", "label OT3")
local ok = TK.SetSlot(2, "bob")
eq(ok, true, "SetSlot ok"); eq(TK.GetSlot(2), "Bob", "SetSlot normalises")
TK.SetSlot(1, "BOB")
eq(TK.GetSlot(1), "Bob", "dedupe: MT gets Bob"); eq(TK.GetSlot(2), "", "dedupe: OT1 cleared")
eq(TK.FindSlot("bOb"), 1, "FindSlot case-insensitive"); eq(TK.FindSlot("Nobody"), nil, "FindSlot miss")
local ok2, err2 = TK.SetSlot(1, "/;[]")
eq(ok2, false, "SetSlot rejects junk name"); eq(TK.GetSlot(1), "Bob", "junk leaves slot unchanged")
eq((TK.SetSlot(5, "Bob")), false, "SetSlot rejects slot 5"); eq((TK.SetSlot(0, "Bob")), false, "SetSlot rejects slot 0")
TK.SetSlot(1, ""); eq(TK.GetSlot(1), "", "SetSlot '' clears")

reset()
eq((TK.SetFirstOT("A")), true, "OT fill 1"); eq(TK.GetSlot(2), "A", "OT1=A")
TK.SetFirstOT("B"); TK.SetFirstOT("C")
eq(TK.GetSlot(4), "C", "OT3=C")
eq((TK.SetFirstOT("D")), false, "OT full rejects")
eq((TK.SetFirstOT("a")), true, "OT already present is ok"); eq(TK.GetSlot(3), "B", "no duplicate created")
TK.ClearAll(); eq(TK.GetSlot(2), "", "ClearAll")

do -- listeners
    reset(); local n = 0
    TK.OnChanged(function() n = n + 1 end)
    TK.SetSlot(1, "Bob"); eq(n, 1, "Changed fires on SetSlot")
    TK.SetSlot(1, "/"); eq(n, 1, "Changed not fired on rejected SetSlot")
    TK.SetSpell("Innervate"); eq(n, 2, "Changed fires on SetSpell")
    eq(TK.GetSpell(), "Innervate", "GetSpell")
end
do -- db missing
    local saved = AIP.db; AIP.db = nil
    eq((TK.SetSlot(1, "Bob")), false, "SetSlot without db"); eq(TK.GetSlot(1), "", "GetSlot without db"); eq(TK.GetSpell(), "", "GetSpell without db")
    AIP.db = saved
end

-- ---- units / candidates ----------------------------------------------------
reset()
local solo = TK.GetCandidates()
eq(#solo, 1, "solo: one candidate"); eq(solo[1].name, "Me", "solo: the player"); eq(TK.UnitFor("me"), "player", "solo UnitFor")
reset()
roster = { { name = "Zed", class = "MAGE" }, { name = "Bram", class = "WARRIOR" }, { name = "Ann", class = "DRUID" }, { name = "Cy", class = "PRIEST" } }
local c = TK.GetCandidates()
eq(c[1].name .. c[2].name .. c[3].name .. c[4].name, "AnnBramCyZed", "candidates: tank classes first, then alpha")
eq(c[1].tank, true, "Ann tank-capable"); eq(c[3].tank, false, "Cy not tank-capable")
eq(TK.UnitFor("bram"), "raid2", "UnitFor case-insensitive"); eq(TK.UnitFor("nobody"), nil, "UnitFor miss")

-- ---- spell resolution / cooldown / presets ---------------------------------
local kind, icon, dn = TK.ResolveSpell("Misdirection")
eq(kind, "spell", "Resolve spell kind"); eq(icon, "icon1", "Resolve spell icon"); eq(dn, "Misdirection", "Resolve spell name")
kind, icon = TK.ResolveSpell("Hearthstone"); eq(kind, "item", "Resolve item kind"); eq(icon, "icon2", "Resolve item icon")
eq(TK.ResolveSpell("Nope"), nil, "Resolve unknown"); eq(TK.ResolveSpell(""), nil, "Resolve empty")
local s, d = TK.GetCooldown("Misdirection", "spell"); eq(s .. "/" .. d, "10/30", "cooldown spell")
s, d = TK.GetCooldown("Hearthstone", "item"); eq(s .. "/" .. d, "5/60", "cooldown item")
s, d = TK.GetCooldown("", nil); eq(s .. "/" .. d, "0/0", "cooldown empty")
local presets = TK.KnownPresets(); eq(#presets, 1, "KnownPresets count"); eq(presets[1], "Misdirection", "KnownPresets only known")

-- ---- Blizzard import / push ------------------------------------------------
reset(); eq((TK.ImportFromBlizzard()), false, "Import solo fails")
reset()
roster = { { name = "Tanky", class = "WARRIOR", role = "MAINTANK" }, { name = "Heal", class = "PRIEST" },
           { name = "Offy", class = "PALADIN", role = "MAINASSIST" }, { name = "Alty", class = "DRUID", role = "MAINASSIST" } }
TK.SetSlot(4, "Old")
local iok = TK.ImportFromBlizzard()
eq(iok, true, "Import ok"); eq(TK.GetSlot(1), "Tanky", "Import MT"); eq(TK.GetSlot(2), "Offy", "Import MA1")
eq(TK.GetSlot(3), "Alty", "Import MA2"); eq(TK.GetSlot(4), "", "Import clears leftover slot")
reset()
roster = { { name = "Heal", class = "PRIEST" } }; TK.SetSlot(1, "Keep")
local nok, nmsg = TK.ImportFromBlizzard()
eq(nok, false, "Import with no flags fails"); eq(TK.GetSlot(1), "Keep", "Import with no flags changes nothing")

reset()
roster = { { name = "Tanky", class = "WARRIOR" }, { name = "Offy", class = "PALADIN" } }
TK.SetSlot(1, "Tanky"); TK.SetSlot(2, "Offy")
eq(TK.CanPush(), false, "CanPush false for plain member")
eq((TK.PushToBlizzard()), false, "Push refused for plain member"); eq(#assignCalls, 0, "Push made no API calls")
isOfficer = true
eq(TK.CanPush(), true, "CanPush true for assist")
eq((TK.PushToBlizzard()), true, "Push ok"); eq(assignCalls[1], "MAINTANK:raid1", "Push MT"); eq(assignCalls[2], "MAINASSIST:raid2", "Push OT1")
TK.PushToBlizzard(); eq(#assignCalls, 2, "Push skips flags already set")
reset(); isLeader = true; eq(TK.CanPush(), false, "CanPush false when not in a raid")

-- ---- slash handler ---------------------------------------------------------
reset(); targetName = "Bram"
TK.SlashHandler("mt"); eq(TK.GetSlot(1), "Bram", "slash mt uses target")
TK.SlashHandler("ot cy"); eq(TK.GetSlot(2), "Cy", "slash ot fills first OT")
TK.SlashHandler("spell Hand of Sacrifice"); eq(TK.GetSpell(), "Hand of Sacrifice", "slash spell")
TK.SlashHandler("mt Zed"); eq(TK.GetSlot(1), "Zed", "slash mt <name>")
TK.SlashHandler("clear"); eq(TK.GetSlot(1) .. TK.GetSlot(2), "", "slash clear")
printed = {}; TK.SlashHandler("bogus"); eq(#printed > 0, true, "slash unknown prints usage")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `luajit tools/tests/tankcast_spec.lua`
Expected: FAIL — `cannot open AutoInvitePlus/modules/TankCast.lua`.

- [ ] **Step 3: Write the logic module**

Create `AutoInvitePlus/modules/TankCast.lua`:

```lua
-- AutoInvite Plus - Tank Cast (logic layer)
-- A 1 MT + 3 OT list plus one configurable spell/item to cast on them. Kept
-- headless so the window (ui/TankCastWindow.lua) is pure presentation and this
-- file can be unit-tested outside the client (tools/tests/tankcast_spec.lua).
--
-- Casting itself happens in the window's secure buttons with the macro
-- "/cast [target=<Name>] <spell>" (see TK.BuildMacro) - addons cannot cast on
-- a named unit any other way on 3.3.5a. This module never writes to chat.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast

TK.SLOTS = 4            -- slot 1 = Main Tank, slots 2-4 = Off-Tank 1-3
TK.MACRO_MAX = 250      -- macro text limit is 255; keep headroom
TK.dirty = false        -- window has a structural change waiting for combat to end
TK.units = nil          -- lower-case name -> unit token, rebuilt on roster events

TK.TANK_CLASSES = { WARRIOR = true, PALADIN = true, DEATHKNIGHT = true, DRUID = true }

-- Offered in the window's preset menu (only those the player actually knows).
TK.PRESET_SPELLS = {
    "Misdirection", "Tricks of the Trade", "Hand of Sacrifice", "Innervate",
    "Earth Shield", "Pain Suppression", "Guardian Spirit", "Power Word: Shield",
}

local changedListeners, rosterListeners = {}, {}

local function fire(list)
    for _, fn in ipairs(list) do pcall(fn) end
end
function TK.OnChanged(fn) changedListeners[#changedListeners + 1] = fn end
function TK.OnRoster(fn) rosterListeners[#rosterListeners + 1] = fn end
function TK.Changed() fire(changedListeners) end
function TK.RosterChanged() TK.RebuildUnits(); fire(rosterListeners) end

local function say(msg)
    if AIP.Print then AIP.Print(msg) end
end

-- ============================================================================
-- SAVED STATE
-- ============================================================================

-- AIP.db.tankCast (defaults live in core/Core.lua). Repairs the shape so a
-- hand-edited/older SavedVariables file can never break the window.
local function cfg()
    local db = AIP.db
    if not db then return nil end
    local c = db.tankCast
    if type(c) ~= "table" then c = {}; db.tankCast = c end
    if type(c.mt) ~= "string" then c.mt = "" end
    if type(c.ots) ~= "table" then c.ots = {} end
    for k = 1, TK.SLOTS - 1 do
        if type(c.ots[k]) ~= "string" then c.ots[k] = "" end
    end
    if type(c.spell) ~= "string" then c.spell = "" end
    return c
end
TK.Cfg = cfg

local function setRaw(c, i, value)
    if i == 1 then c.mt = value else c.ots[i - 1] = value end
end

-- ============================================================================
-- SANITISING / MACRO TEXT
-- ============================================================================

-- Make free text safe to interpolate into a macro line: no control chars, no
-- macro-structural characters (/ ; [ ]) and no |-escapes; whitespace collapsed.
function TK.Sanitize(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("%c", " ")
    text = text:gsub("[/;%[%]|]", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

-- Player names are letters only (plus UTF-8 bytes for accented names).
function TK.SanitizeName(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("[^%a\128-\255]", ""))
end

-- Accepts a plain name or a shift-clicked spell/item link and returns the
-- sanitised display name ("|cff71d5ff|Hspell:34477|h[Misdirection]|h|r" -> "Misdirection").
function TK.ParseSpellInput(text)
    if type(text) ~= "string" then return "" end
    local linked = text:match("|H%a+:[^|]*|h%[(.-)%]|h")
    if linked then text = linked end
    return TK.Sanitize(text)
end

-- The secure macro a tank row runs on left-click, or nil if it can't be built.
-- "target=" (not "@") for 3.3.5a; /cast resolves both spells and items.
function TK.BuildMacro(name, spell)
    name = TK.SanitizeName(name)
    spell = TK.Sanitize(spell)
    if name == "" or spell == "" then return nil end
    local text = "/cast [target=" .. name .. "] " .. spell
    if #text > TK.MACRO_MAX then return nil end
    return text
end

-- ============================================================================
-- TANK LIST
-- ============================================================================

function TK.SlotLabel(i)
    if i == 1 then return "MT" end
    return "OT" .. tostring((i or 1) - 1)
end

function TK.GetSlot(i)
    local c = cfg()
    if not c or type(i) ~= "number" or i < 1 or i > TK.SLOTS then return "" end
    if i == 1 then return c.mt end
    return c.ots[i - 1]
end

function TK.FindSlot(name)
    if type(name) ~= "string" or name == "" then return nil end
    local lname = name:lower()
    for i = 1, TK.SLOTS do
        local s = TK.GetSlot(i)
        if s ~= "" and s:lower() == lname then return i end
    end
    return nil
end

local function normalize(name)
    if AIP.Utils and AIP.Utils.NormalizeName then return AIP.Utils.NormalizeName(name) end
    return name
end

-- Assign (or clear, with nil/"") a slot. A name already in another slot is
-- moved, never duplicated. Returns ok, errorMessage.
function TK.SetSlot(i, name)
    local c = cfg()
    if not c then return false, "Settings are not loaded yet." end
    if type(i) ~= "number" or i < 1 or i > TK.SLOTS or i ~= math.floor(i) then
        return false, "Bad tank slot."
    end
    if name == nil or name == "" then
        setRaw(c, i, "")
        TK.Changed()
        return true
    end
    local clean = TK.SanitizeName(name)
    local norm = clean ~= "" and normalize(clean) or nil
    if not norm then return false, "Invalid player name." end
    for s = 1, TK.SLOTS do
        if s ~= i and TK.GetSlot(s):lower() == norm:lower() then setRaw(c, s, "") end
    end
    setRaw(c, i, norm)
    TK.Changed()
    return true
end

-- Put a name in the first empty off-tank slot (no-op if already listed).
function TK.SetFirstOT(name)
    local clean = TK.SanitizeName(name)
    if clean == "" then return false, "Invalid player name." end
    if TK.FindSlot(clean) then return true end
    for i = 2, TK.SLOTS do
        if TK.GetSlot(i) == "" then return TK.SetSlot(i, name) end
    end
    return false, "All off-tank slots are full (clear one first)."
end

function TK.ClearAll()
    local c = cfg()
    if not c then return end
    for i = 1, TK.SLOTS do setRaw(c, i, "") end
    TK.Changed()
end

function TK.GetSpell()
    local c = cfg()
    return c and c.spell or ""
end

function TK.SetSpell(text)
    local clean = TK.ParseSpellInput(text)
    local c = cfg()
    if not c then return clean end
    c.spell = clean
    TK.Changed()
    return clean
end

-- ============================================================================
-- UNITS / CANDIDATES / STATUS
-- ============================================================================

-- name -> unit token. Used for class colour, health and range only; the cast
-- macro targets by NAME so it survives raid roster reshuffles.
function TK.RebuildUnits()
    local map = {}
    local nRaid = GetNumRaidMembers and GetNumRaidMembers() or 0
    if nRaid > 0 then
        for i = 1, nRaid do
            local unit = "raid" .. i
            local n = UnitName(unit)
            if n then map[n:lower()] = unit end
        end
    else
        local me = UnitName("player")
        if me then map[me:lower()] = "player" end
        local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
        for i = 1, nParty do
            local unit = "party" .. i
            local n = UnitName(unit)
            if n then map[n:lower()] = unit end
        end
    end
    TK.units = map
end

function TK.UnitFor(name)
    if type(name) ~= "string" or name == "" then return nil end
    if not TK.units then TK.RebuildUnits() end
    return TK.units[name:lower()]
end

-- Everyone in the group; tank-capable classes first, then alphabetical.
function TK.GetCandidates()
    if not TK.units then TK.RebuildUnits() end
    local list = {}
    for _, unit in pairs(TK.units) do
        local name = UnitName(unit)
        local _, class = UnitClass(unit)
        if name then
            list[#list + 1] = { name = name, class = class, tank = TK.TANK_CLASSES[class or ""] and true or false }
        end
    end
    table.sort(list, function(a, b)
        if a.tank ~= b.tank then return a.tank end
        return a.name < b.name
    end)
    return list
end

function TK.TargetName()
    if UnitExists and UnitExists("target") and UnitIsPlayer and UnitIsPlayer("target") then
        return (UnitName("target"))
    end
    return nil
end

-- What the configured text is: "spell" (in your spellbook), "item" (cached
-- item) or nil. Also returns the icon texture and canonical name.
function TK.ResolveSpell(text)
    if type(text) ~= "string" or text == "" then return nil end
    if GetSpellInfo then
        local n, _, icon = GetSpellInfo(text)
        if n then return "spell", icon, n end
    end
    if GetItemInfo then
        local n, _, _, _, _, _, _, _, _, icon = GetItemInfo(text)
        if n then return "item", icon, n end
    end
    return nil
end

function TK.GetCooldown(spell, kind)
    if type(spell) ~= "string" or spell == "" then return 0, 0, 0 end
    if kind == "spell" and GetSpellCooldown then
        local s, d, e = GetSpellCooldown(spell)
        return s or 0, d or 0, e or 0
    elseif kind == "item" and GetItemInfo and GetItemCooldown then
        local _, link = GetItemInfo(spell)
        local id = link and tonumber(link:match("item:(%d+)"))
        if id then
            local s, d, e = GetItemCooldown(id)
            return s or 0, d or 0, e or 0
        end
    end
    return 0, 0, 0
end

function TK.KnownPresets()
    local out = {}
    if not GetSpellInfo then return out end
    for _, name in ipairs(TK.PRESET_SPELLS) do
        if GetSpellInfo(name) then out[#out + 1] = name end
    end
    return out
end

-- Is the tank close enough for the configured spell/item? Uses the spell's own
-- range when the client can tell, else the 28-yard interact distance.
function TK.InRange(name, unit, spell)
    unit = unit or TK.UnitFor(name)
    if not unit then return false end
    if UnitIsUnit and UnitIsUnit(unit, "player") then return true end
    spell = spell or TK.GetSpell()
    if spell ~= "" then
        local kind = TK.ResolveSpell(spell)
        if kind == "spell" and IsSpellInRange then
            local r = IsSpellInRange(spell, unit)
            if r ~= nil then return r == 1 end
        elseif kind == "item" and IsItemInRange then
            local r = IsItemInRange(spell, unit)
            if r ~= nil then return r == 1 end
        end
    end
    if CheckInteractDistance then return CheckInteractDistance(unit, 4) and true or false end
    return true
end

-- "ok" | "away" (not in group) | "offline" | "dead" | "range"
function TK.Status(name, spell)
    local unit = TK.UnitFor(name)
    if not unit then return "away" end
    if UnitIsConnected and not UnitIsConnected(unit) then return "offline" end
    if UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit) then return "dead" end
    if not TK.InRange(name, unit, spell) then return "range" end
    return "ok"
end

-- ============================================================================
-- BLIZZARD SYNC (WotLK only has MAINTANK / MAINASSIST raid flags)
-- ============================================================================

-- Mirror the raid's flags: MAINTANK -> MT slot, MAINASSIST players -> OT slots.
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
    local c = cfg()
    if not c then return false, "Settings are not loaded yet." end
    for i = 1, TK.SLOTS do setRaw(c, i, "") end
    if mt then TK.SetSlot(1, mt) end
    local nOT = math.min(#assists, TK.SLOTS - 1)
    for k = 1, nOT do TK.SetSlot(k + 1, assists[k]) end
    return true, string.format("Imported from the raid flags: MT %s, %d off-tank(s) (from Main Assists).",
        mt or "none", nOT)
end

function TK.CanPush()
    if not (GetNumRaidMembers and GetNumRaidMembers() > 0) then return false end
    return ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())) and true or false
end

-- Set the raid's MAINTANK / MAINASSIST flags to match the list. Leader/assist
-- only; skips flags that are already set. Explicit user action only.
function TK.PushToBlizzard()
    if not TK.CanPush() then
        return false, "You must be raid leader or assistant in a raid to set the raid flags."
    end
    if not (SetPartyAssignment and GetPartyAssignment) then
        return false, "This client cannot set raid assignments."
    end
    local set, missing = 0, 0
    for i = 1, TK.SLOTS do
        local name = TK.GetSlot(i)
        if name ~= "" then
            local unit = TK.UnitFor(name)
            if not unit then
                missing = missing + 1
            else
                local assignment = (i == 1) and "MAINTANK" or "MAINASSIST"
                if not GetPartyAssignment(assignment, unit) then
                    SetPartyAssignment(assignment, unit)
                    set = set + 1
                end
            end
        end
    end
    local msg = string.format("Raid flags updated (%d set", set)
    if missing > 0 then msg = msg .. string.format(", %d not in your raid", missing) end
    return true, msg .. ")."
end

-- ============================================================================
-- SLASH: /aip tanks [mt|ot|spell|clear|sync|push|list]
-- ============================================================================

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
    elseif sub == "spell" then
        if arg == "" then
            say("Current spell/item: " .. (TK.GetSpell() ~= "" and TK.GetSpell() or "(none)"))
            return
        end
        local clean = TK.SetSpell(arg)
        local kind = TK.ResolveSpell(clean)
        say("Tank spell/item set to '" .. clean .. "'" ..
            (kind and (" (" .. kind .. ")") or " - not found in your spellbook or item cache (yet)"))
    elseif sub == "clear" then
        TK.ClearAll()
        say("Tank list cleared.")
    elseif sub == "sync" or sub == "import" then
        local _, msg = TK.ImportFromBlizzard()
        say(msg)
    elseif sub == "push" then
        local _, msg = TK.PushToBlizzard()
        say(msg)
    elseif sub == "list" then
        for i = 1, TK.SLOTS do
            local n = TK.GetSlot(i)
            say(TK.SlotLabel(i) .. ": " .. (n ~= "" and n or "-"))
        end
        say("Spell/item: " .. (TK.GetSpell() ~= "" and TK.GetSpell() or "(none)"))
    else
        say("/aip tanks [mt|ot [name]] [spell <name>] [clear] [sync] [push] [list]")
    end
end

-- ============================================================================
-- EVENTS (module-local pub/sub, not a new frame)
-- ============================================================================

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    local E = AIP.Utils.Events
    local function onRoster() TK.RosterChanged() end
    E.Register("RAID_ROSTER_UPDATE", onRoster, "TankCast")
    E.Register("PARTY_MEMBERS_CHANGED", onRoster, "TankCast")
    E.Register("PLAYER_ENTERING_WORLD", onRoster, "TankCast")
    -- Combat ended: apply any tank/spell edit that was deferred by lockdown.
    E.Register("PLAYER_REGEN_ENABLED", function()
        if TK.dirty then TK.Changed() end
    end, "TankCast")
end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `luajit tools/tests/tankcast_spec.lua`
Expected: last line `N passed, 0 failed` and exit code 0. If any `FAIL` line prints, fix the module (not the test) unless the expectation itself is wrong per the spec.

- [ ] **Step 5: Add the saved-variable default**

In `AutoInvitePlus/core/Core.lua`, Edit:

old_string:
```
    floatingBarSize = nil,          -- {w, h} user-resized size of the announcement bar
```
new_string:
```
    floatingBarSize = nil,          -- {w, h} user-resized size of the announcement bar

    -- Tank Cast window (AIP.TankCast): 1 MT + 3 OT list and the spell/item cast on them
    tankCast = {
        mt = "",                    -- Main Tank name ("" = unset)
        ots = {"", "", ""},         -- Off-Tank 1-3
        spell = "",                 -- spell or item name run by the tank buttons
        shown = false,              -- window visible (persisted across reloads)
        showConfig = false,         -- spell/config strip expanded
        pos = nil,                  -- {point, relPoint, x, y}
    },
```

- [ ] **Step 6: Wire the slash command and help**

In `AutoInvitePlus/core/Core.lua`, Edit:

old_string:
```
    elseif cmd == "bar" or cmd == "announcebar" then
        if AIP.RaidTools then AIP.RaidTools.ToggleBar() end
```
new_string:
```
    elseif cmd == "bar" or cmd == "announcebar" then
        if AIP.RaidTools then AIP.RaidTools.ToggleBar() end
    elseif cmd == "tanks" or cmd == "tank" then
        if AIP.TankCast and AIP.TankCast.SlashHandler then AIP.TankCast.SlashHandler(rest) end
```

Then Edit:

old_string:
```
        Print("  /aip bar - Toggle the floating announcement bar")
```
new_string:
```
        Print("  /aip bar - Toggle the floating announcement bar")
        Print("  /aip tanks - Toggle the Tank Cast window (set MT/OTs, cast a spell on them)")
        Print("  /aip tanks mt|ot [name] | spell <name> | clear | sync | push | list")
```

- [ ] **Step 7: Register the module in the .toc**

In `AutoInvitePlus/AutoInvitePlus.toc`, Edit:

old_string:
```
modules\Rotation.lua
```
new_string:
```
modules\Rotation.lua
modules\TankCast.lua
```

- [ ] **Step 8: Checkpoint**

Run the syntax check on `AutoInvitePlus/modules/TankCast.lua`, `AutoInvitePlus/core/Core.lua`, `tools/tests/tankcast_spec.lua`; run `luajit tools/tests/tankcast_spec.lua` again.
Expected: all `OK`, `0 failed`.
In-game (optional now, required in Task 4): `/reload`, then `/aip tanks mt <YourName>`, `/aip tanks spell <a spell you know>`, `/aip tanks list` prints the slots and spell; `/aip help` shows the two new lines. **Do not commit.**

---

### Task 2: Floating window and secure tank rows

**Files:**
- Create: `AutoInvitePlus/ui/TankCastWindow.lua`
- Modify: `AutoInvitePlus/AutoInvitePlus.toc` (after `ui\CompositionUI.lua`)

**Interfaces:**
- Consumes: everything `TK.*` from Task 1; `AIP.UI.CreateIconButton(parent, icon, size, onClick, tooltip)`; `AIP.Utils.Events.Register`; WoW `EasyMenu`, `CooldownFrame_SetTimer`, `RAID_CLASS_COLORS`, `InCombatLockdown`.
- Produces: `TK.ShowWindow()`, `TK.HideWindow()`, `TK.ToggleWindow()`, `TK.IsWindowShown() -> bool`, `TK.LayoutWindow()` (re-sizes window + status line from `win.rowCount`), `TK.EnsureMenuFrame() -> dropdownFrame`, constants `TK.WIN_W`, `TK.PAD`, `TK.CFG_H`; calls the optional Task 3 hooks `TK.BuildConfigStrip(win)` (once, at creation) and `TK.SyncConfigStrip()` (on refresh); expects Task 3 to set `win.cfg` (a Frame of height `TK.CFG_H`, anchored to the window bottom).

- [ ] **Step 1: Write the window file**

Create `AutoInvitePlus/ui/TankCastWindow.lua`:

```lua
-- AutoInvite Plus - Tank Cast window (presentation for AIP.TankCast)
-- Floating window: one secure button per tank slot. Left-click casts the
-- configured spell/item on that tank via `/cast [target=<Name>] <spell>`;
-- right-click (or an empty slot) opens the assign / clear menu.
--
-- 3.3.5a secure-frame rules this file obeys:
--  * rows are SecureActionButtonTemplate (protected): attributes, Show/Hide and
--    SetPoint are ONLY touched when not InCombatLockdown() (see applyStructure);
--  * rows display a snapshot (row.tank / applied.spell) of what their attributes
--    actually do, so the window never disagrees with what a click casts;
--  * the window itself is a plain Frame, so it can be shown/hidden/moved in combat.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local WIN_W, PAD, HDR_H = 190, 6, 20
local ROW_H, ROW_GAP, STATUS_H = 26, 2, 14
local CFG_H = 52
local HP_X, HP_R = 36, 28                       -- hp bar insets inside a row
local HP_W = (WIN_W - PAD * 2) - HP_X - HP_R
local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
TK.WIN_W, TK.PAD, TK.CFG_H = WIN_W, PAD, CFG_H

local STATE_TEXT = { away = "Not in your group", offline = "Offline", dead = "Dead", range = "Out of range" }

local win
local rows = {}
local menuFrame
local applied = { spell = "", kind = nil, icon = nil }   -- what the secure buttons currently do
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
    return win and win.cfg ~= nil and c ~= nil and (c.showConfig or c.spell == "")
end

-- ============================================================================
-- ASSIGN / CLEAR MENU
-- ============================================================================

local function openMenu(row)
    local slot = row.slot
    local current = TK.GetSlot(slot)
    local list = {}
    list[#list + 1] = {
        text = (current ~= "") and current or ("Set " .. TK.SlotLabel(slot)),
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
        list[#list + 1] = { text = "Clear", notCheckable = true, func = function() TK.SetSlot(slot, "") end }
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

-- ============================================================================
-- ROWS
-- ============================================================================

local function createRow(i)
    local row = CreateFrame("Button", "AIPTankCastRow" .. i, win, "SecureActionButtonTemplate")
    row.slot = i
    row.tank = ""
    row:SetSize(WIN_W - PAD * 2, ROW_H)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:Hide()

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(0.11, 0.12, 0.17, 0.92)
    row.accent = row:CreateTexture(nil, "ARTWORK")
    row.accent:SetPoint("TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT"); row.accent:SetWidth(2)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture(1, 0.82, 0, 0.16)

    row.chip = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.chip:SetPoint("LEFT", 7, 0); row.chip:SetWidth(26); row.chip:SetJustifyH("LEFT")
    row.chip:SetText(i == 1 and "|cFFFFD700MT|r" or ("|cFFC0C4D0OT" .. (i - 1) .. "|r"))

    row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.nameFS:SetPoint("LEFT", HP_X, 3); row.nameFS:SetPoint("RIGHT", -HP_R, 3)
    row.nameFS:SetJustifyH("LEFT")

    row.hpBg = row:CreateTexture(nil, "ARTWORK")
    row.hpBg:SetPoint("BOTTOMLEFT", HP_X, 2); row.hpBg:SetSize(HP_W, 3); row.hpBg:SetTexture(0, 0, 0, 0.6)
    row.hp = row:CreateTexture(nil, "OVERLAY")
    row.hp:SetPoint("BOTTOMLEFT", HP_X, 2); row.hp:SetSize(HP_W, 3); row.hp:SetTexture(0.2, 0.85, 0.3, 1)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(20, 20); row.icon:SetPoint("RIGHT", -4, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.cd = CreateFrame("Cooldown", nil, row, "CooldownFrameTemplate")
    row.cd:SetAllPoints(row.icon)

    row.dim = row:CreateTexture(nil, "OVERLAY", nil, 7)
    row.dim:SetAllPoints(); row.dim:SetTexture(0, 0, 0, 0.55); row.dim:Hide()

    -- Left-click on a filled row is the secure macro; this non-secure hook only
    -- handles right-click, empty slots, and the "no spell set" hint.
    row:HookScript("OnClick", function(self, button)
        if button == "RightButton" or self.tank == "" then
            openMenu(self)
        elseif not self.macroSet then
            AIP.Print("Tank window: set a spell or item first (gear icon, top right).")
        end
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.tank == "" then
            GameTooltip:AddLine("Set " .. TK.SlotLabel(self.slot), 1, 0.82, 0)
            GameTooltip:AddLine("Click to pick a player.", 1, 1, 1, true)
        else
            GameTooltip:AddLine(self.tank, 1, 0.82, 0)
            if self.stateText then GameTooltip:AddLine(self.stateText, 1, 0.5, 0.3) end
            if applied.spell ~= "" then GameTooltip:AddLine("Left-click: cast " .. applied.spell, 1, 1, 1) end
            GameTooltip:AddLine("Right-click: change / clear", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

-- Which slots get a row: MT always, filled OTs, plus the first empty OT.
local function visibleSlots()
    local vis, emptyShown = {}, false
    for i = 1, TK.SLOTS do
        if i == 1 or TK.GetSlot(i) ~= "" then
            vis[#vis + 1] = i
        elseif not emptyShown then
            vis[#vis + 1] = i
            emptyShown = true
        end
    end
    return vis
end

-- Window height + status-line position (both non-secure: safe in combat).
function TK.LayoutWindow()
    if not win then return end
    local n = win.rowCount or 1
    local rowsH = n * (ROW_H + ROW_GAP)
    win.status:ClearAllPoints()
    win.status:SetPoint("TOPLEFT", win, "TOPLEFT", PAD + 2, -(HDR_H + PAD + rowsH))
    local h = HDR_H + PAD + rowsH + STATUS_H + PAD
    if cfgOpen() then
        h = h + CFG_H
        win.cfg:Show()
    elseif win.cfg then
        win.cfg:Hide()
    end
    win:SetHeight(h)
end

-- Out-of-combat only: snapshot list + spell, (re)write secure attributes, lay out rows.
local function applyStructure()
    applied.spell = TK.GetSpell()
    applied.kind, applied.icon = TK.ResolveSpell(applied.spell)
    local vis = visibleSlots()
    local pos = {}
    for k, i in ipairs(vis) do pos[i] = k end
    for i = 1, TK.SLOTS do
        local row = rows[i]
        row.tank = TK.GetSlot(i)
        row.cdStart, row.cdDur = nil, nil
        local macro = TK.BuildMacro(row.tank, applied.spell)
        row:SetAttribute("type1", macro and "macro" or nil)
        row:SetAttribute("macrotext1", macro)
        row.macroSet = macro ~= nil
        if pos[i] then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", win, "TOPLEFT", PAD, -(HDR_H + PAD + (pos[i] - 1) * (ROW_H + ROW_GAP)))
            row:Show()
        else
            row:Hide()
        end
    end
    win.rowCount = #vis
    TK.LayoutWindow()
end

local function updateRow(row, cs, cdur, cen)
    if row.tank == "" then
        row.nameFS:SetText("|cFF7A7F8E+ Set " .. TK.SlotLabel(row.slot) .. "|r")
        row.accent:SetTexture(0.4, 0.42, 0.5, 0.5)
        row.hp:Hide(); row.hpBg:Hide(); row.icon:Hide(); row.dim:Hide()
        CooldownFrame_SetTimer(row.cd, 0, 0, 0)     -- no leftover sweep on a cleared slot
        row.cdStart, row.cdDur = nil, nil
        row.stateText = nil
        return
    end
    row.hp:Show(); row.hpBg:Show(); row.icon:Show()
    local unit = TK.UnitFor(row.tank)
    local class
    if unit then local _, cl = UnitClass(unit); class = cl end
    local r, g, b = classColor(class)
    row.nameFS:SetText(hex(r, g, b) .. row.tank .. "|r")
    if row.slot == 1 then row.accent:SetTexture(1, 0.82, 0, 0.7) else row.accent:SetTexture(0.75, 0.78, 0.85, 0.6) end

    local pct = 0
    if unit and UnitExists(unit) then
        local m = UnitHealthMax(unit)
        if m and m > 0 then pct = UnitHealth(unit) / m end
    end
    row.hp:SetWidth(math.max(1, HP_W * pct))
    if pct > 0.5 then row.hp:SetTexture(0.2, 0.85, 0.3, 1)
    elseif pct > 0.25 then row.hp:SetTexture(0.95, 0.8, 0.2, 1)
    else row.hp:SetTexture(0.9, 0.2, 0.2, 1) end

    local st = TK.Status(row.tank, applied.spell)
    row.stateText = STATE_TEXT[st]
    if st == "ok" then row.dim:Hide() else row.dim:Show() end

    row.icon:SetTexture(applied.icon or QUESTION)
    if row.cdStart ~= cs or row.cdDur ~= cdur then
        CooldownFrame_SetTimer(row.cd, cs, cdur, cen)
        row.cdStart, row.cdDur = cs, cdur
    end
end

local function updateStatus()
    local text, r, g, b
    if TK.dirty then
        text, r, g, b = "Changes apply after combat", 1, 0.6, 0.2
    elseif applied.spell == "" then
        text, r, g, b = "No spell set (see gear icon)", 1, 0.5, 0.3
    elseif not applied.kind then
        text, r, g, b = "Unknown spell or item", 0.95, 0.3, 0.3
    else
        text, r, g, b = "L-click cast  |  R-click edit", 0.5, 0.52, 0.6
    end
    win.status:SetText(text)
    win.status:SetTextColor(r, g, b)
end

refreshValues = function()
    if not win or not win:IsShown() then return end
    -- An item may not be cached yet when the list was applied; retry the lookup.
    if applied.spell ~= "" and not applied.kind then
        applied.kind, applied.icon = TK.ResolveSpell(applied.spell)
    end
    local cs, cdur, cen = TK.GetCooldown(applied.spell, applied.kind)
    if cdur and cdur <= 1.5 then cs, cdur = 0, 0 end      -- ignore the global cooldown
    for i = 1, TK.SLOTS do
        if rows[i]:IsShown() then updateRow(rows[i], cs, cdur, cen) end
    end
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
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self)
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
    end, "Spell / item settings")
    gear:SetPoint("RIGHT", close, "LEFT", -4, 0)

    win.status = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    win.status:SetJustifyH("LEFT"); win.status:SetWidth(WIN_W - PAD * 2 - 4); win.status:SetHeight(STATUS_H)

    for i = 1, TK.SLOTS do rows[i] = createRow(i) end
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
    ensureWindow()
    local c = TK.Cfg()
    if c then c.shown = true end
    win:Show()
    refresh()
end

function TK.HideWindow()
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

-- Create the (protected) rows out of combat at login, restore visibility.
if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", function()
        ensureWindow()
        local c = TK.Cfg()
        if c and c.shown then win:Show(); refresh() end
    end, "TankCastUI")
end
```

- [ ] **Step 2: Register the file in the .toc**

In `AutoInvitePlus/AutoInvitePlus.toc`, Edit:

old_string:
```
ui\CompositionUI.lua
```
new_string:
```
ui\CompositionUI.lua
ui\TankCastWindow.lua
```

- [ ] **Step 3: Syntax check**

Run the syntax-check command on `AutoInvitePlus/ui/TankCastWindow.lua`. Expected: `OK`.
Also re-run `luajit tools/tests/tankcast_spec.lua` (must still be `0 failed`).

- [ ] **Step 4: Live check: window renders and rows work (solo)**

Run the live-test loop, then in-game (or via `Send-WowChat`):
1. `/console scriptErrors 1`, `/aip tanks` → window appears near screen-left-centre; take `Screenshot-Wow`, expect a navy "Tanks" window with gold divider, an MT row reading "+ Set MT" and the hint/"No spell set" line.
2. Click the MT row → a menu titled "Set MT" with "Use my target" and your own name appears; pick your name → the row shows your class-coloured name with a green HP bar and a question-mark icon (no spell set yet).
3. `/aip tanks spell <a self-castable buff you know>` → row icon becomes the spell icon, status reads "L-click cast | R-click edit".
4. Left-click the row → the buff is cast on you (check `/run print(UnitBuff("player", 1))` or the buff bar). Right-click → menu with Clear / Use my target / candidates.
5. Drag by the header, `/reload` → position and (if left open) visibility persist.
Expected: no Lua errors at any step.

- [ ] **Step 5: Live check: combat lockdown (manual, needs a mob)**

Set MT to yourself with a spell, pull a training dummy/mob, and during combat run `/aip tanks spell <other spell>`.
Expected: status line turns orange "Changes apply after combat"; the row icon and click behaviour stay on the OLD spell; after combat ends the icon/behaviour switch to the new spell and the status returns to the hint. No "action blocked" errors.

- [ ] **Step 6: Checkpoint**

Syntax check + `luajit tools/tests/tankcast_spec.lua` pass; steps 4-5 observed. **Do not commit.**

---

### Task 3: Spell config strip (spell box, presets, Import/Push)

**Files:**
- Create: `AutoInvitePlus/ui/TankCastConfig.lua`
- Modify: `AutoInvitePlus/AutoInvitePlus.toc` (after `ui\TankCastWindow.lua`)

**Interfaces:**
- Consumes: from Task 2 `TK.WIN_W`, `TK.PAD`, `TK.CFG_H`, `TK.EnsureMenuFrame()`, `TK.LayoutWindow()`; from Task 1 `TK.GetSpell/SetSpell/ParseSpellInput/ResolveSpell/KnownPresets/ImportFromBlizzard/PushToBlizzard/CanPush`; `AIP.UI.CreateEditBox(parent, w, h, numeric, maxChars)`, `AIP.UI.CreateButton(parent, text, w, h, onClick, tooltip)`.
- Produces: `TK.BuildConfigStrip(win)` (creates `win.cfg`, hidden by default, anchored to the window bottom, height `TK.CFG_H`), `TK.SyncConfigStrip()` (refreshes icon / edit text / red border / Push enabled state; safe to call every tick).

- [ ] **Step 1: Write the config strip file**

Create `AutoInvitePlus/ui/TankCastConfig.lua`:

```lua
-- AutoInvite Plus - Tank Cast window: spell/item config strip
-- Shown under the tank rows via the gear icon (and forced open while no spell
-- is set): spell box (accepts a typed name or a shift-clicked spellbook link),
-- class-preset menu, and the Blizzard Import / Push buttons.

local AIP = AutoInvitePlus
if not AIP then return end

AIP.TankCast = AIP.TankCast or {}
local TK = AIP.TankCast
local UI = AIP.UI

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local strip                                   -- the strip's widgets (set by BuildConfigStrip)

StaticPopupDialogs["AIP_TANKCAST_PUSH"] = {
    text = "Set the raid's Main Tank / Main Assist flags to match your Tanks list?\n\nThis is visible to the whole raid.",
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

local function openPresetMenu(anchor)
    local list = { { text = "Preset spells", isTitle = true, notCheckable = true } }
    local known = TK.KnownPresets()
    if #known == 0 then
        list[#list + 1] = { text = "None of the presets are in your spellbook", disabled = true, notCheckable = true }
    else
        for _, name in ipairs(known) do
            list[#list + 1] = { text = name, notCheckable = true, func = function() TK.SetSpell(name) end }
        end
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, TK.EnsureMenuFrame(), anchor, 0, 0, "MENU")
end

local function applyEdit(edit)
    local clean = TK.ParseSpellInput(edit:GetText())
    if clean ~= TK.GetSpell() then TK.SetSpell(clean) end
    edit:SetText(clean)
    TK.SyncConfigStrip()
end

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

    local icon = cfg:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22); icon:SetPoint("TOPLEFT", 0, -4)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93); icon:SetTexture(QUESTION)

    local edit = UI.CreateEditBox(cfg, w - 22 - 4 - 22 - 4, 22, false, 120)
    edit:SetPoint("LEFT", icon, "RIGHT", 4, 0)
    edit:SetScript("OnEnterPressed", function(self) applyEdit(self); self:ClearFocus() end)
    edit:SetScript("OnEscapePressed", function(self) self:SetText(TK.GetSpell()); self:ClearFocus() end)
    edit:HookScript("OnEditFocusLost", function(self) applyEdit(self) end)
    edit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Spell or item to cast on a tank", 1, 0.82, 0)
        GameTooltip:AddLine("Type a name, or shift-click a spell in your spellbook.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local presetBtn = UI.CreateButton(cfg, "v", 22, 22, function(self) openPresetMenu(self) end, "Preset spells for your class")
    presetBtn:SetPoint("LEFT", edit, "RIGHT", 4, 0)

    local half = math.floor((w - 4) / 2)
    local importBtn = UI.CreateButton(cfg, "Import", half, 20, function()
        local _, msg = TK.ImportFromBlizzard()
        AIP.Print(msg)
    end, "Copy the raid's Main Tank / Main Assist flags into this list (Main Assists become off-tanks)")
    importBtn:SetPoint("BOTTOMLEFT", 0, 2)

    local pushBtn = UI.CreateButton(cfg, "Push", half, 20, function()
        StaticPopup_Show("AIP_TANKCAST_PUSH")
    end, "Set the raid's Main Tank / Main Assist flags from this list (raid leader or assistant only)")
    pushBtn:SetPoint("BOTTOMRIGHT", 0, 2)

    strip = { frame = cfg, icon = icon, edit = edit, pushBtn = pushBtn }
end

-- Cheap; safe to call every refresh tick.
function TK.SyncConfigStrip()
    if not strip or not strip.frame:IsShown() then return end
    local spell = TK.GetSpell()
    if not strip.edit:HasFocus() and strip.edit:GetText() ~= spell then strip.edit:SetText(spell) end
    local kind, tex = TK.ResolveSpell(spell)
    strip.icon:SetTexture(tex or QUESTION)
    if spell ~= "" and not kind then
        strip.edit:SetBackdropBorderColor(0.9, 0.2, 0.2)          -- neither a known spell nor an item
    elseif not strip.edit:HasFocus() then
        strip.edit:SetBackdropBorderColor(0.45, 0.45, 0.5)
    end
    if TK.CanPush() then strip.pushBtn:Enable() else strip.pushBtn:Disable() end
end
```

- [ ] **Step 2: Register the file in the .toc**

In `AutoInvitePlus/AutoInvitePlus.toc`, Edit:

old_string:
```
ui\TankCastWindow.lua
```
new_string:
```
ui\TankCastWindow.lua
ui\TankCastConfig.lua
```

- [ ] **Step 3: Syntax check**

Run the syntax-check command on `AutoInvitePlus/ui/TankCastConfig.lua` and `AutoInvitePlus/ui/TankCastWindow.lua`. Expected: `OK` for both.

- [ ] **Step 4: Live check**

Run the live-test loop, then:
1. `/aip tanks` with an empty spell → the config strip is open by itself, status reads "No spell set (see gear icon)"; the spell box shows a question-mark icon.
2. Type a known spell name + Enter → icon updates, status returns to the hint; type `Nonsense` + Enter → box border turns red, status "Unknown spell or item".
3. Shift-click a spell in the spellbook while the box is focused → the box ends up with just the spell name after Enter (not the raw link).
4. Click the `v` button → a preset menu listing only presets your class knows (or the "None of the presets..." line).
5. Click the gear → strip collapses/expands (only when a spell is set); window height follows.
6. Solo: Push is greyed out; Import prints "You are not in a raid."
7. In a raid/party test if available: Push (as leader/assist) shows the Yes/No confirmation, then flags appear on the raid frame; Import fills MT/OT rows from the flags. If no group is available, state explicitly that Import/Push were not live-verified beyond the solo refusals.
Expected: no Lua errors.

- [ ] **Step 5: Checkpoint**

Syntax check on both UI files + `luajit tools/tests/tankcast_spec.lua` pass. **Do not commit.**

---

### Task 4: Title-bar button, simplified-view menu, docs, final verification

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua` (title-bar quick buttons ~lines 1025-1071)
- Modify: `AutoInvitePlus/CLAUDE.md` (add a `TankCast` bullet before the `Updater` bullet)
- Modify: `CLAUDE.md` (repo root; add `TankCast` to the modules list)

**Interfaces:**
- Consumes: `AIP.TankCast.ToggleWindow()` (Task 2), guarded.
- Produces: a "Tanks" button at the left end of the title-bar quick-button row; a "Tank Cast Window" entry in the simplified-view `...` menu.

- [ ] **Step 1: Add the title-bar button**

In `AutoInvitePlus/ui/CentralGUI.lua`, Edit:

old_string:
```
    local qReady = titleBtn("Ready", 52, qBar, -3,
        function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end,
        "Start a ready check")
```
new_string:
```
    local qReady = titleBtn("Ready", 52, qBar, -3,
        function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end,
        "Start a ready check")
    local qTanks = titleBtn("Tanks", 46, qReady, -3,
        function() if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end end,
        "Tank Cast window: set the main/off tanks and cast a spell on them")
```

- [ ] **Step 2: Include it in the simplified-view swap**

Edit:

old_string:
```
    frame.quickTitleButtons = {qTools, qBreak, qPull, qRDF, qBar, qReady}
```
new_string:
```
    frame.quickTitleButtons = {qTools, qBreak, qPull, qRDF, qBar, qReady, qTanks}
```

- [ ] **Step 3: Add the menu entry and tooltip text for the `...` dropdown**

Edit:

old_string:
```
            {text = "Roll Window", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end},
```
new_string:
```
            {text = "Roll Window", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end},
            {text = "Tank Cast Window", notCheckable = true,
                func = function() if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end end},
```

Edit:

old_string:
```
        GameTooltip:AddLine("Ready Check, Bar, RDF, Pull, Break, Rolls", 1, 1, 1, true)
```
new_string:
```
        GameTooltip:AddLine("Ready Check, Bar, RDF, Pull, Break, Rolls, Tanks", 1, 1, 1, true)
```

- [ ] **Step 4: Document the module**

In `AutoInvitePlus/CLAUDE.md`, Edit:

old_string:
```
  - **`Updater`** (`AIP.Updater`) is version-check-only
```
new_string:
```
  - **`TankCast`** (`AIP.TankCast`, `/aip tanks`) is the Tank Cast window: a 1 MT + 3 OT list (`AIP.db.tankCast`, AIP-local so any class can use it; `Import`/`Push` mirror Blizzard's MAINTANK/MAINASSIST flags - WotLK has no off-tank flag, so Main Assists become OTs) plus one configurable spell/item cast on a tank with a click. Split three ways: `modules/TankCast.lua` (headless logic, unit-tested by `luajit tools/tests/tankcast_spec.lua`), `ui/TankCastWindow.lua` (window + rows), `ui/TankCastConfig.lua` (spell box/presets/Import/Push). Casting is a secure macro `/cast [target=<Name>] <spell>` on `SecureActionButtonTemplate` rows, so **attributes, Show/Hide and SetPoint of rows are only touched when `not InCombatLockdown()`** (edits in combat set `TK.dirty` and flush on `PLAYER_REGEN_ENABLED`; rows display a snapshot of what their attributes actually do). Spell/name text is sanitised before it goes into `macrotext`. The module never writes to chat. Opened from the title-bar "Tanks" button (and the simplified-view `...` menu).
  - **`Updater`** (`AIP.Updater`) is version-check-only
```

In repo-root `CLAUDE.md`, Edit:

old_string:
```
PostPull, Rotation, LFGWatch, CharacterCard, TestData
```
new_string:
```
PostPull, Rotation, LFGWatch, CharacterCard, TankCast, TestData
```

- [ ] **Step 5: Syntax check everything touched**

Run the syntax-check command on: `AutoInvitePlus/ui/CentralGUI.lua`, `AutoInvitePlus/ui/TankCastWindow.lua`, `AutoInvitePlus/ui/TankCastConfig.lua`, `AutoInvitePlus/modules/TankCast.lua`, `AutoInvitePlus/core/Core.lua`.
Run: `luajit tools/tests/tankcast_spec.lua`.
Expected: all `OK`, `0 failed`.

- [ ] **Step 6: Live verification (Full and Simplified views)**

Run the live-test loop, then:
1. `/aip` and `Screenshot-Wow`: the title bar shows `Tanks Ready Bar RDF Pull Break Rolls` with **no overlap** of "AutoInvite+ by iuGames" and the other chrome buttons at the default width; click "Tanks" → the window toggles.
2. Simplified View button: the text buttons hide, the `...` menu lists "Tank Cast Window" and it toggles the window.
3. Shrink the main window to its minimum width (900) and re-check the title bar for overlap. If it overlaps, reduce the widths in the `titleBtn(...)` calls (e.g. Tanks 40, Ready 46) until it does not, and re-screenshot.
4. Full solo scenario from Task 2 step 4 once more end to end (MT = yourself, real cast succeeds).
5. Confirm the two API assumptions the spec flagged, and record the observed result in the final report: (a) the `[target=Name]` macro works with a group member other than yourself (party of 2 if available), (b) `SetPartyAssignment("MAINTANK", unit)` behaves as coded (set once, not toggled off). If no second player is available, say these were not live-verified.
6. `/reload` with the window open and the config strip collapsed/expanded: layout and position persist.

Expected: no Lua errors (`/console scriptErrors 1`), no overlap, cast works.

- [ ] **Step 7: Final report to the user**

Summarise: files created/changed, the five intentional spec deviations, what was live-verified vs not (Import/Push and cross-player `[target=Name]` if no group was available), and that nothing was committed (offer to commit).
