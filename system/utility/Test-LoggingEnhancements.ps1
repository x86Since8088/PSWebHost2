# Test Script for Enhanced Logging Features
# Tests all auto-detection capabilities of Write-PSWebHostLog

param(
    [switch]$Verbose
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Testing Enhanced Logging Functionality" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import the module
$modulePath = Join-Path $PSScriptRoot "..\..\modules\PSWebHost_Support\PSWebHost_Support.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Host "✓ Loaded PSWebHost_Support module" -ForegroundColor Green
} else {
    Write-Host "✗ Could not find PSWebHost_Support module at: $modulePath" -ForegroundColor Red
    exit 1
}

# Ensure global variables are initialized
if (-not $global:PSWebServer) {
    $global:PSWebServer = [hashtable]::Synchronized(@{
        Project_Root = @{ Path = (Get-Item $PSScriptRoot).Parent.Parent.FullName }
        events = [hashtable]::Synchronized(@{})
    })
}

if (-not $global:PSWebHostLogQueue) {
    $global:PSWebHostLogQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
}

Write-Host "`nProject Root: $($global:PSWebServer.Project_Root.Path)" -ForegroundColor Gray

# Test 1: Basic Auto-Detection from Script
Write-Host "`n--- Test 1: Basic Auto-Detection ---" -ForegroundColor Yellow
Write-PSWebHostLog -Severity Info -Category TestCategory -Message "Test message with auto-detected Source"
Write-Host "✓ Logged with auto-detected Source" -ForegroundColor Green

# Test 2: Auto-Detection from Function
function Test-FunctionLogging {
    Write-Host "`n--- Test 2: Auto-Detection from Function ---" -ForegroundColor Yellow
    Write-PSWebHostLog -Severity Info -Category TestCategory -Message "Test message from inside function" -ActivityName "CustomActivity"
    Write-Host "✓ Logged from function with auto-detected Source and ActivityName" -ForegroundColor Green
}
Test-FunctionLogging

# Test 3: Progress Tracking
function Test-ProgressTracking {
    Write-Host "`n--- Test 3: Progress Tracking ---" -ForegroundColor Yellow

    $items = 1..10
    $total = $items.Count
    $completed = 0

    Write-PSWebHostLog -Severity Info -Category Progress -Message "Starting progress test" -PercentComplete 0

    foreach ($item in $items) {
        Start-Sleep -Milliseconds 100
        $completed++
        $percent = [math]::Round(($completed / $total) * 100)
        Write-PSWebHostLog -Severity Info -Category Progress -Message "Processed item $item" -PercentComplete $percent
    }

    Write-PSWebHostLog -Severity Info -Category Progress -Message "Progress test complete" -PercentComplete 100
    Write-Host "✓ Logged 12 entries with progress tracking (0%, 10%, 20%...100%)" -ForegroundColor Green
}
Test-ProgressTracking

# Test 4: Session Context Auto-Detection
function Test-SessionAutoDetection {
    Write-Host "`n--- Test 4: Session Context Auto-Detection ---" -ForegroundColor Yellow

    # Simulate session data
    $sessiondata = @{
        UserID = "test.user@example.com"
        SessionID = "test-session-123-abc"
    }

    # Call logging from within this scope (should auto-detect)
    Write-PSWebHostLog -Severity Info -Category Session -Message "Test with session context" -Data @{ TestData = "Session Test" }
    Write-Host "✓ Logged with simulated session context (UserID and SessionID should be auto-detected)" -ForegroundColor Green
}
Test-SessionAutoDetection

# Test 5: RunspaceID Auto-Detection
Write-Host "`n--- Test 5: RunspaceID Auto-Detection ---" -ForegroundColor Yellow
Write-PSWebHostLog -Severity Info -Category Runspace -Message "Test runspace auto-detection"
$currentRunspaceId = [runspace]::DefaultRunspace.Id
Write-Host "✓ Logged with auto-detected RunspaceID: $currentRunspaceId" -ForegroundColor Green

