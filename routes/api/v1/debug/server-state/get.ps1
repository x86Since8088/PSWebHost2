param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    $diagnostics = @{
        PSWebServer_Exists = $null -ne $Global:PSWebServer
        LogDirectory = $Global:PSWebServer.LogDirectory
        LogFilePath = $Global:PSWebServer.LogFilePath
        Project_Root = $Global:PSWebServer.Project_Root.Path
        LogDirectory_Exists = if ($Global:PSWebServer.LogDirectory) { Test-Path $Global:PSWebServer.LogDirectory } else { $false }
        LogFile_Exists = if ($Global:PSWebServer.LogFilePath) { Test-Path $Global:PSWebServer.LogFilePath } else { $false }
    }

    $jsonResponse = $diagnostics | ConvertTo-Json -Depth 5 -Compress
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"
} catch {
    $errorResponse = @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    } | ConvertTo-Json -Compress
    context_reponse -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
