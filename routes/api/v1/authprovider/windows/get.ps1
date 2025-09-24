param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    [hashtable]$SessionData
)

#Get State and RedirectTo from query parameters
$state = $Request.QueryString["state"]
$redirectTo = $Request.QueryString["RedirectTo"]

# Check if the user is authenticated

$isSessionValid = Validate-UserSession -Context $Context
if ($isSessionValid -and ($SessionData.UserID -match '\S{4,256}')) {
    # Redirect back to getaccesstoken
    $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
    return
}

# Serve the login.html file.
$loginHtmlPath = Join-Path $PSScriptRoot 'login.html'
context_reponse -Response $Response -Path $loginHtmlPath