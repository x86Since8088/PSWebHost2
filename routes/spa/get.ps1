# routes\spa\get.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$projectRoot = $Global:PSWebServer.Project_Root.Path
$indexPath = Join-Path $projectRoot "public\spa-shell.html"

$sessionID = $Request.Cookies["PSWebSessionID"]
if (!$sessionID) {
    Write-Host "SPA GET No session ID"
    context_reponse -Response $Response -StatusCode 500 -String "No session ID" -ContentType "text/plain" -StatusDescription "Internal Server Error" -ForegroundColor Red
    return
}
$Session = Get-PSWebSessions -SessionID $sessionID
if (-not $Session) {
    Write-Host "SPA GET Session ID Present, but No session." -ForegroundColor Red
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=$($Request.Url.AbsoluteUri)"
    return
}
$Roles = $session.Roles

if ('unauthenticated' -in $Roles) {
    Write-Host "SPA GET Unauthenticated: $($Roles -join ', ') Session: $($Session|ConvertTo-Json -Depth 2 -Compress)" -ForegroundColor Magenta
    context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=$($Request.Url.AbsoluteUri)"
    return 
}

# context_reponse will handle the Test-Path check, content type, and 404 response internally.
context_reponse -Response $Response -Path $indexPath -StatusCode 200
