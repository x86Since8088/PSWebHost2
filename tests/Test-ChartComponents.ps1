#Requires -Version 7

<#
.SYNOPSIS
    Automated test suite for UI_Uplot chart components
.DESCRIPTION
    Tests all chart types (time-series, area-chart, bar-chart, scatter-plot, multi-axis, heatmap)
    using the MSEdge debugging session
.PARAMETER BaseUrl
    Base URL for PSWebHost (default: http://localhost:8888)
.PARAMETER ChartType
    Specific chart type to test (defaults to all)
.PARAMETER Interactive
    Enable interactive mode after tests
.EXAMPLE
    .\Test-ChartComponents.ps1
.EXAMPLE
    .\Test-ChartComponents.ps1 -ChartType "bar-chart" -Interactive
#>

param(
    [string]$BaseUrl = "http://localhost:8888",
    [ValidateSet('all', 'time-series', 'area-chart', 'bar-chart', 'scatter-plot', 'multi-axis', 'heatmap')]
    [string]$ChartType = 'all',
    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'

# Chart configurations
$charts = @{
    'time-series'  = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/time-series?chartId=test1&source=metrics-db&metric=cpu_usage"
        Container   = '.time-series-container'
        Title       = 'Time Series Chart'
        CanvasCheck = $true
    }
    'area-chart'   = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/area-chart?chartId=test2&source=metrics-db&metric=memory_usage"
        Container   = '.area-chart-container'  # Note: This should match component.js
        Title       = 'Area Chart'
        CanvasCheck = $true
    }
    'bar-chart'    = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/bar-chart?chartId=test3&source=metrics-db&metric=request_count"
        Container   = '.bar-chart-container'
        Title       = 'Bar Chart'
        CanvasCheck = $true
    }
    'scatter-plot' = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/scatter-plot?chartId=test4&source=metrics-db&metric=correlation_data"
        Container   = '.scatter-plot-container'
        Title       = 'Scatter Plot'
        CanvasCheck = $true
    }
    'multi-axis'   = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/multi-axis?chartId=test5&source=metrics-db&metric=multi_metric"
        Container   = '.multi-axis-container'
        Title       = 'Multi-Axis Chart'
        CanvasCheck = $true
    }
    'heatmap'      = @{
        Url         = "$BaseUrl/apps/uplot/api/v1/ui/elements/heatmap?chartId=test6&source=metrics-db&metric=heatmap_data"
        Container   = '.heatmap-container'
        Title       = 'Heatmap'
        CanvasCheck = $true
    }
}

# Test results
$testResults = @()

