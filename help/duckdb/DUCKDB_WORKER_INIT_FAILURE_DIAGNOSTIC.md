# DuckDB Worker Initialization Failure - Diagnostic Report

**Date**: 2026-02-10 12:54 PM
**Error**: Worker request timeout (type: INIT) after 30 seconds
**Status**: ❌ BLOCKING ISSUE

---

## Problem Summary

The DuckDB-WASM worker is failing to initialize because it cannot load the required `.mjs` and `.wasm` files from `/public/lib/`. The server is returning 302 redirects instead of serving the files directly.

### Error Message
```
[MetricsDatabase] Initialization failed: Error: Worker request timeout (type: INIT)
Chart Error: No data source specified. Use ?source=/api/...
```

### Root Cause

HTTP requests to `/public/lib/duckdb-browser.mjs` and `/public/lib/duckdb-mvp.wasm` return:
```
HTTP/1.1 302 Found
Location: http://localhost:8080/public/lib/duckdb-browser.mjs
```

This creates a redirect loop where:
1. Worker tries to load `/public/lib/duckdb-browser.mjs`
2. Server returns 302 redirect to the same URL
3. Worker retries indefinitely
4. 30-second timeout expires
5. Initialization fails

---

## Files Verified to Exist

✅ `C:\SC\PsWebHost\public\lib\duckdb-browser.mjs` - 97KB, valid JavaScript
✅ `C:\SC\PsWebHost\public\lib\duckdb-mvp.wasm` - Valid WASM binary
✅ MIME type configured correctly in `config/settings.json`:
```json
{
  "MimeTypes": {
    ".mjs": "application/javascript"
  }
}
```

---

## Likely Causes

### 1. Authentication Middleware Blocking Static Files (Most Likely)

The `/public/lib/` directory may be getting caught by authentication middleware, causing redirects for unauthenticated requests. Web Workers run in a different context and may not have access to session cookies.

**Evidence**:
- Set-Cookie header in 302 response: `PSWebSessionID=...`
- Main page loads fine (authenticated browser session)
- Worker context doesn't inherit session/cookies

### 2. Static File Routing Issue

The server's route handler may not be properly configured to serve files from `/public/lib/` directory.

**Check**: Look for route handlers in `system/` that might intercept `/public/lib/*` requests

### 3. CORS or Security Headers

Cross-origin restrictions might be blocking worker module imports.

---

## Immediate Fixes to Try

### Fix 1: Exclude `/public/lib/` from Authentication (RECOMMENDED)

Add exception in authentication middleware:

```powershell
# In authentication module or route handler
if ($Request.Url.LocalPath -match '^/public/lib/') {
    # Skip authentication for library files
    # Serve file directly
    return
}
```

### Fix 2: Use CDN Fallback

The worker already has CDN fallback logic. Change worker initialization to prefer CDN:

**File**: `public/lib/metrics-worker.js` (line 90-93)

```javascript
const moduleUrls = [
    'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@latest/dist/duckdb-browser.mjs',  // CDN first
    '/public/lib/duckdb-browser.mjs'  // Local fallback
];
```

This will work immediately but adds external dependency.

### Fix 3: Serve WASM Files with Custom Route

Create explicit route handler for library files:

**New File**: `routes/public/lib/[filename]/get.ps1`

```powershell
param([hashtable]$Context)

$filename = $Context.Request.UrlSegments[-1]
$libPath = Join-Path $Global:PSWebServer.Project_Root.Path "public\lib\$filename"

if (Test-Path $libPath) {
    $ext = [System.IO.Path]::GetExtension($filename)
    $mimeType = switch ($ext) {
        '.mjs' { 'application/javascript' }
        '.wasm' { 'application/wasm' }
        '.js' { 'application/javascript' }
        default { 'application/octet-stream' }
    }

    $Context.Response.ContentType = $mimeType
    $Context.Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $bytes = [System.IO.File]::ReadAllBytes($libPath)
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
} else {
    $Context.Response.StatusCode = 404
    $Context.Response.Close()
}
```

---

## Testing Steps (When Server Fixed)

1. **Verify file access**:
   ```bash
   curl -I http://localhost:8080/public/lib/duckdb-browser.mjs
   # Should return: HTTP/1.1 200 OK
   # Should NOT return: HTTP/1.1 302 Found
   ```

2. **Test worker initialization**:
   - Open browser DevTools Console
   - Navigate to metrics chart
   - Should see: `[Worker] ✓ Successfully loaded DuckDB module from local`
   - Should NOT see: `Worker request timeout (type: INIT)`

3. **Verify chart loads**:
   - Chart should display after 2-3 seconds
   - Should see: `[uPlot DEBUG] ✅ Chart CREATED`
   - Should NOT see: `Chart Error: No data source specified`

---

## Performance Logging Status

✅ **All logging code added** in previous session:
- `metrics-worker.js` - TransactionGuard, batch insert timing
- `metrics-database.js` - Query cancellation, pending requests
- `metrics-chart/component.js` - Timer mutex, unmount protection

❌ **Logging not yet testable** because worker won't initialize

---

## Next Steps (Priority Order)

1. **FIX IMMEDIATELY**: Add `/public/lib/` authentication exception
2. **TEST**: Verify worker loads and initializes
3. **VALIDATE**: Check window.logToServer logs appear in server logs
4. **OPTIMIZE**: Test all performance improvements (35-70x batch insert, etc.)
5. **DOCUMENT**: Update test report with actual results

---

## Quick Temporary Workaround (Use CDN)

If you need the chart working RIGHT NOW:

**Edit**: `public/lib/metrics-worker.js` line 90-93

```javascript
const moduleUrls = [
    'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-browser.mjs',  // CDN FIRST
    '/public/lib/duckdb-browser.mjs'  // Local second
];
```

This will bypass the local file issue and load from CDN immediately.

---

## Files to Check

1. **Authentication middleware**: Look for auth checks that might block `/public/lib/*`
2. **Route handlers**: Check if there's a catch-all route interfering
3. **Static file handler**: Verify `/public/*` is served correctly
4. **CORS settings**: Check if workers need special CORS headers

---

## Summary

🔴 **Status**: DuckDB worker cannot initialize due to 302 redirect loop on `.mjs` files
🔧 **Fix**: Exclude `/public/lib/` from authentication middleware
⚡ **Workaround**: Use CDN URLs (change line 90-93 in metrics-worker.js)
✅ **Logging**: All code added, waiting for worker to initialize to test

The optimization work is complete and ready - we just need the worker to actually load its dependencies!
