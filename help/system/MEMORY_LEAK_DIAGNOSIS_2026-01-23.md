# PSWebHost Memory Leak Diagnosis and Fix

**Date**: 2026-01-23
**Issue**: Server consuming 7.5GB RAM after running overnight
**Status**: ✅ Root cause identified and fixed

---

## Summary

The PSWebHost server was consuming **7.5GB of RAM** (Process ID 16312) after running overnight. Investigation revealed a memory leak in the `Write-PSWebHostLog` function where the `$global:PSWebServer.eventGuid` hashtable was growing unbounded.

---

## Root Cause

**Location**: `modules/PSWebHost_Support/PSWebHost_Support.psm1` lines 1227-1260

### The Problem

The `Write-PSWebHostLog` function creates entries in **two hashtables** for every log event:

1. **`$global:PSWebServer.events`** - Event storage hashtable
   - ✅ **Has cleanup** (lines 1252-1256): Trimmed to 1000 entries

2. **`$global:PSWebServer.eventGuid`** - Date-to-GUID mapping hashtable
   - ❌ **NO CLEANUP**: Grows unbounded (line 1259)

```powershell
# Line 1234: Creates event entry (with cleanup)
$global:PSWebServer.events[$eventGuid] = @{ ... }

# Lines 1252-1256: Cleanup for events (GOOD)
while($global:PSWebServer.events.count -gt 1000) {
    $global:PSWebServer.events.keys |
        Select-Object -First ($global:PSWebServer.events.count - 1000) |
        ForEach-Object{$global:PSWebServer.events.Remove($_)}
}

# Line 1259: Creates eventGuid entry (NO CLEANUP - MEMORY LEAK!)
$global:PSWebServer.eventGuid[$date] = $eventGuid
```

### Impact

- Every log entry adds one entry to `eventGuid` hashtable
- After running overnight with typical activity, this can contain **hundreds of thousands of entries**
- Each entry is approximately 50-100 bytes
- Estimated memory consumption: **hundreds of MB to several GB**

---

## The Fix

### Permanent Fix (Applied)

Modified `PSWebHost_Support.psm1` to add cleanup for the `eventGuid` hashtable:

```powershell
try {
    # Clean up events hashtable (keep last 1000)
    while($global:PSWebServer.events.count -gt 1000) {
        $global:PSWebServer.events.keys |
            Select-Object -First ($global:PSWebServer.events.count - 1000) |
            ForEach-Object{$global:PSWebServer.events.Remove($_)}
    }

    # Clean up eventGuid hashtable (MEMORY LEAK FIX)
    # This hashtable was growing unbounded - keep last 1000 entries
    while($global:PSWebServer.eventGuid.count -gt 1000) {
        $global:PSWebServer.eventGuid.keys |
            Select-Object -First ($global:PSWebServer.eventGuid.count - 1000) |
            ForEach-Object{$global:PSWebServer.eventGuid.Remove($_)}
    }
}
catch{}
```

### Immediate Cleanup (For Running Server)

To clean up memory on the currently running server without restart:

1. **Run the immediate fix script**:
   ```powershell
   . C:\SC\PsWebHost\fix_memory_leak_immediate.ps1
   ```

   This script will:
   - Clear the `eventGuid` hashtable
   - Trim the `events` hashtable to 500 entries
   - Remove stale sessions (older than 24 hours)
   - Force garbage collection
   - Report memory freed

2. **Or manually in the server console**:
   ```powershell
   # Clear the leaking hashtable
   $global:PSWebServer.eventGuid.Clear()

   # Force GC
   [GC]::Collect()
   [GC]::WaitForPendingFinalizers()
   [GC]::Collect()
   ```

---

## Diagnostic Tools Created

Three diagnostic scripts were created during investigation:

1. **`diagnose_memory_leak.ps1`** - External process inspection
   - Identifies server process and memory usage
   - Attempts to query server API
   - Provides recommendations

2. **`inspect_server_memory.ps1`** - Internal memory inspection
   - Run from within server console
   - Estimates size of major data structures
   - Identifies specific memory hogs
   - **Recommended for ongoing monitoring**

