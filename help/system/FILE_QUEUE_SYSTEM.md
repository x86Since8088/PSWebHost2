# File-Based Command Queue System

## Overview

The file-based command queue allows PowerShell scripts to send commands to browsers without requiring HTTP calls or authentication. Commands are written to files, browsers poll for them, execute them, and write results back.

## Architecture

```
PowerShell Script                    Browser
      |                                 |
      | Write command file              |
      v                                 |
  outbox/[sessionid]/                   |
  [commandid].json                      |
      |                                 |
      | <-- Poll endpoint reads         |
      |     and deletes file            |
      |                                 v
      |                            Receive command
      |                                 |
      |                                 | Send "received" ack
      |                                 v
      |                            inbox/[sessionid]/
      |                            [commandid].json
      | <-- Read result                 |
      |     (if waiting)                |
      |                                 v
      |                            Execute command
      |                                 |
      |                                 | Send final result
      |                                 v
      |                            inbox/[sessionid]/
      |                            [commandid].json
      | <-- Read final result           |
      |     and cleanup                 |
      v                                 v
  Complete                         Continue polling
```

## Directory Structure

```
PsWebHost_Data/apps/WebHostDebugExtensions/
├── outbox/
│   ├── all/              # Broadcast to all sessions
│   │   └── [commandid].json
│   └── [sessionid]/      # Session-specific
│       └── [commandid].json
└── inbox/
    ├── all/              # Results from broadcast
    │   └── [commandid].json
    └── [sessionid]/      # Session-specific results
        └── [commandid].json
```

## Command Lifecycle

1. **Enqueue** - PowerShell writes command file to outbox
2. **Poll** - Browser polls endpoint, receives command, deletes from outbox
3. **Acknowledge** - Browser sends "received" status to inbox
4. **Execute** - Browser executes the command
5. **Report** - Browser sends final result ("completed" or "failed") to inbox
6. **Retrieve** - PowerShell reads result from inbox (if waiting)
7. **Cleanup** - Old files removed by cleanup script

## Command Statuses

- `pending` - In outbox, waiting for browser
- `executing` - Delivered to browser (added by poll endpoint)
- `received` - Browser acknowledged receipt
- `completed` - Successfully executed
- `failed` - Execution error

## Files

### Utility Scripts (Client-Side)

- **Debug_Client_Command_Enqueue.ps1** - Enqueue commands from PowerShell
  - `-Command` - JavaScript code or command name
  - `-Type` - eval | predefined | dom | network
  - `-SessionID` - Target session or "all"
  - `-Wait` - Wait for result
  - `-TimeoutSeconds` - Max wait time (default: 30)

- **Debug_Command_Cleanup.ps1** - Clean up stale files
  - `-OutboxMaxAgeMinutes` - Max age for outbox files (default: 60)
  - `-InboxMaxAgeMinutes` - Max age for inbox files (default: 1440)

### Server Endpoints

- **poll/get.ps1** - Browser polls for commands
  - Returns commands from session-specific and "all" outboxes
  - Deletes files after delivery
  - Handles expiration

- **result/post.ps1** - Browser posts execution results
  - Writes to inbox
  - Maintains backward compatibility with in-memory history

### Browser Components

- **component.js** - Debug Console component with polling
- **test-file-queue.html** - Standalone test page

## Usage Examples

### Send a simple command

```powershell
.\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "console.log('Hello from PowerShell!')" `
    -Type eval `
    -SessionID all
```

### Send and wait for result

```powershell
$result = .\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "navigator.userAgent" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 10

if ($result.Success) {
    Write-Host "User Agent: $($result.Result)"
}
```

### Open a card

```powershell
.\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "openCard" `
    -Type predefined `
    -Params @{
        url = "/apps/WebHostDebugExtensions/cards/debug-console"
        title = "Debug Console"
    } `
    -SessionID all `
    -Wait
```

### Browser refresh (don't wait for result)

