# Complete Error Handling Fix - All Components
**Date**: 2026-02-08
**Status**: ✅ COMPLETE

## Summary

Fixed critical error handling bug across **8 locations in 6 components** that was causing throttle logging floods. All components now properly preserve `response.status` on error objects.

## Root Cause

JavaScript `Error` objects don't automatically include custom properties. When components threw errors like:

```javascript
throw new Error(`HTTP error! status: ${response.status}`);
```

The error object had `undefined` status property, causing:
1. Throttle detection to fail (`error.status === 429` check failed)
2. Every throttled retry to be logged to server
3. Hundreds of duplicate log messages per second

## Files Fixed

### 1. `public/elements/main-menu/component.js` (Line 34-39)
**Before**:
```javascript
if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`HTTP error! status: ${response.status}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 2. `public/elements/help-viewer/component.js` (Line 38-43)
**Before**:
```javascript
if (!response.ok) {
    throw new Error(`Failed to load help file: ${response.status} ${response.statusText}`);
}
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`Failed to load help file: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 3. `public/elements/markdown-viewer/component.js` (Lines 60-65, 271-276)
**Two locations fixed** - both GET (line 60) and POST (line 271) operations

**Before** (GET):
```javascript
if (!response.ok) {
    throw new Error(`Failed to load file: ${response.status} ${response.statusText}`);
}
```

**Before** (POST):
```javascript
if (!response.ok) {
    throw new Error(`Failed to save: ${response.status} ${response.statusText}`);
}
```

**After** (both locations):
```javascript
if (!response.ok) {
    const error = new Error(`Failed to load/save: ${response.status} ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 4. `public/elements/chartjs/component.js` (Line 172-177)
**Before**:
```javascript
if (!response.ok) {
    throw new Error(`Data source returned ${response.status}`);
}
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`Data source returned ${response.status}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 5. `public/elements/apps-manager/component.js` (Line 19-24)
**Before**:
```javascript
if (!response.ok) {
    throw new Error(`Failed to load apps: ${response.statusText}`);
}
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`Failed to load apps: ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 6. `public/elements/memory-explorer/component.js` (Line 306-311)
**Before**:
```javascript
if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
}
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`HTTP ${response.status}: ${response.statusText}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 7. `public/elements/uplot/component.js` (Line 209-214)
**Before**:
```javascript
if (!response.ok) throw new Error(`History endpoint returned ${response.status}`);
```

**After**:
```javascript
if (!response.ok) {
    const error = new Error(`History endpoint returned ${response.status}`);
    error.status = response.status;
    error.statusText = response.statusText;
    throw error;
}
```

### 8. `public/elements/admin/users-management/component.js` (Line 20-26)
**Before**:
```javascript
.then(response => {
    if (!response.ok) {
        throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }
    return response.json();
```

**After**:
```javascript
.then(response => {
    if (!response.ok) {
        const error = new Error(`HTTP ${response.status}: ${response.statusText}`);
        error.status = response.status;
        error.statusText = response.statusText;
        throw error;
    }
    return response.json();
```

## Related Fixes (Already Applied)

### `public/psweb_spa.js`

**Line 267-298** - Enhanced `recordFailure()`:
- Only logs once per throttle with expiry time
- Tracks if already throttled with `logged` flag
- Includes expiry time in log message

**Line 1030-1034** - Enhanced `handleError()`:
- Skips logging for 429 status codes
- Prevents duplicate throttle logs

**Line 320** - Reduced console noise:
- Changed `console.warn` to `console.debug` for repeated throttle attempts

## Impact

**Before Fix**:
- Any component error could trigger hundreds of logs per second
- Throttled requests (429) were logged repeatedly
- Server logs flooded, difficult to find actual issues

**After Fix**:
- Each throttle logs exactly ONCE with clear expiry time
- Error status properly tracked through error chain
- Clean, actionable server logs

## Testing

To verify fix is working:

1. **Clear browser cache**: Navigate to `/clear-all-throttle-data.html`
2. **Hard reload**: Ctrl+Shift+R to load fresh JavaScript
3. **Trigger error**: Open any card that returns 500 error
4. **Check logs**: Should see ONE throttle log with expiry time:
   ```
   Warning RequestThrottle Request throttled: /cards/xxx (status 500) - expires at 7:45:30 PM
   ```

## Prevention Guidelines

### For New Components

Always preserve response properties when throwing errors:

```javascript
try {
    const response = await fetch(url);
    if (!response.ok) {
        // REQUIRED: Attach status properties before throwing
        const error = new Error(`HTTP ${response.status}`);
        error.status = response.status;
        error.statusText = response.statusText;
        throw error;
    }
} catch (error) {
    // Status will be available here
    onError({ status: error.status });
}
```

### For Error Handlers

Skip logging for expected client-side responses:

```javascript
const handleError = (error) => {
    // Skip logging for client-side managed responses
    if ([429, 401, 304].includes(error.status)) {
        console.debug(`Skipping server log for ${error.status}`);
        return;
    }

    // Log actual errors
    window.logToServer(error.message, 'Error', { status: error.status });
};
```

## Verification Checklist

- [x] Fixed all 8 error throw locations
- [x] Verified server logs show no 429 floods
- [x] Enhanced recordFailure() to log once with expiry
- [x] Enhanced handleError() to skip 429 logging
- [x] Created clear-all-throttle-data.html helper
- [x] Created test_throttle_fix.html test page
- [x] Updated documentation

## Result

✅ **From hundreds of logs per second → one per throttle**

All components now properly preserve error status, enabling correct throttle detection and preventing log floods.

---

**Fix Completed**: 2026-02-08
**Components Fixed**: 6 files, 8 locations
**Core Files**: 2 files (psweb_spa.js, main-menu/component.js)
**Total Files Modified**: 8 files
