# PSWebHost Menu System Documentation

**Date:** 2026-01-16
**Version:** 1.0

---

## Overview

PSWebHost uses a hierarchical menu system where apps can define their own menu entries that are dynamically integrated into the main navigation structure.

---

## Menu File Locations

### Main Menu
- **File:** `routes/api/v1/ui/elements/main-menu/main-menu.yaml`
- **Purpose:** Core system menu structure
- **Managed by:** System administrators

### App Menus
- **File:** `apps/[AppName]/menu.yaml`
- **Purpose:** App-specific menu entries
- **Managed by:** App developers

---

## Menu Entry Structure

### Basic Entry

```yaml
- Name: Menu Item Name
  parent: Apps\AppName
  url: /apps/AppName/api/v1/ui/elements/component-name
  hover_description: Description shown on hover
  icon: icon-name
  tags:
  - tag1
  - tag2
```

### Fields

| Field | Required | Description | Example |
|-------|----------|-------------|---------|
| `Name` | ✅ Yes | Display name of the menu item | `"Task Management"` |
| `parent` | ⚠️ Recommended | Menu hierarchy path (backslash-separated) | `"System Management\WebHost"` |
| `url` | ✅ Yes | URL to the UI element endpoint | `"/apps/AppName/api/v1/ui/elements/..."` |
| `hover_description` | ⚠️ Recommended | Tooltip text | `"Manage scheduled tasks"` |
| `icon` | ❌ Optional | Icon identifier | `"tasks"`, `"cog"`, `"chart-line"` |
| `tags` | ⚠️ Recommended | Search/filter tags | `["tasks", "jobs", "monitoring"]` |
| `roles` | ❌ Optional | Required user roles | `["admin", "system_admin"]` |

---

## Parent Path Hierarchy

The `parent` field defines where in the menu hierarchy an entry appears.

### Default Parent Path

If no `parent` field is specified:
- **Default:** `Apps\[AppName]`
- **Example:** An entry in `apps/vault/menu.yaml` defaults to `Apps\vault`

### Common Parent Paths

| Parent Path | Description | Usage |
|-------------|-------------|-------|
| `Apps\[AppName]` | Default app submenu | General app menu items |
| `System Management\WebHost` | System-level configuration | Core system tools |
| `Admin Tools` | Administrative utilities | Debug, testing, admin features |
| `Main Menu` | Top-level menu | Primary navigation items |

### Example Hierarchy

```
Main Menu
├── Apps
│   ├── vault
│   │   ├── Credential Manager
│   │   ├── Audit Log
│   │   └── Status
│   ├── WebhostRealtimeEvents
│   │   └── Real-time Events
│   └── UI_Uplot
│       ├── Chart Builder
│       └── Time Series Charts
├── System Management
│   └── WebHost
│       ├── Site Settings
│       ├── Apps
│       ├── Role Management
│       ├── User Management
│       └── Task Management    ← Custom parent path
└── Admin Tools
    ├── Unit Test Runner
    └── Debug Variables
```

---

## Menu to Component Flow

### Step 1: Menu Definition (menu.yaml)

```yaml
- Name: Task Management
  parent: System Management\WebHost
  url: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
  hover_description: Manage scheduled tasks
```

### Step 2: User Clicks Menu Item

- Menu system navigates to: `/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager`

### Step 3: Endpoint Returns Component Metadata

```powershell
# File: apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1

$cardInfo = @{
    component = 'task-manager'
    title = 'Task Management'
    scriptPath = '/apps/WebHostTaskManagement/public/elements/task-manager/component.js'
    width = 12
    height = 800
}

$jsonData = $cardInfo | ConvertTo-Json -Depth 5 -Compress
context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
```

### Step 4: SPA Framework Loads Component

- Reads `scriptPath` from response
- Dynamically loads component.js
- Renders component in UI

---

## Creating App Menu Files

### Example: WebHostTaskManagement

**File:** `apps/WebHostTaskManagement/menu.yaml`

```yaml
# WebHostTaskManagement App Menu
# Task scheduling, job monitoring, and runspace management

- Name: Task Management
  parent: System Management\WebHost
  url: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
  hover_description: Manage scheduled tasks, monitor background jobs, and view active runspaces
  icon: tasks
  tags:
  - tasks
  - jobs
  - runspaces
  - scheduling
  - automation
```

