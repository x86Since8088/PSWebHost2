param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database") -DisableNameChecking

$refGuid = $Request.QueryString["ref"]
$responseIp = $Context.Request.RemoteEndPoint.Address.ToString()
$responseSessionId = $SessionData.SessionID

if ([string]::IsNullOrEmpty($refGuid)) {
    context_reponse -Response $Response -StatusCode 400 -String "Missing reference GUID."
    return
}

$safeRefGuid = Sanitize-SqlQueryString -String $refGuid
$query = "SELECT * FROM account_email_confirmation WHERE email_request_guid = '$safeRefGuid';"
$confirmationRequest = Get-PSWebSQLiteData -File "pswebhost.db" -Query $query

if (-not $confirmationRequest) {
    context_reponse -Response $Response -StatusCode 404 -String "Invalid confirmation link."
    return
}

if ($confirmationRequest.response_date) {
    context_reponse -Response $Response -String "This email address has already been confirmed."
    return
}

if ($confirmationRequest.request_ip -ne $responseIp -or $confirmationRequest.request_session_id -ne $responseSessionId) {
    $message = "Security check failed. You must confirm from the same browser and network you used to register."
    Write-PSWebHostLog -Severity 'Warning' -Category 'Registration' -Message $message -Data @{ Guid = $refGuid }
    context_reponse -Response $Response -StatusCode 403 -String $message
    return
}

# All checks passed, update the record
$responseDate = (Get-Date).ToString("s")
$updateData = @{
    response_date = $responseDate
    response_ip = $responseIp
    response_session_id = $responseSessionId
}
Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'UPDATE' -TableName 'account_email_confirmation' -Data $updateData -Where "email_request_guid = '$safeRefGuid'"

$successMessage = "Email confirmed successfully! You can now close this page."
context_reponse -Response $Response -String $successMessage