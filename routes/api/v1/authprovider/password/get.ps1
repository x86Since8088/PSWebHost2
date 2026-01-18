param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response
)

$loginHtmlPath = Join-Path $PSScriptRoot 'login.html'
context_response -Response $Response -Path $loginHtmlPath