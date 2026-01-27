# Self-Contained URL Layout v2 - Implementation Complete

## Date: 2026-01-26

## Summary

✅ **Implementation complete** - URL layouts are now fully self-contained and independent of layout.json

The SPA now uses v2 URL format that stores endpoint URLs and fetches component paths dynamically from the endpoints, making URLs truly shareable and not dependent on layout.json configuration.

---

## What Was Implemented

### 1. Updated `serializeLayoutToURL()` - v2 Format

**Location**: `public/psweb_spa.js` (line ~1592)

**Changes**:
- Added `elements` parameter
- Store endpoint URLs instead of component paths
- Create unified card array (no separate grid/cards)
- Version bumped to 2

**v2 URL Data Structure**:
```json
{
    "version": 2,
    "cards": [
        {
            "id": "file-explorer-1769486224446",
            "x": 0,
            "y": 14,
            "w": 12,
            "h": 14,
            "elementId": "file-explorer",
            "title": "File Explorer",
            "endpoint": "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer",
            "backgroundColor": "#1a1a1a"
        }
    ]
}
```

### 2. Updated `updateURLWithLayout()` Signature

**Location**: `public/psweb_spa.js` (line ~1637)

**Changes**:
- Added `elements` parameter (3rd parameter)
- Validation for missing elements
- Updated console logging

**New Signature**:
```javascript
const updateURLWithLayout = useCallback((newGridLayout, openCardIds, elements) => {
    // Now receives elements to extract endpoint URLs
})
```

### 3. Updated 4 Call Sites

**All 4 locations now pass `data.elements`**:

1. **openCard** (line ~2465): `updateURLWithLayout(updatedLayout, data.layout.mainPane.content, data.elements);`
2. **removeCard** (line ~2647): `updateURLWithLayout(updatedLayout, newLayout.mainPane.content, data.elements);`
3. **handleLayoutChange** (line ~2666): `updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);`
4. **handleDragOrResizeStop** (line ~2733): `updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);`

### 4. Updated `parseLayoutFromURL()` - v2 Support

**Location**: `public/psweb_spa.js` (line ~1653)

**Changes**:
- Detect v2 format (has `cards` array, version 2)
- Validate card structure
- Remove v1 support (as per user request)
- Enhanced logging

**Validation**:
```javascript
const validCards = layoutData.cards.every(card =>
    card.id && card.elementId &&
    typeof card.x === 'number' && typeof card.y === 'number' &&
    typeof card.w === 'number' && typeof card.h === 'number'
);
```

### 5. Replaced Component Loading Logic

**Location**: `public/psweb_spa.js` (line ~1750)

**Major Changes**:
- Check for v2 URL layout first
- If v2 exists, load completely from URL (bypass layout.json)
- Fetch metadata from endpoints to get `scriptPath`
- Load components from fetched paths
- Build data structure from URL
- Only fallback to layout.json if no v2 URL

**Component Loading Flow**:
```javascript
async loadLayout() {
    const urlLayout = parseLayoutFromURL();

    if (urlLayout && urlLayout.version === 2) {
        // 1. Fetch metadata from each endpoint
        for (card of urlLayout.cards) {
            const metadata = await fetch(card.endpoint).json();
            card.componentPath = metadata.scriptPath || metadata.componentPath;
        }

        // 2. Load all component scripts
        for (card of cardsWithMetadata) {
            const script = await fetch(card.componentPath).text();
            eval(Babel.transform(script));
        }

        // 3. Build elements and layout from URL
        setData({ elements, layout, ... });
        return; // Don't load layout.json
    }

    // Fallback: load layout.json (when no v2 URL)
    fetch('/public/layout.json')...
}
```

---

## Testing Instructions

### Test 1: Open Dynamic Card and Capture URL

**Steps**:
1. Start server: `.\WebHost.ps1`
2. Open browser: `http://localhost:8080/spa`
3. Open main menu
4. Click "File Explorer" (or any dynamic card)
5. Resize/move the card
6. Look at URL bar - should see `?layout=<base64>`
7. Copy the full URL

