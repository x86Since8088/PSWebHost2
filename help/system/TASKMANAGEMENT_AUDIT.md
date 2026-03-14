# TaskManagement Backend/Frontend Audit

## 🔍 Issues Found

### Issue 1: app_init.ps1 - Single Large Try-Catch Block
**Problem:** Lines 15-352 wrapped in one try-catch
- If ANY step fails, entire initialization stops
- No granular error reporting
- Harder to debug which step failed

**Impact:** HIGH - One module failure kills entire app init

### Issue 2: app_init.ps1 - Loading OLD Job System
**Problem:** Lines 23-30 load PSWebHost_JobExecution (old/deprecated)
```powershell
$jobModulePath = Join-Path $PSWebServer['Project_Root'].Path "modules\PSWebHost_JobExecution"
if (Test-Path $jobModulePath) {
    Import-Module $jobModulePath -DisableNameChecking -Force
```

**Impact:** HIGH - Conflicts with new PSWebHost_Jobs system

### Issue 3: app_init.ps1 - No Write-PSWebHostLog
**Problem:** Using Write-Warning, Write-Verbose, Write-Host
- Not centrally logged
- Hard to trace in production

**Impact:** MEDIUM - Poor observability

### Issue 4: API Endpoints - Inconsistent Logging
**Problem:** Most endpoints use Write-Error instead of Write-PSWebHostLog

**Files to check:**
- `/api/v1/jobs/catalog/get.ps1` ✅ Uses Write-PSWebHostLog
- `/api/v1/jobs/start/post.ps1` ✅ Uses Write-PSWebHostLog
- `/api/v1/jobs/stop/post.ps1` ✅ Uses Write-PSWebHostLog
- `/api/v1/tasks/get.ps1` - Need to check
- `/api/v1/tasks/post.ps1` - Need to check
- `/api/v1/jobs/get.ps1` - Need to check
- `/api/v1/jobs/output/get.ps1` - Need to check
- `/api/v1/jobs/delete.ps1` - Need to check
- `/api/v1/jobs/results/get.ps1` - Need to check
- `/api/v1/jobs/results/delete.ps1` - Need to check
- `/api/v1/runspaces/get.ps1` - Need to check

### Issue 5: Frontend/Backend API Mismatch
**Problem:** Frontend expects endpoints that might not exist or use different patterns

## 📊 Frontend API Calls vs Backend Endpoints

| Frontend Call | Backend File | Match | Issues |
|--------------|--------------|-------|--------|
| `GET /api/v1/tasks` | `/tasks/get.ps1` | ✅ | Check logging |
| `POST /api/v1/tasks` | `/tasks/post.ps1` | ✅ | Check logging |
| `GET /api/v1/jobs` | `/jobs/get.ps1` | ✅ | Check logging |
| `DELETE /api/v1/jobs?jobId=X` | `/jobs/delete.ps1` | ⚠️ | URL pattern mismatch? |
| `GET /api/v1/jobs/catalog` | `/jobs/catalog/get.ps1` | ✅ | Good |
| `POST /api/v1/jobs/start` | `/jobs/start/post.ps1` | ✅ | Good |
| `POST /api/v1/jobs/stop` | `/jobs/stop/post.ps1` | ✅ | Good |
| `GET /api/v1/jobs/output?jobId=X` | `/jobs/output/get.ps1` | ✅ | Check logging |
| `GET /api/v1/jobs/results?maxResults=100` | `/jobs/results/get.ps1` | ✅ | Check logging |
| `DELETE /api/v1/jobs/results?jobId=X` | `/jobs/results/delete.ps1` | ✅ | Check logging |
| `GET /api/v1/runspaces` | `/runspaces/get.ps1` | ✅ | Check logging |

## 🔧 Required Fixes

### Fix 1: Refactor app_init.ps1 with Granular Try-Catch

Replace single try-catch with individual blocks for each step:

```powershell
# Step 1: Import app module
try {
    $modulePath = Join-Path $AppRoot "modules\PSWebHost_TaskManagement"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -Force
        Write-PSWebHostLog -Severity 'Info' -Category 'AppInit' -Message "Loaded PSWebHost_TaskManagement module"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppInit' -Message "Failed to load PSWebHost_TaskManagement module: $($_.Exception.Message)"
}

# Step 2: Initialize app namespace
try {
    $PSWebServer['WebHostTaskManagement'] = [hashtable]::Synchronized(@{ ... })
    Write-PSWebHostLog -Severity 'Info' -Category 'AppInit' -Message "Initialized app namespace"
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppInit' -Message "Failed to initialize namespace: $($_.Exception.Message)"
}

# ... continue for each step
```

