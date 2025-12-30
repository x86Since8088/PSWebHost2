# Test-PasswordAuthFlow.ps1
# Tests the complete password authentication flow

[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:8080",
    [switch]$UseTestAccount,
    [string]$Email,
    [string]$Password
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Password Authentication Flow Test" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Create test account if requested
$testAccount = $null
if ($UseTestAccount) {
    Write-Host "[Setup] Creating temporary test account..." -ForegroundColor Yellow
    $newAccountScript = Join-Path $PSScriptRoot "..\system\utility\Account_AuthProvider_Password_New.ps1"

    $testAccount = & $newAccountScript -TestAccount -Verbose:$VerbosePreference

    if ($testAccount) {
        $Email = $testAccount.Email
        $Password = $testAccount.Password
        Write-Host "      ✓ Test account created" -ForegroundColor Green
        Write-Host "        Email: $Email" -ForegroundColor Gray
        Write-Host "        UserID: $($testAccount.UserID)" -ForegroundColor Gray
    }
    else {
        throw "Failed to create test account"
    }
}
elseif (-not $Email -or -not $Password) {
    throw "Email and Password parameters are required when not using -UseTestAccount"
}

# Create a session to maintain cookies
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

try {
    # Step 1: Request /spa to get redirected to auth
    Write-Host "[1/5] Requesting /spa (should redirect to auth)..." -ForegroundColor Yellow
    try {
        $response = Invoke-WebRequest -Uri "$BaseUrl/spa" -WebSession $session -MaximumRedirection 0 -ErrorAction SilentlyContinue
    }
    catch {
        $response = $_.Exception.Response
    }

    if ($response.StatusCode -eq 302 -or $response.StatusCode -eq 307) {
        $redirectUrl = $response.Headers.Location
        Write-Host "      ✓ Redirected to: $redirectUrl" -ForegroundColor Green
    }
    else {
        Write-Host "      ✗ Expected redirect, got: $($response.StatusCode)" -ForegroundColor Red
    }

    # Check for session cookie
    $sessionCookie = $session.Cookies.GetCookies($BaseUrl) | Where-Object { $_.Name -eq 'PSWebSessionID' }
    if ($sessionCookie) {
        Write-Host "      ✓ Session cookie set: $($sessionCookie.Value)" -ForegroundColor Green
    }
    else {
        Write-Host "      ✗ No session cookie found" -ForegroundColor Red
    }

    # Step 2: Get the login page
    Write-Host "`n[2/5] Loading login page..." -ForegroundColor Yellow
    $loginPage = Invoke-WebRequest -Uri "$BaseUrl/api/v1/authprovider/password" -WebSession $session
    if ($loginPage.StatusCode -eq 200) {
        Write-Host "      ✓ Login page loaded (Status: $($loginPage.StatusCode))" -ForegroundColor Green
    }

    # Step 3: Extract state parameter from login page URL or generate one
    $state = [Guid]::NewGuid().ToString()
    $redirectTo = "$BaseUrl/spa"
    Write-Host "      Using state: $state" -ForegroundColor Gray

    # Step 4: Submit login credentials
    Write-Host "`n[3/5] Submitting login credentials..." -ForegroundColor Yellow
    $loginUrl = "$BaseUrl/api/v1/authprovider/password?state=$state&RedirectTo=$([uri]::EscapeDataString($redirectTo))"

    $body = @{
        email = $Email
        password = $Password
        RedirectTo = $redirectTo
    }

    try {
        $loginResponse = Invoke-WebRequest -Uri $loginUrl -Method POST -Body $body -WebSession $session -MaximumRedirection 0 -ErrorAction SilentlyContinue
    }
    catch {
        $loginResponse = $_.Exception.Response
    }

    Write-Host "      Response Status: $($loginResponse.StatusCode)" -ForegroundColor $(if ($loginResponse.StatusCode -in @(200, 302, 307)) { 'Green' } else { 'Red' })

    if ($loginResponse.StatusCode -eq 401) {
        # Authentication failed
        $errorContent = $loginResponse.Content | ConvertFrom-Json
        Write-Host "      ✗ Authentication failed: $($errorContent.Message)" -ForegroundColor Red
        return
    }
    elseif ($loginResponse.StatusCode -eq 422) {
        # Validation failed
        $errorContent = $loginResponse.Content | ConvertFrom-Json
        Write-Host "      ✗ Validation failed: $($errorContent.Message)" -ForegroundColor Red
        return
    }
    elseif ($loginResponse.StatusCode -in @(302, 307)) {
        # Successful redirect
        $nextUrl = $loginResponse.Headers.Location
        Write-Host "      ✓ Login successful, redirecting to: $nextUrl" -ForegroundColor Green

        # Step 5: Follow redirect to get access token
        Write-Host "`n[4/5] Following redirect to get access token..." -ForegroundColor Yellow
        try {
            $tokenResponse = Invoke-WebRequest -Uri "$BaseUrl$nextUrl" -WebSession $session -MaximumRedirection 5
            Write-Host "      ✓ Access token endpoint responded: $($tokenResponse.StatusCode)" -ForegroundColor Green
        }
        catch {
            Write-Host "      ✗ Failed to get access token: $($_.Exception.Message)" -ForegroundColor Red
        }

        # Step 6: Access protected /spa route
        Write-Host "`n[5/5] Accessing protected /spa route..." -ForegroundColor Yellow
        $spaResponse = Invoke-WebRequest -Uri "$BaseUrl/spa" -WebSession $session

        if ($spaResponse.StatusCode -eq 200) {
            Write-Host "      ✓ Successfully accessed /spa (Status: $($spaResponse.StatusCode))" -ForegroundColor Green
            Write-Host "      Content length: $($spaResponse.Content.Length) bytes" -ForegroundColor Gray

            # Check if it's HTML
            if ($spaResponse.Content -match '<html') {
                Write-Host "      ✓ Received HTML content" -ForegroundColor Green
            }
        }
        else {
            Write-Host "      ✗ Failed to access /spa: $($spaResponse.StatusCode)" -ForegroundColor Red
        }
    }
    else {
        Write-Host "      ✗ Unexpected response: $($loginResponse.StatusCode)" -ForegroundColor Red
        if ($loginResponse.Content) {
            Write-Host "      Response: $($loginResponse.Content)" -ForegroundColor Gray
        }
    }

    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "✓ Authentication Flow Test Complete" -ForegroundColor Green
    Write-Host "========================================`n" -ForegroundColor Cyan

}
catch {
    Write-Host "`n✗ Test failed with error:" -ForegroundColor Red
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  $($_.InvocationInfo.PositionMessage)" -ForegroundColor Gray
}
finally {
    # Cleanup test account if created
    if ($testAccount) {
        Write-Host "`n[Cleanup] Removing test account..." -ForegroundColor Yellow
        $removeAccountScript = Join-Path $PSScriptRoot "..\system\utility\Account_AuthProvider_Password_Remove.ps1"

        try {
            & $removeAccountScript -ID $testAccount.UserID -Force -Confirm:$false | Out-Null
            Write-Host "      ✓ Test account removed" -ForegroundColor Green
        }
        catch {
            Write-Host "      ✗ Failed to remove test account: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
