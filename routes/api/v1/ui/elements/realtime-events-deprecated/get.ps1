param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    UI element wrapper for WebHost Realtime Events app
.DESCRIPTION
    Returns the HTML/React component for the Real-time Events viewer
#>

# Check authentication
if (-not $sessiondata -or 'authenticated' -notin $sessiondata.Roles) {
    $jsonResponse = @{ status = 'fail'; message = 'Authentication required' } | ConvertTo-Json
    context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    return
}

try {
    # Return the card component metadata
    $cardInfo = @{
        component = 'realtime-events'
        title = 'Real-time Events'
        description = 'Monitor PSWebHost events and logs in real-time with advanced filtering and sorting'
        scriptPath = '/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js'
        width = 12  # Full width
        height = 600
        features = @(
            'Time range filtering (5 min to 24 hours)'
            'Custom date/time range'
            'Text search across all fields'
            'Category, Severity, Source filtering'
            'User ID and Session ID filtering'
            'Sortable columns'
            'CSV/TSV export'
            'Column visibility toggle'
            'Auto-refresh (5s interval)'
            'Enhanced log format support'
        )
    }

    $jsonData = $cardInfo | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity Error -Category EventViewer -Message "Error loading realtime-events card: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
