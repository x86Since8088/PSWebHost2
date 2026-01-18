param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    UI element endpoint for WebHost Realtime Events app
.DESCRIPTION
    Returns the metadata for the Real-time Events viewer component
.NOTES
    App: WebhostRealtimeEvents
    Version: 1.0.0
#>

try {
    # Return the card component metadata
    $cardInfo = @{
        component = 'realtime-events'
        scriptPath = '/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js'
        title = 'Real-time Events'
        description = 'Monitor PSWebHost events and logs in real-time with advanced filtering and sorting'
        version = '1.0.0'
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

    # Return JSON response using context_response helper
    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'RealtimeEvents' -Message "Error loading realtime-events endpoint: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
