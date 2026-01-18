# PSWebHost Architecture

**Version**: 2.0
**Last Updated**: 2026-01-16
**Status**: Living Document

---

## Table of Contents

1. [System Overview](#system-overview)
2. [Data Flow Architecture](#data-flow-architecture)
3. [App Framework](#app-framework)
4. [Task Scheduling Engine](#task-scheduling-engine)
5. [Troubleshooting Paths](#troubleshooting-paths)
6. [Migration Status](#migration-status)

---

## System Overview

### Core Philosophy

PSWebHost is a **modular, app-based PowerShell web server** where:
- **Apps are self-contained**: Each app owns its routes, UI, data, and background tasks
- **System provides infrastructure**: Core modules, SPA framework, task scheduling
- **Apps initialize themselves**: No app-specific code in system initialization

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser (Client)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ React SPA    │  │ Card System  │  │ UI Elements  │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
└─────────┼──────────────────┼──────────────────┼─────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                    PSWebHost Server                          │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              HTTP Listener (WebHost.ps1)            │    │
│  │                                                     │    │
│  │  Main Loop:                                        │    │
│  │    - Route requests                                │    │
│  │    - Invoke-PsWebHostTaskEngine (every minute)    │    │
│  │    - Handle sessions                               │    │
│  └────────────┬─────────────────────────────┬─────────┘    │
│               │                             │               │
│    ┌──────────▼─────────┐      ┌───────────▼────────────┐ │
│    │   System Modules   │      │   Task Engine          │ │
│    │                    │      │   (PSWebHostTasks)     │ │
│    │ - PSWebHost_Support│      │                        │ │
│    │ - PSWebHost_Database│     │ - Evaluates tasks.yaml│ │
│    └──────────┬─────────┘      │ - Manages jobs        │ │
│               │                 │ - Termination rules   │ │
│    ┌──────────▼─────────┐      └───────────┬───────────┘ │
│    │   Apps Directory   │                  │              │
│    │                    │                  │              │
│    │  Each App:         │◄─────────────────┘              │
│    │  - app.yaml        │                                 │
│    │  - app_init.ps1    │                                 │
│    │  - modules/        │                                 │
│    │  - routes/         │                                 │
│    │  - public/         │                                 │
│    │  - config/         │                                 │
│    │    - tasks.yaml    │                                 │
│    │    - default/      │                                 │
│    └────────────────────┘                                 │
└─────────────────────────────────────────────────────────────┘
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────────────────────────────────────────────────┐
│                      Data Storage                            │
│  - PsWebHost_Data/apps/{AppName}/                          │
│  - PsWebHost_Data/metrics/                                  │
│  - PsWebHost_Data/logs/                                     │
│  - *.db (SQLite databases)                                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Data Flow Architecture

### Complete Data Flow: Frontend → Backend → Storage → Jobs

This section maps **every step** of data flow for troubleshooting.

### Example 1: Server Metrics Dashboard

**Scenario**: User views server metrics card on dashboard

#### Flow Diagram

```
[Browser]
   │
   │ 1. SPA loads layout.json
   │
   ├─→ GET /public/layout.json
   │   └─→ Returns: { "server-heatmap": { "componentPath": "/apps/WebHostMetrics/..." } }
   │
   │ 2. SPA loads component
   │
   ├─→ GET /apps/WebHostMetrics/public/elements/server-heatmap/component.js
   │   └─→ Returns: React component code
   │
   │ 3. Component renders, starts data fetch
   │
   ├─→ GET /apps/WebHostMetrics/api/v1/ui/elements/server-heatmap
   │   │
   │   └─→ [Server] routes/api/v1/ui/elements/server-heatmap/get.ps1
   │       │
   │       ├─→ Check authentication ($sessiondata.Roles)
   │       │
   │       ├─→ Read from $Global:PSWebServer.Metrics.Current
   │       │   │
   │       │   └─→ [In-Memory Cache]
   │       │       │
   │       │       ├─→ Source: Background Job "PSWebHost_MetricsCollection"
   │       │       │   │
   │       │       │   └─→ [Job Loop - Runs every 5 seconds]
   │       │       │       │
   │       │       │       ├─→ Import-Module PSWebHost_Metrics
   │       │       │       │
   │       │       │       ├─→ Invoke-MetricJobMaintenance
   │       │       │       │   │
   │       │       │       │   ├─→ Get-Counter (CPU, Memory, Disk, Network)
   │       │       │       │   │
   │       │       │       │   ├─→ Write to CSV: PsWebHost_Data/metrics/Perf_*.csv
   │       │       │       │   │
   │       │       │       │   └─→ Update $Global:PSWebServer.Metrics.Current
   │       │       │       │
   │       │       │       └─→ Start-Sleep 5
   │       │       │
   │       │       └─→ [SQLite] PsWebHost_Data/pswebhost_perf.db
   │       │           │
   │       │           └─→ Aggregated historical data
   │       │
   │       └─→ Transform to UI format
   │           └─→ Return JSON
   │
   └─→ [Browser] Render charts with data
       │
       └─→ Auto-refresh timer (5s)
           └─→ Loop back to step 3
```

#### Troubleshooting Path

**Problem**: Server heatmap shows "No data available"

**Check in order**:

1. **Is the component loading?**
   ```
   Browser Console → Check for component.js 404 errors
   ```

2. **Is the API responding?**
   ```
   Browser Network Tab → Check /apps/WebHostMetrics/api/v1/ui/elements/server-heatmap
   Status: 200? 401? 500?
   ```

3. **Is authentication working?**
   ```powershell
   # Check session
   $Global:PSWebServer.Sessions | Where-Object { $_.SessionID -eq "..." }
   # Should have Roles containing 'authenticated'
   ```

4. **Is the background job running?**
   ```powershell
   Get-Job -Name "PSWebHost_MetricsCollection"
   # State should be "Running"

   # Check job errors
   Receive-Job -Name "PSWebHost_MetricsCollection" -Keep
   ```

5. **Is data being collected?**
   ```powershell
   # Check in-memory cache
   $Global:PSWebServer.Metrics.Current.Timestamp
   # Should be recent (within last 10 seconds)

   # Check CSV files
   Get-ChildItem PsWebHost_Data/metrics/*.csv |
       Sort-Object LastWriteTime -Desc |
       Select-Object -First 5
   # Should have files from today
   ```

6. **Is the module loaded?**
   ```powershell
   Get-Module PSWebHost_Metrics
   # Should show module is imported

   # Check functions available
   Get-Command -Module PSWebHost_Metrics
   ```

7. **Are performance counters accessible?**
   ```powershell
   # Test direct counter access
   Get-Counter '\Processor(_Total)\% Processor Time'
   ```

---

### Example 2: Real-time Event Logs

**Scenario**: User views real-time events card

#### Flow Diagram

```
[Browser]
   │
   │ 1. Component loads
   │
   ├─→ GET /apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js
   │
   │ 2. Component fetches logs
   │
   ├─→ GET /apps/WebhostRealtimeEvents/api/v1/logs?timerange=60&severity=all
   │   │
   │   └─→ [Server] routes/api/v1/logs/get.ps1
   │       │
   │       ├─→ Check authentication
   │       │
   │       ├─→ Parse query parameters (timerange, severity, category)
   │       │
   │       ├─→ Read from $Global:PSWebServer.EventLog
   │       │   │
   │       │   └─→ [In-Memory Circular Buffer]
   │       │       │
   │       │       ├─→ Source: Write-PSWebHostLog calls
   │       │       │   │
   │       │       │   └─→ Called throughout codebase:
   │       │       │       - API endpoints (errors, warnings)
   │       │       │       - Background jobs
   │       │       │       - System events
   │       │       │       - App-specific events
   │       │       │
   │       │       └─→ Max 10,000 events (oldest removed)
   │       │
   │       ├─→ Filter by timerange, severity, category
   │       │
   │       └─→ Return JSON array
   │
   └─→ [Browser] Display in table
       │
       └─→ Auto-refresh timer (5s)
           └─→ Loop to step 2
```

#### Troubleshooting Path

**Problem**: Events not showing up

1. **Check if events are being logged**:
   ```powershell
   # Check in-memory log
   $Global:PSWebServer.EventLog.Count
   # Should be > 0

   # View recent events
   $Global:PSWebServer.EventLog | Select-Object -Last 10
   ```

2. **Test logging manually**:
   ```powershell
   Write-PSWebHostLog -Severity 'Info' -Category 'Test' -Message 'Test event'

   # Check if it appears
   $Global:PSWebServer.EventLog | Select-Object -Last 1
   ```

3. **Check API response**:
   ```
   Browser Network Tab → /apps/WebhostRealtimeEvents/api/v1/logs
   Response should have array of events
   ```

4. **Verify filter parameters**:
   ```javascript
   // In browser console
   console.log('Applied filters:', severity, category, timerange)
   ```

---

### Example 3: Task Execution Flow (Proposed)

**Scenario**: Scheduled task runs to clean old CSV files

#### Flow Diagram

```
[Main Loop in WebHost.ps1]
   │
   │ Every minute:
   │
   ├─→ Invoke-PsWebHostTaskEngine
   │   │
   │   └─→ [PSWebHostTasks Module]
   │       │
   │       ├─→ Load config/tasks.yaml
   │       │   └─→ Global tasks
   │       │
   │       ├─→ Load apps/*/config/tasks.yaml
   │       │   └─→ App-specific tasks
   │       │
   │       ├─→ For each task:
   │       │   │
   │       │   ├─→ Evaluate schedule (cron expression)
   │       │   │   └─→ Should run now?
   │       │   │
   │       │   ├─→ Check if already running
   │       │   │   └─→ Query $Global:PSWebServer.Tasks.RunningJobs
   │       │   │
   │       │   ├─→ Check termination rules
   │       │   │   ├─→ MaxRuntime exceeded?
   │       │   │   ├─→ MaxFailures reached?
   │       │   │   └─→ Stop signal sent?
   │       │   │
   │       │   ├─→ If should run: Start-Job
   │       │   │   │
   │       │   │   └─→ Example: CleanupMetricsCsv
   │       │   │       │
   │       │   │       ├─→ Get-ChildItem PsWebHost_Data/metrics/*.csv
   │       │   │       │
   │       │   │       ├─→ Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) }
   │       │   │       │
   │       │   │       └─→ Remove-Item
   │       │   │
   │       │   └─→ If should terminate: Stop-Job
   │       │
   │       ├─→ Update task status
   │       │   └─→ $Global:PSWebServer.Tasks.Status[TaskName]
   │       │
   │       └─→ Log task execution
   │           └─→ Write-PSWebHostLog
   │
   └─→ Continue main loop
```

---

## App Framework

### Current State (2026-01-16)

#### ✅ Fully Migrated Apps

**Pattern**: Complete app framework implementation

| App Name | Purpose | Routes Prefixed | app_init.ps1 | UI in App Dir |
|----------|---------|----------------|--------------|---------------|
| **WebHostMetrics** | System metrics collection | ✅ `/apps/WebHostMetrics/` | ✅ Yes | ✅ Yes |
| **WebhostRealtimeEvents** | Event log viewer | ✅ `/apps/WebhostRealtimeEvents/` | ✅ Yes | ✅ Yes |

#### 🔄 Partial Migration Apps

**Status**: Have app_init.ps1, need verification

| App Name | Purpose | app_init.ps1 | Needs Review |
|----------|---------|--------------|--------------|
| vault | Credential management | ✅ Yes | Route prefix verification |
| UI_Uplot | Chart visualization | ✅ Yes | Route standardization |
| SQLiteManager | SQLite DB management | ✅ Yes | Route prefix check |
| DockerManager | Docker container mgmt | ✅ Yes | Route prefix check |
| KubernetesManager | K8s management | ✅ Yes | Route prefix check |
| LinuxAdmin | Linux system admin | ✅ Yes | Route prefix check |
| MySQLManager | MySQL management | ✅ Yes | Route prefix check |
| RedisManager | Redis management | ✅ Yes | Route prefix check |
| SQLServerManager | SQL Server mgmt | ✅ Yes | Route prefix check |
| UnitTests | Test runner | ✅ Yes | Route prefix check |
| WindowsAdmin | Windows admin | ✅ Yes | Route prefix check |
| WSLManager | WSL management | ✅ Yes | Route prefix check |

### Standard App Structure

Every app **MUST** follow this structure:

```
apps/AppName/
├── app.yaml                    # App manifest (REQUIRED)
├── app_init.ps1               # Initialization script (REQUIRED)
├── README.md                  # User documentation (REQUIRED)
├── ARCHITECTURE.md            # Technical docs (RECOMMENDED)
├── modules/                   # PowerShell modules
│   └── PSWebHost_AppName/
│       └── PSWebHost_AppName.psm1
├── routes/                    # API endpoints
│   └── api/v1/
│       ├── resource/
│       │   ├── get.ps1
│       │   ├── get.security.json
│       │   ├── post.ps1
│       │   └── post.security.json
│       └── ui/elements/
│           └── element-name/
│               ├── get.ps1
│               └── get.security.json
├── public/                    # UI components and assets
│   ├── elements/
│   │   └── element-name/
│   │       └── component.js   # React component
│   ├── lib/                   # Client-side libraries
│   └── assets/                # Images, CSS, etc.
├── config/                    # Configuration (NEW)
│   ├── default/              # Default config values
│   │   ├── app.json
│   │   └── features.json
│   └── tasks.yaml            # Scheduled tasks (NEW)
├── tests/                     # Test files
│   ├── twin/                 # Twin testing
│   │   ├── powershell-tests.ps1
│   │   └── browser-tests.js
│   └── unit/                 # Unit tests
└── data/                      # App-local data (optional)
    └── .gitignore            # Don't commit data
```

### App Lifecycle

#### 1. Server Startup (system/init.ps1)

```powershell
# Discover all apps
Get-ChildItem -Path "apps" -Directory | ForEach-Object {
    $appDir = $_.FullName
    $appYaml = Join-Path $appDir "app.yaml"

    if (Test-Path $appYaml) {
        # Load app manifest
        $manifest = Get-Content $appYaml | ConvertFrom-Yaml

        if ($manifest.enabled) {
            # Add modules to PSModulePath
            $modulesPath = Join-Path $appDir "modules"
            $Env:PSModulePath = "$modulesPath;$($Env:PSModulePath)"

            # Execute app_init.ps1
            $initScript = Join-Path $appDir "app_init.ps1"
            if (Test-Path $initScript) {
                & $initScript -PSWebServer $Global:PSWebServer -AppRoot $appDir
            }
        }
    }
}
```

#### 2. App Initialization (app_init.ps1)

Standard template:

```powershell
#Requires -Version 7

param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[AppName:Init]'

# 1. Import modules
$modulePath = Join-Path $AppRoot "modules\PSWebHost_AppName\PSWebHost_AppName.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
    Write-Verbose "$MyTag Loaded module" -Verbose
}

# 2. Initialize app namespace
$PSWebServer['AppName'] = [hashtable]::Synchronized(@{
    AppRoot = $AppRoot
    DataPath = Join-Path $PSWebServer['DataRoot'] "apps\AppName"
    Initialized = Get-Date
    Settings = @{}
    Stats = [hashtable]::Synchronized(@{})
})

# 3. Create data directories
$DataPath = Join-Path $PSWebServer['DataRoot'] "apps\AppName"
if (-not (Test-Path $DataPath)) {
    New-Item -Path $DataPath -ItemType Directory -Force | Out-Null
}

# 4. Initialize database/storage (if needed)
$dbPath = Join-Path $AppRoot "data\app.db"
if (-not (Test-Path $dbPath)) {
    # Create schema
    Initialize-AppDatabase -Path $dbPath
}

# 5. Start background jobs (if needed)
$Global:PSWebServer['AppName_Job'] = Start-Job -Name "AppName_Worker" -ScriptBlock {
    param($AppRoot, $DataPath)

    # Import module in job context
    Import-Module (Join-Path $AppRoot "modules\PSWebHost_AppName\PSWebHost_AppName.psm1")

    while ($true) {
        # Do work
        Invoke-AppWorker
        Start-Sleep -Seconds 60
    }
} -ArgumentList $AppRoot, $DataPath

Write-Host "$MyTag App initialized" -ForegroundColor Green
```

#### 3. Request Routing

```
User Request: GET /apps/AppName/api/v1/resource
    │
    ├─→ [Server] WebHost.ps1 main loop
    │   │
    │   ├─→ Match route pattern: /apps/{AppName}/api/v1/{resource}
    │   │
    │   ├─→ Locate script: apps/AppName/routes/api/v1/resource/get.ps1
    │   │
    │   ├─→ Load security: apps/AppName/routes/api/v1/resource/get.security.json
    │   │   └─→ { "Allowed_Roles": ["authenticated"] }
    │   │
    │   ├─→ Check session authentication
    │   │
    │   ├─→ Execute script:
    │   │   & $scriptPath -Context $Context -Request $Request -Response $Response -sessiondata $sessiondata
    │   │
    │   └─→ Return response to client
```

---

## Task Scheduling Engine

### Design Specification (NEW)

#### Overview

Apps need to run **scheduled background tasks** (cleanup, aggregation, sync, etc.). The task engine provides:

- **Cron-like scheduling**: Define when tasks run
- **Termination rules**: Auto-stop runaway tasks
- **Centralized management**: All tasks visible in one place
- **Per-app isolation**: Each app manages its own tasks
- **Monitoring**: Task execution history and status

#### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    WebHost.ps1 Main Loop                     │
│                                                              │
│  while ($true) {                                            │
│      # Handle HTTP requests                                 │
│      ...                                                    │
│                                                             │
│      # Every minute: Run task engine                        │
│      if ((Get-Date).Second -eq 0) {                        │
│          Invoke-PsWebHostTaskEngine                        │
│      }                                                      │
│                                                             │
│      Start-Sleep -Milliseconds 100                         │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
           │
           │ Calls every minute
           ▼
┌─────────────────────────────────────────────────────────────┐
│              PSWebHostTasks Module                           │
│   (modules/PSWebHostTasks/PSWebHostTasks.psm1)             │
│                                                              │
│  function Invoke-PsWebHostTaskEngine {                     │
│      # 1. Load task definitions                            │
│      $globalTasks = Load-TasksYaml "config/tasks.yaml"    │
│      $appTasks = Get-AppTasks                              │
│                                                             │
│      # 2. Evaluate each task                               │
│      foreach ($task in $allTasks) {                        │
│          if (Test-TaskSchedule $task) {                    │
│              Start-PSWebHostTask $task                     │
│          }                                                  │
│                                                             │
│          # Check termination rules                         │
│          if (Test-TaskTermination $task) {                 │
│              Stop-PSWebHostTask $task                      │
│          }                                                  │
│      }                                                      │
│                                                             │
│      # 3. Cleanup completed jobs                           │
│      Remove-CompletedTasks                                 │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
           │
           │ Reads configuration from
           ▼
┌─────────────────────────────────────────────────────────────┐
│                     Task Configuration                       │
│                                                              │
│  config/tasks.yaml          (Global tasks)                  │
│  apps/AppName/config/tasks.yaml  (App tasks)               │
└─────────────────────────────────────────────────────────────┘
```

#### Task Configuration Format

**config/tasks.yaml** (Global tasks):

```yaml
tasks:
  - name: CleanupOldLogs
    description: Remove log files older than 30 days
    schedule: "0 2 * * *"  # Daily at 2 AM (cron format)
    scriptPath: "system/tasks/CleanupLogs.ps1"
    enabled: true
    termination:
      maxRuntime: 600  # 10 minutes
      maxFailures: 3
      killOnTimeout: true
    environment:
      LOG_PATH: "PsWebHost_Data/logs"
      RETENTION_DAYS: 30

  - name: DatabaseBackup
    description: Backup all SQLite databases
    schedule: "0 3 * * *"  # Daily at 3 AM
    scriptPath: "system/tasks/BackupDatabases.ps1"
    enabled: true
    termination:
      maxRuntime: 1800  # 30 minutes
      maxFailures: 5
      killOnTimeout: true
```

**apps/WebHostMetrics/config/tasks.yaml** (App-specific tasks):

```yaml
tasks:
  - name: MetricsCsvCleanup
    description: Remove CSV files older than retention period
    schedule: "0 4 * * *"  # Daily at 4 AM
    scriptPath: "tasks/CleanupCsvFiles.ps1"  # Relative to app root
    enabled: true
    termination:
      maxRuntime: 300  # 5 minutes
      maxFailures: 3
      killOnTimeout: true
    environment:
      RETENTION_DAYS: 30
      CSV_PATH: "PsWebHost_Data/metrics"

  - name: MetricsAggregation
    description: Aggregate 5s samples to 60s intervals
    schedule: "*/5 * * * *"  # Every 5 minutes
    scriptPath: "tasks/AggregateMetrics.ps1"
    enabled: true
    termination:
      maxRuntime: 240  # 4 minutes
      maxFailures: 3
      killOnTimeout: true

  - name: MetricsDatabaseVacuum
    description: Optimize SQLite database
    schedule: "0 5 * * 0"  # Weekly on Sunday at 5 AM
    scriptPath: "tasks/VacuumDatabase.ps1"
    enabled: true
    termination:
      maxRuntime: 600
      maxFailures: 1
      killOnTimeout: true
```

#### Task Script Example

**apps/WebHostMetrics/tasks/CleanupCsvFiles.ps1**:

```powershell
#Requires -Version 7

# Task: MetricsCsvCleanup
# This script is executed by the PSWebHost Task Engine

param(
    [hashtable]$TaskContext  # Provided by task engine
)

$ErrorActionPreference = 'Stop'

try {
    # Get configuration from task environment
    $retentionDays = [int]($TaskContext.Environment.RETENTION_DAYS ?? 30)
    $csvPath = $TaskContext.Environment.CSV_PATH ?? "PsWebHost_Data/metrics"

    Write-Host "[MetricsCsvCleanup] Starting cleanup (retention: $retentionDays days)" -ForegroundColor Cyan

    # Calculate cutoff date
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)

    # Find old CSV files
    $oldFiles = Get-ChildItem -Path $csvPath -Filter "*.csv" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate }

    Write-Host "[MetricsCsvCleanup] Found $($oldFiles.Count) files to delete"

    # Delete files
    $deletedCount = 0
    foreach ($file in $oldFiles) {
        try {
            Remove-Item -Path $file.FullName -Force
            $deletedCount++
            Write-Verbose "[MetricsCsvCleanup] Deleted: $($file.Name)"
        } catch {
            Write-Warning "[MetricsCsvCleanup] Failed to delete $($file.Name): $_"
        }
    }

    Write-Host "[MetricsCsvCleanup] Deleted $deletedCount files" -ForegroundColor Green

    # Return success result
    return @{
        Status = 'Success'
        FilesDeleted = $deletedCount
        CutoffDate = $cutoffDate.ToString('yyyy-MM-dd')
    }

} catch {
    Write-Error "[MetricsCsvCleanup] Error: $_"

    # Return failure result
    return @{
        Status = 'Failed'
        Error = $_.Exception.Message
    }
}
```

#### Task Engine Functions

**modules/PSWebHostTasks/PSWebHostTasks.psm1**:

```powershell
#Requires -Version 7

# Main entry point - called every minute from main loop
function Invoke-PsWebHostTaskEngine {
    [CmdletBinding()]
    param()

    try {
        # Load global tasks
        $globalTasksFile = Join-Path $Global:PSWebServer.Project_Root.Path "config\tasks.yaml"
        $globalTasks = if (Test-Path $globalTasksFile) {
            Get-Content $globalTasksFile | ConvertFrom-Yaml
        } else {
            @{ tasks = @() }
        }

        # Load app tasks
        $appTasks = @()
        Get-ChildItem -Path "apps" -Directory | ForEach-Object {
            $appTasksFile = Join-Path $_.FullName "config\tasks.yaml"
            if (Test-Path $appTasksFile) {
                $taskDef = Get-Content $appTasksFile | ConvertFrom-Yaml
                foreach ($task in $taskDef.tasks) {
                    # Add app context
                    $task.AppName = $_.Name
                    $task.AppRoot = $_.FullName
                    $appTasks += $task
                }
            }
        }

        # Combine all tasks
        $allTasks = @($globalTasks.tasks) + $appTasks

        # Process each task
        foreach ($task in $allTasks) {
            if (-not $task.enabled) { continue }

            # Check if should run
            if (Test-TaskSchedule -Task $task) {
                Start-PSWebHostTask -Task $task
            }

            # Check if should terminate
            $runningJob = Get-RunningTaskJob -Task $task
            if ($runningJob -and (Test-TaskTermination -Task $task -Job $runningJob)) {
                Stop-PSWebHostTask -Task $task -Job $runningJob
            }
        }

        # Cleanup completed jobs
        Remove-CompletedTaskJobs

    } catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message "Task engine error: $_"
    }
}

# Test if task should run based on cron schedule
function Test-TaskSchedule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task
    )

    # Get last run time
    $lastRun = $Global:PSWebServer.Tasks.LastRun[$Task.name]

    # Parse cron schedule
    $cronSchedule = $Task.schedule

    # Test if current time matches schedule
    $shouldRun = Test-CronSchedule -Expression $cronSchedule -LastRun $lastRun

    return $shouldRun
}

# Start a task as a background job
function Start-PSWebHostTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task
    )

    try {
        # Check if already running
        if (Get-RunningTaskJob -Task $Task) {
            Write-Verbose "[TaskEngine] Task '$($Task.name)' is already running"
            return
        }

        # Resolve script path
        $scriptPath = if ($Task.AppRoot) {
            Join-Path $Task.AppRoot $Task.scriptPath
        } else {
            Join-Path $Global:PSWebServer.Project_Root.Path $Task.scriptPath
        }

        if (-not (Test-Path $scriptPath)) {
            Write-Warning "[TaskEngine] Script not found for task '$($Task.name)': $scriptPath"
            return
        }

        # Build task context
        $taskContext = @{
            TaskName = $Task.name
            AppName = $Task.AppName
            Environment = $Task.environment ?? @{}
            StartTime = Get-Date
        }

        # Start background job
        $job = Start-Job -Name "Task_$($Task.name)_$(Get-Date -Format 'yyyyMMdd_HHmmss')" -ScriptBlock {
            param($ScriptPath, $TaskContext)

            & $ScriptPath -TaskContext $TaskContext

        } -ArgumentList $scriptPath, $taskContext

        # Track running job
        if (-not $Global:PSWebServer.Tasks) {
            $Global:PSWebServer.Tasks = @{
                RunningJobs = @{}
                LastRun = @{}
                History = @()
            }
        }

        $Global:PSWebServer.Tasks.RunningJobs[$Task.name] = @{
            Job = $job
            Task = $Task
            StartTime = Get-Date
            FailureCount = ($Global:PSWebServer.Tasks.RunningJobs[$Task.name]?.FailureCount ?? 0)
        }

        $Global:PSWebServer.Tasks.LastRun[$Task.name] = Get-Date

        Write-PSWebHostLog -Severity 'Info' -Category 'TaskEngine' -Message "Started task: $($Task.name)"

    } catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message "Failed to start task '$($Task.name)': $_"
    }
}

