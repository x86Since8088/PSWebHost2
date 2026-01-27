# Transfer Persistence & Speed Optimization Plan

**Date**: 2026-01-22
**Status**: 🚧 Implementation Plan

---

## Overview

Implement robust transfer persistence with SHA256 verification and optimize upload speeds from current 0.11 MB/s.

---

## Part 1: Transfer Persistence System

### Requirements

1. **Persistent State Storage**
   - Save transfer state to `transfers.json` in user data
   - Location: `PsWebHost_Data/apps/FileExplorer/[UserID]/transfers.json`
   - Update on every chunk completion
   - Load on FileExplorer open

2. **SHA256 Verification**
   - Hash first chunk client-side before upload
   - Send hash to backend for verification against temp file
   - Verify last transmitted chunk on resume
   - Resend chunk if hash mismatch

3. **Resume/Delete UI**
   - Show paused/incomplete transfers on open
   - "Resume" button: Verify hashes and continue
   - "Delete" button: Remove temp file and state

---

### Architecture

#### Frontend State Structure

```javascript
// Transfer state in transfers.json
{
    "transfers": [
        {
            "id": "upload-1234567890-abc123",
            "fileName": "largefile.zip",
            "fileSize": 104857600,
            "uploadGuid": "550e8400-e29b-41d4-a716-446655440000",
            "targetPath": "local|localhost|/uploads",
            "chunkSize": 5242880,  // 5MB
            "totalChunks": 20,
            "completedChunks": 15,
            "firstChunkHash": "a1b2c3d4...",  // SHA256 of first chunk
            "lastChunkHash": "e5f6g7h8...",   // SHA256 of last sent chunk
            "lastChunkNumber": 14,
            "status": "paused",  // 'uploading', 'paused', 'failed', 'completed'
            "startTime": "2026-01-22T12:34:56Z",
            "pausedTime": "2026-01-22T12:40:00Z",
            "bytesTransferred": 78643200,
            "speed": 12.5,  // MB/s at time of pause
            "error": null
        }
    ]
}
```

#### Backend Endpoints

**1. Save Transfer State**
```
POST /apps/WebhostFileExplorer/api/v1/transfers/state
Body: { transferId, state: { ...transferState } }
Response: { success: true }
```

**2. Load Transfer State**
```
GET /apps/WebhostFileExplorer/api/v1/transfers/state
Response: { transfers: [ ...transferStates ] }
```

**3. Delete Transfer**
```
DELETE /apps/WebhostFileExplorer/api/v1/transfers/state?transferId=xxx&deleteTempFile=true
Response: { success: true }
```

**4. Verify Chunk Hash**
```
POST /apps/WebhostFileExplorer/api/v1/transfers/verify
Body: {
    guid: "550e8400-e29b-41d4-a716-446655440000",
    chunkNumber: 0,
    expectedHash: "a1b2c3d4..."
}
Response: {
    valid: true,
    actualHash: "a1b2c3d4...",
    match: true
}
```

---

### Implementation Steps

#### Step 1: Client-Side SHA256 Hashing

**Add to component.js:**
```javascript
/**
 * Calculate SHA256 hash of a Blob/ArrayBuffer
 */
async function calculateSHA256(data) {
    const buffer = data instanceof Blob ? await data.arrayBuffer() : data;
    const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    return hashHex;
}
```

**Usage in uploadViaWebSocket:**
```javascript
// Before sending first chunk
if (chunkIndex === 0) {
    const firstChunkHash = await calculateSHA256(chunk);

    // Verify against backend temp file (if resuming)
    if (uploadGuid && resuming) {
        const verifyResponse = await fetch('/apps/WebhostFileExplorer/api/v1/transfers/verify', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                guid: uploadGuid,
                chunkNumber: 0,
                expectedHash: firstChunkHash
            })
        });

        const verifyResult = await verifyResponse.json();
        if (!verifyResult.match) {
            throw new Error('First chunk hash mismatch - file may have changed');
        }
    }

    // Save hash to transfer state
    transferState.firstChunkHash = firstChunkHash;
}

// After each chunk completion
transferState.lastChunkNumber = chunkIndex;
transferState.lastChunkHash = await calculateSHA256(chunk);
transferState.completedChunks = chunkIndex + 1;
await saveTransferState(transferState);
```

#### Step 2: Backend State Management

