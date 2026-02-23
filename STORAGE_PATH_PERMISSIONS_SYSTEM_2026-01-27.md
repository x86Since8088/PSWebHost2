# Storage Path Permissions System - Implementation Summary
**Date**: 2026-01-27
**Status**: ✅ COMPLETED

---

## Overview

This session implemented a comprehensive storage path permissions system for FileExplorer, allowing administrators to register storage paths in the database and assign fine-grained permissions to Roles, Groups, and Users. The system includes a full-featured FileSharingModal component for managing storage paths and permissions.

---

## Architecture

### Database Schema

Added 2 new tables to `system/db/sqlite/sqliteconfig.json`:

#### 1. Storage_Paths Table
Registers storage locations with metadata:
```sql
CREATE TABLE Storage_Paths (
    PathID TEXT PRIMARY KEY,
    LogicalPath TEXT UNIQUE NOT NULL,        -- e.g., "User:me" or "System:C"
    PhysicalPath TEXT NOT NULL,              -- e.g., "C:\Users\test\Documents"
    Name TEXT NOT NULL,                       -- Display name
    Description TEXT,                         -- Optional description
    OwnerUserID TEXT NOT NULL,               -- Path owner
    CreatedTime INTEGER NOT NULL,            -- Unix timestamp
    UpdatedTime INTEGER NOT NULL,            -- Unix timestamp
    IsActive INTEGER DEFAULT 1,              -- Soft delete flag
    FOREIGN KEY (OwnerUserID) REFERENCES Users(UserID) ON DELETE CASCADE
)
```

#### 2. Storage_Path_Permissions Table
Flexible permission model supporting Roles, Groups, and Users:
```sql
CREATE TABLE Storage_Path_Permissions (
    PathID TEXT NOT NULL,
    PermissionType TEXT NOT NULL CHECK(PermissionType IN ('owner', 'read', 'write')),
    PrincipalType TEXT NOT NULL CHECK(PrincipalType IN ('role', 'group', 'user')),
    PrincipalID TEXT NOT NULL,
    PRIMARY KEY (PathID, PermissionType, PrincipalType, PrincipalID),
    FOREIGN KEY (PathID) REFERENCES Storage_Paths(PathID) ON DELETE CASCADE
)
```

**Permission Examples**:
- Role: `{PrincipalType: 'role', PrincipalID: 'admin'}`
- Group: `{PrincipalType: 'group', PrincipalID: 'editors-group'}`
- User: `{PrincipalType: 'user', PrincipalID: 'john.doe@example.com'}`

---

## Backend Endpoints

### 1. POST /api/v1/storage/paths - Register Storage Path
**File**: `apps/WebhostFileExplorer/routes/api/v1/storage/paths/post.ps1`

**Features**:
- Validates physical path exists
- Auto-creates groups: `{name}_owners`, `{name}_readers`, `{name}_writers`
- Inserts into Storage_Paths table
- Assigns permissions to principals
- Returns created groups and permissions

**Request Body**:
```json
{
  "logicalPath": "User:me",
  "physicalPath": "C:\\Users\\test\\Documents",
  "name": "My Documents",
  "description": "Personal document storage",
  "autoCreateGroups": true,
  "permissions": [
    {
      "type": "owner",
      "principals": [
        { "principalType": "role", "principalId": "admin" }
      ]
    },
    {
      "type": "read",
      "principals": [
        { "principalType": "group", "principalId": "viewers-group" }
      ]
    }
  ]
}
```

**Response**:
```json
{
  "status": "success",
  "data": {
    "pathID": "a1b2c3d4-...",
    "logicalPath": "User:me",
    "physicalPath": "C:\\Users\\test\\Documents",
    "name": "My Documents",
    "createdGroups": [
      { "groupID": "...", "name": "My_Documents_owners", "type": "owner" },
      { "groupID": "...", "name": "My_Documents_readers", "type": "read" },
      { "groupID": "...", "name": "My_Documents_writers", "type": "write" }
    ],
    "permissions": [...]
  }
}
```

**Security**: `admin`, `site_admin`, `system_admin` roles required

---

### 2. GET /api/v1/storage/paths - List Storage Paths
**File**: `apps/WebhostFileExplorer/routes/api/v1/storage/paths/get.ps1`

**Features**:
- Filters paths by user's access (owner, role, group, explicit user permission)
- Returns permissions for each path grouped by type (owner/read/write)
- Resolves principal names (user emails, group names, role names)
- Returns user's effective permissions for each path

