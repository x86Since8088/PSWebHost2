
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
    # Get query parameters for filtering
    $queryParams = @{}
    if ($Request.QueryString['filter']) {
        $queryParams.Filter = $Request.QueryString['filter']
    }
    if ($Request.QueryString['count']) {
        $queryParams.Count = [int]$Request.QueryString['count']
    } else {
        $queryParams.Count = 1000  # Default max events
    }
    if ($Request.QueryString['earliest']) {
        $queryParams.Earliest = [DateTime]::Parse($Request.QueryString['earliest'])
    }
    if ($Request.QueryString['latest']) {
        $queryParams.Latest = [DateTime]::Parse($Request.QueryString['latest'])
    }

    # Initialize buffer if not exists
    if ($null -eq $Global:PSWebServer.EventStreamBuffer) {
        $Global:PSWebServer.EventStreamBuffer = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
        $Global:PSWebServer.EventStreamMaxSize = 1000
        $Global:PSWebServer.EventStreamLastLine = 0
    }

    # Get log tail job output and update the buffer
    $logTailJob = Get-Job -Name "Log_Tail: $($Global:PSWebServer.LogFilePath)" -ErrorAction SilentlyContinue

    if ($logTailJob) {
        # Receive new log entries from the job (without -Keep to consume them)
        $newEntries = Receive-Job -Job $logTailJob -ErrorAction SilentlyContinue

        if ($newEntries) {
            foreach ($entry in $newEntries) {
                # Parse TSV line from log tail
                $fields = $entry.Line -split "`t"
                if ($fields.Count -ge 5) {
                    # Unescape the data field (remove backslash escaping)
                    $dataField = if ($fields.Count -gt 4) { $fields[4] } else { '' }
                    $dataField = $dataField -replace '\\(.)', '$1'  # Remove backslash before any character

                    $logEvent = [PSCustomObject]@{
                        Date = $fields[0]
                        DateTimeOffset = $fields[1]
                        state = $fields[2]  # Severity
                        UserID = if ($fields.Count -gt 3) { $fields[3] } else { '' }  # Category
                        Provider = 'System'
                        Data = $dataField
                        _timestamp = Get-Date
                    }

                    # Add to buffer
                    $Global:PSWebServer.EventStreamBuffer.Enqueue($logEvent)
                }
            }

            # Trim buffer to max size (ring buffer behavior)
            while ($Global:PSWebServer.EventStreamBuffer.Count -gt $Global:PSWebServer.EventStreamMaxSize) {
                $null = $Global:PSWebServer.EventStreamBuffer.TryDequeue([ref]$null)
            }
        }
    } else {
        # Fallback: Read log file directly if job doesn't exist
        # Only populate buffer once on first request to avoid slow repeated reads
        if ($Global:PSWebServer.EventStreamBuffer.Count -eq 0) {
            $logFile = $Global:PSWebServer.LogFilePath
            if (Test-Path $logFile) {
                $lines = Get-Content -Path $logFile -Tail 100 -ErrorAction SilentlyContinue

                foreach ($line in $lines) {
                    $fields = $line -split "`t"
                    if ($fields.Count -ge 5) {
                        # Unescape the data field (remove backslash escaping)
                        $dataField = if ($fields.Count -gt 4) { $fields[4] } else { '' }
                        $dataField = $dataField -replace '\\(.)', '$1'  # Remove backslash before any character

                        $logEvent = [PSCustomObject]@{
                            Date = $fields[0]
                            DateTimeOffset = $fields[1]
                            state = $fields[2]  # Severity
                            UserID = if ($fields.Count -gt 3) { $fields[3] } else { '' }  # Category
                            Provider = 'System'
                            Data = $dataField
                            _timestamp = Get-Date
                        }

                        # Add to buffer
                        $Global:PSWebServer.EventStreamBuffer.Enqueue($logEvent)
                    }
                }

                # Trim buffer to max size
                while ($Global:PSWebServer.EventStreamBuffer.Count -gt $Global:PSWebServer.EventStreamMaxSize) {
                    $null = $Global:PSWebServer.EventStreamBuffer.TryDequeue([ref]$null)
                }
            }
        }
    }

    # Get all events from buffer
    $allEvents = @($Global:PSWebServer.EventStreamBuffer.ToArray())

    # Apply filters
    $filteredEvents = $allEvents

    # Filter by text search
    if ($queryParams.Filter) {
        $filterText = $queryParams.Filter.ToLower()
        $filteredEvents = $filteredEvents | Where-Object {
            $_.Date -match $filterText -or
            $_.state -match $filterText -or
            $_.UserID -match $filterText -or
            $_.Provider -match $filterText -or
            $_.Data -match $filterText
        }
    }

    # Filter by time range
    if ($queryParams.Earliest) {
        $filteredEvents = $filteredEvents | Where-Object {
            try {
                [DateTime]::Parse($_.Date) -ge $queryParams.Earliest
            } catch {
                $true  # Include if date parsing fails
            }
        }
    }

    if ($queryParams.Latest) {
        $filteredEvents = $filteredEvents | Where-Object {
            try {
                [DateTime]::Parse($_.Date) -le $queryParams.Latest
            } catch {
                $true  # Include if date parsing fails
            }
        }
    }

    # Sort by date descending (newest first) and limit count
    $filteredEvents = $filteredEvents |
        Sort-Object -Property { try { [DateTime]::Parse($_.Date) } catch { Get-Date } } -Descending |
        Select-Object -First $queryParams.Count

    # Convert to JSON
    $jsonData = $filteredEvents | ConvertTo-Json -Depth 5 -Compress
    if ($jsonData -in @('null', '')) {
        $jsonData = '[]'
    }

    context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'EventStream' -Message "Error processing event stream: $($_.Exception.Message)"
    $jsonResponse = New-JsonResponse -status 'fail' -message "Failed to retrieve events: $($_.Exception.Message)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}
