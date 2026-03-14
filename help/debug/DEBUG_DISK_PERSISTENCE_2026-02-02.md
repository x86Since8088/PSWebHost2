# Debug Command Disk Persistence - 2026-02-02

## Overview

Added PUT endpoint for debug command results that writes directly to disk without buffering. This provides:
- **Persistence** across server restarts
- **Unbuffered writes** - results written immediately
- **Large result support** - no memory limitations
- **Audit trail** - all results saved to disk
- **Backwards compatibility** - results also added to in-memory history

## Implementation

### PUT Endpoint
**File**: `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/result/put.ps1`

**Method**: PUT
**URL**: `/apps/WebHostDebugExtensions/api/v1/debug/commands/result`
**Auth**: Requires `debug` or `system_admin` role

**Request Body**:
```json
{
  "CommandID": "uuid",
  "Result": "string or object",
  "Error": "error message or null",
  "ExecutionTime": 123
}
```

**Response**:
```json
{
  "status": "success",
  "saved": "disk",
  "filePath": "uuid.json"
}
```

### Storage Location
Results saved to: `PsWebHost_Data/debug_results/{CommandID}.json`

### Result File Format
```json
{
  "CommandID": "abc-123-...",
  "SessionID": "session-id",
  "UserID": "user-id",
  "Status": "completed",
  "CompletedAt": "2026-02-02T10:30:00Z",
  "CompletedTime": "2026-02-02T10:30:00Z",
  "Result": "command result",
  "Error": null,
  "ExecutionTime": 45,
  "ExecutionTimeMs": 45,
  "SavedToDisk": true,
  "FilePath": "C:\\path\\to\\result.json"
}
```

### Client-Side Changes
**File**: `apps/WebHostDebugExtensions/public/debug-poll-service.js`

- **Now uses PUT by default** for all result submissions
- Writes directly to disk (unbuffered)
- Logs storage method in console: `saved to disk` or `saved to memory`
- Can be configured to use POST if needed (set `usePUT = false`)

```javascript
// Use PUT for disk persistence (unbuffered), POST for in-memory (buffered)
const usePUT = true;  // Always use PUT for direct-to-disk writes

const response = await window.psweb_fetchWithAuthHandling(
    '/apps/WebHostDebugExtensions/api/v1/debug/commands/result',
    {
        method: usePUT ? 'PUT' : 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(resultPayload)
    }
);
```

## Helper Functions

### Get-DebugCommandResult
Retrieves a specific command result from disk or memory.

```powershell
# Get from memory first, fallback to disk
$result = Get-DebugCommandResult -CommandID "abc-123-..."

# Force read from disk
$result = Get-DebugCommandResult -CommandID "abc-123-..." -FromDisk
```

### Get-AllDebugCommandResults
Retrieves all command results from disk.

```powershell
# Get all results (sorted by most recent first)
$allResults = Get-AllDebugCommandResults

# Get last 10 results
$recentResults = Get-AllDebugCommandResults -Limit 10
```

## Comparison: POST vs PUT

| Feature | POST (Memory) | PUT (Disk) |
|---------|---------------|------------|
| Storage | In-memory buffer | Direct to disk |
| Persistence | Lost on restart | Survives restart |
| Size limit | Memory constrained | Disk constrained |
| Speed | Faster | Slightly slower (I/O) |
| History limit | MaxHistorySize (500) | Unlimited |
| Audit trail | Temporary | Permanent |
| Buffer mode | Buffered | Unbuffered |

## Usage Examples

### PowerShell: Read Result from Disk
```powershell
# Enqueue command
$result = Debug-ClientCommand -Command "window.location.href" -Type eval
$cmdId = $result.CommandID

# Wait a moment for execution
Start-Sleep -Seconds 3

# Retrieve result (automatically checks memory first, then disk)
$commandResult = Get-DebugCommandResult -CommandID $cmdId

if ($commandResult) {
    Write-Host "Result: $($commandResult.Result)"
    Write-Host "Status: $($commandResult.Status)"
    Write-Host "Saved: $($commandResult.SavedToDisk)"
}
```

### PowerShell: Review All Saved Results
```powershell
# Get last 20 results from disk
$results = Get-AllDebugCommandResults -Limit 20

foreach ($r in $results) {
    Write-Host "[$($r.CompletedAt)] $($r.CommandID) - Status: $($r.Status)"
    if ($r.Error) {
        Write-Host "  Error: $($r.Error)" -ForegroundColor Red
    } else {
        Write-Host "  Result: $($r.Result)" -ForegroundColor Green
    }
}
```