**Create: routes/api/v1/transfers/state/post.ps1**
```powershell
# Save transfer state to user data
param([hashtable]$Body)

$userID = $sessiondata.UserID
$transfersDir = "PsWebHost_Data/apps/FileExplorer/$userID"
$transfersFile = Join-Path $transfersDir "transfers.json"

# Ensure directory exists
if (!(Test-Path $transfersDir)) {
    New-Item -ItemType Directory -Path $transfersDir -Force | Out-Null
}

# Load existing transfers
$transfers = @{ transfers = @() }
if (Test-Path $transfersFile) {
    $transfers = Get-Content $transfersFile -Raw | ConvertFrom-Json -AsHashtable
}

# Update or add transfer
$existingIndex = $transfers.transfers.FindIndex({ $_.id -eq $Body.transferId })
if ($existingIndex -ge 0) {
    $transfers.transfers[$existingIndex] = $Body.state
} else {
    $transfers.transfers += $Body.state
}

# Save to file
$transfers | ConvertTo-Json -Depth 10 | Set-Content $transfersFile

context_simpleResponse -Response $Response -Object @{ success = $true }
```

**Create: routes/api/v1/transfers/state/get.ps1**
```powershell
# Load transfer state from user data
$userID = $sessiondata.UserID
$transfersFile = "PsWebHost_Data/apps/FileExplorer/$userID/transfers.json"

$transfers = @{ transfers = @() }
if (Test-Path $transfersFile) {
    $transfers = Get-Content $transfersFile -Raw | ConvertFrom-Json
}

context_simpleResponse -Response $Response -Object $transfers
```

**Create: routes/api/v1/transfers/state/delete.ps1**
```powershell
# Delete transfer state and optionally temp file
param([hashtable]$Query)

$transferId = $Query.transferId
$deleteTempFile = $Query.deleteTempFile -eq 'true'
$userID = $sessiondata.UserID

# Load transfers
$transfersFile = "PsWebHost_Data/apps/FileExplorer/$userID/transfers.json"
$transfers = Get-Content $transfersFile -Raw | ConvertFrom-Json -AsHashtable

# Find transfer
$transfer = $transfers.transfers | Where-Object { $_.id -eq $transferId }

if ($deleteTempFile -and $transfer.uploadGuid) {
    # Delete temp file
    $uploadInfo = $Global:PSWebServer.ActiveUploads[$transfer.uploadGuid]
    if ($uploadInfo -and (Test-Path $uploadInfo.TempFilePath)) {
        Remove-Item $uploadInfo.TempFilePath -Force
    }
    $Global:PSWebServer.ActiveUploads.Remove($transfer.uploadGuid)
}

# Remove from state
$transfers.transfers = @($transfers.transfers | Where-Object { $_.id -ne $transferId })
$transfers | ConvertTo-Json -Depth 10 | Set-Content $transfersFile

context_simpleResponse -Response $Response -Object @{ success = $true }
```

**Create: routes/api/v1/transfers/verify/post.ps1**
```powershell
# Verify chunk hash against temp file
param([hashtable]$Body)

$guid = $Body.guid
$chunkNumber = [int]$Body.chunkNumber
$expectedHash = $Body.expectedHash

# Get upload info
$uploadInfo = $Global:PSWebServer.ActiveUploads[$guid]
if (!$uploadInfo) {
    context_simpleResponse -Response $Response -StatusCode 404 -Object @{
        valid = $false
        error = "Upload not found"
    }
    return
}

# Read chunk from temp file
$chunkSize = $uploadInfo.ChunkSize
$position = [long]$chunkNumber * $chunkSize
$fileStream = [System.IO.File]::OpenRead($uploadInfo.TempFilePath)

try {
    $fileStream.Seek($position, [System.IO.SeekOrigin]::Begin) | Out-Null

    $buffer = New-Object byte[] $chunkSize
    $bytesRead = $fileStream.Read($buffer, 0, $chunkSize)

    # Calculate SHA256
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($buffer, 0, $bytesRead)
    $actualHash = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLower()

    $match = $actualHash -eq $expectedHash

    context_simpleResponse -Response $Response -Object @{
        valid = $true
        actualHash = $actualHash
        match = $match
        bytesRead = $bytesRead
    }
} finally {
    $fileStream.Close()
}
```

#### Step 3: Resume/Delete UI

