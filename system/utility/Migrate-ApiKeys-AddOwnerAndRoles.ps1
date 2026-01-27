# Migrate-ApiKeys-AddOwnerAndRoles.ps1
# Adds Owner field to API_Keys table and creates API_Key_Roles junction table

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Load WebHost environment
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\')).Path
. (Join-Path $ProjectRoot "WebHost.ps1") -ShowVariables 3>$null 4>$null | Out-Null

$dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

Write-Host "`nAPI Keys Database Migration" -ForegroundColor Cyan
Write-Host "=============================" -ForegroundColor Cyan

# Check if Owner column already exists
$tableInfo = Get-PSWebSQLiteData -File $dbFile -Query "PRAGMA table_info(API_Keys);"
$hasOwner = $tableInfo | Where-Object { $_.name -eq 'Owner' }
$hasOwnerType = $tableInfo | Where-Object { $_.name -eq 'OwnerType' }

if ($hasOwner -and $hasOwnerType) {
    Write-Host "`n✓ Owner columns already exist in API_Keys table" -ForegroundColor Green
} else {
    Write-Host "`n→ Adding Owner and OwnerType columns to API_Keys table..." -ForegroundColor Yellow

    if ($WhatIf) {
        Write-Host "  [WHATIF] Would execute:" -ForegroundColor Gray
        Write-Host "  ALTER TABLE API_Keys ADD COLUMN Owner TEXT DEFAULT 'system';" -ForegroundColor Gray
        Write-Host "  ALTER TABLE API_Keys ADD COLUMN OwnerType TEXT DEFAULT 'User';" -ForegroundColor Gray
    } else {
        try {
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query "ALTER TABLE API_Keys ADD COLUMN Owner TEXT DEFAULT 'system';"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query "ALTER TABLE API_Keys ADD COLUMN OwnerType TEXT DEFAULT 'User';"
            Write-Host "  ✓ Owner columns added successfully" -ForegroundColor Green
        } catch {
            Write-Host "  ✗ Failed to add Owner columns: $($_.Exception.Message)" -ForegroundColor Red
            throw
        }
    }
}

# Check if Users table has Owner column
$usersTableInfo = Get-PSWebSQLiteData -File $dbFile -Query "PRAGMA table_info(Users);"
$usersHasOwner = $usersTableInfo | Where-Object { $_.name -eq 'Owner' }
$usersHasOwnerType = $usersTableInfo | Where-Object { $_.name -eq 'OwnerType' }

if ($usersHasOwner -and $usersHasOwnerType) {
    Write-Host "`n✓ Owner columns already exist in Users table" -ForegroundColor Green
} else {
    Write-Host "`n→ Adding Owner and OwnerType columns to Users table..." -ForegroundColor Yellow
    Write-Host "  (Each API key has its own user account, with Owner pointing to the managing user)" -ForegroundColor Gray

    if ($WhatIf) {
        Write-Host "  [WHATIF] Would execute:" -ForegroundColor Gray
        Write-Host "  ALTER TABLE Users ADD COLUMN Owner TEXT;" -ForegroundColor Gray
        Write-Host "  ALTER TABLE Users ADD COLUMN OwnerType TEXT DEFAULT 'User';" -ForegroundColor Gray
    } else {
        try {
            # SQLite doesn't have ALTER COLUMN, so we can only ADD
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query "ALTER TABLE Users ADD COLUMN Owner TEXT;"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query "ALTER TABLE Users ADD COLUMN OwnerType TEXT DEFAULT 'User';"
            Write-Host "  ✓ Owner columns added to Users table successfully" -ForegroundColor Green
        } catch {
            if ($_.Exception.Message -like "*duplicate column name*") {
                Write-Host "  ✓ Owner columns already exist (duplicate error ignored)" -ForegroundColor Green
            } else {
                Write-Host "  ✗ Failed to add Owner columns to Users: $($_.Exception.Message)" -ForegroundColor Red
                throw
            }
        }
    }
}

# Summary
Write-Host "`n" -NoNewline
Write-Host "Migration Summary" -ForegroundColor Cyan
Write-Host "=================" -ForegroundColor Cyan

$finalTableInfo = Get-PSWebSQLiteData -File $dbFile -Query "PRAGMA table_info(API_Keys);"
$finalTables = Get-PSWebSQLiteData -File $dbFile -Query "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('API_Keys', 'API_Key_Roles');"

Write-Host "`nAPI_Keys table columns:" -ForegroundColor Yellow
$finalTableInfo | Select-Object name, type | Format-Table -AutoSize

$finalUsersInfo = Get-PSWebSQLiteData -File $dbFile -Query "PRAGMA table_info(Users);"
Write-Host "Users table columns (showing Owner-related):" -ForegroundColor Yellow
$finalUsersInfo | Where-Object { $_.name -in @('UserID', 'Email', 'Owner', 'OwnerType') } | Select-Object name, type | Format-Table -AutoSize

Write-Host "Architecture:" -ForegroundColor Cyan
Write-Host "  • Each API key → Linked to dedicated User account (via UserID)" -ForegroundColor White
Write-Host "  • Dedicated User account → Has Owner field (UserID/GroupID of managing user)" -ForegroundColor White
Write-Host "  • Roles → Assigned via PSWeb_Roles table (same as regular users)" -ForegroundColor White
Write-Host "  • Owner → Can manage all API keys they own (for vault integration)" -ForegroundColor White

if (-not $WhatIf) {
    Write-Host "`n✓ Migration completed successfully" -ForegroundColor Green
} else {
    Write-Host "`n[WHATIF] No changes made - use without -WhatIf to apply" -ForegroundColor Yellow
}

Write-Host ""
