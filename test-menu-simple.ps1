# Simple menu test
Import-Module ./ModuleDownload/powershell-yaml/0.4.2/powershell-yaml.psm1 -DisableNameChecking -WarningAction SilentlyContinue

Write-Host "`n=== Testing Menu Endpoint ===" -ForegroundColor Cyan

# Test if global variable exists
Write-Host "`nBefore endpoint call:"
Write-Host "  PSWebServer exists: $($null -ne $Global:PSWebServer)"
if ($Global:PSWebServer) {
    Write-Host "  Apps exists: $($Global:PSWebServer.ContainsKey('Apps'))"
    if ($Global:PSWebServer.ContainsKey('Apps')) {
        Write-Host "  Apps count: $($Global:PSWebServer.Apps.Count)"
        $Global:PSWebServer.Apps.Keys | ForEach-Object { Write-Host "    App: $_" }
    }
}

# Call endpoint
Write-Host "`nCalling endpoint..."
$result = .\routes\api\v1\ui\elements\main-menu\get.ps1 -test -Roles admin

Write-Host "`nAfter endpoint call:"
Write-Host "  PSWebServer exists: $($null -ne $Global:PSWebServer)"
if ($Global:PSWebServer) {
    Write-Host "  Apps exists: $($Global:PSWebServer.ContainsKey('Apps'))"
    if ($Global:PSWebServer.ContainsKey('Apps')) {
        Write-Host "  Apps count: $($Global:PSWebServer.Apps.Count)"
        $Global:PSWebServer.Apps.Keys | ForEach-Object { Write-Host "    App: $_" }
    }
    Write-Host "  MainMenu exists: $($Global:PSWebServer.ContainsKey('MainMenu'))"
    if ($Global:PSWebServer.ContainsKey('MainMenu')) {
        Write-Host "  CachedMenu exists: $($null -ne $Global:PSWebServer.MainMenu.CachedMenu)"
    }
}

Write-Host "`nResult contains Task Management: $($result -match 'Task Management')"
Write-Host "`nResult length: $($result.Length)"
Write-Host "`nFirst 500 chars of result:"
$result.Substring(0, [Math]::Min(500, $result.Length))
