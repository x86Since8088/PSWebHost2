# Switch to New Realtime Events Component

## The Problem

Your browser's **saved layout** still contains the old `event-stream` card. Even though you cleared the cache, the layout itself (which cards are on the dashboard) is saved separately.

## Quick Solution

### Option 1: Remove Old Card, Add New One

1. **Remove the old "Real-time Events" card** from your dashboard:
   - Click the ❌ (X) button on the current "Real-time Events" card
   - This removes it from your saved layout

2. **Add the new card** from the menu:
   - Click "Main Menu" → "Real-time Events"
   - The new enhanced component will load

3. **Drag to position** as desired

### Option 2: Reset Layout (Nuclear Option)

Open the browser console (F12) and run:

```javascript
// Delete the saved layout
localStorage.removeItem('psweb_cache_layout')

// Force reload
location.reload()
```

This will reset your dashboard to the default layout, which should include the new component.

### Option 3: Manual URL Navigation

1. Navigate directly to the new component:
   ```
   http://localhost:8080/api/v1/ui/elements/realtime-events
   ```

2. This will load the new component in a card

3. Drag it to your desired position on the dashboard

### Option 4: Edit Layout JSON Directly

1. Open browser DevTools (F12)
2. Go to **Application** → **Local Storage** → `http://localhost:8080`
3. Find `psweb_cache_layout`
4. Click on it to edit
5. Find this line:
   ```json
   {"i":"event-stream", ...}
   ```
6. Change it to:
   ```json
   {"i":"realtime-events", ...}
   ```
7. Save and refresh

## Why This Happens

PSWebHost has two separate caches:

1. **Component Cache** (`psweb_cache_*`) - The actual JavaScript files
   - You cleared this successfully

2. **Layout** (separate localStorage key) - Which cards are displayed where
   - This is NOT cleared by `clearAllCache()`
   - This is what's causing the old component to load

The layout is saved as a JSON structure like:
```json
{
  "layout": [
    {"i": "event-stream", "x": 0, "y": 14, "w": 12, "h": 14},
    {"i": "server-heatmap", "x": 0, "y": 0, "w": 12, "h": 14}
  ]
}
```

Your saved layout still references `event-stream` instead of `realtime-events`.

## How to Tell Which Component is Loaded

Check the console for:

**Old component (event-stream)**:
```
GET /public/elements/event-stream/component.js
GET /api/v1/ui/elements/event-stream?count=1000
```

**New component (realtime-events)**:
```
GET /public/elements/realtime-events/component.js
GET /api/v1/events/logs?timeRange=15
```

## Verification

After switching, you should see:

1. **Time Range Selector** dropdown at the top (5 min, 15 min, 30 min, etc.)
2. **Multiple filter inputs** (not just one search box)
3. **Sortable column headers** (click to sort)
4. **Different API calls** in Network tab: `/api/v1/events/logs`

## Why No Events Are Showing

The old `event-stream` component reads from `$Global:LogHistory` (an in-memory buffer), which is populated by background jobs.

If you see the old component but no events, it could mean:
- The background log tail job isn't running
- No events have been logged recently
- The LogHistory buffer hasn't been populated

The NEW component (`realtime-events`) reads directly from the log file using `Read-PSWebHostLog`, so it will show events even if the background job isn't running.

## Complete Reset Procedure

If you want to start fresh:

```javascript
// Open console (F12), run all these:

// 1. Clear all PSWebHost caches
Object.keys(localStorage)
  .filter(k => k.startsWith('psweb_cache_'))
  .forEach(k => localStorage.removeItem(k))

// 2. Clear the layout
localStorage.removeItem('gridLayout')
localStorage.removeItem('psweb_cache_layout')

// 3. Clear any saved card settings
Object.keys(localStorage)
  .filter(k => k.includes('event-stream') || k.includes('card_settings'))
  .forEach(k => localStorage.removeItem(k))

// 4. Hard reload
location.reload()
```

## After Switching

Once you have the new component loaded, you'll immediately notice:

✅ **Time range dropdown** - Select 5m, 15m, 30m, 1h, 4h, 24h
✅ **Advanced filters** - Separate inputs for category, severity, source, user, session
✅ **Sortable columns** - Click any column header to sort
✅ **Loading indicator** - Shows when fetching data
✅ **Better performance** - Reads from file, not memory buffer
✅ **Enhanced format** - Shows Source, Activity, Progress, Runspace columns

The difference will be immediately obvious!
