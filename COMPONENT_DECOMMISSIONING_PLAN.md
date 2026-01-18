# Component Decommissioning Plan

## Overview

Several UI components have been migrated from `public/elements/` to dedicated apps. This document tracks the decommissioning of old component directories.

## Status: Duplicate Components

### ✅ Migrated and Ready for Decommission

#### 1. realtime-events / event-stream

**Old Locations:**
- `public/elements/event-stream/` - OLD component using in-memory buffer
- `public/elements/realtime-events/` - Transitional copy (should have been in app from start)

**New Location:**
- `apps/WebhostRealtimeEvents/public/elements/realtime-events/` ✅

**Status:**
- ✅ layout.json updated to use app version
- ✅ Menu points to `/api/v1/ui/elements/realtime-events`
- ✅ App endpoint returns correct `scriptPath`
- ⚠️ Old directories still exist

**Decommission Steps:**
1. Verify app version works correctly (reload page, test all features)
2. Backup old components: `public/elements/event-stream/` and `public/elements/realtime-events/`
3. Delete old directories
4. Test that nothing breaks

**Component Registration:**
- Old: `window.cardComponents['event-stream']`
- New: `window.cardComponents['realtime-events']`

---

#### 2. unit-test-runner

**Old Location:**
- `public/elements/unit-test-runner/`

**New Location:**
- `apps/UnitTests/public/elements/unit-test-runner/` ✅

**Status:**
- ⚠️ Need to verify which version is being used
- ⚠️ Check if layout.json or menu references unit-test-runner
- ⚠️ Old directory still exists

**Decommission Steps:**
1. Check layout.json for unit-test-runner references
2. Check main-menu.yaml for unit-test-runner URL
3. Update references to use app version if needed
4. Verify app version works
5. Backup and delete old directory

**Component Registration:**
- Both register as: `window.cardComponents['unit-test-runner']`

---

## Investigation Required

These components may have app equivalents that need investigation:

### Public Elements Potentially Migrated

1. **vault-manager** (?)
   - Check: `apps/vault/public/elements/vault-manager/`
   - Status: App version exists
   - Action: Verify if public version exists and is obsolete

2. **docker-manager** (?)
   - Check: `apps/DockerManager/public/elements/docker-manager/`
   - Status: App version exists
   - Action: Verify if public version exists

3. **uplot charts** (?)
   - Old: `public/elements/uplot/` (?)
   - New: `apps/UI_Uplot/public/elements/` (multiple chart types)
   - Action: Verify if public uplot directory is obsolete

---

## Decommissioning Checklist

### Before Removing Any Component:

- [ ] Verify app version exists and is functional
- [ ] Check layout.json for references
- [ ] Check main-menu.yaml for references
- [ ] Search codebase for hardcoded references to old path
- [ ] Test app version works from menu
- [ ] Test app version works if in layout (if applicable)
- [ ] Create backup of old component
- [ ] Document component registration name
- [ ] Verify no other code references the old path

### Safe Decommissioning Process:

1. **Phase 1: Rename (Safety)**
   ```bash
   mv public/elements/old-component public/elements/_DEPRECATED_old-component
   ```
   - This breaks any hardcoded references immediately
   - Easy to rollback if something breaks
   - Wait 24-48 hours for issues to surface

2. **Phase 2: Archive**
   ```bash
   mkdir -p archive/deprecated-components/$(date +%Y%m%d)
   mv public/elements/_DEPRECATED_old-component archive/deprecated-components/$(date +%Y%m%d)/
   ```
   - Move to archive directory with timestamp
   - Keeps for historical reference
   - Not served by web server

3. **Phase 3: Delete (After Verification)**
   ```bash
   # After 30 days of no issues:
   rm -rf archive/deprecated-components/YYYYMMDD/_DEPRECATED_old-component
   ```

---

## Current Action Items

### Immediate (Next Session):

1. **Verify realtime-events app version works**
   - Reload page
   - Test all features (time range, filters, sorting, etc.)
   - Check browser console for errors
   - Verify API calls go to `/apps/WebhostRealtimeEvents/api/v1/logs`

2. **Rename old components (Phase 1)**
   ```bash
   mv public/elements/event-stream public/elements/_DEPRECATED_event-stream
   mv public/elements/realtime-events public/elements/_DEPRECATED_realtime-events
   ```

3. **Test for 24 hours**
   - Monitor for any errors
   - Check if anything references old paths
   - Verify app continues to work

### Short Term (This Week):

1. **Investigate unit-test-runner**
   - Check which version is being used
   - Update references if needed
   - Decommission old version

2. **Investigate vault-manager**
   - Check if public version exists
   - Compare with app version
   - Decommission if obsolete

3. **Document component migration status**
   - Create inventory of all public/elements
   - Mark which have app equivalents
   - Mark which are still active

### Long Term (This Month):

1. **Complete decommissioning**
   - Archive all deprecated components
   - Update documentation
   - Remove from backups after verification period