**Response**:
```json
{
  "status": "success",
  "data": {
    "paths": [
      {
        "pathID": "...",
        "logicalPath": "User:me",
        "physicalPath": "C:\\Users\\test\\Documents",
        "name": "My Documents",
        "description": "Personal document storage",
        "ownerUserID": "test@example.com",
        "createdTime": 1706313600,
        "updatedTime": 1706313600,
        "isActive": true,
        "permissions": {
          "owner": [
            { "principalType": "role", "principalId": "admin", "name": "admin" }
          ],
          "read": [
            { "principalType": "group", "principalId": "...", "name": "viewers-group" }
          ],
          "write": []
        },
        "userPermissions": ["owner", "read"]
      }
    ],
    "count": 1
  }
}
```

**Security**: All authenticated users (empty `Allowed_Roles`)

---

### 3. PUT /api/v1/storage/paths - Update Permissions
**File**: `apps/WebhostFileExplorer/routes/api/v1/storage/paths/put.ps1`

**Features**:
- Verifies user is path owner or has owner permission
- Deletes existing permissions
- Inserts new permissions
- Updates `UpdatedTime` timestamp

**Request Body**:
```json
{
  "pathID": "a1b2c3d4-...",
  "permissions": [
    {
      "type": "owner",
      "principals": [
        { "principalType": "role", "principalId": "admin" },
        { "principalType": "user", "principalId": "john@example.com" }
      ]
    },
    {
      "type": "read",
      "principals": [
        { "principalType": "group", "principalId": "viewers-group" }
      ]
    },
    {
      "type": "write",
      "principals": [
        { "principalType": "group", "principalId": "editors-group" }
      ]
    }
  ]
}
```

**Security**: All authenticated users (permission checked in code)

---

### 4. DELETE /api/v1/storage/paths - Deactivate Path
**File**: `apps/WebhostFileExplorer/routes/api/v1/storage/paths/delete.ps1`

**Features**:
- Soft delete (sets `IsActive = 0`)
- Verifies user is path owner or has owner permission
- Updates `UpdatedTime` timestamp

**Request**: `DELETE /api/v1/storage/paths?pathID=a1b2c3d4-...`

**Response**:
```json
{
  "status": "success",
  "data": {
    "pathID": "a1b2c3d4-...",
    "name": "My Documents",
    "deactivated": true,
    "updatedTime": 1706313600
  }
}
```

**Security**: All authenticated users (permission checked in code)

---

## Path Resolution Integration

### Updated Path_Resolve.ps1
**File**: `system/utility/Path_Resolve.ps1`

**Added Storage_Path_Permissions Check** (lines 260-330):

When resolving a path, the system now:
1. Queries `Storage_Paths` by `LogicalPath`
2. If registered, checks `Storage_Path_Permissions`:
   - User is owner → `AccessLevel = 'owner'`
   - User has explicit permission via role/group/user → `AccessLevel = granted permission`
   - No permission found → Access denied
3. If not registered, uses default permissions from switch statement
4. Falls back gracefully if tables don't exist (for backward compatibility)

**Permission Query Logic**:
```sql
SELECT PermissionType
FROM Storage_Path_Permissions
WHERE PathID = @PathID
AND (
    (PrincipalType = 'user' AND PrincipalID = @UserID)
    OR (PrincipalType = 'group' AND PrincipalID IN (SELECT value FROM json_each(@GroupIDs)))
    OR (PrincipalType = 'role' AND PrincipalID IN (SELECT value FROM json_each(@Roles)))
)
ORDER BY CASE PermissionType
    WHEN 'owner' THEN 3
    WHEN 'write' THEN 2
    WHEN 'read' THEN 1
END DESC
LIMIT 1
```

This ensures users get the highest permission level they're entitled to.

---

## FileSharingModal Component

### Frontend Component
**File**: `apps/WebhostFileExplorer/public/elements/file-sharing-modal/component.js`

**Features**:
- **Two-Tab Interface**:
  - Register New Path: Form for creating storage paths
  - Manage Paths: List and edit existing paths

- **Registration Form**:
  - Logical Path (pre-filled if passed via URL param)
  - Physical Path (must exist on filesystem)
  - Name and Description
  - Auto-create groups checkbox
  - Manual permission assignment (if not auto-creating)

- **Permission Management**:
  - Three permission types: Owner, Read, Write
  - Principal selector: Role, Group, or User
  - Add/remove principals for each permission type
  - Visual badges for different principal types

- **Storage Path List**:
  - Shows all paths user has access to
  - Displays logical → physical path mapping
  - Shows user's effective permissions
  - Edit button: Opens permission editor inline
  - Delete button: Deactivates storage path