# Test if task should be terminated
function Test-TaskTermination {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task,

        [Parameter(Mandatory)]
        $Job
    )

    $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]
    $termination = $Task.termination

    # Check max runtime
    if ($termination.maxRuntime) {
        $runtime = ((Get-Date) - $taskInfo.StartTime).TotalSeconds
        if ($runtime -gt $termination.maxRuntime) {
            Write-Warning "[TaskEngine] Task '$($Task.name)' exceeded maxRuntime ($runtime > $($termination.maxRuntime))"
            return $true
        }
    }

    # Check if job failed and max failures reached
    if ($Job.State -eq 'Failed') {
        $taskInfo.FailureCount++
        if ($termination.maxFailures -and $taskInfo.FailureCount -ge $termination.maxFailures) {
            Write-Warning "[TaskEngine] Task '$($Task.name)' reached maxFailures ($($taskInfo.FailureCount))"
            return $true
        }
    }

    return $false
}

# Stop a running task
function Stop-PSWebHostTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task,

        [Parameter(Mandatory)]
        $Job
    )

    try {
        $termination = $Task.termination

        if ($termination.killOnTimeout) {
            Stop-Job -Job $Job -ErrorAction SilentlyContinue
        }

        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue

        # Record in history
        $Global:PSWebServer.Tasks.History += @{
            TaskName = $Task.name
            StartTime = $Global:PSWebServer.Tasks.RunningJobs[$Task.name].StartTime
            EndTime = Get-Date
            Status = 'Terminated'
            Reason = 'Termination rule triggered'
        }

        # Remove from running jobs
        $Global:PSWebServer.Tasks.RunningJobs.Remove($Task.name)

        Write-PSWebHostLog -Severity 'Warning' -Category 'TaskEngine' -Message "Terminated task: $($Task.name)"

    } catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message "Failed to stop task '$($Task.name)': $_"
    }
}

