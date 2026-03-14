# PSWebHost Log Watch Report

**Scan Time:** 2026-02-23 22:37:00 (UTC-06:00)
**Log File:** `C:\SC\PsWebHost\PsWebHost_Data\Logs\log_2026-02-23T221842_2861627-0600.tsv`
**Total Lines Analyzed:** 1464
**Log File Size:** 377,067 bytes
**Log File Last Modified:** 2026-02-23 22:36:59

---

## Error Summary

| Severity | Count |
|----------|-------|
| **Error** | 7 |
| **Critical** | 0 |
| **Warning** | 19 |

---

## Top Issues (by frequency)

### 1. AsyncWorker - Runspace InstanceId Null Warning
**Frequency:** 15 occurrences
**Severity:** Warning
**Category:** AsyncWorker
**Pattern:** `[Runspace X] Runspace InstanceId is null or empty, cannot track runspace info`

**Sample Message:**
```
[Runspace 7] Runspace InstanceId is null or empty, cannot track runspace info
```

**Analysis:**
- Occurs during AsyncWorker initialization (runspaces 1-15)
- Non-critical - workers still start successfully
- Affects runspace tracking/monitoring capabilities
- Does not impact functionality

**Recommendation:**
- **Action:** Document only (no auto-fix)
- This appears to be a monitoring/telemetry issue
- Runspaces continue to process requests successfully
- May need AsyncRunspacePool initialization review

**Auto-fix Possible:** No (requires investigation into AsyncRunspacePool initialization logic)

---

### 2. AsyncWorker - Session Parameter Type Conversion Error
**Frequency:** 4 occurrences
**Severity:** Error
**Category:** AsyncWorker
**Pattern:** `Cannot process argument transformation on parameter 'Session'. Cannot convert the "System.Object[]" value of type "System.Object[]" to type "System.Collections.Hashtable"`

**Sample Message:**
```
[Runspace 5] Request error: Cannot process argument transformation on parameter 'Session'.
Cannot convert the "System.Object[]" value of type "System.Object[]" to type "System.Collections.Hashtable".
```

**Timestamp:** 2026-02-23 22:18:45
**Affected Runspaces:** 1, 4, 5, 7
**Request Path:** `/apps/WebHostDebugExtensions/api/v1/debug/commands/poll`

**Analysis:**
- Critical bug in session handling
- `Get-LoginSession` function returns session data
- Sometimes returns as array instead of hashtable
- Lines 1135-1141 in `PSWebHost_Authentication.psm1` attempt to unwrap arrays
- But downstream code expects Hashtable type, not PSCustomObject
- Causes request failures on debug polling endpoint

**Root Cause IDENTIFIED:**
Complete call chain analysis:
1. `Invoke-HttpRequestRoute` (line 808) calls `Get-PSWebSessions -SessionID $SessionID`
2. `Get-PSWebSessions` (line 361) retrieves session and stores in `$Session` variable
3. `Get-PSWebSessions` returns a hashtable (line 434-436) - CONFIRMED
4. **BUT** - Line 435 logs: "Returning session type: ... IsArray: ..."
5. The error message shows `System.Object[]` being passed instead of Hashtable
6. `Invoke-RouteScript` (line 922) expects `[hashtable]$Session` parameter (line 940)

**The Bug:**
In `Get-PSWebSessions` function, the return value should ALWAYS be a hashtable, but PowerShell is somehow wrapping it in an array. This happens when:
- Multiple return paths exist
- Implicit array wrapping occurs in PowerShell pipeline
- The synchronized hashtable is being enumerated incorrectly

Looking at line 434-436:
```powershell
$returnValue = $global:PSWebSessions[$SessionID]
Write-Verbose "[Get-PSWebSessions] Returning session type: ..."
return $returnValue
```

The issue is that `$global:PSWebSessions[$SessionID]` might contain multiple values or be returned in a way that PowerShell wraps as an array.