2. **Establish policy**
   - New components must be in apps
   - Document migration process
   - Create testing checklist

---

## Component Inventory

### Active Public Components (No App Equivalent)

These components remain in `public/elements/` as they are core UI elements:

1. **main-menu** - Core navigation (may move to core module)
2. **user-card** - Core user widget
3. **title** - Header component (in layout.json, no component.js)
4. **profile** - User profile widget
5. **footer-info** - Footer widget
6. **card** - Generic card wrapper
7. **markdown-viewer** - Core viewer
8. **help-viewer** - Core viewer
9. **file-explorer** - Core file browser (or should this be an app?)
10. **system-log** - Core system logging
11. **system-status** - Core status widget
12. **server-heatmap** - Core monitoring
13. **world-map** - Core monitoring
14. **memory-histogram** - Core monitoring
15. **database-status** - Core status (or migrate to database app?)
16. **chartjs** - Library wrapper
17. **apps-manager** - Core app management
18. **site-settings** - Core settings
19. **admin/** - Admin components (role-management, users-management)

### Deprecated Components (Have App Equivalents)

1. ~~**event-stream**~~ → `apps/WebhostRealtimeEvents/` ⚠️ **READY TO REMOVE**
2. ~~**realtime-events**~~ → `apps/WebhostRealtimeEvents/` ⚠️ **DUPLICATE - REMOVE**
3. ~~**unit-test-runner**~~ → `apps/UnitTests/` ⚠️ **INVESTIGATE**

### Pending Investigation

1. **vault-manager** → `apps/vault/`? (check if public version exists)
2. **uplot** → `apps/UI_Uplot/`? (check structure)

---

## Testing After Decommissioning

### Manual Test Checklist:

For each decommissioned component:

- [ ] Page loads without errors
- [ ] Menu item works (if applicable)
- [ ] Component renders correctly
- [ ] All features work (buttons, filters, etc.)
- [ ] No 404s in browser console
- [ ] No errors in browser console
- [ ] No errors in server logs
- [ ] Data loads correctly from API
- [ ] Sorting/filtering works
- [ ] Export features work (if applicable)

### Browser Console Checks:

Look for these success messages:
```
Loading component for realtime-events from: /apps/WebhostRealtimeEvents/public/elements/realtime-events/component.js
Transforming realtime-events with Babel...
✓ Component realtime-events loaded and registered
```

### API Endpoint Checks:

Verify API calls go to correct location:
```
GET /apps/WebhostRealtimeEvents/api/v1/logs?timeRange=15
GET /apps/WebhostRealtimeEvents/api/v1/status
```

---

## Rollback Plan

If app version doesn't work:

1. **Quick Rollback** (if renamed in Phase 1):
   ```bash
   mv public/elements/_DEPRECATED_old-component public/elements/old-component
   ```

2. **Revert layout.json**:
   ```json
   "event-stream": {
       "componentPath": "/public/elements/event-stream/component.js"
   }
   ```

3. **Hard refresh browser**: Ctrl+F5

4. **Check what broke**:
   - Browser console errors
   - Server logs
   - API responses
   - Component registration

---

## Migration Best Practices (For Future)

When creating new apps with UI components:

1. ✅ **DO**: Create component in `apps/YourApp/public/elements/`
2. ✅ **DO**: Create UI endpoint at `routes/api/v1/ui/elements/your-component/get.ps1`
3. ✅ **DO**: Return `scriptPath` in endpoint response
4. ✅ **DO**: Register component with unique name: `window.cardComponents['your-component']`
5. ✅ **DO**: Add to app's `menu.yaml` for menu integration
6. ❌ **DON'T**: Create in `public/elements/` unless it's a core UI component
7. ❌ **DON'T**: Create duplicate component in both locations
8. ❌ **DON'T**: Assume `/public/elements/` path - always use explicit paths

---

## Questions for Discussion

1. **Should we move core monitoring components to apps?**
   - server-heatmap, world-map, memory-histogram, database-status
   - Pro: Consistency, all cards are apps
   - Con: These feel like core platform features

2. **Should file-explorer become an app?**
   - It's a substantial feature
   - Could have its own app.yaml and route structure
   - Currently treated as core UI

3. **What defines a "core" vs "app" component?**
   - Proposal: Core = required for platform operation
   - Proposal: App = optional feature that can be enabled/disabled

---

## Summary

**Current State:**
- ✅ realtime-events migrated to WebhostRealtimeEvents app
- ✅ layout.json updated to use app version
- ⚠️ Old event-stream and realtime-events directories still exist
- ⚠️ unit-test-runner duplicated in UnitTests app

**Next Steps:**
1. Test realtime-events app version thoroughly
2. Rename old directories to _DEPRECATED_
3. Monitor for 24 hours
4. Archive deprecated components
5. Investigate other potential duplicates

**Goal:**
Clean separation between core platform components (`public/elements/`) and optional app components (`apps/*/public/elements/`).
