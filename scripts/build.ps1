# Compiles patched AS3 source with amxmlc and packages the AIR app with adt.
# Run decompile.ps1 and apply-patches.ps1 first.
#
# Usage:
#   .\scripts\build.ps1                    # compile-only: produces _build\app.game.air.swf (for adl)
#   .\scripts\build.ps1 -Package           # also build + sign the .air installer (prompts for cert pw)
#   .\scripts\build.ps1 -Target bundle     # a self-contained Windows game folder WITH sound
#   .\scripts\build.ps1 -Target android
#   .\scripts\build.ps1 -Target ios
#
# Packaging is OPT-IN: run-adl.ps1 loads the raw .swf, so day-to-day dev only needs the compile step.
#
# WHICH WINDOWS PACKAGE: -Target windows -Package makes a plain .air installer, and that kind of
# package cannot carry the game's sound and Steam add-ons (adt stops with error 112, "the target
# does not support native extensions"). -Target bundle makes a "captive runtime bundle" instead:
# a folder holding the game's .exe, its own copy of the AIR runtime and both add-ons - the same
# shape as the Steam install. It is 32-bit, because the add-ons are. It goes in a win32\ folder
# that needs the game's assets\ and gui\ folders beside it: see docs/build-workflow.md,
# "Windows self-contained bundle". Measured working with AIR SDK 51.3.2 on 2026-10-16.
#
# Prerequisites:
#   - AIR_HOME env var pointing to HARMAN AIR SDK root
#   - A signing certificate at the path set in $KeystorePath below
#     (never commit .p12 files — they are gitignored)
#
# Note: this is a starting template. First compile will likely surface a handful
# of JPEXS decompiler artifacts (missing 'override', minor type mismatches).
# Fix them one at a time — the output is ~95% compilable as-is.

param(
    [ValidateSet("windows","bundle","android","ios")]
    [string]$Target      = "windows",
    [switch]$Package,                           # opt-in: also build the signed .air/.apk/.ipa via adt
    [string]$KeystorePath = "SIGNING_KEY.p12",  # TODO: replace with real cert path
    # The certificate's password. Leave it out and adt asks for it; pass it only for a throwaway
    # self-signed certificate, since a command line is saved in the shell's history.
    [string]$StorePass   = "",
    # bundle only: the Steam install's win32 folder. It is only read, never changed: the add-ons,
    # the sound and Steam DLLs and the icons come from there and sit beside our compiled game.
    [string]$GamePath    = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32"
)
if ($Target -eq "bundle") { $Package = $true }   # a bundle is a package by definition

if (-not $env:AIR_HOME) {
    Write-Error "AIR_HOME is not set. Install HARMAN AIR SDK and set AIR_HOME to its root directory."
    exit 1
}

$amxmlc   = Join-Path $env:AIR_HOME "bin\amxmlc.bat"
$adt      = Join-Path $env:AIR_HOME "bin\adt.bat"
$RepoRoot = Split-Path $PSScriptRoot
$SrcRoot  = Join-Path $RepoRoot "_decompiled\scripts"
$LegacySrc = Join-Path $SrcRoot "scripts"
if (Test-Path $LegacySrc) { $SrcRoot = $LegacySrc }
$AppXml   = Join-Path $RepoRoot "META-INF\AIR\application.xml"
$BuildDir = Join-Path $RepoRoot "_build"
$SwfOut   = Join-Path $BuildDir "app.game.air.swf"

$requiredTools = @($amxmlc)
if ($Package) { $requiredTools += $adt }   # adt is only needed when packaging
foreach ($tool in $requiredTools) {
    if (-not (Test-Path $tool)) {
        Write-Error "$tool not found. Is AIR_HOME set correctly? ($env:AIR_HOME)"
        exit 1
    }
}
if (-not (Test-Path $SrcRoot)) {
    Write-Error "'$SrcRoot' not found. Run decompile.ps1 then apply-patches.ps1 first."
    exit 1
}

