# Comprehensive Migration and Improvements Plan

**Date:** 2026-01-17
**Status:** 📋 Plan Document

---

## Overview

This document outlines the comprehensive plan for:
1. File Explorer migration to WebhostFileExplorer app
2. Menu URL validation for optimal card output
3. Task Manager component CSS refactoring
4. Enhanced contrast-icon functionality for inline styles

---

## Part 1: File Explorer Migration

### Current State

```
routes/api/v1/ui/elements/file-explorer/
├── get.ps1              # Returns file tree data (NOT component metadata!)
├── get.security.json
├── post.ps1             # Handles file operations
└── post.security.json

public/elements/file-explorer/
└── component.js         # React component
```

### Target State

```
apps/WebhostFileExplorer/
├── app.yaml            ✅ Created
├── app_init.ps1        ⚠️ TODO
├── menu.yaml           ⚠️ TODO
├── README.md           ⚠️ TODO
├── public/
│   └── elements/
│       └── file-explorer/
│           └── component.js    ⚠️ TODO (copy from public/)
└── routes/
    └── api/v1/
        ├── files/                    ⚠️ TODO (data API)
        │   ├── get.ps1              # File tree endpoint
        │   ├── get.security.json
        │   ├── post.ps1             # File operations
        │   └── post.security.json
        └── ui/elements/
            └── file-explorer/        ⚠️ TODO (UI metadata)
                ├── get.ps1          # Returns component metadata
                └── get.security.json
```

### Key Difference from Other Migrations

**file-explorer is BOTH:**
1. **Data API** - GET/POST for file operations (should be at `/api/v1/files`)
2. **UI Component** - Needs metadata endpoint (at `/api/v1/ui/elements/file-explorer`)

### Migration Steps

#### Step 1: Create App Initialization

`apps/WebhostFileExplorer/app_init.ps1`:
```powershell
param(
    [hashtable]$PSWebServer,
    [string]$AppRoot
)

$MyTag = '[WebhostFileExplorer:Init]'

Write-Host "$MyTag Initializing File Explorer app..." -ForegroundColor Cyan

try {
    $PSWebServer['WebhostFileExplorer'] = [hashtable]::Synchronized(@{
        AppRoot = $AppRoot
        Initialized = Get-Date

        Settings = @{
            MaxFileSize = 10MB
            AllowedExtensions = @()  # All allowed
            MaxDepth = 10
        }

        Stats = [hashtable]::Synchronized(@{
            FilesUploaded = 0
            FoldersCreated = 0
            LastOperation = $null
        })
    })

    Write-Host "$MyTag File Explorer initialized successfully" -ForegroundColor Green
}
catch {
    Write-Host "$MyTag Failed to initialize: $($_.Exception.Message)" -ForegroundColor Red
    throw
}
```

#### Step 2: Create Menu Configuration

`apps/WebhostFileExplorer/menu.yaml`:
```yaml
- Name: File Explorer
  url: /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer
  hover_description: Browse and manage your personal file storage
  parent: Main Menu
  icon: folder-open
  roles:
    - authenticated
  tags:
    - files
    - storage
    - documents
    - upload
```

#### Step 3: Create UI Element Endpoint

`apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-explorer/get.ps1`:
```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'file-explorer'
        scriptPath = '/apps/WebhostFileExplorer/public/elements/file-explorer/component.js'
        title = 'File Explorer'
        description = 'Browse and manage your personal file storage'
        version = '1.0.0'
        dataEndpoint = '/apps/WebhostFileExplorer/api/v1/files'
        features = @(
            'User-scoped file storage'
            'Hierarchical folder structure'
            'File upload and download'
            'Folder creation and management'
            'File and folder renaming'
            'File and folder deletion'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'FileExplorer' -Message "Error loading file-explorer endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
```

`apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-explorer/get.security.json`:
```json
{"Allowed_Roles":["authenticated"]}
```

#### Step 4: Create Data API Endpoints

Move the current get.ps1 and post.ps1 (file tree and operations) to:
- `apps/WebhostFileExplorer/routes/api/v1/files/get.ps1` (file tree)
- `apps/WebhostFileExplorer/routes/api/v1/files/post.ps1` (file operations)

**Fix typo:** Change `context_reponse` to `context_response`

