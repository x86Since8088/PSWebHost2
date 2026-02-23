# Debug Poll Service - Background Command Execution

**Date**: 2026-02-02
**Status**: ✅ Implemented and Ready for Testing

## Overview

Implemented automatic background debug command polling service that loads for users with `debug` or `system_admin` roles. The service runs without requiring a visible debug console card.

## Implementation

### 1. Debug Poll Service Script
**File**: `apps/WebHostDebugExtensions/public/debug-poll-service.js`

- Standalone JavaScript service that auto-starts on page load
- Polls `/apps/WebHostDebugExtensions/api/v1/debug/commands/poll` every 3 seconds
- Executes commands from DebugCommandLibrary (eval, predefined, dom types)
- Sends results back to server via POST to `/apps/WebHostDebugExtensions/api/v1/debug/commands/result`
- Runs in background - does NOT require visible debug console card
- Exposes `window.DebugPollService` with methods:
  - `start()` - Begin polling
  - `stop()` - Stop polling
  - `poll()` - Manual poll
  - `executeCommand(cmd)` - Execute a debug command

### 2. Poll Service Endpoint
**File**: `apps/WebHostDebugExtensions/routes/api/v1/debug/poll-service/get.ps1`

Serves the debug-poll-service.js script as application/javascript.

**Security**: `apps/WebHostDebugExtensions/routes/api/v1/debug/poll-service/get.security.json`
```json
{
  "RequireAuthentication": true,
  "AllowAnonymous": false,
  "RequiredRoles": ["debug", "system_admin"]
}
```

### 3. SPA Auto-Injection
**File**: `routes/spa/get.ps1` (lines 35-46)

Dynamically injects debug scripts for users with debug or system_admin roles:

```powershell
if ('debug' -in $Roles -or 'system_admin' -in $Roles) {
    Write-PSWebHostLog -Severity 'Debug' -Category 'SPA' -Message "Injecting debug poll service for user with debug role"

    $debugScripts = @"
    <!-- Debug Command Polling Service (Auto-loaded for users with debug role) -->
    <script src="/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js"></script>
    <script src="/apps/WebHostDebugExtensions/api/v1/debug/poll-service"></script>
"@

    # Inject before closing </body> tag
    $htmlContent = $htmlContent -replace '</body>', "$debugScripts`n</body>"
}
```

## How It Works

1. **User Login**: User with debug/system_admin role accesses SPA
2. **Script Injection**: SPA server detects role and injects debug scripts into HTML
3. **Auto-Start**: debug-poll-service.js loads and automatically starts polling
4. **Background Polling**: Service polls every 3 seconds for queued commands
5. **Command Execution**: When commands are found, executes them and sends results back
6. **No UI Required**: Works completely in background without visible card

## Command Types Supported

- **eval**: Execute arbitrary JavaScript via `eval()`
- **predefined**: Execute functions from `window.DebugCommandLibrary`
- **dom**: Execute DOM manipulation commands from library

## Example Commands

### Open a Card
```powershell
$body = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Debug Variables'
    }
} | ConvertTo-Json

Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
    -Method POST `
    -Headers @{ Authorization = "Bearer $token" } `
    -Body $body `
    -ContentType 'application/json'
```

### Get Element HTML
```powershell
$body = @{
    Command = 'getOuterHTML'
    Type = 'predefined'
    Params = @{
        selector = '#card-id'
        maxLength = 10000
    }
} | ConvertTo-Json
```

### Highlight Region
```powershell
$body = @{
    Command = 'highlightRegion'
    Type = 'predefined'
    Params = @{
        selector = '#card-id'
        duration = 5000
        color = '#00ff00'
    }
} | ConvertTo-Json
```

## Testing

### Manual Browser Test
1. Open http://localhost:8080 in browser
2. Log in with account that has `debug` or `system_admin` role
3. Open browser Developer Tools (F12) → Console tab
4. Look for initialization messages:
   ```
   [DebugPollService] Initializing background command polling
   [DebugPollService] Starting polling (every 3000ms)
   [DebugPollService] Initialized and polling started
   ```
5. Switch to Network tab and verify:
   - GET requests to `/apps/WebHostDebugExtensions/api/v1/debug/commands/poll`
   - Requests repeat every 3 seconds
   - Returns 204 (No Content) when no commands queued

### PowerShell Test Script
**File**: `test_debug_commands.ps1`

Updated to reflect new behavior (polling works without visible card). Script:
1. Gets bearer token with debug role
2. Enqueues `openCard` command to open debug-variables card
3. Waits for execution and checks command history
4. Enqueues `getOuterHTML` command to capture card HTML
5. Enqueues `highlightRegion` command to visually highlight the card

## Files Created/Modified

### Created
- `apps/WebHostDebugExtensions/public/debug-poll-service.js`
- `apps/WebHostDebugExtensions/routes/api/v1/debug/poll-service/get.ps1`
- `apps/WebHostDebugExtensions/routes/api/v1/debug/poll-service/get.security.json`
- `test_debug_poll_service.ps1` (implementation checker)

### Modified
- `routes/spa/get.ps1` - Added role-based script injection
- `test_debug_commands.ps1` - Updated documentation to reflect no card requirement

## Benefits

1. **No Manual Setup**: Auto-loads for authorized users
2. **Always Available**: Works as soon as user logs in
3. **No UI Clutter**: Runs in background without visible card
4. **Secure**: Requires debug/system_admin role
5. **Non-Intrusive**: Uses long-polling with 3-second interval
6. **Reliable**: Handles failures gracefully and continues polling

## Architecture

```
PowerShell Script
    ↓ (HTTP POST with bearer token)
Enqueue Endpoint (/api/v1/debug/commands/enqueue)
    ↓ (stores command in queue)
Command Queue (in-memory)
    ↑ (polls every 3 seconds)
Browser Poll Service (debug-poll-service.js)
    ↓ (executes command)
DebugCommandLibrary (commands.js)
    ↓ (sends result)
Result Endpoint (/api/v1/debug/commands/result)
    ↓ (stores result)
Command History (for later retrieval)
```

## Security Considerations

- Only loads for users with `debug` or `system_admin` roles
- All endpoints require authentication
- Commands execute in browser context (same origin policy applies)
- `eval` type commands require careful sanitization on server side
- Bearer tokens expire and require regeneration

## Next Steps

1. **Test in Browser**: Log in with debug role and verify polling starts
2. **Run Test Script**: Execute `test_debug_commands.ps1` to verify end-to-end flow
3. **Monitor Logs**: Check server logs for any errors during command execution
4. **Performance**: Monitor impact of 3-second polling on server load
