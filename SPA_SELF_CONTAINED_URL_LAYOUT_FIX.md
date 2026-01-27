# Self-Contained URL Layout - Implementation Fix

## Date: 2026-01-26

## Problem Statement

**Current Issue**: URL layouts depend on layout.json, causing dynamic cards to fail on restore.

**Root Cause**: When restoring layout from URL, the code looks up `elements[cardId]` in layout.json to get `componentPath`. Dynamic cards don't exist in layout.json → component fails to load.

**User Requirement**: URL layout must be **completely self-contained** and not rely on layout.json.

---

## Solution: Self-Contained URL Layout v2

### New URL Layout Structure

**Store everything needed to reconstruct the card**:

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
            "type": "dynamic",
            "endpoint": "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer",
            "componentPath": "/apps/WebhostFileExplorer/public/elements/file-explorer/component.js",
            "backgroundColor": "#1a1a1a"
        },
        {
            "id": "realtime-events-1769486221470",
            "x": 0,
            "y": 0,
            "w": 12,
            "h": 14,
            "elementId": "realtime-events",
            "title": "Real-time Events",
            "type": "static",
            "componentPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js"
        }
    ]
}
```

**Key Differences from v1**:
- ✅ No separate `grid` and `cards` arrays - unified
- ✅ Every card has complete metadata
- ✅ Component path included directly
- ✅ No lookup required in layout.json
- ✅ Can reconstruct any card from URL alone

---

## Implementation Changes

### Change 1: Update `serializeLayoutToURL()`

**File**: `public/psweb_spa.js`

**Current** (lines 1592-1605):
```javascript
const serializeLayoutToURL = (gridLayout, openCards) => {
    const layoutData = {
        version: 1,
        grid: gridLayout.map(item => ({
            i: item.i,
            x: item.x,
            y: item.y,
            w: item.w,
            h: item.h
        })),
        cards: openCards
    };
    return compressLayout(layoutData);
};
```

**New**:
```javascript
const serializeLayoutToURL = (gridLayout, openCardIds, elements) => {
    // Build complete card data with all metadata
    const cardsData = gridLayout.map(item => {
        const element = elements[item.i];

        if (!element) {
            console.warn(`Element not found for card: ${item.i}`);
            return null;
        }

        // Base card data with position/size
        const cardData = {
            id: item.i,
            x: item.x,
            y: item.y,
            w: item.w,
            h: item.h,
            elementId: element.Element_Id || element.id || item.i,
            title: element.Title || 'Untitled'
        };

        // Add type-specific metadata
        if (element.url) {
            // Dynamic card (loaded via window.openCard)
            cardData.type = 'dynamic';
            cardData.endpoint = element.url;

            // Get componentPath from element or construct from endpoint
            if (element.componentPath) {
                cardData.componentPath = element.componentPath;
            } else if (element.url.includes('/api/v1/ui/elements/')) {
                // Fetch componentPath from endpoint during save
                // For now, store endpoint - will be fetched on restore
                cardData.fetchComponentPath = true;
            }
        } else if (element.componentPath) {
            // Static card with known componentPath
            cardData.type = 'static';
            cardData.componentPath = element.componentPath;
        } else {
            // Fallback - special cards like user-card, title
            cardData.type = 'special';
        }

        // Add visual preferences
        if (element.backgroundColor) {
            cardData.backgroundColor = element.backgroundColor;
        }

        return cardData;
    }).filter(Boolean); // Remove nulls

    const layoutData = {
        version: 2,
        cards: cardsData
    };

    return compressLayout(layoutData);
};
```

**Update all calls to `serializeLayoutToURL`**:
```javascript
// OLD: serializeLayoutToURL(newGridLayout, openCardIds)
// NEW: serializeLayoutToURL(newGridLayout, openCardIds, data.elements)
```

### Change 2: Update `updateURLWithLayout()`

**File**: `public/psweb_spa.js`

**Current** (lines 1607-1621):
```javascript
const updateURLWithLayout = useCallback((newGridLayout, openCardIds) => {
    // ...
    const compressed = serializeLayoutToURL(newGridLayout, openCardIds);
    // ...
}, []);
```

**New**:
```javascript
const updateURLWithLayout = useCallback((newGridLayout, openCardIds, elements) => {
    if (!newGridLayout || newGridLayout.length === 0) return;
    if (!elements) {
        console.warn('Cannot update URL: elements not provided');
        return;
    }

    try {
        const compressed = serializeLayoutToURL(newGridLayout, openCardIds, elements);
        if (compressed) {
            const url = new URL(window.location);
            url.searchParams.set('layout', compressed);
            window.history.replaceState({}, '', url);
            console.log('[URL Layout] Updated URL with self-contained layout (v2)');
        }
    } catch (e) {
        console.warn('Failed to update URL with layout:', e);
    }
}, []);
```

**Update all 4 call sites**:

1. Line 2434: `updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);`
2. Line 2501: `updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);`
3. Line 2233: `updateURLWithLayout(updatedLayout, data.layout.mainPane.content, data.elements);`
4. Line 2415: `updateURLWithLayout(updatedLayout, newLayout.mainPane.content, data.elements);`

### Change 3: Update `parseLayoutFromURL()` and Component Loading

**File**: `public/psweb_spa.js`

**Current** (lines 1623-1650):
```javascript
const parseLayoutFromURL = () => {
    // ... decompress layout ...
    return layoutData;
};
```

**New**:
```javascript
const parseLayoutFromURL = () => {
    try {
        const params = new URLSearchParams(window.location.search);
        const layoutParam = params.get('layout');

        if (!layoutParam) return null;

        const layoutData = decompressLayout(layoutParam);

        if (!layoutData || !layoutData.version) {
            console.warn('[URL Layout] Invalid layout data in URL');
            return null;
        }

        // Handle v2 format (self-contained)
        if (layoutData.version === 2 && layoutData.cards) {
            console.log('[URL Layout] Loaded self-contained layout (v2):', {
                cardCount: layoutData.cards.length
            });
            return layoutData;
        }

        // Handle v1 format (legacy - depends on layout.json)
        if (layoutData.version === 1 && layoutData.grid && layoutData.cards) {
            console.warn('[URL Layout] Legacy format (v1) detected - converting to v2');

            // Convert v1 to v2 format (best effort)
            const cardsData = layoutData.grid.map(item => ({
                id: item.i,
                x: item.x,
                y: item.y,
                w: item.w,
                h: item.h,
                elementId: item.i.split('-')[0], // Extract base ID
                title: 'Restored Card',
                type: 'unknown', // Will need to fetch from layout.json
                requiresLookup: true
            }));

            return {
                version: 2,
                cards: cardsData,
                legacy: true
            };
        }

        console.warn('[URL Layout] Unknown layout format');
        return null;

    } catch (e) {
        console.error('[URL Layout] Failed to parse layout from URL:', e);
        return null;
    }
};
```

### Change 4: Replace Component Loading Logic

**File**: `public/psweb_spa.js`

**Current** (lines 1711-1744): Component loading depends on layout.json

**New** (replace entire component loading section):

```javascript
// Parse URL layout BEFORE fetching layout.json
const urlLayout = parseLayoutFromURL();

