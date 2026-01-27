# WebSocket Upload Protocol

## Overview

The File Explorer supports **WebSocket-based binary upload** for large files with **automatic fallback to PUT chunks**. This provides the best performance when WebSocket is available while ensuring compatibility with all environments.

## Architecture

### Upload Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         Upload Process                          │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ POST /upload-   │
                    │ chunk?action=   │
                    │ init            │
                    │ Returns: GUID   │
                    └─────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Check WebSocket │
                    │ Support         │
                    └─────────────────┘
                              │
                ┌─────────────┴─────────────┐
                │                           │
                ▼                           ▼
     ┌──────────────────┐        ┌──────────────────┐
     │ WebSocket Upload │        │  PUT Chunk       │
     │ (Try First)      │        │  Upload          │
     └──────────────────┘        │  (Fallback)      │
                │                └──────────────────┘
                │ On Error              │
                └───────────►───────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │ Upload Complete │
                    │ or              │
                    │ POST cancel     │
                    └─────────────────┘
```

### Method Selection

1. **WebSocket** (Primary):
   - Used when `window.WebSocket` is available
   - Single persistent connection for entire upload
   - Bidirectional communication (server push progress)
   - Lower overhead (no HTTP headers per chunk)

2. **PUT Chunks** (Fallback):
   - Used when WebSocket unavailable or fails
   - Multiple HTTP requests (one per chunk)
   - Compatible with all environments
   - Same binary protocol (10-byte header + data)

## WebSocket Protocol Specification

### Connection Establishment

**Client Request (WebSocket Upgrade):**
```http
GET /apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid={guid} HTTP/1.1
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

### Frame Protocol

WebSocket frames alternate between **text** (metadata) and **binary** (chunk data):

#### Frame 1: Chunk Metadata (Text)
```json
{
  "type": "chunk",
  "chunkNumber": 0,
  "bytesRemaining": 78643200
}
```

#### Frame 2: Chunk Data (Binary)
```
[25MB binary chunk data]
```

#### Frame 3: Server Progress Response (Text)
```json
{
  "type": "progress",
  "chunkNumber": 0,
  "receivedChunks": 1,
  "totalChunks": 4,
  "receivedBytes": 26214400,
  "complete": false
}
```

#### Frame 4: Completion Response (Text)
```json
{
  "type": "complete",
  "fileName": "largefile.zip",
  "size": 104857600
}
```

### Message Types

| Type | Direction | Format | Description |
|------|-----------|--------|-------------|
| `chunk` | Client → Server | Text (JSON) | Chunk metadata before binary frame |
| `progress` | Server → Client | Text (JSON) | Progress update after chunk received |
| `complete` | Server → Client | Text (JSON) | Upload completed successfully |
| `error` | Server → Client | Text (JSON) | Server-side error occurred |
| `getProgress` | Client → Server | Text (JSON) | Request current progress |
| Binary | Client → Server | Binary | Raw chunk data (25MB) |

## Frontend Implementation

### WebSocket Upload Function

