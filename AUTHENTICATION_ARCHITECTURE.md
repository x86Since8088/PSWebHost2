# PsWebHost Authentication Architecture

## Overview

This document traces the authentication flow, route handling, and module dependencies in PsWebHost. The system implements a multi-provider authentication architecture with session management, lockout protection, and role-based access control.

---

## 1. HTTP Request Processing Flow

### 1.1 Entry Point: WebHost.ps1 Listener Loop

**File:** `WebHost.ps1`

The main listener creates an HttpListener on the configured port (default 8080) and processes incoming requests:

```
WebHost.ps1
  ├─ Initializes via system/init.ps1
  │   ├─ Loads configuration from config/settings.json
  │   ├─ Imports all modules (PSWebHost_Support, PSWebHost_Authentication, etc.)
  │   ├─ Sets up logging job (background runspace)
  │   └─ Initializes global session storage ($global:PSWebSessions)
  │
  └─ Main Loop (end block)
      ├─ Monitors for HTTP requests via HttpListener
      ├─ Supports async mode (async/await pattern with tasks)
      ├─ Monitors module reloads every 30 seconds
      ├─ Monitors settings.json changes every 30 seconds
      ├─ Syncs session state to database every 1 minute
      └─ Calls Process-HttpRequest for each incoming context
```

**Key Parameters:**
- `-Port`: HTTP listener port (default 8080)
- `-Async`: Enable asynchronous request processing (uses separate runspaces)
- `-AuthenticationSchemes`: HTTP authentication scheme (Anonymous, Windows, etc.)

---

### 1.2 Route Resolution: Process-HttpRequest

**File:** `modules/PSWebHost_Support/PSWebHost_Support.psm1` (line 215+)

The `Process-HttpRequest` function implements the core routing logic:

```powershell
Process-HttpRequest -Context $HttpListenerContext -Async [-HostUIQueue $Queue]
```

**Processing Steps:**

1. **Session Management:**
   - Extract or create session cookie (PSWebSessionID)
   - Create 7-day session if new
   - Ensure cookie is HttpOnly and matches connection security (HTTPS flag)
   - Retrieve session data from `$global:PSWebSessions` hashtable

2. **Static File Routing:**
   - Requests to `/public/*` bypass routing and serve static files
   - Sanitize file path to prevent directory traversal attacks
   - Return 400 Bad Request if path fails validation

3. **Root Redirect:**
   - `/` (GET) redirects to `/spa`

4. **Dynamic Route Matching:**
   - URL pattern: `/api/v1/{resource}/{method}/{http-verb}.ps1`
   - Example: `/api/v1/auth/getauthtoken/post.ps1`
   - Route handler naming convention: `routes/{url-path}/{http-method}.ps1`
   - Supports GET, POST, PUT, DELETE, etc.

5. **Security Authorization:**
   - Auto-creates `.security.json` file if missing (default: `["unauthenticated"]`)
   - Example: `routes/api/v1/auth/getauthtoken/get.security.json`
   - Checks if user's roles match `Allowed_Roles` in security config
   - Returns 401 Unauthorized if access denied

6. **Route Invocation:**
   - **Sync mode:** Direct script invocation: `& $scriptPath @scriptParams`
   - **Async mode:** Invokes in separate runspace: `Invoke-ContextRunspace -Context $Context -ScriptPath $scriptPath -SessionID $sessionID`

7. **Fallback:**
   - Returns 404 if no route matches
   - Serves `/public/favicon.ico` for favicon requests

**Security Files:**
```
routes/
├─ api/v1/auth/getauthtoken/
│   ├─ get.ps1
│   ├─ get.security.json          # Auto-created: ["unauthenticated"]
│   ├─ post.ps1
│   └─ post.security.json
└─ api/v1/authprovider/password/
    ├─ post.ps1
    └─ post.security.json
```

---

## 2. Authentication Flow

### 2.1 Login Initiation: getauthtoken/get.ps1

**File:** `routes/api/v1/auth/getauthtoken/get.ps1`

**HTTP Method:** GET
**Security:** Allows unauthenticated access

**Purpose:** Display login form or redirect to specific authentication provider

**Flow:**

1. Serve HTML login form if no provider specified
2. Accept `provider` query parameter (e.g., `?provider=password`)
3. Generate or accept `state` parameter (GUID for CSRF protection)
4. Validate existing session (if already authenticated, redirect to getaccesstoken)
5. Support provider-specific redirects (Google OAuth, Microsoft Entra ID, etc.)

