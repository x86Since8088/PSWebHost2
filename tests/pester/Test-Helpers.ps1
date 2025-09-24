# tests\Test-Helpers.ps1

function FirstError {
    param (
        [ScriptBlock]$Expression
    )
    try {
        & $Expression 2>$null
    } catch {
        return $_ # Return the error object
    }
    return $null # No error occurred
}