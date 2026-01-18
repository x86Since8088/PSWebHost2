param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = New-JsonResponse -status 'fail' -message 'Authentication required'
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Check query parameters for history request
    $queryParams = $Request.QueryString
    $historyMinutes = $queryParams['history']
    $format = $queryParams['format']

    # If history is requested, return aggregated data
    if ($historyMinutes) {
        $minutes = [int]$historyMinutes
        if ($minutes -lt 1) { $minutes = 60 }
        if ($minutes -gt 1440) { $minutes = 1440 }  # Max 24 hours

        $historyData = Get-MetricsHistory -Source 'Aggregated' -Minutes $minutes

        $response_data = @{
            status = 'success'
            type = 'history'
            minutes = $minutes
            recordCount = $historyData.Count
            data = $historyData
        }

        $jsonResponse = $response_data | ConvertTo-Json -Depth 10 -Compress
        context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Get current metrics from global storage
    $metrics = $null
    if ($Global:PSWebServer.Metrics -and $Global:PSWebServer.Metrics.Current.Timestamp) {
        $metrics = $Global:PSWebServer.Metrics.Current
    }

    # If no metrics available yet, try to collect now
    if (-not $metrics -or -not $metrics.Timestamp) {
        try {
            Invoke-MetricJobMaintenance -CollectOnly
            $metrics = $Global:PSWebServer.Metrics.Current
        } catch {
            Write-Warning "[ServerHeatmap] Failed to collect metrics on-demand: $($_.Exception.Message)"
        }
    }

    # Build response in the format expected by the frontend
    $systemStats = @{
        timestamp = if ($metrics.Timestamp) { $metrics.Timestamp } else { (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
        hostname = if ($metrics.Hostname) { $metrics.Hostname } else { $env:COMPUTERNAME }
        metrics = @{}
        cached = $true  # Data is from the metrics cache
    }

    # CPU - Transform to frontend format
    if ($metrics.Cpu -and -not $metrics.Cpu.Error) {
        $cpuData = @()
        $coreIndex = 0
        foreach ($coreValue in $metrics.Cpu.Cores) {
            $cpuData += @{
                name = "CPU $coreIndex"
                value = $coreValue
                unit = "%"
                type = "cpu"
            }
            $coreIndex++
        }
        # If no per-core data, create a single entry with total
        if ($cpuData.Count -eq 0 -and $metrics.Cpu.TotalPercent) {
            $cpuData += @{
                name = "CPU Total"
                value = $metrics.Cpu.TotalPercent
                unit = "%"
                type = "cpu"
            }
        }
        $systemStats.metrics.cpu = $cpuData
        $systemStats.metrics.cpuCoreCount = $metrics.Cpu.CoreCount
    } else {
        $systemStats.metrics.cpu = @(@{
            name = "CPU Status"
            value = "Error"
            unit = ""
            type = "cpu"
            error = if ($metrics.Cpu.Error) { $metrics.Cpu.Error } else { "No data available" }
        })
        $systemStats.metrics.cpuCoreCount = 0
    }

    # Memory - Transform to frontend format
    if ($metrics.Memory -and -not $metrics.Memory.Error) {
        $systemStats.metrics.memory = @{
            total = $metrics.Memory.TotalGB
            used = $metrics.Memory.UsedGB
            free = $metrics.Memory.FreeGB
            percentUsed = $metrics.Memory.PercentUsed
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
            error = if ($metrics.Memory.Error) { $metrics.Memory.Error } else { "No data available" }
        }
    }

    # Disk - Transform to frontend format
    if ($metrics.Disk -and -not $metrics.Disk.Error) {
        $diskData = @()
        foreach ($driveLetter in $metrics.Disk.Keys) {
            if ($driveLetter -eq 'Error') { continue }
            $drive = $metrics.Disk[$driveLetter]
            $diskData += @{
                name = $driveLetter
                total = $drive.TotalGB
                used = $drive.UsedGB
                free = $drive.FreeGB
                percentUsed = $drive.PercentUsed
                unit = "GB"
                type = "disk"
            }
        }
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

    # Network - Transform to frontend format
    if ($metrics.Network -and -not $metrics.Network.Error) {
        $netData = @()
        foreach ($ifaceName in $metrics.Network.Keys) {
            if ($ifaceName -eq 'Error') { continue }
            $iface = $metrics.Network[$ifaceName]
            $netData += @{
                name = $ifaceName
                value = $iface.KBPerSec
                unit = "KB/s"
                type = "network"
            }
        }
        $systemStats.metrics.network = $netData
    } else {
        $systemStats.metrics.network = @(@{
            name = "Network Status"
            value = "Error"
            unit = ""
            type = "network"
        })
    }

    # System Info (processes, threads, handles)
    if ($metrics.System -and -not $metrics.System.Error) {
        $systemStats.metrics.system = @{
            processes = $metrics.System.Processes
            threads = $metrics.System.Threads
            handles = $metrics.System.Handles
            type = "system"
        }
    } else {
        $systemStats.metrics.system = @{
            processes = "Error"
            threads = "Error"
            handles = "Error"
            type = "system"
        }
    }

    # Uptime
    if ($metrics.Uptime -and -not $metrics.Uptime.Error) {
        $systemStats.metrics.uptime = @{
            days = $metrics.Uptime.Days
            hours = $metrics.Uptime.Hours
            minutes = $metrics.Uptime.Minutes
            totalHours = $metrics.Uptime.TotalHours
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

    # Top Processes by CPU
    if ($metrics.TopProcessesCPU -and $metrics.TopProcessesCPU.Count -gt 0) {
        $systemStats.metrics.topProcessesCPU = @($metrics.TopProcessesCPU | ForEach-Object {
            @{
                name = $_.Name
                cpu = $_.Cpu
                memory = $_.MemoryMB
                id = $_.Id
                type = "process"
            }
        })
    } else {
        $systemStats.metrics.topProcessesCPU = @()
    }

    # Top Processes by Memory
    if ($metrics.TopProcessesMem -and $metrics.TopProcessesMem.Count -gt 0) {
        $systemStats.metrics.topProcessesMem = @($metrics.TopProcessesMem | ForEach-Object {
            @{
                name = $_.Name
                memory = $_.MemoryMB
                cpu = $_.Cpu
                id = $_.Id
                type = "process"
            }
        })
    } else {
        $systemStats.metrics.topProcessesMem = @()
    }

    # Add metrics job status info
    $jobStatus = Get-MetricsJobStatus
    $systemStats.metricsStatus = @{
        samplesCollected = $jobStatus.SamplesCount
        aggregatedMinutes = $jobStatus.AggregatedCount
        lastCollection = if ($jobStatus.LastCollection) { $jobStatus.LastCollection.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
        errorCount = $jobStatus.ErrorCount
    }

    $jsonResponse = $systemStats | ConvertTo-Json -Depth 10 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'ServerHeatmap' -Message "Error collecting system stats: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
