# Simple debug command test
$ErrorActionPreference = 'Continue'

Write-Host "=== Testing Debug Command Execution ===" -ForegroundColor Cyan

# Load WebHost environment
$ProjectRoot = $PSScriptRoot
. (Join-Path $ProjectRoot "WebHost.ps1") -InitializeEnvironmentOnly | Out-Null

$dbFile = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost.db"

# Get most recent API key
$apiKeys = Get-PSWebSQLiteData -File $dbFile -Query "SELECT APIKey, Name FROM API_Keys ORDER BY CreatedAt DESC LIMIT 1"

if (-not $apiKeys) {
    Write-Host "No API keys found in database" -ForegroundColor Red
    exit 1
}

$token = $apiKeys.APIKey
Write-Host "Using API key: $($apiKeys.Name)" -ForegroundColor Green

# Test 1: Console log command
Write-Host ""
Write-Host "Test 1: Sending console.log command" -ForegroundColor Yellow

$body1 = @{
    Command = 'console.log("Hello from PowerShell!")'
    Type = 'eval'
} | ConvertTo-Json

try {
    $result1 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' -Method POST -Headers @{ Authorization = "Bearer $token" } -Body $body1 -ContentType 'application/json'
    Write-Host "Command queued: $($result1.commandID)" -ForegroundColor Green
    $cmdId1 = $result1.commandID
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Get window location
Write-Host ""
Write-Host "Test 2: Getting window.location" -ForegroundColor Yellow

$body2 = @{
    Command = 'JSON.stringify(window.location)'
    Type = 'eval'
} | ConvertTo-Json

try {
    $result2 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' -Method POST -Headers @{ Authorization = "Bearer $token" } -Body $body2 -ContentType 'application/json'
    Write-Host "Command queued: $($result2.commandID)" -ForegroundColor Green
    $cmdId2 = $result2.commandID
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Open card
Write-Host ""
Write-Host "Test 3: Opening debug-variables card" -ForegroundColor Yellow

$body3 = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Test from PowerShell'
    }
} | ConvertTo-Json

try {
    $result3 = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' -Method POST -Headers @{ Authorization = "Bearer $token" } -Body $body3 -ContentType 'application/json'
    Write-Host "Command queued: $($result3.commandID)" -ForegroundColor Green
    $cmdId3 = $result3.commandID
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}

# Wait for execution
Write-Host ""
Write-Host "Waiting 5 seconds for commands to execute..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Check results
Write-Host ""
Write-Host "Checking command results..." -ForegroundColor Yellow

try {
    $history = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=10" -Headers @{ Authorization = "Bearer $token" }

    foreach ($id in @($cmdId1, $cmdId2, $cmdId3)) {
        if ($id) {
            $cmd = $history | Where-Object { $_.CommandID -eq $id } | Select-Object -First 1
            if ($cmd) {
                Write-Host ""
                Write-Host "Command: $($cmd.Command)" -ForegroundColor Cyan
                Write-Host "Status: $($cmd.Status)" -ForegroundColor $(if ($cmd.Status -eq 'completed') { 'Green' } else { 'Yellow' })
                if ($cmd.Result) {
                    Write-Host "Result: $($cmd.Result)" -ForegroundColor White
                }
                if ($cmd.Error) {
                    Write-Host "Error: $($cmd.Error)" -ForegroundColor Red
                }
            }
        }
    }
} catch {
    Write-Host "ERROR fetching history: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Test Complete ===" -ForegroundColor Cyan
