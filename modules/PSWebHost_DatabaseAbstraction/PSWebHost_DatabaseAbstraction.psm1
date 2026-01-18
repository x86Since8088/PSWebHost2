#Requires -Version 7

<#
.SYNOPSIS
    PSWebHost Database Abstraction Layer

.DESCRIPTION
    Provides a unified interface for database operations across multiple database backends:
    - SQLite (default)
    - SQL Server
    - PostgreSQL
    - MySQL

    Supports connection pooling, parameterized queries, and automatic provider selection.

.NOTES
    Module: PSWebHost_DatabaseAbstraction
    Author: PSWebHost Team
    Version: 1.0.0
#>

#region Base Database Provider Class

<#
.SYNOPSIS
    Base class for all database providers

.DESCRIPTION
    Defines the interface that all database providers must implement
#>
class PSWebHostDatabaseProvider {
    [string]$ConnectionString
    [string]$ProviderType
    [hashtable]$Config

    PSWebHostDatabaseProvider([hashtable]$Config) {
        $this.Config = $Config
        $this.ProviderType = $Config.Type ?? 'SQLite'
    }

    # Abstract methods to be implemented by derived classes
    [object] ExecuteQuery([string]$Query, [hashtable]$Parameters) {
        throw "ExecuteQuery must be implemented by derived class"
    }

    [int] ExecuteNonQuery([string]$Query, [hashtable]$Parameters) {
        throw "ExecuteNonQuery must be implemented by derived class"
    }

    [object] ExecuteScalar([string]$Query, [hashtable]$Parameters) {
        throw "ExecuteScalar must be implemented by derived class"
    }

    [void] BeginTransaction() {
        throw "BeginTransaction must be implemented by derived class"
    }

    [void] CommitTransaction() {
        throw "CommitTransaction must be implemented by derived class"
    }

    [void] RollbackTransaction() {
        throw "RollbackTransaction must be implemented by derived class"
    }

    [bool] TestConnection() {
        throw "TestConnection must be implemented by derived class"
    }

    [void] Close() {
        throw "Close must be implemented by derived class"
    }
}

#endregion

#region SQLite Provider

<#
.SYNOPSIS
    SQLite database provider implementation
#>
class SQLiteProvider : PSWebHostDatabaseProvider {
    [string]$DatabasePath
    [System.Data.SQLite.SQLiteConnection]$Connection
    [System.Data.SQLite.SQLiteTransaction]$Transaction

    SQLiteProvider([hashtable]$Config) : base($Config) {
        $this.DatabasePath = $Config.DatabasePath ?? $Config.File
        $this.ProviderType = 'SQLite'
        $this.ConnectionString = "Data Source=$($this.DatabasePath);Version=3;"

        # Add additional connection string parameters if provided
        if ($Config.Pooling) {
            $this.ConnectionString += "Pooling=True;Max Pool Size=100;"
        }
        if ($Config.ReadOnly) {
            $this.ConnectionString += "Read Only=True;"
        }
    }

    [object] ExecuteQuery([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = $command.CreateParameter()
                    $param.ParameterName = "@$key"
                    $param.Value = $Parameters[$key] ?? [DBNull]::Value
                    $null = $command.Parameters.Add($param)
                }
            }

            $adapter = New-Object System.Data.SQLite.SQLiteDataAdapter($command)
            $dataSet = New-Object System.Data.DataSet
            $null = $adapter.Fill($dataSet)

            # Convert DataTable to array of hashtables
            $results = @()
            if ($dataSet.Tables.Count -gt 0) {
                foreach ($row in $dataSet.Tables[0].Rows) {
                    $obj = @{}
                    foreach ($col in $dataSet.Tables[0].Columns) {
                        $obj[$col.ColumnName] = $row[$col.ColumnName]
                    }
                    $results += $obj
                }
            }

