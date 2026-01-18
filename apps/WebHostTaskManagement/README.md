# WebHost Task Management

**Version**: 1.0.0
**Category**: System Administration
**Author**: PSWebHost Team

---

## Overview

WebHostTaskManagement provides a centralized web interface for managing all scheduled tasks, monitoring background jobs, and viewing active runspaces across the PSWebHost system.

### Key Features

✅ **Task Management**
- View all scheduled tasks (global + per-app)
- Enable/disable tasks via UI
- Duplicate tasks with modified schedules
- Copy tasks between apps
- Delete custom tasks
- Edit task schedules using cron expression builder
- Manual task triggering
- Task execution history and analytics

✅ **Job Monitoring**
- View all PowerShell background jobs
- Real-time job status (Running, Completed, Failed)
- Job output streaming
- Stop/remove jobs
- Job error details
- Job execution time tracking

✅ **Runspace Management**
- View active PowerShell runspaces
- Runspace resource usage (memory, thread count)
- Identify runspace owners (which app/task created them)
- Force-close stuck runspaces (with confirmation)
- Runspace lifecycle tracking

---

## UI Structure

### Left-Side Navigation Menu

The Task Management card includes a left-side menu with three main sections:

```
┌────────────────────────────────────────────────────┐
│  Task Management                          [⚙️ Settings] │
├──────────────┬─────────────────────────────────────┤
│              │                                     │
│ 📋 Tasks     │  Task List View                    │
│              │                                     │
│ ⚡ Jobs      │  [All tasks with filters]          │
│              │                                     │
│ 🔄 Runspaces │  • Server Metrics Cleanup          │
│              │    Schedule: Daily 2 AM             │
│              │    Status: Enabled ✓                │
│              │    [Enable] [Edit] [Duplicate]      │
│              │                                     │
│              │  • Database Backup                  │
│              │    Schedule: Daily 3 AM             │
│              │    Status: Disabled ✗               │
│              │    [Enable] [Edit] [Delete]         │
│              │                                     │
└──────────────┴─────────────────────────────────────┘
```

---

## Section 1: Tasks

### Task List View

**Path**: Default view when card opens

**Features**:
- **Table View** with sortable columns:
  - Name
  - App
  - Schedule (cron expression with human-readable tooltip)
  - Status (Enabled/Disabled)
  - Last Run (timestamp)
  - Next Run (calculated from schedule)
  - Actions (Enable, Disable, Edit, Run Now, Duplicate, Delete)

- **Filters**:
  - App: Dropdown to filter by app (All, WebHostMetrics, vault, etc.)
  - Status: All, Enabled, Disabled, Running
  - Search: Text search by task name or description

- **Bulk Actions**:
  - Select multiple tasks via checkboxes
  - Bulk enable/disable
  - Bulk delete (custom tasks only)

- **Quick Stats** (top of view):
  - Total Tasks: 23
  - Enabled: 18
  - Running: 2
  - Failed (last 24h): 0

### Task Detail View

**Opened by**: Clicking task name

**Sections**:

1. **Overview**
   - Task name and description
   - App owner
   - Enabled/disabled status toggle
   - Creation date and last modified

2. **Schedule Configuration**
   - Cron expression editor with visual builder
   - Human-readable schedule display
   - Next 5 run times preview
   - Timezone indicator

3. **Script & Parameters**
   - Script path display (read-only for default tasks)
   - Parameter editor (key-value pairs)
   - Environment variables
   - Test button (validates script exists)

4. **Termination Rules**
   - Max runtime (seconds)
   - Max failures before auto-disable
   - Kill on timeout (checkbox)

5. **Execution History**
   - Last 20 executions table:
     - Start Time
     - Duration
     - Status (Success/Failed/Terminated)
     - Output preview (expandable)
     - Error message (if failed)
   - Statistics chart (last 7 days):
     - Success rate
     - Average duration
     - Failure count

6. **Actions**
   - Run Now (manual trigger)
   - Duplicate Task
   - Copy to Another App
   - Export Configuration (JSON)
   - Delete Task (custom tasks only)

### Create/Edit Task Modal

**Opened by**: "New Task" button or "Edit" action

