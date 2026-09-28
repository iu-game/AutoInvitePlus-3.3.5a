# Raid Groups Window — Design

Date: 2026-09-27
Status: Draft, awaiting user review

## Goal

A small, beautiful floating window that lists everyone in the player's raid/party
**grouped by raid subgroup**, as class-coloured name cells. Clicking a cell targets the
player. Raid managers (leader / assistants) see all 8 groups and can move players between
groups (drag-and-drop or menu) and use the same per-player options as Blizzard's default
raid frame. Toggled from the main window's title bar, the minimap button and `/aip groups`.
Deliberately compact.

## Decisions (from brainstorming)

- **New subsystem** in two files, mirroring the Tank Cast split:
  `modules/RaidGroups.lua` (`AIP.RaidGroups`, "RG": headless, unit-tested) and
  `ui/RaidGroupsWindow.lua` (presentation). Reuses the Tank Cast skin helpers
  (`AIP.TankCast.SkinPanel/SkinHeader/CloseButton/Fontize`) when present.
- **"Manager" = raid leader OR assistant** (the game lets both rearrange groups and set
  Main Tank / Main Assist). **Leader-only:** promote/demote, make leader, master looter,
  uninvite, convert raid <-> party.
- **Names only** in the cells; group numbers live in tooltips. No health bars, no raid
  target markers (kept compact; can be added later).
- **Targeting** uses a secure `/target <Name>` macro (name, not roster token), so it works
  in combat and survives roster reshuffles.
- **Moves** use `SetRaidSubgroup` (room in the target group) or `SwapRaidSubgroup`
  (dropped on a member of a full group). This fixes the existing Composition tab's
  failure on full groups.

## Non-goals

Raid target markers, health/mana bars, spec text in cells, pets, saving/loading
compositions (the Composition tab keeps that), party-frame replacement.

## 1. Saved state

`AIP.db.raidGroups = { shown = false, locked = false, pos = nil }` (defaults in
`core/Core.lua`; no `DB_VERSION` bump). `pos = {point, relPoint, x, y}`; the window is
anchored **top-left** so it grows right/down.

## 2. Logic module (`modules/RaidGroups.lua`, headless)

Constants: `MAX_GROUPS = 8`, `GROUP_SIZE = 5`.

**`RG.Snapshot()`** reads the roster and returns:
```lua
{ mode = "raid" | "party" | "solo",
  members = { {name, unit, class, level, group, index, rank, role, isML, online, dead, isSelf}, ... },
  groups  = { [1..8] = { member, ... } },       -- members ordered by raid index
  counts  = { [1..8] = n },
  myRank = 0|1|2, canManage = bool, isLeader = bool }
```
- Raid: `GetRaidRosterInfo(i)` (name, rank, subgroup, level, class, fileName, zone, online,
  isDead, role, isML); `unit = "raid"..i`; `index = i`.
- Party/solo: `player`, `party1..4`, all in group 1; rank 2 for the party leader
  (`UnitIsPartyLeader`), else 0. `canManage` is raid-only.
- `class` is the class **file** name (`WARRIOR`...), used for `RAID_CLASS_COLORS`.

**Visibility.** `RG.VisibleGroups(snap)`: manager in a raid -> `{1..8}`; everyone else ->
the non-empty groups ascending (party/solo -> `{1}`).

**Layout.** `RG.GridSize(n)`: columns `n<=4 -> n`, else `ceil(n/2)` (max 4); rows
`ceil(n/cols)`. `RG.ComputeLayout(visible, snap, dims)` -> `{w, h, groups = {[k] = {group,
x, y, w, h, rows}}}` where a group's height is `rowsShown * (cellH + gap) - gap`
(`rowsShown` = 5 for a manager, else the group's member count; a grid row is as tall as its
tallest group). Cell position inside a group: `y + (m-1) * (cellH + gap)`.

**Move planning.** `RG.PlanMove(snap, fromName, target)` with `target = {group = n}` or
`{name = "X"}`:
- refuse (`nil, reason`) unless `snap.mode == "raid"` and `snap.canManage`; unknown player;
  target in the same group ("already in that group");
- target group with < 5 members -> `{op = "set", index, group}` (even when dropped on a
  member);
