# Bearer Token Authentication for Testing

**Date**: 2026-01-23
**Status**: ✅ Complete

---

## Overview

PSWebHost supports Bearer token authentication via API keys. This document explains how to use Bearer tokens for testing the Job Submission System and other APIs.

**Answer to "Can Bearer tokens be used with curl?"**: **YES**. Bearer tokens work perfectly with curl using the `Authorization: Bearer <token>` header. No need for `Invoke-WebRequest -SessionVariable`.

---

## Quick Start

### 1. Create a Test API Key

**Option A: Using utility script (recommended)**:
```powershell
# From project root - Create test account with Bearer token
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount

# Assign debug role (required for MainLoop job execution)
.\system\utility\RoleAssignment_New.ps1 -Email "TA_Bearer_XyZ12@localhost" -RoleName "debug"

# Output will show:
# Bearer Token Created Successfully!
# ========================================
# KeyID:       abc-123-def...
# Name:        TestBearerKey_XyZ12
# UserID:      generated-user-id
# Email:       TA_Bearer_XyZ12@localhost
# API Key:     abcdefgh1234567890...
# ========================================
```

**Option B: Using test-specific script (all-in-one)**:
```powershell
# From project root or test directory - Creates user, assigns debug role, creates API key
.\apps\WebHostTaskManagement\tests\twin\Create-TestApiKey.ps1

# Output will show:
# Creating test user and Bearer token...
# Creating test user: TA_JobTest_XyZ12@localhost
#   Created user: guid-here
#   Checking for 'debug' role...
#   Adding 'debug' role...
# Creating API key 'TestJobSubmissionKey'...
# API key created successfully!
```

The API key is saved to `.config/test-api-keys.json` for reuse in tests.

### 2. Test with curl

```bash
# Using the generated API key
export API_KEY="your-api-key-here"

# Submit a job
curl -X POST http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "TestJob",
    "command": "Get-Date; Write-Output '\''Hello World'\''",
    "description": "Test job via Bearer token",
    "executionMode": "MainLoop"
  }'

# Get job results
curl http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results \
  -H "Authorization: Bearer $API_KEY"

# Delete a job result
curl -X DELETE "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results?jobId=your-job-id" \
  -H "Authorization: Bearer $API_KEY"
```

### 3. Test with PowerShell

```powershell
# Load the API key from test config
$testConfig = Get-Content "C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin\.config\test-api-keys.json" -Raw | ConvertFrom-Json
$apiKey = $testConfig.TestJobSubmissionKey.ApiKey

# Submit a job
$response = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit" `
    -Method POST `
    -Headers @{ "Authorization" = "Bearer $apiKey" } `
    -ContentType "application/json" `
    -Body (@{
        jobName = "TestJob"
        command = "Get-Process | Select-Object -First 5"
        description = "Test job"
        executionMode = "MainLoop"
    } | ConvertTo-Json)

Write-Host "Job ID: $($response.jobId)"

# Wait for execution
Start-Sleep -Seconds 3

# Get results
$results = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results" `
    -Headers @{ "Authorization" = "Bearer $apiKey" }

$results.results | Format-Table JobName, DateCompleted, Runtime, Success
```

---

## How Bearer Token Authentication Works

### 1. Token Generation

API keys are generated using `New-DatabaseApiKey`:

```powershell
$apiKey = New-DatabaseApiKey `
    -Name "MyTestKey" `
    -UserID "test-user" `
    -Description "Test API key" `
    -CreatedBy "system"

