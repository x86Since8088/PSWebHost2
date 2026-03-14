# Module Conflicts and UI Analysis

## 🚨 Critical Issues Identified

### Issue 1: Module Conflicts and Overlap

You have **THREE** modules handling jobs/tasks with overlapping functionality:

#### Current Modules (Global `modules/` folder):

1. **`modules/PSWebHostTasks/PSWebHostTasks.psm1`**
   - **Purpose**: Scheduled task system (cron-like)
   - **Scope**: Tasks defined in `config/tasks.yaml` files
   - **Execution**: Scheduled based on cron expressions
   - **State**: `$Global:PSWebServer.Tasks`
   - **Status**: ✅ **KEEP** - This is for scheduled/recurring tasks

2. **`modules/PSWebHost_JobExecution/PSWebHost_JobExecution.psd1`** (v1.0.0)
   - **Purpose**: OLD job submission/execution system
   - **Scope**: File-based job submissions
   - **State**: `$Global:PSWebServer.RunningJobs`
   - **Functions**: `Submit-PSWebHostJob`, `Process-PSWebHostJobSubmissions`
   - **Status**: ⚠️ **LEGACY** - Being replaced by PSWebHost_Jobs
   - **Problem**: Still loaded and causing "Cannot index into a null array" errors

3. **`modules/PSWebHost_Jobs/PSWebHost_Jobs.psd1`** (v2.0.0)
   - **Purpose**: NEW unified job management system
   - **Scope**: Job discovery from `apps/*/jobs/` directories
   - **State**: `$Global:PSWebServer.Jobs`
   - **Functions**: 12 functions including job catalog, start, stop, restart
   - **Status**: ✅ **NEW SYSTEM** - Should replace JobExecution

#### Conflict Analysis:

**Direct Conflicts:**
- Both `PSWebHost_JobExecution` and `PSWebHost_Jobs` try to manage background jobs
- Both use similar function names (`Start-PSWebHostJob` vs `Submit-PSWebHostJob`)
- API endpoints using legacy system while new system is available
- WebHost.ps1 calls BOTH systems in the main loop (lines 773-791)

**Data Structure Conflicts:**
```powershell
# Old system:
$Global:PSWebServer.RunningJobs[...]

# New system:
$Global:PSWebServer.Jobs.RunningJobs[...]
$Global:PSWebServer.Jobs.Catalog
$Global:PSWebServer.Jobs.CommandQueue
```

### Issue 2: UI Endpoint Format Incorrect

The task-manager UI endpoint returns the **wrong format**.

#### Current Format (INCORRECT):
```json
{
  "component": "task-manager",
  "title": "Task Management",
  "description": "Manage scheduled tasks, background jobs, and runspaces",
  "scriptPath": "/apps/WebHostTaskManagement/public/elements/task-manager/component.js",
  "width": 12,
  "height": 800,
  "features": [...]
}
```

#### Expected Format (CORRECT):
```json
{
  "status": "success",
  "scriptPath": "/apps/WebHostMetrics/public/elements/memory-histogram/component.js",
  "element": {
    "id": "task-manager",
    "type": "component",
    "component": "task-manager",
    "title": "Task Management",
    "icon": "📋",
    "refreshable": true,
    "helpFile": "public/help/task-manager.md"
  }
}
```

**Impact**: The UI framework may not correctly recognize or load the component.

---

## 📋 Recommended Solution

### Step 1: Module Reorganization

#### Option A: Move App-Specific Modules (RECOMMENDED)

Move job-related modules under the WebHostTaskManagement app:

```
Before:
  modules/
    ├── PSWebHost_JobExecution/    ❌ OLD - conflicts with new
    ├── PSWebHost_Jobs/             ✅ NEW - but app-specific
    └── PSWebHostTasks/             ✅ KEEP - scheduled tasks

After:
  modules/
    └── PSWebHostTasks/             ✅ Global scheduled tasks

  apps/WebHostTaskManagement/
    └── modules/
        ├── PSWebHost_Jobs/         ✅ App-specific job management
        └── (archive PSWebHost_JobExecution as deprecated)
```

**Benefits:**
- Clear separation: scheduled tasks (global) vs job execution (app-specific)
- No conflicts between old and new systems
- App owns its modules
- Easier to maintain and version

#### Option B: Deprecate Old System (ALTERNATIVE)

Keep PSWebHost_Jobs in global modules/ but remove PSWebHost_JobExecution:

```
modules/
  ├── PSWebHostTasks/               ✅ Scheduled tasks
  ├── PSWebHost_Jobs/               ✅ Job execution (new)
  └── _deprecated/
      └── PSWebHost_JobExecution/   ⛔ Archived
```

### Step 2: Update WebHost.ps1 Main Loop

Remove call to old job system:

```powershell
# CURRENT (lines 773-797) - calls BOTH systems:
if (Get-Command Process-PSWebHostJobSubmissions -ErrorAction SilentlyContinue) {
    Process-PSWebHostJobSubmissions  # ❌ OLD SYSTEM
}

# Process job system via WebHostTaskManagement main_loop.ps1 (new system)
$taskMgmtMainLoop = Join-Path $Global:PSWebServer.Project_Root.Path "apps\WebHostTaskManagement\main_loop.ps1"
if (Test-Path $taskMgmtMainLoop) {
    . $taskMgmtMainLoop  # ✅ NEW SYSTEM
}

# PROPOSED - only new system:
# Process app main_loop.ps1 files (includes job system via main_loop.ps1)
# (already implemented with scriptblock caching)
```

