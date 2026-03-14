# Layout System Analysis: Component Path Resolution

## Executive Summary

The PSWebHost SPA currently **hardcodes** the path `/public/elements/{elementId}/component.js` for loading card components. This prevents apps from providing their own UI components because the system always looks in the global `public/elements/` directory.

**The Problem**: Apps like `WebhostRealtimeEvents` need their components loaded from app-specific paths, but the SPA assumes all components are in `public/` and cannot be told otherwise.

**The Solution**: Extend the layout and card loading system to support **explicit component paths** via the UI element endpoint metadata.

---

## Current System Architecture

### 1. Layout Definition (`public/layout.json`)

Defines which cards appear in the UI and where:

```json
{
  "elements": {
    "event-stream": { "Type": "Events", "Title": "Real-time Events" }
  },
  "layout": {
    "mainPane": {
      "content": ["event-stream"]
    }
  }
}
```

**Current Limitation**: Element IDs are used to construct hardcoded paths.

---

### 2. Component Loading (`public/psweb_spa.js`)

#### **Line 1020** - Initial layout load:
```javascript
fetch(`/public/elements/${id}/component.js`)
```

#### **Line 1189** - Dynamic card loading:
```javascript
fetch(`/public/elements/${elementId}/component.js`)
```

#### **Line 1216** - Fallback for legacy components:
```javascript
fetch(`/public/elements/${elementId}/element.js`)
```

**Problem**: All three locations **hardcode** `/public/elements/`.

---

### 3. Menu System (`routes/api/v1/ui/elements/main-menu/main-menu.yaml`)

Menu entries reference UI element endpoints:

```yaml
- url: /api/v1/ui/elements/realtime-events
  Name: Real-time Events
```

**How It Works**:
1. User clicks menu item
2. SPA calls `window.openCard(url, title)`
3. `openCard()` extracts element ID from URL pattern `/api/v1/ui/elements/{elementId}`
4. `loadComponentScript()` tries to load from `/public/elements/{elementId}/component.js`

---

### 4. UI Element Endpoints (e.g., `routes/api/v1/ui/elements/realtime-events/get.ps1`)

Returns metadata about the card:

```json
{
  "component": "realtime-events",
  "title": "Real-time Events",
  "scriptPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js"
}
```

**Current State**:
- ✅ The endpoint **already returns** a `scriptPath` field!
- ❌ The SPA **ignores** this field and uses the hardcoded path instead

---

## The Gap: What's Missing

### Problem Flow

1. **Layout defines**: `"event-stream"` should be in mainPane
2. **SPA hardcodes**: `/public/elements/event-stream/component.js`
3. **App provides**: Component at `/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js`
4. **Result**: 404 error because the SPA never checks the correct path

### Why Apps Can't Work

When an app wants to provide a UI component:

```
apps/WebhostRealtimeEvents/
├── public/elements/realtime-events/component.js  ← Component here
└── routes/api/v1/ui/elements/realtime-events/get.ps1  ← Returns scriptPath
```

The menu calls `/api/v1/ui/elements/realtime-events`, which returns:
```json
{ "scriptPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js" }
```

But `loadComponentScript()` ignores this and tries:
```
/public/elements/realtime-events/component.js  ← 404!
```

---

## Proposed Solution

### Option 1: Extend layout.json with explicit paths ⭐ **RECOMMENDED**

**Why**: Keeps component paths close to their definition, explicit control over what loads from where.

#### Changes Required:

**1. Update `public/layout.json`:**
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

**2. Update `psweb_spa.js` line 1020** (initial load):
```javascript
const componentPath = initialData.elements[id]?.componentPath || `/public/elements/${id}/component.js`;
return fetch(componentPath)
```

**3. Update `psweb_spa.js` line 1189** (dynamic load):
```javascript
const componentPath = data.elements[elementId]?.componentPath || `/public/elements/${elementId}/component.js`;
fetch(componentPath)
```

**Pros**:
- ✅ Backward compatible (defaults to `/public/elements/` if no path specified)
- ✅ Explicit and clear
- ✅ Layout editor can manage paths
- ✅ No API calls needed during initial load

**Cons**:
- ❌ Requires editing `layout.json` for each app component
- ❌ Path duplication (in layout.json and in UI element endpoint)

---

### Option 2: Fetch component path from UI element endpoint

**Why**: Lets each component's endpoint define its own path dynamically.