            return $results

        } catch {
            Write-Error "[SQLiteProvider] ExecuteQuery failed: $($_.Exception.Message)"
            throw
        }
    }

    [int] ExecuteNonQuery([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($this.Transaction) {
                $command.Transaction = $this.Transaction
            }

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = $command.CreateParameter()
                    $param.ParameterName = "@$key"
                    $param.Value = $Parameters[$key] ?? [DBNull]::Value
                    $null = $command.Parameters.Add($param)
                }
            }

            return $command.ExecuteNonQuery()

        } catch {
            Write-Error "[SQLiteProvider] ExecuteNonQuery failed: $($_.Exception.Message)"
            throw
        }
    }

    [object] ExecuteScalar([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = $command.CreateParameter()
                    $param.ParameterName = "@$key"
                    $param.Value = $Parameters[$key] ?? [DBNull]::Value
                    $null = $command.Parameters.Add($param)
                }
            }

            return $command.ExecuteScalar()

        } catch {
            Write-Error "[SQLiteProvider] ExecuteScalar failed: $($_.Exception.Message)"
            throw
        }
    }

    [void] BeginTransaction() {
        $this.EnsureConnection()
        $this.Transaction = $this.Connection.BeginTransaction()
    }

    [void] CommitTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Commit()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [void] RollbackTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Rollback()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [bool] TestConnection() {
        try {
            $this.EnsureConnection()
            return ($this.Connection.State -eq 'Open')
        } catch {
            return $false
        }
    }

    [void] Close() {
        if ($this.Transaction) {
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
        if ($this.Connection -and $this.Connection.State -eq 'Open') {
            $this.Connection.Close()
            $this.Connection.Dispose()
        }
    }

    [void] EnsureConnection() {
        if (-not $this.Connection) {
            $this.Connection = New-Object System.Data.SQLite.SQLiteConnection($this.ConnectionString)
        }
        if ($this.Connection.State -ne 'Open') {
            $this.Connection.Open()
        }
    }
}

#endregion

#region SQL Server Provider

<#
.SYNOPSIS
    SQL Server database provider implementation
#>
class SQLServerProvider : PSWebHostDatabaseProvider {
    [string]$Server
    [string]$Database
    [System.Data.SqlClient.SqlConnection]$Connection
    [System.Data.SqlClient.SqlTransaction]$Transaction

    SQLServerProvider([hashtable]$Config) : base($Config) {
        $this.Server = $Config.Server ?? 'localhost'
        $this.Database = $Config.Database ?? 'PSWebHost'
        $this.ProviderType = 'SQLServer'

        # Build connection string
        $csBuilder = New-Object System.Data.SqlClient.SqlConnectionStringBuilder
        $csBuilder['Data Source'] = $this.Server
        $csBuilder['Initial Catalog'] = $this.Database

        if ($Config.IntegratedSecurity) {
            $csBuilder['Integrated Security'] = $true
        } else {
            $csBuilder['User ID'] = $Config.Username
            $csBuilder['Password'] = $Config.Password
        }

        if ($Config.Encrypt) {
            $csBuilder['Encrypt'] = $true
            $csBuilder['TrustServerCertificate'] = $Config.TrustServerCertificate ?? $false
        }

        $csBuilder['Connection Timeout'] = $Config.ConnectionTimeout ?? 30
        $csBuilder['Pooling'] = $Config.Pooling ?? $true

        $this.ConnectionString = $csBuilder.ConnectionString
    }

    [object] ExecuteQuery([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = New-Object System.Data.SqlClient.SqlParameter("@$key", $Parameters[$key] ?? [DBNull]::Value)
                    $null = $command.Parameters.Add($param)
                }
            }

            $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
            $dataSet = New-Object System.Data.DataSet
            $null = $adapter.Fill($dataSet)

            $results = @()
            if ($dataSet.Tables.Count -gt 0) {
                foreach ($row in $dataSet.Tables[0].Rows) {
                    $obj = @{}
                    foreach ($col in $dataSet.Tables[0].Columns) {
                        $obj[$col.ColumnName] = $row[$col.ColumnName]
                    }
                    $results += $obj
                }
            }

            return $results

        } catch {
            Write-Error "[SQLServerProvider] ExecuteQuery failed: $($_.Exception.Message)"
            throw
        }
    }

    [int] ExecuteNonQuery([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($this.Transaction) {
                $command.Transaction = $this.Transaction
            }

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = New-Object System.Data.SqlClient.SqlParameter("@$key", $Parameters[$key] ?? [DBNull]::Value)
                    $null = $command.Parameters.Add($param)
                }
            }

            return $command.ExecuteNonQuery()

        } catch {
            Write-Error "[SQLServerProvider] ExecuteNonQuery failed: $($_.Exception.Message)"
            throw
        }
    }

    [object] ExecuteScalar([string]$Query, [hashtable]$Parameters) {
        try {
            $this.EnsureConnection()

            $command = $this.Connection.CreateCommand()
            $command.CommandText = $Query

            if ($Parameters) {
                foreach ($key in $Parameters.Keys) {
                    $param = New-Object System.Data.SqlClient.SqlParameter("@$key", $Parameters[$key] ?? [DBNull]::Value)
                    $null = $command.Parameters.Add($param)
                }
            }

            return $command.ExecuteScalar()

        } catch {
            Write-Error "[SQLServerProvider] ExecuteScalar failed: $($_.Exception.Message)"
            throw
        }
    }

    [void] BeginTransaction() {
        $this.EnsureConnection()
        $this.Transaction = $this.Connection.BeginTransaction()
    }

    [void] CommitTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Commit()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [void] RollbackTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Rollback()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [bool] TestConnection() {
        try {
            $this.EnsureConnection()
            return ($this.Connection.State -eq 'Open')
        } catch {
            return $false
        }
    }

    [void] Close() {
        if ($this.Transaction) {
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
        if ($this.Connection -and $this.Connection.State -eq 'Open') {
            $this.Connection.Close()
            $this.Connection.Dispose()
        }
    }

    [void] EnsureConnection() {
        if (-not $this.Connection) {
            $this.Connection = New-Object System.Data.SqlClient.SqlConnection($this.ConnectionString)
        }
        if ($this.Connection.State -ne 'Open') {
            $this.Connection.Open()
        }
    }
}

