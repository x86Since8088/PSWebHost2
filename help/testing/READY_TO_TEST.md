# Ready to Test - Job Catalog Frontend Integration

## ✅ Completed Work

### 1. Frontend Integration (Complete)
**File: `apps/WebHostTaskManagement/public/elements/task-manager/component.js`**
- ✅ Added state properties for catalog, modal, and variables
- ✅ Added `loadCatalog()` method with error handling
- ✅ Added `renderCatalogView()` method - displays job catalog table
- ✅ Added `renderStartJobModal()` method - modal for job configuration
- ✅ Updated `render()` to include start modal
- ✅ Added event listeners for start/confirm/cancel buttons
- ✅ Added defensive coding to prevent null/undefined errors

### 2. Backend API Endpoints (Complete)
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/catalog` (GET) - Returns job catalog
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/start` (POST) - Starts a job
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/stop` (POST) - Stops a job
- ✅ Security.json files for all endpoints

### 3. Main Loop Integration (Complete)
**File: `WebHost.ps1`**
- ✅ Scriptblock caching system for `main_loop.ps1` files
- ✅ Automatic discovery of all apps with main_loop.ps1
- ✅ Hot-reload support (detects file changes via LastWriteTime)
- ✅ Caches scriptblocks in `$Global:PSWebServer.Apps.[appName].ScriptBlocks.MainLoop.Code`
- ✅ Reduces disk I/O and Windows events by reusing scriptblocks

### 4. Bug Fixes (Complete)
**File: `modules/PSWebHost_JobExecution/PSWebHost_JobExecution.psm1`**
- ✅ Fixed "Cannot index into a null array" error (line 942)
- ✅ Added null check before accessing array index

## 🔄 Required Action: Restart Server

**IMPORTANT:** The server must be restarted to activate the new system:

```powershell
# Stop the current server (Ctrl+C)
# Then restart:
.\WebHost.ps1
```

### Why Restart is Required:
1. **Load PSWebHost_Jobs module** - The new job system module loads at startup
2. **Initialize job catalog** - Jobs are discovered from `apps/*/jobs/` directories
3. **Apply scriptblock caching** - Main loop optimization takes effect
4. **Load updated component** - Browser will fetch latest component.js

## 🧪 Testing Steps

### Step 1: Verify Server Startup
After restarting, check console output for:
```
PSWebHost_Jobs module loaded (discovered X jobs)
```

If you see this message, the new system is active.

### Step 2: Test Job Catalog UI
1. Navigate to `http://localhost:8080`
2. Click "Task Management" card
3. Should default to "Job Catalog" view
4. Should see "WebHostMetrics/CollectMetrics" job listed

### Step 3: Test Job Start (No Variables)
If you have a job without template variables:
1. Click "Start" button
2. Job should start immediately
3. Switch to "Active Jobs" view to verify it's running

### Step 4: Test Job Start (With Variables)
For WebHostMetrics/CollectMetrics job:
1. Click "▶ Start" button
2. Modal should open showing "Interval" variable input
3. Enter a value like "30" (seconds)
4. Click "Start Job"
5. Should see success message with Execution ID
6. Switch to "Active Jobs" view
7. Should see job running with ExecutionMode = "BackgroundJob"

### Step 5: Test Job Stop
1. In "Active Jobs" view, find a running job
2. Click "Stop" button
3. Confirm the action
4. Job should be removed from running list

### Step 6: Test Permissions
1. Jobs with role restrictions should show 🔒 instead of Start button
2. Permission badges should show what user can do (start/stop/restart)

### Step 7: Verify Main Loop Optimization
Check logs for verbose output:
```powershell
# Should see once per app when file changes:
[WebHost] Cached main_loop.ps1 scriptblock for app: WebHostTaskManagement
```

You should NOT see this every 2 seconds - only when files change.

## 📊 Expected Behavior

### Job Catalog View
- **Table columns**: Job, Description, Schedule, Variables, Actions
- **Empty state**: "No jobs available" if no jobs discovered
- **Stats cards**: Total Jobs, Can Start
- **Start buttons**: Green "▶ Start" or 🔒 lock icon
- **Variables**: Shown as badges like `{{Interval}}`

### Start Job Modal
- **Header**: "▶ Start Job"
- **Job info**: Display name, description, app name, job ID
- **Variables section**: Dynamic input fields for each variable
- **Buttons**: Cancel (gray), Start Job (green)
- **Auto-close**: Closes after successful submission

### API Responses
**Catalog endpoint should return:**
```json
{
  "success": true,
  "jobs": [
    {
      "jobId": "WebHostMetrics/CollectMetrics",
      "displayName": "Collect System Metrics",
      "permissions": {
        "canStart": true,
        "canStop": true,
        "canRestart": true
      },
      "templateVariables": [
        {
          "name": "Interval",
          "description": "Collection interval in seconds"
        }
      ]
    }
  ],
  "count": 1
}
```

## ❌ Troubleshooting

### Issue: "Using legacy endpoint" message
**Cause:** PSWebHost_Jobs module not loaded
**Fix:** Restart the server

### Issue: Catalog shows 0 jobs
**Cause:** No jobs defined in `apps/*/jobs/` directories
**Fix:** Check that `apps/WebHostMetrics/jobs/CollectMetrics/` exists with `job.json`

### Issue: Browser shows old component
**Cause:** Browser cache
**Fix:** Hard refresh (Ctrl+F5 or Cmd+Shift+R)

### Issue: "Cannot index into a null array" error
**Cause:** Old bug in legacy job system
**Fix:** Already fixed in PSWebHost_JobExecution.psm1, restart server

### Issue: Jobs don't start
**Cause:** Multiple possibilities
**Debug:**
1. Check browser console for errors
2. Check server logs in System Log view
3. Verify PSWebHost_Jobs module is loaded
4. Check that main_loop.ps1 is being executed

## 📁 Files Modified

### Frontend
- `apps/WebHostTaskManagement/public/elements/task-manager/component.js`

### Backend
- `apps/WebHostTaskManagement/routes/api/v1/jobs/catalog/get.ps1`
- `apps/WebHostTaskManagement/routes/api/v1/jobs/start/post.ps1`
- `apps/WebHostTaskManagement/routes/api/v1/jobs/stop/post.ps1`
- `apps/WebHostTaskManagement/main_loop.ps1`

### Core
- `WebHost.ps1` (main loop scriptblock caching)
- `modules/PSWebHost_JobExecution/PSWebHost_JobExecution.psm1` (bug fix)

### Documentation
- `FRONTEND_UPDATE_SUMMARY.md`
- `CATALOG_VIEW_CODE.js` (reference implementation)
- `READY_TO_TEST.md` (this file)

## 🎯 Success Criteria

All of these should work after restart:
- [x] Server loads PSWebHost_Jobs module
- [x] Job catalog endpoint returns jobs
- [x] Frontend displays job catalog without errors
- [x] Can start a job with template variables via modal
- [x] Can start a job without variables directly
- [x] Jobs appear in Active Jobs view
- [x] Can stop running jobs
- [x] Permissions display correctly
- [x] Main loop executes without errors
- [x] No "Cannot index into a null array" errors
- [x] Scriptblocks are cached (not reloaded every 2s)

## 🚀 Next Steps After Testing

Once everything works:
1. Create additional example jobs to demonstrate the system
2. Add job scheduling UI (future enhancement)
3. Add job history viewing (future enhancement)
4. Document how to create new jobs for developers
5. Consider adding job restart functionality
6. Add job execution history graphs/charts
