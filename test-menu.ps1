# Test menu system
.\WebHost.ps1 -ShowVariables *> $null

Write-Host "`n=== Checking Apps Loaded ===" -ForegroundColor Cyan
$Global:PSWebServer.Apps.Keys | ForEach-Object { Write-Host "App: $_" }

Write-Host "`n=== Checking WebHostTaskManagement ===" -ForegroundColor Cyan
if ($Global:PSWebServer.Apps.ContainsKey('WebHostTaskManagement')) {
    $app = $Global:PSWebServer.Apps['WebHostTaskManagement']
    Write-Host "Path: $($app.Path)"
    Write-Host "Manifest loaded: $($null -ne $app.Manifest)"
    Write-Host "Menu property exists: $($null -ne $app.Menu)"
    if ($app.Menu) {
        Write-Host "Menu items count: $($app.Menu.Count)"
        Write-Host "`nMenu data:"
        $app.Menu | ConvertTo-Json -Depth 3
    } else {
        Write-Host "Menu property is null/empty"
    }
} else {
    Write-Host 'WebHostTaskManagement not found in apps'
}

Write-Host "`n=== Checking menu.yaml file ===" -ForegroundColor Cyan
$menuPath = "apps\WebHostTaskManagement\menu.yaml"
if (Test-Path $menuPath) {
    Write-Host "menu.yaml exists at: $menuPath"
    Get-Content $menuPath
} else {
    Write-Host "menu.yaml NOT FOUND at: $menuPath"
}

Write-Host "`n=== Running menu endpoint test ===" -ForegroundColor Cyan
$menuOutput = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin, authenticated, site_admin

# Check if Task Management is in output
if ($menuOutput -match "Task Management") {
    Write-Host "✅ Task Management FOUND in menu output" -ForegroundColor Green
} else {
    Write-Host "❌ Task Management NOT FOUND in menu output" -ForegroundColor Red
}

# Show portion of output
Write-Host "`nMenu output (first 2000 chars):"
$menuOutput.Substring(0, [Math]::Min(2000, $menuOutput.Length))
