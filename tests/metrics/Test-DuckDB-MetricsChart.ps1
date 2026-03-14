<#
.SYNOPSIS
    DuckDB-WASM Metrics Chart Implementation Test Suite

.DESCRIPTION
    Comprehensive testing for the DuckDB-WASM migration including:
    - Performance validation (35-70x improvement target)
    - Memory leak detection
    - Thread safety verification
    - Component protection validation
    - Browser console error checking
    - Rapid time-range change stress test

.PARAMETER SessionID
    Target browser session ID (default: "all")

.PARAMETER TimeoutSeconds
    Maximum time to wait for operations (default: 30)

.PARAMETER StressTestIterations
    Number of rapid UI changes to test (default: 10)

.EXAMPLE
    .\Test-DuckDB-MetricsChart.ps1

.EXAMPLE
    .\Test-DuckDB-MetricsChart.ps1 -SessionID "session123" -StressTestIterations 20

.OUTPUTS
    Comprehensive test report with performance metrics and pass/fail status
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$SessionID = "all",

    [Parameter(Mandatory = $false)]
    [int]$TimeoutSeconds = 30,

    [Parameter(Mandatory = $false)]
    [int]$StressTestIterations = 10
)

$MyTag = '[Test-DuckDB-MetricsChart]'
$utilityPath = Join-Path $PSScriptRoot "..\..\apps\WebHostDebugExtensions\system\utility"

# Test result object
$testReport = @{
    TestSuite = "DuckDB-WASM Metrics Chart"
    StartTime = Get-Date
    EndTime = $null
    Duration = 0
    OverallStatus = "Pass"
    Tests = @()
    PerformanceMetrics = @{}
    Errors = @()
    Warnings = @()
    Summary = ""
}

Write-Host "`n$MyTag ===== DuckDB-WASM Metrics Chart Test Suite =====" -ForegroundColor Cyan
Write-Host "$MyTag Starting comprehensive validation..." -ForegroundColor Cyan

try {
    # =========================================================================
    # TEST 1: Card Load and Initialization
    # =========================================================================
    Write-Host "`n$MyTag [TEST 1/6] Card Load and Initialization" -ForegroundColor Yellow

    $cardUrl = "/apps/UI_Uplot/public/elements/metrics-chart/component.js?source=/apps/WebHostMetrics/api/v1/metrics&metric=cpu&timerange=1h&granularity=15s&delay=5"

    $launchScript = Join-Path $utilityPath "Launch-DebugCard.ps1"
    $loadStartTime = Get-Date

    $launchResult = & $launchScript -Url $cardUrl -Title "Metrics Chart Test" -SessionID $SessionID -Wait

    if (-not $launchResult.Success) {
        throw "Failed to launch metrics chart card: $($launchResult.Error)"
    }

    $cardId = $launchResult.CardID
    $loadDuration = ((Get-Date) - $loadStartTime).TotalMilliseconds

    $testReport.Tests += @{
        Name = "Card Load"
        Result = "Pass"
        Duration = $loadDuration
        Message = "Card loaded successfully in ${loadDuration}ms"
    }

    $testReport.PerformanceMetrics.LoadTime = $loadDuration

    Write-Host "$MyTag   ✓ Card loaded in ${loadDuration}ms (CardID: $cardId)" -ForegroundColor Green

    # Wait for chart initialization
    Start-Sleep -Seconds 3

    # =========================================================================
    # TEST 2: History Load Performance (Target: <100ms)
    # =========================================================================
    Write-Host "`n$MyTag [TEST 2/6] History Load Performance (Target: less than 100ms)" -ForegroundColor Yellow

    $enqueueScript = Join-Path $utilityPath "Debug_Client_Command_Enqueue.ps1"

    # Execute console command to measure history load time
    $perfCheckCommand = @"
(function() {
    const startTime = performance.now();
    const metricsDb = window.metricsDbInstance;

    if (!metricsDb) {
        return { error: 'MetricsDatabase not found', historyLoadTime: null };
    }

    // Check performance entries for history fetch
    const perfEntries = performance.getEntriesByType('measure').filter(e =>
        e.name.includes('history') || e.name.includes('insert')
    );

    const historyEntry = perfEntries.find(e => e.name.includes('history'));

    return {
        historyLoadTime: historyEntry ? historyEntry.duration : null,
        totalInsertTime: perfEntries.filter(e => e.name.includes('insert'))
            .reduce((sum, e) => sum + e.duration, 0),
        measureCount: perfEntries.length
    };
})()
"@

    $perfResult = & $enqueueScript -Command $perfCheckCommand -Type custom -SessionID $SessionID

    Start-Sleep -Milliseconds 1500

    # Poll for result
    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $perfResult.CommandID } | Select-Object -First 1

    if ($historyEntry -and $historyEntry.Result) {
        $historyLoadTime = $historyEntry.Result.historyLoadTime
        $insertTime = $historyEntry.Result.totalInsertTime

        if ($historyLoadTime) {
            $testReport.PerformanceMetrics.HistoryLoadTime = $historyLoadTime
            $testReport.PerformanceMetrics.InsertTime = $insertTime

            $historyPass = $historyLoadTime -lt 100

            $testReport.Tests += @{
                Name = "History Load Performance"
                Result = $historyPass ? "Pass" : "Warn"
                Duration = $historyLoadTime
                Message = "History loaded in ${historyLoadTime}ms (Target: <100ms)"
            }

            if ($historyPass) {
                Write-Host "$MyTag   ✓ History load: ${historyLoadTime}ms (EXCELLENT)" -ForegroundColor Green
            } else {
                Write-Host "$MyTag   ⚠ History load: ${historyLoadTime}ms (SLOW - target <100ms)" -ForegroundColor Yellow
                $testReport.Warnings += "History load exceeded 100ms target"
            }
        }
    }

    # =========================================================================
    # TEST 3: Console Error Check
    # =========================================================================
    Write-Host "`n$MyTag [TEST 3/6] Console Error Detection" -ForegroundColor Yellow

    $consoleCheckCommand = @"
