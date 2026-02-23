# PSWebHost_TaskManagement Module Created - 2026-01-26

## Summary

✅ **Created module manifest (.psd1) for PSWebHost_TaskManagement module**
✅ **Updated app_init.ps1 to use Import-TrackedModule for hot reload support**

---

## What Was Done

### 1. Created Module Manifest
**File**: `apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psd1`

**Module Information**:
- **Name**: PSWebHost_TaskManagement
- **Version**: 1.0.0
- **GUID**: f8a9b7c6-d5e4-3f2a-1b0c-9d8e7f6a5b4c
- **Description**: Job Command Queue Module - File-based command queue for API endpoints to communicate with main_loop.ps1

**Exported Functions** (3):
1. `Submit-JobCommand` - Submit job commands to queue for main_loop.ps1 processing
2. `Get-JobCommandStatus` - Check status of submitted commands
3. `Get-JobStatus` - Get status of running/completed jobs

**Internal Functions** (not exported):
- `Get-JobCommandQueuePath` - Helper function for queue directory management

### 2. Updated app_init.ps1 for Hot Reload
**File**: `apps/WebHostTaskManagement/app_init.ps1`

**Changed From**:
```powershell
$modulePath = Join-Path $AppRoot "modules\PSWebHost_TaskManagement"
if (Test-Path $modulePath) {
    $moduleFiles = @(Get-ChildItem -Path $modulePath -Filter "*.ps*1" -File)
    if ($moduleFiles.Count -gt 0) {
        Import-Module $modulePath -Force -ErrorAction Stop
```

**Changed To**:
```powershell
$manifestPath = Join-Path $AppRoot "modules\PSWebHost_TaskManagement\PSWebHost_TaskManagement.psd1"
if (Test-Path $manifestPath) {
    # Use Import-TrackedModule for hot reload support
    Import-TrackedModule -Path $manifestPath
```

**Benefits**:
- ✅ Hot reload enabled - module changes detected automatically
- ✅ No server restart needed for module updates
- ✅ Consistent with FileExplorerHelper module pattern
- ✅ Uses manifest (.psd1) instead of directory path

---

## Module Structure

```
apps/WebHostTaskManagement/
├── modules/
│   └── PSWebHost_TaskManagement/
│       ├── PSWebHost_TaskManagement.psd1    ← NEW manifest
│       └── PSWebHost_TaskManagement.psm1    ← Renamed from JobCommandQueue.psm1
└── app_init.ps1                             ← UPDATED to use Import-TrackedModule
```

---

## Function Details

### Submit-JobCommand
**Purpose**: Submit a job command to the file-based queue

**Parameters**:
- `Command` - Command type: 'start', 'stop', 'restart', 'status'
- `JobID` - Job identifier (AppName/JobName)
- `UserID` - User ID submitting the command
- `SessionID` - Optional session ID
- `Variables` - Optional hashtable of template variables
- `Roles` - User roles for permission checking

**Returns**: Command object with CommandID

**Usage**:
```powershell
$result = Submit-JobCommand -Command 'start' -JobID 'WebHostMetrics/CollectMetrics' -UserID $userId -Variables @{Interval = 30}
```

### Get-JobCommandStatus
**Purpose**: Check the status of a submitted command

**Parameters**:
- `CommandID` - Command ID to check

**Returns**: Status object or $null if not found

**Usage**:
```powershell
$status = Get-JobCommandStatus -CommandID $commandID
if ($status.Status -eq 'Completed') {
    # Command processed successfully
}
```

### Get-JobStatus
**Purpose**: Get the status of a running or completed job

**Parameters**:
- `ExecutionID` - Execution ID of the job
- `UserID` - User ID for permission checking

**Returns**: Job status object or $null if not found/no permission

**Usage**:
```powershell
$jobStatus = Get-JobStatus -ExecutionID $executionID -UserID $userId
Write-Host "Job Status: $($jobStatus.Status)"
```

---