**Key Variables:**
```powershell
$state = $Request.QueryString["state"]                    # CSRF token
$redirectTo = $Request.QueryString["RedirectTo"]          # Final destination after auth
$provider = $Request.QueryString["provider"]              # Specific auth provider
$sessionID = $Request.Cookies["PSWebSessionID"].Value     # Current session
```

**⚠️ WARNING:** Token-based authentication flow is currently disabled (incomplete implementation).

---

### 2.2 Email/Password Submission: getauthtoken/post.ps1

**File:** `routes/api/v1/auth/getauthtoken/post.ps1`

**HTTP Method:** POST
**Security:** Allows unauthenticated access

**Purpose:** Accept email and password; validate; display available authentication methods

**Flow:**

1. **Extract Form Data:**
   - Get request body: `Get-RequestBody -Request $Request`
   - Parse: `[System.Web.HttpUtility]::ParseQueryString($bodyContent)`
   - Extract: `email`, `password`

2. **Input Validation:**
   - Email: `Test-IsValidEmailAddress -Email $email`
     - Validates format (RFC-compliant)
     - Checks for Unicode security issues
   - Password: `Test-IsValidPassword -Password $password`
     - Checks complexity requirements
     - Returns validation message if invalid

3. **Lockout Check:**
   - Call: `Test-LoginLockout -IPAddress $ipAddress -Username $email`
   - If locked out:
     - Return 429 Too Many Requests
     - Set `Retry-After` header with unlock time
   - Prevents brute force attacks

4. **User Lookup:**
   - Call: `Get-PSWebHostUser -UserID $email`
   - Retrieve user record from database

5. **Authentication Methods Query:**
   - Call: `Get-UserAuthenticationMethods -UserID $email`
   - List available auth providers for user (Password, Windows, Google, etc.)

6. **Response:**
   - **If methods exist:** Display buttons for method selection
   - **If no methods:** Return 404 error
   - **On validation error:** Return 400 with error messages

---

### 2.3 Provider-Specific Authentication: authprovider/{provider}/post.ps1

**Files:**
- `routes/api/v1/authprovider/password/post.ps1`
- `routes/api/v1/authprovider/windows/post.ps1`
- `routes/api/v1/authprovider/google/post.ps1`
- `routes/api/v1/authprovider/o365/post.ps1`
- `routes/api/v1/authprovider/entraid/post.ps1`
- `routes/api/v1/authprovider/certificate/post.ps1`
- `routes/api/v1/authprovider/yubikey/post.ps1`
- `routes/api/v1/authprovider/tokenauthenticator/post.ps1`

#### Password Provider: `authprovider/password/post.ps1`

**HTTP Method:** POST
**Security:** Allows unauthenticated access

**Flow:**

1. **Extract Form Data:**
   ```powershell
   $username = $parsedBody["username"]    # Email format
   $password = $parsedBody["password"]
   ```

2. **Input Validation:**
   - Email format: `Test-IsValidEmailAddress -Email $username`
   - Password present: Check for non-empty value
   - Return 400 if validation fails

3. **Lockout Check:**
   - `Test-LoginLockout -IPAddress $ipAddress -Username $username`
   - Return 429 if locked (with Retry-After header)

4. **Credential Validation:**
   - Create PSCredential object
   - Call: `Invoke-AuthenticationMethod -Name "Password" -Credential $credential`
   - Validates against system/AD or local user database

5. **Success Handling (Authenticated):**
   - Log success: `PSWebLogon -ProviderName "Password" -Result "Success" -Request $Request -UserID $username`
   - Create session: `Set-PSWebSession -SessionID $sessionID -UserID $username -Provider 'Password' -Request $Request`
   - Populate roles/permissions in session
   - Redirect to: `/api/v1/auth/getaccesstoken?state=$state&RedirectTo=$redirectTo` (302 Found)

6. **Failure Handling (Invalid Credentials):**
   - Log failure: `PSWebLogon -ProviderName "Password" -Result "Fail" -Request $Request -UserID $username`
   - Return 401 Unauthorized with error message

7. **Error Handling:**
   - Catch exceptions
   - Log error: `Write-PSWebHostLog -Severity 'Error' -Message "..."`
   - Log event: `PSWebLogon -ProviderName "Password" -Result "error" -Request $Request`
   - Return 500 Internal Server Error with exception message

#### Windows Provider: `authprovider/windows/post.ps1`

**HTTP Method:** POST
**Security:** Allows unauthenticated access

**Similar to Password Flow, with differences:**

1. **Username Transformation:**
   - Converts `user@localhost` to `user@{ComputerName}`