#### Step 5: Copy Component

```bash
cp -r public/elements/file-explorer apps/WebhostFileExplorer/public/elements/
```

#### Step 6: Update Component to Use New Endpoint

In `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`:

Change data API calls from:
```javascript
fetch('/api/v1/ui/elements/file-explorer')  // Old
```

To:
```javascript
fetch('/apps/WebhostFileExplorer/api/v1/files')  // New
```

#### Step 7: Update Main Menu

`routes/api/v1/ui/elements/main-menu/main-menu.yaml`:

**Remove:**
```yaml
- url: /api/v1/ui/elements/file-explorer
  Name: File Explorer
  ...
```

(Will be replaced by app menu entry with `parent: Main Menu`)

#### Step 8: Deprecate Old Endpoint

```bash
mv routes/api/v1/ui/elements/file-explorer routes/api/v1/ui/elements/file-explorer-deprecated
mv public/elements/file-explorer public/elements/file-explorer-deprecated
```

---

## Part 2: Menu URL Validation

### Task: Check Every Menu URL for Optimal Output

Review all menu items to ensure they return the correct content type for optimal card display.

### Categories of Menu URLs

#### 1. UI Element Endpoints (Should return JSON metadata)

**Expected Response:**
```json
{
  "component": "component-name",
  "scriptPath": "/path/to/component.js",
  "title": "Component Title",
  "description": "...",
  "version": "1.0.0"
}
```

**Headers:**
- `Content-Type: application/json`

**Examples to check:**
- `/api/v1/ui/elements/world-map`
- `/api/v1/ui/elements/system-log`
- All `/apps/*/api/v1/ui/elements/*` endpoints

#### 2. HTML Pages (Should return HTML)

**Expected Response:** Complete HTML page

**Headers:**
- `Content-Type: text/html`

**Card Title Format:** `HTML - [title from <title> tag]`

**Examples:**
- `/public/error-modal-demo.html`
- `/public/help/*.html` files

#### 3. Direct Component Files (Should return JavaScript)

**Expected Response:** JavaScript/JSX code

**Headers:**
- `Content-Type: application/javascript`

**Examples:**
- `/apps/*/public/elements/*/component.js` (direct URLs in menu)

#### 4. Data API Endpoints (Should return JSON data)

**Expected Response:** Actual data (not component metadata)

**Headers:**
- `Content-Type: application/json`

**Note:** These should NOT be in main menu as card targets

**Examples:**
- `/api/v1/debug/vars`
- `/api/v1/status/logging`

### Validation Script

Create `system/utility/Validate-MenuUrls.ps1`:

```powershell
#Requires -Version 7

<#
.SYNOPSIS
    Validates all menu URLs return optimal content for card display
.DESCRIPTION
    Tests each menu item URL and categorizes by response type
#>

param(
    [string]$MenuYamlPath = "routes/api/v1/ui/elements/main-menu/main-menu.yaml"
)

# Load menu data
$menuData = Get-Content $MenuYamlPath -Raw | ConvertFrom-Yaml

function Test-MenuUrl {
    param([string]$Url)

    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080$Url" -Method GET

        $contentType = $response.Headers['Content-Type']

        $result = @{
            Url = $Url
            StatusCode = $response.StatusCode
            ContentType = $contentType
            Category = $null
            Recommendation = $null
        }

        # Categorize
        if ($contentType -like '*application/json*') {
            $json = $response.Content | ConvertFrom-Json

            if ($json.component -and $json.scriptPath) {
                $result.Category = 'UI Element (Optimal)'
                $result.Recommendation = '✅ Correct - Returns component metadata'
            }
            elseif ($json.title -and $json.scriptPath) {
                $result.Category = 'UI Element (Good)'
                $result.Recommendation = '⚠️ Consider adding component property'
            }
            else {
                $result.Category = 'Data API'
                $result.Recommendation = '⚠️ Data API - consider wrapping in UI component'
            }
        }
        elseif ($contentType -like '*text/html*') {
            $html = $response.Content
            if ($html -match '<title>(.*?)</title>') {
                $title = $Matches[1]
                $result.Category = 'HTML Page'
                $result.Recommendation = "✅ Will display as: HTML - $title"
            }
            else {
                $result.Category = 'HTML Page (No Title)'
                $result.Recommendation = '⚠️ Add <title> tag for better card title'
            }
        }
        elseif ($contentType -like '*javascript*') {
            $result.Category = 'Direct JS File'
            $result.Recommendation = '⚠️ Consider using UI element endpoint instead'
        }

        return $result
    }
    catch {
        return @{
            Url = $Url
            StatusCode = $_.Exception.Response.StatusCode.value__
            Error = $_.Exception.Message
            Recommendation = '❌ Fix endpoint error'
        }
    }
}

# Process all menu items recursively
function Get-MenuUrls {
    param($Items)

    foreach ($item in $Items) {
        if ($item.url) {
            Test-MenuUrl -Url $item.url
        }

        if ($item.children) {
            Get-MenuUrls -Items $item.children
        }
    }
}

$results = Get-MenuUrls -Items $menuData
$results | Format-Table -AutoSize
```

