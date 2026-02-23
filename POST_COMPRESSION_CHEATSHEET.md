# Post-Compression Cheatsheet - PSWebHost Debug System

**Date**: 2026-02-02
**Context**: File-based command queue system implementation and card testing

---

## 🔑 CRITICAL FIXES MADE

### 1. PSCustomObject Property Assignment (MUST REMEMBER!)
**Location**: `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/poll/get.ps1:60-64`

```powershell
# ❌ WRONG - This FAILS with "property cannot be found on this object"
$cmd.Status = 'executing'
$cmd.ExecutedAt = $now.ToString('o')

# ✅ CORRECT - Use Add-Member for PSCustomObject from ConvertFrom-Json
$cmd | Add-Member -MemberType NoteProperty -Name 'Status' -Value 'executing' -Force
$cmd | Add-Member -MemberType NoteProperty -Name 'ExecutedAt' -Value $now.ToString('o') -Force
```

**Why**: `ConvertFrom-Json` returns immutable `PSCustomObject`. Cannot assign properties directly.

---

### 2. Inbox File Location (Recursive Search)
**Location**: `apps/WebHostDebugExtensions/system/utility/Debug_Client_Command_Enqueue.ps1:137`

```powershell
# ❌ WRONG - Only looks in specific session folder
$inboxFile = Join-Path $sessionInbox "$commandID.json"

# ✅ CORRECT - Search recursively since sessionID may differ
$inboxFile = Get-ChildItem -Path $inboxRoot -Filter "$commandID.json" -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
```

**Why**: Browser may write results to different folder structure (sessionID from bearer token auth may be null). Recursive search finds files regardless of location.

---

### 3. Command Acknowledgment Pattern
**Locations**:
- `apps/WebHostDebugExtensions/public/elements/debug-console/component.js:60-88`
- `public/test-file-queue.html:219-236`

```javascript
// Send "received" status BEFORE execution
await fetch('/apps/WebHostDebugExtensions/api/v1/debug/commands/result', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
        CommandID: cmd.CommandID,
        Status: 'received',  // ← Acknowledge receipt
        Result: null,
        Error: null,
        ExecutionTimeMs: 0
    })
});

// Then execute command...
// Then send final result with Status: 'completed' or 'failed'
```

**Why**: User requested acknowledgment before execution to track command lifecycle.

---

### 4. Browser Refresh Handling
**Location**: `test_card_operations.ps1:197-208`

```powershell
# ❌ WRONG - Wait for result from refresh command
$result = & $EnqueueScript -Command "location.reload()" -Type eval -SessionID all -Wait

# ✅ CORRECT - Don't wait (page reloads before result POST completes)
$result = & $EnqueueScript -Command "setTimeout(() => location.reload(), 500); 'Refresh scheduled'" -Type eval -SessionID all
# Note: No -Wait parameter!
```

**Why**: Browser refresh causes page reload before result POST completes. This is expected behavior.

---

### 5. Script Function Calls
**Location**: `apps/WebHostDebugExtensions/system/utility/Test-AllDebugCards.ps1:103`

```powershell
# ❌ WRONG - Call as function when script is executable
$allCards = Get-DebugMenuCards @discoverParams

# ✅ CORRECT - Call as script with & operator
$allCards = & "$PSScriptRoot\Get-DebugMenuCards.ps1" @discoverParams
```

**Why**: Scripts were converted from function format to executable format. Must invoke with `&` operator.

---

## 📁 FILE-BASED COMMAND QUEUE SYSTEM

### Architecture
```
PowerShell Script → outbox/[sessionid]/[commandid].json
                         ↓
                    Browser polls
                         ↓
                    Delete from outbox
                         ↓
                    Send "received" ack → inbox/[sessionid]/[commandid].json
                         ↓
                    Execute command
                         ↓
                    Send final result → inbox/[sessionid]/[commandid].json
                         ↓
                    PowerShell reads result (if -Wait)
```

### Directory Structure
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

### Command Statuses
- `pending` - In outbox, waiting for browser pickup
- `executing` - Delivered to browser (added by poll endpoint)
- `received` - Browser acknowledged receipt (before execution)
- `completed` - Successfully executed
- `failed` - Execution error

### Usage
```powershell
# Send command and wait for result
$result = .\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "console.log('Hello!')" `
    -Type eval `
    -SessionID all `
    -Wait `
    -TimeoutSeconds 30

if ($result.Success) {
    Write-Host "Result: $($result.Result)"
}
```

---

## 🎴 PREDEFINED COMMANDS

**Location**: `apps/WebHostDebugExtensions/public/elements/debug-console/commands.js`