**Result:** Entry appears under: `System Management → WebHost → Task Management`

### Example: App with Default Parent

**File:** `apps/vault/menu.yaml`

```yaml
- Name: Credential Manager
  url: /apps/vault/api/v1/ui/elements/vault-manager
  hover_description: Manage stored credentials securely
  icon: key
  tags:
  - vault
  - credentials
```

**Result:** Entry appears under: `Apps → vault → Credential Manager` (default)

With explicit parent:

```yaml
- Name: Credential Manager
  parent: Apps\vault
  url: /apps/vault/api/v1/ui/elements/vault-manager
  hover_description: Manage stored credentials securely
  icon: key
```

**Result:** Same location, but explicitly defined

---

## Menu Entry Types

### 1. UI Component Entry

Points to a UI element endpoint that returns a component.

```yaml
- Name: Real-time Events
  parent: Apps\WebhostRealtimeEvents
  url: /api/v1/ui/elements/realtime-events
  hover_description: Monitor events in real-time
```

**Endpoint Returns:**
```json
{
  "component": "realtime-events",
  "scriptPath": "/apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js",
  "title": "Real-time Events"
}
```

### 2. Submenu/Group Entry

Contains child entries (no URL).

```yaml
- Name: System Management
  hover_description: System administration tools
  roles:
  - site_admin
  - system_admin
  collapsed: true
  children:
  - Name: Site Settings
    url: /api/v1/ui/elements/site-settings
```

### 3. External Link Entry

Links to external resources or documentation.

```yaml
- Name: Documentation
  url: https://docs.example.com
  hover_description: External documentation
  external: true
```

---

## Best Practices

### 1. Use Descriptive Parent Paths

✅ **Good:**
```yaml
parent: System Management\WebHost
```

❌ **Bad:**
```yaml
parent: System\Config\Web
```

### 2. Group Related Items

If an app has multiple menu items, use a consistent parent:

```yaml
- Name: Chart Builder
  parent: Apps\UI_Uplot
  url: /apps/uplot/api/v1/ui/elements/uplot-home

- Name: Time Series
  parent: Apps\UI_Uplot
  url: /apps/uplot/api/v1/ui/elements/time-series
```

### 3. Use Meaningful Tags

Tags help with search and filtering:

```yaml
tags:
- visualization  # Category
- charts         # Type
- uplot          # Technology
- analytics      # Purpose
```

### 4. Provide Hover Descriptions

Always include helpful descriptions:

✅ **Good:**
```yaml
hover_description: Manage scheduled tasks, monitor background jobs, and view active runspaces
```

❌ **Bad:**
```yaml
hover_description: Task management
```

### 5. Follow Naming Conventions

- Menu item names: Title Case
- Parent paths: Title Case with backslash separator
- URLs: lowercase with dashes or underscores
- Tags: lowercase, no spaces

---

## Menu Loading Process

### 1. Server Startup

1. Load `routes/api/v1/ui/elements/main-menu/main-menu.yaml`
2. Discover all `apps/*/menu.yaml` files
3. Parse and validate menu entries
4. Build hierarchical menu structure
5. Apply parent path mappings

### 2. Runtime

1. User requests main menu endpoint
2. Server merges main menu + app menus
3. Filters by user roles
4. Returns complete menu structure
5. Client renders menu hierarchy

---

## Troubleshooting

### Menu Item Not Appearing

**Possible Causes:**
1. `menu.yaml` file not in `apps/[AppName]/` directory
2. Invalid YAML syntax
3. App not enabled in `app.yaml`
4. User lacks required roles
5. Parent path doesn't exist in menu structure

**Solution:**
```powershell
# Verify app is enabled
Get-Content apps/AppName/app.yaml | Select-String "enabled"

# Check YAML syntax
Get-Content apps/AppName/menu.yaml | ConvertFrom-Yaml

# Test menu loading
# (Check server logs for menu parsing errors)
```

### Menu Item in Wrong Location

**Cause:** Incorrect `parent` path

