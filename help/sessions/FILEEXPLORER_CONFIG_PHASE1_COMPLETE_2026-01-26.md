# FileExplorer Config-Driven Root System - Phase 1 Complete

## Date: 2026-01-26

## Summary

✅ **Phase 1: Configuration Infrastructure - COMPLETE**

Successfully implemented the foundational configuration system for FileExplorer's config-driven root management. The system replaces hardcoded root definitions with a flexible JSON-based configuration that supports dynamic roots, role-based access, and path template resolution.

---

## What Was Implemented

### 1. FileExplorerConfig Module Created

**Location**: `apps/WebhostFileExplorer/modules/FileExplorerConfig/`

**Files**:
- `FileExplorerConfig.psm1` - Module implementation (5 functions)
- `FileExplorerConfig.psd1` - Module manifest

**Functions Exported** (5):
1. **Get-WebHostFileExplorerConfigPath** - Returns path to roots.json with auto-directory creation
2. **New-WebHostFileExplorerDefaultConfig** - Generates default configuration file
3. **Resolve-WebHostFileExplorerConfigPath** - Resolves path templates with variables
4. **Get-WebHostFileExplorerConfig** - Loads configuration with 5-minute TTL caching
5. **Clear-WebHostFileExplorerConfigCache** - Forces cache reload

**Key Features**:
- ✅ 5-minute TTL caching (47x performance improvement: 8.75ms → 0.18ms)
- ✅ Automatic default config generation if missing
- ✅ Path template resolution with variables like {UserID}, {Project_Root.Path}, {DataPath}
- ✅ Graceful fallback when Write-PSWebHostLog not available
- ✅ Hot reload support via Import-TrackedModule

### 2. Default Configuration Created

**Location**: `PsWebHost_Data/apps/WebhostFileExplorer/config/roots.json`

**Configuration Schema**:
```json
{
  "version": "1.0",
  "roots": [ /* 6 root definitions */ ],
  "systemRoots": { /* System drive config */ }
}
```

**Root Definitions** (6):

1. **user_me** - Personal user storage
   - Path: `User:me`
   - Template: `PsWebHost_Data/UserData/{UserID}/personal`
   - Roles: `authenticated`

2. **user_others** - Admin browsing of all user directories
   - Path: `User:others`
   - Template: `PsWebHost_Data/UserData/{TargetUserID}/personal`
   - Roles: `system_admin`
   - Dynamic: User lookup with patterns `{email}/{last4}` and `{userID}`

3. **buckets** - Shared storage buckets
   - Path: `Bucket:{BucketID}`
   - Template: `PsWebHost_Data/SharedBuckets/{BucketID}`
   - Roles: `authenticated`
   - Dynamic: Database-driven bucket discovery

4. **site_public** - Site public files
   - Path: `Site:public`
   - Template: `{Project_Root.Path}/public`
   - Roles: `site_admin`, `system_admin`

5. **site_project_root** - Site project root
   - Path: `Site:Project_Root`
   - Template: `{Project_Root.Path}`
   - Roles: `system_admin`

6. **site_data** - Site data directory
   - Path: `Site:data`
   - Template: `{DataPath}`
   - Roles: `system_admin`

**System Roots Configuration**:
- Enabled for `system_admin` only
- Auto-discovers Windows drives (C:, D:, etc.)
- Auto-discovers Linux root (/)
- `removeLocalPrefix: true` - New System:C format (not local|localhost|System:C)

### 3. App Initialization Updated

**File**: `apps/WebhostFileExplorer/app_init.ps1`

**Changes**:
- Added FileExplorerConfig module loading via Import-TrackedModule
- Module is optional - fallback to hardcoded roots if module fails to load
- Logs module load status

**Code Added**:
```powershell
# Load FileExplorerConfig module for config-driven root management
$configModulePath = Join-Path $AppRoot "modules\FileExplorerConfig\FileExplorerConfig.psd1"
if (Test-Path $configModulePath) {
    try {
        Import-TrackedModule -Path $configModulePath
        Write-Host "$MyTag Loaded FileExplorerConfig module with hot reload" -ForegroundColor Green
    }
    catch {
        Write-Host "$MyTag Warning: Failed to load FileExplorerConfig module: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "$MyTag FileExplorer will use hardcoded root definitions" -ForegroundColor Yellow
    }
}
```

---

## Testing Results

### Test Script: `test_fileexplorer_config.ps1`

**All Tests Passed** ✅

**Test 1: Config Path Resolution**
- ✅ Config path correctly resolved to: `C:\SC\PsWebHost\PsWebHost_Data\apps\WebhostFileExplorer\config\roots.json`
- ✅ Config file exists

**Test 2: Configuration Loading**
- ✅ Config loaded successfully
- ✅ Version: 1.0
- ✅ Roots count: 6
- ✅ System roots enabled: True
- ✅ All 6 roots listed correctly

**Test 3: Path Template Resolution**
- ✅ `{Project_Root.Path}/public` → `C:\SC\PsWebHost/public`
- ✅ `{DataPath}/apps/{AppName}` → `C:\SC\PsWebHost\PsWebHost_Data/apps/TestApp`
- ✅ Custom variables work correctly

