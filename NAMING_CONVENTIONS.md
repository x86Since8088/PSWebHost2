# PSWebHost Naming Conventions

**Version**: 1.0
**Last Updated**: 2026-01-16

---

## Purpose

Consistent naming prevents confusion and makes the codebase more navigable. This document defines the official naming patterns for all PSWebHost code.

---

## PowerShell Modules

**Pattern**: `PSWebHost_FeatureName`

**Rules**:
- Prefix: `PSWebHost_` (required)
- Feature name: PascalCase
- Separator: Underscore `_`
- No spaces

**Examples**:
```
✅ PSWebHost_Metrics
✅ PSWebHost_Support
✅ PSWebHost_Database
✅ PSWebHost_Tasks
✅ PSWebHost_AppManagement

❌ PSWebHostMetrics        (missing underscore)
❌ pswebhost_metrics       (wrong case)
❌ PSWebHost-Metrics       (wrong separator)
```

**Location**:
```
modules/PSWebHost_FeatureName/
└── PSWebHost_FeatureName.psm1

apps/AppName/modules/PSWebHost_AppName/
└── PSWebHost_AppName.psm1
```

---

## App Directory Names

**Pattern**: `PascalCase` (no underscores, no spaces)

**Rules**:
- PascalCase: Each word capitalized
- No underscores (exception: UI_Uplot for clarity)
- No spaces
- No hyphens

**Examples**:
```
✅ WebHostMetrics
✅ WebhostRealtimeEvents
✅ SQLiteManager
✅ vault                    (lowercase single word is OK)
✅ UI_Uplot                 (exception for clarity)

❌ WebHost_Metrics         (no underscores)
❌ webhost-metrics         (no hyphens)
❌ Webhost Metrics         (no spaces)
❌ webhostmetrics          (should be PascalCase)
```

**Location**:
```
apps/AppName/
```

---

## UI Element IDs

**Pattern**: `kebab-case`

**Rules**:
- All lowercase
- Words separated by hyphens `-`
- No underscores
- No spaces
- Used in layout.json and component registration

**Examples**:
```
✅ server-heatmap
✅ realtime-events
✅ vault-manager
✅ uplot-home
✅ main-menu

❌ serverHeatmap           (camelCase not allowed)
❌ server_heatmap          (underscores not allowed)
❌ ServerHeatmap           (PascalCase not allowed)
```

**Usage**:
```json
// layout.json
{
  "elements": {
    "server-heatmap": { ... },
    "realtime-events": { ... }
  }
}
```

```javascript
// Component registration
window.cardComponents['server-heatmap'] = ServerHeatmap;
```

---

## API Endpoint Paths

**Pattern**: `/apps/{AppName}/api/v1/{resource}`

**Rules**:
- App name: PascalCase (matches app directory name)
- API version: lowercase `v1`, `v2`, etc.
- Resource: lowercase, plural preferred
- Sub-resources: lowercase

**Examples**:
```
✅ /apps/WebHostMetrics/api/v1/metrics
✅ /apps/vault/api/v1/credentials
✅ /apps/SQLiteManager/api/v1/databases
✅ /apps/WebhostRealtimeEvents/api/v1/logs

❌ /apps/webhost-metrics/api/v1/metrics     (app name wrong case)
❌ /apps/WebHostMetrics/api/V1/metrics      (version wrong case)
❌ /apps/WebHostMetrics/api/v1/Metrics      (resource wrong case)
```

**Special Paths** (core system, not app-specific):
```
✅ /api/v1/session          (authentication)
✅ /api/v1/registration     (user registration)
✅ /api/v1/debug            (system debugging)
```

---

## Component File Names

**Pattern**: `component.js` (standardized)

**Rules**:
- Always named `component.js`
- Located in element's directory
- One component per directory

**Structure**:
```
apps/AppName/public/elements/element-name/
├── component.js           ✅ Standard name
├── styles.css            ✅ Optional
└── assets/               ✅ Optional
    └── icon.svg

❌ apps/AppName/public/elements/element-name/
   └── elementName.js     (wrong name)
```

**Benefits**:
- Easy to find: always same name
- Predictable paths in layout.json
- Consistent with module pattern

---

## Configuration Files

### App Manifests

**Pattern**: `app.yaml` (required)

**Location**: `apps/AppName/app.yaml`

**Required Fields**:
```yaml
name: Display Name
version: 1.0.0
description: Brief description
enabled: true
routePrefix: /apps/AppName
```

### Task Definitions

**Pattern**: `tasks.yaml`

**Locations**:
```
config/tasks.yaml                      # Global tasks
apps/AppName/config/tasks.yaml         # App tasks
```

### Security Files

**Pattern**: `{method}.security.json`

**Location**: Same directory as route script

**Examples**:
```
routes/api/v1/resource/
├── get.ps1
├── get.security.json       ✅ Matches script name
├── post.ps1
└── post.security.json      ✅ Matches script name
```

---

## Database Files

**Pattern**: `{purpose}.db` (SQLite)

