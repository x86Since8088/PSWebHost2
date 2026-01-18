param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$errorMessage = "This endpoint is disabled due to a critical security vulnerability."
Write-Error $errorMessage
context_response -Response $Response -StatusCode 501 -String $errorMessage