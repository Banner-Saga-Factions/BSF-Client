# screenshot.ps1 — photograph one window, even when it is buried behind others.
#
# WHY THIS EXISTS. The mod bridge can read the board, but it cannot tell you what
# a player sees: whether a panel drew empty, whether a unit stands in the wrong
# place, whether an error box is sitting on top of everything. That half of the
# job needs a picture. Nothing in this repository took one until now.
#
# HOW IT WORKS, AND WHY NOT THE OBVIOUS WAY. The obvious way is to bring the game
# to the front and copy the screen. That fails here for two reasons: Windows
# refuses to let a background program steal the foreground, and stealing it would
# disturb the very thing being measured. Instead this asks the window to paint a
# copy of itself (PrintWindow with the "render full content" flag), which works on
# a window that is behind others, needs no click, and changes no focus.
#
# TWO TRAPS IT HANDLES, both measured on this machine:
#
#   1. SCREEN SCALING. On a 125% display Windows reports the game window as
#      1920x1080 while an unaware process is told 1536x864. A process that does
#      not declare itself scaling-aware gets the smaller numbers, and every
#      coordinate read off the resulting image lands about a quarter short. The
#      first thing this script does is declare awareness.
#
#   2. THE WINDOW IS NOT WHERE YOU EXPECT. Our build runs under the AIR debug
#      launcher, so the process is `adl`, not anything named after the game. And
#      the launcher spawns it as a grandchild, so a search from the launcher's own
#      process id has to walk down. Pass -Pid to search a process tree, or
#      -ProcessName to search by name.
#
# USAGE
#   .\screenshot.ps1 -Out shot.png -ProcessName adl
#   .\screenshot.ps1 -Out shot.png -Pid 12345          # searches that tree
#   .\screenshot.ps1 -List                             # what windows can be seen
#
# It prints one line of JSON so a caller can read the result without parsing prose.

