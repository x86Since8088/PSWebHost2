#Requires -Version 7

<#
.SYNOPSIS
    Migrates app data directories to centralized PsWebHost_Data structure

.DESCRIPTION
    Moves data from apps/[appname]/data to PsWebHost_Data/apps/[appname]/
    Updates all file references (ps1, js, yaml, json, html)
    Removes old data directories after successful migration

.PARAMETER ProjectRoot
    Root path of PSWebHost project. Defaults to script location.

.PARAMETER AppsToMigrate
    Specific apps to migrate. If not specified, migrates all apps with data directories.

.PARAMETER WhatIf
    Dry-run mode. Shows what would be done without making changes.

.PARAMETER Force
    Skip confirmation prompts

.PARAMETER CreateBackup
    Create backup before migration. Default: $true

.EXAMPLE
    .\Migrate-AppDataPaths.ps1 -WhatIf
    Preview migration without making changes

.EXAMPLE
    .\Migrate-AppDataPaths.ps1 -AppsToMigrate UI_Uplot,vault -Force
    Migrate specific apps without confirmation

.EXAMPLE
    .\Migrate-AppDataPaths.ps1 -Force
    Migrate all apps with data directories
#>

param(
    [string]$ProjectRoot,
    [string[]]$AppsToMigrate,
    [switch]$WhatIf,
    [switch]$Force,
    [bool]$CreateBackup = $true
)

# Determine project root
if (-not $ProjectRoot) {
    $ProjectRoot = $PSScriptRoot -replace '[/\\]system[/\\].*'
}

$ErrorActionPreference = 'Stop'

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PSWebHost Data Path Migration Utility" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan
Write-Host "Project Root: $ProjectRoot" -ForegroundColor Gray
Write-Host "Mode: $(if ($WhatIf) { 'DRY-RUN (No changes will be made)' } else { 'LIVE' })" -ForegroundColor $(if ($WhatIf) { 'Yellow' } else { 'Green' })
Write-Host ""

# Define path mappings for updates
$PathPatterns = @{
    PowerShell = @{
        # Join-Path $AppRoot 'data'  ->  Join-Path $Global:PSWebServer['DataRoot'] "apps\$AppName"
        'Join-Path\s+\$AppRoot\s+[''"]data[''"]' = 'Join-Path $Global:PSWebServer[''DataRoot''] "apps\$AppName"'

        # $AppRoot/data  ->  $Global:PSWebServer['DataRoot']/apps/$AppName
        '\$AppRoot[/\\]data' = '$Global:PSWebServer[''DataRoot'']/apps/$AppName'

        # "$AppRoot\data"  ->  "$($Global:PSWebServer['DataRoot'])\apps\$AppName"
        '"\$AppRoot\\data"' = '"$($Global:PSWebServer[''DataRoot''])\apps\$AppName"'

        # $DataPath variable assignments
        'DataPath\s*=\s*Join-Path\s+\$AppRoot\s+[''"]data[''"]' = 'DataPath = Join-Path $Global:PSWebServer[''DataRoot''] "apps\$AppName"'
    }

    JavaScript = @{
        # /apps/appname/data/  ->  /data/apps/appname/
        '/apps/([^/]+)/data/' = '/data/apps/$1/'

        # '/apps/appname/public/data'  ->  '/data/apps/appname'
        '/apps/([^/]+)/public/data' = '/data/apps/$1'
    }

    YAML = @{
        # data: ./data  ->  (remove this line, handled by init)
        'data:\s*\.?/data' = '# data path managed by app_init.ps1'
    }
}

# Discover apps with data directories
Write-Host "[1/6] Discovering apps with data directories..." -ForegroundColor Yellow

$appsDir = Join-Path $ProjectRoot 'apps'
$allApps = Get-ChildItem -Path $appsDir -Directory -ErrorAction SilentlyContinue

$appsWithData = @()

