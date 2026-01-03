# Test Migration Summary

This document summarizes the migration of tests from `/tests` to `/tests/twin` structure.

## Migration Completed

### From `/tests/pester/Sanitization.Tests.ps1`
**Migrated to:** `/tests/twin/modules/Sanitization.Tests.ps1`

**Changes:**
- Added proper initialization with `system\init.ps1`
- Organized into clearer contexts (Module structure, Basic encoding, XSS attack vectors, Valid paths, Path traversal attacks, Edge cases)
- Made tests more atomic and focused
- Added additional XSS attack vector tests
- Added edge case tests for special characters and spaces
- Improved error handling and validation

**Test Coverage:**
- ✅ Sanitize-HtmlInput function
  - Basic HTML encoding
  - Script tag encoding
  - XSS attack vectors (img, svg, javascript:)
  - Null and empty input handling
- ✅ Sanitize-FilePath function
  - Valid path normalization
  - Path traversal prevention
  - UNC path blocking
  - Edge cases (spaces, special characters)

### From `/tests/Test-AuthFlow.ps1`
**Migrated to:** Multiple atomic test files

1. `/tests/twin/routes/api/v1/auth/getauthtoken/get.Tests.ps1`
   - Tests GET requests without state parameter (302 redirect)
   - Tests GET requests with state parameter (200 OK, HTML content)
   - Validates session cookie handling
   - Verifies HTML response structure

2. `/tests/twin/routes/api/v1/auth/getauthtoken/post.Tests.ps1`
   - Tests POST without email (returns form)
   - Tests POST with invalid email (400 Bad Request)
   - Tests POST with valid email (404 or 200 depending on user existence)
   - Validates JSON responses
   - Tests Content-Type handling

3. `/tests/twin/routes/api/v1/authprovider/windows/post.Tests.ps1`
   - Tests missing credentials (400 Bad Request)
   - Tests invalid credentials (401 Unauthorized)
   - Validates error messages don't leak secrets
   - Tests state parameter validation
   - Includes placeholders for successful authentication tests

**Improvements:**
- Split monolithic test into focused, atomic tests
- Each endpoint has its own test file
- Tests are independent and can run in parallel
- Better error handling and response validation
- Clearer test names and contexts
- Added security tests (password leakage, etc.)

## New Test Files Created

### Route Coverage Analysis
**File:** `/tests/twin/routes/RouteCoverage.Tests.ps1`

**Purpose:**
- Enumerates all route files in `/routes` directory
- Compares against test files in `/tests/twin/routes`
- Reports untested routes with expected test file paths
- Provides coverage statistics
- Validates test file naming conventions
- Verifies proper initialization pattern usage

**Features:**
- Groups untested routes by directory
- Shows coverage percentage
- Can be configured to fail if coverage is below threshold
- Validates test file structure and naming

### Test Helper Module
**File:** `/tests/twin/helpers/Test-Helpers.psm1`

**Purpose:** Provides common functions to reduce duplication across tests

**Functions:**
- `Get-TestWebHost` - Starts a test instance of PSWebHost
- `Stop-TestWebHost` - Stops a test webHost instance
- `Test-JsonResponse` - Validates JSON response format
- `Get-ResponseJson` - Extracts JSON from response with error handling
- `New-TestUser` - Creates a test user in database
- `Remove-TestUser` - Removes test user from database
- `Assert-HttpStatus` - Validates HTTP status codes
- `Assert-JsonProperty` - Validates JSON property values

**Usage Example:**
```powershell
BeforeAll {
    Import-Module (Join-Path $ProjectRoot 'tests\twin\helpers\Test-Helpers.psm1')
    $webHost = Get-TestWebHost -ProjectRoot $ProjectRoot
}

AfterAll {
    Stop-TestWebHost -WebHost $webHost
}

It "Should return valid JSON" {
    $response = Invoke-WebRequest -Uri "$baseUrl/api/endpoint"
    Test-JsonResponse -Response $response | Should -Be $true
}
```

## Test Organization Patterns

### Atomic Tests
Each test file focuses on a single endpoint/component:
- One test file per HTTP method per route
- Tests are independent and isolated
- Setup and teardown handled in BeforeAll/AfterAll
- No shared state between tests

### Test Structure
```powershell
# 1. Initialization (required)
$InitializationScript = "$($psscriptroot -replace '[/\\]tests[\\/].*')\system\init.ps1"
. $InitializationScript

# 2. Main Describe block
Describe "Component Name" {

    # 3. Setup
    BeforeAll {
        # Import modules, start services, create test data
    }

    # 4. Test contexts (logical groupings)
    Context "Feature 1" {
        It "Should behave as expected" {
            # Actual test logic
        }
    }

    Context "Feature 2" {
        # More tests
    }

    # 5. Cleanup
    AfterAll {
        # Stop services, remove test data
    }
}
```