- full group + a target member -> `{op = "swap", index1, index2}`;
- full group + no member -> `nil, "Group N is full - drop on a member to swap."`
`RG.ExecMove(plan)` calls `SetRaidSubgroup(index, group)` / `SwapRaidSubgroup(i1, i2)`.

**Menu model** (the UI maps ids to actions):
- `RG.MemberMenu(snap, member, hasTankCast)` -> ordered `{id, text, enabled}`:
  everyone: `whisper, inspect, achievements, trade, follow` (not for yourself except
  inspect/achievements), and, when `hasTankCast`, `tank_mt`, `tank_ot`; managers (raid):
  `set_mt, clear_mt, set_ma, clear_ma` and `move_1..move_8` (disabled for the current group
  or a full one); leader (raid): `promote_leader`, `promote_assist` **or** `demote_assist`,
  `master_looter`, `uninvite` (not yourself).
- `RG.WindowMenu(snap, locked)` -> `lock`/`unlock`; managers `ready_check`; leader
  `convert_party` (raid with <= 5 members) / `convert_raid` (party); `close`.
`RG.RankLabel(rank)` -> "Raid leader" / "Assistant" / "Member".
`RG.SlashHandler(rest)`: `/aip groups` toggles; `lock` / `unlock`.

All roster/permission APIs are stubbed in the headless tests; nothing in this module
creates frames.

## 3. Window (`ui/RaidGroupsWindow.lua`)

- **Shell:** 14px title bar (shield-less: "GROUPS" + member count `23/25`) + the shared
  panel skin; `x` close button; drag by the title/background unless locked; fade in.
- **Cells (74x15, gap 1; groups gap 3; pad 3):** class-coloured background
  (`RAID_CLASS_COLORS`, ~0.85 alpha) with the name in white outline; **offline** = grey
  overlay, **dead** = dark overlay, **current target** = gold border. Manager view adds a tiny
  rank marker (gold = leader, white = assistant) and `MT`/`MA` tag.
- **Groups:** stacks of up to 5 cells, packed by `RG.GridSize`. Manager view draws empty
  slots as faint drop targets. Non-managers see only non-empty groups; party = one group.
- **Tooltip** on a cell: name (class colour), level + class, **"Group N"**, rank, MT/MA,
  Offline/Dead, then hints (click = target, right-click = options, and for managers
  drag = move). Empty slot: "Group N (empty)".
- **Click** targets (secure macro). **Right-click** a cell -> member menu (section 2).
  **Right-click** the title/background -> window menu (lock, ready check, convert, close).
- **Drag (managers):** `RegisterForDrag("LeftButton")` on the cell; a small class-coloured
  name tag follows the cursor; the hovered group is highlighted; on release the drop target
  is the cell/slot under the cursor (`IsMouseOver`) -> `RG.PlanMove` -> `RG.ExecMove`, or a
  message explaining the refusal. Moves are refused while a layout change is pending
  (`RG.dirty`), as in Tank Cast.
- **Actions:** Whisper (`ChatFrame_SendTell`), Inspect (`InspectUnit`), Achievements
  (`InspectAchievements`), Trade (`InitiateTrade`), Follow (`FollowUnit`), Set/Clear MT/MA
  (`SetPartyAssignment` / `ClearPartyAssignment`), promote/demote (`PromoteToLeader`,
  `PromoteToAssistant`, `DemoteAssistant`), master looter (`SetLootMethod("master", name)`),
  uninvite (`UninviteUnit`, behind a Yes/No popup), ready check (`DoReadyCheck`), convert
  (`ConvertToRaid` / `ConvertToParty`), Tank Cast (`AIP.TankCast.SetSlot(1, name)` /
  `SetFirstOT(name)`, guarded).
- **Secure/combat rules (same as Tank Cast):** the 40 member cells are
  `SecureActionButtonTemplate` (`type1="macro"`, `macrotext1="/target <Name>"`), so
  attributes, Show/Hide and SetPoint of cells, group frames and the window happen **only
  when `not InCombatLockdown()`**; frames are created out of combat at `PLAYER_LOGIN`
  (deferred to `PLAYER_REGEN_ENABLED` if the UI loaded in combat). Roster changes in combat
  set `RG.dirty` and flush after combat; cells render from a snapshot, but dead / offline /
  target state is read live by **name** each 0.25 s tick. Only textures/font strings change
  in combat.
