#Requires -Version 7

<#
.SYNOPSIS
    Diagnose browser connection issues
#>

$MyTag = '[Browser-Diagnostics]'
$EnqueueScript = "..\..\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n$MyTag ================================" -ForegroundColor Cyan
Write-Host "$MyTag Browser Connection Diagnostics" -ForegroundColor Cyan
Write-Host "$MyTag ================================" -ForegroundColor Cyan
Write-Host ""

# Test 1: Check if command files are being picked up
Write-Host "$MyTag [Test 1] Checking if commands are picked up..." -ForegroundColor Yellow

$testCmd = [guid]::NewGuid().ToString()
$commandFile = "PsWebHost_Data\apps\WebHostDebugExtensions\outbox\all\test-$testCmd.json"

@{
    CommandID = "test-$testCmd"
    SessionID = "all"
    Type = "eval"
    Command = "console.log('Test command')"
    Status = "pending"
    EnqueuedAt = (Get-Date).ToString('o')
} | ConvertTo-Json | Out-File -FilePath $commandFile -Encoding UTF8

Write-Host "$MyTag   Created test command file" -ForegroundColor Gray

Start-Sleep -Seconds 5

if (Test-Path $commandFile) {
    Write-Host "$MyTag   ✗ Command file still exists - NOT being picked up" -ForegroundColor Red
    Write-Host "$MyTag   This means browser is NOT polling or poll endpoint is broken" -ForegroundColor Red
    Remove-Item $commandFile -Force
} else {
    Write-Host "$MyTag   ✓ Command file was deleted - browser IS polling" -ForegroundColor Green
}

Write-Host ""

# Test 2: Send simple eval and check inbox
Write-Host "$MyTag [Test 2] Testing simple eval command..." -ForegroundColor Yellow

$result = & $EnqueueScript `
    -Command "2+2" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10 `
    -Verbose

if ($result.Success) {
    Write-Host "$MyTag   ✓ Command executed successfully" -ForegroundColor Green
    Write-Host "$MyTag     Result: $($result.Result)" -ForegroundColor Green
} else {
    Write-Host "$MyTag   ✗ Command failed or timed out" -ForegroundColor Red
    Write-Host "$MyTag     Message: $($result.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 3: Check result endpoint directly
Write-Host "$MyTag [Test 3] Checking result endpoint..." -ForegroundColor Yellow

$testResultPath = "PsWebHost_Data\apps\WebHostDebugExtensions\inbox\test-result-[guid]::NewGuid().ToString()}.json"

try {
    @{
        CommandID = "test-manual"
        Status = "completed"
        Result = "test"
    } | ConvertTo-Json | Out-File -FilePath "PsWebHost_Data\apps\WebHostDebugExtensions\inbox\test-manual.json" -Encoding UTF8 -Force

    if (Test-Path "PsWebHost_Data\apps\WebHostDebugExtensions\inbox\test-manual.json") {
        Write-Host "$MyTag   ✓ Can write to inbox folder" -ForegroundColor Green
        Remove-Item "PsWebHost_Data\apps\WebHostDebugExtensions\inbox\test-manual.json" -Force
    }
} catch {
    Write-Host "$MyTag   ✗ Cannot write to inbox folder: $_" -ForegroundColor Red
}

Write-Host ""

# Test 4: Check for stuck commands
Write-Host "$MyTag [Test 4] Checking for stuck commands..." -ForegroundColor Yellow

$outboxFiles = Get-ChildItem "PsWebHost_Data\apps\WebHostDebugExtensions\outbox" -Recurse -File -ErrorAction SilentlyContinue
$inboxFiles = Get-ChildItem "PsWebHost_Data\apps\WebHostDebugExtensions\inbox" -Recurse -File -ErrorAction SilentlyContinue

Write-Host "$MyTag   Outbox files: $($outboxFiles.Count)" -ForegroundColor Gray
Write-Host "$MyTag   Inbox files: $($inboxFiles.Count)" -ForegroundColor Gray

if ($outboxFiles.Count -gt 0) {
    Write-Host "$MyTag   ⚠ Stuck commands in outbox:" -ForegroundColor Yellow
    $outboxFiles | ForEach-Object {
        $age = (Get-Date) - $_.LastWriteTime
        Write-Host "$MyTag     - $($_.Name) (age: $([math]::Round($age.TotalSeconds, 0))s)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "$MyTag ================================" -ForegroundColor Cyan
Write-Host "$MyTag Diagnostic Summary" -ForegroundColor Cyan
Write-Host "$MyTag ================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "$MyTag ISSUE: Browser is picking up commands but NOT returning results" -ForegroundColor Red
Write-Host ""
Write-Host "$MyTag Possible causes:" -ForegroundColor Yellow
Write-Host "$MyTag   1. Browser console has JavaScript errors" -ForegroundColor Gray
Write-Host "$MyTag   2. Result POST endpoint is failing (auth/permissions)" -ForegroundColor Gray
Write-Host "$MyTag   3. Browser lost authentication token" -ForegroundColor Gray
Write-Host "$MyTag   4. Commands.js not loaded properly" -ForegroundColor Gray
Write-Host "$MyTag   5. Network/fetch errors preventing POST" -ForegroundColor Gray
Write-Host ""
Write-Host "$MyTag Next steps:" -ForegroundColor Yellow
Write-Host "$MyTag   1. Open browser and check console for errors" -ForegroundColor Gray
Write-Host "$MyTag   2. Verify user is still logged in" -ForegroundColor Gray
Write-Host "$MyTag   3. Check if result POST endpoint is accessible" -ForegroundColor Gray
Write-Host "$MyTag   4. Refresh browser page to reset state" -ForegroundColor Gray
Write-Host ""
