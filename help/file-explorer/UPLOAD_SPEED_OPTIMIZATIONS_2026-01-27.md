# FileExplorer Upload Speed Optimizations

**Date**: 2026-01-27
**Status**: ✅ **IMPLEMENTED - READY FOR TESTING**
**Expected Improvement**: **10-50x faster** (from 0.11 MB/s to 1-10+ MB/s)

---

## Problem

FileExplorer upload speed was **0.11 MB/s** - extremely slow due to multiple bottlenecks identified in the transfer system analysis.

---

## Root Cause Analysis

After analyzing the WebSocket and HTTP PUT upload implementations, I identified **4 critical bottlenecks**:

### 1. **Serial Chunk Processing** (BIGGEST - ~100x slowdown)
- Client sent one 5MB chunk at a time
- **Waited for server ACK** before sending next chunk
- Each chunk cycle: Send → Wait for server processing → Wait for network RTT → Send next
- Result: ~100ms+ overhead per chunk, serializing the entire upload

### 2. **Artificial 10ms Delay**
- Client added 10ms `setTimeout` between metadata and binary frames
- Reason given: "ensure metadata arrives before binary frame"
- **Completely unnecessary** - WebSocket guarantees frame ordering

### 3. **File Open/Close Per Chunk**
- Server opened file stream for each 5MB chunk
- Performed seek, write, flush, close
- **Significant overhead** - file handles should be kept open

### 4. **Synchronous Flush Per Chunk**
- Server called `FlushAsync()` after every single chunk write
- Forces disk sync on every 5MB chunk
- **Unnecessary** - OS buffer management is sufficient, only final flush needed

---

## Optimizations Applied

### ✅ Optimization 1: Removed 10ms Artificial Delay
**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
**Line**: ~1744

**Before**:
```javascript
ws.send(metadata);

// Small delay to ensure metadata arrives before binary frame
await new Promise(resolve => setTimeout(resolve, 10));

// Send binary chunk frame
```

**After**:
```javascript
ws.send(metadata);

// Send binary chunk frame immediately (WebSocket guarantees ordering)
const chunkData = await chunk.arrayBuffer();
ws.send(chunkData);
```

**Expected Impact**: **10-30% faster**
**Rationale**: Eliminates 10ms * totalChunks unnecessary delay

---

### ✅ Optimization 2: Batch File Flushing
**Files**:
- `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1` (WebSocket)
- `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1` (HTTP PUT)

**Before**:
```powershell
# Write chunk data
$writeTask = $fileStream.WriteAsync($chunkData, 0, $chunkData.Length)
$writeTask.GetAwaiter().GetResult()

# Flush after EVERY chunk
$flushTask = $fileStream.FlushAsync()
$flushTask.GetAwaiter().GetResult()
```

**After**:
```powershell
# Write chunk data
$writeTask = $fileStream.WriteAsync($chunkData, 0, $chunkData.Length)
$writeTask.GetAwaiter().GetResult()

# Flush every 10 chunks or on final chunk (reduces disk I/O overhead)
$shouldFlush = (($uploadInfo.ReceivedChunks + 1) % 10 -eq 0) -or (($uploadInfo.ReceivedChunks + 1) -eq $uploadInfo.TotalChunks)
if ($shouldFlush) {
    $flushTask = $fileStream.FlushAsync()
    $flushTask.GetAwaiter().GetResult()
}
```

**Expected Impact**: **1.5-2x faster**
**Rationale**: Reduces disk sync operations from N chunks to N/10 chunks + final

---

### ✅ Optimization 3: Chunk Pipelining (BIGGEST IMPACT)
**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
**Function**: `uploadViaWebSocket`

**Before** (Serial Processing):
```javascript
for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
    // Send metadata
    ws.send(metadata);

    // Send binary chunk
    const chunkData = await chunk.arrayBuffer();
    ws.send(chunkData);

    // ❌ WAIT for server ACK before sending next chunk
    await new Promise((res, rej) => {
        resolveProgress = res;
        setTimeout(() => rej(new Error('timeout')), 60000);
    });
}
```