### Recommended Fixes After Validation

For each URL type:

1. **Data APIs in main menu:**
   - Create UI element wrapper endpoint
   - Return component metadata with `dataEndpoint` property

2. **HTML pages without titles:**
   - Add `<title>` tags

3. **Direct JS files:**
   - Create UI element endpoint
   - Reference JS file via `scriptPath`

4. **Broken endpoints:**
   - Fix errors
   - Ensure 200 status

---

## Part 3: Task Manager CSS Refactoring

### Current Issue

`/apps/WebHostTaskManagement/public/elements/task-manager/component.js` contains hardcoded inline styles with color values:

```javascript
// Current (bad)
<div style={{ backgroundColor: '#1a1a1a', color: '#f0f0f0' }}>
<div style={{ border: '1px solid #444' }}>
```

### Problem

- ❌ Doesn't respect user theme
- ❌ Won't work with high contrast mode
- ❌ Can't adapt to dark/light themes
- ❌ Contrast issues

### Solution: CSS Classes + Variables

#### Step 1: Create CSS File

`apps/WebHostTaskManagement/public/elements/task-manager/style.css`:

```css
/* Task Manager Styles - Theme-aware */

:root {
  /* Light theme (default) */
  --task-bg: #ffffff;
  --task-text: #1a1a1a;
  --task-border: #d1d5db;
  --task-header-bg: #f3f4f6;
  --task-accent: #3b82f6;
  --task-success: #10b981;
  --task-warning: #f59e0b;
  --task-error: #ef4444;
  --task-hover: #f9fafb;
}

/* Dark theme detection */
@media (prefers-color-scheme: dark) {
  :root {
    --task-bg: #1a1a1a;
    --task-text: #f0f0f0;
    --task-border: #444;
    --task-header-bg: #2a2a2a;
    --task-accent: #60a5fa;
    --task-success: #34d399;
    --task-warning: #fbbf24;
    --task-error: #f87171;
    --task-hover: #252525;
  }
}

/* Respect card background variable if set */
.task-manager {
  background-color: var(--card-bg-color, var(--task-bg));
  color: var(--text-color, var(--task-text));
  border: 1px solid var(--border-color, var(--task-border));
  padding: 16px;
  border-radius: 8px;
}

.task-header {
  background-color: var(--task-header-bg);
  padding: 12px 16px;
  border-bottom: 1px solid var(--task-border);
  margin: -16px -16px 16px -16px;
  border-radius: 8px 8px 0 0;
}

.task-item {
  background-color: var(--task-bg);
  border: 1px solid var(--task-border);
  padding: 12px;
  margin-bottom: 8px;
  border-radius: 6px;
  transition: background-color 0.2s;
}

.task-item:hover {
  background-color: var(--task-hover);
}

.task-status-running {
  color: var(--task-accent);
  border-left: 3px solid var(--task-accent);
}

.task-status-completed {
  color: var(--task-success);
  border-left: 3px solid var(--task-success);
}

.task-status-failed {
  color: var(--task-error);
  border-left: 3px solid var(--task-error);
}

.task-status-pending {
  color: var(--task-warning);
  border-left: 3px solid var(--task-warning);
}

.task-actions {
  display: flex;
  gap: 8px;
  margin-top: 8px;
}

.task-btn {
  padding: 6px 12px;
  border: 1px solid var(--task-border);
  border-radius: 4px;
  background: var(--task-bg);
  color: var(--task-text);
  cursor: pointer;
  transition: all 0.2s;
}

.task-btn:hover {
  background: var(--task-hover);
}

.task-btn-primary {
  background: var(--task-accent);
  color: white;
  border-color: var(--task-accent);
}

.task-btn-danger {
  background: var(--task-error);
  color: white;
  border-color: var(--task-error);
}
```