**Add to TransferItem component:**
```javascript
const TransferItem = ({ transfer, onCancel, onRetry, onRemove, onResume, onDeletePersisted }) => {
    const isPaused = transfer.status === 'paused';

    return (
        <div className="transfer-item">
            <div className="transfer-icon">{getStatusIcon()}</div>
            <div className="transfer-info">
                <div className="transfer-name">{transfer.fileName}</div>
                <div className="transfer-details">
                    {isPaused ? (
                        <>
                            <span className="transfer-paused-text">
                                Paused at {transfer.completedChunks}/{transfer.totalChunks} chunks
                            </span>
                        </>
                    ) : (
                        {/* ... existing progress UI ... */}
                    )}
                </div>
            </div>
            <div className="transfer-actions">
                {isPaused && (
                    <>
                        <button onClick={() => onResume(transfer.id)} title="Resume">▶</button>
                        <button onClick={() => onDeletePersisted(transfer.id)} title="Delete">🗑</button>
                    </>
                )}
                {/* ... existing actions ... */}
            </div>
        </div>
    );
};
```

**Add resume handler:**
```javascript
const handleResumeTransfer = async (transferId) => {
    const transfer = transfers.find(t => t.id === transferId);
    if (!transfer) return;

    // Verify first chunk hash
    try {
        const verifyResponse = await window.psweb_fetchWithAuthHandling(
            '/apps/WebhostFileExplorer/api/v1/transfers/verify',
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    guid: transfer.uploadGuid,
                    chunkNumber: 0,
                    expectedHash: transfer.firstChunkHash
                })
            }
        );

        const verifyResult = await verifyResponse.json();
        if (!verifyResult.match) {
            showToast('File has changed, cannot resume', 'error');
            return;
        }

        // Verify last chunk hash
        const lastVerifyResponse = await window.psweb_fetchWithAuthHandling(
            '/apps/WebhostFileExplorer/api/v1/transfers/verify',
            {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    guid: transfer.uploadGuid,
                    chunkNumber: transfer.lastChunkNumber,
                    expectedHash: transfer.lastChunkHash
                })
            }
        );

        const lastVerifyResult = await lastVerifyResponse.json();
        if (!lastVerifyResult.match) {
            // Resend last chunk
            logToServer(`Last chunk hash mismatch, will resend chunk ${transfer.lastChunkNumber}`);
        }

        // Resume upload from last verified chunk
        // TODO: Implement resume logic in uploadFile function

    } catch (err) {
        showToast(`Resume failed: ${err.message}`, 'error');
    }
};

const handleDeletePersistedTransfer = async (transferId) => {
    if (!confirm('Delete this transfer and remove temp file?')) return;

    try {
        await window.psweb_fetchWithAuthHandling(
            `/apps/WebhostFileExplorer/api/v1/transfers/state?transferId=${transferId}&deleteTempFile=true`,
            { method: 'DELETE' }
        );

        // Remove from UI
        setTransfers(prev => prev.filter(t => t.id !== transferId));
        showToast('Transfer deleted', 'success');
    } catch (err) {
        showToast(`Failed to delete transfer: ${err.message}`, 'error');
    }
};
```

**Load persisted transfers on mount:**
```javascript
useEffect(() => {
    const loadPersistedTransfers = async () => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/transfers/state'
            );

            if (response.ok) {
                const data = await response.json();
                if (data.transfers && data.transfers.length > 0) {
                    // Add paused transfers to state
                    setTransfers(prev => [...data.transfers, ...prev]);
                    logToServer(`Loaded ${data.transfers.length} persisted transfers`);
                }
            }
        } catch (err) {
            logToServer(`Failed to load persisted transfers: ${err.message}`, 'Error');
        }
    };

    loadPersistedTransfers();
}, []);
```

---

## Part 2: Speed Optimization

### Current Performance

**Observed**: 0.11 MB/s (extremely slow)
**Expected**: 10-100+ MB/s depending on connection

### Bottleneck Analysis

#### Potential Causes:

1. **WebSocket Frame Size Limits**
   - Current: 5MB chunks sent as single frames
   - Issue: Large frames may cause buffering delays
   - Solution: Fragment chunks into smaller WebSocket frames

2. **Synchronous Processing**
   - Current: Wait for progress response before sending next chunk
   - Issue: Network round-trip latency between chunks
   - Solution: Pipeline multiple chunks (send while awaiting response)

3. **Async Write Blocking**
   - Current: `WriteAsync().GetAwaiter().GetResult()` still blocks
   - Issue: PowerShell runspace blocked during I/O
   - Solution: True async with fire-and-forget pattern

4. **CPU-Bound SHA256 Hashing**
   - Future: SHA256 calculation blocks UI thread
   - Issue: Hashing large chunks takes time
   - Solution: Use Web Workers for hashing

5. **WebSocket vs HTTP PUT**
   - Current: WebSocket preferred, HTTP PUT fallback
   - Issue: WebSocket has more overhead than raw HTTP
   - Solution: Test both methods, may prefer HTTP PUT

