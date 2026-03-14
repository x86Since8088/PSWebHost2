# Testing Guide - FileExplorer Storage Path Permissions
**Date**: 2026-01-27

---

## Quick Start

### 1. Start the Server

Open PowerShell and run:

```powershell
cd C:\SC\PsWebHost
.\WebHost.ps1
```

Wait for the server to start. You should see output indicating the server is listening on port 8080.

### 2. Verify Server is Running

In another PowerShell window:

```powershell
Invoke-WebRequest -Uri "http://localhost:8080/" -Method GET -UseBasicParsing
```

You should get a 200 status code.

---

## Automated Testing

### Run the Synthetic Test Script

```powershell
cd C:\SC\PsWebHost
.\Test-UploadAndResume.ps1
```

**What it tests**:
1. Creates a 50MB random test file
2. Checks server availability
3. Initializes an upload
4. Uploads first 25% of chunks
5. Simulates a disconnect (pause)
6. Queries upload status
7. Resumes upload (uploads remaining 75%)
8. Verifies upload completion
9. Simulates progressive hash validation
10. Cleans up test file

**Expected Output**:
```
=== FileExplorer Upload & Resume Synthetic Tests ===

--- Test 1: Create Test File ---
[PASS] Create Test File
       Created 50MB file at C:\Users\...\test-upload-20260127-143052.bin

--- Test 2: Check Server Availability ---
[PASS] Server Availability
       Server version: 1.0.0

... (8 more tests) ...

=== Test Summary ===
Passed: 10
  ✓ Create Test File
  ✓ Server Availability
  ✓ Authentication
  ✓ Initialize Upload
  ✓ Upload First 25%
  ✓ Simulate Disconnect
  ✓ Query Upload Status
  ✓ Resume Upload
  ✓ Verify Upload Completion
  ✓ Progressive Hash Validation

All tests passed! ✓
```

### Custom Test Parameters

```powershell
# Test with 100MB file and 1MB chunks
.\Test-UploadAndResume.ps1 -TestFileSizeMB 100 -ChunkSizeKB 1024

# Test against different server
.\Test-UploadAndResume.ps1 -BaseUrl "http://192.168.1.100:8080"
```

---

## Manual Testing - Storage Path Permissions

### Test 1: Access FileSharingModal

1. Open browser: `http://localhost:8080/apps/WebhostFileExplorer`
2. Navigate to any file
3. Double-click the file
4. **FileActionModal should appear** with options:
   - 📥 Download
   - 📝 Edit as Text (for text files)
   - 🔢 Edit as Hex
   - 🔗 Share
5. Click **"Share"** button
6. **FileSharingModal should open in a new card**

**Expected Result**: FileSharingModal opens with two tabs: "Register New Path" and "Manage Paths"

---

### Test 2: Register Storage Path with Auto-Groups

1. In FileSharingModal, go to **"Register New Path"** tab
2. Fill in the form:
   - **Logical Path**: `User:me` (should be auto-filled from file path)
   - **Physical Path**: `C:\Users\test\Documents`
   - **Name**: `Test Documents`
   - **Description**: `Test storage path for automated testing`
   - **Auto-create groups**: ✓ (checked)
3. Click **"Register Storage Path"**

**Expected Results**:
- Success toast appears: "Storage path registered successfully"
- Switches to "Manage Paths" tab automatically
- Path appears in the list
- Info message shows created groups:
  - `Test_Documents_owners`
  - `Test_Documents_readers`
  - `Test_Documents_writers`

**Verify in Database**:
```powershell
$db = "C:\SC\PsWebHost\system\db\PSWebHost.db"
sqlite3 $db "SELECT * FROM Storage_Paths WHERE Name = 'Test Documents';"
sqlite3 $db "SELECT * FROM User_Groups WHERE Name LIKE 'Test_Documents_%';"
sqlite3 $db "SELECT * FROM Storage_Path_Permissions WHERE PathID = (SELECT PathID FROM Storage_Paths WHERE Name = 'Test Documents');"
```

---

### Test 3: Register Storage Path with Custom Permissions

1. In FileSharingModal, go to **"Register New Path"** tab
2. Fill in the form:
   - **Logical Path**: `System:C/Temp`
   - **Physical Path**: `C:\Temp`
   - **Name**: `Temp Directory`
   - **Auto-create groups**: ☐ (unchecked)
3. Scroll down to **"Permissions"** section
4. **For Owner Permissions**:
   - Select "Role" → Choose "system_admin" → Click "Add"
   - Verify badge appears: 🔑 system_admin
5. **For Read Permissions**:
   - Select "Role" → Choose "admin" → Click "Add"
   - Verify badge appears: 🔑 admin
6. **For Write Permissions**:
   - Select "User" → Enter "test@example.com" → Click "Add"
   - Verify badge appears: 👤 test@example.com
7. Click **"Register Storage Path"**

