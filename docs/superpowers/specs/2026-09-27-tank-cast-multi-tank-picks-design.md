# Tank Cast - Multiple Tanks and Per-Tank Picks (Revision 2)

> **Revision 3 (compact window):** the window was later redesigned for screen space - up to **8 picks per tank** (rows stay one line and the window **widens** with the picks, min 4 slots, anchored top-left; rows and their secure buttons are created on demand, up to **40 tanks** (a raid), flowing into extra columns after 8 rows; each row also has a secure **selector strip** that targets the tank, and a slot may hold a **pet**; the badge tooltip shows name/class/spec/debuffs), rows show only `[health bar][class badge][pick icons][+]` with name/role/health/state in the badge tooltip, a 16px title bar holds every control (add tank, Import, Push, close), and the gear strip, status strip and footer were removed (issues show as a dot in the title bar). Sections 3, 5 and 7 below describe the earlier layout.

Date: 2026-09-27
Status: Draft, awaiting user review
Supersedes (from `2026-09-27-tank-cast-window-design.md`): section 1 (Data), the "one global spell" decision and the "Non-goals" line about per-tank spells / more than 1 MT + 3 OT, section 3 (Window), and the row/config parts of sections 2, 4 and 5. Everything not mentioned here (combat-lockdown rules, sanitising, friendly-target detection, item classification, picker sources, drag-and-drop, Blizzard Import/Push semantics) is unchanged.

## Goal

Let the player keep **more than three off-tanks**, and give **each tank its own list of picks** (several spells/items per tank), each castable on that tank with one click.

## Decisions (from brainstorming)

- Up to **8 tanks**: slot 1 = Main Tank (always exists), slots 2..8 = Off-Tanks, added on demand. `TK.MAX_TANKS = 8`.
- Up to **4 picks per tank**. `TK.MAX_PICKS = 4`. A pick is any spell or item text, chosen with the existing spellbook / bag detection.
- **Picks belong to the slot, not the player**: re-assigning a slot to a different player keeps its picks ("the MT slot always gets Hand of Sacrifice"). Moving a name between slots (dedupe) moves only the name.
- The shared global spell box is removed; per-tank picks replace it.

## Non-goals

Per-tank keybinds, auto-casting, chat output, DataBus sharing, a "copy picks to all tanks" action, more than 8 tanks / 4 picks (constants make it a one-line change, the secure-button pool is sized from them).

## 1. Data (`AIP.db.tankCast`, default shape in `core/Core.lua`, no `DB_VERSION` bump)

```lua
tankCast = {
    tanks = {},          -- array; [1] = MT. Each entry: { name = "", picks = { "Misdirection", ... } }
    shown = false, showConfig = false, pos = nil,
}
```

`TK.Cfg()` repairs the shape on every access: `tanks[1]` always exists; every entry has `name` (string) and `picks` (array of <= MAX_PICKS strings); length is clamped to `MAX_TANKS`.

**Migration (in `TK.Cfg()`, runs once when `tanks` is absent):** from the legacy keys `mt`, `ots` (array of 3) and `spell`:
- `tanks[1] = { name = mt, picks = {} }`; each non-empty `ots[k]` (in order, holes dropped) becomes the next slot.
- If legacy `spell ~= ""`, it becomes the first pick of **every resulting slot** (MT included even when its name is empty).
- The legacy keys are then set to `nil`.

## 2. Logic API (`modules/TankCast.lua`; headless-testable)

Removed: `TK.GetSpell`, `TK.SetSpell`, `TK.SLOTS`, the per-slot `c.mt`/`c.ots` accessors.

