# Menu URL Validation Report

**Date:** 2026-01-17
**Status:** ⚠️ In Review

---

## Overview

This report analyzes all menu URLs across PSWebHost to validate that they return optimal content types for the card loading system.

### Content-Type Classification

The card loader supports three patterns:
1. **JSON Metadata** (Optimal for UI components) - Returns `application/json` with `scriptPath`
2. **Direct HTML** - Returns `text/html` for direct injection into cards
3. **Direct .js/.html files** - Files loaded directly by path

---

## Menu Files Analyzed

### Core Menu
- `routes/api/v1/ui/elements/main-menu/main-menu.yaml`

### App Menus (16 apps)
1. WindowsAdmin
2. LinuxAdmin
3. WSLManager
4. DockerManager
5. KubernetesManager
6. MySQLManager
7. RedisManager
8. SQLServerManager
9. UI_Uplot
10. vault
11. SQLiteManager
12. WebHostTaskManagement
13. WebHostMetrics
14. UnitTests
15. WebhostRealtimeEvents
16. WebhostFileExplorer

---

## Main Menu URL Analysis

### ✅ Optimal URLs (UI Element Endpoints)

These endpoints should return JSON metadata with component information:

| URL | Name | Expected Type | Status |
|-----|------|---------------|--------|
| `/api/v1/ui/elements/world-map` | World Map | JSON metadata | ✅ Assumed OK |
| `/api/v1/ui/elements/system-log` | System Log | JSON metadata | ✅ Assumed OK |
| `/api/v1/ui/elements/markdown-viewer` | Architecture | JSON metadata | ✅ Assumed OK |
| `/api/v1/ui/elements/site-settings` | Site Settings | JSON metadata | ⚠️ Needs verification |
| `/apps/WebHostAppManager/api/v1/ui/elements/apps-manager` | Apps | JSON metadata | ✅ Migrated |
| `/api/v1/ui/elements/admin/role-management` | Role Management | JSON metadata | ⚠️ Needs verification |
| `/api/v1/ui/elements/admin/users-management` | User Management | JSON metadata | ⚠️ Needs verification |
| `/api/v1/ui/elements/nodes-manager` | Linked Nodes | JSON metadata | ⚠️ Needs verification |

### ⚠️ Potentially Sub-Optimal URLs

These may not be returning optimal content for the card system:

#### 1. **Authentication Endpoint**
```yaml
- url: /api/v1/auth/getauthtoken
  Name: Logon
```

**Current Type:** Likely returns auth data (not a UI component)
**Recommendation:**
- If this needs a UI form, create `/api/v1/ui/elements/logon` endpoint
- Return JSON metadata pointing to a login component
- Keep auth API separate

#### 2. **Status Endpoints**
```yaml
- url: /api/v1/status/logging
  Name: Logging Status
```

**Current Type:** Likely returns status JSON (not component metadata)
**Recommendation:**
- Create `/api/v1/ui/elements/logging-status` endpoint
- Return component metadata that displays the status data
- Have component call `/api/v1/status/logging` for data

#### 3. **Debug Endpoints**
```yaml
- url: /api/v1/debug/test-error
  Name: Trigger Test Error

- url: /api/v1/debug/vars
  Name: Debug Variables
```

**Current Type:** Likely return data or trigger actions (not UI components)
**Recommendations:**
- **test-error**: Create UI component that triggers the error and displays result
- **vars**: Create `/api/v1/ui/elements/debug-vars` that returns component metadata

### ✅ Direct HTML Files

```yaml
- url: /public/error-modal-demo.html
  Name: Test Error Modals
```

**Status:** ✅ This is optimal - card loader will detect `text/html` and inject directly

---

## App Menu URL Analysis

### ✅ Apps Following Best Practices

#### WebHostMetrics
```yaml
- url: /apps/WebHostMetrics/api/v1/ui/elements/server-heatmap
  Name: Server Metrics
```
**Status:** ✅ Optimal - Returns JSON metadata

#### WebhostFileExplorer
```yaml
- url: /apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer
  Name: File Explorer
```
**Status:** ✅ Optimal - Returns JSON metadata (just migrated)

#### WebhostRealtimeEvents
```yaml
- url: /apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events
  Name: Real-time Events
```
**Status:** ✅ Optimal - Returns JSON metadata

#### UnitTests
```yaml
- url: /apps/UnitTests/api/v1/ui/elements/unit-test-runner
  Name: Unit Test Runner
```
**Status:** ✅ Optimal - Returns JSON metadata

