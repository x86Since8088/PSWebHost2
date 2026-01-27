#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Scan codebase for dot-sourcing violations

.DESCRIPTION
    Finds all instances of dot-sourcing in the codebase
    Excludes test files and legitimate uses
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Scanning for Dot-Sourcing Violations ==========" -ForegroundColor Cyan

# Find all .ps1 files (exclude tests and specific allowed patterns)
$allFiles = Get-ChildItem -Path @('apps', 'routes', 'system', 'modules') -Recurse -Filter "*.ps1" -File -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -notmatch '\.Tests\.ps1$' -and
        $_.Name -notmatch '^Test-' -and
        $_.DirectoryName -notmatch '\\tests\\'
    }

Write-Host "Scanning $($allFiles.Count) files..." -ForegroundColor Yellow

$violations = @()

foreach ($file in $allFiles) {
    try {
        $content = Get-Content $file.FullName -Raw -ErrorAction Stop

        # Pattern: Dot-sourcing with variable or path
        # Matches:  . $variableName
        #           . "$path"
        #           . (Join-Path ...)
        # But NOT:  . { scriptblock }  (legitimate use)
        if ($content -match '(?m)^\s*\.\s+[\$\(][^{]') {
            $matches = Select-String -Path $file.FullName -Pattern '^\s*\.\s+[\$\(]' -AllMatches

            foreach ($match in $matches) {
                $violations += [PSCustomObject]@{
                    File = $file.FullName -replace [regex]::Escape($PWD), '.'
                    Line = $match.LineNumber
                    Code = $match.Line.Trim()
                    App = if ($file.FullName -match 'apps\\([^\\]+)') { $Matches[1] } else { 'N/A' }
                }
            }
        }
    } catch {
        Write-Verbose "Could not scan $($file.FullName): $($_.Exception.Message)"
    }
}

Write-Host "`n========== Results ==========" -ForegroundColor Cyan

if ($violations.Count -eq 0) {
    Write-Host "✅ No dot-sourcing violations found!" -ForegroundColor Green
    Write-Host "   All code uses proper module imports" -ForegroundColor Gray
} else {
    Write-Host "❌ Found $($violations.Count) dot-sourcing violations:" -ForegroundColor Red
    Write-Host ""

    # Group by app
    $byApp = $violations | Group-Object App | Sort-Object Name

    foreach ($appGroup in $byApp) {
        Write-Host "`n📦 App: $($appGroup.Name)" -ForegroundColor Yellow
        Write-Host "   $($appGroup.Count) violations" -ForegroundColor Gray

        foreach ($violation in ($appGroup.Group | Sort-Object File, Line)) {
            Write-Host "`n   File: $($violation.File):$($violation.Line)" -ForegroundColor White
            Write-Host "   Code: $($violation.Code)" -ForegroundColor Yellow
        }
    }

    Write-Host "`n========== Recommendations ==========" -ForegroundColor Cyan
    Write-Host "For each violation:" -ForegroundColor White
    Write-Host "1. Convert the dot-sourced script to a proper module" -ForegroundColor Gray
    Write-Host "2. Create a .psd1 manifest" -ForegroundColor Gray
    Write-Host "3. Use Import-TrackedModule instead" -ForegroundColor Gray
    Write-Host "4. Update all references" -ForegroundColor Gray
    Write-Host ""
    Write-Host "See MODULE_LOADING_ACCOUNTABILITY_CHECKLIST.md for details" -ForegroundColor Gray
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Files Scanned: $($allFiles.Count)" -ForegroundColor White
Write-Host "Violations: $($violations.Count)" -ForegroundColor $(if ($violations.Count -eq 0) { 'Green' } else { 'Red' })

# Export results to CSV for analysis
if ($violations.Count -gt 0) {
    $csvPath = "DotSourcingViolations_$(Get-Date -Format 'yyyy-MM-dd').csv"
    $violations | Export-Csv -Path $csvPath -NoTypeInformation
    Write-Host "Exported to: $csvPath" -ForegroundColor Gray
}

Write-Host ""

return $violations
