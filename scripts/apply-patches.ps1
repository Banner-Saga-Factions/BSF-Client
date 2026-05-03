# Copies patch files from src/ onto the JPEXS decompile output in _decompiled/.
# Run this after decompile.ps1 and before build.ps1.
#
# Note: JPEXS exports to _decompiled/scripts/scripts/ (double-nested).
# Files in src/ must mirror the AS3 package path, e.g.:
#   src/game/session/states/PreAuthState.as
#   -> _decompiled/scripts/scripts/game/session/states/PreAuthState.as

$RepoRoot    = Split-Path $PSScriptRoot
$SrcDir      = Join-Path $RepoRoot "src"
$TargetRoot  = Join-Path $RepoRoot "_decompiled\scripts\scripts"

if (-not (Test-Path $TargetRoot)) {
    Write-Error "'$TargetRoot' not found. Run scripts\decompile.ps1 first."
    exit 1
}

$files = Get-ChildItem $SrcDir -Recurse -File
if ($files.Count -eq 0) {
    Write-Host "No patch files found in src/ — nothing to apply."
    exit 0
}

foreach ($file in $files) {
    $relative = $file.FullName.Substring($SrcDir.Length).TrimStart('\')
    $dest     = Join-Path $TargetRoot $relative
    $destDir  = Split-Path $dest

    if (-not (Test-Path $destDir)) {
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    }

    $isNew = -not (Test-Path $dest)
    Copy-Item $file.FullName $dest -Force
    $tag = if ($isNew) { "NEW    " } else { "PATCHED" }
    Write-Host "$tag $relative"
}

Write-Host ""
Write-Host "Done. $($files.Count) file(s) applied to $TargetRoot"
