param ([System.Net.HttpListenerContext]$Context, [System.Net.HttpListenerRequest]$Request=$Context.Request, [System.Net.HttpListenerResponse]$Response=$Context.Response)

# Placeholder for O365 authentication
context_response -Response $Response -StatusCode 501 -String 'O365 authentication is not yet implemented.'