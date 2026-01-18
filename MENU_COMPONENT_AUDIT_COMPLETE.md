# Complete Menu to Component Audit

**Date:** 2026-01-16
**Status:** In Progress

## Summary

Audit all menu.yaml files to ensure every URL pointing to `/ui/elements/` has:
1. Valid endpoint file (get.ps1)
2. Endpoint returns `scriptPath` or serves HTML with component
3. Component file exists at the specified path

---

## Main Menu Analysis

File: `routes/api/v1/ui/elements/main-menu/main-menu.yaml`

### UI Elements in Main Menu

| URL | Endpoint Exists | Component Path | Component Exists | Status |
|-----|----------------|----------------|------------------|--------|
| `/api/v1/ui/elements/world-map` | ✅ | `public/elements/world-map/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/server-heatmap` | ✅ | `public/elements/server-heatmap/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/realtime-events` | ✅ | `public/elements/realtime-events/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/file-explorer` | ✅ | `public/elements/file-explorer/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/system-log` | ✅ | `public/elements/system-log/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/markdown-viewer` | ✅ | `public/elements/markdown-viewer/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/unit-test-runner` | ✅ | `public/elements/unit-test-runner/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/job-status` | ✅ | ❌ Returns job data JSON, not a component | ❌ | ⚠️ **NOT A UI COMPONENT** |
| `/api/v1/ui/elements/site-settings` | ✅ | `public/elements/site-settings/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/apps-manager` | ✅ | Needs verification | ❓ | ⏳ TODO |
| `/api/v1/ui/elements/admin/role-management` | ✅ | `public/elements/admin/role-management/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/admin/users-management` | ✅ | `public/elements/admin/users-management/component.js` | ✅ | ✅ OK |
| `/api/v1/ui/elements/nodes-manager` | ✅ | Needs verification | ❓ | ⏳ TODO |
| `/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager` | ✅ | `apps/WebHostTaskManagement/public/elements/task-manager/component.js` | ✅ | ✅ OK |

---

## Issues Found

### ❌ ISSUE 1: job-status is not a UI component

**Problem:**
- URL `/api/v1/ui/elements/job-status` is in the main menu
- Endpoint returns raw job data (JSON array), not a component layout
- No component.js file exists
- This should be a data API, not a UI element

**Fix Options:**
1. **Create a job-status component** at `public/elements/job-status/component.js`
2. **Remove from UI elements menu** - move to a different menu section as a data API
3. **Use the Task Management UI instead** - which includes job monitoring

**Recommendation:** Remove from main menu since Task Management provides better job monitoring UI.

---

## App Menu Files Status

| App | menu.yaml Exists | Status |
|-----|------------------|--------|
| DockerManager | ✅ | OK |
| KubernetesManager | ✅ | OK |
| LinuxAdmin | ✅ | OK |
| MySQLManager | ✅ | OK |
| RedisManager | ✅ | OK |
| SQLiteManager | ✅ | OK |
| SQLServerManager | ✅ | OK |
| UI_Uplot | ✅ | OK |
| UnitTests | ✅ | OK |
| vault | ✅ | OK |
| WebHostMetrics | ✅ | OK |
| WindowsAdmin | ✅ | OK |
| WSLManager | ✅ | OK |
| **WebHostTaskManagement** | ✅ **CREATED** | OK |
| WebhostRealtimeEvents | ❌ Missing | ⏳ TODO |

---

## Component Files Inventory

### Core Components (public/elements/)

```
✅ admin/
   ✅ role-management/component.js
   ✅ users-management/component.js
✅ chartjs/component.js
✅ database-status/component.js
✅ event-stream/component.js          (legacy - superseded by realtime-events)
✅ file-explorer/component.js
✅ footer-info/component.js
✅ help-viewer/component.js
✅ main-menu/component.js
✅ markdown-viewer/component.js
✅ memory-histogram/component.js
✅ profile/component.js
✅ realtime-events/component.js       (current events viewer)
✅ server-heatmap/component.js
✅ site-settings/component.js
✅ system-log/component.js
✅ system-status/component.js
✅ unit-test-runner/component.js
✅ uplot/component.js
✅ world-map/component.js
```

### App Components

```
✅ apps/WebHostTaskManagement/public/elements/task-manager/component.js
✅ apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js
✅ apps/vault/public/elements/vault-manager/component.js
... (additional app components to be audited)
```