**Critical**: For predefined commands to work, `commands.js` MUST be loaded!

```html
<!-- Add to any page using predefined commands -->
<script src="/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js"></script>
```

### Key Commands
- `openCard` - Open a card: `{url: "/path", title: "Title"}`
- `closeCard` - Close card: `{cardId: "id"}` or `{all: true}`
- `validateCard` - Validate card state: `{cardId: "id"}`
- `dumpState` - Get app state
- `browserInfo` - Get browser info
- `listCards` - List all open cards

---

## 🧪 CARD TESTING

### Test All Cards
```powershell
# Using file-based discovery (no PSWebServer.Apps needed)
.\test_cards_file_based.ps1 -SessionID all -TimeoutSeconds 15
```

### Test Results from Last Run
- **Total cards discovered**: 33
- **Passed**: 5 cards (Linux Services, Chart Builder, Heatmaps, Audit Log, Server Metrics)
- **Failed/Timed out**: 28 cards
- **Pass rate**: ~15%

### Known Issues
1. **Most cards timeout after 15 seconds** - `openCard` is async and may take time to fetch/render
2. **Browser must be on main app page** - Standalone test-file-queue.html doesn't have `window.openCard`
3. **SessionID mismatch** - Results may be written to wrong folder if sessionID is null

---

## 📂 CRITICAL FILE LOCATIONS

### Server Endpoints
- `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/poll/get.ps1` - Browser polls for commands
- `apps/WebHostDebugExtensions/routes/api/v1/debug/commands/result/post.ps1` - Browser posts results

### Utility Scripts
- `apps/WebHostDebugExtensions/system/utility/Debug_Client_Command_Enqueue.ps1` - Send commands
- `apps/WebHostDebugExtensions/system/utility/Debug_Command_Cleanup.ps1` - Clean old files
- `apps/WebHostDebugExtensions/system/utility/Get-DebugMenuCards.ps1` - Discover cards (needs PSWebServer.Apps)
- `apps/WebHostDebugExtensions/system/utility/Test-AllDebugCards.ps1` - Test all cards
- `apps/WebHostDebugExtensions/system/utility/Invoke-DebugCardTest.ps1` - Test single card
- `apps/WebHostDebugExtensions/system/utility/Test-DebugCardLoad.ps1` - Validate card load
- `apps/WebHostDebugExtensions/system/utility/Launch-DebugCard.ps1` - Open card
- `apps/WebHostDebugExtensions/system/utility/Close-DebugCard.ps1` - Close card

### Browser Components
- `apps/WebHostDebugExtensions/public/elements/debug-console/component.js` - Main debug console
- `apps/WebHostDebugExtensions/public/elements/debug-console/commands.js` - **PREDEFINED COMMANDS**
- `public/test-file-queue.html` - Standalone test page (NOW includes commands.js)

### Test Scripts
- `test_cards_file_based.ps1` - **NEW** - Test cards using file system discovery
- `test_card_operations.ps1` - Comprehensive card operations test
- `test_live_browser.ps1` - Test live browser commands
- `test_full_cycle.ps1` - End-to-end test

### Documentation
- `FILE_QUEUE_SYSTEM.md` - Complete file-based queue documentation

---

## ⚠️ KNOWN BEHAVIORS & GOTCHAS

### 1. Browser Refresh
- `location.reload()` commands **CANNOT** return results (page reloads)
- **NEVER** use `-Wait` with refresh commands
- Use `setTimeout(() => location.reload(), 500)` to allow acknowledgment

### 2. Post-Refresh Delay
- API calls may fail for 1-2 seconds after refresh while page loads
- This is **normal behavior**

### 3. Command Expiration
- Commands in outbox expire after **60 seconds** if not picked up
- Old files cleaned up by `Debug_Command_Cleanup.ps1`

### 4. Get-DebugMenuCards Requirement
- **REQUIRES** `$Global:PSWebServer.Apps` to be available
- Only works when PSWebServer is running and loaded
- For file-based discovery, use `test_cards_file_based.ps1` instead

### 5. Inbox File Cleanup
- Result files should be deleted after read (line 154 in Debug_Client_Command_Enqueue.ps1)
- Old result files may pile up if cleanup fails
- Run cleanup script: `.\apps\WebHostDebugExtensions\system\utility\Debug_Command_Cleanup.ps1`

---

## 🔧 COMMON OPERATIONS

### Clean Up Old Command Files
```powershell
.\apps\WebHostDebugExtensions\system\utility\Debug_Command_Cleanup.ps1 `
    -OutboxMaxAgeMinutes 30 `
    -InboxMaxAgeMinutes 120
```

### Open a Card via File Queue
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