foreach ($app in $allApps) {
    $appDataDir = Join-Path $app.FullName 'data'

    if (Test-Path $appDataDir) {
        $appName = $app.Name

        # Skip if specific apps specified and this isn't one of them
        if ($AppsToMigrate -and $appName -notin $AppsToMigrate) {
            continue
        }

        # Get data size
        $dataSize = (Get-ChildItem -Path $appDataDir -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum).Sum

        $dataSizeMB = [Math]::Round($dataSize / 1MB, 2)

        $appsWithData += [PSCustomObject]@{
            AppName = $appName
            SourcePath = $appDataDir
            TargetPath = Join-Path $ProjectRoot "PsWebHost_Data\apps\$appName"
            DataSizeMB = $dataSizeMB
            FileCount = (Get-ChildItem -Path $appDataDir -Recurse -File -ErrorAction SilentlyContinue).Count
        }
    }
}

if ($appsWithData.Count -eq 0) {
    Write-Host "  No apps found with data directories to migrate." -ForegroundColor Green
    Write-Host ""
    return
}

Write-Host "  Found $($appsWithData.Count) apps with data directories:" -ForegroundColor White
$appsWithData | Format-Table AppName, FileCount, @{Label='Size (MB)'; Expression={$_.DataSizeMB}} -AutoSize
Write-Host ""

# Confirm migration
if (-not $WhatIf -and -not $Force) {
    $totalSize = ($appsWithData | Measure-Object -Property DataSizeMB -Sum).Sum
    Write-Host "Total data to migrate: $([Math]::Round($totalSize, 2)) MB across $($appsWithData.Count) apps" -ForegroundColor Yellow
    Write-Host ""

    $confirm = Read-Host "Proceed with migration? (y/N)"
    if ($confirm -ne 'y' -and $confirm -ne 'Y') {
        Write-Host "Migration cancelled." -ForegroundColor Yellow
        return
    }
    Write-Host ""
}

# Create backup if requested
if ($CreateBackup -and -not $WhatIf) {
    Write-Host "[2/6] Creating backup..." -ForegroundColor Yellow

    $backupDir = Join-Path $ProjectRoot "PsWebHost_Data\backups\data-migration-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }

    foreach ($app in $appsWithData) {
        $appBackupDir = Join-Path $backupDir $app.AppName

        Write-Host "  Backing up $($app.AppName)..." -ForegroundColor Gray
        Copy-Item -Path $app.SourcePath -Destination $appBackupDir -Recurse -Force
    }

    Write-Host "  Backup created: $backupDir" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Host "[2/6] Skipping backup (WhatIf mode or CreateBackup=false)" -ForegroundColor Gray
    Write-Host ""
}

# Move data directories
Write-Host "[3/6] Moving data directories..." -ForegroundColor Yellow

$migrationLog = @()

foreach ($app in $appsWithData) {
    Write-Host "  Processing $($app.AppName)..." -ForegroundColor White

    if ($WhatIf) {
        Write-Host "    [DRY-RUN] Would move: $($app.SourcePath)" -ForegroundColor Gray
        Write-Host "    [DRY-RUN] To: $($app.TargetPath)" -ForegroundColor Gray
    } else {
        try {
            # Create target directory
            $targetParent = Split-Path $app.TargetPath -Parent
            if (-not (Test-Path $targetParent)) {
                New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
            }

            # Move data
            if (Test-Path $app.TargetPath) {
                Write-Warning "    Target already exists: $($app.TargetPath). Merging..."
                Copy-Item -Path "$($app.SourcePath)\*" -Destination $app.TargetPath -Recurse -Force
            } else {
                Move-Item -Path $app.SourcePath -Destination $app.TargetPath -Force
            }

            Write-Host "    Moved successfully" -ForegroundColor Green

            $migrationLog += [PSCustomObject]@{
                AppName = $app.AppName
                Action = 'DataMoved'
                Status = 'Success'
                Source = $app.SourcePath
                Target = $app.TargetPath
            }

        } catch {
            Write-Host "    ERROR: $_" -ForegroundColor Red

            $migrationLog += [PSCustomObject]@{
                AppName = $app.AppName
                Action = 'DataMoved'
                Status = 'Failed'
                Error = $_.Exception.Message
            }
        }
    }
}

