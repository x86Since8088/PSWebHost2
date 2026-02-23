# Debug Command System - Quick Reference

**Date**: 2026-02-02
**Status**: ✅ Operational

## Overview

The debug command system allows PowerShell scripts to execute JavaScript commands in active browser sessions. Commands are queued server-side and executed by the browser's debug poll service.

## Auto-Loading

The debug poll service auto-loads for users with `debug` or `system_admin` roles. It:
- Polls every 3 seconds at `/apps/WebHostDebugExtensions/api/v1/debug/commands/poll`
- Executes commands automatically
- Sends results back to server
- **Logs command reception to server via `window.logToServer`** (Category: `DebugPoll`, Level: `info`)

## API Endpoints

### 1. Enqueue Command
**POST** `/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue`

**Headers**:
```
Authorization: Bearer <token>
Content-Type: application/json
```

**Body**:
```json
{
  "Command": "command_string_or_function_name",
  "Type": "eval|predefined|dom",
  "Params": { /* optional parameters */ }
}
```

**Response**:
```json
{
  "commandID": "uuid",
  "queuePosition": 1,
  "message": "Command enqueued successfully"
}
```

### 2. Get Command History
**GET** `/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=10`

Returns array of executed commands with results.

## Command Types

### 1. eval - Execute JavaScript
```powershell
$body = @{
    Command = 'console.log("Hello from PowerShell!")'
    Type = 'eval'
} | ConvertTo-Json
```

### 2. predefined - Use DebugCommandLibrary
Available commands: `openCard`, `closeCard`, `getOuterHTML`, `highlightRegion`, `getCardList`, `scrollToCard`

```powershell
$body = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Debug Variables'
    }
} | ConvertTo-Json
```

## PowerShell Examples

### Basic Command Execution
```powershell
# Get bearer token (you need this first)
$token = "your_bearer_token_here"

# Enqueue command
$body = @{
    Command = 'window.location.href'
    Type = 'eval'
} | ConvertTo-Json

$response = Invoke-RestMethod `
    -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
    -Method POST `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body $body

# Wait for execution
Start-Sleep -Seconds 3

# Check result
$history = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=5" `
    -Headers @{ Authorization = "Bearer $token" }

$result = $history | Where-Object { $_.CommandID -eq $response.commandID }
Write-Host "Result: $($result.Result)"
```

### Open a Card
```powershell
$body = @{
    Command = 'openCard'
    Type = 'predefined'
    Params = @{
        url = '/apps/WebHostDebugVariables/cards/debug-variables'
        title = 'Test Card'
    }
} | ConvertTo-Json

Invoke-RestMethod `
    -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' `
    -Method POST `
    -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } `
    -Body $body
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

$response = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue' -Method POST -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' } -Body $body

Start-Sleep -Seconds 2
$history = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=5" -Headers @{ Authorization = "Bearer $token" }
$result = $history | Where-Object { $_.CommandID -eq $response.commandID }
$html = ($result.Result | ConvertFrom-Json).outerHTML
Write-Host $html
```

## Browser Verification

1. **Check Poll Service**: Open DevTools (F12) → Console → Look for `[DebugPollService] Initialized and polling started`
2. **Monitor Polling**: DevTools → Network tab → See requests every 3s to `/debug/commands/poll`
3. **Watch Execution**: Console shows command execution messages
4. **Check Server Logs**: Commands logged via `window.logToServer` in category `DebugPoll`

## Test Scripts

- **test_direct_debug_cmd.ps1** - Interactive test requiring bearer token
- **test_debug_commands.ps1** - Automated test (creates token, opens card, captures HTML)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Commands stay pending | Check browser console for poll service, verify debug role |
| 401 Unauthorized | Invalid/missing bearer token |
| Poll service not loading | User needs debug/system_admin role, clear cache |

## Server Logging (NEW)

When poll endpoint returns commands, it now logs to server via `window.logToServer`:
- **Category**: `DebugPoll`
- **Level**: `info`
- **Data**: Command count and command details (ID, type, command text)

This provides server-side visibility into debug command activity.
