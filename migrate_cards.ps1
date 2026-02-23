# Card Endpoint Migration Script
# Migrates card endpoints from /api/v1/ui/elements/ to /cards/

param(
    [switch]$WhatIf = $false
)

$ErrorActionPreference = 'Stop'
$migrationLog = @()

function Write-MigrationLog {
    param([string]$Message, [string]$Type = 'INFO')
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Type] $Message"
    $migrationLog += $logEntry
    Write-Host $logEntry -ForegroundColor $(if ($Type -eq 'ERROR') { 'Red' } elseif ($Type -eq 'SUCCESS') { 'Green' } else { 'Cyan' })
}

function Move-CardEndpoint {
    param(
        [string]$OldPath,
        [string]$NewPath,
        [string]$CardName
    )

    Write-MigrationLog "Migrating card: $CardName" 'INFO'
    Write-MigrationLog "  From: $OldPath" 'INFO'
    Write-MigrationLog "  To: $NewPath" 'INFO'

    # Check if old path exists
    if (-not (Test-Path $OldPath)) {
        Write-MigrationLog "  ERROR: Old path does not exist: $OldPath" 'ERROR'
        return $false
    }

    # Check if already migrated
    if (Test-Path $NewPath) {
        Write-MigrationLog "  SKIP: Already migrated (new path exists)" 'INFO'
        return $true
    }

    if ($WhatIf) {
        Write-MigrationLog "  WHAT-IF: Would move files from $OldPath to $NewPath" 'INFO'
        return $true
    }

    # Create new directory
    $newDir = Split-Path $NewPath -Parent
    if (-not (Test-Path $newDir)) {
        New-Item -Path $newDir -ItemType Directory -Force | Out-Null
        Write-MigrationLog "  Created directory: $newDir" 'SUCCESS'
    }

    # Move all files from old directory
    try {
        Get-ChildItem -Path $OldPath -File | ForEach-Object {
            $destFile = Join-Path $NewPath $_.Name
            Move-Item -Path $_.FullName -Destination $destFile -Force
            Write-MigrationLog "  Moved: $($_.Name)" 'SUCCESS'
        }

        # Move subdirectories if any
        Get-ChildItem -Path $OldPath -Directory | ForEach-Object {
            $destDir = Join-Path $NewPath $_.Name
            Move-Item -Path $_.FullName -Destination $destDir -Force -Recurse
            Write-MigrationLog "  Moved directory: $($_.Name)" 'SUCCESS'
        }

        # Remove old directory if empty
        if ((Get-ChildItem $OldPath -Force | Measure-Object).Count -eq 0) {
            Remove-Item $OldPath -Force
            Write-MigrationLog "  Removed empty directory: $OldPath" 'SUCCESS'
        }

        return $true
    } catch {
        Write-MigrationLog "  ERROR: $_" 'ERROR'
        return $false
    }
}

function Update-FileReferences {
    param(
        [string]$FilePath,
        [string]$OldUrl,
        [string]$NewUrl
    )

    if (-not (Test-Path $FilePath)) {
        return
    }

    $content = Get-Content -Path $FilePath -Raw
    if ($content -match [regex]::Escape($OldUrl)) {
        if ($WhatIf) {
            Write-MigrationLog "  WHAT-IF: Would update $FilePath" 'INFO'
        } else {
            $newContent = $content -replace [regex]::Escape($OldUrl), $NewUrl
            Set-Content -Path $FilePath -Value $newContent -NoNewline
            Write-MigrationLog "  Updated references in: $FilePath" 'SUCCESS'
        }
    }
}

# Define core card migrations (already migrated main-menu)
$coreCards = @(
    @{ Name = 'help-viewer'; Old = 'routes/api/v1/ui/elements/help-viewer'; New = 'routes/cards/help-viewer' }
    @{ Name = 'job-status'; Old = 'routes/api/v1/ui/elements/job-status'; New = 'routes/cards/job-status' }
    @{ Name = 'markdown-viewer'; Old = 'routes/api/v1/ui/elements/markdown-viewer'; New = 'routes/cards/markdown-viewer' }
    @{ Name = 'nodes-manager'; Old = 'routes/api/v1/ui/elements/nodes-manager'; New = 'routes/cards/nodes-manager' }
    @{ Name = 'site-settings'; Old = 'routes/api/v1/ui/elements/site-settings'; New = 'routes/cards/site-settings' }
    @{ Name = 'system-status'; Old = 'routes/api/v1/ui/elements/system-status'; New = 'routes/cards/system-status' }
    @{ Name = 'event-stream'; Old = 'routes/api/v1/ui/elements/event-stream'; New = 'routes/cards/event-stream' }
    @{ Name = 'memory-explorer'; Old = 'routes/api/v1/ui/elements/memory-explorer'; New = 'routes/cards/memory-explorer' }
    @{ Name = 'system-log'; Old = 'routes/api/v1/ui/elements/system-log'; New = 'routes/cards/system-log' }
    @{ Name = 'card-validation'; Old = 'routes/api/v1/ui/elements/card-validation'; New = 'routes/cards/card-validation' }
    @{ Name = 'admin/role-management'; Old = 'routes/api/v1/ui/elements/admin/role-management'; New = 'routes/cards/admin/role-management' }
    @{ Name = 'admin/users-management'; Old = 'routes/api/v1/ui/elements/admin/users-management'; New = 'routes/cards/admin/users-management' }
)

