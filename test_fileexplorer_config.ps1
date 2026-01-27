#Requires -Version 7

# Test FileExplorerConfig module

Write-Host "========== Testing FileExplorerConfig Module ==========" -ForegroundColor Cyan

# Setup global state (simulate server environment)
$Global:PSWebServer = @{
    DataPath = 'C:\SC\PsWebHost\PsWebHost_Data'
    Project_Root = @{ Path = 'C:\SC\PsWebHost' }
}

# Import module
$modulePath = "C:\SC\PsWebHost\apps\WebhostFileExplorer\modules\FileExplorerConfig\FileExplorerConfig.psd1"
Write-Host "Importing module: $modulePath" -ForegroundColor Yellow

try {
    Import-Module $modulePath -Force -ErrorAction Stop
    Write-Host "✓ Module imported successfully" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed to import module: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Test 1: Get config path
Write-Host "`n--- Test 1: Get Config Path ---" -ForegroundColor Cyan
try {
    $configPath = Get-WebHostFileExplorerConfigPath
    Write-Host "✓ Config path: $configPath" -ForegroundColor Green

    if (Test-Path $configPath) {
        Write-Host "✓ Config file exists" -ForegroundColor Green
    }
    else {
        Write-Host "✗ Config file does not exist" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 2: Load configuration
Write-Host "`n--- Test 2: Load Configuration ---" -ForegroundColor Cyan
try {
    $config = Get-WebHostFileExplorerConfig -Verbose

    if ($config) {
        Write-Host "✓ Config loaded successfully" -ForegroundColor Green
        Write-Host "  Version: $($config.version)" -ForegroundColor Gray
        Write-Host "  Roots count: $($config.roots.Count)" -ForegroundColor Gray
        Write-Host "  System roots enabled: $($config.systemRoots.enabled)" -ForegroundColor Gray

        # List roots
        Write-Host "`n  Configured roots:" -ForegroundColor Gray
        foreach ($root in $config.roots) {
            Write-Host "    - $($root.id): $($root.prefix):$($root.identifier)" -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "✗ Failed to load config (returned null)" -ForegroundColor Red
    }
}
catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 3: Path template resolution
Write-Host "`n--- Test 3: Path Template Resolution ---" -ForegroundColor Cyan
try {
    $template = "{Project_Root.Path}/public"
    $resolved = Resolve-WebHostFileExplorerConfigPath -PathTemplate $template
    Write-Host "✓ Template: $template" -ForegroundColor Gray
    Write-Host "✓ Resolved: $resolved" -ForegroundColor Green

    # Test with custom variables
    $template2 = "{DataPath}/apps/{AppName}"
    $resolved2 = Resolve-WebHostFileExplorerConfigPath -PathTemplate $template2 -Variables @{ AppName = 'TestApp' }
    Write-Host "✓ Template: $template2" -ForegroundColor Gray
    Write-Host "✓ Resolved: $resolved2" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test 4: Cache behavior
Write-Host "`n--- Test 4: Cache Behavior ---" -ForegroundColor Cyan
try {
    # First load (from disk)
    $start = Get-Date
    $config1 = Get-WebHostFileExplorerConfig -Verbose
    $time1 = (Get-Date) - $start
    Write-Host "  First load: $($time1.TotalMilliseconds) ms" -ForegroundColor Gray

    # Second load (from cache)
    $start = Get-Date
    $config2 = Get-WebHostFileExplorerConfig
    $time2 = (Get-Date) - $start
    Write-Host "  Cached load: $($time2.TotalMilliseconds) ms" -ForegroundColor Gray

    if ($time2.TotalMilliseconds -lt $time1.TotalMilliseconds) {
        Write-Host "✓ Cache is working (cached load faster)" -ForegroundColor Green
    }

    # Clear cache
    Clear-WebHostFileExplorerConfigCache
    Write-Host "✓ Cache cleared" -ForegroundColor Green

    # Load after clear (from disk)
    $config3 = Get-WebHostFileExplorerConfig -Verbose
    Write-Host "✓ Reloaded after cache clear" -ForegroundColor Green
}
catch {
    Write-Host "✗ Failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========== All Tests Complete ==========" -ForegroundColor Cyan
