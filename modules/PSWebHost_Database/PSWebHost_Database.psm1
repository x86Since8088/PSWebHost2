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
    $MyTag = "[Invoke-PSWebSQLiteNonQuery]"
    Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Started`n`tFile: $File`n`tQuery: $Query"
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
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Creating directory: '$dbDir'"
        New-Item -Path $dbDir -ItemType Directory -Force | Out-Null
    }

    $connection = New-Object System.Data.SQLite.SQLiteConnection
    $connection.ConnectionString = "Data Source=$dbFilePath"
    $command = $null

    try {
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Opening database connection: $dbFilePath"
        $connection.Open()
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        Write-Verbose "$MyTag $((Get-Date -f 'yyyMMdd HH:mm:ss')) Executing query: $Query"
        $null = $command.ExecuteNonQuery()
    } catch {
        Write-Error "Error executing SQLite non-query. Query: $Query. Error: $_"
    } finally {
        if ($command) { $command.Dispose() }
        if ($connection) { 
        
            $connection.Close() 
        }
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


# Manage and query short-lived test/authentication tokens stored in the LoginSessions table
function Invoke-TestToken {
    [cmdletbinding()]
    param(
        [string]$SessionID,
        [string]$AuthenticationState,
        [string]$State,
        [string]$Provider,
        [string]$UserID,
        [string]$UserAgent,
        [int]$ExpiresInMinutes = 30,
        [switch]$Completed
    )

    if (-not $SessionID) { Write-Error "The -SessionID parameter is required."; return $null }

    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    # Determine the target state
    if ($Completed) { $targetState = 'completed' }
    elseif ($AuthenticationState) { $targetState = $AuthenticationState }
    elseif ($State) { $targetState = $State }
    else { $targetState = $null }

    $safeSession = Sanitize-SqlQueryString -String $SessionID

    # If caller is only querying for a specific state, return the row only when it matches
    if ($targetState -and -not $Provider -and -not $UserID -and -not $UserAgent) {
        $q = "SELECT * FROM LoginSessions WHERE SessionID = '$safeSession' LIMIT 1;"
        $row = Get-PSWebSQLiteData -File $dbFile -Query $q
        if ($row) {
            $entry = if ($row -is [System.Array]) { $row[0] } else { $row }
            if ($entry.AuthenticationState -eq $targetState) { return $entry } else { return $null }
        }
        return $null
    }

    # Otherwise, perform an upsert (insert or replace) to record/update the login session state
    # Compute UNIX epoch seconds (UTC)
    $nowUnix = [int]([Math]::Floor((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds))
    $expiresUnix = [int]([Math]::Floor((Get-Date).AddMinutes($ExpiresInMinutes).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds))

    # Try to read existing row so we don't overwrite fields with empty values when caller omitted them
    $existingRow = $null
    try {
        $existingRow = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM LoginSessions WHERE SessionID = '$safeSession' LIMIT 1;"
        if ($existingRow -is [System.Array]) { $existingRow = $existingRow[0] }
    } catch {
        $existingRow = $null
    }

    $effectiveUser = if ($UserID -and $UserID.Trim() -ne '') { $UserID } elseif ($existingRow -and $existingRow.UserID) { $existingRow.UserID } else { '' }
    $effectiveProvider = if ($Provider -and $Provider.Trim() -ne '') { $Provider } elseif ($existingRow -and $existingRow.Provider) { $existingRow.Provider } else { '' }
    $effectiveStateVal = if ($targetState -and $targetState.Trim() -ne '') { $targetState } elseif ($existingRow -and $existingRow.AuthenticationState) { $existingRow.AuthenticationState } else { '' }
    $effectiveUA = if ($UserAgent -and $UserAgent.Trim() -ne '') { $UserAgent } elseif ($existingRow -and $existingRow.UserAgent) { $existingRow.UserAgent } else { '' }

    $safeUser = Sanitize-SqlQueryString -String $effectiveUser
    $safeProvider = Sanitize-SqlQueryString -String $effectiveProvider
    $safeState = Sanitize-SqlQueryString -String $effectiveStateVal
    $safeUA = Sanitize-SqlQueryString -String $effectiveUA

    # Build INSERT OR REPLACE. Use explicit column list to be clear.
    $insertQuery = "INSERT OR REPLACE INTO LoginSessions (SessionID, UserID, Provider, AuthenticationTime, LogonExpires, AuthenticationState, UserAgent) VALUES ('$safeSession', '$safeUser', '$safeProvider', $nowUnix, $expiresUnix, '$safeState', '$safeUA');"

    try {
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $insertQuery
    } catch {
        Write-Error "Invoke-TestToken: Failed to write LoginSessions row: $_"
        return $null
    }

    # Return the new/updated row
    $selectQuery = "SELECT * FROM LoginSessions WHERE SessionID = '$safeSession' LIMIT 1;"
    return Get-PSWebSQLiteData -File $dbFile -Query $selectQuery
}

# Retrieve user record and roles
function Get-PSWebUser {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [switch]$ListAll
    )

    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"

    if ($ListAll) {
        $q = "SELECT * FROM Users;"
        return Get-PSWebSQLiteData -File $dbFile -Query $q
    }

    if ($UserID) {
        $safe = Sanitize-SqlQueryString -String $UserID
        $q = "SELECT * FROM Users WHERE UserID = '$safe' LIMIT 1;"
    } elseif ($Email) {
        $safe = Sanitize-SqlQueryString -String $Email
        $q = "SELECT * FROM Users WHERE Email = '$safe' LIMIT 1;"
    } else {
        # Do not throw an error here; callers may call with empty values. Return $null to indicate not found.
        Write-Verbose "Get-PSWebUser called without -UserID or -Email; returning null."
        return $null
    }

    $row = Get-PSWebSQLiteData -File $dbFile -Query $q
    if (-not $row) { return $null }
    $user = if ($row -is [System.Array]) { $row[0] } else { $row }

    # Fetch roles for this user
    if ($user.UserID) {
        $safeUser = Sanitize-SqlQueryString -String $user.UserID
        $rq = "SELECT RoleName FROM PSWeb_Roles WHERE PrincipalID = '$safeUser' AND PrincipalType = 'user';"
        $roles = Get-PSWebSQLiteData -File $dbFile -Query $rq
        if ($roles) {
            $user | Add-Member -NotePropertyName Roles -NotePropertyValue (($roles | ForEach-Object { $_.RoleName }) ) -Force
        } else {
            $user | Add-Member -NotePropertyName Roles -NotePropertyValue @() -Force
        }
    }

    return $user
}

# Update user fields and optionally set roles
function Set-PSWebUser {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string[]]$Roles
    )
    if (-not $UserID) { Write-Error "Set-PSWebUser requires -UserID."; return $null }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safeUser = Sanitize-SqlQueryString -String $UserID

    if ($Email) {
        $safeEmail = Sanitize-SqlQueryString -String $Email
        $uq = "UPDATE Users SET Email = '$safeEmail' WHERE UserID = '$safeUser';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $uq
    }

    if ($Roles) {
        # Remove existing roles for user
        $del = "DELETE FROM PSWeb_Roles WHERE PrincipalID = '$safeUser' AND PrincipalType = 'user';"
        Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $del
        foreach ($r in $Roles) {
            $safeR = Sanitize-SqlQueryString -String $r
            $ins = "INSERT OR REPLACE INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safeUser', 'user', '$safeR');"
            Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $ins
        }
    }

    return Get-PSWebUser -UserID $UserID
}

# Create or update a role for a principal
function Set-PSWebHostRole {
    [cmdletbinding()]
    param(
        [string]$PrincipalID,
        [string]$RoleName,
        [string]$PrincipalType = 'user'
    )
    if (-not $PrincipalID -or -not $RoleName) { Write-Error "Set-PSWebHostRole requires -PrincipalID and -RoleName."; return $null }
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $safePrincipal = Sanitize-SqlQueryString -String $PrincipalID
    $safeRole = Sanitize-SqlQueryString -String $RoleName
    $safeType = Sanitize-SqlQueryString -String $PrincipalType

    $q = "INSERT OR REPLACE INTO PSWeb_Roles (PrincipalID, PrincipalType, RoleName) VALUES ('$safePrincipal', '$safeType', '$safeRole');"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $q
    return @{ PrincipalID = $PrincipalID; PrincipalType = $PrincipalType; RoleName = $RoleName }
}