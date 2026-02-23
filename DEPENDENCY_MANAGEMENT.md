# Dependency Management for DuckDB-WASM
**Date**: 2026-02-09
**Status**: Local dependencies with CDN fallback and retry logic

---

## Overview

DuckDB-WASM and Apache Arrow dependencies are managed locally to avoid network errors and improve reliability. The system includes:

1. **Local-first loading** - Tries local copies from `public/lib/` first
2. **CDN fallback** - Falls back to jsdelivr CDN if local fails
3. **Exponential backoff retry** - Retries with delays: 1s, 1s, 5s, 10s, 30s
4. **Continuous retry** - Continues retrying every 60s after initial attempts
5. **Non-blocking** - Runs in Web Worker, doesn't block main thread

---

## Installation Methods

### Method 1: NPM-Based (Recommended)

**Advantages**:
- Version controlled in package.json
- Automatic updates with `npm update`
- Dependency integrity validation
- Works with CI/CD pipelines

**Setup**:
```bash
cd C:\SC\PsWebHost

# Install Node.js dependencies
npm install

# This automatically:
# 1. Downloads @duckdb/duckdb-wasm@1.28.0
# 2. Downloads apache-arrow@14.0.2
# 3. Copies files to public/lib/ via postinstall script
```

**Files Created**:
- `node_modules/@duckdb/duckdb-wasm/` - DuckDB library
- `node_modules/apache-arrow/` - Apache Arrow library
- `public/lib/duckdb-mvp.wasm.js` - DuckDB JavaScript (copied)
- `public/lib/duckdb-mvp.wasm` - DuckDB WebAssembly binary (copied)
- `public/lib/duckdb-browser-mvp.worker.js` - DuckDB worker script (copied)
- `public/lib/apache-arrow.es2015.min.js` - Apache Arrow (copied)

**Update Dependencies**:
```bash
npm update @duckdb/duckdb-wasm
npm update apache-arrow
npm run copy-libs
```

---

### Method 2: PowerShell Script

**Advantages**:
- No Node.js required
- Direct download from CDN
- Simple execution

**Setup**:
```powershell
cd C:\SC\PsWebHost

# Download all dependencies
.\Install-DuckDBDependencies.ps1

# Force re-download
.\Install-DuckDBDependencies.ps1 -Force
```

**Files Created**:
- `public/lib/duckdb-mvp.wasm.js` - DuckDB JavaScript
- `public/lib/duckdb-mvp.wasm` - DuckDB WebAssembly binary
- `public/lib/duckdb-browser-mvp.worker.js` - DuckDB worker script
- `public/lib/apache-arrow.es2015.min.js` - Apache Arrow
- `public/lib/duckdb-dependencies.json` - Dependency manifest

---

## Retry Logic

The metrics-worker.js implements comprehensive retry logic:

### Retry Sequence

1. **Try local copy** (`/public/lib/duckdb-mvp.wasm.js`)
   - Attempt 1: Immediate
   - Attempt 2: Wait 1s, retry
   - Attempt 3: Wait 1s, retry
   - Attempt 4: Wait 5s, retry
   - Attempt 5: Wait 10s, retry
   - Attempt 6: Wait 30s, retry

2. **Try CDN fallback** (`https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-mvp.wasm.js`)
   - Same retry sequence as local

3. **Continuous retry** (if all above fail)
   - Retry every 60 seconds indefinitely
   - Non-blocking (runs in worker thread)
   - Logs each attempt to console

### Implementation

```javascript
async function loadScriptWithRetry(urls, scriptName) {
    const delays = [1000, 1000, 5000, 10000, 30000]; // Exponential backoff

    for (let urlIndex = 0; urlIndex < urls.length; urlIndex++) {
        const url = urls[urlIndex];

        for (let attempt = 0; attempt < delays.length; attempt++) {
            try {
                importScripts(url);
                return; // Success!
            } catch (err) {
                const delay = delays[attempt];
                await sleep(delay);
            }
        }
    }

    // Enter 1-minute retry loop
    while (true) {
        await sleep(60000);
        try {
            importScripts(urls[urls.length - 1]);
            return;
        } catch (err) {
            // Continue loop
        }
    }
}

// Load with retry
await loadScriptWithRetry(
    [
        '/public/lib/duckdb-mvp.wasm.js',  // Local first
        'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.28.0/dist/duckdb-mvp.wasm.js'  // CDN fallback
    ],
    'DuckDB-WASM'
);
```

