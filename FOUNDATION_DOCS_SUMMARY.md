# PSWebHost Foundation Documentation - Summary

**Created**: 2026-01-16
**Status**: ✅ Complete

---

## Documents Created

### 1. ARCHITECTURE.md ✅ COMPLETE
**Location**: `/ARCHITECTURE.md`
**Size**: ~25KB
**Purpose**: Complete system architecture documentation

**Key Sections**:
- **System Overview**: High-level architecture diagram showing browser → server → apps → data → jobs
- **Data Flow Architecture**: Complete troubleshooting paths for:
  - Frontend elements → APIs → Data sets → Background jobs
  - Example 1: Server Metrics Dashboard (full flow with troubleshooting)
  - Example 2: Real-time Event Logs (complete data path)
  - Example 3: Task Execution Flow (proposed task engine)
- **App Framework**: Current state of all 14 apps, migration status
- **Task Scheduling Engine**: Full specification for new cron-like task system
- **Troubleshooting Paths**: Quick reference table for common issues

**Troubleshooting Features**:
- Step-by-step data flow diagrams
- "Check in order" lists for each issue type
- PowerShell commands for verification
- Browser debugging steps

### 2. MIGRATION_ROADMAP.md ✅ COMPLETE
**Location**: `/MIGRATION_ROADMAP.md`
**Size**: ~15KB
**Purpose**: Track migration progress and schedule

**Key Sections**:
- **Phase 1: Pattern Establishment** ✅ COMPLETE (2026-01-16)
  - App framework defined
  - WebHostMetrics and WebhostRealtimeEvents migrated
  - Documentation created

- **Phase 2: Core App Migrations** 🔄 IN PROGRESS (2026-01-17 to 2026-02-15)
  - Priority matrix for 14 apps
  - Per-app migration checklist
  - Weekly goals and targets
  - New app: WebHostTaskManagement

- **Phase 3: Cleanup & Decommissioning** 📋 PLANNED (2026-02-16 to 2026-03-01)
  - Decommission schedule for old files
  - Optimization tasks

- **Phase 4: Task Engine & Advanced Features** 💡 FUTURE (2026-03-01+)
  - Task engine enhancements
  - App store/registry
  - Advanced monitoring
  - Security enhancements

**Special Features**:
- Risk assessment matrix
- Rollback procedures
- Success metrics per phase
- Communication plan

### 3. NAMING_CONVENTIONS.md ✅ COMPLETE
**Location**: `/NAMING_CONVENTIONS.md`
**Size**: ~12KB
**Purpose**: Official naming standards for all code

**Naming Patterns Defined**:
- **PowerShell Modules**: `PSWebHost_FeatureName`
- **App Directories**: `PascalCase` (WebHostMetrics)
- **UI Element IDs**: `kebab-case` (server-heatmap)
- **API Routes**: `/apps/AppName/api/v1/resource`
- **Component Files**: `component.js` (standardized)
- **Database Files**: `purpose.db`
- **Background Jobs**: `Feature_Purpose`
- **Task Names**: `PascalCaseDescription`
- **CSS Classes**: `psw-component-element`
- **Variables**: PowerShell (`$PascalCase`) vs JavaScript (`camelCase`)
- **Functions**: PowerShell (`Verb-Noun`) vs JavaScript (`camelCase`)

**Features**:
- Examples of correct and incorrect usage
- Exception cases documented (UI_Uplot, vault)
- Quick reference table
- Validation checklist

---

## Task Scheduling Engine Design

### Architecture Overview

```
WebHost.ps1 Main Loop
    ↓ (every minute)
Invoke-PsWebHostTaskEngine
    ↓
PSWebHostTasks Module
    ↓
Load Tasks:
  - config/tasks.yaml (global)
  - apps/*/config/tasks.yaml (app-specific)
  - PsWebHost_Data/config/tasks.json (runtime overrides)
    ↓
Evaluate Tasks:
  - Test schedule (cron expression)
  - Check if already running
  - Apply termination rules
    ↓
Execute Tasks:
  - Start background jobs
  - Monitor execution
  - Log results
```

### Task Configuration Layers