**UI Endpoint**:
**File**: `apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-sharing-modal/get.ps1`

Returns standalone HTML page with:
- React 18 (production build)
- FileSharingModal component
- Dark theme styling (VS Code-inspired)
- Opens as SPA card via `window.openCard()`

**Security**: `admin`, `site_admin`, `system_admin` roles required

---

## FileExplorer Integration

### Updated component.js

**Changes** (lines 2435-2436):
```javascript
const [fileActionModal, setFileActionModal] = useState({ visible: false, file: null });
const [fileSharingModal, setFileSharingModal] = useState({ visible: false, filePath: null });
```

**Updated onShare Handler** (line 6610):
```javascript
onShare={(file) => {
    // Build logical path for the file
    const logicalPath = buildTreePath(currentPath.bucket, file.path || file.name);

    // Open File Sharing Modal in a card
    window.openCard(
        `/apps/WebhostFileExplorer/cards/file-sharing-modal?path=${encodeURIComponent(logicalPath)}`,
        `Share: ${file.name}`
    );

    setFileActionModal({ visible: false, file: null });
}}
```

Now when users:
1. Double-click a file → FileActionModal opens
2. Click "Share" → FileSharingModal opens in a new card
3. Can register the path with permissions
4. Path is now protected by Storage_Path_Permissions

---

## Security Architecture

### Three-Layer Permission Model

1. **Default Permissions** (Path_Resolve.ps1 switch statement):
   - `User:me` → Owner (all authenticated users)
   - `User:others` → Admin (system_admin only)
   - `Bucket:{id}` → Checked via Bucket_Access_Check.ps1
   - `Site` → Admin (site_admin, system_admin)
   - `System:{drive}` → Admin (system_admin only)

2. **Storage Path Permissions** (overrides default):
   - If path registered in `Storage_Paths`
   - Check `Storage_Path_Permissions` for user's roles, groups, and direct assignment
   - Highest permission level wins

3. **Endpoint Security** (security.json files):
   - Storage management endpoints: Admin roles only
   - Content endpoints: All authenticated users
   - Editor endpoints: Admin roles only

### Permission Hierarchy
```
owner (3) = admin (3) > write (2) > read (1)
```

Users can only perform operations if their permission level ≥ required level.

---

## Usage Examples

### Example 1: Register Personal Storage with Auto-Groups

**Request**:
```javascript
const response = await fetch('/apps/WebhostFileExplorer/api/v1/storage/paths', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        logicalPath: 'User:me',
        physicalPath: 'C:\\Users\\test\\Documents',
        name: 'My Documents',
        description: 'Personal document storage',
        autoCreateGroups: true
    })
});
```

**Result**:
- Creates 3 groups: `My_Documents_owners`, `My_Documents_readers`, `My_Documents_writers`
- Assigns groups to owner, read, write permissions
- Path now registered in database

### Example 2: Register System Path with Custom Permissions

**Request**:
```javascript
const response = await fetch('/apps/WebhostFileExplorer/api/v1/storage/paths', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        logicalPath: 'System:C/Temp',
        physicalPath: 'C:\\Temp',
        name: 'Temp Directory',
        autoCreateGroups: false,
        permissions: [
            {
                type: 'owner',
                principals: [
                    { principalType: 'role', principalId: 'system_admin' }
                ]
            },
            {
                type: 'read',
                principals: [
                    { principalType: 'role', principalId: 'admin' },
                    { principalType: 'group', principalId: 'developers-group' }
                ]
            },
            {
                type: 'write',
                principals: [
                    { principalType: 'user', principalId: 'admin@example.com' }
                ]
            }
        ]
    })
});
```

**Result**:
- No auto-created groups
- `system_admin` role has owner permission
- `admin` role and `developers-group` have read permission
- `admin@example.com` user has write permission

### Example 3: Update Permissions for Existing Path

**Request**:
```javascript
const response = await fetch('/apps/WebhostFileExplorer/api/v1/storage/paths', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        pathID: 'a1b2c3d4-...',
        permissions: [
            {
                type: 'owner',
                principals: [
                    { principalType: 'role', principalId: 'admin' }
                ]
            },
            {
                type: 'read',
                principals: [
                    { principalType: 'role', principalId: 'authenticated' }
                ]
            }
        ]
    })
});
```

**Result**:
- Replaces all permissions for the path
- Admin role has owner permission
- All authenticated users have read permission

---

## Testing Recommendations

### 1. Storage Path Registration
- Register path with auto-create groups
- Verify groups created in `User_Groups` table
- Verify permissions in `Storage_Path_Permissions` table
- Check FileSharingModal UI shows created groups