param(
    [string]$Out,
    [string]$ProcessName = 'adl',
    [int]$ProcessId = 0,
    [switch]$List,
    # Cut a region out of the capture and blow it up. Reading a small control's
    # position off a full 1938x1038 picture is guesswork; magnified it is not,
    # and clicking needs the position to be right rather than close. Coordinates
    # are in the same space as the full picture, which is the space input.ps1
    # clicks in.
    [int]$CropX = -1,
    [int]$CropY = -1,
    [int]$CropW = 0,
    [int]$CropH = 0,
    [int]$Zoom = 4
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

# The interop surface, kept to the four calls actually needed.
Add-Type @'
using System;
using System.Runtime.InteropServices;

public static class WindowShot {
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    // 0x2 is PW_RENDERFULLCONTENT. Without it a hardware-accelerated window —
    // which this game is — comes back as a blank rectangle. That failure looks
    // exactly like "the game drew nothing", which is a costly thing to believe.
    public const uint RENDER_FULL_CONTENT = 0x00000002;
}
'@

# Declare scaling awareness BEFORE measuring anything. Once a process has drawn
# or measured, this call no longer takes effect, so it goes first.
[void][WindowShot]::SetProcessDPIAware()

<#
.SYNOPSIS
Every process id in a tree, the root included.
#>
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

<#
.SYNOPSIS
The candidate windows, largest first — the game window is the big one.
#>
function Get-Candidates {
    if ($ProcessId -gt 0) {
        $ids = Get-ProcessTree -RootId $ProcessId
        $procs = @()
        foreach ($id in $ids) {
            $p = Get-Process -Id $id -ErrorAction SilentlyContinue
            if ($p) { $procs += $p }
        }
    } else {
        $procs = @(Get-Process -Name $ProcessName -ErrorAction SilentlyContinue)
    }

    $out = @()
    foreach ($p in $procs) {
        if ($p.MainWindowHandle -eq 0) { continue }
        if (-not [WindowShot]::IsWindowVisible($p.MainWindowHandle)) { continue }
        $rect = New-Object WindowShot+RECT
        if (-not [WindowShot]::GetWindowRect($p.MainWindowHandle, [ref]$rect)) { continue }
        $w = $rect.Right - $rect.Left
        $h = $rect.Bottom - $rect.Top
        if ($w -lt 200 -or $h -lt 200) { continue }   # tool windows, not the game
        $out += [pscustomobject]@{
            Pid    = $p.Id
            Name   = $p.ProcessName
            Title  = $p.MainWindowTitle
            Handle = $p.MainWindowHandle
            Width  = $w
            Height = $h
        }
    }
    return @($out | Sort-Object { $_.Width * $_.Height } -Descending)
}

$candidates = Get-Candidates

if ($List) {
    $payload = @{ ok = $true; windows = @($candidates | ForEach-Object {
        @{ pid = $_.Pid; name = $_.Name; title = $_.Title; width = $_.Width; height = $_.Height }
    }) }
    Write-Output ($payload | ConvertTo-Json -Compress -Depth 5)
    exit 0
}

if (-not $Out) {
    Write-Output (@{ ok = $false; reason = 'no -Out given' } | ConvertTo-Json -Compress)
    exit 1
}

if ($candidates.Count -eq 0) {
    $where = if ($ProcessId -gt 0) { "the process tree under $ProcessId" } else { "any process named '$ProcessName'" }
    Write-Output (@{
        ok = $false
        reason = "no visible window at least 200x200 in $where. If the game is still loading, wait and try again; if it has crashed, there is nothing left to photograph."
    } | ConvertTo-Json -Compress)
    exit 1
}

$target = $candidates[0]

$outDir = Split-Path -Parent $Out
if ($outDir -and -not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$bitmap = New-Object System.Drawing.Bitmap($target.Width, $target.Height)
try {
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $hdc = $graphics.GetHdc()
        try {
            $painted = [WindowShot]::PrintWindow($target.Handle, $hdc, [WindowShot]::RENDER_FULL_CONTENT)
        } finally {
            $graphics.ReleaseHdc($hdc)
        }
    } finally {
        $graphics.Dispose()
    }

    if (-not $painted) {
        Write-Output (@{ ok = $false; reason = 'the window refused to paint a copy of itself' } | ConvertTo-Json -Compress)
        exit 1
    }

    if ($CropX -ge 0 -and $CropY -ge 0 -and $CropW -gt 0 -and $CropH -gt 0) {
        # Keep the region inside the picture, so a slightly-too-big box is
        # trimmed rather than throwing.
        $cw = [Math]::Min($CropW, $target.Width - $CropX)
        $ch = [Math]::Min($CropH, $target.Height - $CropY)
        if ($cw -le 0 -or $ch -le 0) {
            Write-Output (@{ ok = $false; reason = "the region ($CropX,$CropY) ${CropW}x${CropH} falls outside the $($target.Width)x$($target.Height) window" } | ConvertTo-Json -Compress)
            exit 1
        }
        $bw = $cw * $Zoom
        $bh = $ch * $Zoom
        $magnified = New-Object System.Drawing.Bitmap $bw, $bh
        try {
            $mg = [System.Drawing.Graphics]::FromImage($magnified)
            try {
                # Nearest-neighbour, not smoothing: a blurred button edge is
                # exactly what makes a position ambiguous.
                $mg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                $destRect = New-Object System.Drawing.Rectangle 0, 0, $bw, $bh
                $srcRect = New-Object System.Drawing.Rectangle $CropX, $CropY, $cw, $ch
                $mg.DrawImage($bitmap, $destRect, $srcRect, [System.Drawing.GraphicsUnit]::Pixel)
            } finally {
                $mg.Dispose()
            }
            $magnified.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
        } finally {
            $magnified.Dispose()
        }
    } else {
        $bitmap.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
    }
} finally {
    $bitmap.Dispose()
}

$size = (Get-Item $Out).Length

# A blank capture is the failure worth naming, because it looks like a success.
# An all-one-colour image compresses to almost nothing, so the file's own size
# tells you before you open it.
$suspiciouslySmall = ($size -lt 20000) -and ($CropW -le 0)

Write-Output (@{
    ok = $true
    path = (Resolve-Path $Out).Path
    width = $target.Width
    height = $target.Height
    bytes = $size
    pid = $target.Pid
    process = $target.Name
    title = $target.Title
    warning = if ($suspiciouslySmall) { 'the image is very small for its size, which usually means the window painted blank' } else { $null }
} | ConvertTo-Json -Compress)