6. **Chunk Size**
   - Current: 5MB chunks
   - Issue: May be suboptimal for WebSocket
   - Solution: Test 1MB, 2MB, 5MB, 10MB chunks

---

### Optimization Strategies

#### Strategy 1: Fragment Large Chunks (Quick Win)

**Problem**: Sending 5MB as single WebSocket frame causes buffering

**Solution**: Fragment into smaller WebSocket frames

```javascript
// Send chunk in 256KB WebSocket frames
const FRAME_SIZE = 256 * 1024; // 256KB

async function sendChunkFragmented(ws, chunkData) {
    const totalSize = chunkData.byteLength;
    let offset = 0;

    while (offset < totalSize) {
        const frameSize = Math.min(FRAME_SIZE, totalSize - offset);
        const frame = chunkData.slice(offset, offset + frameSize);

        // Send frame (don't await - let it queue)
        ws.send(frame);

        offset += frameSize;

        // Yield to event loop every few frames
        if (offset % (FRAME_SIZE * 4) === 0) {
            await new Promise(resolve => setTimeout(resolve, 0));
        }
    }
}
```

**Expected Improvement**: 5-10x faster (0.5-1 MB/s)

---

#### Strategy 2: Pipeline Multiple Chunks

**Problem**: Waiting for response between chunks wastes network bandwidth

**Solution**: Send multiple chunks before waiting for response

```javascript
const MAX_IN_FLIGHT = 3; // Allow 3 chunks in flight

let inFlightCount = 0;
const inFlightPromises = [];

for (let chunkIndex = startChunk; chunkIndex < totalChunks; chunkIndex++) {
    // Wait if too many in flight
    while (inFlightCount >= MAX_IN_FLIGHT) {
        await Promise.race(inFlightPromises);
    }

    // Send chunk asynchronously
    const chunkPromise = sendChunkAsync(chunkIndex).then(() => {
        inFlightCount--;
        const idx = inFlightPromises.indexOf(chunkPromise);
        if (idx >= 0) inFlightPromises.splice(idx, 1);
    });

    inFlightPromises.push(chunkPromise);
    inFlightCount++;
}

// Wait for all to complete
await Promise.all(inFlightPromises);
```

**Expected Improvement**: 2-3x faster with pipelining

---

#### Strategy 3: Use HTTP PUT Instead of WebSocket

**Problem**: WebSocket has framing overhead and connection management

**Solution**: Test HTTP PUT with chunked encoding or parallel requests

```javascript
// Parallel HTTP PUT uploads
const MAX_PARALLEL = 4;

async function uploadViaParallelPut(file, guid, chunkSize) {
    const chunks = [];
    for (let i = 0; i < totalChunks; i++) {
        chunks.push(i);
    }

    // Upload chunks in parallel batches
    for (let i = 0; i < chunks.length; i += MAX_PARALLEL) {
        const batch = chunks.slice(i, i + MAX_PARALLEL);
        await Promise.all(batch.map(chunkIndex => uploadChunk(chunkIndex)));
    }
}

async function uploadChunk(chunkIndex) {
    const start = chunkIndex * chunkSize;
    const end = Math.min(start + chunkSize, file.size);
    const chunk = file.slice(start, end);

    // Create binary data with header
    const header = new Uint32Array([chunkIndex]);
    const chunkData = await chunk.arrayBuffer();
    const combined = new Uint8Array(header.byteLength + chunkData.byteLength);
    combined.set(new Uint8Array(header.buffer), 0);
    combined.set(new Uint8Array(chunkData), header.byteLength);

    await fetch(`/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=${guid}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/octet-stream' },
        body: combined
    });
}
```

**Expected Improvement**: 10-50x faster (1-5 MB/s) with parallel uploads

---

#### Strategy 4: Optimize Backend Write Pattern

**Problem**: Opening/closing file for each chunk is expensive

**Solution**: Keep file handle open in upload session

```powershell
# In upload initialization (POST with action=init)
$fileHandle = [System.IO.File]::Open(
    $tempFilePath,
    [System.IO.FileMode]::Create,
    [System.IO.FileAccess]::Write,
    [System.IO.FileShare]::None  # Exclusive access
)

$uploadInfo.FileHandle = $fileHandle
$Global:PSWebServer.ActiveUploads[$guid] = $uploadInfo

# In chunk handler (GET or PUT)
$fileHandle = $uploadInfo.FileHandle
$fileHandle.Seek($position, [System.IO.SeekOrigin]::Begin)
$writeTask = $fileHandle.WriteAsync($chunkData, 0, $chunkData.Length)
$writeTask.GetAwaiter().GetResult()
# Don't flush on every chunk (expensive)

