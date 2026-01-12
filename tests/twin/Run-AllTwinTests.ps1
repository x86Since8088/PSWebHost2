<#
.SYNOPSIS
    Runs all tests in the twin test structure

.DESCRIPTION
    This script runs all Pester tests in the tests/twin directory, which mirrors
    the main project structure. Tests are organized by component type (routes,
    system, modules, public).

.PARAMETER Path
    Specific path to test. Defaults to all twin tests.

.PARAMETER Tag
    Filter tests by tag

.PARAMETER ExcludeTag
    Exclude tests by tag

.PARAMETER Output
    Output level: None, Minimal, Normal, Detailed, Diagnostic
    Default: Detailed

.PARAMETER CodeCoverage
    Enable code coverage analysis

.EXAMPLE
    .\Run-AllTwinTests.ps1
    Runs all twin tests with detailed output

.EXAMPLE
    .\Run-AllTwinTests.ps1 -Path routes
    Runs only route tests

.EXAMPLE
    .\Run-AllTwinTests.ps1 -CodeCoverage
    Runs all tests with code coverage analysis

.EXAMPLE
    .\Run-AllTwinTests.ps1 -Tag "Authentication" -Output Normal
    Runs only tests tagged with "Authentication"
#>

param(
    [Parameter()]
    [string]$Path,

    [Parameter()]
    [string[]]$Tag,

    [Parameter()]
    [string[]]$ExcludeTag,

    [Parameter()]
    [ValidateSet('None', 'Minimal', 'Normal', 'Detailed', 'Diagnostic')]
    [string]$Output,

    [Parameter()]
    [switch]$CodeCoverage
)

# Initialize test environment
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

# Set testing mode flags - only initialize if null
if ($null -eq $Global:PSWebHostTesting) {
    $Global:PSWebHostTesting = $true
}
if ($null -eq $Global:PSWebHostTestingSession) {
    $Global:PSWebHostTestingSession = $null
}

# Set default path to script root if not provided
if (-not $Path) {
    $Path = $PSScriptRoot
}

# Set default output level if not provided
if (-not $Output) {
    $Output = 'Detailed'
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Twin Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Capture initial pwsh processes
Write-Host "Capturing initial PowerShell processes..." -ForegroundColor Yellow
$initialProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object Id, StartTime, @{Name='CommandLine';Expression={$_.CommandLine}}
$initialProcessIds = $initialProcesses.Id
Write-Host "Found $($initialProcessIds.Count) existing pwsh processes: $($initialProcessIds -join ', ')`n" -ForegroundColor Gray

# Initialize process tracking hashtable
$script:processTracking = @{
    TestProcessMap = @{}  # Maps test names to PIDs they created
    AllNewProcesses = @() # All PIDs created during test run
}

# Ensure Pester module is available
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "ERROR: Pester module not found. Installing..." -ForegroundColor Red
    Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
}

# Import Pester
Import-Module Pester -MinimumVersion 5.0 -ErrorAction Stop

# Create Pester configuration
$config = New-PesterConfiguration

# Set paths
$config.Run.Path = $Path
$config.Run.PassThru = $true

# Set output
$config.Output.Verbosity = $Output

# Set tags if provided
if ($Tag) {
    $config.Filter.Tag = $Tag
}
if ($ExcludeTag) {
    $config.Filter.ExcludeTag = $ExcludeTag
}

# Configure code coverage if requested
if ($CodeCoverage) {
    Write-Host "Code coverage enabled`n" -ForegroundColor Yellow
    $config.CodeCoverage.Enabled = $true

    # Set paths to analyze for coverage
    $ProjectRoot = $psscriptroot -replace '[/\\]tests[\\/].*'
    $config.CodeCoverage.Path = @(
        (Join-Path $ProjectRoot 'routes'),
        (Join-Path $ProjectRoot 'system'),
        (Join-Path $ProjectRoot 'modules')
    )

    $config.CodeCoverage.OutputPath = Join-Path $PSScriptRoot 'coverage.xml'
    $config.CodeCoverage.OutputFormat = 'JaCoCo'
}

