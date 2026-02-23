# PSWebHost Card Fixes - 2026-02-01

## Fixed Cards

### 1. apps-manager ✅ FIXED

**Issue:**
```
Failed to fetch metadata for apps-manager: SyntaxError: JSON.parse: unexpected character at line 1 column 1
```

**Root Cause:**
- Endpoint was returning HTML instead of JSON card metadata
- Component.js file didn't exist

**Solution:**
1. **Modified:** `apps/WebHostAppManager/routes/api/v1/ui/elements/apps-manager/get.ps1`
   - Changed from HTML response to proper card metadata JSON
   - Now returns: `{ component, scriptPath, title, description, features }`

2. **Created:** `public/elements/apps-manager/component.js`
   - React component with full apps management UI
   - Fetches data from `/api/v1/apps/list` endpoint
   - Displays app cards with status, version, description

3. **Created:** `public/elements/apps-manager/style.css`
   - Modern card-based layout
   - Grid display for multiple apps
   - Status indicators (enabled/disabled)
   - Responsive design

4. **Created:** `apps/WebHostAppManager/routes/api/v1/apps/list/get.ps1`
   - Data endpoint that returns list of installed apps
   - Returns: `{ apps: [], nodeGuid, totalApps }`

5. **Created:** `apps/WebHostAppManager/routes/api/v1/apps/list/get.security.json`
   - Requires authentication
   - Allows user, admin, debug, system_admin roles

**Test:**
```javascript
// In browser console:
window.cardManager.openCard('apps-manager');
```

**Expected Result:**
- Card opens successfully
- Shows list of installed apps with details
- Each app shows: name, version, description, status, required roles, loaded time

---

### 2. event-stream ✅ FIXED (Previously)

**Issue:**
- Endpoint was returning event data instead of card metadata
- Component registration existed but endpoint was wrong

**Solution:**
- Modified endpoint to return proper card metadata
- Component was already correct

---

## Remaining Issues

### 1. unit-test-runner ❌ NEEDS INVESTIGATION

**Issue:**
```
HTTP/1.1 500 Internal Server Error
```

**Status:**
- Endpoint file looks correct (returns proper JSON metadata)
- Need to check server logs for actual error
- Possible duplicate key issue: "unit-test-runner-1769998362646" appears twice

**Next Steps:**
1. Check server logs for stack trace
2. Verify no duplicate endpoint files
3. Check if card is being registered twice in layout

### 2. iframe-card (Debug Variables) ❌ ARCHITECTURE ISSUE

**Issue:**
```
Failed to fetch metadata for iframe-card: Error: No scriptPath/componentPath in endpoint response
```

**Status:**
- This is actually the Debug Variables viewer
- Uses endpoint `/api/v1/debug/vars` which is a data endpoint, not a card metadata endpoint
- This is an architectural issue - iframe cards work differently

**Next Steps:**
1. Determine if iframe-card should have its own card metadata endpoint
2. Or update card loading logic to handle iframe cards differently
3. May need special handling for cards that load external URLs

### 3. Component Timeouts ⚠️ WARNING

**Issue:**
```
Component title did not mount within 5000ms
Component apps-manager did not mount within 5000ms
Component unit-test-runner did not mount within 5000ms
```

**Status:**
- Cards are taking too long to load/mount
- Could be:
  - Network latency fetching component.js files
  - Component initialization taking too long
  - JavaScript errors preventing mount

**Next Steps:**
1. Increase timeout threshold in card loader
2. Add better error handling during component mount
3. Check for JavaScript errors in browser console

### 4. Duplicate Keys in React Grid ⚠️ WARNING

**Issue:**
```
Warning: Encountered two children with the same key, `unit-test-runner-1769998362646`
```

**Status:**
- React is detecting duplicate keys in the grid layout
- unit-test-runner is appearing twice
- This can cause rendering issues

**Next Steps:**
1. Check layout configuration
2. Search for duplicate card registrations
3. Verify app manifests aren't registering cards multiple times

---

## Testing Strategy

### Automated Testing
Run the automated test script:
```powershell
cd C:\SC\PsWebHost
.\test_all_cards_automated.ps1 -FixIssues -ExportReport
```

### Manual Testing
1. Open PSWebHost in browser
2. Open browser console (F12)
3. Test each fixed card:
```javascript
// Test apps-manager
window.cardManager.openCard('apps-manager');

// Test event-stream
window.cardManager.openCard('event-stream');
```

4. Verify:
   - Card opens without errors
   - UI elements render correctly
   - Data loads properly
   - Interactions work (buttons, inputs)

---

## Files Modified

### Modified Files (2):
1. `apps/WebHostAppManager/routes/api/v1/ui/elements/apps-manager/get.ps1` - Converted to card metadata endpoint
2. `routes/cards/event-stream/get.ps1` - Converted to card metadata endpoint (previous fix)

### Created Files (5):
1. `public/elements/apps-manager/component.js` - React component for apps manager
2. `public/elements/apps-manager/style.css` - Styles for apps manager
3. `apps/WebHostAppManager/routes/api/v1/apps/list/get.ps1` - Data endpoint for apps list
4. `apps/WebHostAppManager/routes/api/v1/apps/list/get.security.json` - Security config for apps list
5. `CARD_FIXES_2026-02-01.md` - This documentation

---

## Summary

**Fixed:** 2 cards (apps-manager, event-stream)
**Authentication Fix:** Fixed apps-manager to use session-based auth instead of API keys
**Remaining Issues:** 2 cards (unit-test-runner, iframe-card) + 2 warnings (timeouts, duplicate keys)

**Next Priority:**
1. Investigate unit-test-runner 500 error (check server logs)
2. Fix duplicate key warning (find where unit-test-runner is registered twice)
3. Determine solution for iframe-card architecture

**Overall Progress:**
- Major JSON parse error fixed for apps-manager
- Proper separation of card metadata vs data endpoints
- Component architecture now consistent with working cards
- Authentication method corrected (session cookies vs Bearer tokens)

---

## Authentication Fix (2026-02-01)

**Issue:**
The apps-manager component was trying to use API Key Bearer token authentication when it should use session-based authentication.

**Root Cause:**
PSWebHost has two authentication methods:
1. **Session cookies** - for browser users who log in via the UI
2. **Bearer tokens** - for programmatic API access

The component was incorrectly trying to use `window.apiKey` (which doesn't exist in normal browser sessions) for Bearer token authentication.

**Solution:**
Changed from manual fetch with Bearer token to PSWebHost's built-in authentication:

```javascript
// BEFORE (incorrect):
const response = await fetch('/api/v1/apps/list', {
    headers: {
        'Authorization': `Bearer ${window.apiKey || localStorage.getItem('apiKey')}`
    }
});

// AFTER (correct):
const response = await window.psweb_fetchWithAuthHandling('/api/v1/apps/list');
```

**File Modified:**
- `public/elements/apps-manager/component.js:13-21` - Changed loadApps() to use session auth