**Form Fields**:

```
┌─────────────────────────────────────────────┐
│  Task Configuration                     [x] │
├─────────────────────────────────────────────┤
│                                             │
│  Task Name: *                               │
│  [_____________________________________]    │
│                                             │
│  Description:                               │
│  [_____________________________________]    │
│                                             │
│  App: *                                     │
│  [Dropdown: WebHostMetrics       ▼]        │
│                                             │
│  Schedule (Cron): *                         │
│  [0] [2] [*] [*] [*]  [Cron Builder 🕒]    │
│  Next run: Tomorrow at 2:00 AM              │
│                                             │
│  Script Path: *                             │
│  [tasks/CleanupData.ps1] [Browse]          │
│                                             │
│  Parameters:                                │
│  [+ Add Parameter]                          │
│   Key           Value                       │
│  ┌─────────┬────────────────────────┐       │
│  │ RETENTION_DAYS  │ 30             │       │
│  │ DATA_PATH       │ PsWebHost_Data │       │
│  └─────────┴────────────────────────┘       │
│                                             │
│  ☑ Enabled                                  │
│                                             │
│  Termination Rules:                         │
│  Max Runtime: [600] seconds                 │
│  Max Failures: [3]                          │
│  ☑ Kill on timeout                          │
│                                             │
│              [Cancel]  [Save Task]          │
└─────────────────────────────────────────────┘
```

---

## Section 2: Jobs

### Job List View

**Path**: Click "⚡ Jobs" in left menu

**Purpose**: Monitor all PowerShell background jobs running in the system

**Features**:

- **Real-time Job Table**:
  - Job ID
  - Job Name (e.g., "Task_MetricsCsvCleanup_20260116_140530")
  - State (Running, Completed, Failed, Stopped)
  - Owner (Task Engine, App Init, Manual, etc.)
  - Started (timestamp)
  - Elapsed Time (live updating for running jobs)
  - Actions (View Output, Stop, Remove)

- **Filters**:
  - State: All, Running, Completed, Failed
  - Owner: All, Task Engine, WebHostMetrics, vault, etc.
  - Search by job name

- **Auto-refresh**: Live updates every 2 seconds for running jobs

- **Quick Stats**:
  - Total Jobs: 15
  - Running: 3
  - Completed (last hour): 8
  - Failed (last hour): 0

### Job Detail View

**Opened by**: Clicking job name or "View Output"

**Sections**:

1. **Job Information**
   - Job ID
   - Job Name
   - State with color indicator
   - Started timestamp
   - Ended timestamp (if completed)
   - Total duration

2. **Job Output** (live streaming for running jobs)
   ```
   ┌─────────────────────────────────────────┐
   │ Output Stream                           │
   ├─────────────────────────────────────────┤
   │ [2026-01-16 14:05:30] Starting cleanup │
   │ [2026-01-16 14:05:31] Found 15 files   │
   │ [2026-01-16 14:05:32] Deleted 15 files │
   │ [2026-01-16 14:05:33] Cleanup complete │
   │                                         │
   │ [Auto-scroll ☑]         [Download Log] │
   └─────────────────────────────────────────┘
   ```

3. **Error Stream** (if failed)
   - Error messages
   - Exception details
   - Stack trace

4. **Job Context**
   - Owner/creator
   - Associated task (if task-generated)
   - Script path
   - Parameters passed

5. **Actions**
   - Stop Job (if running)
   - Receive Job Output (get final output)
   - Remove Job (cleanup)
   - Restart Task (if task-generated and failed)

### Job Operations

**Stop Job**:
```
┌─────────────────────────────────────┐
│  Confirm Stop Job              [x]  │
├─────────────────────────────────────┤
│  Are you sure you want to stop:    │
│                                     │
│  Job: Task_DatabaseBackup_...      │
│  State: Running                     │
│  Elapsed: 5m 23s                    │
│                                     │
│  This will terminate the job        │
│  immediately.                       │
│                                     │
│           [Cancel]  [Stop Job]      │
└─────────────────────────────────────┘
```

---

## Section 3: Runspaces

### Runspace List View

**Path**: Click "🔄 Runspaces" in left menu

