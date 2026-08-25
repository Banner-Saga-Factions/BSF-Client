# Exports all ActionScript source from the original BSF SWF using JPEXS.
# Output goes to _decompiled/ in the repo root (gitignored).
#
# Usage:
#   .\scripts\decompile.ps1
#   .\scripts\decompile.ps1 -SwfPath "C:\path\to\app.game.air.swf"

param(
    [string]$SwfPath  = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32\app.game.air.swf",
    [string]$FfdecJar = "C:\Program Files (x86)\FFDec\ffdec.jar"
)

$RepoRoot  = Split-Path $PSScriptRoot
$OutputDir = Join-Path $RepoRoot "_decompiled"

if (-not (Test-Path $FfdecJar)) {
    Write-Error "JPEXS not found at '$FfdecJar'. Install from https://github.com/jindrapetrik/jpexs-decompiler/releases"
    exit 1
}
if (-not (Test-Path $SwfPath)) {
    Write-Error "SWF not found at '$SwfPath'. Use -SwfPath to provide a custom path."
    exit 1
}

try { $null = java -version 2>&1 }
catch {
    Write-Error "Java not found. Install Temurin 21 from https://adoptium.net/"
    exit 1
}

Write-Host "Decompiling: $SwfPath"
Write-Host "Output:      $OutputDir"
Write-Host ""

java -jar $FfdecJar -export script $OutputDir $SwfPath

if ($LASTEXITCODE -ne 0) {
    Write-Error "JPEXS export failed (exit code $LASTEXITCODE)."
    exit 1
}

# JPEXS exports AS3 sources under _decompiled/scripts/
# (Older JPEXS versions double-nested as scripts/scripts/ — fall back if seen.)
$ScriptsRoot = Join-Path $OutputDir "scripts"
$LegacyRoot  = Join-Path $ScriptsRoot "scripts"
if (Test-Path $LegacyRoot) { $ScriptsRoot = $LegacyRoot }
if (-not (Test-Path $ScriptsRoot)) {
    Write-Warning "Expected path '$ScriptsRoot' not found. JPEXS may have changed its output structure."
} else {
    $count = (Get-ChildItem $ScriptsRoot -Recurse -Filter "*.as").Count
    Write-Host ""
    Write-Host "Done. $count .as files exported to $ScriptsRoot"
}