### PowerShell: Clean Old Results
```powershell
# Delete results older than 7 days
$resultsDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\debug_results"
$cutoff = (Get-Date).AddDays(-7)

Get-ChildItem -Path $resultsDir -Filter "*.json" |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    Remove-Item -Force

Write-Host "Cleaned old debug results"
```

## Backwards Compatibility

The PUT endpoint maintains full backwards compatibility:

1. **Dual Storage**: Results written to both disk AND in-memory history
2. **Utility Scripts**: Work unchanged - they check in-memory history first
3. **POST Still Works**: Original POST endpoint still functions
4. **Helper Functions**: New functions are additive, don't break existing code

## Benefits

### 1. Persistence
Results survive server restarts, crashes, or updates. Historical data always available.

### 2. Unbuffered I/O
Results written immediately without buffering. No risk of data loss.

### 3. Audit Trail
Complete history of all debug commands executed with timestamps.

### 4. Large Results
No memory constraints - can save very large results (e.g., full HTML dumps, large JSON objects).

### 5. Analysis
Can analyze historical command patterns, performance metrics, error rates.

### 6. Debugging
When troubleshooting, can review exact commands and results from past sessions.

## Performance Considerations

- **Disk I/O**: Each result is a file write operation (typically <1ms for small results)
- **File System**: Uses standard file system - scales to thousands of results
- **Memory Impact**: Minimal - only stores reference in memory, full data on disk
- **Cleanup**: Consider periodic cleanup of old results (manual or scheduled)

## Configuration

### Change to POST (Memory Only)
Edit `debug-poll-service.js`:
```javascript
const usePUT = false;  // Use POST for memory-only storage
```

### Adjust History Retention
Edit `app_init.ps1`:
```powershell
$Global:PSWebServer.DebugCommands = @{
    MaxHistorySize = 1000  # Increase from 500
}
```

### Custom Storage Location
Edit `put.ps1`:
```powershell
$resultsDir = "C:\CustomPath\debug_results"  # Custom location
```

## Files Created/Modified

### New Files
- `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/result/put.ps1` - PUT endpoint
- `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/result/put.security.json` - Security config
- `DEBUG_DISK_PERSISTENCE_2026-02-02.md` - This documentation

### Modified Files
- `apps/WebHostDebugExtensions/public/debug-poll-service.js` - Now uses PUT by default
- `apps/WebHostDebugExtensions/app_init.ps1` - Added helper functions:
  - `Get-DebugCommandResult`
  - `Get-AllDebugCommandResults`

## Testing

### Test PUT Endpoint
```powershell
# With bearer token
$token = "your_token_here"

$body = @{
    CommandID = [guid]::NewGuid().ToString()
    Result = "Test result"
    Error = $null
    ExecutionTime = 100
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/result' `
    -Method PUT `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body $body
```

### Verify File Created
```powershell
$resultsDir = Join-Path $PSScriptRoot "PsWebHost_Data\debug_results"
Get-ChildItem $resultsDir | Select-Object Name, LastWriteTime
```

## Troubleshooting

### Results Not Saving
- Check disk permissions on `PsWebHost_Data/debug_results/`
- Verify server has write access
- Check server logs for errors

### Can't Find Result
- Use `Get-DebugCommandResult` which checks both memory and disk
- Verify CommandID is correct (case-sensitive)
- Check if result file exists: `Test-Path "PsWebHost_Data/debug_results/{CommandID}.json"`

### Directory Not Created
- Server will auto-create on first PUT request
- Manual creation: `New-Item "PsWebHost_Data/debug_results" -ItemType Directory -Force`

## Security

- PUT endpoint requires authentication (debug/system_admin role)
- Results stored with session and user information
- File names are UUIDs (CommandIDs) - no sensitive data in filename
- Directory permissions inherit from `PsWebHost_Data/`
- Consider encrypting sensitive results if needed

## Future Enhancements

Potential improvements:
- Compression for large results (gzip)
- Encryption for sensitive data
- Automatic cleanup policy (configurable retention)
- Result indexing/search capability
- Export to SQLite database option
- Result aggregation/analytics
