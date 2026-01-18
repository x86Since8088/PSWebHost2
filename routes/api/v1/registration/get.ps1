param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response
)

# Serve the registration.html file.
$registrationHtmlPath = Join-Path $PSScriptRoot 'registration.html'
context_response -Response $Response -Path $registrationHtmlPath