# Returns: KeyID, Name, UserID, ApiKey (plaintext, only returned once)
```

The key is:
- **32 bytes** of cryptographically secure random data
- **Base64 encoded** for transmission
- **SHA256 hashed** for storage in database
- **Linked to a UserID** (inherits user's roles)

### 2. Token Storage

API keys are stored in the `API_Keys` table:

| Column | Description |
|--------|-------------|
| KeyID | Unique identifier (GUID) |
| Name | Human-readable name |
| KeyHash | SHA256 hash of the API key |
| UserID | User this key belongs to |
| AllowedIPs | Comma-separated IP restrictions (empty = all) |
| CreatedBy | Who created the key |
| CreatedAt | Timestamp |
| ExpiresAt | Optional expiration |
| Enabled | Active status (1/0) |

### 3. Authentication Flow

When a request includes `Authorization: Bearer <token>`:

1. **Extract Token**: PSWebHost parses the `Authorization` header
2. **Hash Token**: Computes SHA256 hash of the provided token
3. **Database Lookup**: Finds matching `KeyHash` in `API_Keys` table
4. **Validation**: Checks:
   - Key is enabled
   - Key hasn't expired
   - IP is allowed (if restrictions set)
5. **Load User**: Gets user data and roles from `UserID`
6. **Create In-Memory Session**:
   - Checks if session cookie exists
   - If no cookie, generates new SessionID
   - Creates session in `$global:PSWebSessions` (fast, in-memory)
   - Includes: UserID, Provider="API_Key", Roles, AuthTokenExpiration, LastUpdated
7. **Process Request**: Request proceeds immediately with authenticated session

**Session Persistence (Eventual Consistency)**:
- ✅ Sessions created in memory immediately (fast path)
- ✅ Sessions synced to database every **1 minute** by `Sync-SessionStateToDatabase`
- ✅ New sessions (Bearer token, etc.) are automatically created in database on first sync
- ✅ Existing sessions are updated if memory version is newer
- ✅ Provides audit trail for API key usage
- ✅ Session expires after 1 hour (renewable on each request)
- ✅ Session cookie returned in response (optional for Bearer auth)

**Performance Benefits**:
- Fast authentication (no database write on hot path)
- Eventual consistency pattern reduces latency
- Database writes batched every 1 minute
- Follows same pattern as other authentication methods

**Code References**:
- Bearer token auth: `modules/PSWebHost_Support/PSWebHost_Support.psm1:596-650`
- Session sync: `modules/PSWebHost_Support/PSWebHost_Support.psm1:1592-1610`
- Sync trigger: `Webhost.ps1:729-732` (every 1 minute)

---

## Creating API Keys

### Utility Script: Account_Auth_BearerToken_New.ps1

**Location**: `system/utility/Account_Auth_BearerToken_New.ps1`

**Features**:
- Creates Bearer token (API key) for existing or new users
- `-TestAccount` switch creates temporary test user automatically
- Supports IP restrictions and expiration dates
- Follows same pattern as `Account_AuthProvider_Password_New.ps1`

**Usage**:

```powershell
# Create test account with Bearer token (from project root)
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount

# Create Bearer token for existing user by UserID
.\system\utility\Account_Auth_BearerToken_New.ps1 -UserID "user-123" -Name "ProductionKey"

# Create Bearer token for existing user by Email
.\system\utility\Account_Auth_BearerToken_New.ps1 -Email "user@example.com" -Name "UserAPIKey"

# Create with IP restrictions
.\system\utility\Account_Auth_BearerToken_New.ps1 -UserID "user-123" -AllowedIPs @('192.168.1.100') -Name "RestrictedKey"

# Create with expiration
.\system\utility\Account_Auth_BearerToken_New.ps1 -UserID "user-123" -ExpiresAt (Get-Date).AddMonths(6) -Name "TempKey"
```

### Test Script: Create-TestApiKey.ps1

**Location**: `apps/WebHostTaskManagement/tests/twin/Create-TestApiKey.ps1`

**Features**:
- Simplified test key creation for job submission tests
- Stores keys in `.config/test-api-keys.json` for reuse
- Can be called from project root or test directory
- Prevents duplicate key creation (unless `-Force`)

**Usage**:

```powershell
# From project root
.\apps\WebHostTaskManagement\tests\twin\Create-TestApiKey.ps1

# From test directory
cd apps\WebHostTaskManagement\tests\twin
.\Create-TestApiKey.ps1

