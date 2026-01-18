# WebHost Realtime Events - Troubleshooting

## Issue: 404 Error on /api/v1/events/logs

### Symptom
```
GET http://localhost:8080/api/v1/events/logs?timeRange=15
[HTTP/1.1 404 Not Found]
```

Browser console shows:
```
RealtimeEventsCard fetch error: Error: HTTP error! status: 404
```

### Root Cause
The app route structure was incorrect. The routes were at:
```
apps/WebhostRealtimeEvents/routes/api/v1/logs/get.ps1  ❌ WRONG
```

With `routePrefix: /api/v1/events`, this would create the URL:
```
/api/v1/events/api/v1/logs  ❌ WRONG (doubled path)
```

### Solution
Routes must be relative to the app root, not include the full path:

**Correct Structure**:
```
apps/WebhostRealtimeEvents/
├── app.yaml (routePrefix: /api/v1/events)
└── routes/
    ├── logs/
    │   ├── get.ps1  → /api/v1/events/logs ✅
    │   └── get.security.json
    └── status/
        ├── get.ps1  → /api/v1/events/status ✅
        └── get.security.json
```

**Route Mapping Formula**:
```
Final URL = routePrefix + /route/file/path
```

**Examples**:
```
/api/v1/events + /logs = /api/v1/events/logs ✅
/api/v1/events + /status = /api/v1/events/status ✅
```

### How to Fix After File Changes

1. **Restart PSWebHost Server**
   The server must be restarted to pick up:
   - New app.yaml configuration
   - New route files
   - Route structure changes

2. **Verify Route Registration**
   After restart, test the endpoints:
   ```powershell
   # Test status endpoint
   Invoke-RestMethod -Uri http://localhost:8080/api/v1/events/status

   # Test logs endpoint
   Invoke-RestMethod -Uri "http://localhost:8080/api/v1/events/logs?timeRange=15"
   ```

3. **Check App Loading**
   Look for app initialization in server logs:
   ```
   [INFO] Loading app: WebHost Realtime Events
   [INFO] Registered route: /api/v1/events/logs
   [INFO] Registered route: /api/v1/events/status
   ```

4. **Clear Browser Cache**
   Force-reload the component:
   ```
   Ctrl+Shift+R (or Cmd+Shift+R on Mac)
   ```

## Other Common Issues

### Component Not Loading

**Symptom**: Menu click shows blank card or loading forever

**Causes**:
1. Component not at `public/elements/realtime-events/component.js`
2. JSX syntax error in component
3. Component doesn't register itself properly

**Solutions**:
```powershell
# 1. Verify component location
Test-Path public/elements/realtime-events/component.js

# 2. Check browser console for syntax errors
# Open DevTools → Console tab

# 3. Verify component registration
# In browser console:
console.log(window.cardComponents['realtime-events']);
# Should show: function RealtimeEventsCard()
```

### Authentication Errors

**Symptom**: 401 Unauthorized responses

**Cause**: Session expired or security.json misconfigured

**Solution**:
```powershell
# Check security configuration
cat apps/WebhostRealtimeEvents/routes/logs/get.security.json
# Should show: {"Allowed_Roles":["authenticated"]}

# Re-login if session expired
# Click logout, then login again
```

### Empty Results

**Symptom**: Component loads but shows "No logs found"

**Causes**:
1. No logs in selected time range
2. Log file doesn't exist
3. Read-PSWebHostLog not available

**Solutions**:
```powershell
# 1. Check log file exists
Test-Path Logs/PSWebHost.log

# 2. Check log file has content
Get-Content Logs/PSWebHost.log -TotalCount 10

# 3. Test Read-PSWebHostLog directly
Read-PSWebHostLog -StartTime (Get-Date).AddHours(-1) -EndTime (Get-Date)

# 4. Generate test logs
Write-PSWebHostLog -Severity Info -Category Test -Message "Test log entry"
```

### Slow Performance

**Symptom**: API requests take >1 second

