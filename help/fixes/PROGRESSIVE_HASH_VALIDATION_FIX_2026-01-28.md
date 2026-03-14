# Progressive Hash Validation Resume Offset Bug - FIXED

**Date**: 2026-01-28
**Priority**: CRITICAL
**Status**: ✅ FIXED

---

## Bug Summary

After progressive hash validation completed, the upload process "zipped to 100%" without sending the remaining data that was not validated on the first transfer attempt.

**Evidence from User Logs**:
```
[07:22:47] performProgressiveHashValidation END: 975175680 / 6864345088 bytes validated (14%)
[07:22:47] Validated 14% of upload - resuming from byte 975175680
[07:22:50] uploadViaStreaming: Resuming from offset 6864345088, sending 0 bytes
[07:22:50] uploadViaStreaming: Upload complete
```

**Analysis**:
1. Hash validation correctly identified 93 ranges totaling **975,175,680 bytes (14%)** as validated
2. Frontend correctly updated progress to 14%
3. Frontend correctly set `window.pendingResumeUpload.validatedBytes = 975175680`
4. **BUG**: Upload resumed from offset **6,864,345,088** (the FULL file size) instead of **975,175,680** (end of validated data)
5. Since offset equals file size, **0 bytes sent**
6. Upload immediately marked as complete

---

## Root Cause

### The Problem Chain

**Step 1**: User pauses upload, then resumes with file re-selection

**Step 2**: `resumeTransfer` performs progressive hash validation
- Compares server-side temp file hashes with client-side file hashes
- Finds 975MB (14%) validated, remaining 86% needs to be re-uploaded
- Stores result in `window.pendingResumeUpload.validatedBytes = 975175680`

**Step 3**: `resumeTransfer` calls `uploadFile()`

**Step 4**: `uploadFile` detects `window.pendingResumeUpload` and extracts `resumeGuid`
- ❌ **CRITICAL BUG**: Deleted `window.pendingResumeUpload` immediately (line 4358)
- This destroyed the `validatedBytes` field before `uploadViaStreaming` could use it!

**Step 5**: `uploadFile` calls `uploadViaStreaming(file, ..., resumeGuid)`

**Step 6**: `uploadViaStreaming` initializes session with server
- Server checks temp file size: 6.8GB
- Server returns `startOffset: 6864345088` (full file size)
- Client receives this value and uses it directly (line 3568)
- ❌ **CRITICAL BUG**: No override logic to use `validatedBytes` from hash validation

**Step 7**: Upload starts from offset 6.8GB
- File slice: `file.slice(6864345088)` → 0 bytes
- Upload completes immediately with 0 bytes sent

---

## The Fix

### Fix 1: Override Server's startOffset with validatedBytes

**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
**Location**: Lines 3566-3584
**Change**: Added logic to override server's `startOffset` if `validatedBytes` exists

**Before**:
```javascript
const initResult = await initResponse.json();
const uploadGuid = initResult.data.guid;
const startOffset = initResult.data.startOffset || 0;
const bytesReceived = initResult.data.bytesReceived || 0;

logToServer(`uploadViaStreaming: Session initialized with GUID ${uploadGuid}, startOffset: ${startOffset}`);
```

**After**:
```javascript
const initResult = await initResponse.json();
const uploadGuid = initResult.data.guid;
let startOffset = initResult.data.startOffset || 0;  // Changed to 'let'
const bytesReceived = initResult.data.bytesReceived || 0;

// CRITICAL FIX: Override startOffset if we have validated bytes from progressive hash validation
// The server reports the full temp file size, but hash validation may have found corruption
// In that case, we need to resume from the end of the last validated range, not the end of the file
if (window.pendingResumeUpload &&
    window.pendingResumeUpload.uploadGuid === uploadGuid &&
    typeof window.pendingResumeUpload.validatedBytes === 'number') {

    const validatedBytes = window.pendingResumeUpload.validatedBytes;
    logToServer(`uploadViaStreaming: Progressive hash validation found ${validatedBytes} validated bytes, overriding server startOffset ${startOffset}`);
    startOffset = validatedBytes;

    // Clear pendingResumeUpload now that we've used the validatedBytes
    delete window.pendingResumeUpload;
}

logToServer(`uploadViaStreaming: Session initialized with GUID ${uploadGuid}, startOffset: ${startOffset}`);
```

### Fix 2: Don't Delete window.pendingResumeUpload Prematurely

**File**: `apps/WebhostFileExplorer/public/elements/file-explorer/component.js`
**Location**: Lines 4353-4364
**Change**: Delay deletion of `window.pendingResumeUpload` until after `uploadViaStreaming` reads `validatedBytes`

**Before**:
```javascript
resumeGuid = window.pendingResumeUpload.uploadGuid;
const resumeMethod = window.pendingResumeUpload.method;
logToServer(`uploadFile: Detected pending resume for ${file.name}, GUID: ${resumeGuid}, method: ${resumeMethod}`);

// Clear pending resume
delete window.pendingResumeUpload;

// Force the same method for resume
if (resumeMethod === 'streaming') {
    uploadMethod = 'streaming';
}
```

**After**:
```javascript
resumeGuid = window.pendingResumeUpload.uploadGuid;
const resumeMethod = window.pendingResumeUpload.method;
logToServer(`uploadFile: Detected pending resume for ${file.name}, GUID: ${resumeGuid}, method: ${resumeMethod}`);

// NOTE: Do NOT clear window.pendingResumeUpload yet
// uploadViaStreaming needs to access validatedBytes from it
// It will be cleared after the upload function reads it

// Force the same method for resume
if (resumeMethod === 'streaming') {
    uploadMethod = 'streaming';
}
```

