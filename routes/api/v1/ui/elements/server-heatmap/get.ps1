
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Authentication required'
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Collect real system statistics
    $systemStats = @{
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        hostname = $env:COMPUTERNAME
        metrics = @{}
    }

    # CPU Usage (per logical processor)
    $cpuCounters = Get-Counter -Counter '\Processor(*)\% Processor Time' -ErrorAction SilentlyContinue
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
        $systemStats.metrics.cpu = @()
    }

    # Memory Usage
    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) {
        $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB,2)
        $memoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1)

        $systemStats.metrics.memory = @{
            total = $totalMemoryGB
            used = $usedMemoryGB
            free = $freeMemoryGB
            percentUsed = $memoryPercent
            unit = "GB"
            type = "memory"
        }
    }

    # Disk Usage (all drives)
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction SilentlyContinue
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
        $systemStats.metrics.disk = @()
    }

    # Network Interfaces
    $netCounters = Get-Counter -Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction SilentlyContinue
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
        $systemStats.metrics.network = @()
    }

    # Top Processes by CPU
    $topProcessesCPU = @(Get-Process | Where-Object { $_.CPU -gt 0 } |
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

    # Top Processes by Memory
    $topProcessesMem = @(Get-Process |
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

    # System Uptime
    $bootTime = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime
    if ($bootTime) {
        $uptime = (Get-Date) - $bootTime
        $systemStats.metrics.uptime = @{
            days = $uptime.Days
            hours = $uptime.Hours
            minutes = $uptime.Minutes
            totalHours = [math]::Round($uptime.TotalHours, 1)
            type = "uptime"
        }
    }

    # Thread and Handle Count
    $allProcesses = Get-Process
    $systemStats.metrics.system = @{
        processes = $allProcesses.Count
        threads = ($allProcesses | ForEach-Object { $_.Threads.Count } | Measure-Object -Sum).Sum
        handles = ($allProcesses | Measure-Object -Property Handles -Sum).Sum
        type = "system"
    }

    $jsonResponse = $systemStats | ConvertTo-Json -Depth 10 -Compress
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServerHeatmap' -Message "Error collecting system stats: $($_.Exception.Message)"
    $jsonResponse = New-JsonResponse -status 'fail' -message "Failed to collect system statistics: $($_.Exception.Message)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}
