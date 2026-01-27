# Upload Architecture Plan: Direct File Writing + WebSocket Support

## Problem Statement

Current implementation creates separate chunk files in temp directory, requiring assembly step. Goals:
1. Write chunks directly to single temp file
2. Support concurrent chunk uploads from different runspaces
3. Add WebSocket support for real-time binary streaming
4. Fallback to PUT chunks if WebSocket unavailable

## Thread Safety Analysis

### PowerShell Runspace Architecture
- **HttpListener** spawns separate runspaces for concurrent requests
- Each request handler runs in its own runspace (thread pool)
- `$Global:PSWebServer` is accessible across runspaces
- File handles are NOT thread-safe across runspaces

### Synchronized Collections
```powershell
# Thread-safe hashtables
$Global:PSWebServer.Uploads = [hashtable]::Synchronized(@{})
$Global:PSWebServer.UploadTempFiles = [hashtable]::Synchronized(@{})
$Global:PSWebServer.UploadLocks = [hashtable]::Synchronized(@{})
```

### File I/O Thread Safety Options

#### Option 1: Lock Object Per Upload (CHOSEN)
```powershell
# Each upload gets a lock object
$lockObj = [PSCustomObject]@{ Lock = $null }
$Global:PSWebServer.UploadLocks[$guid] = $lockObj

# Synchronized write
[System.Threading.Monitor]::Enter($lockObj)
try {
    # Open file, seek, write, close
} finally {
    [System.Threading.Monitor]::Exit($lockObj)
}
```

**Pros:**
- Thread-safe across runspaces
- Simple lock mechanism
- No shared file handles

**Cons:**
- Sequential chunk writes (one at a time per upload)
- Multiple file open/close operations

#### Option 2: Shared FileStream (REJECTED)
```powershell
$stream = [System.IO.File]::Open($path, 'OpenOrCreate', 'Write', 'ReadWrite')
```

**Pros:**
- Single file handle
- Faster (no repeated open/close)

**Cons:**
- FileStream not thread-safe for concurrent Seek+Write
- Handle can't be shared across runspaces reliably
- Complex state management

### Decision: Lock Object + Open/Seek/Write/Close

Each chunk write will:
1. Acquire lock for upload GUID
2. Open FileStream with FileShare.ReadWrite
3. Seek to chunk position (chunk_number * chunk_size)
4. Write chunk data
5. Close FileStream
6. Release lock

## Direct File Writing Architecture

### Data Structures

```powershell
# Upload metadata
$Global:PSWebServer.Uploads[$guid] = @{
    Guid = $guid
    UserID = $userID
    FileName = 'file.zip'
    FileSize = 104857600
    ChunkSize = 26214400
    TotalChunks = 4
    TargetPath = 'C:\path\to\target'
    TempFilePath = 'C:\path\to\newUploadTemp_guid.tmp'  # Direct file path
    CreatedAt = [datetime]
    ReceivedChunks = 0
    ReceivedBytes = 0  # Track total bytes received
    ChunkBitmap = [bool[]]  # Track which chunks received
}

# Temp file paths (separate tracking)
$Global:PSWebServer.UploadTempFiles[$guid] = 'C:\path\to\newUploadTemp_guid.tmp'

# Lock objects for synchronized writes
$Global:PSWebServer.UploadLocks[$guid] = [PSCustomObject]@{ Lock = $null }
```

### Chunk Write Algorithm

```powershell
function Write-UploadChunk {
    param($Guid, $ChunkNumber, $ChunkData)

    $uploadInfo = $Global:PSWebServer.Uploads[$guid]
    $lockObj = $Global:PSWebServer.UploadLocks[$guid]

    # Acquire lock
    [System.Threading.Monitor]::Enter($lockObj)
    try {
        # Calculate write position
        $position = [long]$ChunkNumber * $uploadInfo.ChunkSize

        # Open file with shared read/write access
        $stream = [System.IO.File]::Open(
            $uploadInfo.TempFilePath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::ReadWrite
        )

        try {
            # Seek to position
            $stream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null

            # Write chunk data
            $stream.Write($chunkData, 0, $chunkData.Length)
            $stream.Flush()
        }
        finally {
            $stream.Close()
        }

        # Update metadata
        $uploadInfo.ChunkBitmap[$ChunkNumber] = $true
        $uploadInfo.ReceivedChunks++
        $uploadInfo.ReceivedBytes += $chunkData.Length

    } finally {
        [System.Threading.Monitor]::Exit($lockObj)
    }
}
```

### Completion Detection

```powershell
# Check if all chunks received
$allReceived = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks

if ($allReceived) {
    # Verify file size
    $tempFileInfo = Get-Item $uploadInfo.TempFilePath
    if ($tempFileInfo.Length -ne $uploadInfo.FileSize) {
        throw "File size mismatch: expected $($uploadInfo.FileSize), got $($tempFileInfo.Length)"
    }

    # Move to final location
    $finalPath = Join-Path $uploadInfo.TargetPath $uploadInfo.FileName
    Move-Item -Path $uploadInfo.TempFilePath -Destination $finalPath -Force

    # Cleanup
    $Global:PSWebServer.Uploads.Remove($guid)
    $Global:PSWebServer.UploadLocks.Remove($guid)
}
```

