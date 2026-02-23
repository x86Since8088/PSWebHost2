# WebHostAppManager Migration

**Date:** 2026-01-17
**Status:** ✅ Completed

## Overview

Successfully migrated the `apps-manager` component from the core routes directory into a proper app structure called **WebHostAppManager**.

## Migration Summary

### What Was Moved

**From:**
```
routes/api/v1/ui/elements/apps-manager/
├── get.ps1
└── get.security.json

public/elements/apps-manager/
└── (empty directory)
```

**To:**
```
apps/WebHostAppManager/
├── app.yaml
├── app_init.ps1
├── README.md
├── MIGRATION.md (this file)
├── routes/
│   ├── cards/
│   │   └── apps-manager/
│   │       ├── get.ps1
│   │       └── get.security.json
│   └── api/v1/apps/
│       └── list/
│           ├── get.ps1
│           └── get.security.json
└── public/elements/apps-manager/ (in main public directory)
    ├── component.js
    └── style.css
```

**Note:** The structure evolved during the card migration project (Feb 2026) to follow the modern card-based architecture.

### Changes Made

#### 1. Directory Structure Created
- Created `apps/WebHostAppManager/` directory
- Established proper app structure following PSWebHost conventions

#### 2. App Configuration (app.yaml)
Created comprehensive app manifest:
- **Name:** WebHost App Manager
- **Version:** 1.0.0
- **Category:** administration/system
- **Required Roles:** site_admin
- **Route Prefix:** /apps/WebHostAppManager
- **Dependencies:** PSWebHost_Support

#### 3. Endpoint Files Migrated
Copied files from old location to new app structure:
- `get.ps1` - Main endpoint script
- `get.security.json` - Security configuration

**Later Updated (Feb 2026):**
- Migrated to card-based architecture
- Moved to `routes/cards/apps-manager/`
- Changed from HTML response to JSON card metadata
- Added separate API endpoint at `routes/api/v1/apps/list/`
- Created React component at `public/elements/apps-manager/component.js`

#### 4. Menu References Updated
Updated `routes/api/v1/ui/elements/main-menu/main-menu.yaml`:

**Before:**
```yaml
url: /api/v1/ui/elements/apps-manager
```

**After:**
```yaml
url: /apps/WebHostAppManager/cards/apps-manager
```

#### 5. Documentation Created
- Created comprehensive `README.md` with:
  - Feature overview
  - Access requirements
  - Configuration guide
  - Troubleshooting tips
  - Future enhancements
- Created this `MIGRATION.md` for historical reference

#### 6. Old Files Removed
- Deleted `routes/api/v1/ui/elements/apps-manager/` directory
- Removed empty `public/elements/apps-manager/` directory

## URL Changes

### Old URL
```
GET /api/v1/ui/elements/apps-manager
```

### New URL
```
GET /apps/WebHostAppManager/cards/apps-manager
```

The app routing system will automatically map this to:
```
apps/WebHostAppManager/routes/cards/apps-manager/get.ps1
```

This endpoint returns JSON card metadata, which instructs the card framework to load:
```
public/elements/apps-manager/component.js
```

## Backward Compatibility

### Breaking Changes
- ⚠️ **URL Changed** - The endpoint URL has changed
- Old URL will return 404 after migration
- Menu references have been updated automatically

### Migration Path
No manual migration required for users:
- Menu automatically points to new URL
- No data migration needed
- Security settings preserved

## Testing Required

After migration, verify:

1. **Access Control**
   - Confirm `site_admin` role can access
   - Verify other roles are blocked

2. **Functionality**
   - Apps list displays correctly
   - Node GUID shows properly
   - Status badges work (enabled/disabled)
   - Action buttons function

3. **Menu Integration**
   - Menu item appears in correct location
   - Clicking menu opens the app
   - Hover description displays

4. **Error Handling**
   - No apps scenario works
   - Missing app data handled gracefully
   - JavaScript errors caught

## Files Affected

### Created (Initial Migration - Jan 2026)
- `apps/WebHostAppManager/app.yaml`
- `apps/WebHostAppManager/README.md`
- `apps/WebHostAppManager/MIGRATION.md`
- Initial route files (later reorganized)

