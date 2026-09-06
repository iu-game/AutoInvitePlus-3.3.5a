# WoW Test Harness — drive a running WoW 3.3.5a client for live addon
# verification (screenshot, click, chat/slash-command injection) and sync
# this repo's addon folders into the client's live AddOns directory.
#
# Windows-only (uses user32.dll via P/Invoke). Requires a WoW 3.3.5a client
# already running and logged into a character. This is a manual-testing aid,
# not a CI tool — nothing here runs unattended or against a headless client.
#
# Setup: copy config.example.ps1 to config.local.ps1 in this same folder and
# set $WowInstallPath to your local WoW 3.3.5a install root.
#
# Usage (from a PowerShell session):
#   . tools\wow-test-harness\harness.ps1
#   Sync-Addon                        # copy repo AutoInvitePlus/ -> live AddOns/
#   Send-WowChat "/reload"
#   Start-Sleep -Seconds 6
#   Send-WowChat "/aip"
#   Screenshot-Wow "C:\temp\aip-check.png"   # then Read the PNG to inspect it
#   Click-Wow -x 541 -y 712                  # coordinates read off a screenshot

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$configLocal = Join-Path $PSScriptRoot "config.local.ps1"
$configExample = Join-Path $PSScriptRoot "config.example.ps1"
if (Test-Path $configLocal) {
    . $configLocal
} elseif (Test-Path $configExample) {
    Write-Warning "config.local.ps1 not found - using config.example.ps1's placeholder path. Copy config.example.ps1 to config.local.ps1 and edit `$WowInstallPath for your machine."
    . $configExample
} else {
    throw "No config.local.ps1 or config.example.ps1 found in $PSScriptRoot"
}

if (-not $WowInstallPath -or -not (Test-Path $WowInstallPath)) {
    throw "WowInstallPath ('$WowInstallPath') does not exist. Fix it in tools\wow-test-harness\config.local.ps1."
}

$AddonNames = @("AutoInvitePlus", "GearScoreLite")
$LiveAddonsPath = Join-Path $WowInstallPath "Interface\AddOns"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if (-not ([System.Management.Automation.PSTypeName]'Win32Automation').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Automation {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);
    // Same entry point, signed dwData - lets a wheel scroll pass a negative
    // delta (scroll down) without the uint-wraparound dance in PowerShell.
    [DllImport("user32.dll", EntryPoint = "mouse_event")] public static extern void mouse_event_signed(uint dwFlags, int dx, int dy, int dwData, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@
}

# Mirrors this repo's addon folders into the live client's AddOns directory.
# Excludes VCS/memory-tool metadata that shouldn't ship to the game folder.
# Run this before every /reload during a test session - the live client
# never sees repo edits until this has copied them over.
function Sync-Addon {
    foreach ($name in $AddonNames) {
        $src = Join-Path $RepoRoot $name
        $dst = Join-Path $LiveAddonsPath $name
        if (-not (Test-Path $src)) { Write-Warning "Skipping $name - not found at $src"; continue }
        robocopy $src $dst /MIR /NJH /XD ".remember" ".git" | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed for $name (exit $LASTEXITCODE)" }
    }
}

function Get-WowWindow {
    $proc = Get-Process -Name Wow -ErrorAction SilentlyContinue
    if (-not $proc) { throw "WoW process not found - is the client running?" }
    return $proc
}

function Focus-Wow {
    $proc = Get-WowWindow
    $hwnd = $proc.MainWindowHandle
    [Win32Automation]::ShowWindow($hwnd, 9) | Out-Null  # SW_RESTORE
    Start-Sleep -Milliseconds 200
    [Win32Automation]::SetForegroundWindow($hwnd) | Out-Null
    Start-Sleep -Milliseconds 300
}

function Get-WowRect {
    $proc = Get-WowWindow
    $rect = New-Object Win32Automation+RECT
    [Win32Automation]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) | Out-Null
    return $rect
}

# x,y are CLIENT-relative pixel coordinates, i.e. coordinates read directly
# off a screenshot produced by Screenshot-Wow (which captures the full
# window rect, so a screenshot's top-left IS x=0,y=0 in this space).
function Click-Wow {
    param([int]$x, [int]$y)
    Focus-Wow
    $rect = Get-WowRect
    $screenX = $rect.Left + $x
    $screenY = $rect.Top + $y
    [Win32Automation]::SetCursorPos($screenX, $screenY) | Out-Null
    Start-Sleep -Milliseconds 100
    [Win32Automation]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # left down
    Start-Sleep -Milliseconds 60
    [Win32Automation]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # left up
    Start-Sleep -Milliseconds 200
}

