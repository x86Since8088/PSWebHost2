# PsWebHost Comprehensive Testing Documentation

## 📋 Table of Contents
- [Overview](#overview)
- [Test Suites](#test-suites)
- [API Endpoint Map](#api-endpoint-map)
- [Execution Flow](#execution-flow)
- [Security Analysis](#security-analysis)
- [Running Tests](#running-tests)
- [Test Results](#test-results)

---

## Overview

This directory contains a comprehensive testing framework for PsWebHost that covers:
- **46 API endpoints** across 10 categories
- **Authentication flows** (3-step process with 9 providers)
- **Security features** (brute force, injection, validation)
- **RBAC configuration** (39 security files analyzed)
- **Session management** and persistence
- **Database operations** and schema validation

### Test Infrastructure

| Component | Description | Status |
|-----------|-------------|--------|
| `Test-AuthFlow.ps1` | Authentication flow testing (9 tests) | ✅ Complete |
| `Test-AllEndpoints.ps1` | All 46 API endpoints (10 categories) | ✅ Complete |
| `Test-Security.ps1` | Security features (6 categories, 20+ tests) | ✅ Complete |
| `Test-RBAC.ps1` | RBAC configuration analysis | ✅ Complete |
| `Run-AllTests.ps1` | Master test runner with reporting | ✅ Complete |
| `Setup-TestUser.ps1` | Test user creation utility | ✅ Complete |
| `helpers/Start-WebHostForTest.psm1` | WebHost process management | ✅ Complete |

---

## Test Suites

### 1. Authentication Flow Tests (`Test-AuthFlow.ps1`)

Tests the complete 3-step authentication process:

```
Step 1: GET /api/v1/auth/getauthtoken
  → Tests: CSRF state generation, form display

Step 2: POST /api/v1/auth/getauthtoken
  → Tests: Email validation, auth method selection, lockout protection

Step 3: POST /api/v1/authprovider/{provider}
  → Tests: Credential validation, session creation, cookie security
```

**Coverage:**
- ✅ CSRF protection (state parameter)
- ✅ Email format validation (RFC compliant + Unicode security)
- ✅ Brute force protection (lockout after failed attempts)
- ✅ Session cookie security (HttpOnly, 7-day expiration)
- ✅ Authentication for 9 providers
- ✅ Invalid credential handling
- ✅ Session persistence

**Run:**
```powershell
# Basic test (no valid credentials)
.\Test-AuthFlow.ps1

# With credentials
.\Test-AuthFlow.ps1 -TestUsername "test@localhost" -TestPassword "TestPassword123!"
```

---

### 2. All Endpoints Test (`Test-AllEndpoints.ps1`)

Comprehensive testing of all 46 API endpoints across 10 categories:

#### Category Breakdown:

**Authentication (8 endpoints)**
- `/api/v1/auth/getauthtoken` (GET, POST)
- `/api/v1/auth/getaccesstoken` (GET)
- `/api/v1/auth/sessionid` (GET)
- `/api/v1/auth/logoff` (GET)

**Auth Providers (13 endpoints)**
- Password, Windows, Google, O365, EntraID
- Certificate, YubiKey, Token Authenticator

**User Management (4 endpoints)**
- `/api/v1/users` (GET, POST, PUT, DELETE)

**Registration (3 endpoints)**
- `/api/v1/registration` (GET, POST)
- `/api/v1/registration/confirm/email` (GET)

**Configuration (2 endpoints)**
- `/api/v1/config/profile` (GET, POST)

**Session (1 endpoint)**
- `/api/v1/session` (GET)

**Database (3 endpoints)**
- `/api/v1/db/sqlite/pswebhost.db/tables` (GET)
- `/api/v1/db/sqlite/pswebhost.db/tableexplorer` (GET)
- `/api/v1/db/sqlite/pswebhost.db/query` (POST)

**Debug (4 endpoints)**
- `/api/v1/debug` (GET)
- `/api/v1/debug/vars` (GET)
- `/api/v1/debug/var` (POST, DELETE)

**Status (2 endpoints)**
- `/api/v1/status/logging` (GET)
- `/api/v1/status/error` (GET)

**UI Elements (6 endpoints)**
- Main menu, File explorer, System status
- World map, Server heatmap, Event stream
- Users management

**Run:**
```powershell
.\Test-AllEndpoints.ps1
```

---

### 3. Security Features Test (`Test-Security.ps1`)

Comprehensive security testing across 6 categories:

#### 1. Brute Force Protection
- ✅ Login lockout after multiple failed attempts
- ✅ 429 Too Many Requests with Retry-After header
- ✅ IP-based rate limiting
- ✅ Username + IP tracking

#### 2. Input Validation
- ✅ Email format validation (7+ invalid patterns tested)
- ✅ Password complexity requirements
- ✅ Unicode homograph attack detection
- ✅ RFC compliance + security checks

#### 3. Injection Attacks
- ✅ SQL injection prevention (5+ payloads)
- ✅ Path traversal blocking (4+ patterns)
- ✅ XSS sanitization (5+ payloads)
- ✅ Safe error handling (no 500s)

#### 4. Session Security
- ✅ CSRF protection via state parameter
- ✅ HttpOnly cookie flag
- ✅ Session fixation prevention
- ✅ Secure cookie attributes

#### 5. Authorization Controls
- ✅ Protected endpoints require authentication
- ✅ RBAC enforcement
- ✅ 401/403 for unauthorized access

#### 6. Error Handling
- ✅ No sensitive information disclosure
- ✅ Safe error messages
- ✅ Proper status codes

**Run:**
```powershell
.\Test-Security.ps1
```

---

### 4. RBAC Configuration Analysis (`Test-RBAC.ps1`)

Analyzes all 39 route security configuration files:

#### Role Hierarchy:
```
1. unauthenticated (Public)
   └─ Login, Registration, Public endpoints

2. authenticated (Standard User)
   └─ Profile config, Session management

3. site_admin (Administrator)
   └─ Database queries, Debug tools, User management

4. Additional Roles
   └─ vault_admin, system_admin, custom roles
```

#### Analysis Includes:
- ✅ Role usage statistics
- ✅ Endpoints by security level
- ✅ Security recommendations
- ✅ Configuration validation
- ✅ Missing security files detection
- ✅ JSON structure validation

**Run:**
```powershell
.\Test-RBAC.ps1
```

---

## API Endpoint Map

### Complete Endpoint Listing (46 total)

#### Authentication & Authorization
```
GET  /api/v1/auth/getauthtoken          [unauthenticated]
POST /api/v1/auth/getauthtoken          [unauthenticated]
GET  /api/v1/auth/getaccesstoken        [authenticated]
GET  /api/v1/auth/sessionid             [unauthenticated, authenticated]
GET  /api/v1/auth/logoff                [authenticated]
```

#### Auth Providers
```
GET  /api/v1/authprovider/password      [unauthenticated]
POST /api/v1/authprovider/password      [unauthenticated]
GET  /api/v1/authprovider/windows       [unauthenticated]
POST /api/v1/authprovider/windows       [unauthenticated]
GET  /api/v1/authprovider/google        [unauthenticated]
GET  /api/v1/authprovider/o365          [unauthenticated]
GET  /api/v1/authprovider/entraID       [unauthenticated]
GET  /api/v1/authprovider/certificate   [unauthenticated]
GET  /api/v1/authprovider/yubikey       [unauthenticated]
POST /api/v1/authprovider/tokenauthenticator  [authenticated]
GET  /api/v1/authprovider/tokenauthenticator/registration  [authenticated]
POST /api/v1/authprovider/tokenauthenticator/registration  [authenticated]
```

#### User Management (Admin Only)
```
GET    /api/v1/users                    [site_admin]
POST   /api/v1/users                    [site_admin]
PUT    /api/v1/users                    [site_admin]
DELETE /api/v1/users                    [site_admin]
```

#### Database (Admin Only)
```
GET  /api/v1/db/sqlite/pswebhost.db/tables        [site_admin]
GET  /api/v1/db/sqlite/pswebhost.db/tableexplorer [site_admin]
POST /api/v1/db/sqlite/pswebhost.db/query         [site_admin]
```

#### Debug (Admin Only)
```
GET    /api/v1/debug                    [unauthenticated, authenticated]
GET    /api/v1/debug/vars               [site_admin]
POST   /api/v1/debug/var                [site_admin]
DELETE /api/v1/debug/var                [site_admin]
```

---

## Execution Flow

### WebHost.ps1 Startup Sequence

```
BEGIN Block (Lines 11-129):
  ├─ Line 14: Load system/init.ps1
  │   ├─ Import modules (6 core modules)
  │   ├─ Load config/settings.json
  │   ├─ Validate database schema (12 tables)
  │   └─ Register roles from config
  │
  ├─ Line 30: -ShowVariables mode → Exit early (for testing)
  │
  ├─ Line 35: -ReloadOnScriptUpdate → Launch in auto-restart loop
  │
  └─ Lines 82-90: HttpListener Setup (FIXED)
      ├─ Try localhost:$port first (no URL ACL needed)
      └─ Fallback to +:$port if admin (requires URL ACL)

END Block (Lines 137-360):
  ├─ Line 196: Main while loop
  │   ├─ Every 1 min:  Sync sessions to DB
  │   ├─ Every 30 sec: Reload settings.json
  │   ├─ Every 30 sec: Hot-reload modules
  │   └─ Every 5 sec:  Clean runspaces (async mode)
  │
  ├─ Line 288: Async request processing
  │   └─ Process-HttpRequest -Async (separate runspace)
  │
  └─ Line 303: Sync request processing (blocking)
      └─ Process-HttpRequest (inline execution)
```

### Authentication Flow (3 Steps)

```
Step 1: GET /api/v1/auth/getauthtoken
  ├─ Line 19-24: Generate CSRF state if missing → 302 redirect
  ├─ Line 27-32: Check existing session → redirect to getaccesstoken
  ├─ Line 35: Create auth attempt record
  └─ Line 47: Serve email entry form HTML

Step 2: POST /api/v1/auth/getauthtoken
  ├─ Line 51-58: Validate email (RFC + Unicode security)
  ├─ Line 61-69: Check brute force lockout
  │   └─ If locked: 429 + Retry-After header
  ├─ Line 71: Get user's auth methods
  └─ Line 73-83: Return auth method buttons HTML

Step 3: POST /api/v1/authprovider/windows
  ├─ Line 42-57: Validate username/password format
  ├─ Line 69-82: Re-check lockout status
  ├─ Line 86-88: Authenticate via Test-PSWebWindowsAuth.ps1
  ├─ Line 99: Create session via Set-PSWebSession
  ├─ Line 103-115: Set secure session cookie (7-day, HttpOnly)
  └─ Line 117: Redirect to /api/v1/auth/getaccesstoken
```

### Request Processing Flow

```
Process-HttpRequest (PSWebHost_Support module):
  ├─ 1. Session Management
  │   ├─ Extract/create PSWebSessionID cookie
  │   └─ Load session from $global:PSWebSessions
  │
  ├─ 2. Static File Serving
  │   └─ /public/* → Direct file serve (bypasses routing)
  │
  ├─ 3. Dynamic Route Resolution
  │   └─ Pattern: /api/v1/{resource}/{method}/{http-verb}.ps1
  │
  ├─ 4. Authorization Check
  │   ├─ Load {route}.security.json
  │   ├─ Auto-create with default ["unauthenticated"] if missing
  │   └─ Check user roles vs Allowed_Roles
  │       └─ 401 if denied
  │
  └─ 5. Route Invocation
      ├─ Sync: Direct execution
      ├─ Async: Runspace delegation
      └─ 404 if no match
```

---

## Security Analysis

### ✅ Strengths

1. **Input Validation**
   - RFC-compliant email validation
   - Unicode homograph attack detection
   - Password complexity enforcement
   - SQL injection prevention via sanitization

2. **Brute Force Protection**
   - IP + username based lockout
   - Configurable attempt limits
   - Retry-After HTTP header (429 status)
   - Lockout duration enforcement

3. **Session Security**
   - HttpOnly cookies (prevent JavaScript access)
   - 7-day expiration
   - CSRF state parameter
   - Session sync to database every 1 minute

4. **RBAC Implementation**
   - Per-route security files
   - Role hierarchy (unauthenticated → authenticated → site_admin)
   - Auto-creation with safe defaults
   - 39/46 routes have security configs

5. **Code Quality**
   - 100% syntax validation passing
   - Safe error-handling patterns
   - Comprehensive logging
   - Module hot-reload capability

### ⚠️ Recommendations

1. **Missing Security Files**
   - 7 routes don't have .security.json files
   - Should be auto-created with ["authenticated"] default

2. **Admin Endpoint Protection**
   - Database query endpoint requires strict authentication
   - Debug endpoints should be disabled in production
   - Consider IP whitelisting for admin access

3. **Session Management**
   - Implement session invalidation on password change
   - Add session timeout (idle detection)
   - Consider rotating session IDs after authentication

4. **Error Handling**
   - Ensure no stack traces in production
   - Implement generic error messages
   - Log detailed errors server-side only

5. **HTTPS Enforcement**
   - Secure cookie flag only works over HTTPS
   - Implement HSTS (HTTP Strict Transport Security)
   - Redirect HTTP to HTTPS automatically

---

## Running Tests

### Quick Start

```powershell
# 1. Navigate to tests directory
cd C:\sc\PsWebHost\tests

# 2. Setup test user (one-time)
.\Setup-TestUser.ps1

# 3. Run all tests
.\Run-AllTests.ps1

# Or run individual tests:
.\Test-AuthFlow.ps1 -TestUsername "test@localhost" -TestPassword "TestPassword123!"
.\Test-AllEndpoints.ps1
.\Test-Security.ps1
.\Test-RBAC.ps1
```

### Prerequisites

1. **PowerShell 7+ Required** ⚠️
   ```powershell
   # Check your version
   $PSVersionTable.PSVersion

   # If < 7.0, download PowerShell 7+
   # Windows: https://github.com/PowerShell/PowerShell/releases
   # Or use: winget install Microsoft.PowerShell

   # Run tests with PowerShell 7+
   pwsh .\tests\Run-AllTests.ps1
   ```
   **Note:** These tests use PowerShell 7+ features like `-SkipHttpErrorCheck` and are not compatible with Windows PowerShell 5.1.

2. **URL ACL Permission**
   ```powershell
   # Run as Administrator
   netsh http add urlacl url=http://+:8888/ user='DOMAIN\Username'
   ```

3. **PowerShell Modules**
   ```powershell
   Install-Module -Name PSSQLite
   Install-Module -Name powershell-yaml
   Install-Module -Name LogError
   ```

4. **Test User** (for authentication tests)
   ```powershell
   .\Setup-TestUser.ps1 -Email "test@localhost" -Password "TestPassword123!"
   ```

### Advanced Options

```powershell
# Run with custom port
.\Run-AllTests.ps1 -Port 9000

# Skip slow tests (endpoint testing)
.\Run-AllTests.ps1 -SkipSlow

# Custom test user
.\Run-AllTests.ps1 -TestUsername "custom@test.com" -TestPassword "MyPass123!"

# Custom report location
.\Run-AllTests.ps1 -ReportPath "C:\Reports"
```

---

## Test Results

### Expected Outcomes

#### Authentication Flow
- **9 tests total**
- Expected: 9 passed, 0 failed
- Duration: ~5-10 seconds

#### All Endpoints
- **40+ tests** (varies by endpoint availability)
- Expected: 35+ passed, 0-5 failed (protected endpoints return 401)
- Duration: ~30-60 seconds

#### Security Features
- **20+ tests** across 6 categories
- Expected: 18+ passed, 0-2 warnings
- Duration: ~15-30 seconds

#### RBAC Configuration
- **3-4 validation checks**
- Expected: All passed with 0-3 recommendations
- Duration: ~2-5 seconds

### Interpreting Results

**Success Indicators:**
- ✅ All authentication tests pass
- ✅ Protected endpoints return 401/403 for unauthenticated requests
- ✅ Brute force lockout triggers on 5-10 attempts
- ✅ SQL injection attempts safely rejected
- ✅ RBAC config has no missing security files

**Warning Signs:**
- ⚠️ Admin endpoints accessible without authentication
- ⚠️ No brute force protection
- ⚠️ Error messages contain stack traces
- ⚠️ Cookies missing HttpOnly flag
- ⚠️ Missing .security.json files

**Critical Issues:**
- ❌ SQL injection succeeds
- ❌ Path traversal allows file access
- ❌ XSS payloads not sanitized
- ❌ Sessions don't persist
- ❌ Authentication bypass possible

---

## Troubleshooting

### Common Issues

**1. WebHost won't start**
```
Error: "The parameter is incorrect"
Fix: Ensure localhost binding is tried first (fixed in WebHost.ps1:82-90)
```

**2. URL ACL permission denied**
```
Error: "No URL ACL reservations found"
Fix: Run as admin: netsh http add urlacl url=http://+:8888/ user='DOMAIN\Username'
```

**3. Missing modules**
```
Error: "Module 'PSSQLite' not found"
Fix: Install-Module -Name PSSQLite, powershell-yaml, LogError
```

**4. Test user doesn't exist**
```
Error: "No user found with that email"
Fix: Run .\Setup-TestUser.ps1 first
```

**5. Port already in use**
```
Error: "Address already in use"
Fix: Use -Port parameter to specify different port
```

---

## Files Reference

| File | Lines | Purpose |
|------|-------|---------|
| `Test-AuthFlow.ps1` | 329 | Authentication flow testing |
| `Test-AllEndpoints.ps1` | 400+ | All API endpoint testing |
| `Test-Security.ps1` | 500+ | Security feature testing |
| `Test-RBAC.ps1` | 300+ | RBAC configuration analysis |
| `Run-AllTests.ps1` | 250+ | Master test runner |
| `Setup-TestUser.ps1` | 70 | Test user creation |
| `helpers/Start-WebHostForTest.psm1` | 185 | WebHost process management |
| `README.md` | This file | Documentation |

---

## Contributing

To add new tests:

1. Create test script: `Test-NewFeature.ps1`
2. Follow naming convention and structure
3. Add to `Run-AllTests.ps1`
4. Update this README with coverage details
5. Ensure tests clean up after themselves

---

## License

This testing framework is part of the PsWebHost project.

---

**Last Updated:** 2025-12-29
**Test Coverage:** 46 endpoints, 60+ test cases, 6 security categories
**Status:** ✅ Comprehensive testing infrastructure complete
