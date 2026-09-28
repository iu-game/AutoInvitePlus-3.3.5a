# Raid Groups Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A compact floating "Raid Groups" window listing everyone in the player's raid/party as class-coloured name cells grouped by subgroup, click-to-target, with full manager tools (drag/drop between groups, promote/demote/kick, MT/MA, ready check, convert) for the raid leader and assistants - toggled from the main window's consolidated "..." menu and the minimap (Shift-click + quick menu), never duplicating an entry between the two menus.

**Architecture:** `modules/RaidGroups.lua` (`AIP.RaidGroups`, "RG": headless roster snapshot, layout math, move planner, menu models - unit-tested) + `ui/RaidGroupsWindow.lua` (presentation, reusing `AIP.TankCast.SkinPanel/SkinHeader/CloseButton/Fontize` and the secure-button/combat-lockdown conventions from Tank Cast). `ui/CentralGUI.lua` is edited to consolidate its title bar into the existing "..." menu (always shown, both views) and to add every new window toggle to the minimap's right-click menu in new, non-duplicating sections.

**Tech Stack:** Lua 5.1, WoW 3.3.5a API, LuaJIT for headless tests, `luaparse` for syntax checks.

**Spec:** `docs/superpowers/specs/2026-09-27-raid-groups-window-design.md` (its "Title bar consolidation" and "Minimap quick menu" passages in section 4 are the source of truth for Task 3).

## Global Constraints

- Lua 5.1 only; ASCII only in Lua string literals.
- `RG.MAX_GROUPS = 8`, `RG.GROUP_SIZE = 5`.
- "Manager" = raid leader OR assistant (`snap.canManage`). Promote/demote/master-looter/uninvite/convert stay **leader-only** (`snap.isLeader`).
- Targeting macro: `/target <Name>` (name, not a roster token) so it survives roster reshuffles and works in combat.
- Moves: `SetRaidSubgroup(index, group)` when the target group has room; `SwapRaidSubgroup(index1, index2)` only when the target group is full and the drop landed on a specific member (see Task 1 Step 3's `PlanMove` for the exact rule - it is a small, deliberate refinement of the spec's wording, recorded there).
- Everything protected (cell attributes, Show/Hide/SetPoint/SetSize of cells, group frames and the window; frame creation) only when `not InCombatLockdown()`, exactly like Tank Cast: structural roster changes in combat set `RG.dirty` and flush on `PLAYER_REGEN_ENABLED`; only textures/font strings update live in combat (dead/offline/target highlight, by name).
- The window is anchored **top-left** (grows right/down as the raid grows), matching Tank Cast.
- **No duplication** between the main-window "..." menu and the minimap quick menu is a hard requirement, not a style preference - Task 3's checkpoint verifies every id appears in exactly the menus the spec assigns it to.
- **Do not `git commit` unless the user asks.** Each task ends with a "Checkpoint" (tests + syntax) instead of a commit.
- Syntax check (repo root; recreate the script if `C:/Users/iuras/AppData/Local/Temp/claude/D--tmp-AutoInvitePlus-3-3-5a/01bb4a72-f1e4-49c9-a03d-c5fe876a0d18/scratchpad/luacheck.js` is gone - it `require`s a scratch-installed `luaparse` and prints `OK`/`FAIL` per file with `{luaVersion:'5.1'}`; ignore the known `break;` false positive):
  `node <scratchpad>/luacheck.js <files>`