---

## Dependency Versions

| Library | Version | Size | Purpose |
|---------|---------|------|---------|
| @duckdb/duckdb-wasm | 1.28.0 | ~4.2MB | Columnar database engine |
| apache-arrow | 14.0.2 | ~500KB | Zero-copy data format |

### DuckDB-WASM Files

1. **duckdb-mvp.wasm.js** (~200KB)
   - JavaScript wrapper/loader
   - Initializes WebAssembly module
   - Provides DuckDBModule() function

2. **duckdb-mvp.wasm** (~4MB)
   - Compiled WebAssembly binary
   - Core database engine
   - Columnar storage implementation

3. **duckdb-browser-mvp.worker.js** (~50KB)
   - Web Worker wrapper (optional)
   - Not currently used (we have custom worker)

### Apache Arrow Files

1. **apache-arrow.es2015.min.js** (~500KB)
   - Arrow IPC format support
   - Zero-copy data transfer
   - Used for future optimization

---

## Verification

### Check Local Files Exist

```powershell
Get-ChildItem C:\SC\PsWebHost\public\lib\duckdb-*.* | Select-Object Name, Length

# Expected output:
# Name                              Length
# ----                              ------
# duckdb-mvp.wasm.js                ~200KB
# duckdb-mvp.wasm                   ~4MB
# duckdb-browser-mvp.worker.js      ~50KB
```

### Test Load in Browser

```javascript
// Open browser console on metrics chart page
// Check for these logs:
[Worker] Attempting to load DuckDB-WASM from local: /public/lib/duckdb-mvp.wasm.js
[Worker] ✓ Successfully loaded DuckDB-WASM from local
[Worker] Attempting to load Apache Arrow from local: /public/lib/apache-arrow.es2015.min.js
[Worker] ✓ Successfully loaded Apache Arrow from local
[Worker] All dependencies loaded successfully
```

### Test CDN Fallback

```powershell
# Temporarily rename local file to simulate failure
Rename-Item C:\SC\PsWebHost\public\lib\duckdb-mvp.wasm.js duckdb-mvp.wasm.js.bak

# Reload page in browser, should see:
[Worker] Attempt 1/5 failed to load DuckDB-WASM from /public/lib/duckdb-mvp.wasm.js: NetworkError
[Worker] Retrying DuckDB-WASM in 1000ms...
[Worker] Attempt 2/5 failed to load DuckDB-WASM from /public/lib/duckdb-mvp.wasm.js: NetworkError
[Worker] Trying next source for DuckDB-WASM...
[Worker] Attempting to load DuckDB-WASM from CDN: https://cdn.jsdelivr.net/...
[Worker] ✓ Successfully loaded DuckDB-WASM from CDN

# Restore file
Rename-Item C:\SC\PsWebHost\public\lib\duckdb-mvp.wasm.js.bak duckdb-mvp.wasm.js
```

---

## Updating Dependencies

### Update to Newer Versions

**NPM Method**:
```bash
# Update package.json
# "dependencies": {
#     "@duckdb/duckdb-wasm": "^1.29.0",  // New version
#     "apache-arrow": "^15.0.0"          // New version
# }

npm update
npm run copy-libs
```

**PowerShell Method**:
```powershell
# Edit Install-DuckDBDependencies.ps1
# Change version numbers in URLs
# $dependencies = @(
#     @{
#         Url = "https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/dist/duckdb-mvp.wasm.js"
#     }
# )

.\Install-DuckDBDependencies.ps1 -Force
```

**Update Worker Script**:
```javascript
// Edit public/lib/metrics-worker.js
// Update CDN fallback URLs to new versions
await loadScriptWithRetry(
    [
        '/public/lib/duckdb-mvp.wasm.js',
        'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@1.29.0/dist/duckdb-mvp.wasm.js'  // Update version
    ],
    'DuckDB-WASM'
);
```

