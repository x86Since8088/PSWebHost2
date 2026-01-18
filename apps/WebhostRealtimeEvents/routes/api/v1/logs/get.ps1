param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$roles = @()
)

<#
.SYNOPSIS
    Real-time event log API with time range filtering and sorting
.DESCRIPTION
    Provides access to PSWebHost event logs with:
    - Time range filtering (last 15 minutes default)
    - Text search filtering
    - Sortable results
    - Column filtering
    - Source from enhanced log format (12 columns)
.PARAMETER timeRange
    Time range in minutes (default: 15)
.PARAMETER earliest
    Earliest timestamp (ISO 8601 format)
.PARAMETER latest
    Latest timestamp (ISO 8601 format)
.PARAMETER filter
    Text filter (searches across all fields)
.PARAMETER category
    Filter by log category
.PARAMETER severity
    Filter by severity level
.PARAMETER source
    Filter by source (script path/function)
.PARAMETER userID
    Filter by user ID
.PARAMETER sessionID
    Filter by session ID
.PARAMETER sortBy
    Field to sort by (Date, Severity, Category, Source, UserID)
.PARAMETER sortOrder
    Sort order: asc or desc (default: desc)
.PARAMETER count
    Maximum number of events to return (default: 1000)
.PARAMETER Test
    Test mode - outputs to console instead of HTTP response
.PARAMETER roles
    Array of roles to use for testing authentication (when Test is enabled)
.EXAMPLE
    # Test endpoint with console output
    .\get.ps1 -Test -roles @('authenticated')
.EXAMPLE
    # Test with query parameters via URL
    /apps/WebhostRealtimeEvents/api/v1/logs?test=true&roles=authenticated
#>

# Check for test mode via query parameter
if ($Request -and $Request.QueryString['test'] -eq 'true') {
    $Test = $true
}

# Parse roles from query parameter if in test mode
if ($Test -and $Request -and $Request.QueryString['roles']) {
    $roles = $Request.QueryString['roles'] -split ','
}