# Create key for specific user
.\Create-TestApiKey.ps1 -UserID "existing-user" -Name "MyTestKey"

# Force recreate existing key
.\Create-TestApiKey.ps1 -Force
```

### Manual Key Creation

```powershell
# Import authentication module
Import-Module "C:\SC\PsWebHost\modules\PSWebHost_Authentication\PSWebHost_Authentication.psd1"

# Create API key
$key = New-DatabaseApiKey `
    -Name "ProductionKey" `
    -UserID "admin-user" `
    -Description "Production API key" `
    -ExpiresAt (Get-Date).AddMonths(6) `
    -AllowedIPs @('192.168.1.100', '192.168.1.101') `
    -CreatedBy "admin"

# Save the key - this is the ONLY time it's available in plaintext!
Write-Host "API Key: $($key.ApiKey)" -ForegroundColor Yellow
```

---

## API Key Management

### List All API Keys

```powershell
$dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"

Get-PSWebSQLiteData -File $dbFile -Query @"
SELECT KeyID, Name, UserID, CreatedBy, CreatedAt, ExpiresAt, Enabled
FROM API_Keys
ORDER BY CreatedAt DESC;
"@
```

### Disable an API Key

```powershell
# Using Remove-DatabaseApiKey function
Remove-DatabaseApiKey -KeyID "abc-123-def..."

# Or directly
$dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query @"
UPDATE API_Keys SET Enabled = 0 WHERE KeyID = 'abc-123-def...';
"@
```

### Revoke All Keys for a User

```powershell
$dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query @"
UPDATE API_Keys SET Enabled = 0 WHERE UserID = 'test-user';
"@
```

---

## Testing Examples

### Example 1: Job Submission Test with Bearer Token

```powershell
# Load test API key
$configPath = "C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin\.config\test-api-keys.json"
$testConfig = Get-Content $configPath -Raw | ConvertFrom-Json
$apiKey = $testConfig.TestJobSubmissionKey.ApiKey

# Submit job
$jobResponse = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit" `
    -Method POST `
    -Headers @{ "Authorization" = "Bearer $apiKey" } `
    -ContentType "application/json" `
    -Body (@{
        jobName = "GetProcesses"
        command = "Get-Process | Select-Object -First 10 | ConvertTo-Json"
        description = "Get top 10 processes"
        executionMode = "MainLoop"
    } | ConvertTo-Json)

Write-Host "Job submitted: $($jobResponse.jobId)" -ForegroundColor Green

# Wait for execution (MainLoop processes every 2 seconds)
Start-Sleep -Seconds 3

# Get results
$results = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results" `
    -Headers @{ "Authorization" = "Bearer $apiKey" }

# Find our job result
$jobResult = $results.results | Where-Object { $_.JobID -eq $jobResponse.jobId }

if ($jobResult) {
    Write-Host "`nJob completed successfully!" -ForegroundColor Green
    Write-Host "Runtime: $($jobResult.Runtime) seconds"
    Write-Host "Output:" -ForegroundColor Cyan
    Write-Host $jobResult.Output
} else {
    Write-Host "Job not completed yet" -ForegroundColor Yellow
}
```

### Example 2: curl Test Script

**File**: `test-job-submission-curl.sh`

```bash
#!/bin/bash

# Load API key from config
API_KEY=$(jq -r '.TestJobSubmissionKey.ApiKey' .config/test-api-keys.json)

if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "Error: API key not found. Run Create-TestApiKey.ps1 first."
    exit 1
fi

echo "Using API Key: ${API_KEY:0:20}..."

# Submit job
echo "Submitting job..."
RESPONSE=$(curl -s -X POST http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "TestCurlJob",
    "command": "Get-Date; Write-Output \"Hello from curl\"",
    "description": "Test job via curl",
    "executionMode": "MainLoop"
  }')

echo "$RESPONSE" | jq '.'

JOB_ID=$(echo "$RESPONSE" | jq -r '.jobId')

if [ "$JOB_ID" = "null" ]; then
    echo "Error: Failed to submit job"
    exit 1
