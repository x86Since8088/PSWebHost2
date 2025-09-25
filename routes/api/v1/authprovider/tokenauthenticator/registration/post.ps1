param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

#region Dependencies
try {
    Import-Module -Name TOTP -ErrorAction Stop
} catch {
    $errorMessage = "Required MFA module (TOTP) not found. Please run validation scripts. Error: $($_.Exception.Message)"
    Write-Error $errorMessage
    context_reponse -Response $Response -StatusCode 500 -String $errorMessage
    return
}
#endregion

#region Helper Functions
function New-RecoveryCodes {
    # Generate 8 user-friendly recovery codes
    $wordList = "alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel", "india", "juliett", "kilo", "lima", "mike", "november", "oscar", "papa", "quebec", "romeo", "sierra", "tango", "uniform", "victor", "whiskey", "xray", "yankee", "zulu"
    $codes = 1..8 | ForEach-Object {
        $part1 = $wordList | Get-Random
        $part2 = $wordList | Get-Random
        $number = Get-Random -Minimum 1000 -Maximum 9999
        "$part1-$part2-$number"
    }
    return $codes
}

function Hash-String {
    param([string]$String)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($String))
    return [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
}
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

$pendingSecretObject = $SessionData.PendingTwoFactorSecret
if (-not $pendingSecretObject) {
    context_reponse -Response $Response -StatusCode 400 -String (@{message='No pending registration found. Please start over.'} | ConvertTo-Json) -ContentType "application/json"
    return
}

# 2. Verify the code
$isValid = Test-GATotp -Secret $pendingSecretObject.Secret -Code $code

if ($isValid) {
    # 3. On success, save the provider data
    $user = Get-PSWebHostUser -UserID $SessionData.UserID

    # Encrypt the secret before storing it
    $encryptedSecret = Protect-String -PlainText $pendingSecretObject.Secret

    # Generate and hash recovery codes
    $recoveryCodes = New-RecoveryCodes
    $hashedRecoveryCodes = $recoveryCodes | ForEach-Object { Hash-String -String $_ }

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