# Get running job for a task
function Get-RunningTaskJob {
    param([hashtable]$Task)

    $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]
    if ($taskInfo -and $taskInfo.Job.State -eq 'Running') {
        return $taskInfo.Job
    }
    return $null
}

# Clean up completed jobs
function Remove-CompletedTaskJobs {
    $completedTasks = $Global:PSWebServer.Tasks.RunningJobs.Keys | Where-Object {
        $job = $Global:PSWebServer.Tasks.RunningJobs[$_].Job
        $job.State -in @('Completed', 'Failed', 'Stopped')
    }

    foreach ($taskName in $completedTasks) {
        $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$taskName]
        $job = $taskInfo.Job

        # Get job output
        $output = Receive-Job -Job $job -ErrorAction SilentlyContinue

        # Record in history
        $Global:PSWebServer.Tasks.History += @{
            TaskName = $taskName
            StartTime = $taskInfo.StartTime
            EndTime = Get-Date
            Status = $job.State
            Output = $output
        }

        # Remove job
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $Global:PSWebServer.Tasks.RunningJobs.Remove($taskName)

        Write-Verbose "[TaskEngine] Cleaned up completed task: $taskName"
    }

    # Keep only last 100 history entries
    if ($Global:PSWebServer.Tasks.History.Count -gt 100) {
        $Global:PSWebServer.Tasks.History = $Global:PSWebServer.Tasks.History | Select-Object -Last 100
    }
}