### ⚠️ Apps Using Data API Endpoints in Menus

#### vault App
```yaml
- url: /apps/vault/api/v1/ui/elements/vault-manager
  Name: Credential Manager
  # ✅ This is correct

- url: /apps/vault/api/v1/audit
  Name: Audit Log
  # ⚠️ This is a DATA endpoint, not UI metadata

- url: /apps/vault/api/v1/status
  Name: Status
  # ⚠️ This is a DATA endpoint, not UI metadata
```

**Problem:**
- `/api/v1/audit` likely returns audit log data (JSON array)
- `/api/v1/status` likely returns status info (JSON object)
- These are not component metadata

**Recommendation:**
Create UI element endpoints:
```yaml
- url: /apps/vault/api/v1/ui/elements/audit-log
  Name: Audit Log
  # Returns: { component: "audit-log", scriptPath: "...", ... }

- url: /apps/vault/api/v1/ui/elements/status
  Name: Status
  # Returns: { component: "vault-status", scriptPath: "...", ... }
```

Then have the components call the data APIs:
- Component calls `/apps/vault/api/v1/audit` for data
- Component calls `/apps/vault/api/v1/status` for data

#### UI_Uplot App
```yaml
- url: /apps/uplot/api/v1/ui/elements/uplot-home
  Name: Chart Builder
  # ✅ Pattern looks correct

- url: /apps/uplot/api/v1/ui/elements/time-series
  Name: Time Series Charts
  # ⚠️ Needs verification - should return component metadata

# ... 5 more chart URLs
```

**Status:** ⚠️ Needs verification
- URLs follow the right pattern (`/ui/elements/...`)
- Need to verify they return JSON metadata, not just HTML or data

---

## URL Pattern Analysis

### Recommended Patterns

#### ✅ UI Component Endpoints (Optimal)
```
/api/v1/ui/elements/{component-name}
/apps/{AppName}/api/v1/ui/elements/{component-name}
```

**Returns:**
```json
{
  "component": "component-name",
  "scriptPath": "/path/to/component.js",
  "title": "Component Title",
  "description": "Component description",
  "version": "1.0.0",
  "width": 12,
  "height": 600
}
```

**Content-Type:** `application/json`

#### ✅ Direct HTML Files
```
/public/{filename}.html
/apps/{AppName}/public/{path}/{filename}.html
```

**Returns:** Full HTML document
**Content-Type:** `text/html`

#### ✅ Direct Component Files
```
/public/elements/{component}/component.js
/apps/{AppName}/public/elements/{component}/component.js
```

**Returns:** JavaScript component code
**Content-Type:** `application/javascript`

### ⚠️ Anti-Patterns

#### ❌ Data API Endpoints in Menu
```
/api/v1/{resource}          # Should not be in menu
/apps/{App}/api/v1/{resource}  # Should not be in menu
```

**Problem:** Returns data, not component metadata

**Solution:** Create a UI element endpoint that wraps the data API

**Example:**
```yaml
# ❌ BAD - Points directly to data API
- url: /api/v1/status/logging
  Name: Logging Status

# ✅ GOOD - Points to UI element that wraps data API
- url: /api/v1/ui/elements/logging-status
  Name: Logging Status
```

The UI element endpoint returns:
```json
{
  "component": "logging-status",
  "scriptPath": "/public/elements/logging-status/component.js",
  "title": "Logging Status"
}
```

The component JavaScript then calls `/api/v1/status/logging` to get data.

---

## Issues Identified

### High Priority

1. **vault app - Data APIs in menu**
   - `/apps/vault/api/v1/audit` - Should be wrapped in UI element
   - `/apps/vault/api/v1/status` - Should be wrapped in UI element

2. **Main menu - Status endpoint**
   - `/api/v1/status/logging` - Should have UI element wrapper

3. **Main menu - Debug endpoints**
   - `/api/v1/debug/test-error` - Should have UI element wrapper
   - `/api/v1/debug/vars` - Should have UI element wrapper

4. **Main menu - Auth endpoint**
   - `/api/v1/auth/getauthtoken` - Should have UI element wrapper or be HTML form

### Medium Priority

5. **Unverified UI elements**
   - `/api/v1/ui/elements/site-settings` - Verify returns metadata
   - `/api/v1/ui/elements/admin/role-management` - Verify returns metadata
   - `/api/v1/ui/elements/admin/users-management` - Verify returns metadata
   - `/api/v1/ui/elements/nodes-manager` - Verify returns metadata
   - `/api/v1/ui/elements/world-map` - Verify returns metadata
   - `/api/v1/ui/elements/system-log` - Verify returns metadata
   - `/api/v1/ui/elements/markdown-viewer` - Verify returns metadata

