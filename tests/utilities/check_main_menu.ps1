# Check Main Menu Content

$response = Invoke-WebRequest -Uri 'http://localhost:8080/cards/main-menu' -SessionVariable session -UseBasicParsing
$json = $response.Content | ConvertFrom-Json

Write-Host "`n===== Main Menu Structure =====" -ForegroundColor Cyan
Write-Host "Total menu items: $($json.Count)" -ForegroundColor Green

Write-Host "`nMenu Items:" -ForegroundColor Yellow
$json | ForEach-Object {
    Write-Host "  - $($_.text)" -ForegroundColor White
    if ($_.url) {
        Write-Host "    URL: $($_.url)" -ForegroundColor Gray
    }
    if ($_.children) {
        Write-Host "    Children: $($_.children.Count)" -ForegroundColor Gray
    }
}

Write-Host "`n===== Checking for Card URLs =====" -ForegroundColor Cyan

# Recursively find all URLs in menu
function Get-AllUrls {
    param($items)
    $urls = @()
    foreach ($item in $items) {
        if ($item.url) {
            $urls += $item.url
        }
        if ($item.children) {
            $urls += Get-AllUrls -items $item.children
        }
    }
    return $urls
}

$allUrls = Get-AllUrls -items $json
Write-Host "Total URLs found: $($allUrls.Count)" -ForegroundColor Green

Write-Host "`nCard URLs (using /cards/ path):" -ForegroundColor Yellow
$cardUrls = $allUrls | Where-Object { $_ -like "*/cards/*" }
$cardUrls | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }

Write-Host "`nOld URLs (still using /api/v1/ui/elements/):" -ForegroundColor Yellow
$oldUrls = $allUrls | Where-Object { $_ -like "*/api/v1/ui/elements/*" }
if ($oldUrls.Count -gt 0) {
    $oldUrls | ForEach-Object { Write-Host "  × $_" -ForegroundColor Red }
} else {
    Write-Host "  None found! All migrated ✓" -ForegroundColor Green
}

Write-Host "`nApp Card URLs:" -ForegroundColor Yellow
$appCardUrls = $allUrls | Where-Object { $_ -like "*/apps/*/cards/*" }
if ($appCardUrls.Count -gt 0) {
    $appCardUrls | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
} else {
    Write-Host "  None found (menu might be dynamically populated)" -ForegroundColor Gray
}
