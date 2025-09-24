param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$body = Get-RequestBody -Request $Request
$userData = $body | ConvertFrom-Json

# Basic validation
if (-not $userData.UserName) {
    context_reponse -Response $Response -StatusCode 400 -String "UserName is required."
    return
}

$newUserID = [Guid]::NewGuid().ToString()

$newUser = @{
    UserID = $newUserID
    UserName = $userData.UserName
    Email = $userData.Email
    Phone = $userData.Phone
}

New-PSWebSQLiteData -File "pswebhost.db" -Table "Users" -Data $newUser

$responseString = $newUser | ConvertTo-Json -Depth 5
context_reponse -Response $Response -String $responseString -ContentType "application/json"
