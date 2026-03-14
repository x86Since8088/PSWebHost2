# Path Resolution Architecture

## Overview

The File Explorer now uses a centralized path resolution system with logical path aliases that map to physical filesystem paths with role-based authorization.

## Logical Path Format

All file operations use logical paths with the format: `Prefix:Identifier/RelativePath`

### Supported Path Prefixes

| Prefix | Format | Description | Authorization |
|--------|--------|-------------|---------------|
| `User` | `User:me/path` | Personal user storage | Authenticated users (own storage only) |
| `Bucket` | `Bucket:{bucketId}/path` | Shared bucket storage | Group membership required |
| `Site` | `Site/path` | Project root access | site_admin or system_admin |
| `System` | `System:{drive}/path` | System paths | system_admin only |
| `Manual` | `Manual:{name}/path` | Manually mounted paths | Future implementation |

### Examples

```
User:me                       → C:\SC\PsWebHost\PsWebHost_Data\UserData\user@example.com\personal
User:me/Documents             → C:\SC\PsWebHost\PsWebHost_Data\UserData\user@example.com\personal\Documents
Bucket:abc-123                → C:\SC\PsWebHost\PsWebHost_Data\SharedBuckets\abc-123
Bucket:abc-123/Reports        → C:\SC\PsWebHost\PsWebHost_Data\SharedBuckets\abc-123\Reports
Site                          → C:\SC\PsWebHost
Site/public                   → C:\SC\PsWebHost\public
Site/routes/api               → C:\SC\PsWebHost\routes\api
System:C                      → C:\
System:C/temp                 → C:\temp
System:root                   → / (Linux)
System:root/var/log           → /var/log (Linux)
```

## Path Resolution Utility

**Location**: `system/utility/Path_Resolve.ps1`

### Parameters

- `LogicalPath` - The logical path to resolve
- `UserID` - The user requesting access
- `Roles` - Array of user's roles
- `RequiredPermission` - Required permission level ('read', 'write', 'owner')

### Returns

```powershell
@{
    Success = $true/$false
    PhysicalPath = "C:\actual\filesystem\path"
    BasePath = "C:\base\path"
    RelativePath = "relative/part"
    StorageType = "personal"/"bucket"/"site"/"system"
    AccessLevel = "owner"/"write"/"read"
    Message = "Error message if failed"
}
```

### Authorization Rules

#### User:me (Personal Storage)
- Requires `authenticated` role
- Always grants `owner` access to own storage
- Maps to `PsWebHost_Data/UserData/{UserID}/personal/`

#### Bucket:{bucketId}
- Requires group membership in bucket's Owner/Write/Read groups
- Access level determined by group membership
- Permission hierarchy: owner > write > read
- Maps to `PsWebHost_Data/SharedBuckets/{bucketId}/`

#### Site
- Requires `site_admin` or `system_admin` role
- `site_admin` restricted to `public/` and `routes/` only
- `system_admin` has full project root access
- Maps to project root directory

#### System:{drive}
- Requires `system_admin` role only
- Windows: `System:C` → `C:\`
- Linux: `System:root` → `/`
- Full filesystem access with no restrictions

## API Endpoints

### GET /api/v1/files

**Query Parameters:**
- `path` - Logical path (default: `User:me`)

**Response:**
```json
{
    "tree": { "name": "root", "type": "folder", "children": [...] },
    "path": "User:me/Documents",
    "storageType": "personal",
    "accessLevel": "owner",
    "basePath": "C:\\SC\\PsWebHost\\PsWebHost_Data\\UserData\\user@example.com\\personal"
}
```

### POST /api/v1/files

**Request Body:**
```json
{
    "action": "createFolder" | "uploadFile" | "rename" | "delete",
    "path": "User:me/Documents",  // Logical path
    "name": "NewFolder",
    ...
}
```

## Frontend Integration

### Storage Source State

The frontend maintains storage source state with logical path prefixes:

```javascript
const [currentPath, setCurrentPath] = useState('User:me');

// Switch to bucket
setCurrentPath('Bucket:abc-123');

// Navigate to subfolder
setCurrentPath('Bucket:abc-123/Reports');

// Switch to site admin view
setCurrentPath('Site/public');

// System admin view
setCurrentPath('System:C');
```

### File Operations

All file operations include the full logical path:

```javascript
fetch('/apps/WebhostFileExplorer/api/v1/files', {
    method: 'POST',
    body: JSON.stringify({
        action: 'createFolder',
        path: 'User:me/Documents',  // Full logical path
        name: 'NewFolder'
    })
});
```

## Navigation

Navigation works by appending to the logical path:

```
User:me                  // Root of personal storage
User:me/Documents        // Documents folder
User:me/Documents/Work   // Work subfolder
```

When navigating up:
- Split path by `/`
- Remove last segment
- Rejoin

## Security Benefits

1. **Centralized Authorization**: All path access goes through single validation point
2. **No Path Traversal**: Relative paths are sanitized, `..` removed
3. **Role-Based Access**: Each path prefix has explicit role requirements
4. **Permission Hierarchy**: owner > write > read enforced consistently
5. **Audit Trail**: All path resolutions can be logged centrally

## Migration Notes

### Old API (Deprecated)
```
GET /api/v1/files?source=personal
GET /api/v1/files?source=bucket&bucketId=abc-123
GET /api/v1/files?source=system&systemPath=C:\temp
```

### New API
```
GET /api/v1/files?path=User:me
GET /api/v1/files?path=Bucket:abc-123
GET /api/v1/files?path=System:C/temp
```

The old API parameters (`source`, `bucketId`, `systemPath`) are deprecated but may be supported temporarily for backward compatibility.

## Future Enhancements

### Manual Paths (Future)
```
Manual:nas-server/path   → Manually configured mount points
Manual:s3-bucket/path    → Cloud storage integration
Manual:ftp-site/path     → Remote filesystem access
```

### Path Aliases (Future)
```
@home    → User:me
@desktop → User:me/Desktop
@docs    → User:me/Documents
```

### Symbolic Links (Future)
- Link between different storage types
- Example: Link from `User:me/Shortcuts/Reports` → `Bucket:abc-123/Reports`

## Implementation Status

- ✅ Path_Resolve.ps1 utility created
- ✅ GET /api/v1/files updated to use logical paths
- ✅ GET /api/v1/files/preview updated to use logical paths
- ✅ GET /api/v1/files/download updated to use logical paths
- ✅ POST /api/v1/files/upload-chunk updated to use logical paths
- ✅ POST /api/v1/files updated to use logical paths (all file operations)
- ✅ GET /api/v1/buckets returns logical path prefixes
- ✅ GET /api/v1/system-paths returns logical path prefixes
- ✅ Frontend component.js updated to use logical paths
