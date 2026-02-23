# WebHostSSHFileAccess

## Status: PLACEHOLDER - Not Yet Implemented

**Created**: 2026-01-22
**Type**: Placeholder
**Priority**: Medium (needed for remote server file management)
**Category**: Storage > Remote Access

## Purpose

Provides SSH/SFTP file access for PSWebHost applications with credential and key management.

This app is a **placeholder** for future implementation of SSH/SFTP functionality, enabling:
- Accessing files on remote servers via SSH/SFTP protocol
- Managing SSH credentials and private keys with encryption
- Browsing remote file systems securely
- Integration with FileExplorer for seamless remote access via logical paths
- Support for `.pswebhost/trash_bin` on remote SSH servers
- Host key verification to prevent MITM attacks

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

## File Structure

```
WebHostSSHFileAccess/
├── app.yaml                 # App manifest and configuration
├── app_init.ps1             # Initialization script
├── README.md                # This documentation
├── data/                    # Data storage (git-ignored)
│   ├── connections.json     # SSH connection configurations
│   └── keys.json            # Encrypted SSH keys storage
├── modules/                 # Future: SSH/SFTP wrapper modules
├── routes/api/v1/           # Future: API endpoints
│   ├── connections/         # Connection management
│   ├── files/               # File operations (SFTP)
│   ├── trash/               # Remote trash operations
│   └── keys/                # SSH key management
└── public/elements/         # Future: UI components
```

## Configuration Format

### connections.json
```json
{
  "version": "1.0.0",
  "connections": [
    {
      "id": "conn-guid",
      "name": "Production Server",
      "hostname": "prod.example.com",
      "port": 22,
      "username": "deploy",
      "authMethod": "key",
      "keyId": "key-guid",
      "encryptedPassword": null,
      "allowedUsers": ["user-id-1", "user-id-2"],
      "allowedRoles": ["admin", "developer"],
      "hostKeyFingerprint": "SHA256:...",
      "lastVerified": "2026-01-22T12:00:00Z",
      "createdAt": "2026-01-22T12:00:00Z",
      "createdBy": "user-id"
    }
  ]
}
```

### keys.json
```json
{
  "version": "1.0.0",
  "keys": [
    {
      "id": "key-guid",
      "name": "Deploy Key",
      "publicKey": "ssh-rsa AAAAB3...",
      "encryptedPrivateKey": "...",
      "fingerprint": "SHA256:...",
      "algorithm": "RSA",
      "keySize": 4096,
      "createdBy": "user-id",
      "createdAt": "2026-01-22T12:00:00Z",
      "lastUsed": "2026-01-22T14:30:00Z"
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

## Implementation Roadmap

### Phase 1: Core SSH Infrastructure (4-6 hours)
1. **SSH Library Integration**
   - Evaluate and integrate SSH.NET library (Renci.SshNet)
   - Alternative: PowerShell OpenSSH module
   - Create wrapper module for SFTP operations

2. **Key Storage & Encryption**
   - Implement AES-256-GCM encryption for private keys
   - Create key import/export functions
   - Add key generation functionality (RSA 4096, Ed25519)

3. **Connection Management**
   - Build connection configuration system
   - Implement host key verification
   - Create connection pool with timeout management
   - Add connection testing endpoint

### Phase 2: File Operations (3-4 hours)
4. **SFTP Wrapper**
   - Implement file list/browse operations
   - Add file upload/download functions
   - Create delete operation (move to trash)
   - Handle permissions and metadata

5. **Logical Path Integration**
   - Parse ssh|hostname|/path format
   - Integrate with FileExplorer path resolver
   - Add validation and error handling

### Phase 3: Trash Bin Support (2-3 hours)
6. **Remote Trash Operations**
   - Create `.pswebhost/trash_bin` structure on remote servers
   - Implement metadata write-then-move pattern
   - Add trash listing and restore functions
   - Support cross-user trash access with roles

### Phase 4: UI & Polish (2-3 hours)
7. **Management UI**
   - Connection management interface
   - SSH key upload/generate interface
   - Connection testing and diagnostics
   - Audit log viewer

8. **Security & Testing**
   - Audit logging for all operations
   - Role-based access control validation
   - Integration testing with FileExplorer
   - Security review and penetration testing

**Total Estimated Effort**: 11-16 hours

**Current Status**: Phase 0 - Placeholder Only

## Dependencies

### Required
- .NET Framework 4.8 or .NET Core 3.1+
- .NET cryptography libraries (AES-256-GCM)
- PSWebHost_Support module

### Planned External Libraries
- **Option 1**: SSH.NET library (Renci.SshNet) - Recommended
  - Version: 2020.0.0 or later
  - License: MIT
  - NuGet: Renci.SshNet
- **Option 2**: PowerShell OpenSSH module
  - Built-in on Windows 10/11 and Windows Server 2019+
  - May have limited functionality

### Integration Points
- FileExplorer (path resolver)
- Vault (optional credential storage)
- Audit logging system

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

## Installation

This app is a placeholder and is currently disabled in app.yaml. Once implemented, it will be automatically loaded by PSWebHost.

**Required Roles**: admin, filemanager

---

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

## Testing Checklist

Once implemented, test the following scenarios:

### Connection Management
- [ ] Add new SSH connection with password authentication
- [ ] Add new SSH connection with key authentication
- [ ] Test connection to valid server
- [ ] Test connection to invalid server (proper error handling)
- [ ] Verify host key fingerprint on first connection
- [ ] Reject connection if host key changes (MITM protection)
- [ ] List all configured connections
- [ ] Delete connection
- [ ] Per-user connection access control
- [ ] Per-role connection access control

### Key Management
- [ ] Import existing SSH private key
- [ ] Generate new RSA 4096 key pair
- [ ] Generate new Ed25519 key pair
- [ ] Export public key
- [ ] Encrypt private keys at rest
- [ ] Decrypt private keys for use
- [ ] List all stored keys
- [ ] Delete key (with confirmation)
- [ ] Prevent deletion of keys in use

### File Operations
- [ ] List files on remote server via SFTP
- [ ] Download file from remote server
- [ ] Upload file to remote server
- [ ] Delete file (moves to trash)
- [ ] Handle large files (streaming)
- [ ] Handle permissions errors gracefully
- [ ] Respect FileExplorer logical path format

### Trash Bin Operations
- [ ] Create `.pswebhost/trash_bin` on remote server
- [ ] Write metadata before moving file
- [ ] Move file to remote trash
- [ ] List trash items on remote server
- [ ] Restore file from remote trash
- [ ] Empty remote trash bin
- [ ] Cross-user trash access with proper roles
- [ ] Register remote trash location in FileExplorer

### Security
- [ ] Audit log for all SSH operations
- [ ] Role-based access enforcement
- [ ] Credential encryption verification
- [ ] No credential exposure in API responses
- [ ] Session timeout enforcement
- [ ] Connection pool cleanup

### Integration
- [ ] FileExplorer can resolve ssh|hostname|path
- [ ] FileExplorer can delete files to remote trash
- [ ] FileExplorer can restore files from remote trash
- [ ] Trash bin browser shows remote locations
- [ ] Undo system works with SSH files

---

## Documentation Status

**Documentation**: Complete (placeholder specification)
**Implementation**: Required - Full SSH/SFTP client functionality
**Last Updated**: 2026-02-23
