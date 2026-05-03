# Compiles patched AS3 source with amxmlc and packages the AIR app with adt.
# Run decompile.ps1 and apply-patches.ps1 first.
#
# Usage:
#   .\scripts\build.ps1                    # defaults to windows
#   .\scripts\build.ps1 -Target android
#   .\scripts\build.ps1 -Target ios
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
    [string]$KeystorePath = "SIGNING_KEY.p12"   # TODO: replace with real cert path
)

if (-not $env:AIR_HOME) {
    Write-Error "AIR_HOME is not set. Install HARMAN AIR SDK and set AIR_HOME to its root directory."
    exit 1
}

$amxmlc   = Join-Path $env:AIR_HOME "bin\amxmlc.bat"
$adt      = Join-Path $env:AIR_HOME "bin\adt.bat"
$RepoRoot = Split-Path $PSScriptRoot
$SrcRoot  = Join-Path $RepoRoot "_decompiled\scripts\scripts"
$AppXml   = Join-Path $RepoRoot "META-INF\AIR\application.xml"
$BuildDir = Join-Path $RepoRoot "_build"
$SwfOut   = Join-Path $BuildDir "app.game.air.swf"

foreach ($tool in $amxmlc, $adt) {
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
& $amxmlc `
    -source-path $SrcRoot `
    -output $SwfOut `
    "$SrcRoot\GameMainAir.as"

if ($LASTEXITCODE -ne 0) { Write-Error "amxmlc failed."; exit 1 }
Write-Host "Compiled: $SwfOut"

# ── Package ───────────────────────────────────────────────────────────────────
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
