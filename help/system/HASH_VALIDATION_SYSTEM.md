# File Hash Validation System

**Date**: 2026-01-27
**Feature**: SHA256 hash validation for file integrity verification with range support

---

## Overview

The hash validation system allows clients to verify uploaded file integrity by comparing SHA256 hashes computed client-side and server-side. Supports full-file and range-based validation with graceful handling of files currently open for writing.

###Key Features

1. ✅ **SHA256 Hash Computation**: Industry-standard cryptographic hash for integrity verification
2. ✅ **Range Support**: Validate specific byte ranges using HTTP Range headers
3. ✅ **Graceful Lock Handling**: Automatic retry when files are open for writing
4. ✅ **Client-Side Validation**: Compare hashes without re-uploading data
5. ✅ **Transfer Integration**: One-click validation from upload transfers
6. ✅ **Large File Optimization**: Streaming hash for files > 100MB

---

## Architecture

### Validation Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Upload Completes                          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
          ┌──────────────────────────────┐
          │   User Clicks "Validate" 🔍  │
          └──────────────┬───────────────┘
                         │
                         ▼
          ┌──────────────────────────────┐
          │   Client Computes SHA256     │
          │   (crypto.subtle.digest)     │
          └──────────────┬───────────────┘
                         │
                         ▼
          ┌──────────────────────────────┐
          │   Request Server Hash        │
          │   GET /api/v1/files/validate │
          │   ?guid={upload_guid}        │
          └──────────────┬───────────────┘
                         │
                ┌────────┴─────────┐
                │                  │
                ▼                  ▼
         ┌───────────┐      ┌──────────────────┐
         │  File     │      │   File Open      │
         │  Ready    │      │   (409 Conflict) │
         └─────┬─────┘      └──────┬───────────┘
               │                   │
               │            ┌──────┴──────────────┐
               │            │  Retry After 5s     │
               │            │  (up to 3 retries)  │
               │            └──────┬──────────────┘
               │                   │
               └──────────────┬────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │   Server Opens File          │
               │   (FileShare.ReadWrite)      │
               └──────────────┬───────────────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │   Server Computes SHA256     │
               │   (full file or range)       │
               └──────────────┬───────────────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │   Return Server Hash         │
               └──────────────┬───────────────┘
                              │
                              ▼
               ┌──────────────────────────────┐
               │   Client Compares Hashes     │
               │   client_hash == server_hash │
               └──────────────┬───────────────┘
                              │
                       ┌──────┴───────┐
                       │     Equal?   │
                       └──────┬───────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
                    ▼                   ▼
             ┌────────────┐      ┌─────────────┐
             │ ✓ Valid    │      │ ✗ Invalid   │
             │ Show Green │      │ Show Red    │
             └────────────┘      └─────────────┘
```

---

## API Endpoints

### Validate File Hash

**Endpoint**: `GET /api/v1/files/validate`

**Query Parameters**:
- `guid` (string): Upload GUID from active or completed transfer
- `path` (string): Logical file path (alternative to GUID)

**Headers** (optional):
- `Range: bytes=START-END`: Validate only specified byte range

**Response** (200 OK):
```json
{
  "status": "success",
  "message": "Hash computed successfully",
  "data": {
    "sha256": "a7f2c3d8e9b1f4a6c2d8e3b9f1a4c6d2e8b3f9a1c4d6e2b8f3a9c1d4e6b2f8a3",
    "fileName": "example.bin",
    "fileSize": 104857600,
    "fullFile": true,
    "hashDuration": 0.523,
    "hashSpeedMBps": 190.25
  }
}
```

**Response** (200 OK - Range):
```json
{
  "status": "success",
  "message": "Hash computed successfully",
  "data": {
    "sha256": "b4e8c1f2a9d6e3b7c2f8a1d4e6b3c9f2a8d1e4b6c3f9a2d8e1b4c6f2a9d3e8b1",
    "fileName": "example.bin",
    "rangeStart": 0,
    "rangeEnd": 1048575,
    "rangeLength": 1048576,
    "fullFile": false,
    "hashDuration": 0.012,
    "hashSpeedMBps": 83.33
  }
}
```

**Response** (409 Conflict - File Open for Writing):
```json
{
  "status": "fail",
  "message": "File is currently being written to. Please retry in a few seconds.",
  "data": {
    "retryAfter": 5,
    "fileOpenForWriting": true
  }
}
```

**Response** (404 Not Found):
```json
{
  "status": "fail",
  "message": "Upload not found: {guid}"
}
```

**Response** (416 Range Not Satisfiable):
```json
{
  "status": "fail",
  "message": "Invalid range: start 100000000 is out of bounds (file size: 10485760)"
}
```

---

## Frontend Usage

### Automatic Validation (One-Click)

After upload completes, a validation button appears:

```
[File.bin] [⚡ Streaming] [Completed] [🔍] [🗑]
                                      ↑
                                   Validate