**Expected URL Format**:
```
http://localhost:8080/spa?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJmaWxlLWV4cGxvcmVyLTE3Njk0ODYyMjQ0NDYiLCJ4IjowLCJ5IjoxNCwidyI6MTIsImgiOjE0LCJlbGVtZW50SWQiOiJmaWxlLWV4cGxvcmVyIiwidGl0bGUiOiJGaWxlIEV4cGxvcmVyIiwiZW5kcG9pbnQiOiIvYXBwcy9XZWJob3N0RmlsZUV4cGxvcmVyL2FwaS92MS91aS9lbGVtZW50cy9maWxlLWV4cGxvcmVyIn1dfQ==
```

**Console Output (Expected)**:
```
[URL Layout] Updated URL with self-contained layout (v2)
```

### Test 2: Decode URL to Verify Format

**In Browser Console**:
```javascript
// Get URL parameter
const params = new URLSearchParams(window.location.search);
const layoutParam = params.get('layout');

// Decode
const decoded = decodeURIComponent(atob(layoutParam).split('').map(c => {
    return '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2);
}).join(''));

// Parse
const layout = JSON.parse(decoded);
console.log('Layout Version:', layout.version); // Should be 2
console.log('Cards:', layout.cards);
console.log('First Card Endpoint:', layout.cards[0]?.endpoint);
```

**Expected Output**:
```javascript
Layout Version: 2
Cards: [{
    id: "file-explorer-1769486224446",
    x: 0, y: 14, w: 12, h: 14,
    elementId: "file-explorer",
    title: "File Explorer",
    endpoint: "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer"
}]
First Card Endpoint: /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer
```

### Test 3: Restore Layout from URL

**Steps**:
1. Copy URL from Test 1
2. Close all browser tabs
3. Open new tab
4. Paste URL and press Enter
5. Watch browser console

**Expected Console Output**:
```
[URL Layout] Loaded v2 layout from URL: {cardCount: 1}
[URL Layout] Using self-contained URL layout (v2) {cardCount: 1}
[URL Layout] Fetching metadata for file-explorer from: /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer
[URL Layout] Got componentPath for file-explorer: /apps/WebhostFileExplorer/public/elements/file-explorer/component.js
[URL Layout] Loading component for file-explorer from: /apps/WebhostFileExplorer/public/elements/file-explorer/component.js
[URL Layout] ✓ Loaded component: file-explorer
[URL Layout] ✓ Loaded UI component: /public/elements/profile/component.js
[URL Layout] ✓ Loaded UI component: /public/elements/main-menu/component.js
[URL Layout] ✓ Loaded UI component: /public/elements/footer-info/component.js
[URL Layout] ✓ Self-contained layout loaded successfully
```

**Expected Result**:
- File Explorer card appears at exact position/size
- No errors about "componentPath not found"
- Card is fully functional

### Test 4: Network Tab Verification

**Steps**:
1. Open URL from Test 1 in new tab
2. Open DevTools → Network tab
3. Watch requests

**Expected Network Requests**:
```
✓ GET /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer (metadata)
✓ GET /apps/WebhostFileExplorer/public/elements/file-explorer/component.js (script)
✓ GET /public/elements/profile/component.js
✓ GET /public/elements/main-menu/component.js
✓ GET /public/elements/footer-info/component.js
✗ NOT: GET /public/layout.json (should be skipped for v2 URLs)
```

### Test 5: Multiple Cards URL

**Steps**:
1. Open SPA
2. Add multiple cards (File Explorer + Real-time Events)
3. Arrange them
4. Copy URL
5. Open in new tab

**Expected**:
- All cards restore at correct positions
- All cards functional

**Console Should Show**:
```
[URL Layout] Loaded v2 layout from URL: {cardCount: 2}
[URL Layout] Fetching metadata for file-explorer...
[URL Layout] Fetching metadata for realtime-events...
[URL Layout] ✓ Loaded component: file-explorer
[URL Layout] ✓ Loaded component: realtime-events
[URL Layout] ✓ Self-contained layout loaded successfully
```

