# routes\spa\get.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$projectRoot = $Global:PSWebServer.Project_Root.Path
$indexPath = Join-Path $projectRoot "public\spa-shell.html"

$sessionCookie = if ($Request.Cookies) { $Request.Cookies["PSWebSessionID"] } else { $null }
if (!$sessionCookie) {
    Write-Host "SPA GET No session ID"
    context_response -Response $Response -StatusCode 500 -String "No session ID" -ContentType "text/plain" -StatusDescription "Internal Server Error" -ForegroundColor Red
    return
}
$sessionID = $sessionCookie.Value
$Session = Get-PSWebSessions -SessionID $sessionID
if (-not $Session) {
    Write-Host "`t[routes\spa\get.ps1] Session ID Present, but No session." -ForegroundColor Red
    context_response -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=$($Request.Url.AbsoluteUri)"
    return
}
$Roles = $session.Roles

if ('unauthenticated' -in $Roles) {
    Write-Host "`t[routes\spa\get.ps1] Unauthenticated: $($Roles -join ', ') `n`t`tSession: $(($Session|Inspect-Object -Depth 4| ConvertTo-YAML) -split '`n' -notmatch '^\s*Type:' -join "`n`t`t`t")" -ForegroundColor Magenta
    context_response -Response $Response -StatusCode 302 -RedirectLocation "/api/v1/auth/getauthtoken?RedirectTo=$($Request.Url.AbsoluteUri)"
    return
}

# Load base HTML
$htmlContent = Get-Content $indexPath -Raw

# Inject debug poll service for users with debug role
if ('debug' -in $Roles -or 'system_admin' -in $Roles) {
    Write-PSWebHostLog -Severity 'Debug' -Category 'SPA' -Message "Injecting debug poll service for user with debug role"

    $debugScripts = @"
    <!-- Debug Command Polling Service (Auto-loaded for users with debug role) -->
    <script src="/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js"></script>
    <script src="/apps/WebHostDebugExtensions/api/v1/debug/poll-service"></script>
"@

    # Inject before closing </body> tag
    $htmlContent = $htmlContent -replace '</body>', "$debugScripts`n</body>"
}

# context_response will handle the Test-Path check, content type, and 404 response internally.
context_response -Response $Response -String $htmlContent -ContentType "text/html; charset=utf-8" -StatusCode 200