```powershell
# Refresh commands can't return results because page reloads
.\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "location.reload()" `
    -Type eval `
    -SessionID all
```

### Clean up old files

```powershell
# Remove files older than 30 minutes from outbox, 2 hours from inbox
.\apps\WebHostDebugExtensions\system\utility\Debug_Command_Cleanup.ps1 `
    -OutboxMaxAgeMinutes 30 `
    -InboxMaxAgeMinutes 120
```

## Testing

### Test with browser

1. Open: `http://localhost:8080/test-file-queue.html`
2. Run: `.\test_live_browser.ps1`
3. Watch commands execute in browser

### Test card operations

1. Open: `http://localhost:8080/`
2. Run: `.\test_card_operations.ps1`
3. Verify cards open/close

### Verify end-to-end

```powershell
.\test_full_cycle.ps1
```

## Advantages

✅ **No HTTP/Auth required** - Simple file I/O, no bearer tokens
✅ **Persists across restarts** - Commands survive server restarts
✅ **Session isolation** - Separate folders per session
✅ **Broadcast support** - Send to all sessions via "all" folder
✅ **Automatic expiration** - Commands timeout after 60 seconds
✅ **Easy debugging** - Just look at the files
✅ **Acknowledgment** - Know when command was received vs completed

## Known Behaviors

- **Refresh commands** - Browser refresh (`location.reload()`) won't return a result because the page reloads. Don't use `-Wait` for refresh commands.
- **Post-refresh delay** - After refresh, API calls may fail for 1-2 seconds while page loads. This is normal.
- **Timeout cleanup** - Commands expire after 60 seconds if not picked up
- **File locking** - Rare race conditions possible if files are being read/written simultaneously

## Maintenance

### Schedule cleanup

```powershell
# Windows Task Scheduler - Run daily at 2 AM
$action = New-ScheduledTaskAction `
    -Execute 'pwsh.exe' `
    -Argument '-NoProfile -File "C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Command_Cleanup.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At 2am

Register-ScheduledTask `
    -TaskName "PSWebHost-DebugCleanup" `
    -Action $action `
    -Trigger $trigger `
    -Description "Clean up old debug command files"
```

### Monitor queue size

```powershell
$outbox = "PsWebHost_Data\apps\WebHostDebugExtensions\outbox"
$inbox = "PsWebHost_Data\apps\WebHostDebugExtensions\inbox"

$outboxCount = (Get-ChildItem $outbox -Recurse -File).Count
$inboxCount = (Get-ChildItem $inbox -Recurse -File).Count

Write-Host "Outbox: $outboxCount files"
Write-Host "Inbox: $inboxCount files"
```

## Troubleshooting

### Commands not executing

- Check browser is open and polling (green indicator)
- Verify files appear in outbox: `ls PsWebHost_Data\apps\WebHostDebugExtensions\outbox\*\*.json`
- Check server logs for poll errors
- Verify browser console for JavaScript errors

### Results not returning

- Check files appear in inbox: `ls PsWebHost_Data\apps\WebHostDebugExtensions\inbox\*\*.json`
- Verify browser can POST to result endpoint (check authentication)
- Check timeout isn't too short
- Look for "received" acknowledgment first

### Old files piling up

- Run cleanup script manually
- Check cleanup script is scheduled
- Reduce max age parameters
- Verify file permissions allow deletion

## Security Considerations

- File-based queue bypasses HTTP auth
- Anyone with filesystem access can enqueue commands
- Commands execute with browser's permissions
- Use for development/debugging only
- Consider adding file permission checks in production
- Monitor for unusual command patterns

## Future Enhancements

- [ ] Priority queue (high/normal/low priority folders)
- [ ] Command expiration policies per command type
- [ ] Result streaming for long-running commands
- [ ] Command queue dashboard
- [ ] Metrics collection (commands/sec, success rate, etc.)
- [ ] File encryption for sensitive commands
- [ ] Command history log
