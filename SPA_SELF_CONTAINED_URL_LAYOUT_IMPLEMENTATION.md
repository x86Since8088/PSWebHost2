# Self-Contained URL Layout - Final Implementation

## Date: 2026-01-26

## Simplified v2 Format (No componentPath in URL)

**Store only essential metadata - fetch componentPath from endpoint dynamically**

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
            "endpoint": "/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer"
        },
        {
            "id": "realtime-events-1769486221470",
            "x": 0,
            "y": 0,
            "w": 12,
            "h": 14,
            "elementId": "realtime-events",
            "title": "Real-time Events",
            "endpoint": "/apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events"
        }
    ]
}
```

**Key Points**:
- ✅ No `componentPath` stored in URL
- ✅ Endpoint returns `scriptPath` or `componentPath`
- ✅ Single source of truth for component locations
- ✅ URLs stay small (~250 chars vs ~420)
- ✅ Component paths can change without breaking URLs

---

## Implementation

### Step 1: Update `serializeLayoutToURL()`

**File**: `public/psweb_spa.js` (line 1592-1605)

**Replace with**:

```javascript
const serializeLayoutToURL = (gridLayout, openCardIds, elements) => {
    // Build simplified card data
    const cardsData = gridLayout
        .filter(item => openCardIds.includes(item.i))
        .map(item => {
            const element = elements[item.i];

            if (!element) {
                console.warn(`Element not found for card: ${item.i}`);
                return null;
            }

            // Base card data
            const cardData = {
                id: item.i,
                x: item.x,
                y: item.y,
                w: item.w,
                h: item.h,
                elementId: element.Element_Id || element.id || item.i.split('-')[0],
                title: element.Title || 'Untitled'
            };

            // Add endpoint URL if available (for both static and dynamic cards)
            if (element.url) {
                cardData.endpoint = element.url;
            }

            // Add backgroundColor if set
            if (element.backgroundColor) {
                cardData.backgroundColor = element.backgroundColor;
            }

            return cardData;
        })
        .filter(Boolean); // Remove nulls

    const layoutData = {
        version: 2,
        cards: cardsData
    };

    return compressLayout(layoutData);
};
```

### Step 2: Update `updateURLWithLayout()` Call Sites

**Update 4 locations to pass `data.elements`**:

**Location 1** (line 2434 - handleLayoutChange):
```javascript
const handleLayoutChange = (layout) => {
    setGridLayout(layout);
    if (data.layout?.mainPane?.content) {
        updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);
    }
};
```

**Location 2** (line 2501 - handleDragOrResizeStop):
```javascript
if (response.ok) {
    CacheManager.invalidate(`card_settings_${endpointGuid}`);
    if (data.layout?.mainPane?.content) {
        updateURLWithLayout(layout, data.layout.mainPane.content, data.elements);
    }
}
```

**Location 3** (line 2233 - openCard):
```javascript
setTimeout(() => {
    if (data.layout?.mainPane?.content) {
        updateURLWithLayout(updatedLayout, data.layout.mainPane.content, data.elements);
    }
}, 50);
```

**Location 4** (line 2415 - removeCard):
```javascript
if (newLayout.mainPane?.content) {
    updateURLWithLayout(updatedLayout, newLayout.mainPane.content, data.elements);
}
```

### Step 3: Update `updateURLWithLayout()` Signature

**File**: `public/psweb_spa.js` (line 1607-1621)

**Replace with**:
```javascript
const updateURLWithLayout = useCallback((newGridLayout, openCardIds, elements) => {
    if (!newGridLayout || newGridLayout.length === 0) return;
    if (!elements) {
        console.warn('[URL Layout] Cannot update URL: elements not provided');
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
        console.warn('[URL Layout] Failed to update URL with layout:', e);
    }
}, []);
```

### Step 4: Replace Component Loading Logic

**File**: `public/psweb_spa.js` (lines 1697-1800)

**Replace entire `fetch('/public/layout.json')` section with**:

```javascript
// Parse URL layout first
const urlLayout = parseLayoutFromURL();

