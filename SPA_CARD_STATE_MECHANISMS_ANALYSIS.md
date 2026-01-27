# SPA Card State Mechanisms - Comprehensive Analysis

## Date: 2026-01-26

## Executive Summary

The PSWebHost SPA has **two separate but complementary mechanisms** for managing card state:

1. **URL Layout State** - Stores grid positions and card IDs (transient, shareable)
2. **Database Card Settings** - Stores size, position, and visual preferences (persistent, per-user)

These mechanisms work together with a **priority hierarchy**, but there's a critical issue with how dynamic elements are handled.

---

## 1. URL Layout State Mechanism

### Purpose
Create shareable, bookmarkable URLs that preserve the exact layout state.

### Data Format
```javascript
{
    "version": 1,
    "grid": [
        { "i": "card-id", "x": 0, "y": 0, "w": 12, "h": 14 }
    ],
    "cards": ["card-id-1", "card-id-2"]  // List of open cards
}
```

### Encoding
- JSON → `JSON.stringify()`
- Compressed → Custom base64 encoding with URL encoding
- URL Parameter → `?layout=<compressed-base64>`

### Update Triggers

**Function**: `updateURLWithLayout(newGridLayout, openCardIds)`

**Called When**:
1. **handleLayoutChange** - User drags/resizes cards (line 2434)
2. **handleDragOrResizeStop** - After drag/resize completes (line 2501)
3. **openCard** - After new card is added (line 2233)
4. **removeCard** - After card is removed (line 2415)

**Code**:
```javascript
const updateURLWithLayout = useCallback((newGridLayout, openCardIds) => {
    const compressed = serializeLayoutToURL(newGridLayout, openCardIds);
    if (compressed) {
        const url = new URL(window.location);
        url.searchParams.set('layout', compressed);
        window.history.replaceState({}, '', url);
        console.log('[URL Layout] Updated URL with current layout');
    }
}, []);
```

### Restoration Mechanism

**Function**: `parseLayoutFromURL()`

**Called When**: Page loads (in `loadLayout()` function)

**Process**:
1. Read `?layout=` parameter from URL
2. Decompress base64 → JSON
3. Validate structure (version, grid, cards)
4. Apply grid positions to override database/layout.json defaults
5. Restore open cards list

**Priority**: URL layout overrides database settings if both exist

**Code**:
```javascript
if (urlLayout && urlLayout.grid) {
    mainPaneLayout = mainPaneLayout.map(item => {
        const urlItem = urlLayout.grid.find(u => u.i === item.i);
        return urlItem ? { ...item, ...urlItem } : item;  // URL wins
    });
}
```

---

## 2. Database Card Settings Mechanism

### Purpose
Persist user preferences for card size, position, and appearance across sessions.

### Storage Location
Database table via `/spa/card_settings` endpoint

**Key Field**: `endpoint_guid` (element.url or element.Element_Id)

### Data Stored
```javascript
{
    "w": 12,              // Width (grid columns)
    "h": 14,              // Height (grid rows)
    "x": 0,               // X position (optional - calculated if not saved)
    "y": 0,               // Y position (optional - calculated if not saved)
    "backgroundColor": "#1a1a1a"  // Visual preference
}
```

### Save Mechanism

**Function**: `handleSaveCardSettings(newCardLayout)`

**Triggered By**:
1. **Card Settings Modal** - User clicks "Save" in settings dialog
2. **Drag/Resize Stop** - Automatic save after user interaction (line 2459)

**Save Process**:
```javascript
// 1. Extract endpoint_guid from element
const element = data.elements[newCardLayout.i];
const endpointGuid = element.url || element.Element_Id;

// 2. Prepare data
const layoutData = { w, h, x, y };
if (backgroundColor !== undefined) {
    layoutData.backgroundColor = backgroundColor;
}

// 3. POST to backend
await fetch('/spa/card_settings', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        endpoint_guid: endpointGuid,
        layout: layoutData
    })
});

// 4. Invalidate cache
CacheManager.invalidate(`card_settings_${endpointGuid}`);

// 5. Update URL with new layout
updateURLWithLayout(layout, data.layout.mainPane.content);
```

### Fetch Mechanism

**Function**: `fetchCardSettings(endpointGuid, skipCache)`

**Called When**:
1. Page load for each card (line 1761)
2. New card opened via `window.openCard()` (line 2172)
3. Background revalidation (stale-while-revalidate pattern)

