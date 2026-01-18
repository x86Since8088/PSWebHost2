# WebHost Metrics - Migration Summary

## Overview

All metrics-related functionality has been migrated from core PSWebHost components into a dedicated **WebHostMetrics** app. This consolidation improves modularity, maintainability, and makes the metrics system a cohesive, self-contained application.

## Migration Date

**Completed:** 2026-01-16

## What Was Moved

### 1. Module
**From:** `modules/PSWebHost_Metrics/`
**To:** `apps/WebHostMetrics/modules/PSWebHost_Metrics/`

**Changes:**
- No code changes required
- Module automatically added to PSModulePath by app framework
- Import statements updated to use module name (not path)

### 2. API Routes
**From:** `routes/api/v1/metrics/`
**To:** `apps/WebHostMetrics/routes/api/v1/metrics/`

**Changes:**
- Routes now served under `/apps/WebHostMetrics/` prefix
- All endpoint security files maintained
- Historical endpoint preserved at `metrics/history/`

**New Endpoints:**
- `/apps/WebHostMetrics/api/v1/metrics` (was `/api/v1/metrics`)
- `/apps/WebHostMetrics/api/v1/metrics/history` (was `/api/v1/metrics/history`)
- `/apps/WebHostMetrics/api/v1/ui/elements/server-heatmap` (new wrapper)

### 3. UI Component
**From:** `public/elements/server-heatmap/`
**To:** `apps/WebHostMetrics/public/elements/server-heatmap/`

**Changes:**
- Component path updated in `layout.json`
- UPlot source URL updated to use new API path
- Component metadata endpoint created
- Explicit `scriptPath` returned from UI element endpoint

### 4. Utility Scripts
**From:** `system/utility/Restart-MetricsCollection.ps1`
**To:** `apps/WebHostMetrics/Restart-MetricsCollection.ps1`

**Changes:**
- Script moved to app directory
- Can be run from app context
- No code changes required

### 5. Documentation
**Created New:**
- `apps/WebHostMetrics/README.md` - User documentation
- `apps/WebHostMetrics/ARCHITECTURE.md` - Technical architecture
- `apps/WebHostMetrics/MIGRATION.md` - This file

## Code Changes Required

### system/init.ps1

**Lines 778-781 (Module Import):**
```powershell
# Before:
Import-Module PSWebHost_Metrics -Force -ErrorAction Stop

# After (with comment):
# Import metrics module from WebHostMetrics app
# The app framework has already added apps/WebHostMetrics/modules to PSModulePath
Import-Module PSWebHost_Metrics -Force -ErrorAction Stop
```

**Line 805 (Background Job Module Import):**
```powershell
# Before:
Import-Module (Join-Path $ModulePath "PSWebHost_Metrics") -Force -ErrorAction Stop

# After:
# Module is in apps/WebHostMetrics/modules which is already in PSModulePath
Import-Module PSWebHost_Metrics -Force -ErrorAction Stop
```

### public/layout.json

**server-heatmap Element:**
```json
// Before:
"server-heatmap": {
    "Type": "Heatmap",
    "Title": "Server Load",
    "componentPath": "/public/elements/server-heatmap/component.js"
}

// After:
"server-heatmap": {
    "Type": "Heatmap",
    "Title": "Server Metrics",
    "componentPath": "/apps/WebHostMetrics/public/elements/server-heatmap/component.js"
}
```

### Component API Reference

**apps/WebHostMetrics/public/elements/server-heatmap/component.js (Line 417):**
```javascript
// Before:
url: `/api/v1/ui/elements/uplot?source=/api/v1/metrics/history&...`

// After:
url: `/api/v1/ui/elements/uplot?source=/apps/WebHostMetrics/api/v1/metrics/history&...`
```

## New Files Created

### App Configuration
- `apps/WebHostMetrics/app.yaml` - App manifest
- `apps/WebHostMetrics/menu.yaml` - Menu integration

### UI Element Wrapper
- `apps/WebHostMetrics/routes/api/v1/ui/elements/server-heatmap/get.ps1`
- `apps/WebHostMetrics/routes/api/v1/ui/elements/server-heatmap/get.security.json`

### Documentation
- `apps/WebHostMetrics/README.md`
- `apps/WebHostMetrics/ARCHITECTURE.md`
- `apps/WebHostMetrics/MIGRATION.md` (this file)

## What Was NOT Changed

### Data Storage
- CSV files remain in: `PsWebHost_Data/metrics/`
- In-memory storage: `$Global:PSWebServer.Metrics`
- No data migration required

### Background Job
- Job name: `PSWebHost_MetricsCollection` (unchanged)
- Job reference: `$Global:PSWebServer.MetricsJob` (unchanged)
- Collection interval: 5 seconds (unchanged)

### Module Functionality
- All functions remain identical
- No breaking changes to API
- Backward compatibility maintained

## Testing Performed

### 1. Module Loading
✅ Module imports successfully from app directory
✅ PSModulePath includes apps/WebHostMetrics/modules
✅ Background job imports module correctly

### 2. Data Collection
✅ Background job starts and runs
✅ CSV files created in PsWebHost_Data/metrics/
✅ In-memory storage populated correctly