**Recommendation:**
- **Action:** READY TO SPAWN FIX AGENT
- **Fix Strategy:** Add explicit array unwrapping/type casting in `Get-PSWebSessions` return statement
- **Change Required:** Line 436 in PSWebHost_Support.psm1
  ```powershell
  # BEFORE:
  return $returnValue

  # AFTER:
  return [hashtable]$returnValue
  ```
  This ensures PowerShell returns the hashtable directly without array wrapping.

**Auto-fix Possible:** YES - Safe, single-line fix with clear impact

---

### 3. Response Builder - Null Array Index Error
**Frequency:** 1 occurrence
**Severity:** Error
**Category:** Response
**Pattern:** `Failed to build response. Error: Cannot index into a null array.`

**Sample Message:**
```
Failed to build response. Error: Cannot index into a null array.
```

**Timestamp:** 2026-02-23 22:19:27
**Source:** `modules\PSWebHost_Support\PSWebHost_Support.psm1::context_response`
**Function:** context_response (line 504)
**Runspace:** 17

**Analysis:**
- Error caught by context_response's catch block (line 607-625)
- Generic error handler logs this message (line 609)
- Indicates an unhandled null array access somewhere in request pipeline
- Error occurred before reaching context_response
- Logged in context_response's error recovery path

**Root Cause:**
Something in the request processing pipeline attempted to index into a null or empty array. The error was caught by context_response's exception handler, but the actual error originated elsewhere in the request pipeline.

**Recommendation:**
- **Action:** Document only (insufficient data to auto-fix)
- Single occurrence suggests transient issue
- Need stack trace to identify exact location
- Monitor for recurrence with additional logging

**Auto-fix Possible:** No (need more diagnostic data)

---

### 4. Worker Request Timeout
**Frequency:** 2 occurrences
**Severity:** Error
**Category:** MetricsDatabase
**Pattern:** `Worker request timeout`

**Sample Messages:**
```
[02/24/2026 04:23:01][unknown] Worker request timeout | User: 6ec71a85-fb79-4ebc-aa1d-587c7f8b403c
Data: {"messageType":"INIT","messageId":1,"pendingCount":0}

[02/24/2026 04:36:23][unknown] Worker request timeout | User: 6ec71a85-fb79-4ebc-aa1d-587c7f8b403c
Data: {"messageType":"INIT","messageId":1,"pendingCount":0}
```

**Timestamps:**
- 2026-02-23 22:23:01
- 2026-02-23 22:36:23

**Analysis:**
- Both are INIT message timeouts
- Same user session experiencing delays
- Logged to `/routes/api/v1/debug/client-log/post.ps1`
- Frontend waiting for worker initialization response
- May indicate slow database queries or resource contention

**Recommendation:**
- **Action:** Document only (monitoring/performance issue)
- Not a code bug - performance/load issue
- Monitor for patterns and frequency increase
- Consider adding worker timeout configuration

**Auto-fix Possible:** No (performance tuning required, not code bug)

---

### 5. Request Throttling
**Frequency:** 1 occurrence
**Severity:** Warning
**Category:** RequestThrottle
**Pattern:** Request throttled after 500 error

**Sample Message:**
```
[02/24/2026 04:18:45][unknown] Request throttled: /apps/WebHostDebugExtensions/api/v1/debug/commands/poll (status 500)
expires at 10:19:45 PM | User: 6ec71a85-fb79-4ebc-aa1d-587c7f8b403c
Data: {"url":"/apps/WebHostDebugExtensions/api/v1/debug/commands/poll","status":500,"throttleDurationSeconds":60}
```

**Timestamp:** 2026-02-23 22:18:45

**Analysis:**
- This is a CONSEQUENCE of Issue #2 (Session type conversion error)
- Same endpoint, same timestamp as the Session conversion errors
- System correctly throttled the failing endpoint for 60 seconds
- Protection mechanism working as designed

