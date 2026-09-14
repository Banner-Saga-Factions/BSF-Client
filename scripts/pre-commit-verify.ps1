<#
.SYNOPSIS
    Compile check run by the pre-commit hook: apply src/ patches, then compile (no packaging).

.DESCRIPTION
    Chains scripts/apply-patches.ps1 (copies src/ onto _decompiled/) and scripts/build.ps1
    (amxmlc compile only - no -Package, since packaging needs a certificate password and would
    hang a commit waiting for input). Requires AIR_HOME to already be set and _decompiled/ to
    already exist (run scripts/decompile.ps1 once first) - the same precondition build.ps1 always
    had on its own.

    Deliberately does NOT run anything under tests/: those tests drive the real running AIR
    client over the mod bridge, and launching the game automatically on every commit would need a
    display and could hang. See CLAUDE.md -> "Pre-commit check".

    apply-patches.ps1 does not call `exit` on its normal success path, so $LASTEXITCODE is reset
    first - otherwise it is empty in a fresh process and the check below fails every commit. The
    reset must be $global:LASTEXITCODE: a plain `$LASTEXITCODE = 0` makes a local copy that
    build.ps1 also reads when this script is called from another one, so a failed compile reported
    success (#279).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/pre-commit-verify.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    $global:LASTEXITCODE = 0
    & (Join-Path $PSScriptRoot 'apply-patches.ps1')
    if ($LASTEXITCODE -ne 0) { exit 1 }

    & (Join-Path $PSScriptRoot 'build.ps1')
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
