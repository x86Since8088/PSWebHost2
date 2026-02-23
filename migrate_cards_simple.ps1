# Simple Card Directory Migration Script
# Moves entire card directories from /api/v1/ui/elements/ to /cards/

$ErrorActionPreference = 'Stop'

# Core cards to migrate (excluding main-menu which is done)
$coreCards = @(
    'help-viewer', 'job-status', 'markdown-viewer', 'nodes-manager',
    'site-settings', 'system-status', 'event-stream', 'memory-explorer',
    'system-log', 'card-validation'
)

# Admin cards
$adminCards = @('role-management', 'users-management')

# Migrate core cards
Write-Host "Migrating core cards..." -ForegroundColor Cyan
foreach ($card in $coreCards) {
    $oldPath = "routes/api/v1/ui/elements/$card"
    $newPath = "routes/cards/$card"

    if (Test-Path $oldPath) {
        if (-not (Test-Path $newPath)) {
            Write-Host "  Moving $card..." -ForegroundColor Yellow
            Move-Item -Path $oldPath -Destination $newPath -Force
            Write-Host "  ✓ $card migrated" -ForegroundColor Green
        } else {
            Write-Host "  ~ $card already migrated" -ForegroundColor Gray
        }
    } else {
        Write-Host "  × $card not found" -ForegroundColor Red
    }
}

# Migrate admin cards
Write-Host "`nMigrating admin cards..." -ForegroundColor Cyan
foreach ($card in $adminCards) {
    $oldPath = "routes/api/v1/ui/elements/admin/$card"
    $newPath = "routes/cards/admin/$card"

    if (Test-Path $oldPath) {
        if (-not (Test-Path $newPath)) {
            Write-Host "  Moving admin/$card..." -ForegroundColor Yellow
            Move-Item -Path $oldPath -Destination $newPath -Force
            Write-Host "  ✓ admin/$card migrated" -ForegroundColor Green
        } else {
            Write-Host "  ~ admin/$card already migrated" -ForegroundColor Gray
        }
    } else {
        Write-Host "  × admin/$card not found" -ForegroundColor Red
    }
}

# App cards - define by app
$appCards = @{
    'DockerManager' = @('docker-manager', 'dockermanager-home')
    'KubernetesManager' = @('kubernetes-status', 'kubernetesmanager-home')
    'SQLiteManager' = @('sqlite-manager', 'sqlite-query-editor')
    'WSLManager' = @('wsl-manager', 'wslmanager-home')
    'WindowsAdmin' = @('service-control', 'task-scheduler', 'windowsadmin-home')
    'LinuxAdmin' = @('linux-cron', 'linux-services', 'linuxadmin-home')
    'MySQLManager' = @('mysql-manager')
    'RedisManager' = @('redis-manager')
    'SQLServerManager' = @('sqlserver-manager')
    'vault' = @('vault-manager')
    'UI_Uplot' = @('uplot-home', 'time-series', 'area-chart', 'bar-chart', 'scatter-plot', 'multi-axis', 'heatmap')
    'Maps' = @('world-map')
    'WebHostMetrics' = @('server-heatmap', 'memory-histogram')
    'WebhostFileExplorer' = @('file-explorer', 'text-editor', 'hex-editor', 'file-sharing-modal')
    'WebhostRealtimeEvents' = @('realtime-events')
    'WebHostDebugExtensions' = @('debug-console')
    'WebHostAppManager' = @('apps-manager')
    'WebHostDebugVariables' = @('debug-variables')
    'WebHostHelpViewer' = @('help-viewer')
    'WebHostTaskManagement' = @('task-manager')
    'UnitTests' = @('unit-test-runner')
}

# Migrate app cards
Write-Host "`nMigrating app cards..." -ForegroundColor Cyan
foreach ($app in $appCards.Keys) {
    Write-Host "`n  App: $app" -ForegroundColor Magenta

    foreach ($card in $appCards[$app]) {
        $oldPath = "apps/$app/routes/api/v1/ui/elements/$card"
        $newPath = "apps/$app/routes/cards/$card"

        if (Test-Path $oldPath) {
            if (-not (Test-Path $newPath)) {
                Write-Host "    Moving $card..." -ForegroundColor Yellow
                $newParent = Split-Path $newPath -Parent
                if (-not (Test-Path $newParent)) {
                    New-Item -Path $newParent -ItemType Directory -Force | Out-Null
                }
                Move-Item -Path $oldPath -Destination $newPath -Force
                Write-Host "    ✓ $card migrated" -ForegroundColor Green
            } else {
                Write-Host "    ~ $card already migrated" -ForegroundColor Gray
            }
        } else {
            Write-Host "    × $card not found" -ForegroundColor Red
        }
    }
}

Write-Host "`n✓ Migration complete!" -ForegroundColor Green
Write-Host "`nNext: Run update_card_url_references.ps1 to update all URL references" -ForegroundColor Yellow
