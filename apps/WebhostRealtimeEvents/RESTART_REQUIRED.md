# Server Restart Required

## Issue: 404 Not Found

The component is loading correctly, but the API endpoints are returning 404:

```
GET /api/v1/events/logs?timeRange=15
[HTTP/1.1 404 Not Found]
```

## Root Cause

PSWebHost needs to be **restarted** to:
1. Discover the new app in `apps/WebhostRealtimeEvents/`
2. Register the app's routes
3. Make `/api/v1/events/logs` and `/api/v1/events/status` available

## Solution

### Restart PSWebHost Server

```powershell
# Stop the server (Ctrl+C in the terminal running WebHost.ps1)
# Then restart it:
.\WebHost.ps1
```

### Verify Routes Are Registered

After restart, check that the app loaded:

```powershell
# Should see "WebHost Realtime Events" in the app list
curl http://localhost:8080/api/v1/apps/installed
```

Test the endpoints directly:

```powershell
# Should return app status (may redirect to login if not authenticated)
curl http://localhost:8080/api/v1/events/status

# Should return log data
curl http://localhost:8080/api/v1/events/logs?timeRange=15
```

## How PSWebHost App Loading Works

1. **Server Start**: PSWebHost scans `apps/` directory
2. **App Discovery**: Reads each `app.yaml` file
3. **Route Registration**: Maps routes based on `routePrefix`
4. **Runtime**: Routes are available at `{routePrefix}/{route-path}`

### Our App Structure

```
apps/WebhostRealtimeEvents/
├── app.yaml (routePrefix: /api/v1/events)
└── routes/
    ├── logs/get.ps1      → /api/v1/events/logs
    └── status/get.ps1    → /api/v1/events/status
```

The `routePrefix` `/api/v1/events` + route path `/logs` = `/api/v1/events/logs`

## After Restart

The browser component will automatically retry the API call and should work immediately:

✅ Time range selector will populate
✅ Logs will load from file
✅ Filters will work
✅ Sorting will work
✅ Export will work

## Alternative: Manual Route Registration (Advanced)

If you don't want to restart the whole server, you could try manually registering the routes (not recommended):

```powershell
# In PowerShell console where PSWebHost is running:
. "apps/WebhostRealtimeEvents/routes/logs/get.ps1"
. "apps/WebhostRealtimeEvents/routes/status/get.ps1"
```

But this won't properly register them in the routing system - **restart is the proper solution**.

## Development Workflow

When developing apps:

1. **Create/modify app files** (routes, components, etc.)
2. **Restart PSWebHost** to load changes
3. **Clear browser cache** if components changed
4. **Test in browser**

For component-only changes (no route changes), you don't need to restart - just:
1. Update `public/elements/{component}/component.js`
2. Hard refresh browser (Ctrl+Shift+R)

## Verification After Restart

Open browser console and watch for:

**Before restart (404)**:
```
GET /api/v1/events/logs → 404 Not Found
RealtimeEventsCard fetch error: HTTP error! status: 404
```

**After restart (success)**:
```
GET /api/v1/events/logs → 200 OK
[Component loads with data]
```

## Summary

✅ Component is correctly placed at `public/elements/realtime-events/component.js`
✅ Routes are correctly structured in `apps/WebhostRealtimeEvents/routes/`
✅ App configuration is correct in `app.yaml`

❌ **Server hasn't loaded the new app yet**

**Action**: Restart PSWebHost server with `.\WebHost.ps1`

Then refresh the browser and the Real-time Events component will work perfectly!