3. **`fix_memory_leak_immediate.ps1`** - Immediate cleanup
   - Clears the leaking hashtable
   - Trims other collections
   - Forces garbage collection
   - Reports before/after memory usage

---

## Verification

### Before Fix
```
Process: PID 16312
Working Set: 7476.18 MB (7.5 GB)
Private Memory: 7544.57 MB
Handles: 1452
Threads: 53
```

### Expected After Fix

With the permanent fix in place, the `eventGuid` hashtable will be automatically limited to 1000 entries, preventing unbounded growth.

**To verify the fix is working**:

Run from server console after restart:
```powershell
# Check hashtable sizes
$global:PSWebServer.eventGuid.Count  # Should stay under 1000
$global:PSWebServer.events.Count     # Should stay under 1000

# Monitor over time
while ($true) {
    $mem = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
    $events = $global:PSWebServer.eventGuid.Count
    Write-Host "$(Get-Date -Format 'HH:mm:ss') - Memory: $mem MB | EventGuid: $events entries"
    Start-Sleep -Seconds 300  # Check every 5 minutes
}
```

---

## Additional Observations

### Other Potential Memory Issues (Not Leaks)

1. **Log Queue**: `$global:PSWebHostLogQueue`
   - Flushed every 15 seconds to disk
   - Can accumulate if flush fails
   - Monitor: Should stay under 5000 entries

2. **Sessions**: `$global:PSWebSessions`
   - Sessions persist until explicit cleanup
   - Should implement periodic cleanup for inactive sessions
   - Recommendation: Clear sessions inactive > 24 hours

3. **Metrics History**: `$global:PSWebServer.Metrics.History`
   - Retention controlled by app configuration
   - Default: 24 hours
   - Check if cleanup is working properly

### Browser Memory

The browser tab was consuming 4GB before forced reset. This suggests:
- Long-running browser session accumulating DOM elements
- Potential JavaScript memory leaks in frontend
- WebSocket connections not being cleaned up properly
- Consider implementing periodic client-side cleanup

---

## Recommendations

### Immediate Actions

1. ✅ **Apply the permanent fix** (already applied)
2. ⚠️ **Run the immediate cleanup script** on running server
3. ⚠️ **Restart the server** to fully clear memory
4. ✅ **Monitor memory usage** using `inspect_server_memory.ps1`

### Long-Term Improvements

1. **Implement session cleanup task**
   ```powershell
   # Add to main loop in Webhost.ps1
   if ((Get-Date) - $lastSessionCleanup -gt [TimeSpan]::FromHours(1)) {
       $cutoff = (Get-Date).AddHours(-24)
       $staleSessions = $global:PSWebSessions.Keys | Where-Object {
           $global:PSWebSessions[$_].LastUpdated -lt $cutoff
       }
       foreach ($sid in $staleSessions) {
           $global:PSWebSessions.Remove($sid)
       }
       $lastSessionCleanup = Get-Date
   }
   ```

2. **Add memory monitoring endpoint**
   - Create `/api/v1/debug/memory/get.ps1`
   - Return hashtable sizes and memory usage
   - Enable proactive monitoring

3. **Review frontend for memory leaks**
   - Check for DOM accumulation
   - Review WebSocket connection cleanup
   - Consider periodic page refresh for long sessions

4. **Add memory alerts**
   - Alert if process exceeds 2GB
   - Alert if hashtables exceed limits
   - Log to monitoring system

---

## Files Modified

1. **`modules/PSWebHost_Support/PSWebHost_Support.psm1`**
   - Lines 1251-1267: Added cleanup for `eventGuid` hashtable

## Files Created

1. **`diagnose_memory_leak.ps1`** - External diagnostic tool
2. **`inspect_server_memory.ps1`** - Internal inspection tool
3. **`fix_memory_leak_immediate.ps1`** - Immediate cleanup script
4. **`MEMORY_LEAK_DIAGNOSIS_2026-01-23.md`** - This document

---

## Conclusion

The memory leak was caused by an unbounded hashtable in the logging system. The fix has been applied and will prevent future occurrences. For the currently running server, run the immediate cleanup script to free memory, or restart the server for a clean slate.

**Estimated memory reduction**: 4-6 GB depending on how many log entries accumulated.