2. **Credential Validation:**
   - Calls external script: `system\auth\Test-PSWebWindowsAuth.ps1`
   - Executes: `& $AuthTestScript -credential $credential`
   - Tests Windows authentication (domain or local AD)

3. **Success Flow:** Identical to password provider
4. **Error Handling:** Identical to password provider

---

### 2.4 Session Access Token: getaccesstoken/get.ps1

**File:** `routes/api/v1/auth/getaccesstoken/get.ps1`

**HTTP Method:** GET
**Security:** Requires authenticated session

**Purpose:** Final step in authentication flow; issue access token and redirect

**Current Status:** ⚠️ **DISABLED** - Token implementation incomplete

**Expected Flow (When Implemented):**
1. Validate session state is "completed"
2. Retrieve user details: `Get-PSWebUser -UserID $sessionData.UserID`
3. Generate access token
4. Set token expiration (default: 1 hour)
5. Redirect to final destination specified by `RedirectTo` parameter

**Current Fallback:**
- Returns 302 redirect to `/spa?error=LoginFlowDisabled`

---

### 2.5 Session Retrieval: sessionid/get.ps1

**File:** `routes/api/v1/auth/sessionid/get.ps1`

**HTTP Method:** GET
**Security:** Allows unauthenticated access (returns public session data)

**Purpose:** Client-side session validation

**Response:**
```json
{
  "SessionID": "guid-here",
  "UserID": "user@example.com",
  "Roles": ["user", "admin"],
  "Provider": "Password",
  "IsAuthenticated": true,
  "LastActivity": "2024-01-15T10:30:00Z"
}
```

---

## 3. Module Dependencies

### 3.1 PSWebHost_Support (Core)

**File:** `modules/PSWebHost_Support/PSWebHost_Support.psm1`

**Functions Used by Routes:**

| Function | Purpose | Used By |
|----------|---------|---------|
| `Process-HttpRequest` | Main route dispatcher | WebHost.ps1 |
| `Write-PSWebHostLog` | Logging to queue | All routes, modules |
| `Get-PSWebSessions` | Retrieve session by ID | Process-HttpRequest |
| `context_reponse` | Send HTTP response | All routes |
| `Get-RequestBody` | Extract POST/PUT body | Auth routes |
| `Invoke-ContextRunspace` | Run route in async runspace | Process-HttpRequest (async mode) |
| `Set-PSWebSession` | Create/update session | Auth routes after success |
| `Validate-UserSession` | Check if session valid | Routes (optional) |
| `New-PSWebHostResult` | Standardized result object | Any error-handling route |

**Exports:** Functions in `.FunctionExportList`

---

### 3.2 PSWebHost_Authentication (User & Auth)

**File:** `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1`

**Functions Used by Routes:**

| Function | Purpose | Used By |
|----------|---------|---------|
| `Get-PSWebHostUser` | Query user by ID | Auth routes |
| `Get-UserAuthenticationMethods` | List auth providers for user | getauthtoken/post.ps1 |
| `Test-IsValidEmailAddress` | Email validation + Unicode check | All auth routes |
| `Test-IsValidPassword` | Password strength validation | Password provider |
| `Test-LoginLockout` | Check IP/user lockout status | All auth providers |
| `Invoke-AuthenticationMethod` | Execute auth (currently: Password) | Password provider |
| `Set-PSWebSession` | Create authenticated session | All providers (success) |
| `PSWebLogon` | Log auth events (success/fail/error) | All providers |

**Key Features:**
- Unicode security validation in email addresses
- Password complexity checking
- Login attempt tracking and lockout
- Multi-provider abstraction layer
- Session role aggregation

---

### 3.3 PSWebHost_Database (Persistence)

**File:** `modules/PSWebHost_Database/PSWebHost_Database.psm1`

**Functions Used by Routes:**

| Function | Purpose | Used By |
|----------|---------|---------|
| `Get-CardSettings` | Retrieve card configuration | Process-HttpRequest (POST routes) |
| `Sync-SessionStateToDatabase` | Persist session to database | WebHost.ps1 (every 1 min) |

**Database Layer:**
- SQLite wrapper (`public\pswebhost.db`)
- Safe error handling (no exceptions on query failures)
- Session persistence
- User/role storage

---

## 4. Request/Response Lifecycle

### 4.1 Detailed Flow Diagram

