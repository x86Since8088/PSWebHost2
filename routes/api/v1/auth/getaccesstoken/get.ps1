param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [string]$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value,
    [hashtable]$SessionData = $global:PSWebSessions[$sessionID]
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Support/PSWebHost_Support.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "system/auth/TestToken.ps1") -DisableNameChecking

$redirectTo = $Request.QueryString["RedirectTo"]
[string]$state = $Request.QueryString["state"]

# This script is the final step. It validates that a login flow was completed and then issues the access token.
Write-Verbose "[getaccesstoken/get.ps1] Validating for a completed session with SessionID $sessionID."
$completedSession = TestToken -SessionID $sessionID -State 'completed'

if ($completedSession) {
    Write-Verbose "[getaccesstoken/get.ps1] Completed session found for UserID $($completedSession.UserID). Granting access token."
    # The user has successfully completed an auth flow.
    # Update the main session with the correct UserID from the completed login session.
    $SessionData.UserID = $completedSession.UserID

    # Generate and store access token
    $accessToken = "real-access-token-" + (-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 64 | ForEach-Object { [char]$_ }))
    $SessionData.AccessToken = $accessToken
    $SessionData.AccessTokenExpiration = (Get-Date).AddHours(1)

    # Redirect to the final destination
    if ($redirectTo) {
        [string[]]$redirectUrls = $redirectTo.Split(',') | ForEach-Object { [System.Web.HttpUtility]::UrlDecode($_) }
        $finalRedirectUrl = $redirectUrls[0]
        context_reponse -Response $Response -StatusCode 302 -RedirectLocation $finalRedirectUrl
    } else {
        # If no redirect is specified, return a success message
        context_reponse -Response $Response -StatusCode 200 -String "Login complete. Access token granted."
    }
    return
} else {
    # No completed authentication flow found for this session.
    # Redirect back to the beginning of the login process.
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=$redirectTo&error=AuthIncomplete"
    return
}
