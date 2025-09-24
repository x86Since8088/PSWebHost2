param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
# This script requires functions for generating TOTP secrets and QR codes.
# These would typically be provided by a PowerShell module like PS-TOTP or a custom library.
# Example placeholder functions:
# function New-TotpSecret { param($Label, $Issuer) ... returns $secretObject }
# function New-QrCodeImage { param($Text) ... returns [byte[]] }
#endregion

# Ensure user is logged in before allowing MFA registration
if (-not $SessionData.UserID) {
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=/profile/security"
    return
}

$user = Get-PSWebHostUser -UserID $SessionData.UserID

# Handle QR code request from the HTML page
if ($Request.QueryString.Get("qrcode") -eq "true") {
    $secret = $SessionData.PendingTwoFactorSecret
    if ($secret) {
        # This assumes New-QrCodeImage function is available
        $qrCodeBytes = New-QrCodeImage -Text $secret.Uri
        context_reponse -Response $Response -StatusCode 200 -Bytes $qrCodeBytes -ContentType "image/png"
    } else {
        context_reponse -Response $Response -StatusCode 404
    }
    return
}

# --- Main logic: Generate a new secret and display the page ---

# 1. Generate a new TOTP Secret
# This assumes New-TotpSecret function is available
$issuer = "PsWebHost"
$secret = New-TotpSecret -Label $user.Email -Issuer $issuer

# 2. Store the secret temporarily in the session for verification later
$SessionData.PendingTwoFactorSecret = $secret

# 3. Serve the registration page
$registerPagePath = Join-Path $PSScriptRoot 'register.html'
$registerPageContent = Get-Content -Path $registerPagePath -Raw

# 4. Inject the secret key into the HTML for manual entry
$registerPageContent = $registerPageContent.Replace('<!-- Secret key will be loaded here by get.ps1 -->', $secret.Secret)

context_reponse -Response $Response -StatusCode 200 -String $registerPageContent -ContentType "text/html"
