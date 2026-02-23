# Quick test to send debug commands to browser
# Uses existing API key if available

$ErrorActionPreference = 'Stop'

Write-Host "=== Testing Debug Command Execution ===" -ForegroundColor Cyan

# Try to find existing API key from database
Write-Host ""
Write-Host "1. Looking for existing API keys..." -ForegroundColor Yellow

try {
    $ProjectRoot = $PSScriptRoot
    . (Join-Path $ProjectRoot "WebHost.ps1") -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null

    $dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

    # Get most recent API key
    $apiKeys = Get-PSWebSQLiteData -File $dbFile -Query "SELECT KeyID, APIKey, Name, UserID FROM API_Keys WHERE ExpiresAt IS NULL OR ExpiresAt > datetime('now') ORDER BY CreatedAt DESC LIMIT 1"

    if ($apiKeys) {
        $token = $apiKeys.APIKey
        Write-Host "  Found API key: $($apiKeys.Name)" -ForegroundColor Green
    } else {
        Write-Host "  No valid API keys found. Creating one..." -ForegroundColor Yellow

        # Create a simple test token
        try {
            $tokenResult = & "$ProjectRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin' 2>&1
            if ($tokenResult -and $tokenResult.AccessToken) {
                $token = $tokenResult.AccessToken
                Write-Host "  Created new test token" -ForegroundColor Green
            } else {
                throw "Failed to create token"
            }
        } catch {
            Write-Host "  Error creating token: $($_.Exception.Message)" -ForegroundColor Red
            Write-Host ""
            Write-Host "  ALTERNATIVE: Use browser session cookie instead" -ForegroundColor Yellow
            Write-Host "  1. Open DevTools in browser (F12)" -ForegroundColor White
            Write-Host "  2. Go to Console tab" -ForegroundColor White
            Write-Host "  3. Run: fetch('/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue', {method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({Command: 'alert(\"Test\")', Type: 'eval'})})" -ForegroundColor White
            exit 1
        }
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 1: Simple eval command
Write-Host ""
Write-Host "2. Sending eval command (alert test)..." -ForegroundColor Yellow

$body1 = @{
    Command = 'console.log("Debug command test from PowerShell!")'
    Type = 'eval'
} | ConvertTo-Json

try {
    $response1 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
        -Method POST `
        -Headers @{ Authorization = "Bearer $token" } `
        -Body $body1 `
        -ContentType 'application/json'

    Write-Host "  ✓ Command enqueued: $($response1.commandID)" -ForegroundColor Green
    $commandId1 = $response1.commandID
} catch {
    Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
    }
}

# Test 2: Open a card
Write-Host ""
Write-Host "3. Sending openCard command..." -ForegroundColor Yellow

$body2 = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Debug Variables (Opened via PowerShell)'
    }
} | ConvertTo-Json

try {
    $response2 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
        -Method POST `
        -Headers @{ Authorization = "Bearer $token" } `
        -Body $body2 `
        -ContentType 'application/json'

    Write-Host "  ✓ Command enqueued: $($response2.commandID)" -ForegroundColor Green
    $commandId2 = $response2.commandID
} catch {
    Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Get window location
Write-Host ""
Write-Host "4. Sending command to get window.location..." -ForegroundColor Yellow

$body3 = @{
    Command = 'JSON.stringify({href: window.location.href, pathname: window.location.pathname})'
    Type = 'eval'
} | ConvertTo-Json

try {
    $response3 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
        -Method POST `
        -Headers @{ Authorization = "Bearer $token" } `
        -Body $body3 `
        -ContentType 'application/json'

    Write-Host "  ✓ Command enqueued: $($response3.commandID)" -ForegroundColor Green
    $commandId3 = $response3.commandID
} catch {
    Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Wait for commands to execute
Write-Host ""
Write-Host "5. Waiting for commands to execute (5 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Check command history
Write-Host ""
Write-Host "6. Checking command execution results..." -ForegroundColor Yellow

try {
    $history = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=10" `
        -Headers @{ Authorization = "Bearer $token" }

    Write-Host "  Retrieved $($history.Count) recent commands" -ForegroundColor Green

    # Show our commands
    foreach ($cmdId in @($commandId1, $commandId2, $commandId3)) {
        if (-not $cmdId) { continue }

        $cmd = $history | Where-Object { $_.CommandID -eq $cmdId } | Select-Object -First 1
        if ($cmd) {
            Write-Host ""
            Write-Host "  Command: $($cmd.Command)" -ForegroundColor Cyan
            Write-Host "  Type: $($cmd.Type)" -ForegroundColor Gray
            Write-Host "  Status: $($cmd.Status)" -ForegroundColor $(if ($cmd.Status -eq 'completed') { 'Green' } elseif ($cmd.Status -eq 'pending') { 'Yellow' } else { 'Red' })

            if ($cmd.Status -eq 'completed') {
                Write-Host "  Execution Time: $($cmd.ExecutionTime)ms" -ForegroundColor Gray
                if ($cmd.Result) {
                    Write-Host "  Result: $($cmd.Result)" -ForegroundColor White
                }
                if ($cmd.Error) {
                    Write-Host "  Error: $($cmd.Error)" -ForegroundColor Red
                }
            } elseif ($cmd.Status -eq 'pending') {
                Write-Host "  WARNING: Command still pending - check browser console and verify poll service is running" -ForegroundColor Yellow
            }
        }
    }
} catch {
    Write-Host "  ✗ Error fetching history: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "TIPS:" -ForegroundColor Yellow
Write-Host "  - Check browser console for [DebugPollService] messages" -ForegroundColor White
Write-Host "  - Check browser Network tab for poll requests" -ForegroundColor White
Write-Host "  - If commands stay pending, ensure browser has debug role and page is loaded" -ForegroundColor White
