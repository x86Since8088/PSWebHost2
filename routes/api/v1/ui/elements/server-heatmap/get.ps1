
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Cache configuration - cache results for 5 seconds to prevent repeated expensive queries
$script:CacheDuration = 5
if (-not $script:CachedStats) {
    $script:CachedStats = @{
        timestamp = [datetime]::MinValue
        data = $null
    }
}

# Timeout tracking - skip operations that have timed out recently
$script:SkipDuration = 30
if (-not $script:TimedOutOperations) {
    $script:TimedOutOperations = @{}
}

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Helper function to check if operation should be skipped
function Test-ShouldSkipOperation {
    param([string]$OperationName)

    if ($script:TimedOutOperations.ContainsKey($OperationName)) {
        $timeSinceTimeout = ((Get-Date) - $script:TimedOutOperations[$OperationName]).TotalSeconds
        if ($timeSinceTimeout -lt $script:SkipDuration) {
            $remainingSkip = [math]::Round($script:SkipDuration - $timeSinceTimeout, 1)
            Write-Verbose "[ServerHeatmap] Skipping '$OperationName' (timed out recently, retry in ${remainingSkip}s)"
            return $true
        } else {
            # Enough time has passed, remove from skip list
            $script:TimedOutOperations.Remove($OperationName)
            Write-Verbose "[ServerHeatmap] Retry timeout period expired for '$OperationName', attempting again"
            return $false
        }
    }
    return $false
}

# Helper function to run command with timeout
function Invoke-WithTimeout {
    param(
        [scriptblock]$ScriptBlock,
        [int]$TimeoutSeconds = 3,
        $DefaultValue = $null,
        [string]$OperationName = "Unknown Operation"
    )

    try {
        $job = Start-Job -ScriptBlock $ScriptBlock
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds

        if ($completed) {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force

            # Operation succeeded, remove from timeout tracking if it was there
            if ($script:TimedOutOperations.ContainsKey($OperationName)) {
                $script:TimedOutOperations.Remove($OperationName)
                Write-Verbose "[ServerHeatmap] Operation '$OperationName' succeeded (previously timed out)"
            }

            return $result
        } else {
            Stop-Job -Job $job
            Remove-Job -Job $job -Force

            # Track this timeout
            $script:TimedOutOperations[$OperationName] = Get-Date
            Write-Verbose "[ServerHeatmap] TIMEOUT: Operation '$OperationName' timed out after $TimeoutSeconds seconds. Will skip for $script:SkipDuration seconds."

            return $DefaultValue
        }
    } catch {
        # Track this failure
        $script:TimedOutOperations[$OperationName] = Get-Date
        Write-Verbose "[ServerHeatmap] ERROR: Operation '$OperationName' failed with error: $($_.Exception.Message). Will skip for $script:SkipDuration seconds."

        return $DefaultValue
    }
}

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Authentication required'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

