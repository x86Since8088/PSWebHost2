param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    [string]$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value,
    $sessiondata = $global:PSWebSessions[$sessionID],
    [hashtable]$CardSettings
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication") -DisableNameChecking

# Helper function to create a JSON response
function New-JsonResponse($status, $message) {
    return @{ status = $status; Message = $message } | ConvertTo-Json
}

# Define the email form with a cancel button
$emailForm = @"
<form id="emailForm">
    <p>Please enter your email address to continue.</p>
    <input type="email" id="email" name="email" placeholder="your@email.com" required>
    <button type="submit" class="btn">Continue</button>
    <button type="button" class="btn" onclick="window.location.href='/spa'">Cancel</button>
</form>
"@
Write-Verbose "	[$($Psscriptroot -replace '^.*?([\/]routes[\/])','$1')] GET $((($SessionData|Inspect-Object | ConvertTo-YAML) -split "`n" -notmatch '^\s*Type:' -join "`n").trim("	"))"

# Read request body
$bodyContent = Get-RequestBody -Request $Request
$parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
$email = $parsedBody["email"]

if ([string]::IsNullOrEmpty($email)) {
    # --- Step 1: Initial check ---
    $isSessionValid = Validate-UserSession -Context $Context -SessionID $sessionID -Verbose
    if ($isSessionValid -and $SessionData.UserID) {
        $jsonResponse = New-JsonResponse -status 'success' -message "You are already logged in as $($SessionData.UserID)."
        context_response -Response $Response -String $jsonResponse -ContentType "application/json"
    } else {
        # Return email form
        $jsonResponse = New-JsonResponse -status 'continue' -message $emailForm
        context_response -Response $Response -String $jsonResponse -ContentType "application/json"
    }
} else {
    # --- Step 2: Email submitted ---
    $ipAddress = $Request.RemoteEndPoint.Address.ToString()

    # Validate email format
    $isEmailValid = Test-IsValidEmailAddress -Email $email
    if (-not $isEmailValid.isValid) {
        $errorMessage = "<p class=""error"">$($isEmailValid.Message)</p>" + $emailForm
        $jsonResponse = New-JsonResponse -status 'fail' -message $errorMessage
        Write-Verbose "Post"
        context_response -Response $Response -StatusCode 400 -String $jsonResponse -ContentType "application/json"
        return
    }

    # Check for lockouts
    $lockoutStatus = Test-LoginLockout -IPAddress $ipAddress -Username $email
    if ($lockoutStatus.LockedOut) {
        $retryAfter = $lockoutStatus.LockedUntil.ToString("o")
        $errorMessage = "<p class='error'>$($lockoutStatus.Message)</p>" + $emailForm
        $jsonResponse = New-JsonResponse -status 'fail' -message $errorMessage
        $Response.AddHeader("Retry-After", $retryAfter)
        context_response -Response $Response -StatusCode 429 -String $jsonResponse -ContentType "application/json"
        return
    }

    $authMethods = Get-UserAuthenticationMethods -Email $email
    if ($authMethods.Count -gt 0) {
        $buttonsHtml = "<div class='auth-methods'><h4>Select Authentication Method:</h4>"
        foreach ($method in $authMethods) {
            $encodedEmail = [System.Web.HttpUtility]::UrlEncode($email)
            $onClickUrl = "/api/v1/authprovider/$method?email=$encodedEmail"
            $buttonsHtml += "<button class='btn' onclick=`"window.location.href='$onClickUrl'`">$method</button>"
        }
        $buttonsHtml += "<button type='button' class='btn' onclick='window.location.reload()'>Cancel</button>"
        $buttonsHtml += "</div>"
        
        $jsonResponse = New-JsonResponse -status 'continue' -message $buttonsHtml
        context_response -Response $Response -String $jsonResponse -ContentType "application/json"
    } else {
        PSWebLogon -ProviderName "GetAuthToken" -Result "Fail" -Request $Request -UserID $email
        $errorMessage = '<p class="error">No user found with that email address, or no authentication methods configured.</p>' + $emailForm
        $jsonResponse = New-JsonResponse -status 'fail' -message $errorMessage
        context_response -Response $Response -StatusCode 404 -String $jsonResponse -ContentType "application/json"
    }
}
