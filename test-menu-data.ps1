# Test menu data
Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

# Call endpoint to initialize
$null = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin

Write-Host "`n=== Checking App Menu Data ===" -ForegroundColor Cyan

$app = $Global:PSWebServer.Apps['WebHostTaskManagement']
Write-Host "`nWebHostTaskManagement:"
Write-Host "  Path: $($app.Path)"
Write-Host "  Menu property exists: $($null -ne $app.Menu)"
if ($app.Menu) {
    Write-Host "  Menu items count: $($app.Menu.Count)"
    if ($app.Menu.Count -gt 0) {
        Write-Host "`nMenu data:"
        $app.Menu | ConvertTo-Json -Depth 3
    }
} else {
    Write-Host "  Menu is null"
}

Write-Host "`n=== Checking CachedMenu ===" -ForegroundColor Cyan
if ($Global:PSWebServer.MainMenu.CachedMenu) {
    Write-Host "Cached menu items count: $($Global:PSWebServer.MainMenu.CachedMenu.Count)"
    if ($Global:PSWebServer.MainMenu.CachedMenu.Count -gt 0) {
        Write-Host "`nCached menu structure:"
        $Global:PSWebServer.MainMenu.CachedMenu | ConvertTo-Json -Depth 5
    }
} else {
    Write-Host "CachedMenu is null"
}
