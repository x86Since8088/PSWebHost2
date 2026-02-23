#Requires -Version 7

$EnqueueScript = ".\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1"

Write-Host "`n=== Testing Card Opening and Validation ===" -ForegroundColor Cyan

# Close all existing cards first
Write-Host "`nClosing all cards..." -ForegroundColor Yellow
& $EnqueueScript -Command 'closeAllCards' -Type predefined -SessionID all -Wait -TimeoutSeconds 15 | Out-Null

Start-Sleep -Seconds 2

# Open a test card
Write-Host "`nOpening Help Viewer..." -ForegroundColor Yellow
$openResult = & $EnqueueScript `
    -Command 'openCard' `
    -Type predefined `
    -Params @{url='/apps/WebHostHelpViewer/api/v1/ui/elements/help-viewer'; title='Help Test Card'} `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 30

Write-Host "Open result:" -ForegroundColor Cyan
$openData = $openResult.Result | ConvertFrom-Json
$openData | Format-List

$cardId = $openData.cardId

# Wait for card to render
Write-Host "`nWaiting 5 seconds for card to render..." -ForegroundColor Gray
Start-Sleep -Seconds 5

# Check how many cards are in grid
Write-Host "`nChecking rendered cards..." -ForegroundColor Yellow
$gridCheck = & $EnqueueScript `
    -Command 'document.querySelectorAll(".react-grid-item").length' `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

Write-Host "Grid items: $($gridCheck.Result)" -ForegroundColor Green

# Check card titles
$titleCheck = & $EnqueueScript `
    -Command 'Array.from(document.querySelectorAll(".card-title")).map(el => el.textContent)' `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

Write-Host "Card titles in DOM: $($titleCheck.Result)" -ForegroundColor Green

# Check appData
$appDataCheck = & $EnqueueScript `
    -Command 'Object.keys(window.appData?.elements || {})' `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

Write-Host "Cards in appData: $($appDataCheck.Result)" -ForegroundColor Green

# Try validation
Write-Host "`nValidating card: $cardId" -ForegroundColor Yellow
$validateResult = & $EnqueueScript `
    -Command 'validateCard' `
    -Type predefined `
    -Params @{cardId=$cardId} `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

Write-Host "Validation result:" -ForegroundColor Cyan
$validateResult.Result | ConvertFrom-Json | Format-List
