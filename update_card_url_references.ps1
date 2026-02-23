# Update Card URL References Script
# Finds and replaces all old card URL patterns with new /cards/ pattern

param(
    [switch]$WhatIf = $false
)

$ErrorActionPreference = 'Stop'
$updatedFiles = @()
$skippedFiles = @()

function Update-FileContent {
    param(
        [string]$FilePath,
        [hashtable]$Replacements
    )

    if (-not (Test-Path $FilePath)) {
        return $false
    }

    # Skip binary files
    $ext = [System.IO.Path]::GetExtension($FilePath)
    if ($ext -in @('.db', '.exe', '.dll', '.png', '.jpg', '.gif', '.ico', '.woff', '.woff2', '.ttf', '.eot')) {
        $script:skippedFiles += $FilePath
        return $false
    }

    try {
        $content = Get-Content -Path $FilePath -Raw -ErrorAction Stop
        $originalContent = $content
        $changed = $false

        foreach ($oldPattern in $Replacements.Keys) {
            $newPattern = $Replacements[$oldPattern]
            if ($content -match [regex]::Escape($oldPattern)) {
                $content = $content -replace [regex]::Escape($oldPattern), $newPattern
                $changed = $true
            }
        }

        if ($changed) {
            if ($WhatIf) {
                Write-Host "WOULD UPDATE: $FilePath" -ForegroundColor Yellow
            } else {
                Set-Content -Path $FilePath -Value $content -NoNewline
                Write-Host "UPDATED: $FilePath" -ForegroundColor Green
            }
            $script:updatedFiles += $FilePath
            return $true
        }
    } catch {
        Write-Host "ERROR reading $FilePath : $_" -ForegroundColor Red
    }

    return $false
}

Write-Host "===== UPDATING CARD URL REFERENCES =====" -ForegroundColor Cyan
Write-Host "Mode: $(if ($WhatIf) { 'WHAT-IF' } else { 'LIVE' })`n" -ForegroundColor Cyan

# Define all URL replacements
# Core cards
$coreReplacements = @{
    '/api/v1/ui/elements/help-viewer' = '/cards/help-viewer'
    '/api/v1/ui/elements/job-status' = '/cards/job-status'
    '/api/v1/ui/elements/markdown-viewer' = '/cards/markdown-viewer'
    '/api/v1/ui/elements/nodes-manager' = '/cards/nodes-manager'
    '/api/v1/ui/elements/site-settings' = '/cards/site-settings'
    '/api/v1/ui/elements/system-status' = '/cards/system-status'
    '/api/v1/ui/elements/event-stream' = '/cards/event-stream'
    '/api/v1/ui/elements/memory-explorer' = '/cards/memory-explorer'
    '/api/v1/ui/elements/system-log' = '/cards/system-log'
    '/api/v1/ui/elements/card-validation' = '/cards/card-validation'
    '/api/v1/ui/elements/admin/role-management' = '/cards/admin/role-management'
    '/api/v1/ui/elements/admin/users-management' = '/cards/admin/users-management'
}

