# routes\spa\layout\get.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$projectRoot = $Global:PSWebServer.Project_Root.Path
$layoutPath = Join-Path $projectRoot "public/layout.json"

# context_response will handle the file check, 404 status, and content type automatically.
context_response -Response $Response -Path $layoutPath