#### Step 2: Update Component

`apps/WebHostTaskManagement/public/elements/task-manager/component.js`:

**Before:**
```javascript
window.cardComponents['task-manager'] = function(props) {
    return (
        <div style={{ backgroundColor: '#1a1a1a', color: '#f0f0f0', padding: '16px' }}>
            <div style={{ borderBottom: '1px solid #444', marginBottom: '16px' }}>
                <h2 style={{ color: '#f0f0f0', margin: '0 0 16px 0' }}>Tasks</h2>
            </div>
            <div style={{ border: '1px solid #444', padding: '12px', backgroundColor: '#2a2a2a' }}>
                Task content
            </div>
        </div>
    );
};
```

**After:**
```javascript
window.cardComponents['task-manager'] = function(props) {
    return (
        <>
            <link rel="stylesheet" href="/apps/WebHostTaskManagement/public/elements/task-manager/style.css" />
            <div className="task-manager">
                <div className="task-header">
                    <h2>Tasks</h2>
                </div>
                <div className="task-item task-status-running">
                    Task content
                </div>
            </div>
        </>
    );
};
```

#### Step 3: Update UI Element Endpoint

Ensure `apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1` includes:

```powershell
$cardInfo = @{
    component = 'task-manager'
    scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
    stylePath = '/apps/WebHostTaskManagement/public/elements/task-manager/style.css'  # NEW
    title = 'Task Management'
    # ...
}
```

---

## Part 4: Enhanced Contrast-Icon for Inline Styles

### Current Limitation

The high contrast button (`◐`) currently only fixes elements with CSS classes, but misses:
- Inline `style="..."` attributes
- Dynamically set styles via JavaScript
- React component inline styles

### Enhancement Plan

Update `public/psweb_spa.js` high contrast detection to also parse and fix inline styles.

#### Current Implementation

```javascript
const applyContrastFixes = (container) => {
    const elements = container.querySelectorAll('*');

    elements.forEach(el => {
        const computedStyle = getComputedStyle(el);
        const textColor = computedStyle.color;
        const bgColor = getBackgroundColor(el);

        // Only checks computed styles, not inline styles directly
    });
};
```

#### Enhanced Implementation

Add inline style parsing:

```javascript
const applyContrastFixes = (container) => {
    const elements = container.querySelectorAll('*');

    elements.forEach(el => {
        const computedStyle = getComputedStyle(el);

        // Get colors from computed style
        let textColor = computedStyle.color;
        let bgColor = getBackgroundColor(el);
        let borderColor = computedStyle.borderColor;

        // ENHANCEMENT: Also check inline styles
        const inlineStyle = el.getAttribute('style');
        let hasInlineStyles = false;

        if (inlineStyle) {
            // Parse inline style for color properties
            const styleObj = parseInlineStyle(inlineStyle);

            if (styleObj.color) {
                textColor = styleObj.color;
                hasInlineStyles = true;
            }

            if (styleObj.backgroundColor) {
                bgColor = styleObj.backgroundColor;
                hasInlineStyles = true;
            }

            if (styleObj.borderColor) {
                borderColor = styleObj.borderColor;
                hasInlineStyles = true;
            }
        }

        // Calculate contrast and fix if needed
        const textLum = getLuminance(parseColor(textColor));
        const bgLum = getLuminance(parseColor(bgColor));
        const ratio = getContrastRatio(textLum, bgLum);

        const isLargeText = parseFloat(computedStyle.fontSize) >= 18 ||
                           (parseFloat(computedStyle.fontSize) >= 14 && computedStyle.fontWeight >= 700);
        const minRatio = isLargeText ? 3.0 : 4.5;

        if (ratio < minRatio) {
            const adjustedColor = adjustColorForContrast(textColor, bgColor);

            // Apply fix with !important to override inline styles
            el.style.setProperty('color', adjustedColor, 'important');

            // If we fixed an inline style, note it
            if (hasInlineStyles) {
                el.setAttribute('data-contrast-fixed-inline', 'true');
                fixCount++;
            }
        }

        // Similar logic for borders
        if (borderColor && borderColor !== 'rgba(0, 0, 0, 0)') {
            const borderLum = getLuminance(parseColor(borderColor));
            const borderRatio = getContrastRatio(borderLum, bgLum);

            if (borderRatio < 3.0) {
                const adjustedBorderColor = adjustColorForContrast(borderColor, bgColor);
                el.style.setProperty('border-color', adjustedBorderColor, 'important');

                if (hasInlineStyles) {
                    fixCount++;
                }
            }
        }
    });
};

// Helper to parse inline style string into object
function parseInlineStyle(styleString) {
    const styleObj = {};
    const declarations = styleString.split(';');

    declarations.forEach(decl => {
        const [property, value] = decl.split(':').map(s => s.trim());
        if (property && value) {
            // Convert kebab-case to camelCase
            const camelProp = property.replace(/-([a-z])/g, g => g[1].toUpperCase());
            styleObj[camelProp] = value;
        }
    });

    return styleObj;
}
```

