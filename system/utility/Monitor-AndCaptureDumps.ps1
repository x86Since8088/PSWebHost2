# Monitor-AndCaptureDumps.ps1
# Monitors PowerShell process memory and captures dumps when threshold is exceeded

<#
.SYNOPSIS
    Monitors process memory and captures dumps when threshold is exceeded.

.DESCRIPTION
    This script continuously monitors the PowerShell process memory usage and
    automatically captures memory dumps when the working set exceeds a specified
    threshold. Useful for diagnosing memory leaks in long-running PowerShell
    applications like PSWebHost.

.PARAMETER ThresholdMB
    Memory threshold in MB. When working set exceeds this, a dump is captured.
    Default: 1024 (1GB)

.PARAMETER CheckIntervalSeconds
    How often to check memory usage in seconds.
    Default: 60

.PARAMETER DumpDirectory
    Directory to save dump files.
    Default: C:\SC\PsWebHost\dumps

.PARAMETER MaxDumps
    Maximum number of dumps to capture before stopping.
    Default: 3

.PARAMETER TargetPID
    Process ID to monitor. If not specified, monitors current process.

.EXAMPLE
    .\Monitor-AndCaptureDumps.ps1 -ThresholdMB 512 -CheckIntervalSeconds 30

    Monitor every 30 seconds and capture dump when memory exceeds 512MB.

.EXAMPLE
    .\Monitor-AndCaptureDumps.ps1 -TargetPID 12345 -MaxDumps 1

    Monitor process 12345 and capture only one dump.
#>

[CmdletBinding()]
param(
    [int]$ThresholdMB = 1024,

    [int]$CheckIntervalSeconds = 60,

    [string]$DumpDirectory = "C:\SC\PsWebHost\dumps",

    [int]$MaxDumps = 3,

    [int]$TargetPID = $PID
)

$ErrorActionPreference = 'Stop'

# Create dump directory if it doesn't exist
if (-not (Test-Path $DumpDirectory)) {
    Write-Host "Creating dump directory: $DumpDirectory" -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $DumpDirectory -Force | Out-Null
}

# Check if dotnet-dump is installed
try {
    $dotnetDumpVersion = & dotnet-dump --version 2>&1
    Write-Host "dotnet-dump version: $dotnetDumpVersion" -ForegroundColor Gray
}
catch {
    Write-Host "ERROR: dotnet-dump is not installed!" -ForegroundColor Red
    Write-Host "Install with: dotnet tool install -g dotnet-dump" -ForegroundColor Yellow
    exit 1
}

$dumpCount = 0
$startTime = Get-Date