---

## Troubleshooting

### Issue: "Failed to load DuckDB-WASM from all sources"

**Cause**: Both local and CDN sources failed
**Solution**:
1. Check local files exist: `Get-ChildItem C:\SC\PsWebHost\public\lib\duckdb-*.*`
2. Re-download: `.\Install-DuckDBDependencies.ps1 -Force`
3. Check network: Test CDN URL in browser
4. Check browser console for detailed error messages

### Issue: "importScripts failed: NetworkError"

**Cause**: Worker can't access local file (CORS or path issue)
**Solution**:
1. Ensure PowerShell web server serves `public/lib/` directory
2. Check URL path is correct: `/public/lib/duckdb-mvp.wasm.js`
3. Test direct access: `http://localhost:8080/public/lib/duckdb-mvp.wasm.js`
4. Check Content-Type header: Should be `application/javascript`

### Issue: Retry loop consuming CPU

**Status**: Not a problem - runs in worker thread
**Info**: Retry logic is non-blocking and runs every 60s, minimal CPU impact

---

## Performance Impact

| Scenario | Load Time | Notes |
|----------|-----------|-------|
| Local files (cached) | ~10ms | Instant from browser cache |
| Local files (first load) | ~50-100ms | Fast from localhost |
| CDN fallback (cached) | ~20ms | CDN cache hit |
| CDN fallback (first load) | ~200-500ms | Network latency + download |
| Retry with 1s delay | +1000ms | Per retry attempt |

**Recommendation**: Always use local files for best performance

---

## CI/CD Integration

### Build Pipeline

```yaml
# .github/workflows/build.yml or similar
steps:
  - name: Install Node.js
    uses: actions/setup-node@v3
    with:
      node-version: '18'

  - name: Install dependencies
    run: |
      cd C:\SC\PsWebHost
      npm ci

  - name: Verify dependencies copied
    run: |
      Test-Path C:\SC\PsWebHost\public\lib\duckdb-mvp.wasm.js
      Test-Path C:\SC\PsWebHost\public\lib\apache-arrow.es2015.min.js
```

---

## Files Summary

| File | Size | Purpose |
|------|------|---------|
| `package.json` | <1KB | NPM dependency manifest |
| `scripts/copy-dependencies.js` | 3KB | NPM postinstall script |
| `Install-DuckDBDependencies.ps1` | 5KB | PowerShell download script |
| `public/lib/duckdb-mvp.wasm.js` | 200KB | DuckDB JavaScript loader |
| `public/lib/duckdb-mvp.wasm` | 4MB | DuckDB WebAssembly binary |
| `public/lib/apache-arrow.es2015.min.js` | 500KB | Apache Arrow library |
| `public/lib/duckdb-dependencies.json` | <1KB | Dependency manifest |
| `public/lib/metrics-worker.js` | 15KB | Worker with retry logic |

**Total Size**: ~5MB (one-time download)

---

## Security Considerations

### Subresource Integrity (SRI)

Future enhancement: Add SRI hashes to verify file integrity

```javascript
const expectedHashes = {
    'duckdb-mvp.wasm.js': 'sha384-...',
    'apache-arrow.es2015.min.js': 'sha384-...'
};

async function verifyIntegrity(url, expectedHash) {
    const response = await fetch(url);
    const buffer = await response.arrayBuffer();
    const hash = await crypto.subtle.digest('SHA-384', buffer);
    // Compare hash
}
```

### Content Security Policy (CSP)

Ensure CSP allows loading from:
- `self` (local files)
- `https://cdn.jsdelivr.net` (CDN fallback)
- `blob:` (for Web Worker)
- `wasm-unsafe-eval` (for WebAssembly)

---

## Conclusion

The dependency management system provides:

✅ **Reliability** - Local-first with CDN fallback
✅ **Performance** - Fast local loading (~50ms)
✅ **Resilience** - Exponential backoff retry
✅ **Non-blocking** - Worker-thread retry loop
✅ **Maintainability** - NPM-based versioning

**Next Step**: Run installation script to download dependencies locally

```powershell
.\Install-DuckDBDependencies.ps1
```
