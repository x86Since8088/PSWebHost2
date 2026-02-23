# Test Debug Command System
# Opens a card and captures its outerHTML via debug console

Write-Host "=== Testing Debug Command System ===" -ForegroundColor Cyan
Write-Host "`nNOTE: Debug polling service auto-loads for users with debug role." -ForegroundColor Yellow
Write-Host "      Ensure you're logged in with debug role and have refreshed the browser." -ForegroundColor Yellow
Write-Host "`nPress Enter to continue..." -ForegroundColor Yellow
Read-Host

# Get bearer token
Write-Host "`n1. Getting bearer token..." -ForegroundColor Yellow
$token = & "$PSScriptRoot\system\utility\Account_Auth_BearerToken_New.ps1" -TestAccount -Roles 'debug','system_admin'

if (-not $token) {
    Write-Host "Failed to get bearer token" -ForegroundColor Red
    exit 1
}

Write-Host "  Token obtained: $($token.AccessToken.Substring(0,20))..." -ForegroundColor Green

# Enqueue command to open debug-variables card
Write-Host "`n2. Enqueuing openCard command..." -ForegroundColor Yellow
$body = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Debug Variables Test'
    }
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
        -Method POST `
        -Headers @{ Authorization = "Bearer $($token.AccessToken)" } `
        -Body $body `
        -ContentType 'application/json'

    Write-Host "  Command enqueued: $($response.commandID)" -ForegroundColor Green
    Write-Host "  Queue position: $($response.queuePosition)" -ForegroundColor Green

    $commandId1 = $response.commandID
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Wait for command to execute
Write-Host "`n3. Waiting for command to execute (3 seconds)..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

# Check command history to see result
Write-Host "`n4. Checking command execution result..." -ForegroundColor Yellow
try {
    $history = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=5" `
        -Headers @{ Authorization = "Bearer $($token.AccessToken)" }

    $openCardCmd = $history | Where-Object { $_.CommandID -eq $commandId1 } | Select-Object -First 1

    if ($openCardCmd) {
        Write-Host "  Status: $($openCardCmd.Status)" -ForegroundColor Green
        Write-Host "  Result:" -ForegroundColor Green
        $openCardCmd.Result | ConvertTo-Json -Depth 3 | Write-Host

        # Extract card ID from result
        $cardId = ($openCardCmd.Result | ConvertFrom-Json).cardId
        Write-Host "`n  Card ID: $cardId" -ForegroundColor Cyan
    } else {
        Write-Host "  Command not found in history" -ForegroundColor Red
    }
} catch {
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}

# Now get the card's outerHTML
if ($cardId) {
    Write-Host "`n5. Getting card outerHTML..." -ForegroundColor Yellow

    $body2 = @{
        Command = 'getOuterHTML'
        Type = 'predefined'
        Params = @{
            selector = "#$cardId"
            maxLength = 10000
        }
    } | ConvertTo-Json

    try {
        $response2 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
            -Method POST `
            -Headers @{ Authorization = "Bearer $($token.AccessToken)" } `
            -Body $body2 `
            -ContentType 'application/json'

        Write-Host "  Command enqueued: $($response2.commandID)" -ForegroundColor Green

        $commandId2 = $response2.commandID

        # Wait for execution
        Start-Sleep -Seconds 2

        # Get result
        $history2 = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=5" `
            -Headers @{ Authorization = "Bearer $($token.AccessToken)" }

        $htmlCmd = $history2 | Where-Object { $_.CommandID -eq $commandId2 } | Select-Object -First 1

        if ($htmlCmd -and $htmlCmd.Status -eq 'completed') {
            Write-Host "`n  outerHTML retrieved (length: $(($htmlCmd.Result | ConvertFrom-Json).fullLength))" -ForegroundColor Green
            Write-Host "`n  Preview (first 500 chars):" -ForegroundColor Cyan
            ($htmlCmd.Result | ConvertFrom-Json).outerHTML.Substring(0, [Math]::Min(500, ($htmlCmd.Result | ConvertFrom-Json).outerHTML.Length)) | Write-Host
        }
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Test highlightRegion command
if ($cardId) {
    Write-Host "`n6. Highlighting the card..." -ForegroundColor Yellow

    $body3 = @{
        Command = 'highlightRegion'
        Type = 'predefined'
        Params = @{
            selector = "#$cardId"
            duration = 5000
            color = '#00ff00'
        }
    } | ConvertTo-Json

    try {
        $response3 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
            -Method POST `
            -Headers @{ Authorization = "Bearer $($token.AccessToken)" } `
            -Body $body3 `
            -ContentType 'application/json'

        Write-Host "  Highlight command sent - card should be highlighted green for 5 seconds" -ForegroundColor Green
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