# Create mock sessiondata if in test mode
if ($Test) {
    if ($roles.Count -eq 0) {
        $roles = @('authenticated')  # Default to authenticated for testing
    }
    $sessiondata = @{
        Roles = $roles
        UserID = 'test-user'
        SessionID = 'test-session'
    }
}

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = @{ status = 'fail'; message = 'Authentication required' } | ConvertTo-Json

    if ($Test) {
        Write-Host "Authentication Failed (401)" -ForegroundColor Red
        Write-Host $jsonResponse -ForegroundColor Yellow
        return
    }

    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Parse query parameters
    $timeRange = if ($Request -and $Request.QueryString['timeRange']) {
        [int]$Request.QueryString['timeRange']
    } else {
        15  # Default: last 15 minutes
    }

    # Time range boundaries
    $now = Get-Date
    $earliest = if ($Request -and $Request.QueryString['earliest']) {
        [DateTime]::Parse($Request.QueryString['earliest'])
    } else {
        $now.AddMinutes(-$timeRange)
    }

    $latest = if ($Request -and $Request.QueryString['latest']) {
        [DateTime]::Parse($Request.QueryString['latest'])
    } else {
        $now
    }

    # Filter parameters
    $filter = if ($Request) { $Request.QueryString['filter'] } else { $null }
    $category = if ($Request) { $Request.QueryString['category'] } else { $null }
    $severity = if ($Request) { $Request.QueryString['severity'] } else { $null }
    $source = if ($Request) { $Request.QueryString['source'] } else { $null }
    $userID = if ($Request) { $Request.QueryString['userID'] } else { $null }
    $sessionID = if ($Request) { $Request.QueryString['sessionID'] } else { $null }
    $activityName = if ($Request) { $Request.QueryString['activityName'] } else { $null }
    $runspaceID = if ($Request) { $Request.QueryString['runspaceID'] } else { $null }

    # Sort parameters
    $sortBy = if ($Request -and $Request.QueryString['sortBy']) { $Request.QueryString['sortBy'] } else { 'Date' }
    $sortOrder = if ($Request -and $Request.QueryString['sortOrder']) { $Request.QueryString['sortOrder'] } else { 'desc' }

    # Count limit
    $count = if ($Request -and $Request.QueryString['count']) {
        [int]$Request.QueryString['count']
    } else {
        1000
    }

    # Use Read-PSWebHostLog to get logs with time range
    $logs = Read-PSWebHostLog -StartTime $earliest -EndTime $latest

    # Apply additional filters if specified
    if ($logs) {
        if ($filter) {
            $filterLower = $filter.ToLower()
            $logs = $logs | Where-Object {
                ($_.Message -and $_.Message.ToLower().Contains($filterLower)) -or
                ($_.Category -and $_.Category.ToLower().Contains($filterLower)) -or
                ($_.Severity -and $_.Severity.ToLower().Contains($filterLower)) -or
                ($_.Source -and $_.Source.ToLower().Contains($filterLower)) -or
                ($_.UserID -and $_.UserID.ToLower().Contains($filterLower)) -or
                ($_.Data -and $_.Data.ToLower().Contains($filterLower))
            }
        }

        if ($category) {
            $logs = $logs | Where-Object { $_.Category -like $category }
        }

        if ($severity) {
            $logs = $logs | Where-Object { $_.Severity -like $severity }
        }

        if ($source) {
            $logs = $logs | Where-Object { $_.Source -like $source }
        }

        if ($userID) {
            $logs = $logs | Where-Object { $_.UserID -like $userID }
        }

        if ($sessionID) {
            $logs = $logs | Where-Object { $_.SessionID -like $sessionID }
        }

        if ($activityName) {
            $logs = $logs | Where-Object { $_.ActivityName -like $activityName }
        }

        if ($runspaceID) {
            $logs = $logs | Where-Object { $_.RunspaceID -like $runspaceID }
        }

        # Sort logs
        $sortProperty = switch ($sortBy) {
            'Date' { { [DateTime]::Parse($_.LocalTime) } }
            'Severity' { { $_.Severity } }
            'Category' { { $_.Category } }
            'Source' { { $_.Source } }
            'UserID' { { $_.UserID } }
            'SessionID' { { $_.SessionID } }
            default { { [DateTime]::Parse($_.LocalTime) } }
        }

        if ($sortOrder -eq 'asc') {
            $logs = $logs | Sort-Object -Property $sortProperty
        } else {
            $logs = $logs | Sort-Object -Property $sortProperty -Descending
        }

        # Limit count
        $logs = $logs | Select-Object -First $count
    }

    # Format response
    $responseData = @{
        status = 'success'
        timeRange = @{
            earliest = $earliest.ToString('o')
            latest = $latest.ToString('o')
            minutes = $timeRange
        }
        filters = @{
            filter = $filter
            category = $category
            severity = $severity
            source = $source
            userID = $userID
            sessionID = $sessionID
            activityName = $activityName
            runspaceID = $runspaceID
        }
        sorting = @{
            sortBy = $sortBy
            sortOrder = $sortOrder
        }
        totalCount = if ($logs) { ($logs | Measure-Object).Count } else { 0 }
        requestedCount = $count
        logs = if ($logs) { @($logs) } else { @() }
    }

    $jsonData = $responseData | ConvertTo-Json -Depth 10 -Compress

    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        Write-Host "Content-Type: application/json" -ForegroundColor Gray
        Write-Host "`nResponse Data:" -ForegroundColor Cyan
        $responseData | ConvertTo-Json -Depth 10 | Write-Host
        Write-Host "`n=== Summary ===" -ForegroundColor Cyan
        Write-Host "Total Events: $($responseData.totalCount)" -ForegroundColor Yellow
        Write-Host "Time Range: $($responseData.timeRange.minutes) minutes" -ForegroundColor Yellow
        Write-Host "Earliest: $($responseData.timeRange.earliest)" -ForegroundColor Gray
        Write-Host "Latest: $($responseData.timeRange.latest)" -ForegroundColor Gray
        if ($responseData.filters.filter) { Write-Host "Text Filter: $($responseData.filters.filter)" -ForegroundColor Yellow }
        if ($responseData.filters.category) { Write-Host "Category: $($responseData.filters.category)" -ForegroundColor Yellow }
        if ($responseData.filters.severity) { Write-Host "Severity: $($responseData.filters.severity)" -ForegroundColor Yellow }
        Write-Host "Sort By: $($responseData.sorting.sortBy) ($($responseData.sorting.sortOrder))" -ForegroundColor Yellow
        return
    }

    context_response -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"

    # Log the request
    Write-PSWebHostLog -Severity Verbose -Category EventViewer -Message "Event log request: $($responseData.totalCount) events returned" -Data @{
        TimeRange = $timeRange
        Filters = $responseData.filters
        ResultCount = $responseData.totalCount
    }
}
catch {
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Error ===" -ForegroundColor Red
        Write-Host "Exception: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "Stack Trace:" -ForegroundColor Gray
        Write-Host $_.ScriptStackTrace
        return
    }

    Write-PSWebHostLog -Severity Error -Category EventViewer -Message "Error processing event log request: $($_.Exception.Message)"

    # Generate detailed error report
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
