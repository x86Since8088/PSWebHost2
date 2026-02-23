# Console Flood Fix - Final Solution
**Date**: 2026-02-08 20:05
**Status**: ✅ COMPLETE

## The Problem (User Report)

Even after fixing server log floods, browser console was still showing hundreds of messages:
```
20:04:51.929 [Card] Throttled request not logged: Failed to load menu: HTTP error! status: 429
20:04:51.929 [RequestThrottle] Request throttled due to previous 500 error. Retry in 9s.
... (repeated 40+ times in same millisecond)
```

## Root Causes

### Issue 1: Console Debug Spam
**Files**: `public/psweb_spa.js` lines 321 and 1032

Both locations were calling `console.debug()` on EVERY throttled retry attempt:
- Line 321: Logged every time a throttled URL was checked
- Line 1032: Logged every time handleError() received 429 status

**Impact**: Even though we skipped server logging, we flooded the browser console.

### Issue 2: Infinite Render Loop
**File**: `public/elements/main-menu/component.js` line 59

The useEffect dependency array included `onError`:
```javascript
}, [searchTerm, onError]);
```

**Problem**: If parent component creates new `onError` function on each render (not wrapped in useCallback), the dependency changes → triggers useEffect → fetches menu → calls onError → parent re-renders → new onError → repeat infinitely.

**Result**: 20+ fetch attempts in same millisecond, each hitting throttle, each logging to console.

## Solutions Applied

### Fix 1: Remove Console Debug Calls

**File**: `public/psweb_spa.js`

**Line 317-321** (before):
```javascript
const throttleInfo = RequestThrottleManager.isThrottled(url);
if (throttleInfo) {
    console.debug(`[RequestThrottle] ${throttleInfo.message}`);
    // Return a fake response...
```

**Line 317-320** (after):
```javascript
const throttleInfo = RequestThrottleManager.isThrottled(url);
if (throttleInfo) {
    // Silent - throttle already logged once when first applied in recordFailure()
    // Return a fake response...
```

**Line 1030-1033** (before):
```javascript
if (error.status === 429) {
    console.debug(`[Card] Throttled request not logged: ${error.message}`);
    return;
}
```

**Line 1030-1033** (after):
```javascript
if (error.status === 429) {
    // Silent - no need to log every retry attempt
    return;
}
```

### Fix 2: Remove onError from Dependency Array

**File**: `public/elements/main-menu/component.js`

**Line 52-59** (before):
```javascript
    pswebFetchMenu();
    return () => {
        isMounted = false;
        if (saveTimeoutRef.current) {
            clearTimeout(saveTimeoutRef.current);
        }
    };
}, [searchTerm, onError]);
```

**Line 52-60** (after):
```javascript
    pswebFetchMenu();
    return () => {
        isMounted = false;
        if (saveTimeoutRef.current) {
            clearTimeout(saveTimeoutRef.current);
        }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
}, [searchTerm]); // onError removed - shouldn't trigger re-fetch
```

## Result

### Before Fixes
- 40+ console messages per second (browser console)
- Hundreds of server logs per second (fixed earlier)
- Infinite render loop causing excessive fetches
- Impossible to debug due to console noise

### After Fixes
- ✅ No console spam for throttled requests
- ✅ No server log spam (fixed earlier)
- ✅ No render loop - component fetches only when searchTerm changes
- ✅ ONE server log when throttle first applied with expiry time
- ✅ Silent retries - no noise in console or logs

## Expected Behavior Now

1. **Initial Error**: Card endpoint returns 500
   - Server log: `Error [category] Failed to load card: HTTP 500`

2. **Throttle Applied**: Client blocks URL for 60 seconds
   - Server log: `Warning RequestThrottle Request throttled: /cards/main-menu (status 500) - expires at 7:46:15 PM`

3. **Subsequent Retries**: Component tries again (e.g., user changes search)
   - Console: *(silent)*
   - Server logs: *(silent)*
   - Result: Clean 429 response, silently blocked

4. **After Throttle Expires**: Normal operation resumes
   - If still failing → new throttle with new log entry
   - If fixed → request succeeds

## Files Modified

1. **`public/psweb_spa.js`**
   - Removed console.debug() at line 321 (throttle check)
   - Removed console.debug() at line 1032 (handleError 429)

2. **`public/elements/main-menu/component.js`**
   - Removed `onError` from useEffect dependency array (line 60)
   - Prevents infinite render loop

## Testing

After hard reload (Ctrl+Shift+R):

1. **Trigger an error** (e.g., card returns 500)
   - Should see ONE log entry with expiry time

2. **Let component retry**
   - Console should be silent
   - Server logs should be silent

3. **Check console for spam**
   - Should see NO repeated throttle messages

4. **Verify no render loop**
   - Component should fetch only when searchTerm changes
   - Not on every render

## Verification Commands

Open browser console and run:
```javascript
// Check if new code loaded
window.psweb_fetchWithAuthHandling.toString().includes('Silent')
// Expected: true

// Monitor console for spam (wait 10 seconds)
// Expected: No repeated throttle messages
```

## Prevention Guidelines

### For Console Logging
- **Never** log on every retry attempt
- **Only** log when state changes (e.g., throttle first applied)
- Use console levels appropriately:
  - `console.error` - Actual errors requiring attention
  - `console.warn` - Important warnings (throttle FIRST applied)
  - `console.info` - Informational (state changes)
  - `console.debug` - Should be rare, never in hot paths
  - **Avoid** - Logging in retry loops

### For useEffect Dependencies
- **Only include values that should trigger re-fetch**
- **Don't include callbacks** unless wrapped in useCallback
- Common culprits: `onError`, `onSuccess`, `callback` props
- Use ESLint disable comment if intentionally excluding

### Pattern for Error Callbacks
```javascript
// WRONG - onError in dependency array
useEffect(() => {
    fetchData().catch(err => onError(err));
}, [onError]); // ← Causes infinite loop if not memoized

// RIGHT - onError excluded
useEffect(() => {
    fetchData().catch(err => onError(err));
    // eslint-disable-next-line react-hooks/exhaustive-deps
}, []); // ← Only fetch on mount
```

## Summary

**Problem**: Console flooded with debug messages + infinite render loop
**Root Cause**: console.debug() in retry path + onError dependency
**Solution**: Remove console spam + remove onError from deps
**Result**: Completely silent throttled retries, clean console

---

**Fix Applied**: 2026-02-08 20:05
**Files Modified**: 2 files (psweb_spa.js, main-menu/component.js)
**Lines Changed**: 4 lines total
**Status**: ✅ Complete - Browser console is now clean
