# Modules Folder Review — Error Handling & Architecture Assessment

**Date:** Generated during codebase refactoring  
**Review Scope:** `modules/` directory (6 core modules)  
**Policy:** No exceptions in runtime code; use `-ErrorAction SilentlyContinue` + `ErrorVariable` for error handling.

---

## Executive Summary

✅ **All runtime modules are COMPLIANT with the no-exception error-handling policy.**

- **0 `-ErrorAction Stop`** in runtime module code
- **0 `throw`** in runtime module code  
- **0 `exit`** in runtime module code
- **20 `throw` occurrences** found only in test helpers (`tests/modules/TestCodeHelpers.psm1`), which are intentionally exempt

**New Standardized Result Helper Available:** `New-PSWebHostResult` (added to `PSWebHost_Support.psm1`) provides a structured result object for standardized error reporting and logging across all modules.

---

## Module Assessment

### 1. **PSWebHost_Support** ✅ COMPLIANT
**Status:** UPDATED with new standardized result helper  
**Key Functions:**
- `Get-RequestBody` — Reads HTTP request bodies with try/catch error handling (existing pattern)
- `ConvertTo-CompressedBase64` — GZip compression helper with try/catch (existing pattern)
- `Set-PSWebSession` — Session management; uses logging via `Write-PSWebHostLog`
- `Get-PSWebSessions` — Retrieves session data from memory or database
- `Write-PSWebHostLog` — Core logging function (non-throwing)
- `Read-PSWebHostLog` — Query logged events
- `context_reponse` — HTTP response builder with try/catch (existing pattern, safe)
- **NEW: `New-PSWebHostResult`** — Standardized result object factory
  - Returns: `@{ ExitCode, Message, Severity, Category, Details, Timestamp }`
  - Logs via `Write-PSWebHostLog` (best-effort, non-throwing)
  - Designed for use by all other modules and route handlers

**Findings:**
- ✅ No `-ErrorAction Stop` found
- ✅ No inappropriate `throw` or `exit` found
- ✅ Existing error patterns use try/catch or Write-Error (acceptable patterns for internal logging)
- ✅ New `New-PSWebHostResult` helper is compliant and ready for adoption

**Recommendations:**
- Encourage other modules to use `New-PSWebHostResult` for consistency
- Document the helper in module documentation for developers

---

### 2. **PSWebHost_Authentication** ✅ COMPLIANT
**Status:** Clean; no risky patterns detected  
**Key Functions:**
- `Get-AuthenticationMethod` — Returns available auth methods (static)
- `Get-AuthenticationMethodForm` — Returns form fields for auth method
- `Get-PSWebHostUser` — Queries users by Email, UserID, or lists all
- `Get-PSWebHostUsers` — Lists all user emails
- `Get-UserAuthenticationMethods` — Retrieves auth providers for a user
- `Get-PSWebHostRole` — Lists roles (all or by user)
- `Invoke-AuthenticationMethod` — Executes Password or Windows authentication
- `Test-IsValidEmailAddress` — Email validation with regex and Unicode checks
- `Test-StringForHighRiskUnicode` — Comprehensive Unicode threat detection
- `Test-IsValidPassword` — Password strength validation
- `Test-LoginLockout` — Rate-limiting and lockout logic
- `Protect-String` / `Unprotect-String` — SecureString encryption/decryption
- `Register-PSWebHostUser` — Creates new users with salt/hash
- `New-PSWebHostUser` — User creation wrapper
- `PSWebLogon` — Logs login events and enforces lockout policies
- `Add-PSWebHostRole`, `Remove-PSWebHostRole`, etc. — Role/Group management

**Error Handling Pattern:**
- Uses `Write-Error` for parameter validation (non-throwing exit)
- Database operations via `Get-PSWebSQLiteData` and `Invoke-PSWebSQLiteNonQuery` (safe)
- No `throw`, `exit`, or `-ErrorAction Stop` detected

**Findings:**
- ✅ No `-ErrorAction Stop`
- ✅ No `throw` or `exit`
- ✅ Parameter validation uses `Write-Error` with `return` (safe pattern)
- ✅ Database calls are isolated and safe

