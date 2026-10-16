# build-anes.ps1 — rebuild the game's two add-ons (sound and Steam) as files the packager accepts.
#
# WHAT THIS DOES: the game talks to its sound engine (FMOD) and to Steam through two "native
# extensions" (add-ons, .ane files: a small Flash library plus a Windows DLL). The Steam install
# holds them only in unpacked form, under win32\META-INF\AIR\extensions\<id>\, which the packager
# (adt) cannot take as input. This script repacks each one into a proper .ane file in _build\anes\,
# ready for build.ps1 -Target bundle. Nothing in the game folder is changed; it is only read.
#
# HOW: each unpacked add-on holds catalog.xml + library.swf at its top level (together they are the
# contents of a .swc library) and META-INF\ANE\extension.xml + Windows-x86\ (the DLL). Zip the first
# two into a .swc, then let adt build the .ane from the descriptor, the .swc and the DLL folder.
# Measured 2026-10-16 with AIR SDK 51.3.2: adt accepts the 2013 descriptors unchanged.
#
# USAGE:
#   .\scripts\build-anes.ps1
#   .\scripts\build-anes.ps1 -GamePath "D:\Games\The Banner Saga Factions\win32"

param(
    [string]$GamePath = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32"
)

$ErrorActionPreference = "Stop"

if (-not $env:AIR_HOME) { Write-Error "AIR_HOME is not set. Point it at the AIR SDK root."; exit 1 }
$adt = Join-Path $env:AIR_HOME "bin\adt.bat"
if (-not (Test-Path $adt)) { Write-Error "$adt not found. Is AIR_HOME set correctly? ($env:AIR_HOME)"; exit 1 }

$extRoot = Join-Path $GamePath "META-INF\AIR\extensions"
if (-not (Test-Path $extRoot)) { Write-Error "No add-ons found at '$extRoot'. Pass -GamePath."; exit 1 }

$RepoRoot = Split-Path $PSScriptRoot
$outDir   = Join-Path $RepoRoot "_build\anes"
$workRoot = Join-Path $RepoRoot "_build\anes-work"
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

foreach ($ext in Get-ChildItem $extRoot -Directory) {
    $id   = $ext.Name
    $work = Join-Path $workRoot $id
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory -Path $work -Force | Out-Null

    # The .swc is just a zip of these two files. tar.exe ships with Windows 10 and later.
    Push-Location $ext.FullName
    try {
        tar.exe -a -c -f (Join-Path $work "library.zip") catalog.xml library.swf
        if ($LASTEXITCODE -ne 0) { throw "zipping the library for $id failed" }
    } finally { Pop-Location }
    $swc = Join-Path $work "library.swc"
    Move-Item (Join-Path $work "library.zip") $swc

    $ane  = Join-Path $outDir "$id.ane"
    $desc = Join-Path $ext.FullName "META-INF\ANE\extension.xml"
    $dlls = Join-Path $ext.FullName "META-INF\ANE\Windows-x86"
    if (Test-Path $ane) { Remove-Item $ane -Force }
    & $adt -package -target ane $ane $desc -swc $swc -platform Windows-x86 -C $dlls .
    if ($LASTEXITCODE -ne 0) { Write-Error "adt could not build $id.ane"; exit 1 }
    Write-Host "Built $ane" -ForegroundColor Green
}

Remove-Item $workRoot -Recurse -Force