#### Changes Required:

**1. Update `psweb_spa.js` `loadComponentScript()` function** (~line 1178):

```javascript
const loadComponentScript = async (elementId) => {
    return new Promise(async (resolve, reject) => {
        // Check if component is already loaded
        if (window.cardComponents[elementId]) {
            resolve();
            return;
        }

        console.log(`Loading component script for ${elementId}...`);

        try {
            // Try to fetch metadata from UI element endpoint
            const endpointUrl = `/api/v1/ui/elements/${elementId}`;
            const metadataRes = await fetch(endpointUrl);

            let componentPath = `/public/elements/${elementId}/component.js`;

            if (metadataRes.ok) {
                const metadata = await metadataRes.json();
                if (metadata.scriptPath) {
                    componentPath = metadata.scriptPath;
                    console.log(`Using scriptPath from endpoint: ${componentPath}`);
                }
            }

            // Fetch and transform component
            const res = await fetch(componentPath);
            if (!res.ok) throw new Error(`HTTP ${res.status}: ${res.statusText}`);

            const text = await res.text();
            if (text) {
                console.log(`Transforming ${elementId} with Babel...`);
                const transformed = Babel.transform(text, { presets: ['react'] }).code;
                (new Function(transformed))();

                if (window.cardComponents[elementId]) {
                    console.log(`✓ Component ${elementId} loaded and registered`);
                } else {
                    console.warn(`⚠ Component ${elementId} loaded but not registered`);
                }
            }
            resolve();
        } catch (err) {
            // Fallback to element.js
            console.log(`Failed to load component, trying element.js fallback...`);
            // ... existing fallback logic ...
            resolve();
        }
    });
};
```

**2. No changes needed to `layout.json`** - backward compatible!

