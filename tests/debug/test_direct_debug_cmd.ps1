# Direct debug command test - no WebHost environment needed
# This script assumes you have a valid session cookie in your browser

Write-Host "=== Debug Command Test (Direct API) ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "NOTE: This test requires either:" -ForegroundColor Yellow
Write-Host "  1. A valid API key (bearer token)" -ForegroundColor White
Write-Host "  2. An active browser session with debug role" -ForegroundColor White
Write-Host ""

# Option 1: Try using a bearer token if you have one
$token = Read-Host "Enter bearer token (or press Enter to skip)"

if ($token) {
    $headers = @{
        'Authorization' = "Bearer $token"
        'Content-Type' = 'application/json'
    }
} else {
    Write-Host "No token provided. Commands will be queued but may fail auth." -ForegroundColor Yellow
    $headers = @{
        'Content-Type' = 'application/json'
    }
}

# Test commands
$commands = @(
    @{
        Name = "Console Log Test"
        Body = @{
            Command = 'console.log("DEBUG: Hello from PowerShell command system!")'
            Type = 'eval'
        }
    },
    @{
        Name = "Get Page URL"
        Body = @{
            Command = 'window.location.href'
            Type = 'eval'
        }
    },
    @{
        Name = "Count Open Cards"
        Body = @{
            Command = 'Object.keys(window.data.elements).length'
            Type = 'eval'
        }
    },
    @{
        Name = "Open Debug Variables Card"
        Body = @{
            Command = 'openCard'
            Type = 'predefined'
            Params = @{
                url = '/apps/WebHostDebugVariables/cards/debug-variables'
                title = 'Test from PowerShell'
            }
        }
    }
)

$commandIds = @()

foreach ($cmd in $commands) {
    Write-Host ""
    Write-Host "Enqueueing: $($cmd.Name)" -ForegroundColor Yellow

    $json = $cmd.Body | ConvertTo-Json -Depth 10

    try {
        $response = Invoke-RestMethod `
            -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
            -Method POST `
            -Headers $headers `
            -Body $json

        Write-Host "  SUCCESS: Command ID $($response.commandID)" -ForegroundColor Green
        $commandIds += $response.commandID
    } catch {
        Write-Host "  FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.ErrorDetails.Message) {
            Write-Host "  Details: $($_.ErrorDetails.Message)" -ForegroundColor Red
        }
    }
}

# Wait for execution
Write-Host ""
Write-Host "Waiting 5 seconds for poll service to execute commands..." -ForegroundColor Cyan
Start-Sleep -Seconds 5

# Check results
Write-Host ""
Write-Host "Fetching command results..." -ForegroundColor Cyan

try {
    $history = Invoke-RestMethod `
        -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=20" `
        -Headers $headers

    Write-Host "Retrieved $($history.Count) commands from history" -ForegroundColor Green
    Write-Host ""

    foreach ($id in $commandIds) {
        $cmd = $history | Where-Object { $_.CommandID -eq $id } | Select-Object -First 1
        if ($cmd) {
            Write-Host "----------------------------------------" -ForegroundColor Gray
            Write-Host "Command: $($cmd.Command)" -ForegroundColor Cyan
            Write-Host "Type: $($cmd.Type)" -ForegroundColor Gray
            Write-Host "Status: $($cmd.Status)" -ForegroundColor $(if ($cmd.Status -eq 'completed') { 'Green' } elseif ($cmd.Status -eq 'pending') { 'Yellow' } else { 'Red' })

            if ($cmd.Status -eq 'completed') {
                Write-Host "Execution Time: $($cmd.ExecutionTime)ms" -ForegroundColor Gray
                if ($cmd.Result) {
                    Write-Host "Result:" -ForegroundColor White
                    Write-Host $cmd.Result -ForegroundColor White
                }
                if ($cmd.Error) {
                    Write-Host "Error: $($cmd.Error)" -ForegroundColor Red
                }
            } elseif ($cmd.Status -eq 'pending') {
                Write-Host "STILL PENDING - Check browser console for poll service" -ForegroundColor Yellow
            }
        } else {
            Write-Host "Command $id not found in history" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "FAILED to fetch history: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Browser Check:" -ForegroundColor Yellow
Write-Host "  1. Open DevTools (F12) > Console" -ForegroundColor White
Write-Host "  2. Look for [DebugPollService] messages" -ForegroundColor White
Write-Host "  3. Check Network tab for poll requests" -ForegroundColor White
