# Server Restart Instructions - Module Cache Issue
**Date**: 2026-02-08 20:35
**Issue**: PowerShell module changes not loaded after "restart"

## Problem

The PowerShell process (PID 8968) is still running from before the module changes. Even though `Import-Module -Force` is used, if the PowerShell session wasn't fully terminated, it may still have cached module state.

## Solution

### Step 1: Kill All PowerShell Processes
```powershell
# Stop the server process
Stop-Process -Id 8968 -Force

# Or kill all pwsh processes (WARNING: This kills ALL PowerShell sessions)
Get-Process pwsh | Stop-Process -Force
```

### Step 2: Verify Port is Free
```powershell
# Check if port 8080 is released
netstat -ano | findstr ":8080"

# Should return nothing after a few seconds
```

### Step 3: Start Fresh Server
```powershell
# Navigate to project root
cd C:\SC\PsWebHost

# Start with verbose logging to see routing
.\WebHost.ps1 -Verbose
```

### Step 4: Verify Module Loaded
After server starts, check the logs for:
```
[Init-TrackedModule] Tracked module PSWebHost_Support from C:\SC\PsWebHost\modules\PSWebHost_Support
```

And when a request comes in, you should see verbose output like:
```
[Process-HttpRequest] Card route request: /cards/server-heatmap
[Resolve-RouteScriptPath] Checking for route script: C:\SC\PsWebHost\apps\WebHostMetrics\routes\cards\server-heatmap\get.ps1
[Resolve-RouteScriptPath] Route script found: C:\SC\PsWebHost\apps\WebHostMetrics\routes\cards\server-heatmap\get.ps1
```

## Alternative: Use -Resume to Reload Modules

If you want to keep the session alive but reload modules:

```powershell
# In the WebHost console, press Ctrl+C to stop the listener
# Then restart with:
.\WebHost.ps1 -Resume
```

But this might not pick up module changes reliably. **Full restart is recommended.**

## Verification

After restart, test the endpoints:

```bash
# Test main-menu
curl http://localhost:8080/cards/main-menu
# Expected: HTTP 200 with JSON menu data

# Test server-heatmap
curl http://localhost:8080/cards/server-heatmap
# Expected: HTTP 200 with component metadata JSON

# Test realtime-events
curl http://localhost:8080/cards/realtime-events
# Expected: HTTP 200 with component metadata JSON
```

All should return **200 OK with JSON** (not 404).

## Why This Happened

1. Module changes made to `PSWebHost_Support.psm1`
2. User "restarted" server but process stayed alive (PID 8968)
3. PowerShell kept cached module version in memory
4. New routing code never loaded
5. Result: 404 for all `/cards/*` endpoints

## Summary

**Problem**: Old module cached in running PowerShell process
**Solution**: Kill process, start fresh
**Command**: `Stop-Process -Id 8968 -Force; .\WebHost.ps1 -Verbose`

---

**Created**: 2026-02-08 20:35
**Status**: Waiting for full process restart