**Caching Strategy**: Stale-While-Revalidate
- Fresh cache: < 10 seconds (return immediately)
- Stale cache: 10-30 seconds (return stale, revalidate in background)
- Expired: > 30 seconds (fetch fresh)

**Code**:
```javascript
const fetchCardSettings = async (endpointGuid, skipCache = false) => {
    // Check cache
    const cached = CacheManager.get(`card_settings_${endpointGuid}`);
    if (cached && cached.isFresh) return cached.data;

    if (cached && cached.isStale) {
        // Return stale, revalidate in background
        fetchCardSettings(endpointGuid, true);  // Background refresh
        return cached.data;
    }

    // Fetch from server
    const response = await fetch(`/spa/card_settings?id=${endpointGuid}`);
    // ... cache and return
};
```

---

## 3. Priority Hierarchy

When a card loads, settings are applied in this order (last wins):

```
1. defaultLayout (from layout.json)
   ↓ overridden by
2. specificLayout (from layout.json gridLayout[])
   ↓ overridden by
3. cardSettings (from database)
   ↓ overridden by
4. urlLayout (from URL ?layout= parameter)
```

**Code**:
```javascript
return {
    i: id,
    x: specificLayout?.x ?? (index % 4) * 3,
    y: specificLayout?.y ?? Math.floor(index / 4) * 2,
    w: cardSettings?.w ?? specificLayout?.w ?? defaultLayout.w,
    h: cardSettings?.h ?? specificLayout?.h ?? defaultLayout.h
};

// Then URL overrides:
if (urlLayout && urlLayout.grid) {
    mainPaneLayout = mainPaneLayout.map(item => {
        const urlItem = urlLayout.grid.find(u => u.i === item.i);
        return urlItem ? { ...item, ...urlItem } : item;
    });
}
```

---

## 4. Element Types and Loading

### Static Elements (layout.json)

**Definition**: Pre-configured in `/public/layout.json`

**Structure**:
```json
{
    "elements": {
        "realtime-events": {
            "Type": "Events",
            "Title": "Real-time Events",
            "componentPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js"
        }
    }
}
```

**Loading**: Component path is **explicitly defined** in layout.json

**Endpoint**: No endpoint - direct component path

### Dynamic Elements (via API)

**Definition**: Loaded dynamically via `window.openCard(url, title)`

**Process**:
1. Extract element ID from URL: `/api/v1/ui/elements/file-explorer` → `file-explorer`
2. Fetch metadata from endpoint (title, description, etc.)
3. Load component from `scriptPath` or `componentPath` returned by endpoint
4. Create dynamic card ID: `file-explorer-1769486224446` (ID + timestamp)

**Structure in Code**:
```javascript
const newElement = {
    Title: finalTitle,
    Element_Id: elementId,           // "file-explorer"
    url: elementUrl,                  // "/api/v1/ui/elements/file-explorer"
    id: cardId,                       // "file-explorer-1769486224446"
    backgroundColor: cardSettings?.backgroundColor,
    loadType: 'component'
};
```

**Endpoint GUID for Settings**:
```javascript
const endpointGuid = element.url || element.Element_Id;
// For dynamic cards: element.url = "/api/v1/ui/elements/file-explorer"
```

---

## 5. The "No componentPath" Error

### Error Message
```
❌ No componentPath specified for element: file-explorer-1769486224446
   Example: "componentPath": "/public/elements/file-explorer-1769486224446/component.js"
```

### Root Cause Analysis

**The Problem**: The SPA code is looking for `file-explorer-1769486224446` in `layout.json` elements:

```javascript
// Line 1715-1724
const element = initialData.elements[id];  // Looks for "file-explorer-1769486224446"
const componentPath = element?.componentPath;

if (!componentPath) {
    console.error(`❌ No componentPath specified for element: ${id}`);
    return Promise.resolve(); // Skip this component
}
```

**Why It Fails**:
- Dynamic card ID: `file-explorer-1769486224446` (with timestamp)
- layout.json only has static IDs: `realtime-events`, `server-heatmap`, etc.
- No entry for `file-explorer-1769486224446` exists in layout.json
- Therefore: `element?.componentPath` is `undefined`

### The Issue

**Two loading paths exist**:

1. **Initial page load** (line 1711-1744): Loads components from layout.json
   - Expects `componentPath` in `elements[id]`
   - Works for static elements
   - **Fails for dynamic cards restored from URL**

2. **Dynamic card opening** (line 2148-2241): Uses `window.openCard()`
   - Fetches component from API endpoint
   - Uses `loadComponentScript()` function
   - Works correctly

**The Gap**: When URL contains a dynamic card (from previous session), the page load path tries to load it from layout.json, which doesn't exist.

---

## 6. URL Metadata Problem

### Current URL Structure

**What's stored**:
```
?layout=<base64-compressed-json>
```

**JSON Content**:
```json
{
    "version": 1,
    "grid": [{"i": "file-explorer-1769486224446", "x": 0, "y": 14, "w": 12, "h": 14}],
    "cards": ["realtime-events-1769486221470", "file-explorer-1769486224446"]
}
```

### What's Missing

**Problem**: No metadata about card source/endpoint

**Need**:
```json
{
    "version": 2,  // Bump version
    "grid": [...],
    "cards": ["realtime-events-1769486221470", "file-explorer-1769486224446"],
    "metadata": {
        "file-explorer-1769486224446": {
            "endpoint": "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer",
            "type": "dynamic"
        },
        "realtime-events-1769486221470": {
            "type": "static",
            "elementId": "realtime-events"
        }
    }
}
```

### Why This Matters

**Without metadata**:
- Can't reload dynamic cards from URL
- Can't distinguish static vs dynamic cards
- Can't fetch component when restoring state

**With metadata**:
- Know which endpoint to call for dynamic cards
- Can properly restore card state
- Can fetch component script before rendering

---

## 7. Card Settings Save Validation Issues

### Current Save Flow

**On Drag/Resize Stop** (line 2459-2514):
```javascript
const handleDragOrResizeStop = async (layout, oldItem, newItem) => {
    // 1. Find element
    const cardElement = data.elements[newItem.i];
    const endpointGuid = cardElement?.url || cardElement?.Element_Id || newItem.i;

    // 2. Save to backend
    await fetch('/spa/card_settings', {
        method: 'POST',
        body: JSON.stringify({
            endpoint_guid: endpointGuid,
            layout: { w: newItem.w, h: newItem.h, x: newItem.x, y: newItem.y }
        })
    });

    // 3. Update URL
    updateURLWithLayout(layout, data.layout.mainPane.content);
};
```

### Validation Gaps

**❌ No validation for**:
1. **Save success**: Response status checked but not awaited properly
2. **Data consistency**: No verification that saved === requested
3. **Endpoint existence**: `/spa/card_settings` endpoint might not exist
4. **Error handling**: Errors logged but user not notified
5. **Race conditions**: Multiple rapid saves could conflict

### Recommended Validation

**Add validation**:
```javascript
// After save
if (response.ok) {
    const saved = await response.json();

    // Verify saved data matches request
    if (saved.w !== newItem.w || saved.h !== newItem.h) {
        console.warn('Saved card settings do not match requested', {
            requested: newItem,
            saved: saved
        });
        // Optionally show user notification
    }

    // Invalidate cache AFTER successful save
    CacheManager.invalidate(`card_settings_${endpointGuid}`);
} else {
    // Show user-friendly error
    console.error('Failed to save card settings:', await response.text());
    // Optionally revert layout change
}
```

---

## 8. Recommended Solutions

### Solution 1: Add Metadata to URL Layout (Recommended)

**Change `serializeLayoutToURL()` to include metadata**:

```javascript
const serializeLayoutToURL = (gridLayout, openCards, elements) => {
    const metadata = {};

    openCards.forEach(cardId => {
        const element = elements[cardId];
        if (element) {
            if (element.url) {
                // Dynamic card
                metadata[cardId] = {
                    type: 'dynamic',
                    endpoint: element.url,
                    elementId: element.Element_Id
                };
            } else {
                // Static card
                metadata[cardId] = {
                    type: 'static',
                    elementId: cardId.split('-')[0]  // Extract base ID
                };
            }
        }
    });

    const layoutData = {
        version: 2,  // Bump version
        grid: gridLayout.map(item => ({
            i: item.i,
            x: item.x,
            y: item.y,
            w: item.w,
            h: item.h
        })),
        cards: openCards,
        metadata: metadata  // NEW
    };

    return compressLayout(layoutData);
};
```

**Update `parseLayoutFromURL()` to use metadata**:

```javascript
const parseLayoutFromURL = () => {
    const layoutData = decompressLayout(layoutParam);

    // Handle both v1 (no metadata) and v2 (with metadata)
    if (layoutData.version === 2 && layoutData.metadata) {
        // Use metadata to reload dynamic cards
        return layoutData;
    } else {
        // Legacy format - best effort
        console.warn('[URL Layout] Legacy format detected, dynamic cards may not load');
        return layoutData;
    }
};
```

**Update component loading to use metadata**:

```javascript
const componentPromises = uniqueCardIds
    .filter(id => id && id !== 'user-card' && id !== 'title')
    .map(id => {
        const element = initialData.elements[id];

        // Check URL metadata first (for dynamic cards)
        const cardMetadata = urlLayout?.metadata?.[id];
        if (cardMetadata && cardMetadata.type === 'dynamic') {
            // Load dynamic card via endpoint
            return window.openCard(cardMetadata.endpoint, cardMetadata.elementId);
        }

        // Otherwise use componentPath from layout.json (static cards)
        const componentPath = element?.componentPath;
        if (!componentPath) {
            console.error(`❌ No componentPath for element: ${id}`);
            return Promise.resolve();
        }

        // Load component
        return fetch(componentPath).then(/* ... */);
    });
```

### Solution 2: Improve Error Handling

**Add user-friendly error notifications**:

```javascript
// In handleDragOrResizeStop
if (!response.ok) {
    const errorText = await response.text();
    console.error('Failed to save card settings:', errorText);

    // Show notification to user
    window.showNotification?.({
        type: 'error',
        message: 'Failed to save card position',
        duration: 3000
    });

    // Optionally revert layout change
    setGridLayout(prevLayout);
}
```

### Solution 3: Add Endpoint Validation

**Verify endpoint exists before saving**:

```javascript
const endpointGuid = cardElement?.url || cardElement?.Element_Id || newItem.i;

if (!endpointGuid) {
    console.error('handleDragOrResizeStop: Could not determine endpoint_guid', {
        cardId: newItem.i,
        cardElement
    });
    // Don't attempt save if we don't know where to save
    return;
}
```

---

## 9. Testing Recommendations

### Test 1: URL Layout with Dynamic Cards

**Steps**:
1. Open dynamic card (file-explorer)
2. Resize/move it
3. Copy URL
4. Open URL in new tab
5. **Expected**: Card loads at saved position
6. **Current**: Error - "No componentPath specified"

### Test 2: Card Settings Save

**Steps**:
1. Open card settings modal
2. Change size (w, h)
3. Click save
4. Open browser DevTools → Network
5. Verify POST to `/spa/card_settings`
6. Check response status and body
7. **Expected**: 200 OK with saved settings
8. **Current**: Unknown - need to test

### Test 3: Settings Persistence

**Steps**:
1. Resize card
2. Wait for auto-save (check console for "Card settings saved")
3. Refresh page (without URL layout)
4. **Expected**: Card loads at new size
5. **Current**: Should work if save succeeded

### Test 4: URL vs Database Priority

**Steps**:
1. Save card at position x=0, y=0, w=6, h=6 (database)
2. Create URL with position x=6, y=6, w=12, h=12
3. Open URL
4. **Expected**: Card at URL position (x=6, y=6, w=12, h=12)
5. **Current**: Should work based on priority code

---

## 10. Summary

### Current State

**✅ Working**:
- URL layout for static cards
- Database settings save/load
- Priority hierarchy
- Drag/resize auto-save

**❌ Broken**:
- URL layout for dynamic cards (no metadata)
- Component loading from URL state
- Error handling/user feedback

**⚠ Needs Validation**:
- Save success verification
- Endpoint existence checking
- Race condition handling

### Recommended Implementation Order

1. **Add metadata to URL layout** (v2 format)
2. **Update component loading** to use metadata
3. **Add save validation** (verify response)
4. **Add error notifications** (user feedback)
5. **Add endpoint validation** (prevent save failures)

### Impact

**Without fixes**:
- Users can't share dynamic card layouts
- Page refresh loses dynamic cards
- Silent save failures
- Poor error UX

**With fixes**:
- Full shareable/bookmarkable layouts
- Reliable state restoration
- Better error handling
- Improved user experience

---

**Created**: 2026-01-26
**Status**: Analysis Complete - Ready for Implementation