**Causes**:
1. Large log file (>100 MB)
2. Very large time range (>24 hours)
3. Too many filters requiring full scan

**Solutions**:
```powershell
# 1. Check log file size
(Get-Item Logs/PSWebHost.log).Length / 1MB
# If >100 MB, consider log rotation

# 2. Reduce time range
# Use shorter ranges (15 min, 30 min, 1 hour)

# 3. Reduce result count
# Set maxEvents to 100-500 instead of 1000+

# 4. Use specific filters
# Filter by severity, category, or source to reduce results
```

### App Not Showing in Menu

**Symptom**: Real-time Events not in menu after restart

**Cause**: Menu cache or app not loaded

**Solutions**:
```powershell
# 1. Check app.yaml enabled
cat apps/WebhostRealtimeEvents/app.yaml | Select-String "enabled"
# Should show: enabled: true

# 2. Invalidate menu cache
# In browser console:
CacheManager.invalidate('main-menu');
location.reload();

# 3. Check server logs for app loading errors
# Look for error messages about WebhostRealtimeEvents
```

## Development Workflow

### Making Changes to Component

```powershell
# 1. Edit source
code apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js

# 2. Copy to deployed location
cp apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js `
   public/elements/realtime-events/component.js

# 3. Clear browser cache and reload
# Ctrl+Shift+R
```

### Making Changes to API Endpoints

```powershell
# 1. Edit route handler
code apps/WebhostRealtimeEvents/routes/logs/get.ps1

# 2. Restart PSWebHost server
# Stop server (Ctrl+C)
# Start server: .\WebHost.ps1

# 3. Test endpoint
Invoke-RestMethod -Uri "http://localhost:8080/api/v1/events/logs?timeRange=15"
```

### Testing Changes

```powershell
# 1. Run twin tests
Invoke-Pester apps/WebhostRealtimeEvents/tests/twin/routes/logs/get.Tests.ps1
Invoke-Pester apps/WebhostRealtimeEvents/tests/twin/routes/status/get.Tests.ps1

# 2. Manual browser testing
# - Open Real-time Events card
# - Test time range selection
# - Test filters
# - Test sorting
# - Test export

# 3. Check for errors in browser console
# DevTools → Console tab
# Look for red error messages
```

## Server Not Picking Up App

### Symptom
After restart, endpoints still return 404

### Checklist

1. **Verify app.yaml format**:
   ```yaml
   name: WebHost Realtime Events
   version: 1.0.0
   enabled: true
   routePrefix: /api/v1/events
   ```
   Keys must be lowercase!

2. **Verify route structure**:
   ```
   apps/WebhostRealtimeEvents/routes/logs/get.ps1  ✅
   NOT: apps/WebhostRealtimeEvents/routes/api/v1/logs/get.ps1  ❌
   ```

3. **Check security.json files exist**:
   ```powershell
   Test-Path apps/WebhostRealtimeEvents/routes/logs/get.security.json
   Test-Path apps/WebhostRealtimeEvents/routes/status/get.security.json
   ```

4. **Check server startup logs**:
   Look for app loading messages in console output when starting WebHost.ps1

5. **Check app directory is correct**:
   Must be in `apps/` folder at root level, not nested deeper

## Getting Help

If issues persist:

1. **Check Server Logs**:
   ```powershell
   Get-Content Logs/PSWebHost.log -Tail 50
   ```

2. **Check Browser Console**:
   F12 → Console tab → Look for error messages

3. **Test API Directly**:
   ```powershell
   # Bypass UI, test API
   $session = New-PSSession # or however you authenticate
   Invoke-RestMethod -Uri http://localhost:8080/api/v1/events/logs -Method GET
   ```

4. **Verify Module Loaded**:
   ```powershell
   # Check if Read-PSWebHostLog is available
   Get-Command Read-PSWebHostLog
   ```

5. **Check File Permissions**:
   ```powershell
   # Ensure server can read log file
   Test-Path Logs/PSWebHost.log
   (Get-Acl Logs/PSWebHost.log).Access
   ```
