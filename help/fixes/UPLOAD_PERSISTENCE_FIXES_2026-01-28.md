# Upload Persistence Fixes - Critical Issues

**Date**: 2026-01-28
**Priority**: HIGH

---

## Critical Issues Identified

### Issue 1: Streaming Uploads Don't Persist to Database

**Problem**:
- Streaming uploads use `upload-stream/put.ps1`
- This endpoint stores upload metadata ONLY in `$Global:PSWebServer.Uploads` (in-memory)
- Database table `Upload_Sessions` is NEVER updated
- When server restarts → upload GUID lost, resume impossible

**Evidence**:
```
User uploaded 1.27GB using streaming method
GUID: d8058f21-69ab-413e-9454-515bffa51951
After server restart:
- Database query: No results
- Temp file search: No file found
- In-memory hashtable: Empty (cleared on restart)
```

**Impact**: Users cannot resume streaming uploads after server restart

---

### Issue 2: Temp Files Not Cleaned Up When Database Entries Removed

**Problem**:
- When upload completes or fails, database entry is deleted
- Temp file (`NewUploadTemp_*.tmp`) is NOT deleted
- Over time, orphaned temp files accumulate

**Evidence**:
```powershell
# From upload-chunk/post.ps1 line 279-281
$deleteQuery = "DELETE FROM Upload_Sessions WHERE UploadGuid = @Guid"
Invoke-SqliteQuery -DataSource $dbFile -Query $deleteQuery -SqlParameters @{ Guid = $data.guid }

# No corresponding Remove-Item for temp file
```

**Impact**: Disk space waste, orphaned files

---

### Issue 3: No Mechanism to Find Orphaned Temp Files

**Problem**:
- Temp files exist without database entries
- No UI to discover or manage them
- No cleanup job to remove old temp files

**Impact**: Users lose access to partially uploaded data

---

## Solutions Implemented

### Solution 1: Batch Validation Endpoint (POST)

**File**: `apps/WebhostFileExplorer/routes/api/v1/files/validation/post.ps1`

**Features**:
- Accepts CSV input with byte ranges and expected hashes
- Can validate by GUID OR logical path
- Returns CSV with pass/fail results
- Works even if database entry missing (searches for orphaned temp files)

**Usage**:
```http
POST /apps/WebhostFileExplorer/api/v1/files/validation?guid=d8058f21-69ab-413e-9454-515bffa51951
Content-Type: text/csv

ByteIndex,Length,Sha256
0,131072,abc123def456...
10485760,131072,789012345678...
```

**Response**:
```csv
ByteIndex,Length,Sha256,Score
0,131072,abc123def456...,pass
10485760,131072,789012345678...,pass
```

**Key Feature**: Finds orphaned temp files by searching filesystem:
```powershell
$tempFileName = "NewUploadTemp_$guid.tmp"
$tempFiles = Get-ChildItem -Path $tempSearchPath -Recurse -Filter $tempFileName
if ($tempFiles) {
    $physicalPath = $tempFiles[0].FullName
}
```

---

## Solutions Needed (Not Yet Implemented)

### Fix 1: Make Streaming Uploads Persist to Database

**File to Modify**: `apps/WebhostFileExplorer/routes/api/v1/files/upload-stream/put.ps1`

**Changes Required**:

**At upload initialization** (around line 106):
```powershell
# CURRENT CODE:
$Global:PSWebServer.Uploads[$uploadGuid] = @{
    Guid = $uploadGuid
    UserID = $userID
    FileName = $fileName
    # ...
}

# ADD AFTER:
# Persist to database
try {
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
    $insertQuery = @"
INSERT INTO Upload_Sessions (
    UploadGuid, UserID, FileName, FileSize, TargetPath, ChunkSize, TotalChunks,
    ChunkBitmap, ReceivedBytes, UploadMethod, TempFilePath, StartTime, LastActivityTime, Status
) VALUES (
    @UploadGuid, @UserID, @FileName, @FileSize, @TargetPath, 0, 0,
    '[]', 0, 'streaming', @TempFilePath, @StartTime, @LastActivityTime, 'active'
)
"@

    Invoke-SqliteQuery -DataSource $dbFile -Query $insertQuery -SqlParameters @{
        UploadGuid = $uploadGuid
        UserID = $userID
        FileName = $fileName
        FileSize = $fileSize
        TargetPath = $targetPathStr
        TempFilePath = $tempFilePath
        StartTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        LastActivityTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }

    Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Persisted streaming upload to database: $uploadGuid"
} catch {
    Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to persist upload to database: $($_.Exception.Message)"
    # Continue anyway - in-memory hashtable is primary
}
```