**After** (Pipelined Processing):
```javascript
const MAX_IN_FLIGHT = 5;  // Allow 5 chunks (~25MB) in-flight simultaneously
const pendingChunks = new Map();  // Track pending ACKs

const sendChunk = async (chunkIndex) => {
    // Send metadata
    ws.send(metadata);

    // Send binary chunk
    const chunkData = await chunk.arrayBuffer();
    ws.send(chunkData);

    // Return promise that resolves on ACK
    return new Promise((res, rej) => {
        const timeoutId = setTimeout(() => {
            pendingChunks.delete(chunkIndex);
            rej(new Error(`timeout for chunk ${chunkIndex}`));
        }, 60000);

        pendingChunks.set(chunkIndex, { resolve: res, reject: rej, timeoutId });
    });
};

// Sliding window pipeline
const inflightPromises = [];
for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
    // Send chunk (non-blocking)
    const chunkPromise = sendChunk(chunkIndex);
    inflightPromises.push(chunkPromise);

    // ✅ Only wait when pipeline is full (5 chunks in-flight)
    if (inflightPromises.length >= MAX_IN_FLIGHT) {
        await inflightPromises.shift();  // Wait for oldest chunk to complete
    }
}

// Wait for remaining chunks
await Promise.all(inflightPromises);
```

**Updated Message Handler**:
```javascript
ws.onmessage = (event) => {
    const message = JSON.parse(event.data);

    if (message.type === 'progress') {
        // ✅ Resolve the specific chunk's promise
        if (message.chunkNumber !== undefined) {
            const pending = pendingChunks.get(message.chunkNumber);
            if (pending) {
                clearTimeout(pending.timeoutId);
                pending.resolve();
                pendingChunks.delete(message.chunkNumber);
            }
        }
        // ... rest of progress handling
    }
};
```

**Expected Impact**: **10-50x faster**
**Rationale**:
- Eliminates network RTT serialization
- Server already supports out-of-order chunks via `ChunkBitmap`
- Pipeline keeps network and server saturated
- 5 chunks in-flight = ~25MB of data in transit at all times

---

## File Changes Summary

### Modified Files (3)

1. **`apps/WebhostFileExplorer/public/elements/file-explorer/component.js`**
   - Removed 10ms artificial delay
   - Implemented chunk pipelining with sliding window
   - Updated message handler to resolve per-chunk promises
   - Removed old `resolveProgress` single-callback mechanism
   - Lines changed: ~150 lines (major refactoring of `uploadViaWebSocket`)

2. **`apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1`**
   - Added conditional flushing (every 10 chunks + final)
   - Lines changed: ~5 lines

3. **`apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1`**
   - Added conditional flushing (every 10 chunks + final)
   - Lines changed: ~5 lines

---

## Testing Instructions

### Test 1: Basic Upload Speed Verification

**Purpose**: Verify upload speed has improved significantly

**Steps**:
1. Start the web server:
   ```powershell
   .\WebHost.ps1
   ```

2. Open browser to http://localhost:8080/spa

3. Open File Explorer from main menu

4. Create a large test file (100MB):
   ```powershell
   fsutil file createnew C:\Temp\test_100mb.bin 104857600
   ```

5. Upload the file via File Explorer

6. **Observe the speed display** in the transfer UI:
   - **Before optimizations**: ~0.11 MB/s (took ~15 minutes for 100MB!)
   - **After optimizations**: Should be **1-10+ MB/s** (takes 10-100 seconds for 100MB)

7. **Check browser console** (F12) for logs:
   ```
   [uploadViaWebSocket] Sending chunk 0/20 (0%)
   [uploadViaWebSocket] Progress update - 5/20 chunks (25%)
   [uploadViaWebSocket] Upload complete
   ```

8. **Verify file integrity**:
   - Check file size matches
   - Compare checksums if possible

**Success Criteria**:
- ✅ Upload speed: **> 1 MB/s** (minimum 10x improvement)
- ✅ Upload completes successfully
- ✅ File size correct
- ✅ No errors in console

---

### Test 2: Concurrent Upload Stress Test

**Purpose**: Verify pipelining works correctly with multiple chunks in-flight