```
HTTP Client Request
        │
        ▼
WebHost.ps1 HttpListener
  │ GetContext() or GetContextAsync()
  │
  ├─ [Async Mode] Create new runspace
  │              Invoke Process-HttpRequest asynchronously
  │
  └─ [Sync Mode]  Direct invocation of Process-HttpRequest
        │
        ▼
Process-HttpRequest (Router)
  │
  ├─ Extract session cookie or create new
  │  └─ Store in $global:PSWebSessions
  │
  ├─ [/public/*] Static file serving
  │             └─ Sanitize path → Serve file
  │
  ├─ [/] Root redirect → /spa
  │
  └─ [/api/v1/*] Route handler lookup
     │
     ├─ Resolve: routes/{path}/{http-method}.ps1
     │
     ├─ Load .security.json (auto-create if missing)
     │
     ├─ Check user roles against Allowed_Roles
     │  │
     │  └─ [Not authorized] → 401 Unauthorized
     │
     ├─ [Authorized] Invoke route handler
     │  │
     │  ├─ Pass: $Context, $Request, $Response, $SessionData
     │  │
     │  └─ Route Handler Logic
     │     │
     │     ├─ [GET /auth/getauthtoken] Serve login form
     │     ├─ [POST /auth/getauthtoken] Validate email, show methods
     │     ├─ [POST /authprovider/password] Authenticate credentials
     │     ├─ [POST /authprovider/windows] Windows auth
     │     ├─ [GET /auth/getaccesstoken] Issue token (disabled)
     │     └─ [GET /auth/sessionid] Return session JSON
     │
     └─ [404] Not found

HTTP Response
        │
        ▼
HTTP Client
```

### 4.2 Session Flow

```
1. First Request (Unauthenticated)
   ├─ No PSWebSessionID cookie
   ├─ Generate new GUID
   ├─ Create cookie (7-day expiry, HttpOnly)
   ├─ Store in $global:PSWebSessions[$sessionID] = @{
   │    SessionID = $sessionID
   │    UserID = $null
   │    Roles = @("unauthenticated")
   │    Provider = $null
   │    CreatedAt = (Get-Date)
   │    LastActivity = (Get-Date)
   │    IsAuthenticated = $false
   │  }
   └─ Route handler sees session as unauthenticated

2. Authentication (POST /authprovider/password)
   ├─ Validate credentials via module function
   ├─ On success: Set-PSWebSession -SessionID $sessionID -UserID "user@example.com"
   ├─ Update session in $global:PSWebSessions:
   │    SessionID = $sessionID
   │    UserID = "user@example.com"
   │    Roles = ["user", "admin"]          # From user profile
   │    Provider = "Password"
   │    IsAuthenticated = $true
   │    LastActivity = (Get-Date)
   └─ Redirect to /api/v1/auth/getaccesstoken

3. Subsequent Requests (Authenticated)
   ├─ PSWebSessionID cookie sent
   ├─ Session retrieved from $global:PSWebSessions
   ├─ UserID present → treated as authenticated
   ├─ Roles checked for route authorization
   └─ Route handler invoked with authenticated session

4. Session Persistence
   └─ Every 1 minute:
      └─ Sync-SessionStateToDatabase
         └─ Write session to SQLite database
```

---

## 5. Error Handling

### 5.1 Pattern

All runtime code follows the safe error-handling pattern:

```powershell
# UNSAFE (old pattern - replaced)
$result = SomeCommand -ErrorAction Stop

# SAFE (current pattern)
$result = SomeCommand -ErrorAction SilentlyContinue -ErrorVariable err
if ($err) {
    # Handle error
    Write-PSWebHostLog -Severity 'Error' -Message "..."
    context_reponse -Response $Response -StatusCode 500 -String "Error message"
    return
}
```

### 5.2 HTTP Status Codes

