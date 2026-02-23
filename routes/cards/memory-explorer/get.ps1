param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Return card metadata (not HTML)
    $cardInfo = @{
        component = 'memory-explorer'
        scriptPath = '/public/elements/memory-explorer/component.js'
        stylePath = '/public/elements/memory-explorer/style.css'
        title = 'Memory Explorer'
        description = 'Advanced memory analysis and exploration tool for PowerShell objects'
        version = '1.0.0'
        width = 12
        height = 14
        features = @(
            'Analyze memory consumption of PowerShell objects'
            'View object graphs and relationships'
            'Calculate type memory overhead'
            'Inspect assembly memory usage'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'MemoryExplorer' -Message "Error loading memory-explorer card: $($_.Exception.Message)"

    $errorResponse = @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    }

    context_response -Response $Response -StatusCode 500 -String ($errorResponse | ConvertTo-Json) -ContentType "application/json"
}
