# PsWebHost Project Documentation Index

## Documentation Files

### 1. **AUTHENTICATION_ARCHITECTURE.md** (NEW)
Comprehensive trace of the authentication system including:
- HTTP request processing flow (WebHost.ps1 → Process-HttpRequest → Route Handler)
- Authentication flow (login form → email validation → provider selection → credentials → session creation)
- Module dependencies (PSWebHost_Support, PSWebHost_Authentication, PSWebHost_Database)
- Session management and persistence
- Error handling patterns
- Security considerations (HTTPS, session cookies, input validation, brute force protection)
- RBAC (Role-Based Access Control) implementation
- All authentication providers (Password, Windows, Google, OAuth, etc.)
- Known issues (MFA disabled, token auth incomplete)
- Extension points for adding new providers

### 2. **MD_VALIDATION_REPORT.md**
Documentation validation report showing all `.ps1.md` files and their sync status with actual `.ps1` files.

### 3. **COMPLETION_REPORT.md**
Full project completion summary including:
- Files modified (10 total across error-handling refactoring)
- All syntax validation results (100% passing)
- Module compliance assessment
- Route audit findings

### 4. **MODULES_REVIEW.md**
Module-by-module compliance review:
- PSWebHost_Support
- PSWebHost_Authentication
- PSWebHost_Database
- PSWebHost_Formatters
- Sanitization
- smtp

### 5. **SYSTEM_ROUTES_REVIEW.md**
Audit of system/ and routes/ folders:
- 13 system files reviewed (100% compliant)
- 53 route handlers reviewed (100% compliant)
- Pattern consistency analysis

---

## Key Architecture Findings

### HTTP Request Flow
```
HTTP Request
    ↓
WebHost.ps1 HttpListener
    ↓
Process-HttpRequest (Router)
    ├─ Session management
    ├─ Static file serving (/public/*)
    ├─ Route resolution (/api/v1/{path}/{method}.ps1)
    ├─ Authorization check (role-based via .security.json)
    └─ Route handler invocation
    ↓
HTTP Response
```

### Authentication Flow
```
1. GET /api/v1/auth/getauthtoken
   └─ Display login form

2. POST /api/v1/auth/getauthtoken
   └─ Validate email, return available methods

3. POST /api/v1/authprovider/{provider}
   ├─ Validate credentials
   ├─ Check lockout status
   ├─ Authenticate user
   └─ Create session + redirect

4. GET /api/v1/auth/getaccesstoken
   └─ Issue access token (currently disabled)
```

### Module Dependency Graph
```
WebHost.ps1
    ├─ system/init.ps1 (initialization)
    │   └─ Imports modules
    │
    └─ Process-HttpRequest (PSWebHost_Support)
        ├─ PSWebHost_Authentication (user auth)
        ├─ PSWebHost_Database (persistence)
        ├─ PSWebHost_Formatters (YAML conversion)
        └─ Sanitization (input validation)
```

---

## Code Quality Status

### Error Handling
✅ **100% Compliant**
- All runtime code uses safe pattern: `-ErrorAction SilentlyContinue -ErrorVariable err`
- No exceptions thrown in production code
- Standardized error logging via `Write-PSWebHostLog`
- Structured result objects via `New-PSWebHostResult`

### Files Modified (Session)
1. `system/validateInstall.ps1` — SQLite error handling
2. `system/Validate3rdPartyModules.ps1` — Module installation safety
3. `system/auth/localaccounts/synclocalaccounts.ps1` — User creation
4. `routes/api/v1/ui/elements/main-menu/get.ps1` — YAML import
5. `routes/api/v1/ui/elements/file-explorer/post.ps1` — Directory listing
6. `routes/api/v1/debug/var/post.ps1` — Variable conversion
7. `routes/api/v1/debug/var/delete.ps1` — Variable deletion
8. `modules/PSWebHost_Support/PSWebHost_Support.psm1` — Added `New-PSWebHostResult`
9. `system/makefavicon.ps1` — Icon generation
10. `system/graphics/MakeIcons.ps1` — Icon generation

