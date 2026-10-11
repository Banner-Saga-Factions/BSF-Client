# Settings for the report-only script lint (.github/workflows/quality-report.yml).
# To run it by hand: Invoke-ScriptAnalyzer -Path scripts -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
@{
    # Errors and warnings only. The Information level is mostly style advice (trailing spaces and
    # the like) and would bury the findings that matter.
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # Every script here is a tool someone runs at a terminal, and its progress and results are
        # meant to be read on screen. The rule exists for scripts whose output is consumed by other
        # scripts, which is not the case in this repo.
        'PSAvoidUsingWriteHost'
    )
}
