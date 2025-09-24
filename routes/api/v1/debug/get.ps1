param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    [hashtable]$SessionData
)

# Serve the debug.html file directly.
# context_reponse will handle the file check, 404 status, and content type automatically.
$debugHtmlPath = Join-Path $PSScriptRoot 'debug.html'
context_reponse -Response $Response -Path $debugHtmlPath