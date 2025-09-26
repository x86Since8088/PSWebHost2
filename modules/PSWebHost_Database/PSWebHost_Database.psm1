function New-PSWebSQLiteTable {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$File,

        [Parameter(Mandatory=$true)]
        [string]$Table,

        [Parameter(Mandatory=$true)]
        [object[]]$Columns
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    if (-not (Test-Path $baseDirectory)) {
        New-Item -Path $baseDirectory -ItemType Directory -Force | Out-Null
    }
    if (Test-Path $File) {
        Write-Verbose "Using file: $File"
        $dbFile = $File
    }
    else {
        $dbFile = Join-Path $baseDirectory $File
    }

    $columnDefinitions = @()
    if ($Columns[0] -is [string]) {
        foreach ($col in $Columns) {
            $columnDefinitions += "`"$col`" TEXT"
        }
    } elseif ($Columns[0] -is [hashtable]) {
        foreach ($key in $Columns[0].Keys) {
            $columnDefinitions += "`"$key`" TEXT"
        }
    } else {
        throw "Columns parameter must be a string array or a hashtable array."
    }

    $query = "CREATE TABLE IF NOT EXISTS `"$Table`" (ID INTEGER PRIMARY KEY AUTOINCREMENT, $($columnDefinitions -join ', '));"
    
    sqlite3 $dbFile $query

    if ($Columns[0] -is [hashtable]) {
        foreach ($row in $Columns) {
            $keys = $row.Keys | ForEach-Object { "`"$_`"" }
            $values = $row.Values | ForEach-Object { "'$_'" }
            $insertQuery = "INSERT INTO `"$Table`" ($($keys -join ', ')) VALUES ($($values -join ', '));"
            sqlite3 $dbFile $insertQuery
        }
    }
}

function New-PSWebSQLiteData {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$File,

        [Parameter(Mandatory=$true)]
        [string]$Table,

        [Parameter(Mandatory=$true)]
        [hashtable]$Data
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    if (Test-Path $File) {
        Write-Verbose "Using file: $File"
        $dbFile = $File
    }
    else {
        $dbFile = Join-Path $baseDirectory $File
    }

    $keys = $Data.Keys | ForEach-Object { "`"$_`"" }
    $values = $Data.Values | ForEach-Object { "'$_'" }
    
    $query = "INSERT INTO `"$Table`" ($($keys -join ', ')) VALUES ($($values -join ', '));"
    
    sqlite3 $dbFile $query
}

function New-PSWebSQLiteDataByID {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$File,

        [Parameter(Mandatory=$true)]
        [string]$Table,

        [Parameter(Mandatory=$true)]
        $ID,

        [Parameter(Mandatory=$true)]
        [hashtable]$Columns
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    if (Test-Path $File) {
        Write-Verbose "Using file: $File"
        $dbFile = $File
    }
    else {
        $dbFile = Join-Path $baseDirectory $File
    }

    $setClauses = @()
    foreach ($key in $Columns.Keys) {
        $setClauses += "`"$key`" = ' $($Columns[$key])'"
    }

    $query = "UPDATE `"$Table`" SET $($setClauses -join ', ') WHERE ID = '$ID';"
    
    sqlite3 $dbFile $query
}

function Get-PSWebSQLiteData {
    [cmdletbinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter(Mandatory=$true)]
        [string]$File,

        [Parameter(Mandatory=$true)]
        [string]$Query
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    if (Test-Path $File) {
        Write-Verbose "Using file: $File"
        $dbFile = $File
    }
    else {
        $dbFile = Join-Path $baseDirectory $File
    }

    if (-not (Test-Path $dbFile)) {
        Write-Error "Database file not found at $dbFile"
        return
    }

    # Execute the query and get the result as CSV
    $csvResult = sqlite3 $dbFile -header -csv $Query
    
    # Convert the CSV result to a PowerShell object
    return $csvResult | ConvertFrom-Csv
}

function Invoke-PSWebSQLiteNonQuery {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$File,
        [Parameter(ParameterSetName='Verb',Mandatory=$true)]
        [ValidateSet('INSERT', 'INSERT OR REPLACE', 'UPDATE', 'DELETE')]
        [string]$Verb,
        [Parameter(ParameterSetName='Verb',Mandatory=$true)]
        [string]$TableName,
        [Parameter(ParameterSetName='Verb',Mandatory=$false)]
        [hashtable]$Data,
        [Parameter(ParameterSetName='Verb',Mandatory=$false)]
        [string]$Where,
        [Parameter(ParameterSetName='Query', Mandatory=$false)]
        [string]$query
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    if (($File -split '[\\/]').count -gt 2 -and (Test-Path $File)) {
        Write-Verbose "Using file: $File"
        $dbFile = $File
    }
    else {
        $dbFile = Join-Path $baseDirectory $File
    }
    if (-not (Test-Path $dbFile)) {
        Write-Error "Database file not found at $dbFile"
        return
    }

    # Helper function to format values based on type
    function Format-SQLiteValue {
        param($value)
        if ($null -eq $value) { return "NULL" }
        if ($value -is [string] -and $value.StartsWith("X'")) {
            return $value # Hex literal for BLOB
        } elseif ($value -is [string]) {
            return "'$($value -replace "'", "''")'" # Quote and escape string
        } elseif ($value -is [boolean]) {
            return if ($value) { 1 } else { 0 } # Convert boolean to integer
        } else {
            return $value # Number or other literal
        }
    }

    if ($query) {
        $CallstaskItem = Get-PSCallStack|Select-Object -Skip 1 -First 1
        Write-Warning -Message "Direct -Query was used:`n`tCommand: $($CallstaskItem.Command)`n`tLocation: $($CallstaskItem.Location)`n`tLineNumber: $($CallstaskItem.ScriptLineNumber)`n`tFunctionName: $($CallstaskItem.FunctionName)`n`tPosition: $($CallstaskItem.Position)`n`tQuery: $($query -replace '`(e\[d+[a-z])','!ANSI ESCAPE SEQUENCE REMOVED($1)!')"
    }
    else {
        $query = ""
        switch ($Verb) {
            'INSERT' {
                if (-not $Data) { Write-Error "-Data parameter is required for INSERT."; return }
                $columns = ($Data.Keys | ForEach-Object { "`"$_`"" }) -join ', '
                $values = ($Data.Values | ForEach-Object { Format-SQLiteValue -value $_ }) -join ', '
                $query = "INSERT INTO `"$TableName`" ($columns) VALUES ($values);"
                break
            }
            'INSERT OR REPLACE' {
                if (-not $Data) { Write-Error "-Data parameter is required for INSERT OR REPLACE."; return }
                $columns = ($Data.Keys | ForEach-Object { "`"$_`"" }) -join ', '
                $values = ($Data.Values | ForEach-Object { Format-SQLiteValue -value $_ }) -join ', '
                $query = "INSERT OR REPLACE INTO `"$TableName`" ($columns) VALUES ($values);"
                break
            }
            'UPDATE' {
                if (-not $Data) { Write-Error "-Data parameter is required for UPDATE."; return }
                if (-not $Where) { Write-Error "-Where parameter is required for UPDATE."; return }
                $setClauses = @()
                foreach ($key in $Data.Keys) {
                    $formattedValue = Format-SQLiteValue -value $Data[$key]
                    $setClauses += "`"$key`" = $formattedValue"
                }
                $query = "UPDATE `"$TableName`" SET $($setClauses -join ', ') WHERE $Where;"
                break
            }
            'DELETE' {
                if (-not $Where) { Write-Error "-Where parameter is required for DELETE."; return }
                $query = "DELETE FROM `"$TableName`" WHERE $Where;"
                break
            }
        }
    }

    if ([string]::IsNullOrEmpty($query)) {
        Write-Error "Could not construct a valid query from the provided parameters."
        return
    }
    if ($query -match '`(e\[d+[a-z])') {
        $CallstaskItem = Get-PSCallStack|Select-Object -Skip 1 -First 1
        $message = "ANSI escape characters in query.`n`t$($query -split '`(e\[d+[a-z])')" +
            "`n`tCommand: $($CallstaskItem.Command)`n`tLocation: $($CallstaskItem.Location)`n`tLineNumber: $($CallstaskItem.ScriptLineNumber)`n`tFunctionName: $($CallstaskItem.FunctionName)`n`tPosition: $($CallstaskItem.Position)`n`tQuery: $($query -replace '`(e\[d+[a-z])','!ANSI ESCAPE SEQUENCE REMOVED($1)!')"
        Write-Warning -Message $message
        Write-PSWebHostLog -message $message -level Warning -Severity Critical -Category 'Suspicious ANSI Escape Sequences'
        return 'aborted'
    }
    sqlite3 $dbFile $query
}

function Set-CardSession {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$SessionID,
        [Parameter(Mandatory=$true)] [string]$UserID,
        [Parameter(Mandatory=$true)] [string]$CardGUID,
        [Parameter(Mandatory=$true)] [string]$DataBackend,
        [Parameter(Mandatory=$true)] [string]$CardDefinition # Gzipped, Base64 encoded JSON
    )

    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    
    # Use INSERT OR REPLACE to handle both new and existing cards based on CardGUID
    $query = "INSERT OR REPLACE INTO CardSessions (CardGUID, SessionID, UserID, DataBackend, CardDefinition) VALUES ('$CardGUID', '$SessionID', '$UserID', '$DataBackend', '$CardDefinition');"

    sqlite3 $dbFile $query
}

#region Auth Functions
function Set-UserProvider {
    [cmdletbinding()]
    param(
        [string]$UserID, [string]$UserName, [string]$provider, 
        [bool]$locked_out, [string]$expires, [bool]$enabled, [string]$data
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "INSERT OR REPLACE INTO auth_user_provider (UserID, UserName, provider, created, locked_out, expires, enabled, data) VALUES ('$UserID', '$UserName', '$provider', '$(Get-Date -UFormat %s)', '$locked_out', '$expires', '$enabled', '$data');"
    sqlite3 $dbFile $query
}

function Get-UserProvider {
    [cmdletbinding()]
    param([string]$UserName, [string]$provider)
    $query = "SELECT * FROM auth_user_provider WHERE UserName = '$UserName' AND provider = '$provider';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Set-LastLoginAttempt {
    [cmdletbinding()]
    param([string]$Username, [string]$IPAddress, [string]$Time, [string]$UserNameLockedUntil, [string]$IPAddressLockedUntil, [int]$UserViolationsCount, [int]$IPViolationCount)
    
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    # Use IPAddress as the key for replacement
    $query = "INSERT OR REPLACE INTO LastLoginAttempt (IPAddress, Username, Time, UserNameLockedUntil, IPAddressLockedUntil, UserViolationsCount, IPViolationCount) VALUES ('$IPAddress', '$Username', '$Time', '$UserNameLockedUntil', '$IPAddressLockedUntil', $UserViolationsCount, $IPViolationCount);"
    sqlite3 $dbFile $query
}

function Get-LastLoginAttempt {
    [cmdletbinding()]
    param([string]$IPAddress)
    $query = "SELECT * FROM LastLoginAttempt WHERE IPAddress = '$IPAddress';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Get-PSWebGroup {
    [cmdletbinding()]
    param([string]$Name)
    $query = "SELECT * FROM User_Groups WHERE Name = '$Name';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Get-PSWebGroups {
    [cmdletbinding()]
    param()
    $dbFile = "pswebhost.db"
    $query = "SELECT Name FROM User_Groups;"
    $groups = Get-PSWebSQLiteData -File $dbFile -Query $query
    if ($groups) {
        return $groups.Name
    } else {
        return @()
    }
}

function Add-UserToGroup {
    [cmdletbinding()]
    param([string]$UserID, [string]$GroupID)
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "INSERT OR IGNORE INTO User_Groups_Map (UserID, GroupID) VALUES ('$UserID','$GroupID');"
    sqlite3 $dbFile $query
}

function Remove-UserFromGroup {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$GroupID
    )
    $dbFile = "pswebhost.db"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Verb 'DELETE' -TableName 'User_Groups_Map' -Where "UserID = '$UserID' AND GroupID = '$GroupID'"
}

function Add-PSWebRoleAssignment {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrincipalID,
        [Parameter(Mandatory=$true)]
        [ValidateSet('user', 'group')] 
        [string]$PrincipalType,
        [Parameter(Mandatory=$true)]
        [string]$RoleName
    )
    $data = @{
        PrincipalID = $PrincipalID
        PrincipalType = $PrincipalType
        RoleName = $RoleName
    }
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'INSERT OR REPLACE' -TableName 'PSWeb_Roles' -Data $data
}

function Set-PSWebRoleAssignment {
    [cmdletbinding()]
    [Alias('Update-PSWebRoleAssignment')]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrincipalID,
        [Parameter(Mandatory=$true)]
        [ValidateSet('user', 'group')] 
        [string]$PrincipalType,
        [Parameter(Mandatory=$true)]
        [string]$RoleName
    )
    Add-PSWebRoleAssignment -PrincipalID $PrincipalID -PrincipalType $PrincipalType -RoleName $RoleName
}

function Remove-PSWebRoleAssignment {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$PrincipalID,
        [Parameter(Mandatory=$true)]
        [string]$RoleName
    )
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'DELETE' -TableName 'PSWeb_Roles' -Where "PrincipalID = '$PrincipalID' AND RoleName = '$RoleName'"
}

function Get-PSWebRoleAssignment {
    [cmdletbinding()]
    param(
        [string]$PrincipalID,
        [string]$RoleName
    )
    $whereClauses = @()
    if ($PrincipalID) { $whereClauses += "PrincipalID = '$PrincipalID'" }
    if ($RoleName) { $whereClauses += "RoleName = '$RoleName'" }
    
    $query = "SELECT * FROM PSWeb_Roles"
    if ($whereClauses) {
        $query += " WHERE $($whereClauses -join ' AND ')"
    }
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Get-PSWebRoles {
    [cmdletbinding()]
    param()
    $dbFile = "pswebhost.db"
    $query = "SELECT DISTINCT RoleName FROM PSWeb_Roles;"
    $roles = Get-PSWebSQLiteData -File $dbFile -Query $query
    if ($roles) {
        return $roles.RoleName
    } else {
        return @()
    }
}

#endregion

function Initialize-PSWebHostDatabase {
    [cmdletbinding()]
    param()

    Write-Verbose "Initializing PsWebHost database..." -Verbose
    $dbFile = "pswebhost.db"

    # Define table structures
    $usersColumns = "ID TEXT PRIMARY KEY", "UserID TEXT UNIQUE NOT NULL", "UserName TEXT UNIQUE NOT NULL", "Email TEXT UNIQUE", "Phone TEXT", "Salt TEXT"
    $userDataColumns = "ID TEXT", "Name TEXT", "Data BLOB", "PRIMARY KEY (ID, Name)"
    $cardSessionColumns = "CardGUID TEXT PRIMARY KEY", "SessionID TEXT", "UserID TEXT", "DataBackend TEXT", "CardDefinition TEXT"
    $authUserProviderColumns = "UserID TEXT", "UserName TEXT", "provider TEXT", "created TEXT", "locked_out INTEGER", "expires TEXT", "enabled INTEGER", "data TEXT", "PRIMARY KEY (UserID, provider)"
    $lastLoginAttemptColumns = "IPAddress TEXT PRIMARY KEY", "Username TEXT", "Time TEXT", "UserNameLockedUntil TEXT", "IPAddressLockedUntil TEXT", "UserViolationsCount INTEGER", "IPViolationCount INTEGER"
    $userGroupsColumns = "GroupID TEXT PRIMARY KEY", "Name TEXT UNIQUE", "Updated TEXT", "Created TEXT"
    $userGroupsMapColumns = "UserID TEXT", "GroupID TEXT", "PRIMARY KEY (UserID, GroupID)"
    $rolesColumns = "PrincipalID TEXT", "PrincipalType TEXT", "RoleName TEXT", "PRIMARY KEY (PrincipalID, RoleName)"
    $loginSessionsColumns = "SessionID TEXT PRIMARY KEY", "UserID TEXT", "AuthenticationTime TEXT", "Provider TEXT", "LogonExpires TEXT"
    $accountEmailConfirmationColumns = "email_request_guid TEXT PRIMARY KEY", "email TEXT", "request_date TEXT", "response_date TEXT", "request_ip TEXT", "response_ip TEXT", "request_session_id TEXT", "response_session_id TEXT"
    $cardSettingsColumns = "endpoint_guid TEXT", "user_id TEXT", "created_date TEXT", "last_updated TEXT", "data TEXT", "PRIMARY KEY (endpoint_guid, user_id)"

    # Build queries
    $queries = @(
        "CREATE TABLE IF NOT EXISTS Users ($($usersColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS User_Data ($($userDataColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS CardSessions ($($cardSessionColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS auth_user_provider ($($authUserProviderColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS LastLoginAttempt ($($lastLoginAttemptColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS User_Groups ($($userGroupsColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS User_Groups_Map ($($userGroupsMapColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS PSWeb_Roles ($($rolesColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS LoginSessions ($($loginSessionsColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS account_email_confirmation ($($accountEmailConfirmationColumns -join ', '));"
        "CREATE TABLE IF NOT EXISTS card_settings ($($cardSettingsColumns -join ', '));"
    )

    # Get DB path
    $dbFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\$dbFile"
    if (-not (Test-Path (Split-Path $dbFilePath))) {
        New-Item -Path (Split-Path $dbFilePath) -ItemType Directory -Force | Out-Null
    }

    # Execute queries
    foreach ($query in $queries) {
        sqlite3 $dbFilePath $query
    }

    Write-Verbose "Database initialization complete." -Verbose
}

function Set-LoginSession {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$SessionID,
        [Parameter(Mandatory=$true)] [string]$UserID,
        [Parameter(Mandatory=$true)] [string]$Provider,
        [Parameter(Mandatory=$true)] [datetime]$AuthenticationTime,
        [Parameter(Mandatory=$true)] [datetime]$LogonExpires,
        [Parameter(Mandatory=$false)] [string]$UserAgent
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "INSERT OR REPLACE INTO LoginSessions (SessionID, UserID, AuthenticationTime, Provider, LogonExpires, UserAgent) VALUES ('$SessionID', '$UserID', '$(Get-Date $AuthenticationTime -UFormat %s)', '$Provider', '$(Get-Date $LogonExpires -UFormat %s)', '$UserAgent');"
    sqlite3 $dbFile $query
}

function Get-LoginSession {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$SessionID
    )
    $query = "SELECT * FROM LoginSessions WHERE SessionID = '$SessionID';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Set-UserData {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$ID,
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [byte[]]$Data
    )
    $hexData = "X'" + ($Data | ForEach-Object { $_.ToString('X2') }) -join '' + "'"
    $dataToSet = @{
        ID = $ID
        Name = $Name
        Data = $hexData
    }
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'INSERT OR REPLACE' -TableName 'User_Data' -Data $dataToSet
    Write-Host "`t[Set-UserData] Invoke-PSWebSQLiteNonQuery -File 'pswebhost.db' -Verb 'INSERT OR REPLACE' -TableName 'User_Data' `n`t`t-Data $dataToSet"
}

function Get-UserData {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$ID,
        [Parameter(Mandatory=$true)] [string]$Name
    )
    $query = "SELECT Data FROM User_Data WHERE ID = '$ID' AND Name LIKE '$Name';"
    $result = Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
    Write-Host "`t[Get-userData]Get-PSWebSQLiteData -File "pswebhost.db" -Query $query"`n`t`tFound: $(($result|Inspect-Object|ConvertTo-Json -Depth 5) -split '
' -join "`n`t`t")]
    if ($result) {
        return $result
    } else {
        return $null
    }
}

function Get-CardSettings {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$EndpointGuid,

        [Parameter(Mandatory=$true)]
        [string]$UserId
    )

    $query = "SELECT data FROM card_settings WHERE endpoint_guid = '$EndpointGuid' AND user_id = '$UserId';"
    $settings = Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
    Write-Host "`t[Get-CardSettings] Get-PSWebSQLiteData -File 'pswebhost.db' -Query '$query'`n`t`tFound: $(($settings|Inspect-Object|ConvertTo-Json -Depth 5) -split '
' -join "`n`t`t")]"
    if ($settings) {
        return $settings.data
    } else {
        return $null
    }
}

