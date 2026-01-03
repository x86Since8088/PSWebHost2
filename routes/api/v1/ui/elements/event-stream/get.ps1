
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

    # Initialize LogHistory if not exists
    if ($null -eq $Global:LogHistory) {
        $Global:LogHistory = [hashtable]::Synchronized(@{})
    }

    # Get all events from LogHistory (synchronized hashtable)
    # Convert hashtable values to array and sort by Index descending (newest first)
    $allEvents = @($Global:LogHistory.Values | Sort-Object -Property Index -Descending)

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
