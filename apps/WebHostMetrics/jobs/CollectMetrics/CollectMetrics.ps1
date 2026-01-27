#Requires -Version 7

<#
.SYNOPSIS
    System Metrics Collection

.DESCRIPTION
    Collects CPU, memory, and disk metrics at regular intervals

.PARAMETER Test
    If specified, runs in test mode

.PARAMETER Roles
    User roles (auto-populated from security.json)

.PARAMETER Variables
    Hashtable of variables passed from job initialization
    Expected variables:
    - Interval: Seconds between metric collections (default: 30)
#>

[CmdletBinding()]
param(
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Variables = @{}
)

$MyTag = '[WebHostMetrics:Job:CollectMetrics]'

try {
    # Get interval from variables
    $interval = if ($Variables.ContainsKey('Interval')) {
        [int]$Variables['Interval']
    } else {
        30
    }

    # Test mode: Collect metrics once and exit
    if ($Test) {
        Write-Verbose "$MyTag Running in TEST mode - collecting metrics once"
        Write-Verbose "$MyTag Collection interval: $interval seconds"

        # Collect CPU metrics
        $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
        $cpuUsage = [math]::Round($cpu.Average, 2)

        # Collect memory metrics
        $os = Get-CimInstance Win32_OperatingSystem
        $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
        $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)

        # Collect disk metrics (C: drive)
        $disk = Get-PSDrive C
        $diskTotalGB = [math]::Round($disk.Used / 1GB + $disk.Free / 1GB, 2)
        $diskUsedGB = [math]::Round($disk.Used / 1GB, 2)
        $diskFreeGB = [math]::Round($disk.Free / 1GB, 2)
        $diskUsagePercent = [math]::Round(($diskUsedGB / $diskTotalGB) * 100, 2)

        $metrics = @{
            Timestamp = (Get-Date).ToString('o')
            CPU = @{
                UsagePercent = $cpuUsage
            }
            Memory = @{
                TotalGB = $totalMemoryGB
                UsedGB = $usedMemoryGB
                FreeGB = $freeMemoryGB
                UsagePercent = $memoryUsagePercent
            }
            Disk = @{
                TotalGB = $diskTotalGB
                UsedGB = $diskUsedGB
                FreeGB = $diskFreeGB
                UsagePercent = $diskUsagePercent
            }
        }

        Write-Verbose "$MyTag Metrics collected - CPU: $cpuUsage%, Memory: $memoryUsagePercent%, Disk: $diskUsagePercent%"

        # Output data to stdout (commentary goes to verbose stream)
        return @{
            Success = $true
            Message = "Test completed successfully"
            Metrics = $metrics
        }
    }

    # Normal mode: Continuous metrics collection
    Write-Host "$MyTag Starting metrics collection job..." -ForegroundColor Cyan
    Write-Host "$MyTag Collection interval: $interval seconds" -ForegroundColor Gray
    Write-Host "$MyTag Running in NORMAL mode - continuous collection every $interval seconds" -ForegroundColor Green
    Write-Host "$MyTag Press Ctrl+C to stop (or stop via API)" -ForegroundColor Yellow

    $collectionCount = 0

    while ($true) {
        $collectionCount++

        try {
            # Collect CPU metrics
            $cpu = Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average
            $cpuUsage = [math]::Round($cpu.Average, 2)

            # Collect memory metrics
            $os = Get-CimInstance Win32_OperatingSystem
            $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
            $memoryUsagePercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 2)

            # Collect disk metrics (C: drive)
            $disk = Get-PSDrive C
            $diskTotalGB = [math]::Round($disk.Used / 1GB + $disk.Free / 1GB, 2)
            $diskUsedGB = [math]::Round($disk.Used / 1GB, 2)
            $diskFreeGB = [math]::Round($disk.Free / 1GB, 2)
            $diskUsagePercent = [math]::Round(($diskUsedGB / $diskTotalGB) * 100, 2)

            $timestamp = Get-Date

            # Output metrics (will be captured by job system)
            Write-Host "[$($timestamp.ToString('yyyy-MM-dd HH:mm:ss'))] Collection #$collectionCount" -ForegroundColor Cyan
            Write-Host "  CPU: $cpuUsage% | Memory: $memoryUsagePercent% ($usedMemoryGB/$totalMemoryGB GB) | Disk: $diskUsagePercent% ($diskUsedGB/$diskTotalGB GB)" -ForegroundColor Gray

            # Store metrics in global structure if available
            if ($Global:PSWebServer.Metrics) {
                $Global:PSWebServer.Metrics.Latest = @{
                    Timestamp = $timestamp
                    CPU = @{ UsagePercent = $cpuUsage }
                    Memory = @{
                        TotalGB = $totalMemoryGB
                        UsedGB = $usedMemoryGB
                        FreeGB = $freeMemoryGB
                        UsagePercent = $memoryUsagePercent
                    }
                    Disk = @{
                        TotalGB = $diskTotalGB
                        UsedGB = $diskUsedGB
                        FreeGB = $diskFreeGB
                        UsagePercent = $diskUsagePercent
                    }
                }
            }
        }
        catch {
            Write-Warning "$MyTag Failed to collect metrics: $_"
        }

        # Wait for next interval
        Start-Sleep -Seconds $interval
    }
}
catch {
    Write-Error "$MyTag Job failed: $_"

    if ($Test) {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }

    throw
}
