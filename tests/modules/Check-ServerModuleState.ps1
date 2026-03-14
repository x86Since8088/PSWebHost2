#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Check server module state by querying a diagnostic endpoint

.DESCRIPTION
    Creates a simple request to get module loading state without authentication.
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Checking Server Module State ==========" -ForegroundColor Cyan

# Try to hit a public/low-auth endpoint to see if server is responding
Write-Host "`n[1/3] Testing server connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-WebRequest -Uri "http://localhost:8080/spa" -MaximumRedirection 0 -ErrorAction SilentlyContinue
    Write-Host "✅ Server is responding (Status: $($response.StatusCode))" -ForegroundColor Green
} catch {
    if ($_.Exception.Response.StatusCode.value__ -eq 302) {
        Write-Host "✅ Server is responding (redirecting as expected)" -ForegroundColor Green
    } else {
        Write-Host "❌ Server not responding: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Check if we can find any WebHostTaskManagement endpoints
Write-Host "`n[2/3] Checking WebHostTaskManagement app registration..." -ForegroundColor Yellow
try {
    # Try the UI element endpoint (usually has lower auth requirements)
    $response = Invoke-WebRequest -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager" `
        -ErrorAction Stop

    if ($response.StatusCode -eq 200) {
        Write-Host "✅ WebHostTaskManagement app is registered" -ForegroundColor Green
        $data = $response.Content | ConvertFrom-Json
        Write-Host "   Component: $($data.component)" -ForegroundColor Gray
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        Write-Host "✅ WebHostTaskManagement app is registered (requires auth)" -ForegroundColor Green
    } else {
        Write-Host "⚠️  WebHostTaskManagement endpoint check: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Check loaded modules (via reflection if possible)
Write-Host "`n[3/3] Attempting to determine module state from API responses..." -ForegroundColor Yellow

# Try the catalog endpoint to see what error/note we get
try {
    $catalogResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/catalog" `
        -ErrorAction SilentlyContinue

    if ($catalogResponse.note) {
        Write-Host "⚠️  Catalog Note: $($catalogResponse.note)" -ForegroundColor Yellow
        if ($catalogResponse.note -match "legacy|old|not.*load") {
            Write-Host "   ❌ This suggests PSWebHost_Jobs module NOT loaded" -ForegroundColor Red
        }
    } elseif ($catalogResponse.jobs) {
        Write-Host "✅ Job catalog working - PSWebHost_Jobs likely loaded" -ForegroundColor Green
        Write-Host "   Jobs found: $($catalogResponse.jobs.Count)" -ForegroundColor Gray
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        Write-Host "⚠️  Catalog endpoint requires authentication (can't determine module state)" -ForegroundColor Yellow
    } else {
        Write-Host "❌ Catalog endpoint error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Try the legacy jobs endpoint
try {
    $jobsResponse = Invoke-RestMethod -Uri "http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs" `
        -ErrorAction SilentlyContinue

    if ($jobsResponse.note) {
        Write-Host "⚠️  Jobs Note: $($jobsResponse.note)" -ForegroundColor Yellow
        if ($jobsResponse.note -match "legacy|Using legacy") {
            Write-Host "   ❌ CONFIRMED: PSWebHost_Jobs module NOT loaded (using legacy fallback)" -ForegroundColor Red
        }
    }
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401 -or $statusCode -eq 403) {
        Write-Host "⚠️  Jobs endpoint requires authentication" -ForegroundColor Yellow
    }
}

Write-Host "`n========== Summary ==========" -ForegroundColor Cyan
Write-Host "If you see 'legacy endpoint' messages, the PSWebHost_Jobs module did NOT load." -ForegroundColor White
Write-Host "Check server startup logs for PSWebHost_Jobs loading errors." -ForegroundColor White
Write-Host ""
