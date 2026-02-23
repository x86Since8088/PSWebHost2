<#
.SYNOPSIS
    Initialization script for Docker Manager app

.DESCRIPTION
    This script is called when the app is loaded during PSWebHost initialization.
    It receives the global PSWebServer hashtable and app root path.

.PARAMETER PSWebServer
    Global server state hashtable

.PARAMETER AppRoot
    Absolute path to this app's root directory
#>

param($PSWebServer, $AppRoot)

Write-Verbose "[DockerManager] Initializing Docker Manager app..."

# Create app namespace in global state
$PSWebServer['DockerManager'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\DockerManager"
    Initialized = Get-Date
    DockerAvailable = $false
    DockerVersion = $null
    DockerError = $null
})

# Ensure data directory exists
$dataPath = $PSWebServer.DockerManager.DataPath
if (-not (Test-Path $dataPath)) {
    New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
}

# Load Docker Manager module
$modulePath = Join-Path $AppRoot "modules\PSDockerManager\PSDockerManager.psd1"
if (Test-Path $modulePath) {
    try {
        Import-Module $modulePath -Force -ErrorAction Stop
        Write-Verbose "[DockerManager] Module loaded successfully"
    } catch {
        Write-Warning "[DockerManager] Failed to load module: $($_.Exception.Message)"
    }
} else {
    Write-Warning "[DockerManager] Module not found at: $modulePath"
}

# Check Docker availability at startup
try {
    $dockerStatus = Test-DockerAvailability
    $PSWebServer.DockerManager.DockerAvailable = $dockerStatus.available
    $PSWebServer.DockerManager.DockerVersion = $dockerStatus.version
    $PSWebServer.DockerManager.DockerError = $dockerStatus.error

    if ($dockerStatus.available) {
        Write-Host "[Init] Docker Manager (v1.0.0) - Docker detected: $($dockerStatus.version)" -ForegroundColor Green
    } else {
        Write-Host "[Init] Docker Manager (v1.0.0) - Docker not available: $($dockerStatus.error)" -ForegroundColor Yellow
    }
} catch {
    Write-Warning "[DockerManager] Failed to check Docker status: $($_.Exception.Message)"
    $PSWebServer.DockerManager.DockerAvailable = $false
    $PSWebServer.DockerManager.DockerError = $_.Exception.Message
    Write-Host "[Init] Docker Manager (v1.0.0) - Docker status unknown" -ForegroundColor Yellow
}