| Function | Behaviour |
|---|---|
| `TK.NumTanks()` | number of slots (1..MAX_TANKS) |
| `TK.SlotLabel(i)` | `"MT"` or `"OT"..(i-1)` |
| `TK.GetSlot(i)` | name or `""` |
| `TK.SetSlot(i, name)` | assign/clear the name; sanitising and dedupe (moves a name out of any other slot) as before; returns `ok, err` |
| `TK.AddTank()` | append an empty OT slot -> `index` or `nil, "All 8 tank slots are in use."` |
| `TK.RemoveTank(i)` | i >= 2 only; removes the slot and its picks, shifts later slots down; MT -> `false, "The main tank slot can't be removed."` |
| `TK.SetFirstOT(name)` | no-op if the name is listed; fills the first empty OT slot, else `AddTank()` |
| `TK.GetPicks(i)` | copy of the pick array |
| `TK.AddPick(i, text)` | `ParseSpellInput` -> reject empty, duplicate (case-insensitive) or >= MAX_PICKS; returns `ok, err` |
| `TK.SetPick(i, j, text)` | replace pick j (same validation; a duplicate of another pick is rejected) |
| `TK.RemovePick(i, j)` | remove pick j |
| `TK.AddPickToAll(text)` | add to every slot that has room and lacks it; returns the count |
| `TK.ClearNames()` / `TK.Reset()` | clear all names (keep slots + picks) / back to MT-only with no picks |
| `TK.TrimEmpty()` | drop trailing OT slots with neither name nor picks |

All mutators call `TK.Changed()` only on success. `BuildMacro`, `Sanitize*`, `ParseSpellInput`, `ResolveSpell`, `GetCooldown`, `IsFriendlyCastable`, `ClassifyItem`, `ListSpells`, `ListItems`, `FromCursor`, `ImportFromBlizzard`, `PushToBlizzard` keep their signatures, except:
- `TK.Status(name)` no longer takes a spell and no longer checks range: `"ok" | "away" | "offline" | "dead"`.
- `TK.InRange(name, unit, pick)` is per pick (the pick is required; no global spell to fall back on).
- `ImportFromBlizzard`: MAINTANK -> slot 1, MAINASSIST players -> OT slots (up to `MAX_TANKS-1`, adding slots as needed); all existing **names** are cleared first, **picks are kept**; then `TrimEmpty()`.
- `PushToBlizzard`: iterates every non-empty slot (MT -> MAINTANK, others -> MAINASSIST), skipping flags already set.

## 3. Window (replaces section 3 of the original spec)

Width 210. Each tank is a two-line row (`ROW_H` = 48):

```
+--------------------------------------+
| Tanks                        [gear] [X] |
|--------------------------------------|
| [MT]  Thorgrim                        |  line 1: chip, class-coloured name,
|       ▓▓▓▓▓▓▓▓▓▓▓▓▓░░                |          thin HP bar under the name
|       [ic][ic][ic] [+]                |  line 2: one 22px icon per pick + dim [+]
| [OT1] Bramble                         |
|       ▓▓▓▓▓▓▓▓░░░░░░                  |
|       [ic] [+]                        |
| [OT2] + Set OT2                       |  empty slot (no picks line until named
|       [+]                             |  or picks exist)
| [ + Add off-tank ]                    |  hidden at MAX_TANKS
| L-click cast | R-click edit           |  status line
| [Import] [Push]   (gear strip)        |
+--------------------------------------+
```

