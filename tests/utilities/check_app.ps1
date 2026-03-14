. 'C:\SC\PsWebHost\WebHost.ps1' -InitializeEnvironmentOnly 3>$null 4>$null 6>$null | Out-Null

if ($Global:PSWebServer.Apps.ContainsKey('WebHostDebugExtensions')) {
    Write-Host 'App registered: YES' -ForegroundColor Green
    $app = $Global:PSWebServer.Apps['WebHostDebugExtensions']
    Write-Host "PublicPath: $($app.PublicPath)"
    Write-Host "Path exists: $(Test-Path $app.PublicPath)"
    Write-Host "File exists: $(Test-Path (Join-Path $app.PublicPath 'debug-poll-service.js'))"
} else {
    Write-Host 'App registered: NO' -ForegroundColor Red
}