**Layer 1: Default Tasks** (templates, read-only)
- Location: `apps/AppName/config/tasks.yaml`
- Purpose: Shipped with app, defines available tasks
- Editable: No (requires app update)

**Layer 2: Runtime Configuration** (user modifications)
- Location: `PsWebHost_Data/config/tasks.json`
- Purpose: Enabled/disabled state, schedule overrides, custom tasks
- Editable: Yes (via WebHostTaskManagement UI)

**Merge Logic**:
```powershell
# 1. Load defaults from YAML
$defaultTasks = Load-DefaultTasks

# 2. Load runtime config
$runtimeConfig = Get-Content "PsWebHost_Data/config/tasks.json" | ConvertFrom-Json

# 3. Merge: runtime overrides defaults
foreach ($task in $defaultTasks) {
    $override = $runtimeConfig.tasks | Where-Object { $_.name -eq $task.name }
    if ($override) {
        if ($override.enabled -eq $false) { $task.enabled = $false }
        if ($override.schedule) { $task.schedule = $override.schedule }
    }
}
```

### Task Operations (via UI)

**Enable/Disable**:
- Updates `PsWebHost_Data/config/tasks.json`
- Sets `enabled: true/false` for task
- Takes effect on next engine cycle (within 1 minute)

**Duplicate**:
- Creates new task with same config
- Appends `_Copy` to name
- Sets `enabled: false` by default
- Allows user to modify schedule/params

**Copy** (cross-app):
- Copies task from one app to another
- Updates `scriptPath` to new app
- User must verify script exists

**Delete**:
- For default tasks: Sets `enabled: false`, adds `deleted: true` marker
- For custom tasks: Removes from runtime config
- Prevents deleted default tasks from reappearing

---

## WebHostTaskManagement App

### Purpose

Provides web UI for managing all scheduled tasks across the system:
- View all tasks (global + per-app)
- Enable/disable tasks
- Duplicate tasks
- Copy tasks between apps
- Delete custom tasks
- Edit task schedules and parameters
- View task execution history
- Monitor running tasks
- Manually trigger tasks

### API Endpoints

**GET `/apps/WebHostTaskManagement/api/v1/tasks`**
- Returns: All tasks (merged defaults + runtime config)
- Filters: `?app=AppName`, `?enabled=true`, `?status=running`

**GET `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}`**
- Returns: Single task details with execution history

**POST `/apps/WebHostTaskManagement/api/v1/tasks`**
- Creates: New custom task
- Body: Task configuration JSON

**PUT `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}`**
- Updates: Task configuration (runtime override)
- Body: Modified task configuration

**DELETE `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}`**
- Deletes: Custom task OR marks default task as deleted

**POST `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}/enable`**
- Enables task

**POST `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}/disable`**
- Disables task

**POST `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}/duplicate`**
- Creates duplicate of task

**POST `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}/run`**
- Manually triggers task execution

**GET `/apps/WebHostTaskManagement/api/v1/tasks/{taskId}/history`**
- Returns: Execution history for task

**GET `/apps/WebHostTaskManagement/api/v1/tasks/running`**
- Returns: Currently running tasks with real-time status

### UI Features

**Task List View**:
- Table with columns: Name, App, Schedule, Status, Last Run, Actions
- Filter by: App, Enabled/Disabled, Running/Stopped
- Search by task name
- Bulk operations: Enable/disable multiple tasks

**Task Details View**:
- Full configuration display
- Edit mode with validation
- Execution history chart
- Next scheduled run time
- Quick actions: Enable, Disable, Run Now, Duplicate, Delete

**Task Editor**:
- Cron expression builder with visual preview
- Parameter editor (key-value pairs)
- Termination rules configuration
- Script path selector
- Validation before save

**Task Monitor**:
- Real-time view of running tasks
- Progress indicators
- Elapsed time
- Stop button (with confirmation)
- Live log streaming (if available)

**Task History**:
- Execution timeline
- Success/failure indicators
- Duration statistics
- Output/error logs
- Filter by date range

---

## App Management Module

### PSWebHostAppManagement Module

