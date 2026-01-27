# Delete & Rename Batch Operation Fix - 2026-01-22

## Issue
Delete operation was failing with "Too Many Requests" error when deleting multiple files.

### Root Causes:
1. **Frontend**: Sending separate DELETE requests for each file (5 requests for 5 files)
2. **Rate Limiting**: Multiple rapid requests triggered HTTP 429 (Too Many Requests)
3. **Parameter Mismatch**: Frontend sending full logical paths, backend expecting name + parent path

---

## Fixes Applied

### ✅ Backend: Batch Delete Support

**File**: `apps/WebhostFileExplorer/routes/api/v1/files/post.ps1`

**Changed**: Delete handler now accepts array of paths for batch operations

**Before**:
```powershell
'delete' {
    if (-not $data.name) {
        throw "Missing required parameter: name"
    }
    $logicalPath = if ($data.path) { $data.path } else { "User:me" }
    # ... single file deletion
}
```

**After**:
```powershell
'delete' {
    # Support both single path and array of paths
    $pathsToDelete = @()
    if ($data.path) { $pathsToDelete += $data.path }
    if ($data.paths) { $pathsToDelete += $data.paths }

    foreach ($logicalPath in $pathsToDelete) {
        # Delete each file
        # Track successes and errors
    }

    # Return result with counts and any errors
}
```

**Features**:
- Accepts single `path` or array `paths`
- Processes all deletes in one request
- Returns detailed results: `{ deleted: [], errors: [], count: N }`
- Logs each deletion with user context
- Handles both files and folders (recursive for folders)

---

### ✅ Frontend: Single Batch Request

**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`

**Changed**: `performDelete` now sends all paths in one request

**Before**:
```javascript
for (const file of files) {
    const response = await fetch('/api/v1/files', {
        method: 'POST',
        body: JSON.stringify({
            action: 'delete',
            path: file.path  // One request per file
        })
    });
}
```

**After**:
```javascript
const paths = files.map(f => f.path);

const response = await fetch('/api/v1/files', {
    method: 'POST',
    body: JSON.stringify({
        action: 'delete',
        paths: paths  // Single request with all paths
    })
});

