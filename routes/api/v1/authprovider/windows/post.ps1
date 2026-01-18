[cmdletbinding()]
param (
    [System.Net.HttpListenerContext]$Context,
    $SessionData,
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
    Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Processing Windows authentication POST from $ipAddress" -WriteHost
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
        write-pswebhostlog -Severity 'Warning' -Category 'Auth' -Message "$MyTag Validation failed for Windows auth POST from $ipAddress. Errors: $($Fail -join '; ')" -Data @{ IPAddress = $ipAddress; Body = $bodyContent } -WriteHost
        $jsonResponse = New-JsonResponse -status 'fail' -message ($Fail -join '<br>')
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }
    $credential = [System.Management.Automation.PSCredential]::new($username, (ConvertTo-SecureString $password -AsPlainText -Force))
    $UserPrincipalName = $credential.GetNetworkCredential().UserName + '@' + ($credential.GetNetworkCredential().Domain -replace '')

    # 2. Check for existing lockouts
    $lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $username
    write-pswebhostlog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Lockout status for $username from $ipAddress`: LockedOut=$(($lockoutStatus).LockedOut); Message='$(($lockoutStatus).Message)'" -Data @{ 
            IPAddress = $ipAddress; 
            Username = $username 
            lockoutStatus = $lockoutStatus
            retryAfter = ($lockoutStatus).LockedUntil|Where-Object{$_}|ForEach-Object{$_.ToString("o")}
        } -WriteHost
    if ($lockoutStatus.LockedOut) {
        $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
        $jsonResponse = New-JsonResponse -status 'fail' -message "<p class='error'>$($lockoutStatus.Message)</p>"
        $Response.AddHeader("Retry-After", $retryAfter)
        context_response -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
        return
    }

    # 3. Attempt Authentication
    $credential = New-Object System.Management.Automation.PSCredential($username, (ConvertTo-SecureString $password -AsPlainText -Force))
    if ($null -eq $global:PSWebServer -or $null -eq $global:PSWebServer.Project_Root) {
        throw "PSWebServer global variable is not initialized in runspace"
    }
    $AuthTestScript = Join-Path $global:PSWebServer.Project_Root.Path "\system\auth\Test-PSWebWindowsAuth.ps1"
    Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Running Test-PSWebWindowsAuth.ps1" -WriteHost
    $isAuthenticated = & $AuthTestScript -credential $credential
    Write-PSWebHostLog -Severity 'Verbose' -Category 'Auth' -Message "$MyTag Completed Test-PSWebWindowsAuth.ps1 - Result: $isAuthenticated" -WriteHost

    if ($isAuthenticated) {
        # --- On Success ---
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Authentication successful for $($UserPrincipalName)."

        # MFA FLOW DISABLED - Completing login directly.
        Write-Warning "$MyTag MFA check has been temporarily disabled in this route."

        # Look up user by Email (UPN) to get the actual UserID (GUID)
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Looking up user by Email: $($UserPrincipalName)"
        $user = Get-PSWebUser -Email $UserPrincipalName
        if (-not $user) {
            Write-Error "$($MyTag) User not found in database for Email: $($UserPrincipalName). User must be registered before Windows authentication."
            $jsonResponse = New-JsonResponse -status 'fail' -message '<p class="error">User not found. Please contact administrator to register your Windows account.</p>'
            context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
            return
        }
        $actualUserID = $user.UserID
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Found user with UserID: $($actualUserID)"

        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: Set-PSWebSession -SessionID `$sessionID -UserID $($actualUserID) -Provider 'Windows' -Request `$Request"
        Set-PSWebSession -SessionID $sessionID -UserID $actualUserID -Provider 'Windows' -Request $Request
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: Set-PSWebSession"

        # Re-set the session cookie explicitly on the response to ensure browser will send it after redirect
        try {
            $cookie = New-Object System.Net.Cookie('PSWebSessionID', $sessionID)
            $hostName = $Request.Url.HostName
            if ($hostName -notmatch '^(localhost|(\d{1,3}\.){3}\d{1,3}|::1)$') { $cookie.Domain = $hostName }
            $cookie.Path = '/'
            $cookie.HttpOnly = $true
            $cookie.Expires = (Get-Date).AddDays(7)
            $cookie.Secure = $Request.IsSecureConnection
            $Response.AppendCookie($cookie)
            Write-Verbose "$($MyTag) Appended Set-Cookie for session on auth success: $($sessionID)"
        } catch {
            Write-Verbose "$($MyTag) Failed to append cookie on auth success: $($_)"
        }

        $redirectUrl = "/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo"
        context_response -Response $Response -StatusCode 302 -RedirectLocation $redirectUrl
    } else {
        # --- On Failure ---
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Calling: PSWebLogon -ProviderName ""Windows"" -Result ""Fail"" -Request `$Request -UserID $($username)"
        PSWebLogon -ProviderName "Windows" -Result "Fail" -Request $Request -UserID $username
        Write-Verbose "$($MyTag) $((Get-Date -f 'yyyMMdd HH:mm:ss')) Completed: PSWebLogon"
        
        $jsonResponse = New-JsonResponse -status 'fail' -message '<p class="error">Authentication failed. Please check your credentials.</p>'
        context_response -Response $Response -StatusCode 401 -String $jsonResponse -ContentType "application/json"
    }
} catch {
    write-pswebhostlog -Severity 'Error' -Category 'Auth' -Message "$($MyTag) Exception during Windows authentication POST: $($_.Exception.Message)" -Data @{ IPAddress = $ipAddress; Body = $bodyContent } -WriteHost
    PSWebLogon -ProviderName "Windows" -Result "error" -Request $Request

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}