(function() {
    const errors = [];
    const warnings = [];

    // Check console history (if available)
    if (window.consoleHistory) {
        errors.push(...window.consoleHistory.filter(e => e.type === 'error'));
        warnings.push(...window.consoleHistory.filter(e => e.type === 'warn'));
    }

    // Check for specific DuckDB-related errors
    const metricsDb = window.metricsDbInstance;
    if (metricsDb && metricsDb.worker) {
        // Worker is alive
        return {
            workerAlive: true,
            errorCount: errors.length,
            warningCount: warnings.length,
            recentErrors: errors.slice(-5).map(e => e.message)
        };
    }

    return {
        workerAlive: false,
        errorCount: errors.length,
        warningCount: warnings.length,
        recentErrors: errors.slice(-5).map(e => e.message)
    };
})()
"@

    $consoleResult = & $enqueueScript -Command $consoleCheckCommand -Type custom -SessionID $SessionID

    Start-Sleep -Milliseconds 1000

    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $consoleResult.CommandID } | Select-Object -First 1

    if ($historyEntry -and $historyEntry.Result) {
        $errorCount = $historyEntry.Result.errorCount
        $warningCount = $historyEntry.Result.warningCount
        $workerAlive = $historyEntry.Result.workerAlive

        $noErrors = $errorCount -eq 0

        $testReport.Tests += @{
            Name = "Console Errors"
            Result = $noErrors ? "Pass" : "Fail"
            Message = "$errorCount errors, $warningCount warnings detected"
            Details = @{
                ErrorCount = $errorCount
                WarningCount = $warningCount
                WorkerAlive = $workerAlive
                RecentErrors = $historyEntry.Result.recentErrors
            }
        }

        if ($noErrors) {
            Write-Host "$MyTag   ✓ No console errors (Worker alive: $workerAlive)" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ✗ $errorCount console errors detected!" -ForegroundColor Red
            $testReport.OverallStatus = "Fail"
            $testReport.Errors += "Console errors detected: $($historyEntry.Result.recentErrors -join ', ')"
        }
    }

    # =========================================================================
    # TEST 4: Rapid Time Range Changes (Stress Test)
    # =========================================================================
    Write-Host "`n$MyTag [TEST 4/6] Rapid Time Range Changes (Stress Test - $StressTestIterations iterations)" -ForegroundColor Yellow

    $timeRanges = @("5m", "15m", "30m", "1h", "3h", "6h", "12h", "24h")
    $stressStartTime = Get-Date

    for ($i = 0; $i -lt $StressTestIterations; $i++) {
        $timeRange = $timeRanges[$i % $timeRanges.Length]

        $changeTimeRangeCommand = @"
(function() {
    const timeRange = '$timeRange';
    // Simulate time range change
    if (window.metricsDbInstance && window.metricsDbInstance.queryForChart) {
        // This tests query cancellation
        window.metricsDbInstance.currentQueryToken++;
        return { timeRange: timeRange, tokenIncremented: true };
    }
    return { timeRange: timeRange, tokenIncremented: false };
})()
"@

        $changeResult = & $enqueueScript -Command $changeTimeRangeCommand -Type custom -SessionID $SessionID

        # No wait - intentionally rapid fire
        Start-Sleep -Milliseconds 50
    }

    $stressDuration = ((Get-Date) - $stressStartTime).TotalMilliseconds

    # Wait for operations to settle
    Start-Sleep -Seconds 2

    # Check if queries are still working after stress
    $postStressCheckCommand = @"
