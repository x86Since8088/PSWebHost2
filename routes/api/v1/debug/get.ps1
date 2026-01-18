param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Serve the debug.html file directly.
# context_response will handle the file check, 404 status, and content type automatically.
$debugHtmlPath = Join-Path $PSScriptRoot 'debug.html'
context_response -Response $Response -Path $debugHtmlPath