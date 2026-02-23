# Test Debug Utility Functions (Standalone)
# This version manually loads functions for testing

param(
    [string]$CardUrl = "/apps/WebHostDebugVariables/cards/debug-variables",
    [string]$CardTitle = "Test Debug Variables",
    [int]$TimeoutSeconds = 15
)

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Debug Utilities Test (Standalone)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Load WebHost environment
Write-Host "Loading WebHost environment..." -ForegroundColor Yellow
$ProjectRoot = $PSScriptRoot

try {
    . (Join-Path $ProjectRoot "WebHost.ps1") -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null
    Write-Host "  [OK] WebHost environment loaded" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Failed to load WebHost: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Manually load WebHostDebugExtensions app
Write-Host "Loading WebHostDebugExtensions..." -ForegroundColor Yellow
$appPath = Join-Path $ProjectRoot "apps\WebHostDebugExtensions"
$appInitPath = Join-Path $appPath "app_init.ps1"

if (Test-Path $appInitPath) {
    try {
        & $appInitPath -PSWebServer $Global:PSWebServer -AppRoot $appPath
        Write-Host "  [OK] WebHostDebugExtensions loaded" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] Failed to load app: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "  [ERROR] app_init.ps1 not found at: $appInitPath" -ForegroundColor Red
    exit 1
}

# Check if server is running
Write-Host ""
Write-Host "Checking Prerequisites..." -ForegroundColor Yellow
try {
    $null = Invoke-WebRequest -Uri "http://localhost:8080" -Method GET -TimeoutSec 2 -UseBasicParsing -ErrorAction SilentlyContinue
    Write-Host "  [OK] Server is running on port 8080" -ForegroundColor Green
} catch {
    Write-Host "  [WARNING] Server might not be running" -ForegroundColor Yellow
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
    Write-Host "ERROR: Some functions are missing." -ForegroundColor Red
    exit 1
}

# Check if debug queue is initialized
Write-Host ""
Write-Host "Checking Debug Queue Initialization..." -ForegroundColor Yellow

if ($Global:PSWebServer.DebugCommands) {
    Write-Host "  [OK] DebugCommands queue is initialized" -ForegroundColor Green
    Write-Host "    Queue Size: $($Global:PSWebServer.DebugCommands.Queue.Count)" -ForegroundColor Gray
    Write-Host "    History Size: $($Global:PSWebServer.DebugCommands.History.Count)" -ForegroundColor Gray
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

try {
    $result1 = Debug-ClientCommand -Command "console.log('[Test] Hello from test')" -Type eval

    if ($result1.Success) {
        Write-Host "  [PASS] Command enqueued" -ForegroundColor Green
        Write-Host "    CommandID: $($result1.CommandID)" -ForegroundColor Gray
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] $($result1.Error)" -ForegroundColor Red
        $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Debug-ClientCommand"; Result = "FAIL" }
}

# Test 2: Get-DebugCommandQueue
Write-Host ""
Write-Host "Test 2: Get-DebugCommandQueue" -ForegroundColor Cyan

try {
    $queue = Get-DebugCommandQueue
    Write-Host "  [PASS] Queue retrieved: $($queue.Count) commands" -ForegroundColor Green
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandQueue"; Result = "FAIL" }
}

# Test 3: Get-DebugCommandHistory
Write-Host ""
Write-Host "Test 3: Get-DebugCommandHistory" -ForegroundColor Cyan

try {
    $history = Get-DebugCommandHistory -Limit 5
    Write-Host "  [PASS] History retrieved: $($history.Count) commands" -ForegroundColor Green
    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "PASS" }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Get-DebugCommandHistory"; Result = "FAIL" }
}

# Test 4: Launch-DebugCard (no wait)
Write-Host ""
Write-Host "Test 4: Launch-DebugCard (no wait)" -ForegroundColor Cyan

try {
    $launchResult = Launch-DebugCard -Url $CardUrl -Title $CardTitle

    if ($launchResult.Success) {
        Write-Host "  [PASS] Card launch command enqueued" -ForegroundColor Green
        Write-Host "    CommandID: $($launchResult.CommandID)" -ForegroundColor Gray
        $testResults += @{ Test = "Launch-DebugCard"; Result = "PASS" }
    } else {
        Write-Host "  [FAIL] $($launchResult.Error)" -ForegroundColor Red
        $testResults += @{ Test = "Launch-DebugCard"; Result = "FAIL" }
    }
} catch {
    Write-Host "  [FAIL] Exception: $($_.Exception.Message)" -ForegroundColor Red
    $testResults += @{ Test = "Launch-DebugCard"; Result = "FAIL" }
}

# Summary
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$passed = ($testResults | Where-Object { $_.Result -eq "PASS" }).Count
$failed = ($testResults | Where-Object { $_.Result -eq "FAIL" }).Count
$total = $testResults.Count

Write-Host ""
Write-Host "Total Tests: $total" -ForegroundColor White
Write-Host "  PASS: $passed" -ForegroundColor Green
Write-Host "  FAIL: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Gray" })

if ($failed -eq 0) {
    Write-Host ""
    Write-Host "All tests passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Queue Status:" -ForegroundColor Cyan
    Write-Host "  Pending: $($Global:PSWebServer.DebugCommands.Queue.Count)" -ForegroundColor Yellow
    Write-Host "  Completed: $($Global:PSWebServer.DebugCommands.History.Count)" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-Host ""
    Write-Host "Some tests failed." -ForegroundColor Red
    exit 1
}
