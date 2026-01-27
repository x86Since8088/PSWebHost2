# Runspace Module Loading Issue - Fix

**Date**: 2026-01-27
**Issue**: Functions not recognized in async runspaces
**Status**: ✅ **FIXED** - Requires server restart

---

## Problem Report

### Error Messages

```
Error: The term 'context_response' is not recognized as a name of a cmdlet, function, script file, or executable program.
Source: modules\PSWebHost_Support\PSWebHost_Support.psm1::Process-HttpRequest
```

```
[FileExplorer] loadFolderContents ERROR: Failed to load folder: Internal Server Error
```

### Root Cause

**Typo in Module Manifest**: The PSWebHost_Support module manifest (`.psd1`) exported `context_reponse` (missing 's') instead of `context_response` (correct spelling).

**Impact**:
- When modules are loaded into async runspaces, the function `context_response` exists in the `.psm1` file
- But the manifest only exports `context_reponse` (typo)
- Result: The function is not available to be called, causing "term not recognized" errors

---

## Fix Applied

### File Modified

**`modules\PSWebHost_Support\PSWebHost_Support.psd1`** (line 15)

**Before**:
```powershell
FunctionsToExport = @(
    'Backup-ConfigurationFile',
    'Complete-PSWebHostEvent',
    'ConvertTo-CompressedBase64',
    'context_reponse',   # ❌ TYPO - missing 's'
    'Get-PSWebHostEvents',
    ...
)
```

**After**:
```powershell
FunctionsToExport = @(
    'Backup-ConfigurationFile',
    'Complete-PSWebHostEvent',
    'ConvertTo-CompressedBase64',
    'context_response',   # ✅ FIXED - correct spelling
    'Get-PSWebHostEvents',
    ...
)
```

---

## How Async Runspace Module Loading Works

### Architecture

When async runspaces are created, modules are loaded in two stages:

#### Stage 1: InitialSessionState (AsyncRunspacePool.ps1)

**File**: `system\AsyncRunspacePool.ps1` (lines 136-153)

```powershell
# Create initial session state with required modules
$iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

# Import core modules
$moduleFiles = @(
    "modules\PSWebHost_Support\PSWebHost_Support.psd1",
    "modules\PSWebHost_Users\PSWebHost_Users.psd1",
    "modules\PSWebHost_Logging\PSWebHost_Logging.psd1",
    "modules\PSWebHost_Database\PSWebHost_Database.psd1",
    "modules\PSWebHost_Authentication\PSWebHost_Authentication.psd1"
)

foreach ($modPath in $moduleFiles) {
    if (Test-Path $modPath) {
        $iss.ImportPSModule($modPath)  # Load module into InitialSessionState
    }
}

$rs = [runspacefactory]::CreateRunspace($iss)
$rs.Open()
```

**Modules loaded**:
- PSWebHost_Support ✓
- PSWebHost_Users ✓
- PSWebHost_Logging ✓
- PSWebHost_Database ✓
- PSWebHost_Authentication ✓

#### Stage 2: init.ps1 Execution (Lines 120-134)

**File**: `system\init.ps1` (lines 177-186 of AsyncRunspacePool.ps1)

After runspace opens, a setup script is executed:

```powershell
$setupScript = {
    param($PSWebServer, $PSWebSessions, ...)

    # Set global variables
    $global:PSWebServer = $PSWebServer
    $global:PSWebSessions = $PSWebSessions
    ...

    # Source init.ps1 with -ForRunspace flag
    . "$($global:PSWebServer.Project_Root.Path)/system/init.ps1" -ForRunspace
}
```

**init.ps1 with -ForRunspace** (lines 120-134):

```powershell
# Import core modules (if not already loaded)
Import-TrackedModule -Path "modules\Sanitization"
Import-TrackedModule -Path "modules\PSWebHost_Support"
Import-TrackedModule -Path "modules\PSWebHost_Database"
Import-TrackedModule -Path "modules\PSWebHost_Authentication"
Import-TrackedModule -Path "modules\smtp"

# Import app-specific modules
Get-ChildItem $AppsPath -Directory |
    Get-ChildItem -Filter modules |
    ForEach-Object { Import-TrackedModule $_.FullName }

# Exit early for runspaces (line 134)
if ($ForRunspace.IsPresent) { return }
```

**App modules loaded**:
- All modules from `apps/*/modules/*`
- Examples: FileExplorerHelper, PSWebHost_Metrics, etc.

---

## Why the Typo Caused Issues

### Function Export Mechanism

When a module is loaded:

1. **Module file (.psm1)** contains function definitions:
   ```powershell
   function context_response {
       # Function code here
   }
   ```

2. **Manifest file (.psd1)** controls what gets exported:
   ```powershell
   FunctionsToExport = @('context_response')
   ```

3. **Only exported functions** are available outside the module

With the typo:
- Function `context_response` exists in .psm1 ✓
- But manifest exports `context_reponse` (typo) ❌
- Result: Function is not exported → Not available to runspace → "Term not recognized" error

---

## Testing the Fix

### Diagnostic Script

**File**: `Test-RunspaceModuleLoading.ps1`

**Run**:
```powershell
# Must run while server is running
pwsh -File Test-RunspaceModuleLoading.ps1
```

**What it checks**:
- ✓ Loaded modules in runspace
- ✓ Availability of critical functions (context_response, Process-HttpRequest, etc.)
- ✓ Global variables ($global:PSWebServer)
- ✓ Identifies missing components

**Expected Output (After Fix + Restart)**:
```
=== Runspace Module Loading Diagnostics ===
✓ Async runspace pool is initialized

Testing runspace 0 (ID: ...)

--- Loaded Modules ---
  ✓ PSWebHost_Support
  ✓ PSWebHost_Database
  ✓ PSWebHost_Authentication
  ✓ PSWebHost_Logging
  ✓ PSWebHost_Users
  - Microsoft.PowerShell.Management
  ...

--- Critical Functions ---
  ✓ context_response
  ✓ Process-HttpRequest
  ✓ Get-RequestBody
  ✓ Write-PSWebHostLog
  ✓ Get-PSWebSQLiteData

--- Global Variables ---
  ✓ $global:PSWebServer

--- Analysis ---
  ✓ All critical components available
```

---

## Required Action

### Restart Server

The fix requires a server restart to reload the module with the corrected manifest:

```powershell
# Stop server (Ctrl+C or)
Stop-Process -Name pwsh -Force

# Start server
.\WebHost.ps1
```

**Why restart is needed**:
- Module is loaded into InitialSessionState when runspaces are created
- Runspaces use the module that was loaded at creation time
- Manifest changes don't affect already-loaded modules
- Restart recreates runspaces with the fixed module

---

## Verification Steps

### 1. Restart Server
```powershell
.\WebHost.ps1
```

### 2. Run Diagnostic
```powershell
# In separate terminal while server is running
pwsh -File Test-RunspaceModuleLoading.ps1
```

### 3. Test File Explorer
- Open browser to http://localhost:8080/spa
- Open File Explorer card
- Navigate to User:me
- Verify folder contents load without errors

### 4. Check Logs
```powershell
# Check for "term not recognized" errors
Get-Content system\db\sqlite\Logs.db | Select-String "context_response"
```

**Expected**: No new "term not recognized" errors after restart

---

## Other Potential Module Loading Issues

### Symptoms

If the diagnostic shows other missing functions or modules:

**Missing App Modules**:
- Symptom: App-specific functions not available
- Cause: App modules not loading via init.ps1
- Check: Lines 127-131 of system\init.ps1
- Fix: Ensure app module paths are correct

**Missing Global Variables**:
- Symptom: $global:PSWebServer is null
- Cause: Setup script in AsyncRunspacePool.ps1 not running
- Check: Lines 177-197 of system\AsyncRunspacePool.ps1
- Fix: Verify setup script execution

**Module Import Failures**:
- Symptom: Expected modules not in loaded list
- Cause: Module file not found or has errors
- Check: Test-Path for module .psd1/.psm1 files
- Fix: Verify module files exist and are valid

### Debug Logging

Add verbose logging to diagnose module loading:

**In init.ps1** (line 46):
```powershell
$moduleInfo = Import-Module $Path -Force -DisableNameChecking -PassThru -Verbose -ErrorAction Continue
```

**In AsyncRunspacePool.ps1** (line 151):
```powershell
Write-Host "Loading module: $modPath" -ForegroundColor Yellow
$iss.ImportPSModule($modPath)
```

---

## Summary

**Issue**: Module manifest typo prevented `context_response` function from being exported

**Fix**: Corrected typo in `modules\PSWebHost_Support\PSWebHost_Support.psd1`

**Status**: ✅ Fixed - Requires server restart

**Action Required**: Restart server to reload modules with corrected manifest

**Verification**: Run `Test-RunspaceModuleLoading.ps1` diagnostic script

---

**Created**: 2026-01-27
**Fixed In**: `modules\PSWebHost_Support\PSWebHost_Support.psd1`
**Requires**: Server restart to take effect