**Purpose**: Monitor PowerShell runspaces for resource usage and hung runspace detection

**Features**:

- **Runspace Table**:
  - Runspace ID
  - State (Opened, Closed, Broken)
  - Owner (which component created it)
  - Created (timestamp)
  - Age (elapsed time since creation)
  - Thread Count
  - Memory Usage (MB)
  - Availability (Available, Busy, Remote)
  - Actions (Inspect, Force Close)

- **Filters**:
  - State: All, Opened, Closed, Broken
  - Owner: All, Task Engine, Background Jobs, HTTP Requests
  - Age: All, >1 hour, >6 hours, >24 hours (detect stuck runspaces)

- **Quick Stats**:
  - Total Runspaces: 28
  - Opened: 25
  - Busy: 3
  - Broken: 0
  - Total Memory: 458 MB

- **Alerts**:
  - Highlights runspaces older than 24 hours in yellow
  - Highlights broken runspaces in red
  - Memory usage over 100MB per runspace in orange

### Runspace Detail View

**Opened by**: Clicking runspace ID

**Sections**:

1. **Runspace Information**
   - Runspace ID
   - State
   - Availability
   - Apartment State (STA/MTA)
   - Thread Options
   - Created timestamp
   - Age (days, hours, minutes)

2. **Resource Usage**
   - Thread Count
   - Memory Usage (MB)
   - Handle Count
   - Graph showing memory usage over time (if tracked)

3. **Owner Context**
   - Created By: Task Engine, App Init, Background Job
   - Associated Job: Task_MetricsCollection_...
   - Associated App: WebHostMetrics
   - Purpose: "Metrics collection background job"

4. **Runspace Variables** (read-only inspection)
   - List of defined variables
   - Module imports
   - Current working directory

5. **Actions**
   - Refresh Info
   - Export Diagnostics (JSON)
   - Force Close (with big red warning)

### Force Close Runspace

**Warning Modal**:
```
┌─────────────────────────────────────────────┐
│  ⚠️  Force Close Runspace           [x]     │
├─────────────────────────────────────────────┤
│  WARNING: This action is DANGEROUS          │
│                                             │
│  Runspace: [12]                             │
│  Owner: Task_MetricsCollection              │
│  Age: 15 days 3 hours                       │
│                                             │
│  Force-closing a runspace may:              │
│  • Cause data loss                          │
│  • Leave orphaned resources                 │
│  • Crash associated jobs                    │
│  • Corrupt in-progress operations           │
│                                             │
│  Only use this if the runspace is stuck     │
│  and you've verified it's safe to close.    │
│                                             │
│  Type the runspace ID to confirm: [____]    │
│                                             │
│           [Cancel]  [Force Close]           │
└─────────────────────────────────────────────┘
```

---

## API Endpoints

### Task Management

**GET** `/apps/WebHostTaskManagement/api/v1/tasks`
- Returns: All tasks (merged defaults + runtime config)
- Query: `?app=AppName&enabled=true&status=running`
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId`
- Returns: Single task details with history
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks`
- Body: Task configuration JSON
- Returns: Created task
- Auth: system_admin role

**PUT** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId`
- Body: Updated task configuration
- Returns: Updated task
- Auth: system_admin role

**DELETE** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId`
- Returns: Success message
- Note: Default tasks are marked deleted, custom tasks removed
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/enable`
- Returns: Updated task
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/disable`
- Returns: Updated task
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/duplicate`
- Body: Optional modifications (name, schedule)
- Returns: New duplicated task
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/copy`
- Body: `{ "targetApp": "AppName" }`
- Returns: Copied task in target app
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/run`
- Returns: Job information
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/tasks/:taskId/history`
- Query: `?limit=50&offset=0&status=failed`
- Returns: Execution history
- Auth: system_admin role

### Job Management

**GET** `/apps/WebHostTaskManagement/api/v1/jobs`
- Returns: All PowerShell jobs
- Query: `?state=Running&owner=TaskEngine`
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/jobs/:jobId`
- Returns: Job details with output
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/jobs/:jobId/stop`
- Returns: Success message
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/jobs/:jobId/remove`
- Returns: Success message
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/jobs/:jobId/output`
- Returns: Job output (streaming for running jobs)
- Auth: system_admin role