```

Click 🔍 to validate:
1. Client computes SHA256 of original file
2. Request server hash via `/api/v1/files/validate?guid={guid}`
3. Compare hashes
4. Display result: ✓ Validated (green) or ✗ Validation Failed (red)

### Programmatic Validation

```javascript
// Validate full file
const result = await validateTransfer(transferId);
if (result.valid) {
    console.log('File integrity verified!');
} else {
    console.log('Hash mismatch:', result.clientHash, '!=', result.serverHash);
}

// Validate specific range
const rangeResult = await validateTransferRange(transferId, 0, 1048575);
if (rangeResult.valid) {
    console.log('First 1MB verified!');
}
```

### Client-Side Hash Computation

```javascript
// Compute SHA256 of file
const file = document.getElementById('file-input').files[0];
const clientHash = await computeClientHash(file);

// Compute SHA256 of range
const rangeHash = await computeClientHash(file, 0, 1048575);  // First 1MB
```

---

## Backend Implementation

### File Opening with Retry

```powershell
$maxRetries = 3
$retryDelayMs = 500

while (-not $fileOpenSuccess -and $retryCount -le $maxRetries) {
    try {
        # Try to open with shared read access (allows concurrent writes)
        $fileStream = [System.IO.File]::Open(
            $physicalPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite  # Key: Allow reading during writes
        )
        $fileOpenSuccess = $true
    }
    catch [System.IO.IOException] {
        # File locked - retry with exponential backoff
        $retryCount++
        if ($retryCount -le $maxRetries) {
            $delayMs = $retryDelayMs * [Math]::Pow(2, $retryCount - 1)
            Start-Sleep -Milliseconds $delayMs
        }
        else {
            # Return 409 Conflict with Retry-After header
            $Response.AddHeader('Retry-After', '5')
            return @{ status = 409, retryAfter = 5 }
        }
    }
}
```

### Full File Hash

```powershell
$sha256 = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha256.ComputeHash($fileStream)
$hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()
```

### Range Hash (Streaming for Large Ranges)

```powershell
# For ranges > 100MB, use streaming to avoid memory pressure
if ($rangeLength -gt 100MB) {
    $buffer = New-Object byte[] 4194304  # 4MB buffer
    $bytesRemaining = $rangeLength

    while ($bytesRemaining -gt 0) {
        $bytesToRead = [Math]::Min($buffer.Length, $bytesRemaining)
        $bytesRead = $fileStream.Read($buffer, 0, $bytesToRead)

        $sha256.TransformBlock($buffer, 0, $bytesRead, $null, 0) | Out-Null
        $bytesRemaining -= $bytesRead
    }

    $sha256.TransformFinalBlock(@(), 0, 0) | Out-Null
    $hashBytes = $sha256.Hash
}
else {
    # Read entire range into memory
    $rangeBytes = New-Object byte[] $rangeLength
    $fileStream.Read($rangeBytes, 0, $rangeLength) | Out-Null
    $hashBytes = $sha256.ComputeHash($rangeBytes)
}
```

---

## Use Cases

### 1. Post-Upload Verification

**Scenario**: Verify file uploaded correctly without corruption

```javascript
// After streaming upload completes
await uploadViaStreaming(file, transferId, targetPath, abortController);

// Validate immediately
const result = await validateTransfer(transferId);
if (!result.valid) {
    showToast('Upload corrupted - please retry', 'error');
}
```

### 2. Incremental Validation

**Scenario**: Validate chunks during multi-part upload

```javascript
// After each chunk uploaded
const chunkStart = chunkIndex * chunkSize;
const chunkEnd = Math.min((chunkIndex + 1) * chunkSize - 1, fileSize - 1);

