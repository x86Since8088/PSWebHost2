# Card Migration Issues Found
**Date**: 2026-02-03
**Status**: Investigation Complete

## Issues Fixed

### ✅ 1. psweb_spa.js Hardcoded Path References
**Files**: `public/psweb_spa.js`
**Issue**: Three instances of hardcoded `/api/v1/ui/elements/` path construction
**Lines**: 1889, 2341, 2460
**Status**: FIXED

**Changes Made**:
```javascript
// Line 1889 - Card endpoint derivation
- card.endpoint = `/api/v1/ui/elements/${elementName}`;
+ card.endpoint = `/cards/${elementName}`;

// Line 2341 - Default endpoint construction
- endpointUrl = `/api/v1/ui/elements/${elementId}`;
+ endpointUrl = `/cards/${elementId}`;

// Line 2460 - Error message
- 2. scriptPath in /api/v1/ui/elements/${elementId} endpoint response, OR
+ 2. scriptPath in /cards/${elementId} endpoint response, OR
```

## Potential Issues (Requires Investigation)

### ⚠️ 2. server-heatmap Component - uplot Reference
**File**: `apps/WebHostMetrics/public/elements/server-heatmap/component.js:417`
**Issue**: References `/api/v1/ui/elements/uplot` which may not exist

**Current Code**:
```javascript
url: `/api/v1/ui/elements/uplot?source=/apps/WebHostMetrics/api/v1/metrics/history&metric=cpu...`
```

**Investigation**:
- No `uplot` card endpoint found in core cards
- UI_Uplot app has: uplot-home, time-series, area-chart, bar-chart, scatter-plot, multi-axis, heatmap
- No generic "uplot" card exists
- `window.cardComponents.uplot` component may be dynamically loaded or legacy

**Status**: NEEDS USER VERIFICATION
- Check if server-heatmap currently works in production
- If broken: May need to update to use specific chart type (e.g., time-series)
- If working: May be using dynamic component loading not captured in migration

**Recommendation**:
If this is broken, update to:
```javascript
url: `/apps/UI_Uplot/cards/time-series?source=/apps/WebHostMetrics/api/v1/metrics/history&metric=cpu...`
```

## Non-Issues (Safe to Ignore)

### ✓ 3. Comment References in Migrated Files
**Files**: Various get.ps1 files in migrated cards
**Examples**:
- `apps/WebHostTaskManagement/routes/cards/task-manager/get.ps1:5`
- `apps/WebhostFileExplorer/routes/cards/file-sharing-modal/get.ps1:1`

**Issue**: Comments still reference old `/api/v1/ui/elements/` paths

**Status**: NON-ISSUE
- Comments/documentation don't affect functionality
- Routing is based on file location, not comments
- Can be updated later for documentation accuracy

### ✓ 4. Legacy Directories Remaining
**Directories**:
- `routes/api/v1/ui/elements/admin/` (empty)
- `routes/api/v1/ui/elements/main-menu/` (only backup file)
- `routes/api/v1/ui/elements/chartjs/` (no PS1 files, possibly legacy)

**Status**: NON-ISSUE
- Empty directories don't break functionality
- Can be cleaned up later
- chartjs might be a different system (needs investigation)

### ✓ 5. Migration Script References
**Files**:
- `migrate_cards.ps1`
- `migrate_cards_simple.ps1`
- `update_card_url_references.ps1`

**Status**: NON-ISSUE
- Migration scripts naturally contain old paths
- Scripts are one-time use and complete
- Can be archived or deleted

## Cleanup Recommendations

### High Priority
- [ ] Investigate and fix server-heatmap uplot reference

### Medium Priority
- [ ] Update comments in migrated get.ps1 files to reflect new paths
- [ ] Remove empty admin and main-menu directories

### Low Priority
- [ ] Investigate chartjs directory purpose
- [ ] Archive migration scripts
- [ ] Update all test scripts to use new paths

## Testing Checklist

### Critical Tests
- [x] Main menu loads from `/cards/main-menu` ✓
- [ ] Server heatmap component loads correctly
- [ ] Docker Manager card opens
- [ ] File Explorer card opens
- [ ] System Log card opens
- [ ] All cards in menu are accessible

### Browser Console Check
- [ ] No 404 errors for /api/v1/ui/elements/ paths
- [ ] All /cards/ requests return 200
- [ ] No JavaScript errors related to card loading

## Summary

**Fixed**: 3 critical hardcoded path references in psweb_spa.js
**Requires Attention**: 1 potential issue (server-heatmap uplot reference)
**Safe to Ignore**: Comment references, empty directories, migration scripts

**Next Action**: Test server-heatmap component to determine if uplot reference is functional or broken.
