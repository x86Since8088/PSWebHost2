# WebHostSSHFileAccess

## Purpose

Provides SSH/SFTP file access for PSWebHost applications.

This app is a **placeholder** for future implementation of SSH/SFTP functionality, enabling:
- Accessing files on remote servers via SSH/SFTP
- Managing SSH credentials and keys
- Browsing remote file systems
- Integration with FileExplorer for seamless remote access
- Support for `.pswebhost/trash_bin` on remote SSH servers

## Integration with Trash Bin System

When FileExplorer deletes files on SSH-accessible remote servers, it uses `.pswebhost/trash_bin` on the remote filesystem. This app would provide:

1. **SSH Key Management**: Store and manage SSH private keys per connection
2. **Connection Management**: Configure and test SSH connections
3. **SFTP Operations**: Read, write, delete files via SFTP protocol
4. **Trash Access**: Access remote trash bins with SSH credentials

## Logical Path Format

FileExplorer would use logical paths to identify SSH-accessible files:

```
ssh|hostname|/path/to/file.txt
ssh|user@hostname:port|/home/user/documents/file.txt
```

## Planned API Endpoints

### Connection Management
- `POST /api/v1/connections` - Add new SSH connection
- `GET /api/v1/connections` - List configured SSH connections
- `DELETE /api/v1/connections/{id}` - Remove connection
- `POST /api/v1/connections/{id}/test` - Test SSH connection

### File Operations (SFTP)
- `GET /api/v1/files` - List files on remote server
- `GET /api/v1/files/download` - Download file via SFTP
- `POST /api/v1/files/upload` - Upload file via SFTP
- `DELETE /api/v1/files` - Delete file (moves to .pswebhost/trash_bin)

### Trash Bin Operations
- `GET /api/v1/trash` - List trash bins on accessible SSH servers
- `POST /api/v1/trash/restore` - Restore file from remote trash
- `DELETE /api/v1/trash` - Empty remote trash bin

### SSH Key Management
- `POST /api/v1/keys` - Add SSH private key
- `GET /api/v1/keys` - List configured keys
- `DELETE /api/v1/keys/{id}` - Remove key
- `POST /api/v1/keys/generate` - Generate new SSH key pair

## Configuration Format

```json
{
  "connections": [
    {
      "id": "conn-guid",
      "name": "Production Server",
      "hostname": "prod.example.com",
      "port": 22,
      "username": "deploy",
      "authMethod": "key",  // "key" or "password"
      "keyId": "key-guid",
      "encryptedPassword": null,
      "allowedUsers": ["user-id-1", "user-id-2"],
      "allowedRoles": ["admin", "developer"]
    }
  ],
  "keys": [
    {
      "id": "key-guid",
      "name": "Deploy Key",
      "publicKey": "ssh-rsa AAAAB3...",
      "encryptedPrivateKey": "...",
      "fingerprint": "SHA256:...",
      "createdBy": "user-id",
      "createdAt": "2026-01-22T12:00:00Z"
    }
  ]
}
```

## Security Considerations

- SSH private keys encrypted at rest
- Per-user or per-role access control
- Audit logging of all remote operations
- No credential/key exposure to frontend
- Support for SSH agent forwarding
- Host key verification (prevent MITM attacks)

## Implementation Status

**Status**: Placeholder - Not Yet Implemented

**Next Steps**:
1. Integrate SSH.NET library or use PowerShell SSH module
2. Implement secure key storage and encryption
3. Create SFTP wrapper for file operations
4. Implement connection pooling and session management
5. Add UI for connection and key management
6. Integrate with FileExplorer for logical path resolution

## Dependencies

- SSH.NET library (Renci.SshNet) or PowerShell OpenSSH module
- .NET cryptography for key encryption
- FileExplorer integration

## Usage Example (Planned)

```powershell
# In FileExplorer backend, when accessing SSH path:
$logicalPath = "ssh|prod.example.com|/var/www/config.json"

# Parse logical path
$connection = Get-WebHostSSHConnection -LogicalPath $logicalPath -UserID $userID

if ($connection) {
    # User has configured connection
    $sftpSession = New-WebHostSSHSession -Connection $connection
    $files = Get-WebHostSSHFiles -Session $sftpSession -Path "/var/www"
    Close-WebHostSSHSession -Session $sftpSession
} else {
    # Prompt user to configure connection
    return "Access denied: No SSH connection configured"
}
```

## Trash Bin Remote Path

When deleting files via SSH:

```powershell
# Original file: ssh|prod.example.com|/var/www/old-config.json
# Trash location: ssh|prod.example.com|/.pswebhost/trash_bin/[userid]/[operation_id]/old-config.json

# Metadata location: ssh|prod.example.com|/.pswebhost/trash_bin/[userid]/[operation_id]/old-config.json.metadata.json
```

## Protocol Support

**Planned Support**:
- SFTP (SSH File Transfer Protocol) - Primary
- SCP (Secure Copy) - Optional
- SSH commands - For trash management

**Not Supported**:
- FTP (use SFTP instead)
- FTPS (use SFTP instead)

## Related Apps

- **FileExplorer**: Primary consumer of SSH file access
- **WebHostSMBClient**: Similar functionality for SMB/CIFS shares
- **Vault**: May store SSH credentials and keys

---

**Created**: 2026-01-22
**Type**: Placeholder
**Priority**: Medium (needed for remote server file management)

## Integration Points

### FileExplorer Integration

```javascript
// Frontend: Detect SSH paths
if (logicalPath.startsWith('ssh|')) {
    // Prompt user to configure connection if needed
    // Show connection selector in file browser
}
```

### Path Resolver Integration

```powershell
# Backend: Resolve SSH paths
function Resolve-WebHostFileExplorerPath {
    param($LogicalPath)

    if ($LogicalPath -match '^ssh\|([^|]+)\|(.+)$') {
        $hostname = $matches[1]
        $remotePath = $matches[2]

        # Get SSH connection for user
        $connection = Get-WebHostSSHConnection -Hostname $hostname -UserID $userID
        # ... use WebHostSSHFileAccess to resolve path
    }
}
```

---

**Documentation Complete**
**Implementation Required**: Full SSH/SFTP client functionality