Write-Host ""

# Update file references
Write-Host "[4/6] Updating file references..." -ForegroundColor Yellow

$filesToUpdate = @()

# Find all files that might contain data paths
$searchPatterns = @('*.ps1', '*.psm1', '*.js', '*.yaml', '*.yml', '*.json', '*.html')

foreach ($app in $appsWithData) {
    $appDir = Join-Path $appsDir $app.AppName
    $appName = $app.AppName

    Write-Host "  Scanning $appName files..." -ForegroundColor Gray

    $files = Get-ChildItem -Path $appDir -Recurse -Include $searchPatterns -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\node_modules\\' -and $_.FullName -notmatch '\\\.git\\' }

    foreach ($file in $files) {
        try {
            $content = Get-Content $file.FullName -Raw -ErrorAction Stop
            $originalContent = $content
            $updated = $false

            $fileExt = $file.Extension.ToLower()

            # Apply PowerShell patterns
            if ($fileExt -in @('.ps1', '.psm1')) {
                foreach ($pattern in $PathPatterns.PowerShell.Keys) {
                    $replacement = $PathPatterns.PowerShell[$pattern] -replace '\$AppName', $appName
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $replacement
                        $updated = $true
                    }
                }
            }

            # Apply JavaScript patterns
            if ($fileExt -eq '.js') {
                foreach ($pattern in $PathPatterns.JavaScript.Keys) {
                    $replacement = $PathPatterns.JavaScript[$pattern]
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $replacement
                        $updated = $true
                    }
                }
            }

            # Apply YAML patterns
            if ($fileExt -in @('.yaml', '.yml')) {
                foreach ($pattern in $PathPatterns.YAML.Keys) {
                    $replacement = $PathPatterns.YAML[$pattern]
                    if ($content -match $pattern) {
                        $content = $content -replace $pattern, $replacement
                        $updated = $true
                    }
                }
            }

            if ($updated) {
                $relativePath = $file.FullName.Substring($ProjectRoot.Length + 1)
                $filesToUpdate += [PSCustomObject]@{
                    AppName = $appName
                    FilePath = $relativePath
                    FileType = $fileExt
                }

                if ($WhatIf) {
                    Write-Host "    [DRY-RUN] Would update: $relativePath" -ForegroundColor Gray
                } else {
                    Set-Content -Path $file.FullName -Value $content -Encoding UTF8 -NoNewline
                    Write-Host "    Updated: $relativePath" -ForegroundColor Green

                    $migrationLog += [PSCustomObject]@{
                        AppName = $appName
                        Action = 'FileUpdated'
                        Status = 'Success'
                        FilePath = $relativePath
                    }
                }
            }

        } catch {
            Write-Warning "    Error updating $($file.Name): $_"

            $migrationLog += [PSCustomObject]@{
                AppName = $appName
                Action = 'FileUpdate'
                Status = 'Failed'
                FilePath = $file.FullName
                Error = $_.Exception.Message
            }
        }
    }
}

Write-Host "  Updated $($filesToUpdate.Count) files" -ForegroundColor Green
Write-Host ""

# Remove old data directories
Write-Host "[5/6] Removing old data directories..." -ForegroundColor Yellow

