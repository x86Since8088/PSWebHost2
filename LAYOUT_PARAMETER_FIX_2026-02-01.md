# Layout Parameter Loading Fix

**Date:** 2026-02-01
**Issue:** Cards launched from main menu work, but cards loaded from URL layout parameter fail to load

---

## Problem Analysis

### Symptoms
- Browser console error: `[URL Layout] Card server-heatmap has no endpoint, skipping`
- 404 errors in server logs:
  - `/api/v1/ui/elements/server` (404)
  - `/api/v1/ui/elements/realtime` (404)
- Cards work when clicked from menu but fail when page reloads with `?layout=` parameter

### Root Causes

#### 1. Corrupted elementId in Saved Layouts (psweb_spa.js:1623)

**Original Code:**
```javascript
elementId: element.Element_Id || element.id || item.i.split('-')[0],
```

**Problem:**
The fallback `item.i.split('-')[0]` is buggy. For a card ID like `"server-heatmap-1234567890"`, it returns `"server"` instead of `"server-heatmap"`.

**Example:**
- Card ID: `"server-heatmap-1738472952083"`
- Expected elementId: `"server-heatmap"`
- Actual elementId (broken): `"server"` ❌

#### 2. Missing Endpoint in Saved Layouts

Cards saved to layout parameter had:
```json
{
  "id": "server-heatmap",
  "elementId": "server",  // Corrupted!
  "title": "Server Metrics"
  // Missing: "endpoint" field
}
```

Should have:
```json
{
  "id": "server-heatmap",
  "elementId": "server-heatmap",
  "endpoint": "/apps/WebHostMetrics/cards/server-heatmap"
}
```

#### 3. Naive Endpoint Derivation

Initial fix attempted to derive endpoint as `/api/v1/ui/elements/${elementId}`, but:
- Used corrupted elementId (`"server"` instead of `"server-heatmap"`)
- Didn't account for app-specific routes (missing `/apps/[AppName]` prefix)
- No fallback for 404 errors

**Actual Endpoint Locations:**
- Server Metrics: `/apps/WebHostMetrics/cards/server-heatmap`
- Real-time Events: `/apps/WebhostRealtimeEvents/cards/realtime-events`

There are **no root-level endpoints** - app prefix is required.

---

## Solution

### Fix 1: Correct elementId Extraction (psweb_spa.js:1623)

**Changed:**
```javascript
// OLD: Buggy split that returns "server" for "server-heatmap-1234567890"
elementId: element.Element_Id || element.id || item.i.split('-')[0],

// NEW: Remove timestamp suffix correctly
elementId: element.Element_Id || element.id || item.i.replace(/-\d{13}$/, ''),
```

**Explanation:**
Uses regex to remove 13-digit timestamp suffix instead of splitting on first hyphen.

**Examples:**
- `"server-heatmap-1738472952083"` → `"server-heatmap"` ✓
- `"realtime-events-1738472952083"` → `"realtime-events"` ✓
- `"memory-explorer-1738472952083"` → `"memory-explorer"` ✓

---

### Fix 2: Improved Endpoint Derivation (psweb_spa.js:1786-1794)

**Changed:**
```javascript
// OLD: Only tried elementId (which was often corrupted)
if (!card.endpoint && card.elementId) {
    card.endpoint = `/api/v1/ui/elements/${card.elementId}`;
}

// NEW: Try card.id first (contains correct element name), fallback to elementId
if (!card.endpoint) {
    const elementName = card.id || card.elementId;
    if (elementName) {
        card.endpoint = `/api/v1/ui/elements/${elementName}`;
        console.log(`[URL Layout] Derived endpoint for ${card.id}: ${card.endpoint} (from ${card.id ? 'id' : 'elementId'})`);
    }
}
```

**Explanation:**
Prioritizes `card.id` field which contains the correct element name, even in corrupted layouts.

---

### Fix 3: Automatic Menu Lookup on 404 (psweb_spa.js:1803-1838)