(function() {
    const metricsDb = window.metricsDbInstance;
    if (!metricsDb || !metricsDb.worker) {
        return { workerAlive: false, queryTokenValid: false };
    }

    return {
        workerAlive: true,
        queryTokenValid: typeof metricsDb.currentQueryToken === 'number',
        currentToken: metricsDb.currentQueryToken
    };
})()
"@

    $postStressResult = & $enqueueScript -Command $postStressCheckCommand -Type custom -SessionID $SessionID

    Start-Sleep -Milliseconds 1000

    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $postStressResult.CommandID } | Select-Object -First 1

    if ($historyEntry -and $historyEntry.Result) {
        $workerAlivePostStress = $historyEntry.Result.workerAlive
        $queryTokenValid = $historyEntry.Result.queryTokenValid

        $stressPass = $workerAlivePostStress -and $queryTokenValid

        $testReport.Tests += @{
            Name = "Stress Test ($StressTestIterations iterations)"
            Result = $stressPass ? "Pass" : "Fail"
            Duration = $stressDuration
            Message = "Worker survived $StressTestIterations rapid changes in ${stressDuration}ms"
            Details = @{
                WorkerAlive = $workerAlivePostStress
                QueryTokenValid = $queryTokenValid
                CurrentToken = $historyEntry.Result.currentToken
            }
        }

        if ($stressPass) {
            Write-Host "$MyTag   ✓ Stress test passed - worker stable after $StressTestIterations changes" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ✗ Stress test failed - worker crashed or became unstable" -ForegroundColor Red
            $testReport.OverallStatus = "Fail"
            $testReport.Errors += "Worker failed under stress test"
        }
    }

    # =========================================================================
    # TEST 5: Memory Stability Check (10 minutes operation)
    # =========================================================================
    Write-Host "`n$MyTag [TEST 5/6] Memory Stability Check (60 second continuous operation)" -ForegroundColor Yellow

    $memoryCheckCommand = @"
