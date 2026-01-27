# PSWebHost Job System - Quick Reference

## Overview

The PSWebHost Job System provides a unified, role-based architecture for managing background jobs across all applications. Jobs are discovered automatically, support template variables, and execute in isolated PowerShell background jobs.

## Utility Scripts

All utility scripts are located in `system/utility/`

### 📋 TaskManagement_AppJobFolder_Get.ps1
**Lists all available jobs across all apps**

```powershell
# Table format (default)
.\system\utility\TaskManagement_AppJobFolder_Get.ps1

# Detailed list format
.\system\utility\TaskManagement_AppJobFolder_Get.ps1 -Format List

# JSON format (for APIs/scripting)
.\system\utility\TaskManagement_AppJobFolder_Get.ps1 -Format Json

# Interactive grid (GUI selection)
.\system\utility\TaskManagement_AppJobFolder_Get.ps1 -Format Grid

# Filter by app
.\system\utility\TaskManagement_AppJobFolder_Get.ps1 -AppName "WebHostMetrics"
```

**Output:**
- JobID (AppName/JobName)
- Display Name
- Description
- Schedule (cron format)
- Template Variables
- Role Permissions (Start/Stop/Restart)
- Init Script indicator
- File paths

### ✨ TaskManagement_JobFolderInApp_New.ps1
**Creates a new job with proper structure and templates**

```powershell
# Basic job
.\system\utility\TaskManagement_JobFolderInApp_New.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -DisplayName "My Job Display Name" `
    -Description "What this job does"

# With cron schedule
.\system\utility\TaskManagement_JobFolderInApp_New.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -DisplayName "Scheduled Job" `
    -Description "Runs on schedule" `
    -DefaultSchedule "*/5 * * * *"

# With init script
.\system\utility\TaskManagement_JobFolderInApp_New.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -DisplayName "Job with Init" `
    -Description "Uses init-job.ps1" `
    -CreateInitScript

# With custom permissions
.\system\utility\TaskManagement_JobFolderInApp_New.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -DisplayName "Restricted Job" `
    -Description "Needs admin" `
    -RolesStart @('admin') `
    -RolesStop @('admin', 'operator') `
    -RolesRestart @('admin')
```

**Creates:**
- `apps/[AppName]/jobs/[JobName]/` directory
- `job.json` with metadata
- `[JobName].ps1` script with -Test and -Roles parameters
- `init-job.ps1` (if -CreateInitScript specified)

### 🧪 TaskManagement_AppJobFolder_Test.ps1
**Tests a job without starting the server**

```powershell
# Basic test
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics"

# With template variables
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics" `
    -Variables @{Interval='10'}

# Validation only (don't execute)
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -SkipExecution

# With verbose output
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{MyVar='value'} `
    -Verbose
```

**Validates:**
- ✓ job.json exists and is valid
- ✓ All required fields present
- ✓ init-job.ps1 executes successfully (if exists)
- ✓ Template variables provided
- ✓ Job script executes with -Test switch
- ✓ Clean JSON output to stdout

### ▶️ TaskManagement_AppJobFolder_Start.ps1
**Starts a job (requires server running)**

```powershell
# Basic start
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics"

# With template variables
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics" `
    -Variables @{Interval='30'}

# With specific user/session
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -UserID "john.doe" `
    -SessionID "session-123" `
    -Variables @{MyVar='value'}
```

**Returns:**
- ExecutionID (GUID)
- Status (Queued)

**Process:**
1. Validates job exists in catalog
2. Checks user permissions
3. Initializes job (runs init-job.ps1)
4. Processes template variables
5. Queues start command
6. Processes command queue
7. Shows running jobs

### ⏹️ TaskManagement_AppJobFolder_Stop.ps1
**Stops a running job**

```powershell
# Stop job
.\system\utility\TaskManagement_AppJobFolder_Stop.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics"

# With specific user
.\system\utility\TaskManagement_AppJobFolder_Stop.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -UserID "john.doe"
```

**Process:**
1. Checks job is running
2. Validates user permissions
3. Queues stop command
4. Processes command queue
5. Moves job to history

### 🔄 TaskManagement_AppJobFolder_Restart.ps1
**Restarts a job (stop then start)**

```powershell
# Restart job
.\system\utility\TaskManagement_AppJobFolder_Restart.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics"

# With new variables
.\system\utility\TaskManagement_AppJobFolder_Restart.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics" `
    -Variables @{Interval='60'}
```

**Process:**
1. Queues stop command (if running)
2. Queues start command with new variables
3. Processes command queue

## Common Workflows

### Creating a New Job

```powershell
# 1. Create job structure
.\system\utility\TaskManagement_JobFolderInApp_New.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -DisplayName "My Job" `
    -Description "Does something useful" `
    -CreateInitScript

# 2. Edit job script
notepad apps\MyApp\jobs\MyJob\MyJob.ps1

