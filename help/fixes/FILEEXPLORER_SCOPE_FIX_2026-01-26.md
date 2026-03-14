# FileExplorer Module Scope Fix - 2026-01-26

## Executive Summary

✅ **Fixed critical module scope isolation issues preventing FileExplorer from working**

When we converted FileExplorerHelper from a dot-sourced script to a proper PowerShell module, it lost access to functions from the calling scope (`context_response`, `Write-PSWebHostLog`, `Get-PSWebHostErrorReport`). This caused "Internal Server Error" failures.

**Root Cause**: Module scope isolation - modules run in their own isolated scope and can't directly access functions from the caller's scope like dot-sourced scripts can.

**Solution**: Use `Get-Command` to call global scope functions from within the module.

---

## Errors Fixed

### Error 1: context_response Not Recognized
```
The term 'context_response' is not recognized as a name of a cmdlet, function, script file, or executable program.
Source: FileExplorerHelper.psm1::Send-WebHostFileExplorerError
```

**Impact**: All FileExplorer API calls failed with 500 Internal Server Error

### Error 2: Path Format Not Parsed
```
Failed to load folder: Internal Server Error
folderPath: local|localhost|User:me
```

**Impact**: Frontend couldn't load any folders after initial root load

---

## Files Fixed

### 1. FileExplorerHelper.psm1
**Issue**: Module functions calling `context_response`, `Write-PSWebHostLog`, and `Get-PSWebHostErrorReport` without scope prefix

**Before**:
```powershell
context_response -Response $Response -StatusCode $StatusCode -String $JsonContent -ContentType "application/json"
```

**After**:
```powershell
& (Get-Command -Name context_response -ErrorAction Stop) -Response $Response -StatusCode $StatusCode -String $JsonContent -ContentType "application/json"
```

**Changes**:
- Updated `Send-WebHostFileExplorerResponse` function (1 call)
- Updated `Send-WebHostFileExplorerError` function (3 calls)
- Updated `Save-WebHostFileExplorerUndoData` function (1 call)
- Updated `Get-WebHostFileExplorerUserInfo` function (1 call)
- Updated `Test-WebHostFileExplorerRemoteVolume` function (1 call)
- Updated `Get-WebHostFileExplorerRemoteTrashPath` function (2 calls)
- Updated `Write-WebHostFileExplorerTrashMetadata` function (4 calls)
- Updated `Move-WebHostFileExplorerToTrash` function (18 calls)

**Total**: 31 function calls fixed

### 2. files/get.ps1
**Issue**: Didn't parse `local|localhost|User:me` path format sent by frontend

**Added**:
```powershell
# Parse path format: local|localhost|User:me/Documents
if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
    $node = $matches[1]        # "local"
    $nodeName = $matches[2]    # "localhost"
    $parsedLogicalPath = $matches[3]  # "User:me/Documents"
    $logicalPath = $parsedLogicalPath
}
```

### 3. files/post.ps1
**Issue**: Same path format parsing issue for all file operations

**Actions Fixed**:
- `createFolder` - Added path parsing
- `uploadFile` - Added path parsing
- `rename` - Added path parsing
- `batchRename` - Added path parsing (in loop)
- `delete` - Added path parsing (in loop)

---

## Technical Details

### Why Dot-Sourcing Worked Before

When a script is dot-sourced:
```powershell
. $helperPath  # Runs in caller's scope
```

The script runs **in the caller's scope** and has direct access to all variables and functions in that scope, including:
- `$Context`, `$Request`, `$Response` variables from the route
- `context_response` function from the route execution environment
- `Write-PSWebHostLog` and `Get-PSWebHostErrorReport` from global scope

### Why Module Import Broke It

When a module is imported:
```powershell
Import-TrackedModule -Path $modulePath  # Runs in isolated scope
```

The module runs **in its own isolated scope** and does NOT have access to:
- Variables from the calling route
- Functions defined in the calling route's execution environment

### The Fix: Accessing Global Scope from Module

Use `Get-Command` with `&` (call operator) to invoke functions from the global scope:

```powershell
# Instead of direct call:
Write-PSWebHostLog -Severity 'Info' -Message "Test"

# Use Get-Command:
& (Get-Command -Name Write-PSWebHostLog -ErrorAction Stop) -Severity 'Info' -Message "Test"
```

**How it works**:
1. `Get-Command -Name FunctionName` searches for the function in available scopes (including global)
2. `-ErrorAction Stop` ensures we fail fast if the function doesn't exist
3. `& (...)` calls the function object returned by Get-Command
4. Parameters are passed normally

**Advantages**:
- ✅ Works across scope boundaries
- ✅ Fails explicitly if function not found (better error messages)
- ✅ Maintains module isolation while accessing necessary functions
- ✅ No global scope pollution

### Path Format Background

The FileExplorer uses a three-part path format for remote access:

**Format**: `protocol|hostname|logicalPath`

**Examples**:
- `local|localhost|User:me` - Local storage, user's personal folder
- `local|localhost|Site:public` - Local storage, site public folder
- `smb|fileserver|Share:documents` - SMB share (future feature)
- `ssh|devserver|/home/user` - SSH/SFTP (future feature)

**Why**:
- Supports multiple storage backends (local, SMB, SSH/SFTP, S3, etc.)
- Allows the frontend to maintain connection context
- Enables multi-node and remote storage scenarios

