# Task Engine Implementation Summary

**Date:** 2026-01-16
**Status:** Core Implementation Complete

## Overview

This document summarizes the implementation of the PSWebHost task scheduling engine and related management infrastructure. The system provides cron-like task scheduling, app scaffolding tools, and comprehensive task/job/runspace monitoring.

---

## Components Implemented

### 1. PSWebHostTasks Module ✅

**Location:** `modules/PSWebHostTasks/PSWebHostTasks.psm1`

**Purpose:** Core task scheduling engine with cron-like functionality

**Key Features:**
- Minute-based task evaluation loop
- Cron expression parsing (5-field format: minute hour day month weekday)
- Task termination rules (maxRuntime, maxFailures, killOnTimeout)
- Multi-layer configuration (YAML defaults + JSON runtime overrides)
- Task execution history tracking
- Background job management
- **Garbage collection with staggered timing** (offset = taskNumber * 3 % 60)

**Exported Functions:**
```powershell
Invoke-PsWebHostTaskEngine        # Main entry point (call every minute)
Get-AllTaskDefinitions            # Loads and merges task configs
Test-TaskSchedule                 # Checks if task should run
Test-CronExpression              # Parses cron schedules
Start-PSWebHostTask              # Launches task as background job
Stop-PSWebHostTask               # Terminates running task
Get-RunningTaskJob               # Gets running job for task
Test-TaskTermination             # Checks termination rules
Remove-CompletedTaskJobs         # Cleanup completed jobs
Invoke-RunspaceGarbageCollection # GC with staggered timing
Invoke-TaskRunspaceGC            # Helper for tasks to call GC
```

**Cron Expression Examples:**
```
"0 * * * *"     - Every hour at minute 0
"*/15 * * * *"  - Every 15 minutes
"0 0 * * *"     - Daily at midnight
"0 2 * * 0"     - Weekly on Sunday at 2 AM
"0 0 1 * *"     - Monthly on the 1st at midnight
```

---

### 2. PSWebHostAppManagement Module ✅

**Location:** `modules/PSWebHostAppManagement/PSWebHostAppManagement.psm1`

**Purpose:** App lifecycle management and scaffolding

**Key Features:**
- Create new apps from templates with variable substitution
- Enable/disable apps via app.yaml modification
- Install apps from ZIP packages or directories
- Uninstall with automatic backup
- Validate app structure
- Export apps as distributable packages

**Exported Functions:**
```powershell
New-PSWebHostApp            # Create app from template
Enable-PSWebHostApp         # Enable an app
Disable-PSWebHostApp        # Disable an app
Get-PSWebHostApp            # Get app information
Uninstall-PSWebHostApp      # Remove app with backup
Test-PSWebHostAppStructure  # Validate app structure
Export-PSWebHostApp         # Package app as ZIP
Install-PSWebHostApp        # Install app from package
```

**Usage Example:**
```powershell
# Create a new app
New-PSWebHostApp -AppName "DataAnalyzer" -Description "Advanced data analysis tools" -Author "John Doe"

# Enable the app
Enable-PSWebHostApp -AppName "DataAnalyzer"

# Export for distribution
Export-PSWebHostApp -AppName "DataAnalyzer" -OutputPath "C:\exports"

# Install from package
Install-PSWebHostApp -PackagePath "C:\packages\DataAnalyzer-v1.0.0-20260116.zip"
```

---

### 3. New App Template ✅

**Location:** `modules/PSWebHostAppManagement/New_App_Template/`

**Template Files Created:**
- `app.yaml.template` - App manifest
- `app_init.ps1.template` - Initialization script
- `README.md.template` - Documentation
- `modules/{{ModuleName}}/{{ModuleName}}.psm1.template` - PowerShell module
- `routes/api/v1/status/get.ps1.template` - Sample API endpoint
- `routes/api/v1/status/get.security.json.template` - Security config
- `public/elements/example-component/component.js.template` - Web component
- `config/tasks.yaml.template` - Task definitions
- `tasks/example-task.ps1.template` - Sample scheduled task
- `tests/Example.Tests.ps1.template` - Pester tests

**Template Variables:**
- `{{AppName}}` - PascalCase app name
- `{{AppDescription}}` - App description
- `{{AppAuthor}}` - Author name
- `{{AppVersion}}` - Version number
- `{{AppRequiredRoles}}` - YAML-formatted roles list
- `{{AppRoutePrefix}}` - API route prefix
- `{{ModuleName}}` - Module name (PSWebHost_AppName)
- `{{CurrentYear}}` - Current year
- `{{CurrentDate}}` - Current date

---

### 4. WebHostTaskManagement App ✅

**Location:** `apps/WebHostTaskManagement/`

**Purpose:** UI for managing tasks, jobs, and runspaces

