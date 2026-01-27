# Quick check: grep for the function exports in PSWebHost_Support
$psd1 = "C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psd1"
$psm1 = "C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psm1"

Write-Host "Checking PSWebHost_Support exports..." -ForegroundColor Cyan

# Get FunctionsToExport from manifest
$manifestContent = Get-Content $psd1 -Raw
if ($manifestContent -match "FunctionsToExport\s*=\s*@\(([\s\S]*?)\)") {
    $exportsBlock = $matches[1]
    $exported = $exportsBlock -split "[',\s]+" | Where-Object { $_ -match '\w' } | ForEach-Object { $_.Trim() }

    Write-Host "Found $($exported.Count) exported functions" -ForegroundColor Yellow

    # Get actual functions from psm1
    $psm1Content = Get-Content $psm1 -Raw
    $functionPattern = 'function\s+([a-zA-Z0-9_-]+)\s*\{'
    $actualFunctions = [regex]::Matches($psm1Content, $functionPattern) | ForEach-Object {
        $_.Groups[1].Value
    }

    Write-Host "Found $($actualFunctions.Count) defined functions" -ForegroundColor Yellow
    Write-Host ""

    # Check for mismatches
    $issues = @()
    foreach ($exportedFunc in $exported) {
        if ($actualFunctions -notcontains $exportedFunc) {
            $issues += $exportedFunc
        }
    }

    if ($issues.Count -gt 0) {
        Write-Host "ERRORS FOUND:" -ForegroundColor Red
        $issues | ForEach-Object {
            Write-Host "  - Exported but not defined: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "OK: All PSWebHost_Support exports are valid" -ForegroundColor Green
    }

    # Show the exports list
    Write-Host ""
    Write-Host "Exported functions:" -ForegroundColor Cyan
    $exported | ForEach-Object {
        $funcName = $_
        if ($actualFunctions -contains $funcName) {
            Write-Host "  OK: $funcName" -ForegroundColor Green
        } else {
            Write-Host "  ERROR: $funcName (not defined in .psm1)" -ForegroundColor Red
        }
    }
}
