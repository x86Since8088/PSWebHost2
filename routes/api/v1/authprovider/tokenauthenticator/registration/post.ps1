param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
# This script requires functions for TOTP validation, encryption, and database interaction.
# Example placeholder functions:
# function Test-TotpCode { param($Secret, $Code) ... returns $bool }
# function Protect-String { param($PlainText) ... returns $encryptedString }
# function New-RecoveryCodes { ... returns $arrayOfCodes }
#endregion

# Ensure user is logged in
if (-not $SessionData.UserID) {
    context_reponse -Response $Response -StatusCode 401 -String (@{message='Unauthorized'} | ConvertTo-Json) -ContentType "application/json"
    return
}

# 1. Get submitted code and pending secret
$body = ($Request.InputStream | New-Object System.IO.StreamReader).ReadToEnd()
$form = [System.Web.HttpUtility]::ParseQueryString($body)
$code = $form["code"]

$pendingSecret = $SessionData.PendingTwoFactorSecret
if (-not $pendingSecret) {
    context_reponse -Response $Response -StatusCode 400 -String (@{message='No pending registration found. Please start over.'} | ConvertTo-Json) -ContentType "application/json"
    return
}

# 2. Verify the code
# This assumes a Test-TotpCode function is available
$isValid = Test-TotpCode -Secret $pendingSecret.Secret -Code $code

if ($isValid) {
    # 3. On success, save the provider data
    $user = Get-PSWebHostUser -UserID $SessionData.UserID

    # Encrypt the secret before storing it
    $encryptedSecret = Protect-String -PlainText $pendingSecret.Secret

    # Generate and hash recovery codes
    $recoveryCodes = New-RecoveryCodes
    $hashedRecoveryCodes = $recoveryCodes | ForEach-Object { Hash-String -String $_ } # Assumes Hash-String exists

    # Construct the data payload for the provider
    $providerData = @{
        Secret = $encryptedSecret
        RecoveryCodes = $hashedRecoveryCodes
        Enabled = $true
    }

    # Save the provider data using the new function
    Set-PSWebAuthProvider -UserID $user.UserID -Provider 'tokenauthenticator' -Data $providerData

    # 4. Clean up session and return recovery codes to the user
    $SessionData.Remove("PendingTwoFactorSecret")
    $jsonResponse = @{ message = "MFA enabled successfully!"; recoveryCodes = $recoveryCodes } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 200 -String $jsonResponse -ContentType "application/json"

} else {
    # 5. On failure
    context_reponse -Response $Response -StatusCode 400 -String (@{message='Invalid code. Please try again.'} | ConvertTo-Json) -ContentType "application/json"
}
