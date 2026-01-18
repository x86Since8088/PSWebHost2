# Test app discovery
$Global:PSWebServer = @{}
$Global:PSWebServer.Apps = @{}

# Simulate path discovery like in Discover-Apps
$scriptRoot = "C:\SC\PsWebHost\routes\api\v1\ui\elements\main-menu"
$projectRoot = Split-Path (Split-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent) -Parent) -Parent

Write-Host "Script Root: $scriptRoot"
Write-Host "Project Root (calculated): $projectRoot"

$Global:PSWebServer.Project_Root = @{ Path = $projectRoot }

$appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
Write-Host "Apps Path: $appsPath"
Write-Host "Apps Path Exists: $(Test-Path $appsPath)"

if (Test-Path $appsPath) {
    $appDirs = Get-ChildItem -Path $appsPath -Directory
    Write-Host "App directories found: $($appDirs.Count)"
    foreach ($appDir in $appDirs) {
        Write-Host "  - $($appDir.Name)"
    }
}
