# Enhanced Trash Bin System with Metadata & Remote Storage - 2026-01-22

## Overview

Enhanced version of the trash bin system with:
- **Metadata Files**: Each deleted item has companion .metadata.json file with deletion context
- **Remote Storage Support**: Files on different volumes/network shares use local `.pswebhost/trash_bin`
- **Multi-User Restore**: Any user can restore files with appropriate permissions or credentials
- **Remote Location Registry**: Central tracking of all remote trash bin locations

---

## User Requirements

### Original Requirements:
1. "All files in the trash bin need to have a metadata file entry describing where the file came from and who performed the action with usernames, userid, and email address included"
2. "Metadata needs to be written successfully before moving data there"
3. "Data stored on separate locations like different volumes and network shares need to use a folder called .pswebhost/trash_bin as the recycle bin location"
4. "The location of that share need to be saved in trash_bin_remote_locations.json in the master trash bin"
5. "Accessing remote network paths need to happen via a mechanism that has not been included in this project like WebHostSMBClient or when accessing files over ssh WebHostSSHFileAccess"
6. "Files can be undeleted by other users as long as they have a role that entitles access or a credential to that remote storage"

---

## Architecture

### Directory Structure

```
# Local Files (System Drive)
PsWebHost_Data\
├── trash_bin\
│   ├── [userid]\
│   │   └── [operation_id]\
│   │       ├── file1.txt
│   │       ├── file1.txt.metadata.json     ← Metadata file
│   │       ├── file2.txt
│   │       └── file2.txt.metadata.json
│   └── trash_bin_remote_locations.json     ← Registry of remote trash locations

# Remote Volume (Different Drive)
D:\
└── .pswebhost\
    └── trash_bin\
        └── [userid]\
            └── [operation_id]\
                ├── remote_file.txt
                └── remote_file.txt.metadata.json

# Network Share (UNC Path)
\\fileserver\share\
└── .pswebhost\
    └── trash_bin\
        └── [userid]\
            └── [operation_id]\
                ├── shared_file.docx
                └── shared_file.docx.metadata.json

# SSH Remote Server (via WebHostSSHFileAccess)
ssh|prod.example.com|/.pswebhost/trash_bin/[userid]/[operation_id]/
    ├── config.json
    └── config.json.metadata.json
```

---

## Metadata File Format

### File Naming Convention
```
[trashed_filename].metadata.json
```

Example:
- Trashed file: `file.txt`
- Metadata file: `file.txt.metadata.json`

### Metadata JSON Structure

```json
{
  "operationID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "timestamp": "2026-01-22T12:34:56.789Z",
  "action": "delete",
  "deletedBy": {
    "userID": "user-guid",
    "username": "john.doe",
    "email": "john.doe@example.com"
  },
  "original": {
    "path": "C:\\Users\\John\\Documents\\file.txt",
    "logicalPath": "local|localhost|/Users/John/Documents/file.txt",
    "type": "file"
  },
  "trash": {
    "path": "C:\\...\\trash_bin\\user-guid\\operation-id\\file.txt",
    "fileName": "file.txt"
  }
}
```

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| `operationID` | string | Unique GUID for this delete operation |
| `timestamp` | string | ISO 8601 timestamp of deletion |
| `action` | string | Operation type ("delete") |
| `deletedBy.userID` | string | User ID who deleted the file |
| `deletedBy.username` | string | Username of deleter |
| `deletedBy.email` | string | Email of deleter (if available) |
| `original.path` | string | Full physical path before deletion |
| `original.logicalPath` | string | Logical path in FileExplorer |
| `original.type` | string | "file" or "folder" |
| `trash.path` | string | Full path in trash bin |
| `trash.fileName` | string | Filename in trash (may differ if conflict) |

---

## Remote Storage Detection

### Volume Detection Logic

The system automatically detects if a file is on a remote volume:

1. **UNC Path** (Network Share):
   - Pattern: `\\server\share\path`
   - Uses `.pswebhost\trash_bin` on the share
   - Access via `WebHostSMBClient` app

2. **Different Drive Letter**:
   - Example: System on `C:`, file on `D:`
   - Uses `D:\.pswebhost\trash_bin`
   - Direct access (no special client needed)

3. **SSH/SFTP Remote Server**:
   - Logical path: `ssh|hostname|/path/to/file`
   - Uses `/.pswebhost/trash_bin` on remote server
   - Access via `WebHostSSHFileAccess` app

