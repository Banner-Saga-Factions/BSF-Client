# apply-fix.ps1 — Patches Zeno's schema-mismatch issues so The Banner Saga's
# editor can compile and load the Mod Content DLC source assets.
#
# Run AFTER you've already used Zeno's "Mod..." dialog to create your project.
# Usage: .\apply-fix.ps1 -ModId <yourmodid> [-GameRoot <path>] [-ModRoot <path>]
#
# This script:
#   1. Restores 6 broken compiled .json.z files from your game install.
#   2. Marks them read-only (so Zeno's compiler can't delete them on relaunch).
#   3. Applies the saga1.json schema migration so the saga master file compiles.
#   4. Unlocks the compiled saga1.json.z so the compiler can write a fresh one.
#
# Idempotent — running it twice is safe.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ModId,

    [string]$GameRoot = "C:\Program Files (x86)\Steam\steamapps\common\tbs",

    [string]$ModRoot
)

$ErrorActionPreference = "Stop"

if (-not $ModRoot) {
    $ModRoot = Join-Path $env:USERPROFILE "tbs_mods\$ModId"
}

$GameAssets = Join-Path $GameRoot "assets"
$ModAssets  = Join-Path $ModRoot  "assets"
$ModSrc     = Join-Path $ModRoot  "assets-src"

Write-Host "Game root:  $GameRoot"
Write-Host "Mod root:   $ModRoot"
Write-Host ""

# --- Sanity checks ---
if (-not (Test-Path $GameAssets)) {
    Write-Error "Game install not found at: $GameAssets`nPass the correct path with -GameRoot."
    exit 1
}

if (-not (Test-Path (Join-Path $GameRoot "assets-src")) -and -not (Test-Path $ModSrc)) {
    Write-Warning "TBS - Mod Content DLC may not be installed. Open Steam -> The Banner Saga -> Properties -> DLC and tick 'TBS - Mod Content'."
}

if (-not (Test-Path $ModRoot)) {
    Write-Error "Mod folder not found at: $ModRoot`nRun Zeno, click 'Mod...', and complete the setup first."
    exit 1
}

# --- Files to restore + lock (saga1.json.z handled separately via source fix) ---
$brokenFiles = @(
    "common\ability\_ability_index.json.z",
    "saga1\locale\fr\convo\part5\cnv_chat_eyvindawaken.json.z",
    "saga1\scene\part2\wld_einartoft_2\wld_einartoft_2.json.z",
    "saga1\scene\map\map_camp.json.z",
    "saga1\scene\part1\wld_grofheim_2\wld_grofheim_2.json.z",
    "saga1\scene\part2\cin_einartoft\cin_einartoft.json.z",
    "saga1\scene\battle\music\frostvellr.btlmusic.json.z"
)

Write-Host "=== Restoring and locking 6 broken compiled files ==="
foreach ($f in $brokenFiles) {
    $src = Join-Path $GameAssets $f
    $dst = Join-Path $ModAssets  $f

    if (-not (Test-Path $src)) {
        Write-Host "  skip (not in game install): $f"
        continue
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null

    # Clear read-only attribute first if present (so we can overwrite)
    if (Test-Path $dst) {
        (Get-Item $dst).IsReadOnly = $false
    }

    Copy-Item -Force $src $dst
    (Get-Item $dst).IsReadOnly = $true
    Write-Host "  locked: $f"
}

# --- saga1.json source-edit fix ---
Write-Host ""
Write-Host "=== Applying saga1.json schema migration ==="
$saga1Src = Join-Path $ModSrc "saga1\saga1.json"

if (-not (Test-Path $saga1Src)) {
    Write-Error "saga1.json not found at $saga1Src`nDid the Mod... prep step finish? Check assets-src exists."
    exit 1
}

$content = Get-Content -Raw -Encoding UTF8 $saga1Src

$alreadyPatched = ($content -match '"title_id":\s*"title_tbs1"') -and ($content -notmatch '"fevs":\s*\[')

if ($alreadyPatched) {
    Write-Host "  saga1.json already patched, skipping"
} else {
    # Backup once
    if (-not (Test-Path "$saga1Src.bak")) {
        Copy-Item $saga1Src "$saga1Src.bak"
        Write-Host "  backup created: saga1.json.bak"
    }

    $old = "`t`"dlcsUrl`": `"saga1/dlcs1.json.z`",`n" +
           "`t`"fevs`": [`n" +
           "`t`t`"saga1/fmod/saga1.fev`"`n" +
           "`t],`n" +
           "`t`"happenings`": [`n"

    $new = "`t`"dlcsUrl`": `"saga1/dlcs1.json.z`",`n" +
           "`t`"campUrls`": [`n" +
           "`t`t`"saga1/scene/camp/cmp_snow/cmp_snow.json.z`",`n" +
           "`t`t`"saga1/scene/camp/cmp_forest/cmp_forest.json.z`"`n" +
           "`t],`n" +
           "`t`"fmodPreloadUrl`": `"saga1/fmod/preload_banks.json.z`",`n" +
           "`t`"talentDefsUrl`": `"common/character/talent/talents.json.z`",`n" +
           "`t`"title_id`": `"title_tbs1`",`n" +
           "`t`"warPoppeningContinueUrl`": `"saga1/convo/war/cnv_war_decide.json.z`",`n" +
           "`t`"warPoppeningImpl`": `"Action_War_Impl_1`",`n" +
           "`t`"warPoppeningUrl`": `"saga1/convo/war/cnv_war.json.z`",`n" +
           "`t`"happenings`": [`n"

    # Detect line-ending style in the source so we match correctly
    if ($content -match "`r`n") {
        $old = $old -replace "`n", "`r`n"
        $new = $new -replace "`n", "`r`n"
    }

    if ($content.Contains($old)) {
        $patched = $content.Replace($old, $new)
        Set-Content -Path $saga1Src -Value $patched -Encoding UTF8 -NoNewline
        Write-Host "  patched: saga1.json"
    } else {
        Write-Error "Expected 'fevs' block not found in saga1.json — file may have an unexpected format. Aborting saga1 patch."
        exit 1
    }
}

# --- Unlock compiled saga1.json.z so compiler can rewrite it ---
$saga1Z = Join-Path $ModAssets "saga1\saga1.json.z"
if (Test-Path $saga1Z) {
    $item = Get-Item $saga1Z
    if ($item.IsReadOnly) {
        $item.IsReadOnly = $false
        Write-Host "  unlocked: saga1\saga1.json.z (compiler will rewrite from source)"
    }
}

Write-Host ""
Write-Host "Done. Relaunch Zeno."
Write-Host "Expected compile log: 'WRITING all outputs for saga1/saga1.json.z' and 'errs=14, oks=1'."
Write-Host "To edit the saga master file in Zeno: File -> Open -> $saga1Src"
