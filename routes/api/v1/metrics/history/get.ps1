param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Metrics History API Endpoint (New Architecture - SQLite Backend)
# Returns historical metrics data from pswebhost_perf.db in Chart.js compatible format

try {
    # Parse query parameters
    $starting = $Request.QueryString["starting"]
    $ending = $Request.QueryString["ending"]
    $metric = $Request.QueryString["metric"] ?? "cpu"
    $granularity = $Request.QueryString["granularity"]  # Optional: 5s or 60s
    $timeRange = $Request.QueryString["timerange"]  # Optional: 5m, 1h, etc.

    # Handle timerange parameter if starting is not provided
    if (-not $starting -and $timeRange) {
        # Parse time range (e.g., "5m", "1h", "24h")
        $minutes = switch -Regex ($timeRange) {
            '^\d+m$' { [int]($timeRange -replace 'm', '') }
            '^\d+h$' { [int]($timeRange -replace 'h', '') * 60 }
            '^\d+d$' { [int]($timeRange -replace 'd', '') * 1440 }
            default { 5 }
        }

        $startTime = (Get-Date).AddMinutes(-$minutes)
        $endTime = Get-Date
    }
    elseif ($starting) {
        # Parse dates from starting/ending parameters
        try {
            $startTime = [datetime]::Parse($starting)
            $endTime = if ($ending) { [datetime]::Parse($ending) } else { Get-Date }
        }
        catch {
            $errorResponse = @{
                status = 'error'
                message = "Invalid datetime format. Use ISO 8601 format (e.g., 2026-01-06T10:00:00)"
            } | ConvertTo-Json
            context_reponse -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
            return
        }
    }
    else {
        # Default to last 5 minutes if neither starting nor timerange provided
        $startTime = (Get-Date).AddMinutes(-5)
        $endTime = Get-Date
    }

    # Auto-select granularity based on time range if not specified
    $rangeHours = ($endTime - $startTime).TotalHours
    if (-not $granularity) {
        $granularity = if ($rangeHours -lt 1) { '5s' } else { '60s' }
    }
    $secondsFilter = if ($granularity -eq '5s') { 5 } else { 60 }

    # Format timestamps for SQL query
    $startTimeStr = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
    $endTimeStr = $endTime.ToString('yyyy-MM-dd HH:mm:ss')

    # Determine table name and query based on metric type
    $tableName = switch ($metric) {
        'cpu' { 'Perf_CPUCore' }
        'memory' { 'Perf_MemoryUsage' }
        'disk' { 'Perf_DiskIO' }
        'network' { 'Network' }
        default { 'Perf_CPUCore' }
    }

    # Query SQLite
    $query = @"
SELECT * FROM $tableName
WHERE Timestamp >= '$startTimeStr'
  AND Timestamp <= '$endTimeStr'
  AND Seconds = $secondsFilter
ORDER BY Timestamp ASC;
"@

    $results = Get-PSWebSQLiteData -File 'pswebhost_perf.db' -Query $query

    # Transform results to Chart.js format
    $metricsData = @{
        datasets = @()
    }

    $colors = @('#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16')

    switch ($metric) {
        'cpu' {
            # Group by core number
            $coreMap = @{}
            foreach ($row in $results) {
                $coreNum = $row.CoreNumber
                if (-not $coreMap.ContainsKey($coreNum)) {
                    $coreMap[$coreNum] = @()
                }
                $coreMap[$coreNum] += @{
                    x = Get-Date $row.Timestamp -Format 'o'
                    y = [double]$row.Percent_Avg
                }
            }

            # Create dataset for each core
            $coreIndex = 0
            foreach ($coreNum in ($coreMap.Keys | Sort-Object)) {
                $metricsData.datasets += @{
                    label = "CPU $coreNum"
                    data = $coreMap[$coreNum]
                    borderColor = $colors[$coreIndex % $colors.Length]
                    backgroundColor = ($colors[$coreIndex % $colors.Length] + '40')
                    borderWidth = 2
                    tension = 0.4
                    pointRadius = 0
                    fill = $false
                }
                $coreIndex++
            }

            # Add average line (average of all cores at each timestamp)
            $timestampMap = @{}
            foreach ($row in $results) {
                $timestamp = $row.Timestamp
                if (-not $timestampMap.ContainsKey($timestamp)) {
                    $timestampMap[$timestamp] = @()
                }
                $timestampMap[$timestamp] += [double]$row.Percent_Avg
            }

            $avgData = @()
            foreach ($timestamp in ($timestampMap.Keys | Sort-Object)) {
                $avgValue = ($timestampMap[$timestamp] | Measure-Object -Average).Average
                $avgData += @{
                    x = Get-Date $timestamp -Format 'o'
                    y = [math]::Round($avgValue, 1)
                }
            }

            $metricsData.datasets += @{
                label = "Average"
                data = $avgData
                borderColor = '#ffffff'
                backgroundColor = 'rgba(255, 255, 255, 0.3)'
                borderWidth = 3
                tension = 0.4
                pointRadius = 0
                fill = $false
            }
        }

        'memory' {
            $memData = $results | ForEach-Object {
                @{
                    x = Get-Date $_.Timestamp -Format 'o'
                    y = [double]$_.MB_Avg
                }
            }

            $metricsData.datasets += @{
                label = "Memory Usage (MB)"
                data = $memData
                borderColor = '#3b82f6'
                backgroundColor = 'rgba(59, 130, 246, 0.2)'
                borderWidth = 2
                tension = 0.4
                pointRadius = 0
                fill = $true
            }
        }

        'disk' {
            # Group by drive
            $driveMap = @{}
            foreach ($row in $results) {
                $drive = $row.Drive
                if (-not $driveMap.ContainsKey($drive)) {
                    $driveMap[$drive] = @()
                }
                $driveMap[$drive] += @{
                    x = Get-Date $row.Timestamp -Format 'o'
                    y = [double]$row.KBPerSec_Avg
                }
            }

            # Create dataset for each drive
            $driveIndex = 0
            foreach ($drive in ($driveMap.Keys | Sort-Object)) {
                $metricsData.datasets += @{
                    label = "$drive KB/s"
                    data = $driveMap[$drive]
                    borderColor = $colors[$driveIndex % $colors.Length]
                    backgroundColor = ($colors[$driveIndex % $colors.Length] + '40')
                    borderWidth = 2
                    tension = 0.4
                    pointRadius = 0
                    fill = $false
                }
                $driveIndex++
            }
        }

        'network' {
            # Group by adapter name
            $adapterMap = @{}
            foreach ($row in $results) {
                $adapter = $row.AdapterName
                if (-not $adapterMap.ContainsKey($adapter)) {
                    $adapterMap[$adapter] = @()
                }
                $totalKB = [double]$row.IngressKB_Avg + [double]$row.EgressKB_Avg
                $adapterMap[$adapter] += @{
                    x = Get-Date $row.Timestamp -Format 'o'
                    y = $totalKB
                }
            }

            # Create dataset for each adapter
            $adapterIndex = 0
            foreach ($adapter in ($adapterMap.Keys | Sort-Object)) {
                $metricsData.datasets += @{
                    label = "$adapter KB/s"
                    data = $adapterMap[$adapter]
                    borderColor = $colors[$adapterIndex % $colors.Length]
                    backgroundColor = ($colors[$adapterIndex % $colors.Length] + '40')
                    borderWidth = 2
                    tension = 0.4
                    pointRadius = 0
                    fill = $false
                }
                $adapterIndex++
            }
        }
    }

    $successResponse = @{
        status = 'success'
        metric = $metric
        startTime = $startTime.ToString('o')
        endTime = $endTime.ToString('o')
        granularity = $granularity
        sampleCount = $results.Count
        data = $metricsData
    } | ConvertTo-Json -Depth 10 -Compress

    context_reponse -Response $Response -String $successResponse -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "Error in metrics history API: $($_.Exception.Message)"
    $errorResponse = @{
        status = 'error'
        message = "Error processing metrics history: $($_.Exception.Message)"
        metric = $metric
        timeRange = $timeRange
        starting = $starting
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
