# Tank Cast Window — Design

> Sections 1 and 3 and the single-spell / 1+3 tank decisions are superseded by 2026-09-27-tank-cast-multi-tank-picks-design.md.

Date: 2026-09-27
Status: Draft, awaiting user review

## Goal

Let a player designate a main tank (MT) and up to three off-tanks (OT) from the
AutoInvitePlus title-bar quick buttons, and cast one configurable spell (or use one
configurable item) on any of them with a single click from a small floating window.
Typical uses: Misdirection, Tricks of the Trade, Hand of Sacrifice, Innervate,
Earth Shield, Pain Suppression, Guardian Spirit, Power Word: Shield.

## Decisions (from brainstorming)

- **Tank source:** AIP-local list (works without raid-assist) plus one-click import
  from Blizzard flags and an explicit, leader/assist-only push back to Blizzard.
- **Spell vs item:** one free-text field. `/cast` resolves both spells and items in
  3.3.5a, so a single field covers both. ("cast a specific item" read as "spell";
  items come along for free.)
- **Approach:** new module `modules/TankCast.lua` (`AIP.TankCast`), not an extension of
  RaidTools and not a main-window tab.
- **Spell scope:** one global spell for all tank rows (per-tank spells are out of scope).

## Non-goals

Per-tank spells, auto-casting, chat announcements, DataBus sharing of the tank list,
a resize grip, more than 1 MT + 3 OT slots.

## 1. Data

Add to the `defaults` table in `core/Core.lua` (no `DB_VERSION` bump — additive key):

```lua
tankCast = {
    mt    = "",            -- normalized name, "" = unset
    ots   = {},            -- array of up to 3 normalized names (holes stored as "")
    spell = "",            -- spell or item name (display form, unsanitized)
    shown = false,         -- window visibility persisted across reloads
    pos   = nil,           -- {point, relPoint, x, y}
    showConfig = false,    -- spell-config strip expanded
},
```

Names go through `AIP.Utils.NormalizeName` and are compared with `:lower()`.
The list persists across sessions (guild raids reuse tanks). A tank not currently in
the group is kept in the list but rendered dimmed as "not in group".

## 2. Secure casting layer (3.3.5a constraint)

Casting on a specific unit is protected, so each tank row is a
`SecureActionButtonTemplate` button:

- `type1 = "macro"`, `macrotext1 = "/cast [target=<Name>] <Spell>"`.
  `target=` is used (not `@`) for 3.3.5a compatibility. This casts without changing
  the player's actual target.
- Only LeftButton carries secure attributes. Right-click (and left-click on an empty
  slot) is handled by a normal `HookScript("OnClick")` that opens the row menu.
- Attributes and row anchors are only written when `not InCombatLockdown()`. If a
  change is requested in combat, set `TC.dirty = true`, show "applies after combat"
  in the footer, and flush on `PLAYER_REGEN_ENABLED`.
- **Correction found in review:** the container frame (`AIPTankCastWindow`) is the
  parent of the secure rows, so it is *implicitly protected* and cannot be
  shown/hidden/resized/moved (or created) in combat either. Those operations are
  guarded with `InCombatLockdown()`: open/close print a "not during combat" hint,
  resize defers to the post-combat flush, drag is ignored, and login creation waits
  for `PLAYER_REGEN_ENABLED` when the UI was reloaded mid-combat.
- **Sanitising:** the spell and name are stripped of newlines and of `/ ; [ ]` and
  truncated before being interpolated into `macrotext`; total macro length capped
  below 255. Empty spell -> no macrotext set (click does nothing, footer prompts to
  set a spell).
- Module events use `AIP.Utils.Events` where possible. The secure/health/cooldown
  refresh needs `PLAYER_REGEN_ENABLED`, `RAID_ROSTER_UPDATE`,
  `PARTY_MEMBERS_CHANGED`, `UNIT_HEALTH`, `SPELL_UPDATE_COOLDOWN` (guarded
  `Register` calls; one owner string for `UnregisterAll`).
- **No chat output** anywhere in this module, so there is no throttle or mute risk.

## 3. Window (visual design)

Matches the RaidTools announcement bar: navy body `(0.045, 0.05, 0.072)`, header
strip `(0.11, 0.12, 0.18)`, gold 1px divider `(1, 0.82, 0, 0.4)`, UI-Tooltip-Border
edge. Draggable by the header; position saved to `db.tankCast.pos`.

```
+----------------------------------+
| Tanks                    [⚙] [X] |   header, 18px
|----------------------------------|   gold divider
| [MT]  Thorgrim          (icon)   |   row, 26px
|       ▓▓▓▓▓▓▓▓▓▓▓▓░░             |   thin HP bar on the row's bottom edge
| [OT1] Bramble           (icon)   |
| [OT2] + Set OT                   |   empty slot, dashed outline
|----------------------------------|
| (icon) [ Misdirection      ][v]  |   spell strip (shown when ⚙ toggled
| [Import] [Push]                  |   or spell unset)
+----------------------------------+
```

