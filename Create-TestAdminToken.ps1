#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Create admin bearer token for testing

.DESCRIPTION
    Creates a test user with system_admin role and returns a bearer token.
#>

[CmdletBinding()]
param(
    [int]$Port = 8080
)

Write-Host "`n========== Creating Admin Test Token ==========" -ForegroundColor Cyan

# Create a test token with admin roles
$tokenScript = Join-Path $PSScriptRoot "system\utility\Account_Auth_BearerToken_Get.ps1"

Write-Host "Creating test token with system_admin role..." -ForegroundColor Yellow

$token = & $tokenScript -Create -TestToken -Roles @('system_admin', 'site_admin', 'authenticated') -Verbose

if (-not $token) {
    Write-Host "❌ Failed to create token" -ForegroundColor Red
    exit 1
}

Write-Host "`n✅ Token created successfully!" -ForegroundColor Green
Write-Host "   Bearer Token: $($token.BearerToken)" -ForegroundColor Cyan
Write-Host "   User Email: $($token.UserEmail)" -ForegroundColor Gray
Write-Host "   Roles: $($token.Roles -join ', ')" -ForegroundColor Gray
Write-Host "   KeyID: $($token.KeyID)" -ForegroundColor Gray

# Test the token with job catalog endpoint
Write-Host "`n========== Testing Job Catalog ==========" -ForegroundColor Cyan

$headers = @{
    'Authorization' = "Bearer $($token.BearerToken)"
    'Content-Type' = 'application/json'
}

try {
    Write-Host "Testing: GET /apps/WebHostTaskManagement/api/v1/jobs/catalog..." -ForegroundColor Yellow

    $response = Invoke-RestMethod -Uri "http://localhost:$Port/apps/WebHostTaskManagement/api/v1/jobs/catalog" `
        -Method GET `
        -Headers $headers `
        -TimeoutSec 10

    if ($response.success) {
        Write-Host "✅ Job catalog loaded successfully!" -ForegroundColor Green
        Write-Host "   Jobs found: $($response.jobs.Count)" -ForegroundColor Gray

        if ($response.note) {
            Write-Host "   ⚠️  Note: $($response.note)" -ForegroundColor Yellow
        }

        if ($response.jobs.Count -gt 0) {
            Write-Host "`n   Sample jobs:" -ForegroundColor Gray
            $response.jobs | Select-Object -First 3 | ForEach-Object {
                Write-Host "     - $($_.jobId): $($_.displayName)" -ForegroundColor Cyan
            }
        }
    } else {
        Write-Host "❌ Job catalog returned error: $($response.error)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Job catalog test failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test the jobs endpoint
Write-Host "`n========== Testing Active Jobs ==========" -ForegroundColor Cyan

try {
    Write-Host "Testing: GET /apps/WebHostTaskManagement/api/v1/jobs..." -ForegroundColor Yellow

    $response = Invoke-RestMethod -Uri "http://localhost:$Port/apps/WebHostTaskManagement/api/v1/jobs" `
        -Method GET `
        -Headers $headers `
        -TimeoutSec 10

    Write-Host "✅ Active jobs endpoint responded" -ForegroundColor Green

    if ($response.note) {
        Write-Host "   ⚠️  Note: $($response.note)" -ForegroundColor Yellow

        if ($response.note -match "legacy|Using legacy") {
            Write-Host "   ❌ PROBLEM: PSWebHost_Jobs module NOT loaded (using legacy fallback)" -ForegroundColor Red
        }
    }

    if ($response.jobs) {
        Write-Host "   Running: $($response.jobs.running.Count)" -ForegroundColor Gray
        Write-Host "   Pending: $($response.jobs.pending.Count)" -ForegroundColor Gray
        Write-Host "   Completed: $($response.jobs.completed.Count)" -ForegroundColor Gray
    }
} catch {
    Write-Host "❌ Active jobs test failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "Bearer Token: $($token.BearerToken)" -ForegroundColor White
Write-Host "`nUse this token for further testing:" -ForegroundColor Yellow
Write-Host "  `$headers = @{ 'Authorization' = 'Bearer $($token.BearerToken)' }" -ForegroundColor Cyan
Write-Host "  Invoke-RestMethod -Uri 'http://localhost:8080/...' -Headers `$headers" -ForegroundColor Cyan
Write-Host ""

# Return the token
return $token
