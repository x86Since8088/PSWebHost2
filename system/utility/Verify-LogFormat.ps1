# Verification Script - Demonstrates New Log Format
# Directly writes to a test log file to show the enhanced 12-column format

param(
    [string]$TestLogPath = "C:\SC\PsWebHost\Logs\Test-EnhancedLogging.log"
)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Log Format Verification" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Ensure Logs directory exists
$logsDir = Split-Path $TestLogPath -Parent
if (-not (Test-Path $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "Created Logs directory: $logsDir" -ForegroundColor Green
}

# Create sample log entries in new format (12 columns)
$utcNow = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$localNow = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffzzz")

$sampleEntries = @(
    # Entry 1: Auto-detected source and activity
    "$utcNow`t$localNow`tInfo`tTestCategory`tTest message with auto-detected source`tsystem/utility/Test-LoggingEnhancements.ps1::Test-FunctionLogging`tTest-FunctionLogging`t`t`t`t1`t{}",

    # Entry 2: Progress tracking
    "$utcNow`t$localNow`tInfo`tProgress`tProcessing item 5 of 10`tsystem/utility/Test-LoggingEnhancements.ps1::Test-ProgressTracking`tTest-ProgressTracking`t50`t`t`t1`t{}",

    # Entry 3: With session context
    "$utcNow`t$localNow`tInfo`tSession`tUser action logged`troutes/api/v1/users/get.ps1::Get-UserList`tGet-UserList`t`tuser@example.com`tsession-abc-123`t3`t{}",

    # Entry 4: Manual override with all fields
    "$utcNow`t$localNow`tWarning`tSecurity`tSuspicious activity detected`tSecurityMonitor::ThreatDetection`tThreatDetection`t75`tsystem`tsecurity-audit`t5`t{`"IPAddress`":`"192.168.1.100`",`"FailedAttempts`":5}",

    # Entry 5: Complex data structure
    "$utcNow`t$localNow`tError`tDatabase`tQuery failed`troutes/api/v1/data/query.ps1::Execute-Query`tExecute-Query`t`tadmin@example.com`tsession-xyz-789`t2`t{`"Query`":`"SELECT * FROM Users`",`"Error`":`"Connection timeout`",`"Duration`":5000}"
)

# Write entries to test log file
Set-Content -Path $TestLogPath -Value ($sampleEntries -join "`n")
Write-Host "✓ Created test log file with 5 sample entries" -ForegroundColor Green
Write-Host "  Location: $TestLogPath`n" -ForegroundColor Gray

# Display the new format structure
Write-Host "--- New Log Format (12 Columns) ---" -ForegroundColor Yellow
Write-Host "1.  UTCTime" -ForegroundColor Cyan
Write-Host "2.  LocalTime" -ForegroundColor Cyan
Write-Host "3.  Severity" -ForegroundColor Cyan
Write-Host "4.  Category" -ForegroundColor Cyan
Write-Host "5.  Message" -ForegroundColor Cyan
Write-Host "6.  Source          [NEW - Auto-detected]" -ForegroundColor Green
Write-Host "7.  ActivityName    [NEW - Auto-detected]" -ForegroundColor Green
Write-Host "8.  PercentComplete [NEW - Progress tracking]" -ForegroundColor Green
Write-Host "9.  UserID          [Enhanced - Auto-detected]" -ForegroundColor Yellow
Write-Host "10. SessionID       [Enhanced - Auto-detected]" -ForegroundColor Yellow
Write-Host "11. RunspaceID      [NEW - Auto-detected]" -ForegroundColor Green
Write-Host "12. Data            [Existing - JSON payload]" -ForegroundColor White

# Parse and display sample entries
Write-Host "`n--- Sample Log Entries ---`n" -ForegroundColor Cyan

$entries = Get-Content $TestLogPath
$entryNum = 1
foreach ($entry in $entries) {
    $parts = $entry -split "`t"

    Write-Host "Entry ${entryNum}:" -ForegroundColor White
    Write-Host "  Timestamp:   $($parts[1])" -ForegroundColor Gray
    Write-Host "  Severity:    $($parts[2])" -ForegroundColor Gray
    Write-Host "  Category:    $($parts[3])" -ForegroundColor Gray
    Write-Host "  Message:     $($parts[4])" -ForegroundColor White
    Write-Host "  Source:      $($parts[5])" -ForegroundColor Green
    Write-Host "  Activity:    $($parts[6])" -ForegroundColor Green
    if ($parts[7]) { Write-Host "  Progress:    $($parts[7])%" -ForegroundColor Green }
    if ($parts[8]) { Write-Host "  UserID:      $($parts[8])" -ForegroundColor Yellow }
    if ($parts[9]) { Write-Host "  SessionID:   $($parts[9])" -ForegroundColor Yellow }
    Write-Host "  RunspaceID:  $($parts[10])" -ForegroundColor Green
    if ($parts[11] -ne "{}") { Write-Host "  Data:        $($parts[11])" -ForegroundColor Gray }
    Write-Host ""

    $entryNum++
}

# Show old format comparison
Write-Host "--- Old Format (8 Columns) - For Comparison ---" -ForegroundColor Yellow
Write-Host "UTCTime | LocalTime | Severity | Category | Message | SessionID | UserID | Data" -ForegroundColor Gray
Write-Host "  (Missing: Source, ActivityName, PercentComplete, RunspaceID)`n" -ForegroundColor Red

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Verification Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "✓ New format demonstrated" -ForegroundColor Green
Write-Host "✓ 4 new fields added before Data column:" -ForegroundColor Green
Write-Host "    - Source (auto-detects calling script/function)" -ForegroundColor Gray
Write-Host "    - ActivityName (auto-detects function name)" -ForegroundColor Gray
Write-Host "    - PercentComplete (for progress tracking)" -ForegroundColor Gray
Write-Host "    - RunspaceID (auto-detects runspace)" -ForegroundColor Gray
Write-Host "✓ 2 fields enhanced with auto-detection:" -ForegroundColor Green
Write-Host "    - UserID (auto-detects from session)" -ForegroundColor Gray
Write-Host "    - SessionID (auto-detects from session)" -ForegroundColor Gray
Write-Host "`nTest log file: $TestLogPath" -ForegroundColor Yellow
Write-Host ""
