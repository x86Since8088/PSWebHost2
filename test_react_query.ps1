#Requires -Version 7

$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n=== Querying React Component Tree ===" -ForegroundColor Cyan

$result = & $EnqueueScript `
    -Command 'queryReactTree' `
    -Type predefined `
    -Params @{} `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 15

if ($result.Success) {
    $data = $result.Result | ConvertFrom-Json

    Write-Host "`nTotal React Components: $($data.totalComponents)" -ForegroundColor Green
    Write-Host "Card Components Found: $($data.cardComponents.Count)" -ForegroundColor Green

    if ($data.cardComponents.Count -gt 0) {
        Write-Host "`n=== Card Components ===" -ForegroundColor Yellow
        $data.cardComponents | Format-Table -Property componentName, id, title -AutoSize
    }

    Write-Host "`n=== Opening a Test Card ===" -ForegroundColor Cyan
    $openResult = & $EnqueueScript `
        -Command 'openCard' `
        -Type predefined `
        -Params @{url='/apps/WebHostHelpViewer/cards/help-viewer'; title='Help Test'} `
        -SessionID all `
        -Wait `
        -TimeoutSeconds 30

    if ($openResult.Success) {
        $cardId = ($openResult.Result | ConvertFrom-Json).cardId
        Write-Host "Opened card: $cardId" -ForegroundColor Green

        Write-Host "`nWaiting 3 seconds..." -ForegroundColor Gray
        Start-Sleep -Seconds 3

        Write-Host "`n=== Querying React Tree Again ===" -ForegroundColor Cyan
        $result2 = & $EnqueueScript `
            -Command 'queryReactTree' `
            -Type predefined `
            -Params @{} `
            -SessionID all `
            -Wait `
            -TimeoutSeconds 15

        if ($result2.Success) {
            $data2 = $result2.Result | ConvertFrom-Json
            Write-Host "Total Components: $($data2.totalComponents)" -ForegroundColor Green
            Write-Host "Card Components: $($data2.cardComponents.Count)" -ForegroundColor Green

            if ($data2.cardComponents.Count -gt 0) {
                Write-Host "`n=== Card Components (After Opening) ===" -ForegroundColor Yellow
                $data2.cardComponents | Format-Table -Property componentName, id, title -AutoSize
            }
        }
    }
} else {
    Write-Host "Failed to query React tree" -ForegroundColor Red
    $result | Format-List
}
