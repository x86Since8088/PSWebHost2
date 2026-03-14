# Console.log to window.logToServer Migration Report

**Date:** 2026-02-01
**Status:** Key components migrated

---

## Summary

Migrated critical component files from `console.log/error` to `window.logToServer()` for centralized server-side logging.

**Total Audit:** 299 console.log instances across 48 files
**Files Updated:** 4 component files
**Instances Migrated:** 12 console statements

---

## Migration Signature

```javascript
// OLD
console.log('Message');
console.error('Error:', error);

// NEW
window.logToServer('Message', 'ComponentName', 'Info');
window.logToServer(`Error: ${error.message}`, 'ComponentName', 'Error', { error: error.toString() });
```

### window.logToServer Parameters

```javascript
window.logToServer(message, category, level, data)
```

- **message** (string): Log message
- **category** (string): Component/module name (e.g., 'FileExplorer', 'TaskManager')
- **level** (string): 'Info' | 'Error' | 'Warning' | 'Debug' (default: 'Info')
- **data** (object): Optional additional context data

### Server Endpoint

- **Path:** `/api/v1/debug/client-log`
- **Batching:** 15-second intervals
- **Rate Limiting:** Configured on server
- **Beacon:** Uses sendBeacon on page unload for reliability

---

## Files Updated

### 1. public/elements/apps-manager/component.js

**Changes:** 1 instance

```javascript
// Line 28 - Error handling
- console.error('Error loading apps:', err);
+ window.logToServer(`Error loading apps: ${err.message}`, 'AppsManager', 'Error', { error: err.toString() });
```

**Reason:** Centralize error reporting for app loading failures

---

### 2. apps/WebHostTaskManagement/public/elements/task-manager/component.js

**Changes:** 2 instances (1 info, 1 error)

```javascript
// Line 117 - Catalog loaded
- console.log('[TaskManager] Loaded catalog:', jobs.length, 'jobs');
+ window.logToServer(`Loaded catalog: ${jobs.length} jobs`, 'TaskManager', 'Info');

// Line 120 - Catalog load error
- console.error('[TaskManager] Failed to load catalog:', error);
+ window.logToServer(`Failed to load catalog: ${error.message}`, 'TaskManager', 'Error', { error: error.toString() });
```

**Reason:** Track task catalog operations and failures on server

---

### 3. apps/WebHostMetrics/public/elements/memory-histogram/component.js

**Changes:** 7 instances (5 info, 2 error)

```javascript
// Line 22 - MetricsManager loaded
- console.log('MetricsManager loaded');
+ window.logToServer('MetricsManager loaded', 'MemoryHistogram', 'Info');

// Line 26 - MetricsManager load failure
- console.error('Failed to load MetricsManager');
+ window.logToServer('Failed to load MetricsManager', 'MemoryHistogram', 'Error');

// Line 51 - Chart.js loaded
- console.log('Chart.js loaded');
+ window.logToServer('Chart.js loaded', 'MemoryHistogram', 'Info');

// Line 65 - Date adapter loaded
- console.log('Chart.js date adapter loaded');
+ window.logToServer('Chart.js date adapter loaded', 'MemoryHistogram', 'Info');

// Line 80 - ChartDataAdapter loaded
- console.log('ChartDataAdapter loaded');
+ window.logToServer('ChartDataAdapter loaded', 'MemoryHistogram', 'Info');

// Line 90 - Script loading error
- console.error('Script loading error:', err);
+ window.logToServer(`Script loading error: ${err.message}`, 'MemoryHistogram', 'Error', { error: err.toString() });

// Line 126 - Loading memory history
- console.log(`Loading memory history: ${start.toISOString()} to ${now.toISOString()}`);
+ window.logToServer(`Loading memory history: ${start.toISOString()} to ${now.toISOString()}`, 'MemoryHistogram', 'Info');

// Line 162 - Memory data load error
- console.error('Error loading memory data:', error);
+ window.logToServer(`Error loading memory data: ${error.message}`, 'MemoryHistogram', 'Error', { error: error.toString() });

// Line 260 - Chart created
- console.log('[MemoryHistogram] Chart created with incremental update adapter');
+ window.logToServer('Chart created with incremental update adapter', 'MemoryHistogram', 'Info');

// Line 267 - Chart updated
- console.log('[MemoryHistogram] Chart updated incrementally');
+ window.logToServer('Chart updated incrementally', 'MemoryHistogram', 'Info');
```

**Reason:** Track metrics visualization lifecycle and dependency loading

---

### 4. apps/WebhostFileExplorer/public/elements/file-explorer/component.js

**Changes:** 1 instance (3 intentionally left as local-only debug)

```javascript
// Line 2597 - Migration notice
- console.log('[FileExplorer] Migration: Disabled pipelining (was causing timeouts)');
+ window.logToServer('Migration: Disabled pipelining (was causing timeouts)', 'FileExplorer', 'Info');
```

**Intentionally NOT Changed:**