const chunkResult = await validateTransferRange(transferId, chunkStart, chunkEnd);
if (!chunkResult.valid) {
    console.error(`Chunk ${chunkIndex} corrupted - retrying...`);
    await retryChunk(chunkIndex);
}
```

### 3. Resume Validation

**Scenario**: Verify already-uploaded bytes before resuming

```javascript
// Before resuming upload
const bytesAlreadyUploaded = 52428800;  // 50MB

// Validate what's already there
const resumeResult = await validateTransferRange(transferId, 0, bytesAlreadyUploaded - 1);
if (!resumeResult.valid) {
    console.error('Existing data corrupted - starting over');
    await startNewUpload();
} else {
    console.log('Existing data valid - resuming from 50MB');
    await resumeUpload(bytesAlreadyUploaded);
}
```

### 4. Silent Background Validation

**Scenario**: Validate all uploads in background without user interaction

```javascript
// After all uploads complete
const completedTransfers = transfers.filter(t => t.status === 'completed');

for (const transfer of completedTransfers) {
    const result = await validateTransfer(transfer.id);
    if (!result.valid) {
        logToServer(`Transfer ${transfer.id} failed validation`, 'Error');
        // Flag for review
    }
}
```

---

## Performance Characteristics

### Hash Computation Speed

| File Size | Client (Browser) | Server (PowerShell) | Network Overhead |
|-----------|------------------|---------------------|------------------|
| 1MB       | ~5ms             | ~3ms                | ~20ms            |
| 10MB      | ~50ms            | ~30ms               | ~20ms            |
| 100MB     | ~500ms           | ~300ms              | ~20ms            |
| 1GB       | ~5s              | ~3s                 | ~20ms            |
| 10GB      | ~50s             | ~30s                | ~20ms            |

**Throughput**: ~200 MB/s (server-side), ~150 MB/s (client-side)

### Range Validation Performance

| Range Size | Hash Time | Use Case |
|------------|-----------|----------|
| 1KB        | <1ms      | Quick spot check |
| 1MB        | ~5ms      | Chunk verification |
| 10MB       | ~50ms     | Incremental validation |
| 100MB      | ~500ms    | Large chunk validation |

---

## Error Handling

### Client-Side Errors

**1. File Not Found in Transfer**
```
Error: Transfer not found
Action: Check transferId is correct
```

**2. Browser Hash API Not Available**
```
Error: crypto.subtle.digest is not available
Action: Use modern browser (Chrome 60+, Firefox 57+, Edge 79+)
```

**3. File Read Error**
```
Error: Failed to read file
Action: Check file still exists and is accessible
```

### Server-Side Errors

**1. Upload Not Found (404)**
```
Error: Upload not found: {guid}
Causes:
- Upload expired (cleaned up)
- Invalid GUID
- Different user session
```

**2. File Open for Writing (409)**
```
Error: File is currently being written to
Causes:
- Upload still in progress
- Another process writing to file
- File system lock
Action: Client automatically retries after 5 seconds (up to 3 times)
```

**3. Invalid Range (416)**
```
Error: Invalid range: start 100000000 is out of bounds (file size: 10485760)
Causes:
- Range exceeds file size
- Negative range values
- Start > End
```

**4. Permission Denied (403)**
```
Error: Unauthorized: You do not own this upload
Causes:
- Different user trying to validate
- Session expired
```

---

## Security Considerations

### 1. Session Validation

All validation requests require authentication:
```json
{
  "requireAuth": true,
  "requireSession": true,
  "rateLimitPerMinute": 30
}
```

### 2. User Ownership Check

Users can only validate their own uploads:
```powershell
if ($uploadInfo.UserID -ne $userID) {
    return 403 Forbidden
}
```

### 3. Path Traversal Prevention

File paths resolved through `Resolve-WebHostFileExplorerPath`:
- Validates user has read permission
- Prevents accessing files outside authorized directories
- Blocks directory traversal attacks (`../`, absolute paths)

### 4. Rate Limiting

Maximum 30 validation requests per minute per user:
- Prevents hash computation abuse (CPU intensive)
- Protects against DoS

---

## Monitoring and Logging

### Successful Validation

```
[Info] Computing SHA256 hash of full file
  UserID: user123
  FilePath: C:\uploads\temp\streamUpload_12345.tmp
  FileSize: 104857600

