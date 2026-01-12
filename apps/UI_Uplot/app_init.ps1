#Requires -Version 7

param(
    $PSWebServer,
    [string]$AppRoot
)

# Initialize UI_Uplot app namespace
$Global:PSWebServer['UI_Uplot'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\UI_Uplot"
    Initialized = Get-Date

    # Chart instances registry (for real-time updates)
    Charts = [hashtable]::Synchronized(@{})

    # Data source connections (for SQL.js, metrics DB, etc.)
    DataSources = [hashtable]::Synchronized(@{})

    # Cache for frequently accessed data
    DataCache = [hashtable]::Synchronized(@{})

    # Statistics
    Stats = [hashtable]::Synchronized(@{
        ChartsCreated = 0
        DataPointsServed = 0
        CacheHits = 0
        CacheMisses = 0
    })
})

# Ensure data directory exists
$DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\UI_Uplot"
if (-not (Test-Path $dataPath)) {
    New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
}

# Create subdirectories for different data types
@('csv', 'json', 'exports', 'dashboards') | ForEach-Object {
    $subDir = Join-Path $dataPath $_
    if (-not (Test-Path $subDir)) {
        New-Item -Path $subDir -ItemType Directory -Force | Out-Null
    }
}

Write-Host "[Init] Loaded app: uPlot Chart Builder (v1.0.0)" -ForegroundColor Green
Write-Verbose "[UI_Uplot] Data path: $dataPath"
Write-Verbose "[UI_Uplot] Initialized chart registry"
