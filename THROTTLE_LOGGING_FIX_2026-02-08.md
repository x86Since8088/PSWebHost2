# Request Throttle Logging Fix
**Date**: 2026-02-08
**Issue**: Throttling logic writing too many messages to server logs
**Status**: ✅ FIXED

## Problem

### Before Fix
When a URL was throttled due to errors:
1. **Initial error** (e.g., 500) triggers `recordFailure()` → logged to console only
2. **Every subsequent attempt** to that URL:
   - `isThrottled()` returns true
   - Returns fake 429 response
   - Component calls `onError()`
   - `handleError()` logs to server via `window.logToServer()`
   - **Result**: Hundreds of duplicate 429 errors in server logs

### Log Flood Example
```
2026-02-09T01:26:48 Error main-menu Failed to load menu: HTTP error! status: 429
2026-02-09T01:26:49 Error main-menu Failed to load menu: HTTP error! status: 429
2026-02-09T01:26:50 Error main-menu Failed to load menu: HTTP error! status: 429
... (repeated hundreds of times)
```

**Problem**: Each throttled request attempt logged to server, flooding logs with duplicate entries.

## Solution

### Changes Made

#### 1. Enhanced `recordFailure()` Method
**File**: `public/psweb_spa.js` lines 267-298

**Changes**:
- ✅ Check if URL is **already throttled** before logging
- ✅ Log to server **only once** per throttle period
- ✅ Include **expiry time** in log message
- ✅ Track `logged: true` flag to prevent duplicate logs

**Before**:
```javascript
recordFailure(url, status) {
    this.throttledRequests.set(url, {
        timestamp: Date.now(),
        status
    });
    console.warn(`[RequestThrottle] Throttling ${url} for 60s due to ${status} error`);
}
```

**After**:
```javascript
recordFailure(url, status) {
    // Only log if this is a NEW throttle (not already throttled)
    const alreadyThrottled = this.throttledRequests.has(url);

    const now = Date.now();
    const expiryTime = new Date(now + this.throttleDuration);

    this.throttledRequests.set(url, {
        timestamp: now,
        status,
        logged: !alreadyThrottled
    });

    // Only log once per throttle period
    if (!alreadyThrottled) {
        const expiryTimeStr = expiryTime.toLocaleTimeString();
        console.warn(`[RequestThrottle] Throttling ${url} for 60s due to ${status} error. Expires at ${expiryTimeStr}`);

        // Log to server once with expiry time
        window.logToServer(
            `Request throttled: ${url} (status ${status}) - expires at ${expiryTimeStr}`,
            'RequestThrottle',
            'Warning',
            {
                url: url,
                status: status,
                throttleDurationSeconds: this.throttleDuration / 1000,
                expiryTime: expiryTime.toISOString()
            }
        );
    }
}
```

#### 2. Prevent Duplicate Logging in `handleError()`
**File**: `public/psweb_spa.js` lines 1020-1040

**Changes**:
- ✅ Skip logging for 429 status codes (throttled requests)
- ✅ Throttle already logged once in `recordFailure()`

**Before**:
```javascript
const handleError = (error) => {
    if (error && typeof error === 'object') {
        setErrorInfo({ ... });

        // Log to server (logs EVERY error including 429s)
        window.logToServer(error.message, elementId, 'Error', { ... });
    }
};
```

**After**:
```javascript
const handleError = (error) => {
    if (error && typeof error === 'object') {
        setErrorInfo({ ... });

        // Don't log client-side throttled requests (429) - already logged once
        if (error.status === 429) {
            console.debug(`[Card] Throttled request not logged: ${error.message}`);
            return;
        }

        // Log to server
        window.logToServer(error.message, elementId, 'Error', { ... });
    }
};
```

#### 3. Reduced Console Noise
**File**: `public/psweb_spa.js` line 320

**Changes**:
- ✅ Changed `console.warn` → `console.debug` for throttled attempts
- ✅ Only warnings show once when throttle first applied

**Before**:
```javascript
if (throttleInfo) {
    console.warn(`[RequestThrottle] ${throttleInfo.message}`); // Every attempt!
    return new Response(...);
}
```

**After**:
```javascript
if (throttleInfo) {
    console.debug(`[RequestThrottle] ${throttleInfo.message}`); // Debug level
    return new Response(...);
}
```

## Result

### After Fix

**One log message per throttle**:
```
2026-02-09T01:30:15 Warning RequestThrottle Request throttled: /cards/main-menu (status 500) - expires at 7:31:15 PM
```

That's it! No more flood of duplicate messages.

### Log Entry Format

**Category**: `RequestThrottle`
**Severity**: `Warning`
**Message**: `Request throttled: {url} (status {status}) - expires at {time}`
**Data**:
```json
{
    "url": "/cards/main-menu",
    "status": 500,
    "throttleDurationSeconds": 60,
    "expiryTime": "2026-02-09T01:31:15.123Z"
}
```

## Benefits

✅ **Single log per throttle** - No duplicate flood
✅ **Expiry time included** - Know exactly when throttle lifts
✅ **Server log readable** - Not overwhelmed with 429s
✅ **Console cleaner** - Throttle attempts use debug level
✅ **Better observability** - Can track which URLs are problematic

## Testing

### Before Fix
1. Trigger error on endpoint (e.g., 500 from broken card)
2. Component retries repeatedly
3. **Result**: Hundreds of log entries flooding server logs

### After Fix
1. Trigger error on endpoint
2. Component retries repeatedly
3. **Result**: One single log entry with expiry time

### Verify Fix

**In Browser Console**:
```javascript
// Simulate error
fetch('/cards/test-card').then(r => console.log(r.status)); // Returns 500

// Check throttle
RequestThrottleManager.throttledRequests.get('/cards/test-card');
// Should show: { timestamp: ..., status: 500, logged: true }

// Try again (should be throttled)
fetch('/cards/test-card').then(r => console.log(r.status)); // Returns 429

// Check server logs - should only see ONE log entry for this throttle
```

**Expected Console Output**:
```
[RequestThrottle] Throttling /cards/test-card for 60s due to 500 error. Expires at 7:31:15 PM
[RequestThrottle] Request throttled due to previous 500 error. Retry in 59s.  ← debug level
[RequestThrottle] Request throttled due to previous 500 error. Retry in 58s.  ← debug level
```

**Expected Server Logs** (only one entry):
```
Request throttled: /cards/test-card (status 500) - expires at 7:31:15 PM
```

## Clear Existing Throttles

If you have URLs currently throttled from before this fix:

**Browser Console**:
```javascript
// Clear all throttles
RequestThrottleManager.throttledRequests.clear();
console.log('✓ All throttles cleared');

// Reload page
location.reload();
```

## Files Modified

1. **`public/psweb_spa.js`**:
   - Lines 267-298: `recordFailure()` method
   - Lines 1020-1040: `handleError()` function
   - Line 320: Console logging level

## Summary

**Before**: Hundreds of duplicate 429 errors logged to server
**After**: One log message per throttle with expiry time

The throttling **functionality** remains unchanged - it still prevents hammering broken endpoints. Only the **logging** behavior is fixed to be less noisy and more informative.

---

**Fix Applied**: 2026-02-08 19:35 PST
**Files Modified**: 1 (public/psweb_spa.js)
**Lines Changed**: ~40 lines