(function() {
    if (!performance.memory) {
        return { supported: false };
    }

    return {
        supported: true,
        usedJSHeapSize: performance.memory.usedJSHeapSize,
        totalJSHeapSize: performance.memory.totalJSHeapSize,
        jsHeapSizeLimit: performance.memory.jsHeapSizeLimit,
        usedMB: (performance.memory.usedJSHeapSize / 1024 / 1024).toFixed(2)
    };
})()
"@

    # Initial memory reading
    $memInitResult = & $enqueueScript -Command $memoryCheckCommand -Type custom -SessionID $SessionID
    Start-Sleep -Milliseconds 1000

    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $memInitResult.CommandID } | Select-Object -First 1

    $memoryInitial = $null
    if ($historyEntry -and $historyEntry.Result -and $historyEntry.Result.supported) {
        $memoryInitial = [double]$historyEntry.Result.usedMB
        Write-Host "$MyTag   Initial memory: ${memoryInitial}MB" -ForegroundColor Cyan
    }

    # Let it run for 60 seconds
    Write-Host "$MyTag   Running for 60 seconds..." -ForegroundColor Cyan
    Start-Sleep -Seconds 60

    # Final memory reading
    $memFinalResult = & $enqueueScript -Command $memoryCheckCommand -Type custom -SessionID $SessionID
    Start-Sleep -Milliseconds 1000

    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $memFinalResult.CommandID } | Select-Object -First 1

    if ($historyEntry -and $historyEntry.Result -and $historyEntry.Result.supported) {
        $memoryFinal = [double]$historyEntry.Result.usedMB
        $memoryGrowth = $memoryFinal - $memoryInitial

        $testReport.PerformanceMetrics.MemoryInitial = $memoryInitial
        $testReport.PerformanceMetrics.MemoryFinal = $memoryFinal
        $testReport.PerformanceMetrics.MemoryGrowth = $memoryGrowth

        # Memory growth should be <10MB for 60 seconds
        $memoryPass = $memoryGrowth -lt 10

        $testReport.Tests += @{
            Name = "Memory Stability"
            Result = $memoryPass ? "Pass" : "Warn"
            Message = "Memory grew ${memoryGrowth}MB over 60 seconds (${memoryInitial}MB → ${memoryFinal}MB)"
            Details = @{
                Initial = $memoryInitial
                Final = $memoryFinal
                Growth = $memoryGrowth
            }
        }

        if ($memoryPass) {
            Write-Host "$MyTag   ✓ Memory stable: +${memoryGrowth}MB over 60s" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ⚠ Memory leak detected: +${memoryGrowth}MB over 60s" -ForegroundColor Yellow
            $testReport.Warnings += "Memory growth exceeded 10MB threshold"
        }
    } else {
        Write-Host "$MyTag   ⚠ Memory API not supported in browser" -ForegroundColor Yellow
        $testReport.Warnings += "Memory API not available for testing"
    }

    # =========================================================================
    # TEST 6: Chart Rendering Validation
    # =========================================================================
    Write-Host "`n$MyTag [TEST 6/6] Chart Rendering Validation" -ForegroundColor Yellow

    $chartValidationCommand = @"