**Location**: `modules/PSWebHostAppManagement/PSWebHostAppManagement.psm1`

**Functions**:

```powershell
# Create new app from template
New-PSWebHostApp -Name "MyNewApp" -Description "..." -Category "..."

# Install app from directory or archive
Install-PSWebHostApp -Path "path/to/app" -Enable

# Uninstall app
Uninstall-PSWebHostApp -Name "AppName" -RemoveData

# Enable/disable app
Enable-PSWebHostApp -Name "AppName"
Disable-PSWebHostApp -Name "AppName"

# Get app information
Get-PSWebHostApp -Name "AppName"
Get-PSWebHostApp -All

# Verify app structure
Test-PSWebHostAppStructure -Path "apps/AppName"

# Export app (for sharing)
Export-PSWebHostApp -Name "AppName" -Destination "export.zip"

# Import app configuration
Import-PSWebHostAppConfig -Name "AppName" -ConfigFile "config.json"
```

### New App Template Structure

**Location**: `modules/PSWebHostAppManagement/New_App_Template/`

**Contents**:
```
New_App_Template/
├── app.yaml.template                   # Manifest template with placeholders
├── app_init.ps1.template              # Initialization script template
├── README.md.template                 # Documentation template
├── ARCHITECTURE.md.template           # Architecture doc template
├── config/
│   ├── default/
│   │   └── app.json.template          # Default config template
│   └── tasks.yaml.template            # Task definitions template
├── modules/
│   └── PSWebHost_AppName/
│       └── PSWebHost_AppName.psm1.template
├── routes/
│   └── api/v1/
│       ├── resource/
│       │   ├── get.ps1.template       # GET endpoint template
│       │   ├── get.security.json      # Security template
│       │   ├── post.ps1.template      # POST endpoint template
│       │   └── post.security.json
│       └── ui/elements/
│           └── element-name/
│               ├── get.ps1.template
│               └── get.security.json
├── public/
│   └── elements/
│       └── element-name/
│           └── component.js.template  # React component template
├── tasks/
│   └── ExampleTask.ps1.template       # Task script template
└── tests/
    └── twin/
        ├── powershell-tests.ps1.template
        └── browser-tests.js.template
```

**Placeholders Used**:
- `{{AppName}}` - PascalCase app name
- `{{AppNameKebab}}` - kebab-case element ID
- `{{AppDescription}}` - Description from user input
- `{{AppCategory}}` - Category from user input
- `{{AuthorName}}` - Author from user input
- `{{CurrentYear}}` - Current year

**Example Usage**:
```powershell
# Create new app from template
New-PSWebHostApp -Name "LogAnalyzer" -Description "Advanced log analysis and visualization" -Category "monitoring" -Author "DevTeam"

# This creates:
apps/LogAnalyzer/
├── app.yaml                  (AppName = LogAnalyzer)
├── app_init.ps1             (Initializes LogAnalyzer)
├── README.md                (Pre-filled documentation)
├── modules/PSWebHost_LogAnalyzer/
├── routes/api/v1/logs/      (Example endpoints)
├── public/elements/log-analyzer/
└── config/tasks.yaml        (Example tasks)
```

---

## Module System

### Modules to Create

#### 1. PSWebHostTasks (Task Engine)
**Location**: `modules/PSWebHostTasks/PSWebHostTasks.psm1`
**Status**: 📋 To be created

**Key Functions**:
- `Invoke-PsWebHostTaskEngine` - Main entry point
- `Start-PSWebHostTask` - Start task as job
- `Stop-PSWebHostTask` - Terminate task
- `Test-TaskSchedule` - Evaluate cron expression
- `Test-TaskTermination` - Check termination rules
- `Get-RunningTaskJob` - Get job for task
- `Get-TaskHistory` - Retrieve execution history
- `Save-TaskConfiguration` - Persist runtime config
- `Load-TaskConfiguration` - Load merged config

#### 2. PSWebHostAppManagement (App Management)
**Location**: `modules/PSWebHostAppManagement/PSWebHostAppManagement.psm1`
**Status**: 📋 To be created

