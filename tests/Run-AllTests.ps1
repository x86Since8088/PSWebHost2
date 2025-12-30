# Run-AllTests.ps1
# Master test runner for PsWebHost
# Executes all test suites and generates comprehensive report

[CmdletBinding()]
param(
    [string]$TestUsername = "test@localhost",
    [string]$TestPassword = "TestPassword123!",
    [int]$Port = 0,
    [switch]$SkipSlow,
    [string]$ReportPath = ".\test-results"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Warning "This test suite requires PowerShell 6+ (PowerShell Core/7+)"
    Write-Warning "Current version: $($PSVersionTable.PSVersion)"
    Write-Warning "Download: https://github.com/PowerShell/PowerShell/releases"
    Write-Host "`nNote: For Windows PowerShell 5.1, run 'pwsh' to use PowerShell 7+"
    return
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                                                              ║
║         PsWebHost Comprehensive Test Suite Runner           ║
║                                                              ║
║  Testing Categories:                                         ║
║    1. Authentication Flow                                    ║
║    2. All API Endpoints (46 endpoints)                       ║
║    3. Security Features (Brute Force, Injection, etc.)       ║
║    4. RBAC Configuration Analysis                            ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$startTime = Get-Date
$testsDir = $PSScriptRoot
$results = @{}

# Ensure report directory exists
if (-not (Test-Path $ReportPath)) {
    New-Item -Path $ReportPath -ItemType Directory -Force | Out-Null
}

$reportFile = Join-Path $ReportPath "test-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"

function Run-TestSuite {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [switch]$Skip
    )

    if ($Skip) {
        Write-Host "`n[SKIP] $Name" -ForegroundColor Gray
        $script:results[$Name] = @{
            Status = "Skipped"
            Duration = 0
            Output = ""
        }
        return
    }

    Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  Running: $($Name.PadRight(55))║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

    $suiteStart = Get-Date

    try {
        # Build argument list
        $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ScriptPath)
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            if ($value -is [switch]) {
                if ($value) {
                    $argList += "-$key"
                }
            } else {
                $argList += "-$key"
                $argList += $value
            }
        }

        # Execute test
        $output = & powershell $argList 2>&1 | Out-String

        $suiteEnd = Get-Date
        $duration = ($suiteEnd - $suiteStart).TotalSeconds

        # Parse results
        $passed = if ($output -match 'Passed:\s*(\d+)') { [int]$matches[1] } else { 0 }
        $failed = if ($output -match 'Failed:\s*(\d+)') { [int]$matches[1] } else { 0 }
        $skipped = if ($output -match 'Skipped:\s*(\d+)') { [int]$matches[1] } else { 0 }

        $status = if ($failed -eq 0) { "Success" } else { "Failed" }

        Write-Host "`nTest Suite Completed:" -ForegroundColor $(if ($failed -eq 0) { 'Green' } else { 'Yellow' })
        Write-Host "  Duration: $([math]::Round($duration, 2))s" -ForegroundColor Gray
        Write-Host "  Passed: $passed | Failed: $failed | Skipped: $skipped" -ForegroundColor Gray

        $script:results[$Name] = @{
            Status = $status
            Duration = $duration
            Passed = $passed
            Failed = $failed
            Skipped = $skipped
            Output = $output
        }

    } catch {
        $suiteEnd = Get-Date
        $duration = ($suiteEnd - $suiteStart).TotalSeconds

        Write-Host "`n[ERROR] Test suite failed to execute:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red

        $script:results[$Name] = @{
            Status = "Error"
            Duration = $duration
            Error = $_.Exception.Message
            Output = ""
        }
    }
}

# ============================================
# Execute Test Suites
# ============================================

# Test 1: Setup Test User
if (Test-Path (Join-Path $testsDir "Setup-TestUser.ps1")) {
    Write-Host "`n[SETUP] Creating test user..." -ForegroundColor Cyan
    try {
        & (Join-Path $testsDir "Setup-TestUser.ps1") -Email $TestUsername -Password $TestPassword -ErrorAction Continue
    } catch {
        Write-Host "  Note: Test user may already exist or setup failed" -ForegroundColor Yellow
    }
}

# Test 2: Authentication Flow
Run-TestSuite -Name "Authentication Flow" `
    -ScriptPath (Join-Path $testsDir "Test-AuthFlow.ps1") `
    -Parameters @{
        TestUsername = $TestUsername
        TestPassword = $TestPassword
        Port = $Port
    }