foreach ($app in $appsWithData) {
    $oldDataDir = Join-Path $appsDir "$($app.AppName)\data"

    if (Test-Path $oldDataDir) {
        if ($WhatIf) {
            Write-Host "  [DRY-RUN] Would remove: $oldDataDir" -ForegroundColor Gray
        } else {
            try {
                Remove-Item -Path $oldDataDir -Recurse -Force
                Write-Host "  Removed: $oldDataDir" -ForegroundColor Green

                $migrationLog += [PSCustomObject]@{
                    AppName = $app.AppName
                    Action = 'OldDataRemoved'
                    Status = 'Success'
                    Path = $oldDataDir
                }

            } catch {
                Write-Warning "  Failed to remove $oldDataDir : $_"

                $migrationLog += [PSCustomObject]@{
                    AppName = $app.AppName
                    Action = 'OldDataRemoved'
                    Status = 'Failed'
                    Path = $oldDataDir
                    Error = $_.Exception.Message
                }
            }
        }
    }
}

Write-Host ""

# Generate migration report
Write-Host "[6/6] Generating migration report..." -ForegroundColor Yellow

$reportPath = Join-Path $ProjectRoot "PsWebHost_Data\system\utility\data-migration-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$reportDir = Split-Path $reportPath -Parent

if (-not (Test-Path $reportDir)) {
    New-Item -Path $reportDir -ItemType Directory -Force | Out-Null
}

$report = @{
    Timestamp = Get-Date -Format 'o'
    Mode = if ($WhatIf) { 'DryRun' } else { 'Live' }
    ProjectRoot = $ProjectRoot
    AppsMigrated = $appsWithData.AppName
    TotalApps = $appsWithData.Count
    FilesUpdated = $filesToUpdate.Count
    BackupLocation = if ($CreateBackup) { $backupDir } else { 'None' }
    MigrationLog = $migrationLog
    Summary = @{
        DataMoved = ($migrationLog | Where-Object { $_.Action -eq 'DataMoved' -and $_.Status -eq 'Success' }).Count
        FilesUpdated = ($migrationLog | Where-Object { $_.Action -eq 'FileUpdated' -and $_.Status -eq 'Success' }).Count
        OldDataRemoved = ($migrationLog | Where-Object { $_.Action -eq 'OldDataRemoved' -and $_.Status -eq 'Success' }).Count
        Failures = ($migrationLog | Where-Object { $_.Status -eq 'Failed' }).Count
    }
}

if (-not $WhatIf) {
    $report | ConvertTo-Json -Depth 10 | Out-File $reportPath -Encoding UTF8
    Write-Host "  Report saved: $reportPath" -ForegroundColor Green
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Migration Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Apps migrated: $($report.Summary.DataMoved)" -ForegroundColor $(if ($report.Summary.DataMoved -gt 0) { 'Green' } else { 'Gray' })
Write-Host "Files updated: $($report.Summary.FilesUpdated)" -ForegroundColor $(if ($report.Summary.FilesUpdated -gt 0) { 'Green' } else { 'Gray' })
Write-Host "Old directories removed: $($report.Summary.OldDataRemoved)" -ForegroundColor $(if ($report.Summary.OldDataRemoved -gt 0) { 'Green' } else { 'Gray' })
Write-Host "Failures: $($report.Summary.Failures)" -ForegroundColor $(if ($report.Summary.Failures -gt 0) { 'Red' } else { 'Green' })
Write-Host ""

if ($report.Summary.Failures -gt 0) {
    Write-Host "Failed operations:" -ForegroundColor Red
    $migrationLog | Where-Object { $_.Status -eq 'Failed' } | Format-Table AppName, Action, Error -AutoSize
}

if ($WhatIf) {
    Write-Host "This was a DRY-RUN. No changes were made." -ForegroundColor Yellow
    Write-Host "Run without -WhatIf to perform actual migration." -ForegroundColor Yellow
} else {
    Write-Host "Migration complete!" -ForegroundColor Green
    if ($CreateBackup) {
        Write-Host "Backup location: $backupDir" -ForegroundColor Cyan
    }
}

Write-Host ""
Write-Host "========================================`n" -ForegroundColor Cyan

return $report
