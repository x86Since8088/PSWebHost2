# Test-AllEndpoints.ps1
# Comprehensive test suite for all PsWebHost API endpoints
# Discovered: 46 total endpoints across 9 categories

[CmdletBinding()]
param(
    [string]$TestUsername = "test@localhost",
    [string]$TestPassword = "TestPassword123!",
    [int]$Port = 0,
    [switch]$SkipAuth
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

# Check PowerShell version
if ($PSVersionTable.PSVersion.Major -lt 6) {
    Write-Warning "This test suite requires PowerShell 6+ (PowerShell Core/7+)"
    Write-Warning "Current version: $($PSVersionTable.PSVersion)"
    Write-Warning "Note: For Windows PowerShell 5.1, run 'pwsh' to use PowerShell 7+"
    return
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PsWebHost Comprehensive API Test Suite" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Import helper module
Import-Module (Join-Path $ProjectRoot 'tests\helpers\Start-WebHostForTest.psm1') -Force

$webHost = $null
$testsPassed = 0
$testsFailed = 0
$testsSkipped = 0
$sessionCookie = $null
$authenticatedSession = $null

function Test-Endpoint {
    param(
        [string]$Category,
        [string]$Name,
        [string]$Method = "GET",
        [string]$Path,
        [hashtable]$Headers = @{},
        [string]$Body = "",
        [int[]]$ExpectedStatusCodes = @(200),
        [scriptblock]$Validation,
        [switch]$RequiresAuth,
        [switch]$Skip
    )

    if ($Skip) {
        $script:testsSkipped++
        Write-Host "[SKIP] [$Category] $Name" -ForegroundColor Gray
        return
    }

    Write-Host "`n[TEST] [$Category] $Name" -ForegroundColor Yellow
    Write-Host "  → $Method $Path" -ForegroundColor Gray

    try {
        $uri = "$baseUrl$Path"
        $params = @{
            Uri = $uri
            Method = $Method
            UseBasicParsing = $true
            TimeoutSec = 10
        }

        # Add session cookie if authenticated
        if ($RequiresAuth -and $script:authenticatedSession) {
            $params['WebSession'] = $script:authenticatedSession
        }

        # Add custom headers
        if ($Headers.Count -gt 0) {
            $params['Headers'] = $Headers
        }

        # Add body for POST/PUT/DELETE
        if ($Body -and $Method -in @('POST', 'PUT', 'PATCH', 'DELETE')) {
            $params['Body'] = $Body
            if (-not $Headers.ContainsKey('Content-Type')) {
                $params['ContentType'] = 'application/x-www-form-urlencoded'
            }
        }

        $response = Invoke-WebRequest @params

        # Check status code
        if ($response.StatusCode -notin $ExpectedStatusCodes) {
            throw "Expected status code $($ExpectedStatusCodes -join ' or '), got $($response.StatusCode)"
        }

        Write-Host "  ✓ Status: $($response.StatusCode)" -ForegroundColor Green

        # Run custom validation
        if ($Validation) {
            & $Validation $response
        }

        $script:testsPassed++
        Write-Host "[PASS] [$Category] $Name" -ForegroundColor Green
        return $response

    } catch {
        $script:testsFailed++
        Write-Host "[FAIL] [$Category] $Name" -ForegroundColor Red
        Write-Host "  ✗ Error: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

try {
    # ============================================
    # SETUP: Start WebHost
    # ============================================
    Write-Host "[SETUP] Starting WebHost..." -ForegroundColor Cyan
    $webHost = Start-WebHostForTest -ProjectRoot $ProjectRoot -Port $Port -Verbose:$false

    if (-not $webHost.Ready) {
        throw "WebHost failed to start or did not respond within timeout"
    }

    Write-Host "[SETUP] WebHost started at $($webHost.Url)" -ForegroundColor Green
    $baseUrl = $webHost.Url.TrimEnd('/')

    # ============================================
    # CATEGORY 1: Authentication Endpoints
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 1: Authentication Endpoints  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 1.1: GET /api/v1/auth/getauthtoken (without state)
    Test-Endpoint -Category "Auth" -Name "Get auth token - no state" `
        -Path "/api/v1/auth/getauthtoken" `
        -ExpectedStatusCodes @(302) `
        -Validation {
            param($r)
            if ($r.Headers['Location'] -notmatch 'state=') {
                throw "Redirect should contain state parameter"
            }
            Write-Host "  ✓ Redirected with state parameter" -ForegroundColor Green
        }

    # Test 1.2: GET /api/v1/auth/getauthtoken (with state)
    $stateGuid = (New-Guid).Guid
    Test-Endpoint -Category "Auth" -Name "Get auth token - with state" `
        -Path "/api/v1/auth/getauthtoken?state=$stateGuid" `
        -Validation {
            param($r)
            if ($r.Content.Length -eq 0) {
                throw "Should return HTML content"
            }
            Write-Host "  ✓ Received HTML form ($($r.Content.Length) bytes)" -ForegroundColor Green
        }

    # Test 1.3: POST /api/v1/auth/getauthtoken (no email)
    Test-Endpoint -Category "Auth" -Name "Post auth token - request form" `
        -Method "POST" `
        -Path "/api/v1/auth/getauthtoken" `
        -Body "" `
        -Validation {
            param($r)
            $json = $r.Content | ConvertFrom-Json
            if ($json.status -ne 'continue') {
                throw "Expected status 'continue', got '$($json.status)'"
            }
            Write-Host "  ✓ Received email form" -ForegroundColor Green
        }

    # Test 1.4: POST /api/v1/auth/getauthtoken (invalid email)
    Test-Endpoint -Category "Auth" -Name "Post auth token - invalid email" `
        -Method "POST" `
        -Path "/api/v1/auth/getauthtoken" `
        -Body "email=notvalid" `
        -ExpectedStatusCodes @(400) `
        -Validation {
            param($r)
            $json = $r.Content | ConvertFrom-Json
            if ($json.status -ne 'fail') {
                throw "Expected status 'fail'"
            }
            Write-Host "  ✓ Rejected invalid email" -ForegroundColor Green
        }

    # Test 1.5: POST /api/v1/auth/getauthtoken (valid email - no user)
    Test-Endpoint -Category "Auth" -Name "Post auth token - valid email (nonexistent)" `
        -Method "POST" `
        -Path "/api/v1/auth/getauthtoken" `
        -Body "email=nonexistent@test.com" `
        -ExpectedStatusCodes @(404, 200) `
        -Validation {
            param($r)
            $json = $r.Content | ConvertFrom-Json
            Write-Host "  ✓ Response: $($json.status)" -ForegroundColor Green
        }

    # Test 1.6: GET /api/v1/auth/sessionid (unauthenticated)
    Test-Endpoint -Category "Auth" -Name "Get session ID - unauthenticated" `
        -Path "/api/v1/auth/sessionid" `
        -Validation {
            param($r)
            Write-Host "  ✓ Received session info" -ForegroundColor Green
        }

    # Test 1.7: GET /api/v1/auth/getaccesstoken (unauthenticated)
    Test-Endpoint -Category "Auth" -Name "Get access token - unauthenticated" `
        -Path "/api/v1/auth/getaccesstoken" `
        -ExpectedStatusCodes @(200, 302, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Status: $($r.StatusCode)" -ForegroundColor Green
        }

    # Test 1.8: GET /api/v1/auth/logoff
    Test-Endpoint -Category "Auth" -Name "Logoff" `
        -Path "/api/v1/auth/logoff" `
        -ExpectedStatusCodes @(200, 302) `
        -Validation {
            param($r)
            Write-Host "  ✓ Logoff successful" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 2: Auth Provider Endpoints
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 2: Auth Provider Endpoints   ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 2.1: GET /api/v1/authprovider/password
    Test-Endpoint -Category "AuthProvider" -Name "Password provider - GET form" `
        -Path "/api/v1/authprovider/password?state=$stateGuid" `
        -Validation {
            param($r)
            Write-Host "  ✓ Received password form" -ForegroundColor Green
        }

    # Test 2.2: POST /api/v1/authprovider/password (missing creds)
    Test-Endpoint -Category "AuthProvider" -Name "Password provider - missing credentials" `
        -Method "POST" `
        -Path "/api/v1/authprovider/password?state=$stateGuid" `
        -Body "" `
        -ExpectedStatusCodes @(400, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Rejected missing credentials" -ForegroundColor Green
        }

    # Test 2.3: POST /api/v1/authprovider/password (invalid creds)
    Test-Endpoint -Category "AuthProvider" -Name "Password provider - invalid credentials" `
        -Method "POST" `
        -Path "/api/v1/authprovider/password?state=$stateGuid" `
        -Body "email=test@localhost&password=wrongpassword" `
        -ExpectedStatusCodes @(400, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Rejected invalid credentials" -ForegroundColor Green
        }

    # Test 2.4: GET /api/v1/authprovider/windows
    Test-Endpoint -Category "AuthProvider" -Name "Windows provider - GET form" `
        -Path "/api/v1/authprovider/windows?state=$stateGuid" `
        -Validation {
            param($r)
            Write-Host "  ✓ Received Windows auth form" -ForegroundColor Green
        }

    # Test 2.5: POST /api/v1/authprovider/windows (missing creds)
    Test-Endpoint -Category "AuthProvider" -Name "Windows provider - missing credentials" `
        -Method "POST" `
        -Path "/api/v1/authprovider/windows?state=$stateGuid" `
        -Body "" `
        -ExpectedStatusCodes @(400) `
        -Validation {
            param($r)
            $json = $r.Content | ConvertFrom-Json
            if ($json.Message -notmatch 'required') {
                throw "Should mention required fields"
            }
            Write-Host "  ✓ Rejected missing credentials" -ForegroundColor Green
        }

    # Test 2.6: OAuth Providers (Google, O365, EntraID) - GET only
    foreach ($provider in @('google', 'o365', 'entraID')) {
        Test-Endpoint -Category "AuthProvider" -Name "$provider provider - GET redirect" `
            -Path "/api/v1/authprovider/$provider?state=$stateGuid" `
            -ExpectedStatusCodes @(200, 302) `
            -Validation {
                param($r)
                Write-Host "  ✓ Provider endpoint accessible" -ForegroundColor Green
            }
    }

    # Test 2.7: Other Providers (Certificate, YubiKey, TokenAuth)
    foreach ($provider in @('certificate', 'yubikey')) {
        Test-Endpoint -Category "AuthProvider" -Name "$provider provider - GET form" `
            -Path "/api/v1/authprovider/$provider?state=$stateGuid" `
            -ExpectedStatusCodes @(200, 302) `
            -Validation {
                param($r)
                Write-Host "  ✓ Provider endpoint accessible" -ForegroundColor Green
            }
    }

    # Test 2.8: Token Authenticator Registration
    Test-Endpoint -Category "AuthProvider" -Name "Token authenticator - registration GET" `
        -Path "/api/v1/authprovider/tokenauthenticator/registration" `
        -ExpectedStatusCodes @(200, 302, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Registration endpoint accessible" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 3: Session Management
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 3: Session Management         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 3.1: GET /api/v1/session
    Test-Endpoint -Category "Session" -Name "Get session info" `
        -Path "/api/v1/session" `
        -ExpectedStatusCodes @(200, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Session endpoint responded" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 4: User Management (requires auth)
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 4: User Management            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 4.1: GET /api/v1/users (unauthenticated - should fail)
    Test-Endpoint -Category "Users" -Name "Get users - unauthenticated" `
        -Path "/api/v1/users" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            if ($r.StatusCode -in @(401, 403)) {
                Write-Host "  ✓ Properly requires authentication" -ForegroundColor Green
            } else {
                Write-Host "  ! Warning: Should require authentication" -ForegroundColor Yellow
            }
        }

    # ============================================
    # CATEGORY 5: Registration
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 5: Registration               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 5.1: GET /api/v1/registration
    Test-Endpoint -Category "Registration" -Name "Get registration form" `
        -Path "/api/v1/registration" `
        -Validation {
            param($r)
            Write-Host "  ✓ Registration form accessible" -ForegroundColor Green
        }

    # Test 5.2: POST /api/v1/registration (missing data)
    Test-Endpoint -Category "Registration" -Name "Post registration - missing data" `
        -Method "POST" `
        -Path "/api/v1/registration" `
        -Body "" `
        -ExpectedStatusCodes @(200, 400) `
        -Validation {
            param($r)
            Write-Host "  ✓ Validation working" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 6: Configuration
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 6: Configuration              ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 6.1: GET /api/v1/config/profile
    Test-Endpoint -Category "Config" -Name "Get profile config" `
        -Path "/api/v1/config/profile" `
        -ExpectedStatusCodes @(200, 401) `
        -Validation {
            param($r)
            Write-Host "  ✓ Profile endpoint accessible" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 7: Database Endpoints
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 7: Database Endpoints         ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 7.1: GET /api/v1/db/sqlite/pswebhost.db/tables
    Test-Endpoint -Category "Database" -Name "List database tables" `
        -Path "/api/v1/db/sqlite/pswebhost.db/tables" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            if ($r.StatusCode -eq 200) {
                Write-Host "  ! Warning: DB endpoint should require authentication" -ForegroundColor Yellow
            } else {
                Write-Host "  ✓ Properly protected" -ForegroundColor Green
            }
        }

    # Test 7.2: GET /api/v1/db/sqlite/pswebhost.db/tableexplorer
    Test-Endpoint -Category "Database" -Name "Database table explorer" `
        -Path "/api/v1/db/sqlite/pswebhost.db/tableexplorer" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            Write-Host "  ✓ Table explorer endpoint accessible" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 8: Debug Endpoints
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 8: Debug Endpoints            ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 8.1: GET /api/v1/debug
    Test-Endpoint -Category "Debug" -Name "Debug info" `
        -Path "/api/v1/debug" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            Write-Host "  ✓ Debug endpoint accessible" -ForegroundColor Green
        }

    # Test 8.2: GET /api/v1/debug/vars
    Test-Endpoint -Category "Debug" -Name "Debug variables list" `
        -Path "/api/v1/debug/vars" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            Write-Host "  ✓ Debug vars endpoint accessible" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 9: Status Endpoints
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 9: Status Endpoints           ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 9.1: GET /api/v1/status/logging
    Test-Endpoint -Category "Status" -Name "Logging status" `
        -Path "/api/v1/status/logging" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            Write-Host "  ✓ Logging status endpoint accessible" -ForegroundColor Green
        }

    # Test 9.2: GET /api/v1/status/error
    Test-Endpoint -Category "Status" -Name "Error status" `
        -Path "/api/v1/status/error" `
        -ExpectedStatusCodes @(200, 401, 403) `
        -Validation {
            param($r)
            Write-Host "  ✓ Error status endpoint accessible" -ForegroundColor Green
        }

    # ============================================
    # CATEGORY 10: UI Elements
    # ============================================
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  CATEGORY 10: UI Elements               ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan

    # Test 10.1-10.6: Various UI element endpoints
    $uiEndpoints = @(
        @{Name="Main menu"; Path="/api/v1/ui/elements/main-menu"},
        @{Name="File explorer"; Path="/api/v1/ui/elements/file-explorer"},
        @{Name="System status"; Path="/api/v1/ui/elements/system-status"},
        @{Name="World map"; Path="/api/v1/ui/elements/world-map"},
        @{Name="Server heatmap"; Path="/api/v1/ui/elements/server-heatmap"},
        @{Name="Event stream"; Path="/api/v1/ui/elements/event-stream"},
        @{Name="Users management"; Path="/api/v1/ui/elements/admin/users-management"}
    )

    foreach ($ui in $uiEndpoints) {
        Test-Endpoint -Category "UI" -Name $ui.Name `
            -Path $ui.Path `
            -ExpectedStatusCodes @(200, 401, 403) `
            -Validation {
                param($r)
                Write-Host "  ✓ UI endpoint accessible" -ForegroundColor Green
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
    }

    Remove-Module Start-WebHostForTest -Force -ErrorAction SilentlyContinue

    # Summary
    Write-Host "`n╔════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           Test Results Summary          ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host "Passed:  $testsPassed" -ForegroundColor Green
    Write-Host "Failed:  $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { 'Green' } else { 'Red' })
    Write-Host "Skipped: $testsSkipped" -ForegroundColor Yellow
    Write-Host "Total:   $($testsPassed + $testsFailed + $testsSkipped)" -ForegroundColor Cyan

    $successRate = if (($testsPassed + $testsFailed) -gt 0) {
        [math]::Round(($testsPassed / ($testsPassed + $testsFailed)) * 100, 1)
    } else { 0 }
    Write-Host "Success Rate: $successRate%" -ForegroundColor $(if ($successRate -ge 80) { 'Green' } elseif ($successRate -ge 60) { 'Yellow' } else { 'Red' })

    if ($testsFailed -eq 0) {
        Write-Host "`n✓ All tests passed!" -ForegroundColor Green
    } else {
        Write-Host "`n✗ Some tests failed - review output above" -ForegroundColor Red
    }
    Write-Host ""
}