**Test 4: Cache Behavior**
- ✅ First load: 8.75ms (from disk)
- ✅ Cached load: 0.18ms (from memory) - **47x faster**
- ✅ Cache clear works
- ✅ Reload after clear works

**Module Validation**:
```powershell
Test-ModuleManifest FileExplorerConfig.psd1
# Result: Valid manifest with 5 exported functions
```

---

## Technical Implementation Details

### Caching Strategy

**TTL**: 5 minutes (configurable via `$script:ConfigCacheTTL`)

**Cache Variables**:
- `$script:ConfigCache` - Stores loaded configuration
- `$script:ConfigCacheTime` - Timestamp of last load

**Benefits**:
- Reduces disk I/O by 47x
- Automatic expiration prevents stale config
- Manual cache clear for immediate reload
- Force reload via `-Force` parameter

### Path Template Resolution

**Supported Variables**:
- `{UserID}` - Current user ID
- `{TargetUserID}` - Target user ID (for User:others)
- `{DataPath}` - PSWebServer data path
- `{DataRoot}` - PSWebServer data root
- `{Project_Root.Path}` - Project root path
- Custom variables via `-Variables` hashtable

**Resolution Process**:
1. Merge built-in and custom variables
2. Replace all `{variable}` patterns
3. Warn if unresolved variables remain
4. Return resolved path

### Global Scope Access

**Pattern Used**:
```powershell
$logCmd = Get-Command -Name Write-PSWebHostLog -ErrorAction SilentlyContinue
if ($logCmd) {
    & $logCmd -Severity 'Info' -Message "Log message"
}
```

**Why**:
- Module runs in isolated scope
- Can't directly access global functions
- Get-Command finds function in global scope
- Check if command exists before calling (graceful degradation)
- Works in both server and test environments

---

## Integration Points

### Server Startup Flow

1. **WebHost.ps1** - Loads system modules and init.ps1
2. **App Discovery** - Finds WebhostFileExplorer app
3. **app_init.ps1** - Runs initialization
   - Creates app namespace
   - Loads FileExplorerConfig module via Import-TrackedModule
   - Module registered in `$Global:PSWebServer.Modules`
4. **Hot Reload** - Invoke-ModuleRefreshAsNeeded monitors module file changes

### Module Usage in Routes

Routes can now call configuration functions directly:

```powershell
# Example: roots/get.ps1
$config = Get-WebHostFileExplorerConfig

foreach ($rootDef in $config.roots) {
    # Check roles
    if ($sessiondata.Roles -contains $rootDef.roles[0]) {
        # Add root to response
        $roots += @{
            path = $rootDef.pathFormat
            name = $rootDef.name
            type = $rootDef.type
        }
    }
}
```

---

## Files Created/Modified

### Created (4 files)

1. **apps/WebhostFileExplorer/modules/FileExplorerConfig/FileExplorerConfig.psm1**
   - Module implementation with 5 functions
   - 280 lines of code

2. **apps/WebhostFileExplorer/modules/FileExplorerConfig/FileExplorerConfig.psd1**
   - Module manifest
   - Version 1.0.0

3. **PsWebHost_Data/apps/WebhostFileExplorer/config/roots.json**
   - Default configuration with 6 roots
   - System roots configuration

4. **test_fileexplorer_config.ps1**
   - Comprehensive test suite
   - 4 test scenarios

### Modified (1 file)

1. **apps/WebhostFileExplorer/app_init.ps1**
   - Added FileExplorerConfig module loading
   - 15 lines added

---

## Next Steps: Phase 2 - User:others Implementation

**Pending Work**:

1. **Create User_Resolve.ps1** utility
   - Resolve email/last4 patterns to UserID
   - Resolve direct UserID patterns
   - Database integration for user lookup

2. **Update Path_Resolve.ps1**
   - Add User:others case
   - Require system_admin role
   - Parse user patterns and resolve UserID
   - Build path to target user's storage

3. **Update tree/post.ps1**
   - Add User:others user listing
   - Query database for all users
   - Return email/last4 format nodes

**Implementation Order**:
1. Create User_Resolve.ps1
2. Update Path_Resolve.ps1 for User:others
3. Update tree/post.ps1 for user listing
4. Test email/last4 resolution
5. Test UserID resolution
6. Test navigation to other users' folders

---

## Success Criteria

✅ FileExplorerConfig module created with .psd1 manifest
✅ Module loads successfully on server startup
✅ Configuration file created with 6 root definitions
✅ Caching works (47x performance improvement)
✅ Path template resolution works
✅ Hot reload support enabled
✅ All tests pass
✅ Graceful degradation in test environment

---

## Backward Compatibility

**Fallback Strategy**:
- If FileExplorerConfig module fails to load, app_init.ps1 logs warning
- Routes can check if config is available: `if (Get-Command Get-WebHostFileExplorerConfig)`
- Hardcoded root logic remains as fallback

**Migration Path**:
- Phase 1: Config infrastructure (COMPLETE)
- Phase 2-4: Update routes to use config
- Final: Remove hardcoded logic once all routes updated

---

**Status**: ✅ PHASE 1 COMPLETE
**Next**: Begin Phase 2 - User:others Implementation
**Ready**: Yes - proceed with User_Resolve.ps1 creation

**Created**: 2026-01-26
**Completed**: 2026-01-26