# In finalization
$fileHandle.Flush()
$fileHandle.Close()
```

**Expected Improvement**: 2-5x faster by reducing I/O overhead

---

#### Strategy 5: Remove Synchronous Waits

**Problem**: `GetAwaiter().GetResult()` blocks the runspace

**Solution**: Use fire-and-forget with completion tracking

```powershell
# Fire-and-forget write
$fileHandle.WriteAsync($chunkData, 0, $chunkData.Length) | Out-Null

# Send progress immediately (don't wait for write)
$progressResponse = @{
    type = 'progress'
    chunkNumber = $currentChunkNumber
    receivedChunks = $uploadInfo.ReceivedChunks
} | ConvertTo-Json

$webSocket.SendAsync($progressBytes, 'Text', $true, [CancellationToken]::None) | Out-Null
```

**Expected Improvement**: Removes blocking, allows overlap of network and I/O

---

#### Strategy 6: Adjust Chunk Size Based on Connection

**Dynamic chunk sizing:**

```javascript
// Start with 1MB chunks
let chunkSize = 1 * 1024 * 1024;

// Measure speed after first few chunks
let sampledSpeed = 0; // MB/s

if (chunkIndex === 3) {
    const elapsed = (Date.now() - startTime) / 1000;
    const bytesTransferred = chunkIndex * chunkSize;
    sampledSpeed = (bytesTransferred / 1024 / 1024) / elapsed;

    // Adjust chunk size based on speed
    if (sampledSpeed > 50) {
        chunkSize = 10 * 1024 * 1024; // 10MB for fast connections
    } else if (sampledSpeed > 10) {
        chunkSize = 5 * 1024 * 1024; // 5MB for medium
    } else {
        chunkSize = 1 * 1024 * 1024; // 1MB for slow
    }
}
```

---

### Recommended Implementation Order

1. **Quick Win: Fragment WebSocket frames** (Strategy 1) - 1 hour
   - Test immediately, should see 5-10x improvement

2. **Medium Win: Keep file handle open** (Strategy 4) - 2 hours
   - Reduce I/O overhead significantly

3. **Big Win: Parallel HTTP PUT** (Strategy 3) - 4 hours
   - May achieve 10-50x improvement
   - Compare with WebSocket performance

4. **Advanced: Pipeline chunks** (Strategy 2) - 3 hours
   - Further optimize whichever method is faster

5. **Polish: Dynamic chunk sizing** (Strategy 6) - 2 hours
   - Adapt to connection speed

---

## Testing Plan

### Test Cases

1. **Small File (< 10 MB)**
   - Test resume after 50% complete
   - Test hash verification
   - Test delete with temp file cleanup

2. **Medium File (100 MB)**
   - Test speed improvement strategies
   - Measure actual MB/s throughput
   - Test resume after network interruption

3. **Large File (1 GB)**
   - Test long-running transfer persistence
   - Test resume after browser close/reopen
   - Test memory usage and stability

4. **Concurrent Uploads**
   - Test 3-5 files uploading simultaneously
   - Measure aggregate throughput
   - Test individual file resume

5. **Hash Verification**
   - Corrupt temp file, verify detection
   - Change source file, verify resume rejection
   - Test last chunk resend on mismatch

---

## Success Metrics

**Transfer Persistence:**
- ✅ transfers.json created and updated
- ✅ Persisted transfers loaded on open
- ✅ Resume continues from last chunk
- ✅ First and last chunk hash verified
- ✅ Delete removes temp file

**Speed Optimization:**
- 🎯 Target: 10+ MB/s (100x improvement from 0.11 MB/s)
- 🎯 Minimum: 1 MB/s (10x improvement)
- 🎯 Stretch: 50+ MB/s on gigabit LAN

---

## Implementation Estimate

**Transfer Persistence**: 8-12 hours
- Frontend SHA256 + state management: 4 hours
- Backend endpoints: 3 hours
- Resume UI and logic: 3 hours
- Testing: 2 hours

**Speed Optimization**: 6-10 hours
- Quick wins (fragmentation, file handle): 3 hours
- HTTP PUT parallel upload: 4 hours
- Testing and tuning: 3 hours

**Total**: 14-22 hours

---

**Next Steps**:
1. Implement Strategy 1 (fragment frames) as quick test
2. Measure actual improvement
3. Proceed with remaining strategies based on results
4. Implement transfer persistence in parallel

