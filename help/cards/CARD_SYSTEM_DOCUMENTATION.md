# PSWebHost Card System Documentation

**Agent: Agent_PSWebhost_Cards**
**Created:** 2026-02-23
**Version:** 1.0

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Card Architecture](#card-architecture)
3. [Card Loading Flow](#card-loading-flow)
4. [Layout System](#layout-system)
5. [Card Inventory](#card-inventory)
6. [Known Issues](#known-issues)
7. [Troubleshooting Guide](#troubleshooting-guide)
8. [Creating New Cards](#creating-new-cards)

---

## Executive Summary

### Site-Settings Card Analysis - ROOT CAUSE IDENTIFIED

**Status:** ✅ **WORKING CORRECTLY**

The site-settings card is **properly configured** and should load without issues:

- **Endpoint:** `C:\SC\PsWebHost\routes\cards\site-settings\get.ps1` ✅
- **Component:** `C:\SC\PsWebHost\public\elements\site-settings\component.js` ✅
- **Registration:** `window.cardComponents['site-settings']` ✅
- **scriptPath:** `/public/elements/site-settings/component.js` ✅

**Component Status:** Intentionally shows "Implementation Pending" banner - this is by design, not a bug.

### Critical Issues Found

1. **Duplicate scriptPath Keys** in help-viewer and markdown-viewer endpoints (lines 97-98, 127-128, 145-146, 156-157 in help-viewer; lines 15-16, 50-51, 77-78, 89-90 in markdown-viewer)
2. **File-explorer deprecated** component still referenced in layout.json

---

## Card Architecture

### Component Types

PSWebHost supports four types of cards:

#### 1. Dynamic React Components (Recommended)
- Require both endpoint + component.js
- Endpoint returns JSON with `scriptPath`
- Component registers in `window.cardComponents[cardId]`
- Supports complex interactions and state management

**Example:** site-settings, system-log, memory-explorer

#### 2. Static Elements
- Hardcoded in layout.json
- No endpoint required
- Examples: TitleCard, UserCard, footer-info

#### 3. HTML Injection Cards
- Endpoint returns `Content-Type: text/html`
- Content injected directly into card via iframe or dangerouslySetInnerHTML
- Used for simple static content

#### 4. IFrame Cards
- Generic iframe container for external URLs
- Fallback for non-card URLs

---

## Card Loading Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. User Action: Click menu item or openCard(url, title)        │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2. Extract elementId from URL                                   │
│    - /cards/system-log → "system-log"                          │
│    - /apps/Maps/cards/world-map → "world-map"                 │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3. Check if card already open                                   │
│    - If yes: scroll to existing card                           │
│    - If no: continue                                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4. loadComponentScript(elementId, null, endpointUrl)           │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 5. Fetch endpoint (e.g., /cards/system-log)                    │
│    - Check Content-Type header                                  │
└────────────────────────┬────────────────────────────────────────┘
                         │
                ┌────────┴────────┐
                ▼                 ▼
┌───────────────────────┐  ┌──────────────────────┐
│ Content-Type:         │  │ Content-Type:        │
│ application/json      │  │ text/html            │
└──────┬────────────────┘  └──────┬───────────────┘
       │                          │
       ▼                          ▼
┌───────────────────────┐  ┌──────────────────────┐
│ Parse JSON response   │  │ Extract HTML content │
│ Get scriptPath        │  │ Extract <title> tag  │
└──────┬────────────────┘  └──────┬───────────────┘
       │                          │
       ▼                          │
┌───────────────────────┐         │
│ Load component.js     │         │
│ via <script> tag      │         │
└──────┬────────────────┘         │
       │                          │
       ▼                          │
┌───────────────────────┐         │
│ Babel transforms JSX  │         │
│ to JavaScript         │         │
└──────┬────────────────┘         │
       │                          │
       ▼                          │
┌───────────────────────┐         │
│ Component registers:  │         │
│ window.cardComponents │         │
│   [elementId]         │         │
└──────┬────────────────┘         │
       │                          │
       └──────────┬───────────────┘
                  │
                  ▼
┌─────────────────────────────────────────────────────────────────┐
│ 6. Create card with unique ID: elementId-timestamp             │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 7. Fetch card settings from database (dimensions, colors)      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 8. Add to gridLayout with temporary 2x2 size                   │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 9. After 100ms: Apply saved dimensions and position            │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│ 10. Update URL with ?layout= parameter (compressed JSON)       │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layout System

### URL Layout Parameter (`?layout=`)

The layout system enables shareable/bookmarkable card configurations via URL parameters.

#### Encoding Process

1. **Layout Data Structure (v2):**
```json
{
  "version": 2,
  "cards": [
    {
      "id": "system-log-1234567890",
      "elementId": "system-log",
      "x": 0,
      "y": 0,
      "w": 6,
      "h": 12,
      "title": "System Log",
      "endpoint": "/cards/system-log",
      "backgroundColor": "#ff0000"
    }
  ]
}
```

2. **Compression:** Base64-encoded with URL-safe characters
   - Uses `btoa(encodeURIComponent(json))` with character code mapping
   - Reverse: `decodeURIComponent(atob(compressed))`

3. **URL Format:**
```
http://localhost:8080/?layout=eyJ2ZXJzaW9uIjoyLCJjYXJkcyI...
```

#### Decompression & Validation

The `parseLayoutFromURL()` function:
- Extracts `?layout=` parameter
- Decompresses base64 → JSON
- Validates required fields: `id`, `elementId`, `x`, `y`, `w`, `h`
- Loads cards with their saved positions and dimensions

#### Layout Persistence

- **URL updates** triggered by:
  - Opening new cards (`openCard`, `openCardCopy`)
  - Resizing cards
  - Moving cards
  - Closing cards

- **Update frequency:** After layout changes + 50ms debounce

---

## Card Inventory

### Core Cards (routes/cards/*)

| Card Name | Endpoint | Component | Status |
|-----------|----------|-----------|--------|
| **card-validation** | `/cards/card-validation` | `/public/elements/card-validation/component.js` | ⚠️ No component file |
| **event-stream** | `/cards/event-stream` | `/public/elements/event-stream/component.js` | ✅ Working |
| **help-viewer** | `/cards/help-viewer` | `/public/elements/help-viewer/component.js` | 🐛 Duplicate scriptPath keys |
| **job-status** | `/cards/job-status` | `/public/elements/job-status/component.js` | ⚠️ No component file |
| **main-menu** | `/cards/main-menu` | `/public/elements/main-menu/component.js` | ✅ Working |
| **markdown-viewer** | `/cards/markdown-viewer` | `/public/elements/markdown-viewer/component.js` | 🐛 Duplicate scriptPath keys |
| **memory-explorer** | `/cards/memory-explorer` | `/public/elements/memory-explorer/component.js` | ✅ Working |
| **nodes-manager** | `/cards/nodes-manager` | `/public/elements/nodes-manager/component.js` | ⚠️ No component file |
| **site-settings** | `/cards/site-settings` | `/public/elements/site-settings/component.js` | ✅ Working (shows "pending" by design) |
| **system-log** | `/cards/system-log` | `/public/elements/system-log/component.js` | ✅ Working |
| **system-status** | `/cards/system-status` | `/public/elements/system-status/component.js` | ✅ Working |

### App Cards (apps/*/routes/cards/*)

**41 app card endpoints detected:**

| App | Card | Endpoint | Component |
|-----|------|----------|-----------|
| **DockerManager** | docker-manager | `/apps/DockerManager/cards/docker-manager` | ✅ |
| **DockerManager** | dockermanager-home | `/apps/DockerManager/cards/dockermanager-home` | ✅ |
| **KubernetesManager** | kubernetes-status | `/apps/KubernetesManager/cards/kubernetes-status` | ✅ |
| **KubernetesManager** | kubernetesmanager-home | `/apps/KubernetesManager/cards/kubernetesmanager-home` | ✅ |
| **LinuxAdmin** | linux-cron | `/apps/LinuxAdmin/cards/linux-cron` | ✅ |
| **LinuxAdmin** | linux-services | `/apps/LinuxAdmin/cards/linux-services` | ✅ |
| **LinuxAdmin** | linuxadmin-home | `/apps/LinuxAdmin/cards/linuxadmin-home` | ✅ |
| **Maps** | world-map | `/apps/Maps/cards/world-map` | ✅ |
| **MySQLManager** | mysql-manager | `/apps/MySQLManager/cards/mysql-manager` | ✅ |
| **RedisManager** | redis-manager | `/apps/RedisManager/cards/redis-manager` | ✅ |
| **SQLiteManager** | sqlite-manager | `/apps/SQLiteManager/cards/sqlite-manager` | ✅ |
| **SQLiteManager** | sqlite-query-editor | `/apps/SQLiteManager/cards/sqlite-query-editor` | ✅ |
| **SQLServerManager** | sqlserver-manager | `/apps/SQLServerManager/cards/sqlserver-manager` | ✅ |
| **UI_Uplot** | area-chart | `/apps/UI_Uplot/cards/area-chart` | ✅ |
| **UI_Uplot** | bar-chart | `/apps/UI_Uplot/cards/bar-chart` | ✅ |
| **UI_Uplot** | heatmap | `/apps/UI_Uplot/cards/heatmap` | ✅ |
| **UI_Uplot** | metrics-chart | `/apps/UI_Uplot/cards/metrics-chart` | ✅ |
| **UI_Uplot** | multi-axis | `/apps/UI_Uplot/cards/multi-axis` | ✅ |
| **UI_Uplot** | scatter-plot | `/apps/UI_Uplot/cards/scatter-plot` | ✅ |
| **UI_Uplot** | time-series | `/apps/UI_Uplot/cards/time-series` | ✅ |
| **UI_Uplot** | uplot-home | `/apps/UI_Uplot/cards/uplot-home` | ✅ |
| **UnitTests** | unit-test-runner | `/apps/UnitTests/cards/unit-test-runner` | ✅ |
| **vault** | vault-manager | `/apps/vault/cards/vault-manager` | ✅ |
| **WebHostAppManager** | apps-manager | `/apps/WebHostAppManager/cards/apps-manager` | ✅ |
| **WebHostDebugExtensions** | debug-console | `/apps/WebHostDebugExtensions/cards/debug-console` | ✅ |
| **WebHostDebugVariables** | debug-variables | `/apps/WebHostDebugVariables/cards/debug-variables` | ✅ |
| **WebhostFileExplorer** | file-explorer | `/apps/WebhostFileExplorer/cards/file-explorer` | ✅ |
| **WebhostFileExplorer** | file-sharing-modal | `/apps/WebhostFileExplorer/cards/file-sharing-modal` | ✅ |
| **WebhostFileExplorer** | hex-editor | `/apps/WebhostFileExplorer/cards/hex-editor` | ✅ |
| **WebhostFileExplorer** | text-editor | `/apps/WebhostFileExplorer/cards/text-editor` | ✅ |
| **WebHostHelpViewer** | help-viewer | `/apps/WebHostHelpViewer/cards/help-viewer` | ✅ |
| **WebHostMetrics** | cpu-histogram | `/apps/WebHostMetrics/cards/cpu-histogram` | ✅ |
| **WebHostMetrics** | memory-histogram | `/apps/WebHostMetrics/cards/memory-histogram` | ✅ |
| **WebHostMetrics** | server-heatmap | `/apps/WebHostMetrics/cards/server-heatmap` | ✅ |
| **WebhostRealtimeEvents** | realtime-events | `/apps/WebhostRealtimeEvents/cards/realtime-events` | ✅ |
| **WebHostTaskManagement** | task-manager | `/apps/WebHostTaskManagement/cards/task-manager` | ✅ |
| **WindowsAdmin** | service-control | `/apps/WindowsAdmin/cards/service-control` | ✅ |
| **WindowsAdmin** | task-scheduler | `/apps/WindowsAdmin/cards/task-scheduler` | ✅ |
| **WindowsAdmin** | windowsadmin-home | `/apps/WindowsAdmin/cards/windowsadmin-home` | ✅ |
| **WSLManager** | wsl-manager | `/apps/WSLManager/cards/wsl-manager` | ✅ |
| **WSLManager** | wslmanager-home | `/apps/WSLManager/cards/wslmanager-home` | ✅ |

### Static Elements (layout.json)

| Element | Type | Component Path | Status |
|---------|------|----------------|--------|
| title | Static | N/A (hardcoded TitleCard) | ✅ |
| user-card | Static | N/A (hardcoded UserCard) | ✅ |
| main-menu | Menu | `/public/elements/main-menu/component.js` | ✅ |
| system-status | Log | `/public/elements/system-status/component.js` | ✅ |
| world-map | Map | `/apps/Maps/public/elements/world-map/component.js` | ✅ |
| server-heatmap | Heatmap | `/apps/WebHostMetrics/public/elements/server-heatmap/component.js` | ✅ |
| realtime-events | Events | `/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` | ✅ |
| header-icon | Icon | `/public/elements/header-icon/component.js` | ⚠️ No component file |
| footer-info | Footer | `/public/elements/footer-info/component.js` | ✅ |

---

## Known Issues

### Critical Issues

#### 1. Duplicate `scriptPath` Keys in Endpoints

**Affected Files:**
- `C:\SC\PsWebHost\routes\cards\help-viewer\get.ps1`
- `C:\SC\PsWebHost\routes\cards\markdown-viewer\get.ps1`

**Problem:**
Both endpoints have duplicate `scriptPath` keys in their JSON responses (appears 2-4 times in error handlers).

**Example from help-viewer/get.ps1:**
```powershell
$errorResponse = @{
    scriptPath = '/public/elements/help-viewer/component.js'  # Line 97
    scriptPath = '/public/elements/help-viewer/component.js'  # Line 98 - DUPLICATE!
    status = 'error'
    message = 'No help file specified. Use ?file=path/to/file.md'
}
```

**Impact:**
- PowerShell hashtables allow duplicate keys (last value wins)
- JSON conversion may behave unexpectedly
- Confusing for developers reading the code

**Fix Required:**
Remove duplicate `scriptPath` lines from all error response blocks.

#### 2. Missing Component Files

The following cards have endpoints but no component files:

- `card-validation` - No component at `/public/elements/card-validation/component.js`
- `job-status` - No component at `/public/elements/job-status/component.js`
- `nodes-manager` - No component at `/public/elements/nodes-manager/component.js`
- `header-icon` - Referenced in layout.json but no component file

**Impact:** Cards will fail to load if opened.

#### 3. Deprecated File Explorer

`file-explorer-deprecated` component still exists and is referenced in layout.json gridLayout.

**Fix Required:**
- Remove from gridLayout in layout.json
- Update references to use `/apps/WebhostFileExplorer/cards/file-explorer`

---

## Troubleshooting Guide

### Card Won't Load

**Symptom:** Card opens but shows blank or error message

**Diagnostic Steps:**

1. **Check Browser Console:**
```javascript
// Check if component is registered
console.log(window.cardComponents['card-name']);

// Should return a React component function, not undefined
```

2. **Check Endpoint Response:**
```bash
# Test endpoint directly
curl http://localhost:8080/cards/card-name

# Should return JSON with scriptPath or HTML content
```

3. **Check Network Tab:**
- Look for 404 errors on component.js files
- Check Content-Type headers
- Verify scriptPath URLs are correct

4. **Check File Paths:**
- Endpoint: `routes/cards/[card-name]/get.ps1`
- Component: `public/elements/[card-name]/component.js`
- Path in endpoint should match actual file location

### Common Errors

#### Error: "No component path found for [elementId]"

**Cause:** Endpoint doesn't return `scriptPath` in JSON response

**Fix:**
Add `scriptPath` to endpoint response:
```powershell
$cardInfo = @{
    component = 'my-card'
    scriptPath = '/public/elements/my-card/component.js'
    title = 'My Card'
}
```

#### Error: "window.cardComponents[...] is undefined"

**Cause:** Component script didn't register itself

**Fix:**
Add registration at end of component.js:
```javascript
window.cardComponents = window.cardComponents || {};
window.cardComponents['my-card'] = MyCardComponent;
```

#### Card Shows "Implementation Pending"

**Cause:** Intentional design pattern for incomplete features (e.g., site-settings)

**Not a bug!** This is the component working correctly but showing placeholder UI.

#### Card Appears But Has Wrong Size

**Cause:** Card settings not saved in database or findNextFreePosition collision

**Fix:**
- Clear card settings: DELETE from card_settings WHERE endpoint = '/cards/card-name'
- Restart and re-open card to save default dimensions

### Debugging Card Loading

**Enable verbose logging:**
```javascript
// In browser console before opening card
window.logLevel = 'debug';

// Open card
window.openCard('/cards/system-log', 'System Log');

// Check console for:
// - [loadComponentScript] messages
// - [openCard] messages
// - [URL Layout] messages
```

**Check layout state:**
```javascript
// Current grid layout
console.log(window.appData?.gridLayout);

// Open card IDs
console.log(window.appData?.openCards);

// Elements registry
console.log(window.appData?.elements);
```

---

## Creating New Cards

### Step-by-Step Guide

#### 1. Create Endpoint

**File:** `routes/cards/my-new-card/get.ps1`

```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Return card metadata
    $cardInfo = @{
        component = 'my-new-card'
        scriptPath = '/public/elements/my-new-card/component.js'
        title = 'My New Card'
        description = 'Description of what this card does'
        version = '1.0.0'
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardLoad' -Message "Error loading card: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
```

#### 2. Create Component

**File:** `public/elements/my-new-card/component.js`

```javascript
// My New Card Component
const MyNewCardComponent = ({ url, element }) => {
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);

    React.useEffect(() => {
        // Fetch data from API
        fetch('/api/v1/my-data')
            .then(res => res.json())
            .then(data => {
                setData(data);
                setLoading(false);
            })
            .catch(err => {
                console.error('Failed to load data:', err);
                setLoading(false);
            });
    }, []);

    if (loading) {
        return React.createElement('div', {
            className: 'loading',
            style: { padding: '20px', textAlign: 'center' }
        }, 'Loading...');
    }

    return React.createElement('div', {
        className: 'my-new-card',
        style: { padding: '16px' }
    },
        React.createElement('h2', null, 'My New Card'),
        React.createElement('p', null, JSON.stringify(data, null, 2))
    );
};

// IMPORTANT: Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['my-new-card'] = MyNewCardComponent;
```

#### 3. Add to Menu (Optional)

**File:** `routes/cards/main-menu/main-menu.yaml`

```yaml
- Name: My Section
  roles:
  - authenticated
  children:
  - Name: My New Card
    url: /cards/my-new-card
    hover_description: Description of my card
    tags:
    - custom
    - feature
```

#### 4. Test the Card

```javascript
// In browser console
window.openCard('/cards/my-new-card', 'My New Card');

// Verify registration
console.log(window.cardComponents['my-new-card']);
```

### Best Practices

1. **Always use React.createElement** - No JSX unless using Babel transform
2. **Register component** - `window.cardComponents[cardId] = Component`
3. **Error handling** - Wrap API calls in try/catch
4. **Loading states** - Show loading indicator while fetching data
5. **Unique IDs** - Use `${elementId}-${Date.now()}` for card IDs
6. **scriptPath must match** - Endpoint scriptPath must point to real file
7. **No duplicate keys** - Check PowerShell hashtables for duplicate keys
8. **Content-Type matters** - JSON returns scriptPath, HTML injects content

---

## Card Configuration Reference

### Endpoint Response Format

**Standard JSON Response:**
```json
{
  "component": "card-name",
  "scriptPath": "/public/elements/card-name/component.js",
  "title": "Card Title",
  "description": "Card description",
  "version": "1.0.0",
  "width": 12,
  "height": 14
}
```

**HTML Response:**
Just return `Content-Type: text/html` and the content will be injected.

### Component Registration

**Always include at end of component.js:**
```javascript
window.cardComponents = window.cardComponents || {};
window.cardComponents['card-id'] = ComponentName;
```

**Component naming patterns:**
- Hyphenated ID: `'system-log'` → `SystemLogCard`
- Nested paths: `'admin/users-management'` → `UserManagementComponent`
- App cards: `'world-map'` → `WorldMapCard` (no app prefix needed)

### Card Dimensions

Default card sizing in `layout.json`:
```json
{
  "i": "card-id",
  "w": 12,  // Width (1-12 grid columns)
  "h": 14,  // Height (arbitrary units, ~15px per unit)
  "x": 0,   // X position
  "y": 0    // Y position
}
```

**Recommended sizes:**
- Small card: `w: 3, h: 8`
- Medium card: `w: 6, h: 12`
- Large card: `w: 12, h: 14`
- Full width: `w: 12`

---

## Summary of Findings

### What Works

✅ Card loading system is well-architected
✅ Site-settings card is properly configured (shows "pending" by design)
✅ 41 app cards with proper endpoints and components
✅ URL layout system enables shareable configurations
✅ React components register correctly in window.cardComponents
✅ Both JSON and HTML content types supported

### What Needs Fixing

🐛 Duplicate `scriptPath` keys in help-viewer and markdown-viewer endpoints
⚠️ Missing components: card-validation, job-status, nodes-manager, header-icon
⚠️ Deprecated file-explorer still in layout.json gridLayout

### Recommendations

1. **Fix duplicate scriptPath keys** - Remove duplicates from error handlers
2. **Create missing components** - Or remove card endpoints if not needed
3. **Clean up layout.json** - Remove file-explorer-deprecated references
4. **Add validation** - Create card-validation component to test all cards
5. **Document menu.yaml** - Add comments explaining structure and roles

---

**Document Maintained By:** Agent_PSWebhost_Cards
**Last Updated:** 2026-02-23
**Next Review:** When new cards are added or architecture changes
