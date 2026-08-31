# input.ps1 — click the game window.
#
# WHY THIS EXISTS. The mod bridge reaches the battle and nothing else. Every
# other screen the game has — the town, the great hall where the roster lives,
# the mead house — is reachable only the way a player reaches it, by clicking.
# This is that half of the job.
#
# THE COORDINATE SYSTEM IS THE WHOLE DESIGN. X and Y here are **pixels measured
# on the picture screenshot.ps1 takes**, with (0,0) at the very top-left of the
# captured image — the corner of the title bar, not of the game's drawing area.
# That is deliberate: the capture is sized from GetWindowRect, so one pixel in
# the image is one pixel of the window at the same offset, and the workflow
# "take a picture, read a position off it, click that position" needs no
# arithmetic and no guessing about how tall a title bar is.
#
# WHAT IT DOES TO YOUR MACHINE, WHICH IS NOT NOTHING. This synthesises real
# input: it brings the game to the front and moves the actual mouse pointer.
# While a script using this is running, the machine is not yours — a click meant
# for the game lands in whatever is in front if the raising failed. It therefore
# checks what is actually in front before clicking, and refuses rather than
# clicking blind, because a stray click that goes somewhere unexpected is much
# worse than a step that stops.
#
# TWO CLICKS, SPLIT IN REAL TIME — AND NOT ONLY ON THE BATTLE BOARD.
#
# The battle board is where this rule was first written down: the first click on
# a target only ARMS the action and the second commits it, with the two needing
# to be about a second apart. Measured here, it turns out to be more general than
# that. Clicking a building in the town behaves the same way: one click does
# nothing at all, and a second one opens it.
#
# THE REASON IS NOT THAT THE GAME WANTS TWO CLICKS. Measured 2026-08-30 across
# three runs: the FIRST click of a run is swallowed, and every click after it
# works on its own. Run 2 lost a click on a popup close button and then opened
# the great hall with a SINGLE click; run 3 spent a click on empty ground and
# then closed the popup AND opened the hall, one click each. Waiting does not
# help — a lone click after fifteen seconds still did nothing.
#
# WHY is not settled, and the likeliest answer has already been ruled out: giving
# that press to the title bar instead does NOT help (measured, same day), so it is
# not simply Windows swallowing the press that raises a background window. The
# press has to land on the game itself to be spent. What happens next is visible
# in the client: SceneViewController acts on a release only if it saw the matching
# press, and says nothing at all when it did not.
#
# So the first press of a run is spent DELIBERATELY: the driver asks for two
# presses on the first click of a run and one on every click after it. This file
# clicks ONCE by default and does not decide that policy — see driver.js.
#
# USAGE
#   .\input.ps1 -ProcessId 1234 -X 640 -Y 400
#   .\input.ps1 -ProcessId 1234 -X 640 -Y 400 -Button right    # cancels an armed attack
#
# Prints one line of JSON, like the other helpers here.