**Rules**:
- Lowercase
- Descriptive purpose
- `.db` extension

**Examples**:
```
✅ pswebhost_perf.db
✅ vault.db
✅ app_data.db

❌ Database.db             (not descriptive)
❌ data.sqlite             (use .db extension)
```

**Location**:
```
PsWebHost_Data/
├── pswebhost_perf.db
└── apps/
    ├── vault/
    │   └── vault.db
    └── AppName/
        └── app.db
```

---

## Data Directories

**Pattern**: App-specific under centralized `PsWebHost_Data/`

**Structure**:
```
PsWebHost_Data/
├── logs/                  # Core logs
├── metrics/               # Core metrics (CSV files)
├── sessions/              # Session data
└── apps/                  # App-specific data
    ├── AppName/
    │   ├── exports/
    │   ├── uploads/
    │   └── cache/
    └── vault/
        └── backups/
```

**Naming Rules**:
- Directory names: lowercase, descriptive
- No spaces in directory names
- Organize by feature/purpose

---

## Background Job Names

**Pattern**: `{AppOrFeature}_{Purpose}`

**Rules**:
- PascalCase for app/feature name
- Underscore separator
- Descriptive purpose

**Examples**:
```
✅ PSWebHost_MetricsCollection
✅ WebHostMetrics_CsvCleanup
✅ vault_BackupDatabase
✅ UnitTests_TestRunner

❌ metricsJob              (not descriptive)
❌ PSWebHost-Metrics       (wrong separator)
```

**Task-generated Jobs** (via task engine):
```
Pattern: Task_{TaskName}_{Timestamp}

Examples:
Task_MetricsCsvCleanup_20260116_140530
Task_DatabaseBackup_20260116_030000
```

---

## Task Names

**Pattern**: `PascalCaseDescription` (in tasks.yaml)

**Rules**:
- PascalCase
- Descriptive action
- No underscores or hyphens

**Examples**:
```yaml
# ✅ Good task names
tasks:
  - name: CleanupOldLogs
  - name: DatabaseBackup
  - name: MetricsCsvCleanup
  - name: AggregateMetrics

# ❌ Bad task names
tasks:
  - name: cleanup_logs       (wrong case)
  - name: Task1              (not descriptive)
  - name: backup-db          (hyphens not allowed)
```

---

## Global State Keys

**Pattern**: PascalCase for app namespaces

**Structure**:
```powershell
$Global:PSWebServer = @{
    # Core system (PascalCase)
    Project_Root = @{ ... }
    DataRoot = "..."
    Sessions = @{ ... }

    # App namespaces (match app directory name)
    WebHostMetrics = @{ ... }
    vault = @{ ... }
    UI_Uplot = @{ ... }

    # Legacy (to be refactored)
    Metrics = @{ ... }          # Will move under WebHostMetrics
    MetricsJob = [Job]          # Will move under WebHostMetrics
}
```

**Rules**:
- App keys match app directory names exactly
- Core system keys use PascalCase with underscore for compound words
- Synchronized hashtables for cross-thread access

---

## CSS Class Names

**Pattern**: `psw-{component}-{element}`

**Rules**:
- Prefix: `psw-` (PSWebhost)
- Component: kebab-case
- Element: kebab-case
- All lowercase

**Examples**:
```css
/* ✅ Good class names */
.psw-card-header { }
.psw-server-heatmap-grid { }
.psw-realtime-events-row { }
.psw-vault-manager-form { }

/* ❌ Bad class names */
.serverHeatmap { }           /* no prefix, wrong case */
.card_header { }             /* no prefix, underscores */
.PSW-Header { }              /* wrong case */
```

**Benefits**:
- Avoids conflicts with other libraries
- Easy to identify PSWebHost styles
- Clear component ownership

---

## Variable Naming

### PowerShell Variables

**Pattern**: `$PascalCase` or `$camelCase`

**Rules**:
- **Script-level**: `$PascalCase`
- **Local/temporary**: `$camelCase`
- **Global**: `$Global:PascalCase`

**Examples**:
```powershell
# ✅ Script-level variables
$MyTag = '[AppName:Init]'
$DataPath = Join-Path $AppRoot "data"
$TaskContext = @{ ... }

# ✅ Local variables
$csvFiles = Get-ChildItem ...
$filteredData = $data | Where-Object ...
$startTime = Get-Date

# ✅ Global variables
$Global:PSWebServer
$Global:PSWebHostDotSourceLoaded

# ❌ Bad variable names
$my_tag                     # underscores
$DATAPATH                   # all caps
$d                          # not descriptive
```

### JavaScript Variables

**Pattern**: `camelCase`

**Rules**:
- Constants: `UPPER_SNAKE_CASE`
- React components: `PascalCase`
- Regular variables: `camelCase`

