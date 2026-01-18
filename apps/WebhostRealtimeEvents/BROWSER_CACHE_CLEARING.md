# Browser Cache Clearing Instructions

## Issue

Your browser has cached the old event-stream component. The console shows:
```
Cache hit (stale) for event-stream, revalidating...
GET http://localhost:8080/api/v1/ui/elements/event-stream?count=1000
```

The new realtime-events component is installed, but your browser is loading the old cached layout.

## Solution: Clear Browser Cache and Layout

### Option 1: Clear All Cache (Recommended)

1. Open the browser console (F12)
2. Run this command:
   ```javascript
   clearAllCache()
   ```
3. Hard refresh the page: **Ctrl+Shift+R** (Windows/Linux) or **Cmd+Shift+R** (Mac)
4. You should now see the new Real-time Events card

### Option 2: Clear Layout Cache Only

1. Open the browser console (F12)
2. Run this command:
   ```javascript
   localStorage.removeItem('psweb_cache_layout')
   ```
3. Refresh the page normally (F5)

### Option 3: Clear PSWebHost Cache Entries

1. Open the browser console (F12)
2. Run this command:
   ```javascript
   CacheManager.invalidatePattern('.*')
   ```
3. Hard refresh: **Ctrl+Shift+R**

### Option 4: Browser Developer Tools

1. Open Developer Tools (F12)
2. Go to **Application** tab (Chrome) or **Storage** tab (Firefox)
3. Select **Local Storage** → `http://localhost:8080`
4. Find and delete:
   - `psweb_cache_layout`
   - `psweb_cache_event-stream`
   - Any other `psweb_cache_*` entries
5. Hard refresh: **Ctrl+Shift+R**

### Option 5: Manual URL

After clearing cache, you can manually navigate to the new card:
```
http://localhost:8080/api/v1/ui/elements/realtime-events
```

Click this in the menu to load the new component directly.

## Verification

After clearing cache, you should see in the console:
```
Loading component script for realtime-events...
✓ Component loaded for realtime-events
```

And the XHR requests should go to:
```
GET http://localhost:8080/api/v1/events/logs?timeRange=15
```

NOT:
```
GET http://localhost:8080/api/v1/ui/elements/event-stream
```

## Why This Happens

PSWebHost's SPA caches:
1. **Layout** - Which cards are displayed and their positions
2. **Card Settings** - Individual card configurations
3. **API Responses** - Recent data (with TTL)

When you had the old "Real-time Events" card on your dashboard:
- The layout was cached with `event-stream` as the card ID
- Even though the menu now points to `realtime-events`, your saved layout still references `event-stream`

Clearing the cache forces the SPA to reload the layout from the menu configuration, which now points to the new `realtime-events` component.

## For Developers

If you're testing frequently, use the console helpers:

**View cache stats:**
```javascript
viewCacheStats()
```

**Clear all cache:**
```javascript
clearAllCache()
```

**Invalidate specific pattern:**
```javascript
CacheManager.invalidatePattern('event-stream')
```

**Check what's cached:**
```javascript
Object.keys(localStorage).filter(k => k.startsWith('psweb_cache_'))
```

## Production Deployment

When deploying this update to production:

1. **Update the menu configuration** (already done)
2. **Copy component to public directory** (already done)
3. **Consider cache invalidation strategy**:
   - Option A: Increment app version in `app.yaml`
   - Option B: Add cache-busting query parameter to component URL
   - Option C: Document that users should clear cache after update
   - Option D: Add a "Clear Cache" button to site settings

## Component File Locations

✅ **Correct (all in place)**:
- `public/elements/realtime-events/component.js` - Deployed location
- `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` - Source location
- `routes/api/v1/ui/elements/realtime-events/get.ps1` - UI wrapper

✅ **Menu Updated**:
- `routes/api/v1/ui/elements/main-menu/main-menu.yaml` - Points to new URL

## Next Steps

1. Clear your browser cache using one of the options above
2. Navigate to "Real-time Events" in the menu
3. Verify the new enhanced component loads
4. Enjoy the new features:
   - Time range filtering (5 min to 24 hours)
   - Advanced filtering by category, severity, source, user, session
   - Sortable columns
   - Enhanced log format support
   - Better export options

## Still Not Working?

If after clearing cache you still see the old component:

1. Check the browser console for errors
2. Verify the file exists:
   ```
   http://localhost:8080/public/elements/realtime-events/component.js
   ```
3. Check the Network tab to see which component.js is being loaded
4. Try a different browser or incognito/private window
5. Restart the PSWebHost server

## Cache Management Going Forward

To prevent similar issues in the future:

1. **During Development**: Clear cache frequently or use incognito mode
2. **After Updates**: Always clear cache after pulling updates
3. **Version Changes**: Consider implementing automatic cache invalidation on version change
4. **User Education**: Document cache clearing in update notes