6. **UI_Uplot endpoints**
   - Verify all 7 chart URLs return component metadata

---

## Recommended Actions

### Immediate Actions

1. **Fix vault app menu**
   - Create `/apps/vault/api/v1/ui/elements/audit-log/get.ps1`
   - Create `/apps/vault/api/v1/ui/elements/status-display/get.ps1`
   - Update menu.yaml to use new UI element URLs
   - Keep data APIs at current paths for component use

2. **Fix status endpoint in main menu**
   - Create `/api/v1/ui/elements/logging-status/get.ps1`
   - Update main-menu.yaml to use new URL

3. **Fix debug endpoints**
   - Create `/api/v1/ui/elements/debug-test-error/get.ps1`
   - Create `/api/v1/ui/elements/debug-vars/get.ps1`
   - Update main-menu.yaml to use new URLs

### Verification Actions

4. **Test all UI element endpoints**
   - Create automated test script
   - Verify each `/ui/elements/...` endpoint returns JSON metadata
   - Verify `scriptPath` points to existing component
   - Verify Content-Type is `application/json`

5. **Test all direct HTML files**
   - Verify Content-Type is `text/html`
   - Verify HTML has `<title>` tag for card titles

---

## Testing Script

To validate all menu URLs, use this PowerShell script:

```powershell
# Menu URL Validator
$menuFiles = Get-ChildItem -Path "C:\SC\PsWebHost" -Recurse -Filter "menu.yaml"
$results = @()

foreach ($file in $menuFiles) {
    $content = Get-Content $file.FullName -Raw
    $yaml = ConvertFrom-Yaml $content

    foreach ($item in $yaml) {
        if ($item.url) {
            $url = "http://localhost:8080$($item.url)"

            try {
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing
                $contentType = $response.Headers['Content-Type']

                $results += [PSCustomObject]@{
                    File = $file.Name
                    Name = $item.Name
                    URL = $item.url
                    Status = $response.StatusCode
                    ContentType = $contentType
                    IsOptimal = $contentType -match 'application/json|text/html'
                }
            }
            catch {
                $results += [PSCustomObject]@{
                    File = $file.Name
                    Name = $item.Name
                    URL = $item.url
                    Status = "ERROR"
                    ContentType = $_.Exception.Message
                    IsOptimal = $false
                }
            }
        }
    }
}

# Display results
$results | Format-Table -AutoSize

# Show problematic URLs
$results | Where-Object { -not $_.IsOptimal } | Format-Table -AutoSize
```

---

## Content-Type Expectations

| Endpoint Pattern | Expected Content-Type | Card Behavior |
|------------------|----------------------|---------------|
| `/api/v1/ui/elements/*` | `application/json` | Load component via scriptPath |
| `/apps/*/api/v1/ui/elements/*` | `application/json` | Load component via scriptPath |
| `/public/*.html` | `text/html` | Inject HTML directly into card |
| `/public/*.js` | `application/javascript` | Load as component module |
| `/api/v1/*` (not /ui/elements/) | `application/json` | ⚠️ Data API - should not be in menu |

---

## Migration Priority

### Phase 1: Fix Data API URLs in Menus (High Priority)
1. vault /audit endpoint
2. vault /status endpoint
3. Main menu /status/logging
4. Main menu /debug/* endpoints

### Phase 2: Verify Existing UI Elements (Medium Priority)
1. Test all UI element endpoints
2. Verify component files exist
3. Check for broken scriptPath references

### Phase 3: Document Standards (Low Priority)
1. Create menu URL standards document
2. Add validation to app creation workflow
3. Create menu item templates

---

## Summary

### Current State
- **16 app menu files** analyzed
- **1 core menu file** analyzed
- **~30-40 menu URLs** identified

### Issues Found
- **5 high-priority** URLs using data APIs instead of UI elements
- **7+ medium-priority** URLs needing verification

### Recommendations
1. Always use `/ui/elements/` pattern for menu URLs
2. Data APIs should only be called by components, not in menus
3. Direct HTML/JS files are acceptable with proper Content-Type
4. Implement automated testing for menu URL validation

---

**Next Steps:**
1. Create UI element wrappers for data API endpoints
2. Run validation script across all menu URLs
3. Update documentation with best practices
4. Consider implementing pre-commit hooks for menu validation

---

**Last Updated:** 2026-01-17
**Status:** ⚠️ Needs Action on High Priority Items