# 3. Edit init script (if needed)
notepad apps\MyApp\jobs\MyJob\init-job.ps1

# 4. Update job.json (if needed)
notepad apps\MyApp\jobs\MyJob\job.json

# 5. Test the job
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{MyVar='value'}
```

### Running a Job

```powershell
# 1. Start the server (if not running)
.\WebHost.ps1 -Port 8080

# 2. List available jobs
.\system\utility\TaskManagement_AppJobFolder_Get.ps1

# 3. Start the job
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{MyVar='value'}

# 4. Stop the job when done
.\system\utility\TaskManagement_AppJobFolder_Stop.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob"
```

### Debugging a Job

```powershell
# 1. Test without server
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{MyVar='value'} `
    -Verbose

# 2. Check job output (pipe to file)
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{MyVar='value'} > output.json

# 3. Validate only (don't execute)
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -SkipExecution
```

## Job Script Template

Every job script should follow this pattern:

```powershell
#Requires -Version 7

<#
.SYNOPSIS
    Job display name

.DESCRIPTION
    Job description

.PARAMETER Test
    If specified, runs in test mode (single execution, stdout output)

.PARAMETER Roles
    User roles (auto-populated from security.json)

.PARAMETER Variables
    Hashtable of variables passed from job initialization
#>

[CmdletBinding()]
param(
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Variables = @{}
)

$MyTag = '[AppName:Job:JobName]'

try {
    # Get variables
    $myVar = if ($Variables.ContainsKey('MyVar')) {
        $Variables['MyVar']
    } else {
        'default_value'
    }

    # Test mode: Run once and output data to stdout
    if ($Test) {
        Write-Verbose "$MyTag Running in TEST mode"

        # Perform test operations
        $result = @{
            Success = $true
            Message = "Test completed"
            Data = @{
                # Your data here
            }
        }

        Write-Verbose "$MyTag Test completed"

        # Output data to stdout (commentary in verbose stream)
        return $result
    }

    # Normal mode: Continuous operation
    Write-Host "$MyTag Starting job..." -ForegroundColor Cyan
    Write-Host "$MyTag MyVar: $myVar" -ForegroundColor Gray

    while ($true) {
        # Job logic here
        Write-Host "$MyTag Performing work..." -ForegroundColor Yellow

        # Do work...

        Start-Sleep -Seconds 5
    }
}
catch {
    Write-Error "$MyTag Job failed: $_"

    if ($Test) {
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }

    throw
}
```

## job.json Template

```json
{
  "Name": "Display Name",
  "Description": "Description with {{VariableName}} templates",
  "default_schedule": "*/5 * * * *",
  "ScriptRelativePath": "JobName.ps1",
  "argumentlist": [],
  "roles_start": ["admin", "operator"],
  "roles_stop": ["admin"],
  "roles_restart": ["admin"],
  "template_variables": {
    "VariableName": "Description of what this variable does"
  }
}
```

## init-job.ps1 Template

```powershell
#Requires -Version 7

<#
.SYNOPSIS
    Initialization script for job

.DESCRIPTION
    Runs before job.json is parsed
    Use for validation and setting defaults

.PARAMETER Variables
    Hashtable of variables for template substitution
#>

[CmdletBinding()]
param(
    [hashtable]$Variables = @{}
)

$MyTag = '[AppName:Job:JobName:Init]'

try {
    Write-Verbose "$MyTag Running initialization..."

    # Set default variables
    if (-not $Variables.ContainsKey('MyVar')) {
        $Variables['MyVar'] = 'default_value'
        Write-Verbose "$MyTag Set default MyVar: default_value"
    }

    # Validate required variables
    if (-not $Variables.ContainsKey('RequiredVar')) {
        throw "Required variable 'RequiredVar' not provided"
    }

    # Validate variable values
    $myVar = $Variables['MyVar']
    if ($myVar -notmatch '^[a-z]+$') {
        throw "MyVar must contain only lowercase letters, got: $myVar"
    }

    Write-Verbose "$MyTag Initialization complete"
}
catch {
    Write-Error "$MyTag Initialization failed: $_"
    throw
}
```

## Cron Schedule Examples

```
*/5 * * * *     # Every 5 minutes
0 * * * *       # Every hour
0 0 * * *       # Daily at midnight
0 2 * * 0       # Weekly on Sunday at 2am
0 0 1 * *       # Monthly on the 1st at midnight
```

## Role-Based Permissions

Jobs support three permission levels:

- **roles_start**: Who can start the job
- **roles_stop**: Who can stop the job
- **roles_restart**: Who can restart the job

Common role patterns:

```json
// Admin only
{
  "roles_start": ["admin"],
  "roles_stop": ["admin"],
  "roles_restart": ["admin"]
}

// Operators can start/restart, only admin can stop
{
  "roles_start": ["admin", "operator"],
  "roles_stop": ["admin"],
  "roles_restart": ["admin", "operator"]
}

// Multiple viewer roles can start, admins control
{
  "roles_start": ["admin", "metrics_viewer", "dashboard_user"],
  "roles_stop": ["admin"],
  "roles_restart": ["admin"]
}

// No roles = all authenticated users
{
  "roles_start": [],
  "roles_stop": [],
  "roles_restart": []
}
```

