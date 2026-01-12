# Update menu.yaml files for database apps

$menus = @{
    "RedisManager" = @"
# Menu entries for Redis Manager
# These will be integrated into the main PSWebHost menu under:
# Databases > Redis

- Name: Redis Manager
  url: /api/v1/ui/elements/redis-manager
  hover_description: Redis cache and data structure management
  icon: database
  tags:
    - databases
    - redis
    - cache
"@

    "SQLiteManager" = @"
# Menu entries for SQLite Manager
# These will be integrated into the main PSWebHost menu under:
# Databases > SQLite

- Name: SQLite Manager
  url: /api/v1/ui/elements/sqlite-manager
  hover_description: SQLite database file management
  icon: database
  tags:
    - databases
    - sqlite
    - sql
"@

    "SQLServerManager" = @"
# Menu entries for SQL Server Manager
# These will be integrated into the main PSWebHost menu under:
# Databases > SQL Server

- Name: SQL Server Manager
  url: /api/v1/ui/elements/sqlserver-manager
  hover_description: Microsoft SQL Server administration
  icon: database
  tags:
    - databases
    - sqlserver
    - sql
    - microsoft
"@

    "VaultManager" = @"
# Menu entries for Vault Manager
# These will be integrated into the main PSWebHost menu under:
# Databases > Vault

- Name: Vault Manager
  url: /api/v1/ui/elements/vault-manager
  hover_description: HashiCorp Vault secrets management
  icon: lock
  tags:
    - databases
    - vault
    - secrets
    - security
"@
}

foreach ($app in $menus.Keys) {
    $menuPath = "apps\$app\menu.yaml"
    Write-Host "Updating $menuPath..." -ForegroundColor Yellow
    $menus[$app] | Out-File $menuPath -Encoding UTF8
    Write-Host "  ✓ Updated" -ForegroundColor Green
}

Write-Host "`nAll database app menus updated!" -ForegroundColor Green
