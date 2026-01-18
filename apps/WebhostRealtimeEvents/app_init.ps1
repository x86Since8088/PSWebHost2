#Requires -Version 7

# WebhostRealtimeEvents App Initialization Script
# This script runs during PSWebHost startup when the WebhostRealtimeEvents app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebhostRealtimeEvents:Init]'

# Initialize WebhostRealtimeEvents app namespace
$Global:PSWebServer['WebhostRealtimeEvents'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\WebhostRealtimeEvents"
    Initialized = Get-Date

    # Event stream settings
    Settings = @{
        MaxEventsInMemory = 10000
        DefaultTimeRange = 60  # minutes
        RefreshInterval = 5    # seconds
    }

    # Statistics
    Stats = [hashtable]::Synchronized(@{
        EventsServed = 0
        FiltersApplied = 0
        ExportsGenerated = 0
    })
})

# Ensure data directory exists
$DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\WebhostRealtimeEvents"
if (-not (Test-Path $DataPath)) {
    New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
    Write-Verbose "$MyTag Created data directory: $DataPath" -Verbose
}

# Create subdirectories for exports and archives
@('exports', 'archives') | ForEach-Object {
    $subDir = Join-Path $DataPath $_
    if (-not (Test-Path $subDir)) {
        New-Item -Path $subDir -ItemType Directory -Force | Out-Null
    }
}

Write-Host "$MyTag Realtime Events app initialized" -ForegroundColor Green
Write-Verbose "$MyTag Data path: $DataPath"
Write-Verbose "$MyTag Max events in memory: $($Global:PSWebServer['WebhostRealtimeEvents'].Settings.MaxEventsInMemory)"