function RightClick-Wow {
    param([int]$x, [int]$y)
    Focus-Wow
    $rect = Get-WowRect
    [Win32Automation]::SetCursorPos($rect.Left + $x, $rect.Top + $y) | Out-Null
    Start-Sleep -Milliseconds 100
    [Win32Automation]::mouse_event(0x0008, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # right down
    Start-Sleep -Milliseconds 60
    [Win32Automation]::mouse_event(0x0010, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # right up
    Start-Sleep -Milliseconds 200
}

function DoubleClick-Wow {
    param([int]$x, [int]$y)
    Click-Wow -x $x -y $y
    Start-Sleep -Milliseconds 40
    Click-Wow -x $x -y $y
}

# Scrolls the mouse wheel at a client-relative point. notches > 0 scrolls up
# (content moves down / view moves toward the top); notches < 0 scrolls down.
# One notch = one wheel click (WHEEL_DELTA = 120), matching a physical mouse.
function Scroll-Wow {
    param([int]$x, [int]$y, [int]$notches = 3)
    Focus-Wow
    $rect = Get-WowRect
    [Win32Automation]::SetCursorPos($rect.Left + $x, $rect.Top + $y) | Out-Null
    Start-Sleep -Milliseconds 100
    [Win32Automation]::mouse_event_signed(0x0800, 0, 0, ($notches * 120), [UIntPtr]::Zero) | Out-Null  # MOUSEEVENTF_WHEEL
    Start-Sleep -Milliseconds 200
}

# Left-click-drag from (x1,y1) to (x2,y2), e.g. for a scrollbar thumb or a
# slider. Moves through a few intermediate points, not a single jump -
# WoW's slider/scrollbar widgets track OnMouseMove deltas while dragging, so
# a single teleport-then-release can be missed entirely.
function Drag-Wow {
    param([int]$x1, [int]$y1, [int]$x2, [int]$y2, [int]$steps = 8)
    Focus-Wow
    $rect = Get-WowRect
    $startX = $rect.Left + $x1; $startY = $rect.Top + $y1
    $endX = $rect.Left + $x2; $endY = $rect.Top + $y2
    [Win32Automation]::SetCursorPos($startX, $startY) | Out-Null
    Start-Sleep -Milliseconds 100
    [Win32Automation]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # left down
    Start-Sleep -Milliseconds 80
    for ($i = 1; $i -le $steps; $i++) {
        $ix = $startX + [int](($endX - $startX) * $i / $steps)
        $iy = $startY + [int](($endY - $startY) * $i / $steps)
        [Win32Automation]::SetCursorPos($ix, $iy) | Out-Null
        Start-Sleep -Milliseconds 40
    }
    [Win32Automation]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero) | Out-Null  # left up
    Start-Sleep -Milliseconds 200
}

# Types text into whatever UI element currently has keyboard focus (e.g. an
# addon EditBox you just Click-Wow'd into) - unlike Send-WowChat, this does
# NOT open the chat box first or press Enter to submit. Pass -Submit to press
# Enter afterward (most WoW EditBoxes call their OnEnterPressed handler).
function Type-WowText {
    param([string]$text, [switch]$Submit)
    Focus-Wow
    $escaped = $text -replace '([\{\}\+\^%~\(\)\[\]])', '{$1}'
    [System.Windows.Forms.SendKeys]::SendWait($escaped)
    Start-Sleep -Milliseconds 150
    if ($Submit) {
        [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
        Start-Sleep -Milliseconds 200
    }
}

# Runs arbitrary Lua via the client's /run command - the single highest-value
# addition here for DATA-ACCURACY testing: instead of eyeballing screenshots
# or guessing, you can query the client's own state directly (GetItemInfo,
# GetSpellInfo, dump an addon's Lua tables, etc.) and get ground truth back
# via chat/print. Requires /run to actually be enabled server-side - some
# servers restrict it to GMs. Verify once per session with:
#   Run-WowLua 'print("HARNESS_LUA_OK")'
#   Screenshot-Wow ... # or Read-WowChatLog if that text doesn't appear in
# chat, /run is blocked here and this function is a no-op for your purposes.
# Long results should be chunked (chat lines truncate) - print in small
# pieces rather than one huge table dump.
function Run-WowLua {
    param([string]$code)
    $full = "/run $code"
    if ($full.Length -gt 255) {
        throw "Run-WowLua: command is $($full.Length) chars (limit 255 - WoW's chat edit box silently truncates past this, which breaks the Lua chunk mid-string/mid-expression with a confusing error, e.g. `"unfinished string near '<eof>'`". Split into multiple shorter calls, e.g. stash a short global alias first (`Z=AutoInvitePlus`) to shave chars off every subsequent reference."
    }
    Send-WowChat $full
}

function Screenshot-Wow {
    param([string]$outPath)
    Focus-Wow
    $rect = Get-WowRect
    $w = $rect.Right - $rect.Left
    $h = $rect.Bottom - $rect.Top
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bmp.Size)
    $bmp.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $outPath
}

# Crops and optionally upscales a region of a previously-saved screenshot -
# useful for reading small/dense UI text that's illegible at native size.
function Crop-Screenshot {
    param([string]$inPath, [string]$outPath, [int]$x, [int]$y, [int]$width, [int]$height, [int]$scale = 3)
    $img = [System.Drawing.Image]::FromFile($inPath)
    $cropRect = New-Object System.Drawing.Rectangle $x, $y, $width, $height
    $bmp = New-Object System.Drawing.Bitmap $cropRect.Width, $cropRect.Height
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($img, (New-Object System.Drawing.Rectangle 0, 0, $cropRect.Width, $cropRect.Height), $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
    $scaled = New-Object System.Drawing.Bitmap ($cropRect.Width * $scale), ($cropRect.Height * $scale)
    $g2 = [System.Drawing.Graphics]::FromImage($scaled)
    $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g2.DrawImage($bmp, (New-Object System.Drawing.Rectangle 0, 0, $scaled.Width, $scaled.Height))
    $scaled.Save($outPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $g2.Dispose(); $bmp.Dispose(); $scaled.Dispose(); $img.Dispose()
    return $outPath
}

# Opens chat with Enter, types the given text (a slash command or plain
# message), submits with Enter. Focuses the WoW window first.
function Send-WowChat {
    param([string]$text)
    Focus-Wow
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 200
    # Escape SendKeys special characters: {}, +^%~()[]
    $escaped = $text -replace '([\{\}\+\^%~\(\)\[\]])', '{$1}'
    [System.Windows.Forms.SendKeys]::SendWait($escaped)
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
    Start-Sleep -Milliseconds 300
}
