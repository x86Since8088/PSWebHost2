#Requires -Version 7

<#
.SYNOPSIS
    Tests file-based command queue with a live browser

.DESCRIPTION
    This script sends commands to the browser via the file-based queue.
    Open http://localhost:8080/test-file-queue.html in your browser first!
#>

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " File-Based Queue - Live Browser Test" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "INSTRUCTIONS:" -ForegroundColor Yellow
Write-Host "1. Open your browser to: " -NoNewline -ForegroundColor White
Write-Host "http://localhost:8080/test-file-queue.html" -ForegroundColor Green
Write-Host "2. Keep the browser window visible" -ForegroundColor White
Write-Host "3. Press ENTER when ready..." -ForegroundColor White
Write-Host ""

$null = Read-Host

Write-Host "`nStarting tests..." -ForegroundColor Cyan
Write-Host ""

# Test 1: Simple console log
Write-Host "[Test 1] Sending console.log command..." -ForegroundColor Yellow
$result1 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "console.log('✓ File-based queue is working!'); console.log('Timestamp: ' + new Date().toISOString()); 'Console log test complete'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15 `
    -Verbose

if ($result1.Success) {
    Write-Host "  ✓ Success: $($result1.Result)" -ForegroundColor Green
    Write-Host "  Execution Time: $($result1.ExecutionTimeMs)ms" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result1.Message)" -ForegroundColor Red
    Write-Host "  Make sure the browser is open and polling!" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# Test 2: Get page info
Write-Host "`n[Test 2] Getting page information..." -ForegroundColor Yellow
$result2 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "JSON.stringify({url: location.href, title: document.title, userAgent: navigator.userAgent.substring(0,50)})" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result2.Success) {
    Write-Host "  ✓ Success" -ForegroundColor Green
    try {
        $info = $result2.Result | ConvertFrom-Json
        Write-Host "  URL: $($info.url)" -ForegroundColor White
        Write-Host "  Title: $($info.title)" -ForegroundColor White
        Write-Host "  User Agent: $($info.userAgent)..." -ForegroundColor White
    } catch {
        Write-Host "  Result: $($result2.Result)" -ForegroundColor White
    }
} else {
    Write-Host "  ✗ Failed: $($result2.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 3: Alert test
Write-Host "`n[Test 3] Showing browser alert..." -ForegroundColor Yellow
$result3 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "alert('File-based queue test from PowerShell!'); 'Alert shown'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result3.Success) {
    Write-Host "  ✓ Success: $($result3.Result)" -ForegroundColor Green
    Write-Host "  Check the browser for the alert dialog" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result3.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 4: DOM manipulation
Write-Host "`n[Test 4] Changing page background color..." -ForegroundColor Yellow
$result4 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "document.body.style.background = 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)'; document.body.style.color = 'white'; 'Background changed'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result4.Success) {
    Write-Host "  ✓ Success: $($result4.Result)" -ForegroundColor Green
    Write-Host "  The page background should now be purple gradient" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result4.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 3

# Test 5: Reset background
Write-Host "`n[Test 5] Resetting page background..." -ForegroundColor Yellow
$result5 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "document.body.style.background = '#f5f5f5'; document.body.style.color = ''; 'Background reset'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result5.Success) {
    Write-Host "  ✓ Success: $($result5.Result)" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed: $($result5.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 6: Performance test
Write-Host "`n[Test 6] Performance measurement..." -ForegroundColor Yellow
$result6 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "JSON.stringify({memory: performance.memory ? performance.memory.usedJSHeapSize : 'N/A', timing: performance.timing.domContentLoadedEventEnd - performance.timing.navigationStart})" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result6.Success) {
    Write-Host "  ✓ Success" -ForegroundColor Green
    Write-Host "  Performance data: $($result6.Result)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed: $($result6.Message)" -ForegroundColor Red
}

# Summary
Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Test Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$successCount = @($result1, $result2, $result3, $result4, $result5, $result6) | Where-Object { $_.Success } | Measure-Object | Select-Object -ExpandProperty Count

Write-Host "Tests Passed: $successCount / 6" -ForegroundColor $(if ($successCount -eq 6) { "Green" } else { "Yellow" })
Write-Host ""

if ($successCount -eq 6) {
    Write-Host "✓ All tests passed! File-based queue is fully operational." -ForegroundColor Green
} else {
    Write-Host "⚠ Some tests failed. Check that:" -ForegroundColor Yellow
    Write-Host "  - Browser is open to http://localhost:8080/test-file-queue.html" -ForegroundColor White
    Write-Host "  - Browser is actively polling (green indicator)" -ForegroundColor White
    Write-Host "  - No console errors in browser" -ForegroundColor White
}

Write-Host ""