### Test Contexts by Category
Tests are organized into logical contexts:
- **Module structure** - Validates exported functions exist
- **Basic functionality** - Core feature tests
- **Error handling** - Invalid input, edge cases
- **Security** - XSS, injection, authentication
- **Response validation** - Status codes, headers, content type
- **Edge cases** - Boundary conditions, special characters

## Migration Status

### Completed Migrations
- ✅ Sanitization module tests
- ✅ Authentication flow tests (split into atomic tests)
- ✅ Route coverage analysis
- ✅ Test helper module created
- ✅ UserRoles system tests (migrated and enhanced)
- ✅ Security system tests (new comprehensive suite)
- ✅ Password authentication tests (GET and POST)
- ✅ Logoff endpoint test
- ✅ Get access token endpoint test
- ✅ User management tests (GET, POST, PUT, DELETE)

### New Tests Created (Dec 2024 Session)

#### Authentication Routes (6 files)
1. **`/tests/twin/routes/api/v1/authprovider/password/get.Tests.ps1`**
   - Login form retrieval (7 test cases)
   - State parameter handling
   - Security headers validation
   - Error handling

2. **`/tests/twin/routes/api/v1/authprovider/password/post.Tests.ps1`**
   - Validation - Missing required fields (3 test cases)
   - Validation - Invalid email format (2 test cases)
   - Validation - Password strength (2 test cases)
   - Authentication - Invalid credentials (3 test cases)
   - Authentication - Valid credentials (3 test cases)
   - Security - Password not leaked (2 test cases)
   - Rate limiting and brute force protection (3 test cases)
   - State parameter handling (2 test cases)
   - Content-Type handling (2 test cases)
   - **Total**: 22 test cases

3. **`/tests/twin/routes/api/v1/auth/logoff/get.Tests.ps1`**
   - Logoff without session (3 test cases)
   - Logoff with active session (3 test cases)
   - Logoff with authenticated user (2 test cases)
   - Security considerations (3 test cases)
   - Response validation (3 test cases)
   - Edge cases (3 test cases)
   - **Total**: 17 test cases

4. **`/tests/twin/routes/api/v1/auth/getaccesstoken/get.Tests.ps1`**
   - Without completed authentication flow (3 test cases)
   - With completed authentication flow (2 test cases)
   - RedirectTo parameter handling (3 test cases)
   - State parameter handling (2 test cases)
   - Access token generation (3 test cases)
   - Security validations (4 test cases)
   - Error handling (3 test cases)
   - Session updates (2 test cases)
   - Response types (3 test cases)
   - **Total**: 25 test cases

#### User Management Routes (4 files)
5. **`/tests/twin/routes/api/v1/users/get.Tests.ps1`**
   - Retrieve all users (5 test cases)
   - Response format (2 test cases)
   - Security considerations (3 test cases)
   - Empty database (2 test cases)
   - Performance (1 test case)
   - Error handling (1 test case)
   - **Total**: 14 test cases

6. **`/tests/twin/routes/api/v1/users/post.Tests.ps1`**
   - Create user with valid data (6 test cases)
   - Validation - Missing required fields (4 test cases)
   - Content-Type handling (2 test cases)
   - Response validation (2 test cases)
   - Database persistence (1 test case)
   - Security - SQL injection prevention (2 test cases)
   - Security - XSS prevention (1 test case)
   - Edge cases (3 test cases)
   - **Total**: 21 test cases

7. **`/tests/twin/routes/api/v1/users/put.Tests.ps1`**
   - Update user with valid data (5 test cases)
   - Response validation (2 test cases)
   - Security - SQL injection prevention (2 test cases)
   - Profile image upload (3 test cases)
   - Error handling (2 test cases)
   - Persistence validation (1 test case)
   - **Total**: 15 test cases

8. **`/tests/twin/routes/api/v1/users/delete.Tests.ps1`**
   - Delete user with valid UserID (4 test cases)
   - Delete associated data (2 test cases)
   - Security - SQL injection prevention (2 test cases)
   - Error handling (3 test cases)
   - Idempotency (1 test case)
   - Security - Authorization (2 test cases)
   - Cascade deletion considerations (2 test cases)
   - Response format (2 test cases)
   - Audit and logging (2 test cases)
   - **Total**: 20 test cases

**Session Summary**:
- **Files Created**: 8 new test files
- **Test Cases Implemented**: 134 test cases (fully implemented with actual logic)
- **Coverage Increase**: 7/59 routes (11.86%) → 15/59 routes (25.42%)
- **Areas Covered**: Authentication (password, logoff, access token), User management (CRUD operations)