# Check cache
$cacheAge = ((Get-Date) - $script:CachedStats.timestamp).TotalSeconds
if ($cacheAge -lt $script:CacheDuration -and $script:CachedStats.data) {
    Write-Verbose "[ServerHeatmap] Returning cached data (age: $([math]::Round($cacheAge, 1))s)"
    $jsonResponse = $script:CachedStats.data | ConvertTo-Json -Depth 10 -Compress
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Collect real system statistics
    $systemStats = @{
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        hostname = $env:COMPUTERNAME
        metrics = @{}
        cached = $false
    }

    # CPU Usage (per logical processor) - with timeout
    if (-not (Test-ShouldSkipOperation -OperationName "CPU_Counters")) {
        $cpuCounters = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "CPU_Counters" -ScriptBlock {
            Get-Counter -Counter '\Processor(*)\% Processor Time' -ErrorAction Stop
        }

        if ($cpuCounters) {
            $cpuData = @($cpuCounters.CounterSamples | Where-Object { $_.InstanceName -ne '_total' } | ForEach-Object {
                @{
                    name = "CPU $($_.InstanceName)"
                    value = [math]::Round($_.CookedValue, 1)
                    unit = "%"
                    type = "cpu"
                }
            })
            $systemStats.metrics.cpu = $cpuData
        } else {
            $systemStats.metrics.cpu = @(@{
                name = "CPU Status"
                value = "Error"
                unit = ""
                type = "cpu"
            })
        }
    } else {
        $systemStats.metrics.cpu = @(@{
            name = "CPU Status"
            value = "Error"
            unit = ""
            type = "cpu"
        })
    }

    # Memory Usage - with timeout
    if (-not (Test-ShouldSkipOperation -OperationName "Memory_Query")) {
        $os = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "Memory_Query" -ScriptBlock {
            Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        }

        if ($os) {
            $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
            $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
            $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
            $memoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1)

            $systemStats.metrics.memory = @{
                total = $totalMemoryGB
                used = $usedMemoryGB
                free = $freeMemoryGB
                percentUsed = $memoryPercent
                unit = "GB"
                type = "memory"
            }
        } else {
            $systemStats.metrics.memory = @{
                total = "Error"
                used = "Error"
                free = "Error"
                percentUsed = "Error"
                unit = "GB"
                type = "memory"
            }
        }
    } else {
        $systemStats.metrics.memory = @{
            total = "Error"
            used = "Error"
            free = "Error"
            percentUsed = "Error"
            unit = "GB"
            type = "memory"
        }
    }

    # Disk Usage (all drives) - with timeout
    if (-not (Test-ShouldSkipOperation -OperationName "Disk_Query")) {
        $drives = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "Disk_Query" -ScriptBlock {
            Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        }

        if ($drives) {
            $diskData = @($drives | ForEach-Object {
                $totalGB = [math]::Round($_.Size / 1GB, 2)
                $freeGB = [math]::Round($_.FreeSpace / 1GB, 2)
                $usedGB = [math]::Round($totalGB - $freeGB, 2)
                $percentUsed = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

                @{
                    name = "$($_.DeviceID)"
                    total = $totalGB
                    used = $usedGB
                    free = $freeGB
                    percentUsed = $percentUsed
                    unit = "GB"
                    type = "disk"
                }
            })
            $systemStats.metrics.disk = $diskData
        } else {
            $systemStats.metrics.disk = @(@{
                name = "Disk Status"
                total = "Error"
                used = "Error"
                free = "Error"
                percentUsed = "Error"
                unit = "GB"
                type = "disk"
            })
        }
    } else {
        $systemStats.metrics.disk = @(@{
            name = "Disk Status"
            total = "Error"
            used = "Error"
            free = "Error"
            percentUsed = "Error"
            unit = "GB"
            type = "disk"
        })
    }

    # Network Interfaces - with timeout
    if (-not (Test-ShouldSkipOperation -OperationName "Network_Counters")) {
        $netCounters = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "Network_Counters" -ScriptBlock {
            Get-Counter -Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction Stop
        }

        if ($netCounters) {
            $netData = @($netCounters.CounterSamples | Where-Object {
                $_.InstanceName -notmatch 'Loopback|isatap'
            } | ForEach-Object {
                $bytesPerSec = [math]::Round($_.CookedValue / 1KB, 1)
                @{
                    name = $_.InstanceName
                    value = $bytesPerSec
                    unit = "KB/s"
                    type = "network"
                }
            })
            $systemStats.metrics.network = $netData
        } else {
            $systemStats.metrics.network = @(@{
                name = "Network Status"
                value = "Error"
                unit = ""
                type = "network"
            })
        }
    } else {
        $systemStats.metrics.network = @(@{
            name = "Network Status"
            value = "Error"
            unit = ""
            type = "network"
        })
    }

    # Top Processes by CPU - optimized to avoid timeout
    $topProcessesCPU = @(Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CPU -gt 0 } |
        Sort-Object CPU -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            @{
                name = $_.ProcessName
                cpu = [math]::Round($_.CPU, 2)
                memory = [math]::Round($_.WorkingSet64 / 1MB, 1)
                id = $_.Id
                type = "process"
            }
        })
    $systemStats.metrics.topProcessesCPU = $topProcessesCPU

    # Top Processes by Memory - optimized
    $topProcessesMem = @(Get-Process -ErrorAction SilentlyContinue |
        Sort-Object WorkingSet64 -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            @{
                name = $_.ProcessName
                memory = [math]::Round($_.WorkingSet64 / 1MB, 1)
                cpu = [math]::Round($_.CPU, 2)
                id = $_.Id
                type = "process"
            }
        })
    $systemStats.metrics.topProcessesMem = $topProcessesMem

    # System Uptime - with timeout
    if (-not (Test-ShouldSkipOperation -OperationName "Uptime_Query")) {
        $bootTime = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "Uptime_Query" -ScriptBlock {
            (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
        }

        if ($bootTime) {
            $uptime = (Get-Date) - $bootTime
            $systemStats.metrics.uptime = @{
                days = $uptime.Days
                hours = $uptime.Hours
                minutes = $uptime.Minutes
                totalHours = [math]::Round($uptime.TotalHours, 1)
                type = "uptime"
            }
        } else {
            $systemStats.metrics.uptime = @{
                days = "Error"
                hours = "Error"
                minutes = "Error"
                totalHours = "Error"
                type = "uptime"
            }
        }
    } else {
        $systemStats.metrics.uptime = @{
            days = "Error"
            hours = "Error"
            minutes = "Error"
            totalHours = "Error"
            type = "uptime"
        }
    }

    # Thread and Handle Count - OPTIMIZED: Use WMI performance counter instead of enumerating all threads
    # This is much faster than accessing .Threads.Count on every process
    $allProcesses = Get-Process -ErrorAction SilentlyContinue

    # Use performance counter for thread count (much faster)
    if (-not (Test-ShouldSkipOperation -OperationName "Thread_Count")) {
        $threadCount = Invoke-WithTimeout -TimeoutSeconds 2 -OperationName "Thread_Count" -ScriptBlock {
            (Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop |
                Measure-Object -Property ThreadCount -Sum).Sum
        } -DefaultValue "Error"
    } else {
        $threadCount = "Error"
    }

    $systemStats.metrics.system = @{
        processes = $allProcesses.Count
        threads = $threadCount
        handles = ($allProcesses | Measure-Object -Property Handles -Sum -ErrorAction SilentlyContinue).Sum
        type = "system"
    }

    # Update cache
    $script:CachedStats = @{
        timestamp = Get-Date
        data = $systemStats
    }

    $jsonResponse = $systemStats | ConvertTo-Json -Depth 10 -Compress
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServerHeatmap' -Message "Error collecting system stats: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