### Testing Enhanced Contrast

Test with various inline style scenarios:

```html
<!-- Test 1: Inline text color -->
<div style="color: #666; background: #2a2a2a;">
    Low contrast text
</div>

<!-- Test 2: React inline styles -->
<div style="{{backgroundColor: '#1a1a1a', color: '#888'}}">
    React inline style
</div>

<!-- Test 3: Mixed inline and class -->
<div className="task-item" style="border-color: #444;">
    Mixed styles
</div>

<!-- Test 4: Complex inline -->
<div style="padding: 10px; color: rgb(102, 102, 102); background-color: #2a2a2a; border: 1px solid #444;">
    Multiple inline properties
</div>
```

After clicking high contrast (◐):
- All text should have 4.5:1 contrast
- All borders should have 3:1 contrast
- Inline styles should be overridden with `!important`
- Badge should show total fixes including inline styles

---

## Implementation Priority

### Phase 1: Critical (Do First)
1. ✅ File Explorer migration - Complete app structure
2. ✅ Update menu URLs to point to new endpoints
3. ✅ Deprecate old endpoints

### Phase 2: Important (Do Soon)
4. ⚠️ Menu URL validation script
5. ⚠️ Fix any broken/sub-optimal menu URLs
6. ⚠️ Task Manager CSS refactoring

### Phase 3: Enhancement (Nice to Have)
7. ⚠️ Enhanced contrast-icon for inline styles
8. ⚠️ Test all changes thoroughly
9. ⚠️ Update documentation

---

## Testing Checklist

After implementing all changes:

### File Explorer
- [ ] App loads without errors
- [ ] Menu item appears correctly
- [ ] Card opens with file tree
- [ ] File upload works
- [ ] Folder creation works
- [ ] File operations work
- [ ] Data API at correct path

### Menu URLs
- [ ] All menu URLs return 200 status
- [ ] UI elements return JSON metadata
- [ ] HTML pages have titles
- [ ] Cards display correctly
- [ ] No broken links

### Task Manager
- [ ] Uses CSS classes (no inline styles)
- [ ] Respects light theme
- [ ] Respects dark theme
- [ ] High contrast works
- [ ] Colors adapt to theme

### Contrast Enhancement
- [ ] Detects inline styles
- [ ] Fixes inline text colors
- [ ] Fixes inline border colors
- [ ] Fixes React inline styles
- [ ] Badge shows correct count
- [ ] Works with existing class-based fixes

---

## Summary

This comprehensive plan covers:
1. **File Explorer Migration** - Full app structure with data and UI endpoints
2. **Menu URL Validation** - Ensure all URLs return optimal content
3. **Task Manager Refactoring** - Replace inline styles with CSS classes
4. **Contrast Enhancement** - Fix inline styles in addition to classes

Each section includes:
- Current state analysis
- Target state definition
- Step-by-step implementation
- Code examples
- Testing procedures

**Status:** Ready for implementation
**Complexity:** High
**Impact:** High - Improves consistency, maintainability, accessibility

---

**Last Updated:** 2026-01-17
**Created By:** Claude Code (AI Assistant)
**Type:** Implementation Plan