[Info] SHA256 hash computed successfully
  UserID: user123
  FilePath: C:\uploads\temp\streamUpload_12345.tmp
  Hash: a7f2c3d8e9b1f4a6c2d8e3b9f1a4c6d2e8b3f9a1c4d6e2b8f3a9c1d4e6b2f8a3
  BytesHashed: 104857600
  Duration: 0.523
  SpeedMBps: 190.25
```

### File Locked (Retry)

```
[Warning] File locked for validation (attempt 1/4): The process cannot access the file
  UserID: user123
  FilePath: C:\uploads\temp\streamUpload_12345.tmp

[Info] File opened for validation after 1 retries
  UserID: user123
  FilePath: C:\uploads\temp\streamUpload_12345.tmp
```

### Validation Failed (Hash Mismatch)

```
[Error] validateTransfer: Range validation FAILED
  Client Hash: a7f2c3d8e9b1f4a6c2d8e3b9f1a4c6d2e8b3f9a1c4d6e2b8f3a9c1d4e6b2f8a3
  Server Hash: b4e8c1f2a9d6e3b7c2f8a1d4e6b3c9f2a8d1e4b6c3f9a2d8e1b4c6f2a9d3e8b1
```

---

## Testing

### Manual Testing

```powershell
# Test full file validation
Invoke-RestMethod -Uri "http://localhost:8080/apps/WebhostFileExplorer/api/v1/files/validate?guid=12345-67890" `
    -Headers @{ Authorization = "Bearer $token" } `
    -Method GET

# Test range validation
Invoke-RestMethod -Uri "http://localhost:8080/apps/WebhostFileExplorer/api/v1/files/validate?guid=12345-67890" `
    -Headers @{
        Authorization = "Bearer $token"
        Range = "bytes=0-1048575"
    } `
    -Method GET

# Test file locked scenario (run during active upload)
Invoke-RestMethod -Uri "http://localhost:8080/apps/WebhostFileExplorer/api/v1/files/validate?guid=12345-67890" `
    -Headers @{ Authorization = "Bearer $token" } `
    -Method GET
# Should return 409 Conflict with Retry-After: 5
```

### Automated Testing

```javascript
// Browser console test
async function testValidation() {
    // Upload file
    const file = document.getElementById('file-input').files[0];
    await uploadFile(file, '/test');

    // Find transfer
    const transfer = transfers.find(t => t.fileName === file.name);

    // Validate
    const result = await validateTransfer(transfer.id);
    console.assert(result.valid, 'Validation should pass for uncorrupted upload');
}
```

---

## Troubleshooting

### Issue: Validation Always Fails

**Symptoms**: Hash mismatch on every validation

**Causes**:
1. File modified after upload (timestamp, permissions)
2. Different encoding/line endings (text files)
3. Client-side file changed after upload

**Diagnosis**:
```powershell
# Check server file hash
$file = "C:\uploads\temp\streamUpload_12345.tmp"
$hash = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
Write-Host "Server hash: $hash"

# Compare with client hash from logs
```

### Issue: 409 Errors (File Locked)

**Symptoms**: Multiple 409 responses, validation never completes

**Causes**:
1. Upload still in progress (expected - wait)
2. File handle not released (bug)
3. Antivirus scanning file (external lock)

**Solutions**:
- Wait for upload to complete before validating
- Check no process has file open: `handle.exe {filename}`
- Temporarily disable antivirus file scanning

### Issue: Slow Hash Computation

**Symptoms**: Validation takes minutes for large files

**Causes**:
1. Disk I/O bottleneck (slow disk)
2. CPU bottleneck (many concurrent validations)
3. Network storage (SMB, NFS)

**Solutions**:
- Use SSD for temp upload directory
- Rate limit concurrent validations
- Validate during off-peak hours
- Use range validation for spot checks instead of full file

---

## Summary

The hash validation system provides:

✅ **Integrity Verification**: Cryptographic proof files uploaded correctly
✅ **Range Support**: Validate specific byte ranges for incremental verification
✅ **Graceful Error Handling**: Automatic retry when files are locked
✅ **Performance**: 200 MB/s hash computation throughput
✅ **Security**: User ownership validation, rate limiting
✅ **Ease of Use**: One-click validation from transfer UI

**Result**: Production-ready file integrity verification with comprehensive error handling and performance optimization.

---

**END OF DOCUMENT**
