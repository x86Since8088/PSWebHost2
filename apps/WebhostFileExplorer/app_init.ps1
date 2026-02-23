param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebhostFileExplorer:Init]'
Write-Host "$MyTag Initializing WebHost File Explorer..." -ForegroundColor Cyan

try {
    $PSWebServer['WebhostFileExplorer'] = [hashtable]::Synchronized(@{
        AppRoot = $AppRoot
        Initialized = Get-Date
        Settings = @{
            MaxFileSize = 10485760  # 10MB default (can be overridden by app.yaml)
            MaxDepth = 10
            AllowedExtensions = @()  # Empty = all allowed
        }
        Stats = [hashtable]::Synchronized(@{
            FileOperations = 0
            LastOperation = $null
            TreeRequests = 0
            LastTreeRequest = $null
        })
    })

    # Load FileExplorerConfig module for config-driven root management
    $configModulePath = Join-Path $AppRoot "modules\FileExplorerConfig\FileExplorerConfig.psd1"
    if (Test-Path $configModulePath) {
        try {
            Import-TrackedModule -Path $configModulePath
            Write-Host "$MyTag Loaded FileExplorerConfig module with hot reload" -ForegroundColor Green
        }
        catch {
            Write-Host "$MyTag Warning: Failed to load FileExplorerConfig module: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "$MyTag FileExplorer will use hardcoded root definitions" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "$MyTag FileExplorerConfig module not found (will use hardcoded roots)" -ForegroundColor Yellow
    }

    Write-Host "$MyTag WebHost File Explorer initialized successfully" -ForegroundColor Green
    Write-Host "$MyTag   Max File Size: $($PSWebServer['WebhostFileExplorer'].Settings.MaxFileSize / 1MB) MB" -ForegroundColor Gray
    Write-Host "$MyTag   Max Depth: $($PSWebServer['WebhostFileExplorer'].Settings.MaxDepth)" -ForegroundColor Gray
}
catch {
    Write-Host "$MyTag Failed to initialize: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