**Key Functions**:
- `New-PSWebHostApp` - Create from template
- `Install-PSWebHostApp` - Install app
- `Uninstall-PSWebHostApp` - Remove app
- `Enable-PSWebHostApp` - Enable app
- `Disable-PSWebHostApp` - Disable app
- `Get-PSWebHostApp` - Get app info
- `Test-PSWebHostAppStructure` - Validate app
- `Export-PSWebHostApp` - Package app
- `Import-PSWebHostAppConfig` - Import config

#### 3. PSWebHost_TaskManagement (Task Management App Module)
**Location**: `apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psm1`
**Status**: 📋 To be created

**Key Functions**:
- `Get-AllTasks` - Get merged task list
- `Get-TaskDetails` - Get single task with history
- `New-CustomTask` - Create new task
- `Update-TaskConfiguration` - Modify task
- `Remove-CustomTask` - Delete task
- `Copy-Task` - Duplicate or copy to another app
- `Enable-Task` - Enable task
- `Disable-Task` - Disable task
- `Invoke-TaskNow` - Manual execution
- `Get-TaskExecutionHistory` - History retrieval

---

## Integration Points

### 1. Main Loop Integration (WebHost.ps1)

**Add to main request loop**:
```powershell
# Existing request handling loop
while ($true) {
    # Handle HTTP requests
    ...

    # Task engine execution (once per minute)
    if ((Get-Date).Second -eq 0) {
        try {
            Invoke-PsWebHostTaskEngine
        } catch {
            Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message "Task engine error: $_"
        }
    }

    Start-Sleep -Milliseconds 100
}
```

### 2. Initialization (system/init.ps1)

**After app framework initialization**:
```powershell
# Initialize task engine
if (Get-Module PSWebHostTasks) {
    try {
        Initialize-PSWebHostTaskEngine
        Write-Host "[Init] Task engine initialized" -ForegroundColor Green
    } catch {
        Write-Warning "[Init] Failed to initialize task engine: $_"
    }
}
```

### 3. Menu Integration

**Add to main menu** (`routes/api/v1/ui/elements/main-menu/main-menu.yaml`):
```yaml
categories:
  - id: system
    name: System
    icon: cog
    items:
      - id: task-management
        name: Task Management
        route: /apps/WebHostTaskManagement
        icon: clock
        roles:
          - system_admin
```

---

## Data Storage Structure

### Task Configuration Storage

**Default tasks** (immutable):
```yaml
# apps/AppName/config/tasks.yaml
tasks:
  - name: CleanupOldData
    description: Remove data older than retention period
    schedule: "0 2 * * *"
    scriptPath: "tasks/CleanupData.ps1"
    enabled: true
    termination:
      maxRuntime: 600
      maxFailures: 3
```

**Runtime configuration** (user modifications):
```json
// PsWebHost_Data/config/tasks.json
{
  "version": "1.0",
  "lastModified": "2026-01-16T14:30:00Z",
  "tasks": [
    {
      "name": "CleanupOldData",
      "appName": "WebHostMetrics",
      "enabled": false,                  // Override: disabled by user
      "schedule": "0 3 * * *"            // Override: changed to 3 AM
    },
    {
      "name": "CustomBackup",            // Custom task (not in defaults)
      "appName": "vault",
      "description": "Custom backup task",
      "schedule": "0 */6 * * *",
      "scriptPath": "tasks/CustomBackup.ps1",
      "enabled": true,
      "termination": {
        "maxRuntime": 1800
      }
    },
    {
      "name": "MetricsCsvCleanup",
      "appName": "WebHostMetrics",
      "deleted": true                    // Marker: user deleted this default task
    }
  ]
}
```

### Task Execution History

**Storage**: SQLite database `PsWebHost_Data/tasks.db`