fi

echo "Job ID: $JOB_ID"

# Wait for execution
echo "Waiting for job execution..."
sleep 3

# Get results
echo "Fetching results..."
curl -s http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results \
  -H "Authorization: Bearer $API_KEY" | jq ".results[] | select(.JobID == \"$JOB_ID\")"
```

### Example 3: Pester Test with Bearer Token

```powershell
BeforeAll {
    # Load test API key
    $configPath = Join-Path $PSScriptRoot ".config\test-api-keys.json"

    if (-not (Test-Path $configPath)) {
        # Create API key if doesn't exist
        & (Join-Path $PSScriptRoot "Create-TestApiKey.ps1")
    }

    $testConfig = Get-Content $configPath -Raw | ConvertFrom-Json
    $script:ApiKey = $testConfig.TestJobSubmissionKey.ApiKey
    $script:BaseUri = "http://localhost:8080/apps/WebHostTaskManagement/api/v1"
    $script:Headers = @{ "Authorization" = "Bearer $($script:ApiKey)" }
}

Describe "Job Submission API with Bearer Token" {
    It "Should submit a job with Bearer token" {
        $body = @{
            jobName = "PesterTest"
            command = "Write-Output 'Test from Pester'"
            executionMode = "MainLoop"
        } | ConvertTo-Json

        $response = Invoke-RestMethod `
            -Uri "$script:BaseUri/jobs/submit" `
            -Method POST `
            -Headers $script:Headers `
            -ContentType "application/json" `
            -Body $body

        $response.success | Should -Be $true
        $response.jobId | Should -Not -BeNullOrEmpty
    }

    It "Should retrieve job results with Bearer token" {
        $results = Invoke-RestMethod `
            -Uri "$script:BaseUri/jobs/results" `
            -Headers $script:Headers

        $results.success | Should -Be $true
        $results.count | Should -BeGreaterOrEqual 0
    }
}
```

---

## Security Considerations

### 1. Key Storage

**Test Environment**:
- ✅ Store keys in `.config/test-api-keys.json` (git-ignored)
- ✅ Use short-lived keys
- ✅ Recreate keys for each test run if needed

**Production Environment**:
- ❌ NEVER commit API keys to git
- ❌ NEVER log API keys in plaintext
- ✅ Store keys in secure key management system (Azure Key Vault, etc.)
- ✅ Use environment variables for CI/CD pipelines
- ✅ Set expiration dates on all keys
- ✅ Set IP restrictions when possible

### 2. Key Rotation

```powershell
# Disable old key
Remove-DatabaseApiKey -Name "OldTestKey"

# Create new key
.\Create-TestApiKey.ps1 -Name "NewTestKey" -Force

# Update test config to use new key
```

### 3. Monitoring

Monitor API key usage:

```powershell
# Check authentication logs
$dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"

Get-PSWebSQLiteData -File $dbFile -Query @"
SELECT * FROM Logs
WHERE Category = 'Auth'
AND Message LIKE '%API key%'
ORDER BY Timestamp DESC
LIMIT 50;
"@
```

---

## Troubleshooting

### Issue: "Unauthorized" Error

**Problem**: API request returns 401 Unauthorized

**Solutions**:
1. Verify API key is correct:
   ```powershell
   $testConfig = Get-Content ".config/test-api-keys.json" -Raw | ConvertFrom-Json
   Write-Host "API Key: $($testConfig.TestJobSubmissionKey.ApiKey)"
   ```

2. Check key is enabled in database:
   ```powershell
   $dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"
   Get-PSWebSQLiteData -File $dbFile -Query @"
   SELECT KeyID, Name, Enabled, ExpiresAt FROM API_Keys WHERE Name = 'TestJobSubmissionKey';
   "@
   ```

3. Verify Authorization header format:
   ```bash
   # Correct format
   Authorization: Bearer abc123...

   # Incorrect formats
   Authorization: abc123...           # Missing "Bearer "
   Authorization: Bearer: abc123...   # Extra colon
   Authorization: "Bearer abc123..."  # Quoted
   ```

### Issue: "Forbidden" Error

**Problem**: API request returns 403 Forbidden

**Solutions**:
1. Check user roles:
   ```powershell
   $dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"
   Get-PSWebSQLiteData -File $dbFile -Query @"
   SELECT u.UserID, u.DisplayName, GROUP_CONCAT(ur.Role) as Roles
   FROM Users u
   LEFT JOIN User_Roles ur ON u.UserID = ur.UserID
   WHERE u.UserID = 'test-user'
   GROUP BY u.UserID;
   "@
   ```

2. Job submission requires elevated roles:
   - MainLoop: requires `debug` role
   - Runspace/BackgroundJob: requires `debug`, `task_manager`, `system_admin`, or `site_admin`

3. Add required role:
   ```powershell
   $dbFile = "C:\SC\PsWebHost\PsWebHost_Data\pswebhost.db"
   Invoke-PSWebSQLiteNonQuery -File $dbFile -Query @"
   INSERT INTO User_Roles (UserID, Role) VALUES ('test-user', 'debug');
   "@
   ```

### Issue: API Key Not Found

**Problem**: `.config/test-api-keys.json` doesn't exist

**Solution**:
```powershell
# Create test API key
cd C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin
.\Create-TestApiKey.ps1
```

### Issue: curl JSON Parsing Errors

**Problem**: curl fails to parse JSON response

**Solution**: Use `-s` (silent) and pipe to `jq`:
```bash
# Good
curl -s http://localhost:8080/api/endpoint \
  -H "Authorization: Bearer $API_KEY" | jq '.'

# Bad (shows progress, breaks JSON parsing)
curl http://localhost:8080/api/endpoint \
  -H "Authorization: Bearer $API_KEY"
```

---

## Comparison: Bearer Token vs Session Cookie

| Aspect | Bearer Token | Session Cookie |
|--------|-------------|----------------|
| **Authentication** | `Authorization: Bearer <token>` | `Cookie: PSWebSessionID=<id>` |
| **curl Support** | ✅ Native | ✅ `-H "Cookie: ..."` |
| **PowerShell** | ✅ Headers | ✅ `-SessionVariable` or Headers |
| **Expiration** | Optional (set on key) | Session timeout |
| **Revocation** | Disable key in DB | Logout endpoint |
| **Best For** | API testing, automation, CI/CD | Interactive web use |
| **Security** | Key must be stored securely | Cookie managed by browser |

**For Testing**: Bearer tokens are recommended because:
- No need to maintain session state
- Easier to use in scripts and curl
- Can create/revoke keys programmatically
- Better for CI/CD pipelines

---

## Summary

✅ **Bearer tokens work perfectly with curl** - just use `Authorization: Bearer <token>` header
✅ **No need for `Invoke-WebRequest -SessionVariable`** - Bearer tokens are simpler for API testing
✅ **Create test keys with `Create-TestApiKey.ps1`** - keys stored in `.config/` for reuse
✅ **API keys inherit user roles** - link to test user with appropriate roles
✅ **Keys are secure** - stored as SHA256 hash, plaintext only shown once

**Quick Test**:
```bash
# Create key
pwsh -File Create-TestApiKey.ps1

# Load key and test
export API_KEY=$(jq -r '.TestJobSubmissionKey.ApiKey' .config/test-api-keys.json)
curl -H "Authorization: Bearer $API_KEY" http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results
```

---

## References

- **Authentication Module**: `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1`
- **Bearer Token Handler**: `modules/PSWebHost_Support/PSWebHost_Support.psm1:596-642`
- **Job Submission API**: `apps/WebHostTaskManagement/routes/api/v1/jobs/`
- **Test Utilities**: `apps/WebHostTaskManagement/tests/twin/`
- **Job Submission Docs**: `apps/WebHostTaskManagement/JOB_SUBMISSION_SYSTEM.md`