### 3. API Endpoints
✅ `/apps/WebHostMetrics/api/v1/metrics` returns current metrics
✅ `/apps/WebHostMetrics/api/v1/metrics?action=realtime` returns CSV data
✅ `/apps/WebHostMetrics/api/v1/metrics/history` returns historical data

### 4. UI Component
✅ Component loads from app path
✅ Dashboard renders correctly
✅ Charts display real-time data
✅ UPlot integration works
✅ Auto-refresh functioning

### 5. Background Job
✅ Job starts on server initialization
✅ Metrics collected every 5 seconds
✅ CSV files written correctly
✅ No errors in job output

## Rollback Plan

If issues are encountered, rollback steps:

### 1. Revert system/init.ps1
```powershell
# Line 778-781: Restore original module import
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_Metrics") -Force

# Line 805: Restore original job module import
Import-Module (Join-Path $ModulePath "PSWebHost_Metrics") -Force -ErrorAction Stop
```

### 2. Revert layout.json
```json
"server-heatmap": {
    "Type": "Heatmap",
    "Title": "Server Load",
    "componentPath": "/public/elements/server-heatmap/component.js"
}
```

### 3. Restore API Routes
```powershell
# Copy routes back to original location
Copy-Item -Path apps/WebHostMetrics/routes/api/v1/metrics/* -Destination routes/api/v1/metrics/ -Recurse
```

### 4. Disable App
```yaml
# Edit apps/WebHostMetrics/app.yaml
enabled: false
```

### 5. Restart Server
Full server restart to clear module cache and reload original configuration.

## Benefits of Migration

### 1. Modularity
- Metrics system is now a self-contained app
- Can be enabled/disabled independently
- Clear ownership and responsibility

### 2. Maintainability
- All related files in one location
- Easier to find and update code
- Comprehensive documentation in app directory

### 3. Consistency
- Follows PSWebHost app framework patterns
- Menu integration via `menu.yaml`
- Standard route prefix pattern (`/apps/AppName/`)

### 4. Scalability
- App can be extended independently
- New metrics can be added to app
- Doesn't pollute core codebase

### 5. Distribution
- App can be packaged separately
- Easier to share with other PSWebHost instances
- Version control at app level

## Post-Migration Checklist

### Immediate
- [x] Verify metrics collection is running
- [x] Check CSV files are being created
- [x] Test API endpoints return data
- [x] Confirm UI dashboard works

### Within 24 Hours
- [x] Monitor background job for errors
- [x] Verify CSV cleanup is working
- [x] Check memory usage is bounded
- [x] Ensure historical data accessible

### Within 1 Week
- [ ] Decommission old `modules/PSWebHost_Metrics/` directory
- [ ] Decommission old `routes/api/v1/metrics/` directory
- [ ] Decommission old `public/elements/server-heatmap/` directory
- [ ] Update any external documentation

## Decommissioning Old Files

**Recommended Timeline:** 1 week after successful migration

### Step 1: Rename Old Directories (Safety)
```powershell
# Modules
Rename-Item modules/PSWebHost_Metrics modules/_DEPRECATED_PSWebHost_Metrics

# Routes
Rename-Item routes/api/v1/metrics routes/api/v1/_DEPRECATED_metrics

# UI Component
Rename-Item public/elements/server-heatmap public/elements/_DEPRECATED_server-heatmap
```

**Wait 48 hours for issues to surface**

### Step 2: Archive Deprecated Directories
```powershell
# Create archive
$archiveDir = "archive/deprecated-metrics-$(Get-Date -Format 'yyyyMMdd')"
New-Item -Path $archiveDir -ItemType Directory -Force

# Move to archive
Move-Item modules/_DEPRECATED_PSWebHost_Metrics $archiveDir/
Move-Item routes/api/v1/_DEPRECATED_metrics $archiveDir/
Move-Item public/elements/_DEPRECATED_server-heatmap $archiveDir/
```

**Wait 30 days**

### Step 3: Delete Archive
```powershell
# After 30 days of no issues
Remove-Item $archiveDir -Recurse -Force
```

## Known Issues

### None

No issues identified during migration. All functionality preserved and working.

## Support

For issues related to the migration:

1. Check `apps/WebHostMetrics/README.md` for troubleshooting
2. Review `apps/WebHostMetrics/ARCHITECTURE.md` for technical details
3. Check background job: `Get-Job -Name "PSWebHost_MetricsCollection"`
4. Verify module loaded: `Get-Module PSWebHost_Metrics`
5. Check CSV files: `Get-ChildItem PsWebHost_Data/metrics/*.csv | Sort LastWriteTime -Desc | Select -First 5`

## References

- [WebHost Metrics README](./README.md)
- [Architecture Documentation](./ARCHITECTURE.md)
- [App Framework Documentation](../../docs/Apps.md)
- [Component Path Specification](../../COMPONENT_PATH_SPECIFICATION.md)

## Change Log

### 2026-01-16 - Initial Migration
- Migrated all metrics components to WebHostMetrics app
- Updated system/init.ps1 module imports
- Updated layout.json component paths
- Created comprehensive documentation
- Tested and verified all functionality
- Migration successful - no breaking changes

---

**Migration Status:** ✅ **COMPLETE**

**Backward Compatibility:** ✅ **MAINTAINED**

**Testing Status:** ✅ **PASSED**

**Documentation:** ✅ **COMPLETE**
