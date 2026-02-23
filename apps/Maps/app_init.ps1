param([hashtable]$PSWebServer, [string]$AppRoot)

$MyTag = '[Maps:Init]'
Write-Host "$MyTag Initializing Maps app..." -ForegroundColor Cyan

# Initialize app state in PSWebServer hashtable
$PSWebServer['Maps'] = @{
    AppRoot = $AppRoot
    Initialized = Get-Date
    Version = '1.0.0'
    MapConfig = @{
        DefaultProjection = 'equirectangular'
        ImageWidth = 2048
        ImageHeight = 1024
        MaxMarkers = 100
    }
}

Write-Host "$MyTag Maps initialized successfully" -ForegroundColor Green