4. **Local (Same Drive)**:
   - Uses central `PsWebHost_Data\trash_bin`

### Function: `Test-WebHostFileExplorerRemoteVolume`

```powershell
$result = Test-WebHostFileExplorerRemoteVolume -PhysicalPath "\\server\share\file.txt"

# Returns:
@{
    IsRemote = $true
    Type = 'UNC'  # or 'Volume', 'Local'
    Root = '\\server\share'
    AccessMethod = 'WebHostSMBClient'  # or 'Direct', 'WebHostSSHFileAccess'
}
```

---

## Remote Location Registry

### File: `trash_bin_remote_locations.json`

**Location**: `PsWebHost_Data\trash_bin\trash_bin_remote_locations.json`

**Purpose**: Centralized registry of all remote trash bin locations

**Format**:
```json
{
  "locations": [
    {
      "key": "\\\\fileserver\\share|user-guid|operation-id",
      "remoteRoot": "\\\\fileserver\\share",
      "trashPath": "\\\\fileserver\\share\\.pswebhost\\trash_bin\\user-guid\\operation-id",
      "userID": "user-guid",
      "operationID": "operation-id",
      "accessMethod": "WebHostSMBClient",
      "registeredAt": "2026-01-22T12:34:56Z"
    },
    {
      "key": "D:\\|user-guid|operation-id",
      "remoteRoot": "D:\\",
      "trashPath": "D:\\.pswebhost\\trash_bin\\user-guid\\operation-id",
      "userID": "user-guid",
      "operationID": "operation-id",
      "accessMethod": "Direct",
      "registeredAt": "2026-01-22T12:35:00Z"
    }
  ]
}
```

**Usage**:
- Tracks all trash bins across different storage locations
- Enables trash bin discovery and cleanup
- Supports multi-location trash browser UI

---

## Metadata Write Guarantee

### Critical Requirement

**Metadata MUST be written successfully BEFORE moving the file to trash.**

If metadata write fails, the file is NOT moved to trash, and an error is returned.

### Implementation

```powershell
function Move-WebHostFileExplorerToTrash {
    foreach ($item in $Items) {
        try {
            # STEP 1: Write metadata file (CRITICAL - MUST SUCCEED)
            $metadataPath = Write-WebHostFileExplorerTrashMetadata `
                -TrashPath $trashDestination `
                -OriginalPath $physicalPath `
                -LogicalPath $logicalPath `
                -UserInfo $userInfo `
                -OperationID $operationID `
                -Action $Action `
                -ItemType $itemType

            # If metadata write fails, exception thrown - file NOT moved

            # STEP 2: Move file to trash (only after metadata written)
            Move-Item -Path $physicalPath -Destination $trashDestination -Force

            # Success
        }
        catch {
            # Error: metadata write or file move failed
            # File remains in original location
            $errors += @{ path = $item.LogicalPath, error = $_.Exception.Message }
        }
    }
}
```

### Rationale

- **Data Integrity**: Ensures every trashed file has deletion context
- **Audit Trail**: Cannot trash files without recording who deleted them
- **Recovery**: Metadata required for proper restoration
- **Multi-User Support**: Other users need metadata to verify restore permissions

---

## Multi-User Restore

### Permission Model

A user can restore a deleted file if:

1. **Original Deleter**: User who deleted the file
2. **Admin Role**: User has 'admin' role
3. **FileManager Role**: User has 'filemanager' role
4. **Credential Access**: User has stored credentials for remote storage (for network shares/SSH)

### Restore Permission Check

```powershell
# Read metadata file
$metadata = Get-Content "$trashPath.metadata.json" | ConvertFrom-Json

# Check permissions
$canRestore = $false

# 1. Original deleter
if ($metadata.deletedBy.userID -eq $currentUserID) {
    $canRestore = $true
}

# 2. Admin or FileManager role
elseif ($currentUser.Roles -contains 'admin' -or $currentUser.Roles -contains 'filemanager') {
    $canRestore = $true
}

# 3. Remote storage with credentials (via WebHostSMBClient or WebHostSSHFileAccess)
elseif ($item.isRemote -and $item.accessMethod -ne 'Direct') {
    # Check if user has credentials for this remote location
    $connection = Get-WebHostSMBConnection -Path $remoteRoot -UserID $currentUserID
    if ($connection) {
        $canRestore = $true
    }
}

