param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$userID = $Request.QueryString["UserID"]
if (-not $userID) {
    context_reponse -Response $Response -StatusCode 400 -String "UserID is required."
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
    New-PSWebSQLiteDataByID -File "pswebhost.db" -Table "Users" -ID $userID -Columns $updateData
}

if ($files.profileImage) {
    $userDir = Join-Path $Global:PSWebServer.Project_Root.Path "public/users/$userID"
    
    $makeIconsScript = Join-Path $Global:PSWebServer.Project_Root.Path "system/graphics/MakeIcons.ps1"
    & $makeIconsScript -bytes $files.profileImage.Content -OutputDir $userDir -Name "profile"
}

$user = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT * FROM Users WHERE UserID = '$userID';"
$responseString = $user | ConvertTo-Json -Depth 5
context_reponse -Response $Response -String $responseString -ContentType "application/json"