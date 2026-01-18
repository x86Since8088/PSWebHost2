# Route Prefix Fix

## Problem

The app routes were returning 404 because PSWebHost's app system requires apps to use the `/apps/{appname}` route prefix pattern.

**Original (broken)**:
- `routePrefix: /api/v1/events`
- Routes not registered properly

**Fixed**:
- `routePrefix: /apps/realtimeevents`
- Routes now register correctly

## Changes Made

### 1. Updated app.yaml

Changed routePrefix from `/api/v1/events` to `/apps/realtimeevents`:

```yaml
routePrefix: /apps/realtimeevents
```

### 2. Updated Component API URL

Changed the component to use the correct API path:

**Before**:
```javascript
const url = `/api/v1/events/logs?${params.toString()}`;
```

**After**:
```javascript
const url = `/apps/realtimeevents/api/v1/logs?${params.toString()}`;
```

## Final API Endpoints

With `routePrefix: /apps/realtimeevents` and routes in `routes/api/v1/`:

- **Logs**: `/apps/realtimeevents/api/v1/logs`
- **Status**: `/apps/realtimeevents/api/v1/status`

## Next Step: Restart Server

**IMPORTANT**: Restart the PSWebHost server for these changes to take effect:

```powershell
# Stop server (Ctrl+C)
# Then restart:
.\WebHost.ps1
```

After restart, hard-refresh the browser (Ctrl+Shift+R) and the component will work!

## How PSWebHost App Routing Works

PSWebHost apps must follow this pattern:

1. **routePrefix** must start with `/apps/{appname}`
2. **Route files** go in `routes/` directory
3. **Final URLs** = `routePrefix` + route path

### Example:

```yaml
# app.yaml
routePrefix: /apps/myapp
```

```
routes/
  api/
    v1/
      data/
        get.ps1
```

**Result**: `/apps/myapp/api/v1/data`

### Why This Pattern?

The init.ps1 script looks for this pattern to register app-specific routes:

```powershell
if ($manifest.routePrefix -and $manifest.routePrefix -match '^/apps/([a-zA-Z0-9_-]+)') {
    $routePrefixName = $matches[1]
    # Register app routes...
}
```

Apps that don't follow `/apps/*` pattern won't have their routes registered.

## Files Updated

✅ `apps/WebhostRealtimeEvents/app.yaml` - Changed routePrefix
✅ `public/elements/realtime-events/component.js` - Updated API URL
✅ `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` - Source copy updated

## Verification

After server restart, test the endpoint:

```bash
curl "http://localhost:8080/apps/realtimeevents/api/v1/logs?timeRange=15"
```

Should return JSON with logs (or redirect to login if not authenticated).

In browser console, you should see:

```
GET /apps/realtimeevents/api/v1/logs → 200 OK
```

Instead of:

```
GET /api/v1/events/logs → 404 Not Found
```