# Define app card migrations
$appCards = @(
    @{ App = 'DockerManager'; Name = 'docker-manager' }
    @{ App = 'DockerManager'; Name = 'dockermanager-home' }
    @{ App = 'KubernetesManager'; Name = 'kubernetes-status' }
    @{ App = 'KubernetesManager'; Name = 'kubernetesmanager-home' }
    @{ App = 'SQLiteManager'; Name = 'sqlite-manager' }
    @{ App = 'SQLiteManager'; Name = 'sqlite-query-editor' }
    @{ App = 'WSLManager'; Name = 'wsl-manager' }
    @{ App = 'WSLManager'; Name = 'wslmanager-home' }
    @{ App = 'WindowsAdmin'; Name = 'service-control' }
    @{ App = 'WindowsAdmin'; Name = 'task-scheduler' }
    @{ App = 'WindowsAdmin'; Name = 'windowsadmin-home' }
    @{ App = 'LinuxAdmin'; Name = 'linux-cron' }
    @{ App = 'LinuxAdmin'; Name = 'linux-services' }
    @{ App = 'LinuxAdmin'; Name = 'linuxadmin-home' }
    @{ App = 'MySQLManager'; Name = 'mysql-manager' }
    @{ App = 'RedisManager'; Name = 'redis-manager' }
    @{ App = 'SQLServerManager'; Name = 'sqlserver-manager' }
    @{ App = 'vault'; Name = 'vault-manager' }
    @{ App = 'UI_Uplot'; Name = 'uplot-home' }
    @{ App = 'UI_Uplot'; Name = 'time-series' }
    @{ App = 'UI_Uplot'; Name = 'area-chart' }
    @{ App = 'UI_Uplot'; Name = 'bar-chart' }
    @{ App = 'UI_Uplot'; Name = 'scatter-plot' }
    @{ App = 'UI_Uplot'; Name = 'multi-axis' }
    @{ App = 'UI_Uplot'; Name = 'heatmap' }
    @{ App = 'Maps'; Name = 'world-map' }
    @{ App = 'WebHostMetrics'; Name = 'server-heatmap' }
    @{ App = 'WebHostMetrics'; Name = 'memory-histogram' }
    @{ App = 'WebhostFileExplorer'; Name = 'file-explorer' }
    @{ App = 'WebhostFileExplorer'; Name = 'text-editor' }
    @{ App = 'WebhostFileExplorer'; Name = 'hex-editor' }
    @{ App = 'WebhostFileExplorer'; Name = 'file-sharing-modal' }
    @{ App = 'WebhostRealtimeEvents'; Name = 'realtime-events' }
    @{ App = 'WebHostDebugExtensions'; Name = 'debug-console' }
    @{ App = 'WebHostAppManager'; Name = 'apps-manager' }
    @{ App = 'WebHostDebugVariables'; Name = 'debug-variables' }
    @{ App = 'WebHostHelpViewer'; Name = 'help-viewer' }
    @{ App = 'WebHostTaskManagement'; Name = 'task-manager' }
    @{ App = 'UnitTests'; Name = 'unit-test-runner' }
)

Write-MigrationLog "===== CARD ENDPOINT MIGRATION STARTED =====" 'INFO'
Write-MigrationLog "Mode: $(if ($WhatIf) { 'WHAT-IF (no changes will be made)' } else { 'LIVE' })" 'INFO'
Write-MigrationLog "" 'INFO'

# Migrate core cards
Write-MigrationLog "=== Migrating Core Cards (12 cards) ===" 'INFO'
$successCount = 0
$failCount = 0

foreach ($card in $coreCards) {
    if (Move-CardEndpoint -OldPath $card.Old -NewPath $card.New -CardName $card.Name) {
        $successCount++
    } else {
        $failCount++
    }
}

Write-MigrationLog "Core cards migration: $successCount succeeded, $failCount failed" 'INFO'
Write-MigrationLog "" 'INFO'

# Migrate app cards
Write-MigrationLog "=== Migrating App Cards (29 cards) ===" 'INFO'
$appSuccessCount = 0
$appFailCount = 0

foreach ($card in $appCards) {
    $oldPath = "apps/$($card.App)/routes/api/v1/ui/elements/$($card.Name)"
    $newPath = "apps/$($card.App)/routes/cards/$($card.Name)"
    $cardFullName = "$($card.App)/$($card.Name)"

    if (Move-CardEndpoint -OldPath $oldPath -NewPath $newPath -CardName $cardFullName) {
        $appSuccessCount++
    } else {
        $appFailCount++
    }
}

Write-MigrationLog "App cards migration: $appSuccessCount succeeded, $appFailCount failed" 'INFO'
Write-MigrationLog "" 'INFO'

# Save migration log
$logFile = "card_migration_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$migrationLog | Out-File $logFile
Write-MigrationLog "Migration log saved to: $logFile" 'SUCCESS'

Write-MigrationLog "===== CARD ENDPOINT MIGRATION COMPLETED =====" 'INFO'
Write-MigrationLog "Total: $(($successCount + $appSuccessCount)) cards migrated, $(($failCount + $appFailCount)) failed" 'INFO'

if (-not $WhatIf) {
    Write-Host ""
    Write-Host "NEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Run: .\update_card_references.ps1 to update all URL references" -ForegroundColor Yellow
    Write-Host "2. Test the application" -ForegroundColor Yellow
    Write-Host "3. Commit changes if everything works" -ForegroundColor Yellow
}
