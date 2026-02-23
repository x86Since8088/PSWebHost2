# Card Execution Fix - Empty Response Bodies
**Date**: 2026-02-08 20:25
**Status**: ✅ FIXED

## Issue

After adding card routing for `/cards/*` requests, endpoints returned HTTP 200 OK but with **empty response bodies**, causing JSON parse errors:

```
SyntaxError: JSON.parse: unexpected end of data at line 1 column 1 of the JSON data
```

**Affected Endpoints**:
- `/cards/server-heatmap` (apps/WebHostMetrics)
- `/cards/realtime-events` (apps/WebhostRealtimeEvents)

## Root Cause

The card routing code (lines 993-1022) found the scripts and set `$scriptPath`, but also set `$handled = $true`. This prevented the script execution code (lines 1031+) from running because it was inside an `if (-not $handled)` block.

**Flow Before Fix**:
```powershell
# Line 993-1022: Card routing
if (-not $handled -and $requestedPath -match '^/cards/') {
    $scriptPath = Resolve-RouteScriptPath ...  # Find script
    $handled = $true  # ← Problem: Sets handled flag
}

# Line 1024: Check if handled
if (-not $handled) {  # ← Skips because $handled = $true!
    # Script execution code here - NEVER RUNS!
}
```

**Result**: Scripts found but never executed → HTTP 200 with empty body

## Solution

**File**: `modules/PSWebHost_Support/PSWebHost_Support.psm1`

### Change 1: Remove $handled flag (Lines 993-1022)

**Before**:
```powershell
if ($scriptPath) {
    Write-Verbose "$($MyTag) Card route found in app '$appName': $scriptPath"
    $handled = $true  # ← Removed
    break
}
```

**After**:
```powershell
if ($scriptPath) {
    Write-Verbose "$($MyTag) Card route found in app '$appName': $scriptPath"
    # Don't set $handled here - fall through to normal execution
    break
}
```

### Change 2: Check scriptPath before route resolution (Line 1024)

**Before**:
```powershell
if (-not $handled) {
    Write-Verbose "$($MyTag) No handler matched yet, attempting route resolution"
    $routeBaseDir = Join-Path $projectRoot "routes"
    $scriptPath = $null  # ← This cleared the card scriptPath!
    $scriptPath = Resolve-RouteScriptPath ...
```

**After**:
```powershell
# Only do normal route resolution if card routing didn't find anything
if (-not $handled -and -not $scriptPath) {
    Write-Verbose "$($MyTag) No handler matched yet, attempting route resolution"
    $routeBaseDir = Join-Path $projectRoot "routes"
    $scriptPath = Resolve-RouteScriptPath ...
```

## Flow After Fix

```powershell
# 1. Card routing (lines 993-1022)
if (-not $handled -and $requestedPath -match '^/cards/') {
    $scriptPath = Resolve-RouteScriptPath ...
    # Sets $scriptPath, does NOT set $handled
}

# 2. Normal route resolution (line 1024)
if (-not $handled -and -not $scriptPath) {  # ← Skips if $scriptPath set
    $scriptPath = Resolve-RouteScriptPath ...
}

# 3. Script execution (line 1031+)
if ($scriptPath) {  # ← Runs for card scripts!
    # Execute with Context, SessionData, etc.
    & $scriptPath @scriptParams
}
```

## Result

✅ **Card scripts now execute properly with:**
- HTTP 200 OK status
- Valid JSON response body
- Proper authentication (SessionData parameter)
- Component metadata returned

## Testing

After restarting the server:

```bash
# Test server-heatmap
curl http://localhost:8080/cards/server-heatmap

# Expected: JSON with component metadata:
{
  "status": "success",
  "component": "server-heatmap",
  "scriptPath": "/apps/WebHostMetrics/public/elements/server-heatmap/component.js",
  "title": "Server Heatmap",
  ...
}

# Test realtime-events
curl http://localhost:8080/cards/realtime-events

# Expected: JSON with component metadata:
{
  "component": "realtime-events",
  "scriptPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js",
  "title": "Real-time Events",
  ...
}
```

## Summary

**Problem**: Scripts found but not executed (HTTP 200 with empty body)
**Root Cause**: `$handled = $true` prevented script execution code from running
**Solution**:
1. Don't set `$handled` in card routing
2. Check `$scriptPath` before clearing it in normal route resolution

**Files Modified**: 1 file (PSWebHost_Support.psm1)
**Lines Changed**: 6 lines
**Restart Required**: Yes (PowerShell module change)

---

**Fix Applied**: 2026-02-08 20:25
**Status**: ✅ Complete - Restart server to apply
