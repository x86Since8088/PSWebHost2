<#
.SYNOPSIS
    Initialization script for SQL Server Manager app

.DESCRIPTION
    This script is called when the app is loaded during PSWebHost initialization.
    It receives the global PSWebServer hashtable and app root path.

.PARAMETER PSWebServer
    Global server state hashtable

.PARAMETER AppRoot
    Absolute path to this app's root directory
#>

param($PSWebServer, $AppRoot)

Write-Verbose "[SQLServerManager] Initializing SQL Server Manager app..."

# Create app namespace in global state
$PSWebServer['SQLServerManager'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\SQLServerManager"
    Initialized = Get-Date
    # Add app-specific state here
})

# Ensure data directory exists
$dataPath = $PSWebServer.SQLServerManager.DataPath
if (-not (Test-Path $dataPath)) {
    New-Item -Path $dataPath -ItemType Directory -Force | Out-Null
}

# Load any app-specific configuration
# $configPath = Join-Path $AppRoot "config.json"
# if (Test-Path $configPath) {
#     $config = Get-Content $configPath | ConvertFrom-Json
#     $PSWebServer.SQLServerManager.Config = $config
# }

# Initialize any background jobs or resources here
# Example:
# Start-Job -ScriptBlock { ... }

Write-Host "[Init] Loaded app: SQL Server Manager (v1.0.0)" -ForegroundColor Green