function Test-Chart {
    param(
        [string]$Name,
        [hashtable]$Config
    )

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Testing: $Name" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan

    $result = @{
        ChartType   = $Name
        Url         = $Config.Url
        Passed      = 0
        Failed      = 0
        Tests       = @()
        Screenshot  = $null
        Performance = $null
    }

    try {
        # Launch debugging session
        Write-Host "Launching Edge for $Name..." -ForegroundColor Yellow

        $edgePath = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
        if (-not (Test-Path $edgePath)) {
            $edgePath = "C:\Program Files\Microsoft\Edge\Application\msedge.exe"
        }

        $tempProfile = Join-Path $env:TEMP "EdgeProfile_$([guid]::NewGuid())"
        $proc = Start-Process -FilePath $edgePath `
            -ArgumentList @(
            "--new-window",
            "--remote-debugging-port=9222",
            "--user-data-dir=$tempProfile",
            "--headless",
            $Config.Url
        ) `
            -PassThru

        Start-Sleep -Seconds 3

        # Connect to debugging session
        $targets = Invoke-RestMethod -Uri "http://localhost:9222/json" -TimeoutSec 5
        $pageTarget = $targets | Where-Object { $_.type -eq 'page' } | Select-Object -First 1

        if (-not $pageTarget) {
            throw "No page target found"
        }

        $wsUrl = $pageTarget.webSocketDebuggerUrl
        $wsClient = [System.Net.WebSockets.ClientWebSocket]::new()
        $wsClient.ConnectAsync([System.Uri]$wsUrl, [Threading.CancellationToken]::None).Wait()

        # Enable Runtime and Page domains
        $script:cdpId = 1000

        function Send-CDP {
            param([string]$Method, [hashtable]$Params = @{})

            $script:cdpId++
            $command = @{
                id     = $script:cdpId
                method = $Method
                params = $Params
            } | ConvertTo-Json -Compress -Depth 10

            $bytes = [System.Text.Encoding]::UTF8.GetBytes($command)
            $segment = [System.ArraySegment[byte]]::new($bytes)
            $wsClient.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).Wait()
        }

        function Receive-CDP {
            $buffer = New-Object byte[] 65536
            $segment = [System.ArraySegment[byte]]::new($buffer)
            $ms = New-Object System.IO.MemoryStream

            $cts = [System.Threading.CancellationTokenSource]::new(5000)

            try {
                do {
                    $task = $wsClient.ReceiveAsync($segment, $cts.Token)
                    $r = $task.Result

                    if ($r.Count -gt 0) {
                        $ms.Write($buffer, 0, $r.Count)
                    }
                } while (-not $r.EndOfMessage)

                return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
            }
            catch {
                return $null
            }
            finally {
                $cts.Dispose()
            }
        }

        function Eval-JS {
            param([string]$Script)

            Send-CDP -Method 'Runtime.evaluate' -Params @{ expression = $Script; returnByValue = $true }

            $timeout = [DateTime]::Now.AddSeconds(5)
            while ([DateTime]::Now -lt $timeout) {
                $response = Receive-CDP
                if ($response) {
                    $obj = $response | ConvertFrom-Json
                    if ($obj.id -eq $script:cdpId) {
                        return $obj.result.result.value
                    }
                }
            }
            return $null
        }

        Send-CDP -Method 'Runtime.enable' | Out-Null
        Receive-CDP | Out-Null

        Send-CDP -Method 'Page.enable' | Out-Null
        Receive-CDP | Out-Null

        # Wait for page load
        Start-Sleep -Seconds 2

        # Test 1: Container exists
        Write-Host "  [Test] Container exists..." -NoNewline
        $hasContainer = Eval-JS -Script "document.querySelector('$($Config.Container)') !== null"
        if ($hasContainer) {
            Write-Host " PASS" -ForegroundColor Green
            $result.Passed++
            $result.Tests += "Container exists"
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $result.Failed++
        }

        # Test 2: Chart header
        Write-Host "  [Test] Chart header..." -NoNewline
        $hasHeader = Eval-JS -Script "document.querySelector('.chart-header') !== null"
        if ($hasHeader) {
            Write-Host " PASS" -ForegroundColor Green
            $result.Passed++
            $result.Tests += "Chart header rendered"
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $result.Failed++
        }

        # Test 3: Title text
        Write-Host "  [Test] Title text..." -NoNewline
        $title = Eval-JS -Script "document.querySelector('.chart-header h2')?.textContent"
        if ($title -eq $Config.Title) {
            Write-Host " PASS ($title)" -ForegroundColor Green
            $result.Passed++
            $result.Tests += "Title correct: $title"
        }
        else {
            Write-Host " FAIL (expected: $($Config.Title), got: $title)" -ForegroundColor Red
            $result.Failed++
        }

        # Test 4: Chart canvas (if applicable)
        if ($Config.CanvasCheck) {
            Write-Host "  [Test] Chart canvas..." -NoNewline
            $hasCanvas = Eval-JS -Script "document.querySelector('#chartContainer canvas') !== null || document.querySelector('#heatmapCanvas canvas') !== null"
            if ($hasCanvas) {
                Write-Host " PASS" -ForegroundColor Green
                $result.Passed++
                $result.Tests += "Chart canvas rendered"
            }
            else {
                Write-Host " FAIL" -ForegroundColor Red
                $result.Failed++
            }
        }

        # Test 5: Controls exist
        Write-Host "  [Test] Chart controls..." -NoNewline
        $hasControls = Eval-JS -Script "document.querySelector('.chart-controls') !== null"
        if ($hasControls) {
            Write-Host " PASS" -ForegroundColor Green
            $result.Passed++
            $result.Tests += "Chart controls present"
        }
        else {
            Write-Host " FAIL" -ForegroundColor Red
            $result.Failed++
        }

        # Test 6: No JavaScript errors
        Write-Host "  [Test] No JS errors..." -NoNewline
        $errorCount = Eval-JS -Script "window.__errorCount || 0"
        if ($errorCount -eq 0) {
            Write-Host " PASS" -ForegroundColor Green
            $result.Passed++
            $result.Tests += "No JavaScript errors"
        }
        else {
            Write-Host " FAIL ($errorCount errors)" -ForegroundColor Red
            $result.Failed++
        }

        # Get performance metrics
        $perfJS = @'
(function() {
    try {
        const perf = performance.getEntriesByType('navigation')[0];
        return {
            domContentLoaded: Math.round(perf.domContentLoadedEventEnd - perf.domContentLoadedEventStart),
            loadComplete: Math.round(perf.loadEventEnd - perf.loadEventStart),
            domInteractive: Math.round(perf.domInteractive - perf.fetchStart),
            totalTime: Math.round(perf.loadEventEnd - perf.fetchStart)
        };
    } catch(e) {
        return null;
    }
})()
'@
        $perf = Eval-JS -Script $perfJS
        if ($perf) {
            $result.Performance = $perf
            Write-Host "  [Info] Load time: $($perf.totalTime)ms" -ForegroundColor Cyan
        }

        # Cleanup
        $wsClient.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "Test complete", [Threading.CancellationToken]::None).Wait()
        $wsClient.Dispose()
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue

    }
    catch {
        Write-Host "`n  [Error] $($_.Exception.Message)" -ForegroundColor Red
        $result.Failed++
    }

    return $result
}

