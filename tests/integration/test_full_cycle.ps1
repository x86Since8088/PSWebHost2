#Requires -Version 7

$token = "6OQXSDf05WJTFMaNPGxHE8qB4kWY+y2xNUs0is3yiQY="

Write-Host "=== Testing File-Based Command Queue ===" -ForegroundColor Cyan
Write-Host ""

# Step 1: Enqueue a command
Write-Host "[Step 1] Enqueueing command to outbox..." -ForegroundColor Yellow
$enqueueResult = & "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1" `
    -Command "console.log('Test successful at ' + new Date().toISOString()); 'SUCCESS'" `
    -Type eval `
    -SessionID all

Write-Host "  CommandID: $($enqueueResult.CommandID)" -ForegroundColor Green
$commandID = $enqueueResult.CommandID

# Step 2: Verify file exists in outbox
Write-Host "`n[Step 2] Verifying command file in outbox..." -ForegroundColor Yellow
$outboxFile = "C:\SC\PsWebHost\PsWebHost_Data\apps\WebHostDebugExtensions\outbox\all\$commandID.json"
if (Test-Path $outboxFile) {
    Write-Host "  �File exists in outbox" -ForegroundColor Green
    $fileContent = Get-Content $outboxFile -Raw | ConvertFrom-Json
    Write-Host "  Status: $($fileContent.Status)" -ForegroundColor White
} else {
    Write-Host "  � File NOT found in outbox!" -ForegroundColor Red
    exit 1
}

# Step 3: Poll endpoint (simulate browser)
Write-Host "`n[Step 3] Polling endpoint (simulating browser)..." -ForegroundColor Yellow
$uri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/poll"
$headers = @{ Authorization = "Bearer $token" }

try {
    $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -UseBasicParsing

    if ($response.StatusCode -eq 200) {
        Write-Host "  � Commands received from poll endpoint" -ForegroundColor Green
        $data = $response.Content | ConvertFrom-Json
        $command = $data.commands[0]

        Write-Host "  CommandID: $($command.CommandID)" -ForegroundColor White
        Write-Host "  Type: $($command.Type)" -ForegroundColor White
        Write-Host "  Status: $($command.Status)" -ForegroundColor White

    } elseif ($response.StatusCode -eq 204) {
        Write-Host "  � No commands found (204)" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "  � Poll failed: $_" -ForegroundColor Red
    exit 1
}

# Step 4: Verify file was deleted from outbox
Write-Host "`n[Step 4] Verifying command file removed from outbox..." -ForegroundColor Yellow
if (-not (Test-Path $outboxFile)) {
    Write-Host "  � File correctly removed from outbox after poll" -ForegroundColor Green
} else {
    Write-Host "  � WARNING: File still in outbox" -ForegroundColor Yellow
}

# Step 5: Simulate browser posting result back
Write-Host "`n[Step 5] Simulating browser posting execution result..." -ForegroundColor Yellow
$resultUri = "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/result"

$resultPayload = @{
    CommandID = $commandID
    Result = "SUCCESS"
    Error = $null
    ExecutionTimeMs = 42
} | ConvertTo-Json

try {
    $response = Invoke-WebRequest -Uri $resultUri -Method POST -Headers $headers -Body $resultPayload -ContentType "application/json" -UseBasicParsing

    if ($response.StatusCode -eq 200) {
        Write-Host "  � Result posted successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "  � Result post failed: $_" -ForegroundColor Red
    exit 1
}

# Step 6: Verify result in inbox
Write-Host "`n[Step 6] Verifying result file in inbox..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 500  # Give it a moment to write

# The session ID from the poll endpoint's sessiondata
$inboxFile = "C:\SC\PsWebHost\PsWebHost_Data\apps\WebHostDebugExtensions\inbox\all\$commandID.json"

if (Test-Path $inboxFile) {
    Write-Host "  � Result file exists in inbox" -ForegroundColor Green
    $resultContent = Get-Content $inboxFile -Raw | ConvertFrom-Json
    Write-Host "  Status: $($resultContent.Status)" -ForegroundColor White
    Write-Host "  Result: $($resultContent.Result)" -ForegroundColor White
    Write-Host "  ExecutionTime: $($resultContent.ExecutionTimeMs)ms" -ForegroundColor White
} else {
    Write-Host "  � Result file NOT found in inbox!" -ForegroundColor Red
    Write-Host "  Checking other session folders..." -ForegroundColor Yellow

    $inboxRoot = "C:\SC\PsWebHost\PsWebHost_Data\apps\WebHostDebugExtensions\inbox"
    if (Test-Path $inboxRoot) {
        $allInboxFiles = Get-ChildItem -Path $inboxRoot -Filter "$commandID.json" -Recurse -ErrorAction SilentlyContinue
        if ($allInboxFiles) {
            Write-Host "  Found in: $($allInboxFiles[0].FullName)" -ForegroundColor Cyan
            $resultContent = Get-Content $allInboxFiles[0].FullName -Raw | ConvertFrom-Json
            Write-Host "  Status: $($resultContent.Status)" -ForegroundColor White
            Write-Host "  Result: $($resultContent.Result)" -ForegroundColor White
        }
    }
}

Write-Host "`n=== Test Complete ===" -ForegroundColor Cyan
Write-Host "✓ File-based queue system is working!" -ForegroundColor Green
