param (
    [System.Net.HttpListenerContext]$Context,
    $sessiondata
)

$body = Get-RequestBody -Request $Context.Request | ConvertFrom-Json
$cardId = $body.id
$layoutData = $body.layout | ConvertTo-Json -Compress
$userId = $SessionData.UserID

if (-not $cardId -or -not $userId -or -not $layoutData) {
    context_reponse -Response $Context.Response -StatusCode 400 -String "Missing card ID, user ID, or layout data."
    return
}

Set-CardSettings -EndpointGuid $cardId -UserId $userId -Data $layoutData

$response = @{
    status = 'success';
    message = 'Card settings saved.'
} | ConvertTo-Json
context_reponse -Response $Context.Response -String $response -ContentType "application/json"