**Structure:**
```
WebHostTaskManagement/
├── app.yaml
├── app_init.ps1
├── README.md
├── modules/
│   └── PSWebHost_TaskManagement/
│       └── PSWebHost_TaskManagement.psm1
├── routes/api/v1/
│   ├── tasks/
│   │   ├── get.ps1              # List all tasks
│   │   ├── get.security.json
│   │   ├── post.ps1             # Update task config
│   │   └── post.security.json
│   ├── jobs/
│   │   ├── get.ps1              # List background jobs
│   │   ├── get.security.json
│   │   ├── delete.ps1           # Stop/remove job
│   │   └── delete.security.json
│   ├── runspaces/
│   │   ├── get.ps1              # List runspaces
│   │   └── get.security.json
│   └── ui/elements/task-manager/
│       ├── get.ps1              # UI endpoint
│       └── get.security.json
└── public/elements/task-manager/
    └── component.js             # Main UI component
```

**API Endpoints:**

**GET /apps/WebHostTaskManagement/api/v1/tasks**
- Returns all task definitions with runtime status
- Includes: enabled state, running status, last run time, failure count

**POST /apps/WebHostTaskManagement/api/v1/tasks**
- Updates task configuration (enable/disable, schedule, environment)
- Modifies runtime config in `PsWebHost_Data/config/tasks.json`

**GET /apps/WebHostTaskManagement/api/v1/jobs**
- Lists all PowerShell background jobs
- Shows: ID, name, state, running time, associated task

**DELETE /apps/WebHostTaskManagement/api/v1/jobs?jobId=123**
- Stops and removes a background job
- Cleans up task tracking references

**GET /apps/WebHostTaskManagement/api/v1/runspaces**
- Lists all PowerShell runspaces
- Shows: ID, state, availability, associated job, thread options

**GET /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager**
- Returns UI component layout configuration

**UI Features:**
- **Left-side navigation menu** with three views:
  - 📋 **Tasks:** Enable/disable tasks, view schedules, monitor status
  - ⚡ **Jobs:** View running jobs, stop/remove jobs, see execution times
  - 🔄 **Runspaces:** Monitor runspace usage, detect leaks
- **Auto-refresh** every 5 seconds
- **Statistics dashboard** showing counts and status
- **Interactive actions:** Enable/disable tasks, stop jobs with confirmation
- **Responsive table views** with color-coded status badges

---

## Configuration Architecture

### Layer 1: Default Configuration (Read-Only)
**Location:** `apps/AppName/config/tasks.yaml`

```yaml
tasks:
  - name: AppName_MaintenanceTask
    description: Periodic maintenance operations
    enabled: true
    schedule:
      cron: "0 2 * * *"  # Daily at 2 AM
    script:
      path: apps/AppName/tasks/maintenance.ps1
      type: file
    termination:
      maxRuntime: 600
      maxFailures: 3
      killOnTimeout: true
    environment:
      LOG_LEVEL: "INFO"
      RETENTION_DAYS: "30"
    tags:
      - maintenance
```

### Layer 2: Runtime Configuration (Editable via UI)
**Location:** `PsWebHost_Data/config/tasks.json`

```json
{
  "version": "1.0",
  "lastModified": "2026-01-16T10:30:00Z",
  "tasks": [
    {
      "name": "AppName_MaintenanceTask",
      "appName": "AppName",
      "enabled": false,
      "schedule": "0 3 * * *",
      "environment": {
        "LOG_LEVEL": "DEBUG"
      }
    }
  ]
}
```

**Merge Logic:**
- Runtime config overrides default config
- `enabled`, `schedule`, `environment` can be overridden
- Setting `deleted: true` removes task from execution
- Custom tasks (not in defaults) have `custom: true` flag

---

## Database Schema

**Location:** `PsWebHost_Data/tasks.db`

### TaskExecutions Table
```sql
CREATE TABLE TaskExecutions (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL,
    AppName TEXT,
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    Duration INTEGER,
    Status TEXT NOT NULL,
    ExitCode INTEGER,
    Output TEXT,
    ErrorMessage TEXT,
    TriggeredBy TEXT,
    TriggeredByUser TEXT,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_task_name ON TaskExecutions(TaskName);
CREATE INDEX idx_start_time ON TaskExecutions(StartTime DESC);
CREATE INDEX idx_status ON TaskExecutions(Status);
CREATE INDEX idx_app_name ON TaskExecutions(AppName);
```

### TaskConfigurations Table
```sql
CREATE TABLE TaskConfigurations (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL UNIQUE,
    AppName TEXT,
    Configuration TEXT NOT NULL,
    IsCustom INTEGER DEFAULT 0,
    IsDeleted INTEGER DEFAULT 0,
    CreatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    UpdatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_config_task_name ON TaskConfigurations(TaskName);
CREATE INDEX idx_config_app_name ON TaskConfigurations(AppName);
```