**Examples**:
```javascript
// ✅ Good JavaScript naming
const MAX_RETRY_COUNT = 3;
const API_BASE_URL = '/apps/WebHostMetrics';

class ServerHeatmap extends React.Component { }

const fetchData = () => { };
const metricData = [];
const isLoading = false;

// ❌ Bad JavaScript naming
const max_retry_count = 3;  // constants should be UPPER_CASE
const FetchData = () => { }; // functions should be camelCase
const metric_data = [];      // variables should be camelCase
```

---

## Function Naming

### PowerShell Functions

**Pattern**: `Verb-Noun` (approved verbs)

**Rules**:
- Use approved verbs: Get, Set, New, Remove, Invoke, Test, etc.
- Nouns in PascalCase
- Module prefix for exported functions

**Examples**:
```powershell
# ✅ Module functions (exported)
function Get-PSWebHostApp { }
function New-PSWebHostApp { }
function Invoke-PsWebHostTaskEngine { }
function Test-TaskSchedule { }

# ✅ Private functions (not exported)
function Get-RunningTaskJob { }
function Remove-CompletedTaskJobs { }

# ❌ Bad function names
function GetApp { }          # missing hyphen
function create-app { }      # wrong case
function DoTask { }          # unapproved verb
```

### JavaScript Functions

**Pattern**: `camelCase` (descriptive verbs)

**Examples**:
```javascript
// ✅ Good function names
function fetchMetrics() { }
function renderChart(data) { }
function handleError(error) { }

// ❌ Bad function names
function FetchMetrics() { }  // PascalCase only for classes
function get_data() { }      // underscores
function f1() { }            // not descriptive
```

---

## Documentation Files

**Pattern**: `ALL_CAPS.md` or `PascalCase.md`

**Standard Files** (ALL_CAPS):
```
README.md           ✅ User documentation
ARCHITECTURE.md     ✅ Technical architecture
MIGRATION.md        ✅ Migration notes
CHANGELOG.md        ✅ Version history
LICENSE.md          ✅ License
CONTRIBUTING.md     ✅ Contribution guide
```

**Feature-Specific Docs** (PascalCase):
```
TaskEngineSpec.md
ComponentGuide.md
ApiReference.md
```

**Location**:
```
/                           # Root-level system docs
├── README.md
├── ARCHITECTURE.md
└── MIGRATION_ROADMAP.md

apps/AppName/               # App-specific docs
├── README.md
├── ARCHITECTURE.md
└── MIGRATION.md
```

---

## Exception Cases

### Allowed Exceptions

These exceptions are permitted for historical or clarity reasons:

1. **UI_Uplot**: Underscore in app name for clarity (UI vs Uplot)
2. **vault**: All lowercase app name (single word, common noun)
3. **psweb_fetchWithAuthHandling**: Function name with underscore (core utility, established pattern)

### When to Request Exception

If you believe an exception is warranted:

1. Document the reason
2. Show how it improves clarity
3. Demonstrate no naming conflicts
4. Get approval before implementing

---

## Validation Checklist

Before committing code, verify:

- [ ] Module names use `PSWebHost_` prefix
- [ ] App directories are PascalCase
- [ ] Element IDs are kebab-case
- [ ] API routes are lowercase with app prefix
- [ ] Component files are named `component.js`
- [ ] Functions use approved PowerShell verbs
- [ ] Variables follow case conventions
- [ ] CSS classes use `psw-` prefix
- [ ] No spaces in any file/directory names
- [ ] Documentation files follow standard naming

---

## Quick Reference Table

| Item | Pattern | Example |
|------|---------|---------|
| **Module** | PSWebHost_Name | PSWebHost_Metrics |
| **App Directory** | PascalCase | WebHostMetrics |
| **Element ID** | kebab-case | server-heatmap |
| **API Route** | /apps/App/api/v1/resource | /apps/vault/api/v1/credentials |
| **Component File** | component.js | component.js |
| **Config File** | lowercase.yaml | tasks.yaml |
| **Database File** | purpose.db | vault.db |
| **Background Job** | Feature_Purpose | PSWebHost_MetricsCollection |
| **Task Name** | PascalCase | CleanupOldLogs |
| **PowerShell Var** | $PascalCase or $camelCase | $DataPath, $filteredData |
| **JavaScript Var** | camelCase | fetchData, metricData |
| **PowerShell Func** | Verb-Noun | Get-PSWebHostApp |
| **JavaScript Func** | camelCase | fetchMetrics |
| **CSS Class** | psw-component-element | psw-card-header |
| **Documentation** | ALLCAPS.md or PascalCase.md | README.md, ApiGuide.md |

---

## Enforcement

### Code Review Checklist

Reviewers should verify naming conventions during code review:

- Scan file names for pattern compliance
- Check API routes follow app prefix pattern
- Verify element IDs in layout.json
- Review new function names against approved verbs
- Check CSS class prefixes

### Automated Checks (Future)

Consider adding linting rules:
- PowerShell Script Analyzer custom rules
- ESLint rules for JavaScript naming
- File name pattern validators in CI/CD

---

**Document Status**: Official Standard
**Next Review**: When adding new naming categories
**Exceptions**: Request via GitHub issue with justification
