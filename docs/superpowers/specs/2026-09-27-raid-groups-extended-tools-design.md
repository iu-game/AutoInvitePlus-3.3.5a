# Raid Groups — Extended Player Tools — Design

Date: 2026-09-27
Status: Draft, awaiting user review
Extends: `2026-09-27-raid-groups-window-design.md` (the shipped Raid Groups window). Everything
here adds to that window; nothing in the base spec changes.

## Goal

Give the Raid Groups window: a richer context menu for every viewer; raid target icons for
managers; a per-player note that is either private (local) or a manager-broadcast
"assignment" with a toast notification; a group-position lock separate from the existing
window-position lock; visible debuff icons plus an extensive buff/debuff tooltip for
everyone; a personal "you're missing a buff you can give" indicator; and click-to-cast
quick buffs/heals on any player.

## Governing rule (from brainstorming)

**Prefer a live game-interface query over DataBus whenever one exists; DataBus is used
only for information the client genuinely cannot query, and never overrides what a live
query says.** Concretely: raid target icons, buffs, debuffs, roster/rank/role, and spec all
come straight from WoW's own API (`GetRaidTargetIndex`, `UnitBuff`/`UnitDebuff`,
`GetRaidRosterInfo`, inspect) exactly as the base window already does. The **only** thing
that goes over DataBus in this feature is the shared assignment note/text, because there is
no native WoW concept of "an arbitrary text tag on a raid member" for a query to return. If
this were ever to change, the live query wins.

## Decisions (from brainstorming)

- **Notes: both kinds.** A private note (anyone can set, on anyone, local only, persisted)
  and a manager-set "assignment" (leader/assistant only, broadcast to the raid's other AIP
  users over DataBus, shown as a toast). Both display in the tooltip.
- **Buff/heal helper: both.** A read-only "you personally are missing a buff for this
  player" indicator, AND configurable click-to-cast quick-cast slots on every cell.
- **Aura display: debuffs as icons, everything else in the tooltip.** Up to 4 small debuff
  icons render under the name; the tooltip lists every buff and debuff (name, icon, stacks,
  time left) plus missing raid buffs.
- **Scope cut (told to the user, standing):** the quick-cast spell/item picker is the
  existing type-a-name/shift-click box, not a rebuild of Tank Cast's icon-grid popup.
- **Reuse boundary:** quick-cast is explicitly built ON `AIP.TankCast`'s existing
  spell/item detection (`ListSpells/ListItems/ResolveSpell/IsFriendlyCastable/BuildMacro/
  GetCooldown/Usability`) - guarded; if Tank Cast is not loaded, quick-cast reports that and
  no-ops, rather than duplicating that engine. Debuff/buff LISTING, by contrast, is
  reimplemented locally in `RaidGroups.lua` (a small, independent scan) rather than made to
  depend on Tank Cast, because it is core to this window and must work even if Tank Cast is
  absent - unlike the optional `tank_mt`/`tank_ot` menu shortcuts, which already correctly
  degrade when Tank Cast is missing.
- **Missing-buff indicator is personal**: it lights up only for a raid buff *your own class*
  can provide (cross-referenced against `AIP.Panels.RaidMgmt.ClassBuffs[yourClass]`), not
  "someone is missing something" in general.
- **Raid icon setting stays manager-only** (leader/assistant), matching every other
  structural action in this window; seeing an icon is not restricted.
- **Group-position lock is per-viewer**, not synced - it is a personal "don't let my own
  drags move someone by accident" safety catch, not a raid-wide state.

## Non-goals

Ignore/report from this menu, a full icon-grid quick-cast picker (see scope cut above),
persisting received assignments across a reload (they live exactly as long as DataBus's own
event cache does), more than 2 quick-cast slots, buff icons rendered on the cell (tooltip
only, per the decision above).

## 1. Saved data

Extends `AIP.db.raidGroups` (defaults in `core/Core.lua`; no `DB_VERSION` bump):
```lua
raidGroups = {
    shown, locked, pos,       -- existing (window position lock)
    groupLocked = false,      -- NEW: blocks drag + "Move to Group N" (manager toggle)
    notes = {},               -- NEW: private notes, [lowercaseName] = "text" (persisted)
    quickCast = {},           -- NEW: array of up to 2 spell/item name strings (persisted)
},
```
Received assignments are **not** persisted - they live in an in-memory cache
(`RG.assignments[lowercaseName] = {text, author, time}`), exactly like DataBus's own
`DB.State.receivedEvents`, and are gone on `/reload` until re-broadcast.