function Set-CardSettings {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$EndpointGuid,

        [Parameter(Mandatory=$true)]
        [string]$UserId,

        [Parameter(Mandatory=$true)]
        [string]$Data # Compressed JSON
    )

    $date = (Get-Date).ToString("s")
    # TODO: This query uses a sub-select and is too complex for the basic Invoke-PSWebSQLiteNonQuery builder.
    # It should be refactored or the builder function enhanced if this pattern is common.
    $query = "INSERT OR REPLACE INTO card_settings (endpoint_guid, user_id, created_date, last_updated, data) VALUES ('$EndpointGuid', '$UserId', COALESCE((SELECT created_date FROM card_settings WHERE endpoint_guid = '$EndpointGuid' AND user_id = '$UserId'), '$date'), '$date', '$Data');"
    Write-Host "`t[Set-CardSettings] Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query '$query'"
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query $query
}

#region Provider Data Functions

function ConvertFrom-CompressedBase64 {
    param (
        [string]$InputString
    )
    try {
        $compressedBytes = [System.Convert]::FromBase64String($InputString)
        $memStream = New-Object System.IO.MemoryStream
        $memStream.Write($compressedBytes, 0, $compressedBytes.Length)
        $memStream.Position = 0
        $gzipStream = New-Object System.IO.Compression.GZipStream($memStream, [System.IO.Compression.CompressionMode]::Decompress)
        $streamReader = New-Object System.IO.StreamReader($gzipStream)
        $uncompressedString = $streamReader.ReadToEnd()
        $gzipStream.Close()
        $memStream.Close()
        return $uncompressedString
    } catch {
        Write-Error "Failed to decompress or decode Base64 string. Error: $($_.Exception.Message)"
        return $null
    }
}

