# Metrics Endpoint Path Fixes

**Date:** 2026-02-01
**Issue:** Components referencing incorrect metrics API paths causing 404 errors

---

## Problem

Components were calling metrics endpoints at root-level paths (`/api/v1/metrics/*`) but the actual endpoints are app-specific at `/apps/WebHostMetrics/api/v1/metrics/*`.

This caused continuous 404 errors in server logs every 5 seconds from polling operations.

---

## Root Cause

When the WebHostMetrics app was created, it placed its API routes under the app-specific path structure:
- `/apps/WebHostMetrics/api/v1/metrics`
- `/apps/WebHostMetrics/api/v1/metrics/history`

However, older components that were built before the app system still referenced the old root-level paths:
- `/api/v1/metrics` ❌
- `/api/v1/metrics/history` ❌

---

## Files Fixed

### 1. public/elements/uplot/component.js

#### Fix 1: Historical Data Endpoint (Lines 198, 204, 222)

**Changed:**
```javascript
// OLD: Root-level path
const historyUrl = new URL('/api/v1/metrics/history', window.location.origin);
console.log(`[uPlot DEBUG] 📥 /api/v1/metrics/history response: ${totalRecords}...`);

// NEW: App-specific path
const historyUrl = new URL('/apps/WebHostMetrics/api/v1/metrics/history', window.location.origin);
console.log(`[uPlot DEBUG] 📥 /apps/WebHostMetrics/api/v1/metrics/history response: ${totalRecords}...`);
```

**Impact:** Fixed initial data loading for uPlot charts

---

#### Fix 2: Real-time Incremental Data Endpoint (Lines 245, 251, 275)

**Changed:**
```javascript
// OLD: Root-level path
// Fetch incremental data from /api/v1/metrics (CSV files, called every 5 seconds)
const incrementalUrl = new URL('/api/v1/metrics', window.location.origin);
console.log(`[uPlot DEBUG] 📊 Incremental fetch #${incrementalFetchCountRef.current} from /api/v1/metrics: ${totalRecords} CSV records`);

// NEW: App-specific path
// Fetch incremental data from /apps/WebHostMetrics/api/v1/metrics (CSV files, called every 5 seconds)
const incrementalUrl = new URL('/apps/WebHostMetrics/api/v1/metrics', window.location.origin);
console.log(`[uPlot DEBUG] 📊 Incremental fetch #${incrementalFetchCountRef.current} from /apps/WebHostMetrics/api/v1/metrics: ${totalRecords} CSV records`);
```

**Impact:**
- Fixed continuous 404 errors (every 5 seconds)
- Restored real-time metrics updates in uPlot charts

---

### 2. public/elements/server-heatmap/component.js

#### Fix: Embedded uPlot URL Source Parameter (Line 417)

**Changed:**
```javascript
// OLD: Root-level path in URL parameter
url: `/api/v1/ui/elements/uplot?source=/api/v1/metrics/history&metric=cpu&timerange=${timeRange}...`

// NEW: App-specific path in URL parameter
url: `/api/v1/ui/elements/uplot?source=/apps/WebHostMetrics/api/v1/metrics/history&metric=cpu&timerange=${timeRange}...`
```

**Impact:** Fixed historical data source for heatmap visualization

---

## Server Log Impact

### Before Fix:
```
2026-02-02T05:20:19Z  Info  Routing  404 Not Found: /api/v1/metrics from 127.0.0.1
2026-02-02T05:20:24Z  Info  Routing  404 Not Found: /api/v1/metrics from 127.0.0.1
2026-02-02T05:20:29Z  Info  Routing  404 Not Found: /api/v1/metrics from 127.0.0.1
... (repeating every 5 seconds)
```

### After Fix:
- No more 404 errors for `/api/v1/metrics`
- Real-time metrics polling works correctly
- Charts receive live data updates

---

## Related Architecture

### App-Specific Routing Structure

PSWebHost uses an app-based routing system where apps can define their own API endpoints:

```
apps/
  WebHostMetrics/
    routes/
      api/
        v1/
          metrics/
            get.ps1          → /apps/WebHostMetrics/api/v1/metrics
          metrics/
            history/
              get.ps1        → /apps/WebHostMetrics/api/v1/metrics/history
```

**Convention:**
- App routes: `/apps/[AppName]/api/[version]/[resource]`
- Global routes: `/api/[version]/[resource]`

Apps should always use their own app-prefixed paths to avoid conflicts with global routes.

---

## Testing

### Verify Fix:
1. Open browser with uPlot chart or server heatmap
2. Open browser DevTools Network tab
3. Confirm requests to `/apps/WebHostMetrics/api/v1/metrics` return 200 OK
4. Check server logs for absence of 404 errors
5. Verify charts update with real-time data every 5 seconds

### Expected Behavior:
- ✅ No 404 errors in server logs
- ✅ uPlot charts show real-time updates
- ✅ Server heatmap displays historical data
- ✅ Polling occurs every 5 seconds without errors

---

## Additional Components to Check

The following components may also need review for similar issues:

**Metrics Consumers:**
- `public/lib/metrics-manager.js` - ✅ Already correct (uses `/apps/WebHostMetrics/api/v1/metrics`)
- `public/lib/metrics-fetcher.js` - Should be checked
- `public/lib/metrics-database.js` - Should be checked

**Other Charts:**
- `apps/UI_Uplot/*` chart components - May have similar hardcoded paths

---

## Prevention

**For Future Development:**

1. **Never hardcode root-level API paths** in app components
2. **Use relative paths** or make endpoints configurable
3. **Check route definitions** before referencing endpoints
4. **Use app-prefixed paths** for all app-specific resources
5. **Document endpoint locations** in app READMEs

**Example - Configurable Endpoint:**
```javascript
// Good: Configurable
const metricsEndpoint = config.metricsEndpoint || '/apps/WebHostMetrics/api/v1/metrics';

// Bad: Hardcoded
const metricsEndpoint = '/api/v1/metrics';
```

---

## Related Fixes

This fix is related to:
- **Layout Parameter Fix** (2026-02-01) - Fixed card loading from URL parameters
- **Source Map Cleanup** (2026-02-01) - Removed missing source map references
- **Console Log Migration** (2026-02-01) - Migrated to centralized logging

---

## End of Report