# Test cron schedule
function Test-CronSchedule {
    param(
        [string]$Expression,
        [datetime]$LastRun
    )

    # Simple cron parser (supports: minute hour day month weekday)
    # Example: "0 2 * * *" = Daily at 2 AM
    # Example: "*/5 * * * *" = Every 5 minutes

    $parts = $Expression -split '\s+'
    $now = Get-Date

    # If last run was less than 1 minute ago, don't run again
    if ($LastRun -and ($now - $LastRun).TotalSeconds -lt 60) {
        return $false
    }

    # Parse cron fields
    $minute = $parts[0]
    $hour = $parts[1]
    $day = $parts[2]
    $month = $parts[3]
    $weekday = $parts[4]

    # Test minute
    if ($minute -ne '*') {
        if ($minute -match '^\*/(\d+)$') {
            # Every N minutes
            $interval = [int]$matches[1]
            if ($now.Minute % $interval -ne 0) { return $false }
        } elseif ([int]$minute -ne $now.Minute) {
            return $false
        }
    }

    # Test hour
    if ($hour -ne '*' -and [int]$hour -ne $now.Hour) {
        return $false
    }

    # Test day of month
    if ($day -ne '*' -and [int]$day -ne $now.Day) {
        return $false
    }

    # Test month
    if ($month -ne '*' -and [int]$month -ne $now.Month) {
        return $false
    }

    # Test day of week (0 = Sunday)
    if ($weekday -ne '*' -and [int]$weekday -ne [int]$now.DayOfWeek) {
        return $false
    }

    return $true
}