**Expected Results**:
- Success toast appears
- Path appears in "Manage Paths" tab
- Permissions show:
  - Owner: system_admin (role)
  - Read: admin (role)
  - Write: test@example.com (user)

---

### Test 4: Update Permissions for Existing Path

1. In FileSharingModal, go to **"Manage Paths"** tab
2. Find "Test Documents" path
3. Click edit button (✏️)
4. Permission editor expands inline
5. **Add new permission**:
   - In "Read Permissions" section
   - Select "Role" → Choose "authenticated" → Click "Add"
6. **Remove existing permission**:
   - Click × button on one of the auto-created group permissions
7. Click **"Update Permissions"**

**Expected Results**:
- Success toast: "Permissions updated successfully"
- Editor closes
- Refresh page and verify changes persisted

---

### Test 5: Verify Permission Enforcement

**Setup**: Register a restricted path (admin-only):

```powershell
# Using PowerShell to call API directly
$body = @{
    logicalPath = "System:C/AdminOnly"
    physicalPath = "C:\AdminOnly"
    name = "Admin Only Path"
    autoCreateGroups = $false
    permissions = @(
        @{
            type = "owner"
            principals = @(
                @{principalType = "role"; principalId = "admin"}
            )
        },
        @{
            type = "read"
            principals = @(
                @{principalType = "role"; principalId = "admin"}
            )
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-WebRequest -Uri "http://localhost:8080/apps/WebhostFileExplorer/api/v1/storage/paths" `
    -Method POST `
    -ContentType "application/json" `
    -Body $body `
    -UseBasicParsing
```

**Test**:
1. Log in as non-admin user
2. Try to access `System:C/AdminOnly` path via FileExplorer
3. **Expected**: Access denied (403 Forbidden)
4. Log in as admin user
5. Try to access `System:C/AdminOnly` path
6. **Expected**: Access granted (200 OK)

---

### Test 6: Deactivate Storage Path

1. In FileSharingModal, go to **"Manage Paths"** tab
2. Find "Temp Directory" path
3. Click delete button (🗑️)
4. Confirm deletion dialog

**Expected Results**:
- Success toast: "Storage path deactivated"
- Path removed from list
- File access reverts to default permissions

**Verify in Database**:
```powershell
sqlite3 $db "SELECT IsActive FROM Storage_Paths WHERE Name = 'Temp Directory';"
# Should return: 0
```

---

## Manual Testing - Upload Settings & Resume

### Test 7: Upload Settings Race Condition Fix

1. Open FileExplorer: `http://localhost:8080/apps/WebhostFileExplorer`
2. Click Settings (⚙️) button
3. **Uncheck "WebSocket Upload"** method
4. Keep "PUT Chunks Upload" checked
5. Close settings
6. Upload a large file (>50MB)
7. After a few chunks, click **Pause**
8. Wait 2 seconds
9. Click **Resume**

**Expected Results**:
- Check server logs for: `"Settings loaded: ...websocket=false..."`
- Check server logs for: `"uploadFileWithResume: Using putChunks method"`
- Transfer resumes using PUT chunks (NOT WebSocket)
- Transfer panel shows method badge: 📤 PUT Chunks

---

### Test 8: Progressive Hash Validation

**Setup**: Create a large test file

```powershell
# Create 200MB test file
$path = "C:\Users\test\Downloads\test-large.bin"
$stream = [System.IO.File]::Create($path)
$buffer = New-Object byte[] (1024 * 1024)
$random = New-Object System.Random

for ($i = 0; $i -lt 200; $i++) {
    $random.NextBytes($buffer)
    $stream.Write($buffer, 0, $buffer.Length)
}

$stream.Close()
```

**Test**:
1. In FileExplorer, navigate to target folder
2. Drag and drop `test-large.bin` file
3. Upload starts
4. After 50MB uploaded, **close browser tab** (or click pause)
5. Re-open FileExplorer
6. Navigate to same folder
7. Drag and drop **same file** again
8. **Resume dialog should appear**

**Expected Dialog**:
```
Resume Upload?

File: test-large.bin
Size: 200 MB
Uploaded: 50 MB (25%)

The file you selected appears to be an incomplete upload.

Would you like to:
[ Resume ] [ Start Fresh ] [ Cancel ]
```

9. If file still accessible in browser, click **Resume**
10. **Watch browser console logs**:
    - `Progressive validation: Phase 1 - Checking 100MB chunks`
    - `Progressive validation: Phase 2 - Narrowing with 10MB chunks`
    - `Progressive validation: Phase 3 - Pinpointing with 1MB chunks`
    - `Validation complete: Files match`

**If file not accessible**:
- File selection dialog appears
- Select the file manually
- Validation proceeds

**If files differ**:
- Dialog shows: `⚠️ First 1MB of files differ. Overwrite existing upload?`
- Choose to overwrite or cancel

---

### Test 9: File Operations Refresh

