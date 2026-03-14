# Debug Variables Endpoint Fix

**Date:** 2026-02-01
**Issue:** debug-variables component failing to load with 500 error

---

## Problem

The debug-variables card was failing to load with these errors:

```
Error: Component file not found:
C:\SC\PsWebHost\apps\WebHostDebugVariables\routes\api\v1\ui\elements\debug-variables\..\..\..\..\..\public\elements\debug-variables\component.js

Warning: Component debug-variables failed to load after 5000ms
```

---

## Root Cause

The endpoint had **two issues**:

### Issue 1: Incorrect Relative Path

**File:** `apps/WebHostDebugVariables/routes/api/v1/ui/elements/debug-variables/get.ps1`

**Line 9 (OLD):**
```powershell
$componentJs = Join-Path $PSScriptRoot "..\..\..\..\..\public\elements\debug-variables\component.js"
```

**Problem:** The path goes up 5 levels instead of 6.

**$PSScriptRoot Location:**
```
C:\SC\PsWebHost\apps\WebHostDebugVariables\routes\api\v1\ui\elements\debug-variables
```

**Going Up 5 Levels:**
1. `debug-variables` → `elements`
2. `elements` → `ui`
3. `ui` → `v1`
4. `v1` → `api`
5. `api` → `routes` ❌

**Result:**
```
C:\SC\PsWebHost\apps\WebHostDebugVariables\routes\public\elements\debug-variables\component.js
```
This path doesn't exist!

**Should Be (6 levels):**
```
C:\SC\PsWebHost\apps\WebHostDebugVariables\public\elements\debug-variables\component.js
```

---

### Issue 2: Old HTML-Serving Format

The endpoint was using the **deprecated HTML-serving format** instead of the **JSON metadata format**.

**Old Format (Deprecated):**
- Reads component JavaScript file
- Embeds script directly in HTML
- Returns HTML wrapped in JSON
- Client receives pre-built HTML

**New Format (Current Standard):**
- Returns JSON metadata only
- Includes `scriptPath` pointing to component
- Client loads component script separately
- Follows established card architecture

---

## Solution

Completely rewrote the endpoint to use the **JSON metadata format** (same as memory-explorer, debug-console, etc.)

**File:** `apps/WebHostDebugVariables/routes/api/v1/ui/elements/debug-variables/get.ps1`

**Before (40 lines):**
```powershell
try {
    $componentJs = Join-Path $PSScriptRoot "..\..\..\..\..\public\elements\debug-variables\component.js"

    if (-not (Test-Path $componentJs)) {
        throw "Component file not found: $componentJs"
    }

    $jsContent = Get-Content $componentJs -Raw

    $json = @{
        success = $true
        html = @"
<div id="debug-variables-container" style="width: 100%; height: 100%;"></div>
<script>
$jsContent
</script>
"@
    } | ConvertTo-Json -Compress

    context_response -Response $Response -String $json -ContentType "application/json"
}
```

**After (37 lines):**
```powershell
try {
    # Return card metadata (not HTML)
    $cardInfo = @{
        component = 'debug-variables'
        scriptPath = '/apps/WebHostDebugVariables/public/elements/debug-variables/component.js'
        stylePath = $null
        title = 'Debug Variables'
        description = 'View and monitor PowerShell variables in real-time'
        version = '1.0.0'
        width = 12
        height = 10
        features = @(
            'Real-time variable monitoring'
            'Variable value inspection'
            'Type information display'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
```

---

## Benefits of JSON Metadata Format

1. **No File Path Issues** - Uses absolute web paths, not filesystem paths
2. **Consistent Architecture** - Matches all other card endpoints
3. **Better Caching** - Browser can cache component scripts separately
4. **Cleaner Code** - No file reading or embedding logic
5. **Easier Debugging** - Component scripts visible in DevTools
6. **Hot Reload Friendly** - Component changes don't require endpoint restart

---

## Response Format Comparison

### Old HTML-Serving Format:
```json
{
  "success": true,
  "html": "<div id='...'></div><script>/* entire component code */</script>"
}
```

### New JSON Metadata Format:
```json
{
  "component": "debug-variables",
  "scriptPath": "/apps/WebHostDebugVariables/public/elements/debug-variables/component.js",
  "stylePath": null,
  "title": "Debug Variables",
  "description": "View and monitor PowerShell variables in real-time",
  "version": "1.0.0",
  "width": 12,
  "height": 10,
  "features": [
    "Real-time variable monitoring",
    "Variable value inspection",
    "Type information display"
  ]
}
```

---

## Client-Side Loading Flow

### Old Flow:
1. Client fetches endpoint → receives embedded HTML/script
2. Client injects HTML into DOM
3. Component executes immediately

### New Flow:
1. Client fetches endpoint → receives metadata JSON
2. Client reads `scriptPath` from metadata
3. Client fetches component script separately
4. Client registers component in `window.cardComponents`
5. Client renders component using React

---

## Testing

### Verify Fix:

1. **Open debug-variables card from menu**
   - Menu path: Main Menu → Debug Variables
   - Should open without errors

2. **Check browser console**
   - No "Component file not found" errors
   - No "failed to load after 5000ms" warnings

3. **Check server logs**
   - No 500 errors for `/apps/WebHostDebugVariables/cards/debug-variables`
   - No "Component file not found" messages

4. **Test component functionality**
   - Card displays variable monitoring UI
   - Real-time updates work correctly

---

## Related Fixes

This fix follows the same pattern as:
- **memory-explorer** (2026-02-01) - Same HTML→JSON conversion
- **apps-manager** (previous session) - Same authentication fix pattern

---

## Architecture Notes

### Card Endpoint Conventions

All app card endpoints should follow this structure:

```powershell
# Return JSON metadata
$cardInfo = @{
    component = 'component-name'          # Must match window.cardComponents key
    scriptPath = '/apps/AppName/public/elements/component-name/component.js'
    stylePath = '/apps/AppName/public/elements/component-name/style.css'  # or $null
    title = 'Human Readable Title'
    description = 'Brief description'
    version = '1.0.0'
    width = 12                            # Grid width (1-12)
    height = 10                           # Grid height
    features = @(                         # Optional feature list
        'Feature 1'
        'Feature 2'
    )
}

context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
```

### Path Conventions:
- ✅ **Absolute web paths:** `/apps/AppName/public/...`
- ❌ **Relative filesystem paths:** `..\..\..\..\public\...`

---

## Prevention

**For Future Development:**

1. **Always use absolute web paths** in card metadata
2. **Never use Join-Path with $PSScriptRoot** for component paths
3. **Use JSON metadata format** for all new card endpoints
4. **Follow established patterns** from working endpoints (debug-console, memory-explorer, etc.)
5. **Test locally** before committing

---

## Status

✅ **Fixed** - Endpoint now returns proper JSON metadata with absolute paths

---

## End of Report
