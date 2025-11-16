[cmdletbinding()]
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)
$MyTag = '[routes\api\v1\authprovider\windows\post.ps1]'
# Import required modules

Import-Module PSWebHost_Authentication -DisableNameChecking
Import-Module PSWebHost_Database -DisableNameChecking

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Get state and RedirectTo from query parameters
$state = $Request.QueryString["state"]
$redirectTo = $Request.QueryString["RedirectTo"]
$sessionID = $Request.Cookies["PSWebSessionID"].Value

# 1. Get Request Data
$ipAddress = $Request.RemoteEndPoint.Address.ToString()
$bodyContent = ""
$username = $null
$password = $null

try {
    $bodyContent = Get-RequestBody -Request $Request
    $parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
    $username = $parsedBody["username"]
    $password = $parsedBody["password"]

    if ($username -like '*@localhost') {
        $username = $username -replace '@localhost', ("@" + $Env:computername)
    }

    [string[]]$Fail = @()
    $IsUserNameValid = Test-IsValidEmailAddress -Email $username -AddCustomRegex '[a-zA-Z0-9._\+\-]+@[a-zA-Z0-9.\-]+'

    if ([string]::IsNullOrEmpty($username)) {
        $fail+='<p class="error">Username is required.</p>'
    } elseif (-not ($IsUserNameValid.isValid)) {
        $Fail += "<p class=""error"">$($IsUserNameValid.Message)</p>"
    }

    if ([string]::IsNullOrEmpty($password)) {
        $fail+='<p class="error">Password is required.</p>'
    } else {
        $passwordValidation = Test-IsValidPassword -Password $password -Numbers 0
        if (-not $passwordValidation.IsValid) {
            $Fail += "<p class='error'>$($passwordValidation.Message)</p>"
        }
    }

    if ($Fail.count -ne 0) {
        $jsonResponse = New-JsonResponse -status 'fail' -message ($Fail -join '<br>')
        context_reponse -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }
    $credential = [System.Management.Automation.PSCredential]::new($username, (ConvertTo-SecureString $password -AsPlainText -Force))
    $UserPrincipalName = $credential.GetNetworkCredential().UserName + '@' + ($credential.GetNetworkCredential().Domain -replace '')

    # 2. Check for existing lockouts
    $lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $username
    if ($lockoutStatus.LockedOut) {
        $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
        $jsonResponse = New-JsonResponse -status 'fail' -message "<p class='error'>$($lockoutStatus.Message)</p>"
        $Response.AddHeader("Retry-After", $retryAfter)
        context_reponse -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
        return
    }

    # 3. Attempt Authentication
    $credential = New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $password -AsPlainText -Force))
    $AuthTestScript = Join-Path $global:PSWebServer.Project_Root.Path "\system\auth\Test-PSWebWindowsAuth.ps1"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Running '\system\auth\Test-PSWebWindowsAuth.ps1'" 
    $isAuthenticated = & $AuthTestScript -credential $credential
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed '\system\auth\Test-PSWebWindowsAuth.ps1'" 

    if ($isAuthenticated) {
        # --- On Success ---
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Authentication successful for $UserPrincipalName."
        
        # MFA FLOW DISABLED - Completing login directly.
        Write-Warning "$MyTag MFA check has been temporarily disabled in this route."

        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Set-PSWebSession -SessionID `$sessionID -UserID $UserPrincipalName -Provider 'Windows' -Request `$Request"
        Set-PSWebSession -SessionID $sessionID -UserID $UserPrincipalName -Provider 'Windows' -Request $Request
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Set-PSWebSession"

        $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
        context_reponse -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
    } else {
        # --- On Failure ---
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: PSWebLogon -ProviderName "Windows" -Result "Fail" -Request `$Request -UserID $username"
        PSWebLogon -ProviderName "Windows" -Result "Fail" -Request $Request -UserID $username
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: PSWebLogon"
        
        $jsonResponse = New-JsonResponse -status 'fail' -message '<p class="error">Authentication failed. Please check your credentials.</p>'
        context_reponse -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Auth' -Message "Invalid request body for Windows auth POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent }
    PSWebLogon -ProviderName "Windows" -Result "error" -Request $Request

    $jsonResponse = New-JsonResponse -status 'fail' -message "An internal error occurred: $($_.Exception.Message)`n$($_.InvocationInfo.PositionMessage)"
    context_reponse -Response $Response -StatusCode 500 -String $jsonResponse -ContentType "application/json"
}