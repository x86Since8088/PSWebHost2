# Log_Tail.ps1 - Usage Guide

## Overview
`Log_Tail.ps1` is a PowerShell utility for monitoring log files in real-time. It outputs new lines as PSCustomObjects with metadata including path, encoding, timestamp, line number, and content.

## Features

- ✅ **Real-time monitoring** - Watches files and outputs new lines as they're written
- ✅ **Multiple file support** - Monitor multiple files simultaneously (separate job per file)
- ✅ **Auto-discovery** - No path? Automatically tails all log files in project folders
- ✅ **Wildcard support** - Use `*.log`, `*` or any wildcard pattern to match files
- ✅ **Quote trimming** - Automatically strips quotes and whitespace from paths
- ✅ **Job management** - Start as background jobs for non-blocking operation
- ✅ **Auto-cleanup** - When `-Seconds` is used with `-AsJob`, automatically waits, receives, and removes jobs
- ✅ **Interactive file selection** - Use GridView to select files from project folders
- ✅ **Encoding detection** - Automatically detects UTF-8, Unicode, BigEndian, or defaults to UTF-8
- ✅ **Structured output** - Returns PSCustomObjects for easy filtering and formatting

## Output Format

Each new line is returned as a PSCustomObject with:

```powershell
[PSCustomObject]@{
    Path       = "C:\full\path\to\file.log"
    Encoding   = "Unicode"
    Date       = [DateTime] (timestamp when line was read)
    LineNumber = 1  (incremental counter per file)
    Line       = "actual log content"
}
```

## Usage Modes

### 1. Direct File Monitoring (Inline)

Monitor a file directly in the current session (blocking):

```powershell
# Monitor indefinitely (Ctrl+C to stop)
.\system\utility\Log_Tail.ps1 -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv"

# Monitor for 30 seconds then stop
.\system\utility\Log_Tail.ps1 -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv" -Seconds 30
```

### 2. Background Jobs (Non-blocking)

Start monitoring as a background job:

```powershell
# Monitor indefinitely as background job
.\system\utility\Log_Tail.ps1 -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv" -AsJob

# Monitor with timeout and auto-cleanup
.\system\utility\Log_Tail.ps1 -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv" -AsJob -Seconds 60
```

**With `-Seconds` and `-AsJob`:**
- Starts the background job
- **Automatically waits** for the timeout period
- **Automatically receives** all output
- **Automatically removes** the jobs
- Returns nothing (output is displayed, jobs are cleaned up)

**Without `-Seconds`:**
- Starts the background job
- Returns job objects
- Jobs run indefinitely until manually stopped
- Requires manual management (list/receive/stop)

### 3. Auto-Discovery (No Path)

Omit `-Path` to automatically tail **all** log files found in project folders:

```powershell
# Tail all discovered log files
.\system\utility\Log_Tail.ps1 -AsJob -Seconds 60

# Output shows which files are being monitored:
# No path specified. Tailing all 9 discovered log files:
#   - C:\SC\PsWebHost\PsWebHost_Data\Logs\log.tsv
#   - C:\SC\PsWebHost\tests\test-host-logs\webhost.8888.out.txt
#   ...
```

### 4. Wildcard Patterns

Use wildcards to match multiple files:

```powershell
# All TSV files in a folder
.\system\utility\Log_Tail.ps1 -Path "C:\logs\*.tsv" -AsJob -Seconds 30

# All log files recursively (bare asterisk expands to project root)
.\system\utility\Log_Tail.ps1 -Path "*" -AsJob -Seconds 30

# Multiple wildcard patterns
.\system\utility\Log_Tail.ps1 -Path "C:\logs\app*.log","C:\logs\db*.log" -AsJob
```

**Path Processing:**
- Quotes and whitespace trimmed: `"  file.log  "` → `file.log`
- Bare asterisk: `*` → `C:\sc\PsWebHost\*`
- Wildcards expanded using `Get-ChildItem -Include *.log,*.csv,*.tsv,*.txt`

### 5. Multiple Explicit Files

Monitor multiple files simultaneously (one job per file):