param(
    [string]$ProcessName = 'adl',
    [int]$ProcessId = 0,
    [Parameter(Mandatory = $true)][int]$X,
    [Parameter(Mandatory = $true)][int]$Y,
    [ValidateSet('left', 'right')]
    [string]$Button = 'left',
    # HOW MANY CLICKS, AND HOW FAR APART. ONE by default, which is what the game
    # actually wants. The lost-first-press problem is handled by the title-bar
    # click further down, not by clicking the target twice. Ask for -Repeat 2
    # only when you mean it: on anything that changes the screen, the second
    # click lands on whatever the first one opened.
    [int]$Repeat = 1,
    [int]$GapMs = 900,
    # Click even when the window we raised is not the one in front. Off by
    # default: see the note above about where a stray click ends up.
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WindowInput {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hWnd, uint gaFlags);
    [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
    [DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    public const int SW_RESTORE = 9;
    public const uint GA_ROOT = 2;
    public const byte VK_MENU = 0x12;
    public const uint KEYEVENTF_KEYUP = 0x0002;
    public const uint MOUSEEVENTF_LEFTDOWN  = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP    = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP   = 0x0010;
}
'@

# Real pixels, not scaled ones — the same reason screenshot.ps1 does this first.
# If capture and clicking disagree about scaling, every click lands short.
[void][WindowInput]::SetProcessDPIAware()

function Get-ProcessTree {
    param([int]$RootId)
    $all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId
    $found = New-Object System.Collections.Generic.List[int]
    $found.Add($RootId)
    $frontier = @($RootId)
    while ($frontier.Count -gt 0) {
        $next = @()
        foreach ($p in $frontier) {
            foreach ($c in $all) {
                if ($c.ParentProcessId -eq $p -and -not $found.Contains([int]$c.ProcessId)) {
                    $found.Add([int]$c.ProcessId)
                    $next += [int]$c.ProcessId
                }
            }
        }
        $frontier = $next
    }
    return $found
}

if ($ProcessId -gt 0) {
    $procs = @()
    foreach ($id in Get-ProcessTree -RootId $ProcessId) {
        $p = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($p) { $procs += $p }
    }
} else {
    $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
}

$target = $null
$best = 0
$rect = New-Object WindowInput+RECT
foreach ($p in $procs) {
    if ($p.MainWindowHandle -eq 0) { continue }
    if (-not [WindowInput]::IsWindowVisible($p.MainWindowHandle)) { continue }
    $r = New-Object WindowInput+RECT
    if (-not [WindowInput]::GetWindowRect($p.MainWindowHandle, [ref]$r)) { continue }
    $area = ($r.Right - $r.Left) * ($r.Bottom - $r.Top)
    if ($area -gt $best) { $best = $area; $target = $p; $rect = $r }
}

if (-not $target) {
    Write-Output (@{ ok = $false; reason = 'no visible game window found to click' } | ConvertTo-Json -Compress)
    exit 1
}


# UN-MINIMISE BEFORE MEASURING, NOT AFTER. Windows parks a minimised window off
# the side of the screen at about -32000, so a rectangle read while it is still
# minimised describes nowhere at all, and every position worked out from it is
# nonsense. Restoring first and re-reading costs one call.
#
# ONLY UN-MINIMISE A WINDOW THAT IS MINIMISED. Asking to "restore" a MAXIMISED
# window shrinks it back to its old size, which ruins every coordinate taken
# from the last screenshot. Measured the hard way: an unconditional restore here
# turned a 1938x1038 window into 1042x767 between one click and the next.
if ([WindowInput]::IsIconic($target.MainWindowHandle)) {
    [void][WindowInput]::ShowWindow($target.MainWindowHandle, [WindowInput]::SW_RESTORE)
    Start-Sleep -Milliseconds 300
    [void][WindowInput]::GetWindowRect($target.MainWindowHandle, [ref]$rect)
}

$width  = $rect.Right - $rect.Left
$height = $rect.Bottom - $rect.Top

# A position from a picture taken before the window moved or shrank would land
# somewhere arbitrary. Refuse instead, and say what the window is now, so the
# caller can take a fresh picture rather than wonder why nothing happened.
if ($X -lt 0 -or $Y -lt 0 -or $X -ge $width -or $Y -ge $height) {
    Write-Output (@{
        ok = $false
        reason = "($X,$Y) is outside the window, which is ${width}x${height}. Take a fresh screenshot and read the position off that."
    } | ConvertTo-Json -Compress)
    exit 1
}

$screenX = $rect.Left + $X
$screenY = $rect.Top + $Y

# BRING IT TO THE FRONT. Windows refuses to let a background program simply take
# the foreground, and refuses SILENTLY — the call returns and nothing moves. The
# tap on ALT releases that lock, which is the documented way round it.
[WindowInput]::keybd_event([WindowInput]::VK_MENU, 0, 0, [UIntPtr]::Zero)
[WindowInput]::keybd_event([WindowInput]::VK_MENU, 0, [WindowInput]::KEYEVENTF_KEYUP, [UIntPtr]::Zero)
[void][WindowInput]::SetForegroundWindow($target.MainWindowHandle)
Start-Sleep -Milliseconds 400

$front = [WindowInput]::GetForegroundWindow()
$isFront = ($front -eq $target.MainWindowHandle)

if (-not $isFront -and -not $Force) {
    Write-Output (@{
        ok = $false
        reason = 'the game did not come to the front, so a click would land in whatever did. Click its taskbar button once by hand, or pass -Force if you are sure.'
    } | ConvertTo-Json -Compress)
    exit 1
}

# ARRIVE AT THE SPOT, DO NOT TELEPORT TO IT.
#
# KEPT, BUT NOT THE THING THAT FIXES ANYTHING. This used to carry the theory that
# the game hit-tests on mouse MOVEMENT and so needs the pointer to walk onto its
# target. That theory is wrong — the lost click was the activation press — and the
# stepping was in place for every measurement that failed as well as every one
# that worked, so it was never what made the difference.
#
# It stays because it is cheap and because a pointer that arrives with movement
# around it is closer to what a person does. Do not cite it as a cause, and do not
# remove it expecting a change: nothing here has been measured without it.
[void][WindowInput]::SetCursorPos(($screenX - 6), ($screenY - 6))
Start-Sleep -Milliseconds 90
[void][WindowInput]::SetCursorPos(($screenX - 2), ($screenY - 2))
Start-Sleep -Milliseconds 90
[void][WindowInput]::SetCursorPos($screenX, $screenY)
Start-Sleep -Milliseconds 350
# A check against the likeliest remaining mistake: something floating over the
# game at exactly this spot. Only a warning — the game draws into child windows
# and the ancestor test is not perfect — but worth reporting.
$point = New-Object WindowInput+POINT
$point.X = $screenX
$point.Y = $screenY
$under = [WindowInput]::WindowFromPoint($point)
$underRoot = [WindowInput]::GetAncestor($under, [WindowInput]::GA_ROOT)
$coveredWarning = $null
if ($underRoot -ne $target.MainWindowHandle) {
    $coveredWarning = 'something else appears to be on top at that spot; the click may not have reached the game'
}

for ($i = 0; $i -lt $Repeat; $i++) {
    if ($i -gt 0) {
        # The gap is the point. Two presses inside one drawn frame count as one.
        Start-Sleep -Milliseconds $GapMs
        # Nudge off the spot and back, so the second press arrives with movement
        # around it rather than as a bare second press at a stationary pointer.
        [void][WindowInput]::SetCursorPos(($screenX - 3), ($screenY - 3))
        Start-Sleep -Milliseconds 60
        [void][WindowInput]::SetCursorPos($screenX, $screenY)
        Start-Sleep -Milliseconds 120
    }
    if ($Button -eq 'right') {
        [WindowInput]::mouse_event([WindowInput]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [WindowInput]::mouse_event([WindowInput]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
    } else {
        [WindowInput]::mouse_event([WindowInput]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
        Start-Sleep -Milliseconds 40
        [WindowInput]::mouse_event([WindowInput]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    }
}

Write-Output (@{
    ok = $true
    button = $Button
    clicks = $Repeat
    at = "$X,$Y"
    screen = "$screenX,$screenY"
    window = "${width}x${height}"
    cameToFront = $isFront

    warning = $coveredWarning
} | ConvertTo-Json -Compress)
