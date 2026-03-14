$modulesPath = "C:\SC\PsWebHost\modules"
$manifests = Get-ChildItem $modulesPath -Recurse -Filter *.psd1

Write-Host ""
Write-Host "=== Module Export Validation ===" -ForegroundColor Cyan
Write-Host ""

$issues = @()

foreach ($manifest in $manifests) {
    $moduleName = $manifest.BaseName
    Write-Host "Validating: $moduleName" -ForegroundColor Yellow

    $psm1File = Join-Path $manifest.DirectoryName "$moduleName.psm1"

    if (-not (Test-Path $psm1File)) {
        Write-Host "  WARNING: No .psm1 file found" -ForegroundColor Yellow
        continue
    }

    try {
        $manifestData = Import-PowerShellDataFile -Path $manifest.FullName
    } catch {
        Write-Host "  ERROR: Failed to parse manifest" -ForegroundColor Red
        $issues += $moduleName
        continue
    }

    $exportedFunctions = $manifestData.FunctionsToExport
    if ($null -eq $exportedFunctions -or $exportedFunctions.Count -eq 0) {
        Write-Host "  INFO: No functions exported" -ForegroundColor Gray
        continue
    }

    $psm1Content = Get-Content $psm1File -Raw
    $functionPattern = 'function\s+([a-zA-Z0-9_-]+)\s*\{'
    $actualFunctions = [regex]::Matches($psm1Content, $functionPattern) | ForEach-Object {
        $_.Groups[1].Value
    }

    Write-Host "  Exported: $($exportedFunctions.Count) | Defined: $($actualFunctions.Count)" -ForegroundColor Gray

    $missingInPsm1 = @()
    foreach ($exportedFunc in $exportedFunctions) {
        if ($actualFunctions -notcontains $exportedFunc) {
            $missingInPsm1 += $exportedFunc
        }
    }

    if ($missingInPsm1.Count -gt 0) {
        Write-Host "  ERROR: Exported but not defined:" -ForegroundColor Red
        $missingInPsm1 | ForEach-Object {
            Write-Host "    - $_" -ForegroundColor Red
        }
        $issues += $moduleName
    } else {
        Write-Host "  OK: All exports valid" -ForegroundColor Green
    }
    Write-Host ""
}

Write-Host "=== Summary ===" -ForegroundColor Cyan
Write-Host "Modules with issues: $($issues.Count)" -ForegroundColor $(if ($issues.Count -eq 0) { "Green" } else { "Red" })

if ($issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues found in: $($issues -join ', ')" -ForegroundColor Red
}
