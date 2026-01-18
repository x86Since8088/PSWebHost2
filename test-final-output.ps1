Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

Write-Host "`n=== Testing Menu Output with system_admin role ===" -ForegroundColor Cyan

$result = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles system_admin 2>$null

if ($result -match "Task Management") {
    Write-Host "✅ SUCCESS: Task Management FOUND in menu output!" -ForegroundColor Green
} else {
    Write-Host "❌ FAILED: Task Management NOT FOUND in menu output" -ForegroundColor Red
}

Write-Host "`n=== Testing Menu Output with authenticated role ===" -ForegroundColor Cyan

$result2 = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles authenticated 2>$null

if ($result2 -match "Task Management") {
    Write-Host "⚠️  Task Management found with authenticated role (should NOT appear)" -ForegroundColor Yellow
} else {
    Write-Host "✅ Correct: Task Management NOT in output for authenticated role" -ForegroundColor Green
}

Write-Host "`n=== Checking System Management section ===" -ForegroundColor Cyan
$menuObj = $result | ConvertFrom-Json
$sysMgmt = $menuObj | Where-Object { $_.text -eq "System Management" }
if ($sysMgmt) {
    Write-Host "Found System Management section"
    $webhost = $sysMgmt.children | Where-Object { $_.text -eq "WebHost" }
    if ($webhost) {
        Write-Host "  Found WebHost subsection"
        Write-Host "  WebHost children count: $($webhost.children.Count)"
        $webhost.children | ForEach-Object { Write-Host "    - $($_.text)" }
    }
}
