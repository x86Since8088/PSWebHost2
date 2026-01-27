# Binary Upload Protocol

## Overview

The File Explorer uses an efficient binary upload protocol for large file transfers. This replaces the previous base64-encoded chunk system with a more performant binary transfer approach.

## Architecture

### Workflow

1. **Initialize Upload** (POST with JSON)
   - Client sends file metadata
   - Server allocates GUID and creates temp directory
   - Server stores upload metadata in `$Global:PSWebServer.Uploads[guid]`
   - Returns GUID and upload URL

2. **Upload Chunks** (PUT with binary data)
   - Client sends binary chunks with custom header
   - Server validates GUID and ownership
   - Server saves chunks to temp directory
   - Server tracks received chunks for idempotency

3. **Complete Upload** (automatic on last chunk)
   - Server assembles file from chunks
   - Server moves file to target location
   - Server cleans up temp directory
   - Server removes GUID from global hashtable

4. **Cancel Upload** (POST with action=cancel)
   - Client requests cancellation
   - Server cleans up temp directory
   - Server removes GUID from global hashtable

## Protocol Specification

### 1. Initialize Upload

**Endpoint:** `POST /api/v1/files/upload-chunk`

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "action": "init",
  "fileName": "largefile.zip",
  "fileSize": 104857600,
  "chunkSize": 26214400,
  "totalChunks": 4,
  "targetPath": "User:me/Documents"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Upload initialized",
  "data": {
    "guid": "550e8400-e29b-41d4-a716-446655440000",
    "uploadUrl": "/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=550e8400-e29b-41d4-a716-446655440000",
    "fileName": "largefile.zip",
    "fileSize": 104857600,
    "totalChunks": 4
  }
}
```

### 2. Upload Chunk

**Endpoint:** `PUT /api/v1/files/upload-chunk?guid={guid}`

**Request Headers:**
```
Content-Type: application/octet-stream
```

**Request Body Format:**

Binary data with 10-byte header + chunk data:

| Bytes | Type   | Description                    | Endianness    |
|-------|--------|--------------------------------|---------------|
| 0-1   | uint16 | Random value (for validation)  | Little-endian |
| 2-5   | uint32 | Chunk number (0-based)         | Little-endian |
| 6-9   | uint32 | Bytes remaining in transfer    | Little-endian |
| 10+   | bytes  | Actual chunk data              | -             |

**Example Header Construction (JavaScript):**
```javascript
const header = new ArrayBuffer(10);
const headerView = new DataView(header);

// Random uint16 (bytes 0-1)
const randomValue = Math.floor(Math.random() * 65536);
headerView.setUint16(0, randomValue, true); // little-endian

// Chunk number uint32 (bytes 2-5)
headerView.setUint32(2, chunkIndex, true);

// Bytes remaining uint32 (bytes 6-9)
headerView.setUint32(6, bytesRemaining, true);

// Combine header + chunk data
const chunkArrayBuffer = await chunk.arrayBuffer();
const binaryData = new Uint8Array(10 + chunk.size);
binaryData.set(new Uint8Array(header), 0);
binaryData.set(new Uint8Array(chunkArrayBuffer), 10);
```

**Response (200 OK) - More chunks needed:**
```json
{
  "status": "success",
  "message": "Chunk received",
  "data": {
    "chunkNumber": 0,
    "receivedChunks": 1,
    "totalChunks": 4,
    "complete": false,
    "bytesRemaining": 78643200
  }
}
```

**Response (200 OK) - Upload complete:**
```json
{
  "status": "success",
  "message": "Upload completed successfully",
  "data": {
    "fileName": "largefile.zip",
    "size": 104857600,
    "complete": true,
    "receivedChunks": 4,
    "totalChunks": 4
  }
}
```

### 3. Cancel Upload

**Endpoint:** `POST /api/v1/files/upload-chunk`

**Request Headers:**
```
Content-Type: application/json
```

**Request Body:**
```json
{
  "action": "cancel",
  "guid": "550e8400-e29b-41d4-a716-446655440000"
}
```

**Response (200 OK):**
```json
{
  "status": "success",
  "message": "Upload cancelled"
}
```

## Server Implementation

### Global Upload State

Upload metadata is stored in a synchronized hashtable:

```powershell
$Global:PSWebServer.Uploads[guid] = @{
    Guid = $uploadGuid
    UserID = $userID
    FileName = $data.fileName
    FileSize = [long]$data.fileSize
    ChunkSize = [int]$data.chunkSize
    TotalChunks = [int]$data.totalChunks
    TargetPath = $targetResult.PhysicalPath
    TempDirectory = $uploadTempDir
    CreatedAt = Get-Date
    ReceivedChunks = 0
    ChunkMap = @{}  # Track which chunks have been received
}
```

### Binary Header Parsing (PowerShell)

```powershell
# Read binary data from request
$memStream = New-Object System.IO.MemoryStream
$Request.InputStream.CopyTo($memStream)
$chunkData = $memStream.ToArray()
$memStream.Close()