```javascript
async function uploadViaWebSocket(file, guid, transferId, abortController, chunkSize, totalChunks) {
    return new Promise((resolve, reject) => {
        // Create WebSocket URL
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        const wsUrl = `${protocol}//${window.location.host}/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=${guid}`;

        const ws = new WebSocket(wsUrl);
        ws.binaryType = 'arraybuffer';

        ws.onopen = async () => {
            // Upload all chunks
            for (let i = 0; i < totalChunks; i++) {
                // Check cancellation
                if (abortController.signal.aborted) {
                    throw new Error('Upload cancelled');
                }

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
            const message = JSON.parse(event.data);

            if (message.type === 'progress') {
                // Update UI progress
                updateProgress(message.receivedChunks / message.totalChunks);

                if (message.complete) {
                    ws.close();
                    resolve();
                }
            } else if (message.type === 'error') {
                reject(new Error(message.message));
            }
        };

        ws.onerror = () => reject(new Error('WebSocket connection error'));
    });
}
```

### Fallback Mechanism

```javascript
async function uploadFile(file, targetPath) {
    // Initialize upload
    const { guid } = await initializeUpload(file, targetPath);

    // Try WebSocket first
    if (window.WebSocket) {
        try {
            await uploadViaWebSocket(file, guid, ...);
            console.log('Upload completed via WebSocket');
            return;
        } catch (wsError) {
            console.log('WebSocket failed, falling back to PUT chunks:', wsError);
        }
    }

    // Fallback to PUT chunks
    await uploadViaPutChunks(file, guid, ...);
    console.log('Upload completed via PUT chunks');
}
```

## Backend Implementation

### WebSocket Message Loop (PowerShell)

```powershell
# Check if WebSocket upgrade requested
if ($Context.Request.IsWebSocketRequest) {
    # Accept WebSocket
    $wsContext = $Context.AcceptWebSocketAsync($null).GetAwaiter().GetResult()
    $webSocket = $wsContext.WebSocket

    # 30MB buffer for messages
    $buffer = New-Object byte[] (30 * 1024 * 1024)

    # Track current chunk metadata
    $currentChunkNumber = $null
    $currentBytesRemaining = $null

    # Message loop
    while ($webSocket.State -eq 'Open') {
        # Receive message
        $result = $webSocket.ReceiveAsync(
            [ArraySegment[byte]]::new($buffer),
            [System.Threading.CancellationToken]::None
        ).GetAwaiter().GetResult()

        if ($result.MessageType -eq 'Text') {
            # Parse metadata
            $metadata = $jsonText | ConvertFrom-Json

            if ($metadata.type -eq 'chunk') {
                $currentChunkNumber = [int]$metadata.chunkNumber
                $currentBytesRemaining = [long]$metadata.bytesRemaining
            }
        }
        elseif ($result.MessageType -eq 'Binary') {
            # Extract chunk data
            $chunkData = $buffer[0..($result.Count - 1)]

            # Write chunk using synchronized file I/O
            [System.Threading.Monitor]::Enter($lockObj)
            try {
                $position = [long]$currentChunkNumber * $uploadInfo.ChunkSize

                $fileStream = [System.IO.File]::Open(
                    $uploadInfo.TempFilePath,
                    [System.IO.FileMode]::OpenOrCreate,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::ReadWrite
                )

                try {
                    $fileStream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $fileStream.Write($chunkData, 0, $chunkData.Length)
                    $fileStream.Flush()
                } finally {
                    $fileStream.Close()
                }

                # Update metadata
                $uploadInfo.ChunkBitmap[$currentChunkNumber] = $true
                $uploadInfo.ReceivedChunks++
                $uploadInfo.ReceivedBytes += $chunkData.Length
            } finally {
                [System.Threading.Monitor]::Exit($lockObj)
            }

            # Send progress response
            $progressResponse = @{
                type = 'progress'
                chunkNumber = $currentChunkNumber
                receivedChunks = $uploadInfo.ReceivedChunks
                totalChunks = $uploadInfo.TotalChunks
                receivedBytes = $uploadInfo.ReceivedBytes
                complete = $uploadInfo.ReceivedChunks -eq $uploadInfo.TotalChunks
            } | ConvertTo-Json -Compress

            $progressBytes = [System.Text.Encoding]::UTF8.GetBytes($progressResponse)
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

## Performance Comparison

### WebSocket vs PUT Chunks

| Metric | WebSocket | PUT Chunks |
|--------|-----------|------------|
| **Connections** | 1 persistent connection | 1 connection per chunk (4 for 100MB) |
| **HTTP Headers** | 1 upgrade handshake | 1 set per chunk |
| **Request Overhead** | ~200 bytes (initial) | ~200 bytes × chunks |
| **Progress Updates** | Server push (instant) | Client polling or per-response |
| **Latency** | Lower (no reconnect) | Higher (HTTP overhead) |
| **Browser Support** | 97%+ (IE 10+) | 100% |

### Example: 100MB File Upload

**WebSocket:**
- Initial handshake: 1 request
- Chunk frames: 4 binary frames
- Progress frames: 4 text responses
- **Total overhead:** ~1KB

**PUT Chunks:**
- Chunk requests: 4 PUT requests
- HTTP headers: 4 × ~200 bytes = ~800 bytes
- **Total overhead:** ~1KB

Both methods have similar overhead for this example, but **WebSocket scales better** for larger files with more chunks due to the single persistent connection.

## Error Handling

### Client-Side Errors

| Error | Cause | Handling |
|-------|-------|----------|
| `WebSocket connection error` | Network issue, server unavailable | Fallback to PUT chunks |
| `WebSocket connection closed unexpectedly` | Server crash, timeout | Fallback to PUT chunks |
| `Upload cancelled by user` | User clicked cancel | Close WebSocket, POST cancel |
| `Progress response timeout` | Server overloaded | Retry or fallback |

### Server-Side Errors

| Error | HTTP Code | WebSocket Message |
|-------|-----------|-------------------|
| Upload not found | 404 | `{"type":"error","message":"Upload not found"}` |
| Unauthorized | 403 | `{"type":"error","message":"Unauthorized"}` |
| File write error | 500 | `{"type":"error","message":"File write failed"}` |
| File size mismatch | 500 | `{"type":"error","message":"File size mismatch"}` |

### Automatic Fallback Scenarios

WebSocket upload fails and falls back to PUT chunks when:
1. WebSocket connection fails to establish
2. WebSocket errors during upload
3. Server returns error message via WebSocket
4. WebSocket closes unexpectedly (not cancelled)

**Note:** Cancellation does NOT trigger fallback - the upload is terminated.

## Cancellation

### Client Cancellation Flow

```javascript
// User clicks cancel button
cancelTransfer(transferId);

// AbortController signals cancellation
abortController.abort();

// WebSocket detects abort and closes
if (abortController.signal.aborted) {
    ws.close(1000, 'Upload cancelled');
}

// POST cancel request to server
await fetch('/api/v1/files/upload-chunk', {
    method: 'POST',
    body: JSON.stringify({
        action: 'cancel',
        guid: uploadGuid
    })
});
```

### Server Cleanup

When cancellation is received:
1. Remove temp file: `Remove-Item $uploadInfo.TempFilePath`
2. Remove from hashtables: `$Global:PSWebServer.Uploads.Remove($guid)`
3. Release lock: `$Global:PSWebServer.UploadLocks.Remove($guid)`

## Security

### Authentication

- **WebSocket Upgrade:** Session validated via `Test-WebHostFileExplorerSession`
- **GUID Verification:** Upload ownership checked per message
- **Path Authorization:** `Resolve-WebHostFileExplorerPath` with `write` permission

### Rate Limiting

- **Connection Timeout:** 5 minutes max WebSocket connection
- **Message Size:** 30MB buffer limit (prevents memory exhaustion)
- **Chunk Validation:** Chunk number must be < total chunks

### Attack Prevention

- **Path Traversal:** Prevented by path resolution system
- **Chunk Injection:** GUID ownership verification
- **Concurrent Upload:** Lock mechanism prevents race conditions
- **Memory Exhaustion:** Buffer size limit enforced

## Testing

### Manual Testing

1. **WebSocket Success:**
   ```javascript
   // Upload a large file (>100MB)
   // Check browser console for "WebSocket upload" logs
   // Verify completion message
   ```

2. **WebSocket Fallback:**
   ```javascript
   // Disable WebSocket in browser dev tools (Network tab)
   // Upload a file
   // Verify fallback to PUT chunks in logs
   ```

3. **Cancellation:**
   ```javascript
   // Start upload
   // Click cancel button immediately
   // Verify WebSocket closes
   // Verify POST cancel request sent
   ```

### Automated Testing

See `system/utility/Test-WebSocketUpload.ps1` for PowerShell test scripts.

## Monitoring & Logging

### Client Logging

```javascript
logToServer(`uploadViaWebSocket: WebSocket connection established`);
logToServer(`uploadViaWebSocket: Sending chunk ${i}/${totalChunks}`);
logToServer(`uploadViaWebSocket: Progress update - ${receivedChunks}/${totalChunks} chunks`);
logToServer(`uploadViaWebSocket: Upload complete`);
```

### Server Logging

```powershell
Write-PSWebHostLog -Severity 'Info' -Message "WebSocket upload started" -Data @{
    UserID = $userID
    Guid = $guid
    FileSize = $uploadInfo.FileSize
}

Write-PSWebHostLog -Severity 'Debug' -Message "Chunk received" -Data @{
    ChunkNumber = $chunkNumber
    ChunkSize = $chunkData.Length
}

Write-PSWebHostLog -Severity 'Info' -Message "WebSocket upload completed" -Data @{
    Method = 'WebSocket'
    Duration = (Get-Date) - $uploadInfo.CreatedAt
}
```

## Browser Compatibility

| Browser | WebSocket Support | PUT Support | Notes |
|---------|-------------------|-------------|-------|
| Chrome 16+ | ✅ Yes | ✅ Yes | Full support |
| Firefox 11+ | ✅ Yes | ✅ Yes | Full support |
| Safari 7+ | ✅ Yes | ✅ Yes | Full support |
| Edge (all) | ✅ Yes | ✅ Yes | Full support |
| IE 10+ | ✅ Yes | ✅ Yes | Limited WebSocket |
| IE 9 | ❌ No | ✅ Yes | PUT chunks only |

**Overall Support:** WebSocket = 97%+, PUT = 100%

## Future Enhancements

1. **Parallel WebSocket Streams:**
   - Open multiple WebSocket connections
   - Upload different chunks concurrently
   - Requires server-side coordination

2. **Compression:**
   - Compress chunks before transfer (gzip)
   - Decompress on server
   - Requires `Content-Encoding` negotiation

3. **Resumable Uploads:**
   - Persist chunk bitmap across sessions
   - Allow resume after disconnect
   - Send `getProgress` to resume from last chunk

4. **Checksum Validation:**
   - Calculate SHA256 per chunk (client)
   - Verify on server
   - Reject corrupted chunks

## References

- [RFC 6455: The WebSocket Protocol](https://tools.ietf.org/html/rfc6455)
- [MDN WebSocket API](https://developer.mozilla.org/en-US/docs/Web/API/WebSocket)
- [.NET HttpListener WebSocket Support](https://docs.microsoft.com/en-us/dotnet/api/system.net.httplistener)
- [Binary Upload Protocol](./BINARY_UPLOAD_PROTOCOL.md)
- [Upload Architecture Plan](./UPLOAD_ARCHITECTURE_PLAN.md)
