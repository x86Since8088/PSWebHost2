param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response
)



#Get State and RedirectTo from query parameters
$state = $Request.QueryString["state"]
$redirectTo = $Request.QueryString["RedirectTo"]

# Check if the user is authenticated
$sessionID = $request.Cookies["PSWebSessionID"].Value
$SessionData = Get-PSWebSessions -SessionID $sessionID
$isSessionValid = Validate-UserSession -Context $Context -Verbose
if ($isSessionValid -and ($SessionData.ID -match '\S{4,256}')) {
    # Redirect back to getaccesstoken
    $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
    Write-Verbose "`t[authprovider\windows\get.ps1] isSessionValid: $isSessionValid `n`t`t$(($SessionData|Inspect-Object | ConvertTo-YAML) -split '`n' -notmatch '^\s*Type:' -join "`n`t`t")"
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
    return
}
else {
    Write-Verbose "`t[authprovider\windows\get.ps1] isSessionValid: $isSessionValid `n`t`t$(($SessionData|Inspect-Object -Depth 4| ConvertTo-YAML) -split '`n' -notmatch '^\s*Type:' -join "`n`t`t")"
}

# Serve the login.html file.
$loginHtmlPath = Join-Path $PSScriptRoot 'login.html'
context_reponse -Response $Response -Path $loginHtmlPath