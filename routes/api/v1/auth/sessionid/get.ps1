param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    [string]$sessionID = $Context.Request.Cookies["PSWebSessionID"].Value,
    [hashtable]$SessionData = $global:PSWebSessions[$sessionID],
    [hashtable]$CardSettings
)



# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1") -DisableNameChecking

$jsonResponse = $SessionData | convertto-json -Depth 10
context_reponse -Response $Response -String $jsonResponse -ContentType "application/json" -StatusCode 200 



