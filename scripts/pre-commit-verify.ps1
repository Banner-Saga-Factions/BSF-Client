<#
.SYNOPSIS
    Compile check run by the pre-commit hook: apply src/ patches, then compile (no packaging).

.DESCRIPTION
    Chains scripts/apply-patches.ps1 (copies src/ onto _decompiled/) and scripts/build.ps1
    (amxmlc compile only — no -Package, since packaging needs a certificate password and would
    hang a commit waiting for input). Requires AIR_HOME to already be set and _decompiled/ to
    already exist (run scripts/decompile.ps1 once first) — the same precondition build.ps1 always
    had on its own.

    Deliberately does NOT run anything under tests/: those tests drive the real running AIR
    client over the mod bridge, and launching the game automatically on every commit would need a
    display and could hang. See CLAUDE.md -> "Pre-commit check".

    apply-patches.ps1 does not call `exit` on its normal success path, so $LASTEXITCODE would
    otherwise still hold whatever a much earlier command left it at. Resetting it to 0
    immediately before the call makes "still 0 afterward" mean what it looks like it means.

.EXAMPLE
    ./scripts/pre-commit-verify.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'apply-patches.ps1')
    if ($LASTEXITCODE -ne 0) { exit 1 }

    & (Join-Path $PSScriptRoot 'build.ps1')
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