#endregion

#region PostgreSQL Provider

<#
.SYNOPSIS
    PostgreSQL database provider implementation
#>
class PostgreSQLProvider : PSWebHostDatabaseProvider {
    [string]$Server
    [string]$Database
    [object]$Connection
    [object]$Transaction

    PostgreSQLProvider([hashtable]$Config) : base($Config) {
        $this.Server = $Config.Server ?? 'localhost'
        $this.Database = $Config.Database ?? 'pswebhost'
        $this.ProviderType = 'PostgreSQL'

        # Build connection string for Npgsql
        $port = $Config.Port ?? 5432
        $username = $Config.Username ?? 'postgres'
        $password = $Config.Password ?? ''

        $this.ConnectionString = "Host=$($this.Server);Port=$port;Database=$($this.Database);Username=$username;Password=$password;"

        if ($Config.SSL) {
            $this.ConnectionString += "SSL Mode=Require;"
        }
        if ($Config.Pooling) {
            $this.ConnectionString += "Pooling=true;Maximum Pool Size=100;"
        }
    }

    [object] ExecuteQuery([string]$Query, [hashtable]$Parameters) {
        # Note: Requires Npgsql assembly to be loaded
        # For now, return a placeholder implementation
        throw "PostgreSQL provider requires Npgsql assembly. Please install: Install-Package Npgsql"
    }

    [int] ExecuteNonQuery([string]$Query, [hashtable]$Parameters) {
        throw "PostgreSQL provider requires Npgsql assembly. Please install: Install-Package Npgsql"
    }

    [object] ExecuteScalar([string]$Query, [hashtable]$Parameters) {
        throw "PostgreSQL provider requires Npgsql assembly. Please install: Install-Package Npgsql"
    }

    [void] BeginTransaction() {
        throw "PostgreSQL provider requires Npgsql assembly"
    }

    [void] CommitTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Commit()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [void] RollbackTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Rollback()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [bool] TestConnection() {
        return $false
    }

    [void] Close() {
        if ($this.Transaction) {
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
        if ($this.Connection) {
            $this.Connection.Close()
            $this.Connection.Dispose()
        }
    }
}

#endregion

#region MySQL Provider

<#
.SYNOPSIS
    MySQL database provider implementation
#>
class MySQLProvider : PSWebHostDatabaseProvider {
    [string]$Server
    [string]$Database
    [object]$Connection
    [object]$Transaction

    MySQLProvider([hashtable]$Config) : base($Config) {
        $this.Server = $Config.Server ?? 'localhost'
        $this.Database = $Config.Database ?? 'pswebhost'
        $this.ProviderType = 'MySQL'

        # Build connection string for MySql.Data
        $port = $Config.Port ?? 3306
        $username = $Config.Username ?? 'root'
        $password = $Config.Password ?? ''

        $this.ConnectionString = "Server=$($this.Server);Port=$port;Database=$($this.Database);Uid=$username;Pwd=$password;"

        if ($Config.SSL) {
            $this.ConnectionString += "SslMode=Required;"
        }
        if ($Config.Pooling) {
            $this.ConnectionString += "Pooling=true;Max Pool Size=100;"
        }
    }

    [object] ExecuteQuery([string]$Query, [hashtable]$Parameters) {
        throw "MySQL provider requires MySql.Data assembly. Please install: Install-Package MySql.Data"
    }

    [int] ExecuteNonQuery([string]$Query, [hashtable]$Parameters) {
        throw "MySQL provider requires MySql.Data assembly. Please install: Install-Package MySql.Data"
    }

    [object] ExecuteScalar([string]$Query, [hashtable]$Parameters) {
        throw "MySQL provider requires MySql.Data assembly. Please install: Install-Package MySql.Data"
    }

