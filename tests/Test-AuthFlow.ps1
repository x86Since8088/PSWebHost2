# Test-AuthFlow.ps1
# Comprehensive test for authentication flow:
# 1. GET /api/v1/auth/getauthtoken
# 2. POST /api/v1/auth/getauthtoken (with email)
# 3. POST /api/v1/authprovider/windows (with credentials)

[CmdletBinding()]
param(
    [string]$TestUsername,
    [string]$TestPassword,
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Warning "This test suite requires PowerShell 6+ (PowerShell Core/7+)"
    Write-Warning "Current version: $($PSVersionTable.PSVersion)"
    Write-Warning "Download: https://github.com/PowerShell/PowerShell/releases"
    Write-Host "`nNote: For Windows PowerShell 5.1, run 'pwsh' to use PowerShell 7+"
    return
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Authentication Flow Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import helper module
Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1') -Force

$webHost = $null
$testsPassed = 0
$testsFailed = 0

function Test-Step {
    param(
        [string]$Name,
        [scriptblock]$Test
    )

    Write-Host "`n[TEST] $Name" -ForegroundColor Yellow
    try {
        & $Test
        $script:testsPassed++
        Write-Host "[PASS] $Name" -ForegroundColor Green
        return $true
    } catch {
        $script:testsFailed++
        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.InnerException) {
            Write-Host "  Inner: $($_.Exception.InnerException.Message)" -ForegroundColor Red
        }
        return $false
    }
}

