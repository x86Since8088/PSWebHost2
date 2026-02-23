param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'debug-console'
        scriptPath = '/apps/WebHostDebugExtensions/public/elements/debug-console/component.js'
        title = 'Debug Console'
        description = 'Browser-side debugging and remote command execution'
        version = '1.0.0'
        width = 12
        height = 800
        features = @(
            'Remote JavaScript execution in browser'
            'Predefined diagnostic command library'
            'DOM inspection and manipulation'
            'Network endpoint testing'
            'Command history and result viewing'
            'Session-targeted command delivery'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "Error loading debug-console UI endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
