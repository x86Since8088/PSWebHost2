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

$safeUserID = Sanitize-SqlQueryString -String $userID

# First, get the user's unique ID (GUID) to ensure related data is deleted
$userToDelete = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT ID FROM Users WHERE UserID COLLATE NOCASE = '$safeUserID';"
if ($userToDelete) {
    $id = $userToDelete.ID
    # Delete associated data from User_Data table
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'DELETE' -TableName 'User_Data' -Where "ID = '$id'"
}

# Now delete the main user record
Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'DELETE' -TableName 'Users' -Where "UserID COLLATE NOCASE = '$safeUserID'"

context_reponse -Response $Response -String "User deleted successfully."
