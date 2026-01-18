# Component Path Specification

## Overview

PSWebHost requires **explicit component paths** for all UI elements. The system will **NOT** assume or fallback to `/public/elements/` directories. This design ensures code clarity and makes component references obvious to code reviewers.

## Why Explicit Paths?

1. **Code Clarity**: Reviewers can immediately see where components are loaded from
2. **App Support**: Apps can provide components from their own directories
3. **No Hidden Assumptions**: No magic path resolution or fallback behavior
4. **Easier Debugging**: Clear error messages when paths are missing

## How to Specify Component Paths

Component paths can be specified in **two ways**:

### Method 1: In `layout.json` (Preferred for static components)

```json
{
  "elements": {
    "server-heatmap": {
      "Type": "Heatmap",
      "Title": "Server Load",
      "componentPath": "/public/elements/server-heatmap/component.js"
    },
    "event-stream": {
      "Type": "Events",
      "Title": "Real-time Events",
      "componentPath": "/public/elements/realtime-events/component.js"
    }
  }
}
```

**Advantages**:
- ✅ No API call needed during component load
- ✅ Faster initial page load
- ✅ Path is immediately visible in layout configuration

**Use When**:
- Component is defined in layout.json
- Component path is static and won't change
- Performance is critical (initial page load)

### Method 2: Via UI Element Endpoint (Preferred for app components)

In your endpoint at `routes/api/v1/ui/elements/{element-id}/get.ps1`:

```powershell
$cardInfo = @{
    component = 'my-card'
    title = 'My Card Title'
    scriptPath = '/apps/MyApp/public/elements/my-card/component.js'
}

$jsonData = $cardInfo | ConvertTo-Json -Depth 5
context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
```

**Advantages**:
- ✅ Apps control their own component paths
- ✅ No modification to layout.json required
- ✅ Dynamic - can change based on app configuration

**Use When**:
- Component is provided by an app
- Component is opened via menu (not in layout.json)
- Path needs to be dynamic or configurable

## Component Loading Priority

When loading a component, the system checks paths in this order:

1. **Explicit path parameter** (if passed to `loadComponentScript()`)
2. **`componentPath` in layout.json** (if element is defined there)
3. **`scriptPath` from UI element endpoint** (fetched from `/api/v1/ui/elements/{id}`)
4. **ERROR** - No fallback, component loading fails with clear error message

## Error Messages

If no path is found, you'll see:

```
❌ No component path found for system-log. Component paths must be explicitly specified via:
  1. componentPath in layout.json, OR
  2. scriptPath in /api/v1/ui/elements/system-log endpoint response
```

This error tells you exactly what's missing and where to fix it.

## Examples

### Example 1: Standard Component in layout.json

```json
{
  "elements": {
    "file-explorer": {
      "Type": "Files",
      "Title": "File Explorer",
      "componentPath": "/public/elements/file-explorer/component.js"
    }
  }
}
```

### Example 2: App Component (Not in layout.json)

**Menu Entry** (`routes/api/v1/ui/elements/main-menu/main-menu.yaml`):
```yaml
- url: /api/v1/ui/elements/realtime-events
  Name: Real-time Events
  roles:
  - authenticated
```

**UI Element Endpoint** (`routes/api/v1/ui/elements/realtime-events/get.ps1`):
```powershell
$cardInfo = @{
    component = 'realtime-events'
    title = 'Real-time Events'
    scriptPath = '/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js'
}
```

**Component File**:
```
apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js
```

### Example 3: Mixed - App Component in Layout

If you want an app component to appear in the initial layout:

**layout.json**:
```json
{
  "elements": {
    "realtime-events": {
      "Type": "Events",
      "Title": "Real-time Events",
      "componentPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js"
    }
  },
  "layout": {
    "mainPane": {
      "content": ["realtime-events"]
    }
  }
}
```

## Migration Guide

### For Existing Components

If you have existing components in `/public/elements/`, update `layout.json`:

**Before**:
```json
{
  "elements": {
    "my-card": { "Type": "Card", "Title": "My Card" }
  }
}
```

**After**:
```json
{
  "elements": {
    "my-card": {
      "Type": "Card",
      "Title": "My Card",
      "componentPath": "/public/elements/my-card/component.js"
    }
  }
}
```

