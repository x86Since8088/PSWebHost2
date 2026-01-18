#Requires -Version 7

<#
.SYNOPSIS
    Audits all component.js files for proper React registration

.DESCRIPTION
    Checks all component.js files to ensure they:
    1. Check before custom element registration: if (!customElements.get('...'))
    2. Register in window.cardComponents
    3. Use React component wrapper (not HTML string)

.EXAMPLE
    .\Audit-ComponentRegistrations.ps1

.EXAMPLE
    .\Audit-ComponentRegistrations.ps1 -Fix
#>

param(
    [switch]$Fix,
    [switch]$Verbose
)

$ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Component Registration Audit" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Find all component.js files
$componentFiles = Get-ChildItem -Path $ProjectRoot -Filter "component.js" -Recurse -File |
    Where-Object { $_.FullName -match '[\\/]public[\\/]elements[\\/]' }

Write-Host "Found $($componentFiles.Count) component.js files`n" -ForegroundColor Green

$issues = @()
$compliant = @()

foreach ($file in $componentFiles) {
    $relativePath = $file.FullName.Replace($ProjectRoot, '').TrimStart('\', '/')

    Write-Host "Checking: $relativePath" -ForegroundColor Gray

    $content = Get-Content -Path $file.FullName -Raw
    $fileIssues = @()

    # Extract component name from path
    $componentName = ($file.Directory.Name)

    # Check 1: Does it have customElements.define()?
    if ($content -match 'customElements\.define\s*\(\s*[''"]([^''"]+)[''"]') {
        $definedName = $matches[1]

        # Check if it has the safety check
        $hasCheck = $content -match "if\s*\(\s*!customElements\.get\s*\(\s*['\`"]$definedName['\`"]"

        if (-not $hasCheck) {
            $fileIssues += "❌ Missing safety check: if (!customElements.get('$definedName'))"
        }
    } else {
        $fileIssues += "⚠️  No customElements.define() found"
    }

    # Check 2: Does it register in window.cardComponents?
    $hasCardComponentsReg = $content -match 'window\.cardComponents\s*\[?\s*[''"]([^''"]+)[''"]?\s*\]?\s*='

    if (-not $hasCardComponentsReg) {
        $fileIssues += "❌ Missing window.cardComponents registration"
    } else {
        $registeredName = $matches[1]

        # Check 3: Is it a React component or HTML string?
        # Look for the registration pattern
        if ($content -match "window\.cardComponents\[['\`"]$registeredName['\`"]\]\s*=\s*function\s*\([^)]*\)\s*\{") {
            # It's a function - check if it returns React element or HTML string
            $afterFunction = $content -split "window\.cardComponents\[['\`"]$registeredName['\`"]\]\s*=\s*function", 2
            if ($afterFunction.Count -gt 1) {
                $functionBody = $afterFunction[1]

                # Check for React.createElement or JSX
                $hasReactCode = ($functionBody -match 'React\.createElement' -or
                                $functionBody -match 'React\.useEffect' -or
                                $functionBody -match 'React\.useRef')

                # Check for string return (bad pattern)
                $hasStringReturn = ($functionBody -match 'return\s*[`''""][^`''""]*<[^>]+>')

                if ($hasStringReturn -and -not $hasReactCode) {
                    $fileIssues += "❌ Returns HTML string instead of React component"
                } elseif ($hasReactCode) {
                    # Good - uses React
                } else {
                    $fileIssues += "⚠️  Registration function found but unclear if React component"
                }
            }
        } else {
            $fileIssues += "⚠️  window.cardComponents registration is not a function"
        }
    }

    if ($fileIssues.Count -eq 0) {
        $compliant += [PSCustomObject]@{
            File = $relativePath
            ComponentName = $componentName
            Status = 'OK'
        }
        Write-Host "  ✓ OK" -ForegroundColor Green
    } else {
        $issues += [PSCustomObject]@{
            File = $relativePath
            ComponentName = $componentName
            Issues = $fileIssues
            FullPath = $file.FullName
        }
        Write-Host "  Issues found:" -ForegroundColor Yellow
        foreach ($issue in $fileIssues) {
            Write-Host "    $issue" -ForegroundColor Yellow
        }
    }

    Write-Host ""
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Audit Summary" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Host "Total components: $($componentFiles.Count)" -ForegroundColor White
Write-Host "Compliant: $($compliant.Count) ✓" -ForegroundColor Green
Write-Host "Issues found: $($issues.Count) ⚠️" -ForegroundColor $(if ($issues.Count -gt 0) { 'Yellow' } else { 'Green' })

if ($issues.Count -gt 0) {
    Write-Host "`nComponents with issues:" -ForegroundColor Yellow
    Write-Host "------------------------" -ForegroundColor Yellow

    foreach ($item in $issues) {
        Write-Host "`n$($item.File):" -ForegroundColor Cyan
        foreach ($issue in $item.Issues) {
            Write-Host "  $issue" -ForegroundColor Yellow
        }
    }

    # Export to file
    $reportPath = Join-Path $ProjectRoot "component_audit_report.txt"
    $report = @"
Component Registration Audit Report
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Total components: $($componentFiles.Count)
Compliant: $($compliant.Count)
Issues found: $($issues.Count)

========================================
Components with Issues
========================================

$($issues | ForEach-Object {
    "`n$($_.File):"
    $_.Issues | ForEach-Object { "  $_" }
} | Out-String)

========================================
Compliant Components
========================================

$($compliant | ForEach-Object { $_.File } | Out-String)
"@

    $report | Out-File -FilePath $reportPath -Encoding utf8
    Write-Host "`nFull report saved to: $reportPath" -ForegroundColor Cyan
}

if ($Fix) {
    Write-Host "`n⚠️  Fix mode not yet implemented" -ForegroundColor Yellow
    Write-Host "Manual fixes required based on the template in:" -ForegroundColor Yellow
    Write-Host "  COMPONENT_TEMPLATE_GUIDE.md" -ForegroundColor White
}

Write-Host ""
