Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

Write-Host "`n=== Test with NO roles specified (simulates unauthenticated) ===" -ForegroundColor Cyan
$result = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Search "task" 2>$null

if ($result -match "Task Management") {
    Write-Host "FOUND Task Management" -ForegroundColor Green
} else {
    Write-Host "NOT FOUND Task Management" -ForegroundColor Red
    Write-Host "This is expected - unauthenticated users get default 'unauthenticated' role" -ForegroundColor Gray
}
