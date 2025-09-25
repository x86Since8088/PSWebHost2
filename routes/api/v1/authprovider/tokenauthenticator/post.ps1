param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
try {
    Import-Module -Name OTP -ErrorAction Stop
} catch {
    $errorMessage = "Required MFA module (OTP) not found. Please run validation scripts. Error: $($_.Exception.Message)"
    Write-Error $errorMessage
    context_reponse -Response $Response -StatusCode 500 -String $errorMessage
    return
}
#endregion

# 1. Verify that we are in the 'mfa_required' state.
$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value
$mfaSession = Invoke-TestToken -SessionID $sessionID -State 'mfa_required'

if (-not $mfaSession) {
    context_reponse -Response $Response -StatusCode 400 -String (@{message='MFA challenge not initiated. Please log in first.'} | ConvertTo-Json) -ContentType "application/json"
    return
}

# 2. Get user and submitted code
$user = Get-PSWebHostUser -UserID $mfaSession.UserID
$body = ($Request.InputStream | New-Object System.IO.StreamReader).ReadToEnd()
$form = [System.Web.HttpUtility]::ParseQueryString($body)
$code = $form["code"]

# 3. Retrieve and decrypt the user's stored secret
$providerData = Get-PSWebAuthProvider -UserID $user.UserID -Provider 'tokenauthenticator'
if (-not $providerData -or -not $providerData.Secret) {
    context_reponse -Response $Response -StatusCode 500 -String (@{message='MFA is not configured correctly for this user.'} | ConvertTo-Json) -ContentType "application/json"
    return
}

$encryptedSecret = $providerData.Secret
$secret = Unprotect-String -EncryptedString $encryptedSecret

# 4. Validate the code
$expectedCode = Get-OTPCode -Secret $secret
$isValid = $expectedCode.Code -eq $code

if ($isValid) {
    # 5. On success, complete the login flow
    Invoke-TestToken -SessionID $sessionID -UserID $user.UserID -Completed
    
    # Redirect to get the final access token. RedirectTo should be handled by getaccesstoken.
    $redirectTo = $Request.QueryString["RedirectTo"] # Pass along if present
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getaccesstoken?RedirectTo=$redirectTo"

} else {
    # 6. On failure, return an error
    # We put the mfa_required state back so the user can try again.
    Invoke-TestToken -SessionID $sessionID -UserID $user.UserID -AuthenticationState 'mfa_required'
    context_reponse -Response $Response -StatusCode 400 -String (@{message='Invalid code.'} | ConvertTo-Json) -ContentType "application/json"
}