# Parse header (little-endian)
$randomValue = [BitConverter]::ToUInt16($chunkData, 0)
$chunkNumber = [BitConverter]::ToUInt32($chunkData, 2)
$bytesRemaining = [BitConverter]::ToUInt32($chunkData, 6)

# Extract actual chunk data (skip 10 byte header)
$actualChunkData = $chunkData[10..($chunkData.Length - 1)]
```

### Idempotency

The server tracks received chunks in `ChunkMap`. If a chunk is uploaded multiple times (network retry), the server returns success without re-saving the chunk.

```powershell
if ($uploadInfo.ChunkMap.ContainsKey($chunkNumber)) {
    # Return success (idempotent)
    return "Chunk already received"
}
```

### File Assembly

When all chunks are received:

```powershell
$outputStream = [System.IO.File]::OpenWrite($finalFilePath)
try {
    for ($i = 0; $i -lt $uploadInfo.TotalChunks; $i++) {
        $chunkFile = Join-Path $uploadInfo.TempDirectory "chunk_$i"
        $chunkContent = [System.IO.File]::ReadAllBytes($chunkFile)
        $outputStream.Write($chunkContent, 0, $chunkContent.Length)
    }
} finally {
    $outputStream.Close()
}
```

## Client Implementation

### Upload Flow

```javascript
// 1. Initialize upload
const initResponse = await fetch('/api/v1/files/upload-chunk', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        action: 'init',
        fileName: file.name,
        fileSize: file.size,
        chunkSize: 25 * 1024 * 1024, // 25MB
        totalChunks: Math.ceil(file.size / (25 * 1024 * 1024)),
        targetPath: 'User:me'
    })
});
const { guid } = (await initResponse.json()).data;

// 2. Upload chunks
for (let i = 0; i < totalChunks; i++) {
    const chunk = file.slice(i * chunkSize, (i + 1) * chunkSize);
    const bytesRemaining = file.size - ((i + 1) * chunkSize);

    // Create binary header
    const header = new ArrayBuffer(10);
    const view = new DataView(header);
    view.setUint16(0, Math.floor(Math.random() * 65536), true);
    view.setUint32(2, i, true);
    view.setUint32(6, Math.max(0, bytesRemaining), true);

    // Combine header + chunk
    const chunkData = await chunk.arrayBuffer();
    const binary = new Uint8Array(10 + chunk.size);
    binary.set(new Uint8Array(header), 0);
    binary.set(new Uint8Array(chunkData), 10);

    // Upload
    await fetch(`/api/v1/files/upload-chunk?guid=${guid}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: binary
    });
}
```

### Cancellation

```javascript
// Cancel upload
await fetch('/api/v1/files/upload-chunk', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        action: 'cancel',
        guid: uploadGuid
    })
});
```

## Performance Comparison

### Old Protocol (Base64 Chunks)
- Chunk size: 512KB
- Encoding: Base64 (33% size overhead)
- Total requests for 100MB file: ~200 requests
- Effective transfer: ~133MB (due to base64)

### New Protocol (Binary Chunks)
- Chunk size: 25MB
- Encoding: Raw binary (no overhead)
- Total requests for 100MB file: ~5 requests
- Effective transfer: 100MB (actual file size)

**Performance Improvement:**
- 40x fewer HTTP requests
- 25% less data transferred (no base64 overhead)
- Faster upload speeds due to larger chunk sizes

## Security

### Authorization
- All endpoints require `authenticated` role
- GUID ownership is verified on every PUT and cancel request
- User can only access their own uploads

### Validation
- File size limits enforced
- Chunk number validation
- GUID format validation
- Path authorization via `Resolve-WebHostFileExplorerPath`

## Error Handling

### Client-Side
- AbortController for cancellation support
- Automatic retry on network failure (idempotent)
- Cleanup on error (calls cancel endpoint)

### Server-Side
- Temp directory cleanup on error
- GUID removal from global hashtable on error
- Comprehensive error logging with user context

## File Locations

### Backend
- **POST endpoint:** `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/post.ps1`
- **PUT endpoint:** `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1`
- **Security:** `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/*.security.json`

### Frontend
- **Upload function:** `apps/WebhostFileExplorer/public/elements/file-explorer/component.js` (uploadFile)

### Testing
- **Test script:** `system/utility/Test-BinaryUpload.ps1`

## Future Enhancements

Potential improvements:
- Resume capability (track received chunks across sessions)
- Parallel chunk uploads (upload multiple chunks simultaneously)
- Compression support (gzip chunks before transfer)
- Progress streaming (server-sent events for real-time progress)
- Checksum validation (verify chunk integrity)
