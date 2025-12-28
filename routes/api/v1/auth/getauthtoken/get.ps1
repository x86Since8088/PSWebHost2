param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response
)

# Import required modules
Import-Module PSWebHost_Support -DisableNameChecking
Import-Module PSWebHost_Database -DisableNameChecking
# Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "system/auth/TestToken.ps1") -DisableNameChecking


$sessionCookie = $Request.Cookies["PSWebSessionID"]
[string]$SessionID = $sessionCookie.Value
$SessionData = Get-PSWebSessions -SessionID $SessionID
$redirectTo = $Request.QueryString["RedirectTo"]
[string]$state = $Request.QueryString["state"]
if ([string]::IsNullOrEmpty($state)) {
    $state = (New-Guid).Guid
    $newUrl = "$($Request.Url.PathAndQuery)&state=$state"
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation $newUrl
    return
}

# If an existing logon has not expired for this session, redirect to getaccesstoken
$ValidateUserSession = Validate-UserSession -Context $Context -Verbose
Write-Verbose "`tValidateUserSession: $($ValidateUserSession)"

if ($ValidateUserSession) {
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
    return
} else {
    # Initiate a record for this authentication attempt
    Invoke-TestToken -SessionID $sessionCookie.Value -AuthenticationState 'initiated' -Provider 'GetAuthToken' -UserID 'pending' -UserAgent $Request.UserAgent -Verbose
}

$provider = $Request.QueryString["Provider"]
if (-not [string]::IsNullOrEmpty($provider)) {
    # A specific provider was requested, redirect to it.
    $redirectUrl = "/api/v1/authprovider/$provider?state=$state&RedirectTo=$redirectTo"
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
    return
}

# Serve the getauthtoken.html file.
$authHtmlPath = Join-Path $PSScriptRoot 'getauthtoken.html'
context_reponse -Response $Response -Path $authHtmlPath