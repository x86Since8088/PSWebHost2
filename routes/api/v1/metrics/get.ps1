param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = @{ status = 'fail'; message = 'Authentication required' } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    $queryParams = $Request.QueryString
    $action = $queryParams['action']

    switch ($action) {
        'status' {
            # Return metrics job status
            $status = Get-MetricsJobStatus
            $response_data = @{
                status = 'success'
                data = $status
            }
        }
        'history' {
            # Return historical metrics
            $minutes = [int]($queryParams['minutes'] ?? 60)
            $source = $queryParams['source'] ?? 'Aggregated'

            if ($minutes -lt 1) { $minutes = 60 }
            if ($minutes -gt 1440) { $minutes = 1440 }

            $history = Get-MetricsHistory -Source $source -Minutes $minutes
            $response_data = @{
                status = 'success'
                type = 'history'
                source = $source
                minutes = $minutes
                recordCount = $history.Count
                data = $history
            }
        }
        'samples' {
            # Return raw samples (last N minutes)
            $minutes = [int]($queryParams['minutes'] ?? 5)
            if ($minutes -lt 1) { $minutes = 1 }
            if ($minutes -gt 60) { $minutes = 60 }

            $samples = Get-MetricsHistory -Source 'Samples' -Minutes $minutes
            $response_data = @{
                status = 'success'
                type = 'samples'
                minutes = $minutes
                recordCount = $samples.Count
                data = $samples
            }
        }
        'csv' {
            # Return CSV history (for longer time ranges)
            $startDate = if ($queryParams['start']) { [datetime]::Parse($queryParams['start']) } else { (Get-Date).AddDays(-1) }
            $endDate = if ($queryParams['end']) { [datetime]::Parse($queryParams['end']) } else { Get-Date }

            $csvData = Get-MetricsFromCsv -StartDate $startDate -EndDate $endDate
            $response_data = @{
                status = 'success'
                type = 'csv'
                startDate = $startDate.ToString('yyyy-MM-dd HH:mm:ss')
                endDate = $endDate.ToString('yyyy-MM-dd HH:mm:ss')
                recordCount = $csvData.Count
                data = $csvData
            }
        }
        'realtime' {
            # Return real-time metrics from interim CSV files (new architecture)
            $starting = if ($queryParams['starting']) {
                [datetime]::Parse($queryParams['starting'])
            } else {
                (Get-Date).AddMinutes(-5)
            }
            $metric = $queryParams['metric']  # cpu, memory, disk, network

            # Read interim CSV files from PsWebHost_Data/metrics/
            $projectRoot = $Global:PSWebServer.Project_Root.Path
            $csvDir = Join-Path $projectRoot "PsWebHost_Data/metrics"

            if (-not (Test-Path $csvDir)) {
                $response_data = @{
                    status = 'success'
                    startTime = $starting.ToString('o')
                    endTime = (Get-Date).ToString('o')
                    granularity = '5s'
                    data = @{}
                }
            }
            else {
                $csvFiles = Get-ChildItem -Path $csvDir -Filter "*.csv" -ErrorAction SilentlyContinue | Where-Object {
                    # Parse timestamp from filename (e.g., "Perf_CPUCore_2026-01-06_15-18-00.csv")
                    if ($_.BaseName -match '_(\d{4}-\d{2}-\d{2})_(\d{2})-(\d{2})-(\d{2})$') {
                        # Convert filename format to parseable datetime: 2026-01-06_15-18-00 -> 2026-01-06T15:18:00
                        $timestampStr = "$($matches[1])T$($matches[2]):$($matches[3]):$($matches[4])"
                        $fileTime = [datetime]::Parse($timestampStr)
                        $fileTime -ge $starting
                    } else { $false }
                }

                # Parse CSV files, group by table type
                $data = @{}
                foreach ($file in $csvFiles) {
                    $baseName = $file.BaseName
                    # Extract table name (e.g., "Perf_CPUCore_2026-01-06T10:24:00" -> "Perf_CPUCore")
                    if ($baseName -match '^(Perf_\w+|Network)_\d{4}') {
                        $tableName = $matches[1]

                        # Filter by metric parameter if specified
                        if ($metric) {
                            $skipFile = $false
                            switch ($metric) {
                                'cpu' { if ($tableName -ne 'Perf_CPUCore') { $skipFile = $true } }
                                'memory' { if ($tableName -ne 'Perf_MemoryUsage') { $skipFile = $true } }
                                'disk' { if ($tableName -ne 'Perf_DiskIO') { $skipFile = $true } }
                                'network' { if ($tableName -ne 'Network') { $skipFile = $true } }
                            }
                            if ($skipFile) { continue }
                        }

                        $csvData = Import-Csv -Path $file.FullName -ErrorAction SilentlyContinue
                        if ($csvData) {
                            if (-not $data.ContainsKey($tableName)) {
                                $data[$tableName] = @()
                            }
                            $data[$tableName] += $csvData
                        }
                    }
                }

                $response_data = @{
                    status = 'success'
                    startTime = $starting.ToString('o')
                    endTime = (Get-Date).ToString('o')
                    granularity = '5s'
                    data = $data
                }
            }
        }
        default {
            # Return current metrics
            $current = Get-CurrentMetrics
            $status = Get-MetricsJobStatus

            $response_data = @{
                status = 'success'
                timestamp = $current.Timestamp
                hostname = $current.Hostname
                metrics = @{
                    cpu = $current.Cpu
                    memory = $current.Memory
                    disk = $current.Disk
                    network = $current.Network
                    system = $current.System
                    uptime = $current.Uptime
                }
                metricsStatus = @{
                    samplesCount = $status.SamplesCount
                    aggregatedCount = $status.AggregatedCount
                    lastCollection = if ($status.LastCollection) { $status.LastCollection.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                    lastAggregation = if ($status.LastAggregation) { $status.LastAggregation.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
                    errorCount = $status.ErrorCount
                }
            }
        }
    }

    $jsonResponse = $response_data | ConvertTo-Json -Depth 10 -Compress
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Metrics' -Message "Error in metrics API: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
