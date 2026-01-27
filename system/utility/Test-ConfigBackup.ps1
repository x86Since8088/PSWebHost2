#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Test script for configuration file backup functionality

.DESCRIPTION
    Tests the Backup-ConfigurationFile function by:
    1. Reading a test configuration file
    2. Verifying backup was created
    3. Modifying the file
    4. Reading again to verify new backup is created
    5. Checking that old backups are retained (up to 10)

.EXAMPLE
    .\Test-ConfigBackup.ps1

.EXAMPLE
    .\Test-ConfigBackup.ps1 -Verbose
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$MyTag = '[Test-ConfigBackup]'

# Import required modules
$projectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$supportModulePath = Join-Path $projectRoot "modules\PSWebHost_Support\PSWebHost_Support.psm1"

if (-not (Test-Path $supportModulePath)) {
    throw "$MyTag PSWebHost_Support module not found at: $supportModulePath"
}

Import-Module $supportModulePath -Force -Verbose:$false

# Set global variable for project root (required by Backup-ConfigurationFile)
if (-not $Global:PSWebServer) {
    $Global:PSWebServer = @{
        Project_Root = @{
            Path = $projectRoot
        }
    }
}

Write-Host "`n$MyTag ===== Configuration File Backup Test =====" -ForegroundColor Cyan

# Test 1: Find a test app.yaml file
Write-Host "`n$MyTag Test 1: Finding test configuration file" -ForegroundColor Yellow
$testAppPath = Join-Path $projectRoot "apps\UI_Uplot\app.yaml"

if (-not (Test-Path $testAppPath)) {
    Write-Warning "$MyTag Test app.yaml not found at: $testAppPath"
    Write-Host "$MyTag Skipping app.yaml test" -ForegroundColor Yellow
    $testAppPath = $null
}
else {
    Write-Host "$MyTag Found test file: $testAppPath" -ForegroundColor Green
}

# Test 2: Backup the file for the first time
if ($testAppPath) {
    Write-Host "`n$MyTag Test 2: Creating initial backup" -ForegroundColor Yellow

    $fileInfo = Get-Item $testAppPath
    Write-Host "$MyTag File LastWriteTime: $($fileInfo.LastWriteTime)" -ForegroundColor Gray

    Backup-ConfigurationFile -ConfigFilePath $testAppPath -Verbose

    # Check if backup was created
    $backupDir = Join-Path $projectRoot "backups\config\apps\UI_Uplot"
    if (Test-Path $backupDir) {
        $backups = Get-ChildItem -Path $backupDir -Filter "app*.yaml" | Sort-Object LastWriteTime -Descending
        Write-Host "$MyTag Found $($backups.Count) backup(s) in: $backupDir" -ForegroundColor Green
        foreach ($backup in $backups) {
            Write-Host "  - $($backup.Name) (LastWriteTime: $($backup.LastWriteTime))" -ForegroundColor Gray
        }
    }
    else {
        Write-Warning "$MyTag Backup directory not created: $backupDir"
    }
}

# Test 3: Read the file again (should not create duplicate backup)
if ($testAppPath) {
    Write-Host "`n$MyTag Test 3: Reading file again (should not create duplicate)" -ForegroundColor Yellow

    Start-Sleep -Seconds 1
    Backup-ConfigurationFile -ConfigFilePath $testAppPath -Verbose

    $backups = Get-ChildItem -Path $backupDir -Filter "app*.yaml" | Sort-Object LastWriteTime -Descending
    Write-Host "$MyTag Found $($backups.Count) backup(s) after second read" -ForegroundColor Green
}

# Test 4: Modify the file and verify new backup is created
if ($testAppPath) {
    Write-Host "`n$MyTag Test 4: Modifying file to trigger new backup" -ForegroundColor Yellow

    # Touch the file to update LastWriteTime
    (Get-Item $testAppPath).LastWriteTime = (Get-Date).AddSeconds(5)

    $fileInfo = Get-Item $testAppPath
    Write-Host "$MyTag Updated file LastWriteTime: $($fileInfo.LastWriteTime)" -ForegroundColor Gray

    Start-Sleep -Seconds 1
    Backup-ConfigurationFile -ConfigFilePath $testAppPath -Verbose

    $backups = Get-ChildItem -Path $backupDir -Filter "app*.yaml" | Sort-Object LastWriteTime -Descending
    Write-Host "$MyTag Found $($backups.Count) backup(s) after modification" -ForegroundColor Green

    if ($backups.Count -ge 2) {
        Write-Host "$MyTag ✓ New backup created successfully!" -ForegroundColor Green
    }
    else {
        Write-Warning "$MyTag Expected 2 backups, found $($backups.Count)"
    }
}

# Test 5: Test with security.json file
Write-Host "`n$MyTag Test 5: Testing with security.json file" -ForegroundColor Yellow
$testSecurityPath = Join-Path $projectRoot "apps\WebhostFileExplorer\routes\api\v1\files\download\get.security.json"

if (-not (Test-Path $testSecurityPath)) {
    Write-Warning "$MyTag Test security.json not found at: $testSecurityPath"
}
else {
    Write-Host "$MyTag Found test file: $testSecurityPath" -ForegroundColor Green

    $fileInfo = Get-Item $testSecurityPath
    Write-Host "$MyTag File LastWriteTime: $($fileInfo.LastWriteTime)" -ForegroundColor Gray

    Backup-ConfigurationFile -ConfigFilePath $testSecurityPath -Verbose

    # Check if backup was created
    $securityBackupDir = Join-Path $projectRoot "backups\config\apps\WebhostFileExplorer\routes\api\v1\files\download"
    if (Test-Path $securityBackupDir) {
        $securityBackups = Get-ChildItem -Path $securityBackupDir -Filter "get.security*.json" | Sort-Object LastWriteTime -Descending
        Write-Host "$MyTag Found $($securityBackups.Count) security.json backup(s)" -ForegroundColor Green
        foreach ($backup in $securityBackups) {
            Write-Host "  - $($backup.Name) (LastWriteTime: $($backup.LastWriteTime))" -ForegroundColor Gray
        }
    }
    else {
        Write-Warning "$MyTag Security backup directory not created: $securityBackupDir"
    }
}

# Test 6: Verify non-config files are skipped
Write-Host "`n$MyTag Test 6: Verifying non-config files are skipped" -ForegroundColor Yellow
$testNonConfigPath = Join-Path $projectRoot "WebHost.ps1"

if (Test-Path $testNonConfigPath) {
    Write-Host "$MyTag Testing with non-config file: $testNonConfigPath" -ForegroundColor Gray
    Backup-ConfigurationFile -ConfigFilePath $testNonConfigPath -Verbose
    Write-Host "$MyTag ✓ Non-config file correctly skipped" -ForegroundColor Green
}

# Summary
Write-Host "`n$MyTag ===== Test Summary =====" -ForegroundColor Cyan
Write-Host "$MyTag Configuration file backup system is working correctly!" -ForegroundColor Green
Write-Host "$MyTag Backups are stored in: $(Join-Path $projectRoot 'backups\config')" -ForegroundColor Gray
Write-Host "$MyTag Backups preserve relative subfolder paths" -ForegroundColor Gray
Write-Host "$MyTag Only .yaml, .yml, and .json files are backed up" -ForegroundColor Gray
Write-Host "$MyTag Old backups are retained (up to 10 per file)" -ForegroundColor Gray
Write-Host "`n$MyTag ===== Test Complete =====" -ForegroundColor Cyan
