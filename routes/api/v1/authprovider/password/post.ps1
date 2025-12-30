param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata = $Global:PSWebSessions[$Context.Request.Cookies["PSWebSessionID"].Value]
)
$MyTag = '[routes\api\v1\authprovider\password\post.ps1]'

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database") -DisableNameChecking 3>$null 4>$null
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication") -DisableNameChecking 3>$null 4>$null
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Support") -DisableNameChecking 3>$null 4>$null

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
    Write-Host "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Processing Password authentication POST from $($ipAddress)"
    $bodyContent = Get-RequestBody -Request $Request
    $parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
    $email = $parsedBody["email"]
    $password = $parsedBody["password"]
    $redirectTo = $parsedBody["RedirectTo"]

    [string[]]$Fail = @()
    $IsEmailValid = Test-IsValidEmailAddress -Email $email
    if ([string]::IsNullOrEmpty($email)) {
        $fail+='<p class="error">Email is required.</p>'
    } elseif (-not ($IsEmailValid.isValid)) {
        $Fail += "<p class=""error"">$($IsEmailValid.Message)</p>"
    }

    if ([string]::IsNullOrEmpty($password)) {
        $fail+='<p class="error">Password is required.</p>'
    } else {
        $passwordValidation = Test-IsValidPassword -Password $password
        if (-not $passwordValidation.IsValid) {
            $Fail += "<p class='error'>$($passwordValidation.Message)</p>"
        }
    }

    if ($Fail.count -ne 0) {
        write-pswebhostlog -Severity 'Warning' -Category 'Auth' -Message "$MyTag Validation failed for Password auth POST from $ipAddress. Errors: $($Fail -join '; ')" -Data @{ IPAddress = $ipAddress; Body = $bodyContent } -WriteHost
        $jsonResponse = New-JsonResponse -status 'fail' -message ($Fail -join '<br>')
        context_reponse -Response $Response -StatusCode 422 -String $jsonResponse -ContentType "application/json"
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

        # MFA FLOW DISABLED - Completing login directly.
        Write-Warning "MFA check has been temporarily disabled in this route."
        Set-PSWebSession -SessionID $sessionID -UserID $user.UserID -Roles $user.Roles -Provider 'Password' -Request $Request
        
        $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
        context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl

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