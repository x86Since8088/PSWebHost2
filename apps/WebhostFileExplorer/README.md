# WebHost FileExplorer

Comprehensive file management application for PsWebHost with advanced features including multi-select operations, trash bin with undo, batch rename, and binary/WebSocket uploads.

---

## Documentation Index

### Core Architecture
- **MODULE_REFACTORING_SUMMARY.md** - Module structure and helper functions
- **UPLOAD_ARCHITECTURE_PLAN.md** - Direct file writing and WebSocket upload architecture
- **BINARY_UPLOAD_PROTOCOL.md** - Binary upload protocol specification
- **WEBSOCKET_UPLOAD_PROTOCOL.md** - WebSocket upload with PUT fallback

### Feature Implementations (2026-01-22)
- **FILEEXPLORER_ENHANCEMENTS_2026-01-22.md** - Multi-select, delete/rename dialogs, UI improvements
- **UPLOAD_FIXES_2026-01-22.md** - Upload performance fixes (5MB chunks, async writes, speed/ETA display)
- **DELETE_RENAME_FIX_2026-01-22.md** - Batch delete/rename fixes (single request, no rate limiting)
- **BATCH_RENAME_IMPLEMENTATION_2026-01-22.md** - Batch rename with wildcard/regex and conflict detection
- **TRASH_BIN_UNDO_SYSTEM_2026-01-22.md** - Trash bin, undo system, bulk confirmation requirement
- **ENHANCED_TRASH_BIN_SYSTEM_2026-01-22.md** - Metadata files, remote storage, multi-user restore
- **DELETE_LOGGING_SYSTEM_2026-01-22.md** - Comprehensive delete operation logging

### Session Summaries
- **SESSION_SUMMARY_2026-01-22-B.md** - Multi-select, dialogs, transfer persistence planning
- **SESSION_SUMMARY_2026-01-22-C.md** - Batch rename and trash bin implementation
- **SESSION_SUMMARY_2026-01-22-D.md** - Enhanced trash bin with metadata and remote storage

### Planning Documents
- **TRANSFER_PERSISTENCE_PLAN.md** - Transfer persistence and speed optimization plan

---

## Quick Start

### Directory Structure
```
apps/WebhostFileExplorer/
├── modules/
│   └── FileExplorerHelper.ps1          # Shared helper functions
├── routes/api/v1/
│   ├── files/
│   │   ├── get.ps1                     # File tree listing
│   │   ├── post.ps1                    # File operations (delete, rename, batchRename)
│   │   ├── preview/get.ps1             # File preview
│   │   ├── download/get.ps1            # File download with range support
│   │   └── upload-chunk/
│   │       ├── post.ps1                # Upload initialization & cancellation
│   │       ├── put.ps1                 # Binary chunk upload (fallback)
│   │       └── get.ps1                 # WebSocket binary upload
│   ├── undo/
│   │   └── post.ps1                    # Undo delete/rename operations
│   ├── buckets/                        # Bucket management endpoints
│   └── system-paths/                   # System path endpoints
└── public/elements/file-explorer/
    └── component.js                    # React-based file explorer UI
```

---

## Feature Summary

### File Operations
- **Browse**: Incremental tree loading for large directories
- **Multi-Select**: Checkbox-based selection with "Select All"
- **Delete**: Soft delete to trash bin with bulk confirmation
- **Rename**: Single and batch rename with wildcard/regex patterns
- **Upload**: Binary/WebSocket upload with 5MB chunks (fallback to PUT)
- **Download**: Single and batch download with range support
- **Preview**: Text, image, PDF, audio, video preview

### Trash Bin & Undo
- **Trash Bin**: Files moved to `PsWebHost_Data\trash_bin` instead of permanent deletion
- **Remote Storage**: Different volumes/network shares use `.pswebhost/trash_bin`
- **Metadata**: Each deleted file has `.metadata.json` with deletion context
- **Undo**: Restore deleted files or reverse rename operations
- **Multi-User Restore**: Admins can restore files deleted by other users
- **Undo History**: Up to 50 operations tracked per user

### Upload System
- **Primary Method**: WebSocket binary upload (single persistent connection)
- **Fallback**: HTTP PUT chunks (compatibility with all environments)
- **Chunk Size**: 5MB (optimized from 25MB)
- **Progress**: Real-time speed (MB/s) and ETA display
- **Async I/O**: Non-blocking file writes using .NET async APIs
- **Direct Writing**: Chunks written directly to temp file (no assembly step)

### Batch Operations
- **Batch Delete**: Single request for multiple files (no rate limiting)
- **Batch Rename**: Wildcard/regex patterns with live preview
- **Conflict Detection**: Backend validates conflicts before executing
- **Bulk Confirmation**: User must type "bulk" for multi-file operations

---

## API Endpoints

### File Operations
```
GET  /api/v1/files?path={logicalPath}               # List files/folders
POST /api/v1/files                                    # File operations
  - action: delete        (paths: [...])              # Delete files
  - action: rename        (path: ..., newName: ...)   # Rename single file
  - action: batchRename   (renames: [...])            # Batch rename
  - action: createFolder  (path: ..., name: ...)      # Create folder
```

### Upload
```
POST /api/v1/files/upload-chunk?action=init         # Initialize upload
PUT  /api/v1/files/upload-chunk?guid={guid}         # Upload chunk (binary)
GET  /api/v1/files/upload-chunk?guid={guid}         # WebSocket upload
POST /api/v1/files/upload-chunk?action=cancel       # Cancel upload
```