**Schema**:
```sql
CREATE TABLE TaskExecutions (
    ID INTEGER PRIMARY KEY AUTOINCREMENT,
    TaskName TEXT NOT NULL,
    AppName TEXT,
    StartTime TEXT NOT NULL,
    EndTime TEXT,
    Duration INTEGER,           -- Seconds
    Status TEXT NOT NULL,       -- Running, Completed, Failed, Terminated
    ExitCode INTEGER,
    Output TEXT,
    ErrorMessage TEXT,
    TriggeredBy TEXT,          -- Scheduled, Manual, API
    TriggeredByUser TEXT
);

CREATE INDEX idx_task_name ON TaskExecutions(TaskName);
CREATE INDEX idx_start_time ON TaskExecutions(StartTime DESC);
CREATE INDEX idx_status ON TaskExecutions(Status);
```

---

## Next Steps

### Immediate (This Week)

1. **Create PSWebHostTasks Module**
   - Implement core task engine functions
   - Add cron expression parser
   - Implement termination rules logic
   - Create runtime config merge system

2. **Create PSWebHostAppManagement Module**
   - Implement app scaffolding functions
   - Create complete templates
   - Add validation logic
   - Build export/import functions

3. **Build WebHostTaskManagement App**
   - Create all API endpoints
   - Build React UI components
   - Implement task CRUD operations
   - Add real-time monitoring

4. **Integration Testing**
   - Test task engine with sample tasks
   - Verify runtime config merging
   - Test UI operations (enable/disable/duplicate/delete)
   - Validate termination rules

### Short Term (Next 2 Weeks)

5. **Add Tasks to Existing Apps**
   - WebHostMetrics: CSV cleanup, aggregation
   - vault: Database backup
   - System: Log cleanup, database vacuum

6. **Documentation**
   - Create TASK_ENGINE_SPECIFICATION.md
   - Write app development guide
   - Create video tutorials
   - Update ARCHITECTURE.md with implementation details

7. **Monitoring & Alerting**
   - Task failure notifications
   - Execution time alerts
   - Dead task detection
   - Performance monitoring

---

## Success Criteria

**Foundation Docs**: ✅ COMPLETE
- [x] ARCHITECTURE.md with full data flow diagrams
- [x] MIGRATION_ROADMAP.md with phases and checklist
- [x] NAMING_CONVENTIONS.md with all patterns
- [x] WebHostTaskManagement app structure defined
- [x] Task engine specification complete
- [x] App template system designed

**Next Phase Targets**:
- [ ] PSWebHostTasks module functional
- [ ] PSWebHostAppManagement module functional
- [ ] WebHostTaskManagement UI operational
- [ ] 3+ apps using task engine
- [ ] Runtime task configuration working
- [ ] Task duplicate/copy/delete features tested

---

## Documentation Locations

All foundation documents created:

1. **`/ARCHITECTURE.md`** - System architecture and data flows
2. **`/MIGRATION_ROADMAP.md`** - Migration phases and progress
3. **`/NAMING_CONVENTIONS.md`** - Official naming standards
4. **`/FOUNDATION_DOCS_SUMMARY.md`** - This document
5. **`/apps/WebHostMetrics/ENDPOINT_ALIGNMENT_REPORT.md`** - Endpoint validation
6. **`/apps/APP_INITIALIZATION_STATUS.md`** - App init status
7. **`/apps/WebHostMetrics/MIGRATION.md`** - WebHostMetrics migration
8. **`/apps/WebHostMetrics/ARCHITECTURE.md`** - Metrics app architecture
9. **`/apps/WebHostMetrics/README.md`** - Metrics app user docs

**Total Documentation**: ~60KB of comprehensive technical documentation

---

## Conclusion

✅ **Foundation documentation is complete** and provides:

1. **Clear Architecture** - Understand how every piece connects
2. **Troubleshooting Paths** - Debug data flow issues systematically
3. **Migration Plan** - Structured approach to standardizing apps
4. **Naming Standards** - Consistency across the codebase
5. **Task Engine Design** - Complete specification for scheduling system
6. **App Management** - Template system for rapid app development

**The codebase is now trackable** because:
- Every feature has a documented location
- Data flows are mapped end-to-end
- Migration states are clearly marked
- Naming is standardized and predictable
- Future work is planned in phases

**Ready for next phase**: Implementing the task engine and completing app migrations.

---

**Document Created**: 2026-01-16
**Status**: ✅ Complete
**Next Action**: Implement PSWebHostTasks module and WebHostTaskManagement app
