# WebHostAppManager App Initialization Script
# This script runs during PSWebHost startup when the WebHostAppManager app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebHostAppManager:Init]'

Write-Host "$MyTag Initializing WebHost App Manager..." -ForegroundColor Cyan

try {
    # Initialize app namespace
    $PSWebServer['WebHostAppManager'] = [hashtable]::Synchronized(@{
        AppRoot = $AppRoot
        Initialized = Get-Date

        # App settings (from app.yaml config)
        Settings = @{
            EnableAppActions = $true
            ShowLoadTimestamps = $true
            ShowNodeGuid = $true
        }

        # Statistics
        Stats = [hashtable]::Synchronized(@{
            ViewCount = 0
            LastViewed = $null
        })
    })

    Write-Host "$MyTag WebHost App Manager initialized successfully" -ForegroundColor Green
    Write-Verbose "$MyTag App root: $AppRoot" -Verbose
}
catch {
    Write-Host "$MyTag Failed to initialize: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