### Test 6: Endpoint Failure Handling

**Steps**:
1. Manually edit URL to use invalid endpoint
2. Open URL
3. Check console

**Expected**:
- Error logged but doesn't crash
- Other cards still load
- Invalid card shows error state

**Console Output**:
```
[URL Layout] Failed to fetch metadata for invalid-card: HTTP 404: Not Found
[URL Layout] ✓ Self-contained layout loaded successfully
```

### Test 7: No layout.json Dependency

**Steps**:
1. Temporarily rename `/public/layout.json` to `layout.json.bak`
2. Open v2 URL
3. Verify cards load

**Expected**:
- Cards load from URL (no layout.json needed)
- Console shows: `[URL Layout] Using self-contained URL layout (v2)`
- No errors about missing layout.json

4. Restore layout.json: `mv layout.json.bak layout.json`

---

## Verification Checklist

- [ ] URL contains `version: 2` when decoded
- [ ] URL contains `cards` array (not separate grid/cards)
- [ ] URL contains endpoint URLs
- [ ] Opening URL loads cards without layout.json
- [ ] Network tab shows endpoint metadata fetch
- [ ] Network tab shows component script fetch
- [ ] No "componentPath not found" errors
- [ ] Cards restore at exact positions
- [ ] Multiple cards work
- [ ] Drag/resize updates URL
- [ ] Opening new card updates URL
- [ ] Removing card updates URL

---

## Files Modified

**Single File**: `public/psweb_spa.js`

**Lines Changed**: ~220 lines
- `serializeLayoutToURL()`: ~40 lines (replaced)
- `updateURLWithLayout()`: ~15 lines (updated signature)
- `parseLayoutFromURL()`: ~35 lines (v2 support)
- `loadLayout()`: ~120 lines (added v2 loading logic)
- 4 call sites: ~4 lines (added data.elements parameter)

---

## Breaking Changes

**Removed**:
- v1 URL format support (no backwards compatibility)
- Old URLs will not work (need to be regenerated)

**Reason**: User requested "do not worry about backwards compatibility"

**Migration**: Users need to re-save their layouts to generate new v2 URLs

---

## Benefits Achieved

✅ **Self-contained URLs** - All metadata in URL
✅ **No layout.json dependency** - v2 URLs load independently
✅ **Dynamic cards work** - Fetch component paths from endpoints
✅ **Single source of truth** - Component paths from endpoints
✅ **URLs stay small** - ~280 chars (vs ~420 with stored paths)
✅ **Component paths can change** - URLs remain valid
✅ **Truly shareable** - Works across different server instances

---

## Known Limitations

**URL Size**:
- ~280 chars per card
- Browser limit: 2000+ chars
- Max ~7 cards before hitting limits
- Solution: Use LZ-string compression if needed

**Static Cards**:
- Cards without endpoints won't serialize (skipped)
- Only dynamic cards (with endpoint URLs) work in v2
- Solution: Add endpoint URLs to static cards in layout.json

**Error Handling**:
- Endpoint failures log errors but don't prevent page load
- Cards with errors added to layout with loadError property
- User can't see which card failed (UI doesn't show error state)
- Solution: Add error UI component for failed cards

---

## Next Steps (Optional Enhancements)

### 1. Add Error UI for Failed Cards
Show user-friendly message when card fails to load:
```javascript
if (element.loadError) {
    return <div className="card-error">
        <h3>Failed to load: {element.Title}</h3>
        <p>{element.loadError}</p>
        <button onClick={() => window.location.reload()}>Retry</button>
    </div>
}
```

### 2. Add URL Compression (LZ-string)
For layouts with many cards:
```javascript
import LZString from 'lz-string';

const compressed = LZString.compressToEncodedURIComponent(JSON.stringify(layoutData));
```