- **Pick icons:** each is a `SecureActionButtonTemplate` (`type1="macro"`, `macrotext1="/cast [target=<TankName>] <pick>"`), with its own cooldown sweep, a 1px coloured frame (none = fine, orange = can't target a friendly, red = unknown spell/item), a tooltip (spell/item tooltip + "Cast on <Name>"), and range/dead/offline dimming (range is per pick).
- **Right-click a pick:** menu *Change pick...* (opens the picker for that pick) / *Remove pick*. **Left-click on an empty slot's / no-macro icon** shows a hint.
- **`[+]`** (non-secure) opens the picker to add a pick; hidden at `MAX_PICKS`.
- **Name area** (non-secure button): click opens the tank menu - *Use my target*, *Clear*, *Remove tank* (OT slots only), then the candidate list (tank-capable classes first, capped at 40), as today.
- **`[+ Add off-tank]`** (non-secure) calls `TK.AddTank()`.
- **Drag and drop:** dropping a spell/item on a pick icon replaces it; on `[+]` adds it (`TK.FromCursor`).
- Window height = header + rows + add button + status line + (gear strip when open). No resize grip.
- **Secure pool:** `MAX_TANKS` row containers (plain Frames, each parent of its pick buttons) and `MAX_TANKS * MAX_PICKS` = 32 pick buttons are all created once, out of combat, at login. Rows/picks beyond the current counts are hidden.

**Combat rules (unchanged, extended):** row containers are parents of protected buttons, hence implicitly protected like the window. All attribute writes and all Show/Hide/SetPoint/SetSize of window, rows, pick buttons, `[+]`, `[+ Add off-tank]` happen only in `applyStructure()` when `not InCombatLockdown()`. Edits in combat mutate the saved list, set `TK.dirty`, and flush on `PLAYER_REGEN_ENABLED`. The window renders from a **snapshot** (`applied`) so displayed picks/tanks always equal what a click casts.

## 4. Picker (`ui/TankCastConfig.lua`)

The existing popup (Spells / Items tabs, tooltips with the item classification line, drag-move, Esc to close) is reused with a **target context**: `TK.OpenPicker(tankIndex, pickIndex)` (`pickIndex == nil` -> add). The title reads "Pick for MT/OT<n> <Name>". Choosing calls `TK.AddPick` / `TK.SetPick` and reports errors with `AIP.Print`. A **"type a name" edit box** is added at the bottom (Enter accepts; also accepts a shift-clicked link) because the shared spell box no longer exists.

## 5. Gear strip

Only **Import** and **Push** remain (the global spell box and its icon are removed). It is hidden unless the gear is toggled.

## 6. Slash commands

`/aip tanks` toggles the window. New/changed subcommands: `pick <mt|otN|N> <name>` (add a pick), `unpick <mt|otN|N> <name>`, `spell <name>` = add to every tank (`AddPickToAll`), `addot` (append an OT slot), `clear` = clear names only, `reset` = wipe all tanks and picks. `mt`, `ot`, `sync`, `push`, `list` (now prints every slot with its picks) are kept. `help` documents them. Slot selectors: `mt`, `ot1..ot7`, or a number 1..8.

## 7. Status line

Priority: `TK.dirty` -> "Changes apply after combat"; no picks anywhere -> "No picks yet - click + on a tank"; any unknown pick -> "A pick isn't in your spellbook or bags"; any pick with `IsFriendlyCastable == false` -> "A pick can't target a friendly player"; else the hint line.

## 8. Testing / verification

Headless (`tools/tests/tankcast_spec.lua`): tank list (add up to 8, reject the 9th, remove shifts down, MT can't be removed, dedupe moves a name but not picks, SetFirstOT adds a slot), picks (add/set/remove, cap of 4, duplicate rejection case-insensitive, sanitising, empty rejection, AddPickToAll), migration from the legacy shape (including empty-MT + spell), Import keeps picks and trims trailing empties, Push covers all slots, slash handlers (`pick`, `unpick`, `spell`, `addot`, `clear`, `reset`, `list`), plus all existing logic tests that are unaffected.

Live (after the client restart): window layout with 1, 4 and 8 tanks; per-tank picks add/replace/remove via picker, drag-drop and `/aip tanks pick`; real solo cast from a pick (MT = self); combat deferral; title-bar and Simplified-view checks; `IsProtected()` confirmation.

## 9. Risks

- 8 rows x 48px + extras is ~440px tall at the maximum; the window is clamped to the screen and movable. If it is too tall in practice, `ROW_H` or `MAX_TANKS` is a one-line change.
- 32 secure buttons is a small pool; creation happens once, out of combat.
- Existing installs are unaffected in practice because the feature has not shipped, but the migration keeps any saved 1+3 list and shared spell.
