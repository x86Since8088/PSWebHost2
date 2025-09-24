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

Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query "DELETE FROM Users WHERE UserID = '$userID';"
Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query "DELETE FROM User_Data WHERE GUID = '$userID';"

context_reponse -Response $Response -String "User deleted successfully."
