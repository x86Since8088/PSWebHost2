# Dynamic Component Loading Without layout.json

**Date:** 2026-01-17
**Status:** ✅ Implemented

---

## Summary

Updated the PSWebHost SPA framework to support **fully dynamic component loading** without requiring components to be registered in `public/layout.json`. Apps are now truly plug-and-play - they can define their UI components entirely through their endpoint responses.

---

## Changes Made

### 1. Updated `loadComponentScript` Function

**File:** `public/psweb_spa.js`

**Changes:**
- Added `endpointUrl` parameter to accept the full endpoint URL from the menu
- Uses the provided endpoint URL instead of constructing a generic one
- Falls back to standard `/api/v1/ui/elements/{elementId}` if no URL provided

**Function Signature:**
```javascript
const loadComponentScript = async (elementId, explicitPath = null, endpointUrl = null)
```

**Behavior:**
1. **If `explicitPath` provided**: Use it directly (for layout.json components)
2. **If `endpointUrl` provided**: Fetch metadata from that specific endpoint
3. **Otherwise**: Try standard endpoint pattern `/api/v1/ui/elements/{elementId}`
4. **Extract `scriptPath`**: From endpoint response JSON
5. **Load component.js**: From the scriptPath location

### 2. Updated `openCard` Function

**File:** `public/psweb_spa.js`

**Change:**
```javascript
// Before
await loadComponentScript(elementId);

// After
await loadComponentScript(elementId, null, elementUrl);
```

Now passes the full endpoint URL (from menu.yaml) to the component loader.

---

## How It Works

### Menu Flow

1. **User clicks menu item** with URL `/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager`
2. **`openCard()` is called** with this full URL
3. **Extracts `elementId`**: "task-manager"
4. **Calls `loadComponentScript()`**: Passing "task-manager" AND the full endpoint URL
5. **Fetches endpoint**: Gets JSON with `scriptPath`
6. **Loads component.js**: From the scriptPath
7. **Mounts component**: In a new card

### Endpoint Response Format

Apps should return JSON with at minimum:
```json
{
  "component": "task-manager",
  "scriptPath": "/apps/WebHostTaskManagement/public/elements/task-manager/component.js",
  "title": "Task Management",
  "description": "...",
  "width": 12,
  "height": 800
}
```

**Key field:** `scriptPath` - Tells the framework where to find component.js

---

## Benefits

### ✅ No layout.json Registration Required

Apps can now be completely self-contained:
- Define menu in `apps/AppName/menu.yaml`
- Define endpoint in `apps/AppName/routes/api/v1/ui/elements/component-name/get.ps1`
- Define component in `apps/AppName/public/elements/component-name/component.js`

**No central configuration needed!**

### ✅ True Plug-and-Play Apps

Adding a new app is now:
1. Copy app folder to `apps/`
2. Enable in app.yaml
3. Define menu.yaml (optional)
4. Restart server

No need to modify `public/layout.json` or any core files.

### ✅ Multi-Tenant Friendly

Different apps can be enabled/disabled per instance without modifying shared configuration files.

### ✅ Backwards Compatible

Existing components registered in `layout.json` still work:
- `layout.json` components use `componentPath` directly
- Dynamic components use endpoint `scriptPath`
- Both patterns work seamlessly

---

## Component Registration Options

### Option A: Dynamic Loading (Recommended for Apps)

**No layout.json entry needed**

1. Create menu.yaml:
```yaml
- Name: My Component
  url: /apps/MyApp/api/v1/ui/elements/my-component
  parent: Apps\MyApp
```

2. Create endpoint that returns:
```json
{
  "scriptPath": "/apps/MyApp/public/elements/my-component/component.js",
  "component": "my-component",
  "title": "My Component"
}
```

3. Create component.js that registers:
```javascript
window.cardComponents['my-component'] = function(props) { ... }
```

**That's it!** No central configuration needed.

### Option B: Static Registration (For Core Components)

**Register in layout.json**