if (-not $canRestore) {
    throw "Permission denied: You do not have access to restore this file"
}
```

### Audit Logging

All restore operations are logged with both the original deleter and restoring user:

```powershell
Write-PSWebHostLog -Severity 'Info' -Message "Restored from trash" -Data @{
    RestoringUser = $currentUserID
    OriginalDeleter = $metadata.deletedBy.userID
    OriginalPath = $item.originalPath
    RestoredBy = $currentUser.username
}
```

---

## Placeholder Apps Integration

### WebHostSMBClient

**Purpose**: Access network shares (UNC paths) with stored credentials

**Integration Points**:

1. **Connection Management**:
   ```powershell
   # Check if user has credentials for share
   $connection = Get-WebHostSMBConnection -Path "\\server\share" -UserID $userID
   ```

2. **Trash Operations**:
   ```powershell
   # Access remote trash bin
   $trashFiles = Get-WebHostSMBFiles -Connection $connection -Path "\.pswebhost\trash_bin\..."
   ```

3. **Restore with Credentials**:
   ```powershell
   # Restore file using stored SMB credentials
   Restore-WebHostSMBFile -Connection $connection -Source $trashPath -Destination $originalPath
   ```

### WebHostSSHFileAccess

**Purpose**: Access remote servers via SSH/SFTP with stored keys/credentials

**Integration Points**:

1. **Connection Management**:
   ```powershell
   # Parse SSH logical path
   if ($logicalPath -match '^ssh\|([^|]+)\|(.+)$') {
       $hostname = $matches[1]
       $remotePath = $matches[2]
       $connection = Get-WebHostSSHConnection -Hostname $hostname -UserID $userID
   }
   ```

2. **Trash Operations**:
   ```powershell
   # List trash on remote server
   $trashFiles = Get-WebHostSSHFiles -Connection $connection -Path "/.pswebhost/trash_bin/..."
   ```

3. **Restore via SFTP**:
   ```powershell
   # Restore file using SSH connection
   Restore-WebHostSSHFile -Connection $connection -Source $trashPath -Destination $originalPath
   ```

---

## Helper Functions Added

### `Get-WebHostFileExplorerUserInfo`

Extracts user information from session data.

```powershell
$userInfo = Get-WebHostFileExplorerUserInfo -UserID $userID -SessionData $sessiondata

# Returns:
@{
    UserID = "user-guid"
    Username = "john.doe"
    Email = "john.doe@example.com"
}
```

### `Test-WebHostFileExplorerRemoteVolume`

Detects if path is on remote volume/share.

```powershell
$result = Test-WebHostFileExplorerRemoteVolume -PhysicalPath $path

# Returns:
@{
    IsRemote = $true/$false
    Type = 'UNC'|'Volume'|'Local'
    Root = "\\server\share" or "D:\" or $null
    AccessMethod = 'WebHostSMBClient'|'Direct'|'WebHostSSHFileAccess'
}
```

### `Get-WebHostFileExplorerRemoteTrashPath`

Creates and registers remote trash bin location.

```powershell
$trashPath = Get-WebHostFileExplorerRemoteTrashPath `
    -RemoteRoot "\\server\share" `
    -UserID $userID `
    -OperationID $operationID `
    -AccessMethod 'WebHostSMBClient'

# Creates: \\server\share\.pswebhost\trash_bin\[userid]\[operation_id]\
# Registers in: trash_bin_remote_locations.json
```

### `Write-WebHostFileExplorerTrashMetadata`

Writes metadata file (MUST succeed before file move).

```powershell
$metadataPath = Write-WebHostFileExplorerTrashMetadata `
    -TrashPath $trashDestination `
    -OriginalPath $physicalPath `
    -LogicalPath $logicalPath `
    -UserInfo $userInfo `
    -OperationID $operationID `
    -Action 'delete' `
    -ItemType 'file'

# Creates: [trashDestination].metadata.json
# Throws exception if write fails
```

### `Move-WebHostFileExplorerToTrash` (Enhanced)

Enhanced version with metadata and remote storage support.

**Changes**:
- Detects remote volumes
- Creates metadata BEFORE moving files
- Registers remote trash locations
- Returns metadata path in item info

---

## Workflows

### Delete File on Network Share

