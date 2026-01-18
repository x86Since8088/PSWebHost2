Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

Write-Host "`n=== Test 1: With system_admin role and 'task' tag ===" -ForegroundColor Cyan
$result1 = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles system_admin -Tags task 2>$null
if ($result1 -match "Task Management") {
    Write-Host "SUCCESS: Found with system_admin + task tag" -ForegroundColor Green
} else {
    Write-Host "FAILED: Not found with system_admin + task tag" -ForegroundColor Red
}

Write-Host "`n=== Test 2: With admin,authenticated,site_admin roles and 'task' tag ===" -ForegroundColor Cyan
$result2 = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin,authenticated,site_admin -Tags task 2>$null
if ($result2 -match "Task Management") {
    Write-Host "SUCCESS: Found with admin,authenticated,site_admin + task tag" -ForegroundColor Green
} else {
    Write-Host "FAILED: Not found with admin,authenticated,site_admin + task tag" -ForegroundColor Red
    Write-Host "Output length: $($result2.Length)" -ForegroundColor Yellow
}

Write-Host "`n=== Test 3: With admin,authenticated,site_admin,system_admin roles and 'task' tag ===" -ForegroundColor Cyan
$result3 = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin,authenticated,site_admin,system_admin -Tags task 2>$null
if ($result3 -match "Task Management") {
    Write-Host "SUCCESS: Found with all admin roles + task tag" -ForegroundColor Green
} else {
    Write-Host "FAILED: Not found with all admin roles + task tag" -ForegroundColor Red
}

Write-Host "`n=== Test 4: Without tags ===" -ForegroundColor Cyan
$result4 = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles system_admin 2>$null
if ($result4 -match "Task Management") {
    Write-Host "SUCCESS: Found with system_admin (no tag filter)" -ForegroundColor Green
} else {
    Write-Host "FAILED: Not found with system_admin (no tag filter)" -ForegroundColor Red
}