## How the Command Queue Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  API Endpoint (Runspace)                                    │
│  ┌──────────────────────────────────────┐                   │
│  │ Submit-JobCommand                    │                   │
│  │  - Creates command JSON file         │                   │
│  │  - Writes to JobCommandQueue/        │                   │
│  └──────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
                        │
                        │ Write command.json
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  PsWebHost_Data/apps/WebHostTaskManagement/                 │
│  ├── JobCommandQueue/           (Pending commands)          │
│  │   ├── {guid-1}.json                                      │
│  │   └── {guid-2}.json                                      │
│  ├── JobCommandResults/         (Processed commands)        │
│  │   ├── {guid-1}.json                                      │
│  │   └── {guid-2}.json                                      │
│  └── JobStatus/                 (Running job status)        │
│      ├── {execution-id-1}.json                              │
│      └── {execution-id-2}.json                              │
└─────────────────────────────────────────────────────────────┘
                        ▲
                        │ Read & process commands
                        │
┌─────────────────────────────────────────────────────────────┐
│  main_loop.ps1 (Main Process)                               │
│  ┌──────────────────────────────────────┐                   │
│  │ Process-JobCommandQueue              │                   │
│  │  - Reads JobCommandQueue/            │                   │
│  │  - Processes each command            │                   │
│  │  - Has access to $Global:PSWebServer │                   │
│  │  - Moves to JobCommandResults/       │                   │
│  └──────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────┘
```

### Why File-Based Queue?

**Problem**: API endpoints run in runspaces (separate threads) and can't directly modify `$Global:PSWebServer.Jobs` in the main process.

**Solution**: File-based command queue
- API endpoints write command files to queue directory
- main_loop.ps1 reads and processes commands with full access to global state
- Results written back to results directory for API to retrieve

**Benefits**:
- ✅ Thread-safe communication between runspaces and main process
- ✅ Persistent queue survives runspace recycles
- ✅ Simple debugging (inspect .json files directly)
- ✅ No complex synchronization primitives needed

---

## Testing

### Module Validation
```powershell
# Validate manifest
Test-ModuleManifest "apps\WebHostTaskManagement\modules\PSWebHost_TaskManagement\PSWebHost_TaskManagement.psd1"

# Result: ✅ Valid
# Name: PSWebHost_TaskManagement
# Version: 1.0.0
# ExportedFunctions: Submit-JobCommand, Get-JobCommandStatus, Get-JobStatus
```

### Module Import Test
```powershell
# Import with manifest
Import-Module "apps\WebHostTaskManagement\modules\PSWebHost_TaskManagement\PSWebHost_TaskManagement.psd1" -Force

# Verify functions
Get-Command -Module PSWebHost_TaskManagement

# Result: ✅ Shows 3 exported functions
```

### Hot Reload Test
After server restart:
1. Edit PSWebHost_TaskManagement.psm1
2. Wait 30 seconds (Invoke-ModuleRefreshAsNeeded runs)
3. Module should auto-reload with changes
4. Verify: `$Global:PSWebServer.Modules.PSWebHost_TaskManagement.LastWriteTime`

---

## Integration with Existing Code

### Routes Using This Module

**Before** (if they were using old import):
```powershell
# Some routes might have been importing the module directly
Import-Module (Join-Path $PSScriptRoot "..\..\modules\PSWebHost_TaskManagement")
```

**Now** (should use):
```powershell
# Module is already loaded by app_init.ps1 via Import-TrackedModule
# Routes can call functions directly:
$result = Submit-JobCommand -Command 'start' -JobID $jobId -UserID $userId
```

### Example: Start Job Endpoint
```powershell
# apps/WebHostTaskManagement/routes/api/v1/jobs/start/post.ps1

# Submit command to queue (module function available globally)
$commandResult = Submit-JobCommand `
    -Command 'start' `
    -JobID $data.jobId `
    -UserID $sessiondata.UserID `
    -SessionID $sessiondata.SessionID `
    -Variables $data.variables `
    -Roles $sessiondata.Roles