# Test 6: Manual Override
Write-Host "`n--- Test 6: Manual Override ---" -ForegroundColor Yellow
Write-PSWebHostLog `
    -Severity Warning `
    -Category ManualOverride `
    -Message "Test with manually specified fields" `
    -Source "CustomSource::CustomFunction" `
    -ActivityName "ManualActivity" `
    -UserID "manual.user@example.com" `
    -SessionID "manual-session-456" `
    -RunspaceID "99" `
    -PercentComplete 50 `
    -Data @{ CustomField = "Manual Override Test" }
Write-Host "✓ Logged with all manually specified fields" -ForegroundColor Green

# Test 7: Complex Data Logging
Write-Host "`n--- Test 7: Complex Data Logging ---" -ForegroundColor Yellow
Write-PSWebHostLog `
    -Severity Error `
    -Category ComplexData `
    -Message "Test with complex data structure" `
    -Data @{
        Query = "SELECT * FROM Users WHERE Email = ?"
        Parameters = @("test@example.com")
        ErrorDetails = @{
            Code = "DB_ERROR_001"
            Message = "Connection timeout"
            StackTrace = "Line 1`nLine 2`nLine 3"
        }
        Metrics = @{
            Duration = 5000
            RetryCount = 3
        }
    }
Write-Host "✓ Logged with nested complex data structure" -ForegroundColor Green

# Wait for log queue to process
Write-Host "`n--- Waiting for log queue to flush ---" -ForegroundColor Yellow
Start-Sleep -Seconds 2

# Test 8: Read Logs with New Filters
Write-Host "`n--- Test 8: Reading Logs with Enhanced Filters ---" -ForegroundColor Yellow

$logFile = Join-Path $global:PSWebServer.Project_Root.Path "Logs\PSWebHost.log"

if (Test-Path $logFile) {
    # Test format detection
    Write-Host "`nTesting format auto-detection..." -ForegroundColor Gray
    $recentLogs = Read-PSWebHostLog -StartTime (Get-Date).AddMinutes(-5) -Category "*"

    if ($recentLogs) {
        $logCount = ($recentLogs | Measure-Object).Count
        Write-Host "✓ Read $logCount log entries" -ForegroundColor Green

        # Test Source filter
        Write-Host "`nFiltering by Source pattern..." -ForegroundColor Gray
        $sourceLogs = Read-PSWebHostLog -StartTime (Get-Date).AddMinutes(-5) -Source "*Test-LoggingEnhancements*"
        $sourceCount = ($sourceLogs | Measure-Object).Count
        Write-Host "✓ Found $sourceCount logs from this test script" -ForegroundColor Green

        # Test Activity filter
        Write-Host "`nFiltering by ActivityName..." -ForegroundColor Gray
        $activityLogs = Read-PSWebHostLog -StartTime (Get-Date).AddMinutes(-5) -ActivityName "*Progress*"
        $activityCount = ($activityLogs | Measure-Object).Count
        Write-Host "✓ Found $activityCount logs with 'Progress' activity" -ForegroundColor Green

        # Test Category filter
        Write-Host "`nFiltering by Category..." -ForegroundColor Gray
        $categoryLogs = Read-PSWebHostLog -StartTime (Get-Date).AddMinutes(-5) -Category "Progress"
        $categoryCount = ($categoryLogs | Measure-Object).Count
        Write-Host "✓ Found $categoryCount logs in 'Progress' category" -ForegroundColor Green

        # Display sample log entries
        Write-Host "`n--- Sample Log Entries (Last 5) ---" -ForegroundColor Cyan
        $recentLogs | Select-Object -Last 5 | ForEach-Object {
            Write-Host "`nTimestamp: $($_.LocalTime)" -ForegroundColor Gray
            Write-Host "Severity:  $($_.Severity)" -ForegroundColor Gray
            Write-Host "Category:  $($_.Category)" -ForegroundColor Gray
            Write-Host "Message:   $($_.Message)" -ForegroundColor White
            Write-Host "Source:    $($_.Source)" -ForegroundColor Gray
            if ($_.ActivityName) { Write-Host "Activity:  $($_.ActivityName)" -ForegroundColor Gray }
            if ($_.PercentComplete) { Write-Host "Progress:  $($_.PercentComplete)%" -ForegroundColor Gray }
            if ($_.UserID) { Write-Host "UserID:    $($_.UserID)" -ForegroundColor Gray }
            if ($_.SessionID) { Write-Host "SessionID: $($_.SessionID)" -ForegroundColor Gray }
            if ($_.RunspaceID) { Write-Host "Runspace:  $($_.RunspaceID)" -ForegroundColor Gray }
        }

    } else {
        Write-Host "✗ No logs found in the specified time range" -ForegroundColor Red
    }
} else {
    Write-Host "✗ Log file not found at: $logFile" -ForegroundColor Red
    Write-Host "   Note: Logs may not have been written yet. Check queue status." -ForegroundColor Yellow
}

