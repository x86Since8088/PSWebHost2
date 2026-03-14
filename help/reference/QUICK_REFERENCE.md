# PSWebHost Debug System - Quick Reference

**Last Updated**: 2026-02-02
**Full Details**: See `POST_COMPRESSION_CHEATSHEET.md` and `FILE_QUEUE_SYSTEM.md`

---

## =4 CRITICAL FIXES TO REMEMBER

### 1. PSCustomObject from ConvertFrom-Json
```powershell
# L WRONG
$obj.NewProperty = "value"

#  CORRECT
$obj | Add-Member -MemberType NoteProperty -Name 'NewProperty' -Value 'value' -Force
```

### 2. Browser Refresh Commands
```powershell
# L WRONG - Will timeout (page reloads)
& $EnqueueScript -Command "location.reload()" -Type eval -Wait

#  CORRECT - Don't wait
& $EnqueueScript -Command "location.reload()" -Type eval
```

### 3. Script Invocation (When Converted from Functions)
```powershell
# L WRONG
$result = Get-DebugMenuCards

#  CORRECT
$result = & "$PSScriptRoot\Get-DebugMenuCards.ps1"
```

---

## =� File-Based Queue System

**Architecture**: PowerShell writes to `outbox/` � Browser polls � Executes � Posts to `inbox/`

**Directory**: `PsWebHost_Data/apps/WebHostDebugExtensions/outbox|inbox/`

**Command Lifecycle**: pending � executing � received � completed/failed

**Details**: See `FILE_QUEUE_SYSTEM.md` for full documentation

---

## <� Common Commands

### Send Command
```powershell
.\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1 `
    -Command "openCard" -Type predefined `
    -Params @{url="/path"; title="Title"} `
    -SessionID all -Wait -TimeoutSeconds 30
```

### Test Browser Connection
```powershell
.\diagnose_browser_connection.ps1
```

### Clean Old Files
```powershell
.\apps\WebHostDebugExtensions\system\utility\Debug_Command_Cleanup.ps1 `
    -OutboxMaxAgeMinutes 30 -InboxMaxAgeMinutes 120
```

---

## <� Card Loading Patterns

### Normal Card (React Component)
**Endpoint Returns**: `Content-Type: application/json`
```json
{
    "scriptPath": "/apps/myapp/public/elements/mycard/component.js",
    "title": "My Card"
}
```
**Result**: Loads React component, renders dynamically

### HTML Card
**Endpoint Returns**: `Content-Type: text/html`
```html
<!DOCTYPE html><html>...</html>
```
**Result**: Displays HTML content directly in card

**Note**: Both patterns are valid. System auto-detects based on Content-Type.

---

## =' Predefined Commands (NEW)

**Must load**: `commands.js` in page
```html
<script src="/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js"></script>
```

### Card Management (UPDATED)
- `openCard` - `{url, title}` - Opens a card
- `closeCard` - `{cardId}` or `{all: true}` - Closes specific/all cards
- **`closeAllCards`** - **NEW** - No params, closes all open cards
- `validateCard` - `{cardId}` - Validates card state
- **`getCardCount`** - **NEW** - Returns count and IDs of open cards
- **`waitForCardLoad`** - **NEW** - `{cardId, timeoutMs}` - Waits for card to finish loading

### DOM/Debug
- `dumpState` - Get app state
- `browserInfo` - Browser details
- `listCards` - All open cards
- `querySelector` - `{selector}` - Query DOM elements

**Full List**: See `commands.js` (40+ commands)

---

## = Troubleshooting

### Commands Not Returning Results
1. **Check browser is open** - Must have active browser tab
2. **Verify polling** - Commands disappear from outbox?
3. **Check inbox** - `ls PsWebHost_Data\apps\WebHostDebugExtensions\inbox\*\*.json`
4. **Test connectivity** - `.\diagnose_browser_connection.ps1`

### Cards Timing Out
1. **Increase timeout** - `-TimeoutSeconds 45`
2. **Check card endpoint** - Test URL directly in browser
3. **Close other cards first** - Too many open cards cause delays
4. **Use closeAllCards** - `closeAllCards` predefined command before testing

### Browser Not Polling
1. **Refresh browser** - Reload main app page
2. **Check authentication** - Re-login if needed
3. **Verify commands.js loaded** - Check browser console for errors

---

## =� Test Scripts

### Continuous Card Testing with Logging (NEW - BEST FOR QA)
```powershell
.\test_cards_continuous.ps1 -DelayBetweenCards 5 -MaxCards 10
```
**Does**: Opens each card, validates, logs all QA data to server
**Logs to**: `CardValidation`, `IframeCardLoad` categories
**Works with**: Both component and iframe cards

### Iframe Loader Testing
```powershell
.\test_iframe_loader.ps1
```
**Does**: Tests iframe-based cards, verifies loader script injection
**Logs to**: `IframeCardLoad` category with DOM analysis

### Automated Card Validation Page (HTML-based)
```powershell
.\test_card_validation_page.ps1
```
**Does**: Opens HTML validation page that auto-runs tests and submits results to server log
**URL**: `/public/card-validation-test.html`
**Direct**: `window.openCard("/public/card-validation-test.html")`
**Log Category**: `CardValidation`
**View Logs**: Open System Log card, filter by "CardValidation"

### Sequential Card Testing (PowerShell-based)
```powershell
.\test_cards_improved.ps1 -DelayBetweenCards 3
```
**Does**: Opens each card, validates DOM, checks for errors, closes before next

### Browser Connection Test (RUN THIS FIRST)
```powershell
.\diagnose_browser_connection.ps1
```
**Does**: Verifies browser is connected and polling

### File-Based Discovery
```powershell
.\test_cards_file_based.ps1 -TimeoutSeconds 30
```
**Does**: Discovers cards from menu.yaml, tests all

---

## =� Key Files

### Utilities
- `Debug_Client_Command_Enqueue.ps1` - Send commands
- `Debug_Command_Cleanup.ps1` - Clean old files

### Browser Components
- `commands.js` - **CRITICAL** - Predefined commands library (UPDATED)
- `component.js` - Debug console with polling
- `psweb_spa.js` - Main SPA with card management

### Test/Diagnostic Scripts
- `diagnose_browser_connection.ps1` - Check browser connectivity
- `test_cards_sequential_with_validation.ps1` - Sequential testing

### Documentation
- **`QUICK_REFERENCE.md`** - This file (concise)
- `FILE_QUEUE_SYSTEM.md` - Complete queue system docs
- `POST_COMPRESSION_CHEATSHEET.md` - Comprehensive reference (~8KB)
- `CARD_TIMEOUT_INVESTIGATION_REPORT.md` - Timeout analysis

---

## =� Best Practices

1. **Always close cards** - Use `closeAllCards` between tests
2. **Test browser first** - Run `diagnose_browser_connection.ps1`
3. **Use reasonable timeouts** - 30-45s for card operations
4. **Clean up regularly** - Run cleanup script periodically
5. **Sequential testing** - Test one card at a time to avoid overload

---

**Need Help?** Start with `diagnose_browser_connection.ps1` to verify system status.
