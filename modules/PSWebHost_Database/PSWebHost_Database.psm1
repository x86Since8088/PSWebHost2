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
    $dbFile = Join-Path $baseDirectory $File

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
    $dbFile = Join-Path $baseDirectory $File

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
    $dbFile = Join-Path $baseDirectory $File

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

        [Parameter(Mandatory=$true)]
        [string]$Query
    )

    $baseDirectory = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    $dbFile = Join-Path $baseDirectory $File

    if (-not (Test-Path $dbFile)) {
        Write-Error "Database file not found at $dbFile"
        return
    }

    sqlite3 $dbFile $Query
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
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
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
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "SELECT * FROM LastLoginAttempt WHERE IPAddress = '$IPAddress';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Get-PSWebGroup {
    [cmdletbinding()]
    param([string]$Name)
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
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

function Set-RoleForPrincipal {
    [cmdletbinding()]
    param([string]$PrincipalID, [string]$RoleName) # Principal can be a UserID or GroupID
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "INSERT OR IGNORE INTO PSWeb_Roles (PrincipalID, RoleName) VALUES ('$PrincipalID','$RoleName');"
    sqlite3 $dbFile $query
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
    $usersColumns = "UserID TEXT PRIMARY KEY", "UserName TEXT UNIQUE NOT NULL", "Email TEXT UNIQUE", "Phone TEXT", "Salt TEXT"
    $userDataColumns = "GUID TEXT", "Name TEXT", "Data BLOB", "PRIMARY KEY (GUID, Name)"
    $cardSessionColumns = "CardGUID TEXT PRIMARY KEY", "SessionID TEXT", "UserID TEXT", "DataBackend TEXT", "CardDefinition TEXT"
    $authUserProviderColumns = "UserID TEXT", "UserName TEXT", "provider TEXT", "created TEXT", "locked_out INTEGER", "expires TEXT", "enabled INTEGER", "data TEXT", "PRIMARY KEY (UserID, provider)"
    $lastLoginAttemptColumns = "IPAddress TEXT PRIMARY KEY", "Username TEXT", "Time TEXT", "UserNameLockedUntil TEXT", "IPAddressLockedUntil TEXT", "UserViolationsCount INTEGER", "IPViolationCount INTEGER"
    $userGroupsColumns = "GroupID TEXT PRIMARY KEY", "Name TEXT UNIQUE", "Updated TEXT", "Created TEXT"
    $userGroupsMapColumns = "UserID TEXT", "GroupID TEXT", "PRIMARY KEY (UserID, GroupID)"
    $rolesColumns = "PrincipalID TEXT", "RoleName TEXT", "PRIMARY KEY (PrincipalID, RoleName)" # PrincipalID can be a UserID or GroupID
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
        [Parameter(Mandatory=$true)] [datetime]$LogonExpires
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "INSERT OR REPLACE INTO LoginSessions (SessionID, UserID, AuthenticationTime, Provider, LogonExpires) VALUES ('$SessionID', '$UserID', '$(Get-Date $AuthenticationTime -UFormat %s)', '$Provider', '$(Get-Date $LogonExpires -UFormat %s)');"
    sqlite3 $dbFile $query
}

function Get-LoginSession {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$SessionID
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "SELECT * FROM LoginSessions WHERE SessionID = '$SessionID';"
    Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
}

function Set-UserData {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$GUID,
        [Parameter(Mandatory=$true)] [string]$Name,
        [Parameter(Mandatory=$true)] [byte[]]$Data
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $hexData = "X'" + ($Data | ForEach-Object { $_.ToString('X2') }) -join '' + "'"
    $query = "INSERT OR REPLACE INTO User_Data (GUID, Name, Data) VALUES ('$GUID', '$Name', $hexData);"
    Invoke-PSWebSQLiteNonQuery -File "pswebhost.db" -Query $query
}

function Get-UserData {
    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$true)] [string]$GUID,
        [Parameter(Mandatory=$true)] [string]$Name
    )
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\pswebhost.db"
    $query = "SELECT Data FROM User_Data WHERE GUID = '$GUID' AND Name = '$Name';"
    $result = Get-PSWebSQLiteData -File "pswebhost.db" -Query $query
    if ($result) {
        return $result.Data
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
    # Use INSERT OR REPLACE to handle both new and existing settings
    $query = "INSERT OR REPLACE INTO card_settings (endpoint_guid, user_id, created_date, last_updated, data) VALUES ('$EndpointGuid', '$UserId', COALESCE((SELECT created_date FROM card_settings WHERE endpoint_guid = '$EndpointGuid' AND user_id = '$UserId'), '$date'), '$date', '$Data');"
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

function Get-PSWebUserGuid {
    param(
        [string]$UserID,
        [string]$Email
    )
    $dbFile = "pswebhost.db"
    if ($UserID) {
        $query = "SELECT GUID FROM Users WHERE UserID = '$UserID';"
    } elseif ($Email) {
        $query = "SELECT GUID FROM Users WHERE Email = '$Email';"
    } else {
        return $null
    }
    return (Get-PSWebSQLiteData -File $dbFile -Query $query).GUID
}

function Get-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider = '*'
    )

    $guid = Get-PSWebUserGuid -UserID $UserID -Email $Email
    if (-not $guid) { return $null }

    $providerName = if ($Provider -eq '*') { '%' } else { $Provider }
    $nameQuery = "Auth_${providerName}_Registration"

    $userData = Get-UserData -GUID $guid -Name $nameQuery
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

    $guid = Get-PSWebUserGuid -UserID $UserID -Email $Email
    if (-not $guid) { Write-Error "User not found."; return }

    $name = "Auth_${Provider}_Registration"
    $json = $Data | ConvertTo-Json -Compress
    $compressedData = ConvertTo-CompressedBase64 -InputString $json

    Set-UserData -GUID $guid -Name $name -Data $compressedData
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
    Set-PSWebAuthProvider -UserID $UserID -Email $Email -Provider $Provider -Data $Data
}

function Remove-PSWebAuthProvider {
    [cmdletbinding()]
    param(
        [string]$UserID,
        [string]$Email,
        [string]$Provider
    )
    $guid = Get-PSWebUserGuid -UserID $UserID -Email $Email
    if (-not $guid) { Write-Error "User not found."; return }

    $name = "Auth_${Provider}_Registration"
    $dbFile = "pswebhost.db"
    $query = "DELETE FROM User_Data WHERE GUID = '$guid' AND Name = '$name';"
    Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
}

#endregion

