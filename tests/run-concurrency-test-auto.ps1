<#
.SYNOPSIS
    Automated concurrency test runner with server management

.DESCRIPTION
    This script will:
    1. Check if server is running
    2. Start server if needed (in background)
    3. Run concurrency tests
    4. Report results
#>

param(
    [int]$Port = 8888,
    [string]$SettingsFile = "config\settings.json"
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = Split-Path -Parent $PSScriptRoot

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Automated Concurrency Test Runner" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Check if server is already running
Write-Host "[Step 1] Checking if server is running on port $Port..." -ForegroundColor Yellow
$serverRunning = $false
try {
    $response = Invoke-WebRequest -Uri "http://localhost:$Port" -Method Get -TimeoutSec 2 -ErrorAction Stop
    $serverRunning = $true
    Write-Host "  ✓ Server is already running" -ForegroundColor Green
} catch {
    Write-Host "  ✗ Server is not running" -ForegroundColor Yellow
}

# Step 2: Start server if needed
$serverJob = $null
if (-not $serverRunning) {
    Write-Host "`n[Step 2] Starting server in background..." -ForegroundColor Yellow

    $serverJob = Start-Job -ScriptBlock {
        param($ProjectRoot, $Port)
        Set-Location $ProjectRoot
        & "$ProjectRoot\WebHost.ps1" -Async -Port $Port
    } -ArgumentList $ProjectRoot, $Port

    Write-Host "  Server job started (JobId: $($serverJob.Id))" -ForegroundColor Gray
    Write-Host "  Waiting for server to initialize..." -ForegroundColor Gray

    # Wait for server to be ready (max 30 seconds)
    $timeout = 30
    $elapsed = 0
    while ($elapsed -lt $timeout -and -not $serverRunning) {
        Start-Sleep -Seconds 1
        $elapsed++

        try {
            $response = Invoke-WebRequest -Uri "http://localhost:$Port" -Method Get -TimeoutSec 1 -ErrorAction Stop
            $serverRunning = $true
            Write-Host "  ✓ Server is ready (took $elapsed seconds)" -ForegroundColor Green
            break
        } catch {
            # Still starting up
            if ($elapsed % 5 -eq 0) {
                Write-Host "  Still waiting... ($elapsed/$timeout seconds)" -ForegroundColor Gray
            }
        }
    }

    if (-not $serverRunning) {
        Write-Host "  ✗ Server failed to start within $timeout seconds" -ForegroundColor Red
        if ($serverJob) {
            $serverJob | Stop-Job
            $serverJob | Remove-Job -Force
        }
        exit 1
    }
} else {
    Write-Host "`n[Step 2] Skipping server start (already running)" -ForegroundColor Gray
}

# Step 3: Get API key for authentication
Write-Host "`n[Step 3] Getting authentication credentials..." -ForegroundColor Yellow
$apiKey = $null

# Try to get API key from settings.json
$settingsPath = Join-Path $ProjectRoot $SettingsFile
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath | ConvertFrom-Json
        # Use localhost_admin key for testing
        if ($settings.ApiKeys.localhost_admin) {
            $apiKey = $settings.ApiKeys.localhost_admin.key
            Write-Host "  ✓ Found localhost_admin API key" -ForegroundColor Green
        } elseif ($settings.ApiKeys.global_read) {
            $apiKey = $settings.ApiKeys.global_read.key
            Write-Host "  ✓ Found global_read API key" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ✗ Could not parse settings.json: $($_.Exception.Message)" -ForegroundColor Red
    }
}

if (-not $apiKey) {
    Write-Host "  ✗ No API key found in settings.json" -ForegroundColor Red
    Write-Host "  Please provide an API key" -ForegroundColor Yellow
    Write-Host ""
    $apiKey = Read-Host "Enter API key (or press Enter to skip)"
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Host "  ⚠ Continuing without authentication (tests may fail)" -ForegroundColor Yellow
    }
}

# Step 4: Run concurrency tests
Write-Host "`n[Step 4] Running concurrency tests..." -ForegroundColor Yellow

$testScript = Join-Path $ProjectRoot "tests\manual-concurrency-test.ps1"
if (-not (Test-Path $testScript)) {
    Write-Host "  ✗ Test script not found: $testScript" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "========================================"
Write-Host ""

# Run the test script
$testParams = @{
    Port = $Port
}
if ($apiKey) {
    $testParams.ApiKey = $apiKey
}

try {
    & $testScript @testParams
    $testExitCode = $LASTEXITCODE
} catch {
    Write-Host "Test execution failed: $($_.Exception.Message)" -ForegroundColor Red
    $testExitCode = 1
}

# Step 5: Cleanup
Write-Host "`n[Step 5] Cleanup..." -ForegroundColor Yellow
if ($serverJob) {
    Write-Host "  Stopping server job..." -ForegroundColor Gray
    $serverJob | Stop-Job
    $serverJob | Remove-Job -Force
    Write-Host "  ✓ Server stopped" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Complete" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

exit $testExitCode
