param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$responseObject = @{
    user = $null
}

$isSessionValid = Validate-UserSession -Context $Context -SessionID $SessionData.SessionID -SessionData $SessionData -Verbose

if ($isSessionValid -and $SessionData.UserID) {
    $userRoles = Get-UserRoles -UserID $SessionData.UserID
    $responseObject.user = @{
        UserName = $SessionData.UserID
        Roles = $userRoles
    }
}

$jsonResponse = $responseObject | ConvertTo-Json
context_reponse -Response $Response -String $jsonResponse -ContentType "application/json"