| Code | Scenario | Route Handler |
|------|----------|---------------|
| 200 | Success (GET requests) | Any route |
| 302 | Redirect (auth success) | authprovider/* (success) |
| 400 | Bad Request | Input validation failure |
| 401 | Unauthorized | Invalid credentials OR insufficient roles |
| 404 | Not Found | Unknown route or resource |
| 429 | Too Many Requests | Login lockout active |
| 500 | Internal Server Error | Unhandled exception in route |

---

## 6. Security Considerations

### 6.1 Session Security

- **HttpOnly Flag:** Prevents JavaScript access to session cookie
- **Secure Flag:** Only transmitted over HTTPS (when applicable)
- **SameSite:** Not explicitly set (would prevent CSRF in modern browsers)
- **Expiry:** 7 days
- **State Parameter:** GUID-based CSRF token in OAuth flows

### 6.2 Input Validation

- **Email:** RFC-compliant validation + Unicode character check
- **Password:** Complexity requirements configurable
- **Paths:** Directory traversal prevention via `Sanitize-FilePath`

### 6.3 Brute Force Protection

- **Login Lockout:** Tracks failed attempts per IP and username
- **Lockout Duration:** Configurable (see `Test-LoginLockout`)
- **Retry-After Header:** Informs clients when to retry

### 6.4 Role-Based Access Control (RBAC)

- **Per-Route Security Files:** `.security.json` defines allowed roles
- **Automatic Creation:** Missing security files default to `["unauthenticated"]`
- **Authorization Check:** Performed in `Process-HttpRequest` before handler invocation

---

## 7. Authentication Providers

### Implemented Providers

| Provider | Status | Files |
|----------|--------|-------|
| Password | ✅ Implemented | `authprovider/password/post.ps1` |
| Windows | ✅ Implemented | `authprovider/windows/post.ps1` |
| Google | ⚠️ Partial | `authprovider/google/*` |
| Office 365 | ⚠️ Partial | `authprovider/o365/*` |
| Entra ID | ⚠️ Partial | `authprovider/entraid/*` |
| Certificate | ⚠️ Partial | `authprovider/certificate/*` |
| YubiKey | ⚠️ Partial | `authprovider/yubikey/*` |
| Token Auth | ⚠️ Partial | `authprovider/tokenauthenticator/*` |

### Common Pattern

Each provider POST handler:
1. Extracts provider-specific credentials
2. Validates input
3. Checks lockout status
4. Invokes authentication method
5. On success: Creates session + redirects
6. On failure: Logs event + returns 401

---

## 8. Known Issues & Incomplete Features

| Issue | Location | Status | Impact |
|-------|----------|--------|--------|
| Token-based auth disabled | `routes/api/v1/auth/getaccesstoken/get.ps1` | ⚠️ Incomplete | Access token generation not working |
| MFA check disabled | `authprovider/password/post.ps1`, `authprovider/windows/post.ps1` | ⚠️ Incomplete | Multi-factor authentication not enforced |
| OAuth providers | Multiple | ⚠️ Partial | Some OAuth flows incomplete |
| Token authenticator | `authprovider/tokenauthenticator/*` | ⚠️ Partial | Token-based login incomplete |

---

## 9. Testing & Debugging

### 9.1 Enabling Verbose Logging

In `config/settings.json`:
```json
{
  "debug_url": {
    "/api/v1/auth": {
      "VerbosePreference": "Continue",
      "DebugPreference": "Continue"
    }
  }
}
```

### 9.2 Route Testing

Use curl or Postman to test:

```bash
# 1. Get login form
curl http://localhost:8080/api/v1/auth/getauthtoken/get

# 2. Submit email
curl -X POST http://localhost:8080/api/v1/auth/getauthtoken/post \
  -d "email=user@example.com&password=TestPassword123"

# 3. Authenticate with password
curl -X POST http://localhost:8080/api/v1/authprovider/password/post \
  -d "username=user@example.com&password=TestPassword123" \
  -H "Cookie: PSWebSessionID=<session-guid>"

# 4. Check session
curl http://localhost:8080/api/v1/auth/sessionid/get \
  -H "Cookie: PSWebSessionID=<session-guid>"
```

### 9.3 Log Analysis

Logs are written to `PSWebHost_Data/Logs/` directory with structured format:
- Category: Auth, Security, Routing, etc.
- Severity: Critical, Error, Warning, Info, Verbose, Debug
- Timestamp: ISO 8601 format

---

## 10. Extension Points

### Adding a New Authentication Provider

1. **Create route handler:**
   ```
   routes/api/v1/authprovider/myprovider/post.ps1
   ```

2. **Implement pattern:**
   - Extract credentials
   - Validate input
   - Check lockout (if applicable)
   - Call authentication method
   - On success: `Set-PSWebSession` + redirect
   - On failure: `PSWebLogon` + return 401

3. **Security file:**
   ```json
   routes/api/v1/authprovider/myprovider/post.security.json
   {
     "Allowed_Roles": ["unauthenticated"]
   }
   ```

4. **Register in PSWebHost_Authentication:**
   - Add provider to `Invoke-AuthenticationMethod` switch statement
   - Implement provider-specific validation logic

---

## Summary

PsWebHost implements a flexible, multi-provider authentication system with:
- **Modular routing** via URL-to-file-path mapping
- **Session management** with in-memory storage + database persistence
- **Role-based access control** via per-route security files
- **Multi-provider authentication** (Password, Windows, OAuth, etc.)
- **Brute force protection** via login lockout
- **Safe error handling** with standardized logging
- **Asynchronous request processing** via runspace delegation

The architecture separates concerns across modules (support, authentication, database) and route handlers, enabling maintainability and extensibility.
