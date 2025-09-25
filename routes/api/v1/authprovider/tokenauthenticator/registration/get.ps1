param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
# This script uses functions from the TOTP and QRCodeGenerator modules.
# These are expected to be downloaded by Validate3rdPartyModules.ps1
try {
    Import-Module -Name TOTP -ErrorAction Stop
    Import-Module -Name QRCodeGenerator -ErrorAction Stop
} catch {
    $errorMessage = "Required MFA modules (TOTP, QRCodeGenerator) not found. Please run validation scripts. Error: $($_.Exception.Message)"
    Write-Error $errorMessage
    context_reponse -Response $Response -StatusCode 500 -String $errorMessage
    return
}
#endregion

# Ensure user is logged in before allowing MFA registration
if (-not $SessionData.UserID) {
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=/profile/security"
    return
}

$user = Get-PSWebHostUser -UserID $SessionData.UserID

# Handle QR code request from the HTML page
if ($Request.QueryString.Get("qrcode") -eq "true") {
    $secretObject = $SessionData.PendingTwoFactorSecret
    if ($secretObject) {
        $tempFile = New-TemporaryFile
        try {
            New-QRCode -TextInput $secretObject.SetupUri -OutFile $tempFile.FullName -ImageFormat Png
            $qrCodeBytes = [System.IO.File]::ReadAllBytes($tempFile.FullName)
            context_reponse -Response $Response -StatusCode 200 -Bytes $qrCodeBytes -ContentType "image/png"
        } finally {
            Remove-Item $tempFile -Force
        }
    } else {
        context_reponse -Response $Response -StatusCode 404
    }
    return
}

# --- Main logic: Generate a new secret and display the page ---

# 1. Generate a new TOTP Secret
$issuer = "PsWebHost"
$secretObject = New-GATotpSecret -Account $user.Email -Issuer $issuer

# 2. Store the secret object temporarily in the session for verification later
# We store the whole object as it contains the SetupUri for the QR code
$SessionData.PendingTwoFactorSecret = $secretObject

# 3. Serve the registration page
$registerPagePath = Join-Path $PSScriptRoot 'register.html'
$registerPageContent = Get-Content -Path $registerPagePath -Raw

# 4. Inject the secret key into the HTML for manual entry
$registerPageContent = $registerPageContent.Replace('<!-- Secret key will be loaded here by get.ps1 -->', $secretObject.Secret)

context_reponse -Response $Response -StatusCode 200 -String $registerPageContent -ContentType "text/html"