**Recommendations:**
- No changes required; module is well-designed for exception-free operation
- Consider adopting `New-PSWebHostResult` for database operations to standardize error reporting

---

### 3. **PSWebHost_Database** ✅ COMPLIANT
**Status:** Clean; provides SQLite abstraction layer  
**Key Functions:**
- `Get-PSWebSQLiteData` — Executes SELECT queries and returns results
- `Invoke-PSWebSQLiteNonQuery` — Executes INSERT/UPDATE/DELETE queries
- `New-PSWebSQLiteData` — Wrapper for INSERT with data sanitization
- `Sanitize-SqlQueryString` — SQL injection prevention (single-quote escaping)

**Error Handling Pattern:**
- Uses try/catch for database connection errors
- `Write-Error` for parameter validation
- Gracefully returns `$null` on failure instead of throwing

**Findings:**
- ✅ No `-ErrorAction Stop`
- ✅ No `throw` or `exit`
- ✅ Try/catch blocks safely handle SQLite exceptions without re-throwing
- ✅ SQL sanitization prevents injection attacks

**Recommendations:**
- No changes required; module is safe and defensive
- Consider wrapping database error messages in `New-PSWebHostResult` for consistency (optional, as this is a low-level utility)

---

### 4. **PSWebHost_Formatters** ✅ COMPLIANT
**Status:** Clean; provides data transformation utilities  
**Key Functions:**
- `Convert-ObjectToYaml` — Recursive object-to-YAML conversion with depth limits
- `Get-ObjectSafeWalk` — (Incomplete, mostly commented out) Safe object traversal
- `Test-Walkable` — Determines if an object can be traversed
- `Inspect-Object` — Safe object inspection with depth and blacklist controls

**Error Handling Pattern:**
- Uses parameter validation with `Write-Error` and `return` (non-throwing)
- Try/catch blocks for object property access (safe)
- Handles null/error cases gracefully

**Findings:**
- ✅ No `-ErrorAction Stop`
- ✅ No `throw` or `exit`
- ✅ Recursive functions have depth limits to prevent stack overflow
- ✅ All error conditions return safe defaults or graceful errors

**Recommendations:**
- `Get-ObjectSafeWalk` function is incomplete (commented logic); consider either completing it or removing it
- No critical changes needed; module is well-designed

---

### 5. **Sanitization** ✅ COMPLIANT
**Status:** Clean; input validation and path security  
**Key Functions:**
- `Sanitize-HtmlInput` — Removes ANSI escape codes and HTML-encodes
- `Write-RequestSanitizationFail` — Logs sanitization failures
- `Sanitize-FilePath` — Path traversal prevention with base directory validation

**Error Handling Pattern:**
- Uses `Write-Error` for missing parameters (non-throwing)
- Returns structured result objects: `@{ Score = 'pass'|'fail'; Path|Message }`
- No exceptions; graceful failure modes

**Findings:**
- ✅ No `-ErrorAction Stop`
- ✅ No `throw` or `exit`
- ✅ Path traversal defense is robust
- ✅ Returns clear status/error information

**Recommendations:**
- No changes required; module is well-designed for security
- Could benefit from adopting `New-PSWebHostResult` for consistent logging

---

### 6. **smtp** ✅ COMPLIANT
**Status:** Clean; email service wrapper  
**Key Functions:**
- `Send-SmtpEmail` — Sends emails via SMTP with configurable server/credentials

**Error Handling Pattern:**
- Uses `Write-Error` for missing parameters and configuration issues (non-throwing)
- Try/catch for `Send-MailMessage` exceptions with detailed error handling
  - Distinguishes between SMTP errors, authentication failures, and general errors
  - Provides user-friendly error messages with remediation guidance
- No re-throw; errors logged and returned as messages

**Findings:**
- ✅ No `-ErrorAction Stop`
- ✅ No `throw` or `exit`
- ✅ Comprehensive error diagnostics with user guidance
- ✅ Gracefully handles missing config without exception