- **Events:** `RAID_ROSTER_UPDATE`, `PARTY_MEMBERS_CHANGED`, `PARTY_LEADER_CHANGED`,
  `PLAYER_ENTERING_WORLD`, `PLAYER_REGEN_ENABLED`, `PLAYER_TARGET_CHANGED` via
  `AIP.Utils.Events`.

## 4. Integration

**Title bar consolidation (revised per user feedback):** the seven individual quick
buttons (Rolls, Break, Pull, RDF, Bar, Ready, Tanks) are removed from the title bar
entirely - not just hidden at narrow width. Full View now shows the same single **"..."**
button Simplified View already used (`quickActionsBtn`), always visible in both views.
`frame.quickTitleButtons` and the per-view show/hide branch for it are deleted; the
`titleBtn(...)` helper and chrome (minimize/maximize/close/Simplified-View-density toggle)
are unaffected. The button's menu gains **Raid Groups Window** as a new row (after "Tank
Cast Window"); everything else in it is unchanged.

**Minimap quick menu** (`GUI.ShowQuickMenu`) gains the same window/action toggles, organised
into new sections so nothing already there is duplicated - "Raid Tools Bar" stays exactly
where it is under the existing **Toggles** section:

```
AutoInvite+                         (title)
Open Main Window                                  <- unchanged
Toggles                             (title)
  [x] Auto-Invite                                  <- unchanged
  [x] Raid Tools Bar                               <- unchanged (NOT duplicated below)
Windows                             (title, NEW)
  Roll Window
  Tank Cast Window
  Raid Groups Window
  Toggle Dungeon Finder (RDF)
Raid Tools                          (title, NEW)
  Start Ready Check
  Pull Timer (10s)
  Break Timer (5m)
Actions                             (title)
  Spam Invite Message / Invite Guild / Invite Friends   <- unchanged
Cancel
```

Every entry from the old title-bar menu now appears in exactly one place in the minimap
menu (as well as in the title bar's own "..." menu) - none are dropped, none are doubled.
Both menus are built from one shared list in `RaidGroups.lua`/`CentralGUI.lua` (or a small
shared helper) so the two never drift apart.

- **Toolbar:** the "..." button's menu (section above) gains the Raid Groups row; no new
  title-bar button.
- **Minimap:** Shift + left-click toggles the Raid Groups window directly; the tooltip
  gains a "Shift-click: Raid groups" line; the right-click quick menu is reorganised as above.
- **Slash:** `/aip groups [lock|unlock]`; `help` documents it.
- **`.toc`:** `modules\RaidGroups.lua` after `modules\TankCast.lua`;
  `ui\RaidGroupsWindow.lua` after `ui\TankCastConfig.lua`.
- **Docs:** `AutoInvitePlus/CLAUDE.md` bullet + repo-root module list; a note in the title-bar
  section that the quick buttons were consolidated into the "..." menu.

## 5. Testing / verification

Headless (`tools/tests/raidgroups_spec.lua`, LuaJIT): snapshot for raid/party/solo (ranks,
groups, ordering, roles); visibility rules (manager vs member, empty groups); `GridSize` and
`ComputeLayout` (1..8 groups, row heights, non-manager vs manager); `PlanMove` (set, swap,
full group, same group, permission, unknown player); `ExecMove` call routing; both menu
models per rank (leader / assistant / member / self, `hasTankCast`); slash handler.

Live (needs the client; a solo/party check is possible here): open from the toolbar, the
minimap (Shift-click) and `/aip groups`; targeting click; lock via right-click; layout; party
view. **Not verifiable without a group:** manager view, drag/drop and swap, promote/kick
menus, master looter, raid ready check -> report as not live-verified.

## 6. Risks

- The title bar is already crowded; an 8th button may overlap at the minimum main-window
  width (check live; fold into the `...` menu if needed).
- `RegisterForDrag` on a secure button with a click macro: a drag must not also fire the
  `/target` (verify live).
- `GetMouseFocus`/`IsMouseOver` drop detection and `SetRaidSubgroup` behaviour with a
  full target group (handled by the swap path) need a real raid to confirm.
- `UnitIsPartyLeader`, `ClearPartyAssignment`, `InspectAchievements`, `InitiateTrade`
  availability/signatures on 3.3.5a are checked defensively (`if fn then ... end`).
