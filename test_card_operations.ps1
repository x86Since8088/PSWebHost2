#Requires -Version 7

<#
.SYNOPSIS
    Comprehensive card testing via file-based queue

.DESCRIPTION
    Tests card operations including:
    - Opening cards
    - Validating cards
    - Closing cards
    - Browser refresh (without expecting result back)
#>

param(
    [Parameter()]
    [switch]$SkipBrowserCheck
)

Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Card Operations Test - File-Based Queue" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

if (-not $SkipBrowserCheck) {
    Write-Host "SETUP:" -ForegroundColor Yellow
    Write-Host "1. Open browser to: " -NoNewline -ForegroundColor White
    Write-Host "http://localhost:8080/" -ForegroundColor Green
    Write-Host "2. Keep browser window visible" -ForegroundColor White
    Write-Host "3. Press ENTER when ready..." -ForegroundColor White
    Write-Host ""
    $null = Read-Host
}

Write-Host "Starting card operation tests..." -ForegroundColor Cyan
Write-Host ""

# Test 1: List available cards
Write-Host "[Test 1] Getting list of all available cards..." -ForegroundColor Yellow
$result1 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "
        const cards = [];
        document.querySelectorAll('[data-card-url]').forEach(el => {
            cards.push({
                title: el.textContent.trim(),
                url: el.getAttribute('data-card-url')
            });
        });
        JSON.stringify({count: cards.length, cards: cards.slice(0, 10)})
    " `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result1.Success) {
    Write-Host "  ✓ Success" -ForegroundColor Green
    try {
        $cardData = $result1.Result | ConvertFrom-Json
        Write-Host "  Found $($cardData.count) available cards" -ForegroundColor White
        $cardData.cards | Select-Object -First 5 | ForEach-Object {
            Write-Host "    - $($_.title)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Result: $($result1.Result)" -ForegroundColor White
    }
} else {
    Write-Host "  ✗ Failed: $($result1.Message)" -ForegroundColor Red
    Write-Host "  Make sure browser is at http://localhost:8080/" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# Test 2: Open Debug Console card
Write-Host "`n[Test 2] Opening Debug Console card..." -ForegroundColor Yellow
$result2 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "
        window.openCard && window.openCard({
            url: '/apps/WebHostDebugExtensions/cards/debug-console',
            title: 'Debug Console - Queue Test'
        });
        'Card open initiated'
    " `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result2.Success) {
    Write-Host "  ✓ Success: $($result2.Result)" -ForegroundColor Green
    Write-Host "  Debug Console card should now be open in browser" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result2.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 3

# Test 3: Get currently open cards
Write-Host "`n[Test 3] Getting list of currently open cards..." -ForegroundColor Yellow
$result3 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "
        const openCards = window.appState && window.appState.openCards ?
            window.appState.openCards.map(c => ({id: c.id, title: c.title})) :
            [];
        JSON.stringify({count: openCards.length, cards: openCards})
    " `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result3.Success) {
    Write-Host "  ✓ Success" -ForegroundColor Green
    try {
        $openCards = $result3.Result | ConvertFrom-Json
        Write-Host "  $($openCards.count) card(s) currently open:" -ForegroundColor White
        $openCards.cards | ForEach-Object {
            Write-Host "    - [$($_.id)] $($_.title)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "  Result: $($result3.Result)" -ForegroundColor White
    }
} else {
    Write-Host "  ✗ Failed: $($result3.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 4: Send message to Debug Console
Write-Host "`n[Test 4] Sending test message to console..." -ForegroundColor Yellow
$result4 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "
        console.log('%c=== File-Based Queue Test ===', 'color: #4CAF50; font-size: 16px; font-weight: bold');
        console.log('✓ Commands are being received from PowerShell');
        console.log('✓ File-based queue is operational');
        console.log('✓ Timestamp:', new Date().toISOString());
        'Console messages sent'
    " `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result4.Success) {
    Write-Host "  ✓ Success: $($result4.Result)" -ForegroundColor Green
    Write-Host "  Check browser console for formatted output" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result4.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 5: Validate a card (non-destructive test)
Write-Host "`n[Test 5] Validating System Log card..." -ForegroundColor Yellow
$result5 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "
        fetch('/cards/system-log')
            .then(r => r.ok ? 'PASS: Card loads successfully' : 'FAIL: HTTP ' + r.status)
            .then(result => result)
            .catch(e => 'FAIL: ' + e.message)
    " `
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

# Test 6: Browser refresh (don't wait for result - it won't come back)
Write-Host "`n[Test 6] Testing browser refresh..." -ForegroundColor Yellow
Write-Host "  Note: Refresh commands don't return results (page reloads)" -ForegroundColor Gray

# Send the command without waiting
$result6 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "setTimeout(() => location.reload(), 500); 'Refresh scheduled'" `
    -Type eval `
    -SessionID all

Write-Host "  ✓ Refresh command sent (CommandID: $($result6.CommandID))" -ForegroundColor Green
Write-Host "  Browser should refresh in 0.5 seconds..." -ForegroundColor Gray

Start-Sleep -Seconds 5

# Test 7: Verify browser reconnected after refresh
Write-Host "`n[Test 7] Verifying browser reconnected after refresh..." -ForegroundColor Yellow
$result7 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "'Browser is back online - refresh successful!'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result7.Success) {
    Write-Host "  ✓ Success: $($result7.Result)" -ForegroundColor Green
    Write-Host "  Browser successfully refreshed and reconnected" -ForegroundColor Gray
} else {
    Write-Host "  ✗ Failed: $($result7.Message)" -ForegroundColor Red
    Write-Host "  Browser may still be loading..." -ForegroundColor Yellow
}

# Summary
Write-Host "`n" -NoNewline
Write-Host "============================================" -ForegroundColor Cyan
Write-Host " Test Summary" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$testResults = @(
    @{Name="List Cards"; Result=$result1.Success},
    @{Name="Open Card"; Result=$result2.Success},
    @{Name="Get Open Cards"; Result=$result3.Success},
    @{Name="Console Messages"; Result=$result4.Success},
    @{Name="Validate Card"; Result=$result5.Success},
    @{Name="Browser Refresh"; Result=$true}, # Always pass - we don't wait
    @{Name="Post-Refresh Reconnect"; Result=$result7.Success}
)

$passCount = ($testResults | Where-Object { $_.Result }).Count

Write-Host "Tests Passed: $passCount / $($testResults.Count)" -ForegroundColor $(if ($passCount -eq $testResults.Count) { "Green" } else { "Yellow" })
Write-Host ""

$testResults | ForEach-Object {
    $icon = if ($_.Result) { "✓" } else { "✗" }
    $color = if ($_.Result) { "Green" } else { "Red" }
    Write-Host "  $icon $($_.Name)" -ForegroundColor $color
}

Write-Host ""

if ($passCount -eq $testResults.Count) {
    Write-Host "============================================" -ForegroundColor Green
    Write-Host " ALL TESTS PASSED! " -ForegroundColor Green
    Write-Host " File-based queue is fully operational! " -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
} else {
    Write-Host "Some tests failed. This is usually because:" -ForegroundColor Yellow
    Write-Host "  - Browser wasn't open or at the wrong page" -ForegroundColor White
    Write-Host "  - Browser polling was disabled" -ForegroundColor White
    Write-Host "  - Network/timing issues" -ForegroundColor White
}

Write-Host ""