**Recommendations:**
- No changes required; error handling is thorough and user-friendly
- Consider wrapping email send results in `New-PSWebHostResult` for consistency with other modules

---

## Standardized Result Helper — Usage Guide

The new `New-PSWebHostResult` function provides a standardized way to return results with metadata:

```powershell
# Import function from PSWebHost_Support
Import-Module PSWebHost_Support

# Successful operation
$result = New-PSWebHostResult -ExitCode 0 -Message "User created successfully" -Severity 'Info' -Category 'UserManagement'

# Operation with warnings
$result = New-PSWebHostResult -ExitCode 1 -Message "User created but email not verified" -Severity 'Warning' -Category 'UserManagement' -Details @{ UserID = $uid; Email = $email }

# Error result
$result = New-PSWebHostResult -ExitCode 2 -Message "Failed to create user: database error" -Severity 'Error' -Category 'UserManagement'

# Result properties
$result.ExitCode      # [int] Exit code for caller
$result.Message       # [string] Human-readable message
$result.Severity      # [string] Critical|Error|Warning|Info|Verbose|Debug
$result.Category      # [string] Logical category (e.g., 'UserManagement', 'Auth', 'Database')
$result.Details       # [hashtable|null] Additional context/metadata
$result.Timestamp     # [string] ISO 8601 timestamp
```

**Adoption Strategy:**
1. Use `New-PSWebHostResult` for route handlers and high-level business logic
2. Database and utility modules can continue using current patterns (they already return structured data)
3. Gradually migrate public functions to return standardized results

---

## Architecture Notes

### Error Handling Hierarchy
1. **Database Layer** (`PSWebHost_Database`): Safely wraps SQLite, returns `$null` on error
2. **Service Modules** (`PSWebHost_Authentication`, `Sanitization`, `smtp`): Use `Write-Error` + `return` for validation; try/catch for external calls
3. **Logging Layer** (`PSWebHost_Support`): `Write-PSWebHostLog` and `New-PSWebHostResult` provide structured logging
4. **Route Handlers** (`routes/api/*`): Return HTTP responses with appropriate status codes; no thrown exceptions

### Best Practice Pattern
```powershell
function Invoke-Operation {
    param([string]$Data)

    # 1. Parameter validation (non-throwing)
    if (-not $Data) { Write-Error "Data is required"; return }

    # 2. Execute with error variable
    $result = Get-Something -Data $Data -ErrorAction SilentlyContinue -ErrorVariable err
    if ($err) {
        Write-Verbose "Error occurred: $err"
        return (New-PSWebHostResult -ExitCode 1 -Message $err[0].Exception.Message -Severity 'Error' -Category 'Operation')
    }

    # 3. Return structured result
    return (New-PSWebHostResult -ExitCode 0 -Message "Success" -Details @{ Result = $result })
}
```

---

## Summary Table

| Module | Status | Critical Issues | Minor Issues | Recommendation |
|--------|--------|-----------------|--------------|-----------------|
| PSWebHost_Support | ✅ Clean | None | None | Encourage adoption of `New-PSWebHostResult` helper |
| PSWebHost_Authentication | ✅ Clean | None | None | No changes needed |
| PSWebHost_Database | ✅ Clean | None | None | No changes needed |
| PSWebHost_Formatters | ✅ Clean | Incomplete function (`Get-ObjectSafeWalk`) | None | Consider removing/completing `Get-ObjectSafeWalk` |
| Sanitization | ✅ Clean | None | None | No changes needed |
| smtp | ✅ Clean | None | None | No changes needed |

---

## Action Items

- [ ] **Documentation:** Update developer guide to recommend `New-PSWebHostResult` for public functions
- [ ] **Formatter Module:** Decide whether to complete or remove `Get-ObjectSafeWalk` function
- [ ] **Gradual Adoption:** Migrate route handlers to use `New-PSWebHostResult` for consistent error reporting
- [ ] **Testing:** Ensure test modules remain separate and continue using `throw` for assertions (already compliant)

---

**Status:** Review Complete — All modules compliant with no-exception policy. ✅
