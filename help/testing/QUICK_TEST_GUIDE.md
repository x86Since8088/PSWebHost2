# Quick Test Guide - FileExplorer Upload & Resume

## Prerequisites

1. **Server must be running**:
   ```powershell
   cd C:\SC\PsWebHost
   .\WebHost.ps1
   ```

2. **PowerShell 7+** required

---

## Run Tests

### Quick Test (Default Settings)
```powershell
cd C:\SC\PsWebHost
.\Test-UploadAndResume.ps1
```

**What it does**:
- Creates 50MB test file
- Tests upload/pause/resume cycle
- Validates progressive hash checking
- Cleans up automatically

**Expected Duration**: 1-2 minutes

---

## Custom Test Parameters

### Large File Test (100MB)
```powershell
.\Test-UploadAndResume.ps1 -TestFileSizeMB 100
```

### Bigger Chunks (1MB)
```powershell
.\Test-UploadAndResume.ps1 -ChunkSizeKB 1024
```

### Small File, Small Chunks (Fast Test)
```powershell
.\Test-UploadAndResume.ps1 -TestFileSizeMB 10 -ChunkSizeKB 256
```

### Remote Server
```powershell
.\Test-UploadAndResume.ps1 -BaseUrl "http://192.168.1.100:8080"
```

### Combined
```powershell
.\Test-UploadAndResume.ps1 `
    -TestFileSizeMB 200 `
    -ChunkSizeKB 512 `
    -BaseUrl "http://localhost:8080"
```

---

## Expected Output

```
=== FileExplorer Upload & Resume Synthetic Tests ===

--- Test 1: Create Test File ---
[PASS] Create Test File
       Created 50MB file at C:\Users\test\AppData\Local\Temp\test-upload-20260128-010203.bin

--- Test 2: Check Server Availability ---
[PASS] Server Availability
       Server is responding (HTTP 200)

--- Test 3: Create Bearer Token ---
Creating test bearer token...
[PASS] Create Bearer Token
       Token: TestBearerKey_AbCdE

--- Test 4: Initialize Upload ---
[PASS] Initialize Upload
       Upload GUID: a1b2c3d4-..., Total chunks: 100

--- Test 5: Upload First 25% of Chunks ---
[PASS] Upload First 25%
       Uploaded 25 / 25 chunks

--- Test 6: Simulate Disconnect ---
Simulating connection interruption (pausing for 2 seconds)...
[PASS] Simulate Disconnect
       Paused upload

--- Test 7: Query Upload Status ---
[PASS] Query Upload Status
       Received 25 / 100 chunks (25%)

--- Test 8: Resume Upload ---
Missing chunks: 75
[PASS] Resume Upload
       Uploaded 75 / 75 missing chunks

--- Test 9: Verify Upload Completion ---
[PASS] Verify Upload Completion
       Received 100 / 100 chunks (COMPLETE)

--- Test 10: Progressive Hash Validation (Simulated) ---
First 100MB SHA256: abcdef1234567890...
[PASS] Progressive Hash Validation
       Computed hash for validation

--- Cleanup ---
✓ Test file deleted: C:\Users\test\AppData\Local\Temp\test-upload-20260128-010203.bin
✓ Removing bearer token: TestBearerKey_AbCdE
✓ Bearer token removed

=== Test Complete ===
Passed: 10
  ✓ Create Test File
  ✓ Check Server Availability
  ✓ Create Bearer Token
  ✓ Initialize Upload
  ✓ Upload First 25%
  ✓ Simulate Disconnect
  ✓ Query Upload Status
  ✓ Resume Upload
  ✓ Verify Upload Completion
  ✓ Progressive Hash Validation

All tests passed! ✓
```

---

## Troubleshooting

### Error: "Cannot reach server"
**Fix**:
```powershell
# Check if server is running
curl http://localhost:8080/

# If not running, start it:
cd C:\SC\PsWebHost
.\WebHost.ps1
```

### Error: "Failed to create bearer token"
**Possible causes**:
1. System/init.ps1 not found
2. Database not accessible
3. Permission issues

**Fix**:
```powershell
# Try creating token manually:
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount -Roles admin