---

## Action Items

### High Priority

- [ ] **Create menu.yaml for WebhostRealtimeEvents app**
  - Location: `apps/WebhostRealtimeEvents/menu.yaml`
  - Entry: Real-time Events component

- [ ] **Fix or remove job-status from main menu**
  - Option A: Create component at `public/elements/job-status/component.js`
  - Option B: Remove from UI elements, use Task Management instead
  - **Recommendation:** Remove from menu (Task Management has better UI)

- [ ] **Verify apps-manager component**
  - Check if endpoint returns scriptPath
  - Verify component.js exists

- [ ] **Verify nodes-manager component**
  - Check if endpoint returns scriptPath
  - Verify component.js exists

### Medium Priority

- [ ] **Audit all app menu.yaml files**
  - Verify each URL has valid component
  - Check component.js files exist

- [ ] **Document endpoint patterns**
  - Pattern A: HTML response with embedded component (vault-manager)
  - Pattern B: JSON with scriptPath (realtime-events, task-manager)
  - Standardize on Pattern B for new components

### Low Priority

- [ ] **Clean up legacy components**
  - `event-stream` is superseded by `realtime-events`
  - Consider deprecating or removing

- [ ] **Update app template**
  - Ensure menu.yaml is included in template
  - Include example component with scriptPath pattern

---

## Verification Commands

### Check if all menu URLs have valid endpoints:

```powershell
# Extract all /ui/elements/ URLs from main menu
$urls = Select-String -Path "routes/api/v1/ui/elements/main-menu/main-menu.yaml" -Pattern "url:\s+(/[^\s]+ui/elements/[^\s]+)" |
    ForEach-Object { $_.Matches.Groups[1].Value -replace '\?.*', '' }

foreach ($url in $urls) {
    $path = $url -replace '^/apps/([^/]+)/', 'apps/$1/routes/' -replace '^/', 'routes/'
    $endpointFile = "$path/get.ps1"

    $exists = Test-Path $endpointFile
    $status = if ($exists) { "✅" } else { "❌" }

    Write-Host "$status $url"
    Write-Host "   → $endpointFile"
}
```

### Check all app menu.yaml files:

```powershell
Get-ChildItem -Path "apps/*/menu.yaml" | ForEach-Object {
    $appName = $_.Directory.Name
    Write-Host "📋 $appName" -ForegroundColor Cyan

    $content = Get-Content $_.FullName -Raw
    $urls = [regex]::Matches($content, 'url:\s+([^\s\n]+)') | ForEach-Object { $_.Groups[1].Value }

    foreach ($url in $urls) {
        Write-Host "   - $url"
    }
}
```

---

## Recommendations

### 1. Standardize UI Element Pattern

**Adopt JSON with scriptPath pattern** for all new components:

```json
{
  "component": "component-name",
  "title": "Component Title",
  "description": "Description",
  "scriptPath": "/apps/AppName/public/elements/component-name/component.js",
  "width": 12,
  "height": 600
}
```

**Benefits:**
- Works with SPA framework
- Supports dashboard cards
- Dynamic loading
- Better performance

### 2. App Menu Integration

Ensure all apps with UI components have `menu.yaml`:

```yaml
# apps/AppName/menu.yaml
- Name: Component Name
  url: /apps/AppName/api/v1/ui/elements/component-name
  hover_description: Description
  icon: icon-name
  tags:
  - tag1
  - tag2
```

### 3. Remove Non-UI Elements from UI Menu

Move data-only endpoints (like job-status) out of `/ui/elements/`:
- Data APIs: `/api/v1/data/jobs`, `/api/v1/data/metrics`
- UI Components: `/api/v1/ui/elements/component-name`

---

## Next Steps

1. ✅ **Created:** `apps/WebHostTaskManagement/menu.yaml`
2. ⏳ **TODO:** Create `apps/WebhostRealtimeEvents/menu.yaml`
3. ⏳ **TODO:** Fix or remove job-status from main menu
4. ⏳ **TODO:** Complete verification of apps-manager and nodes-manager
5. ⏳ **TODO:** Audit all app menu.yaml entries for valid components

---

**Completion Status:** 85% Complete
**Blockers:** None
**Estimated Completion:** 15 minutes of verification work
