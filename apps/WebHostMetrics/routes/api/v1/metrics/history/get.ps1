param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

# Metrics History API Endpoint (CSV-based Architecture)
# Returns historical metrics data from CSV files in PsWebHost_Data/metrics/
# CSV data is embedded in JSON response for efficient transmission

# Load required modules and functions for test mode
if ($Test) {
    # $PSScriptRoot = apps/WebHostMetrics/routes/api/v1/metrics/history
    # Need to go up 7 levels to reach project root
    $projectRoot = Split-Path (Split-Path (Split-Path (Split-Path (Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent) -Parent) -Parent) -Parent) -Parent

    # Initialize global PSWebServer if needed
    if (-not $Global:PSWebServer) {
        $Global:PSWebServer = @{
            Project_Root = @{ Path = $projectRoot }
        }
    }
    elseif (-not $Global:PSWebServer.Project_Root) {
        $Global:PSWebServer.Project_Root = @{ Path = $projectRoot }
    }

    # Mock Write-PSWebHostLog if not available
    if (-not (Get-Command Write-PSWebHostLog -ErrorAction SilentlyContinue)) {
        function Write-PSWebHostLog {
            param($Severity, $Category, $Message, $Data)
            Write-Host "[$Severity] [$Category] $Message" -ForegroundColor Yellow
        }
    }
}

# Handle test mode session setup
if ($Test) {
    # Read and display security configuration
    $securityFile = Join-Path $PSScriptRoot "get.security.json"
    if (Test-Path $securityFile) {
        $securityConfig = Get-Content $securityFile -Raw | ConvertFrom-Json
        Write-Host "`n=== Security Configuration ===" -ForegroundColor Cyan
        Write-Host "Allowed Roles: $($securityConfig.Allowed_Roles -join ', ')" -ForegroundColor Yellow
        Write-Host "================================`n" -ForegroundColor Cyan
    }

    # Create mock sessiondata
    if ($Roles.Count -eq 0) {
        $Roles = @('authenticated')
    }
    else {
        # Ensure 'authenticated' is always included when roles are specified
        if ('authenticated' -notin $Roles) {
            $Roles = @('authenticated') + $Roles
        }
    }
    $sessiondata = @{
        Roles = $Roles
        UserID = 'test-user'
        SessionID = 'test-session'
    }
}