### Runspace Management

**GET** `/apps/WebHostTaskManagement/api/v1/runspaces`
- Returns: All runspace information
- Query: `?state=Opened&minAge=3600`
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/runspaces/:runspaceId`
- Returns: Detailed runspace info
- Auth: system_admin role

**POST** `/apps/WebHostTaskManagement/api/v1/runspaces/:runspaceId/close`
- Body: `{ "force": true, "confirmation": "runspace-id" }`
- Returns: Success message
- Auth: system_admin role

**GET** `/apps/WebHostTaskManagement/api/v1/runspaces/:runspaceId/diagnostics`
- Returns: Full diagnostic information (variables, modules, etc.)
- Auth: system_admin role

---

## Configuration

### Default Configuration
**File**: `config/default/app.json`

```json
{
  "taskHistoryRetention": 30,
  "maxConcurrentTasks": 10,
  "enableNotifications": true,
  "defaultTaskTimeout": 600,
  "autoRefreshInterval": 5,
  "runspaceMemoryWarning": 100,
  "runspaceAgeWarning": 86400
}
```

### User Configuration
**Location**: User can override via Settings UI (gear icon)

---

## Security

### Role Requirements

**system_admin** role required for all operations.

**Why**: Task management can execute arbitrary PowerShell scripts and manipulate system resources.

### Audit Logging

All task management operations are logged:
- Task enable/disable
- Task creation/deletion
- Task manual execution
- Job termination
- Runspace force-close

Logged to: `PsWebHost_Data/apps/WebHostTaskManagement/logs/audit.log`

---

## Troubleshooting

### Task Not Running

1. Check task is enabled:
   - Open Tasks section
   - Verify "Status: Enabled ✓"

2. Check schedule:
   - View task details
   - Verify "Next Run" is in the future
   - Check cron expression is valid

3. Check task engine:
   ```powershell
   # Verify task engine module loaded
   Get-Module PSWebHostTasks

   # Check task engine is being called
   $Global:PSWebServer.Tasks.LastRun
   ```

4. Check script path exists:
   - View task details
   - Click "Test" button next to script path

5. View execution history:
   - Check for recent failures
   - Read error messages

### Job Stuck

1. Navigate to Jobs section
2. Find stuck job (look for long elapsed time)
3. Click job name to view output
4. Check if job is making progress
5. If stuck, click "Stop Job"
6. Review job logs to identify cause

### Runspace Memory Leak

1. Navigate to Runspaces section
2. Sort by "Memory Usage" (descending)
3. Identify high-memory runspaces
4. Check "Owner" to identify source
5. If legitimate: Ignore or increase warning threshold
6. If leaked: Force close (with caution)
7. Report issue to app owner

---

## Development

### Adding Task Support to Your App

**Step 1**: Create `config/tasks.yaml` in your app:

```yaml
tasks:
  - name: MyAppCleanup
    description: Clean up old data
    schedule: "0 3 * * *"
    scriptPath: "tasks/Cleanup.ps1"
    enabled: true
    termination:
      maxRuntime: 600
      maxFailures: 3
      killOnTimeout: true
    environment:
      RETENTION_DAYS: 30
```

**Step 2**: Create task script `tasks/Cleanup.ps1`:

```powershell
param([hashtable]$TaskContext)

# Your cleanup logic here
Write-Host "Running cleanup for $($TaskContext.TaskName)"
```

**Step 3**: Test task:
- Navigate to WebHostTaskManagement
- Find your task in the list
- Click "Run Now" to test manually

**Step 4**: Enable for production:
- Click "Enable" button
- Task will run on schedule

---

## License

Part of PSWebHost system. See root LICENSE.md for details.

---

## Support

- **Documentation**: This file and ARCHITECTURE.md
- **Issues**: GitHub issue tracker
- **Logs**: `PsWebHost_Data/apps/WebHostTaskManagement/logs/`

---

**Last Updated**: 2026-01-16
**Version**: 1.0.0
**Status**: Ready for Implementation
