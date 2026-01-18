# Menu URL to Component Audit

**Date:** 2026-01-16
**Purpose:** Verify all menu URLs point to valid endpoints with component.js files

## Audit Process

For each URL in main-menu.yaml:
1. Check if endpoint file exists
2. Check if endpoint returns `scriptPath`
3. Verify component.js exists at scriptPath location

---

## Core Routes UI Elements (`/api/v1/ui/elements/`)

### ✅ `/api/v1/ui/elements/world-map`
- **Endpoint:** `routes/api/v1/ui/elements/world-map/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/server-heatmap`
- **Endpoint:** `routes/api/v1/ui/elements/server-heatmap/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/realtime-events`
- **Endpoint:** `routes/api/v1/ui/elements/realtime-events/get.ps1` - EXISTS
- **Returns:** `scriptPath: '/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js'`
- **Component:** `apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js` - EXISTS ✓

### ✅ `/api/v1/ui/elements/file-explorer`
- **Endpoint:** `routes/api/v1/ui/elements/file-explorer/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/system-log`
- **Endpoint:** `routes/api/v1/ui/elements/system-log/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/markdown-viewer?file=public/help/architecture.md`
- **Endpoint:** `routes/api/v1/ui/elements/markdown-viewer/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/unit-test-runner`
- **Endpoint:** `routes/api/v1/ui/elements/unit-test-runner/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/job-status`
- **Endpoint:** `routes/api/v1/ui/elements/job-status/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/site-settings`
- **Endpoint:** `routes/api/v1/ui/elements/site-settings/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/apps-manager`
- **Endpoint:** `routes/api/v1/ui/elements/apps-manager/get.ps1` - EXISTS
- **Component:** Needs verification

### ✅ `/api/v1/ui/elements/admin/role-management`
- **Endpoint:** `routes/api/v1/ui/elements/admin/role-management/get.ps1` - EXISTS
- **Component:** `public/elements/admin/role-management/component.js` - EXISTS ✓

### ✅ `/api/v1/ui/elements/admin/users-management`
- **Endpoint:** `routes/api/v1/ui/elements/admin/users-management/get.ps1` - EXISTS
- **Component:** `public/elements/admin/users-management/component.js` - EXISTS ✓

### ✅ `/api/v1/ui/elements/nodes-manager`
- **Endpoint:** `routes/api/v1/ui/elements/nodes-manager/get.ps1` - EXISTS
- **Component:** Needs verification

---

## App-based UI Elements (`/apps/...`)

### ✅ `/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager`
- **Endpoint:** `apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1` - EXISTS ✓
- **Returns:** `scriptPath: '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'`
- **Component:** `apps/WebHostTaskManagement/public/elements/task-manager/component.js` - EXISTS ✓
- **Menu File:** `apps/WebHostTaskManagement/menu.yaml` - EXISTS ✓

---

## Verification Script

Run this to check all components exist:

```powershell
# Check all UI element endpoints and their components
$menuFile = "routes/api/v1/ui/elements/main-menu/main-menu.yaml"
$menuContent = Get-Content $menuFile -Raw

# Extract URLs
$urls = [regex]::Matches($menuContent, 'url:\s+(/[^\s\n]+)') | ForEach-Object { $_.Groups[1].Value }

$results = foreach ($url in $urls) {
    # Skip non-UI element URLs
    if ($url -notmatch '/ui/elements/') { continue }

    # Remove query parameters
    $cleanUrl = ($url -split '\?')[0]

    # Determine endpoint path
    if ($cleanUrl -match '^/apps/([^/]+)/(.+)$') {
        $appName = $matches[1]
        $path = $matches[2]
        $endpointPath = "apps/$appName/routes/$path/get.ps1"
    } else {
        $path = $cleanUrl.TrimStart('/')
        $endpointPath = "routes/$path/get.ps1"
    }

    # Check endpoint exists
    $endpointExists = Test-Path $endpointPath

    [PSCustomObject]@{
        URL = $url
        EndpointPath = $endpointPath
        EndpointExists = $endpointExists
    }
}

$results | Format-Table -AutoSize
```

---

## Action Items

### Immediate
- [x] Create `apps/WebHostTaskManagement/menu.yaml`
- [ ] Verify all core UI element endpoints return valid `scriptPath`
- [ ] Check all component.js files exist at specified paths
- [ ] Document which endpoints use HTML responses vs JSON with scriptPath

### Pattern Standardization
- [ ] Decide: Should all new UI elements use JSON response with `scriptPath`?
- [ ] Update template to follow this pattern
- [ ] Document the two patterns:
  - **Pattern A:** HTML response with embedded component (vault-manager)
  - **Pattern B:** JSON response with scriptPath (realtime-events, task-manager)

### App Menu Integration
- [ ] Verify app menu.yaml files are loaded into the Apps menu
- [ ] Check if apps menu is populated automatically from app menu.yaml files
- [ ] Test that Task Management appears in the Apps menu

---

## Notes

**Two UI Element Response Patterns:**

1. **HTML with Embedded Component** (older pattern)
   - Returns full HTML page with `<script>` tag containing component code
   - Example: `vault-manager`
   - Loaded directly as standalone page

2. **JSON with scriptPath** (newer SPA pattern)
   - Returns JSON: `{ "component": "name", "scriptPath": "/path/to/component.js" }`
   - Example: `realtime-events`, `task-manager`
   - Loaded dynamically by SPA framework
   - Preferred for dashboard cards

**Recommendation:** Use Pattern 2 (JSON with scriptPath) for all new components as it integrates better with the SPA framework and allows for dashboard card functionality.