**Root vs Subpath**:
- `User:` is a **root** (maps to a storage location in config)
- `User:me` is a **subpath** under the User: root (user's personal storage)
- `User:others` is a **subpath** under the User: root (other users' shared storage)
- `Site:` is a **root** (maps to site storage)
- `Site:Project_Root` is a **subroot** (mounted storage location from config)
- `Site:data` is another **subroot**

---

## Path Format Parsing Implementation

### Pattern Matching
```powershell
if ($logicalPath -match '^([^|]+)\|([^|]+)\|(.+)$') {
    $node = $matches[1]        # "local", "smb", "ssh", etc.
    $nodeName = $matches[2]    # "localhost", "fileserver", "devserver", etc.
    $logicalPath = $matches[3] # "User:me/Documents", "Site:public", etc.
}
```

### Endpoints Updated
| Endpoint | Operations | Status |
|----------|-----------|--------|
| `files/get.ps1` | List folder contents | ✅ Fixed |
| `files/post.ps1` | createFolder, uploadFile | ✅ Fixed |
| `files/post.ps1` | rename, batchRename | ✅ Fixed |
| `files/post.ps1` | delete (array of paths) | ✅ Fixed |
| `tree/post.ps1` | Tree expansion | ✅ Already had parsing |
| `versioninfo/get.ps1` | File version info | ✅ Already had parsing |

---

## Testing Verification

### Module Scope Fix Verification
1. ✅ Module loads successfully
   ```powershell
   Import-Module FileExplorerHelper.psd1 -Force -PassThru
   # Shows 16 exported functions
   ```

2. ✅ Functions call global scope correctly
   - `context_response` found via Get-Command
   - `Write-PSWebHostLog` found via Get-Command
   - `Get-PSWebHostErrorReport` found via Get-Command

3. ⏳ **Pending User Testing**:
   - Load FileExplorer in browser
   - Expand User:me folder
   - Should see folder contents (no "Internal Server Error")

### Path Parsing Fix Verification
1. ✅ Regex pattern matches correctly
   ```powershell
   "local|localhost|User:me" -match '^([^|]+)\|([^|]+)\|(.+)$'
   # $matches[1] = "local"
   # $matches[2] = "localhost"
   # $matches[3] = "User:me"
   ```

2. ⏳ **Pending User Testing**:
   - Click through folders: User:me → Documents → SubFolder
   - Create a folder
   - Upload a file
   - Rename a file
   - Delete a file
   - All operations should work without errors

---

## Root Cause Analysis

### Why Did This Happen?

**Decision**: Convert FileExplorerHelper from dot-sourced script to proper module
- **Reason**: Module accountability, hot reload, proper exports, versioning
- **Oversight**: Didn't account for scope isolation when accessing route environment functions

**The conversion was correct**, but incomplete:
- ✅ Created proper module structure (directory + .psd1 + .psm1)
- ✅ Defined explicit exports (16 functions)
- ✅ Updated all 12 route files to use Import-TrackedModule
- ❌ **Missed**: Functions calling into route execution environment
- ❌ **Missed**: Path format parsing needed after module isolation

### Why Wasn't This Caught Earlier?

1. **Static Analysis Limitations**: PowerShell doesn't have compile-time type checking
2. **Module Loaded Successfully**: Import succeeded, functions exist, no syntax errors
3. **Error Only at Runtime**: Scope issue only manifests when function is called
4. **Deep Call Stack**: Error happens inside helper function, not at import

### Lessons Learned

1. **Module Scope Isolation is Real**
   - Modules run in isolated scope
   - Can't access caller's variables or functions directly
   - Must use scope prefixes or Get-Command

2. **Dot-Sourcing Has Hidden Dependencies**
   - Scripts rely on caller's scope
   - Not obvious what functions/variables are external dependencies
   - Need careful analysis when converting

3. **Testing Strategy**
   - Module import success != module works correctly
   - Need runtime testing of all code paths
   - Should test with actual route execution environment

---

## Future Improvements

### 1. Make Dependencies Explicit
Instead of calling global functions, consider:

```powershell
# Option A: Pass functions as parameters
function Send-WebHostFileExplorerResponse {
    param(
        [scriptblock]$ContextResponse = { param($r, $c, $s, $ct) context_response -Response $r -StatusCode $c -String $s -ContentType $ct }
    )
    & $ContextResponse -Response $Response -StatusCode $StatusCode ...
}

# Option B: Use dependency injection
$dependencies = @{
    ContextResponse = Get-Command context_response
    WriteLog = Get-Command Write-PSWebHostLog
}
```

### 2. Add Module Tests
Create `FileExplorerHelper.Tests.ps1`:
```powershell
Describe "FileExplorerHelper" {
    It "Can access global functions" {
        { & (Get-Command Write-PSWebHostLog) -Severity 'Info' -Message "Test" } | Should -Not -Throw
    }

    It "Parses path format correctly" {
        $path = "local|localhost|User:me"
        if ($path -match '^([^|]+)\|([^|]+)\|(.+)$') {
            $matches[3] | Should -Be "User:me"
        }
    }
}
```

### 3. Add Scope Validation
In module functions that need global access:
```powershell
begin {
    # Validate required global functions exist
    $requiredFunctions = @('context_response', 'Write-PSWebHostLog', 'Get-PSWebHostErrorReport')
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Required global function not found: $func"
        }
    }
}
```

---

## Summary

**Issue**: Converting FileExplorerHelper from dot-sourced script to module broke scope access
**Impact**: All FileExplorer API calls failed with 500 errors
**Root Cause**: Module scope isolation prevented access to route execution environment functions
**Solution**: Use `Get-Command` with `&` operator to call global scope functions from within module
**Status**: ✅ Fixed, pending user testing

**Files Modified**: 4
- `FileExplorerHelper.psm1` - 31 function calls updated
- `files/get.ps1` - Added path parsing
- `files/post.ps1` - Added path parsing for 5 actions

**Next Steps**:
1. User tests FileExplorer in browser
2. Verify all operations work (load, create, upload, rename, delete)
3. Monitor logs for any remaining errors

---

**Created**: 2026-01-26
**Status**: ✅ READY FOR TESTING