### Fix 2: Remove OLD Job System Load

**DELETE lines 23-30:**
```powershell
# 2. Import job execution module (required for job submission endpoints)
$jobModulePath = Join-Path $PSWebServer['Project_Root'].Path "modules\PSWebHost_JobExecution"
if (Test-Path $jobModulePath) {
    Import-Module $jobModulePath -DisableNameChecking -Force
    Write-Verbose "$MyTag Loaded PSWebHost_JobExecution module" -Verbose
} else {
    Write-Warning "$MyTag Job execution module not found: $jobModulePath"
}
```

**REPLACE with:**
```powershell
# 2. Verify PSWebHost_Jobs module is loaded (new system)
try {
    if (-not (Get-Module PSWebHost_Jobs)) {
        Write-PSWebHostLog -Severity 'Warning' -Category 'AppInit' -Message "PSWebHost_Jobs module not loaded - job features will be limited"
    } else {
        Write-PSWebHostLog -Severity 'Info' -Category 'AppInit' -Message "PSWebHost_Jobs module available"
    }
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppInit' -Message "Error checking PSWebHost_Jobs: $($_.Exception.Message)"
}
```

### Fix 3: Add Write-PSWebHostLog Throughout

**Replace:**
- `Write-Host` → `Write-PSWebHostLog -Severity 'Info'`
- `Write-Verbose` → `Write-PSWebHostLog -Severity 'Verbose'`
- `Write-Warning` → `Write-PSWebHostLog -Severity 'Warning'`
- `Write-Error` → `Write-PSWebHostLog -Severity 'Error'`

**Category:** Use `'AppInit'` for app_init.ps1

### Fix 4: Audit and Fix API Endpoint Logging

Each API endpoint should:
1. Use Write-PSWebHostLog for all errors
2. Include request context (UserID, SessionID if available)
3. Log important operations (start job, stop job, etc.)

**Pattern:**
```powershell
try {
    # ... endpoint logic
    Write-PSWebHostLog -Severity 'Info' -Category 'TaskManagement' -Message "Job started: $jobId by user: $($sessiondata.UserID)"
} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'TaskManagement' -Message "Failed to start job: $($_.Exception.Message)" -Data @{
        JobID = $jobId
        UserID = $sessiondata.UserID
        Error = $_.Exception.ToString()
    }
    # Return error response...
}
```

### Fix 5: Ensure Frontend/Backend Consistency

Check each endpoint parameter handling matches frontend expectations.

## 📝 Implementation Order

1. **CRITICAL** - Fix app_init.ps1:
   - Remove old job system load
   - Break into granular try-catch blocks
   - Add Write-PSWebHostLog throughout

2. **HIGH** - Audit API endpoints:
   - Check each for Write-PSWebHostLog usage
   - Verify parameter handling matches frontend
   - Add proper error logging

3. **MEDIUM** - Verify frontend/backend contracts:
   - Test each API call from frontend
   - Ensure response formats match expectations
   - Add error handling on both sides

## 🧪 Testing Checklist

After fixes:
- [ ] Server starts without errors
- [ ] app_init.ps1 logs each step clearly
- [ ] Old job system not loaded
- [ ] All API endpoints use Write-PSWebHostLog
- [ ] Frontend can call all endpoints successfully
- [ ] Errors are properly logged to server logs
- [ ] No "Using legacy endpoint" message

## 📊 Expected Log Output After Fixes

```
[AppInit] Loading PSWebHost_TaskManagement module
[AppInit] Loaded PSWebHost_TaskManagement module
[AppInit] Verifying PSWebHost_Jobs module
[AppInit] PSWebHost_Jobs module available
[AppInit] Initializing app namespace
[AppInit] Initialized app namespace
[AppInit] Creating data directories
[AppInit] Created data directory: C:\...\apps\WebHostTaskManagement
[AppInit] Initializing task database
[AppInit] Created multi-node task database
[AppInit] Registered node: abc123 (hostname)
[AppInit] Loading task inventory
[AppInit] Loaded 5 tasks
[AppInit] Task management system initialized
```