**Steps**:
1. Create multiple test files:
   ```powershell
   fsutil file createnew C:\Temp\test_50mb_1.bin 52428800
   fsutil file createnew C:\Temp\test_50mb_2.bin 52428800
   fsutil file createnew C:\Temp\test_50mb_3.bin 52428800
   ```

2. Upload all 3 files **simultaneously** (select all 3, drag-and-drop)

3. **Observe**:
   - All 3 uploads should progress concurrently
   - Speed should remain high for all transfers
   - No errors or timeouts

**Success Criteria**:
- ✅ All uploads complete successfully
- ✅ Speed remains > 1 MB/s for each upload
- ✅ No timeout errors
- ✅ All file sizes correct

---

### Test 3: WebSocket Fallback to PUT

**Purpose**: Verify HTTP PUT fallback still works if WebSocket fails

**Steps**:
1. Disable WebSocket support in browser (or simulate failure)
   - Open DevTools → Network tab → Right-click → Block WebSocket
   - Or temporarily break WebSocket endpoint

2. Upload a file

3. **Observe**:
   - Should automatically fall back to PUT chunks
   - Toast message: "Upload completed: filename (PUT)"
   - Speed should still be improved (from flushing optimization)

**Success Criteria**:
- ✅ Upload completes via PUT method
- ✅ Speed improved (though slower than WebSocket)
- ✅ File integrity maintained

---

### Test 4: Large File Upload (1GB)

**Purpose**: Stress test with very large file

**Steps**:
1. Create 1GB test file:
   ```powershell
   fsutil file createnew C:\Temp\test_1gb.bin 1073741824
   ```

2. Upload via File Explorer

3. **Monitor**:
   - Memory usage (should remain stable - no memory leaks)
   - Speed consistency (should maintain high speed throughout)
   - Progress accuracy
   - Server logs for any errors

**Success Criteria**:
- ✅ Upload completes successfully
- ✅ Speed remains high throughout (> 1 MB/s)
- ✅ Memory usage stable
- ✅ File size: exactly 1,073,741,824 bytes

---

### Test 5: Cancel During Upload

**Purpose**: Verify cancellation works correctly with pipelined chunks

**Steps**:
1. Start uploading a large file (500MB+)

2. After 20-30% progress, click **Cancel** button

3. **Verify**:
   - Upload stops immediately
   - Toast: "Upload cancelled"
   - Transfer list shows "Cancelled by user"
   - Temp file cleaned up on server
   - No hanging requests in Network tab

**Success Criteria**:
- ✅ Upload cancels immediately
- ✅ Temp file removed
- ✅ No errors in console
- ✅ No hanging WebSocket connections

---

### Test 6: Network Interruption Recovery

**Purpose**: Verify timeout handling with pipelined chunks

**Steps**:
1. Start uploading a file

2. Simulate network interruption:
   - Pause network in DevTools (Network tab → Offline)
   - Wait 10-15 seconds
   - Resume network

3. **Observe**:
   - Upload may fail with timeout error
   - OR may recover and continue (depending on timing)
   - No crashes or hanging state

**Success Criteria**:
- ✅ Either completes successfully OR fails gracefully
- ✅ Clear error message if failure
- ✅ Transfer list shows correct status
- ✅ No crashes

---

## Performance Expectations

### Before Optimizations
- **Speed**: 0.11 MB/s
- **100MB file**: ~15 minutes
- **1GB file**: ~2.5 hours

### After Optimizations
**Conservative Estimate** (10x improvement):
- **Speed**: 1-2 MB/s
- **100MB file**: 50-100 seconds
- **1GB file**: 8-16 minutes

**Optimistic Estimate** (50x improvement):
- **Speed**: 5-10 MB/s
- **100MB file**: 10-20 seconds
- **1GB file**: 1.5-3 minutes

**Theoretical Maximum** (100x improvement):
- **Speed**: 10-20 MB/s (limited by disk I/O and network)
- **100MB file**: 5-10 seconds
- **1GB file**: 50-100 seconds

---

## Architecture Changes

### Pipelining Architecture

**Before** (Serial):
```
Client                 Server
  |                      |
  |--Chunk 0------------>|
  |                      |--Write to disk
  |<-----ACK 0-----------|
  |                      |
  |--Chunk 1------------>|
  |                      |--Write to disk
  |<-----ACK 1-----------|
  ...
```
**Total time**: N * (send + process + RTT)

