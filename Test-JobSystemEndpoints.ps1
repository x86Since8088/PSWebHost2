#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Test WebHostTaskManagement API endpoints

.DESCRIPTION
    Tests all job system endpoints with proper authentication.
    Creates an admin session and tests catalog, jobs, tasks endpoints.
#>

param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$Username = "admin",
    [string]$Password = "admin"
)

$ErrorActionPreference = 'Stop'

Write-Host "`n========== Testing WebHostTaskManagement Endpoints ==========" -ForegroundColor Cyan

# Step 1: Authenticate and get session cookie
Write-Host "`n[1/6] Authenticating..." -ForegroundColor Yellow
try {
    $loginBody = @{
        username = $Username
        password = $Password
    } | ConvertTo-Json

    $loginResponse = Invoke-WebRequest -Uri "$BaseUrl/api/v1/login" `
        -Method POST `
        -Body $loginBody `
        -ContentType "application/json" `
        -SessionVariable webSession `
        -ErrorAction Stop

    Write-Host "✅ Authentication successful" -ForegroundColor Green
    Write-Host "   Session: $($webSession.Cookies.GetCookies($BaseUrl) | Where-Object { $_.Name -eq 'PSWebSessionID' } | Select-Object -ExpandProperty Value)" -ForegroundColor Gray
} catch {
    Write-Host "❌ Authentication failed: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Step 2: Test job catalog endpoint
Write-Host "`n[2/6] Testing job catalog..." -ForegroundColor Yellow
try {
    $catalogResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/catalog" `
        -WebSession $webSession `
        -ErrorAction Stop

    if ($catalogResponse.success) {
        Write-Host "✅ Job catalog loaded" -ForegroundColor Green
        Write-Host "   Jobs found: $($catalogResponse.jobs.Count)" -ForegroundColor Gray

        if ($catalogResponse.jobs.Count -gt 0) {
            Write-Host "   Sample jobs:" -ForegroundColor Gray
            $catalogResponse.jobs | Select-Object -First 3 | ForEach-Object {
                Write-Host "     - $($_.jobId): $($_.displayName)" -ForegroundColor Gray
            }
        }

        if ($catalogResponse.note) {
            Write-Host "   ⚠️  Note: $($catalogResponse.note)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "❌ Job catalog returned error: $($catalogResponse.error)" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Job catalog failed: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails.Message) {
        Write-Host "   Details: $($_.ErrorDetails.Message)" -ForegroundColor Yellow
    }
}

# Step 3: Test active jobs endpoint
Write-Host "`n[3/6] Testing active jobs..." -ForegroundColor Yellow
try {
    $jobsResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs" `
        -WebSession $webSession `
        -ErrorAction Stop

    Write-Host "✅ Active jobs loaded" -ForegroundColor Green
    if ($jobsResponse.note) {
        Write-Host "   ⚠️  Note: $($jobsResponse.note)" -ForegroundColor Yellow
    }
    if ($jobsResponse.jobs) {
        Write-Host "   Running: $($jobsResponse.jobs.running.Count)" -ForegroundColor Gray
        Write-Host "   Pending: $($jobsResponse.jobs.pending.Count)" -ForegroundColor Gray
        Write-Host "   Completed: $($jobsResponse.jobs.completed.Count)" -ForegroundColor Gray
    }
} catch {
    Write-Host "❌ Active jobs failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 4: Test scheduled tasks endpoint
Write-Host "`n[4/6] Testing scheduled tasks..." -ForegroundColor Yellow
try {
    $tasksResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/tasks" `
        -WebSession $webSession `
        -ErrorAction Stop

    if ($tasksResponse.success) {
        Write-Host "✅ Scheduled tasks loaded" -ForegroundColor Green
        Write-Host "   Tasks found: $($tasksResponse.tasks.Count)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Scheduled tasks returned error" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Scheduled tasks failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 5: Test job results endpoint
Write-Host "`n[5/6] Testing job results..." -ForegroundColor Yellow
try {
    $resultsResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/jobs/results?maxResults=10" `
        -WebSession $webSession `
        -ErrorAction Stop

    if ($resultsResponse.success) {
        Write-Host "✅ Job results loaded" -ForegroundColor Green
        Write-Host "   Results found: $($resultsResponse.results.Count)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Job results returned error" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Job results failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Step 6: Test runspaces endpoint
Write-Host "`n[6/6] Testing runspaces..." -ForegroundColor Yellow
try {
    $runspacesResponse = Invoke-RestMethod -Uri "$BaseUrl/apps/WebHostTaskManagement/api/v1/runspaces" `
        -WebSession $webSession `
        -ErrorAction Stop

    if ($runspacesResponse.success) {
        Write-Host "✅ Runspaces loaded" -ForegroundColor Green
        Write-Host "   Runspaces found: $($runspacesResponse.runspaces.Count)" -ForegroundColor Gray
    } else {
        Write-Host "❌ Runspaces returned error" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Runspaces failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n========== Test Summary ==========" -ForegroundColor Cyan
Write-Host "All endpoint tests completed. Review results above." -ForegroundColor White
Write-Host ""