```javascript
// Line 54 - Cache eviction (too verbose for server)
console.log(`[FileDetailsCache] Evicted folder: ${evictPath}`);
// Note: Don't log cache evictions to server (too verbose)

// Line 101 - Version cache eviction (too verbose for server)
console.log(`[VersionInfoCache] Evicted file: ${evictPath}`);
// Note: Don't log cache evictions to server (too verbose)

// Line 1467 - Fallback when window.logToServer unavailable
console.log(`[FileExplorer][${new Date().toISOString()}] ${message}`);
// Fallback if global logger not available
```

**Reason:**
- Cache evictions are too verbose and local-only debugging
- Fallback console.log only used when window.logToServer is unavailable
- FileExplorer already uses server logging abstraction via `_globalLogToServer`

---

## Files NOT Yet Updated

### Third-Party Libraries (Excluded)
- `public/lib/babel.min.js` (1 instance)
- `public/lib/react.development.js` (2 instances)
- `public/lib/react-dom.development.js` (2 instances)
- `public/lib/mermaid.min.js` (10 instances)
- `public/lib/sql-wasm.js` (1 instance)

**Reason:** Third-party code should not be modified

---

### Test Files (Excluded)
All `*/tests/twin/browser-tests.js` files (5 instances each in 12 files = 60 total)

**Reason:** Test files should maintain local console output for debugging

---

### Remaining Component Files (Consider for Future Migration)

**High Priority:**
- `public/elements/uplot/component.js` (21 instances)
- `public/elements/file-explorer-deprecated/component.js` (35 instances - deprecated, low priority)
- `public/lib/metrics-database.js` (23 instances)
- `public/lib/metrics-manager.js` (9 instances)
- `public/lib/metrics-fetcher.js` (4 instances)

**Medium Priority:**
- `public/elements/chartjs/component.js` (6 instances)
- `public/lib/unit-test-framework.js` (16 instances)
- `public/lib/chart-data-adapter.js` (4 instances)
- `apps/WebHostMetrics/public/elements/server-heatmap/component.js` (1 instance)
- `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` (1 instance)

**Low Priority (UI_Uplot charts):**
- `apps/UI_Uplot/public/elements/console-logger.js` (3 instances)
- `apps/UI_Uplot/public/elements/uplot-home/component.js` (3 instances)
- Various UI_Uplot chart components (1 instance each)

---

## Migration Guidelines

### When to Use window.logToServer

✅ **DO USE for:**
- Error conditions and exceptions
- Important lifecycle events (component loaded, initialized, destroyed)
- User actions that change state
- API call failures
- Configuration changes
- Performance warnings
- Security-related events

❌ **DO NOT USE for:**
- Verbose/chatty debug logs (cache evictions, every render, etc.)
- Third-party library internals
- Logs that fire multiple times per second
- Sensitive data (passwords, tokens, PII)

### Best Practices

1. **Use descriptive categories:** Match component/module name
2. **Include context:** Use the `data` parameter for additional info
3. **Choose appropriate levels:**
   - `Info`: Normal operations, state changes
   - `Warning`: Potential issues, fallbacks triggered
   - `Error`: Exceptions, failures
   - `Debug`: Development-only verbose logging

4. **Format error messages:**
   ```javascript
   catch (error) {
       window.logToServer(
           `Failed to load data: ${error.message}`,
           'ComponentName',
           'Error',
           { error: error.toString(), stack: error.stack }
       );
   }
   ```

5. **Keep fallback for critical errors:**
   ```javascript
   try {
       window.logToServer(message, category, 'Error');
   } catch {
       console.error('[Fallback]', message); // Ensure error isn't lost
   }
   ```

---

## Benefits of Migration

1. **Centralized Logging:** All client-side logs in server logs for analysis
2. **Historical Data:** Logs persisted on server, not lost on page refresh
3. **Correlation:** Client logs correlated with server-side events
4. **Monitoring:** Track client-side errors and patterns
5. **Debugging:** Reproduce user issues from server logs
6. **Rate Limiting:** Prevent log spam via server-side rate limiting

---

## Next Steps

1. **Test migrated components:** Verify logs appear in server logs at `/api/v1/debug/client-log`
2. **Update remaining high-priority files:** metrics libraries, uplot component
3. **Monitor log volume:** Ensure batching and rate limiting work correctly
4. **Update cheat sheet:** Reflect logging best practices
5. **Consider log viewer UI:** Create admin interface for viewing client logs

---

## Server Log Location

Client logs are written to server logs with:
- **Category:** As specified in window.logToServer call
- **Severity:** Mapped from level parameter
- **Source:** Extracted from JavaScript stack trace
- **UserID:** From current session
- **SessionID:** From current session

Query server logs:
```powershell
Get-Content "C:\SC\PsWebHost\PsWebHost_Data\Logs\log_*.tsv" |
    Select-String "ClientLog" |
    Select-Object -Last 50
```

---

## End of Report
