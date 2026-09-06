# WoW Test Harness

A Windows-only PowerShell tool for **live-testing this repo's addons against
a real, running WoW 3.3.5a client** — screenshot the game window, click UI
elements, and inject slash commands/chat text, all driven from outside the
game. It exists because this repo has no build/test/lint toolchain (see the
root `CLAUDE.md`): the only way to actually verify a change is `/reload` +
observe, and this tool automates the "observe" (and "click around") part so
that can happen without a human at the keyboard for every check.

This is a manual-verification aid for interactive dev sessions, not a CI
tool. Nothing here runs headless or unattended against a client that isn't
already up and logged in.

## Requirements

- Windows, with WoW 3.3.5a installed locally.
- PowerShell (Windows PowerShell 5.1, the default on Windows).
- WoW already running and logged into a character before you use the
  harness — it does not launch or log in the client.

## Setup

1. Copy `config.example.ps1` to `config.local.ps1` (same folder).
2. Edit `config.local.ps1`: set `$WowInstallPath` to your WoW 3.3.5a
   install root (the folder containing `Wow.exe`).

`config.local.ps1` is gitignored — it's machine-specific and never
committed.

## Why syncing is required

The live client loads addons from `<WowInstallPath>\Interface\AddOns\`,
which is a **separate copy** of the addon folders, not this repo. Editing
files in this repo has no effect on the running client until you sync.
`Sync-Addon` mirrors this repo's `AutoInvitePlus/` and `GearScoreLite/`
folders into the live AddOns directory (via `robocopy /MIR`, excluding VCS
and unrelated tooling metadata) — run it before every `/reload` you expect
to reflect a code change.

## Usage

```powershell
. tools\wow-test-harness\harness.ps1

# 1. Push repo changes into the live client's AddOns folder
Sync-Addon

# 2. Reload the UI to pick them up
Send-WowChat "/reload"
Start-Sleep -Seconds 6   # reload takes a few seconds; adjust if needed

# 3. Open the addon and take a screenshot to see what happened
Send-WowChat "/aip"
Start-Sleep -Milliseconds 800
Screenshot-Wow "C:\temp\aip-check.png"
# Then Read the PNG (e.g. via Claude Code's Read tool) to inspect it visually.

# 4. Click something (coordinates are read directly off a screenshot -
#    Screenshot-Wow captures the full window, so a screenshot's top-left
#    pixel is x=0,y=0 in Click-Wow's coordinate space)
Click-Wow -x 541 -y 712
Start-Sleep -Milliseconds 500
Screenshot-Wow "C:\temp\aip-after-click.png"

# 5. Zoom into a region of a saved screenshot when text is too small to read
Crop-Screenshot -inPath "C:\temp\aip-check.png" -outPath "C:\temp\aip-check-zoom.png" `
    -x 480 -y 420 -width 400 -height 20 -scale 3
```

## Functions

| Function | Purpose |
|---|---|
| `Sync-Addon` | Mirrors repo `AutoInvitePlus/`/`GearScoreLite/` into the live client's AddOns folder |
| `Focus-Wow` | Brings the WoW window to the foreground (called automatically by the others) |
| `Screenshot-Wow -outPath <path>` | Saves a PNG of the full WoW window |
| `Crop-Screenshot -inPath -outPath -x -y -width -height [-scale]` | Crops + upscales a region of a saved screenshot for legibility |
| `Click-Wow -x <int> -y <int>` | Left-clicks at window-relative pixel coordinates |
| `RightClick-Wow -x <int> -y <int>` | Right-clicks (context menus, e.g. item links) |
| `DoubleClick-Wow -x <int> -y <int>` | Double-clicks (e.g. equip-from-bag) |
| `Scroll-Wow -x -y [-notches <int>]` | Mouse-wheel scroll at a point; positive scrolls up, negative scrolls down (default 3 notches) |
| `Drag-Wow -x1 -y1 -x2 -y2 [-steps <int>]` | Left-click-drag between two points (scrollbar thumbs, sliders) - moves through intermediate points, not a single jump, since WoW's slider widgets track motion deltas |
| `Type-WowText -text <string> [-Submit]` | Types into whatever already has keyboard focus (e.g. an addon EditBox you just clicked) - unlike `Send-WowChat`, does NOT open chat first. `-Submit` presses Enter afterward |
| `Run-WowLua -code <string>` | Sends `/run <code>` - the highest-value tool for data-accuracy checks: query the client's own state (`GetItemInfo`, `GetSpellInfo`, dump an addon's Lua tables) instead of guessing from a screenshot. **Verify once per session it's not blocked server-side**: `Run-WowLua 'print("HARNESS_LUA_OK")'` then screenshot chat. Chat lines truncate long output - print in small chunks, not one big table dump |
| `Send-WowChat -text <string>` | Opens chat, types the given text (slash command or message), submits it |

## Gotchas

- **WoW's UI scale setting is not 1:1 with screen pixels.** Coordinates for
  `Click-Wow` must be read directly off a `Screenshot-Wow` image — don't try
  to compute them from a Lua file's `SetPoint` offsets, they're in a
  different coordinate space and won't line up. When a target is small or
  buttons are close together, take a screenshot, click your best estimate,
  screenshot again to check what actually got hit (e.g. via the tooltip that
  appears under the cursor), and adjust.
- Multi-monitor setups can put the WoW window at negative screen
  coordinates; the harness handles this correctly (it uses the window's
  actual rect, not an assumption about monitor layout), but be aware of it
  if you're debugging coordinates by hand.
- `/console scriptErrors 1` is worth sending once per session so Lua errors
  surface as visible popups you can screenshot, instead of only appearing in
  a chat log you'd otherwise have to scroll to find.
