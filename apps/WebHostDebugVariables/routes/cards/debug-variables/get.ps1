param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Return card metadata (not HTML)
    $cardInfo = @{
        component = 'debug-variables'
        scriptPath = '/apps/WebHostDebugVariables/public/elements/debug-variables/component.js'
        stylePath = $null
        title = 'Debug Variables'
        description = 'View and monitor PowerShell variables in real-time'
        version = '1.0.0'
        width = 12
        height = 10
        features = @(
            'Real-time variable monitoring'
            'Variable value inspection'
            'Type information display'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVariables' -Message "Error loading debug-variables card: $($_.Exception.Message)"

    $errorResponse = @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    }

    context_response -Response $Response -StatusCode 500 -String ($errorResponse | ConvertTo-Json) -ContentType "application/json"
}
