# Quick Start: Installing DuckDB-WASM Dependencies

**Time Required**: 2-3 minutes

---

## Option 1: NPM Method (Recommended)

### Prerequisites
- Node.js 16+ installed ([Download](https://nodejs.org/))

### Steps

```powershell
# 1. Navigate to project directory
cd C:\SC\PsWebHost

# 2. Install dependencies (one command does everything)
npm install

# That's it! This automatically:
# - Downloads @duckdb/duckdb-wasm from NPM
# - Downloads apache-arrow from NPM
# - Copies files to public/lib/
```

### Verify Installation

```powershell
# Check files were copied
Get-ChildItem public\lib\duckdb-*.* | Select-Object Name, Length
Get-ChildItem public\lib\apache-arrow.*.js | Select-Object Name, Length

# Expected output:
# Name                              Length
# ----                              ------
# duckdb-mvp.wasm.js                ~200KB
# duckdb-mvp.wasm                   ~4MB
# duckdb-browser-mvp.worker.js      ~50KB
# apache-arrow.es2015.min.js        ~500KB
```

---

## Option 2: PowerShell Script (No Node.js Required)

### Steps

```powershell
# 1. Navigate to project directory
cd C:\SC\PsWebHost

# 2. Run installation script
.\Install-DuckDBDependencies.ps1

# Output should show:
# [Install-DuckDBDependencies] ===== DuckDB-WASM Dependency Installer =====
# [Install-DuckDBDependencies]   ✓ Downloaded successfully: 4.2MB
# [Install-DuckDBDependencies]   ✓ Downloaded successfully: 200KB
# [Install-DuckDBDependencies]   ✓ Downloaded successfully: 500KB
# [Install-DuckDBDependencies] ✓ All dependencies ready!
```

---

## What Happens Next?

Once dependencies are installed locally, the metrics-worker.js will:

1. **Try local files first** - Loads from `/public/lib/` (fast, ~50ms)
2. **Fallback to CDN if needed** - Uses jsdelivr CDN as backup
3. **Retry with exponential backoff** - 1s, 1s, 5s, 10s, 30s delays
4. **Continue retrying every minute** - Non-blocking, runs in worker thread

---

## Test the Installation

### Start the Server

```powershell
# Start your PSWebHost server (your normal command)
# Example:
# .\Start-WebHost.ps1
```

### Load Metrics Chart

1. Navigate to: `http://localhost:8080/apps/UI_Uplot/public/elements/metrics-chart/`
2. Open browser console (F12)
3. Look for these logs:

```
[Worker] Attempting to load DuckDB-WASM from local: /public/lib/duckdb-mvp.wasm.js
[Worker] ✓ Successfully loaded DuckDB-WASM from local
[Worker] Attempting to load Apache Arrow from local: /public/lib/apache-arrow.es2015.min.js
[Worker] ✓ Successfully loaded Apache Arrow from local
[Worker] All dependencies loaded successfully
[Worker] Initializing DuckDB-WASM...
[Worker] DuckDB-WASM initialized with in-memory storage
```

✅ **Success!** Dependencies loaded locally

---

## Troubleshooting

### Issue: npm command not found

**Solution**: Install Node.js from https://nodejs.org/

### Issue: Files not found after npm install

**Solution**:
```powershell
# Manually run copy script
npm run copy-libs
```

### Issue: PowerShell script blocked

**Solution**:
```powershell
# Enable script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Then run the script again
.\Install-DuckDBDependencies.ps1
```

### Issue: Network error downloading files

**Solution**: Check internet connection, try again

### Issue: Worker shows CDN retry messages

**Solution**: Local files not accessible by web server
- Verify files exist in `public/lib/`
- Check web server serves the `public/lib/` directory
- Test direct access: `http://localhost:8080/public/lib/duckdb-mvp.wasm.js`

---

## Next Steps

After dependencies are installed:

1. ✅ Run DuckDB test suite
   ```powershell
   .\Test-DuckDB-MetricsChart.ps1
   ```

2. ✅ Monitor performance in production
   - Check browser console for load times
   - Should see "Successfully loaded from local"
   - History load should be <100ms

3. ✅ Update dependencies periodically
   ```powershell
   npm update
   npm run copy-libs
   ```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `npm install` | Install all dependencies |
| `npm update` | Update to newer versions |
| `npm run copy-libs` | Manually copy files to public/lib |
| `.\Install-DuckDBDependencies.ps1` | PowerShell download |
| `.\Install-DuckDBDependencies.ps1 -Force` | Force re-download |

---

**That's it!** Dependencies are now managed locally with automatic CDN fallback and retry logic.