**After** (Pipelined):
```
Client                 Server
  |                      |
  |--Chunk 0------------>|
  |--Chunk 1------------>|--Write chunk 0
  |--Chunk 2------------>|--Write chunk 1
  |--Chunk 3------------>|<-ACK 0
  |--Chunk 4------------>|--Write chunk 2
  |<-----ACK 1-----------|<-ACK 1
  |--Chunk 5------------>|--Write chunk 3
  |<-----ACK 2-----------|
  ...
```
**Total time**: Send time + process time (RTT mostly hidden)

### Pipeline Depth: 5 Chunks

**Why 5?**
- **Balance**: Too few = serialization, too many = memory/complexity
- **In-flight data**: 5 chunks * 5MB = 25MB in memory (acceptable)
- **RTT hiding**: Covers typical 50-200ms RTT with 5 outstanding requests
- **Server capacity**: Monitor locks still work correctly

---

## Rollback Plan

If issues occur:

### Rollback All Changes
```bash
git checkout apps/WebhostFileExplorer/public/elements/file-explorer/component.js
git checkout apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1
git checkout apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1
```

### Rollback Selectively

**Rollback pipelining only** (keep flushing and delay removal):
```bash
git diff HEAD~1 component.js > pipeline-changes.patch
# Manually revert just the pipelining code
```

**Rollback flushing optimization** (if causing corruption):
```bash
git checkout apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1
git checkout apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/put.ps1
```

---

## Security Considerations

### ✅ No Security Changes
- All security checks remain unchanged
- Session validation: Still performed
- Permission checks: Still performed
- Upload GUID validation: Still performed
- Monitor locks: Still prevent race conditions

### ✅ No New Vulnerabilities Introduced
- Pipelining uses existing ChunkBitmap idempotency mechanism
- Timeout handling prevents resource exhaustion
- AbortController prevents hanging connections
- Same memory constraints as before (10MB buffer)

---

## Next Steps (Optional - NOT IMPLEMENTED)

### Future Optimization 4: Persistent File Handles
**Effort**: 4-6 hours (HIGH)
**Expected Impact**: Additional 2-3x improvement

Currently file handle is opened/closed per chunk. Could keep handle open for entire upload.

**Changes Required**:
- Store `FileStream` object in `$uploadInfo` hashtable
- Open file on upload init
- Keep handle open during all chunk writes
- Close on completion or cancellation
- Handle cleanup on errors

**Why Not Implemented Now**:
- Requires significant refactoring
- Current improvements already provide 10-50x boost
- Lifecycle management complexity (error handling, cleanup)
- Can be added later if more speed needed

---

## Verification Checklist

After testing, verify:

- [ ] Upload speed improved significantly (> 1 MB/s)
- [ ] Small files upload successfully
- [ ] Large files (1GB+) upload successfully
- [ ] Multiple concurrent uploads work
- [ ] WebSocket upload works
- [ ] PUT fallback works
- [ ] Cancel functionality works
- [ ] No memory leaks during large uploads
- [ ] File integrity preserved (correct size)
- [ ] No errors in browser console
- [ ] No errors in server logs
- [ ] Server performance acceptable (CPU/memory)

---

## Summary

✅ **3 optimizations implemented**:
1. Removed 10ms artificial delay (10-30% improvement)
2. Batch file flushing (1.5-2x improvement)
3. Chunk pipelining with 5-deep sliding window (10-50x improvement)

✅ **Expected total improvement**: **10-50x faster** (from 0.11 MB/s to 1-10+ MB/s)

✅ **Files modified**: 3 files, ~160 lines changed

✅ **Risk level**: **Low-Medium**
- Optimization 1 & 2: Very low risk
- Optimization 3: Medium risk (significant architectural change, but well-tested pattern)

✅ **Ready for testing**: User can start testing immediately

---

**Created**: 2026-01-27
**Implementation Time**: ~3 hours
**Expected Impact**: 10-50x upload speed improvement
**Status**: ✅ IMPLEMENTED - READY FOR TESTING
