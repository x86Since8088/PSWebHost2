#Requires -Version 7

$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n=== Opening Help Viewer Card ===" -ForegroundColor Cyan

$result = & $EnqueueScript `
    -Command 'openCard' `
    -Type predefined `
    -Params @{url='/apps/WebHostHelpViewer/cards/help-viewer?file=help/help-viewer.md'; title='Help Viewer'} `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 30

Write-Host "`nOpen Result:" -ForegroundColor Yellow
$result | Format-List

if ($result.Success) {
    $cardId = ($result.Result | ConvertFrom-Json).cardId
    Write-Host "`nCard ID: $cardId" -ForegroundColor Green

    Write-Host "`nWaiting 3 seconds for card to load..." -ForegroundColor Gray
    Start-Sleep -Seconds 3

    Write-Host "`n=== Validating Card ===" -ForegroundColor Cyan

    $validate = & $EnqueueScript `
        -Command 'validateCard' `
        -Type predefined `
        -Params @{cardId=$cardId} `
        -SessionID all `
        -Wait `
        -TimeoutSeconds 10

    Write-Host "`nValidation Result:" -ForegroundColor Yellow
    $validate | Format-List

    if ($validate.Success) {
        Write-Host "`nValidation Data:" -ForegroundColor Cyan
        $validate.Result | ConvertFrom-Json | Format-List
    }
} else {
    Write-Host "`nFailed to open card!" -ForegroundColor Red
}
