# window.ps1 — resize the game window so a screenshot is worth taking.
#
# WHY THIS EXISTS. Launched under the AIR debug runtime the game opens at about
# 518x422 — the size in the application descriptor. That is fine for the mod
# bridge, which never looks at the screen, and useless for anything a person
# would want photographed: at that size the initiative bar, the stat panel and
# the unit banners are all unreadable. Measured on a first run, and written down
# because nothing on screen suggests the window is smaller than it should be.
#
# The game re-lays-out on resize (its stage scales), so making the window bigger
# before photographing it costs one call and changes nothing about the run.
#
# USAGE
#   .\window.ps1 -ProcessId 1234 -Width 1600 -Height 900
#   .\window.ps1 -ProcessId 1234 -Maximize
#
# Prints one line of JSON, like screenshot.ps1, so a caller can read the result.

param(
    [string]$ProcessName = 'adl',
    [int]$ProcessId = 0,
    [int]$Width = 0,
    [int]$Height = 0,
    [switch]$Maximize
)

$ErrorActionPreference = 'Stop'

Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WindowMove {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public const int SW_MAXIMIZE = 3;
    public const int SW_RESTORE  = 9;
}
'@

# Same reason as screenshot.ps1: measure in real pixels, not scaled ones.
[void][WindowMove]::SetProcessDPIAware()

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
foreach ($p in $procs) {
    if ($p.MainWindowHandle -eq 0) { continue }
    if (-not [WindowMove]::IsWindowVisible($p.MainWindowHandle)) { continue }
    $rect = New-Object WindowMove+RECT
    if (-not [WindowMove]::GetWindowRect($p.MainWindowHandle, [ref]$rect)) { continue }
    $area = ($rect.Right - $rect.Left) * ($rect.Bottom - $rect.Top)
    if ($area -gt $best) { $best = $area; $target = $p }
}

if (-not $target) {
    Write-Output (@{ ok = $false; reason = 'no visible window found to resize' } | ConvertTo-Json -Compress)
    exit 1
}

if ($Maximize) {
    [void][WindowMove]::ShowWindow($target.MainWindowHandle, [WindowMove]::SW_MAXIMIZE)
} else {
    if ($Width -le 0 -or $Height -le 0) {
        Write-Output (@{ ok = $false; reason = 'give -Width and -Height, or -Maximize' } | ConvertTo-Json -Compress)
        exit 1
    }
    # Restore first: a maximised window ignores a move, and silently, which looks
    # like the resize simply did not work.
    [void][WindowMove]::ShowWindow($target.MainWindowHandle, [WindowMove]::SW_RESTORE)
    [void][WindowMove]::MoveWindow($target.MainWindowHandle, 0, 0, $Width, $Height, $true)
}

# Give the game a moment to lay itself out again before anyone photographs it.
Start-Sleep -Milliseconds 600

$after = New-Object WindowMove+RECT
[void][WindowMove]::GetWindowRect($target.MainWindowHandle, [ref]$after)

Write-Output (@{
    ok = $true
    pid = $target.Id
    process = $target.ProcessName
    width = $after.Right - $after.Left
    height = $after.Bottom - $after.Top
} | ConvertTo-Json -Compress)
