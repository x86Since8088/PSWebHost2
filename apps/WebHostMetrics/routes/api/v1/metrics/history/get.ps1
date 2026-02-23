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
        '5s'  { 5 }
        '15s' { 15 }
        '30s' { 30 }
        '1m'  { 60 }
        default { 5 }  # Native granularity is 5 seconds
    }
    $granularityLabel = if ($granularity) { $granularity } else { '5s' }

    # Map metric names to CSV file prefixes
    $metricFileMap = @{
        'cpu' = 'Perf_CPUCore'
        'memory' = 'Perf_MemoryUsage'
        'disk' = 'Perf_DiskIO'
        'network' = 'Network'
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

        foreach ($metricName in $requestedMetrics) {
            $filePrefix = $metricFileMap[$metricName]
            if (-not $filePrefix) { continue }

            # Find CSV files matching the time range
            # Format: Perf_CPUCore_2026-01-20_13-00-00.csv
            $pattern = "${filePrefix}_*.csv"
            $csvFiles = Get-ChildItem -Path $csvDir -Filter $pattern -ErrorAction SilentlyContinue | Where-Object {
                # Parse timestamp from filename: Perf_CPUCore_2026-01-20_13-00-00.csv
                if ($_.BaseName -match '_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})$') {
                    $timestampStr = "$($matches[1])T$($matches[2]):$($matches[3]):$($matches[4])"
                    try {
                        $fileTime = [datetime]::Parse($timestampStr)
                        return $fileTime -ge $startTime -and $fileTime -le $endTime
                    }
                    catch {
                        return $false
                    }
                }
                return $false
            } | Sort-Object Name

            if ($csvFiles) {
                # Read and concatenate CSV files
                $csvContent = @()
                $headerWritten = $false

                foreach ($file in $csvFiles) {
                    $lines = Get-Content -Path $file.FullName

                    if (-not $headerWritten) {
                        # Include header from first file
                        $csvContent += $lines
                        $headerWritten = $true
                    }
                    else {
                        # Skip header from subsequent files
                        $csvContent += $lines | Select-Object -Skip 1
                    }
                }

                # Apply downsampling if granularity > 5s
                if ($granularitySeconds -gt 5 -and $csvContent.Count -gt 1) {
                    # Parse CSV and aggregate
                    $header = $csvContent[0]
                    $dataLines = $csvContent | Select-Object -Skip 1

                    # For now, simple downsampling: take every Nth row where N = granularitySeconds / 5
                    # More sophisticated aggregation (averaging) could be added later
                    $skipFactor = [int]($granularitySeconds / 5)
                    $sampledLines = @($header)

                    for ($i = 0; $i -lt $dataLines.Count; $i += $skipFactor) {
                        $sampledLines += $dataLines[$i]
                    }

                    $csvContent = $sampledLines
                }

                # Store as single CSV string using user-friendly metric name as key
                if ($csvContent.Count -gt 0) {
                    $csvDataBySources[$metricName] = $csvContent -join "`n"
                }
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

    $jsonResponse = $response_data | ConvertTo-Json -Depth 10 -Compress

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

    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
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
