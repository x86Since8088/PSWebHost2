param (
    [System.Net.HttpListenerContext]$Context,
    $sessiondata
)

try {
    $body = Get-RequestBody -Request $Context.Request | ConvertFrom-Json
    $cardId = $body.id
    $layoutData = $body.layout | ConvertTo-Json -Compress
    $userId = $SessionData.UserID

    Write-Host "[card_settings POST] Received request: cardId=$cardId, userId=$userId, layoutData=$layoutData"

    if (-not $cardId -or -not $userId -or -not $layoutData) {
        $errorMsg = "Missing card ID, user ID, or layout data. cardId=$cardId, userId=$userId, layoutData=$layoutData"
        Write-Host "[card_settings POST] ERROR: $errorMsg"
        context_response -Response $Context.Response -StatusCode 400 -String $errorMsg
        return
    }

    $result = Set-CardSettings -EndpointGuid $cardId -UserId $userId -Data $layoutData

    if ($result) {
        $response = @{
            status = 'success';
            message = 'Card settings saved.'
        } | ConvertTo-Json
        context_response -Response $Context.Response -String $response -ContentType "application/json"
    } else {
        $errorMsg = "Set-CardSettings returned false"
        Write-Host "[card_settings POST] ERROR: $errorMsg"
        context_response -Response $Context.Response -StatusCode 500 -String $errorMsg
    }
} catch {
    $errorMsg = "Exception in card_settings POST: $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    Write-Host "[card_settings POST] ERROR: $errorMsg" -ForegroundColor Red
    context_response -Response $Context.Response -StatusCode 500 -String $errorMsg
}