```json
"my-component": {
    "Type": "Custom",
    "Title": "My Component",
    "componentPath": "/public/elements/my-component/component.js"
}
```

This skips the endpoint fetch and loads the component directly.

---

## Migration Guide

### For Existing Apps Using layout.json

**No changes required** - components registered in layout.json continue to work.

### For New Apps

**Don't add to layout.json** - just define the menu.yaml and endpoint.

### Removing from layout.json

If you want to migrate an existing component to dynamic loading:

1. **Remove from layout.json**
2. **Ensure menu.yaml has correct URL**
3. **Ensure endpoint returns `scriptPath`**
4. **Test that component still loads**

---

## Examples

### Example 1: Task Management (WebHostTaskManagement)

**Menu:** `apps/WebHostTaskManagement/menu.yaml`
```yaml
- Name: Task Management
  parent: System Management\WebHost
  url: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
```

**Endpoint:** `apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1`
```powershell
$cardInfo = @{
    component = 'task-manager'
    scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
    title = 'Task Management'
    width = 12
    height = 800
}
context_reponse -Response $Response -String ($cardInfo | ConvertTo-Json) -ContentType "application/json"
```

**Component:** `apps/WebHostTaskManagement/public/elements/task-manager/component.js`
```javascript
window.cardComponents['task-manager'] = function(props) {
    // Component implementation
}
```

**Result:** Works without layout.json entry! ✅

---

## Technical Details

### Component Loading Priority

1. **Explicit path parameter** (if provided to loadComponentScript)
2. **Endpoint URL** (from menu click - NEW!)
3. **Standard endpoint pattern** (fallback for legacy behavior)

### Error Handling

If component can't be loaded:
- Logs error to console
- Logs to server via `/api/v1/debug/client-log`
- Continues loading other components (doesn't block)
- Shows error message in console

### Caching

Components are cached in `window.cardComponents[elementId]` after first load:
- Subsequent opens of the same component reuse cached version
- Refresh page to reload components

---

## Testing

### Test Dynamic Loading

1. Click menu item for app component (e.g., Task Management)
2. Check browser console for:
   ```
   Loading component script for task-manager...
   Fetching component metadata from: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
   ✓ Using scriptPath from endpoint: /apps/WebHostTaskManagement/public/elements/task-manager/component.js
   ✓ Component task-manager loaded and registered
   ```
3. Component should display in a new card

### Test layout.json Components (Backwards Compatibility)

1. Click menu item for core component (e.g., World Map)
2. Should still load from layout.json componentPath
3. No endpoint fetch needed

---

## Troubleshooting

### Component Not Loading

**Check:**
1. Does endpoint exist and return 200?
2. Does response include `scriptPath` field?
3. Does component.js file exist at scriptPath?
4. Does component.js register `window.cardComponents[elementId]`?

**Debug:**
```javascript
// In browser console
console.log(window.cardComponents); // See registered components
```

### Wrong Endpoint Being Called

**Issue:** Standard endpoint `/api/v1/ui/elements/{elementId}` instead of app endpoint

**Solution:** Ensure menu.yaml URL is correct and includes full path:
```yaml
url: /apps/AppName/api/v1/ui/elements/component-name  # ✅ Correct
url: /api/v1/ui/elements/component-name               # ❌ Wrong - won't find app endpoint
```

---

## Future Enhancements

### Potential Improvements

1. **App Manifest Discovery**: Automatically discover all apps and their endpoints
2. **Component Registry API**: Endpoint to list all available components
3. **Hot Reload**: Reload components without page refresh
4. **Lazy Loading**: Load component.js only when card is opened, not on page load

---

## Files Modified

- `public/psweb_spa.js` - Updated loadComponentScript and openCard functions
- `public/layout.json` - Removed task-manager entry (no longer needed)

---

## Status

✅ **Implemented and Working**

Apps can now be fully self-contained without requiring `layout.json` entries!

---

**Last Updated:** 2026-01-17
**Author:** PSWebHost Development Team