### For New App Components

1. Create your component file in your app directory:
   ```
   apps/MyApp/public/elements/my-component/component.js
   ```

2. Create UI element endpoint:
   ```
   routes/api/v1/ui/elements/my-component/get.ps1
   ```

3. Return `scriptPath` in endpoint response:
   ```powershell
   @{
       component = 'my-component'
       scriptPath = '/apps/MyApp/public/elements/my-component/component.js'
   }
   ```

4. Add menu entry (if desired):
   ```yaml
   - url: /api/v1/ui/elements/my-component
     Name: My Component
   ```

## Path Validation

Component paths should:
- ✅ Start with `/` (absolute path)
- ✅ End with `.js`
- ✅ Point to an accessible file on the server
- ✅ Be served by PSWebHost's static file handler

Common mistakes:
- ❌ Relative paths: `elements/my-card/component.js`
- ❌ Missing extension: `/public/elements/my-card/component`
- ❌ Wrong extension: `/public/elements/my-card/component.jsx`

## Debugging Tips

### Check Browser Console

Look for these log messages:

**Success**:
```
Loading component for server-heatmap from: /public/elements/server-heatmap/component.js
Transforming server-heatmap with Babel from /public/elements/server-heatmap/component.js...
✓ Component server-heatmap loaded and registered
```

**Failure (Missing Path)**:
```
❌ No componentPath specified for element: my-card
   Element definition: { Type: "Card", Title: "My Card" }
   Component paths must be explicitly defined in layout.json
   Example: "componentPath": "/public/elements/my-card/component.js"
```

**Failure (Wrong Path)**:
```
❌ Failed to load my-card component from /wrong/path/component.js: HTTP 404: Not Found
   Path attempted: /wrong/path/component.js
```

### Check Network Tab

- Look for requests to component paths
- 404 errors indicate wrong paths
- 200 OK means file was found but may have JS errors

### Check Server Logs

If components won't load, check PSWebHost logs for:
- Static file serving errors
- Route registration issues
- App initialization problems

## Best Practices

1. **Use Consistent Naming**: Match element ID to component directory name
   - Element ID: `realtime-events`
   - Directory: `elements/realtime-events/`

2. **Keep Paths Absolute**: Always start with `/`
   - ✅ `/public/elements/my-card/component.js`
   - ❌ `public/elements/my-card/component.js`

3. **Document App Components**: In your app's README, specify the component path

4. **Test After Changes**: After updating paths, hard-refresh browser (Ctrl+F5)

5. **Use Descriptive Names**: Component IDs should match their function
   - ✅ `realtime-events`, `file-explorer`, `server-heatmap`
   - ❌ `card1`, `widget2`, `thing`

## Testing

### Test Component Path Resolution

Use browser console:

```javascript
// Check what's in layout data
console.log(window.layoutData?.elements?.['my-card']);

// Manually load a component
window.loadComponentScript('my-card', '/path/to/component.js');

// Check if component registered
console.log(window.cardComponents?.['my-card']);
```

### Test UI Element Endpoint

```powershell
# PowerShell
Invoke-WebRequest -Uri "http://localhost:8080/api/v1/ui/elements/my-card" |
    Select-Object -ExpandProperty Content |
    ConvertFrom-Json |
    Select-Object scriptPath
```

```bash
# curl
curl http://localhost:8080/api/v1/ui/elements/my-card | jq .scriptPath
```

## Summary

**Key Takeaways**:

1. 🎯 **Paths must be explicit** - No assumptions or fallbacks
2. 📝 **Two specification methods** - layout.json or endpoint response
3. 🚀 **Apps control their paths** - Via scriptPath in endpoint
4. 🔍 **Clear error messages** - Know exactly what's missing
5. ⚡ **Performance option** - Use layout.json to avoid API calls

**Quick Reference**:

| Scenario | Where to Specify Path | Example |
|----------|----------------------|---------|
| Static component in layout | `layout.json` → `componentPath` | `/public/elements/my-card/component.js` |
| App component via menu | Endpoint → `scriptPath` | `/apps/MyApp/public/elements/card/component.js` |
| App component in layout | `layout.json` → `componentPath` | `/apps/MyApp/public/elements/card/component.js` |

**Questions?** Check browser console logs for detailed error messages.
