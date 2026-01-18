param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$userID = $Request.QueryString["UserID"]
if (-not $userID) {
    context_response -Response $Response -StatusCode 400 -String "UserID is required."
    return
}

$multipart = Parse-MultipartFormData -Request $Request
$formData = $multipart.FormData
$files = $multipart.Files

$updateData = @{}
if ($formData.UserName) { $updateData.UserName = $formData.UserName }
if ($formData.Email) { $updateData.Email = $formData.Email }
if ($formData.Phone) { $updateData.Phone = $formData.Phone }

if ($updateData.Count -gt 0) {
        $setClauses = $updateData.Keys | ForEach-Object {
        $value = $updateData[$_]
        $safeValue = Sanitize-SqlQueryString -String $value
        "`"$_`" = '$safeValue'"
    }
    $setStatement = $setClauses -join ", "
    $safeUserID = Sanitize-SqlQueryString -String $userID
    $query = "UPDATE Users SET $setStatement WHERE UserID COLLATE NOCASE = '$safeUserID';"
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query $query
}

if ($files.profileImage) {
    $userDir = Join-Path $Global:PSWebServer.Project_Root.Path "public/users/$userID"

    $makeIconsScript = Join-Path $Global:PSWebServer.Project_Root.Path "system/graphics/MakeIcons.ps1"
    & $makeIconsScript -bytes $files.profileImage.Content -OutputDir $userDir -Name "profile"
}

$safeUserID = Sanitize-SqlQueryString -String $userID
$user = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT * FROM Users WHERE UserID COLLATE NOCASE = '$safeUserID';"
$responseString = $user | ConvertTo-Json -Depth 5
context_response -Response $Response -String $responseString -ContentType "application/json"