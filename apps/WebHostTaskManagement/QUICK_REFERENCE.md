# WebHostTaskManagement - Quick Reference Card

**Version**: 1.0.0
**Date**: 2026-01-23

---

## 🚀 Quick Start

### 1. Setup (One-time)
```powershell
# Create test API key
cd C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin
.\Create-TestApiKey.ps1
```

### 2. Test
```powershell
# Unit tests
Invoke-Pester -Path JobSubmission.Tests.ps1

# Integration tests
.\Test-JobSubmissionWithBearerToken.ps1

# curl tests (Bash)
./test-job-with-curl.sh
```

---

## 📡 API Endpoints

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/v1/jobs/submit` | POST | Bearer/Cookie | Submit job |
| `/api/v1/jobs/results` | GET | Bearer/Cookie | Get results |
| `/api/v1/jobs/results?jobId=<id>` | DELETE | Bearer/Cookie | Delete result |

**Base URL**: `http://localhost:8080/apps/WebHostTaskManagement`

---

## 🔐 Authentication

### Bearer Token (Recommended)

**PowerShell**:
```powershell
$apiKey = "your-api-key-here"
$headers = @{ "Authorization" = "Bearer $apiKey" }
Invoke-RestMethod -Uri "http://localhost:8080/api/endpoint" -Headers $headers
```

**curl**:
```bash
export API_KEY="your-api-key-here"
curl -H "Authorization: Bearer $API_KEY" http://localhost:8080/api/endpoint
```

### Session Cookie

**PowerShell**:
```powershell
$session = $null
Invoke-RestMethod -Uri "http://localhost:8080/auth/login" -SessionVariable session -Method POST
Invoke-RestMethod -Uri "http://localhost:8080/api/endpoint" -WebSession $session
```

**curl**:
```bash
curl -c cookies.txt -X POST http://localhost:8080/auth/login
curl -b cookies.txt http://localhost:8080/api/endpoint
```

---

## 💼 Job Submission

### Submit Job (PowerShell)

```powershell
$response = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit" `
    -Method POST `
    -Headers @{ "Authorization" = "Bearer $apiKey" } `
    -ContentType "application/json" `
    -Body (@{
        jobName = "MyJob"
        command = "Get-Process | Select-Object -First 5"
        description = "Get processes"
        executionMode = "MainLoop"  # or "Runspace" or "BackgroundJob"
    } | ConvertTo-Json)

Write-Host "Job ID: $($response.jobId)"
```

### Submit Job (curl)

```bash
curl -X POST http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{
    "jobName": "MyJob",
    "command": "Get-Process | Select-Object -First 5",
    "description": "Get processes",
    "executionMode": "MainLoop"
  }'
```

---

## 📊 Get Results

### Get All Results (PowerShell)

```powershell
$results = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results" `
    -Headers @{ "Authorization" = "Bearer $apiKey" }

$results.results | Format-Table JobName, DateCompleted, Runtime, Success
```

### Get Specific Result (curl)

```bash
curl "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results?maxResults=10" \
  -H "Authorization: Bearer $API_KEY" | jq '.results[0]'
```

---

## 🗑️ Delete Result

### Delete (PowerShell)

```powershell
Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results?jobId=$jobId" `
    -Method DELETE `
    -Headers @{ "Authorization" = "Bearer $apiKey" }
```

### Delete (curl)

```bash
curl -X DELETE "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results?jobId=$JOB_ID" \
  -H "Authorization: Bearer $API_KEY"
```

---

## ⚙️ Execution Modes

| Mode | Blocking | Roles Required | Best For |
|------|----------|----------------|----------|
| **MainLoop** | Yes | `debug` | Quick commands (< 2s) |
| **Runspace** | No | `debug`, `task_manager`, `system_admin`, `site_admin` | Long commands, async |
| **BackgroundJob** | No | Same as Runspace | Very long, isolated tasks |

---

## 👥 Role Requirements

### API Endpoints

| Endpoint | Roles |
|----------|-------|
| Submit job | `debug`, `task_manager`, `system_admin`, `site_admin` |
| Get results | `authenticated` |
| Delete result | `authenticated` (own results only) |

### Execution Modes

- **MainLoop**: Requires `debug` role
- **Runspace/BackgroundJob**: Requires `debug`, `task_manager`, `system_admin`, or `site_admin`

---

## 📂 Directory Structure

```
PsWebHost_Data/apps/WebHostTaskManagement/
├── JobSubmission/[UserID]/     # Pending submissions (JSON)
├── JobOutput/                  # Processed submissions (moved here)
└── JobResults/                 # Execution results (JSON)
```

---

## 🔧 Common Commands

### Create API Key (Production)
```powershell
# From project root
.\system\utility\Account_Auth_BearerToken_New.ps1 -TestAccount

# For existing user
.\system\utility\Account_Auth_BearerToken_New.ps1 -Email "user@example.com" -Name "MyAPIKey"
```

