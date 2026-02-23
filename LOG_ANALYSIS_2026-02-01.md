# Server Log Analysis - 2026-02-01

**Analysis Date:** 2026-02-01
**Log Source:** `PsWebHost_Data\Logs\log_*.tsv`

---

## Summary

Analyzed recent server logs and identified 3 categories of issues:

1. ✅ **Component timeout warnings** - Root cause identified and fixed
2. ✅ **Repeated 404 errors** - Fixed `/api/v1/metrics` endpoint path
3. ✅ **Network disconnection errors** - Normal behavior, no action needed

---

## Issue 1: Component Timeout Warnings

### Symptoms
```
Warning  ComponentTimeout  Component title failed to load after 5000ms
Warning  ComponentTimeout  Component server failed to load after 5000ms
Warning  ComponentTimeout  Component realtime failed to load after 5000ms
```

**Frequency:** Multiple occurrences every few minutes
**Affected Users:** Session 6ec71a85-fb79-4ebc-aa1d-587c7f8b403c

### Root Cause

Components were trying to load with corrupted elementIds:
- `"server"` instead of `"server-heatmap"`
- `"realtime"` instead of `"realtime-events"`

This was caused by a bug in layout serialization code (`psweb_spa.js:1623`) that used `item.i.split('-')[0]` to extract elementId, which incorrectly split on the first hyphen.

**Example:**
- Card ID: `"server-heatmap-1738472952083"`
- Extracted elementId: `"server"` ❌ (should be `"server-heatmap"`)
- Component lookup: Failed (no component named "server")
- Result: Timeout after 5000ms

### Fix Applied

**File:** `public/psweb_spa.js`

1. **Line 1623** - Fixed elementId extraction:
   ```javascript
   // OLD: Buggy split
   elementId: element.Element_Id || element.id || item.i.split('-')[0],

   // NEW: Regex to remove timestamp
   elementId: element.Element_Id || element.id || item.i.replace(/-\d{13}$/, ''),
   ```

2. **Lines 1786-1794** - Improved endpoint derivation:
   ```javascript
   // Try card.id first (contains correct name), fallback to elementId
   const elementName = card.id || card.elementId;
   if (elementName) {
       card.endpoint = `/api/v1/ui/elements/${elementName}`;
   }
   ```

3. **Lines 1803-1838** - Added automatic menu lookup:
   - When endpoint returns 404, fetch main menu
   - Search for correct app-specific URL
   - Retry with correct endpoint

### Status
✅ **Fixed** - Changes deployed, requires browser refresh to test

### Documentation
- See: `LAYOUT_PARAMETER_FIX_2026-02-01.md`

---

## Issue 2: Repeated 404 Errors for `/api/v1/metrics`

### Symptoms
```
Info  Routing  404 Not Found: /api/v1/metrics from 127.0.0.1:62363
Info  Routing  404 Not Found: /api/v1/metrics from 127.0.0.1:62363
... (repeating every 5 seconds)
```

**Frequency:** Every 5 seconds, continuously
**Impact:** Performance overhead from failed requests, cluttered logs

### Root Cause

The uPlot component (`public/elements/uplot/component.js`) was polling `/api/v1/metrics` for real-time incremental data, but the actual endpoint is at `/apps/WebHostMetrics/api/v1/metrics`.

**Code Location:** Line 251
```javascript
// Fetches new metrics data every 5 seconds
const incrementalUrl = new URL('/api/v1/metrics', window.location.origin);
```

This is a legacy path from before the app-based routing system was implemented.

### Fix Applied

**File:** `public/elements/uplot/component.js`

**Lines 245, 251, 275:**
```javascript
// OLD: Root-level path
const incrementalUrl = new URL('/api/v1/metrics', window.location.origin);

// NEW: App-specific path
const incrementalUrl = new URL('/apps/WebHostMetrics/api/v1/metrics', window.location.origin);
```

### Expected Result After Fix
- ✅ No more 404 errors for `/api/v1/metrics`
- ✅ Real-time chart updates work correctly
- ✅ Reduced server log noise
- ✅ Improved performance (no wasted request cycles)

### Status
✅ **Fixed** - Changes deployed

