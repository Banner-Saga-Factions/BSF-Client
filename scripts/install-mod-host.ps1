# install-mod-host.ps1 — put the test helper program where the game will find it.
#
# WHAT THIS DOES: the game looks for a helper ("mod host") in a mods\ folder inside its own
# install directory. This copies our helper there and writes the small descriptor that tells the
# game how to start it. Nothing else in the install is touched.
#
# WHY A DESCRIPTOR: the game can start mods\host.exe on its own, but our helper is a script, which
# needs an interpreter to run it. mods\host.json names the program and its arguments, so a helper
# written in any language can be launched. That file names something the game will execute — treat
# it as seriously as you would an executable you dropped in the game folder.
#
# USAGE:
#   .\scripts\install-mod-host.ps1                          # install
#   .\scripts\install-mod-host.ps1 -Script .\my-script.json # install and stage a command script
#   .\scripts\install-mod-host.ps1 -Remove                  # take it all out again
#
# AFTER INSTALLING, look for these lines in the game log to confirm it worked:
#   ModBridge started host: ...node.exe host.js
#   [modhost] bridge ready ...

param(
    [string]$GamePath = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32",
    [string]$Script   = "",
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $GamePath)) {
    Write-Error "Game directory not found: $GamePath"
    exit 1
}

$modsDir = Join-Path $GamePath "mods"

if ($Remove) {
    if (Test-Path $modsDir) {
        Remove-Item -Recurse -Force $modsDir
        Write-Host "Removed $modsDir" -ForegroundColor Green
        Write-Host "The game will now log 'ModBridge disabled: no mods/host.exe' and run normally." -ForegroundColor DarkGray
    } else {
        Write-Host "Nothing to remove - $modsDir does not exist." -ForegroundColor Yellow
    }
    exit 0
}

# The helper is a script, so we need the program that runs it. Resolve it to a real file path:
# the game starts the helper directly and cannot search the PATH the way a shell does.
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) {
    Write-Error "Could not find node on your PATH. Install Node.js, or edit mods\host.json by hand to name a different program."
    exit 1
}

$hostSource = Join-Path $PSScriptRoot "mod-host\host.js"
if (-not (Test-Path $hostSource)) {
    Write-Error "Missing $hostSource"
    exit 1
}

New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
Copy-Item $hostSource (Join-Path $modsDir "host.js") -Force

# The descriptor. "args" is relative because the game starts the helper with mods\ as its
# working directory.
$descriptor = [ordered]@{
    program = $node
    args    = @("host.js")
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $modsDir "host.json"), ($descriptor | ConvertTo-Json), $utf8)

if ($Script) {
    if (-not (Test-Path $Script)) {
        Write-Error "Script file not found: $Script"
        exit 1
    }
    Copy-Item $Script (Join-Path $modsDir "script.json") -Force
    Write-Host "Staged command script from $Script" -ForegroundColor Cyan
} elseif (Test-Path (Join-Path $modsDir "script.json")) {
    Write-Host "Leaving the existing mods\script.json in place." -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Installed the test helper into $modsDir" -ForegroundColor Green
Write-Host "  runs as: $node host.js" -ForegroundColor DarkGray
Write-Host ""
Write-Host "While the game runs it writes everything the game sent to:" -ForegroundColor Yellow
Write-Host "  $modsDir\transcript.jsonl" -ForegroundColor Yellow
Write-Host "That file is your evidence. It should never contain a real password or session key." -ForegroundColor Yellow
