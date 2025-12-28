param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [string]$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value
    
)

# Import required modules
Import-Module PSWebHost_Database -DisableNameChecking
Import-Module PSWebHost_Authentication -DisableNameChecking
Import-Module PSWebHost_Support -DisableNameChecking
# Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "system/auth/TestToken.ps1") -DisableNameChecking

$redirectTo = $Request.QueryString["RedirectTo"]
$stringState = $Request.QueryString["state"]

# Ensure session data is loaded
$SessionData = Get-PSWebSessions -SessionID $sessionID

[string]$state = $stringState

# This script is the final step. It validates that a login flow was completed and then issues the access token.
# Write-Verbose "[getaccesstoken/get.ps1] Validating for a completed session with SessionID $sessionID."
$completedSession = Invoke-TestToken -SessionID $sessionID -State 'completed' -Verbose  -UserAgent $Request.UserAgent
 # Only treat a completed session as valid when it contains a real UserID (not empty or 'pending')
 if ($completedSession -and $completedSession.UserID -and $completedSession.UserID.Trim() -ne '' -and $completedSession.UserID -ne 'pending') {
     Write-Verbose "[getaccesstoken/get.ps1] Completed session found $($completedSession|ConvertTo-Json -Compress). Granting access token."
     # The user has successfully completed an auth flow.
     # Update the main session with the correct UserID and all aggregated roles.
     $user = Get-PSWebUser -UserID $completedSession.UserID
     if ($user) {
         Set-PSWebSession -SessionID $sessionID -UserID $user.UserID -Roles $user.Roles -Provider $completedSession.Provider -Request $Request
    } else {
          # This case is unlikely if the auth flow is working correctly.
          Write-PSWebHostLog -Severity 'Error' -Category 'Auth' -Message "Could not find user details for UserID '$($completedSession.UserID)' after a completed login flow."
          if ($completedSession.UserID -and $completedSession.UserID.Trim() -ne '') {
              # Use Set-PSWebSession to safely update the session store and DB
              Set-PSWebSession -SessionID $sessionID -UserID $completedSession.UserID -Provider $completedSession.Provider -Request $Request
          }
    }
     # Generate and store access token
     $accessToken = "real-access-token-" + (-join (((65..90) + (97..122) + (48..57) * 8) | Get-Random -Count 64 | ForEach-Object { [char]$_ }))
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
     # No valid completed authentication flow found for this session (either none, or the completed entry has no UserID).
     if ($completedSession -and (-not $completedSession.UserID -or $completedSession.UserID.Trim() -eq '' -or $completedSession.UserID -eq 'pending')) {
          Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "Completed login flow found for SessionID '$sessionID' but no valid UserID present; cannot grant access token."
     }
     # Redirect back to the beginning of the login process.
     context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/spa?error=LoginFlowDisabled"
     return
 }