# App cards
$appReplacements = @{
    '/apps/dockermanager/api/v1/ui/elements/docker-manager' = '/apps/dockermanager/cards/docker-manager'
    '/apps/dockermanager/api/v1/ui/elements/dockermanager-home' = '/apps/dockermanager/cards/dockermanager-home'
    '/apps/kubernetesmanager/api/v1/ui/elements/kubernetes-status' = '/apps/kubernetesmanager/cards/kubernetes-status'
    '/apps/kubernetesmanager/api/v1/ui/elements/kubernetesmanager-home' = '/apps/kubernetesmanager/cards/kubernetesmanager-home'
    '/apps/sqlitemanager/api/v1/ui/elements/sqlite-manager' = '/apps/sqlitemanager/cards/sqlite-manager'
    '/apps/sqlitemanager/api/v1/ui/elements/sqlite-query-editor' = '/apps/sqlitemanager/cards/sqlite-query-editor'
    '/apps/wslmanager/api/v1/ui/elements/wsl-manager' = '/apps/wslmanager/cards/wsl-manager'
    '/apps/wslmanager/api/v1/ui/elements/wslmanager-home' = '/apps/wslmanager/cards/wslmanager-home'
    '/apps/windowsadmin/api/v1/ui/elements/service-control' = '/apps/windowsadmin/cards/service-control'
    '/apps/windowsadmin/api/v1/ui/elements/task-scheduler' = '/apps/windowsadmin/cards/task-scheduler'
    '/apps/windowsadmin/api/v1/ui/elements/windowsadmin-home' = '/apps/windowsadmin/cards/windowsadmin-home'
    '/apps/linuxadmin/api/v1/ui/elements/linux-cron' = '/apps/linuxadmin/cards/linux-cron'
    '/apps/linuxadmin/api/v1/ui/elements/linux-services' = '/apps/linuxadmin/cards/linux-services'
    '/apps/linuxadmin/api/v1/ui/elements/linuxadmin-home' = '/apps/linuxadmin/cards/linuxadmin-home'
    '/apps/mysqlmanager/api/v1/ui/elements/mysql-manager' = '/apps/mysqlmanager/cards/mysql-manager'
    '/apps/redismanager/api/v1/ui/elements/redis-manager' = '/apps/redismanager/cards/redis-manager'
    '/apps/sqlservermanager/api/v1/ui/elements/sqlserver-manager' = '/apps/sqlservermanager/cards/sqlserver-manager'
    '/apps/vault/api/v1/ui/elements/vault-manager' = '/apps/vault/cards/vault-manager'
    '/apps/UI_Uplot/api/v1/ui/elements/uplot-home' = '/apps/UI_Uplot/cards/uplot-home'
    '/apps/UI_Uplot/api/v1/ui/elements/time-series' = '/apps/UI_Uplot/cards/time-series'
    '/apps/UI_Uplot/api/v1/ui/elements/area-chart' = '/apps/UI_Uplot/cards/area-chart'
    '/apps/UI_Uplot/api/v1/ui/elements/bar-chart' = '/apps/UI_Uplot/cards/bar-chart'
    '/apps/UI_Uplot/api/v1/ui/elements/scatter-plot' = '/apps/UI_Uplot/cards/scatter-plot'
    '/apps/UI_Uplot/api/v1/ui/elements/multi-axis' = '/apps/UI_Uplot/cards/multi-axis'
    '/apps/UI_Uplot/api/v1/ui/elements/heatmap' = '/apps/UI_Uplot/cards/heatmap'
    '/apps/Maps/api/v1/ui/elements/world-map' = '/apps/Maps/cards/world-map'
    '/apps/WebHostMetrics/api/v1/ui/elements/server-heatmap' = '/apps/WebHostMetrics/cards/server-heatmap'
    '/apps/WebHostMetrics/api/v1/ui/elements/memory-histogram' = '/apps/WebHostMetrics/cards/memory-histogram'
    '/apps/WebhostFileExplorer/api/v1/ui/elements/file-explorer' = '/apps/WebhostFileExplorer/cards/file-explorer'
    '/apps/WebhostFileExplorer/api/v1/ui/elements/text-editor' = '/apps/WebhostFileExplorer/cards/text-editor'
    '/apps/WebhostFileExplorer/api/v1/ui/elements/hex-editor' = '/apps/WebhostFileExplorer/cards/hex-editor'
    '/apps/WebhostFileExplorer/api/v1/ui/elements/file-sharing-modal' = '/apps/WebhostFileExplorer/cards/file-sharing-modal'
    '/apps/WebhostRealtimeEvents/api/v1/ui/elements/realtime-events' = '/apps/WebhostRealtimeEvents/cards/realtime-events'
    '/apps/WebHostDebugExtensions/api/v1/ui/elements/debug-console' = '/apps/WebHostDebugExtensions/cards/debug-console'
    '/apps/WebHostAppManager/api/v1/ui/elements/apps-manager' = '/apps/WebHostAppManager/cards/apps-manager'
    '/apps/WebHostDebugVariables/api/v1/ui/elements/debug-variables' = '/apps/WebHostDebugVariables/cards/debug-variables'
    '/apps/WebHostHelpViewer/api/v1/ui/elements/help-viewer' = '/apps/WebHostHelpViewer/cards/help-viewer'
    '/apps/WebHostTaskManagement/api/v1/ui/elements/task-manager' = '/apps/WebHostTaskManagement/cards/task-manager'
    '/apps/UnitTests/api/v1/ui/elements/unit-test-runner' = '/apps/UnitTests/cards/unit-test-runner'
}

$allReplacements = $coreReplacements + $appReplacements

# Find all files to update (excluding migration plan and logs)
Write-Host "Finding files to update..." -ForegroundColor Cyan

$filesToUpdate = @()

# Menu.yaml files
$filesToUpdate += Get-ChildItem -Path "apps/*/menu.yaml" -Recurse -ErrorAction SilentlyContinue
$filesToUpdate += Get-ChildItem -Path "routes/api/v1/ui/elements/main-menu/main-menu.yaml" -ErrorAction SilentlyContinue

# Component JavaScript files
$filesToUpdate += Get-ChildItem -Path "public" -Filter "*.js" -Recurse -ErrorAction SilentlyContinue
$filesToUpdate += Get-ChildItem -Path "apps/*/public" -Filter "*.js" -Recurse -ErrorAction SilentlyContinue

# HTML files
$filesToUpdate += Get-ChildItem -Path "public" -Filter "*.html" -Recurse -ErrorAction SilentlyContinue
$filesToUpdate += Get-ChildItem -Path "apps/*/public" -Filter "*.html" -Recurse -ErrorAction SilentlyContinue

# PowerShell test files
$filesToUpdate += Get-ChildItem -Path "tests" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
$filesToUpdate += Get-ChildItem -Path "test_*.ps1" -ErrorAction SilentlyContinue

# Markdown documentation
$filesToUpdate += Get-ChildItem -Path "apps/*/*.md" -Recurse -ErrorAction SilentlyContinue
$filesToUpdate += Get-ChildItem -Path "*.md" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "CARD_MIGRATION*" }

Write-Host "Found $($filesToUpdate.Count) files to process`n" -ForegroundColor Cyan

# Update each file
$updateCount = 0
foreach ($file in $filesToUpdate) {
    if (Update-FileContent -FilePath $file.FullName -Replacements $allReplacements) {
        $updateCount++
    }
}

Write-Host "`n===== UPDATE COMPLETE =====" -ForegroundColor Cyan
Write-Host "Files updated: $updateCount / $($filesToUpdate.Count)" -ForegroundColor Green
Write-Host "Files skipped: $($skippedFiles.Count) (binary/special files)" -ForegroundColor Gray

if ($updatedFiles.Count -gt 0) {
    $logFile = "card_url_update_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
    $updatedFiles | Out-File $logFile
    Write-Host "`nUpdated files list saved to: $logFile" -ForegroundColor Yellow
}

if (-not $WhatIf) {
    Write-Host "`nNEXT STEPS:" -ForegroundColor Yellow
    Write-Host "1. Test the application to ensure all cards load correctly" -ForegroundColor Yellow
    Write-Host "2. Check git diff to review changes" -ForegroundColor Yellow
    Write-Host "3. Commit if everything works" -ForegroundColor Yellow
}