// If URL layout exists (v2), use it EXCLUSIVELY
if (urlLayout && urlLayout.version === 2 && !urlLayout.legacy) {
    console.log('[URL Layout] Using self-contained URL layout, bypassing layout.json');

    // Load all components from URL metadata
    const componentPromises = urlLayout.cards
        .filter(card => card.type !== 'special')
        .map(async card => {
            try {
                // If component path is directly available, load it
                if (card.componentPath) {
                    console.log(`Loading ${card.id} from URL metadata: ${card.componentPath}`);
                    const res = await fetch(card.componentPath);
                    if (!res.ok) throw new Error(`HTTP ${res.status}`);
                    const text = await res.text();
                    if (text) {
                        const transformed = Babel.transform(text, { presets: ['react'] }).code;
                        (new Function(transformed))();
                    }
                    return;
                }

                // If dynamic card needs to fetch componentPath from endpoint
                if (card.type === 'dynamic' && card.endpoint) {
                    console.log(`Fetching metadata for ${card.id} from: ${card.endpoint}`);
                    const res = await fetch(card.endpoint);
                    if (!res.ok) throw new Error(`HTTP ${res.status}`);
                    const metadata = await res.json();

                    // Get componentPath or scriptPath from endpoint response
                    const componentPath = metadata.componentPath || metadata.scriptPath;
                    if (!componentPath) {
                        throw new Error('No componentPath in endpoint response');
                    }

                    // Load the component
                    const compRes = await fetch(componentPath);
                    if (!compRes.ok) throw new Error(`HTTP ${compRes.status}`);
                    const text = await compRes.text();
                    if (text) {
                        const transformed = Babel.transform(text, { presets: ['react'] }).code;
                        (new Function(transformed))();
                    }

                    // Update card metadata with fetched componentPath
                    card.componentPath = componentPath;
                    return;
                }

                console.warn(`Cannot load component for ${card.id}: insufficient metadata`);
            } catch (err) {
                console.error(`Failed to load component for ${card.id}:`, err);
            }
        });

    // Load profile component
    const profilePromise = fetch('/public/elements/profile/component.js')
        .then(res => res.text())
        .then(text => {
            if (text) (new Function(Babel.transform(text, { presets: ['react'] }).code))();
        });

    await Promise.all([...componentPromises, profilePromise]);

    // Build data structure from URL layout
    const elements = {};
    urlLayout.cards.forEach(card => {
        elements[card.id] = {
            id: card.id,
            Element_Id: card.elementId,
            Title: card.title,
            componentPath: card.componentPath,
            url: card.endpoint,
            backgroundColor: card.backgroundColor,
            loadType: 'component'
        };
    });

    const gridLayout = urlLayout.cards.map(card => ({
        i: card.id,
        x: card.x,
        y: card.y,
        w: card.w,
        h: card.h
    }));

    const layout = {
        title: { left: ['title'], content: [], right: ['user-card'] },
        leftPane: { top: ['main-menu'], bottom: [] },
        mainPane: { content: urlLayout.cards.map(c => c.id) },
        rightPane: { content: [] },
        footer: { left: [], center: ['footer-info'], right: [] }
    };

    setGridLayout(gridLayout);
    setData({
        elements,
        layout,
        componentsReady: true,
        gridLayout: []
    });

    return; // Skip layout.json loading
}