# Return command ID to client
$json = @{
    success = $true
    commandId = $commandResult.CommandID
    message = "Job start command queued"
} | ConvertTo-Json

context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
```

---

## Comparison with Other Modules

### PSWebHost_TaskManagement vs FileExplorerHelper

| Aspect | PSWebHost_TaskManagement | FileExplorerHelper |
|--------|-------------------------|-------------------|
| **Purpose** | Job command queue | File operation helpers |
| **Exported Functions** | 3 | 16 |
| **Scope Access** | Uses global variables directly | Calls global functions via Get-Command |
| **Hot Reload** | ✅ Enabled | ✅ Enabled |
| **Location** | apps/WebHostTaskManagement/modules/ | apps/WebhostFileExplorer/modules/ |
| **Load Method** | Import-TrackedModule in app_init.ps1 | Import-TrackedModule in route files |

**Key Difference**:
- PSWebHost_TaskManagement is loaded **once** by app_init.ps1 and available to all routes
- FileExplorerHelper is loaded by **each route file** that needs it

**Why**:
- TaskManagement module provides core functionality needed by all task endpoints
- FileExplorer module is only needed by FileExplorer endpoints

---

## Migration Notes

### If You Had Old References

**Old module location** (if it existed):
```
modules/PSWebHost_Jobs/JobCommandQueue.psm1
```

**New module location**:
```
apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psm1
apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psd1  ← NEW
```

**Old import**:
```powershell
Import-Module "modules\PSWebHost_Jobs\JobCommandQueue.psm1"
```

**New import** (in app_init.ps1):
```powershell
Import-TrackedModule -Path (Join-Path $AppRoot "modules\PSWebHost_TaskManagement\PSWebHost_TaskManagement.psd1")
```

### Update Any Direct Imports

If any route files were importing the module directly, they should be updated:

**Before**:
```powershell
Import-Module (Join-Path $PSScriptRoot "..\..\modules\PSWebHost_Jobs\JobCommandQueue.psm1")
```

**After**:
```powershell
# Module already loaded by app_init.ps1 - no import needed
# Just call the functions directly
```

---

## Benefits of This Change

### 1. Proper Module Structure ✅
- Manifest file (.psd1) provides metadata and version control
- Explicit function exports (no implicit exports)
- Standard PowerShell module layout

### 2. Hot Reload Support ✅
- Changes to module automatically detected
- No server restart needed for development
- Tracked in `$Global:PSWebServer.Modules`

### 3. Better Organization ✅
- Module lives with the app that uses it
- Clear ownership (TaskManagement app owns this module)
- Easier to maintain and update

### 4. Consistency ✅
- Follows same pattern as FileExplorerHelper
- Aligns with module accountability guidelines
- Uses Import-TrackedModule for all app modules

---

## Next Steps

### 1. Restart Server
The module manifest and app_init.ps1 changes require a server restart to take effect.

### 2. Verify Module Load
After restart, check logs for:
```
Loaded PSWebHost_TaskManagement module with hot reload from: ...PSWebHost_TaskManagement.psd1
```

### 3. Test Job Operations
1. Submit a job start command
2. Check command status
3. Verify job executes
4. Check job status

### 4. Test Hot Reload
1. Edit PSWebHost_TaskManagement.psm1 (add a comment)
2. Wait 30 seconds
3. Check `$Global:PSWebServer.Modules.PSWebHost_TaskManagement.LastWriteTime`
4. Should show updated timestamp

---

## Files Modified/Created

### Created (1 file):
- `apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psd1`

### Modified (1 file):
- `apps/WebHostTaskManagement/app_init.ps1`

### Already Existed:
- `apps/WebHostTaskManagement/modules/PSWebHost_TaskManagement/PSWebHost_TaskManagement.psm1` (user moved and renamed)

---

**Created**: 2026-01-26
**Status**: ✅ READY FOR SERVER RESTART
**Next Action**: Restart server and verify module loads with hot reload
