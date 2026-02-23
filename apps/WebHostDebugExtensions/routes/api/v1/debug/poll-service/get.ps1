param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Return debug poll service script
    $scriptPath = Join-Path $PSScriptRoot "..\..\..\..\..\public\debug-poll-service.js"

    if (-not (Test-Path $scriptPath)) {
        throw "Debug poll service script not found: $scriptPath"
    }

    $scriptContent = Get-Content $scriptPath -Raw

    context_response -Response $Response -String $scriptContent -ContentType "application/javascript; charset=utf-8"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "Error serving debug poll service: $($_.Exception.Message)"

    context_response -Response $Response -StatusCode 500 -String "Error loading debug poll service" -ContentType "text/plain"
}
