# App Initialization Status

## Overview

All PSWebHost apps now follow a consistent initialization pattern using `app_init.ps1` files. The app framework in `system/init.ps1` automatically discovers and executes these files during server startup.

## App Initialization Pattern

Each app's `app_init.ps1` file:
- Takes two parameters: `$PSWebServer` (hashtable) and `$AppRoot` (string)
- Imports app-specific modules
- Sets up data directories under `PsWebHost_Data/apps/[AppName]`
- Creates app namespaces in `$Global:PSWebServer`
- Performs any app-specific initialization (background jobs, database setup, etc.)

## App Initialization Status

### ✅ Apps WITH app_init.ps1

| App Name | Purpose | Special Initialization |
|----------|---------|------------------------|
| **DockerManager** | Docker container management | ✓ Module import, data directories |
| **KubernetesManager** | Kubernetes management | ✓ Module import, data directories |
| **LinuxAdmin** | Linux system administration | ✓ Module import, data directories |
| **MySQLManager** | MySQL database management | ✓ Module import, data directories |
| **RedisManager** | Redis management | ✓ Module import, data directories |
| **SQLiteManager** | SQLite database management | ✓ Module import, data directories |
| **SQLServerManager** | SQL Server management | ✓ Module import, data directories |
| **UI_Uplot** | Chart visualization | ✓ Chart registry, data cache |
| **UnitTests** | Testing framework | ✓ Test runner setup |
| **vault** | Credential management | ✓ Database schema, module import |
| **WindowsAdmin** | Windows administration | ✓ Module import, data directories |
| **WSLManager** | WSL management | ✓ Module import, data directories |
| **WebHostMetrics** | Metrics collection | ✓ Background job, metrics storage |
| **WebhostRealtimeEvents** | Real-time event monitoring | ✓ Event stream settings |

### Total: 14 apps with app_init.ps1 files

## Recent Changes (2026-01-16)

### Created app_init.ps1 Files

#### 1. WebHostMetrics (`apps/WebHostMetrics/app_init.ps1`)
**Previous State**: Initialization code was embedded in `system/init.ps1` (lines 775-856)

**Changes Made**:
- ✅ Created `app_init.ps1` with full metrics initialization
- ✅ Imports PSWebHost_Metrics module
- ✅ Starts background job for 5-second interval metrics collection
- ✅ Sets up synchronized hashtables for thread-safe metrics storage
- ✅ Configures job execution state tracking
- ✅ Removed custom initialization code from `system/init.ps1`

**Initialization Details**:
```powershell
# Module import (from apps/WebHostMetrics/modules)
Import-Module PSWebHost_Metrics -Force

# Initialize metrics system
Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30

# Start background job for metrics collection
Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock { ... }
```

#### 2. WebhostRealtimeEvents (`apps/WebhostRealtimeEvents/app_init.ps1`)
**Previous State**: No initialization file, no custom code in `system/init.ps1`

**Changes Made**:
- ✅ Created `app_init.ps1` for consistency and future extensibility
- ✅ Sets up synchronized hashtable for event stream settings
- ✅ Creates data directories for exports and archives
- ✅ Configures default settings (max events, time range, refresh interval)

**Initialization Details**:
```powershell
# Create app namespace with settings
$Global:PSWebServer['WebhostRealtimeEvents'] = [hashtable]::Synchronized(@{
    Settings = @{
        MaxEventsInMemory = 10000
        DefaultTimeRange = 60  # minutes
        RefreshInterval = 5    # seconds
    }
    Stats = [hashtable]::Synchronized(@{...})
})

# Create data directories
New-Item -Path "PsWebHost_Data/apps/WebhostRealtimeEvents/exports"
New-Item -Path "PsWebHost_Data/apps/WebhostRealtimeEvents/archives"
```

### Removed Custom Initialization from system/init.ps1

**Before (lines 775-856, 82 lines)**:
- Custom metrics initialization code
- Module import
- Background job creation
- Execution state setup
- Error handling

