<#
.SYNOPSIS
    Migrates all OS and Container components to their respective apps

.DESCRIPTION
    Moves routes, public elements, tests, and system files for:
    - WindowsAdmin (services, tasks)
    - LinuxAdmin (linux-services, linux-cron)
    - WSLManager (wsl-manager)
    - DockerManager (docker-manager)
    - KubernetesManager (kubernetes-status)

.PARAMETER WhatIf
    Simulate the migration without actually moving files
#>

param(
    [switch]$WhatIf
)

$projectRoot = $PSScriptRoot
Set-Location $projectRoot

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "OS & Container Apps Migration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "MODE: DRY RUN (WhatIf)" -ForegroundColor Yellow
    Write-Host "No files will actually be moved`n" -ForegroundColor Yellow
}

# Define migrations
$migrations = @(
    # WindowsAdmin
    @{
        App = "WindowsAdmin"
        Components = @(
            "routes/api/v1/system/services",
            "routes/api/v1/system/tasks",
            "public/elements/service-control",
            "routes/api/v1/ui/elements/service-control",
            "public/elements/task-scheduler",
            "routes/api/v1/ui/elements/task-scheduler"
        )
    },

    # LinuxAdmin
    @{
        App = "LinuxAdmin"
        Components = @(
            "routes/api/v1/ui/elements/linux-services",
            "public/elements/linux-services",
            "routes/api/v1/ui/elements/linux-cron",
            "public/elements/linux-cron"
        )
    },

    # WSLManager
    @{
        App = "WSLManager"
        Components = @(
            "routes/api/v1/ui/elements/wsl-manager",
            "public/elements/wsl-manager"
        )
    },

    # DockerManager
    @{
        App = "DockerManager"
        Components = @(
            "routes/api/v1/ui/elements/docker-manager",
            "public/elements/docker-manager"
        )
    },

    # KubernetesManager
    @{
        App = "KubernetesManager"
        Components = @(
            "routes/api/v1/ui/elements/kubernetes-status",
            "public/elements/kubernetes-status"
        )
    }
)

$totalComponents = ($migrations | ForEach-Object { $_.Components.Count } | Measure-Object -Sum).Sum
$current = 0

foreach ($migration in $migrations) {
    Write-Host "`n========== $($migration.App) ==========" -ForegroundColor Cyan

    foreach ($component in $migration.Components) {
        $current++
        Write-Host "`n[$current/$totalComponents] Processing: $component" -ForegroundColor Yellow

        $params = @{
            ComponentPath = $component
            TargetApp = $migration.App
        }

        if ($WhatIf) {
            $params.WhatIf = $true
        }

        try {
            & ".\system\utility\Move-ComponentToApp.ps1" @params
            if (-not $?) {
                throw "Move-ComponentToApp.ps1 failed"
            }
        } catch {
            if (-not $WhatIf) {
                Write-Host "ERROR migrating $component : $($_.Exception.Message)" -ForegroundColor Red
                $continue = Read-Host "Continue? (y/n)"
                if ($continue -ne 'y') {
                    exit 1
                }
            }
        }
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "Migration $(if ($WhatIf) { 'Simulation' } else { 'Complete' })!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green

if (-not $WhatIf) {
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  - Moved $totalComponents component groups" -ForegroundColor White
    Write-Host "  - Updated 5 apps" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Update each app's menu.yaml" -ForegroundColor Gray
    Write-Host "  2. Restart PSWebHost" -ForegroundColor Gray
    Write-Host "  3. Test all functionality" -ForegroundColor Gray
    Write-Host "  4. Consider moving tests and help files with -IncludeTests -IncludeHelp" -ForegroundColor Gray
    Write-Host ""
}
