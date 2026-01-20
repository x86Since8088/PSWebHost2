#Requires -Version 7

<#
.SYNOPSIS
    Migrates user data from "file-explorer" to "personal" folder naming.

.DESCRIPTION
    Renames existing UserData/{UserID}/file-explorer folders to "personal".
    This migration supports the transition from the old "file-explorer" naming
    convention to the new "personal" naming convention.

    Can be run in two modes:
    1. Batch mode: Migrate all users (default)
    2. Single user mode: Migrate specific user on-demand

.PARAMETER UserID
    Optional. If specified, only migrates this user's folder.
    If not specified, migrates all users.

.PARAMETER WhatIf
    Preview what would be migrated without making changes

.OUTPUTS
    Returns hashtable with:
    - Success: Boolean
    - MigratedCount: Number of users migrated
    - SkippedCount: Number of users skipped (already migrated)
    - Errors: Array of error messages
    - Details: Array of migration details

.EXAMPLE
    # Migrate all users
    & $script

.EXAMPLE
    # Migrate specific user
    & $script -UserID "user@example.com"

.EXAMPLE
    # Preview migration
    & $script -WhatIf
#>

param(
    [string]$UserID = $null,
    [switch]$WhatIf
)

$ErrorActionPreference = "Continue"

# Initialize results
$result = @{
    Success = $true
    MigratedCount = 0
    SkippedCount = 0
    Errors = @()
    Details = @()
}

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        # Standalone execution
        Split-Path (Split-Path $PSScriptRoot)
    }

    $userDataPath = Join-Path $projectRoot "PsWebHost_Data\UserData"

    # Check if UserData directory exists
    if (-not (Test-Path $userDataPath)) {
        $result.Details += "UserData directory does not exist: $userDataPath"
        return $result
    }

    # Get list of user directories to process
    if ($UserID) {
        # Single user mode
        $userDirs = @(Get-ChildItem -Path $userDataPath -Directory | Where-Object { $_.Name -eq $UserID })
        if ($userDirs.Count -eq 0) {
            $result.Details += "User directory not found: $UserID"
            return $result
        }
    }
    else {
        # Batch mode - all users
        $userDirs = Get-ChildItem -Path $userDataPath -Directory
    }

    Write-Host "=== File Explorer to Personal Migration ===" -ForegroundColor Cyan
    Write-Host "UserData Path: $userDataPath" -ForegroundColor Gray
    Write-Host "Users to check: $($userDirs.Count)" -ForegroundColor Gray
    if ($WhatIf) {
        Write-Host "[WHATIF] Running in preview mode" -ForegroundColor Yellow
    }
    Write-Host ""

    # Process each user directory
    foreach ($userDir in $userDirs) {
        $userId = $userDir.Name
        $fileExplorerPath = Join-Path $userDir.FullName "file-explorer"
        $personalPath = Join-Path $userDir.FullName "personal"

        # Check if migration is needed
        if (Test-Path $fileExplorerPath) {
            # Check if personal folder already exists (conflict)
            if (Test-Path $personalPath) {
                Write-Host "  [SKIP] $userId - Both 'file-explorer' and 'personal' exist (manual resolution needed)" -ForegroundColor Yellow
                $result.SkippedCount++
                $result.Details += "Skipped $userId - conflict: both folders exist"
                continue
            }

            # Perform migration
            Write-Host "  [MIGRATE] $userId" -ForegroundColor Green
            Write-Host "    From: $fileExplorerPath" -ForegroundColor DarkGray
            Write-Host "    To:   $personalPath" -ForegroundColor DarkGray

            if (-not $WhatIf) {
                try {
                    # Rename folder
                    Rename-Item -Path $fileExplorerPath -NewName "personal" -Force

                    # Log migration
                    Write-PSWebHostLog -Severity 'Info' -Category 'Migration' `
                        -Message "Migrated file-explorer to personal" `
                        -Data @{ UserID = $userId; OldPath = $fileExplorerPath; NewPath = $personalPath }

                    $result.MigratedCount++
                    $result.Details += "Migrated $userId successfully"
                    Write-Host "    ✓ Success" -ForegroundColor Green
                }
                catch {
                    $errorMsg = "Failed to migrate $userId : $($_.Exception.Message)"
                    Write-Host "    ✗ Error: $errorMsg" -ForegroundColor Red
                    $result.Errors += $errorMsg
                    $result.Success = $false
                }
            }
            else {
                Write-Host "    [WHATIF] Would rename folder" -ForegroundColor Yellow
                $result.MigratedCount++
            }
        }
        elseif (Test-Path $personalPath) {
            # Already migrated
            Write-Host "  [OK] $userId - Already using 'personal'" -ForegroundColor DarkGray
            $result.SkippedCount++
        }
        else {
            # No file explorer data yet
            Write-Host "  [SKIP] $userId - No file explorer data" -ForegroundColor DarkGray
            $result.SkippedCount++
        }
    }

    Write-Host ""
    Write-Host "=== Migration Summary ===" -ForegroundColor Cyan
    Write-Host "Migrated: $($result.MigratedCount)" -ForegroundColor Green
    Write-Host "Skipped:  $($result.SkippedCount)" -ForegroundColor Gray
    Write-Host "Errors:   $($result.Errors.Count)" -ForegroundColor $(if ($result.Errors.Count -gt 0) { 'Red' } else { 'Gray' })

    if ($WhatIf) {
        Write-Host ""
        Write-Host "[WHATIF] No changes were made. Run without -WhatIf to perform migration." -ForegroundColor Yellow
    }

    return $result
}
catch {
    Write-Error "Migration failed: $_"
    $result.Success = $false
    $result.Errors += "Critical error: $($_.Exception.Message)"
    return $result
}