Export-ModuleMember -Function @(
    'Invoke-PsWebHostTaskEngine'
    'Start-PSWebHostTask'
    'Stop-PSWebHostTask'
    'Get-RunningTaskJob'
)
```

---

## Troubleshooting Paths

### Quick Reference Table

| Symptom | Check First | Then Check | Finally Check |
|---------|-------------|------------|---------------|
| **Dashboard blank** | Browser console errors | Layout.json syntax | Component paths |
| **Card shows "No data"** | API response in network tab | Background job status | Data in memory/disk |
| **API returns 401** | Session authentication | Security.json file | Role configuration |
| **API returns 500** | Server error logs | Module loaded | Function exists |
| **Task not running** | tasks.yaml syntax | Schedule expression | Script path exists |
| **Task keeps failing** | Task output/errors | Termination rules | Script logic |
| **Background job stopped** | Get-Job status | Job errors | Module availability |

---

## Migration Status

See [MIGRATION_ROADMAP.md](./MIGRATION_ROADMAP.md) for detailed migration plan.

### Quick Status

- ✅ **Complete**: WebHostMetrics, WebhostRealtimeEvents
- 🔄 **In Progress**: App framework standardization
- 📋 **Planned**: Task engine implementation, remaining app migrations
- 🗑️ **Decommission**: Scheduled for 2026-01-23 (old public/elements/)

---

## Naming Conventions

See [NAMING_CONVENTIONS.md](./NAMING_CONVENTIONS.md) for complete guide.

### Quick Reference

- **Modules**: `PSWebHost_FeatureName`
- **Apps**: `PascalCase` (WebHostMetrics, vault)
- **Element IDs**: `kebab-case` (server-heatmap, realtime-events)
- **Routes**: `/apps/AppName/api/v1/resource`
- **Components**: `component.js` (standard name)

---

**Document Status**: Living Document - Update as architecture evolves
**Next Review**: When task engine is implemented