**After (lines 775-778, 4 lines)**:
```powershell
# NOTE: App-specific initialization (modules, background jobs, data directories, etc.)
# is now handled by each app's app_init.ps1 file, which is automatically discovered
# and executed by the app framework above. See apps/*/app_init.ps1 for details.
```

**Result**: Removed 78 lines of app-specific code from core init.ps1

## Benefits of This Approach

### 1. Modularity
- Each app's initialization is self-contained
- Apps can be added/removed without modifying core code
- Clear separation of concerns

### 2. Maintainability
- All app-related code in one location (`apps/AppName/`)
- Easy to find and update initialization logic
- Consistent pattern across all apps

### 3. Testability
- App initialization can be tested independently
- Can execute app_init.ps1 directly with mock parameters
- No need to run full server startup for testing

### 4. Scalability
- Adding new apps doesn't require changes to `system/init.ps1`
- Framework automatically discovers new apps
- Standard interface for all app initialization

### 5. Code Review
- Reviewers can see all app code in the app directory
- No hidden initialization in core system files
- Clear dependencies and requirements

## App Framework Discovery Process

The app framework in `system/init.ps1` (lines 645-654):

```powershell
# Run app_init.ps1 if it exists
$initScript = Join-Path $appDir "app_init.ps1"
if (Test-Path $initScript) {
    try {
        & $initScript -PSWebServer $Global:PSWebServer -AppRoot $appDir
        Write-Verbose "Executed app init script for: $appName" -Verbose
    } catch {
        Write-Warning "Failed to execute app_init.ps1 for app '$appName': $($_.Exception.Message)"
    }
}
```

**Process**:
1. Framework iterates through all enabled apps in `apps/` directory
2. Adds app's `modules/` directory to `$Env:PSModulePath`
3. Checks for `app_init.ps1` file
4. Executes with standard parameters if found
5. Logs errors but continues server startup

## Standard app_init.ps1 Template

```powershell
#Requires -Version 7

# [AppName] App Initialization Script
# This script runs during PSWebHost startup when the [AppName] app is loaded

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[[AppName]:Init]'

# Initialize app namespace
$Global:PSWebServer['[AppName]'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\[AppName]"
    Initialized = Get-Date
})

# Import app-specific modules (if any)
$modulePath = Join-Path $AppRoot "modules\[ModuleName].psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Verbose "$MyTag Loaded module: [ModuleName]" -Verbose
}

# Ensure data directory exists
$DataPath = Join-Path $Global:PSWebServer['DataRoot'] "apps\[AppName]"
if (-not (Test-Path $DataPath)) {
    New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
    Write-Verbose "$MyTag Created data directory: $DataPath" -Verbose
}

# Perform app-specific initialization
# - Start background jobs
# - Initialize databases
# - Set up caches
# - Configure services

Write-Host "$MyTag [AppName] app initialized" -ForegroundColor Green
Write-Verbose "$MyTag Data path: $DataPath"
```

## Verification

To verify all apps have been initialized:

```powershell
# Check which apps have been initialized
$Global:PSWebServer.Keys | Where-Object { $_ -notin @('Metrics', 'MetricsJob', 'Project_Root', 'DataRoot', 'ModulesPath', 'Apps', 'AppCategories', 'ConsoleLogger') }

# Check for app_init.ps1 files
Get-ChildItem -Path "apps" -Directory | ForEach-Object {
    $appName = $_.Name
    $initFile = Join-Path $_.FullName "app_init.ps1"
    [PSCustomObject]@{
        App = $appName
        HasInit = Test-Path $initFile
        InitFile = $initFile
    }
} | Format-Table -AutoSize
```

## Migration Complete

✅ All apps now follow the consistent `app_init.ps1` pattern
✅ No app-specific code remains in `system/init.ps1`
✅ App framework automatically discovers and executes initialization scripts
✅ System is more modular, maintainable, and scalable

---

**Last Updated**: 2026-01-16
**Status**: Complete
