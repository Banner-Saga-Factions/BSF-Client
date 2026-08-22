# run-adl.ps1 — Run the freshly-compiled client under the AIR SDK 51 debug launcher (adl).
#
# WHY: the Steam install ships a 2013 AIR runtime (AIR 3.7 / SWF v20) that cannot run a SWF compiled
# with AIR SDK 51. adl uses the modern SDK runtime, so the APIs our compiled code links against are
# present. This is NON-DESTRUCTIVE (it does not modify the Steam install) and — crucially — prints
# runtime errors / trace() output to the console (and to _build\adl-run.log), so a boot failure shows
# the actual error instead of exiting silently.
#
# PREREQS:
#   - AIR_HOME set to the AIR SDK 51 root (adl lives in $AIR_HOME\bin\adl.exe)
#   - The local server running on localhost:8082  (..\bsf-server\start-server.bat)
#   - The compiled SWF present in the install dir as app.game.air.swf:
#       .\scripts\build.ps1 -Target windows           # produces _build\app.game.air.swf
#       Copy-Item .\_build\app.game.air.swf "<GamePath>\app.game.air.swf" -Force
#
# IN-GAME: once at camp, press Ctrl+Shift+A to start the player-vs-AI battle.

param(
    [string]$GamePath  = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32",
    [string]$ServerUrl = "http://localhost:8082/",
    [string]$Username  = "test2",
    [string]$SteamId   = "123456"
)

if (-not $env:AIR_HOME) { Write-Error "AIR_HOME is not set. Point it at the AIR SDK 51 root."; exit 1 }
$adl = Join-Path $env:AIR_HOME "bin\adl.exe"
foreach ($p in @($adl, $GamePath)) {
    if (-not (Test-Path $p)) { Write-Error "Not found: $p"; exit 1 }
}
$swf = Join-Path $GamePath "app.game.air.swf"
if (-not (Test-Path $swf)) {
    Write-Error "No app.game.air.swf in '$GamePath'. Swap the compiled SWF in first (see header)."
    exit 1
}

$RepoRoot = Split-Path $PSScriptRoot
$srcDesc  = Join-Path $RepoRoot "META-INF\AIR\application.xml"
$buildDir = Join-Path $RepoRoot "_build"
$testDesc = Join-Path $buildDir "application-adl.xml"
$logFile  = Join-Path $buildDir "adl-run.log"
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

# Build an adl-friendly descriptor from the real one:
#   1. Bump the AIR namespace 3.7 -> 51.0 so SDK 51's adl accepts it.
#   2. Strip the <extensions> block so adl does not demand the FMOD/Steamworks ANEs via -extdir; the
#      code falls back to NullSoundDriver (sound) and NullSteamworks (Steam auth) when those
#      extensions are absent. (Discord auth lives in PreAuthState, not a Steamworks subclass.)
$desc = Get-Content -Raw $srcDesc
$desc = $desc -replace 'air/application/3\.7', 'air/application/51.0'
$desc = [regex]::Replace($desc, '(?s)\s*<extensions>.*?</extensions>', '')
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($testDesc, $desc, $utf8)
Write-Host "Wrote adl descriptor: $testDesc  (namespace 51.0, <extensions> stripped)" -ForegroundColor Cyan

# The client boots through login -> camp, so the server must be up.
$serverUp = Test-NetConnection -ComputerName localhost -Port 8082 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $serverUp) {
    Write-Host "WARNING: nothing is listening on localhost:8082 — start ..\bsf-server\start-server.bat first." -ForegroundColor Yellow
}

# Same arguments launch-game-1p.ps1 passes to the captive .exe.
$gameArgs = @(
    "--debug",
    "--server", $ServerUrl,
    "--username", $Username,
    "--factions",
    "--developer",
    "--steam_id", $SteamId,
    "--steam", "false",
    "--versus_start",
    "--versus_countdown", "0"
)

# root-dir = the install dir, so <content>app.game.air.swf</content> and all game assets resolve there.
Write-Host "Launching under adl (root = $GamePath) ..." -ForegroundColor Green
Write-Host "In-game: press Ctrl+Shift+A for the player-vs-AI battle (only after your party has loaded)." -ForegroundColor DarkGray
Write-Host "Watch this console for errors." -ForegroundColor DarkGray
Write-Host ""
# The Tee-Object below only flushes when the pipeline ends, so while the game is running
# $logFile still holds the PREVIOUS session - and force-killing the game loses this one
# entirely. Say so here rather than letting someone read a stale file as today's evidence.
Write-Host "LOGS - read this before trusting a log file:" -ForegroundColor Yellow
Write-Host "  While the game is running, $logFile still contains the PREVIOUS run." -ForegroundColor Yellow
Write-Host "  It is only written when the game exits, and is lost entirely if you force-kill it." -ForegroundColor Yellow
Write-Host "  The live log is: $env:APPDATA\TheBannerSagaFactions\Local Store\logs\A-0.log.txt" -ForegroundColor Yellow
Write-Host "  That file is locked while the game runs, so read it after exit." -ForegroundColor Yellow
Write-Host ""

& $adl -profile extendedDesktop $testDesc $GamePath -- @gameArgs *>&1 | Tee-Object -FilePath $logFile

Write-Host ""
Write-Host "adl exited. This run's output is now in $logFile" -ForegroundColor Yellow