## WebSocket Support

### .NET HttpListener WebSocket Capabilities

**Available since .NET 4.5:**
- `HttpListenerContext.IsWebSocketRequest` - Check if upgrade requested
- `HttpListenerContext.AcceptWebSocketAsync()` - Accept WebSocket connection
- `HttpListenerWebSocketContext` - WebSocket context
- `System.Net.WebSockets.WebSocket` - WebSocket communication

### WebSocket Upgrade Handshake

**Client Request:**
```http
GET /api/v1/files/upload-chunk?guid=xxx HTTP/1.1
Host: localhost:8080
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==
Sec-WebSocket-Version: 13
```

**Server Response:**
```http
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

### WebSocket Binary Protocol

**Frame Format:**
```
Frame 1 (Control): JSON metadata
{
    "type": "chunk",
    "chunkNumber": 0,
    "bytesRemaining": 78643200
}

Frame 2 (Binary): Raw chunk data (25MB)
[binary data...]

Frame 3 (Control): Progress request
{
    "type": "getProgress"
}

Frame 4 (Control): Server response
{
    "type": "progress",
    "receivedChunks": 1,
    "totalChunks": 4,
    "receivedBytes": 26214400,
    "complete": false
}
```

### WebSocket Endpoint Design

**GET /api/v1/files/upload-chunk?guid=xxx**
- Check `IsWebSocketRequest`
- Validate GUID and ownership
- Accept WebSocket connection
- Enter message loop:
  1. Receive control frame (chunk metadata)
  2. Receive binary frame (chunk data)
  3. Write chunk using synchronized write
  4. Send progress response
  5. Repeat until complete

### WebSocket Implementation

```powershell
# In GET endpoint
if ($Context.Request.IsWebSocketRequest) {
    # Validate GUID
    $uploadInfo = $Global:PSWebServer.Uploads[$guid]
    if (-not $uploadInfo) {
        $Context.Response.StatusCode = 404
        return
    }

    # Accept WebSocket
    $wsContext = $Context.AcceptWebSocketAsync($null).GetAwaiter().GetResult()
    $webSocket = $wsContext.WebSocket

    # Message loop
    $buffer = New-Object byte[] (30 * 1024 * 1024) # 30MB buffer

    while ($webSocket.State -eq 'Open') {
        # Receive message
        $result = $webSocket.ReceiveAsync(
            [ArraySegment[byte]]::new($buffer),
            [System.Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()

        if ($result.MessageType -eq 'Text') {
            # Control message (chunk metadata)
            $json = [System.Text.Encoding]::UTF8.GetString($buffer, 0, $result.Count)
            $metadata = $json | ConvertFrom-Json

            # Store for next binary frame
            $chunkNumber = $metadata.chunkNumber
        }
        elseif ($result.MessageType -eq 'Binary') {
            # Binary chunk data
            $chunkData = $buffer[0..($result.Count - 1)]

            # Write chunk using synchronized write
            Write-UploadChunk -Guid $guid -ChunkNumber $chunkNumber -ChunkData $chunkData

            # Send progress
            $progress = @{
                type = 'progress'
                receivedChunks = $uploadInfo.ReceivedChunks
                totalChunks = $uploadInfo.TotalChunks
                complete = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks
            } | ConvertTo-Json

            $progressBytes = [System.Text.Encoding]::UTF8.GetBytes($progress)
            $webSocket.SendAsync(
                [ArraySegment[byte]]::new($progressBytes),
                'Text',
                $true,
                [System.Threading.CancellationToken]::None
            ).GetAwaiter().GetResult()
        }
    }
}
```

### Frontend WebSocket Client

```javascript
async function uploadViaWebSocket(file, guid, uploadUrl) {
    return new Promise((resolve, reject) => {
        // Convert http:// to ws://
        const wsUrl = uploadUrl.replace(/^http/, 'ws');
        const ws = new WebSocket(wsUrl);

        ws.binaryType = 'arraybuffer';

        ws.onopen = async () => {
            // Upload chunks
            for (let i = 0; i < totalChunks; i++) {
                const chunk = file.slice(i * chunkSize, (i + 1) * chunkSize);
                const bytesRemaining = file.size - ((i + 1) * chunkSize);

                // Send metadata frame
                ws.send(JSON.stringify({
                    type: 'chunk',
                    chunkNumber: i,
                    bytesRemaining: Math.max(0, bytesRemaining)
                }));

                // Send binary frame
                const chunkData = await chunk.arrayBuffer();
                ws.send(chunkData);

                // Wait for progress response
                await waitForProgress();
            }
        };

        ws.onmessage = (event) => {
            const progress = JSON.parse(event.data);
            if (progress.complete) {
                ws.close();
                resolve();
            }
        };

        ws.onerror = reject;
    });
}
```

## Fallback Strategy

### Detection Flow

```javascript
async function uploadFile(file, targetPath) {
    // 1. Initialize upload (POST)
    const { guid, uploadUrl } = await initializeUpload(file, targetPath);

    // 2. Try WebSocket
    if (window.WebSocket) {
        try {
            await uploadViaWebSocket(file, guid, uploadUrl);
            return; // Success
        } catch (wsError) {
            console.log('WebSocket failed, falling back to PUT chunks:', wsError);
        }
    }

    // 3. Fallback to PUT chunks
    await uploadViaPutChunks(file, guid, uploadUrl);
}
```

### Browser Support
- **WebSocket**: 97%+ of browsers (IE 10+, all modern browsers)
- **PUT binary**: All browsers
- **Fallback**: Automatic and seamless

## Performance Comparison

| Method | Overhead | Concurrency | Real-time Progress |
|--------|----------|-------------|-------------------|
| PUT chunks | HTTP headers per chunk | Limited by browser | Polling required |
| WebSocket | WS handshake once | Unlimited | Server push |

**WebSocket advantages:**
- Single connection for entire upload
- Bidirectional communication (server can push progress)
- Lower per-chunk overhead (no HTTP headers)
- Can send chunks in parallel (if server supports)

## Implementation Phases

### Phase 1: Direct File Writing (PUT endpoint)
1. ✅ Add `TempFilePath` to upload metadata
2. ✅ Add `UploadLocks` synchronized hashtable
3. ✅ Implement synchronized write function
4. ✅ Update PUT endpoint to write directly
5. ✅ Remove chunk file assembly code
6. ✅ Test concurrent chunk uploads

### Phase 2: WebSocket Support
1. ✅ Create GET endpoint for WebSocket upgrade
2. ✅ Implement WebSocket message loop
3. ✅ Add binary chunk receiver
4. ✅ Add progress sender
5. ✅ Update frontend to try WebSocket first
6. ✅ Implement fallback to PUT
7. ✅ Test WebSocket upload flow

### Phase 3: Testing & Optimization
1. Load test with concurrent uploads
2. Verify thread safety
3. Test WebSocket fallback scenarios
4. Measure performance improvements
5. Add telemetry/metrics

## Security Considerations

### WebSocket Security
- Same authentication as PUT (session validation)
- GUID ownership verification
- Rate limiting per connection
- Connection timeout (5 minutes)
- Max message size enforcement

### File I/O Security
- Validate chunk positions (prevent seeks outside file bounds)
- Verify total bytes written equals expected file size
- Atomic move to final location
- Cleanup on error or timeout

## Monitoring & Logging

```powershell
# Track active uploads
Write-PSWebHostLog -Severity 'Info' -Message "WebSocket upload started" -Data @{
    Guid = $guid
    UserID = $userID
    FileName = $fileName
    FileSize = $fileSize
}

# Track chunk writes
Write-PSWebHostLog -Severity 'Debug' -Message "Chunk written" -Data @{
    Guid = $guid
    ChunkNumber = $chunkNumber
    ChunkSize = $chunkData.Length
    Position = $position
}

# Track completion
Write-PSWebHostLog -Severity 'Info' -Message "Upload completed" -Data @{
    Guid = $guid
    Method = 'WebSocket' # or 'PUT'
    Duration = (Get-Date) - $uploadInfo.CreatedAt
    FinalSize = (Get-Item $finalPath).Length
}
```

## Error Scenarios & Handling

| Scenario | Detection | Handling |
|----------|-----------|----------|
| Client disconnect | WebSocket.State != Open | Cleanup after timeout (5 min) |
| Chunk out of order | ChunkNumber validation | Accept (direct write supports out-of-order) |
| Duplicate chunk | ChunkBitmap check | Idempotent (rewrite same position) |
| File size mismatch | Compare on completion | Reject upload, cleanup temp file |
| Concurrent same chunk | Lock mechanism | Sequential writes (safe) |
| Runspace crash | Orphaned lock | Timeout-based cleanup |

## Files to Create/Modify

### Backend
- ✅ `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1` - Direct write
- ✅ `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1` - WebSocket endpoint
- ✅ `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.security.json` - Auth

### Frontend
- ✅ `apps/WebhostFileExplorer/public/elements/file-explorer/component.js` - WebSocket client + fallback

### Documentation
- ✅ `apps/WebhostFileExplorer/UPLOAD_ARCHITECTURE_PLAN.md` - This document
- ✅ `apps/WebhostFileExplorer/WEBSOCKET_UPLOAD_PROTOCOL.md` - WebSocket spec

### Testing
- ✅ `system/utility/Test-DirectFileWrite.ps1` - Thread safety tests
- ✅ `system/utility/Test-WebSocketUpload.ps1` - WebSocket protocol tests