function Get-PSWebUserIDFromDb {
    param(
        [string]$UserID,
        [string]$Email
    )
    $dbFile = "pswebhost.db"
    if ($UserID) {
        $query = "SELECT ID FROM Users WHERE UserID = '$UserID';"
    } elseif ($Email) {
        $query = "SELECT ID FROM Users WHERE Email = '$Email';"
    } else {
        return $null
    }
    $data = Get-PSWebSQLiteData -File $dbFile -Query $query
    Write-Host "`t[Get-PSWebUserIDFromDb] Get-PSWebSQLiteData -File '$dbFile' -Query '$query'`n`t`tFound: $($data)]"
    return (Get-PSWebSQLiteData -File $dbFile -Query $query).ID
}

function Get-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider = '*'
    )

    $id = Get-PSWebUserIDFromDb -UserID $UserID -Email $Email
    if (-not $id) { return $null }

    $providerName = if ($Provider -eq '*') { '%' } else { $Provider }
    $nameQuery = "Auth_${providerName}_Registration"

    $userData = Get-UserData -ID $id -Name $nameQuery
    if (-not $userData) { return $null }

    $results = @()
    foreach($data in $userData) {
        $decompressedJson = ConvertFrom-CompressedBase64 -InputString $data.Data
        $psObject = $decompressedJson | ConvertFrom-Json
        $results += $psObject
    }
    return $results
}

