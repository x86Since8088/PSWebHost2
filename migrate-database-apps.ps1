<#
.SYNOPSIS
    Migrates all Database components to their respective apps

.DESCRIPTION
    Moves routes, public elements, tests, and system files for:
    - MySQLManager (mysql-manager)
    - RedisManager (redis-manager)
    - SQLiteManager (sqlite-manager)
    - SQLServerManager (sqlserver-manager)
    - VaultManager (vault-manager)

.PARAMETER WhatIf
    Simulate the migration without actually moving files
#>

param(
    [switch]$WhatIf
)

$projectRoot = $PSScriptRoot
Set-Location $projectRoot

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Database Apps Migration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

if ($WhatIf) {
    Write-Host "MODE: DRY RUN (WhatIf)" -ForegroundColor Yellow
    Write-Host "No files will actually be moved`n" -ForegroundColor Yellow
}

# Define migrations
$migrations = @(
    # MySQLManager
    @{
        App = "MySQLManager"
        Components = @(
            "routes/api/v1/ui/elements/mysql-manager",
            "public/elements/mysql-manager"
        )
    },

    # RedisManager
    @{
        App = "RedisManager"
        Components = @(
            "routes/api/v1/ui/elements/redis-manager",
            "public/elements/redis-manager"
        )
    },

    # SQLiteManager
    @{
        App = "SQLiteManager"
        Components = @(
            "routes/api/v1/ui/elements/sqlite-manager",
            "public/elements/sqlite-manager"
        )
    },

    # SQLServerManager
    @{
        App = "SQLServerManager"
        Components = @(
            "routes/api/v1/ui/elements/sqlserver-manager",
            "public/elements/sqlserver-manager"
        )
    },

    # VaultManager
    @{
        App = "VaultManager"
        Components = @(
            "routes/api/v1/ui/elements/vault-manager",
            "public/elements/vault-manager"
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
    Write-Host "  - Updated 5 database apps" -ForegroundColor White
    Write-Host ""
    Write-Host "Next Steps:" -ForegroundColor Yellow
    Write-Host "  1. Update each app's menu.yaml" -ForegroundColor Gray
    Write-Host "  2. Restart PSWebHost" -ForegroundColor Gray
    Write-Host "  3. Test all functionality" -ForegroundColor Gray
    Write-Host ""
}
