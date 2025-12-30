param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

Write-Warning "The token-based MFA feature is currently disabled due to incomplete implementation."
context_reponse -Response $Response -StatusCode 501 -String "MFA feature is not implemented."