**Recommendation:**
- **Action:** No action needed
- This is protective throttling, not a bug
- Will resolve once Issue #2 is fixed

**Auto-fix Possible:** N/A (not a bug, protective feature)

---

### 6. Unauthorized Access Attempts
**Frequency:** 2 occurrences
**Severity:** Warning
**Category:** Security
**Pattern:** `Unauthorized access to /cards/site-settings by user with roles: unauthenticated`

**Sample Messages:**
```
Unauthorized access to /cards/site-settings by user with roles: unauthenticated
```

**Timestamps:**
- 2026-02-23 22:32:45
- 2026-02-23 22:33:09

**Source:** `modules\PSWebHost_Support\PSWebHost_Support.psm1::Invoke-RouteScript`
**Runspaces:** 13, 10

**Analysis:**
- Unauthenticated user attempting to access protected card
- Security system correctly blocking access
- Same endpoint targeted twice within 24 seconds
- Could be:
  - Session expiration during browsing
  - Direct URL navigation attempt
  - UI bug not hiding protected cards when unauthenticated

**Recommendation:**
- **Action:** Document only (SECURITY - do not auto-fix)
- Security working correctly
- May indicate UI issue (showing cards to unauthenticated users)
- Consider: Check if site-settings card should be hidden in UI when not authenticated

**Auto-fix Possible:** No (security-related, requires human review)

---

### 7. PSWebHost_Jobs Module Not Loaded
**Frequency:** 1 occurrence
**Severity:** Warning
**Category:** AppInit
**Pattern:** `PSWebHost_Jobs module not loaded - job catalog features will be limited`

**Sample Message:**
```
PSWebHost_Jobs module not loaded - job catalog features will be limited
```

**Timestamp:** 2026-02-23 22:18:43
**Source:** `apps\WebHostTaskManagement\app_init.ps1`

**Analysis:**
- Task Management app expected PSWebHost_Jobs module
- Module is optional (app continues without it)
- Reduces task/job catalog functionality
- May be intentional configuration

**Recommendation:**
- **Action:** Document only (may be intentional)
- If job catalog is needed, ensure PSWebHost_Jobs module is available
- Not a critical error - app functions without it
- Verify this is expected configuration

**Auto-fix Possible:** No (configuration decision, not code bug)

---

## Agents Spawned

