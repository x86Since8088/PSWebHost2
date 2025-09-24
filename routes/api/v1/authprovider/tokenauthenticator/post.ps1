param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
# This script requires functions for TOTP validation and decryption.
# Example placeholder functions:
# function Test-TotpCode { param($Secret, $Code) ... returns $bool }
# function Unprotect-String { param($EncryptedString) ... returns $plainText }
#endregion

# 1. Verify that we are in the 'mfa_required' state.
$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value
$mfaSession = TestToken -SessionID $sessionID -State 'mfa_required'

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
# This is a conceptual query
$dbUser = (Get-PSWebSQLiteData -Query "SELECT * FROM Users WHERE UserID = '$($user.UserID)'")
$encryptedSecret = $dbUser.TwoFactorSecret
$secret = Unprotect-String -EncryptedString $encryptedSecret

# 4. Validate the code
$isValid = Test-TotpCode -Secret $secret -Code $code

if ($isValid) {
    # 5. On success, complete the login flow
    TestToken -SessionID $sessionID -UserID $user.UserID -Completed
    
    # Redirect to get the final access token. RedirectTo should be handled by getaccesstoken.
    $redirectTo = $Request.QueryString["RedirectTo"] # Pass along if present
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getaccesstoken?RedirectTo=$redirectTo"

} else {
    # 6. On failure, return an error
    # We put the mfa_required state back so the user can try again.
    TestToken -SessionID $sessionID -UserID $user.UserID -AuthenticationState 'mfa_required'
    context_reponse -Response $Response -StatusCode 400 -String (@{message='Invalid code.'} | ConvertTo-Json) -ContentType "application/json"
}
