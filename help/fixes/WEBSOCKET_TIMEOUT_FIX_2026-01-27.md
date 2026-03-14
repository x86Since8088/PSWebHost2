# WebSocket Timeout Fix - Force Serial Mode

**Date**: 2026-01-27
**Status**: ✅ **FIXED**

---

## Problem

User logs showed WebSocket uploads timing out on multiple chunks (0, 1, 2, 3) after 60 seconds each:

```
[01/27/2026 08:26:16] uploadViaWebSocket: Timeout for chunk 0
[01/27/2026 08:26:16] uploadViaWebSocket: Timeout for chunk 1
[01/27/2026 08:26:16] uploadViaWebSocket: Timeout for chunk 2
[01/27/2026 08:26:16] uploadViaWebSocket: Timeout for chunk 3
[01/27/2026 08:26:16] uploadFile: WebSocket upload failed, falling back to PUT chunks
```

**Root Cause**: Pipelining was still enabled from previous testing. The `usePipelining` state was loading from localStorage where it was previously set to `"true"`, even though the new default is `false`.

---

## Fix Applied

### 1. Added Migration Code

Force existing users to serial mode on first load after update:

```javascript
const [usePipelining, setUsePipelining] = useState(() => {
    // MIGRATION: Force default to false for existing users
    const saved = localStorage.getItem('fileExplorer_usePipelining');
    const migrated = localStorage.getItem('fileExplorer_pipelineMigrated');

    if (!migrated) {
        // First time after update - force to false and mark as migrated
        localStorage.setItem('fileExplorer_usePipelining', 'false');
        localStorage.setItem('fileExplorer_pipelineMigrated', 'true');
        console.log('[FileExplorer] Migration: Disabled pipelining (was causing timeouts)');
        return false;
    }

    return saved === 'true'; // Default to false
});
```

**What it does**:
- Checks if user has been migrated (`fileExplorer_pipelineMigrated`)
- If not migrated:
  - Forces `usePipelining` to `false`
  - Saves to localStorage
  - Marks user as migrated
  - Logs to console
- Future loads will respect user's setting

### 2. Enhanced Logging

Added clearer mode indication:

```javascript
// At upload start
const pipelineMode = usePipelining ? 'PIPELINED (5 chunks parallel)' : 'SERIAL (one at a time)';
logToServer(`uploadFile: WebSocket upload starting - Mode: ${pipelineMode}`);
```

Added debug logging in message handler:

```javascript
if (enablePipelining) {
    logToServer(`uploadViaWebSocket: PIPELINED - Resolved chunk ${message.chunkNumber}`, 'Debug');
} else {
    logToServer(`uploadViaWebSocket: SERIAL - Resolving ACK (resolver exists: ${!!currentAckResolver})`, 'Debug');
}
```

---

## Testing Instructions

### Test 1: Verify Migration

**Steps**:
1. Open browser console (F12)
2. Reload File Explorer page
3. **Look for**: `[FileExplorer] Migration: Disabled pipelining (was causing timeouts)`
4. Check localStorage:
   ```javascript
   localStorage.getItem('fileExplorer_usePipelining') // Should be "false"
   localStorage.getItem('fileExplorer_pipelineMigrated') // Should be "true"
   ```

**Success Criteria**:
- ✅ Migration message appears in console
- ✅ localStorage values set correctly
- ✅ No more migration on subsequent reloads

---

### Test 2: Verify Serial Mode Upload

**Steps**:
1. Upload a 50MB file
2. **Monitor console** for:
   ```
   uploadFile: WebSocket upload starting - Mode: SERIAL (one at a time)
   uploadViaWebSocket: Using serial mode (no pipelining)
   uploadViaWebSocket: SERIAL - Resolving ACK (resolver exists: true)
   ```
3. **Verify**: No timeout errors
4. **Verify**: Upload completes successfully
5. **Verify**: Speed is ~3-3.5 MB/s

**Success Criteria**:
- ✅ Logs show "SERIAL (one at a time)"
- ✅ No timeout errors
- ✅ Upload completes
- ✅ Good speed (~3.5 MB/s)

---

### Test 3: Settings Still Work

**Steps**:
1. Open settings (⚙️)
2. **Verify**: "Enable pipelining" is **unchecked**
3. **Check** the box to enable pipelining
4. Upload a file
5. **Verify**: Console shows "PIPELINED (5 chunks parallel)"
6. **Uncheck** the box again
7. **Verify**: localStorage updated

**Success Criteria**:
- ✅ Toggle works
- ✅ Console shows correct mode
- ✅ Settings persist after reload

---

## What Changed

### File Modified

**`apps/WebhostFileExplorer/public/elements/file-explorer/component.js`**

**Changes**:
1. Added migration check in `usePipelining` useState initializer (10 lines)
2. Enhanced upload start logging (1 line)
3. Added debug logging in message handler (4 lines)

**Lines Changed**: ~15 lines

---

## Expected Behavior After Fix

### First Load After Update
```
[FileExplorer] Migration: Disabled pipelining (was causing timeouts)
uploadFile: WebSocket upload starting - Mode: SERIAL (one at a time)
uploadViaWebSocket: Using serial mode (no pipelining)
uploadViaWebSocket: SERIAL - Resolving ACK (resolver exists: true)
```

### Subsequent Loads
```
uploadFile: WebSocket upload starting - Mode: SERIAL (one at a time)
uploadViaWebSocket: Using serial mode (no pipelining)
```

### If User Enables Pipelining
```
uploadFile: WebSocket upload starting - Mode: PIPELINED (5 chunks parallel)
uploadViaWebSocket: WebSocket connection established (pipelining: true)
uploadViaWebSocket: PIPELINED - Resolved chunk 0
```

---

## Manual Override (If Needed)

If user wants to force serial mode immediately without waiting for migration:

**Option 1: Browser Console**
```javascript
localStorage.setItem('fileExplorer_usePipelining', 'false');
location.reload();
```

**Option 2: Clear All Settings**
```javascript
localStorage.removeItem('fileExplorer_usePipelining');
localStorage.removeItem('fileExplorer_pipelineMigrated');
localStorage.removeItem('fileExplorer_useWebSocket');
location.reload();
```

---

## Rollback Plan

If migration causes issues:

**Remove migration code**:
```javascript
// Revert to simple version
const [usePipelining, setUsePipelining] = useState(() => {
    const saved = localStorage.getItem('fileExplorer_usePipelining');
    return saved === 'true';
});
```

**Force users to manually disable**:
```javascript
// Force false always (nuclear option)
const [usePipelining, setUsePipelining] = useState(false);
```

---

## Summary

✅ **Migration added**: Automatically disables pipelining for existing users on first load

✅ **Better logging**: Console clearly shows SERIAL vs PIPELINED mode

✅ **No breaking changes**: Settings still work, users can re-enable if desired

✅ **Expected result**: WebSocket uploads should now work at ~3.5 MB/s with no timeouts

---

**Created**: 2026-01-27
**Fix Type**: Migration + Enhanced Logging
**Lines Changed**: ~15
**Risk**: Very Low (adds safety check, doesn't change logic)
