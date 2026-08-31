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
# IN-GAME: with -Landing camp, press Ctrl+Shift+A once at camp to start the player-vs-AI battle.
# The default landing is the match search instead, which is a different screen - see -Landing below.

# TWO PLAYERS AT ONCE: pass two comma-separated names and ids and the game builds one view per
# name, side by side in a single window — left is the first name, right is the second. Each half is
# a separate game with its own login and its own connection. This is game code, so it works here
# just as it does for the Steam build:
#     .\scripts\run-adl.ps1 -Username "test,Pieloaf" -SteamId "123456,293850"

param(
    [string]$GamePath  = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32",
    [string]$ServerUrl = "http://localhost:8082/",
    [string]$Username  = "test2",
    [string]$SteamId   = "123456",
    # Launch whatever SWF is installed, even when it is not the one we just built. Off by default,
    # because launching the shipped build by accident looks exactly like launching ours.
    [switch]$AllowUnpatched,
    # WHERE THE PLAYER ENDS UP after logging in.
    #   versus (default) - straight into the match search, which is what every previous run did.
    #   camp             - the town, from which the great hall, mead house and proving grounds are
    #                      reachable by clicking. This takes MORE than leaving out --versus_start: see
    #                      the note on argument order further down, which is what actually makes it work.
    # CAMP NEEDS AN ACCOUNT THAT HAS FINISHED THE TUTORIAL. FactionsState sends an account with
    # completed_tutorial = 0 to the tutorial instead, which looks like the wrong screen rather than a
    # refusal. Check the accounts table before blaming the launcher.
    [ValidateSet('versus', 'camp')]
    [string]$Landing = 'versus'
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

# WHICH BUILD IS ACTUALLY INSTALLED? The check above only proves a game file is there, not that it
# is ours. Launching the shipped file under this launcher works fine and looks completely normal —
# but it has no mod bridge and no Ctrl+Shift+A practice battle, and nothing on screen says so.
# Compare it against what we last built and refuse rather than let that afternoon happen.
$builtSwf = Join-Path $buildDir "app.game.air.swf"
if (-not (Test-Path $builtSwf)) {
    Write-Host "NOTE: no $builtSwf to compare against, so which build is installed is unknown." -ForegroundColor Yellow
    Write-Host "      Run .\scripts\build.ps1 if you meant to launch our build." -ForegroundColor Yellow
} else {
    $installedHash = (Get-FileHash $swf -Algorithm MD5).Hash
    $builtHash     = (Get-FileHash $builtSwf -Algorithm MD5).Hash
    if ($installedHash -ne $builtHash) {
        Write-Host "The game file installed at:" -ForegroundColor Red
        Write-Host "  $swf  ($installedHash)" -ForegroundColor Red
        Write-Host "is NOT the one we built:" -ForegroundColor Red
        Write-Host "  $builtSwf  ($builtHash)" -ForegroundColor Red
        Write-Host ""
        Write-Host "That is almost certainly the shipped game. It will start and look right, but it has" -ForegroundColor Yellow
        Write-Host "no mod bridge and no Ctrl+Shift+A practice battle." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To launch our build, copy it in first:" -ForegroundColor Cyan
        Write-Host "  Copy-Item '$builtSwf' '$swf' -Force" -ForegroundColor Cyan
        Write-Host "To launch the installed one on purpose, pass -AllowUnpatched." -ForegroundColor DarkGray
        if (-not $AllowUnpatched) {
            exit 1
        }
        Write-Host "-AllowUnpatched given; launching the installed file anyway." -ForegroundColor Yellow
    } else {
        Write-Host "Installed game file matches our build ($builtHash)." -ForegroundColor Green
    }
}

# One id per name, or the later views silently share the first id and log in as each other.
$nameCount = ($Username -split ",").Count
$idCount   = ($SteamId  -split ",").Count
if ($nameCount -ne $idCount) {
    Write-Error "Got $nameCount name(s) but $idCount id(s). Pass one id per name, e.g. -Username 'a,b' -SteamId '1,2'."
    exit 1
}
if ($nameCount -gt 1) {
    Write-Host "Two-player mode: $nameCount views in one window, left to right - $Username" -ForegroundColor Cyan
}

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

# The client cannot get past login without the server, whichever landing is asked for.
$serverUp = Test-NetConnection -ComputerName localhost -Port 8082 -InformationLevel Quiet -WarningAction SilentlyContinue
if (-not $serverUp) {
    Write-Host "WARNING: nothing is listening on localhost:8082 - start ..\bsf-server\start-server.bat first." -ForegroundColor Yellow
}

# Same arguments launch-game-1p.ps1 passes to the captive .exe, minus --developer: see below.
#
# THE RUN MODE HAS TO END UP AS "FACTIONS", OR THE GAME STOPS AT THE MAIN MENU.
# Several arguments set that one value and the last one given wins, so what matters is not which
# ones appear but which one appears last. --factions sets it; --versus_start sets it as well AND
# asks for the match search; --developer sets it to something else. Anything other than FACTIONS -
# including the default, which is BETA when no mode argument is given at all - means ReadyState
# never enters FactionsState and the game stops at the main menu without announcing a place.
#
# WE USED TO PASS --developer HERE AND IT NEVER DID ANYTHING. It sets the run mode and nothing
# else, and in both landings a later argument overwrote it - --versus_start for the match search,
# --factions for camp. Its only real effect was to make the ORDER of the list load-bearing, which
# cost a run to diagnose when the camp landing was added. It is gone, and with it the trap.
$gameArgs = @(
    "--debug",
    "--server", $ServerUrl,
    "--username", $Username
)
# --factions in both landings. For camp that is what puts the run mode where it needs to be, and
# leaving out --versus_start is what lets FactionsState run out of branches, complete, and hand on
# through TownLoadState to the town.
$gameArgs += @("--factions")
$gameArgs += @(
    "--steam_id", $SteamId,
    "--steam", "false"
)
if ($Landing -eq 'versus') {
    $gameArgs += @("--versus_start")
}
$gameArgs += @("--versus_countdown", "0")
Write-Host "Landing: $Landing" -ForegroundColor Cyan

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