# Test 3: All Endpoints
Run-TestSuite -Name "All API Endpoints" `
    -ScriptPath (Join-Path $testsDir "Test-AllEndpoints.ps1") `
    -Parameters @{
        TestUsername = $TestUsername
        TestPassword = $TestPassword
        Port = $Port
    } `
    -Skip:$SkipSlow

# Test 4: Security Features
Run-TestSuite -Name "Security Features" `
    -ScriptPath (Join-Path $testsDir "Test-Security.ps1") `
    -Parameters @{
        Port = $Port
    }

# Test 5: RBAC Configuration
Run-TestSuite -Name "RBAC Configuration" `
    -ScriptPath (Join-Path $testsDir "Test-RBAC.ps1") `
    -Parameters @{
        Port = $Port
    }

# ============================================
# Generate Report
# ============================================

$endTime = Get-Date
$totalDuration = ($endTime - $startTime).TotalSeconds

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Test Results Summary                      ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0
$successfulSuites = 0
$failedSuites = 0

foreach ($suite in $results.Keys | Sort-Object) {
    $result = $results[$suite]

    $statusColor = switch ($result.Status) {
        "Success" { "Green"; $successfulSuites++ }
        "Failed" { "Red"; $failedSuites++ }
        "Skipped" { "Gray" }
        "Error" { "Red"; $failedSuites++ }
        default { "White" }
    }

    $statusIcon = switch ($result.Status) {
        "Success" { "[PASS]" }
        "Failed" { "[FAIL]" }
        "Skipped" { "[SKIP]" }
        "Error" { "[ERROR]" }
        default { "[?]" }
    }

    Write-Host "`n$statusIcon $suite" -ForegroundColor $statusColor
    Write-Host "  Status: $($result.Status)" -ForegroundColor $statusColor
    Write-Host "  Duration: $([math]::Round($result.Duration, 2))s" -ForegroundColor Gray

    if ($result.ContainsKey('Passed')) {
        Write-Host "  Passed: $($result.Passed) | Failed: $($result.Failed) | Skipped: $($result.Skipped)" -ForegroundColor Gray
        $totalPassed += $result.Passed
        $totalFailed += $result.Failed
        $totalSkipped += $result.Skipped
    }

    if ($result.ContainsKey('Error')) {
        Write-Host "  Error: $($result.Error)" -ForegroundColor Red
    }
}

# Generate Markdown Report
$report = @"
# PsWebHost Test Report

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Total Duration:** $([math]::Round($totalDuration, 2))s
**Project:** $ProjectRoot

---

## Summary

| Metric | Value |
|--------|-------|
| Test Suites Run | $($results.Count) |
| Successful Suites | $successfulSuites |
| Failed Suites | $failedSuites |
| Total Tests Passed | $totalPassed |
| Total Tests Failed | $totalFailed |
| Total Tests Skipped | $totalSkipped |
| Success Rate | $([math]::Round(($totalPassed / ($totalPassed + $totalFailed)) * 100, 1))% |

---

## Test Suite Results

"@

foreach ($suite in $results.Keys | Sort-Object) {
    $result = $results[$suite]
    $statusEmoji = switch ($result.Status) {
        "Success" { ":white_check_mark:" }
        "Failed" { ":x:" }
        "Skipped" { ":heavy_minus_sign:" }
        "Error" { ":warning:" }
        default { ":question:" }
    }

    $report += @"

### $statusEmoji $suite

- **Status:** $($result.Status)
- **Duration:** $([math]::Round($result.Duration, 2))s

"@

    if ($result.ContainsKey('Passed')) {
        $report += @"
- **Passed:** $($result.Passed)
- **Failed:** $($result.Failed)
- **Skipped:** $($result.Skipped)

"@
    }

    if ($result.ContainsKey('Error')) {
        $report += @"
- **Error:** ``$($result.Error)``

"@
    }
}

$report += @"

---

## System Information

- **OS:** $([System.Environment]::OSVersion.VersionString)
- **PowerShell:** $($PSVersionTable.PSVersion)
- **Working Directory:** $ProjectRoot
- **Test Port:** $Port

---

## Test Details

"@

foreach ($suite in $results.Keys | Sort-Object) {
    $result = $results[$suite]

    $report += @"

<details>
<summary><strong>$suite - Full Output</strong></summary>

``````
$($result.Output)
``````

</details>

"@
}

# Save report
$report | Out-File -FilePath $reportFile -Encoding UTF8

Write-Host "`n╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Overall Summary                           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan

Write-Host "`nTest Suites:     $successfulSuites passed, $failedSuites failed, $($results.Count) total" -ForegroundColor White
Write-Host "Individual Tests: $totalPassed passed, $totalFailed failed, $totalSkipped skipped" -ForegroundColor White
Write-Host "Duration:        $([math]::Round($totalDuration, 2))s" -ForegroundColor White
Write-Host "Report:          $reportFile" -ForegroundColor Cyan

if ($failedSuites -eq 0 -and $totalFailed -eq 0) {
    Write-Host "`n✓ All tests passed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ Some tests failed - review report for details" -ForegroundColor Red
    exit 1
}