**Pros**:
- ✅ Fully dynamic - apps control their own paths
- ✅ No `layout.json` changes needed
- ✅ Leverages existing `scriptPath` field in UI element endpoints
- ✅ Backward compatible (defaults to `/public/elements/` if endpoint doesn't exist)

**Cons**:
- ❌ Extra API call for each component load
- ❌ Slightly slower initial page load
- ❌ Endpoint must exist for app components (but this is already the case for menu integration)

---

### Option 3: Hybrid Approach (Best of Both Worlds) ⭐⭐ **RECOMMENDED**

Combine both options for maximum flexibility:

1. **Check `layout.json` first** for explicit `componentPath`
2. **Fallback to UI element endpoint** if no path in layout
3. **Fallback to `/public/elements/`** if neither exists

#### Implementation:

```javascript
const loadComponentScript = async (elementId) => {
    // ... existing checks ...

    // 1. Check layout data for explicit componentPath
    let componentPath = data?.elements?.[elementId]?.componentPath;

    // 2. If no path in layout, try fetching from endpoint
    if (!componentPath) {
        try {
            const endpointUrl = `/api/v1/ui/elements/${elementId}`;
            const metadataRes = await fetch(endpointUrl);
            if (metadataRes.ok) {
                const metadata = await metadataRes.json();
                componentPath = metadata.scriptPath;
            }
        } catch (err) {
            console.log(`No metadata endpoint for ${elementId}, using default path`);
        }
    }

    // 3. Final fallback to default path
    if (!componentPath) {
        componentPath = `/public/elements/${elementId}/component.js`;
    }

    console.log(`Loading component from: ${componentPath}`);

    // ... rest of existing fetch and transform logic ...
};
```

**Pros**:
- ✅ Maximum flexibility
- ✅ Can optimize by adding paths to layout.json (avoids API call)
- ✅ Fully backward compatible
- ✅ Apps work without layout.json changes

**Cons**:
- ❌ More complex logic
- ❌ Two potential sources of truth for component paths

---

## Recommendation

**Use Option 3 (Hybrid)** for these reasons:

1. **Apps work immediately** - No layout.json changes required, endpoints already return scriptPath
2. **Performance can be optimized** - Add componentPath to layout.json for frequently-used cards
3. **Backward compatible** - Existing cards in /public/elements/ continue to work
4. **Future-proof** - Supports both static and dynamic component paths

---

## Implementation Plan

### Phase 1: Update SPA Component Loading

**Files to Modify**:
- `public/psweb_spa.js`

**Changes**:
1. Update `loadComponentScript()` function (line ~1178)
2. Update initial component loading in `loadLayout()` (line ~1020)
3. Add caching for endpoint metadata responses

### Phase 2: Update Layout for App Components

**Files to Modify**:
- `public/layout.json`

**Changes**:
1. Add `componentPath` field to app-provided elements:
```json
"realtime-events": {
  "Type": "Events",
  "Title": "Real-time Events",
  "componentPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js"
}
```

### Phase 3: Test & Verify

**Test Cases**:
1. ✅ Legacy components in `/public/elements/` still load
2. ✅ App components load from their app directories
3. ✅ Menu-triggered cards load correctly
4. ✅ Layout-defined cards load correctly
5. ✅ Dynamic `openCard()` calls work
6. ✅ 404 errors gracefully fall back

---

## Current State: Real-time Events App

### What Works:
- ✅ App structure created
- ✅ API endpoints working (`/apps/WebhostRealtimeEvents/api/v1/logs`)
- ✅ Component exists at `public/elements/realtime-events/component.js`
- ✅ UI element endpoint returns `scriptPath`
- ✅ Menu entry exists

### What Doesn't Work:
- ❌ SPA ignores `scriptPath` from endpoint
- ❌ SPA hardcodes `/public/elements/realtime-events/component.js`
- ❌ Component loads from wrong location

### After Fix:
- ✅ SPA checks endpoint for `scriptPath`
- ✅ Component loads from `/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js`
- ✅ Card displays correctly in UI

---

## Files Involved

### Core SPA Files:
- `public/psweb_spa.js` - Main SPA logic (**needs modification**)
- `public/layout.json` - Layout definition (optional modification)

### Layout Management:
- `routes/spa/layout/get.ps1` - Returns layout.json
- `routes/spa/mainmenu/layout/get.ps1` - Layout editor UI
- `routes/spa/mainmenu/layout/put.ps1` - Layout update endpoint

### Menu System:
- `routes/api/v1/ui/elements/main-menu/main-menu.yaml` - Main menu items
- `routes/api/v1/ui/elements/main-menu/get.ps1` - Menu builder logic

### Example App Component:
- `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js`
- `routes/api/v1/ui/elements/realtime-events/get.ps1` (already returns `scriptPath`)

---

## Migration Path for Existing Apps

### For New Apps (Moving Forward):

1. **Create UI element endpoint** at `routes/api/v1/ui/elements/{app-name}/get.ps1`
2. **Return scriptPath** in endpoint response:
   ```powershell
   @{
       component = 'my-app-card'
       title = 'My App'
       scriptPath = '/apps/MyApp/public/elements/my-app-card/component.js'
   }
   ```
3. **Place component** at the path specified in scriptPath
4. **Add menu entry** in app's `menu.yaml` or `main-menu.yaml`

### For Existing Components in /public/elements/:

**No changes required** - they will continue to work as before.

---

## Security Considerations

1. **Path Validation**: Ensure scriptPath URLs are validated/sanitized
2. **Authentication**: UI element endpoints should check authentication (already done)
3. **CSP Headers**: May need to allow script loading from `/apps/` paths
4. **Path Traversal**: Prevent `../` in scriptPath values

---

## Testing Strategy

### Unit Tests:
- Test component path resolution logic
- Test fallback behavior
- Test caching of endpoint metadata

### Integration Tests:
- Load app component from custom path
- Load legacy component from /public/elements/
- Handle missing components gracefully
- Verify endpoint metadata is fetched correctly

### Browser Tests:
- Test in Chrome, Firefox, Edge
- Verify console logs show correct paths
- Check network tab for fetch calls
- Verify error handling in browser console

---

## Future Enhancements

1. **Component Registry**: Maintain a client-side registry of loaded components
2. **Preloading**: Fetch all component metadata on initial load for better performance
3. **CDN Support**: Allow components to be loaded from external URLs
4. **Version Management**: Support component versioning in paths
5. **Dynamic Imports**: Use ES6 dynamic imports instead of Babel transform

---

## Summary

The current system **cannot support app-provided UI components** because it hardcodes the `/public/elements/` path. The fix requires:

1. **Modify `psweb_spa.js`** to check for `scriptPath` from UI element endpoints
2. **Optionally extend `layout.json`** to include explicit `componentPath` fields
3. **Maintain backward compatibility** with existing components

**Result**: Apps can provide their own React components at custom paths, while existing components continue to work without modification.