// Check if we have a self-contained v2 URL layout
if (urlLayout && urlLayout.version === 2 && urlLayout.cards) {
    console.log('[URL Layout] Using self-contained URL layout (v2)', {
        cardCount: urlLayout.cards.length
    });

    try {
        // Step 1: Fetch metadata for all cards with endpoints
        const metadataPromises = urlLayout.cards.map(async card => {
            if (!card.endpoint) {
                // Static card without endpoint - skip metadata fetch
                return { ...card, static: true };
            }

            try {
                console.log(`[URL Layout] Fetching metadata for ${card.elementId} from: ${card.endpoint}`);
                const res = await fetch(card.endpoint);
                if (!res.ok) {
                    throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                }
                const metadata = await res.json();

                // Extract scriptPath or componentPath from response
                const componentPath = metadata.scriptPath || metadata.componentPath;
                if (!componentPath) {
                    throw new Error('No scriptPath/componentPath in endpoint response');
                }

                return {
                    ...card,
                    componentPath: componentPath,
                    metadata: metadata
                };
            } catch (err) {
                console.error(`[URL Layout] Failed to fetch metadata for ${card.elementId}:`, err);
                return {
                    ...card,
                    loadError: err.message
                };
            }
        });

        const cardsWithMetadata = await Promise.all(metadataPromises);

        // Step 2: Load all component scripts
        const componentPromises = cardsWithMetadata
            .filter(card => card.componentPath && !card.loadError)
            .map(async card => {
                try {
                    console.log(`[URL Layout] Loading component for ${card.elementId} from: ${card.componentPath}`);
                    const res = await fetch(card.componentPath);
                    if (!res.ok) {
                        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                    }
                    const text = await res.text();
                    if (text) {
                        const transformed = Babel.transform(text, { presets: ['react'] }).code;
                        (new Function(transformed))();
                        console.log(`[URL Layout] ✓ Loaded component: ${card.elementId}`);
                    }
                } catch (err) {
                    console.error(`[URL Layout] Failed to load component for ${card.elementId}:`, err);
                    card.loadError = err.message;
                }
            });

        // Load profile component (always needed)
        const profilePromise = fetch('/public/elements/profile/component.js')
            .then(res => res.text())
            .then(text => {
                if (text) {
                    (new Function(Babel.transform(text, { presets: ['react'] }).code))();
                }
            })
            .catch(err => console.error('[URL Layout] Failed to load profile component:', err));

        await Promise.all([...componentPromises, profilePromise]);

        // Step 3: Build data structure from URL layout
        const elements = {};
        cardsWithMetadata.forEach(card => {
            elements[card.id] = {
                id: card.id,
                Element_Id: card.elementId,
                Title: card.title,
                url: card.endpoint,
                componentPath: card.componentPath,
                backgroundColor: card.backgroundColor,
                loadError: card.loadError || null,
                loadType: 'component'
            };
        });

        const gridLayout = cardsWithMetadata.map(card => ({
            i: card.id,
            x: card.x,
            y: card.y,
            w: card.w,
            h: card.h
        }));

        // Build minimal layout structure
        const layout = {
            title: {
                left: ['title'],
                content: [],
                right: ['user-card']
            },
            leftPane: {
                top: ['main-menu'],
                bottom: []
            },
            mainPane: {
                content: cardsWithMetadata.map(c => c.id)
            },
            rightPane: {
                content: []
            },
            footer: {
                left: [],
                center: ['footer-info'],
                right: []
            }
        };

        // Add static UI elements (title, user-card, main-menu, footer-info)
        // These don't come from URL, they're always present
        elements['title'] = {
            icon: '/public/icon/Tank1_48x48.png',
            Title: 'PSWeb Server',
            'display-close-icon': false
        };
        elements['user-card'] = {
            Type: 'User',
            Title: 'User Management'
        };
        elements['main-menu'] = {
            Type: 'Menu',
            Title: 'Main Menu',
            componentPath: '/public/elements/main-menu/component.js'
        };
        elements['footer-info'] = {
            Type: 'footer',
            Title: '',
            Content: '© 2024 PSWebHost',
            componentPath: '/public/elements/footer-info/component.js'
        };

        // Load UI components (main-menu, footer-info)
        const uiComponents = [
            '/public/elements/main-menu/component.js',
            '/public/elements/footer-info/component.js'
        ];

        await Promise.all(uiComponents.map(path =>
            fetch(path)
                .then(res => res.text())
                .then(text => {
                    if (text) {
                        (new Function(Babel.transform(text, { presets: ['react'] }).code))();
                    }
                })
                .catch(err => console.error(`Failed to load ${path}:`, err))
        ));

        setGridLayout(gridLayout);
        setData({
            elements,
            layout,
            componentsReady: true,
            gridLayout: []
        });

        console.log('[URL Layout] ✓ Self-contained layout loaded successfully');
        return; // Exit early - don't load layout.json

    } catch (err) {
        console.error('[URL Layout] Failed to load self-contained layout:', err);
        console.log('[URL Layout] Falling back to layout.json');
        // Fall through to normal layout.json loading
    }
}