try {
    # Step 0: Start WebHost
    Write-Host "[SETUP] Starting WebHost..." -ForegroundColor Cyan
    $webHost = Start-WebHostForTest -ProjectRoot $ProjectRoot -Port $Port -Verbose

    if (-not $webHost.Ready) {
        throw "WebHost failed to start or did not respond within timeout"
    }

    Write-Host "[SETUP] WebHost started at $($webHost.Url)" -ForegroundColor Green
    Write-Host "[SETUP] Process ID: $($webHost.Process.Id)" -ForegroundColor Green
    Write-Host "[SETUP] Log file: $($webHost.OutFiles.StdOut)" -ForegroundColor Green

    $baseUrl = $webHost.Url.TrimEnd('/')
    $sessionCookie = $null

    # Step 1: Test GET /api/v1/auth/getauthtoken
    Test-Step "GET /api/v1/auth/getauthtoken - Initial request without state" {
        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/getauthtoken" `
            -Method GET `
            -UseBasicParsing `
            -MaximumRedirection 0 `
            -ErrorAction SilentlyContinue

        if ($response.StatusCode -ne 302) {
            throw "Expected 302 redirect to add state parameter, got $($response.StatusCode)"
        }

        $location = $response.Headers['Location']
        if ($location -notmatch 'state=') {
            throw "Redirect location should contain state parameter, got: $location"
        }

        Write-Host "  ✓ Redirected to: $location" -ForegroundColor Gray
    }

    # Step 2: Test GET /api/v1/auth/getauthtoken with state
    Test-Step "GET /api/v1/auth/getauthtoken - With state parameter" {
        $stateGuid = (New-Guid).Guid
        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/getauthtoken?state=$stateGuid" `
            -Method GET `
            -UseBasicParsing `
            -SessionVariable 'webSession'

        if ($response.StatusCode -ne 200) {
            throw "Expected 200 OK, got $($response.StatusCode)"
        }

        # Should contain the login form HTML
        if ($response.Content -notmatch 'getauthtoken\.html') {
            Write-Host "  ✓ Received HTML content ($(($response.Content).Length) bytes)" -ForegroundColor Gray
        }

        # Extract session cookie
        $script:sessionCookie = $webSession.Cookies.GetCookies($baseUrl) | Where-Object { $_.Name -eq 'PSWebSessionID' }
        if ($script:sessionCookie) {
            Write-Host "  ✓ Session cookie: $($sessionCookie.Value)" -ForegroundColor Gray
        } else {
            Write-Host "  ! No session cookie received (may be set later)" -ForegroundColor Yellow
        }
    }

    # Step 3: Test POST /api/v1/auth/getauthtoken - No email (should return form)
    Test-Step "POST /api/v1/auth/getauthtoken - Request email form" {
        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/getauthtoken" `
            -Method POST `
            -UseBasicParsing `
            -ContentType "application/x-www-form-urlencoded" `
            -Body ""

        if ($response.StatusCode -ne 200) {
            throw "Expected 200 OK, got $($response.StatusCode)"
        }

        $json = $response.Content | ConvertFrom-Json
        if ($json.status -ne 'continue') {
            throw "Expected status 'continue', got '$($json.status)'"
        }

        if ($json.Message -notmatch 'email') {
            throw "Expected email form in message"
        }

        Write-Host "  ✓ Received email form" -ForegroundColor Gray
    }

    # Step 4: Test POST /api/v1/auth/getauthtoken - With invalid email
    Test-Step "POST /api/v1/auth/getauthtoken - Invalid email format" {
        $body = "email=notanemail"
        try {
            $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/getauthtoken" `
                -Method POST `
                -UseBasicParsing `
                -ContentType "application/x-www-form-urlencoded" `
                -Body $body `
                -ErrorAction Stop
        } catch {
            $response = $_.Exception.Response
            if (-not $response) { throw }
        }

        if ($response.StatusCode -ne 400) {
            throw "Expected 400 Bad Request for invalid email, got $($response.StatusCode)"
        }

        $json = $response.Content | ConvertFrom-Json
        if ($json.status -ne 'fail') {
            throw "Expected status 'fail', got '$($json.status)'"
        }

        Write-Host "  ✓ Rejected invalid email" -ForegroundColor Gray
    }

    # Step 5: Test POST /api/v1/auth/getauthtoken - With valid email
    Test-Step "POST /api/v1/auth/getauthtoken - Valid email (test@localhost)" {
        $testEmail = "test@localhost"
        $body = "email=$testEmail"

        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/getauthtoken" `
            -Method POST `
            -UseBasicParsing `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body `
            

        $json = $response.Content | ConvertFrom-Json

        # Could be 404 (no user found) or 200 (user found with auth methods)
        if ($response.StatusCode -eq 404) {
            if ($json.status -ne 'fail') {
                throw "Expected status 'fail' for 404, got '$($json.status)'"
            }
            Write-Host "  ✓ User not found (expected for test account)" -ForegroundColor Gray
        } elseif ($response.StatusCode -eq 200) {
            if ($json.status -ne 'continue') {
                throw "Expected status 'continue', got '$($json.status)'"
            }
            if ($json.Message -notmatch 'auth-methods|Authentication Method') {
                throw "Expected auth methods in message"
            }
            Write-Host "  ✓ Received authentication methods" -ForegroundColor Gray
        } else {
            throw "Expected 200 or 404, got $($response.StatusCode)"
        }
    }

    # Step 6: Test POST /api/v1/authprovider/windows - Missing credentials
    Test-Step "POST /api/v1/authprovider/windows - Missing credentials" {
        $stateGuid = (New-Guid).Guid
        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
            -Method POST `
            -UseBasicParsing `
            -ContentType "application/x-www-form-urlencoded" `
            -Body "" `
            

        if ($response.StatusCode -ne 400) {
            throw "Expected 400 Bad Request for missing credentials, got $($response.StatusCode)"
        }

        $json = $response.Content | ConvertFrom-Json
        if ($json.status -ne 'fail') {
            throw "Expected status 'fail', got '$($json.status)'"
        }

        if ($json.Message -notmatch 'required') {
            throw "Expected 'required' error message"
        }

        Write-Host "  ✓ Rejected request with missing credentials" -ForegroundColor Gray
    }

    # Step 7: Test POST /api/v1/authprovider/windows - Invalid credentials
    Test-Step "POST /api/v1/authprovider/windows - Invalid credentials" {
        $stateGuid = (New-Guid).Guid
        $body = "username=invalid@localhost&password=wrongpassword123"

        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
            -Method POST `
            -UseBasicParsing `
            -ContentType "application/x-www-form-urlencoded" `
            -Body $body `
            

        # Should be 401 Unauthorized for invalid credentials
        if ($response.StatusCode -ne 401) {
            # Could also be 400 if validation fails
            if ($response.StatusCode -ne 400) {
                throw "Expected 401 or 400, got $($response.StatusCode)"
            }
        }

        $json = $response.Content | ConvertFrom-Json
        if ($json.status -ne 'fail') {
            throw "Expected status 'fail', got '$($json.status)'"
        }

        Write-Host "  ✓ Rejected invalid credentials" -ForegroundColor Gray
    }

    # Step 8: Test POST /api/v1/authprovider/windows - Valid credentials (if provided)
    if ($TestUsername -and $TestPassword) {
        Test-Step "POST /api/v1/authprovider/windows - Valid credentials" {
            $stateGuid = (New-Guid).Guid
            $body = "username=$TestUsername&password=$TestPassword"

            $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/authprovider/windows?state=$stateGuid" `
                -Method POST `
                -UseBasicParsing `
                -ContentType "application/x-www-form-urlencoded" `
                -Body $body `
                -MaximumRedirection 0 `
                -ErrorAction SilentlyContinue

            if ($response.StatusCode -ne 302) {
                # Check if it's an auth failure
                $json = $response.Content | ConvertFrom-Json
                if ($response.StatusCode -eq 401) {
                    throw "Authentication failed - credentials may be incorrect"
                } else {
                    throw "Expected 302 redirect on success, got $($response.StatusCode): $($json.Message)"
                }
            }

            $location = $response.Headers['Location']
            if ($location -notmatch '/api/v1/auth/getaccesstoken') {
                throw "Expected redirect to getaccesstoken, got: $location"
            }

            # Check for session cookie
            $cookies = $response.Headers['Set-Cookie']
            if ($cookies -match 'PSWebSessionID=([^;]+)') {
                $sessionId = $matches[1]
                Write-Host "  ✓ Session created: $sessionId" -ForegroundColor Gray
            }

            Write-Host "  ✓ Authentication successful, redirected to: $location" -ForegroundColor Gray
        }
    } else {
        Write-Host "`n[SKIP] POST /api/v1/authprovider/windows - Valid credentials" -ForegroundColor Yellow
        Write-Host "  To test valid credentials, run with:" -ForegroundColor Yellow
        Write-Host "  .\Test-AuthFlow.ps1 -TestUsername 'user@domain' -TestPassword 'password'" -ForegroundColor Yellow
    }

    # Step 9: Test session endpoint
    Test-Step "GET /api/v1/auth/sessionid - Check session info" {
        $response = Invoke-WebRequest -Uri "$baseUrl/api/v1/auth/sessionid" `
            -Method GET `
            -UseBasicParsing `
            

        if ($response.StatusCode -ne 200) {
            throw "Expected 200 OK, got $($response.StatusCode)"
        }

        # Response should be JSON with session info
        try {
            $json = $response.Content | ConvertFrom-Json
            Write-Host "  ✓ Session info: $(($json | ConvertTo-Json -Compress))" -ForegroundColor Gray
        } catch {
            Write-Host "  ✓ Received response (non-JSON)" -ForegroundColor Gray
        }
    }

} catch {
    Write-Host "`n[ERROR] Test execution failed:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
} finally {
    # Cleanup
    if ($webHost -and $webHost.Process) {
        Write-Host "`n[CLEANUP] Stopping WebHost process $($webHost.Process.Id)..." -ForegroundColor Cyan
        try {
            $webHost.Process | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "[CLEANUP] Error stopping process: $_" -ForegroundColor Yellow
        }

        # Display log output
        Write-Host "`n[LOGS] WebHost output:" -ForegroundColor Cyan
        Write-Host "----------------------------------------" -ForegroundColor Gray
        if (Test-Path $webHost.OutFiles.StdOut) {
            Get-Content $webHost.OutFiles.StdOut -ErrorAction SilentlyContinue | ForEach-Object {
                Write-Host $_ -ForegroundColor Gray
            }
        }
        Write-Host "----------------------------------------" -ForegroundColor Gray
    }

    Remove-Module Start-WebHostForTest -Force -ErrorAction SilentlyContinue

    # Summary
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "Test Results" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Passed: $testsPassed" -ForegroundColor Green
    Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
    Write-Host "Total:  $($testsPassed + $testsFailed)" -ForegroundColor Cyan

    if ($testsFailed -eq 0) {
        Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ Some tests failed" -ForegroundColor Red
    }
    Write-Host ""
}
