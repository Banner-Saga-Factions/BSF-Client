# Settings for the report-only script lint (.github/workflows/quality-report.yml).
@{
    ExcludeRules = @(
        # The scripts that use Write-Host print progress and results meant to be read on screen.
        'PSAvoidUsingWriteHost'
    )
}