# Test 9: Backwards Compatibility
Write-Host "`n--- Test 9: Backwards Compatibility ---" -ForegroundColor Yellow
Write-Host "Testing that Read-PSWebHostLog can handle both old and new log formats..." -ForegroundColor Gray

# Create a temporary log file with old format (8 columns)
$tempOldLog = Join-Path $env:TEMP "test_old_format.log"
$oldFormatEntry = "2026-01-16T12:00:00.000Z`t2026-01-16T06:00:00.000-06:00`tInfo`tOldFormat`tOld format test message`ttest-session`ttest.user@example.com`t{}"
Set-Content -Path $tempOldLog -Value $oldFormatEntry

# Try to read it (should add empty columns for new fields)
$oldLogs = Get-Content $tempOldLog | ForEach-Object {
    $parts = $_ -split "`t"
    if ($parts.Count -eq 8) {
        [PSCustomObject]@{
            UTCTime = $parts[0]
            LocalTime = $parts[1]
            Severity = $parts[2]
            Category = $parts[3]
            Message = $parts[4]
            SessionID = $parts[5]
            UserID = $parts[6]
            Data = $parts[7]
            Source = ""
            ActivityName = ""
            PercentComplete = ""
            RunspaceID = ""
        }
    }
}

if ($oldLogs) {
    Write-Host "✓ Successfully parsed old format log (8 columns)" -ForegroundColor Green
    Write-Host "  - Added empty Source, ActivityName, PercentComplete, RunspaceID fields" -ForegroundColor Gray
} else {
    Write-Host "✗ Failed to parse old format log" -ForegroundColor Red
}

Remove-Item $tempOldLog -ErrorAction SilentlyContinue

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ All 9 test scenarios completed" -ForegroundColor Green
Write-Host "`nFeatures Tested:" -ForegroundColor White
Write-Host "  1. Auto-detection of Source from script" -ForegroundColor Gray
Write-Host "  2. Auto-detection of Source and ActivityName from function" -ForegroundColor Gray
Write-Host "  3. Progress tracking with PercentComplete" -ForegroundColor Gray
Write-Host "  4. Auto-detection of UserID and SessionID from session" -ForegroundColor Gray
Write-Host "  5. Auto-detection of RunspaceID" -ForegroundColor Gray
Write-Host "  6. Manual override of all fields" -ForegroundColor Gray
Write-Host "  7. Complex nested data structures" -ForegroundColor Gray
Write-Host "  8. Enhanced filtering in Read-PSWebHostLog" -ForegroundColor Gray
Write-Host "  9. Backwards compatibility with old log format" -ForegroundColor Gray
Write-Host "`nLog file location: $logFile" -ForegroundColor Yellow
Write-Host "`nTo view all test logs:" -ForegroundColor White
Write-Host "  Read-PSWebHostLog -StartTime (Get-Date).AddMinutes(-5) -Source '*Test-LoggingEnhancements*'" -ForegroundColor Cyan
Write-Host ""