- Width ~190px; height follows filled rows + one empty slot + optional config strip.
- Row: role chip (gold **MT**, silver **OT1-3**), class-coloured name, HP bar, spell
  icon at right with a cooldown sweep (`CooldownFrameTemplate`).
- Row dims to 0.45 alpha when the tank is out of range (`IsSpellInRange` for spells,
  `IsItemInRange` for items), dead, offline, or not in the group. A tooltip states
  which.
- Left-click = cast. Right-click = menu: *Change tank...*, *Use my target*, *Clear*.
  Empty slot left-click opens the picker directly.
- **Picker:** dropdown of current raid/party members, tank-capable classes (Warrior,
  Paladin, Death Knight, Druid) listed first, then everyone else, plus *My target*.
- **Spell strip:** icon preview, edit box, class-preset dropdown (Misdirection,
  Tricks of the Trade, Hand of Sacrifice, Innervate, Earth Shield, Pain Suppression,
  Guardian Spirit, Power Word: Shield; only presets whose spell the player knows via
  `GetSpellInfo` are listed). Shift-clicking a spellbook spell into the edit box is
  parsed from the `|Hspell:id|h[Name]|h` link. Border turns red when the text is
  neither `GetSpellInfo` nor `GetItemInfo` resolvable.
- Name -> unit token map (`raidN`/`partyN`/`player`) rebuilt on roster events; used
  for class colour, HP, range, and dead/offline state. It is never used as the cast
  target (the macro uses the name, which survives roster reshuffles).

## 4. Blizzard sync

WotLK only has `MAINTANK` and `MAINASSIST` raid flags — there is no off-tank flag.

- **Import:** `GetRaidRosterInfo` role `MAINTANK` -> MT slot; `MAINASSIST` players ->
  OT slots in roster order (truncated to 3). Tooltip states this mapping.
- **Push:** enabled only when `IsRaidLeader()` or `IsRaidOfficer()`; calls
  `SetPartyAssignment("MAINTANK", name)` for the MT and `"MAINASSIST"` for the OTs.
  Explicit click only, never automatic. Exact `SetPartyAssignment` argument form to be
  confirmed in the live client during implementation.

## 5. Wiring

- `AutoInvitePlus.toc`: add `modules\TankCast.lua` after `modules\Rotation.lua`
  (before `LFGWatch.lua`). It depends only on `AIP.Utils` and core, loaded earlier.
- `CentralGUI.lua`: add `titleBtn("Tanks", 46, qReady, -3, ...)` after `qReady`,
  append it to `frame.quickTitleButtons`, and add a "Tank Window" entry to the
  simplified-view `...` quick menu. Calls are guarded
  (`if AIP.TankCast and AIP.TankCast.Toggle then ...`). Title-bar width/overlap must be
  re-checked in both Full and Simplified views.
- `Core.lua` `SlashHandler`: `/aip tanks` toggles; subcommands `mt <name>`,
  `ot <name>`, `clear`, `spell <name>`, `sync`. Add to the `help` branch.
- `AIP/CLAUDE.md`: one paragraph documenting `AIP.TankCast` and the secure-button /
  combat-lockdown rules. `WIRING.md` is not affected (not matchmaking code).

## 6. Error handling

- Combat lockdown: queued + flushed (section 2).
- Spell unknown/typo: red border, click is a no-op with a one-line `AIP.Print` hint
  (local print, not chat).
- Tank left the group / offline: row dimmed, cast simply fails in the client.
- Duplicate assignment (same name as MT and OT): assigning a name removes it from any
  other slot.
- `AIP.db` nil early: all accessors guard and fall back to defaults.

## 7. Testing / verification

No test framework exists. Verification steps:

1. `luaparse` (`luaVersion: '5.1'`) over all touched files (ignore the known
   `break;` false positive).
2. Sync the addon to the client with the harness, `/reload`, `/console scriptErrors 1`.
3. Solo secure-cast test: set MT to the player's own name, spell `Power Word:
   Fortitude` (or any self-castable buff/item); click the row and confirm the cast
   and the cooldown sweep. Confirms the `macrotext` path end to end without a group.
4. Combat-lockdown test: change the spell during combat, confirm the "applies after
   combat" notice and that it applies on `PLAYER_REGEN_ENABLED`.
5. Screenshot the window and title bar in Full and Simplified views; confirm no
   title-bar overlap and correct dim/range states.
6. Group test (party of 2+) for the picker, Import, and Push if a second account is
   available; otherwise flag as not live-verified.

## 8. Risks

- Title bar is already crowded (6 buttons); adding a 7th may overlap the title at
  narrow widths. Mitigation: verify, and shrink button widths or fold into the `...`
  menu if needed.
- `SetPartyAssignment` signature and the `[target=Name]` conditional for names not
  currently targetable need live confirmation.
