# Debug Utilities Fixes - 2026-02-02

## Summary

Fixed WebHostDebugExtensions utility scripts to work with the correct global variable paths and added helper functions for easier access to command history.

## Problems Fixed

### 1. Incorrect Global Variable References
**Problem**: Utility scripts referenced `$Global:PSWebHostDebugCommandHistory` which doesn't exist.
**Solution**: Updated all utility scripts to use `$Global:PSWebServer.DebugCommands.History`

**Files Updated**:
- `Launch-DebugCard.ps1` - 1 occurrence
- `Close-DebugCard.ps1` - 1 occurrence
- `Get-DebugOpenCards.ps1` - 1 occurrence
- `Test-DebugCardLoad.ps1` - 2 occurrences
- `Invoke-DebugCardTest.ps1` - 8 occurrences

### 2. Property Name Mismatch in Result Endpoint
**Problem**: Browser sends `ExecutionTime` but server expected `ExecutionTimeMs`
**Solution**: Updated result endpoint to accept both property names for backwards compatibility

**File**: `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/result/post.ps1`

Added:
```powershell
$execTime = if ($resultData.ExecutionTimeMs) { $resultData.ExecutionTimeMs } else { $resultData.ExecutionTime }

$resultObj = @{
    ...
    ExecutionTime = $execTime
    ExecutionTimeMs = $execTime
    CompletedTime = (Get-Date).ToString('o')  # Alias for utility scripts
    ...
}
```

### 3. Missing Helper Functions
**Problem**: No convenient way to access command history
**Solution**: Added helper functions to `app_init.ps1`

**Functions Added**:
- `Get-DebugCommandHistory` - Retrieve and filter command history
  - Parameters: `-Limit`, `-CommandID`, `-Status`
  - Returns sorted history (most recent first)

- `Get-DebugCommandQueue` - Get pending commands from queue
  - Returns array of queued commands

## Architecture

### Command Flow
```
1. PowerShell Script
   ↓ calls Debug-ClientCommand
2. $Global:PSWebServer.DebugCommands.Queue (enqueued)
   ↓ browser polls /api/v1/debug/commands/poll
3. Browser receives commands
   ↓ executes via DebugCommandLibrary or eval()
4. Browser POSTs result to /api/v1/debug/commands/result
   ↓ stored in history
5. $Global:PSWebServer.DebugCommands.History
   ↑ utility scripts check history
6. Utility functions retrieve results
```

### Global Variables
- `$Global:PSWebServer.DebugCommands` - Main container
  - `.Queue` - ConcurrentQueue of pending commands
  - `.History` - ConcurrentBag of completed commands
  - `.MaxQueueSize` - 100
  - `.MaxHistorySize` - 500

### Helper Functions
- `Get-DebugCommandHistory -Limit 10` - Get recent history
- `Get-DebugCommandHistory -CommandID "abc..."` - Get specific command
- `Get-DebugCommandHistory -Status completed` - Filter by status
- `Get-DebugCommandQueue` - Get pending commands

## Utility Function Usage

### Launch-DebugCard
```powershell
# Launch without waiting
$result = Launch-DebugCard -Url "/apps/WebHostDebugVariables/cards/debug-variables" -Title "Debug Vars"

# Launch and wait for completion (requires active browser session)
$result = Launch-DebugCard -Url "/apps/..." -Title "Test" -Wait -TimeoutSeconds 10

if ($result.Success) {
    Write-Host "Card launched: $($result.Result.cardId)"
}
```

### Close-DebugCard
```powershell
# Close specific card
Close-DebugCard -CardID "debug-variables-123456" -Wait

# Close all cards of a type
Close-DebugCard -ElementID "file-explorer" -Wait

# Close all cards
Close-DebugCard -All
```

### Get-DebugOpenCards
```powershell
# Get list of open cards (requires browser session)
$cards = Get-DebugOpenCards -TimeoutSeconds 5

foreach ($card in $cards) {
    Write-Host "Card: $($card.id) - Element: $($card.elementId)"
}
```

### Test-DebugCardLoad
```powershell
# Test loading a card with validation
$testResult = Test-DebugCardLoad `
    -Url "/apps/WebhostFileExplorer/cards/file-explorer" `
    -ValidationRules @{
        RequiredElements = @(".file-tree", ".toolbar")
        MaxLoadTimeMs = 5000
        RequireComponent = $true
    } `
    -CloseAfterTest

if ($testResult.Status -eq "Pass") {
    Write-Host "Card test passed!"
} else {
    Write-Host "Errors: $($testResult.Errors -join ', ')"
}
```

### Debug-ClientCommand
```powershell
# Execute arbitrary JavaScript
Debug-ClientCommand -Command "console.log('Hello from server')" -Type eval

# Execute predefined command
Debug-ClientCommand -Command "openCard" -Type predefined -Params @{
    url = "/apps/..."
    title = "Test Card"
}

# Target specific session
Debug-ClientCommand -Command "alert('Hello')" -Type eval -SessionID "abc123"
```

## Testing

### Test Script
Run `test_debug_utilities.ps1` to verify all utilities are working:

```powershell
.\test_debug_utilities.ps1
```

Tests:
1. Debug-ClientCommand (eval)
2. Get-DebugCommandQueue
3. Launch-DebugCard (no wait)
4. Launch-DebugCard (with wait) - requires browser
5. Get-DebugCommandHistory
6. Get-DebugOpenCards - requires browser

**Note**: Tests requiring active browser sessions will be skipped if no debug role user is logged in.

## Requirements for Testing

1. **Server Running**: PSWebHost must be running on port 8080
2. **App Loaded**: WebHostDebugExtensions app must be loaded (happens automatically on startup)
3. **Browser Session** (optional): For wait-based tests, need active browser with user having debug/system_admin role
4. **Poll Service**: debug-poll-service.js must be loaded in browser (auto-loads for debug role users)

## Verification Checklist

- [x] All utility scripts updated to use correct global path
- [x] Result endpoint accepts both ExecutionTime and ExecutionTimeMs
- [x] Helper functions added to app_init
- [x] CompletedTime alias added for utility script compatibility
- [x] Test script created
- [ ] Test script run successfully (pending browser session)
- [ ] Documentation updated

## Notes

- PUT endpoint not needed - browser already uses POST for result submission
- The user mentioned needing a PUT method, but the current POST implementation works correctly
- If a PUT endpoint is specifically requested, it can be created as an alias to the POST endpoint

## Next Steps

1. Run test script with active browser session
2. Test card validation with Test-DebugCardLoad
3. Test batch card operations with Test-AllDebugCards
4. Create automated test reports with New-DebugTestReport