    [void] BeginTransaction() {
        throw "MySQL provider requires MySql.Data assembly"
    }

    [void] CommitTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Commit()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [void] RollbackTransaction() {
        if ($this.Transaction) {
            $this.Transaction.Rollback()
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
    }

    [bool] TestConnection() {
        return $false
    }

    [void] Close() {
        if ($this.Transaction) {
            $this.Transaction.Dispose()
            $this.Transaction = $null
        }
        if ($this.Connection) {
            $this.Connection.Close()
            $this.Connection.Dispose()
        }
    }
}

#endregion

#region Database Factory

<#
.SYNOPSIS
    Factory function to create database provider instances

.DESCRIPTION
    Creates the appropriate database provider based on configuration

.PARAMETER Config
    Configuration hashtable with database settings

.EXAMPLE
    $config = @{
        Type = 'SQLite'
        DatabasePath = 'C:\data\mydb.db'
    }
    $db = New-PSWebHostDatabase -Config $config

.EXAMPLE
    $config = @{
        Type = 'SQLServer'
        Server = 'sql.example.com'
        Database = 'PSWebHost'
        IntegratedSecurity = $true
    }
    $db = New-PSWebHostDatabase -Config $config
#>
function New-PSWebHostDatabase {
    [CmdletBinding()]
    [OutputType([PSWebHostDatabaseProvider])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $providerType = $Config.Type ?? 'SQLite'

    switch ($providerType) {
        'SQLite' {
            return [SQLiteProvider]::new($Config)
        }
        'SQLServer' {
            return [SQLServerProvider]::new($Config)
        }
        'PostgreSQL' {
            return [PostgreSQLProvider]::new($Config)
        }
        'MySQL' {
            return [MySQLProvider]::new($Config)
        }
        default {
            throw "Unsupported database provider type: $providerType"
        }
    }
}

#endregion

#region Helper Functions

<#
.SYNOPSIS
    Execute a query and return results

.PARAMETER Database
    Database provider instance

.PARAMETER Query
    SQL query to execute

.PARAMETER Parameters
    Query parameters (hashtable)

.EXAMPLE
    $results = Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users WHERE Active = @Active" -Parameters @{ Active = 1 }
#>
function Invoke-PSWebHostDbQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSWebHostDatabaseProvider]$Database,

        [Parameter(Mandatory)]
        [string]$Query,

        [hashtable]$Parameters = @{}
    )

    try {
        return $Database.ExecuteQuery($Query, $Parameters)
    } catch {
        Write-Error "Database query failed: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Execute a non-query command (INSERT, UPDATE, DELETE)

.PARAMETER Database
    Database provider instance

.PARAMETER Query
    SQL command to execute

.PARAMETER Parameters
    Query parameters (hashtable)

.EXAMPLE
    $rowsAffected = Invoke-PSWebHostDbNonQuery -Database $db -Query "UPDATE Users SET Active = @Active WHERE ID = @ID" -Parameters @{ Active = 0; ID = 123 }
#>
function Invoke-PSWebHostDbNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSWebHostDatabaseProvider]$Database,

        [Parameter(Mandatory)]
        [string]$Query,

        [hashtable]$Parameters = @{}
    )

    try {
        return $Database.ExecuteNonQuery($Query, $Parameters)
    } catch {
        Write-Error "Database non-query failed: $($_.Exception.Message)"
        throw
    }
}

<#
.SYNOPSIS
    Execute a scalar query (returns single value)

.PARAMETER Database
    Database provider instance

.PARAMETER Query
    SQL query to execute

.PARAMETER Parameters
    Query parameters (hashtable)

.EXAMPLE
    $count = Invoke-PSWebHostDbScalar -Database $db -Query "SELECT COUNT(*) FROM Users WHERE Active = @Active" -Parameters @{ Active = 1 }
#>
function Invoke-PSWebHostDbScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSWebHostDatabaseProvider]$Database,

        [Parameter(Mandatory)]
        [string]$Query,

        [hashtable]$Parameters = @{}
    )

    try {
        return $Database.ExecuteScalar($Query, $Parameters)
    } catch {
        Write-Error "Database scalar query failed: $($_.Exception.Message)"
        throw
    }
}

#endregion

# Export module members
Export-ModuleMember -Function @(
    'New-PSWebHostDatabase'
    'Invoke-PSWebHostDbQuery'
    'Invoke-PSWebHostDbNonQuery'
    'Invoke-PSWebHostDbScalar'
)

# Export classes (PowerShell 5.1+ / 7+)
Export-ModuleMember -Variable @()