## Template Variables

Template variables allow job metadata to adapt based on input:

```json
{
  "Description": "Collects metrics every {{Interval}} seconds",
  "template_variables": {
    "Interval": "Interval in seconds between collections"
  }
}
```

Provide variables when starting jobs:

```powershell
.\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob" `
    -Variables @{Interval='30'}
```

Variables are validated in init-job.ps1:

```powershell
# Check if variable provided
if (-not $Variables.ContainsKey('Interval')) {
    throw "Required variable 'Interval' not provided"
}

# Validate value
$interval = [int]$Variables['Interval']
if ($interval -lt 5 -or $interval -gt 3600) {
    throw "Interval must be between 5 and 3600 seconds"
}
```

## Test Mode vs Normal Mode

### Test Mode (-Test)
- Runs once and exits
- Outputs data to stdout (JSON)
- Commentary goes to verbose stream
- Perfect for testing and scripting
- No server required

```powershell
# Test mode
.\apps\MyApp\jobs\MyJob\MyJob.ps1 -Test -Variables @{MyVar='value'}

# Capture output
$result = .\apps\MyApp\jobs\MyJob\MyJob.ps1 -Test -Variables @{MyVar='value'} | ConvertFrom-Json
```

### Normal Mode
- Runs continuously (while loop)
- Outputs to host (colored)
- Runs as background job
- Controlled via APIs
- Requires server running

```powershell
# Normal mode (via utility)
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "MyApp" `
    -JobName "MyJob"
```

## Module Functions (Advanced)

If you need programmatic access:

```powershell
# Import module
Import-Module .\modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1

# Initialize system
Initialize-PSWebHostJobSystem

# Get catalog
$catalog = Get-PSWebHostJobCatalog
$catalog.Keys  # List all JobIDs

# Start job
$result = Start-PSWebHostJob `
    -JobID "MyApp/MyJob" `
    -UserID "john.doe" `
    -Variables @{MyVar='value'} `
    -Roles @('admin')

# Process commands
Process-PSWebHostJobCommandQueue

# Get running jobs
$running = Get-PSWebHostRunningJobs -UserID "john.doe"

# Get job status
$status = Get-PSWebHostJobStatus `
    -ExecutionID $result.ExecutionID `
    -UserID "john.doe"

# Stop job
Stop-PSWebHostJob `
    -JobID "MyApp/MyJob" `
    -UserID "john.doe" `
    -Roles @('admin')
```

## Troubleshooting

### Job not discovered
```powershell
# Check job.json exists
Test-Path apps\MyApp\jobs\MyJob\job.json

# Validate JSON
Get-Content apps\MyApp\jobs\MyJob\job.json | ConvertFrom-Json

# Check catalog
.\system\utility\TaskManagement_AppJobFolder_Get.ps1
```

### Job won't start
```powershell
# Test manually first
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 -AppName "MyApp" -JobName "MyJob" -Verbose

# Check permissions
$catalog = Get-PSWebHostJobCatalog
$catalog['MyApp/MyJob'].Metadata.roles_start
```

### Template variables not working
```powershell
# Test init-job.ps1
$Variables = @{MyVar='test'}
. apps\MyApp\jobs\MyJob\init-job.ps1 -Variables $Variables -Verbose
$Variables  # Check variables after init

# Verify template syntax in job.json
Get-Content apps\MyApp\jobs\MyJob\job.json -Raw | Select-String '\{\{(\w+)\}\}'
```

## Example: WebHostMetrics/CollectMetrics

Complete working example located at:
`apps/WebHostMetrics/jobs/CollectMetrics/`

**Features:**
- Collects CPU, memory, disk metrics
- Template variable: `{{Interval}}` (5-3600 seconds)
- init-job.ps1 validates interval
- Test mode: Single collection
- Normal mode: Continuous collection
- Roles: admin, metrics_viewer (start)

**Usage:**
```powershell
# Test
.\system\utility\TaskManagement_AppJobFolder_Test.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics" `
    -Variables @{Interval='10'}

# Start (30 second intervals)
.\system\utility\TaskManagement_AppJobFolder_Start.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics" `
    -Variables @{Interval='30'}

# Stop
.\system\utility\TaskManagement_AppJobFolder_Stop.ps1 `
    -AppName "WebHostMetrics" `
    -JobName "CollectMetrics"
```

---

**Documentation:** `NEW_JOB_SYSTEM_IMPLEMENTATION_2026-01-25.md`
**Module:** `modules/PSWebHost_Jobs/`
**Utilities:** `system/utility/TaskManagement_*.ps1`
**Example:** `apps/WebHostMetrics/jobs/CollectMetrics/`
