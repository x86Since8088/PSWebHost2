param (
    [System.Net.HttpListenerContext]$Context,
    $sessiondata
)

$cardId = $Context.Request.QueryString["id"]
$userId = $SessionData.UserID

if (-not $cardId -or -not $userId) {
    context_reponse -Response $Context.Response -StatusCode 400 -String "Missing card ID or user ID."
    return
}

$settings = Get-CardSettings -EndpointGuid $cardId -UserId $userId

if ($settings) {
    context_reponse -Response $Context.Response -String $settings -ContentType "application/json"
} else {
    context_reponse -Response $Context.Response -StatusCode 404 -String "{}"
}
