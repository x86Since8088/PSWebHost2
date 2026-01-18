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

# Enrich session data with user email if not already present
if ($SessionData -and $SessionData.UserID -and -not $SessionData.Email) {
    try {
        $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
        $safeUserID = Sanitize-SqlQueryString -String $SessionData.UserID
        $user = Get-PSWebSQLiteData -File $dbFile -Query "SELECT Email FROM Users WHERE UserID COLLATE NOCASE = '$safeUserID';"
        if ($user) {
            $SessionData | Add-Member -NotePropertyName Email -NotePropertyValue $user.Email -Force
        }
    } catch {
        Write-PSWebHostLog -Severity 'Warning' -Category 'Session' -Message "Could not fetch user email: $($_.Exception.Message)"
    }
}

$jsonResponse = $SessionData | convertto-json -Depth 10
context_response -Response $Response -String $jsonResponse -ContentType "application/json" -StatusCode 200 
