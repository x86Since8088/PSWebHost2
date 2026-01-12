# Create database management apps

$apps = @(
    @{
        Name = "MySQLManager"
        DisplayName = "MySQL Manager"
        Description = "MySQL database administration and monitoring"
        SubCategory = "MySQL"
    },
    @{
        Name = "RedisManager"
        DisplayName = "Redis Manager"
        Description = "Redis cache and data structure management"
        SubCategory = "Redis"
    },
    @{
        Name = "SQLiteManager"
        DisplayName = "SQLite Manager"
        Description = "SQLite database file management"
        SubCategory = "SQLite"
    },
    @{
        Name = "SQLServerManager"
        DisplayName = "SQL Server Manager"
        Description = "Microsoft SQL Server administration"
        SubCategory = "SQL Server"
    },
    @{
        Name = "VaultManager"
        DisplayName = "Vault Manager"
        Description = "HashiCorp Vault secrets management"
        SubCategory = "Vault"
    }
)

foreach ($app in $apps) {
    Write-Host "`n=== Creating $($app.DisplayName) ===" -ForegroundColor Cyan

    & ".\system\utility\New-PSWebHostApp.ps1" `
        -AppName $app.Name `
        -DisplayName $app.DisplayName `
        -Description $app.Description `
        -Category "Databases" `
        -SubCategory $app.SubCategory `
        -RequiredRoles @('admin', 'database_admin') `
        -CreateSampleRoute
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host "All Database Apps Created!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Green
