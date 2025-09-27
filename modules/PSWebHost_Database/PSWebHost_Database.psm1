function Get-PSWebSQLiteData {
    [cmdletbinding()]
    param(
        [string]$File,
        [string]$Query
    )

    if (-not $File) { Write-Error "The -File parameter is required."; return }
    if (-not $Query) { Write-Error "The -Query parameter is required."; return }

    # Ensure the database file path is absolute
    if (-not (Test-Path -Path $File -PathType Leaf)) {
        $dbFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/$File"
    } else {
        $dbFilePath = $File
    }

    if (-not (Test-Path $dbFilePath)) {
        # This is not an error condition, as the db may not have been created yet.
        return $null
    }

    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = "Data Source=$dbFilePath"
    $command = $null
    $reader = $null

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $reader = $command.ExecuteReader()

        $results = @()
        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $row[$reader.GetName($i)] = $reader.GetValue($i)
            }
            $results += New-Object PSObject -Property $row
        }
        return $results
    } catch {
        Write-Error "Error executing SQLite query. Query: $Query. Error: $_"
        return $null
    } finally {
        if ($reader) { $reader.Close() }
        if ($command) { $command.Dispose() }
        if ($connection) { $connection.Close() }
    }
}

function Invoke-PSWebSQLiteNonQuery {
    [cmdletbinding()]
    param(
        [string]$File,
        [string]$Query
    )

    if (-not $File) { Write-Error "The -File parameter is required."; return }
    if (-not $Query) { Write-Error "The -Query parameter is required."; return }

    # Ensure the database file path is absolute
    if (-not (Test-Path -Path $File -PathType Leaf)) {
        $dbFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/$File"
    } else {
        $dbFilePath = $File
    }

    # Ensure the directory exists
    $dbDir = Split-Path -Path $dbFilePath -Parent
    if (-not (Test-Path -Path $dbDir)) {
        New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
    }

    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = "Data Source=$dbFilePath"
    $command = $null

    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.ExecuteNonQuery()
    } catch {
        Write-Error "Error executing SQLite non-query. Query: $Query. Error: $_"
    } finally {
        if ($command) { $command.Dispose() }
        if ($connection) { $connection.Close() }
    }
}

function New-PSWebSQLiteData {
    [cmdletbinding()]
    param(
        [string]$File,
        [string]$Table,
        [hashtable]$Data
    )

    if (-not $File) { Write-Error "The -File parameter is required."; return }
    if (-not $Table) { Write-Error "The -Table parameter is required."; return }
    if (-not $Data) { Write-Error "The -Data parameter is required."; return }

    $columns = ($Data.Keys | ForEach-Object { "`"$_`"" }) -join ", "
    
    $values = $Data.Values | ForEach-Object {
        if ($_ -is [string]) {
            "'$(Sanitize-SqlQueryString -String $_)'"
        } elseif ($_ -is [bool]) {
            if ($_) { 1 } else { 0 }
        } elseif ($_ -eq $null) {
            "NULL"
        } else {
            # For numbers or other types, don't quote
            $_
        }
    }
    $valuesString = $values -join ", "

    $query = "INSERT INTO `"$Table`" ($columns) VALUES ($valuesString);"
    
    Invoke-PSWebSQLiteNonQuery -File $File -Query $query
}

function Sanitize-SqlQueryString {
    [cmdletbinding()]
    param(
        [string]$String
    )
    if ($null -eq $String) { return "" }
    # Simple sanitization: escape single quotes
    return $String.Replace("'", "''")
}