function Set-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider,
        [hashtable]$Data
    )

    $id = Get-PSWebUserIDFromDb -UserID $UserID -Email $Email
    if (-not $id) { Write-Error "User not found."; return }

    $name = "Auth_${Provider}_Registration"
    $json = $Data | ConvertTo-Json -Compress
    $compressedData = ConvertTo-CompressedBase64 -InputString $json

    Set-UserData -ID $id -Name $name -Data $compressedData
    Write-Host "`t[Set-PSWebAuthProvider] Set-UserData -ID $id -Name $name -Data $compressedData"
}

function Add-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider,
        [hashtable]$Data
    )

    $existing = Get-PSWebAuthProvider -UserID $UserID -Email $Email -Provider $Provider
    if ($existing) {
        Write-Error "Provider '$Provider' already exists for this user."
        return
    }
    Write-Host "`t[Add-PSWebAuthProvider] Set-PSWebAuthProvider -UserID $UserID -Email $Email -Provider $Provider -Data $Data"
    Set-PSWebAuthProvider -UserID $UserID -Email $Email -Provider $Provider -Data $Data
}

function Remove-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider
    )
    $id = Get-PSWebUserIDFromDb -UserID $UserID -Email $Email
    if (-not $id) { Write-Error "User not found."; return }

    $name = "Auth_${Provider}_Registration"
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Verb 'DELETE' -TableName 'User_Data' -Where "ID = '$id' AND Name = '$name'"
}