## 2. DataBus addition (the one field that needs it)

New entry in `DB.EventTypes` (`core/DataBus.lua`):
```lua
RGNOTE = {
    id = "RGNOTE", name = "Raid Groups Assignment",
    fields = {"player", "note", "author"},
},
```
`RaidGroups.lua` calls `AIP.DataBus.Broadcast(AIP.DataBus.CreateEvent("RGNOTE", {...}))` to
send and `AIP.DataBus.Subscribe("RGNOTE", RG.OnAssignmentEvent, "RaidGroups")` once at load
(guarded - both calls no-op cleanly if DataBus is somehow absent). Existing rate-limiting,
255-byte cap and 10-minute TTL apply unchanged.

## 3. Logic additions (`modules/RaidGroups.lua`, all headless-tested)

**Raid target icons** (interface-only, no DataBus - the server already syncs these):
- `RG.RAID_ICONS = {"Star","Circle","Diamond","Triangle","Moon","Square","Cross","Skull"}`
  (Blizzard's canonical 1-8 order)
- `RG.GetRaidIcon(snap, name) -> index (0 = none) | nil` (unknown name)
- `RG.SetRaidIcon(snap, name, index) -> ok, err` (0-8; requires `snap.canManage`)

**Notes:**
- `RG.GetNote(name) -> text` / `RG.SetNote(name, text) -> ok, err` (anyone; sanitised,
  capped at 60 chars; "" clears it)
- `RG.GetAssignment(name) -> text, author` (from the in-memory cache)
- `RG.SetAssignment(snap, name, text) -> ok, err` (requires `snap.canManage`; sanitises,
  updates the local cache immediately - DataBus never echoes your own broadcasts back to
  you - then calls `AIP.DataBus.Broadcast`, guarded)
- `RG.OnAssignmentEvent(event)` - the DataBus subscriber: updates the cache and fires
  `RG.OnAssignment(fn)` listeners (separate from `RG.OnChanged`, so a toast doesn't need to
  diff a full re-render to know what changed)

**Group-position lock** (mirrors the existing window-position lock, separate flag):
- `RG.IsGroupLocked() / RG.SetGroupLocked(on) / RG.ToggleGroupLocked(snap)` (toggle requires
  `snap.canManage`)
- `RG.PlanMove` gains one more refusal: when `RG.IsGroupLocked()`, return
  `nil, "Group positions are locked."` before any other check.

**Debuffs / buffs / missing-buff indicator** (independent local implementation - see the
reuse-boundary decision above):
- `RG.ListDebuffs(unit, limit) -> list, total` / `RG.ListBuffs(unit, limit) -> list, total`
  (`{name, icon, count, dtype, timeLeft}`, same shape philosophy as Tank Cast's own
  `TK.ListDebuffs`, but this file's own copy)
- `RG.MissingBuffsForViewer(unit) -> array of buff names` (guarded call into
  `AIP.Panels.RaidMgmt.CheckUnitBuffs(unit).missingBuffs`, filtered to buffs
  `AIP.Panels.RaidMgmt.ClassBuffs[yourClass]` lists; `{}` if that panel/module is absent)

**Quick-cast** (thin wrapper around `AIP.TankCast`'s existing engine, guarded throughout):
- `RG.MAX_QUICKCAST = 2`
- `RG.GetQuickCast() -> array (copy)`
- `RG.AddQuickCast(text) -> ok, err` / `RG.SetQuickCast(i, text) -> ok, err` /
  `RG.RemoveQuickCast(i) -> ok, err` (same validation spirit as Tank Cast's picks: sanitise
  via `AIP.TankCast.ParseSpellInput`, reject empty/duplicate, cap at `MAX_QUICKCAST`; if
  `AIP.TankCast` is absent, `ok=false, err="Tank Cast module is required for quick-cast."`)
- `RG.BuildQuickCastMacro(name, spellText) -> macro | nil` (delegates to
  `AIP.TankCast.BuildMacro`, nil if Tank Cast is absent)

**Context-menu model extensions** (`RG.MemberMenu`/`RG.WindowMenu`, same {id,text,enabled}
shape as the base spec):
- Everyone: `focus` ("Set Focus") / `clear_focus`, `add_friend`, `note_private` ("Set
  Note...")
- Managers: `note_assignment` ("Set Assignment..."), a `raid_icon` submenu (modelled as 9
  flat ids `raid_icon_1..8` + `raid_icon_clear` the UI groups into one submenu)
- `RG.WindowMenu` gains `group_lock` (managers only; text flips "Lock Group Positions" /
  "Unlock Group Positions") and `quickcast_config` ("Configure Quick-Cast...", everyone)

## 4. Window additions (`ui/RaidGroupsWindow.lua`)

- **Cell layout:** grows from one line to two: line 1 = raid-icon overlay (if any) + name +
  up to 2 quick-cast icons (12px, secure `/cast [target=Name] <configured spell>` buttons,
  same combat-lockdown rules as every other secure button in this addon); line 2 = up to 4
  small (10px) debuff icons from `RG.ListDebuffs`. A small dot (bottom-right) lights up per
  `RG.MissingBuffsForViewer`.
- **Tooltip:** extends the existing name/class/spec/group/rank/role/state block with: every
  buff and debuff (icon + name + stacks + time left), the private note (if any, "Note:
  ..."), and the assignment (if any, "Assignment: <text> - <author>").
- **Toast bubble:** a new, independent, non-secure frame (`AIPRaidGroupsBubble`) - never
  parented to the protected window, so it is safe to create/show/hide in combat. Shown for
  ~3s (fade via `AIP.UI.FadeIn`/`FadeOut`) reading `"<author>: <text>"` whenever
  `RG.OnAssignment` fires for a player currently visible in your raid. Anchored under the
  Raid Groups window if it exists, else `UIParent` top-centre.
- **Menus:** `doMemberAction`/`openMemberMenu` wire the new ids; `note_private`/
  `note_assignment` open a `StaticPopupDialogs` entry with `hasEditBox = true`; the
  `raid_icon` ids build one submenu list under "Set Raid Icon".
- **Quick-cast config:** `quickcast_config` opens a small text-entry popup (per the stated
  scope cut) that calls `RG.AddQuickCast`/`RG.SetQuickCast`.

## 5. Testing / verification

Headless (extends `tools/tests/raidgroups_spec.lua`): raid-icon get/set + permission;
private note get/set/sanitise/cap; assignment set (permission, cache update, DataBus stub
call recorded) and `OnAssignmentEvent` updating the cache + firing listeners; group-lock
toggle + permission + `PlanMove` refusal; `ListDebuffs`/`ListBuffs` shape and limit;
`MissingBuffsForViewer` filtering by the viewer's class; quick-cast add/set/remove/cap/
dedupe and the "Tank Cast required" fallback message; every new menu id present/absent by
rank exactly like the base spec's menu tests.

Live (solo-checkable here): context-menu rows render and the popups open; own-cell debuff
icons appear when a real debuff is present (can self-apply via a testable ability if
available, or note as best-effort); quick-cast icon casts on yourself; the toast bubble
appears and fades when you set your own assignment (DataBus won't echo it back from itself,
so this checks only the local-cache-update half - the cross-player broadcast half needs a
second player and is reported not-live-verified if unavailable). **Needs a real raid /
second player:** raid icon visibility to another viewer, receiving someone else's
assignment + the toast firing from a network event, group-lock actually blocking a
manager's drag with other real members to drag.

## 6. Risks

- Cell height growing from one line to two roughly doubles vertical space per row; at 40
  visible rows this is a real space cost the user should see live before calling it settled.
- `StaticPopupDialogs` with `hasEditBox = true` on 3.3.5a: field names/behaviour (`editBox`,
  `OnAccept(self, data)` reading `self.editBox:GetText()`) need live confirmation, same
  caveat as the base spec's `AIP_RAIDGROUPS_UNINVITE` popup.
- `SetRaidTarget`/`GetRaidTargetIndex` argument order and the canonical 1-8 icon order need
  live confirmation on this client build.