# Main execution
Write-Host "`n=== UI_Uplot Chart Component Tests ===" -ForegroundColor Cyan
Write-Host "Base URL: $BaseUrl`n" -ForegroundColor White

# Check if PSWebHost is running
try {
    Invoke-WebRequest -Uri "$BaseUrl/api/v1/auth/status" -TimeoutSec 3 -UseBasicParsing | Out-Null
    Write-Host "PSWebHost is running" -ForegroundColor Green
}
catch {
    Write-Error "PSWebHost is not running. Start WebHost.ps1 first."
    exit 1
}

# Run tests
if ($ChartType -eq 'all') {
    foreach ($chart in $charts.Keys) {
        $result = Test-Chart -Name $chart -Config $charts[$chart]
        $testResults += $result
    }
}
else {
    if ($charts.ContainsKey($ChartType)) {
        $result = Test-Chart -Name $ChartType -Config $charts[$ChartType]
        $testResults += $result
    }
    else {
        Write-Error "Unknown chart type: $ChartType"
        exit 1
    }
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$totalPassed = ($testResults | Measure-Object -Property Passed -Sum).Sum
$totalFailed = ($testResults | Measure-Object -Property Failed -Sum).Sum
$totalTests = $totalPassed + $totalFailed

foreach ($result in $testResults) {
    $status = if ($result.Failed -eq 0) { "PASS" } else { "FAIL" }
    $color = if ($result.Failed -eq 0) { "Green" } else { "Red" }

    Write-Host "`n$($result.ChartType):" -ForegroundColor White
    Write-Host "  Status: $status ($($result.Passed)/$($result.Passed + $result.Failed) tests passed)" -ForegroundColor $color

    if ($result.Performance) {
        Write-Host "  Load time: $($result.Performance.totalTime)ms" -ForegroundColor Cyan
    }
}

Write-Host "`nOverall: $totalPassed/$totalTests tests passed" -ForegroundColor $(if ($totalFailed -eq 0) { "Green" } else { "Yellow" })

if ($totalFailed -eq 0) {
    Write-Host "`nAll tests passed! ✓" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "`n$totalFailed test(s) failed" -ForegroundColor Red
    exit 1
}