### 2. Permission Evaluation
- Register path with specific role/group/user permissions
- Test file access with users having different permissions
- Verify `Path_Resolve.ps1` correctly grants/denies access
- Test permission hierarchy (owner > write > read)

### 3. Permission Updates
- Edit permissions via FileSharingModal
- Verify old permissions deleted, new ones inserted
- Test file access after permission changes

### 4. Storage Path Deactivation
- Deactivate a storage path
- Verify `IsActive = 0` in database
- Verify path no longer appears in FileSharingModal list
- Test that file access now uses default permissions

### 5. UI Integration
- Open FileExplorer
- Double-click file → FileActionModal appears
- Click "Share" → FileSharingModal opens in new card
- Register storage path from modal
- Verify modal updates after registration

### 6. Multi-User Scenarios
- User A registers path with permissions
- User B (admin) should see path in manage tab
- User C (no permission) should NOT see path
- Test role-based access (admin, site_admin, system_admin)
- Test group-based access (add user to group, verify access)

---

## Files Summary

### Database Schema (1 file)
1. `system/db/sqlite/sqliteconfig.json` - Added Storage_Paths and Storage_Path_Permissions tables

### Backend Endpoints (8 files)
2. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/post.ps1` - Register storage path
3. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/post.security.json` - Admin roles only
4. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/get.ps1` - List storage paths
5. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/get.security.json` - All authenticated
6. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/put.ps1` - Update permissions
7. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/put.security.json` - All authenticated
8. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/delete.ps1` - Deactivate path
9. `apps/WebhostFileExplorer/routes/api/v1/storage/paths/delete.security.json` - All authenticated

### Frontend Components (3 files)
10. `apps/WebhostFileExplorer/public/elements/file-sharing-modal/component.js` - React component
11. `apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-sharing-modal/get.ps1` - UI endpoint
12. `apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-sharing-modal/get.security.json` - Admin roles only

### Core System Files (2 files)
13. `system/utility/Path_Resolve.ps1` - Updated with Storage_Path_Permissions check
14. `apps/WebhostFileExplorer/public/elements/file-explorer/component.js` - Integrated onShare handler

**Total**: 14 files (1 modified database schema, 8 new endpoints, 3 new UI files, 2 modified core files)

---

## Performance Considerations

### Query Optimization
- `LogicalPath` has UNIQUE constraint → fast lookups
- `Storage_Path_Permissions` primary key covers all filter columns
- User group query uses indexed `UserID` column
- Role/group checks use `json_each()` for efficient IN queries

### Caching Opportunities (Future)
- Cache user's group memberships (reduce `User_Groups_Map` queries)
- Cache storage path permissions per user (reduce permission queries)
- Invalidate cache on permission updates

### Scalability
- Path resolution adds ~2-3 queries per request
- Falls back gracefully if tables don't exist
- Soft delete prevents orphaned permissions

---

## Known Limitations

1. **No GET /api/v1/groups endpoint**: FileSharingModal currently can't list available groups for selection
2. **No group creation from modal**: Can only use existing groups or auto-create
3. **No permission preview**: Users can't see what access a permission set grants before applying
4. **No audit log**: Permission changes not tracked
5. **No bulk operations**: Can't update multiple paths at once

---

## Future Enhancements

1. **Add GET /api/v1/groups endpoint**: List all groups for selector
2. **Group creation modal**: Allow creating groups from FileSharingModal
3. **Permission preview**: Show effective permissions for test user/role/group
4. **Audit logging**: Track who changes permissions and when
5. **Bulk operations**: Update permissions for multiple paths
6. **Permission templates**: Save/apply common permission sets
7. **Inheritance**: Allow child paths to inherit parent permissions
8. **Time-based permissions**: Expiration dates for temporary access

---

## Integration with Existing Systems

### Compatible with:
- ✅ FileExplorer file operations (uses Path_Resolve.ps1)
- ✅ Text Editor (uses same content endpoints)
- ✅ Hex Editor (uses same content endpoints)
- ✅ File Sharing system (separate File_Shares table)
- ✅ Bucket system (Bucket_Access_Check.ps1 still works)
- ✅ Upload system (path resolution happens before upload)
- ✅ Download system (path resolution happens before download)

### Requires:
- SQLite database with Storage_Paths and Storage_Path_Permissions tables
- db_sqlitequery and db_sqlitenonquery functions
- psweb_fetchWithAuthHandling for authenticated requests
- window.openCard for SPA card system
- React 18 for FileSharingModal

---

**END OF SESSION SUMMARY**
