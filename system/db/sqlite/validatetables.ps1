[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$DatabaseFile,

    [Parameter(Mandatory=$true)]
    [string]$ConfigFile
)

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database/PSWebHost_Database.psm1") -DisableNameChecking

if (-not (Test-Path $ConfigFile)) {
    Write-Error "Schema config file not found: $ConfigFile"
    return
}

$schema = Get-Content -Path $ConfigFile | ConvertFrom-Json

foreach ($table in $schema.tables) {
    $tableName = $table.name
    Write-Verbose "Validating table: $tableName"

    # Check if table exists
    $checkTableQuery = "SELECT name FROM sqlite_master WHERE type='table' AND name='$tableName';"
    $tableExists = Get-PSWebSQLiteData -File $DatabaseFile -Query $checkTableQuery

    if (-not $tableExists) {
        # --- Create Table --- 
        Write-Host "Table '$tableName' not found. Creating it."
        $columnsDef = @()
        foreach ($col in $table.columns) {
            $columnsDef += "`"$($col.name)`" $($col.type) $($col.constraint)"
        }
        if ($table.primary_key) {
            $pk = $table.primary_key -join ", "
            $columnsDef += "PRIMARY KEY ($pk)"
        }
        $createQuery = "CREATE TABLE `"$tableName`" ($($columnsDef -join ", "));"
        Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $createQuery
    } else {
        # --- Check and Add Columns ---
        $pragmaQuery = "PRAGMA table_info('$tableName');"
        $existingColumns = Get-PSWebSQLiteData -File $DatabaseFile -Query $pragmaQuery
        $existingColumnNames = $existingColumns | ForEach-Object { $_.name }

        foreach ($column in $table.columns) {
            if ($column.name -notin $existingColumnNames) {
                Write-Host "Column '$($column.name)' not found in table '$tableName'. Adding it."
                $addColumnQuery = "ALTER TABLE `"$tableName`" ADD COLUMN `"$($column.name)"`" $($column.type) $($column.constraint);"
                Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $addColumnQuery
            }
        }
    }
}

Write-Verbose "Database schema validation complete."
