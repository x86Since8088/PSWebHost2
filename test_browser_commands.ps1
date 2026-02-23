#Requires -Version 7

Write-Host "`n=== Testing Browser Commands via File-Based Queue ===" -ForegroundColor Cyan
Write-Host ""

# Test 1: Browser Info
Write-Host "[Test 1] Getting browser info..." -ForegroundColor Yellow
$result1 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "browserInfo" `
    -Type predefined `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result1.Success) {
    Write-Host "  ✓ Browser Info Retrieved" -ForegroundColor Green
    Write-Host "  Result: $($result1.Result)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed: $($result1.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Test 2: List all cards
Write-Host "`n[Test 2] Listing all cards..." -ForegroundColor Yellow
$result2 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "listCards" `
    -Type predefined `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result2.Success) {
    Write-Host "  ✓ Cards Listed" -ForegroundColor Green
    $cards = $result2.Result | ConvertFrom-Json
    Write-Host "  Found $($cards.Length) cards" -ForegroundColor White
    $cards | Select-Object -First 5 | ForEach-Object {
        Write-Host "    - $($_.title)" -ForegroundColor Gray
    }
} else {
    Write-Host "  ✗ Failed: $($result2.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Test 3: Open a debug card
Write-Host "`n[Test 3] Opening debug console card..." -ForegroundColor Yellow
$result3 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "openCard" `
    -Type predefined `
    -Params @{
        url = "/apps/WebHostDebugExtensions/cards/debug-console"
        title = "Debug Console Test"
    } `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result3.Success) {
    Write-Host "  ✓ Card Opened" -ForegroundColor Green
    Write-Host "  Result: $($result3.Result)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed: $($result3.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 2

# Test 4: Console log test
Write-Host "`n[Test 4] Testing console.log forwarding..." -ForegroundColor Yellow
$result4 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "console.log('=== File-Based Queue Test ==='); console.log('Timestamp: ' + new Date().toISOString()); 'Console test complete'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result4.Success) {
    Write-Host "  ✓ Console Log Test Complete" -ForegroundColor Green
    Write-Host "  Result: $($result4.Result)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed: $($result4.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Test 5: Get current page info
Write-Host "`n[Test 5] Getting current page information..." -ForegroundColor Yellow
$result5 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "JSON.stringify({url: window.location.href, title: document.title, cards: window.appState ? window.appState.openCards.length : 0})" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result5.Success) {
    Write-Host "  ✓ Page Info Retrieved" -ForegroundColor Green
    try {
        $pageInfo = $result5.Result | ConvertFrom-Json
        Write-Host "  URL: $($pageInfo.url)" -ForegroundColor White
        Write-Host "  Title: $($pageInfo.title)" -ForegroundColor White
        Write-Host "  Open Cards: $($pageInfo.cards)" -ForegroundColor White
    } catch {
        Write-Host "  Result: $($result5.Result)" -ForegroundColor White
    }
} else {
    Write-Host "  ✗ Failed: $($result5.Message)" -ForegroundColor Red
}

Start-Sleep -Seconds 1

# Test 6: Browser refresh test
Write-Host "`n[Test 6] Testing browser refresh (location.reload)..." -ForegroundColor Yellow
$result6 = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "location.reload(); 'Refresh initiated'" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result6.Success) {
    Write-Host "  ✓ Browser Refresh Initiated" -ForegroundColor Green
    Write-Host "  Result: $($result6.Result)" -ForegroundColor White
} else {
    Write-Host "  ✗ Failed or browser refreshed before response: $($result6.Message)" -ForegroundColor Yellow
}

Write-Host "`n=== Browser Command Tests Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor Cyan
Write-Host "  Tests Run: 6" -ForegroundColor White
Write-Host "  Check browser console for console.log output" -ForegroundColor Gray
Write-Host "  Check browser for opened cards" -ForegroundColor Gray