---

## Garbage Collection Implementation

### Strategy
Each runspace runs `[gc]::Collect()` every 60 minutes with staggered timing to avoid simultaneous GC pauses.

### Offset Calculation
```powershell
$offsetMinutes = ($jobIndex * 3) % 60
```

**Example Schedule:**
- Job 0: GC at XX:00 (offset 0)
- Job 1: GC at XX:03 (offset 3)
- Job 2: GC at XX:06 (offset 6)
- Job 20: GC at XX:00 (offset 60 % 60 = 0)

### Functions
- **Invoke-RunspaceGarbageCollection:** Called from main task engine, schedules GC
- **Invoke-TaskRunspaceGC:** Helper function tasks can call internally

---

## Integration Steps

### 1. Add to Main Server Loop

**File:** `WebHost.ps1`

```powershell
# In main loop, check every second
if ((Get-Date).Second -eq 0) {
    # Call task engine every minute
    if (Get-Command Invoke-PsWebHostTaskEngine -ErrorAction SilentlyContinue) {
        Invoke-PsWebHostTaskEngine
    }
}
```

### 2. Import Modules on Startup

**File:** `system/init.ps1`

```powershell
# Import task management modules
Import-Module (Join-Path $modulesPath "PSWebHostTasks\PSWebHostTasks.psm1") -Force
Import-Module (Join-Path $modulesPath "PSWebHostAppManagement\PSWebHostAppManagement.psm1") -Force
```

### 3. Enable WebHostTaskManagement App

```powershell
Enable-PSWebHostApp -AppName "WebHostTaskManagement"
```

### 4. Verify Menu Integration

Already added to `routes/api/v1/ui/elements/main-menu/main-menu.yaml`:

```yaml
- Name: Task Management
  url: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
  hover_description: Manage scheduled tasks, monitor background jobs, and view active runspaces.
  tags:
  - tasks
  - jobs
  - runspaces
  - scheduling
  - automation
```

---

## Testing Checklist

### Module Testing

```powershell
# Test task engine
Import-Module .\modules\PSWebHostTasks\PSWebHostTasks.psm1 -Force

# Get task definitions
$tasks = Get-AllTaskDefinitions
$tasks | Format-Table name, enabled, schedule

# Test cron expression
Test-CronExpression -Expression "*/5 * * * *"  # Should match if current minute % 5 == 0

# Test app management
Import-Module .\modules\PSWebHostAppManagement\PSWebHostAppManagement.psm1 -Force

# Create test app
New-PSWebHostApp -AppName "TestApp" -Description "Test application" -Author "TestUser"

# Validate structure
Test-PSWebHostAppStructure -AppName "TestApp" -Strict

# Get app info
Get-PSWebHostApp -AppName "TestApp"
```

### API Testing

```powershell
# Test tasks endpoint
. .\apps\WebHostTaskManagement\routes\api\v1\tasks\get.ps1
# Call with -Test -Roles @('admin') -Query @{}

# Test jobs endpoint
. .\apps\WebHostTaskManagement\routes\api\v1\jobs\get.ps1
# Call with -Test -Roles @('admin') -Query @{}

# Test runspaces endpoint
. .\apps\WebHostTaskManagement\routes\api\v1\runspaces\get.ps1
# Call with -Test -Roles @('admin') -Query @{}
```

### UI Testing

1. Navigate to: `/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager`
2. Verify left-side menu displays (Tasks, Jobs, Runspaces)
3. Test switching between views
4. Test enable/disable task actions
5. Test job stop/remove actions
6. Verify auto-refresh updates data every 5 seconds

---

## Example: Creating a New App with Tasks

```powershell
# 1. Create the app
New-PSWebHostApp `
    -AppName "LogArchiver" `
    -Description "Automatic log file archival and cleanup" `
    -Author "DevOps Team" `
    -RequiredRoles @('admin', 'system_admin')

# 2. Edit the task configuration
# File: apps/LogArchiver/config/tasks.yaml

tasks:
  - name: LogArchiver_DailyCleanup
    description: Archive and compress old log files
    enabled: true
    schedule:
      cron: "0 1 * * *"  # Daily at 1 AM
    script:
      path: apps/LogArchiver/tasks/cleanup.ps1
      type: file
    termination:
      maxRuntime: 1800  # 30 minutes
      maxFailures: 2
      killOnTimeout: true
    environment:
      ARCHIVE_PATH: "C:\\Archives\\Logs"
      RETENTION_DAYS: "90"
      COMPRESSION_LEVEL: "Optimal"
    tags:
      - cleanup
      - archival

# 3. Create the task script
# File: apps/LogArchiver/tasks/cleanup.ps1

param([hashtable]$TaskContext)

$archivePath = $env:ARCHIVE_PATH
$retentionDays = [int]$env:RETENTION_DAYS

Write-Host "Starting log cleanup..."

# Find old log files
$oldLogs = Get-ChildItem -Path "C:\Logs" -Filter "*.log" |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) }

foreach ($log in $oldLogs) {
    # Archive logic here
}

return @{ Success = $true; FilesProcessed = $oldLogs.Count }

# 4. Enable the app
Enable-PSWebHostApp -AppName "LogArchiver"

# 5. Restart server to load the app and its tasks
```