// Otherwise, use layout.json (normal flow)
fetch('/public/layout.json')
    .then(response => response.json())
    .then(async initialData => {
        // Existing layout.json loading logic...
        // (Keep current implementation for when no URL layout exists)
    });
```

---

## Migration Strategy

### Phase 1: Add v2 Support (Backwards Compatible)

1. ✅ Implement new `serializeLayoutToURL()` with full metadata
2. ✅ Update `updateURLWithLayout()` to accept elements parameter
3. ✅ Update all 4 call sites to pass `data.elements`
4. ✅ Implement v2 parsing in `parseLayoutFromURL()`
5. ✅ Add v1→v2 conversion for legacy URLs

**Result**: New URLs are v2, old URLs still work (with limitations)

### Phase 2: Implement Self-Contained Loading

1. ✅ Add component loading for v2 URLs (bypass layout.json)
2. ✅ Test with static cards
3. ✅ Test with dynamic cards
4. ✅ Test with mixed layouts

**Result**: v2 URLs fully independent of layout.json

### Phase 3: Deprecate v1 (Optional)

1. ⚠ Add warning for v1 URLs
2. ⚠ Auto-convert v1 to v2 on page load
3. ⚠ Update URL automatically

**Result**: All URLs eventually v2

---

## Testing Checklist

### Test 1: Static Card URL
```javascript
// 1. Open static card (realtime-events)
// 2. Resize/move it
// 3. Copy URL
// 4. Open in new tab
// Expected: Card loads at exact position, no layout.json dependency
```

### Test 2: Dynamic Card URL
```javascript
// 1. Open dynamic card (file-explorer via menu)
// 2. Resize/move it
// 3. Copy URL
// 4. Open in new tab
// Expected: Card loads at exact position, fetches component from endpoint
```

### Test 3: Mixed Layout URL
```javascript
// 1. Open multiple cards (static + dynamic)
// 2. Arrange them
// 3. Copy URL
// 4. Open in new tab
// Expected: All cards load correctly, layout preserved
```

### Test 4: Component Path Fetch
```javascript
// 1. Open dynamic card
// 2. Check Network tab for:
//    - GET /apps/.../api/v1/ui/elements/file-explorer (metadata)
//    - GET /apps/.../public/elements/file-explorer/component.js (script)
// Expected: Both requests succeed, component loads
```

### Test 5: Legacy v1 URL
```javascript
// 1. Use old URL format (v1)
// 2. Open in browser
// Expected: Warning logged, best-effort conversion, some cards may not load
```

### Test 6: No Layout.json Dependency
```javascript
// 1. Rename /public/layout.json to layout.json.bak
// 2. Open v2 URL
// Expected: Layout loads correctly from URL alone
// 3. Restore layout.json
```

---

## Benefits

### Before (v1)
- ❌ Dynamic cards fail to restore from URL
- ❌ Depends on layout.json being available
- ❌ Error: "No componentPath specified"
- ❌ URLs not truly shareable

### After (v2)
- ✅ All cards restore correctly from URL
- ✅ Completely independent of layout.json
- ✅ URLs are fully self-contained
- ✅ URLs are truly shareable/bookmarkable
- ✅ Works even if layout.json is missing
- ✅ Supports dynamic card endpoints

---

## Code Size Impact

**v1 URL** (example):
```
?layout=eyJ2ZXJzaW9uIjoxLCJncmlkIjpbeyJpIjoiZmlsZS1leHBsb3Jlci0xNzY5NDg2MjI0NDQ2IiwieCI6MCwieSI6MTQsInciOjEyLCJoIjoxNH1dLCJjYXJkcyI6WyJmaWxlLWV4cGxvcmVyLTE3Njk0ODYyMjQ0NDYiXX0=
```
Length: ~180 chars

**v2 URL** (example with full metadata):
```
?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJmaWxlLWV4cGxvcmVyLTE3Njk0ODYyMjQ0NDYiLCJ4IjowLCJ5IjoxNCwidyI6MTIsImgiOjE0LCJlbGVtZW50SWQiOiJmaWxlLWV4cGxvcmVyIiwidGl0bGUiOiJGaWxlIEV4cGxvcmVyIiwidHlwZSI6ImR5bmFtaWMiLCJlbmRwb2ludCI6Ii9hcHBzL1dlYmhvc3RGaWxlRXhwbG9yZXIvYXBpL3YxL3VpL2VsZW1lbnRzL2ZpbGUtZXhwbG9yZXIiLCJjb21wb25lbnRQYXRoIjoiL2FwcHMvV2ViaG9zdEZpbGVFeHBsb3Jlci9wdWJsaWMvZWxlbWVudHMvZmlsZS1leHBsb3Jlci9jb21wb25lbnQuanMifV19
```
Length: ~420 chars

**Increase**: ~2.3x larger, but still well within URL limits (2000+ chars supported by all browsers)

**Compression**: Already using base64 compression, could add LZ-string for further reduction if needed

---

## Implementation Priority

**High Priority** (Must Have):
1. ✅ Update `serializeLayoutToURL()` with full metadata
2. ✅ Update `updateURLWithLayout()` call sites
3. ✅ Add v2 parsing logic
4. ✅ Implement self-contained component loading

**Medium Priority** (Should Have):
1. ✅ Add v1→v2 migration
2. ✅ Add fallback for missing componentPath (fetch from endpoint)
3. ✅ Error handling for failed component loads

**Low Priority** (Nice to Have):
1. ⚠ URL compression optimization (LZ-string)
2. ⚠ v1 deprecation warnings
3. ⚠ Auto-upgrade v1 URLs on load

---

## Summary

**Core Change**: URL layout becomes **completely self-contained** with all metadata needed to reconstruct cards without layout.json.

**Key Benefits**:
- ✅ Dynamic cards work in URLs
- ✅ No layout.json dependency
- ✅ Truly shareable layouts
- ✅ Better error handling

**Migration**: Backwards compatible - v1 URLs still work (with limitations), new URLs are v2.

**Next Step**: Implement Phase 1 (add v2 support) in psweb_spa.js

---

**Created**: 2026-01-26
**Status**: Ready for Implementation