**Solution:**
```yaml
# Verify parent path matches existing menu structure
# Use backslash separator: \
parent: System Management\WebHost  # ✅ Correct
parent: System Management/WebHost  # ❌ Wrong separator
```

### Component Not Loading

**Cause:** Menu points to endpoint, but endpoint doesn't return valid component metadata

**Solution:**
1. Verify endpoint exists: `apps/AppName/routes/api/v1/ui/elements/component/get.ps1`
2. Check endpoint returns `scriptPath` field
3. Verify component.js exists at scriptPath location

---

## Migration Checklist

When adding menu.yaml to an existing app:

- [ ] Create `apps/[AppName]/menu.yaml`
- [ ] Define `parent` path for hierarchy placement
- [ ] Specify `url` pointing to UI element endpoint
- [ ] Add `hover_description` for tooltips
- [ ] Include relevant `tags` for search
- [ ] Test menu appears in correct location
- [ ] Verify component loads when clicked
- [ ] Check role-based access works
- [ ] Update app documentation

---

## Examples

### System Management Tool

```yaml
# apps/WebHostTaskManagement/menu.yaml
- Name: Task Management
  parent: System Management\WebHost
  url: /apps/WebHostTaskManagement/api/v1/ui/elements/task-manager
  hover_description: Manage scheduled tasks, monitor background jobs, and view active runspaces
  icon: tasks
  tags:
  - tasks
  - scheduling
  - automation
```

### App with Multiple Entries

```yaml
# apps/UI_Uplot/menu.yaml
- Name: Chart Builder
  parent: Apps\UI_Uplot
  url: /apps/uplot/api/v1/ui/elements/uplot-home
  hover_description: Create and customize uPlot charts
  icon: chart-line
  tags:
  - visualization
  - charts

- Name: Time Series
  parent: Apps\UI_Uplot
  url: /apps/uplot/api/v1/ui/elements/time-series
  hover_description: Create time-based line charts
  icon: chart-line
  tags:
  - visualization
  - time-series
```

### Debug Tool

```yaml
# Debug tool in Admin Tools section
- Name: Unit Test Runner
  parent: Admin Tools
  url: /api/v1/ui/elements/unit-test-runner
  hover_description: Run in-browser unit tests
  roles:
  - debug
  tags:
  - testing
  - debug
```

---

## App Template

New apps created with `New-PSWebHostApp` automatically include a menu.yaml template:

**File:** `modules/PSWebHostAppManagement/New_App_Template/menu.yaml.template`

```yaml
# {{AppName}} App Menu
# {{AppDescription}}

- Name: {{AppName}}
  parent: Apps\{{AppName}}
  url: /apps/{{AppName}}/api/v1/ui/elements/{{AppName}}-home
  hover_description: {{AppDescription}}
  icon: grid
  tags:
  - {{AppName}}
  - app
```

**Customization Options:**

```yaml
# For system-level tools:
parent: System Management\WebHost

# For admin utilities:
parent: Admin Tools

# For app-specific items (default):
parent: Apps\{{AppName}}
```

---

## Reference

### Menu System Files

| File | Purpose |
|------|---------|
| `routes/api/v1/ui/elements/main-menu/main-menu.yaml` | Core system menu |
| `apps/*/menu.yaml` | App-specific menus |
| `modules/PSWebHostAppManagement/New_App_Template/menu.yaml.template` | Template for new apps |

### Parent Path Examples

| Parent Path | Result Location |
|-------------|----------------|
| (none) | `Apps\[AppName]` (default) |
| `Apps\[AppName]` | App submenu |
| `System Management\WebHost` | System config section |
| `Admin Tools` | Admin utilities section |
| `Main Menu` | Top level |

### Field Reference

| Field | Type | Required | Default |
|-------|------|----------|---------|
| Name | string | Yes | - |
| parent | string | No | `Apps\[AppName]` |
| url | string | Yes | - |
| hover_description | string | No | Name value |
| icon | string | No | - |
| tags | array | No | [] |
| roles | array | No | [] |
| collapsed | boolean | No | false |
| children | array | No | [] |

---

**Last Updated:** 2026-01-16
**Maintainer:** PSWebHost Development Team
