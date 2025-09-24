param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    [hashtable]$SessionData = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Support/PSWebHost_Support.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "system/auth/TestToken.ps1") -DisableNameChecking

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Get state from query parameters
$state = $Request.QueryString["state"]

# 1. Get Request Data
$ipAddress = $Request.RemoteEndPoint.Address.ToString()
$bodyContent = ""
$email = $null
$password = $null
$redirectTo = $null

try {
    if ($Request.HasEntityBody) {
        $reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
        $bodyContent = $reader.ReadToEnd()
        $reader.Close()

        $parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
        $email = $parsedBody["email"]
        $password = $parsedBody["password"]
        $redirectTo = $parsedBody["RedirectTo"]
    }

    [string[]]$Fail = @()
    $IsEmailValid = Test-IsValidEmailAddress -Email $email
    if ([string]::IsNullOrEmpty($email)) {
        $fail+='Email is required.'
    } elseif (-not ($IsEmailValid.isValid)) {
        $Fail += $IsEmailValid.Message
    }

    if ([string]::IsNullOrEmpty($password)) {
        $fail+='Password is required.'
    } else {
        $passwordValidation = Test-IsValidPassword -Password $password
        if (-not $passwordValidation.IsValid) {
            $Fail += $passwordValidation.Message
        }
    }

    if ($Fail.count -ne 0) {
        $jsonResponse = New-JsonResponse -status 'fail' -message ($Fail -join '<br>')
        context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    # 2. Check for existing lockouts
    $lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $email
    if ($lockoutStatus.LockedOut) {
        $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
        $jsonResponse = New-JsonResponse -status 'fail' -message $lockoutStatus.Message
        $Response.AddHeader("Retry-After", $retryAfter)
        context_reponse -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
        return
    }

    # 3. Attempt Authentication
    $isAuthenticated = Invoke-AuthenticationMethod -Name "Password" -FormData @{ Username = $email; Password = $password }

    if ($isAuthenticated) {
        # --- On Success ---
        $user = Get-PSWebHostUser -Email $email
        $sessionID = $Context.Request.Cookies["PSWebSessionID"].Value

        # Check if user has MFA enabled
        $tokenProvider = Get-PSWebAuthProvider -UserID $user.UserID -Provider 'tokenauthenticator'

        if ($tokenProvider.Enabled) {
            # MFA is enabled. Set intermediate state and redirect to MFA challenge.
            TestToken -SessionID $sessionID -UserID $user.UserID -AuthenticationState 'mfa_required'
            $redirectUrl = "/api/v1/authprovider/tokenauthenticator/mfa.html?RedirectTo=$redirectTo"
            context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
        } else {
            # MFA is not enabled. Complete the login directly.
            TestToken -SessionID $sessionID -UserID $user.UserID -Completed
            $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
            context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
        }

    } else {
        # --- On Failure ---
        PSWebLogon -ProviderName "Password" -Result "Fail" -Request $Request -UserID $email
        
        $jsonResponse = New-JsonResponse -status 'fail' -message 'Authentication failed. Please check your credentials.'
        context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Auth' -Message "Invalid request body for Password auth POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent }
    PSWebLogon -ProviderName "Password" -Result "error" -Request $Request

    $jsonResponse = New-JsonResponse -status 'fail' -message "An internal error occurred: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}