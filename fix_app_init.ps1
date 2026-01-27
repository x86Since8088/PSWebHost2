#!/usr/bin/env pwsh
#Requires -Version 7

<#
.SYNOPSIS
    Replaces app_init.ps1 with the fixed version

.DESCRIPTION
    - Backs up original app_init.ps1
    - Replaces with fixed version (granular try-catch, no old job system)
    - Validates the replacement
#>

$ErrorActionPreference = 'Stop'

Write-Host "`n=== Replacing app_init.ps1 with Fixed Version ===" -ForegroundColor Cyan

$appInitPath = "C:\SC\PsWebHost\apps\WebHostTaskManagement\app_init.ps1"
$fixedPath = "C:\SC\PsWebHost\apps\WebHostTaskManagement\app_init_fixed.ps1"
$backupPath = "C:\SC\PsWebHost\apps\WebHostTaskManagement\app_init.ps1.backup"

# Check if fixed version exists
if (-not (Test-Path $fixedPath)) {
    Write-Host "❌ Fixed version not found at: $fixedPath" -ForegroundColor Red
    Write-Host "   Make sure app_init_fixed.ps1 exists" -ForegroundColor Yellow
    exit 1
}

# Backup original
try {
    Write-Host "`n[1/3] Backing up original app_init.ps1..." -ForegroundColor Yellow
    Copy-Item $appInitPath $backupPath -Force
    Write-Host "✅ Backup created: $backupPath" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to create backup: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Replace with fixed version
try {
    Write-Host "`n[2/3] Replacing with fixed version..." -ForegroundColor Yellow
    Copy-Item $fixedPath $appInitPath -Force
    Write-Host "✅ Replaced app_init.ps1 with fixed version" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to replace file: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Restoring backup..." -ForegroundColor Yellow
    Copy-Item $backupPath $appInitPath -Force
    Write-Host "   Backup restored" -ForegroundColor Green
    exit 1
}

# Validate replacement
try {
    Write-Host "`n[3/3] Validating replacement..." -ForegroundColor Yellow

    $content = Get-Content $appInitPath -Raw

    # Check for key improvements
    $hasGranularTryCatch = ($content -match 'Step 1:.*Import App Module') -and ($content -match 'Step 2:.*Verify PSWebHost_Jobs')
    $noOldJobSystem = $content -notmatch 'PSWebHost_JobExecution'
    $hasWritePSWebHostLog = $content -match 'Write-PSWebHostLog'

    if ($hasGranularTryCatch) {
        Write-Host "  ✅ Granular try-catch blocks detected" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Granular try-catch not found" -ForegroundColor Yellow
    }

    if ($noOldJobSystem) {
        Write-Host "  ✅ Old job system loading removed" -ForegroundColor Green
    } else {
        Write-Host "  ❌ Old job system still referenced!" -ForegroundColor Red
    }

    if ($hasWritePSWebHostLog) {
        Write-Host "  ✅ Write-PSWebHostLog usage detected" -ForegroundColor Green
    } else {
        Write-Host "  ⚠️  Write-PSWebHostLog not found" -ForegroundColor Yellow
    }

    if ($hasGranularTryCatch -and $noOldJobSystem -and $hasWritePSWebHostLog) {
        Write-Host "`n🎉 Replacement successful and validated!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Replacement completed but validation failed" -ForegroundColor Yellow
        Write-Host "   Review the file manually" -ForegroundColor Yellow
    }

} catch {
    Write-Host "❌ Validation failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n=== Next Steps ===" -ForegroundColor Cyan
Write-Host "1. Stop the current server (Ctrl+C in server window)" -ForegroundColor Yellow
Write-Host "2. Restart the server: .\WebHost.ps1" -ForegroundColor Yellow
Write-Host "3. Run diagnostic: .\diagnose_job_system.ps1" -ForegroundColor Yellow
Write-Host ""