**During upload progress** (periodically update `ReceivedBytes`):
```powershell
# After every 10MB or every 30 seconds
if (($bytesWritten % 10485760) -eq 0) {
    try {
        $updateQuery = @"
UPDATE Upload_Sessions
SET ReceivedBytes = @ReceivedBytes,
    LastActivityTime = @LastActivityTime
WHERE UploadGuid = @Guid
"@

        Invoke-SqliteQuery -DataSource $dbFile -Query $updateQuery -SqlParameters @{
            ReceivedBytes = $bytesWritten
            LastActivityTime = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
            Guid = $guid
        }
    } catch {
        # Log but don't fail upload
    }
}
```

**At upload completion** (around line 443):
```powershell
# CURRENT CODE:
$Global:PSWebServer.Uploads.Remove($guid) | Out-Null

# ADD BEFORE:
# Remove from database
try {
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
    $deleteQuery = "DELETE FROM Upload_Sessions WHERE UploadGuid = @Guid"
    Invoke-SqliteQuery -DataSource $dbFile -Query $deleteQuery -SqlParameters @{ Guid = $guid }
} catch {
    Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to remove upload from database: $($_.Exception.Message)"
}
```

---

### Fix 2: Delete Temp Files When Database Entries Removed

**Files to Modify**:
1. `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/post.ps1` (line ~279)
2. `apps/WebhostFileExplorer/routes/api/v1/files/upload-chunk/get.ps1` (line ~373)
3. `apps/WebhostFileExplorer/routes/api/v1/files/upload-stream/put.ps1` (multiple places)

**Pattern to Add**:
```powershell
# Before deleting database entry, get temp file path
$query = "SELECT TempFilePath FROM Upload_Sessions WHERE UploadGuid = @Guid"
$result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters @{ Guid = $guid }

$tempFilePath = $result.TempFilePath

# Delete database entry
$deleteQuery = "DELETE FROM Upload_Sessions WHERE UploadGuid = @Guid"
Invoke-SqliteQuery -DataSource $dbFile -Query $deleteQuery -SqlParameters @{ Guid = $guid }

# Delete temp file
if ($tempFilePath -and (Test-Path $tempFilePath)) {
    try {
        Remove-Item $tempFilePath -Force -ErrorAction Stop
        Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Deleted temp file: $tempFilePath"
    } catch {
        Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to delete temp file: $($_.Exception.Message)"
    }
}
```

---

### Fix 3: Add Cleanup Job for Orphaned Temp Files

**Create New File**: `apps/WebhostFileExplorer/jobs/CleanupOrphanedUploads.ps1`

```powershell
<#
.SYNOPSIS
    Cleanup orphaned upload temp files

.DESCRIPTION
    Finds temp files that have no corresponding database entry and removes them
    if they're older than 24 hours.
#>

param (
    [int]$MaxAgeHours = 24
)

$tempDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

# Find all temp files
$tempFiles = Get-ChildItem -Path $tempDir -Recurse -Filter "NewUploadTemp_*.tmp" -ErrorAction SilentlyContinue

Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Found $($tempFiles.Count) temp upload files"

$removedCount = 0
$keptCount = 0

foreach ($tempFile in $tempFiles) {
    # Extract GUID from filename
    if ($tempFile.Name -match 'NewUploadTemp_([a-f0-9\-]+)\.tmp') {
        $guid = $matches[1]

        # Check if database entry exists
        $query = "SELECT UploadGuid FROM Upload_Sessions WHERE UploadGuid = @Guid"
        $result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters @{ Guid = $guid }

        if (-not $result) {
            # No database entry - check age
            $age = (Get-Date) - $tempFile.LastWriteTime

            if ($age.TotalHours -gt $MaxAgeHours) {
                # Old orphaned file - delete
                try {
                    Remove-Item $tempFile.FullName -Force -ErrorAction Stop
                    $removedCount++
                    Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Removed orphaned temp file (age: $([Math]::Round($age.TotalHours, 1))h): $($tempFile.Name)"
                } catch {
                    Write-PSWebHostLog -Severity 'Warning' -Category 'FileExplorer' -Message "Failed to remove orphaned temp file: $($_.Exception.Message)"
                }
            } else {
                $keptCount++
                Write-PSWebHostLog -Severity 'Debug' -Category 'FileExplorer' -Message "Keeping recent orphaned temp file (age: $([Math]::Round($age.TotalHours, 1))h): $($tempFile.Name)"
            }
        }
    }
}

Write-PSWebHostLog -Severity 'Info' -Category 'FileExplorer' -Message "Cleanup complete: removed $removedCount orphaned files, kept $keptCount recent files"

return @{
    RemovedCount = $removedCount
    KeptCount = $keptCount
}
```