New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# ── Compile ──────────────────────────────────────────────────────────────────
Write-Host "Compiling ($Target) ..."
# -swf-version=20 stamps the output as SWF v20. NOTE: the game's 2013 captive AIR runtime still
# cannot run a SWF built with this 2025 SDK (newer APIs -> silent VerifyError at load), so the
# compiled client is launched under the SDK's modern runtime via scripts/run-adl.ps1, which loads
# v20 fine. Retained as the tested config; safe to remove if you only ever run under adl.
& $amxmlc `
    -swf-version=20 `
    -source-path $SrcRoot `
    -output $SwfOut `
    "$SrcRoot\GameMainAir.as"

if ($LASTEXITCODE -ne 0) { Write-Error "amxmlc failed."; exit 1 }
Write-Host "Compiled: $SwfOut"

# ── Package (opt-in) ───────────────────────────────────────────────────────────
if (-not $Package) {
    Write-Host ""
    Write-Host "Compile-only build complete. SWF ready: $SwfOut" -ForegroundColor Green
    Write-Host "Deploy it with run-adl.ps1 (it loads the raw .swf). Pass -Package to also build the signed installer." -ForegroundColor DarkGray
    exit 0
}

Write-Host "Packaging ..."
$keystoreArgs = @("-storetype", "pkcs12", "-keystore", $KeystorePath)
if ($StorePass) { $keystoreArgs += @("-storepass", $StorePass) }

if ($Target -eq "windows") {
    $out = Join-Path $BuildDir "BSFFactions.air"
    & $adt -package @keystoreArgs $out $AppXml $SwfOut
}
elseif ($Target -eq "bundle") {
    # 1. The two add-ons, repacked from the Steam install into _build\anes\.
    & (Join-Path $PSScriptRoot "build-anes.ps1") -GamePath $GamePath
    if ($LASTEXITCODE -ne 0) { Write-Error "Rebuilding the add-ons failed."; exit 1 }

    # 2. A copy of the descriptor that names THIS SDK's version, as run-adl.ps1 does - but keeping
    #    the <extensions> block, because here the add-ons really are there. The version is read
    #    from the SDK itself, so the same script works whichever SDK AIR_HOME points at.
    $sdkXml = [xml](Get-Content -Raw (Join-Path $env:AIR_HOME "airsdk.xml"))
    $appNs  = @($sdkXml.airSdk.applicationNamespaces.versionMap)[0].descriptorNamespace
    if (-not $appNs) { Write-Error "Could not read the SDK's version from airsdk.xml."; exit 1 }
    $desc = (Get-Content -Raw $AppXml) -replace 'http://ns\.adobe\.com/air/application/3\.7', $appNs
    $bundleXml = Join-Path $BuildDir "application-bundle.xml"
    [IO.File]::WriteAllText($bundleXml, $desc, (New-Object System.Text.UTF8Encoding($false)))

    # 3. The bundle itself. adt will not write over an existing one, so clear it first.
    $out = Join-Path $BuildDir "bundle\win32"
    if (Test-Path $out) { Remove-Item $out -Recurse -Force }
    $fromGame = @("icon", "fmodex.dll", "fmod_event.dll", "fmod_event_net.dll", "steam_api.dll", "steam_appid.txt")
    foreach ($f in $fromGame) {
        if (-not (Test-Path (Join-Path $GamePath $f))) { Write-Error "Missing $f in '$GamePath'. Pass -GamePath."; exit 1 }
    }
    & $adt -package @keystoreArgs -target bundle -arch x86 $out $bundleXml `
        -extdir (Join-Path $BuildDir "anes") `
        -C $GamePath @fromGame `
        -C $BuildDir "app.game.air.swf"
}
elseif ($Target -eq "android") {
    # Remove air.steamworks.ane.SteamworksAneContext from application.xml before packaging.
    $out = Join-Path $BuildDir "BSFFactions.apk"
    & $adt -package -target apk-debug @keystoreArgs $out $AppXml $SwfOut
}
elseif ($Target -eq "ios") {
    # Requires -provisioning-profile; add your .mobileprovision path here.
    $out = Join-Path $BuildDir "BSFFactions.ipa"
    & $adt -package -target ipa-debug @keystoreArgs $out $AppXml $SwfOut
}

if ($LASTEXITCODE -ne 0) { Write-Error "adt packaging failed."; exit 1 }
Write-Host "Done. Output: $out"
