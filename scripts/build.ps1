# Compiles patched AS3 source with amxmlc and packages the AIR app with adt.
# Run decompile.ps1 and apply-patches.ps1 first.
#
# Usage:
#   .\scripts\build.ps1                    # compile-only: produces _build\app.game.air.swf (for adl)
#   .\scripts\build.ps1 -Package           # also build + sign the .air installer (prompts for cert pw)
#   .\scripts\build.ps1 -Target android
#   .\scripts\build.ps1 -Target ios
#
# Packaging is OPT-IN: run-adl.ps1 loads the raw .swf, so day-to-day dev only needs the compile step.
# The adt packaging step needs a signing cert and rejects the Steamworks/FMOD ANEs on desktop targets
# (error 112), so it is skipped unless you pass -Package.
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
    [ValidateSet("windows","android","ios")]
    [string]$Target      = "windows",
    [switch]$Package,                           # opt-in: also build the signed .air/.apk/.ipa via adt
    [string]$KeystorePath = "SIGNING_KEY.p12"   # TODO: replace with real cert path
)

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

if ($Target -eq "windows") {
    $out = Join-Path $BuildDir "BSFFactions.air"
    & $adt -package @keystoreArgs $out $AppXml $SwfOut
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