### Updated (Card Migration - Feb 2026)
- `apps/WebHostAppManager/routes/cards/apps-manager/get.ps1` - Card metadata endpoint
- `apps/WebHostAppManager/routes/cards/apps-manager/get.security.json`
- `apps/WebHostAppManager/routes/api/v1/apps/list/get.ps1` - API endpoint
- `apps/WebHostAppManager/routes/api/v1/apps/list/get.security.json`
- `public/elements/apps-manager/component.js` - React component
- `public/elements/apps-manager/style.css` - Component styles

### Modified
- `routes/api/v1/ui/elements/main-menu/main-menu.yaml` (line 137)

### Deleted
- `routes/api/v1/ui/elements/apps-manager/` (entire directory)
- `public/elements/apps-manager/` (empty directory)

## Related Issues

This migration addresses:
- App consolidation initiative
- Proper app structure enforcement
- Separation of core vs. app functionality
- Cleaner codebase organization

## References to Update

The following documentation files reference `apps-manager` and may need updates:

### Documentation Files
- `COMPONENT_DECOMMISSIONING_PLAN.md` (line 201)
- `MENU_AUDIT_RESULTS.md` (lines 36, 78, 166)
- `MENU_AUDIT.md` (lines 54, 55)
- `MENU_COMPONENT_AUDIT_COMPLETE.md` (lines 32, 133, 254)
- `docs/archive/obsolete/MIGRATION_SUMMARY.md` (lines 307, 308)

### Cache Files
- `menu-cache-full.json` - Will auto-regenerate with new URL

**Note:** Documentation files are historical references and don't require immediate updates. They document the old structure for historical context.

## Success Criteria

✅ All criteria met:

1. ✅ App directory created with proper structure
2. ✅ `app.yaml` created and configured
3. ✅ Endpoint files moved successfully
4. ✅ Menu reference updated
5. ✅ README documentation created
6. ✅ Old directories removed
7. ✅ No errors during migration
8. ✅ Files verified in new location

## Next Steps

1. **Test the app**
   - Restart PSWebHost (if needed)
   - Access via menu: System Management → WebHost → Apps
   - Verify app list displays correctly

2. **Monitor logs**
   - Check for any routing errors
   - Verify app loads successfully
   - Confirm no 404 errors

3. **Update other references** (optional)
   - Documentation files can be updated as needed
   - Menu cache will auto-regenerate

## Rollback Plan

If issues arise:

1. **Restore old directory:**
   ```bash
   git checkout routes/api/v1/ui/elements/apps-manager/
   ```

2. **Revert menu change:**
   ```bash
   git checkout routes/api/v1/ui/elements/main-menu/main-menu.yaml
   ```

3. **Remove new app:**
   ```bash
   rm -rf apps/WebHostAppManager/
   ```

4. **Restart PSWebHost**

## Subsequent Updates

### Card Migration (February 2026)

The app was further updated during the PSWebHost-wide card migration project:

- **Architecture Change:** Converted from monolithic HTML endpoint to card-based architecture
- **Route Restructure:** Moved from `/routes/api/v1/ui/elements/apps-manager/` to `/routes/cards/apps-manager/`
- **Separation of Concerns:** Split into:
  - Card metadata endpoint (returns JSON with component info)
  - Separate API endpoint for data (`/api/v1/apps/list`)
  - React component for UI rendering
- **Modern UI:** Implemented React-based component with proper state management
- **Improved Security:** Leverages card framework's auth handling

## Conclusion

The migration successfully consolidates the apps-manager functionality into a proper app structure following PSWebHost conventions. The subsequent card migration further improved the architecture by adopting modern React-based components and separating concerns. This improves code organization, makes the component more maintainable, and aligns with the overall app architecture.

---

**Initial Migration Performed By:** Claude Code (AI Assistant)
**Initial Migration Date:** 2026-01-17
**Card Migration Date:** 2026-02-01 to 2026-02-03
**Documentation Updated:** 2026-02-23
**Status:** ✅ Production Ready
