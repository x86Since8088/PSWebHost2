# WebHostSMBClient

## Purpose

Provides SMB/CIFS network share access for PSWebHost applications.

This app is a **placeholder** for future implementation of SMB client functionality, enabling:
- Accessing files on network shares (\\server\share\path)
- Managing credentials for SMB connections
- Browsing remote file systems
- Integration with FileExplorer trash bin for remote locations

## Integration with Trash Bin System

When FileExplorer deletes files on network shares, it uses `.pswebhost/trash_bin` on the remote share itself. This app would provide:

1. **Credential Management**: Store and retrieve SMB credentials per share
2. **Connection Testing**: Verify access before operations
3. **File Operations**: Read, write, delete files on SMB shares
4. **Trash Access**: Access remote trash bins with appropriate credentials

## Planned API Endpoints

### Connection Management
- `POST /api/v1/connections` - Add new SMB connection with credentials
- `GET /api/v1/connections` - List configured SMB connections
- `DELETE /api/v1/connections/{id}` - Remove connection
- `POST /api/v1/connections/{id}/test` - Test connection

### File Operations
- `GET /api/v1/files` - List files on SMB share
- `GET /api/v1/files/download` - Download file from share
- `POST /api/v1/files/upload` - Upload file to share
- `DELETE /api/v1/files` - Delete file on share (moves to .pswebhost/trash_bin)

### Trash Bin Operations
- `GET /api/v1/trash` - List trash bins on accessible shares
- `POST /api/v1/trash/restore` - Restore file from remote trash
- `DELETE /api/v1/trash` - Empty remote trash bin

## Configuration Format

```json
{
  "connections": [
    {
      "id": "conn-guid",
      "name": "File Server",
      "server": "fileserver.domain.com",
      "share": "documents",
      "credentials": {
        "username": "domain\\user",
        "encryptedPassword": "...",
        "useCurrentUser": false
      },
      "allowedUsers": ["user-id-1", "user-id-2"],
      "allowedRoles": ["admin", "filemanager"]
    }
  ]
}
```

## Security Considerations

- Credentials encrypted at rest
- Per-user or per-role access control
- Audit logging of all file operations
- No credential exposure to frontend
- Integration with Windows Credential Manager (optional)

## Implementation Status

**Status**: Placeholder - Not Yet Implemented

**Next Steps**:
1. Implement credential storage and encryption
2. Create SMB connection wrapper (using .NET classes or PowerShell)
3. Implement file operation endpoints
4. Integrate with FileExplorer for seamless remote file access
5. Add UI for connection management

## Dependencies

- .NET SMB client libraries
- PowerShell New-SmbMapping / Get-SmbConnection cmdlets
- Windows Credential Manager (optional)

## Usage Example (Planned)

```powershell
# In FileExplorer backend, when accessing remote share:
$connection = Get-WebHostSMBConnection -Path "\\server\share\file.txt" -UserID $userID

if ($connection) {
    # User has stored credentials for this share
    $files = Get-WebHostSMBFiles -Connection $connection -Path "/folder"
} else {
    # Prompt user to add connection
    return "Access denied: No credentials for this share"
}
```

## Related Apps

- **FileExplorer**: Primary consumer of SMB access
- **WebHostSSHFileAccess**: Similar functionality for SSH/SFTP access
- **Vault**: May store SMB credentials

---

**Created**: 2026-01-22
**Type**: Placeholder
**Priority**: Medium (needed for full trash bin functionality on network shares)
