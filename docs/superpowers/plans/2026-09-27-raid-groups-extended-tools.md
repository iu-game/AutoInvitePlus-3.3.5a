# Raid Groups — Extended Player Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the shipped Raid Groups window with: a richer context menu for every viewer; manager-only raid target icons; private notes (anyone) and manager-broadcast assignments (DataBus, with a toast); a group-position lock separate from the window-position lock; debuff icons on the cell plus an extensive buff/debuff/note/assignment tooltip; a personal missing-buff indicator; and click-to-cast quick-cast slots for buffs/heals on any player.

**Architecture:** All new behaviour lives in `modules/RaidGroups.lua` (headless, unit-tested) except the one new DataBus event type (`core/DataBus.lua`) and the UI rendering (`ui/RaidGroupsWindow.lua`). Two reuse boundaries, both deliberate (see the spec): quick-cast is a thin wrapper around `AIP.TankCast`'s existing spell/item engine (guarded - reports plainly if Tank Cast is absent); buff/debuff scanning is reimplemented locally so this core feature never depends on Tank Cast.

**Tech Stack:** Lua 5.1, WoW 3.3.5a API, LuaJIT for headless tests, `luaparse` for syntax checks.

**Spec:** `docs/superpowers/specs/2026-09-27-raid-groups-extended-tools-design.md` (extends `2026-09-27-raid-groups-window-design.md`, already shipped).

## Global Constraints