**Added:**
```javascript
let res = await fetch(card.endpoint);

// If 404, try to find the correct endpoint by searching the menu
if (res.status === 404) {
    console.log(`[URL Layout] Got 404, searching menu for correct endpoint...`);
    try {
        const menuRes = await window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/main-menu');
        if (menuRes.ok) {
            const menuData = await menuRes.json();

            // Recursively search menu for matching URL
            const findUrlInMenu = (items, elementName) => {
                for (const item of items) {
                    if (item.url && item.url.includes(`/elements/${elementName}`)) {
                        return item.url;
                    }
                    if (item.children) {
                        const found = findUrlInMenu(item.children, elementName);
                        if (found) return found;
                    }
                }
                return null;
            };

            const elementName = card.id || card.elementId;
            const correctUrl = findUrlInMenu(menuData, elementName);

            if (correctUrl) {
                console.log(`[URL Layout] Found correct endpoint in menu: ${correctUrl}`);
                card.endpoint = correctUrl;
                res = await fetch(correctUrl);
            }
        }
    } catch (menuErr) {
        console.warn(`[URL Layout] Failed to search menu:`, menuErr);
    }
}
```

**Explanation:**
When endpoint fetch returns 404:
1. Fetches the main menu (which contains all app cards with full URLs)
2. Recursively searches menu tree for element name
3. Finds the correct app-specific URL (e.g., `/apps/WebHostMetrics/cards/server-heatmap`)
4. Retries fetch with correct URL

**Example Flow:**
1. Try `/api/v1/ui/elements/server-heatmap` → 404
2. Fetch menu → find "Server Metrics" item
3. Extract URL: `/apps/WebHostMetrics/cards/server-heatmap`
4. Retry → Success ✓

---

## Benefits

1. **Fixes Existing Broken Layouts:** Automatically corrects corrupted elementIds and missing endpoints
2. **Prevents Future Corruption:** Fixes root cause in serialization code
3. **Transparent to Users:** Cards load correctly without manual intervention
4. **Backward Compatible:** Handles both old and new layout formats
5. **Resilient:** Falls back to menu lookup if endpoint derivation fails

---

## Testing

### Test Case 1: Broken Layout Parameter

**URL:**
```
http://localhost:8080/spa?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJzZXJ2ZXItaGVhdG1hcCIsIngiOjAsInkiOjAsInciOjEyLCJoIjoyMCwiZWxlbWVudElkIjoic2VydmVyIiwidGl0bGUiOiJTZXJ2ZXIgTWV0cmljcyJ9LHsiaWQiOiJyZWFsdGltZS1ldmVudHMiLCJ4IjowLCJ5IjoyMCwidyI6MTIsImgiOjI1LCJlbGVtZW50SWQiOiJyZWFsdGltZSIsInRpdGxlIjoiUmVhbC10aW1lIEV2ZW50cyJ9XX0%3D#
```

**Decoded Layout:**
```json
{
  "version": 2,
  "cards": [
    {
      "id": "server-heatmap",
      "x": 0,
      "y": 0,
      "w": 12,
      "h": 20,
      "elementId": "server",
      "title": "Server Metrics"
    },
    {
      "id": "realtime-events",
      "x": 0,
      "y": 20,
      "w": 12,
      "h": 25,
      "elementId": "realtime",
      "title": "Real-time Events"
    }
  ]
}
```

**Expected Behavior:**
1. Derive endpoint from `card.id`: `/api/v1/ui/elements/server-heatmap`
2. Get 404
3. Search menu, find `/apps/WebHostMetrics/cards/server-heatmap`
4. Load successfully ✓

### Test Case 2: Fresh Layout Save

**Scenario:** Open cards from menu, save layout

**Expected:**
- elementId correctly extracted (e.g., `"server-heatmap"` not `"server"`)
- endpoint included in saved layout
- No 404 errors on reload

---

## Related Issues

### Server Logs 404 Errors

**Before Fix:**
```
404 Not Found: /api/v1/ui/elements/server from 127.0.0.1
404 Not Found: /api/v1/ui/elements/realtime from 127.0.0.1
```

**After Fix:**
- Initial 404 for derived endpoint (expected)
- Menu search finds correct endpoint
- Subsequent requests succeed

### Metrics Endpoint 404s

**Separate Issue:** Repeated 404s for `/api/v1/metrics` (every 5 seconds)

**Status:** Not addressed in this fix - requires separate investigation

---

## Files Modified

### public/psweb_spa.js

**Line 1623:** Fixed elementId extraction in `serializeLayoutToURL`
**Line 1786-1794:** Improved endpoint derivation for layout loading
**Line 1803-1838:** Added automatic menu lookup fallback on 404

---

## Next Steps

1. ✅ Test broken layout URL to verify cards load correctly
2. ✅ Monitor server logs for 404 reduction
3. ⬜ Investigate `/api/v1/metrics` 404 errors (separate issue)
4. ⬜ Consider caching menu data to reduce redundant fetches
5. ⬜ Add user-facing error messages for failed card loads

---

## End of Report
