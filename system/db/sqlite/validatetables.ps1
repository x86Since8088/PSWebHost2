[cmdletbinding()]
param(
    [string]$DatabaseFile,
    [string]$ConfigFile
)
$ScriptRoot = $PSScriptRoot
if (!$OldVerbosePreference) {
    $OldVerbosePreference = $VerbosePreference 
}
$ProjectRoot = $ScriptRoot -replace '[\\/]System[\\/].*'
if ($null -eq $Global:PSWebServer) {
    # Dot-source the main init script to load the environment
    $InitScript = $ProjectRoot
    'system','init.ps1'|ForEach-Object{$InitScript = Join-Path $InitScript $_} 
    . $InitScript -Loadvariables
}
# If the environment is already loaded, we can get the ProjectRoot from the global variable
else {
    $ProjectRoot = $global:PSWebServer.Project_Root.Path
}
$VerbosePreference = 'continue'
if (!$DatabaseFile) {
    $DatabaseFile = Join-Path $ProjectRoot "PsWebHost_Data/pswebhost.db"
}
if (!$ConfigFile) {
    $ConfigFile = Join-Path $ProjectRoot "system/db/sqlite/sqliteconfig.json"
}

# Import required modules
Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Database") -DisableNameChecking -Verbose:$False

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
        # --- Compare schemas and update if necessary ---
        Write-Verbose "Table '$tableName' exists. Verifying schema."
        $pragmaQuery = "PRAGMA table_info('$tableName');"
        $existingColumns = Get-PSWebSQLiteData -File $DatabaseFile -Query $pragmaQuery
        
        $needsRebuild = $false

        # 1. Check for schema differences (column types, constraints, PK)
        $schemaColumnsByName = $table.columns | Group-Object -Property name -AsHashTable
        $existingColumnsByName = $existingColumns | Group-Object -Property name -AsHashTable

        # Check for columns that have been removed in the schema
        $removedColumns = $existingColumnsByName.Keys | Where-Object { -not $schemaColumnsByName.ContainsKey($_) }
        if ($removedColumns) {
            $needsRebuild = $true
            Write-Verbose "Reason for rebuild: Columns to be removed: $($removedColumns -join ', ')"
        }

        if (-not $needsRebuild) {
            foreach($colName in $schemaColumnsByName.Keys) {
                $schemaCol = $schemaColumnsByName[$colName]
                $existingCol = $existingColumnsByName[$colName]

                if (-not $existingCol) {
                    # This is a new column, can be added without rebuild
                    continue
                }

                # Compare Type
                if ($schemaCol.type -ne $existingCol.type) {
                    $needsRebuild = $true
                    Write-Verbose "Reason for rebuild: Type mismatch for column '$colName' ('$($schemaCol.type)' vs '$($existingCol.type)')"
                    break
                }

                # Compare NOT NULL constraint
                $schemaNotNull = $schemaCol.constraint -like '*NOT NULL*'
                $existingNotNull = [bool]$existingCol.notnull
                if ($schemaNotNull -ne $existingNotNull) {
                    $needsRebuild = $true
                    Write-Verbose "Reason for rebuild: NOT NULL mismatch for column '$colName'"
                    break
                }
            }
        }

        # 2. Check for primary key differences
        if (-not $needsRebuild) {
            $schemaPK = @(($table.columns | Where-Object{$_.constraint -match '\bprimary\b'}).Name | Sort-Object)
            if ($schemaPK) {
                $dbPK = @(($existingColumns | Where-Object { ($_.pk -band 1) -eq 1 } | Sort-Object -Property pk).name)
                if ((Compare-Object $schemaPK $dbPK).Count -gt 0) {
                    $needsRebuild = $true
                    Write-Verbose "Reason for rebuild: Primary key mismatch."
                }
            }
        }

        if ($needsRebuild) {
            Write-Host "Schema mismatch for table '$tableName'. Rebuilding table."

            # 1. Rename old table
            $tempTableName = "${tableName}_old_$(Get-Date -Format 'yyyyMMddHHmmss')"
            $renameQuery = "ALTER TABLE `"$tableName`" RENAME TO `"$tempTableName`";"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $renameQuery
            Write-Verbose "Renamed table '$tableName' to '$tempTableName'"

            # 2. Create new table with correct schema
            $columnsDef = @()
            foreach ($col in $table.columns) {
                $columnsDef += "`"$($col.name)`" $($col.type) $($col.constraint)"
            }
            if ($table.primary_key) {
                $pk = $table.primary_key -join '", "'
                $columnsDef += "PRIMARY KEY (`"$pk`")"
            }
            $createQuery = "CREATE TABLE `"$tableName`" ($($columnsDef -join ', '));"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $createQuery
            Write-Verbose "Created new table '$tableName' with updated schema."

            # 3. Copy data from old table to new table
            $oldColumns = (Get-PSWebSQLiteData -File $DatabaseFile -Query "PRAGMA table_info('$tempTableName');").name
            $newColumns = ($table.columns).name
            $commonColumns = $oldColumns | Where-Object { $_ -in $newColumns }
            
            if ($commonColumns.Count -gt 0) {
                $colList = ($commonColumns | ForEach-Object { "`"$_`"" }) -join ', '
                $copyQuery = "INSERT INTO `"$tableName`" ($colList) SELECT $colList FROM `"$tempTableName`";"
                try {
                    Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $copyQuery
                    Write-Verbose "Copied data from '$tempTableName' to '$tableName'."
                } catch {
                    Write-Error "Failed to copy data during table rebuild. Error: $_ "
                    Write-Error "The original data is preserved in '$tempTableName'. Manual intervention may be required."
                    # Optionally, try to revert the rename.
                    # $revertQuery = "ALTER TABLE `"$tempTableName`" RENAME TO `"$tableName`";"
                    # Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $revertQuery
                    return
                }
            }

            # 4. Drop old table
            $dropQuery = "DROP TABLE `"$tempTableName`";"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $dropQuery
            Write-Verbose "Dropped old table '$tempTableName'."

        } else {
            # --- No rebuild needed, just add missing columns ---
            $existingColumnNames = $existingColumns | ForEach-Object { $_.name }
            foreach ($column in $table.columns) {
                if ($column.name -notin $existingColumnNames) {
                    Write-Host "Column '$($column.name)' not found in table '$tableName'. Adding it."
                    $addColumnQuery = "ALTER TABLE `"$tableName`" ADD COLUMN `"$($column.name)`" $($column.type) $($column.constraint);"
                    Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $addColumnQuery
                }
            }
        }
    }
}

# --- Validate and create views ---
if ($schema.views) {
    foreach ($view in $schema.views) {
        $viewName = $view.name
        Write-Verbose "Validating view: $viewName"

        # Check if view exists
        $checkViewQuery = "SELECT name FROM sqlite_master WHERE type='view' AND name='$viewName';"
        $viewExists = Get-PSWebSQLiteData -File $DatabaseFile -Query $checkViewQuery

        if (-not $viewExists) {
            Write-Host "View '$viewName' not found. Creating it."
            $createViewQuery = "CREATE VIEW `"$viewName`" AS $($view.definition);"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $createViewQuery
        } else {
            # View exists - drop and recreate to ensure it matches the definition
            Write-Verbose "View '$viewName' exists. Recreating to ensure current definition."
            $dropViewQuery = "DROP VIEW `"$viewName`";"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $dropViewQuery
            $createViewQuery = "CREATE VIEW `"$viewName`" AS $($view.definition);"
            Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Query $createViewQuery
        }
    }
}

Write-Verbose "Database schema validation complete."
$VerbosePreference = $OldVerbosePreference