**Test Tree Refresh on Create**:
1. In FileExplorer, navigate to a folder
2. Note the folder tree on the left
3. Click "New Folder" button
4. Enter name: `Test Folder`
5. **Expected**: Folder tree on left automatically refreshes and shows new folder

**Test Tree Refresh on Rename**:
1. Right-click a file or folder
2. Click "Rename"
3. Enter new name
4. **Expected**: Both file list AND folder tree update

**Test Tree Refresh on Delete**:
1. Right-click a file or folder
2. Click "Delete"
3. Confirm deletion
4. **Expected**: Both file list AND folder tree update

---

### Test 10: Resume Button Transfer Persistence

1. Upload a large file
2. After 25% uploaded, click **Pause**
3. Transfer shows in transfers panel with status "Paused"
4. Click **Resume** button on the transfer

**Expected Results**:
- Transfer **stays visible** in transfers panel
- Status changes from "Paused" to "Uploading"
- Progress continues from 25%
- Transfer ID remains the same (check logs)
- No duplicate transfer appears in list

**Check Server Logs**:
```
resumeTransfer: State BEFORE resume {"transferId":"upload-123...","status":"paused",...}
resumeTransfer: Status transition: paused → uploading
resumeTransfer: State AFTER resume setup {"transferId":"upload-123...","status":"uploading",...}
uploadFile: Reusing existing transfer ID: upload-123...
```

---

## Troubleshooting

### Issue: Tests fail with "Server not responding"

**Solution**:
```powershell
# Check if server is running
Get-Process | Where-Object {$_.ProcessName -eq "pwsh" -or $_.ProcessName -eq "powershell"}

# Check if port 8080 is in use
netstat -ano | findstr :8080

# Restart server
cd C:\SC\PsWebHost
.\WebHost.ps1
```

### Issue: "Storage_Paths table not found"

**Solution**:
```powershell
# Verify database tables exist
$db = "C:\SC\PsWebHost\system\db\PSWebHost.db"
sqlite3 $db ".tables"

# Should include:
# Storage_Paths
# Storage_Path_Permissions
```

If tables don't exist, the server should auto-create them on startup from `sqliteconfig.json`.

### Issue: FileSharingModal doesn't open

**Check**:
1. Browser console for JavaScript errors
2. User has admin/site_admin/system_admin role
3. Security.json file exists: `apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-sharing-modal/get.security.json`

### Issue: Permissions not enforced

**Debug**:
```powershell
# Check if path is registered
sqlite3 $db "SELECT * FROM Storage_Paths WHERE LogicalPath = 'User:me';"

# Check permissions
sqlite3 $db "SELECT * FROM Storage_Path_Permissions WHERE PathID = '...';"

# Check user's groups
sqlite3 $db "SELECT g.Name FROM User_Groups g JOIN User_Groups_Map m ON g.GroupID = m.GroupID WHERE m.UserID = 'test@example.com';"

# Check user's roles
sqlite3 $db "SELECT RoleName FROM PSWeb_Roles WHERE PrincipalID = 'test@example.com';"
```

---

## Success Criteria

### All Tests Pass When:

✅ **Synthetic Test Script**:
- All 10 tests show [PASS]
- Test file created and cleaned up
- Upload completes 100%

✅ **Storage Path Permissions**:
- Can register paths with auto-groups
- Can register paths with custom permissions
- Can update permissions for existing paths
- Can deactivate storage paths
- Permissions correctly enforced

✅ **Upload & Resume**:
- Upload settings loaded before resume
- Correct method selected (respects disabled methods)
- Progressive hash validation works
- Resume button keeps transfer visible
- No duplicate transfers created

✅ **File Operations**:
- New folder creation refreshes tree
- Rename updates both list and tree
- Delete updates both list and tree

---

## Next Steps After Testing

### If All Tests Pass:
1. Document any issues found (even minor ones)
2. Test with real users in staging environment
3. Monitor server logs for any warnings
4. Prepare for production deployment

### If Tests Fail:
1. Note which test failed and the error message
2. Check server logs for detailed error information
3. Verify all files are in place (17 files total)
4. Check database schema matches specification
5. Report findings for debugging

---

## Performance Benchmarks

### Expected Performance:

- **Path Registration**: < 500ms
- **Permission Query**: < 100ms
- **Chunk Upload (512KB)**: 50-200ms (network dependent)
- **Resume Detection**: < 200ms
- **Progressive Hash (100MB)**: 2-5 seconds
- **Tree Refresh**: < 300ms

### Monitor These Metrics:

```powershell
# Check database size growth
Get-Item "C:\SC\PsWebHost\system\db\PSWebHost.db" | Select-Object Length

# Check server memory usage
Get-Process pwsh | Select-Object WorkingSet64

# Check upload temp files
Get-ChildItem "C:\SC\PsWebHost\PsWebHost_Data\*" -Filter "NewUploadTemp_*.tmp" -Recurse
```

---

**END OF TESTING GUIDE**