// Normal flow: load from layout.json (when no URL layout or v2 loading failed)
fetch('/public/layout.json')
    .then(response => response.json())
    .then(async initialData => {
        // Apply URL layout if it exists (v1 format or position overrides)
        if (urlLayout) {
            console.log('[URL Layout] Applying layout from URL (v1 or override mode)');
            if (urlLayout.cards) {
                initialData.layout.mainPane.content = urlLayout.cards;
            }
        }

        // ... rest of existing layout.json loading code ...
        // (Keep all existing logic from line 1707 onwards)
```

### Step 5: Update `parseLayoutFromURL()`

**File**: `public/psweb_spa.js` (lines 1623-1650)

**Replace with**:
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

        // Handle v2 format (self-contained with endpoint URLs)
        if (layoutData.version === 2 && layoutData.cards) {
            console.log('[URL Layout] Detected v2 format (self-contained)');

            // Validate all cards have required fields
            const validCards = layoutData.cards.every(card =>
                card.id && card.elementId && typeof card.x === 'number' &&
                typeof card.y === 'number' && typeof card.w === 'number' &&
                typeof card.h === 'number'
            );

            if (!validCards) {
                console.warn('[URL Layout] Invalid card data in v2 layout');
                return null;
            }

            return layoutData;
        }

        // Handle v1 format (legacy - depends on layout.json)
        if (layoutData.version === 1 && layoutData.grid && layoutData.cards) {
            console.log('[URL Layout] Detected v1 format (legacy)');
            return {
                version: 1,
                grid: layoutData.grid,
                cards: layoutData.cards
            };
        }

        console.warn('[URL Layout] Unknown layout format version:', layoutData.version);
        return null;

    } catch (e) {
        console.error('[URL Layout] Failed to parse layout from URL:', e);
        return null;
    }
};
```

---

## URL Size Comparison

### v1 Format (current)
```
?layout=eyJ2ZXJzaW9uIjoxLCJncmlkIjpbeyJpIjoiZmlsZS1leHBsb3Jlci0xNzY5NDg2MjI0NDQ2IiwieCI6MCwieSI6MTQsInciOjEyLCJoIjoxNH1dLCJjYXJkcyI6WyJmaWxlLWV4cGxvcmVyLTE3Njk0ODYyMjQ0NDYiXX0=
```
**Length**: ~180 characters

### v2 Format (with endpoint, no componentPath)
```
?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI6W3siaWQiOiJmaWxlLWV4cGxvcmVyLTE3Njk0ODYyMjQ0NDYiLCJ4IjowLCJ5IjoxNCwidyI6MTIsImgiOjE0LCJlbGVtZW50SWQiOiJmaWxlLWV4cGxvcmVyIiwidGl0bGUiOiJGaWxlIEV4cGxvcmVyIiwiZW5kcG9pbnQiOiIvYXBwcy9XZWJob3N0RmlsZUV4cGxvcmVyL2FwaS92MS91aS9lbGVtZW50cy9maWxlLWV4cGxvcmVyIn1dfQ==
```
**Length**: ~280 characters

**Increase**: Only ~1.5x larger (vs 2.3x with componentPath stored)

**Still well within browser limits** (2000+ chars supported)

---

## Component Loading Flow

### For v2 URL Layout Cards

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Parse URL → Extract cards with endpoint URLs             │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. For each card with endpoint:                             │
│    Fetch metadata from endpoint                              │
│    GET /apps/.../api/v1/ui/elements/file-explorer           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Extract scriptPath from response:                        │
│    {                                                         │
│      "scriptPath": "/apps/.../component.js",                │
│      "title": "File Explorer",                              │
│      "width": 12,                                           │
│      "height": 600                                          │
│    }                                                        │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. Load component script from scriptPath                    │
│    GET /apps/.../component.js                               │
│    Transform with Babel → Execute                           │
└─────────────────────────────────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Render card with position/size from URL                  │
└─────────────────────────────────────────────────────────────┘
```

---

## Error Handling

### Scenario 1: Endpoint Unreachable
```javascript
// Card marked with loadError
{
    id: "file-explorer-...",
    loadError: "HTTP 404: Not Found"
}

// Display error card with helpful message
```

### Scenario 2: No scriptPath in Response
```javascript
// Check for both scriptPath and componentPath
const componentPath = metadata.scriptPath || metadata.componentPath;
if (!componentPath) {
    throw new Error('No scriptPath/componentPath in endpoint response');
}
```

### Scenario 3: Component Script Fails
```javascript
// Card still added to layout with error
// User can see what failed and potentially fix/reload
```

---

## Testing Plan

### Test 1: Single Dynamic Card
```bash
# 1. Open file-explorer via menu
# 2. Move to x=6, y=10, resize to w=8, h=12
# 3. Copy URL
# 4. Open in new tab
# Expected: Card at exact position, component loads from endpoint
```

### Test 2: Multiple Dynamic Cards
```bash
# 1. Open file-explorer and realtime-events
# 2. Arrange them side-by-side
# 3. Copy URL
# 4. Open in new tab
# Expected: Both cards at correct positions
```

### Test 3: Network Inspection
```bash
# Open URL with file-explorer
# Check Network tab:
# ✓ GET /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer (metadata)
# ✓ GET /apps/WebhostFileExplorer/public/elements/file-explorer/component.js (script)
```

### Test 4: Endpoint Failure
```bash
# 1. Create URL with invalid endpoint
# 2. Open URL
# Expected: Error logged, card shows error state (not crash)
```

### Test 5: No layout.json
```bash
# 1. Temporarily rename layout.json
# 2. Open v2 URL
# Expected: Layout loads from URL (bypasses layout.json)
# 3. Restore layout.json
```

---

## Benefits

✅ **URLs smaller** (~280 vs ~420 chars with stored componentPath)
✅ **Single source of truth** for component locations (endpoint)
✅ **Component paths can change** without breaking saved URLs
✅ **Completely independent** of layout.json for v2 URLs
✅ **Dynamic cards work** in shareable URLs
✅ **Backwards compatible** with v1 URLs

---

## Implementation Checklist

- [ ] Update `serializeLayoutToURL()` (store endpoint, not componentPath)
- [ ] Update `updateURLWithLayout()` signature (add elements parameter)
- [ ] Update 4 call sites (pass data.elements)
- [ ] Replace component loading logic (fetch metadata from endpoints)
- [ ] Update `parseLayoutFromURL()` (handle v2 format)
- [ ] Test single dynamic card URL
- [ ] Test multiple cards URL
- [ ] Test endpoint failure handling
- [ ] Test v1 backwards compatibility
- [ ] Test without layout.json (v2 independence)

---

**Status**: Ready for Implementation
**File to Modify**: `public/psweb_spa.js`
**Estimated Changes**: ~200 lines (mostly replacing existing component loading)
