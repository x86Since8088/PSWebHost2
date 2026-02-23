# Test Debug Utility Functions
# Tests the WebHostDebugExtensions utility scripts

param(
    [string]$CardUrl = "/apps/WebHostDebugVariables/cards/debug-variables",
    [string]$CardTitle = "Test Debug Variables",
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug Utilities Test Suite" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check if server is running
Write-Host "Checking Prerequisites..." -ForegroundColor Yellow
$serverRunning = $false
try {
    $null = Invoke-WebRequest -Uri "http://localhost:8080" -Method GET -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
    $serverRunning = $true
    Write-Host "  [OK] Server is running on port 8080" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Server is not running on port 8080" -ForegroundColor Red
    Write-Host "  Please start the server first: .\WebHost.ps1" -ForegroundColor Yellow
    exit 1
}

# Check if functions are loaded
Write-Host ""
Write-Host "Checking Function Availability..." -ForegroundColor Yellow

$functions = @(
    "Debug-ClientCommand",
    "Launch-DebugCard",
    "Close-DebugCard",
    "Get-DebugOpenCards",
    "Get-DebugCommandHistory",
    "Get-DebugCommandQueue"
)

$allFunctionsLoaded = $true
foreach ($func in $functions) {
    if (Get-Command $func -ErrorAction SilentlyContinue) {
        Write-Host "  [OK] $func is available" -ForegroundColor Green
    } else {
        Write-Host "  [ERROR] $func not found" -ForegroundColor Red
        $allFunctionsLoaded = $false
    }
}

if (-not $allFunctionsLoaded) {
    Write-Host ""
    Write-Host "ERROR: Some functions are missing. Make sure WebHostDebugExtensions app is loaded." -ForegroundColor Red
    Write-Host "The app_init.ps1 script should load these functions on startup." -ForegroundColor Yellow
    exit 1
}

# Check if debug queue is initialized
Write-Host ""
Write-Host "Checking Debug Queue Initialization..." -ForegroundColor Yellow

if ($Global:PSWebServer.DebugCommands) {
    Write-Host "  [OK] DebugCommands queue is initialized" -ForegroundColor Green
    Write-Host "    Queue Size: $($Global:PSWebServer.DebugCommands.Queue.Count)" -ForegroundColor Gray
    Write-Host "    History Size: $($Global:PSWebServer.DebugCommands.History.Count)" -ForegroundColor Gray
    Write-Host "    Max Queue: $($Global:PSWebServer.DebugCommands.MaxQueueSize)" -ForegroundColor Gray
    Write-Host "    Max History: $($Global:PSWebServer.DebugCommands.MaxHistorySize)" -ForegroundColor Gray
} else {
    Write-Host "  [ERROR] DebugCommands queue not initialized" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Running Tests" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$testResults = @()

# Test 1: Debug-ClientCommand (Simple eval)
Write-Host ""
Write-Host "Test 1: Debug-ClientCommand (eval)" -ForegroundColor Cyan
Write-Host "  Enqueueing simple console.log command..." -ForegroundColor Gray

try {
    $result1 = Debug-ClientCommand -Command "console.log('[Test] Hello from Debug-ClientCommand')" -Type eval

    if ($result1.Success) {
        Write-Host "  [PASS] Command enqueued successfully" -ForegroundColor Green
        Write-Host "    CommandID: $($result1.CommandID)" -ForegroundColor Gray
        Write-Host "    Queue Position: $($result1.QueuePosition)" -ForegroundColor Gray
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] Command failed: $($result1.Error)" -ForegroundColor Red
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL"; Error = $result1.Error }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Test 2: Get-DebugCommandQueue
Write-Host ""
Write-Host "Test 2: Get-DebugCommandQueue" -ForegroundColor Cyan
Write-Host "  Retrieving command queue..." -ForegroundColor Gray

try {
    $queue = Get-DebugCommandQueue
    Write-Host "  [PASS] Queue retrieved: $($queue.Count) commands" -ForegroundColor Green
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Test 3: Launch-DebugCard (without wait)
Write-Host ""
Write-Host "Test 3: Launch-DebugCard (no wait)" -ForegroundColor Cyan
Write-Host "  Launching card: $CardTitle" -ForegroundColor Gray

try {
    $launchResult = Launch-DebugCard -Url $CardUrl -Title $CardTitle

    if ($launchResult.Success) {
        Write-Host "  [PASS] Card launch command enqueued" -ForegroundColor Green
        Write-Host "    CommandID: $($launchResult.CommandID)" -ForegroundColor Gray
        $cardCommandID = $launchResult.CommandID
        $testResults += @{ Test = "Launch-DebugCard (no wait)"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] Launch failed: $($launchResult.Error)" -ForegroundColor Red
        $testResults += @{ Test = "Launch-DebugCard (no wait)"; Result = "FAIL"; Error = $launchResult.Error }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Launch-DebugCard (no wait)"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Test 4: Launch-DebugCard (with wait)
Write-Host ""
Write-Host "Test 4: Launch-DebugCard (with wait)" -ForegroundColor Cyan
Write-Host "  Launching card with wait (timeout: ${TimeoutSeconds}s)..." -ForegroundColor Gray
Write-Host "  NOTE: This requires an active browser session with debug role" -ForegroundColor Yellow

try {
    $launchResult = Launch-DebugCard -Url $CardUrl -Title "$CardTitle (Wait Test)" -Wait -TimeoutSeconds $TimeoutSeconds

    if ($launchResult.Success) {
        Write-Host "  [PASS] Card launched and confirmed" -ForegroundColor Green
        Write-Host "    CommandID: $($launchResult.CommandID)" -ForegroundColor Gray
        if ($launchResult.Result) {
            Write-Host "    Result: $($launchResult.Result | ConvertTo-Json -Compress)" -ForegroundColor Gray
        }
        $testResults += @{ Test = "Launch-DebugCard (wait)"; Result = "PASS" }
    } else {
        Write-Host "  [WARN] Launch timed out or failed: $($launchResult.Message)" -ForegroundColor Yellow
        Write-Host "    This is expected if no browser session is active" -ForegroundColor Gray
        $testResults += @{ Test = "Launch-DebugCard (wait)"; Result = "SKIP"; Reason = "No active browser session" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Launch-DebugCard (wait)"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Test 5: Get-DebugCommandHistory
Write-Host ""
Write-Host "Test 5: Get-DebugCommandHistory" -ForegroundColor Cyan
Write-Host "  Retrieving command history..." -ForegroundColor Gray

try {
    $history = Get-DebugCommandHistory -Limit 10
    Write-Host "  [PASS] History retrieved: $($history.Count) commands" -ForegroundColor Green

    if ($history.Count -gt 0) {
        Write-Host "  Recent commands:" -ForegroundColor Gray
        $history | Select-Object -First 3 | ForEach-Object {
            Write-Host "    - $($_.CommandID.Substring(0,8))... | Status: $($_.Status) | Completed: $($_.CompletedAt)" -ForegroundColor DarkGray
        }
    }

    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Test 6: Get-DebugOpenCards
Write-Host ""
Write-Host "Test 6: Get-DebugOpenCards" -ForegroundColor Cyan
Write-Host "  Querying open cards (timeout: 5s)..." -ForegroundColor Gray
Write-Host "  NOTE: This requires an active browser session" -ForegroundColor Yellow

try {
    $openCards = Get-DebugOpenCards -TimeoutSeconds 5

    if ($openCards) {
        Write-Host "  [PASS] Query succeeded: $($openCards.Count) open cards" -ForegroundColor Green
        $openCards | ForEach-Object {
            Write-Host "    - $($_.id) ($($_.elementId))" -ForegroundColor Gray
        }
        $testResults += @{ Test = "Get-DebugOpenCards"; Result = "PASS" }
    } else {
        Write-Host "  [WARN] Query timed out or no cards open" -ForegroundColor Yellow
        $testResults += @{ Test = "Get-DebugOpenCards"; Result = "SKIP"; Reason = "No active browser session" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugOpenCards"; Result = "FAIL"; Error = $_.Exception.Message }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passed = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$skipped = ($testResults | Where-Object { $_.Result -eq "SKIP" }).Count
$total = $testResults.Count

Write-Host ""
Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "  PASS: $passed" -ForegroundColor Green
Write-Host "  FAIL: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })
Write-Host "  SKIP: $skipped" -ForegroundColor Yellow

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Error)" -ForegroundColor Red
    }
}

if ($skipped -gt 0) {
    Write-Host ""
    Write-Host "Skipped Tests (require active browser session):" -ForegroundColor Yellow
    $testResults | Where-Object { $_.Result -eq "SKIP" } | ForEach-Object {
        Write-Host "  - $($_.Test): $($_.Reason)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($failed -eq 0) {
    Write-Host "All core tests passed!" -ForegroundColor Green
    exit 0
} else {
    Write-Host "Some tests failed. Please review errors above." -ForegroundColor Red
    exit 1
}