- **Governing rule:** a live game-interface query always wins over DataBus; DataBus carries only the shared assignment text, because nothing else here has a native equivalent.
- `RG.MAX_QUICKCAST = 2`. Raid icon order is Blizzard's canonical `{Star, Circle, Diamond, Triangle, Moon, Square, Cross, Skull}` (indices 1-8; 0 clears).
- Notes and assignments are sanitised (`%c` stripped, whitespace collapsed/trimmed) and capped at 60 characters. Empty text clears the entry.
- Every new manager-gated action (`SetRaidIcon`, `SetAssignment`, `ToggleGroupLocked`, and `PlanMove`'s existing gate plus the new group-lock refusal) returns `ok, err` and is enforced in the headless logic layer, not just hidden in the UI - the menu disables a row for convenience, but the underlying function re-checks permission itself.
- Assignments are **never persisted** - `RG.assignments` is an in-memory cache only, exactly like DataBus's own `DB.State.receivedEvents`. Private notes and quick-cast slots **are** persisted (`AIP.db.raidGroups.notes` / `.quickCast`).
- Combat-lockdown rules are unchanged and extend to the new secure quick-cast buttons: attributes/Show/Hide/SetPoint only when `not InCombatLockdown()`, inside the existing `applyStructure`/`refresh` gate.
- **First-pass UI layout note:** cell width/height and icon placement below are a reasonable first pass, not pixel-verified against a live screenshot (unlike the logic, which is fully headless-tested). Task 3's live check is where this gets corrected, the same way Tank Cast's visuals were iterated after the first build.
- **Do not `git commit` unless the user asks.** Each task ends with a "Checkpoint" instead of a commit.
- Syntax check (repo root; recreate `<scratchpad>/luacheck.js` if gone - see the Tank Cast/Raid Groups plans for its exact contents): `node <scratchpad>/luacheck.js <files>`.
- Headless tests (repo root): `luajit tools/tests/raidgroups_spec.lua` (extended by this plan) and `luajit tools/tests/tankcast_spec.lua` (regression - must stay green).
- Live loop (repo root, PowerShell): `. tools\wow-test-harness\harness.ps1; Sync-Addon; Send-WowChat "/reload"; Start-Sleep 8` - no new files are added by this plan (only edits to existing ones), so a plain `/reload` is enough.

## Review Focus

1. **Assignment echo:** the setter must see their own assignment immediately (DataBus never echoes a sender's own broadcast back), via the local-cache-update-before-broadcast order in `RG.SetAssignment` (Task 1 test).
2. **Group lock actually blocks both paths**: the drag path (`endDrag`) and the menu path (`move_N`) must both refuse once `RG.IsGroupLocked()` is true, not just one of them (Task 1 tests cover `PlanMove`; Task 2's live check covers the drag UI path, since `endDrag` calls the same `PlanMove`).
3. **Missing-buff indicator is personal, not generic**: must only light up for a buff the *viewer's own class* can provide, never "anyone is missing anything" (Task 1 test).
4. **Quick-cast without Tank Cast installed** must fail with a clear message, not a silent no-op or an error (Task 1 test).
5. **Raid icon permission**: setting requires manager; reading (`GetRaidIcon`) never does, since seeing icons is normal for everyone (Task 1 tests for both).

---

### Task 1: RaidGroups.lua logic extensions, DataBus event type, defaults, headless tests

**Files:**
- Modify: `AutoInvitePlus/modules/RaidGroups.lua`
- Modify: `tools/tests/raidgroups_spec.lua`
- Modify: `AutoInvitePlus/core/Core.lua` (the `raidGroups` defaults block)
- Modify: `AutoInvitePlus/core/DataBus.lua` (one new `DB.EventTypes` entry)

**Interfaces:**
- Consumes: guarded `AIP.DataBus.CreateEvent/Broadcast/Subscribe`, guarded `AIP.Panels.RaidMgmt.CheckUnitBuffs/ClassBuffs`, guarded `AIP.TankCast.ParseSpellInput/BuildMacro`.
- Produces (all on `AIP.RaidGroups` = `RG`, in addition to everything the base window already has): `RG.RAID_ICONS`, `RG.GetRaidIcon(snap, name)`, `RG.SetRaidIcon(snap, name, index) -> ok, err`, `RG.GetNote(name)`, `RG.SetNote(name, text) -> ok, err`, `RG.GetAssignment(name) -> text, author`, `RG.SetAssignment(snap, name, text) -> ok, err`, `RG.OnAssignmentEvent(event)`, `RG.OnAssignment(fn)`, `RG.IsGroupLocked()/SetGroupLocked(on)/ToggleGroupLocked(snap) -> ok, resultOrErr`, `RG.ListDebuffs(unit, limit) -> list, total`, `RG.ListBuffs(unit, limit) -> list, total`, `RG.MissingBuffsForViewer(unit) -> array`, `RG.MAX_QUICKCAST`, `RG.GetQuickCast()/AddQuickCast(text)/SetQuickCast(i,text)/RemoveQuickCast(i)/BuildQuickCastMacro(name, spellText)`. Extended: `RG.PlanMove` (group-lock refusal), `RG.MemberMenu` (new ids), `RG.WindowMenu` (new ids).

- [ ] **Step 1: Add test stubs and the failing tests**

In `tools/tests/raidgroups_spec.lua`, Edit (add stubs right after the existing `SwapRaidSubgroup` stub, before `dofile(...)`):

old_string:
```
SwapRaidSubgroup = function(i1, i2) assignCalls[#assignCalls + 1] = "swap:" .. i1 .. "/" .. i2 end

dofile("AutoInvitePlus/modules/RaidGroups.lua")
```
new_string:
```
SwapRaidSubgroup = function(i1, i2) assignCalls[#assignCalls + 1] = "swap:" .. i1 .. "/" .. i2 end

-- Raid target icons: a plain unit->index map, exactly like the real client state.
local raidIcons = {}
SetRaidTarget = function(unit, index) raidIcons[unit] = (index and index > 0) and index or nil end
GetRaidTargetIndex = function(unit) return raidIcons[unit] end

-- Time + auras (same stub shape as tools/tests/tankcast_spec.lua's UnitDebuff stub).
local now = 100
GetTime = function() return now end
local buffsByUnit, debuffsByUnit = {}, {}
local function auraStub(byUnit)
    return function(unit, i)
        local d = byUnit[unit] and byUnit[unit][i]
        if d then return d[1], "", d[2], d[3], d[4], 0, d[5], "player" end
    end
end
UnitBuff = auraStub(buffsByUnit)
UnitDebuff = auraStub(debuffsByUnit)

-- DataBus: records outgoing broadcasts and captures the RGNOTE subscriber so tests
-- can simulate an incoming assignment from another player.
local dbBroadcasts, subscribedCb = {}, nil
AutoInvitePlus.DataBus = {
    CreateEvent = function(t, d) return { type = t, data = d } end,
    Broadcast = function(event) dbBroadcasts[#dbBroadcasts + 1] = event end,
    Subscribe = function(eventType, cb, owner) if eventType == "RGNOTE" then subscribedCb = cb end end,
}

-- Raid Management panel's buff-coverage engine (real shape: RM.ClassBuffs[class] is an
-- array of {buffName=...}; RM.CheckUnitBuffs(unit).missingBuffs is an array of names).
local missingFor = {}
AutoInvitePlus.Panels = { RaidMgmt = {
    ClassBuffs = { WARRIOR = { { buffName = "Battle Shout" }, { buffName = "Commanding Shout" } } },
    CheckUnitBuffs = function(unit) return { missingBuffs = missingFor[unit] or {} } end,
} }

-- Tank Cast's reused spell/item engine (only the two functions quick-cast needs).
AutoInvitePlus.TankCast = {
    ParseSpellInput = function(t)
        if type(t) ~= "string" then return "" end
        return (t:gsub("^%s+", ""):gsub("%s+$", ""))
    end,
    BuildMacro = function(name, spell)
        if name == "" or spell == "" then return nil end
        return "/cast [target=" .. name .. "] " .. spell
    end,
}

dofile("AutoInvitePlus/modules/RaidGroups.lua")
```

Then Edit `reset()` to also clear the new mutable state:

old_string:
```
local function reset()
    raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
    assignCalls, printed = {}, {}
    AIP.db.raidGroups = {}
end
```
new_string:
```
local function reset()
    raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
    assignCalls, printed = {}, {}
    AIP.db.raidGroups = {}
    raidIcons, buffsByUnit, debuffsByUnit, dbBroadcasts, missingFor = {}, {}, {}, {}, {}
    now = 100
    RG.assignments = {}
end
```

Then append the new tests before the final `print(...)`/`os.exit(...)` lines:

old_string:
```
print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```
new_string:
```
-- ---- group-position lock ----------------------------------------------------
reset()
eq(RG.IsGroupLocked(), false, "starts unlocked")
local gok, gerr = RG.ToggleGroupLocked({ canManage = false })
eq(gok, false, "toggle refused without manage permission"); eq(RG.IsGroupLocked(), false, "...and stays unlocked")
gok, gerr = RG.ToggleGroupLocked({ canManage = true })
eq(gok, true, "manager can toggle"); eq(gerr, true, "returns the new state"); eq(RG.IsGroupLocked(), true, "now locked")
RG.SetGroupLocked(false); eq(RG.IsGroupLocked(), false, "SetGroupLocked(false)")

reset(); isOfficerFlag = true
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" }, { name = "C", group = 2, class = "Priest" } }
local snapGL = RG.Snapshot()
RG.SetGroupLocked(true)
local _, glReason = RG.PlanMove(snapGL, "A", { group = 2 })
eq(glReason, "Group positions are locked.", "PlanMove refuses while group-locked")
RG.SetGroupLocked(false)
eq((RG.PlanMove(snapGL, "A", { group = 2 })).op, "set", "PlanMove works again once unlocked")

-- ---- raid target icons -------------------------------------------------------
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapIcon = RG.Snapshot()
eq(RG.GetRaidIcon(snapIcon, "A"), 0, "no icon by default")
eq((RG.SetRaidIcon(snapIcon, "A", 8)), false, "no permission without manage")
isOfficerFlag = true
snapIcon = RG.Snapshot()
eq((RG.SetRaidIcon(snapIcon, "A", 8)), true, "manager can set")
eq(RG.GetRaidIcon(snapIcon, "A"), 8, "reads back the icon just set")
eq((RG.SetRaidIcon(snapIcon, "A", 9)), false, "bad index rejected")
eq((RG.SetRaidIcon(snapIcon, "Nobody", 1)), false, "unknown player")
eq(RG.RAID_ICONS[8], "Skull", "canonical icon order")

-- ---- private notes ------------------------------------------------------------
reset()
eq(RG.GetNote("Bob"), "", "no note by default")
eq((RG.SetNote("Bob", "  hello world  ")), true, "set ok")
eq(RG.GetNote("bob"), "hello world", "note lookup is case-insensitive and trimmed")
RG.SetNote("Bob", string.rep("x", 100))
eq(#RG.GetNote("Bob"), 60, "note capped at 60 chars")
RG.SetNote("Bob", "")
eq(RG.GetNote("Bob"), "", "empty text clears the note")
eq((RG.SetNote("", "x")), false, "rejects an empty name")

-- ---- assignments (shared, manager-set, broadcast) ------------------------------
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" } }
local snapAsg = RG.Snapshot()
eq((RG.SetAssignment(snapAsg, "A", "Interrupt")), false, "no permission without manage")
isOfficerFlag = true
snapAsg = RG.Snapshot()
eq((RG.SetAssignment(snapAsg, "A", "Interrupt")), true, "manager can set")
local atext, aauthor = RG.GetAssignment("A")
eq(atext, "Interrupt", "local cache updated immediately (no DataBus echo to wait for)")
eq(aauthor, "Me", "author is the setter")
eq(#dbBroadcasts, 1, "exactly one broadcast sent"); eq(dbBroadcasts[1].type, "RGNOTE", "broadcast event type")
eq(dbBroadcasts[1].data.player, "A", "broadcast player field"); eq(dbBroadcasts[1].data.note, "Interrupt", "broadcast note field")
RG.SetAssignment(snapAsg, "A", "")
eq(RG.GetAssignment("A"), "", "clearing removes it")
eq(type(subscribedCb), "function", "the module subscribed to RGNOTE at load")
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "B", note = "Kite", author = "Zed" } })
local btext, bauthor = RG.GetAssignment("B")
eq(btext, "Kite", "an assignment received from another player updates the cache"); eq(bauthor, "Zed", "...with its real author")
local seen = {}
RG.OnAssignment(function(name, text, author) seen[#seen + 1] = name .. ":" .. text .. ":" .. author end)
subscribedCb({ type = "RGNOTE", sender = "Zed", data = { player = "B", note = "Stack", author = "Zed" } })
eq(seen[#seen], "B:Stack:Zed", "OnAssignment listeners fire on a received event")

-- ---- debuffs / buffs -----------------------------------------------------------
reset()
debuffsByUnit.raid1 = { { "Sunder Armor", "iconSA", 5, nil, 112 }, { "Curse of Weakness", "iconCW", 1, "Curse", 220 } }
buffsByUnit.raid1 = { { "Battle Shout", "iconBS", 1, nil, 0 } }
local dl, dtotal = RG.ListDebuffs("raid1", 1)
eq(#dl, 1, "ListDebuffs honours the limit"); eq(dtotal, 2, "...but reports the real total")
eq(dl[1].name, "Sunder Armor", "debuff name"); eq(dl[1].timeLeft, 12, "time left = expiration - now")
local bl = RG.ListBuffs("raid1", 5)
eq(#bl, 1, "ListBuffs"); eq(bl[1].name, "Battle Shout", "buff name"); eq(bl[1].timeLeft, nil, "no expiration = no timer")
eq(#(RG.ListDebuffs(nil, 5)), 0, "ListDebuffs nil unit")

-- ---- missing-buff indicator (personal: only what the viewer can provide) ------
reset()
missingFor.raid1 = { "Battle Shout", "Arcane Intellect" }
eq(table.concat(RG.MissingBuffsForViewer("raid1"), ","), "Battle Shout", "only the buff the viewer's own class (WARRIOR) can provide")
missingFor.raid1 = { "Arcane Intellect" }
eq(#RG.MissingBuffsForViewer("raid1"), 0, "nothing the viewer can provide -> empty")
local savedPanels = AIP.Panels; AIP.Panels = nil
eq(#RG.MissingBuffsForViewer("raid1"), 0, "gracefully empty when the Raid Management panel is absent")
AIP.Panels = savedPanels

-- ---- quick-cast -----------------------------------------------------------------
reset()
eq((RG.AddQuickCast("Flash of Light")), true, "add ok"); eq(RG.GetQuickCast()[1], "Flash of Light", "stored")
eq((RG.AddQuickCast("flash of light")), false, "duplicate rejected (case-insensitive)")
eq((RG.AddQuickCast("Renew")), true, "second slot"); eq((RG.AddQuickCast("Regrowth")), false, "cap at MAX_QUICKCAST")
eq((RG.SetQuickCast(2, "Regrowth")), true, "replace slot 2"); eq(RG.GetQuickCast()[2], "Regrowth", "replaced")
eq((RG.SetQuickCast(2, "Flash of Light")), false, "SetQuickCast rejects a duplicate of another slot")
eq((RG.RemoveQuickCast(1)), true, "remove ok"); eq(RG.GetQuickCast()[1], "Regrowth", "later slots shift up"); eq(#RG.GetQuickCast(), 1, "one fewer")
local qcCopy = RG.GetQuickCast(); qcCopy[1] = "Hacked"
eq(RG.GetQuickCast()[1], "Regrowth", "GetQuickCast returns a copy")
eq(RG.BuildQuickCastMacro("Bob", "Flash of Light"), "/cast [target=Bob] Flash of Light", "macro built via Tank Cast")
local savedTC = AIP.TankCast; AIP.TankCast = nil
eq((RG.AddQuickCast("Renew")), false, "AddQuickCast requires Tank Cast")
eq(RG.BuildQuickCastMacro("Bob", "X"), nil, "BuildQuickCastMacro requires Tank Cast")
AIP.TankCast = savedTC

-- ---- extended menus -------------------------------------------------------------
reset()
raid = { { name = "Me", rank = 2, group = 1, class = "Paladin" }, { name = "Grunt", rank = 0, group = 2, class = "Warrior" } }
local snapMember = RG.Snapshot()
local mm = RG.MemberMenu(snapMember, snapMember.members[2], false)
eq(findId(mm, "focus") ~= nil, true, "menu: Set Focus present for others")
eq(findId(mm, "note_private") ~= nil, true, "menu: private note present")
eq(findId(mm, "note_assignment"), nil, "menu: assignment note requires manage")
eq(findId(mm, "raid_icon_1"), nil, "menu: raid icons require manage")
isOfficerFlag = true
local snapMgr = RG.Snapshot()
local mmMgr = RG.MemberMenu(snapMgr, snapMgr.members[2], false)
eq(findId(mmMgr, "note_assignment") ~= nil, true, "manager menu: assignment note present")
eq(findId(mmMgr, "raid_icon_8").text, "Set Raid Icon: Skull", "manager menu: raid icon rows are labelled")
eq(findId(mmMgr, "raid_icon_clear") ~= nil, true, "manager menu: clear raid icon present")
eq(findId(mmMgr, "move_2").enabled, false, "move to the member's own group is still disabled")
RG.SetGroupLocked(true)
local mmLocked = RG.MemberMenu(snapMgr, snapMgr.members[2], false)
eq(findId(mmLocked, "move_3").enabled, false, "move rows disabled while group positions are locked")
RG.SetGroupLocked(false)

local wm = RG.WindowMenu(snapMember, false)
eq(findId(wm, "group_lock"), nil, "window menu: group-lock control requires manage")
eq(findId(wm, "quickcast_config") ~= nil, true, "window menu: quick-cast config always offered")
local wmMgr = RG.WindowMenu(snapMgr, false)
eq(findId(wmMgr, "group_lock").text, "Lock Group Positions", "window menu: group-lock label")
RG.SetGroupLocked(true)
eq(findId(RG.WindowMenu(snapMgr, false), "group_lock").text, "Unlock Group Positions", "window menu: group-lock label flips")
RG.SetGroupLocked(false)

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `luajit tools/tests/raidgroups_spec.lua`
Expected: FAIL - `attempt to call field 'IsGroupLocked' (a nil value)` (or similar, for the first new function referenced).

- [ ] **Step 3: Add the group-position lock**

In `AutoInvitePlus/modules/RaidGroups.lua`, Edit:

old_string:
```
function RG.ToggleLocked()
    RG.SetLocked(not RG.IsLocked())
    return RG.IsLocked()
end
```
new_string:
```
function RG.ToggleLocked()
    RG.SetLocked(not RG.IsLocked())
    return RG.IsLocked()
end

function RG.IsGroupLocked()
    local c = cfg()
    return (c and c.groupLocked) and true or false
end

function RG.SetGroupLocked(on)
    local c = cfg()
    if not c then return false end
    c.groupLocked = on and true or false
    return true
end

-- Manager-only: this protects a manager from their OWN mis-drags, so only a
-- manager may turn it on or off.
function RG.ToggleGroupLocked(snap)
    if not (snap and snap.canManage) then
        return false, "You must be raid leader or assistant to lock group positions."
    end
    RG.SetGroupLocked(not RG.IsGroupLocked())
    return true, RG.IsGroupLocked()
end
```

- [ ] **Step 4: Wire the group lock into PlanMove**

In `AutoInvitePlus/modules/RaidGroups.lua`, Edit:

old_string:
```
function RG.PlanMove(snap, fromName, target)
    if not (snap.mode == "raid" and snap.canManage) then
        return nil, "You must be raid leader or assistant to move players."
    end
    local mover = findByName(snap, fromName)
```
new_string:
```
function RG.PlanMove(snap, fromName, target)
    if not (snap.mode == "raid" and snap.canManage) then
        return nil, "You must be raid leader or assistant to move players."
    end
    if RG.IsGroupLocked() then
        return nil, "Group positions are locked."
    end
    local mover = findByName(snap, fromName)
```

- [ ] **Step 5: Add raid target icons, notes/assignments, buffs/debuffs, quick-cast**

In `AutoInvitePlus/modules/RaidGroups.lua`, Edit (insert everything between MOVE PLANNING and MENUS):

old_string:
```
function RG.ExecMove(plan)
    if not plan then return end
    if plan.op == "set" and SetRaidSubgroup then
        SetRaidSubgroup(plan.index, plan.group)
    elseif plan.op == "swap" and SwapRaidSubgroup then
        SwapRaidSubgroup(plan.index1, plan.index2)
    end
end

-- ============================================================================
-- MENUS
-- ============================================================================
```
new_string:
```
function RG.ExecMove(plan)
    if not plan then return end
    if plan.op == "set" and SetRaidSubgroup then
        SetRaidSubgroup(plan.index, plan.group)
    elseif plan.op == "swap" and SwapRaidSubgroup then
        SwapRaidSubgroup(plan.index1, plan.index2)
    end
end

-- ============================================================================
-- RAID TARGET ICONS (interface-only: the server already syncs these to everyone;
-- no DataBus involved - see the spec's governing rule. Reading is unrestricted;
-- setting requires a manager.)
-- ============================================================================

RG.RAID_ICONS = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

function RG.GetRaidIcon(snap, name)
    local m = findByName(snap, name)
    if not m or not m.unit then return nil end
    if not GetRaidTargetIndex then return 0 end
    return GetRaidTargetIndex(m.unit) or 0
end

-- index 0 clears the icon; 1-8 selects one of RG.RAID_ICONS.
function RG.SetRaidIcon(snap, name, index)
    if not (snap.mode == "raid" and snap.canManage) then
        return false, "You must be raid leader or assistant to set raid icons."
    end
    local m = findByName(snap, name)
    if not m then return false, "Unknown player." end
    if type(index) ~= "number" or index < 0 or index > 8 then return false, "Bad icon." end
    if SetRaidTarget then SetRaidTarget(m.unit, index) end
    return true
end

-- ============================================================================
-- NOTES (private, local only) AND ASSIGNMENTS (shared, manager-set, broadcast over
-- DataBus - the ONE piece of information here with no native interface equivalent;
-- see the spec's governing rule). Assignments are never persisted: they live only
-- as long as this session's DataBus event cache would, exactly like a PING/LFM.
-- ============================================================================

local MAX_NOTE_LEN = 60

local function sanitizeNote(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("%c", " "):gsub("%s+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    if #text > MAX_NOTE_LEN then text = text:sub(1, MAX_NOTE_LEN) end
    return text
end

function RG.GetNote(name)
    local c = cfg()
    if not c or type(name) ~= "string" or name == "" then return "" end
    if type(c.notes) ~= "table" then c.notes = {} end
    return c.notes[name:lower()] or ""
end

function RG.SetNote(name, text)
    local c = cfg()
    if not c then return false, "Settings are not loaded yet." end
    if type(name) ~= "string" or name == "" then return false, "Unknown player." end
    if type(c.notes) ~= "table" then c.notes = {} end
    local clean = sanitizeNote(text)
    c.notes[name:lower()] = (clean ~= "") and clean or nil
    RG.Changed()
    return true
end

RG.assignments = RG.assignments or {}   -- [lowerName] = {text, author, time}
local assignmentListeners = {}
function RG.OnAssignment(fn) assignmentListeners[#assignmentListeners + 1] = fn end
local function fireAssignment(name, text, author)
    for _, fn in ipairs(assignmentListeners) do pcall(fn, name, text, author) end
end

function RG.GetAssignment(name)
    if type(name) ~= "string" then return "", nil end
    local a = RG.assignments[name:lower()]
    if not a then return "", nil end
    return a.text, a.author
end

-- Manager-set only; broadcasts to the raid's other AIP users. Updates the LOCAL
-- cache immediately - DataBus never echoes a broadcast back to its own sender, so
-- without this the setter would never see their own assignment appear.
function RG.SetAssignment(snap, name, text)
    if not (snap.mode == "raid" and snap.canManage) then
        return false, "You must be raid leader or assistant to set an assignment."
    end
    local m = findByName(snap, name)
    if not m then return false, "Unknown player." end
    local clean = sanitizeNote(text)
    local author = (UnitName and UnitName("player")) or "?"
    RG.assignments[m.name:lower()] = (clean ~= "")
        and { text = clean, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAssignment(m.name, clean, author)
    if AIP.DataBus and AIP.DataBus.CreateEvent and AIP.DataBus.Broadcast then
        AIP.DataBus.Broadcast(AIP.DataBus.CreateEvent("RGNOTE", { player = m.name, note = clean, author = author }))
    end
    return true
end

-- The DataBus subscriber: someone else's assignment arrived.
function RG.OnAssignmentEvent(event)
    local data = event and event.data
    if not data or not data.player then return end
    local text = sanitizeNote(data.note)
    local author = data.author or event.sender or "?"
    RG.assignments[data.player:lower()] = (text ~= "")
        and { text = text, author = author, time = (GetTime and GetTime()) or 0 } or nil
    fireAssignment(data.player, text, author)
end

-- ============================================================================
-- BUFFS / DEBUFFS / MISSING-BUFF INDICATOR (interface-only: UnitBuff/UnitDebuff
-- plus the existing buff-coverage engine in the Raid Management panel; guarded,
-- independent scan - see the spec's reuse-boundary decision)
-- ============================================================================

local function scanAuras(unit, fn, limit)
    local out, total = {}, 0
    if not unit or not fn then return out, 0 end
    limit = limit or 12
    for i = 1, 40 do
        local name, _, icon, count, dtype, _, expires = fn(unit, i)
        if not name then break end
        total = total + 1
        if #out < limit then
            local left = (type(expires) == "number" and expires > 0) and (expires - ((GetTime and GetTime()) or 0)) or nil
            out[#out + 1] = { name = name, icon = icon, count = count, dtype = dtype, timeLeft = left }
        end
    end
    return out, total
end

function RG.ListDebuffs(unit, limit) return scanAuras(unit, UnitDebuff, limit) end
function RG.ListBuffs(unit, limit) return scanAuras(unit, UnitBuff, limit) end

-- Raid buffs missing from this unit that YOUR class can provide - not "someone is
-- missing something" in general, only what is personally actionable for you.
function RG.MissingBuffsForViewer(unit)
    local Panel = AIP.Panels and AIP.Panels.RaidMgmt
    if not (Panel and Panel.CheckUnitBuffs and Panel.ClassBuffs) then return {} end
    local myClass
    if UnitClass then local _, c = UnitClass("player"); myClass = c end
    local canProvide = myClass and Panel.ClassBuffs[myClass]
    if not canProvide then return {} end
    local mine = {}
    for _, b in ipairs(canProvide) do mine[b.buffName] = true end
    local result = Panel.CheckUnitBuffs(unit)
    local missing = (result and result.missingBuffs) or {}
    local out = {}
    for _, name in ipairs(missing) do
        if mine[name] then out[#out + 1] = name end
    end
    return out
end

-- ============================================================================
-- QUICK-CAST (click-to-cast buffs/heals on ANY cell; a thin wrapper around Tank
-- Cast's existing spell/item engine - see the spec's reuse-boundary decision.
-- Requires AIP.TankCast; degrades to a clear error message without it.)
-- ============================================================================

RG.MAX_QUICKCAST = 2

local function tcRequired()
    return AIP.TankCast and AIP.TankCast.ParseSpellInput and AIP.TankCast.BuildMacro
end

function RG.GetQuickCast()
    local c = cfg()
    local list = (c and c.quickCast) or {}
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
end

local function qcHas(list, clean, skip)
    local l = clean:lower()
    for k, v in ipairs(list) do if k ~= skip and v:lower() == l then return true end end
    return false
end

function RG.AddQuickCast(text)
    if not tcRequired() then return false, "Tank Cast module is required for quick-cast." end
    local c = cfg()
    if not c then return false, "Settings are not loaded yet." end
    if type(c.quickCast) ~= "table" then c.quickCast = {} end
    local clean = AIP.TankCast.ParseSpellInput(text)
    if clean == "" then return false, "Enter a spell or item name." end
    if #c.quickCast >= RG.MAX_QUICKCAST then return false, "You already have " .. RG.MAX_QUICKCAST .. " quick-cast slots." end
    if qcHas(c.quickCast, clean) then return false, "Already a quick-cast slot." end
    c.quickCast[#c.quickCast + 1] = clean
    RG.Changed()
    return true
end

function RG.SetQuickCast(i, text)
    if not tcRequired() then return false, "Tank Cast module is required for quick-cast." end
    local c = cfg()
    if not c or type(c.quickCast) ~= "table" or not c.quickCast[i] then return false, "Bad slot." end
    local clean = AIP.TankCast.ParseSpellInput(text)
    if clean == "" then return false, "Enter a spell or item name." end
    if qcHas(c.quickCast, clean, i) then return false, "Already a quick-cast slot." end
    c.quickCast[i] = clean
    RG.Changed()
    return true
end

function RG.RemoveQuickCast(i)
    local c = cfg()
    if not c or type(c.quickCast) ~= "table" or not c.quickCast[i] then return false, "Bad slot." end
    table.remove(c.quickCast, i)
    RG.Changed()
    return true
end

function RG.BuildQuickCastMacro(name, spellText)
    if not tcRequired() then return nil end
    return AIP.TankCast.BuildMacro(name, spellText)
end

-- ============================================================================
-- MENUS
-- ============================================================================
```

- [ ] **Step 6: Extend RG.MemberMenu and RG.WindowMenu**

In `AutoInvitePlus/modules/RaidGroups.lua`, Edit:

old_string:
```
    if not member.isSelf then add("whisper", "Whisper") end
    add("inspect", "Inspect")
    add("achievements", "Compare Achievements")
    if not member.isSelf then
        add("trade", "Trade")
        add("follow", "Follow")
    end
    if hasTankCast then
        add("tank_mt", "Set as Main Tank (Tank Cast)")
        add("tank_ot", "Add as Off-Tank (Tank Cast)")
    end

    if snap.mode == "raid" and snap.canManage then
        add("set_mt", "Set as Main Tank")
        add("clear_mt", "Clear Main Tank")
        add("set_ma", "Set as Main Assist")
        add("clear_ma", "Clear Main Assist")
        for g = 1, RG.MAX_GROUPS do
            add("move_" .. g, "Move to Group " .. g, g ~= member.group and (snap.counts[g] or 0) < RG.GROUP_SIZE)
        end
        if snap.isLeader and not member.isSelf then
```
new_string:
```
    if not member.isSelf then add("whisper", "Whisper") end
    add("inspect", "Inspect")
    add("achievements", "Compare Achievements")
    if not member.isSelf then
        add("trade", "Trade")
        add("follow", "Follow")
        add("focus", "Set Focus")
        add("clear_focus", "Clear Focus")
        add("add_friend", "Add Friend")
    end
    add("note_private", "Set Note...")
    if hasTankCast then
        add("tank_mt", "Set as Main Tank (Tank Cast)")
        add("tank_ot", "Add as Off-Tank (Tank Cast)")
    end

    if snap.mode == "raid" and snap.canManage then
        add("note_assignment", "Set Assignment...")
        for i = 1, #RG.RAID_ICONS do
            add("raid_icon_" .. i, "Set Raid Icon: " .. RG.RAID_ICONS[i])
        end
        add("raid_icon_clear", "Clear Raid Icon")
        add("set_mt", "Set as Main Tank")
        add("clear_mt", "Clear Main Tank")
        add("set_ma", "Set as Main Assist")
        add("clear_ma", "Clear Main Assist")
        for g = 1, RG.MAX_GROUPS do
            add("move_" .. g, "Move to Group " .. g,
                g ~= member.group and (snap.counts[g] or 0) < RG.GROUP_SIZE and not RG.IsGroupLocked())
        end
        if snap.isLeader and not member.isSelf then
```

Then Edit:

old_string:
```
function RG.WindowMenu(snap, locked)
    local list = {}
    list[#list + 1] = { id = "lock", text = locked and "Unlock position" or "Lock position", enabled = true }
    if snap.canManage then
        list[#list + 1] = { id = "ready_check", text = "Ready Check", enabled = true }
    end
    if snap.isLeader then
```
new_string:
```
function RG.WindowMenu(snap, locked)
    local list = {}
    list[#list + 1] = { id = "lock", text = locked and "Unlock position" or "Lock position", enabled = true }
    if snap.canManage then
        list[#list + 1] = { id = "group_lock", text = RG.IsGroupLocked() and "Unlock Group Positions" or "Lock Group Positions", enabled = true }
        list[#list + 1] = { id = "ready_check", text = "Ready Check", enabled = true }
    end
    list[#list + 1] = { id = "quickcast_config", text = "Configure Quick-Cast...", enabled = true }
    if snap.isLeader then
```

- [ ] **Step 7: Wire the group-lock toggle and note edits into doWindowAction... (Task 2 handles this; Step 7 is the module-side event registration only)**

In `AutoInvitePlus/modules/RaidGroups.lua`, Edit (subscribe to the new DataBus event alongside the existing roster events):

old_string:
```
if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    local E = AIP.Utils.Events
    local function onRoster() RG.Changed() end
    E.Register("RAID_ROSTER_UPDATE", onRoster, "RaidGroups")
    E.Register("PARTY_MEMBERS_CHANGED", onRoster, "RaidGroups")
    E.Register("PARTY_LEADER_CHANGED", onRoster, "RaidGroups")
    E.Register("PLAYER_ENTERING_WORLD", onRoster, "RaidGroups")
    E.Register("PLAYER_REGEN_ENABLED", function() if RG.dirty then RG.Changed() end end, "RaidGroups")
end
```
new_string:
```
if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    local E = AIP.Utils.Events
    local function onRoster() RG.Changed() end
    E.Register("RAID_ROSTER_UPDATE", onRoster, "RaidGroups")
    E.Register("PARTY_MEMBERS_CHANGED", onRoster, "RaidGroups")
    E.Register("PARTY_LEADER_CHANGED", onRoster, "RaidGroups")
    E.Register("PLAYER_ENTERING_WORLD", onRoster, "RaidGroups")
    E.Register("PLAYER_REGEN_ENABLED", function() if RG.dirty then RG.Changed() end end, "RaidGroups")
end

if AIP.DataBus and AIP.DataBus.Subscribe then
    AIP.DataBus.Subscribe("RGNOTE", RG.OnAssignmentEvent, "RaidGroups")
end
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `luajit tools/tests/raidgroups_spec.lua`
Expected: `N passed, 0 failed`.

- [ ] **Step 9: Core.lua defaults**

In `AutoInvitePlus/core/Core.lua`, Edit:

old_string:
```
    raidGroups = {
        shown = false,
        locked = false,
        pos = nil,                  -- {point, relPoint, x, y}
    },
```
new_string:
```
    raidGroups = {
        shown = false,
        locked = false,             -- window position locked
        groupLocked = false,        -- group positions locked (manager safety toggle)
        notes = {},                 -- private per-player notes, [lowercaseName] = "text"
        quickCast = {},             -- up to RG.MAX_QUICKCAST spell/item names
        pos = nil,                  -- {point, relPoint, x, y}
    },
```

- [ ] **Step 10: DataBus event type**

In `AutoInvitePlus/core/DataBus.lua`, Edit:

old_string:
```
    -- PONG: Response to ping
    PONG = {
        id = "PONG",
        name = "Presence Response",
        fields = {
            "version",      -- string: addon version
        },
    },

    -- GEAR: a player's own gear-readiness summary (so peers don't inspect them)
```
new_string:
```
    -- PONG: Response to ping
    PONG = {
        id = "PONG",
        name = "Presence Response",
        fields = {
            "version",      -- string: addon version
        },
    },

    -- RGNOTE: Raid Groups manager-set assignment note on a player (the one field in
    -- the Raid Groups feature with no native interface equivalent - see its spec)
    RGNOTE = {
        id = "RGNOTE",
        name = "Raid Groups Assignment",
        fields = {
            "player",       -- string: the player this assignment is about
            "note",         -- string: the assignment text ("" clears it)
            "author",       -- string: who set it
        },
    },

    -- GEAR: a player's own gear-readiness summary (so peers don't inspect them)
```

- [ ] **Step 11: Checkpoint**

Syntax-check `AutoInvitePlus/modules/RaidGroups.lua`, `AutoInvitePlus/core/Core.lua`, `AutoInvitePlus/core/DataBus.lua`, `tools/tests/raidgroups_spec.lua`. Run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua` (regression).
Expected: all `OK`; both suites `0 failed`. **Do not commit.**

---

### Task 2: Window UI - cell layout, tooltip, menus, popups, toast bubble

**Files:**
- Modify: `AutoInvitePlus/ui/RaidGroupsWindow.lua`

**Interfaces:**
- Consumes: everything added in Task 1.
- Produces: no new public interface - this task wires Task 1's logic into the window.

- [ ] **Step 1: Grow the cell and add its new visual elements**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit (constants - two-row cells: name+icons row, then a debuff-icon row):

old_string:
```
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD, HDR_H = 4, 16
local CELL_W, CELL_H, CELL_GAP = 76, 15, 1
local GROUP_GAP = 4
local DIMS = { cellW = CELL_W, cellH = CELL_H, gap = CELL_GAP, groupGap = GROUP_GAP, pad = PAD }
```
new_string:
```
local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD, HDR_H = 4, 16
-- Two rows per cell: row 1 = raid-icon + rank + name + quick-cast icons; row 2 = up
-- to 4 small debuff icons. This is a first-pass layout (see the plan's Global
-- Constraints note) - expect a live-feedback round after this ships.
local CELL_W = 92
local ROW1_H, ROW2_H, ROW_GAP = 11, 10, 1
local CELL_H, CELL_GAP = ROW1_H + ROW_GAP + ROW2_H, 2
local GROUP_GAP = 4
local DIMS = { cellW = CELL_W, cellH = CELL_H, gap = CELL_GAP, groupGap = GROUP_GAP, pad = PAD }
local MAX_DEBUFF_ICONS = 4
local DEBUFF_ICON_SZ = ROW2_H
local QC_ICON_SZ = ROW1_H
```

- [ ] **Step 2: Rewrite acquireCell to build the new elements**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit:

old_string:
```
local function acquireCell(index)
    local cell = cellPool[index]
    if cell then return cell end
    cell = CreateFrame("Button", "AIPRaidGroupsCell" .. index, win, "SecureActionButtonTemplate")
    cell:SetSize(CELL_W, CELL_H)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell:Hide()

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(); cell.bg:SetTexture(0.5, 0.5, 0.5, 0.85)
    cell.nameFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    cell.nameFS:SetPoint("LEFT", 3, 0); cell.nameFS:SetPoint("RIGHT", -3, 0); cell.nameFS:SetJustifyH("LEFT")
    cell.overlay = cell:CreateTexture(nil, "OVERLAY")
    cell.overlay:SetAllPoints(); cell.overlay:SetTexture(0, 0, 0, 0.55); cell.overlay:Hide()
    cell.targetBorder = CreateFrame("Frame", nil, cell)
    cell.targetBorder:SetAllPoints()
    cell.targetBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    cell.targetBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
    cell.targetBorder:Hide()
    cell.rankFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 8, "OUTLINE")
    cell.rankFS:SetPoint("TOPLEFT", 1, -1)

    cell:HookScript("OnClick", function(self, button)
        if button == "RightButton" then openMemberMenu(self.member) end
    end)
    cell:SetScript("OnDragStart", function(self) if self.member then beginDrag(self) end end)
    cell:SetScript("OnDragStop", function() endDrag() end)
    cell:SetScript("OnEnter", function(self)
        local m = self.member
        if not m then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = classColor(m.class)
        GameTooltip:AddLine(m.name, r, g, b)
        GameTooltip:AddLine((m.level and (m.level .. " ") or "") .. (m.class or ""), 0.8, 0.82, 0.9)
        GameTooltip:AddLine("Group " .. m.group, 0.8, 0.82, 0.9)
        if m.rank and m.rank > 0 then GameTooltip:AddLine(RG.RankLabel(m.rank), 1, 0.82, 0) end
        if m.role == "MAINTANK" then GameTooltip:AddLine("Main Tank", 0.6, 0.8, 1) end
        if m.role == "MAINASSIST" then GameTooltip:AddLine("Main Assist", 0.6, 0.8, 1) end
        if not m.online then GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6) end
        if m.dead then GameTooltip:AddLine("Dead", 0.9, 0.3, 0.3) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Click: target  |  Right-click: options", 0.7, 0.72, 0.8)
        if applied.snap and applied.snap.mode == "raid" and applied.snap.canManage then
            GameTooltip:AddLine("Drag: move to another group", 0.7, 0.72, 0.8)
        end
        GameTooltip:Show()
    end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cellPool[index] = cell
    return cell
end
```
new_string:
```
-- Extensive tooltip: identity, live buffs/debuffs, notes/assignment, hints.
local function showCellTooltip(cell)
    local m = cell.member
    if not m then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    local r, g, b = classColor(m.class)
    GameTooltip:AddLine(m.name, r, g, b)
    GameTooltip:AddLine((m.level and (m.level .. " ") or "") .. (m.class or ""), 0.8, 0.82, 0.9)
    GameTooltip:AddLine("Group " .. m.group, 0.8, 0.82, 0.9)
    if m.rank and m.rank > 0 then GameTooltip:AddLine(RG.RankLabel(m.rank), 1, 0.82, 0) end
    if m.role == "MAINTANK" then GameTooltip:AddLine("Main Tank", 0.6, 0.8, 1) end
    if m.role == "MAINASSIST" then GameTooltip:AddLine("Main Assist", 0.6, 0.8, 1) end
    if not m.online then GameTooltip:AddLine("Offline", 0.6, 0.6, 0.6) end
    if m.dead then GameTooltip:AddLine("Dead", 0.9, 0.3, 0.3) end

    if m.unit then
        local buffs, btotal = RG.ListBuffs(m.unit, 20)
        local debuffs, dtotal = RG.ListDebuffs(m.unit, 20)
        if btotal > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Buffs (" .. btotal .. ")", 0.6, 1, 0.6)
            for _, a in ipairs(buffs) do
                local icon = a.icon and ("|T" .. a.icon .. ":12|t ") or ""
                local stacks = (a.count and a.count > 1) and (" x" .. a.count) or ""
                GameTooltip:AddLine(icon .. a.name .. stacks, 0.85, 0.95, 0.85)
            end
        end
        if dtotal > 0 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Debuffs (" .. dtotal .. ")", 1, 0.6, 0.6)
            for _, a in ipairs(debuffs) do
                local c = (DebuffTypeColor and (DebuffTypeColor[a.dtype or "none"] or DebuffTypeColor["none"])) or { r = 0.8, g = 0, b = 0 }
                local icon = a.icon and ("|T" .. a.icon .. ":12|t ") or ""
                local stacks = (a.count and a.count > 1) and (" x" .. a.count) or ""
                GameTooltip:AddLine(icon .. a.name .. stacks, c.r, c.g, c.b)
            end
        end
    end

    local note = RG.GetNote(m.name)
    if note ~= "" then GameTooltip:AddLine(" "); GameTooltip:AddLine("Note: " .. note, 0.9, 0.9, 0.6, true) end
    local atext, aauthor = RG.GetAssignment(m.name)
    if atext ~= "" then GameTooltip:AddLine("Assignment: " .. atext .. " - " .. (aauthor or "?"), 1, 0.82, 0, true) end

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Click: target  |  Right-click: options", 0.7, 0.72, 0.8)
    if applied.snap and applied.snap.mode == "raid" and applied.snap.canManage then
        GameTooltip:AddLine("Drag: move to another group", 0.7, 0.72, 0.8)
    end
    GameTooltip:Show()
end

local function acquireCell(index)
    local cell = cellPool[index]
    if cell then return cell end
    cell = CreateFrame("Button", "AIPRaidGroupsCell" .. index, win, "SecureActionButtonTemplate")
    cell:SetSize(CELL_W, CELL_H)
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:RegisterForDrag("LeftButton")
    cell:Hide()

    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetAllPoints(); cell.bg:SetTexture(0.5, 0.5, 0.5, 0.85)
    cell.overlay = cell:CreateTexture(nil, "OVERLAY")
    cell.overlay:SetAllPoints(); cell.overlay:SetTexture(0, 0, 0, 0.55); cell.overlay:Hide()
    cell.targetBorder = CreateFrame("Frame", nil, cell)
    cell.targetBorder:SetAllPoints()
    cell.targetBorder:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
    cell.targetBorder:SetBackdropBorderColor(1, 0.82, 0, 1)
    cell.targetBorder:Hide()

    -- Row 1: raid icon (left) + rank tag + name (flex) + up to 2 quick-cast icons.
    cell.raidIcon = cell:CreateTexture(nil, "ARTWORK")
    cell.raidIcon:SetSize(ROW1_H, ROW1_H); cell.raidIcon:SetPoint("TOPLEFT", 1, -1)
    cell.raidIcon:Hide()
    cell.rankFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 8, "OUTLINE")
    cell.rankFS:SetPoint("TOPLEFT", cell.raidIcon, "TOPRIGHT", 1, 0)

    cell.qc = {}
    for q = 1, RG.MAX_QUICKCAST do
        local b = CreateFrame("Button", "AIPRaidGroupsQC" .. index .. "_" .. q, cell, "SecureActionButtonTemplate")
        b:SetSize(QC_ICON_SZ, QC_ICON_SZ)
        b:RegisterForClicks("LeftButtonUp")
        if q == 1 then b:SetPoint("TOPRIGHT", cell, "TOPRIGHT", -1, -1)
        else b:SetPoint("TOPRIGHT", cell.qc[q - 1], "TOPLEFT", -1, 0) end
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints(); b.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate"); b.cd:SetAllPoints(b.icon)
        b:Hide()
        b:HookScript("OnClick", function(self)
            if not self.macroSet then AIP.Print("Configure a quick-cast spell first (right-click the title bar).") end
        end)
        b:SetScript("OnEnter", function(self)
            if not self.spellText then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(self.spellText, 1, 0.82, 0)
            if cell.member then GameTooltip:AddLine("Cast on " .. cell.member.name, 1, 1, 1) end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cell.qc[q] = b
    end

    cell.nameFS = fontize(cell:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    cell.nameFS:SetPoint("LEFT", cell.rankFS, "RIGHT", 2, 0)
    cell.nameFS:SetPoint("RIGHT", cell.qc[RG.MAX_QUICKCAST], "LEFT", -2, 0)
    cell.nameFS:SetPoint("TOP", cell, "TOP", 0, -1)
    cell.nameFS:SetJustifyH("LEFT")

    -- Row 2: up to MAX_DEBUFF_ICONS small debuff icons.
    cell.debuffIcons = {}
    for d = 1, MAX_DEBUFF_ICONS do
        local t = cell:CreateTexture(nil, "ARTWORK")
        t:SetSize(DEBUFF_ICON_SZ, DEBUFF_ICON_SZ)
        t:SetTexCoord(0.1, 0.9, 0.1, 0.9)
        t:SetPoint("TOPLEFT", 1 + (d - 1) * (DEBUFF_ICON_SZ + 1), -(ROW1_H + ROW_GAP + 1))
        t:Hide()
        cell.debuffIcons[d] = t
    end

    -- Missing-buff indicator: a small dot, bottom-right.
    cell.missingDot = cell:CreateTexture(nil, "OVERLAY")
    cell.missingDot:SetSize(4, 4); cell.missingDot:SetPoint("BOTTOMRIGHT", -1, 1)
    cell.missingDot:SetTexture(1, 0.3, 0.3, 1); cell.missingDot:Hide()

    cell:HookScript("OnClick", function(self, button)
        if button == "RightButton" then openMemberMenu(self.member) end
    end)
    cell:SetScript("OnDragStart", function(self) if self.member then beginDrag(self) end end)
    cell:SetScript("OnDragStop", function() endDrag() end)
    cell:SetScript("OnEnter", function(self) showCellTooltip(self) end)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    cellPool[index] = cell
    return cell
end
```

- [ ] **Step 2: Syntax check the cell rewrite in isolation**

Run the syntax check on `AutoInvitePlus/ui/RaidGroupsWindow.lua`.
Expected: `OK`.

- [ ] **Step 3: Set the quick-cast macros and raid-icon overlay in applyStructure**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit:

old_string:
```
            if m then
                idx = idx + 1
                local cell = acquireCell(idx)
                cell.member = m
                local macro = "/target " .. (m.name:gsub("[/;%[%]|]", ""))
                cell:SetAttribute("type1", "macro")
                cell:SetAttribute("macrotext1", macro)
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", win, "TOPLEFT", gl.x + PAD, -(HDR_H + gl.y + (slot - 1) * (CELL_H + CELL_GAP)))
                cell:Show()
```
new_string:
```
            if m then
                idx = idx + 1
                local cell = acquireCell(idx)
                cell.member = m
                local macro = "/target " .. (m.name:gsub("[/;%[%]|]", ""))
                cell:SetAttribute("type1", "macro")
                cell:SetAttribute("macrotext1", macro)
                local qcSlots = RG.GetQuickCast()
                for q = 1, RG.MAX_QUICKCAST do
                    local btn, spell = cell.qc[q], qcSlots[q]
                    local qmacro = spell and RG.BuildQuickCastMacro(m.name, spell) or nil
                    btn:SetAttribute("type1", qmacro and "macro" or nil)
                    btn:SetAttribute("macrotext1", qmacro)
                    btn.macroSet = qmacro ~= nil
                    btn.spellText = spell
                    if spell then btn:Show() else btn:Hide() end
                end
                cell:ClearAllPoints()
                cell:SetPoint("TOPLEFT", win, "TOPLEFT", gl.x + PAD, -(HDR_H + gl.y + (slot - 1) * (CELL_H + CELL_GAP)))
                cell:Show()
```

Then Edit (clear quick-cast attributes on the retirement path alongside the existing cell-hide logic):

old_string:
```
    for i = idx + 1, #cellPool do
        local cell = cellPool[i]
        if cell and cell.SetAttribute then
            cell.member = nil
            cell:SetAttribute("type1", nil)
            cell:SetAttribute("macrotext1", nil)
            cell:Hide()
        end
    end
```
new_string:
```
    for i = idx + 1, #cellPool do
        local cell = cellPool[i]
        if cell and cell.SetAttribute then
            cell.member = nil
            cell:SetAttribute("type1", nil)
            cell:SetAttribute("macrotext1", nil)
            for q = 1, RG.MAX_QUICKCAST do
                local btn = cell.qc[q]
                btn:SetAttribute("type1", nil); btn:SetAttribute("macrotext1", nil)
                btn.macroSet, btn.spellText = false, nil
                btn:Hide()
            end
            cell:Hide()
        end
    end
```

- [ ] **Step 4: Populate debuff icons, raid-icon overlay, and the missing-buff dot in refreshValues**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit:

old_string:
```
refreshValues = function()
    if not win or not win:IsShown() or not applied.snap then return end
    local targetName = UnitName and UnitExists and UnitExists("target") and UnitName("target")
    for _, cell in ipairs(cellPool) do
        if cell.member then
            local m = cell.member
            cell.bg:SetTexture(classColor(m.class))
            cell.nameFS:SetText(m.name)
            -- SetShown does not exist on 3.3.5a (added in a later client) - Show()/Hide().
            if not m.online or m.dead then cell.overlay:Show() else cell.overlay:Hide() end
            cell.overlay:SetTexture(0, 0, 0, (not m.online) and 0.6 or 0.4)
            if targetName == m.name then cell.targetBorder:Show() else cell.targetBorder:Hide() end
            local tag = (m.role == "MAINTANK" and "MT") or (m.role == "MAINASSIST" and "MA") or ""
            if applied.snap.canManage and m.rank and m.rank > 0 then
                tag = (tag ~= "" and (tag .. " ") or "") .. (m.rank == 2 and "L" or "A")
            end
            cell.rankFS:SetText(tag)
        end
    end
end
```
new_string:
```
refreshValues = function()
    if not win or not win:IsShown() or not applied.snap then return end
    local targetName = UnitName and UnitExists and UnitExists("target") and UnitName("target")
    for _, cell in ipairs(cellPool) do
        if cell.member then
            local m = cell.member
            cell.bg:SetTexture(classColor(m.class))
            cell.nameFS:SetText(m.name)
            -- SetShown does not exist on 3.3.5a (added in a later client) - Show()/Hide().
            if not m.online or m.dead then cell.overlay:Show() else cell.overlay:Hide() end
            cell.overlay:SetTexture(0, 0, 0, (not m.online) and 0.6 or 0.4)
            if targetName == m.name then cell.targetBorder:Show() else cell.targetBorder:Hide() end
            local tag = (m.role == "MAINTANK" and "MT") or (m.role == "MAINASSIST" and "MA") or ""
            if applied.snap.canManage and m.rank and m.rank > 0 then
                tag = (tag ~= "" and (tag .. " ") or "") .. (m.rank == 2 and "L" or "A")
            end
            cell.rankFS:SetText(tag)

            local iconIdx = RG.GetRaidIcon(applied.snap, m.name)
            if iconIdx and iconIdx > 0 then
                cell.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
                local col, row = (iconIdx - 1) % 4, math.floor((iconIdx - 1) / 4)
                cell.raidIcon:SetTexCoord(col * 0.25, col * 0.25 + 0.25, row * 0.25, row * 0.25 + 0.25)
                cell.raidIcon:Show()
            else
                cell.raidIcon:Hide()
            end

            if m.unit then
                local debuffs = RG.ListDebuffs(m.unit, MAX_DEBUFF_ICONS)
                for d = 1, MAX_DEBUFF_ICONS do
                    local a, t = debuffs[d], cell.debuffIcons[d]
                    if a then t:SetTexture(a.icon); t:Show() else t:Hide() end
                end
                local missing = RG.MissingBuffsForViewer(m.unit)
                if #missing > 0 then cell.missingDot:Show() else cell.missingDot:Hide() end
            else
                for d = 1, MAX_DEBUFF_ICONS do cell.debuffIcons[d]:Hide() end
                cell.missingDot:Hide()
            end
        end
    end
end
```

- [ ] **Step 5: Extend doMemberAction with the new ids**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit:

old_string:
```
    elseif id == "uninvite" then
        StaticPopup_Show("AIP_RAIDGROUPS_UNINVITE", member.name, nil, member.name)
    else
        local g = id:match("^move_(%d+)$")
        if g and applied.snap then
            local plan, err = RG.PlanMove(applied.snap, member.name, { group = tonumber(g) })
            if plan then RG.ExecMove(plan) else AIP.Print(err) end
        end
    end
end
```
new_string:
```
    elseif id == "uninvite" then
        StaticPopup_Show("AIP_RAIDGROUPS_UNINVITE", member.name, nil, member.name)
    elseif id == "focus" then if FocusUnit and unit then FocusUnit(unit) end
    elseif id == "clear_focus" then if ClearFocus then ClearFocus() end
    elseif id == "add_friend" then if AddFriend then AddFriend(member.name) end
    elseif id == "note_private" then
        StaticPopup_Show("AIP_RAIDGROUPS_NOTE", member.name, nil, member.name)
    elseif id == "note_assignment" then
        StaticPopup_Show("AIP_RAIDGROUPS_ASSIGNMENT", member.name, nil, member.name)
    elseif id == "raid_icon_clear" then
        if applied.snap then
            local ok, err = RG.SetRaidIcon(applied.snap, member.name, 0)
            if not ok then AIP.Print(err) end
        end
    else
        local iconIdx = id:match("^raid_icon_(%d+)$")
        if iconIdx and applied.snap then
            local ok, err = RG.SetRaidIcon(applied.snap, member.name, tonumber(iconIdx))
            if not ok then AIP.Print(err) end
            return
        end
        local g = id:match("^move_(%d+)$")
        if g and applied.snap then
            local plan, err = RG.PlanMove(applied.snap, member.name, { group = tonumber(g) })
            if plan then RG.ExecMove(plan) else AIP.Print(err) end
        end
    end
end
```

- [ ] **Step 6: Extend doWindowAction and add the new popups**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit:

old_string:
```
local function doWindowAction(id)
    if id == "lock" then RG.ToggleLocked()
    elseif id == "ready_check" then if DoReadyCheck then DoReadyCheck() end
    elseif id == "convert" then
        if not applied.snap then return end
        if applied.snap.mode == "raid" and ConvertToParty then ConvertToParty()
        elseif applied.snap.mode == "party" and ConvertToRaid then ConvertToRaid() end
    elseif id == "close" then RG.HideWindow() end
end
```
new_string:
```
local function doWindowAction(id)
    if id == "lock" then RG.ToggleLocked()
    elseif id == "group_lock" then
        if applied.snap then
            local ok, err = RG.ToggleGroupLocked(applied.snap)
            if not ok then AIP.Print(err) end
        end
    elseif id == "ready_check" then if DoReadyCheck then DoReadyCheck() end
    elseif id == "quickcast_config" then RG.ShowQuickCastConfig(1)
    elseif id == "convert" then
        if not applied.snap then return end
        if applied.snap.mode == "raid" and ConvertToParty then ConvertToParty()
        elseif applied.snap.mode == "party" and ConvertToRaid then ConvertToRaid() end
    elseif id == "close" then RG.HideWindow() end
end

-- Configures RG.MAX_QUICKCAST slots one at a time, chaining to the next slot's
-- popup on Accept so the whole config is a couple of quick prompts.
function RG.ShowQuickCastConfig(slot)
    if slot > RG.MAX_QUICKCAST then return end
    local current = RG.GetQuickCast()[slot] or ""
    StaticPopup_Show("AIP_RAIDGROUPS_QUICKCAST", tostring(slot), nil, { slot = slot, current = current })
end
```

Then Edit (add the three new popups next to the existing uninvite one):

old_string:
```
-- text_arg1/data are both the player's name so the "Remove %s" formatting and the
-- OnAccept handler agree even if only one of them is populated on this client.
StaticPopupDialogs["AIP_RAIDGROUPS_UNINVITE"] = {
    text = "Remove %s from the raid?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self, data)
        local name = data or (self and self.data)
        if name and UninviteUnit then UninviteUnit(name) end
    end,
}
```
new_string:
```
-- text_arg1/data are both the player's name so the "Remove %s" formatting and the
-- OnAccept handler agree even if only one of them is populated on this client.
StaticPopupDialogs["AIP_RAIDGROUPS_UNINVITE"] = {
    text = "Remove %s from the raid?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self, data)
        local name = data or (self and self.data)
        if name and UninviteUnit then UninviteUnit(name) end
    end,
}

StaticPopupDialogs["AIP_RAIDGROUPS_NOTE"] = {
    text = "Note for %s:",
    button1 = OKAY, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local name = data or self.data
        self.editBox:SetText(name and RG.GetNote(name) or "")
        self.editBox:HighlightText()
    end,
    OnAccept = function(self, data)
        local name = data or self.data
        if not name then return end
        local ok, err = RG.SetNote(name, self.editBox:GetText())
        if not ok then AIP.Print(err) end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():GetButton1():Click() end,
}

StaticPopupDialogs["AIP_RAIDGROUPS_ASSIGNMENT"] = {
    text = "Assignment for %s (shared with the raid):",
    button1 = OKAY, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local name = data or self.data
        self.editBox:SetText(name and (RG.GetAssignment(name)) or "")
        self.editBox:HighlightText()
    end,
    OnAccept = function(self, data)
        local name = data or self.data
        if not (name and applied.snap) then return end
        local ok, err = RG.SetAssignment(applied.snap, name, self.editBox:GetText())
        if not ok then AIP.Print(err) end
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():GetButton1():Click() end,
}

StaticPopupDialogs["AIP_RAIDGROUPS_QUICKCAST"] = {
    text = "Quick-cast slot %s (spell or item name; blank to clear):",
    button1 = OKAY, button2 = CANCEL, hasEditBox = true, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        self.editBox:SetText((data and data.current) or "")
        self.editBox:HighlightText()
    end,
    OnAccept = function(self, data)
        if not data then return end
        local text = self.editBox:GetText()
        local ok, err
        if text == "" then ok, err = RG.RemoveQuickCast(data.slot)
        elseif RG.GetQuickCast()[data.slot] then ok, err = RG.SetQuickCast(data.slot, text)
        else ok, err = RG.AddQuickCast(text) end
        if not ok and err then AIP.Print(err) end
        RG.ShowQuickCastConfig(data.slot + 1)
    end,
    EditBoxOnEnterPressed = function(self) self:GetParent():GetButton1():Click() end,
}
```

- [ ] **Step 7: The toast bubble**

In `AutoInvitePlus/ui/RaidGroupsWindow.lua`, Edit (add near the bottom, right before the final `PLAYER_LOGIN`/`PLAYER_REGEN_ENABLED` event block):

old_string:
```
if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function() if pendingInit then initWindow() end end, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_TARGET_CHANGED", function() refreshValues() end, "RaidGroupsUI")
end
```
new_string:
```
-- ============================================================================
-- TOAST BUBBLE (assignments) - a standalone, non-secure frame. Never parented to
-- the protected window, so it is safe to create/show/hide even in combat.
-- ============================================================================

local bubble
local function ensureBubble()
    if bubble then return bubble end
    bubble = CreateFrame("Frame", "AIPRaidGroupsBubble", UIParent)
    bubble:SetSize(220, 24)
    skinPanel(bubble, 0.95)
    bubble.fs = fontize(bubble:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    bubble.fs:SetPoint("CENTER"); bubble.fs:SetJustifyH("CENTER")
    bubble:Hide()
    return bubble
end

function RG.ShowBubble(text)
    ensureBubble()
    bubble.fs:SetText(text)
    if win and win:IsShown() then
        bubble:ClearAllPoints(); bubble:SetPoint("TOP", win, "BOTTOM", 0, -4)
    else
        bubble:ClearAllPoints(); bubble:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end
    if AIP.UI and AIP.UI.FadeIn then AIP.UI.FadeIn(bubble, 0.15, 1) else bubble:Show() end
    bubble.hideAt = ((GetTime and GetTime()) or 0) + 3
    bubble:SetScript("OnUpdate", function(self)
        if ((GetTime and GetTime()) or 0) >= self.hideAt then
            self:SetScript("OnUpdate", nil)
            if AIP.UI and AIP.UI.FadeOut then AIP.UI.FadeOut(self, 0.4, true) else self:Hide() end
        end
    end)
end

RG.OnAssignment(function(name, text, author)
    if text == "" then return end   -- a clear is silent; only a new assignment toasts
    RG.ShowBubble(author .. ": " .. text)
end)

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function() if pendingInit then initWindow() end end, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_TARGET_CHANGED", function() refreshValues() end, "RaidGroupsUI")
end
```

- [ ] **Step 8: Syntax check + regression**

Run the syntax check on `AutoInvitePlus/ui/RaidGroupsWindow.lua`. Run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua`.
Expected: `OK`; both suites `0 failed` (this task touches only presentation, so the logic suites should be unaffected - if either regresses, something in Task 2 broke module load order or shadowed a Task 1 name).

**Do not commit.**

---

### Task 3: Docs, deploy, live verification, final review

**Files:**
- Modify: `AutoInvitePlus/CLAUDE.md` (extend the `RaidGroups` bullet)

- [ ] **Step 1: Document the extension**

In `AutoInvitePlus/CLAUDE.md`, find the `RaidGroups` bullet (added by the base plan) and append, inside the same bullet, after its existing sentence about combat rules and before the final "Opened from..." sentence:

Add this text (append, do not remove anything): "Extended with: raid target icons (`RG.RAID_ICONS`, interface-only - `GetRaidTargetIndex`/`SetRaidTarget`, manager-only to set); private notes (`RG.GetNote`/`SetNote`, local, persisted) and manager-broadcast assignments (`RG.SetAssignment`/`OnAssignmentEvent`, the ONE thing here that goes over DataBus - a new `RGNOTE` event type in `core/DataBus.lua` - because there is no native equivalent; a toast pops from the window's title on receipt); a group-position lock (`RG.IsGroupLocked`, separate from the window-position lock, blocks drags and \"Move to Group N\"); visible debuff icons plus an extensive buff/debuff/note/assignment tooltip (`RG.ListDebuffs`/`ListBuffs`, an independent scan - does not depend on Tank Cast, unlike quick-cast below); a personal missing-raid-buff dot (`RG.MissingBuffsForViewer`, reuses `AIP.Panels.RaidMgmt.CheckUnitBuffs`/`ClassBuffs`, filtered to what the viewer's own class can provide); and click-to-cast quick-cast slots (`RG.MAX_QUICKCAST`, `RG.AddQuickCast`/`GetQuickCast`/`BuildQuickCastMacro` - a thin wrapper around `AIP.TankCast`'s spell/item engine, degrading to a clear error message if Tank Cast is absent)."

- [ ] **Step 2: Syntax check + full regression**

Run the syntax check on every touched file: `AutoInvitePlus/modules/RaidGroups.lua`, `AutoInvitePlus/ui/RaidGroupsWindow.lua`, `AutoInvitePlus/core/Core.lua`, `AutoInvitePlus/core/DataBus.lua`, `tools/tests/raidgroups_spec.lua`.
Run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua`.
Expected: all `OK`; both suites `0 failed`.

- [ ] **Step 3: Deploy**

Run the live loop (`Sync-Addon`, `/reload` - no new files, so no client restart needed). Confirm via the harness that the file hashes on the client match the repo (as in every prior round).

- [ ] **Step 4: Live checks (solo/party; note each result)**

1. Open the window; confirm the taller two-row cells render without error (`/console scriptErrors 1`); screenshot and look at the actual pixel layout - this is the first live look at Task 2's first-pass numbers (widen/narrow/reposition anything that looks wrong before calling this done).
2. Right-click your own cell: confirm Set Focus/Clear Focus/Add Friend/Set Note/Inspect/Achievements appear (not Whisper/Trade/Follow, since it's your own row); set a private note, hover, confirm "Note: ..." appears in the tooltip.
3. Right-click the title bar: confirm "Configure Quick-Cast..." opens, set a self-castable spell for slot 1, Enter/Accept, confirm it chains to slot 2's prompt; leave slot 2 blank; confirm a quick-cast icon appears on your own cell and casts correctly when clicked.
4. Solo, raid icon and assignment/group-lock manager rows are correctly ABSENT (not a manager outside a raid) - confirm they don't appear.
5. If a debuff is present on yourself (self-inflict a testable one, or note best-effort if none is available), confirm its icon renders in row 2 and the tooltip lists it under "Debuffs".
6. `/reload`: confirm the private note and quick-cast slots persisted; confirm the group-lock flag does NOT persist as "on" if it was never set (default false).
Expected: no Lua errors at any step.

**Needs a real raid / second player (report as not live-verified if unavailable):** raid icon visibility and setting; another player receiving your assignment and their toast firing; the missing-buff dot actually lighting up on a real undersupplied raid member; group-lock actually blocking a drag with other real members present; the quick-cast icon casting on someone other than yourself.

- [ ] **Step 5: Final whole-branch review**

Dispatch a fresh reviewer on the most capable model (`Agent`, `model: "fable"`) with: this plan and both specs (base + extended), the touched-file list, this plan's **Review Focus** section verbatim, and the instruction to be read-only and rank findings Critical/Important/Minor with a concrete failure scenario - checking especially: the DataBus event's field whitelist/serialisation (does `RGNOTE`'s free-text `note` field survive `DB.Serialize`'s escaping intact, including a name or note containing the wire format's own delimiter characters?), combat-lockdown correctness of the new quick-cast secure buttons (created inside the existing `acquireCell`, which is already gated - confirm nothing new bypasses that gate), the assignment cache's memory growth over a long raid (does anything ever prune `RG.assignments` the way DataBus prunes its own event cache?), and whether `note`/`author` sanitisation before broadcast is sufficient to stop one player's assignment text from breaking another player's addon-message parser. Re-grade its findings by effect; fix Critical/Important with a test where headless-testable (or a live check otherwise); ledger Minors as deferred in the final message.

- [ ] **Step 6: Final report**

Summarise: files changed, what was live-verified vs not (see the "needs a real raid" list above), the rulings made, the deferred minors, and that nothing is committed (offer to commit).
