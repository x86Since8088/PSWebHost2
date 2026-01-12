#Requires -Version 7

<#
.SYNOPSIS
    Metrics Database Handler
.DESCRIPTION
    Fetches data from PSWebHost metrics database and converts to uPlot format
    uPlot format: [[timestamps], [series1], [series2], ...]
#>

param($Request, $Response, $Session)

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    $config = $bodyJson | ConvertFrom-Json

    if (-not $config.metricName) {
        throw "metricName is required"
    }

    $metricName = $config.metricName
    $timeRange = $config.timeRange ?? '24h'
    $aggregation = $config.aggregation ?? 'raw'

    # Calculate time range
    $endTime = Get-Date
    $startTime = switch -Regex ($timeRange) {
        '^\d+h$' { $endTime.AddHours(-[int]($timeRange -replace 'h', '')) }
        '^\d+d$' { $endTime.AddDays(-[int]($timeRange -replace 'd', '')) }
        '^\d+m$' { $endTime.AddMinutes(-[int]($timeRange -replace 'm', '')) }
        default { $endTime.AddHours(-24) }
    }

    Write-Verbose "[UI_Uplot] Fetching metrics: $metricName from $startTime to $endTime (aggregation: $aggregation)"

    # Check if PSWebHost metrics module is available
    $metricsAvailable = $Global:PSWebServer.ContainsKey('Metrics') -or (Get-Module -Name 'PSWebHost_Metrics' -ListAvailable)

    if (-not $metricsAvailable) {
        # Generate sample data for demonstration
        Write-Warning "[UI_Uplot] Metrics module not available, generating sample data"

        $sampleData = @()
        $currentTime = [long]($startTime.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
        $endTimestamp = [long]($endTime.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
        $interval = 60 # 1 minute intervals

        while ($currentTime -le $endTimestamp) {
            $sampleData += [PSCustomObject]@{
                timestamp = $currentTime
                value = [Math]::Round((Get-Random -Minimum 20 -Maximum 80) + [Math]::Sin($currentTime / 100) * 10, 2)
            }
            $currentTime += $interval
        }

        # Convert to uPlot format
        $timestamps = @()
        $values = @()

        foreach ($point in $sampleData) {
            $timestamps += $point.timestamp
            $values += $point.value
        }

        $uplotData = @($timestamps, $values)

    } else {
        # Fetch actual metrics from PSWebHost metrics database
        # This would integrate with the actual metrics system

        try {
            # Try to use Get-PSWebMetrics if available
            if (Get-Command -Name 'Get-PSWebMetrics' -ErrorAction SilentlyContinue) {
                $metricsData = Get-PSWebMetrics -MetricName $metricName -StartTime $startTime -EndTime $endTime -Aggregation $aggregation
            } else {
                throw "Metrics command not available"
            }

            # Convert to uPlot format
            $timestamps = @()
            $values = @()

            foreach ($point in $metricsData) {
                if ($point.timestamp -is [datetime]) {
                    $unixTime = [long]($point.timestamp.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
                    $timestamps += $unixTime
                } else {
                    $timestamps += $point.timestamp
                }

                $values += $point.value
            }

            $uplotData = @($timestamps, $values)

        } catch {
            throw "Failed to fetch metrics: $_"
        }
    }

    # Build response
    $responseData = @{
        success = $true
        data = $uplotData
        metadata = @{
            metricName = $metricName
            timeRange = $timeRange
            aggregation = $aggregation
            startTime = $startTime.ToString('o')
            endTime = $endTime.ToString('o')
            dataPoints = $uplotData[0].Count
            xAxisLabel = 'timestamp'
            seriesLabels = @($metricName)
        }
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "[UI_Uplot] Returned metrics data: $($uplotData[0].Count) points"

    # Update statistics
    $appNamespace = $Global:PSWebServer['UI_Uplot']
    if ($appNamespace.Stats) {
        $appNamespace.Stats['DataPointsServed'] += $uplotData[0].Count
    }

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] Metrics data processing error: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