- Headless tests (repo root): `luajit tools/tests/raidgroups_spec.lua` (new file, Task 1) and `luajit tools/tests/tankcast_spec.lua` (must stay green - Task 3 touches shared title-bar code paths only, not Tank Cast's own files, but re-run it as a regression check anyway).
- Live loop (repo root, PowerShell): `. tools\wow-test-harness\harness.ps1; Sync-Addon; Send-WowChat "/reload"; Start-Sleep 8` (files are already in the `.toc` from this plan's Task 1/2 steps, so a plain `/reload` loads everything - no client restart needed, same as every Tank Cast round so far).

## Review Focus

Failure modes the spec implies that no plain unit test pins, most likely first - each has its test/check in the owning task.

1. **Non-manager sees an empty group** (must never happen - only Task 1's `VisibleGroups` prevents it; Task 2 must not re-filter and accidentally show one anyway).
2. **Drag-drop onto a full group's member vs its background**: swap only from a member drop, refuse (not silently no-op) from a background drop on a full group (Task 1 `PlanMove` tests + Task 2 live check).
3. **Menu item present in both the title-bar menu and the minimap menu** (the one duplication class explicitly forbidden) - Task 3 checkpoint diffs the two id lists.
4. **Combat mid-move**: a drag/right-click move action started before combat and released after `InCombatLockdown()` flips true must be refused with the same "changes apply after combat" wording Tank Cast uses, not silently dropped (Task 2 live check).
5. **Solo/party player who is also "the raid leader" in the trivial sense** (`UnitIsPartyLeader`) must NOT get `canManage`/manager powers outside a real raid - Task 1 test.

---

### Task 1: RaidGroups logic module, defaults, slash command, headless tests

**Files:**
- Create: `AutoInvitePlus/modules/RaidGroups.lua`
- Create: `tools/tests/raidgroups_spec.lua`
- Modify: `AutoInvitePlus/core/Core.lua` (defaults near the `tankCast` block; slash branch near `elseif cmd == "tanks"`; help near the tanks help lines)
- Modify: `AutoInvitePlus/AutoInvitePlus.toc` (after `modules\TankCast.lua`)

**Interfaces:**
- Consumes: nothing from other AIP modules (fully self-contained; guarded `AIP.Utils.Events` registration only).
- Produces (all on `AIP.RaidGroups` = `RG`):
  - `RG.MAX_GROUPS` (8), `RG.GROUP_SIZE` (5)
  - `RG.Snapshot() -> snap` (shape in the spec's section 2)
  - `RG.VisibleGroups(snap) -> array of group numbers, ascending`
  - `RG.GridSize(n) -> cols, rows`
  - `RG.ComputeLayout(visible, snap, dims) -> { w, h, groups = { [g] = {x, y, w, h, rows} } }` where `dims = {cellW, cellH, gap, groupGap, pad}`
  - `RG.PlanMove(snap, fromName, target) -> plan | nil, err` (`target = {group=n}` or `{name=str}`; `plan = {op="set", index, group}` or `{op="swap", index1, index2}`)
  - `RG.ExecMove(plan)`
  - `RG.RankLabel(rank) -> string`
  - `RG.MemberMenu(snap, member, hasTankCast) -> array of {id, text, enabled}`
  - `RG.WindowMenu(snap, locked) -> array of {id, text, enabled}`
  - `RG.IsLocked() / RG.SetLocked(on) / RG.ToggleLocked()`
  - `RG.ShowWindow / RG.HideWindow / RG.ToggleWindow / RG.IsWindowShown` (stubs here - `nil`/no-op until Task 2 defines the real ones; `ToggleWindow` guarded exactly like Tank Cast's pattern so `SlashHandler` never errors before Task 2 loads)
  - `RG.SlashHandler(rest)`
  - `RG.OnChanged(fn) / RG.Changed()` (module-local pub/sub, same shape as `TK.OnChanged`)

- [ ] **Step 1: Write the failing test file**

Create `tools/tests/raidgroups_spec.lua`:

```lua
-- Headless tests for AutoInvitePlus/modules/RaidGroups.lua (pure logic; no WoW client).
-- Run from the repo root:  luajit tools/tests/raidgroups_spec.lua

local printed = {}
AutoInvitePlus = {
    db = { raidGroups = {} },
    Print = function(msg) printed[#printed + 1] = msg end,
}
local AIP = AutoInvitePlus

-- ---- WoW API stubs ---------------------------------------------------------
local raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
local assignCalls = {}

local function raidEntry(i) return raid[i] end
GetNumRaidMembers = function() return #raid end
GetNumPartyMembers = function() return #party end
GetRaidRosterInfo = function(i)
    local r = raidEntry(i); if not r then return nil end
    -- name, rank, subgroup, level, class(localized), fileName, zone, online, isDead, role, isML
    return r.name, r.rank or 0, r.group or 1, r.level or 80, r.class or "Warrior", r.class and r.class:upper() or "WARRIOR",
        "Zone", r.online ~= false, r.dead and true or false, r.role, r.isML and true or false
end
local function partyUnit(idx) return idx == 0 and "player" or ("party" .. idx) end
UnitName = function(unit)
    if unit == "player" then return "Me" end
    local n = unit:match("^party(%d)$")
    if n then local e = party[tonumber(n)]; return e and e.name end
end
UnitClass = function(unit)
    if unit == "player" then return "Warrior", "WARRIOR" end
    local n = unit:match("^party(%d)$")
    if n then local e = party[tonumber(n)]; if e then return e.class, e.class:upper() end end
end
UnitLevel = function() return 80 end
UnitIsDead = function() return false end
UnitIsConnected = function() return true end
IsRaidLeader = function() return isLeaderFlag and 1 or nil end
IsRaidOfficer = function() return isOfficerFlag and 1 or nil end
UnitIsPartyLeader = function(unit) return unit == partyLeaderUnit end
SetRaidSubgroup = function(index, group) assignCalls[#assignCalls + 1] = "set:" .. index .. "->" .. group end
SwapRaidSubgroup = function(i1, i2) assignCalls[#assignCalls + 1] = "swap:" .. i1 .. "/" .. i2 end

dofile("AutoInvitePlus/modules/RaidGroups.lua")
local RG = AIP.RaidGroups

-- ---- tiny test framework ---------------------------------------------------
local pass, fail = 0, 0
local function eq(actual, expected, label)
    if actual == expected then pass = pass + 1
    else fail = fail + 1; print("FAIL " .. label .. ": expected [" .. tostring(expected) .. "], got [" .. tostring(actual) .. "]") end
end
local function reset()
    raid, party, isLeaderFlag, isOfficerFlag, partyLeaderUnit = {}, {}, false, false, nil
    assignCalls, printed = {}, {}
    AIP.db.raidGroups = {}
end

local function findId(list, id) for _, it in ipairs(list) do if it.id == id then return it end end end

-- ---- Snapshot: solo / party / raid -----------------------------------------
reset()
local snap = RG.Snapshot()
eq(snap.mode, "solo", "solo mode"); eq(#snap.members, 1, "solo: just me"); eq(snap.members[1].isSelf, true, "solo: self flagged")
eq(snap.canManage, false, "solo: cannot manage"); eq(snap.groups[1][1].name, "Me", "solo: in group 1")

reset(); party = { [1] = { name = "Ally", class = "Priest" } }
snap = RG.Snapshot()
eq(snap.mode, "party", "party mode"); eq(#snap.members, 2, "party: me + 1"); eq(snap.counts[1], 2, "party: both in group 1")
eq(snap.canManage, false, "party: cannot manage without real leadership")
partyLeaderUnit = "player"
snap = RG.Snapshot(); eq(snap.canManage, false, "party leader alone does not grant raid manage powers")

reset()
raid = {
    { name = "Boss", rank = 2, group = 1, class = "Paladin" },
    { name = "Ass", rank = 1, group = 1, class = "Priest" },
    { name = "Grunt", rank = 0, group = 2, class = "Warrior" },
    { name = "Offline", rank = 0, group = 2, class = "Mage", online = false },
    { name = "Dead", rank = 0, group = 3, class = "Rogue", dead = true },
}
snap = RG.Snapshot()
eq(snap.mode, "raid", "raid mode"); eq(#snap.members, 5, "raid: five members"); eq(snap.counts[1], 2, "raid: two in group 1")
eq(snap.counts[2], 2, "raid: two in group 2"); eq(snap.counts[3], 1, "raid: one in group 3"); eq(snap.counts[4] or 0, 0, "raid: group 4 empty")
eq(snap.groups[3][1].dead, true, "raid: dead flagged"); eq(snap.groups[2][2].online, false, "raid: offline flagged")
eq(snap.myRank, 0, "raid: my own rank when not listed defaults to 0"); eq(snap.canManage, false, "raid: not manager")
isOfficerFlag = true; snap = RG.Snapshot(); eq(snap.canManage, true, "raid: officer can manage")
isOfficerFlag, isLeaderFlag = false, true; snap = RG.Snapshot(); eq(snap.canManage, true, "raid: leader can manage"); eq(snap.isLeader, true, "raid: isLeader flag")

-- ---- VisibleGroups ----------------------------------------------------------
reset(); local vsolo = RG.VisibleGroups(RG.Snapshot()); eq(#vsolo, 1, "solo visible: 1 group"); eq(vsolo[1], 1, "solo visible: group 1")
reset()
raid = { { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 3, class = "Mage" } }
local vmember = RG.VisibleGroups(RG.Snapshot())
eq(#vmember, 2, "member view: only non-empty groups"); eq(vmember[1], 1, "member view: group 1 first"); eq(vmember[2], 3, "member view: group 3 second, group 2 skipped")
isLeaderFlag = true
local vmgr = RG.VisibleGroups(RG.Snapshot())
eq(#vmgr, 8, "manager view: all 8 groups"); eq(vmgr[8], 8, "manager view: includes empty group 8")

-- ---- GridSize ----------------------------------------------------------------
local function grid(n) local c, r = RG.GridSize(n); return c .. "x" .. r end
eq(grid(1), "1x1", "grid 1"); eq(grid(3), "3x1", "grid 3"); eq(grid(4), "4x1", "grid 4")
eq(grid(5), "3x2", "grid 5"); eq(grid(6), "3x2", "grid 6"); eq(grid(7), "4x2", "grid 7"); eq(grid(8), "4x2", "grid 8")

-- ---- ComputeLayout ------------------------------------------------------------
reset()
raid = {
    { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" },
    { name = "C", group = 2, class = "Priest" },
}
local dims = { cellW = 10, cellH = 2, gap = 0, groupGap = 1, pad = 0 }
local s2 = RG.Snapshot()
local layout = RG.ComputeLayout({ 1, 2 }, s2, dims)
eq(layout.groups[1].x, 0, "layout: group 1 at x=0"); eq(layout.groups[1].rows, 2, "layout: group 1 shows its 2 members (non-manager)")
eq(layout.groups[1].h, 4, "layout: group 1 height = 2 rows * (cellH+gap) - gap = 4")
eq(layout.groups[2].x, 11, "layout: group 2 starts after group 1's width + groupGap"); eq(layout.groups[2].rows, 1, "layout: group 2 shows its 1 member")
eq(layout.w, 21, "layout: total width = 2 groups * 10 + 1 gap"); eq(layout.h, 4, "layout: total height = the taller row (group 1's 4px)")

isLeaderFlag = true
local smgr = RG.Snapshot()
local layoutMgr = RG.ComputeLayout(RG.VisibleGroups(smgr), smgr, dims)
eq(layoutMgr.groups[1].rows, RG.GROUP_SIZE, "layout: manager view always reserves 5 rows per group")
eq(layoutMgr.groups[1].h, 10, "layout: manager group height = 5*(2)-0 = 10 with these dims")

-- ---- PlanMove / ExecMove ------------------------------------------------------
reset()
raid = {
    { name = "A", group = 1, class = "Warrior" }, { name = "B", group = 1, class = "Mage" },
    { name = "C", group = 2, class = "Priest" },
}
local snapNoMgr = RG.Snapshot()
eq((RG.PlanMove(snapNoMgr, "A", { group = 2 })), nil, "PlanMove: refused without manage permission")
isOfficerFlag = true
local snapMgr = RG.Snapshot()
local plan = RG.PlanMove(snapMgr, "A", { group = 2 })
eq(plan.op, "set", "PlanMove: room available -> set"); eq(plan.group, 2, "PlanMove: target group"); eq(plan.index, 1, "PlanMove: source raid index")
eq((RG.PlanMove(snapMgr, "A", { group = 1 })), nil, "PlanMove: refused, already in that group")
eq((RG.PlanMove(snapMgr, "Nobody", { group = 2 })), nil, "PlanMove: refused, unknown player")
plan = RG.PlanMove(snapMgr, "A", { name = "C" })
eq(plan.op, "set", "PlanMove: dropped on a member of a non-full group is still a plain move")

reset(); isOfficerFlag = true
local full = {}
for i = 1, RG.GROUP_SIZE do full[i] = { name = "M" .. i, group = 1, class = "Warrior" } end
full[#full + 1] = { name = "X", group = 2, class = "Mage" }
raid = full
local snapFull = RG.Snapshot()
eq((RG.PlanMove(snapFull, "X", { group = 1 })), nil, "PlanMove: full group + no target member -> refused")
local swapPlan = RG.PlanMove(snapFull, "X", { name = "M3" })
eq(swapPlan.op, "swap", "PlanMove: full group + dropped on a member -> swap")
eq(swapPlan.index1, RG.GROUP_SIZE + 1, "PlanMove: swap index1 = mover"); eq(swapPlan.index2, 3, "PlanMove: swap index2 = the member dropped on")

RG.ExecMove({ op = "set", index = 5, group = 3 }); eq(assignCalls[#assignCalls], "set:5->3", "ExecMove: set calls SetRaidSubgroup")
RG.ExecMove({ op = "swap", index1 = 1, index2 = 2 }); eq(assignCalls[#assignCalls], "swap:1/2", "ExecMove: swap calls SwapRaidSubgroup")

-- ---- Menus --------------------------------------------------------------------
eq(RG.RankLabel(2), "Raid leader", "RankLabel 2"); eq(RG.RankLabel(1), "Assistant", "RankLabel 1"); eq(RG.RankLabel(0), "Member", "RankLabel 0")

reset()
-- "Me" is the row that matches the UnitName("player") stub, i.e. the viewer's own
-- row (rank 2, so later it also stands in for "the raid leader querying their own
-- row"); "Grunt" is the other member every officer/leader assertion acts on.
raid = { { name = "Me", rank = 2, group = 1, class = "Paladin" }, { name = "Grunt", rank = 0, group = 2, class = "Warrior" } }
local snapMember = RG.Snapshot()
local grunt = snapMember.members[2]
local mm = RG.MemberMenu(snapMember, grunt, true)
eq(findId(mm, "whisper") ~= nil, true, "member menu: whisper present for others")
eq(findId(mm, "tank_mt") ~= nil, true, "member menu: Tank Cast entries present when hasTankCast")
eq(findId(mm, "move_1"), nil, "member menu: no move entries without manage permission")
eq(findId(mm, "promote_leader"), nil, "member menu: no leader-only entries for a plain member")

local me = snapMember.members[1]
eq(me.isSelf, true, "fixture sanity: 'Me' resolves as the viewer's own row")
local selfMenu = RG.MemberMenu(snapMember, me, true)
eq(findId(selfMenu, "whisper"), nil, "member menu: no whisper on yourself")
eq(findId(selfMenu, "inspect") ~= nil, true, "member menu: inspect still offered on yourself")

isOfficerFlag = true
local snapOfficer = RG.Snapshot()
local mmOfficer = RG.MemberMenu(snapOfficer, snapOfficer.members[2], false)
eq(findId(mmOfficer, "set_mt") ~= nil, true, "officer menu: MT/MA entries present")
local move2 = findId(mmOfficer, "move_2")
eq(move2.enabled, false, "officer menu: move to the member's own group is disabled")
eq(findId(mmOfficer, "move_3").enabled, true, "officer menu: move to a different, non-full group is enabled")
eq(findId(mmOfficer, "promote_leader"), nil, "officer (non-leader) menu: no leader-only entries")

isLeaderFlag, isOfficerFlag = true, false
local snapLeader = RG.Snapshot()
local mmLeader = RG.MemberMenu(snapLeader, snapLeader.members[2], false)
eq(findId(mmLeader, "promote_leader") ~= nil, true, "leader menu: promote_leader present")
eq(findId(mmLeader, "uninvite") ~= nil, true, "leader menu: uninvite present")
eq(findId(mmLeader, "promote_assist") ~= nil, true, "leader menu: rank-0 member offered promote_assist, not demote")
eq(findId(mmLeader, "demote_assist"), nil, "leader menu: rank-0 member is not offered demote")
local mmLeaderOnBoss = RG.MemberMenu(snapLeader, snapLeader.members[1], false)
eq(findId(mmLeaderOnBoss, "demote_assist"), nil, "leader menu: the raid leader row has no demote entry")
eq(findId(mmLeaderOnBoss, "promote_leader"), nil, "leader menu: no 'promote to leader' on yourself")

local wmMember = RG.WindowMenu(snapMember, false)
eq(findId(wmMember, "ready_check"), nil, "window menu: no ready check for a plain member")
eq(findId(wmMember, "lock").text, "Lock position", "window menu: lock label unlocked")
local wmLeader = RG.WindowMenu(snapLeader, true)
eq(findId(wmLeader, "ready_check") ~= nil, true, "window menu: ready check for a manager")
eq(findId(wmLeader, "lock").text, "Unlock position", "window menu: lock label locked")
eq(findId(wmLeader, "close") ~= nil, true, "window menu: close always present")

-- ---- lock / slash -------------------------------------------------------------
reset()
eq(RG.IsLocked(), false, "starts unlocked"); eq(RG.ToggleLocked(), true, "toggle locks"); eq(RG.IsLocked(), true, "locked")
eq(AIP.db.raidGroups.locked, true, "lock persisted in db.raidGroups.locked")
RG.SetLocked(false); eq(RG.IsLocked(), false, "SetLocked(false)")
RG.SlashHandler("lock"); eq(RG.IsLocked(), true, "slash lock toggles"); RG.SlashHandler("unlock"); eq(RG.IsLocked(), false, "slash unlock")

print(string.format("%d passed, %d failed", pass, fail))
os.exit(fail == 0 and 0 or 1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `luajit tools/tests/raidgroups_spec.lua`
Expected: FAIL — `cannot open AutoInvitePlus/modules/RaidGroups.lua: No such file or directory`.

- [ ] **Step 3: Write the logic module**

Create `AutoInvitePlus/modules/RaidGroups.lua`:

```lua
-- AutoInvite Plus - Raid Groups (logic layer)
-- A compact "who's in what group" window: a roster snapshot, the grid-layout math,
-- the move planner (SetRaidSubgroup vs SwapRaidSubgroup), and the per-rank menu
-- models. Kept headless (tools/tests/raidgroups_spec.lua) so ui/RaidGroupsWindow.lua
-- is pure presentation. "Manager" = raid leader OR assistant, matching what the
-- game itself lets rearrange groups and set Main Tank/Main Assist; promote/demote/
-- master-looter/uninvite/convert stay leader-only (see RG.MemberMenu/WindowMenu).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.RaidGroups = AIP.RaidGroups or {}
local RG = AIP.RaidGroups

RG.MAX_GROUPS = 8
RG.GROUP_SIZE = 5
RG.dirty = false

local changedListeners = {}
local function fire(list) for _, fn in ipairs(list) do pcall(fn) end end
function RG.OnChanged(fn) changedListeners[#changedListeners + 1] = fn end
function RG.Changed() fire(changedListeners) end

local function say(msg) if AIP.Print then AIP.Print(msg) end end

-- ============================================================================
-- SAVED STATE (position/lock only - the roster itself is never persisted)
-- ============================================================================

local function cfg()
    local db = AIP.db
    if not db then return nil end
    local c = db.raidGroups
    if type(c) ~= "table" then c = {}; db.raidGroups = c end
    return c
end
RG.Cfg = cfg

function RG.IsLocked()
    local c = cfg()
    return (c and c.locked) and true or false
end

function RG.SetLocked(on)
    local c = cfg()
    if not c then return false end
    c.locked = on and true or false
    return true
end

function RG.ToggleLocked()
    RG.SetLocked(not RG.IsLocked())
    return RG.IsLocked()
end

-- ============================================================================
-- SNAPSHOT
-- ============================================================================

-- Everyone in the player's group right now. mode = "raid" | "party" | "solo".
function RG.Snapshot()
    local n = GetNumRaidMembers and GetNumRaidMembers() or 0
    local members, groups, counts = {}, {}, {}
    for g = 1, RG.MAX_GROUPS do groups[g] = {} end

    local mode, myRank, isLeader = "solo", 0, false
    if n > 0 then
        mode = "raid"
        for i = 1, n do
            local name, rank, subgroup, level, _, fileName, _, online, isDead, role, isML = GetRaidRosterInfo(i)
            if name then
                subgroup = subgroup or 1
                local m = {
                    name = name, unit = "raid" .. i, class = fileName, level = level, group = subgroup,
                    index = i, rank = rank or 0, role = role, isML = isML and true or false,
                    online = online ~= false, dead = isDead and true or false,
                    isSelf = (UnitName and UnitName("player") == name),
                }
                members[#members + 1] = m
                groups[subgroup][#groups[subgroup] + 1] = m
                counts[subgroup] = (counts[subgroup] or 0) + 1
                if m.isSelf then myRank = m.rank end
            end
        end
        isLeader = (IsRaidLeader and IsRaidLeader()) and true or false
        local isOfficer = (IsRaidOfficer and IsRaidOfficer()) and true or false
        return {
            mode = mode, members = members, groups = groups, counts = counts,
            myRank = myRank, isLeader = isLeader, canManage = isLeader or isOfficer,
        }
    end

    local nParty = GetNumPartyMembers and GetNumPartyMembers() or 0
    if nParty > 0 then mode = "party" end
    local meName = UnitName and UnitName("player") or "You"
    local meRank = (UnitIsPartyLeader and UnitIsPartyLeader("player")) and 2 or 0
    local me = {
        name = meName, unit = "player", class = select(2, UnitClass and UnitClass("player")), level = UnitLevel and UnitLevel("player"),
        group = 1, index = 0, rank = meRank, role = nil, isML = false, online = true, dead = false, isSelf = true,
    }
    members[1] = me
    groups[1][1] = me
    counts[1] = 1
    for i = 1, nParty do
        local unit = "party" .. i
        local name = UnitName and UnitName(unit)
        if name then
            local _, class = UnitClass and UnitClass(unit)
            local m = {
                name = name, unit = unit, class = class, level = UnitLevel and UnitLevel(unit),
                group = 1, index = i, rank = (UnitIsPartyLeader and UnitIsPartyLeader(unit)) and 2 or 0,
                role = nil, isML = false, online = true, dead = false, isSelf = false,
            }
            members[#members + 1] = m
            groups[1][#groups[1] + 1] = m
            counts[1] = counts[1] + 1
        end
    end
    -- Party "leadership" never grants raid manage powers - there is no raid to manage.
    return { mode = mode, members = members, groups = groups, counts = counts, myRank = meRank, isLeader = false, canManage = false }
end

-- Which groups a viewer gets to see: managers get all 8 (so they can drag into an
-- empty one); everyone else only sees groups that actually have someone in them.
function RG.VisibleGroups(snap)
    if snap.mode == "raid" and snap.canManage then
        local all = {}
        for g = 1, RG.MAX_GROUPS do all[g] = g end
        return all
    end
    local out = {}
    for g = 1, RG.MAX_GROUPS do
        if (snap.counts[g] or 0) > 0 then out[#out + 1] = g end
    end
    return out
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

-- Columns/rows for n groups: up to 4 groups -> one row; more -> ceil(n/2), capped
-- at 4 columns (so 5-8 groups always draw as a 2-row grid, never a single wide row).
function RG.GridSize(n)
    if n <= 0 then return 1, 1 end
    if n <= 4 then return n, 1 end
    local cols = math.min(4, math.ceil(n / 2))
    return cols, math.ceil(n / cols)
end

-- Pixel layout for the visible groups, in reading order (row-major) into the grid
-- GridSize gives. dims = {cellW, cellH, gap, groupGap, pad}. A manager's groups are
-- always GROUP_SIZE cells tall (room to drop into); a non-manager's are only as
-- tall as the group's real member count (never 0 - VisibleGroups already excludes
-- empty groups for them).
function RG.ComputeLayout(visible, snap, dims)
    local cols, rows = RG.GridSize(#visible)
    local cellH, gap, groupGap, pad = dims.cellH, dims.gap, dims.groupGap, dims.pad
    local groupW = dims.cellW

    -- Row heights: each grid row is as tall as its tallest group that row.
    local rowH = {}
    for k, g in ipairs(visible) do
        local r = math.floor((k - 1) / cols) + 1
        local shown = snap.canManage and (snap.mode == "raid") and RG.GROUP_SIZE or math.max(1, snap.counts[g] or 0)
        local h = shown * (cellH + gap) - gap
        if not rowH[r] or h > rowH[r] then rowH[r] = h end
    end

    local out = { groups = {} }
    for k, g in ipairs(visible) do
        local col = (k - 1) % cols
        local row = math.floor((k - 1) / cols) + 1
        local x = pad + col * (groupW + groupGap)
        local y = pad
        for r = 1, row - 1 do y = y + rowH[r] + groupGap end
        local shown = snap.canManage and (snap.mode == "raid") and RG.GROUP_SIZE or math.max(1, snap.counts[g] or 0)
        out.groups[g] = { x = x, y = y, w = groupW, h = shown * (cellH + gap) - gap, rows = shown }
    end

    local totalRowH = 0
    for r = 1, rows do totalRowH = totalRowH + (rowH[r] or 0) end
    out.w = pad * 2 + cols * groupW + (cols - 1) * groupGap
    out.h = pad * 2 + totalRowH + (rows - 1) * groupGap
    return out
end

-- ============================================================================
-- MOVE PLANNING
-- ============================================================================

local function findByName(snap, name)
    if not name then return nil end
    local l = name:lower()
    for _, m in ipairs(snap.members) do if m.name:lower() == l then return m end end
    return nil
end

-- Decide what a drop should do. target = {group = n} (dropped on empty space / the
-- group itself) or {name = "X"} (dropped on member X's cell). Returns a plan or
-- nil, reason. Rule: if the destination group has room, it is always a plain move
-- (even when dropped on a specific member - there is no need to swap when a slot
-- is free); only a FULL destination group turns a member-drop into a swap, and a
-- background-drop on a full group is refused outright (nothing to swap with).
function RG.PlanMove(snap, fromName, target)
    if not (snap.mode == "raid" and snap.canManage) then
        return nil, "You must be raid leader or assistant to move players."
    end
    local mover = findByName(snap, fromName)
    if not mover then return nil, "Unknown player." end

    local targetMember, tg
    if target and target.name then
        targetMember = findByName(snap, target.name)
        if not targetMember then return nil, "Unknown player." end
        tg = targetMember.group
    elseif target and target.group then
        tg = target.group
    else
        return nil, "No destination given."
    end

    if tg == mover.group then return nil, mover.name .. " is already in that group." end

    local count = snap.counts[tg] or 0
    if count < RG.GROUP_SIZE then
        return { op = "set", index = mover.index, group = tg }
    end
    if targetMember then
        return { op = "swap", index1 = mover.index, index2 = targetMember.index }
    end
    return nil, "Group " .. tg .. " is full - drop on a member to swap."
end

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

function RG.RankLabel(rank)
    if rank == 2 then return "Raid leader" end
    if rank == 1 then return "Assistant" end
    return "Member"
end

-- Right-click a member cell. hasTankCast lets the caller fold in Tank Cast
-- shortcuts without RaidGroups depending on that module directly.
function RG.MemberMenu(snap, member, hasTankCast)
    local list = {}
    local function add(id, text, enabled)
        list[#list + 1] = { id = id, text = text, enabled = enabled ~= false }
    end

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
            add("promote_leader", "Promote to Leader")
            if member.rank == 1 then add("demote_assist", "Demote Assistant") else add("promote_assist", "Promote to Assistant") end
            add("master_looter", "Set as Master Looter")
            add("uninvite", "Remove from Raid")
        end
    end
    return list
end

-- Right-click the window's title/background.
function RG.WindowMenu(snap, locked)
    local list = {}
    list[#list + 1] = { id = "lock", text = locked and "Unlock position" or "Lock position", enabled = true }
    if snap.canManage then
        list[#list + 1] = { id = "ready_check", text = "Ready Check", enabled = true }
    end
    if snap.isLeader then
        local total = #snap.members
        if snap.mode == "raid" and total <= RG.GROUP_SIZE then
            list[#list + 1] = { id = "convert", text = "Convert to Party", enabled = true }
        elseif snap.mode == "party" then
            list[#list + 1] = { id = "convert", text = "Convert to Raid", enabled = true }
        end
    end
    list[#list + 1] = { id = "close", text = "Close", enabled = true }
    return list
end

-- ============================================================================
-- SLASH: /aip groups [lock|unlock]
-- ============================================================================

function RG.SlashHandler(rest)
    local sub = (rest or ""):match("^%s*(%S*)"):lower()
    if sub == "" then
        if RG.ToggleWindow then RG.ToggleWindow() else say("The Raid Groups window is not loaded.") end
    elseif sub == "lock" then
        say(RG.ToggleLocked() and "Raid Groups window locked." or "Raid Groups window unlocked.")
    elseif sub == "unlock" then
        RG.SetLocked(false)
        say("Raid Groups window unlocked.")
    else
        say("/aip groups [lock|unlock]")
    end
end

-- ============================================================================
-- EVENTS
-- ============================================================================

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

- [ ] **Step 4: Run the tests to verify they pass**

Run: `luajit tools/tests/raidgroups_spec.lua`
Expected: `N passed, 0 failed`. Fix the module, not the test, on any `FAIL` unless the test's expectation contradicts this plan's stated `PlanMove` rule (§ Step 3's comment above `RG.PlanMove` is the tie-breaker).

- [ ] **Step 5: Saved-variable default**

In `AutoInvitePlus/core/Core.lua`, find the `tankCast = { ... }` defaults block and Edit immediately after its closing `},`:

old_string (the line right after the `tankCast` block's closing `},`):
```
    rollDuration = 10,              -- Roll countdown seconds
```
new_string:
```
    -- Raid Groups window (AIP.RaidGroups): position/lock only - the roster itself
    -- is read live from the game, never persisted.
    raidGroups = {
        shown = false,
        locked = false,
        pos = nil,                  -- {point, relPoint, x, y}
    },
    rollDuration = 10,              -- Roll countdown seconds
```

(If `rollDuration` no longer immediately follows `tankCast` when you read the file, insert the `raidGroups` block directly after `tankCast`'s closing `},` instead - the anchor is positional, not the exact neighboring line.)

- [ ] **Step 6: Slash command and help**

In `AutoInvitePlus/core/Core.lua`, Edit:

old_string:
```
    elseif cmd == "tanks" or cmd == "tank" then
        if AIP.TankCast and AIP.TankCast.SlashHandler then AIP.TankCast.SlashHandler(rest) end
```
new_string:
```
    elseif cmd == "tanks" or cmd == "tank" then
        if AIP.TankCast and AIP.TankCast.SlashHandler then AIP.TankCast.SlashHandler(rest) end
    elseif cmd == "groups" or cmd == "raidgroups" then
        if AIP.RaidGroups and AIP.RaidGroups.SlashHandler then AIP.RaidGroups.SlashHandler(rest) end
```

Then Edit:

old_string:
```
        Print("  /aip tanks mt|ot [name] | addot | pick|unpick <mt|otN> <name> | spell <name> | clear | reset | lock | sync | push | list")
```
new_string:
```
        Print("  /aip tanks mt|ot [name] | addot | pick|unpick <mt|otN> <name> | spell <name> | clear | reset | lock | sync | push | list")
        Print("  /aip groups - Toggle the Raid Groups window (right-click a name or the title bar for options)")
        Print("  /aip groups lock | unlock")
```

- [ ] **Step 7: Register the module in the .toc**

In `AutoInvitePlus/AutoInvitePlus.toc`, Edit:

old_string:
```
modules\TankCast.lua
```
new_string:
```
modules\TankCast.lua
modules\RaidGroups.lua
```

- [ ] **Step 8: Checkpoint**

Syntax-check `AutoInvitePlus/modules/RaidGroups.lua`, `AutoInvitePlus/core/Core.lua`, `tools/tests/raidgroups_spec.lua`; run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua` (regression - must still be green).
Expected: all `OK`, both `0 failed`. **Do not commit.**

---

### Task 2: Raid Groups window (cells, groups, tooltip, targeting, drag/drop, menus)

**Files:**
- Create: `AutoInvitePlus/ui/RaidGroupsWindow.lua`
- Modify: `AutoInvitePlus/AutoInvitePlus.toc` (after `ui\TankCastConfig.lua`)

**Interfaces:**
- Consumes: everything from Task 1's `RG.*`; guarded `AIP.TankCast.SetSlot/SetFirstOT` for the `tank_mt`/`tank_ot` menu rows; `AIP.TankCast.SkinPanel/SkinHeader/CloseButton/Fontize/EnsureMenuFrame` (loaded earlier in the `.toc`, so these functions already exist on `AIP.TankCast` by the time this file runs - guarded with `if AIP.TankCast and ... then` everywhere they're used, so a missing Tank Cast install degrades to plain styling instead of erroring).
- Produces: `RG.ShowWindow() / RG.HideWindow() / RG.ToggleWindow() / RG.IsWindowShown()` (replacing Task 1's stub guards).

- [ ] **Step 1: Write the window file**

Create `AutoInvitePlus/ui/RaidGroupsWindow.lua`:

```lua
-- AutoInvite Plus - Raid Groups window (presentation for AIP.RaidGroups)
-- A compact "who's in what group" window: class-coloured name cells packed into
-- their raid subgroups. Click a cell to target that player (secure /target macro);
-- right-click for the per-rank menu (RG.MemberMenu). Managers (raid leader or
-- assistant) see every one of the 8 groups, including empty ones, and can drag a
-- cell to another group to move/swap. Everyone else sees only non-empty groups.
--
-- Styling is borrowed from Tank Cast (AIP.TankCast.SkinPanel/SkinHeader/
-- CloseButton/Fontize/EnsureMenuFrame - guarded, since RaidGroups does not
-- otherwise depend on the TankCast module).
--
-- 3.3.5a secure-frame rules (same as Tank Cast):
--  * member cells are SecureActionButtonTemplate (protected): attributes,
--    Show/Hide and SetPoint are ONLY touched when not InCombatLockdown()
--    (see applyStructure); cells are created ON DEMAND there too;
--  * their parents (group frames) and the window are therefore implicitly
--    protected too: Show/Hide/SetSize/StartMoving on them are guarded/deferred
--    the same way, and every frame is created out of combat
--    (PLAYER_LOGIN / first ShowWindow, deferred to PLAYER_REGEN_ENABLED if the
--    UI loaded mid-combat);
--  * everything renders from a snapshot, so the window never disagrees with what
--    a click targets while a roster change waits for combat to end; moves
--    (structural) are refused outright while RG.dirty (see TK.GuardEdit's
--    Tank Cast precedent - RG.GuardEdit mirrors it).

local AIP = AutoInvitePlus
if not AIP then return end

AIP.RaidGroups = AIP.RaidGroups or {}
local RG = AIP.RaidGroups
local TC = AIP.TankCast   -- optional: only used for shared skin helpers + Tank Cast menu rows

local WHITE = "Interface\\Buttons\\WHITE8X8"
local PAD, HDR_H = 4, 16
local CELL_W, CELL_H, CELL_GAP = 76, 15, 1
local GROUP_GAP = 4
local DIMS = { cellW = CELL_W, cellH = CELL_H, gap = CELL_GAP, groupGap = GROUP_GAP, pad = PAD }

local function fontize(fs, size, flags)
    if TC and TC.Fontize then return TC.Fontize(fs, size, flags) end
    local font = GameFontHighlight and GameFontHighlight:GetFont()
    if font then fs:SetFont(font, size, flags or "") end
    return fs
end

local function skinPanel(f, alpha)
    if TC and TC.SkinPanel then TC.SkinPanel(f, alpha); return end
    f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1, insets = {left=1,right=1,top=1,bottom=1} })
    f:SetBackdropColor(0.04, 0.045, 0.065, alpha or 0.96)
    f:SetBackdropBorderColor(0.30, 0.33, 0.42, 1)
end

local function skinHeader(f, h)
    if TC and TC.SkinHeader then TC.SkinHeader(f, h); return end
    local hdr = f:CreateTexture(nil, "BORDER")
    hdr:SetPoint("TOPLEFT", 1, -1); hdr:SetPoint("TOPRIGHT", -1, -1); hdr:SetHeight(h - 1)
    hdr:SetTexture(0.12, 0.13, 0.19, 1)
end

local function menuFrame()
    if TC and TC.EnsureMenuFrame then return TC.EnsureMenuFrame() end
    RG.menuFrame = RG.menuFrame or CreateFrame("Frame", "AIPRaidGroupsMenu", UIParent, "UIDropDownMenuTemplate")
    return RG.menuFrame
end

local win
local groupFrames = {}          -- [g] = frame
local cellPool = {}             -- flat pool of member-cell buttons, reused across groups
local applied = { snap = nil, visible = {}, layout = nil, hasTankCast = false }
local refresh, refreshValues

-- Structural edits are refused while a change waits for combat to end (mirrors
-- Tank Cast's TK.GuardEdit): the window still shows the OLD roster, so an index
-- taken from it could hit the wrong live member.
function RG.GuardEdit()
    if not RG.dirty then return true end
    AIP.Print("Changes apply after combat - wait for the fight to end before editing again.")
    return false
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.6, 0.6, 0.65
end

-- ============================================================================
-- MEMBER / WINDOW ACTIONS (menu id -> effect)
-- ============================================================================

local function act(fn)
    return function() if RG.GuardEdit() then fn() end end
end

local function doMemberAction(id, member)
    local unit = member.unit
    if id == "whisper" then if ChatFrame_SendTell then ChatFrame_SendTell(member.name) end
    elseif id == "inspect" then if InspectUnit and unit then InspectUnit(unit) end
    elseif id == "achievements" then if InspectAchievements and unit then InspectAchievements(unit) end
    elseif id == "trade" then if InitiateTrade and unit then InitiateTrade(unit) end
    elseif id == "follow" then if FollowUnit and unit then FollowUnit(unit) end
    elseif id == "tank_mt" then
        if AIP.TankCast and AIP.TankCast.SetSlot then
            local ok, err = AIP.TankCast.SetSlot(1, member.name); if not ok then AIP.Print(err) end
        end
    elseif id == "tank_ot" then
        if AIP.TankCast and AIP.TankCast.SetFirstOT then
            local ok, err = AIP.TankCast.SetFirstOT(member.name); if not ok then AIP.Print(err) end
        end
    elseif id == "set_mt" then if SetPartyAssignment and unit then SetPartyAssignment("MAINTANK", unit) end
    elseif id == "clear_mt" then if ClearPartyAssignment and unit then ClearPartyAssignment("MAINTANK", unit) end
    elseif id == "set_ma" then if SetPartyAssignment and unit then SetPartyAssignment("MAINASSIST", unit) end
    elseif id == "clear_ma" then if ClearPartyAssignment and unit then ClearPartyAssignment("MAINASSIST", unit) end
    elseif id == "promote_leader" then if PromoteToLeader and unit then PromoteToLeader(unit) end
    elseif id == "promote_assist" then if PromoteToAssistant and unit then PromoteToAssistant(unit) end
    elseif id == "demote_assist" then if DemoteAssistant and unit then DemoteAssistant(unit) end
    elseif id == "master_looter" then if SetLootMethod then SetLootMethod("master", member.name) end
    elseif id == "uninvite" then
        RG.pendingUninvite = member.name
        StaticPopup_Show("AIP_RAIDGROUPS_UNINVITE")
    else
        local g = id:match("^move_(%d+)$")
        if g and applied.snap then
            local plan, err = RG.PlanMove(applied.snap, member.name, { group = tonumber(g) })
            if plan then RG.ExecMove(plan) else AIP.Print(err) end
        end
    end
end

local function openMemberMenu(member)
    if not applied.snap then return end
    local list = { { text = member.name, isTitle = true, notCheckable = true } }
    for _, item in ipairs(RG.MemberMenu(applied.snap, member, applied.hasTankCast)) do
        list[#list + 1] = {
            text = item.text, notCheckable = true, disabled = not item.enabled,
            func = act(function() doMemberAction(item.id, member) end),
        }
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, menuFrame(), "cursor", 0, 0, "MENU")
end

local function doWindowAction(id)
    if id == "lock" then RG.ToggleLocked()
    elseif id == "ready_check" then if DoReadyCheck then DoReadyCheck() end
    elseif id == "convert" then
        if not applied.snap then return end
        if applied.snap.mode == "raid" and ConvertToParty then ConvertToParty()
        elseif applied.snap.mode == "party" and ConvertToRaid then ConvertToRaid() end
    elseif id == "close" then RG.HideWindow() end
end

local function openWindowMenu(anchor)
    if not applied.snap then return end
    local list = { { text = "Raid Groups", isTitle = true, notCheckable = true } }
    for _, item in ipairs(RG.WindowMenu(applied.snap, RG.IsLocked())) do
        list[#list + 1] = {
            text = item.text, notCheckable = true, disabled = not item.enabled,
            func = function() doWindowAction(item.id) end,
        }
    end
    list[#list + 1] = { text = "Cancel", notCheckable = true }
    EasyMenu(list, menuFrame(), anchor, 0, 0, "MENU")
end

StaticPopupDialogs["AIP_RAIDGROUPS_UNINVITE"] = {
    text = "Remove %s from the raid?",
    button1 = YES, button2 = NO, timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self) self.text:SetText(string.format(self.text:GetText(), RG.pendingUninvite or "?")) end,
    OnAccept = function()
        if RG.pendingUninvite and UninviteUnit then UninviteUnit(RG.pendingUninvite) end
        RG.pendingUninvite = nil
    end,
}

-- ============================================================================
-- DRAG (managers only)
-- ============================================================================

local dragTag       -- the small name tag that follows the cursor
local dragFrom       -- member name being dragged

local function ensureDragTag()
    if dragTag then return dragTag end
    dragTag = CreateFrame("Frame", "AIPRaidGroupsDragTag", UIParent)
    dragTag:SetSize(CELL_W, CELL_H)
    dragTag:SetFrameStrata("TOOLTIP")
    local bg = dragTag:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(1, 1, 1, 1)
    dragTag.bg = bg
    dragTag.fs = fontize(dragTag:CreateFontString(nil, "OVERLAY"), 10, "OUTLINE")
    dragTag.fs:SetAllPoints(); dragTag.fs:SetJustifyH("CENTER")
    dragTag:Hide()
    return dragTag
end

local function findCellUnder(x, y)
    for _, cell in ipairs(cellPool) do
        if cell:IsShown() and cell.member and cell:IsMouseOver() then return cell end
    end
    return nil
end

local function beginDrag(cell)
    if not (applied.snap and applied.snap.mode == "raid" and applied.snap.canManage) then return end
    dragFrom = cell.member.name
    local tag = ensureDragTag()
    local r, g, b = classColor(cell.member.class)
    tag.bg:SetTexture(r, g, b, 0.9)
    tag.fs:SetText(cell.member.name)
    tag:ClearAllPoints(); tag:SetPoint("CENTER", UIParent, "BOTTOMLEFT", 0, 0)
    tag:Show()
    tag:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end)
end

local function endDrag()
    if not dragFrom then return end
    local target = findCellUnder()
    local plan, err
    if target and target.member then
        if not RG.GuardEdit() then dragFrom = nil; if dragTag then dragTag:Hide() end; return end
        plan, err = RG.PlanMove(applied.snap, dragFrom, { name = target.member.name })
    elseif target and target.emptyGroup then
        if not RG.GuardEdit() then dragFrom = nil; if dragTag then dragTag:Hide() end; return end
        plan, err = RG.PlanMove(applied.snap, dragFrom, { group = target.emptyGroup })
    end
    if plan then RG.ExecMove(plan) elseif err then AIP.Print(err) end
    dragFrom = nil
    if dragTag then dragTag:Hide(); dragTag:SetScript("OnUpdate", nil) end
end

-- ============================================================================
-- CELLS
-- ============================================================================

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

-- An empty manager slot: same size, no secure attributes, a drop target only.
local function acquireEmptySlot(group, slotNum)
    local key = "empty_" .. group .. "_" .. slotNum
    local cell = cellPool[key]
    if cell then return cell end
    cell = CreateFrame("Frame", nil, win)
    cell:SetSize(CELL_W, CELL_H)
    cell.emptyGroup = group
    local bg = cell:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(); bg:SetTexture(0.12, 0.13, 0.18, 0.5)
    cell:Hide()
    cellPool[key] = cell
    return cell
end

-- ============================================================================
-- LAYOUT
-- ============================================================================

function RG.LayoutWindow()
    if not win then return end
    if InCombatLockdown() then RG.dirty = true; return end
    win:SetSize(applied.layout and (applied.layout.w + PAD * 2) or (CELL_W + PAD * 2),
                HDR_H + (applied.layout and applied.layout.h or CELL_H) + PAD)
end

local function applyStructure()
    local snap = RG.Snapshot()
    applied.snap = snap
    applied.hasTankCast = (AIP.TankCast and AIP.TankCast.SetSlot) and true or false
    local visible = RG.VisibleGroups(snap)
    applied.visible = visible
    local layout = RG.ComputeLayout(visible, snap, DIMS)
    applied.layout = layout

    local idx = 0
    for _, g in ipairs(visible) do
        local gl = layout.groups[g]
        local members = snap.groups[g]
        local shown = gl.rows
        for slot = 1, shown do
            local m = members[slot]
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
            else
                local slotFrame = acquireEmptySlot(g, slot)
                slotFrame:ClearAllPoints()
                slotFrame:SetPoint("TOPLEFT", win, "TOPLEFT", gl.x + PAD, -(HDR_H + gl.y + (slot - 1) * (CELL_H + CELL_GAP)))
                slotFrame:Show()
            end
        end
    end
    for i = idx + 1, #cellPool do
        local cell = cellPool[i]
        if cell and cell.SetAttribute then
            cell.member = nil
            cell:SetAttribute("type1", nil)
            cell:SetAttribute("macrotext1", nil)
            cell:Hide()
        end
    end
    for key, frame in pairs(cellPool) do
        if type(key) == "string" then frame:Hide() end
    end
    -- Re-show the empty slots this pass actually used (the blanket hide above
    -- clears every string-keyed slot frame first so stale ones from a shrunk
    -- raid don't linger).
    for _, g in ipairs(visible) do
        local gl = layout.groups[g]
        local members = snap.groups[g]
        for slot = 1, gl.rows do
            if not members[slot] then
                local slotFrame = cellPool["empty_" .. g .. "_" .. slot]
                if slotFrame then slotFrame:Show() end
            end
        end
    end

    win.memberCount:SetText(#snap.members .. (snap.mode == "raid" and ("/" .. (RG.MAX_GROUPS * RG.GROUP_SIZE)) or ""))
    RG.LayoutWindow()
end

refreshValues = function()
    if not win or not win:IsShown() or not applied.snap then return end
    local targetName = UnitName and UnitExists and UnitExists("target") and UnitName("target")
    for _, cell in ipairs(cellPool) do
        if cell.member then
            local m = cell.member
            cell.bg:SetTexture(classColor(m.class))
            cell.nameFS:SetText(m.name)
            cell.overlay:SetShown(not m.online or m.dead)
            cell.overlay:SetTexture(0, 0, 0, (not m.online) and 0.6 or 0.4)
            cell.targetBorder:SetShown(targetName == m.name)
            local tag = (m.role == "MAINTANK" and "MT") or (m.role == "MAINASSIST" and "MA") or ""
            if applied.snap.canManage and m.rank and m.rank > 0 then
                tag = (tag ~= "" and (tag .. " ") or "") .. (m.rank == 2 and "L" or "A")
            end
            cell.rankFS:SetText(tag)
        end
    end
end

refresh = function()
    if not win then return end
    if InCombatLockdown() then RG.dirty = true; refreshValues(); return end
    RG.dirty = false
    applyStructure()
    refreshValues()
end

-- ============================================================================
-- WINDOW
-- ============================================================================

local function restorePosition()
    local c = RG.Cfg()
    local pos = c and c.pos
    win:ClearAllPoints()
    if pos then
        win:SetPoint(pos.point or "CENTER", UIParent, pos.relPoint or "CENTER", pos.x or 0, pos.y or 0)
    else
        win:SetPoint("CENTER", UIParent, "CENTER", 320, 0)
    end
end

local function anchorTopLeft()
    local l, t = win:GetLeft(), win:GetTop()
    if l and t then win:ClearAllPoints(); win:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", l, t) end
end

local function ensureWindow()
    if win then return win end
    win = CreateFrame("Frame", "AIPRaidGroupsWindow", UIParent)
    win:SetSize(CELL_W + PAD * 2, HDR_H + CELL_H + PAD)
    win:SetFrameStrata("MEDIUM")
    win:SetClampedToScreen(true)
    skinPanel(win)
    skinHeader(win, HDR_H)
    restorePosition()

    win:SetMovable(true); win:EnableMouse(true); win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self)
        if InCombatLockdown() or RG.IsLocked() then return end
        self.moving = true; self:StartMoving()
    end)
    win:SetScript("OnDragStop", function(self)
        if not self.moving then return end
        self.moving = false; self:StopMovingOrSizing(); anchorTopLeft()
        local point, _, relPoint, x, y = self:GetPoint()
        local c = RG.Cfg(); if c then c.pos = {point = point, relPoint = relPoint, x = x, y = y} end
    end)

    local title = fontize(win:CreateFontString(nil, "OVERLAY"), 9, "OUTLINE")
    title:SetPoint("TOPLEFT", 5, -3); title:SetText("GROUPS"); title:SetTextColor(1, 0.82, 0)
    win.memberCount = fontize(win:CreateFontString(nil, "OVERLAY"), 9, "")
    win.memberCount:SetPoint("TOPRIGHT", -5, -3); win.memberCount:SetTextColor(0.7, 0.72, 0.8)

    local hit = CreateFrame("Button", nil, win)
    hit:SetPoint("TOPLEFT", 1, -1); hit:SetPoint("TOPRIGHT", -1, -1); hit:SetHeight(HDR_H - 2)
    hit:RegisterForDrag("LeftButton")
    hit:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    hit:SetScript("OnDragStart", function() local f = win:GetScript("OnDragStart"); if f then f(win) end end)
    hit:SetScript("OnDragStop", function() local f = win:GetScript("OnDragStop"); if f then f(win) end end)
    hit:SetScript("OnClick", function(self, button) if button == "RightButton" then openWindowMenu(self) end end)
    hit:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:AddLine("Raid Groups", 1, 0.82, 0)
        GameTooltip:AddLine("Click a name: target", 1, 1, 1)
        GameTooltip:AddLine("Right-click a name: options", 0.75, 0.78, 0.88)
        GameTooltip:AddLine("Right-click here: window options", 0.75, 0.78, 0.88)
        GameTooltip:Show()
    end)
    hit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win:SetScript("OnUpdate", function(self, elapsed)
        self.acc = (self.acc or 0) + elapsed
        if self.acc < 0.25 then return end
        self.acc = 0
        refreshValues()
    end)

    RG.OnChanged(refresh)
    win:Hide()
    refresh()
    return win
end

function RG.ShowWindow()
    if InCombatLockdown() then AIP.Print("The Raid Groups window can't be opened during combat.") return end
    ensureWindow()
    local c = RG.Cfg(); if c then c.shown = true end
    if AIP.UI and AIP.UI.FadeIn then AIP.UI.FadeIn(win, 0.15, 1) else win:Show() end
    refresh()
end

function RG.HideWindow()
    if InCombatLockdown() then AIP.Print("The Raid Groups window can't be closed during combat.") return end
    if win then win:Hide() end
    local c = RG.Cfg(); if c then c.shown = false end
end

function RG.ToggleWindow()
    if win and win:IsShown() then RG.HideWindow() else RG.ShowWindow() end
end

function RG.IsWindowShown() return win ~= nil and win:IsShown() end

local pendingInit = false
local function initWindow()
    if InCombatLockdown() then pendingInit = true; return end
    pendingInit = false
    ensureWindow()
    local c = RG.Cfg()
    if c and c.shown then win:Show(); refresh() end
end

if AIP.Utils and AIP.Utils.Events and AIP.Utils.Events.Register then
    AIP.Utils.Events.Register("PLAYER_LOGIN", initWindow, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_REGEN_ENABLED", function() if pendingInit then initWindow() end end, "RaidGroupsUI")
    AIP.Utils.Events.Register("PLAYER_TARGET_CHANGED", function() refreshValues() end, "RaidGroupsUI")
end
```

- [ ] **Step 2: Register the file in the .toc**

In `AutoInvitePlus/AutoInvitePlus.toc`, Edit:

old_string:
```
ui\TankCastConfig.lua
```
new_string:
```
ui\TankCastConfig.lua
ui\RaidGroupsWindow.lua
```

- [ ] **Step 3: Syntax check + regression**

Run the syntax check on `AutoInvitePlus/ui/RaidGroupsWindow.lua`. Run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua` (both must be green - this file only reads `AIP.TankCast`, never writes it).
Expected: `OK`; both suites `0 failed`.

- [ ] **Step 4: Checkpoint (live deferred to Task 4)**

**Do not commit.**

---

### Task 3: Consolidate the main window title bar; extend the minimap menu (no duplicates)

**Files:**
- Modify: `AutoInvitePlus/ui/CentralGUI.lua`

**Interfaces:**
- Consumes: `AIP.RaidGroups.ToggleWindow` (guarded).
- Produces: no new public interface - this task only reorganises existing UI.

- [ ] **Step 1: Remove the seven per-button title-bar quick buttons; always show the "..." menu**

In `AutoInvitePlus/ui/CentralGUI.lua`, Edit (removes `titleBtn` and all seven `qXxx` buttons - the helper is only used by them):

old_string:
```
    -- Quick raid buttons in the title bar - stay visible even when minimized.
    local function titleBtn(text, w, ref, ofs, onClick, tip)
        local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        b:SetSize(w, 18); b:SetText(text)
        b:SetPoint("RIGHT", ref, "LEFT", ofs, 0)
        b:SetScript("OnClick", onClick)
        b:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tip); GameTooltip:Show() end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return b
    end
    -- Simplified View toggle - lives in the title bar (not the tab bar)
```
new_string:
```
    -- Simplified View toggle - lives in the title bar (not the tab bar)
```

Then Edit (delete the seven button constructions and the now-obsolete comment above `quickTitleButtons`):

old_string:
```
    local qTools = titleBtn("Rolls", 46, simpleBtn, -3,
        function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end,
        "Raid Tools (roll window)")
    local qBreak = titleBtn("Break", 44, qTools, -3,
        function() if AIP.DBMBridge then AIP.DBMBridge.SendBreak(5) end end, "5-minute break timer")
    local qPull = titleBtn("Pull", 40, qBreak, -3,
        function() if AIP.DBMBridge then AIP.DBMBridge.SendPull(10) end end, "Pull timer (10s, DBM-synced)")
    local qRDF = titleBtn("RDF", 40, qPull, -3,
        function() if AIP.LFGWatch and AIP.LFGWatch.Toggle then AIP.LFGWatch.Toggle() end end,
        "Toggle the Dungeon Finder queue window")
    local qBar = titleBtn("Bar", 38, qRDF, -3,
        function() if AIP.RaidTools and AIP.RaidTools.ToggleBar then AIP.RaidTools.ToggleBar() end end,
        "Toggle the floating announcement bar")
    local qReady = titleBtn("Ready", 52, qBar, -3,
        function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end,
        "Start a ready check")
    local qTanks = titleBtn("Tanks", 46, qReady, -3,
        function() if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end end,
        "Tank Cast window: set the main/off tanks and cast a spell on them")

    -- Simplified View shrinks the window to GUI.SIMPLIFIED_WIDTH (380px),
    -- which isn't wide enough for "AutoInvite+ by iuGames" plus all six
    -- text quick-buttons above without them overlapping the title - so in
    -- that mode they're replaced by this single dropdown button instead.
    -- Full View has room (1000px default) and keeps the buttons as-is.
    frame.quickTitleButtons = {qTools, qBreak, qPull, qRDF, qBar, qReady, qTanks}

    local quickActionsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    quickActionsBtn:SetSize(28, 18)
    quickActionsBtn:SetText("...")
    quickActionsBtn:SetPoint("RIGHT", simpleBtn, "LEFT", -3, 0)
    quickActionsBtn:Hide()
    quickActionsBtn:SetScript("OnClick", function(self)
        if not GUI.TitlebarQuickMenu then
            GUI.TitlebarQuickMenu = CreateFrame("Frame", "AIPTitlebarQuickMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local menuList = {
            {text = "Quick Actions", isTitle = true, notCheckable = true},
            {text = "Start Ready Check", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end},
            {text = "Toggle Announcement Bar", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleBar then AIP.RaidTools.ToggleBar() end end},
            {text = "Toggle Dungeon Finder (RDF)", notCheckable = true,
                func = function() if AIP.LFGWatch and AIP.LFGWatch.Toggle then AIP.LFGWatch.Toggle() end end},
            {text = "Pull Timer (10s)", notCheckable = true,
                func = function() if AIP.DBMBridge then AIP.DBMBridge.SendPull(10) end end},
            {text = "Break Timer (5m)", notCheckable = true,
                func = function() if AIP.DBMBridge then AIP.DBMBridge.SendBreak(5) end end},
            {text = "Roll Window", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end},
            {text = "Tank Cast Window", notCheckable = true,
                func = function() if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end end},
            {text = " ", disabled = true, notCheckable = true},
            {text = "Cancel", notCheckable = true},
        }
        EasyMenu(menuList, GUI.TitlebarQuickMenu, self, 0, 0, "MENU")
    end)
    quickActionsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quick Actions")
        GameTooltip:AddLine("Ready Check, Bar, RDF, Pull, Break, Rolls, Tanks", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    quickActionsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.quickActionsBtn = quickActionsBtn
```
new_string:
```
    -- Title bar consolidation: every quick action lives in this ONE "..." button,
    -- in BOTH Full and Simplified view (Simplified needed it first purely for
    -- width; Full View gets it too now so the title bar never has to grow to fit
    -- a per-feature button again - see GUI.ToggleSimplifiedView, which used to
    -- swap a row of buttons for this and now just always shows it).
    local quickActionsBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    quickActionsBtn:SetSize(28, 18)
    quickActionsBtn:SetText("...")
    quickActionsBtn:SetPoint("RIGHT", simpleBtn, "LEFT", -3, 0)
    quickActionsBtn:SetScript("OnClick", function(self)
        if not GUI.TitlebarQuickMenu then
            GUI.TitlebarQuickMenu = CreateFrame("Frame", "AIPTitlebarQuickMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local menuList = {
            {text = "Quick Actions", isTitle = true, notCheckable = true},
            {text = "Start Ready Check", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end end},
            {text = "Toggle Announcement Bar", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleBar then AIP.RaidTools.ToggleBar() end end},
            {text = "Toggle Dungeon Finder (RDF)", notCheckable = true,
                func = function() if AIP.LFGWatch and AIP.LFGWatch.Toggle then AIP.LFGWatch.Toggle() end end},
            {text = "Pull Timer (10s)", notCheckable = true,
                func = function() if AIP.DBMBridge then AIP.DBMBridge.SendPull(10) end end},
            {text = "Break Timer (5m)", notCheckable = true,
                func = function() if AIP.DBMBridge then AIP.DBMBridge.SendBreak(5) end end},
            {text = "Roll Window", notCheckable = true,
                func = function() if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end end},
            {text = "Tank Cast Window", notCheckable = true,
                func = function() if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end end},
            {text = "Raid Groups Window", notCheckable = true,
                func = function() if AIP.RaidGroups and AIP.RaidGroups.ToggleWindow then AIP.RaidGroups.ToggleWindow() end end},
            {text = " ", disabled = true, notCheckable = true},
            {text = "Cancel", notCheckable = true},
        }
        EasyMenu(menuList, GUI.TitlebarQuickMenu, self, 0, 0, "MENU")
    end)
    quickActionsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Quick Actions")
        GameTooltip:AddLine("Ready Check, Bar, RDF, Pull, Break, Rolls, Tanks, Groups", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    quickActionsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame.quickActionsBtn = quickActionsBtn
```

- [ ] **Step 2: Delete the now-dead simplified-view branch for the removed buttons**

In `AutoInvitePlus/ui/CentralGUI.lua`, Edit:

old_string:
```
    -- Title bar: swap the six text quick-buttons for a single "..." dropdown
    -- (see GUI.CreateFrame) so they don't overlap "AutoInvite+ by iuGames" at
    -- the narrow Simplified width. Full View has room and keeps the buttons.
    if frame.quickTitleButtons then
        for _, btn in ipairs(frame.quickTitleButtons) do
            if enabled then btn:Hide() else btn:Show() end
        end
    end
    if frame.quickActionsBtn then
        if enabled then frame.quickActionsBtn:Show() else frame.quickActionsBtn:Hide() end
    end

```
new_string:
```

```

(The "..." button is now unconditionally shown at creation - see Step 1 - and never touched by the simplified-view toggle at all, so both of these branches are removed rather than inverted.)

- [ ] **Step 3: Minimap - Shift-click toggles Raid Groups; extend the tooltip**

In `AutoInvitePlus/ui/CentralGUI.lua`, Edit:

old_string:
```
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            GUI.Toggle()
        elseif button == "RightButton" then
            -- Show quick menu
            GUI.ShowQuickMenu(self)
        end
    end)
```
new_string:
```
    button:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            if IsShiftKeyDown() then
                if AIP.RaidGroups and AIP.RaidGroups.ToggleWindow then AIP.RaidGroups.ToggleWindow() end
            else
                GUI.Toggle()
            end
        elseif button == "RightButton" then
            -- Show quick menu
            GUI.ShowQuickMenu(self)
        end
    end)
```

Then Edit (tooltip hint):

old_string:
```
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open main window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Quick menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
```
new_string:
```
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFFFFFFFLeft-click:|r Open main window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFShift-click:|r Raid Groups window", 0.7, 0.7, 0.7)
        GameTooltip:AddLine("|cFFFFFFFFRight-click:|r Quick menu", 0.7, 0.7, 0.7)
        GameTooltip:Show()
```

- [ ] **Step 4: Minimap quick menu - add the "Windows" and "Raid Tools" sections (nothing duplicated)**

In `AutoInvitePlus/ui/CentralGUI.lua`, Edit (insert two new sections between the existing "Toggles" section and the existing "Actions" section; "Raid Tools Bar" under "Toggles" is untouched, so it is not duplicated by the new "Windows" section's own entries):

old_string:
```
        {text = "Actions", isTitle = true, notCheckable = true},
        {text = "Spam Invite Message", func = function() AIP.SpamInvite() end, notCheckable = true},
```
new_string:
```
        {text = "Windows", isTitle = true, notCheckable = true},
        {text = "Roll Window", func = function()
            if AIP.RaidTools and AIP.RaidTools.ToggleRollWindow then AIP.RaidTools.ToggleRollWindow() end
        end, notCheckable = true},
        {text = "Tank Cast Window", func = function()
            if AIP.TankCast and AIP.TankCast.ToggleWindow then AIP.TankCast.ToggleWindow() end
        end, notCheckable = true},
        {text = "Raid Groups Window", func = function()
            if AIP.RaidGroups and AIP.RaidGroups.ToggleWindow then AIP.RaidGroups.ToggleWindow() end
        end, notCheckable = true},
        {text = "Toggle Dungeon Finder (RDF)", func = function()
            if AIP.LFGWatch and AIP.LFGWatch.Toggle then AIP.LFGWatch.Toggle() end
        end, notCheckable = true},
        {text = "Raid Tools", isTitle = true, notCheckable = true},
        {text = "Start Ready Check", func = function()
            if AIP.RaidTools and AIP.RaidTools.StartReadyCheck then AIP.RaidTools.StartReadyCheck() end
        end, notCheckable = true},
        {text = "Pull Timer (10s)", func = function() if AIP.DBMBridge then AIP.DBMBridge.SendPull(10) end end, notCheckable = true},
        {text = "Break Timer (5m)", func = function() if AIP.DBMBridge then AIP.DBMBridge.SendBreak(5) end end, notCheckable = true},
        {text = "Actions", isTitle = true, notCheckable = true},
        {text = "Spam Invite Message", func = function() AIP.SpamInvite() end, notCheckable = true},
```

- [ ] **Step 5: Checkpoint - no-duplication check + regression**

Run the syntax check on `AutoInvitePlus/ui/CentralGUI.lua`. Then verify no id/label is duplicated **within either single menu** and that the title-bar "..." menu and the minimap quick menu between them cover the same seven original actions plus Raid Groups exactly once each (this is the Review Focus #3 check - do it by inspection, listing both menus' entries side by side):

Title-bar "..." menu (8 rows): Start Ready Check, Toggle Announcement Bar, Toggle Dungeon Finder (RDF), Pull Timer (10s), Break Timer (5m), Roll Window, Tank Cast Window, Raid Groups Window.
Minimap quick menu's new rows (7, spread across "Windows" + "Raid Tools"): Roll Window, Tank Cast Window, Raid Groups Window, Toggle Dungeon Finder (RDF), Start Ready Check, Pull Timer (10s), Break Timer (5m). Plus the pre-existing, untouched "Raid Tools Bar" checkbox under "Toggles" (this is the ONE entry that intentionally appears once in the minimap menu and is represented in the title-bar menu by the differently-worded "Toggle Announcement Bar" - both control the same `AIP.RaidTools.ToggleBar`, which is expected and fine: the "no duplication" rule is about not having the SAME wording twice in the SAME menu, and about the minimap menu not gaining a second "Raid Tools Bar" row - confirm exactly one "Raid Tools Bar"-labelled row exists in the whole minimap menu).
Expected: `OK` from the syntax check; the manual list above matches what Step 1 and Step 4's new_strings actually contain (re-read the file if in doubt - do not rely on memory of this plan).

Run `luajit tools/tests/tankcast_spec.lua` and `luajit tools/tests/raidgroups_spec.lua` as a final regression (neither test file touches `CentralGUI.lua`, so this only confirms Task 3 didn't corrupt something these tests would catch indirectly - e.g. a Lua error at file scope breaking the whole addon load order is NOT caught by these tests, which is exactly why the syntax check above is not optional).
Expected: both `0 failed`.

**Do not commit.**

---

### Task 4: Docs, deploy, live verification, final review

**Files:**
- Modify: `AutoInvitePlus/CLAUDE.md` (new `RaidGroups` bullet before the `Updater` bullet; a note in the title-bar section that quick buttons are consolidated)
- Modify: repo-root `CLAUDE.md` (add `RaidGroups` to the modules list)

- [ ] **Step 1: Document the module**

In `AutoInvitePlus/CLAUDE.md`, Edit:

old_string:
```
  - **`Updater`** (`AIP.Updater`) is version-check-only
```
new_string:
```
  - **`RaidGroups`** (`AIP.RaidGroups`, `/aip groups`) is the Raid Groups window: a compact, class-coloured "who's in what group" panel read live from the roster (nothing persisted but window position/lock). "Manager" = raid leader OR assistant (`snap.canManage`) - matches what the game itself lets rearrange groups/set MT-MA; promote/demote/master-looter/uninvite/convert stay leader-only (`snap.isLeader`). Non-managers see only non-empty groups (`RG.VisibleGroups`); managers see all 8, including empty ones, and can drag a cell to another group (`RG.PlanMove` -> `SetRaidSubgroup` when the destination has room, `SwapRaidSubgroup` only when dropped on a member of a FULL group) or use "Move to Group N" from the right-click menu. Click a cell targets that player via a secure `/target <Name>` macro; right-click opens `RG.MemberMenu` (whisper/inspect/achievements/trade/follow, Tank Cast shortcuts, MT/MA, move-to-group, and leader-only promote/demote/master looter/uninvite); right-clicking the title bar opens `RG.WindowMenu` (lock, ready check, convert, close). Split like Tank Cast: `modules/RaidGroups.lua` (headless logic incl. the grid-layout math `RG.GridSize`/`RG.ComputeLayout`, unit-tested by `luajit tools/tests/raidgroups_spec.lua`) and `ui/RaidGroupsWindow.lua` (presentation; reuses `AIP.TankCast`'s skin helpers when present, guarded). Same combat rules as Tank Cast: member cells are `SecureActionButtonTemplate`, created on demand, and all structural changes (attributes/Show/Hide/SetPoint/creation) happen only `not InCombatLockdown()`, deferring to `PLAYER_REGEN_ENABLED`. Opened from the main window's consolidated "..." title-bar menu, Shift+left-click on the minimap button, or the minimap's right-click quick menu.
  - **`Updater`** (`AIP.Updater`) is version-check-only
```

In repo-root `CLAUDE.md`, Edit:

old_string:
```
PostPull, Rotation, LFGWatch, CharacterCard, TankCast, TestData
```
new_string:
```
PostPull, Rotation, LFGWatch, CharacterCard, TankCast, RaidGroups, TestData
```

- [ ] **Step 2: Syntax check + full regression**

Run the syntax check on every touched/created file: `AutoInvitePlus/modules/RaidGroups.lua`, `AutoInvitePlus/ui/RaidGroupsWindow.lua`, `AutoInvitePlus/ui/CentralGUI.lua`, `AutoInvitePlus/core/Core.lua`, `AutoInvitePlus/AutoInvitePlus.toc` is not Lua (skip), `tools/tests/raidgroups_spec.lua`.
Run `luajit tools/tests/raidgroups_spec.lua` and `luajit tools/tests/tankcast_spec.lua`.
Expected: all `OK`; both suites `0 failed`.

- [ ] **Step 3: Deploy and confirm the client has the new module**

Run the live loop (`Sync-Addon`, `/reload`). Then via the harness: `Run-WowLua 'UIErrorsFrame:AddMessage("RG="..tostring(AutoInvitePlus.RaidGroups~=nil).." win="..tostring(AIPRaidGroupsWindow~=nil),1,1,0)'` and screenshot.
Expected: `RG=true win=true` (files are already in the `.toc`, so a plain `/reload` - not a client restart - is enough, per the Global Constraints note).

- [ ] **Step 4: Live checks (solo/party; note each result)**

With `/console scriptErrors 1`:
1. Title bar: open the main window, click "...", confirm "Raid Groups Window" appears and toggles the window; confirm the seven pre-existing rows are still there and unchanged in wording.
2. Minimap: hover shows the new Shift-click hint; Shift-left-click toggles the Raid Groups window; right-click shows "Windows" and "Raid Tools" sections with the entries from Task 3 Step 4, and exactly one "Raid Tools Bar" row (under "Toggles", unmoved).
3. `/aip groups` toggles the same window. Solo: one group with just you, a class-coloured cell, no manage powers even if `/run` tricks make `UnitIsPartyLeader` true (not applicable solo, but confirms Task 1's `canManage` design holds).
4. Click your own cell -> you become your own target (harmless but proves the secure macro fires). Right-click -> menu shows inspect/achievements but not whisper/trade/follow (Review Focus doesn't cover this directly but it's the cheapest possible sanity check of `RG.MemberMenu`'s self-exclusion).
5. Right-click the title bar -> window menu shows Lock/Unlock and Close but not Ready Check (solo -> `canManage` false) or Convert (not `isLeader` in the raid sense).
6. Lock via the menu; confirm the window can no longer be dragged; unlock; confirm it can again.
7. `/reload` with the window open -> position, lock and open/closed state persist.
Expected: no Lua errors at any step.

- [ ] **Step 5: Final whole-branch review**

Dispatch a fresh reviewer on the most capable model (`Agent`, `model: "fable"`) with: this plan and the spec, the full file list from Tasks 1-4, this plan's **Review Focus** section verbatim, and the instruction to be read-only and rank findings Critical/Important/Minor with a concrete failure scenario - checking especially: combat-lockdown correctness of the new cell/group/window frames and the drag path, `RG.PlanMove`'s set-vs-swap boundary, the manager-visibility rule never leaking an empty group to a non-manager, and that Task 3 truly introduced no duplicate menu entry. Re-grade its findings by effect; fix Critical/Important with a test where headless-testable (or a live check otherwise); ledger Minors as deferred in the final message.

- [ ] **Step 6: Final report**

Summarise: files created/changed, what was live-verified vs not (raid-only behaviour - manager view, drag/drop and swap, promote/demote/master looter/uninvite/ready check/convert - needs a real raid and should be reported as not live-verified unless the user can test with a group), the rulings made, the deferred minors, and that nothing is committed (offer to commit).