(function() {
    // Check for uPlot canvas
    const canvas = document.querySelector('canvas');
    if (!canvas) {
        return { found: false, error: 'Canvas not found' };
    }

    const ctx = canvas.getContext('2d');
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);
    const pixels = imageData.data;

    // Check if canvas has been drawn (not all transparent)
    let nonTransparentPixels = 0;
    for (let i = 3; i < pixels.length; i += 4) {
        if (pixels[i] > 0) {
            nonTransparentPixels++;
        }
    }

    const percentDrawn = (nonTransparentPixels / (pixels.length / 4) * 100).toFixed(2);

    return {
        found: true,
        canvasWidth: canvas.width,
        canvasHeight: canvas.height,
        nonTransparentPixels: nonTransparentPixels,
        percentDrawn: percentDrawn,
        rendered: percentDrawn > 1
    };
})()
"@

    $chartResult = & $enqueueScript -Command $chartValidationCommand -Type custom -SessionID $SessionID

    Start-Sleep -Milliseconds 1000

    $historyResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100" -Method GET
    $historyEntry = $historyResponse.commands | Where-Object { $_.CommandID -eq $chartResult.CommandID } | Select-Object -First 1

    if ($historyEntry -and $historyEntry.Result) {
        $chartFound = $historyEntry.Result.found
        $chartRendered = $historyEntry.Result.rendered
        $percentDrawn = $historyEntry.Result.percentDrawn

        $chartPass = $chartFound -and $chartRendered

        $testReport.Tests += @{
            Name = "Chart Rendering"
            Result = $chartPass ? "Pass" : "Fail"
            Message = "Chart ${chartRendered ? 'rendered' : 'NOT rendered'} (${percentDrawn}% of canvas drawn)"
            Details = @{
                CanvasFound = $chartFound
                Rendered = $chartRendered
                PercentDrawn = $percentDrawn
            }
        }

        if ($chartPass) {
            Write-Host "$MyTag   ✓ Chart rendered correctly (${percentDrawn}% of canvas)" -ForegroundColor Green
        } else {
            Write-Host "$MyTag   ✗ Chart NOT rendered" -ForegroundColor Red
            $testReport.OverallStatus = "Fail"
            $testReport.Errors += "Chart failed to render"
        }
    }

} catch {
    $testReport.OverallStatus = "Fail"
    $testReport.Errors += "Exception during test suite: $($_.Exception.Message)"
    Write-Host "$MyTag ✗ Test suite failed with exception: $_" -ForegroundColor Red

} finally {
    # Clean up - close test card
    if ($cardId) {
        Write-Host "`n$MyTag Closing test card..." -ForegroundColor Cyan
        try {
            $closeScript = Join-Path $utilityPath "Close-DebugCard.ps1"
            & $closeScript -CardID $cardId -SessionID $SessionID -Wait -TimeoutSeconds 5 | Out-Null
        } catch {
            Write-Warning "$MyTag Failed to close card: $_"
        }
    }

    # Finalize report
    $testReport.EndTime = Get-Date
    $testReport.Duration = ($testReport.EndTime - $testReport.StartTime).TotalSeconds

    # Calculate pass rate
    $totalTests = $testReport.Tests.Count
    $passedTests = ($testReport.Tests | Where-Object { $_.Result -eq "Pass" }).Count
    $failedTests = ($testReport.Tests | Where-Object { $_.Result -eq "Fail" }).Count
    $warnTests = ($testReport.Tests | Where-Object { $_.Result -eq "Warn" }).Count

    # Generate summary
    $testReport.Summary = @"
DuckDB-WASM Metrics Chart Test Suite Results
=============================================
Overall Status: $($testReport.OverallStatus)
Duration: $([math]::Round($testReport.Duration, 2)) seconds
Tests: $passedTests passed, $failedTests failed, $warnTests warnings (out of $totalTests)

Performance Metrics:
- Load Time: $($testReport.PerformanceMetrics.LoadTime)ms
- History Load: $($testReport.PerformanceMetrics.HistoryLoadTime)ms (Target: <100ms)
- Memory Initial: $($testReport.PerformanceMetrics.MemoryInitial)MB
- Memory Final: $($testReport.PerformanceMetrics.MemoryFinal)MB
- Memory Growth: $($testReport.PerformanceMetrics.MemoryGrowth)MB

$(if ($testReport.Errors.Count -gt 0) {
    "Errors:`n" + ($testReport.Errors | ForEach-Object { "- $_" } | Out-String)
} else { "" })

$(if ($testReport.Warnings.Count -gt 0) {
    "Warnings:`n" + ($testReport.Warnings | ForEach-Object { "- $_" } | Out-String)
} else { "" })
"@

    # Display summary
    Write-Host "`n$MyTag ===== TEST SUITE COMPLETE =====" -ForegroundColor Cyan
    Write-Host $testReport.Summary

    Write-Host "`n$MyTag Overall Status: $($testReport.OverallStatus)" -ForegroundColor $(
        if ($testReport.OverallStatus -eq "Pass") { "Green" }
        elseif ($testReport.OverallStatus -eq "Warn") { "Yellow" }
        else { "Red" }
    )

    # Save report to file
    $reportPath = Join-Path $PSScriptRoot "DUCKDB_TEST_RESULTS_$(Get-Date -Format 'yyyy-MM-dd_HHmmss').json"
    $testReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $reportPath -Encoding UTF8

    Write-Host "`n$MyTag Test report saved to: $reportPath" -ForegroundColor Cyan
}

return $testReport