---

## Expected Behavior After Fix

### Test Case: 6.8GB Upload with 86% Corruption

**Setup**:
- User uploads 6.8GB file (6,864,345,088 bytes)
- Upload interrupted after 6.8GB received (100% transferred)
- Server-side temp file has corruption in last 86% (only first 975MB valid)
- User restarts browser and resumes upload

**Step 1**: Progressive hash validation
```
[INFO] performProgressiveHashValidation START
[INFO] Server reports: fileSize=6864345088, firstHash=abc123...
[INFO] Validating range 0: hash matches
[INFO] Validating range 10485760: hash matches
...
[INFO] Validating range 1048576000: hash MISMATCH - stopping
[INFO] performProgressiveHashValidation END: 975175680 / 6864345088 bytes validated (14%)
```

**Step 2**: Resume upload with corrected offset
```
[INFO] resumeTransfer: Setting pendingResumeUpload | Data: {
    "validatedBytes": 975175680,
    "uploadGuid": "5c6014c4-5e3e-4585-bc94-b503bd1ecfbc"
}
[INFO] uploadFile: Detected pending resume, GUID: 5c6014c4-5e3e-4585-bc94-b503bd1ecfbc
[INFO] uploadViaStreaming: Session initialized with GUID 5c6014c4-5e3e-4585-bc94-b503bd1ecfbc
[INFO] uploadViaStreaming: Server reported startOffset: 6864345088
[INFO] uploadViaStreaming: Progressive hash validation found 975175680 validated bytes, overriding server startOffset 6864345088
[INFO] uploadViaStreaming: Resuming from offset 975175680, sending 5889169408 bytes
```

**Step 3**: Upload remaining data
- Client sends bytes from 975,175,680 to 6,864,345,088
- Server overwrites corrupt data in temp file
- Upload completes successfully

---

## Technical Details

### Why Server Reports Wrong Offset

The server's `upload-stream/put.ps1` endpoint returns `startOffset` based on the **current temp file size**:

```powershell
# Line 65 in upload-stream/put.ps1
if (Test-Path $tempFilePath) {
    $existingFile = Get-Item $tempFilePath
    $startOffset = $existingFile.Length  # ← Returns FULL file size
    $uploadGuid = $resumeGuid
}
```

This is correct behavior from the server's perspective - it received 6.8GB and saved it all. The server doesn't know the data is corrupt until the client performs hash validation.

### Why Client Must Override

The client-side progressive hash validation is the ONLY component that knows:
1. How much data is actually valid (975MB)
2. Where corruption starts (offset 975,175,680)

Therefore, the client MUST override the server's `startOffset` with the `validatedBytes` value.

### File Overwrite Behavior

When the client sends data from offset 975MB:

1. **Client**: Sends `Content-Range: bytes 975175680-6864345087/6864345088`
2. **Server**: Receives header and seeks file stream to offset 975175680
3. **Server**: Writes incoming data starting at that position
4. **Result**: Data from 975MB to 6.8GB is overwritten with correct data

The file length remains 6.8GB throughout (pre-allocated by `$fileStream.SetLength($FileSize)` in Save-IncomingFileUpload.ps1).

---

## Testing Verification

### Test 1: Resume After Hash Validation

1. Start 6.8GB upload
2. Upload completes (100%)
3. Manually corrupt temp file (overwrite last 86% with zeros)
4. Restart browser
5. Click "Resume" on paused transfer
6. Re-select file
7. **Expected**: Hash validation finds 14% valid, resumes from 975MB
8. **Expected**: Upload sends remaining 5.8GB
9. **Expected**: Upload completes successfully

### Test 2: Log Output Verification

Look for these log entries:

```
✅ uploadViaStreaming: Progressive hash validation found 975175680 validated bytes, overriding server startOffset 6864345088
✅ uploadViaStreaming: Resuming from offset 975175680, sending 5889169408 bytes
```

**NOT**:
```
❌ uploadViaStreaming: Resuming from offset 6864345088, sending 0 bytes
```

### Test 3: Progress Bar Behavior

- Hash validation completes: Progress jumps to 14%
- Upload resumes: Progress increases from 14% to 100%
- Transfer speed shows normal rates (not instant completion)

---

## Related Files Modified

### 1. component.js (2 changes)

**Change 1** (lines 3566-3584):
- Added override logic for `startOffset` using `validatedBytes`
- Clears `window.pendingResumeUpload` after reading it

**Change 2** (lines 4353-4364):
- Removed premature deletion of `window.pendingResumeUpload`
- Added comment explaining why deletion is delayed

---

## Status: ✅ FIXED

**Date Fixed**: 2026-01-28
**Verified**: Pending user testing

---

## Additional Notes

### Why This Bug Was Subtle

1. The server was behaving correctly (reporting actual file size)
2. The client was storing the correct data (`validatedBytes`)
3. The bug was in the **timing** of when `window.pendingResumeUpload` was deleted
4. The deletion happened between storing the data and reading it

### Prevention

Future code should follow this pattern:

```javascript
// 1. Store data
window.pendingResumeUpload = { validatedBytes, uploadGuid, ... };

// 2. Call async function that needs the data
await uploadFunction();

// 3. That function reads and clears the data
// (NOT the caller)
```

**Don't do this**:
```javascript
// 1. Store data
window.pendingResumeUpload = { ... };

// 2. Clear data immediately
delete window.pendingResumeUpload;  // ← BUG! Data lost before use

// 3. Call function that needs the data
await uploadFunction();  // ← Can't access data anymore
```

---

**END OF DOCUMENT**