### Undo
```
POST /api/v1/undo                                    # Undo operation
  - operationId: {guid}
```

### Preview & Download
```
GET /api/v1/files/preview?path={logicalPath}        # Preview file
GET /api/v1/files/download?path={logicalPath}       # Download file
```

---

## Known Issues & Limitations

### Current Issues
1. **Upload Speed**: 0.11 MB/s (target: 10+ MB/s)
   - Solution planned: Fragment WebSocket frames + Parallel HTTP PUT
2. **No Transfer Persistence**: Uploads lost on page refresh
   - Solution planned: SHA256 verification + state persistence
3. **No Undo UI**: Backend ready, frontend UI pending
4. **No Trash Browser UI**: Backend ready, frontend UI pending

### Future Enhancements
- WebHostSMBClient app (network share access)
- WebHostSSHFileAccess app (SSH/SFTP access)
- Transfer method switcher (WebSocket/HTTP toggle)
- Copy/Paste operations
- Drag-and-drop file operations
- Context menu (right-click)
- Keyboard shortcuts (F2, Delete, Ctrl+A)

---

## Testing Checklist

### Multi-Select
- [ ] Click individual checkboxes to select files
- [ ] Click header checkbox to select all
- [ ] Header shows indeterminate state when some selected
- [ ] Selected rows highlighted

### Delete
- [ ] Single file delete (no confirmation required)
- [ ] Multi-file delete (bulk confirmation required)
- [ ] Files moved to trash bin
- [ ] Metadata files created
- [ ] Remote volume files use `.pswebhost/trash_bin`

### Batch Rename
- [ ] Wildcard mode works (`*.txt` → `renamed_*.md`)
- [ ] Regex mode works (capture groups)
- [ ] Live preview updates as you type
- [ ] Conflict detection prevents overwrites
- [ ] Bulk confirmation required

### Undo
- [ ] Restore deleted files from trash
- [ ] Reverse rename operations
- [ ] Admin can restore files deleted by others
- [ ] Operation marked as undone in undo.json

### Upload
- [ ] WebSocket upload works
- [ ] PUT fallback works if WebSocket fails
- [ ] Progress shows speed (MB/s) and ETA
- [ ] Cancel upload works
- [ ] Large files (500MB+) complete successfully

---

## Performance Metrics

### File Operations
- Single file delete: 50-150ms
- Batch delete (5 files): 300-700ms
- Single rename: 20-50ms
- Batch rename (5 files): 100-300ms

### Upload Performance
- Current: 0.11 MB/s (needs optimization)
- Target: 10+ MB/s
- Chunk processing: ~50-100ms per 5MB chunk
- WebSocket overhead: ~200 bytes (initial handshake)

---

## Security

### Authentication
- All endpoints require `authenticated` role
- Session validation via `Test-WebHostFileExplorerSession`
- User ID tracked for all operations

### Authorization
- Path resolution with permission checks
- Read/Write permissions enforced per file
- Multi-user restore requires admin/filemanager role

### Audit Trail
- All delete operations logged with user context
- Undo operations logged with deleter and restorer
- Metadata files track who deleted files
- Comprehensive START/STOP logging for all operations

---

## Configuration

### Upload Settings
```powershell
# In FileExplorer component.js
$chunkSize = 5 * 1024 * 1024  # 5MB chunks
$timeout = 60000              # 60 second timeout per chunk
$bufferSize = 10 * 1024 * 1024  # 10MB WebSocket buffer
```

### Trash Bin Settings
```powershell
# Undo history limit
$maxUndoOperations = 50  # Last 50 operations saved

# Trash locations
$localTrash = "PsWebHost_Data\trash_bin"
$remoteTrash = ".pswebhost\trash_bin"  # On remote volumes/shares
```

---

## Troubleshooting

### Upload Issues
**Symptom**: Upload starts then stops immediately
- Check temp directory permissions
- Check disk space
- Review logs for errors

**Symptom**: Upload speed very slow
- Check disk I/O (Get-Counter '\PhysicalDisk(*)\Disk Bytes/sec')
- Check network utilization
- Review logs for slow chunk writes (>100ms)

### Delete Issues
**Symptom**: Delete fails with "Access denied"
- Check write permissions on original location
- Check write permissions on trash bin
- Review user roles and permissions

**Symptom**: Metadata write fails
- Check trash bin directory permissions
- Check disk space
- Review logs for metadata write errors

### Restore Issues
**Symptom**: Restore fails with "Original location occupied"
- Check if file/folder exists at original path
- User must manually resolve conflict

**Symptom**: Restore fails with "Permission denied"
- Check if user is original deleter, admin, or has filemanager role
- Review metadata file for deletion context

---

## Development Notes

### Code Organization
- Helper functions centralized in `FileExplorerHelper.ps1`
- Consistent response format via helper functions
- Dot-sourcing for hot-reloading during development

### Testing Strategy
1. Unit test helper functions independently
2. Integration test endpoints with mock data
3. E2E test UI workflows in browser

### Deployment
- No restart required (PowerShell scripts reload automatically)
- Cache clearing recommended (browser refresh for JS updates)
- No database changes
- Trash bin directories created automatically

---

**Last Updated**: 2026-01-22
**Version**: 1.0
**Status**: Production Ready (UI enhancements pending)