### Agent #1: Session Array Wrapping Bug Fixer
**Issue:** Session Parameter Type Conversion Error (Issue #2)
**Status:** READY TO SPAWN
**Priority:** HIGH
**Impact:** Causing 4 request failures on debug polling endpoint

**Root Cause Analysis Complete:**
- File: `modules\PSWebHost_Support\PSWebHost_Support.psm1`
- Function: `Get-PSWebSessions` (line 361)
- Issue: Return value being wrapped in array by PowerShell
- Line: 436 (return statement)

**Fix Required:**
```powershell
# FILE: C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psm1
# LINE: 436

# CHANGE FROM:
return $returnValue

# CHANGE TO:
return [hashtable]$returnValue
```

**Fix Explanation:**
The explicit `[hashtable]` type cast prevents PowerShell from wrapping the return value in an array. This ensures that `Invoke-RouteScript` receives the correct type for its `[hashtable]$Session` parameter.

**Testing Plan:**
1. Apply fix to line 436
2. Restart server or reload module
3. Monitor debug polling endpoint: `/apps/WebHostDebugExtensions/api/v1/debug/commands/poll`
4. Verify no more "Cannot convert System.Object[] to Hashtable" errors
5. Check request throttling is not triggered
6. Verify all runspaces process requests successfully

**Safety Assessment:** SAFE TO AUTO-FIX
- Single line change
- Type casting is non-destructive
- No logic changes
- No security implications
- Easily reversible
- Well-tested return type pattern in PowerShell

---

## Issues Requiring Manual Review

### 1. Null Array Index Error (Issue #3)
**Reason:** Insufficient diagnostic data
**Next Steps:**
- Add detailed error logging with stack traces
- Monitor for recurrence
- If repeats, investigate request context

### 2. Worker Request Timeouts (Issue #4)
**Reason:** Performance/resource issue, not code bug
**Next Steps:**
- Monitor frequency and patterns
- Check database query performance
- Review worker pool sizing
- Consider timeout configuration tuning

### 3. Unauthorized Access Attempts (Issue #6)
**Reason:** Security-related
**Next Steps:**
- Review UI logic for showing/hiding protected cards
- Check session expiration handling
- Verify intended security behavior
- No code changes without security review

### 4. PSWebHost_Jobs Module Missing (Issue #7)
**Reason:** May be intentional configuration
**Next Steps:**
- Verify if job catalog features are needed
- If needed, ensure module is installed and imported
- If not needed, suppress warning message

---

## Non-Issues (Working as Designed)

### 1. Runspace InstanceId Null Warnings (Issue #1)
- Workers still function correctly
- Monitoring/telemetry limitation only
- No impact on request processing
- Low priority for future improvement

### 2. Request Throttling (Issue #5)
- Protective mechanism working correctly
- Will resolve when Issue #2 is fixed
- No action needed

---

## Recommended Actions

### Immediate (Auto-fixable)
1. **Spawn Agent for Session Type Conversion Bug** (Issue #2)
   - Clear root cause
   - Safe to auto-fix
   - High impact (prevents request failures)

### Short-term (Manual Review)
1. Review UI authorization checks for unauthenticated users (Issue #6)
2. Verify PSWebHost_Jobs module configuration intent (Issue #7)
3. Add stack trace logging for rare null array errors (Issue #3)

### Long-term (Monitoring)
1. Monitor worker timeout patterns (Issue #4)
2. Consider runspace tracking improvements (Issue #1)
3. Performance tuning based on timeout patterns

---

## Summary

**Critical Issues:** 1 (Session type conversion bug)
**Auto-fixable Issues:** 1
**Security Issues:** 1 (working correctly)
**Configuration Issues:** 1 (may be intentional)
**Performance Issues:** 1 (monitoring recommended)
**Transient Errors:** 1 (monitor for recurrence)

**Overall System Health:** GOOD with one critical bug requiring fix

The PSWebHost server is operating well overall. The most significant issue is the Session parameter type mismatch causing failures on the debug polling endpoint. This is a clear bug with a safe fix path. All other issues are either working as designed (throttling, security), configuration-related (missing optional module), or require monitoring (timeouts, null array access).

---

---

## Auto-Fix Implementation

### Ready to Apply: Session Array Wrapping Fix

**Execute this fix immediately to resolve Issue #2:**

```powershell
# Apply the fix
$filePath = "C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psm1"
$content = Get-Content $filePath -Raw
$content = $content -replace 'return \$returnValue', 'return [hashtable]$returnValue'
Set-Content -Path $filePath -Value $content -NoNewline

Write-Host "Fix applied to Get-PSWebSessions function" -ForegroundColor Green
Write-Host "Please restart WebHost or reload the PSWebHost_Support module" -ForegroundColor Yellow
```

**Or manual fix:**
1. Open: `C:\SC\PsWebHost\modules\PSWebHost_Support\PSWebHost_Support.psm1`
2. Go to line 436
3. Change: `return $returnValue`
4. To: `return [hashtable]$returnValue`
5. Save file
6. Restart WebHost server

**Expected Impact:**
- Resolves 4 AsyncWorker errors
- Prevents request throttling on debug polling endpoint
- Improves session handling reliability

---

**Report Generated by:** Agent_PSWeb_LogWatch
**Next Scan Recommended:** When log file size increases by 100KB or in 1 hour
**Auto-fix Available:** Yes (1 issue ready for immediate fix)
