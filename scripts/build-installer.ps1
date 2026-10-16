# Builds the Windows setup file for our rebuilt game (BSF-Custom-Server #47, Wave 3a).
#
# WHAT THIS DOES: gathers the self-contained game folder made by build.ps1 -Target bundle and the
# game's art and sound folders (assets\, gui\) from a Steam install into _build\installer-stage\,
# then has Inno Setup (a free installer maker) pack them into one setup file in _build\installer\.
# The Steam install is only read, never changed.
#
# WHY: the AIR SDK licence (section 6.1) forbids handing out a program that "runs without
# installation", so players get a real installer, not a zip. See docs/build-workflow.md,
# "Windows installer".
#
# Usage (build the bundle first, and again after every commit - the commit check rebuilds the
# game file, which leaves an older bundle out of date):
#   $env:AIR_HOME="C:\AirSDK\AIRSDK_51.3.2"; .\scripts\build.ps1 -Target bundle
#   .\scripts\build-installer.ps1
#   .\scripts\build-installer.ps1 -Version 1.11.0 -LaunchArgs "--steam true --server https://example.org/" -PrivacyUrl https://example.org/privacy
#
# Prerequisites:
#   - Inno Setup 6: winget install JRSoftware.InnoSetup (free for non-commercial use)
#   - _build\bundle\win32 from build.ps1 -Target bundle

param(
    # The installer's own version. It must be above the original game's 1.10.51, so it is never
    # mistaken for Stoic's release, and each published setup should carry a higher one.
    [string]$Version    = "1.11.0",
    # The options the Start-menu shortcut passes to the game. The default is for local testing.
    [string]$LaunchArgs = "--steam true --server http://localhost:8082/",
    # Shown to the player before installing (licence section 6.4 needs a published privacy policy).
    [string]$PrivacyUrl = "(privacy policy address to come - BSF-Custom-Server #377)",
    # The Steam install's win32 folder, as in build.ps1. assets\ and gui\ come from the folder above it.
    [string]$GamePath   = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32",
    # Inno Setup's command-line compiler. Found automatically when left out.
    [string]$IsccPath   = ""
)

$RepoRoot  = Split-Path $PSScriptRoot
$BuildDir  = Join-Path $RepoRoot "_build"
$BundleDir = Join-Path $BuildDir "bundle\win32"
$StageDir  = Join-Path $BuildDir "installer-stage"
$InfoFile  = Join-Path $BuildDir "installer-info.txt"
$OutDir    = Join-Path $BuildDir "installer"
$IssFile   = Join-Path $RepoRoot "installer\bsf-factions.iss"
$GameRoot  = Split-Path $GamePath

# -- Checks ------------------------------------------------------------------------------------
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "-Version must look like 1.11.0 (three numbers)."; exit 1
}
if ([version]$Version -le [version]"1.10.51") {
    Write-Error "-Version $Version is not above the original game's 1.10.51."; exit 1
}

if (-not $IsccPath) {
    $found = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    $candidates = @()
    if ($found) { $candidates += $found.Source }
    $candidates += (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe")
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe") }
    $IsccPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $IsccPath -or -not (Test-Path $IsccPath)) {
    Write-Error "Inno Setup not found. Install it with: winget install JRSoftware.InnoSetup (or pass -IsccPath)."; exit 1
}

$bundleSwf = Join-Path $BundleDir "app.game.air.swf"
if (-not (Test-Path $bundleSwf)) {
    Write-Error "No bundle at '$BundleDir'. Run: .\scripts\build.ps1 -Target bundle"; exit 1
}
$latestSwf = Join-Path $BuildDir "app.game.air.swf"
if ((Test-Path $latestSwf) -and ((Get-Item $bundleSwf).LastWriteTime -lt (Get-Item $latestSwf).LastWriteTime)) {
    Write-Error "The bundle is older than the latest compiled game (a commit rebuilds it). Run: .\scripts\build.ps1 -Target bundle"; exit 1
}
foreach ($d in @("assets", "gui")) {
    if (-not (Test-Path (Join-Path $GameRoot $d))) {
        Write-Error "Missing '$d' beside '$GamePath'. Pass -GamePath (the Steam install's win32 folder)."; exit 1
    }
}

# -- Stage -------------------------------------------------------------------------------------
# robocopy /MIR makes each stage folder an exact copy, and only copies what changed since the
# last run. Exit codes below 8 mean success.
function Copy-Mirror($from, $to, $extra) {
    & robocopy $from $to /MIR /NFL /NDL /NJH /NJS /NP @extra | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Error "Copying '$from' failed (robocopy $LASTEXITCODE)."; exit 1 }
}
Write-Host "Staging files in $StageDir ..."
# Never ship the test helper (mods\), the backup of the original game file, or the SDK's tools.
Copy-Mirror $BundleDir (Join-Path $StageDir "win32") @("/XD", "mods", "/XF", "bk-app.game.air.swf", "adl*.exe", "adt*")
Copy-Mirror (Join-Path $GameRoot "assets") (Join-Path $StageDir "assets") @()
Copy-Mirror (Join-Path $GameRoot "gui") (Join-Path $StageDir "gui") @()

$tools = Get-ChildItem $StageDir -Recurse -File -Include "adl*.exe", "adt*" -ErrorAction SilentlyContinue
if ($tools) {
    Write-Error "The SDK's own tools must never be shipped (licence 3.3(a)(iv)): $($tools.FullName -join ', ')"; exit 1
}

# The page the player reads before installing. Plain ASCII, which Inno shows as-is.
$info = @"
The Banner Saga Factions (Community Server) - version $Version

This installs a community-maintained copy of Banner Saga: Factions that plays on the
community server. It does not change a Steam copy you already have. Saved games are
shared with the Steam copy.

Privacy policy: $PrivacyUrl

When the game starts you will see the HARMAN logo for about two seconds. HARMAN makes
the Adobe AIR runtime the game is built on, and its free licence requires the logo.
"@
[IO.File]::WriteAllText($InfoFile, ($info -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)

# -- Build -------------------------------------------------------------------------------------
Write-Host "Building the setup file with $IsccPath ..."
& $IsccPath /Q "/DAppVersion=$Version" "/DLaunchArgs=$LaunchArgs" "/DStageDir=$StageDir" `
    "/DInfoFile=$InfoFile" "/DOutputDir=$OutDir" $IssFile
if ($LASTEXITCODE -ne 0) { Write-Error "Inno Setup failed (ISCC $LASTEXITCODE)."; exit 1 }

$setup = Join-Path $OutDir "BSF-Client-Setup-$Version.exe"
$hash  = (Get-FileHash -Algorithm SHA256 $setup).Hash.ToLower()
$sizeMb = [math]::Round((Get-Item $setup).Length / 1MB)
Write-Host ""
Write-Host "Done. Output: $setup ($sizeMb MB)" -ForegroundColor Green
Write-Host "SHA-256: $hash"
