param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$sessionCookie = $Request.Cookies["PSWebSessionID"]
if ($sessionCookie) {
    $sessionID = $sessionCookie.Value
    Remove-PSWebSession -SessionID $sessionID

    # Expire the cookie
    $expiredCookie = New-Object System.Net.Cookie("PSWebSessionID", "")
    $expiredCookie.Expires = (Get-Date).AddDays(-1)
    $Response.AppendCookie($expiredCookie)
}

# Redirect to the home page
context_response -Response $Response -StatusCode 302 -RedirectLocation "/"