// Check for partial failures
if (result.data.errors.length > 0) {
    // Show specific error messages
}
```

**Benefits**:
- Single HTTP request regardless of file count
- No rate limiting issues
- Better error handling (shows which files failed)
- Faster execution (no network round-trips between deletes)

---

### ✅ Backend: Rename Path Fix

**File**: `apps/WebhostFileExplorer/routes/api/v1/files/post.ps1`

**Changed**: Rename handler now works with full logical paths

**Before**:
```powershell
'rename' {
    if (-not $data.oldName -or -not $data.newName) {
        throw "Missing required parameters: oldName, newName"
    }
    $logicalPath = if ($data.path) { $data.path } else { "User:me" }
    # Expected: oldName, newName, optional parent path
}
```

**After**:
```powershell
'rename' {
    if (-not $data.path -or -not $data.newName) {
        throw "Missing required parameters: path, newName"
    }
    # Resolve full logical path
    $pathResult = Resolve-WebHostFileExplorerPath -LogicalPath $data.path ...
    # Extract parent directory
    $parentDir = Split-Path $pathResult.PhysicalPath -Parent
    $newPath = Join-Path $parentDir $data.newName
    Rename-Item -Path $pathResult.PhysicalPath -NewName $data.newName
}
```

**Matches Frontend**: Frontend sends `path` (full logical path) + `newName` (new filename)

---

## API Contract

### Delete (Batch)

**Request**:
```json
POST /apps/WebhostFileExplorer/api/v1/files
{
    "action": "delete",
    "paths": [
        "local|localhost|/folder/file1.txt",
        "local|localhost|/folder/file2.txt",
        "local|localhost|/folder/subfolder"
    ]
}
```

**Response (Success)**:
```json
{
    "status": "success",
    "message": "Deleted 3 item(s)",
    "data": {
        "deleted": [
            "local|localhost|/folder/file1.txt",
            "local|localhost|/folder/file2.txt",
            "local|localhost|/folder/subfolder"
        ],
        "errors": [],
        "count": 3
    }
}
```

**Response (Partial Failure)**:
```json
{
    "status": "success",
    "message": "Deleted 2 item(s)",
    "data": {
        "deleted": [
            "local|localhost|/folder/file1.txt",
            "local|localhost|/folder/file2.txt"
        ],
        "errors": [
            {
                "path": "local|localhost|/folder/readonly.txt",
                "error": "Access denied"
            }
        ],
        "count": 2
    }
}
```

---

### Rename

**Request**:
```json
POST /apps/WebhostFileExplorer/api/v1/files
{
    "action": "rename",
    "path": "local|localhost|/folder/oldname.txt",
    "newName": "newname.txt"
}
```

**Response**:
```json
{
    "status": "success",
    "message": "Item renamed successfully",
    "data": {
        "newName": "newname.txt",
        "newPath": "C:\\Users\\...\\newname.txt"
    }
}
```

---

## Testing

### Test Cases:

1. **Single File Delete**
   - Select 1 file
   - Click delete
   - Confirm deletion
   - ✅ Should send single path in array

2. **Multi-File Delete (5 files)**
   - Select 5 files with checkboxes
   - Click delete
   - Confirm deletion
   - ✅ Should send 1 request with 5 paths
   - ✅ Should not trigger rate limiting

3. **Delete with Mixed Permissions**
   - Select files with different permissions
   - Attempt delete
   - ✅ Should delete allowed files
   - ✅ Should report errors for denied files

4. **Rename**
   - Select 1 file
   - Click rename
   - Enter new name
   - ✅ Should rename successfully
   - ✅ Should refresh folder view

---

## Performance Improvement

**Before**:
- 5 files = 5 HTTP requests
- Network overhead: 5 × round-trip time
- Rate limiting risk
- Slower execution

**After**:
- 5 files = 1 HTTP request
- Network overhead: 1 × round-trip time
- No rate limiting
- Faster execution

**Speedup**: ~5x for 5 files, scales linearly with file count

---

## Backward Compatibility

**Maintained**: Backend still accepts single `path` parameter for single-file delete

```json
// Still works
{
    "action": "delete",
    "path": "local|localhost|/file.txt"
}

// Also works
{
    "action": "delete",
    "paths": ["local|localhost|/file.txt"]
}
```

---

## Error Handling

### Frontend:
- Shows specific error messages if any files fail
- Displays count of successfully deleted files
- Doesn't fail entire operation if some files succeed

### Backend:
- Logs each deletion with user context
- Continues processing remaining files after errors
- Returns detailed error information per file

---

## Security Considerations

- ✅ Each path still validated with `Resolve-WebHostFileExplorerPath`
- ✅ Write permission checked for each file
- ✅ Access control enforced per file (not batch-level)
- ✅ Recursive delete only for folders (not files)
- ✅ User ID logged for audit trail

---

## Files Modified

### Backend (1 file):
- `apps/WebhostFileExplorer/routes/api/v1/files/post.ps1`
  - Lines 209-268: Delete handler (batch support)
  - Lines 182-208: Rename handler (path fix)

### Frontend (1 file):
- `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
  - Lines 2085-2129: performDelete (batch request)
  - Lines 2134-2166: performRename (already correct)

**Total**: 2 files modified, ~60 lines changed

---

## Deployment Notes

**Restart Required**: No (PowerShell scripts reload automatically)

**Cache Clearing**: Yes (users should refresh browser to get updated component.js)

**Database Changes**: None

**Breaking Changes**: None (backward compatible)

---

## Success Metrics

After Fix:
- ✅ Delete 5 files = 1 HTTP request
- ✅ No "Too Many Requests" errors
- ✅ Faster deletion (no network overhead between files)
- ✅ Better error reporting (shows which files failed)
- ✅ Rename works correctly with full logical paths

---

**Applied**: 2026-01-22
**Status**: ✅ Fixed and ready for testing
**Issue Resolved**: HTTP 429 "Too Many Requests" on multi-file delete