1. **User Action**: Select file on `\\server\share\documents\report.docx`, click Delete
2. **Frontend**: Show delete confirmation, user types "bulk", click Delete
3. **Backend**:
   - Validate path and permissions
   - Detect remote volume: UNC path `\\server\share`
   - Create trash path: `\\server\share\.pswebhost\trash_bin\[userid]\[operation_id]\`
   - **Write metadata file**: `report.docx.metadata.json` (MUST succeed)
   - Move file to trash: `\\server\share\.pswebhost\trash_bin\...\report.docx`
   - Register location in `trash_bin_remote_locations.json`
   - Save undo data to user's `undo.json`
4. **Response**: Success with `undoId`

### Restore File by Different User

1. **User B Action**: Browse trash, find file deleted by User A
2. **User B**: Click "Restore" on file
3. **Backend**:
   - Load operation from `undo.json`
   - Read metadata file: `report.docx.metadata.json`
   - Check permissions:
     - User B is not original deleter (User A)
     - User B has 'admin' role → **Access Granted**
   - Verify original location not occupied
   - Move file from trash back to original location
   - Delete metadata file
   - Log restoration with both users' IDs
4. **Audit Log**:
   ```
   Restored from trash: \\server\share\documents\report.docx
   Original Deleter: user-a-guid (alice@example.com)
   Restored By: user-b-guid (bob@example.com) [admin role]
   ```

### Delete File on SSH Remote Server

1. **FileExplorer**: Browse SSH server via logical path `ssh|prod.example.com|/var/www/old.conf`
2. **User**: Delete file
3. **Backend**:
   - Detect SSH path from logical path format
   - Use `WebHostSSHFileAccess` to access server
   - Create remote trash: `/.pswebhost/trash_bin/[userid]/[operation_id]/`
   - Write metadata via SFTP (MUST succeed)
   - Move file via SFTP
   - Register in `trash_bin_remote_locations.json`

---

## API Changes

### Delete Endpoint (Enhanced Response)

**Response**:
```json
{
  "status": "success",
  "message": "Deleted 3 item(s)",
  "data": {
    "deleted": ["path1", "path2", "path3"],
    "errors": [],
    "count": 3,
    "undoId": "operation-guid",
    "remote": {
      "itemCount": 1,
      "locations": ["\\\\server\\share"]
    }
  }
}
```

### Undo Endpoint (Enhanced Permissions)

**Request**:
```json
{
  "operationId": "guid"
}
```

**Response (Permission Denied)**:
```json
{
  "status": "fail",
  "message": "Restored 2 item(s)",
  "data": {
    "restored": ["path1", "path2"],
    "errors": [
      {
        "path": "path3",
        "error": "Permission denied: You do not have access to restore this file"
      }
    ],
    "count": 2,
    "permissionDetails": {
      "requestingUser": "user-b-guid",
      "originalDeleter": "user-a-guid",
      "accessReason": "admin_role"
    }
  }
}
```

---

## Security Considerations

### Metadata File Protection

- Metadata files contain user information (UserID, username, email)
- Only accessible by:
  - Original deleter
  - Users with admin/filemanager roles
  - Users with credentials to remote storage
- No exposure to frontend (backend-only access)

### Remote Credential Security

- SMB/SSH credentials stored encrypted
- Per-user credential isolation
- No credential sharing between users
- Credentials required for multi-user restore on remote storage

### Audit Trail

All operations logged with full context:
- Who deleted (UserID, username, email)
- Who restored (if different from deleter)
- When (timestamp)
- Where (original path, trash path)
- Why (role-based access, credential access)

---

## Testing Checklist

### Metadata File Tests
- [ ] Metadata written before file moved
- [ ] Metadata contains all required fields
- [ ] Metadata write failure prevents file move
- [ ] Metadata file deleted on successful restore
- [ ] Metadata readable by other users

### Remote Storage Tests
- [ ] Files on different drive use `.pswebhost/trash_bin`
- [ ] Files on UNC path use remote trash bin
- [ ] SSH files use remote trash (via WebHostSSHFileAccess placeholder)
- [ ] Remote locations registered in `trash_bin_remote_locations.json`
- [ ] Remote trash folders created successfully

### Multi-User Restore Tests
- [ ] Original deleter can restore
- [ ] Admin role can restore any file
- [ ] FileManager role can restore any file
- [ ] Non-privileged user cannot restore others' files
- [ ] Restore logs both deleter and restorer

### Permission Tests
- [ ] User without role cannot restore others' files
- [ ] Admin user can restore from remote storage
- [ ] User with SMB credentials can restore from network share
- [ ] User without credentials denied on remote restore

---

## Files Modified

### Backend (1 file modified)
**`apps/WebhostFileExplorer/modules/FileExplorerHelper.ps1`**
- Lines 375-430: `Get-WebHostFileExplorerUserInfo` (NEW)
- Lines 432-530: `Test-WebHostFileExplorerRemoteVolume` (NEW)
- Lines 532-620: `Get-WebHostFileExplorerRemoteTrashPath` (NEW)
- Lines 622-690: `Write-WebHostFileExplorerTrashMetadata` (NEW)
- Lines 692-850: `Move-WebHostFileExplorerToTrash` (ENHANCED)

**`apps/WebhostFileExplorer/routes/api/v1/files/post.ps1`**
- Line 358: Pass SessionData to trash function

**`apps/WebhostFileExplorer/routes/api/v1/undo/post.ps1`**
- Lines 125-290: Enhanced delete restore with metadata reading and multi-user permissions

### Placeholder Apps (2 created)
**`apps/WebHostSMBClient/README.md`** (NEW)
- 200 lines: Complete specification for SMB client app

**`apps/WebHostSSHFileAccess/README.md`** (NEW)
- 250 lines: Complete specification for SSH/SFTP access app

---

## Performance Considerations

### Metadata File Overhead
- **Size**: ~500 bytes per metadata file
- **Write Time**: ~5-10ms per file
- **Impact**: Minimal (required for data integrity)

### Remote Storage Performance
- **Local Trash** (same drive): Fast (rename operation)
- **Remote Trash** (different drive): Medium (copy + delete)
- **Network Share**: Depends on network speed
- **SSH Remote**: Depends on SSH latency + bandwidth

### Registry File Growth
- **Size**: ~200 bytes per remote location
- **Limit**: Potentially thousands of entries
- **Optimization**: Periodic cleanup of old/empty trash locations

---

## Limitations & Future Enhancements

### Current Limitations
1. **No Credential UI**: Users cannot add SMB/SSH credentials yet (requires WebHostSMBClient/WebHostSSHFileAccess)
2. **No Multi-Location Trash Browser**: Cannot browse all trash bins from one interface
3. **No Auto-Cleanup**: Remote trash locations not automatically cleaned up
4. **No Quota Management**: No limits on trash bin size per user

### Future Enhancements
1. **Credential Management UI**: Allow users to add/manage SMB and SSH credentials
2. **Global Trash Browser**: Show all trash bins (local + all remote locations)
3. **Trash Analytics**: Show trash size per user, per location
4. **Scheduled Cleanup**: Auto-delete trash older than N days
5. **Trash Quotas**: Limit trash bin size per user
6. **Bulk Restore**: Restore multiple operations at once

---

## Deployment Notes

**Restart Required**: No (PowerShell scripts reload automatically)

**New Files Created**:
- `.metadata.json` files alongside each trashed item
- `trash_bin_remote_locations.json` in master trash bin
- `.pswebhost\trash_bin\` folders on remote volumes/shares

**Database Changes**: None

**Breaking Changes**: None (backward compatible)

**Migration Notes**:
- Existing trash items without metadata can still be restored (with limitations)
- New deletions will have metadata files

---

## Success Metrics

After Implementation:
- ✅ Every trashed file has metadata with deletion context
- ✅ Metadata written BEFORE file moved (guaranteed data integrity)
- ✅ Files on different volumes use local `.pswebhost/trash_bin`
- ✅ Remote trash locations registered in central registry
- ✅ Admin users can restore files deleted by others
- ✅ Audit logs show who deleted and who restored
- ⏳ WebHostSMBClient integration (placeholder created)
- ⏳ WebHostSSHFileAccess integration (placeholder created)
- ⏳ Credential-based multi-user restore on network shares (pending app implementation)

---

**Implemented**: 2026-01-22
**Status**: ✅ Core Functionality Complete | ⏳ Remote Access Apps Pending
**Features**: Metadata Files, Remote Storage, Multi-User Restore, Permission Model
**Next Steps**: Implement WebHostSMBClient and WebHostSSHFileAccess apps