```powershell
# Monitor multiple files
.\system\utility\Log_Tail.ps1 -Path "file1.log","file2.log","file3.log" -AsJob -Seconds 30

# Mix of paths
.\system\utility\Log_Tail.ps1 -Path "C:\logs\app.log",".\test.log" -AsJob
```

### 6. Interactive File Selection

Select files interactively from project folders:

```powershell
# Select files with GridView (Ctrl+Click for multiple)
.\system\utility\Log_Tail.ps1 -SelectWithGridView -AsJob -Seconds 60
```

Searches these folders for `.log`, `.csv`, `.tsv`, `.txt` files:
- `PsWebHost_Data\Logs`
- `tests`
- `PsWebHost_Data`

### 7. Job Management

When jobs are started without `-Seconds`, manage them manually:

```powershell
# List all tail jobs
.\system\utility\Log_Tail.ps1 -Name '*'

# List specific job
.\system\utility\Log_Tail.ps1 -Name '*log.tsv*'

# Receive output from jobs (keeps jobs running)
.\system\utility\Log_Tail.ps1 -Name '*' -Receive

# Stop and remove jobs
.\system\utility\Log_Tail.ps1 -Name '*' -Stop
```

## Job Names

Each tail job is named using the pattern:
```
Log_Tail: [full path to file]
```

Example:
```
Log_Tail: C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv
```

## Examples

### Example 1: Quick 10-Second Tail with Auto-Cleanup

```powershell
.\system\utility\Log_Tail.ps1 -Path "C:\logs\app.log" -AsJob -Seconds 10
```

Output:
```
Started 1 tail job(s):
Id Name                              State
-- ----                              -----
 1 Log_Tail: C:\logs\app.log        Running

Waiting for jobs to complete (10s timeout)...

Receiving job output:
========================================
Job: Log_Tail: C:\logs\app.log (State: Completed)
========================================
Path     Encoding Date                 LineNumber Line
----     -------- ----                 ---------- ----
C:\lo... UTF-8    12/29/2025 4:45 PM            1 New log entry here

Removing completed jobs...
Jobs cleaned up successfully
```

### Example 2: Auto-Discovery - Tail All Log Files

```powershell
.\system\utility\Log_Tail.ps1 -AsJob -Seconds 30
```

Output:
```
No path specified. Tailing all 9 discovered log files:
  - C:\SC\PsWebHost\PsWebHost_Data\Logs\log.tsv
  - C:\SC\PsWebHost\tests\test-host-logs\webhost.8888.out.txt
  - C:\SC\PsWebHost\tests\test-host-logs\webhost.80.out.txt
  ...

Started 9 tail job(s):
...
```

### Example 3: Wildcard Pattern Matching

```powershell
# All TSV files in logs folder
.\system\utility\Log_Tail.ps1 -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\*.tsv" -AsJob -Seconds 60
```

### Example 4: Monitor Multiple Files with GridView

```powershell
.\system\utility\Log_Tail.ps1 -SelectWithGridView -AsJob -Seconds 30
```

1. GridView opens showing all log files
2. Select multiple files (Ctrl+Click)
3. Script starts one job per file
4. Waits 30 seconds
5. Displays all output
6. Cleans up jobs automatically

### Example 5: Long-Running Background Monitoring

```powershell
# Start monitoring (no timeout)
.\system\utility\Log_Tail.ps1 -Path "C:\logs\app.log" -AsJob

# Later, check output
.\system\utility\Log_Tail.ps1 -Name '*' -Receive

# When done, stop
.\system\utility\Log_Tail.ps1 -Name '*' -Stop
```

### Example 6: Monitor and Filter

```powershell
# Tail inline and filter for errors
.\system\utility\Log_Tail.ps1 -Path "C:\logs\app.log" -Seconds 60 |
    Where-Object { $_.Line -match 'ERROR' }
```

### Example 7: Multiple Files, Specific Timeout

```powershell
.\system\utility\Log_Tail.ps1 `
    -Path "C:\logs\web.log","C:\logs\db.log","C:\logs\auth.log" `
    -AsJob -Seconds 120
```