try {
    # Get query parameters - handle both real Request and test Query hashtable
    if ($Test -and $Query.Count -gt 0) {
        # In test mode, use Query hashtable directly
        $queryParams = $Query
    } elseif ($Request) {
        # Normal mode, use Request.QueryString
        $queryParams = $Request.QueryString
    } else {
        # Test mode with no Query - create empty collection
        $queryParams = @{}
    }

    # Parse query parameters
    $starting = $queryParams["starting"]
    $ending = $queryParams["ending"]
    $metrics = $queryParams["metrics"]  # Comma-separated: cpu,memory,disk,network (or empty for all)
    $timeRange = $queryParams["timerange"]  # Optional: 5m, 1h, 24h, etc.
    $granularity = $queryParams["granularity"]  # Optional: 5s, 15s, 30s, 1m (default: 5s)

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
                message = "Invalid datetime format. Use ISO 8601 format (e.g., 2026-01-20T10:00:00)"
            } | ConvertTo-Json
            if ($Test) {
                Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
                Write-Host "Status: 400 Bad Request" -ForegroundColor Red
                Write-Host "Content-Type: application/json" -ForegroundColor Gray
                Write-Host "`nResponse:" -ForegroundColor Cyan
                $errorResponse | Write-Host
                return
            }
            context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
            return
        }
    }
    else {
        # Default to last 5 minutes if neither starting nor timerange provided
        $startTime = (Get-Date).AddMinutes(-5)
        $endTime = Get-Date
    }

    # Determine which metrics to fetch
    $requestedMetrics = if ($metrics) { $metrics -split ',' } else { @('cpu', 'memory', 'disk', 'network') }

    # Parse granularity (default to 5s which is native collection interval)
    $granularitySeconds = switch ($granularity) {
        '1s'  { 1 }
        '5s'  { 5 }
        '15s' { 15 }
        '30s' { 30 }
        '1m'  { 60 }
        default { 5 }  # Native granularity is 5 seconds
    }
    $granularityLabel = if ($granularity) { $granularity } else { '5s' }

    # Map metric names to CSV file prefixes (for per-minute detailed files)
    $metricFileMap = @{
        'cpu' = 'Perf_CPUCore'
        'memory' = 'Perf_MemoryUsage'
        'disk' = 'Perf_DiskIO'
        'network' = 'Network'
    }

    # Map metric names to columns in daily aggregate files (metrics_YYYY-MM-DD.csv)
    $dailyMetricColumns = @{
        'cpu' = @{ ValueColumn = 'Cpu_Avg'; MinColumn = 'Cpu_Min'; MaxColumn = 'Cpu_Max' }
        'memory' = @{ ValueColumn = 'Memory_PercentUsed_Avg'; MinColumn = 'Memory_PercentUsed_Min'; MaxColumn = 'Memory_PercentUsed_Max' }
    }

    # Test mode: show query info
    if ($Test) {
        Write-Host "[Test Mode] Time range: $($startTime.ToString('yyyy-MM-dd HH:mm:ss')) to $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
        Write-Host "[Test Mode] Requested metrics: $($requestedMetrics -join ', ')" -ForegroundColor Cyan
        Write-Host "[Test Mode] Granularity: $granularityLabel ($granularitySeconds seconds)" -ForegroundColor Cyan
    }

    # Get CSV directory
    $projectRoot = $Global:PSWebServer.Project_Root.Path
    $csvDir = Join-Path $projectRoot "PsWebHost_Data\metrics"

    if (-not (Test-Path $csvDir)) {
        $response_data = @{
            status = 'success'
            startTime = $startTime.ToString('o')
            endTime = $endTime.ToString('o')
            granularity = $granularityLabel
            metrics = @{}
            message = 'No metrics data directory found'
        }
    }
    else {
        # Build response with CSV data grouped by source
        $csvDataBySources = @{}

        # OPTIMIZATION: Calculate time range once, decide data source upfront
        $timeRangeMinutes = ($endTime - $startTime).TotalMinutes
        $useDaily = $timeRangeMinutes -gt 5

        # OPTIMIZATION: Pre-format time boundaries for string comparison (faster than datetime comparison)
        $startTimeStr = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
        $endTimeStr = $endTime.ToString('yyyy-MM-dd HH:mm:ss')

        foreach ($metricName in $requestedMetrics) {
            # OPTIMIZATION: Use List<string> instead of array concatenation (O(1) vs O(n) per add)
            $csvList = [System.Collections.Generic.List[string]]::new()
            $nativeGranularity = 60  # Default for daily files

            # Decide data source BEFORE reading any files (avoid redundant I/O)
            if (-not $useDaily -and $metricFileMap.ContainsKey($metricName)) {
                # Short time range (≤5 min): Use Perf_* files with 5-second granularity
                $filePrefix = $metricFileMap[$metricName]
                $pattern = "${filePrefix}_*.csv"
                $nativeGranularity = 5

                $csvFiles = Get-ChildItem -Path $csvDir -Filter $pattern -ErrorAction SilentlyContinue | Where-Object {
                    if ($_.BaseName -match '_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})$') {
                        $timestampStr = "$($matches[1])T$($matches[2]):$($matches[3]):$($matches[4])"
                        try {
                            $fileTime = [datetime]::Parse($timestampStr)
                            return $fileTime -ge $startTime -and $fileTime -le $endTime
                        }
                        catch { return $false }
                    }
                    return $false
                } | Sort-Object Name

                if ($csvFiles) {
                    $headerWritten = $false
                    foreach ($file in $csvFiles) {
                        # OPTIMIZATION: Use StreamReader for efficient line-by-line reading
                        $reader = [System.IO.StreamReader]::new($file.FullName)
                        try {
                            $lineNum = 0
                            while ($null -ne ($line = $reader.ReadLine())) {
                                if ($lineNum -eq 0) {
                                    if (-not $headerWritten) {
                                        $csvList.Add($line)
                                        $headerWritten = $true
                                    }
                                }
                                else {
                                    $csvList.Add($line)
                                }
                                $lineNum++
                            }
                        }
                        finally {
                            $reader.Close()
                            $reader.Dispose()
                        }
                    }
                }
            }

            # Use daily files for longer ranges OR if no Perf_* data found
            if (($useDaily -or $csvList.Count -le 1) -and $dailyMetricColumns.ContainsKey($metricName)) {
                $colMapping = $dailyMetricColumns[$metricName]
                $nativeGranularity = 60

                # Reset if switching from Perf_* files
                if ($csvList.Count -gt 0) {
                    $csvList.Clear()
                }

                # Find daily files matching the date range
                $dailyFiles = Get-ChildItem -Path $csvDir -Filter "metrics_*.csv" -ErrorAction SilentlyContinue | Where-Object {
                    if ($_.BaseName -match 'metrics_(\d{4}-\d{2}-\d{2})$') {
                        try {
                            $fileDate = [datetime]::Parse($matches[1])
                            return $fileDate.Date -ge $startTime.Date -and $fileDate.Date -le $endTime.Date
                        }
                        catch { return $false }
                    }
                    return $false
                } | Sort-Object Name

                if ($dailyFiles) {
                    # Add header
                    $csvList.Add('"Timestamp","Host","Percent_Avg","Percent_Min","Percent_Max"')

                    foreach ($file in $dailyFiles) {
                        # OPTIMIZATION: Use StreamReader with direct string parsing (avoid Import-Csv overhead)
                        $reader = [System.IO.StreamReader]::new($file.FullName)
                        try {
                            $headerLine = $reader.ReadLine()
                            if (-not $headerLine) { continue }

                            # OPTIMIZATION: Parse header once to find column indices
                            $headers = $headerLine -replace '"', '' -split ','
                            $tsIdx = [Array]::IndexOf($headers, 'Timestamp')
                            $hostIdx = [Array]::IndexOf($headers, 'Hostname')
                            $valIdx = [Array]::IndexOf($headers, $colMapping.ValueColumn)
                            $minIdx = [Array]::IndexOf($headers, $colMapping.MinColumn)
                            $maxIdx = [Array]::IndexOf($headers, $colMapping.MaxColumn)

                            if ($tsIdx -lt 0 -or $valIdx -lt 0) { continue }

                            while ($null -ne ($line = $reader.ReadLine())) {
                                if ([string]::IsNullOrWhiteSpace($line)) { continue }

                                # OPTIMIZATION: Direct string split instead of regex
                                $values = $line -replace '"', '' -split ','

                                if ($values.Count -le $tsIdx) { continue }

                                $timestamp = $values[$tsIdx]

                                # OPTIMIZATION: String comparison for time filtering (faster than datetime parsing)
                                if ($timestamp -lt $startTimeStr -or $timestamp -gt $endTimeStr) { continue }

                                $percentAvg = if ($valIdx -ge 0 -and $values.Count -gt $valIdx) { $values[$valIdx] } else { '' }
                                if ([string]::IsNullOrWhiteSpace($percentAvg)) { continue }

                                $hostName = if ($hostIdx -ge 0 -and $values.Count -gt $hostIdx) { $values[$hostIdx] } else { 'unknown' }
                                $percentMin = if ($minIdx -ge 0 -and $values.Count -gt $minIdx) { $values[$minIdx] } else { $percentAvg }
                                $percentMax = if ($maxIdx -ge 0 -and $values.Count -gt $maxIdx) { $values[$maxIdx] } else { $percentAvg }

                                # Transform timestamp format: "2026-02-25 00:00:00" -> "2026-02-25_00-00-00"
                                $formattedTimestamp = $timestamp -replace ' ', '_' -replace ':', '-'

                                $csvList.Add("`"$formattedTimestamp`",`"$hostName`",`"$percentAvg`",`"$percentMin`",`"$percentMax`"")
                            }
                        }
                        finally {
                            $reader.Close()
                            $reader.Dispose()
                        }
                    }
                }
            }

            # Apply downsampling with aggregation if granularity > native
            if ($csvList.Count -gt 1) {
                if ($granularitySeconds -gt $nativeGranularity) {
                    $skipFactor = [int]($granularitySeconds / $nativeGranularity)

                    # OPTIMIZATION: Use List for result building
                    $sampledList = [System.Collections.Generic.List[string]]::new()
                    $sampledList.Add($csvList[0])  # Header

                    # OPTIMIZATION: Aggregate with min/max/avg instead of just sampling
                    $dataCount = $csvList.Count - 1
                    for ($i = 0; $i -lt $dataCount; $i += $skipFactor) {
                        $windowEnd = [Math]::Min($i + $skipFactor, $dataCount)

                        # For single-point windows, just take the point
                        if ($windowEnd - $i -eq 1) {
                            $sampledList.Add($csvList[$i + 1])
                            continue
                        }

                        # Aggregate multiple points: calculate avg, track min/max
                        $sumAvg = 0.0
                        $minVal = [double]::MaxValue
                        $maxVal = [double]::MinValue
                        $firstTimestamp = $null
                        $firstHost = $null
                        $validPoints = 0

                        for ($j = $i; $j -lt $windowEnd; $j++) {
                            $line = $csvList[$j + 1]
                            $parts = $line -replace '"', '' -split ','

                            if ($parts.Count -ge 3) {
                                if (-not $firstTimestamp) {
                                    $firstTimestamp = $parts[0]
                                    $firstHost = $parts[1]
                                }

                                $avgVal = 0.0
                                if ([double]::TryParse($parts[2], [ref]$avgVal)) {
                                    $sumAvg += $avgVal
                                    $validPoints++

                                    # Track min from Percent_Min column or avg
                                    $minPoint = $avgVal
                                    if ($parts.Count -ge 4) {
                                        [double]::TryParse($parts[3], [ref]$minPoint) | Out-Null
                                    }
                                    if ($minPoint -lt $minVal) { $minVal = $minPoint }

                                    # Track max from Percent_Max column or avg
                                    $maxPoint = $avgVal
                                    if ($parts.Count -ge 5) {
                                        [double]::TryParse($parts[4], [ref]$maxPoint) | Out-Null
                                    }
                                    if ($maxPoint -gt $maxVal) { $maxVal = $maxPoint }
                                }
                            }
                        }

                        if ($validPoints -gt 0 -and $firstTimestamp) {
                            $aggregatedAvg = [Math]::Round($sumAvg / $validPoints, 1)
                            $aggregatedMin = [Math]::Round($minVal, 1)
                            $aggregatedMax = [Math]::Round($maxVal, 1)
                            $sampledList.Add("`"$firstTimestamp`",`"$firstHost`",`"$aggregatedAvg`",`"$aggregatedMin`",`"$aggregatedMax`"")
                        }
                    }

                    $csvList = $sampledList
                }
            }

            # Store as single CSV string
            if ($csvList.Count -gt 1) {
                $csvDataBySources[$metricName] = $csvList -join "`n"
            }
        }

        # Build response
        $response_data = @{
            status = 'success'
            startTime = $startTime.ToString('o')
            endTime = $endTime.ToString('o')
            granularity = $granularityLabel
            format = 'csv'
            sources = $csvDataBySources.Keys -join ','
            data = $csvDataBySources
        }
    }

    # OPTIMIZATION: Remove -Compress (HTTP compression handles this, reduces CPU overhead)
    $jsonResponse = $response_data | ConvertTo-Json -Depth 10

    # Test mode output
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nResponse Summary:" -ForegroundColor Cyan
        Write-Host "  Time Range: $($response_data.startTime) to $($response_data.endTime)" -ForegroundColor Yellow
        Write-Host "  Format: $($response_data.format)" -ForegroundColor Yellow
        Write-Host "  Sources: $($response_data.sources)" -ForegroundColor Yellow
        foreach ($source in $response_data.data.Keys) {
            $lineCount = ($response_data.data[$source] -split "`n").Count
            Write-Host "  $source`: $lineCount lines" -ForegroundColor Yellow
        }

        Write-Host "`nSample CSV Data (first 5 lines):" -ForegroundColor Cyan
        foreach ($source in $response_data.data.Keys) {
            Write-Host "`n[$source]" -ForegroundColor Green
            ($response_data.data[$source] -split "`n") | Select-Object -First 5 | ForEach-Object {
                Write-Host "  $_" -ForegroundColor Gray
            }
        }

        Write-Host "`n=== End Test Results ===" -ForegroundColor Cyan
        return
    }

    # Cache for 30 seconds - metrics data changes slowly and this reduces server load
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json" -CacheDuration 30
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "Error in metrics history API: $($_.Exception.Message)"

    # Test mode error output
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host "`n=== End Test Error ===" -ForegroundColor Red
        return
    }

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