Write-Host "`n=== Memory Monitoring Started ===" -ForegroundColor Cyan
Write-Host "Target PID:      $TargetPID" -ForegroundColor White
Write-Host "Threshold:       ${ThresholdMB}MB" -ForegroundColor White
Write-Host "Check Interval:  ${CheckIntervalSeconds}s" -ForegroundColor White
Write-Host "Max Dumps:       $MaxDumps" -ForegroundColor White
Write-Host "Dump Directory:  $DumpDirectory" -ForegroundColor White
Write-Host "Started:         $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host "================================`n" -ForegroundColor Cyan

$logPath = Join-Path $DumpDirectory "memory_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
"Timestamp,WorkingSetMB,PrivateMB,GC_MB,Gen0,Gen1,Gen2,Threads,Handles,DumpCaptured" | Out-File -FilePath $logPath -Encoding UTF8

while ($dumpCount -lt $MaxDumps) {
    try {
        $proc = Get-Process -Id $TargetPID -ErrorAction Stop

        $workingSetMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
        $privateMB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
        $gcMB = [math]::Round([GC]::GetTotalMemory($false) / 1MB, 2)
        $gen0 = [GC]::CollectionCount(0)
        $gen1 = [GC]::CollectionCount(1)
        $gen2 = [GC]::CollectionCount(2)
        $threads = $proc.Threads.Count
        $handles = $proc.HandleCount

        $timestamp = Get-Date -Format 'HH:mm:ss'
        $color = if ($workingSetMB -gt ($ThresholdMB * 0.9)) { 'Yellow' } elseif ($workingSetMB -gt $ThresholdMB) { 'Red' } else { 'Gray' }

        Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
        Write-Host "WS: ${workingSetMB}MB | Private: ${privateMB}MB | GC: ${gcMB}MB | Gen0/1/2: $gen0/$gen1/$gen2 | Threads: $threads | Handles: $handles" -ForegroundColor $color

        # Log to CSV
        $dumpCaptured = $false

        # Check threshold
        if ($workingSetMB -gt $ThresholdMB) {
            $dumpPath = Join-Path $DumpDirectory "high_memory_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"

            Write-Host "`n[ALERT] Memory threshold exceeded! Capturing dump..." -ForegroundColor Yellow
            Write-Host "  Working Set: ${workingSetMB}MB (threshold: ${ThresholdMB}MB)" -ForegroundColor Yellow

            try {
                # Capture full dump
                $captureStart = Get-Date
                & dotnet-dump collect -p $TargetPID -o $dumpPath --type Full 2>&1 | Out-Null

                if (Test-Path $dumpPath) {
                    $captureTime = ((Get-Date) - $captureStart).TotalSeconds
                    $dumpSizeMB = [math]::Round((Get-Item $dumpPath).Length / 1MB, 2)

                    Write-Host "✓ Dump captured: $dumpPath" -ForegroundColor Green
                    Write-Host "  Size: ${dumpSizeMB}MB | Time: ${captureTime}s" -ForegroundColor Green

                    $dumpCount++
                    $dumpCaptured = $true

                    # Force GC after dump
                    [GC]::Collect()
                    [GC]::WaitForPendingFinalizers()
                    [GC]::Collect()

                    Write-Host "`n  Forced GC collection. New GC Memory: $([math]::Round([GC]::GetTotalMemory($false) / 1MB, 2))MB" -ForegroundColor Cyan
                    Write-Host "  Captured $dumpCount of $MaxDumps dumps`n" -ForegroundColor Cyan

                    # Wait longer after capturing dump
                    if ($dumpCount -lt $MaxDumps) {
                        Write-Host "  Waiting 5 minutes before resuming monitoring..." -ForegroundColor Gray
                        Start-Sleep -Seconds 300
                    }
                }
                else {
                    Write-Host "✗ Dump file not found after capture attempt" -ForegroundColor Red
                }
            }
            catch {
                Write-Host "✗ Failed to capture dump: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        # Log entry
        "$((Get-Date).ToString('o')),$workingSetMB,$privateMB,$gcMB,$gen0,$gen1,$gen2,$threads,$handles,$dumpCaptured" | Out-File -FilePath $logPath -Encoding UTF8 -Append

        Start-Sleep -Seconds $CheckIntervalSeconds
    }
    catch {
        if ($_.Exception.Message -like "*Cannot find a process*") {
            Write-Host "`n[INFO] Process $TargetPID has ended" -ForegroundColor Yellow
            break
        }
        else {
            Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            break
        }
    }
}

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host "`n=== Monitoring Complete ===" -ForegroundColor Cyan
Write-Host "Duration:        $($duration.ToString('hh\:mm\:ss'))" -ForegroundColor White
Write-Host "Dumps Captured:  $dumpCount" -ForegroundColor White
Write-Host "Log File:        $logPath" -ForegroundColor White
Write-Host "Dump Directory:  $DumpDirectory" -ForegroundColor White
Write-Host "===========================`n" -ForegroundColor Cyan

if ($dumpCount -gt 0) {
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "1. Analyze dumps with: dotnet-dump analyze <dump_file>" -ForegroundColor White
    Write-Host "2. Key commands:" -ForegroundColor White
    Write-Host "   > eeheap -gc" -ForegroundColor Gray
    Write-Host "   > dumpheap -stat" -ForegroundColor Gray
    Write-Host "   > dumpheap -type Hashtable" -ForegroundColor Gray
    Write-Host "   > dumpheap -min 85000" -ForegroundColor Gray
    Write-Host "   > finalizequeue" -ForegroundColor Gray
    Write-Host "   > gchandles`n" -ForegroundColor Gray
}
