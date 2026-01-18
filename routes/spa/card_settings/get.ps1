param (
    [System.Net.HttpListenerContext]$Context,
    $sessiondata
)

$cardId = $Context.Request.QueryString["id"]
$userId = $SessionData.UserID

if (-not $cardId -or -not $userId) {
    context_response -Response $Context.Response -StatusCode 400 -String "Missing card ID or user ID."
    return
}

$settings = Get-CardSettings -EndpointGuid $cardId -UserId $userId

if ($settings) {
    # Cache saved settings for 30 minutes (1800 seconds)
    context_response -Response $Context.Response -String $settings -ContentType "application/json" -CacheDuration 1800
} else {
    # Return default settings (12x14 grid units) when no DB match exists
    # Cache defaults for only 10 seconds since they may be customized soon
    $defaultSettings = @{
        data = (@{
            w = 12
            h = 14
        } | ConvertTo-Json -Compress)
    } | ConvertTo-Json
    context_response -Response $Context.Response -String $defaultSettings -ContentType "application/json" -CacheDuration 10
}
