param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$filePath = Join-Path $PSScriptRoot "file-explorer.html"

context_reponse -Response $Response -Path $filePath