---

## Performance Considerations

### Task Engine
- Evaluates every minute (60-second interval)
- Lightweight cron parsing with regex
- Deduplication prevents running same task multiple times in a minute
- Completed jobs cleaned up immediately to free resources

### Garbage Collection
- Staggered timing prevents simultaneous GC pauses
- Offset distribution: (taskNumber * 3) % 60
- Maximum 20 unique offsets per hour (0, 3, 6, ..., 57)
- Tasks can call `Invoke-TaskRunspaceGC` internally for long-running operations

### Database
- Indexed columns for fast queries (TaskName, StartTime, Status, AppName)
- Task history retention configurable via app settings
- Background job execution doesn't block main thread

---

## File Locations Reference

### Core Modules
```
modules/
├── PSWebHostTasks/
│   └── PSWebHostTasks.psm1
└── PSWebHostAppManagement/
    ├── PSWebHostAppManagement.psm1
    └── New_App_Template/
        ├── app.yaml.template
        ├── app_init.ps1.template
        ├── README.md.template
        ├── modules/
        ├── routes/
        ├── public/
        ├── config/
        ├── tasks/
        └── tests/
```

### Task Management App
```
apps/WebHostTaskManagement/
├── app.yaml
├── app_init.ps1
├── README.md
├── modules/PSWebHost_TaskManagement/
├── routes/api/v1/
│   ├── tasks/
│   ├── jobs/
│   ├── runspaces/
│   └── ui/elements/task-manager/
└── public/elements/task-manager/
```

### Configuration Files
```
PsWebHost_Data/
├── config/
│   └── tasks.json          # Runtime task overrides
├── apps/
│   └── WebHostTaskManagement/
│       ├── exports/
│       ├── logs/
│       └── backups/
└── tasks.db                 # Task execution history
```

---

## Next Steps

### Immediate (Required for Operation)
1. ✅ Create PSWebHostTasks module
2. ✅ Create PSWebHostAppManagement module
3. ✅ Build WebHostTaskManagement app
4. ✅ Create API endpoints and UI components
5. ⏳ **Integrate task engine into WebHost.ps1 main loop**
6. ⏳ **Import modules in system/init.ps1**
7. ⏳ **Restart server and test**

### Short-term (This Week)
- Create sample tasks for existing apps (WebHostMetrics, WebhostRealtimeEvents)
- Add task execution history viewer to UI
- Implement task duplication/copy functionality in UI
- Add cron expression builder/helper in UI
- Create unit tests for task engine

### Medium-term (This Month)
- Add task execution notifications (email, webhook)
- Implement task execution reports and analytics
- Add task dependency support (run task B after task A completes)
- Create task scheduling wizard in UI
- Add bulk task operations (enable/disable multiple tasks)

### Long-term (Future Enhancements)
- Distributed task execution across linked nodes
- Task execution queue with priority levels
- Advanced scheduling (one-time tasks, calendar-based schedules)
- Task output streaming to UI in real-time
- Task templates library with pre-built maintenance tasks

---

## Success Criteria

### ✅ Completed
- [x] PSWebHostTasks module with full cron functionality
- [x] Garbage collection with staggered timing
- [x] PSWebHostAppManagement module with scaffolding
- [x] Complete app template with 10+ template files
- [x] WebHostTaskManagement app structure
- [x] API endpoints for tasks, jobs, runspaces
- [x] Task manager UI with left-side navigation
- [x] Database schema for execution history
- [x] Menu integration for Task Management

### ⏳ Pending Integration
- [ ] Task engine called from WebHost.ps1 main loop
- [ ] Modules imported in system/init.ps1
- [ ] Server restart to load new components
- [ ] Verify tasks run on schedule
- [ ] Verify UI displays and updates correctly
- [ ] Verify garbage collection runs with correct offsets
- [ ] Create at least one working sample task

---

## Documentation Links

- **Architecture:** See `ARCHITECTURE.md` for system overview
- **Migration Roadmap:** See `MIGRATION_ROADMAP.md` for migration progress
- **Naming Conventions:** See `NAMING_CONVENTIONS.md` for patterns
- **Foundation Summary:** See `FOUNDATION_DOCS_SUMMARY.md` for overview
- **App README:** See `apps/WebHostTaskManagement/README.md` for app details

---

**Implementation Completed:** 2026-01-16
**Next Action:** Integrate task engine into WebHost.ps1 main loop and test