### Documentation
- See: `METRICS_ENDPOINT_FIXES_2026-02-01.md`

---

## Issue 3: Network Disconnection Errors

### Symptoms
```
Error  ErrorArrayCheck  Exception calling "Write" with "3" argument(s):
"The specified network name is no longer available."
At C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psm1:586 char:13
```

**Frequency:** Occasional bursts (6+ in quick succession)
**Timestamp Example:** 2026-02-02T05:03:45Z

### Root Cause

This is **normal network behavior**, not a bug:

1. Client makes HTTP request to server
2. Server begins processing and writing response
3. Client closes connection prematurely (user navigates away, timeout, etc.)
4. Server attempts to write to closed socket
5. Operating system returns "network name is no longer available" error

**Common Triggers:**
- User closes browser tab mid-request
- Network interruption (Wi-Fi disconnect, etc.)
- Browser cancels request (navigation, reload)
- Request timeout on client side
- Large file transfer interrupted

### Code Location
`PSWebHost_Support.psm1:586` - Response stream write operation:
```powershell
$Response.OutputStream.Write($contentBytes, 0, $contentBytes.Length)
```

### Analysis
These errors are **expected and harmless**:
- ✅ Server is correctly handling network cleanup
- ✅ Error is caught and logged (not crashing)
- ✅ No data corruption or server instability
- ✅ Other requests continue to process normally

### Recommendations

**Option 1: Leave as-is** (Recommended)
- Errors are informative for debugging network issues
- Help track client disconnection patterns
- Minimal log noise (only occasional bursts)

**Option 2: Suppress logging** (Not recommended)
- Could hide legitimate network problems
- Masks patterns in client behavior

**Option 3: Log at Debug level** (Alternative)
```powershell
# Change from Error to Debug for disconnection errors
if ($_.Exception.Message -like "*network name is no longer available*") {
    Write-PSWebHostLog -Severity 'Debug' -Category 'Network' -Message "Client disconnected during write"
} else {
    Write-PSWebHostLog -Severity 'Error' -Category 'ErrorArrayCheck' -Message $_.Exception.Message
}
```

### Status
✅ **No action needed** - Working as designed

---

## Additional Observations

### 1. Temperature Sensor Warning (Expected)
Mentioned in previous session - system without WMI thermal sensors. Not an error.

### 2. DataRoot Path Null Errors (Known Issue)
13 apps showing null path errors during initialization. Apps still load successfully. Low priority.

### 3. Global Cache Updates (Normal)
Regular cache updates logged as Debug level:
```
Debug  GlobalCache  Updated cache: 3 jobs, 0 runspaces, 0 tasks (0.2ms)
```
Working as designed.

---

## Testing Checklist

After applying fixes, verify:

- [ ] Refresh browser with layout parameter URL
- [ ] Confirm no "Component timeout" warnings in logs
- [ ] Verify uPlot charts show real-time updates
- [ ] Check server logs for absence of `/api/v1/metrics` 404s
- [ ] Monitor Network tab in browser DevTools
- [ ] Test card loading from main menu
- [ ] Test card loading from URL layout parameter

---

## Server Health Status

**Overall:** ✅ **Healthy**

| Component | Status | Notes |
|-----------|--------|-------|
| HTTP Server | ✅ Running | Port 8080 responding |
| Authentication | ✅ Working | Session cookies valid |
| Routing | ✅ Working | Most endpoints functional |
| Background Jobs | ✅ Active | 3 jobs running |
| Metrics Collection | ✅ Working | Data being tracked |
| Client Logging | ✅ Working | Logs received from browser |

**Fixed Issues:**
- ✅ Component loading (layout parameter)
- ✅ Metrics endpoint paths
- ✅ Source map 404s (previous session)

**Known Non-Issues:**
- ✅ Network disconnection errors (normal)
- ✅ Temperature sensor warnings (expected)

---

## Related Documentation

- `LAYOUT_PARAMETER_FIX_2026-02-01.md` - Component timeout fix details
- `METRICS_ENDPOINT_FIXES_2026-02-01.md` - 404 fix details
- `CONSOLE_LOG_MIGRATION_REPORT.md` - Logging improvements

---

## End of Report