# If successful, run test again
```

### Error: "Upload check failed"
**Possible causes**:
1. FileExplorer app not loaded
2. Invalid target path
3. Permission denied

**Fix**:
```powershell
# Check app is loaded
curl http://localhost:8080/apps/WebhostFileExplorer/

# Should return 200 OK
```

### Error: "Chunk upload failed"
**Possible causes**:
1. Network timeout
2. Server error
3. Disk full

**Check server logs**:
```powershell
# Server console will show errors
# Look for upload-chunk endpoint errors
```

### Tests hang on "Uploading chunks"
**Possible causes**:
1. Server not responding to chunk uploads
2. Network issue
3. Server overloaded

**Fix**:
- Press Ctrl+C to cancel
- Check server logs
- Try with smaller file: `-TestFileSizeMB 10`

---

## Advanced Usage

### Run Only Specific Tests

Edit `Test-UploadAndResume.ps1` and comment out tests you don't want:

```powershell
# ============================================================================
# Test 5: Upload First 25% of Chunks
# ============================================================================

# Write-Host "`n--- Test 5: Upload First 25% of Chunks ---" -ForegroundColor Yellow
# ... (comment out entire test block)
```

### Change Upload Percentage

Edit line ~110 in `Test-UploadAndResume.ps1`:

```powershell
# Upload 50% instead of 25%
$chunksToUpload = [Math]::Ceiling($totalChunks * 0.50)  # Was: 0.25
```

### Debug Mode

Add `-Verbose` to HTTP requests:

```powershell
$response = Invoke-WebRequest `
    -Uri $uri `
    -Method PUT `
    -Body $chunkData `
    -Headers $script:Headers `
    -UseBasicParsing `
    -Verbose  # ADD THIS
```

---

## Performance Benchmarks

### Expected Speeds (Localhost)

| File Size | Chunks | Duration | Speed |
|-----------|--------|----------|-------|
| 10 MB     | 20     | ~5 sec   | 2 MB/s |
| 50 MB     | 100    | ~15 sec  | 3.3 MB/s |
| 100 MB    | 200    | ~30 sec  | 3.3 MB/s |
| 500 MB    | 1000   | ~2.5 min | 3.3 MB/s |

*Speeds may vary based on disk speed and system load*

### Bottlenecks

1. **Disk I/O**: Temp file creation and chunk writes
2. **Network latency**: Even on localhost, HTTP overhead adds up
3. **SQLite locks**: Database writes for chunk tracking

### Optimization Tips

- Use **larger chunks** for faster uploads: `-ChunkSizeKB 2048`
- Run on **SSD** for faster disk I/O
- **Reduce file size** for quicker tests

---

## What Gets Tested

✅ **File Creation**: Random binary file generation
✅ **Server Availability**: HTTP connectivity
✅ **Authentication**: Bearer token creation and usage
✅ **Upload Initialization**: Upload GUID and chunk calculation
✅ **Partial Upload**: First 25% of chunks
✅ **Disconnect Simulation**: Pause and wait
✅ **Status Query**: Check server-side upload state
✅ **Resume Logic**: Upload only missing chunks
✅ **Completion Verification**: 100% chunk receipt
✅ **Hash Validation**: SHA256 computation (simulated)
✅ **Cleanup**: File and token removal

---

## Manual Cleanup (If Needed)

### Remove Test Files
```powershell
Remove-Item "$env:TEMP\test-upload-*.bin" -Force
```

### Remove Test Tokens
```powershell
# List all test tokens
.\system\utility\Account_Auth_BearerToken_Get.ps1 | Where-Object { $_.Name -like 'TestBearerKey_*' }

# Remove specific token
.\system\utility\Account_Auth_BearerToken_Remove.ps1 -Name TestBearerKey_xxxxx
```

### Clear Upload Temp Files
```powershell
Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\*" -Filter "NewUploadTemp_*.tmp" -Recurse | Remove-Item -Force
```

---

## Next Steps

After tests pass:
1. Review `TESTING_GUIDE_2026-01-27.md` for manual UI tests
2. Test FileSharingModal in browser
3. Test progressive hash validation with real resume scenario
4. Review `STORAGE_PATH_PERMISSIONS_SYSTEM_2026-01-27.md` for architecture details

---

**Quick Reference Card - Keep This Handy!**