#endregion

function Invoke-TestToken {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$false)]
        [string]$State,

        [Parameter(Mandatory=$false)]
        [string]$SessionID = '%',

        [Parameter(Mandatory=$false)]
        [string]$UserID = '%',

        [Parameter(Mandatory=$false)]
        [string]$Provider = '%',

        [Parameter(Mandatory=$false)]
        [string]$AuthenticationState,

        [Parameter(Mandatory=$false)]
        [switch]$Completed,

        [Parameter(Mandatory=$false)]
        [string]$UserAgent
    )

    if ($null -eq $global:PSWebServer) {
        $ProjectRoot = $PSScriptRoot -replace '[\/]system[\/].*'
        . "$ProjectRoot\system\init.ps1"
    }

    $DatabaseFile = "pswebhost.db"

    # Cleanup expired and incomplete sessions first
    $cleanupTime = (Get-Date).AddMinutes(-5).ToUniversalTime()
    $cleanupTimeUnix = [int64]((Get-Date $cleanupTime) - (Get-Date "1970-01-01 00:00:00Z")).TotalSeconds
    Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Verb 'DELETE' -TableName 'LoginSessions' -Where "AuthenticationTime < $cleanupTimeUnix AND (AuthenticationState IS NOT 'completed' OR AuthenticationState IS NULL)"

    # Handle state updates
    if ($PSBoundParameters.ContainsKey('AuthenticationState') -or $Completed) {
        if ($SessionID -eq '%') {
            Write-Error "A specific SessionID must be provided to update AuthenticationState."
            return
        }
        $newState = if ($Completed) { 'completed' } else { $AuthenticationState }
        Write-Verbose "[TestToken.ps1] Attempting to upsert state to '$newState' for SessionID $SessionID."

        # Get existing session data to preserve fields that aren't being updated
        $existingSession = Get-LoginSession -SessionID $SessionID

        $finalUserID = if ($UserID -ne '%') { $UserID } else { $existingSession.UserID }
        if (-not $finalUserID) { $finalUserID = 'pending' } # Default for new records

        $finalProvider = if ($Provider -ne '%') { $Provider } else { $existingSession.Provider }
        if (-not $finalProvider) { $finalProvider = 'PsWebHost' } # Default for new records

        $finalUserAgent = if ($UserAgent) { $UserAgent } else { $existingSession.UserAgent }

        $authTime = [int64]((Get-Date) - (Get-Date "1970-01-01 00:00:00Z")).TotalSeconds
        $expiresTime = if ($Completed) { (Get-Date).AddDays(7) } else { (Get-Date).AddMinutes(10) }
        $expiresUnix = [int64]($expiresTime - (Get-Date "1970-01-01 00:00:00Z")).TotalSeconds

        $upsertData = @{
            SessionID = $SessionID
            UserID = $finalUserID
            Provider = $finalProvider
            AuthenticationState = $newState
            AuthenticationTime = $authTime
            LogonExpires = $expiresUnix
            UserAgent = $finalUserAgent
        }
        
        Write-Verbose "[TestToken.ps1] Executing upsert..."
        Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Verb 'INSERT OR REPLACE' -TableName 'LoginSessions' -Data $upsertData
        return
    }

    # Handle state validation
    Write-Verbose "[TestToken.ps1] Attempting to validate state '$State' for SessionID $SessionID."
    $query = "SELECT * FROM LoginSessions WHERE SessionID LIKE '$SessionID' AND UserID LIKE '$UserID' AND Provider LIKE '$Provider' ORDER BY AuthenticationTime DESC;"
    $results = Get-PSWebSQLiteData -File $DatabaseFile -Query $query
    Write-Verbose "[TestToken.ps1] Found $($results.Count) matching sessions."

    if ($null -ne $State) {
        foreach ($result in $results) {
            if ($result.AuthenticationState -eq $State) {
                Write-Verbose "[TestToken.ps1] Match found! AuthenticationState is '$($result.AuthenticationState)'. Clearing state and returning object."
                # State matches, clear it to prevent reuse, and return the session object
                Invoke-PSWebSQLiteNonQuery -File $DatabaseFile -Verb 'UPDATE' -TableName 'LoginSessions' -Data @{ AuthenticationState = $null } -Where "SessionID = '$($result.SessionID)'"
                return $result
            }
        }
        # If no session matched the state
        Write-Verbose "[TestToken.ps1] No session found with matching state."
        return $null
    }

    # If no state is provided for validation, just return the query results
    return $results
}

function Get-PSWebUser {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$UserID
    )

    $user = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT * FROM Users WHERE UserID = '$UserID';"
    if (-not $user) { return $null }

    # Get direct roles
    $directRoles = (Get-PSWebRoleAssignment -PrincipalID $user.ID -PrincipalType 'user').RoleName

    # Get group roles
    $groupRoles = @()
    $userGroups = Get-PSWebSQLiteData -File "pswebhost.db" -Query "SELECT GroupID FROM User_Groups_Map WHERE UserID = '$($user.ID)';"
    if ($userGroups) {
        foreach ($group in $userGroups) {
            $groupRoles += (Get-PSWebRoleAssignment -PrincipalID $group.GroupID -PrincipalType 'group').RoleName
        }
    }

    $user.Roles = ($directRoles + $groupRoles) | Select-Object -Unique
    return $user
}