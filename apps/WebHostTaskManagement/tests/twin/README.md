# WebHostTaskManagement Twin Tests

## Overview

These tests validate the job submission and execution system in PSWebHost.

## Authentication for Tests

Tests can use Bearer token authentication for API calls. See `BEARER_TOKEN_TESTING.md` for details.

### Create Test API Key

```powershell
# Create test API key (only needed once)
.\Create-TestApiKey.ps1

# API key is stored in .config/test-api-keys.json for reuse
```

### Use Bearer Token in Tests

```powershell
# Load test API key
$testConfig = Get-Content ".config/test-api-keys.json" -Raw | ConvertFrom-Json
$apiKey = $testConfig.TestJobSubmissionKey.ApiKey

# Use in API calls
Invoke-RestMethod -Uri "http://localhost:8080/api/endpoint" `
    -Headers @{ "Authorization" = "Bearer $apiKey" }
```

## Running Tests

### Run all tests:
```powershell
Invoke-Pester -Path "C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin\JobSubmission.Tests.ps1"
```

### Run specific test context:
```powershell
Invoke-Pester -Path "C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin\JobSubmission.Tests.ps1" -Tag "JobSubmission"
```

### Run with verbose output:
```powershell
Invoke-Pester -Path "C:\SC\PsWebHost\apps\WebHostTaskManagement\tests\twin\JobSubmission.Tests.ps1" -Output Detailed
```

## Test Coverage

### Job Submission
- ✅ Submit job with debug role (MainLoop)
- ✅ Submit job with task_manager role (Runspace)
- ✅ Submit job with system_admin role (BackgroundJob)
- ✅ Reject MainLoop without debug role
- ✅ Reject Runspace/BackgroundJob without elevated roles

### Job Execution - MainLoop Mode
- ✅ Execute simple command
- ✅ Capture errors
- ✅ Record execution timing

### Job Execution - Runspace Mode
- ✅ Start job in dedicated runspace
- ✅ Verify async execution
- ✅ Verify result file creation

### Job Execution - Background Job Mode
- ✅ Start PowerShell background job
- ✅ Wait for completion
- ✅ Verify result file

### Job Results Management
- ✅ Retrieve results for user
- ✅ Delete job results
- ✅ Verify ownership filtering

### Integration Tests
- ✅ Process pending submissions from file system
- ✅ Move submissions to output directory
- ✅ Generate results

## Prerequisites

- PowerShell 7+
- Pester 5.x
- PSWebHost modules loaded
- Write access to PsWebHost_Data directory

## Test Data

Tests create temporary job submissions in:
- `PsWebHost_Data/apps/WebHostTaskManagement/JobSubmission/test-user*/`
- `PsWebHost_Data/apps/WebHostTaskManagement/JobOutput/`
- `PsWebHost_Data/apps/WebHostTaskManagement/JobResults/`

All test data is automatically cleaned up after tests complete.

## Expected Behavior

All tests should pass without errors. If tests fail:

1. **Check module loading**: Ensure PSWebHost_JobExecution module exists
2. **Check directory permissions**: Ensure write access to PsWebHost_Data
3. **Check for conflicts**: Ensure no other processes are using test files
4. **Check logs**: Review PSWebHost logs for errors

## Continuous Integration

These tests are designed to run in CI/CD pipelines:

```yaml
- name: Run Job Submission Tests
  run: |
    pwsh -Command "Invoke-Pester -Path 'apps/WebHostTaskManagement/tests/twin/JobSubmission.Tests.ps1' -CI"
```
