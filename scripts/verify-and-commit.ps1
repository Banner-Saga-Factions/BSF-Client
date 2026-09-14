<#
.SYNOPSIS
    Runs the same compile check the pre-commit hook runs, then commits — skipping the hook's own
    redundant re-run of that check.

.DESCRIPTION
    The pre-commit hook (installed via simple-git-hooks, see package.json) runs
    scripts/pre-commit-verify.ps1 — apply src/ patches, then compile — on every `git commit`, and
    its full compiler output goes wherever the commit is run from. This script runs that same
    check itself first, with the full output captured to logs/verify-build.log (gitignored)
    instead of printed — only a short pass/fail line, or the tail of the log on failure, appears
    on screen. If it passes, it commits with SKIP_SIMPLE_GIT_HOOKS=1 set for that one git
    invocation: the hook's own documented off switch, not `git commit --no-verify` — it skips a
    repeat of a check this script just ran, not the check itself.

    Never runs `git add` — stage the files you want committed first.

.PARAMETER Message
    The full commit message (subject line first, body after — the same text you would pass to
    `git commit -m`).

.PARAMETER TailLines
    How many lines of the failing log to print on a compile failure. Default 40.

.EXAMPLE
    ./scripts/verify-and-commit.ps1 -Message "Fix the deploy-ready button not re-enabling after a cancelled drag"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Message,

    [int] $TailLines = 40
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Push-Location $repoRoot
try {
    if (-not (Test-Path logs)) {
        New-Item -ItemType Directory -Path logs -Force | Out-Null
    }

    $staged = git diff --cached --name-only
    if (-not $staged) {
        Write-Host "Nothing is staged — stage the files you want committed first." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "Verifying (apply-patches + compile) ..." -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'pre-commit-verify.ps1') *> logs/verify-build.log
    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "VERIFY FAILED — last $TailLines line(s) of logs/verify-build.log:" -ForegroundColor Red
        Get-Content logs/verify-build.log -Tail $TailLines
        exit 1
    }
    Write-Host "Build OK." -ForegroundColor Green

    Write-Host "Committing (pre-commit hook's own compile check skipped — just ran it above) ..." -ForegroundColor Cyan
    $env:SKIP_SIMPLE_GIT_HOOKS = '1'
    git commit -m $Message
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
