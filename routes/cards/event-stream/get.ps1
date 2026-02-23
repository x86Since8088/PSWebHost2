param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Return card metadata for event-stream component
    $cardInfo = @{
        component = 'event-stream'
        scriptPath = '/public/elements/event-stream/component.js'
        title = 'Event Stream'
        description = 'Real-time event log viewer with filtering and export capabilities'
        version = '1.0.0'
        width = 12
        height = 600
        features = @(
            'Real-time event log streaming'
            'Advanced filtering by text, date range'
            'Column visibility toggle'
            'Auto-refresh capability'
            'Event selection and export'
            'Customizable display options'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'EventStream' -Message "Error loading event-stream card: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
