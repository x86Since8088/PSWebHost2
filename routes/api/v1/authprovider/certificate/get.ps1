param ([System.Net.HttpListenerContext]$Context, [System.Net.HttpListenerRequest]$Request=$Context.Request, [System.Net.HttpListenerResponse]$Response=$Context.Response)

# Placeholder for Certificate authentication
context_reponse -Response $Response -StatusCode 501 -String 'Certificate authentication is not yet implemented.'