### Step 3: Fix UI Endpoint

Update `apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1`:

```powershell
# Current return structure:
$cardInfo = @{
    component = 'task-manager'
    title = 'Task Management'
    description = '...'
    scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
    width = 12
    height = 800
    features = @(...)
}

# Should be:
$elementConfig = @{
    status = 'success'
    scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
    element = @{
        id = 'task-manager'
        type = 'component'
        component = 'task-manager'
        title = 'Task Management'
        icon = '📋'
        description = 'Manage scheduled tasks, background jobs, and runspaces'
        refreshable = $true
        autoRefreshInterval = 5000  # 5 seconds
        helpFile = 'public/help/task-manager.md'
        width = 12  # Full width card
        height = 800
        features = @(
            'Browse and start jobs from catalog'
            'Monitor active background jobs'
            'View scheduled tasks'
            'Track runspace usage'
            'Stop and restart jobs'
            'Role-based permissions'
        )
    }
}
```

### Step 4: Update app.yaml Dependencies

Update `apps/WebHostTaskManagement/app.yaml`:

```yaml
# Current:
dependencies:
  - PSWebHost_Support
  - PSWebHostTasks

# Should be:
dependencies:
  - PSWebHost_Support
  - PSWebHostTasks  # For scheduled tasks
  # PSWebHost_Jobs loaded by app's modules/ folder
```

---

## 🔧 Implementation Plan

### Phase 1: Fix Immediate Issues (Do First)
1. ✅ Fix UI endpoint format
2. ✅ Remove call to Process-PSWebHostJobSubmissions from WebHost.ps1
3. ✅ Test that new job system works without old system

### Phase 2: Module Reorganization (Do After Testing)
1. Create `apps/WebHostTaskManagement/modules/` directory
2. Move `modules/PSWebHost_Jobs/` to `apps/WebHostTaskManagement/modules/PSWebHost_Jobs/`
3. Move `modules/PSWebHost_JobExecution/` to `modules/_deprecated/PSWebHost_JobExecution/`
4. Update module loading in app_init.ps1 or app.yaml
5. Test thoroughly

### Phase 3: Documentation
1. Document the separation:
   - **Scheduled Tasks** = PSWebHostTasks (cron-like, recurring)
   - **Job Execution** = PSWebHost_Jobs (on-demand, from catalog)
2. Create migration guide if any apps depend on old job system
3. Update API documentation

---

## 📊 Module Comparison Table

| Feature | PSWebHostTasks | PSWebHost_JobExecution (OLD) | PSWebHost_Jobs (NEW) |
|---------|---------------|------------------------------|----------------------|
| **Purpose** | Scheduled recurring tasks | On-demand job execution | Unified job management |
| **Definition** | tasks.yaml | File submission | apps/*/jobs/*.json |
| **Trigger** | Cron expressions | API submission | API/UI/Schedule |
| **State Location** | `$Global:PSWebServer.Tasks` | `$Global:PSWebServer.RunningJobs` | `$Global:PSWebServer.Jobs` |
| **Execution** | Main loop check | Background Job | Background Job/Main Loop/Runspace |
| **Discovery** | Config files | N/A | Auto-discover from apps |
| **Permissions** | Global config | N/A | Per-job roles |
| **Variables** | Task config | N/A | Template variables |
| **UI Integration** | View/Enable/Disable | Submit/Results | Catalog/Start/Stop/Restart |
| **Status** | ✅ Active | ⚠️ Deprecated | ✅ Active |
| **Should Keep?** | YES | NO | YES |
| **Location** | modules/ (global) | modules/ → _deprecated/ | modules/ OR apps/*/modules/ |

---

## 🎯 Decision Matrix

### When to Use Each System:

**Use PSWebHostTasks when:**
- Need recurring execution on a schedule (cron)
- Task should run automatically
- Task is defined in config
- Example: Daily cleanup, hourly metrics collection

**Use PSWebHost_Jobs when:**
- User triggers execution via UI/API
- Need template variables (dynamic parameters)
- Want job catalog browsing
- Need role-based permissions
- Example: On-demand reports, manual operations

**Don't Use PSWebHost_JobExecution:**
- ⛔ Legacy system
- ⛔ Being replaced by PSWebHost_Jobs
- ⛔ Causes conflicts and errors

---

## ⚠️ Breaking Changes Warning

If you move modules or deprecate PSWebHost_JobExecution:

**Check for dependencies:**
```powershell
# Search for uses of old job system
Get-ChildItem -Path "C:\SC\PsWebHost" -Recurse -Include "*.ps1","*.psm1" |
  Select-String "Submit-PSWebHostJob|Process-PSWebHostJobSubmissions" |
  Select-Object Path, LineNumber, Line
```

**Apps that might be affected:**
- Any app with routes calling `Submit-PSWebHostJob`
- Any background processes using old job system
- Scripts in `system/utility/` that interact with jobs

---

## 📝 Summary of Immediate Actions

1. **Fix UI endpoint** - Update to correct format (see Step 3)
2. **Remove old job system call** - Edit WebHost.ps1 (see Step 2)
3. **Test new system** - Restart server and verify job catalog works
4. **Document the change** - Update README/docs about new vs old systems

Then decide on module reorganization (Option A or B).