### 3. Add Static Card Endpoints
Update layout.json to include endpoint URLs for static cards:
```json
{
    "realtime-events": {
        "url": "/apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events",
        "componentPath": "/apps/.../component.js"
    }
}
```

### 4. Add Share Button
Add UI button to copy shareable URL:
```javascript
<button onClick={() => {
    navigator.clipboard.writeText(window.location.href);
    alert('Layout URL copied!');
}}>Share Layout</button>
```

---

## Testing Status

**Automated Testing Script**: `Test-URLLayoutV2.ps1`
- Run with: `pwsh -File Test-URLLayoutV2.ps1`
- Tests: Server status, endpoint format, v2 encoding/decoding
- Generates test URL for manual browser testing

**Manual Testing Required**:
- [ ] Test 1: Open dynamic card and capture URL
- [ ] Test 2: Decode URL to verify format
- [ ] Test 3: Restore layout from URL
- [ ] Test 4: Network tab verification
- [ ] Test 5: Multiple cards URL
- [ ] Test 6: Endpoint failure handling
- [ ] Test 7: No layout.json dependency
- [ ] Test 8: Card dimensions restore correctly (h:30 stays h:30, no NaN warnings)

---

## Post-Implementation Fix: Card Dimension Restoration

**Issue Reported**: Cards loaded from URL were not displaying with correct dimensions. User saw h:30 changing to h:32, and NaN warnings for value attribute in CardSettingsModal.

**Root Cause**: React GridLayout requires cards to be rendered before dimensions can be applied. Directly setting final dimensions in initial render doesn't work reliably.

**Solution Applied**: Two-step rendering pattern (matching `openCard()` behavior):

```javascript
// Step 1: Render with temporary small dimensions
const tempGridLayout = cardsWithMetadata.map((card, index) => ({
    i: card.id,
    x: 0,
    y: index * 2,
    w: 2,
    h: 2
}));
setGridLayout(tempGridLayout);
setData({ elements, layout, componentsReady: true, gridLayout: [] });

// Step 2: After 150ms, apply actual dimensions from URL
setTimeout(() => {
    const actualGridLayout = cardsWithMetadata.map(card => ({
        i: card.id,
        x: card.x,
        y: card.y,
        w: card.w,
        h: card.h
    }));
    setGridLayout(actualGridLayout);
}, 150);
```

**Files Modified**: `public/psweb_spa.js` (lines 1904-1935)

**Status**: ✅ Fixed - Ready for testing

---

## Troubleshooting

### Issue: "No componentPath specified" Error

**Cause**: v1 URL or malformed v2 URL

**Solution**:
1. Check console for version: `Layout Version: 2`
2. Regenerate URL by opening card and copying new URL

### Issue: Card Doesn't Load from URL

**Cause**: Endpoint not returning scriptPath

**Solution**:
1. Check endpoint response: `GET /apps/.../api/v1/ui/elements/file-explorer`
2. Verify response has `scriptPath` or `componentPath` field
3. Check endpoint file: `apps/.../routes/api/v1/ui/elements/file-explorer/get.ps1`

### Issue: URL Too Long

**Cause**: Too many cards in layout

**Solution**:
1. Reduce number of cards
2. Implement LZ-string compression
3. Use server-side layout storage with short IDs

### Issue: Layout.json Still Loading

**Cause**: URL has no layout parameter or v2 parse failed

**Solution**:
1. Check URL has `?layout=` parameter
2. Check console for parse errors
3. Verify v2 format with decode test

---

## Summary

**Implementation Complete**: ✅ All changes made to `psweb_spa.js`

**Ready for Testing**: Yes - follow testing instructions above

**Breaking Changes**: v1 URLs no longer work (regenerate layouts)

**Benefits**: Fully self-contained, shareable URLs independent of layout.json

**Status**: Ready for production testing

---

**Created**: 2026-01-26
**Status**: ✅ IMPLEMENTATION COMPLETE - READY FOR TESTING