### Test Card Load
```powershell
.\apps\WebHostDebugExtensions\system\utility\Test-DebugCardLoad.ps1 `
    -Url "/apps/WebHostMetrics/cards/server-heatmap" `
    -ExpectedTitle "Server Metrics" `
    -SessionID all
```

### Monitor Queue Size
```powershell
$outbox = "PsWebHost_Data\apps\WebHostDebugExtensions\outbox"
$inbox = "PsWebHost_Data\apps\WebHostDebugExtensions\inbox"

$outboxCount = (Get-ChildItem $outbox -Recurse -File).Count
$inboxCount = (Get-ChildItem $inbox -Recurse -File).Count

Write-Host "Outbox: $outboxCount files, Inbox: $inboxCount files"
```

---

## 🐛 TROUBLESHOOTING

### Commands Not Executing
1. Check browser is open and polling (green indicator on test page)
2. Verify files appear in outbox: `ls PsWebHost_Data\apps\WebHostDebugExtensions\outbox\*\*.json`
3. Check server logs for poll errors
4. Verify browser console for JavaScript errors
5. Ensure commands.js is loaded if using predefined commands

### Results Not Returning
1. Check files appear in inbox: `ls PsWebHost_Data\apps\WebHostDebugExtensions\inbox\*\*.json`
2. Verify browser can POST to result endpoint (check authentication)
3. Check timeout isn't too short (increase `-TimeoutSeconds`)
4. Look for "received" acknowledgment first (partial success)
5. Check sessionID mismatch (result in wrong folder)

### Cards Timing Out
1. Increase timeout: `-TimeoutSeconds 30` or higher
2. Verify browser is on main app page (not standalone test page)
3. Check card URL is valid and accessible
4. Verify `window.openCard` function is available
5. Test simpler commands first (e.g., `eval: "1+1"`)

### Get-DebugMenuCards Not Found
```powershell
# Instead of calling as function:
$allCards = Get-DebugMenuCards

# Call as script:
$allCards = & ".\apps\WebHostDebugExtensions\system\utility\Get-DebugMenuCards.ps1"
```

---

## 📊 CARD TEST RESULTS SUMMARY

### Passed Cards (5/33 = 15%)
1. ✅ Linux Services - `/apps/linuxadmin/cards/linux-services`
2. ✅ Chart Builder - `/apps/uplot/api/v1/ui/elements/uplot-home`
3. ✅ Heatmaps - `/apps/uplot/api/v1/ui/elements/heatmap`
4. ✅ Audit Log - `/apps/vault/api/v1/audit`
5. ✅ Server Metrics - `/apps/WebHostMetrics/cards/server-heatmap`

### Failed/Timed Out Cards (28/33 = 85%)
Most cards timed out after 15 seconds. Possible causes:
- `openCard` async operation taking too long
- Card rendering/fetching delays
- Browser not responding quickly enough
- Insufficient timeout duration

**ACTION NEEDED**: Investigate why most cards timeout. Consider:
1. Increasing timeout to 30-60 seconds
2. Testing individual cards to isolate issues
3. Checking card endpoints for errors
4. Validating `window.openCard` implementation

---

## 🎯 NEXT STEPS

1. ✅ File-based queue system implemented and tested
2. ✅ Acknowledgment pattern added (received → completed)
3. ✅ Browser refresh handling fixed
4. ✅ Test scripts updated to call executables properly
5. ⏳ Card testing - low pass rate, needs investigation
6. ⏳ Increase timeout and re-test all cards
7. ⏳ Fix cards that consistently fail
8. ⏳ Add automated cleanup schedule

---

## 💡 IMPORTANT REMINDERS

1. **ALWAYS use Add-Member for PSCustomObject** from ConvertFrom-Json
2. **NEVER wait for browser refresh commands** (page reloads)
3. **ALWAYS load commands.js** when using predefined commands
4. **Use recursive search** when looking for inbox files
5. **Call scripts with &** operator when converted from function format
6. **Increase timeouts** for async operations like openCard
7. **Clean up old files** regularly to prevent pile-up

---

## 📝 DOCUMENTATION FILES

- `FILE_QUEUE_SYSTEM.md` - Complete file-based queue documentation
- `POST_COMPRESSION_CHEATSHEET.md` - This file
- `CARD_VALIDATION_ANALYSIS_2026-02-02.md` - Card validation analysis (if exists)
- `CARD_FIXES_2026-02-02.md` - Card fixes log (if exists)
- `VALIDATION_REPORT_2026-02-02.md` - Validation report (if exists)

---

**END OF CHEATSHEET**

*Generated: 2026-02-02*
*Context: File-based queue implementation and card testing session*