**All 10 files pass syntax validation** ✅

### Security Features
- **Session Cookies:** HttpOnly, Secure (HTTPS), 7-day expiry
- **Input Validation:** Email, password, file paths
- **Brute Force Protection:** Login lockout (IP + username)
- **Authorization:** Role-based access control (RBAC)
- **Logging:** Comprehensive audit trail via `Write-PSWebHostLog`

---

## Known Limitations

| Issue | Location | Impact | Status |
|-------|----------|--------|--------|
| Token auth disabled | `routes/api/v1/auth/getaccesstoken/get.ps1` | Access tokens not issued | ⚠️ Incomplete |
| MFA disabled | Auth providers | Multi-factor auth not enforced | ⚠️ Incomplete |
| OAuth incomplete | Multiple providers | Some OAuth flows broken | ⚠️ Partial |
| Token authenticator | `authprovider/tokenauthenticator/*` | Token-based login broken | ⚠️ Partial |

---

## Extension Points

### Adding New Authentication Provider

1. Create route: `routes/api/v1/authprovider/{name}/post.ps1`
2. Implement standard pattern (validate → authenticate → session)
3. Create security file: `post.security.json` with `Allowed_Roles`
4. Register in `PSWebHost_Authentication` module

### Adding New Routes

1. Create file: `routes/{path}/{http-method}.ps1`
2. Implement route handler with parameters: `$Context`, `$Request`, `$Response`, `$SessionData`
3. Security file auto-created with default roles: `["unauthenticated"]`
4. Use `context_reponse` function to send response

---

## Testing & Debugging

### Enable Verbose Logging
Edit `config/settings.json`:
```json
{
  "debug_url": {
    "/api/v1/auth": {
      "VerbosePreference": "Continue"
    }
  }
}
```

### Test Authentication Flow
```bash
# 1. Get login form
curl http://localhost:8080/api/v1/auth/getauthtoken/get

# 2. Submit email
curl -X POST http://localhost:8080/api/v1/auth/getauthtoken/post \
  -d "email=user@example.com&password=TestPassword123"

# 3. Check session
curl http://localhost:8080/api/v1/auth/sessionid/get \
  -H "Cookie: PSWebSessionID=<guid>"
```

### View Logs
```powershell
Get-ChildItem PsWebHost_Data/Logs/ | Select-Object -Last 5
```

---

## Next Steps (Optional)

1. **Complete MFA Implementation** — Uncomment and implement MFA checks in password/windows providers
2. **Enable Token Authentication** — Implement `getaccesstoken/get.ps1` logic
3. **Complete OAuth Flows** — Finish Google, O365, Entra ID integrations
4. **Add OpenID Connect** — Support OIDC alongside OAuth2
5. **Implement Certificate Auth** — Finish certificate-based authentication
6. **Add Passwordless Auth** — Support WebAuthn/FIDO2

---

## File Locations

### Core Files
- `WebHost.ps1` — Main listener and request dispatcher
- `system/init.ps1` — Initialization and module loading
- `system/Functions.ps1` — Common utility functions

### Authentication Routes
- `routes/api/v1/auth/` — Session/token management
- `routes/api/v1/authprovider/` — Provider-specific handlers

### Modules
- `modules/PSWebHost_Support/` — Core functionality
- `modules/PSWebHost_Authentication/` — Auth logic
- `modules/PSWebHost_Database/` — Data persistence
- `modules/PSWebHost_Formatters/` — Data transformation
- `modules/Sanitization/` — Input validation

### Configuration
- `config/settings.json` — Application settings
- `config/settings.json.md` — Settings documentation
- `public/` — Static web files
- `routes/` — Dynamic route handlers

### Testing
- `tests/` — Test scripts and pester tests
- `tests/pester/` — Unit tests

---

## Related Documentation

- `README.md` — Project overview
- `GEMINI.md` — Gemini AI setup notes
- `routes/Design.md` — Route design documentation
- `config/settings.json.md` — Configuration reference

---

**Last Updated:** 2024
**Status:** All core functionality documented and validated ✅