Monitors 3 files for 2 minutes, then displays all captured output and cleans up.

## Advanced Usage

### Existing Job Termination

The script automatically terminates existing jobs for the same file before starting a new one:

```powershell
# First call - starts job
.\system\utility\Log_Tail.ps1 -Path "file.log" -AsJob

# Second call - stops first job, starts new one
.\system\utility\Log_Tail.ps1 -Path "file.log" -AsJob
```

### Encoding Detection

The script detects file encoding automatically:
- **UTF-8** - BOM: `0xEF 0xBB 0xBF`
- **Unicode (UTF-16 LE)** - BOM: `0xFF 0xFE`
- **BigEndianUnicode (UTF-16 BE)** - BOM: `0xFE 0xFF`
- **Default** - Falls back to system default if no BOM detected
- **Assumed UTF-8** - If file cannot be read, assumes UTF-8

### File Access

Files are opened with `FileShare.ReadWrite`, allowing:
- The log file to be written to while being tailed
- Multiple processes to read the same file
- No locks that would prevent logging

## Common Scenarios

### Development - Watch Test Results

```powershell
.\system\utility\Log_Tail.ps1 `
    -Path ".\tests\test-results.log" `
    -AsJob -Seconds 300  # 5 minutes
```

### Troubleshooting - Monitor Errors

```powershell
.\system\utility\Log_Tail.ps1 `
    -Path "C:\sc\PsWebHost\PsWebHost_Data\Logs\log.tsv" `
    -Seconds 60 |
    Where-Object { $_.Line -match 'Error|Warning' } |
    Select-Object Date, Line
```

### Production - Long-Term Monitoring

```powershell
# Start monitoring
$jobs = .\system\utility\Log_Tail.ps1 `
    -Path "C:\logs\production.log" `
    -AsJob

# Check periodically
.\system\utility\Log_Tail.ps1 -Name '*production*' -Receive | Out-File captured.txt -Append

# Stop when done
.\system\utility\Log_Tail.ps1 -Name '*production*' -Stop
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-Path` | string[] | Full or relative paths to files to monitor |
| `-SelectWithGridView` | switch | Interactive file selection from project folders |
| `-Name` | string | Job name pattern for management (supports wildcards) |
| `-Receive` | switch | Receive output from matching jobs |
| `-Stop` | switch | Stop and remove matching jobs |
| `-Seconds` | int | Timeout in seconds (0 = indefinite, default: 0) |
| `-AsJob` | switch | Run as background job instead of inline |

## Notes

- **Line Numbers** start at 1 and increment per file per job
- **Existing Output Ignored** - Only new lines written AFTER the tail starts are captured
- **100ms Polling** - Checks for new data every 100 milliseconds
- **Separate Jobs** - Each file gets its own job for isolation
- **Date Precision** - Timestamp reflects when the line was READ, not when it was written
- **Auto-Cleanup** - When `-Seconds` > 0 and `-AsJob`, jobs are automatically cleaned up after timeout

## Troubleshooting

### No Output Shown

**Cause:** File already at end, no new lines written after tail started

**Solution:** Write new entries to the log while tail is running, or restart tail to capture recent entries

### Jobs Not Found

**Cause:** Jobs completed or were already cleaned up

**Solution:** Use `-Seconds` parameter or check `Get-Job` directly

### Permission Denied

**Cause:** File locked by another process with exclusive access

**Solution:** Ensure file is opened with shared read/write access by the writing process

## Performance

- **Memory:** Minimal - only stores current line being read
- **CPU:** Low - 100ms sleep between polls when no data
- **File Handles:** One handle per file per job (closed when job completes)
- **Scalability:** Can monitor dozens of files simultaneously

## Status: ✅ Complete

All features implemented and tested:
- ✅ Single and multiple file monitoring
- ✅ Background job support
- ✅ Auto-cleanup with `-Seconds` and `-AsJob`
- ✅ Interactive file selection
- ✅ Job management (list, receive, stop)
- ✅ Encoding detection
- ✅ Structured PSCustomObject output
- ✅ Existing job termination before new start
