Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

Write-Host "`n=== Simulating Browser Search Request ===" -ForegroundColor Cyan
Write-Host "URL: http://localhost:8080/api/v1/ui/elements/main-menu?search=task" -ForegroundColor Gray

# Simulate different user role scenarios
$roleScenarios = @(
    @{ Name = "authenticated"; Roles = @("authenticated") }
    @{ Name = "admin"; Roles = @("admin") }
    @{ Name = "site_admin"; Roles = @("site_admin") }
    @{ Name = "system_admin"; Roles = @("system_admin") }
    @{ Name = "admin + site_admin"; Roles = @("admin", "site_admin") }
    @{ Name = "admin + site_admin + system_admin"; Roles = @("admin", "site_admin", "system_admin") }
)

foreach ($scenario in $roleScenarios) {
    Write-Host "`n--- Testing with roles: $($scenario.Name) ---" -ForegroundColor Yellow

    # Simulate the request with Search parameter
    $result = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles $scenario.Roles -Search "task" 2>$null

    if ($result -match "Task Management") {
        Write-Host "  FOUND Task Management" -ForegroundColor Green
    } else {
        Write-Host "  NOT FOUND Task Management" -ForegroundColor Red

        # Check what's in the results
        try {
            $menuObj = $result | ConvertFrom-Json
            $itemCount = $menuObj.Count
            Write-Host "  Total menu items returned: $itemCount" -ForegroundColor Gray

            # Check if "No results" is first item
            if ($menuObj[0].text -eq "No results.") {
                Write-Host "  'No results' message present - search found nothing" -ForegroundColor Gray
            }
        } catch {
            Write-Host "  Could not parse result: $_" -ForegroundColor Gray
        }
    }
}

Write-Host "`n=== Checking Task Management Tags ===" -ForegroundColor Cyan
$null = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles system_admin 2>$null
$app = $Global:PSWebServer.Apps['WebHostTaskManagement']
if ($app -and $app.Menu) {
    Write-Host "Task Management tags:" -ForegroundColor Gray
    $app.Menu[0].tags | ForEach-Object { Write-Host "  - $_" }
}