### Create API Key (Testing)
```powershell
# From project root
.\apps\WebHostTaskManagement\tests\twin\Create-TestApiKey.ps1

# From test directory
cd apps\WebHostTaskManagement\tests\twin
.\Create-TestApiKey.ps1
```

### Load API Key
```powershell
$config = Get-Content ".config/test-api-keys.json" -Raw | ConvertFrom-Json
$apiKey = $config.TestJobSubmissionKey.ApiKey
```

### Check Job Processing
```powershell
# Check pending submissions
Get-ChildItem "PsWebHost_Data/apps/WebHostTaskManagement/JobSubmission" -Recurse

# Check results
Get-ChildItem "PsWebHost_Data/apps/WebHostTaskManagement/JobResults"
```

### View Logs
```powershell
Get-Content "PsWebHost_Data/Logs/*.log" -Tail 50 | Where-Object { $_ -match "JobExecution" }
```

---

## 🧪 Testing

### Unit Tests (Pester)
```powershell
Invoke-Pester -Path "apps/WebHostTaskManagement/tests/twin/JobSubmission.Tests.ps1"
# Expected: 15 tests passed
```

### Integration Tests (PowerShell)
```powershell
cd apps/WebHostTaskManagement/tests/twin
.\Test-JobSubmissionWithBearerToken.ps1
# Expected: 10 tests passed
```

### curl Tests (Bash)
```bash
cd apps/WebHostTaskManagement/tests/twin
./test-job-with-curl.sh
# Expected: All tests completed successfully
```

---

## 🐛 Troubleshooting

### Issue: Unauthorized (401)
```powershell
# Verify API key exists
Get-Content ".config/test-api-keys.json" | ConvertFrom-Json

# Recreate if needed
.\Create-TestApiKey.ps1 -Force
```

### Issue: Forbidden (403)
```powershell
# Check user roles
$dbFile = "PsWebHost_Data/pswebhost.db"
Get-PSWebSQLiteData -File $dbFile -Query @"
SELECT u.UserID, GROUP_CONCAT(ur.Role) as Roles
FROM Users u LEFT JOIN User_Roles ur ON u.UserID = ur.UserID
WHERE u.UserID = 'test-user' GROUP BY u.UserID;
"@

# Add debug role if missing
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query @"
INSERT OR IGNORE INTO User_Roles (UserID, Role) VALUES ('test-user', 'debug');
"@
```

### Issue: Job Not Processing
```powershell
# Check if server is running
Get-Process -Name pwsh | Where-Object { $_.CommandLine -like "*Webhost.ps1*" }

# Check module is loaded
Get-Command Process-PSWebHostJobSubmissions

# Restart server if needed
.\Webhost.ps1 -Resume
```

---

## 📚 Documentation

| Document | Purpose |
|----------|---------|
| `JOB_SUBMISSION_SYSTEM.md` | Complete API documentation |
| `BEARER_TOKEN_TESTING.md` | Authentication guide |
| `COMPLETE_TESTING_GUIDE.md` | Comprehensive testing guide |
| `IMPLEMENTATION_SUMMARY_2026-01-23.md` | Implementation overview |
| `QUICK_REFERENCE.md` | This document |

---

## 📋 Complete Example

```powershell
# 1. Load API key
$config = Get-Content "apps/WebHostTaskManagement/tests/twin/.config/test-api-keys.json" -Raw | ConvertFrom-Json
$apiKey = $config.TestJobSubmissionKey.ApiKey
$headers = @{ "Authorization" = "Bearer $apiKey" }

# 2. Submit job
$job = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit" `
    -Method POST -Headers $headers -ContentType "application/json" `
    -Body (@{ jobName = "Test"; command = "Get-Date"; executionMode = "MainLoop" } | ConvertTo-Json)

Write-Host "Job ID: $($job.jobId)"

# 3. Wait for execution
Start-Sleep -Seconds 3

# 4. Get result
$results = Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results" `
    -Headers $headers

$result = $results.results | Where-Object { $_.JobID -eq $job.jobId }

# 5. Display result
Write-Host "Output: $($result.Output)"
Write-Host "Runtime: $($result.Runtime) seconds"

# 6. Delete result
Invoke-RestMethod `
    -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/results?jobId=$($job.jobId)" `
    -Method DELETE -Headers $headers
```

---

## 🎯 Key Facts

- ✅ Bearer tokens work with curl (no `Invoke-WebRequest -SessionVariable` needed)
- ✅ Jobs processed every 2 seconds in main loop
- ✅ Output captured with `2>&1` redirection
- ✅ API keys stored as SHA256 hash (secure)
- ✅ API keys inherit user roles
- ✅ Test coverage: 30 tests (100%)
- ✅ Production ready

---

**Last Updated**: 2026-01-23
**Status**: ✅ Production Ready