# Add process tracking plugin
$processTrackingPlugin = @{
    Start = {
        # Track processes at start of each test
        param($Context)
        if ($Context.Test) {
            $Context.Test.PluginData.PreTestProcessIds = @(Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
        }
    }
    End = {
        # Check for new processes after each test
        param($Context)
        if ($Context.Test) {
            $postTestProcessIds = @(Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
            $preTestProcessIds = $Context.Test.PluginData.PreTestProcessIds

            $newProcesses = $postTestProcessIds | Where-Object { $_ -notin $preTestProcessIds -and $_ -notin $script:initialProcessIds }

            if ($newProcesses.Count -gt 0) {
                $testPath = $Context.Test.ExpandedPath
                $script:processTracking.TestProcessMap[$testPath] = $newProcesses
                $script:processTracking.AllNewProcesses += $newProcesses
            }
        }
    }
}

# Register the plugin
$config.TestExtension.Add($processTrackingPlugin)

# Run tests
$result = Invoke-Pester -Configuration $config

# Capture final pwsh processes
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Process Cleanup Analysis" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$finalProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object Id, StartTime
$finalProcessIds = $finalProcesses.Id
$newProcessIds = $finalProcessIds | Where-Object { $_ -notin $initialProcessIds }

Write-Host "Initial pwsh processes: $($initialProcessIds.Count)" -ForegroundColor Gray
Write-Host "Final pwsh processes:   $($finalProcessIds.Count)" -ForegroundColor Gray
Write-Host "New processes created:  $($newProcessIds.Count)" -ForegroundColor $(if ($newProcessIds.Count -gt 0) { 'Yellow' } else { 'Green' })

if ($newProcessIds.Count -gt 0) {
    Write-Host "`nNew process PIDs: $($newProcessIds -join ', ')" -ForegroundColor Yellow

    # Display which tests created processes
    if ($script:processTracking.TestProcessMap.Count -gt 0) {
        Write-Host "`nTests that created processes:" -ForegroundColor Yellow
        foreach ($test in $script:processTracking.TestProcessMap.Keys | Sort-Object) {
            $pids = $script:processTracking.TestProcessMap[$test]
            Write-Host "  [$($pids -join ', ')] $test" -ForegroundColor Cyan
        }
    }

    # Attempt cleanup
    Write-Host "`nAttempting to stop orphaned processes..." -ForegroundColor Yellow
    $cleaned = 0
    $failed = 0

    foreach ($pid in $newProcessIds) {
        try {
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host "  Stopping PID $pid..." -ForegroundColor Gray -NoNewline
                Stop-Process -Id $pid -Force -ErrorAction Stop
                $cleaned++
                Write-Host " OK" -ForegroundColor Green
            }
        } catch {
            $failed++
            Write-Host " FAILED: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Write-Host "`nCleanup summary: $cleaned stopped, $failed failed`n" -ForegroundColor $(if ($failed -gt 0) { 'Yellow' } else { 'Green' })

    # Write process tracking report
    $reportPath = Join-Path $PSScriptRoot 'process-tracking-report.txt'
    $reportContent = @"
========================================
Process Tracking Report
========================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Initial Processes: $($initialProcessIds.Count)
Final Processes:   $($finalProcessIds.Count)
New Processes:     $($newProcessIds.Count)
Cleaned:           $cleaned
Failed to Clean:   $failed

Initial Process IDs:
$($initialProcessIds -join ', ')

New Process IDs:
$($newProcessIds -join ', ')

========================================
Tests that Created Processes
========================================

"@

    if ($script:processTracking.TestProcessMap.Count -gt 0) {
        foreach ($test in $script:processTracking.TestProcessMap.Keys | Sort-Object) {
            $pids = $script:processTracking.TestProcessMap[$test]
            $reportContent += "[$($pids -join ', ')] $test`r`n"
        }
    } else {
        $reportContent += "No tests tracked as creating processes`r`n"
    }

    $reportContent += @"

========================================
Areas for Improvement
========================================

"@

    # Group tests by file to identify problematic test files
    $testsByFile = @{}
    foreach ($test in $script:processTracking.TestProcessMap.Keys) {
        # Extract file name from test path (usually first component)
        if ($test -match '^([^.]+)') {
            $fileName = $matches[1]
            if (-not $testsByFile.ContainsKey($fileName)) {
                $testsByFile[$fileName] = @()
            }
            $testsByFile[$fileName] += $test
        }
    }

    if ($testsByFile.Count -gt 0) {
        $reportContent += "Test files with process leaks (sorted by count):`r`n`r`n"
        foreach ($file in ($testsByFile.Keys | Sort-Object { $testsByFile[$_].Count } -Descending)) {
            $count = $testsByFile[$file].Count
            $reportContent += "  $file`: $count test(s) leaked processes`r`n"
        }
    } else {
        $reportContent += "No process leaks detected - all tests cleaned up properly!`r`n"
    }

    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Process tracking report saved to: $reportPath" -ForegroundColor Gray

} else {
    Write-Host "`nNo orphaned processes detected - excellent!`n" -ForegroundColor Green

    # Write clean report
    $reportPath = Join-Path $PSScriptRoot 'process-tracking-report.txt'
    $reportContent = @"
========================================
Process Tracking Report
========================================
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Initial Processes: $($initialProcessIds.Count)
Final Processes:   $($finalProcessIds.Count)
New Processes:     0

Result: No orphaned processes detected - all tests cleaned up properly!
"@
    $reportContent | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Host "Process tracking report saved to: $reportPath" -ForegroundColor Gray
}

# Display test summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total:  " -NoNewline
Write-Host $result.TotalCount -ForegroundColor White
Write-Host "Passed: " -NoNewline
Write-Host $result.PassedCount -ForegroundColor Green
Write-Host "Failed: " -NoNewline
Write-Host $result.FailedCount -ForegroundColor $(if ($result.FailedCount -gt 0) { 'Red' } else { 'Green' })
Write-Host "Skipped:" -NoNewline
Write-Host $result.SkippedCount -ForegroundColor Yellow

if ($result.Duration) {
    Write-Host "Duration: $($result.Duration.TotalSeconds) seconds`n" -ForegroundColor Gray
}

# Code coverage summary
if ($CodeCoverage -and $result.CodeCoverage) {
    Write-Host "`nCode Coverage:" -ForegroundColor Cyan
    $coverage = $result.CodeCoverage
    $coveragePercent = if ($coverage.CommandsAnalyzedCount -gt 0) {
        [math]::Round(($coverage.CommandsExecutedCount / $coverage.CommandsAnalyzedCount) * 100, 2)
    } else { 0 }

    Write-Host "  Analyzed: $($coverage.CommandsAnalyzedCount) commands"
    Write-Host "  Executed: $($coverage.CommandsExecutedCount) commands"
    Write-Host "  Coverage: " -NoNewline
    $coverageColor = if ($coveragePercent -ge 80) { 'Green' } elseif ($coveragePercent -ge 60) { 'Yellow' } else { 'Red' }
    Write-Host "$coveragePercent%" -ForegroundColor $coverageColor
    Write-Host "  Report saved to: $($config.CodeCoverage.OutputPath)`n"
}

# Exit with appropriate code
if ($result.FailedCount -gt 0) {
    Write-Host "Tests FAILED" -ForegroundColor Red
    exit 1
} else {
    Write-Host "All tests PASSED" -ForegroundColor Green
    exit 0
}