**Schedule the job** in `apps/WebhostFileExplorer/app_init.ps1`:
```powershell
# Schedule cleanup job to run daily at 3 AM
$cleanupJob = @{
    Name = 'CleanupOrphanedUploads'
    ScriptPath = Join-Path $AppPath 'jobs/CleanupOrphanedUploads.ps1'
    Schedule = '0 3 * * *'  # Cron: 3 AM daily
    Parameters = @{ MaxAgeHours = 24 }
}

Register-PSWebHostJob @cleanupJob
```

---

### Fix 4: Add UI to Show Orphaned Temp Files

**Create New Endpoint**: `apps/WebhostFileExplorer/routes/api/v1/files/orphaned-uploads/get.ps1`

```powershell
# GET /api/v1/files/orphaned-uploads
# Returns list of orphaned temp files with GUID, filename (guessed), size, age

$tempDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"

$tempFiles = Get-ChildItem -Path $tempDir -Recurse -Filter "NewUploadTemp_*.tmp"

$orphanedUploads = @()

foreach ($tempFile in $tempFiles) {
    if ($tempFile.Name -match 'NewUploadTemp_([a-f0-9\-]+)\.tmp') {
        $guid = $matches[1]

        # Check database
        $query = "SELECT FileName FROM Upload_Sessions WHERE UploadGuid = @Guid"
        $result = Invoke-SqliteQuery -DataSource $dbFile -Query $query -SqlParameters @{ Guid = $guid }

        if (-not $result) {
            # Orphaned
            $orphanedUploads += @{
                guid = $guid
                fileName = 'Unknown (orphaned)'
                fileSize = $tempFile.Length
                tempFilePath = $tempFile.FullName
                lastModified = $tempFile.LastWriteTime.ToString('o')
                ageHours = [Math]::Round(((Get-Date) - $tempFile.LastWriteTime).TotalHours, 1)
            }
        }
    }
}

$json = New-WebHostFileExplorerResponse -Status 'success' -Message "Found $($orphanedUploads.Count) orphaned uploads" -Data @{ orphanedUploads = $orphanedUploads }
Send-WebHostFileExplorerResponse -Response $Response -StatusCode 200 -JsonContent $json
```

---

## Testing After Fixes

### Test 1: Streaming Upload Persistence

1. Start 100MB streaming upload
2. Upload 50MB
3. Restart server
4. Query database:
   ```sql
   SELECT * FROM Upload_Sessions WHERE UploadMethod = 'streaming';
   ```
5. **Expected**: Entry found with ReceivedBytes = ~50MB

### Test 2: Temp File Cleanup on Completion

1. Complete an upload
2. Check database:
   ```sql
   SELECT * FROM Upload_Sessions WHERE UploadGuid = 'xxx';
   ```
3. Check filesystem:
   ```powershell
   Test-Path "PsWebHost_Data/.../NewUploadTemp_xxx.tmp"
   ```
4. **Expected**: Both database entry AND temp file deleted

### Test 3: Orphaned File Cleanup Job

1. Create fake orphaned file:
   ```powershell
   New-Item "PsWebHost_Data/NewUploadTemp_test-guid.tmp" -Value "test"
   ```
2. Set file timestamp to 25 hours ago
3. Run cleanup job
4. **Expected**: File deleted, log entry created

---

## Current Workaround

Until fixes are implemented, users with streaming uploads after server restart must:

1. **Re-upload the file** (progressive hash validation will skip already-received data if temp file found)
2. **Use chunked upload methods** (WebSocket or PUT chunks) which DO persist to database

---

## Priority Order

1. **Fix 1** (Streaming persistence) - **HIGH** - Enables resume for most users
2. **Fix 2** (Temp file cleanup) - **MEDIUM** - Prevents disk waste
3. **Fix 3** (Cleanup job) - **LOW** - Nice to have, automated cleanup
4. **Fix 4** (UI for orphaned files) - **LOW** - User convenience

---

**Document Created**: 2026-01-28
**Status**: Fixes documented, batch validation endpoint implemented
**Remaining Work**: Implement Fixes 1-4

---

**END OF DOCUMENT**