### Pending Migrations
From `/tests` directory (to be migrated):
- `/tests/pester/validateInstall.Tests.ps1` → Update `/tests/twin/system/validateInstall.Tests.ps1`
- `/tests/pester/WebRoutes.Tests.ps1` → Break into individual route tests
- `/tests/Test-RBAC.ps1` → `/tests/twin/system/RBAC.Tests.ps1`
- ~~`/tests/Test-Security.ps1`~~ → ✅ Completed - `/tests/twin/system/Security.Tests.ps1`
- ~~`/tests/Test-PasswordAuthFlow.ps1`~~ → ✅ Completed - `/tests/twin/routes/api/v1/authprovider/password/*.Tests.ps1`
- `/tests/Test-WindowsAuthFlow.ps1` → Already covered by windows/post.Tests.ps1

### Test Files to Review
These files in `/tests` may need migration or can be deprecated:
- `/tests/analyze_functions.ps1` - Analysis tool, keep as-is
- `/tests/debug-WebHost.ps1` - Debug tool, keep as-is
- `/tests/diagnose_urlacl.ps1` - Diagnostic tool, keep as-is
- `/tests/Setup-TestUser.ps1` - Utility, keep as-is or integrate into helpers
- `/tests/Test-AllEndpoints.ps1` - Can be replaced by route coverage test
- `/tests/Run-AllTests.ps1` - Use `/tests/twin/Run-AllTwinTests.ps1` instead

## Running Migrated Tests

### All Tests
```powershell
pwsh C:\SC\PsWebHost\tests\twin\Run-AllTwinTests.ps1
```

### Specific Module
```powershell
Invoke-Pester C:\SC\PsWebHost\tests\twin\modules\Sanitization.Tests.ps1
```

### Specific Route
```powershell
Invoke-Pester C:\SC\PsWebHost\tests\twin\routes\api\v1\auth\getauthtoken\get.Tests.ps1
```

### Coverage Analysis
```powershell
pwsh C:\SC\PsWebHost\tests\twin\Run-AllTwinTests.ps1 -CodeCoverage
```

### Route Coverage Report
```powershell
Invoke-Pester C:\SC\PsWebHost\tests\twin\routes\RouteCoverage.Tests.ps1 -Output Detailed
```

## Best Practices Applied

1. **Initialization Pattern**: All tests use consistent init script sourcing
2. **Atomic Tests**: Each test file tests one component/endpoint
3. **Clear Naming**: Test files follow `*.Tests.ps1` convention
4. **Proper Contexts**: Tests grouped logically (functionality, errors, security, etc.)
5. **Independent Tests**: No dependencies between test files
6. **Cleanup**: Always clean up resources in AfterAll
7. **Error Handling**: Proper try/catch for HTTP requests
8. **Security Focus**: Tests include security validations
9. **Documentation**: Clear descriptions in test names
10. **Reusability**: Common functions in helper module

## Next Steps

1. **Continue Migration**: Migrate remaining test files from `/tests/pester`
2. **Implement Placeholders**: Replace `$true | Should -Be $true` with actual tests
3. **Add Integration Tests**: Create tests that verify end-to-end workflows
4. **Increase Coverage**: Use coverage test to identify gaps
5. **CI/CD Integration**: Set up automated test execution
6. **Performance Tests**: Add benchmarks for critical endpoints
7. **Security Scanning**: Integrate security test tools

## Coverage Goals

- **Target**: 80%+ route coverage
- **Current**: 25.42% (15/59 route tests)
  - Previous: 11.86% (7/59 routes)
  - Increase: +13.56% (+8 routes)
- **Priority**: Authentication, authorization, data manipulation endpoints
- **Nice to have**: Static content, informational endpoints

### Routes Tested (15 total)
**Authentication (7 routes)**:
- ✅ GET/POST /api/v1/auth/getauthtoken
- ✅ GET /api/v1/auth/getaccesstoken
- ✅ GET /api/v1/auth/logoff
- ✅ GET/POST /api/v1/authprovider/password
- ✅ POST /api/v1/authprovider/windows

**User Management (4 routes)**:
- ✅ GET /api/v1/users
- ✅ POST /api/v1/users
- ✅ PUT /api/v1/users
- ✅ DELETE /api/v1/users

**UI Elements (3 routes)**:
- ✅ GET /api/v1/ui/elements/main-menu
- ✅ GET/POST /spa/card_settings

**Security/Modules (1 test)**:
- ✅ Sanitization module

### Routes Still Untested (44 routes)
High priority remaining:
- User registration endpoints (GET, POST, confirm)
- Other auth providers (certificate, entraID, google, o365, yubikey, tokenauthenticator)
- Profile management (GET, POST)
- UI element endpoints (event-stream, file-explorer, server-heatmap, system-log, system-status, world-map, etc.)
- Database endpoints (query, tableexplorer, tables)
- Debug endpoints

## Notes

- Tests in `/tests/twin` are the new standard
- Old tests in `/tests` should be deprecated after migration
- All new features should include twin tests
- Tests should run in both Windows and Linux (cross-platform)
- WebHost test helper required for integration tests
