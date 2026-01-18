# PSWebHost Database Abstraction Layer

**Version:** 1.0.0
**Date:** 2026-01-17

---

## Overview

The PSWebHost Database Abstraction Layer provides a unified interface for working with multiple database backends. This allows PSWebHost applications to switch between database systems without changing application code.

### Supported Databases

- ✅ **SQLite** - Default, fully implemented
- ✅ **SQL Server** - Fully implemented
- ⚠️ **PostgreSQL** - Structure ready, requires Npgsql assembly
- ⚠️ **MySQL** - Structure ready, requires MySql.Data assembly

---

## Quick Start

### Basic SQLite Usage

```powershell
# Import the module
Import-Module PSWebHost_DatabaseAbstraction

# Create database instance
$config = @{
    Type = 'SQLite'
    DatabasePath = 'C:\data\myapp.db'
    Pooling = $true
}
$db = New-PSWebHostDatabase -Config $config

# Execute a query
$users = Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users WHERE Active = @Active" -Parameters @{ Active = 1 }

# Execute an insert
$rowsAffected = Invoke-PSWebHostDbNonQuery -Database $db -Query "INSERT INTO Users (Name, Email) VALUES (@Name, @Email)" -Parameters @{
    Name = 'John Doe'
    Email = 'john@example.com'
}

# Get a single value
$userCount = Invoke-PSWebHostDbScalar -Database $db -Query "SELECT COUNT(*) FROM Users"

# Close connection
$db.Close()
```

### SQL Server Usage

```powershell
$config = @{
    Type = 'SQLServer'
    Server = 'sql.example.com'
    Database = 'PSWebHost'
    IntegratedSecurity = $true
    Encrypt = $true
    TrustServerCertificate = $false
}
$db = New-PSWebHostDatabase -Config $config

# Same query methods work across all providers
$tasks = Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Tasks WHERE Enabled = @Enabled" -Parameters @{ Enabled = 1 }

$db.Close()
```

---

## Configuration

### SQLite Configuration

```powershell
@{
    Type = 'SQLite'
    DatabasePath = 'C:\path\to\database.db'  # Required
    File = 'C:\path\to\database.db'          # Alias for DatabasePath
    Pooling = $true                          # Optional: Enable connection pooling
    ReadOnly = $false                        # Optional: Open in read-only mode
}
```

### SQL Server Configuration

```powershell
@{
    Type = 'SQLServer'
    Server = 'localhost'                     # Required: Server hostname or IP
    Database = 'PSWebHost'                   # Required: Database name
    IntegratedSecurity = $true               # Use Windows Authentication
    # OR use SQL Authentication:
    # Username = 'sa'
    # Password = 'your_password'
    Encrypt = $true                          # Use encryption
    TrustServerCertificate = $false          # Validate server certificate
    ConnectionTimeout = 30                   # Connection timeout in seconds
    Pooling = $true                          # Enable connection pooling
}
```

### PostgreSQL Configuration

```powershell
@{
    Type = 'PostgreSQL'
    Server = 'localhost'                     # Required: Server hostname or IP
    Database = 'pswebhost'                   # Required: Database name
    Port = 5432                              # Optional: Default 5432
    Username = 'postgres'                    # Required
    Password = 'your_password'               # Required
    SSL = $true                              # Optional: Use SSL
    Pooling = $true                          # Optional: Enable pooling
}
```

**Note:** Requires Npgsql assembly:
```powershell
Install-Package Npgsql -Source nuget.org
```

### MySQL Configuration

```powershell
@{
    Type = 'MySQL'
    Server = 'localhost'                     # Required: Server hostname or IP
    Database = 'pswebhost'                   # Required: Database name
    Port = 3306                              # Optional: Default 3306
    Username = 'root'                        # Required
    Password = 'your_password'               # Required
    SSL = $false                             # Optional: Use SSL
    Pooling = $true                          # Optional: Enable pooling
}
```

**Note:** Requires MySql.Data assembly:
```powershell
Install-Package MySql.Data -Source nuget.org
```

---

## API Reference

### New-PSWebHostDatabase

Creates a new database provider instance.

**Parameters:**
- `Config` (hashtable) - Database configuration

**Returns:** Database provider instance

**Example:**
```powershell
$db = New-PSWebHostDatabase -Config @{ Type = 'SQLite'; DatabasePath = 'data.db' }
```

### Invoke-PSWebHostDbQuery

Executes a SELECT query and returns results.

**Parameters:**
- `Database` (provider) - Database instance
- `Query` (string) - SQL query
- `Parameters` (hashtable) - Query parameters

**Returns:** Array of hashtables

**Example:**
```powershell
$results = Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users WHERE ID = @ID" -Parameters @{ ID = 123 }
```

### Invoke-PSWebHostDbNonQuery

Executes INSERT, UPDATE, DELETE commands.

**Parameters:**
- `Database` (provider) - Database instance
- `Query` (string) - SQL command
- `Parameters` (hashtable) - Query parameters

**Returns:** Number of rows affected

**Example:**
```powershell
$rows = Invoke-PSWebHostDbNonQuery -Database $db -Query "DELETE FROM Users WHERE ID = @ID" -Parameters @{ ID = 123 }
```

### Invoke-PSWebHostDbScalar

Executes a query that returns a single value.

**Parameters:**
- `Database` (provider) - Database instance
- `Query` (string) - SQL query
- `Parameters` (hashtable) - Query parameters

**Returns:** Single value

**Example:**
```powershell
$count = Invoke-PSWebHostDbScalar -Database $db -Query "SELECT COUNT(*) FROM Users"
```

---

## Transactions

All providers support transactions:

```powershell
$db = New-PSWebHostDatabase -Config $config

try {
    # Begin transaction
    $db.BeginTransaction()

    # Execute multiple commands
    Invoke-PSWebHostDbNonQuery -Database $db -Query "INSERT INTO Accounts (Name) VALUES (@Name)" -Parameters @{ Name = 'Account1' }
    Invoke-PSWebHostDbNonQuery -Database $db -Query "INSERT INTO Logs (Message) VALUES (@Msg)" -Parameters @{ Msg = 'Account created' }

    # Commit if all successful
    $db.CommitTransaction()

} catch {
    # Rollback on error
    $db.RollbackTransaction()
    Write-Error "Transaction failed: $_"
} finally {
    $db.Close()
}
```

---

## Advanced Usage

### Connection Testing

```powershell
$db = New-PSWebHostDatabase -Config $config

if ($db.TestConnection()) {
    Write-Host "✓ Database connection successful"
} else {
    Write-Error "✗ Database connection failed"
}

$db.Close()
```

### Provider Properties

Each provider exposes properties for inspection:

```powershell
$db = New-PSWebHostDatabase -Config $config

Write-Host "Provider Type: $($db.ProviderType)"
Write-Host "Connection String: $($db.ConnectionString)"

if ($db.ProviderType -eq 'SQLite') {
    Write-Host "Database Path: $($db.DatabasePath)"
}

$db.Close()
```

### Using in PSWebHost Apps

Example of using the abstraction layer in an app endpoint:

```powershell
# routes/api/v1/users/get.ps1

param (
    [System.Net.HttpListenerContext]$Context,
    [hashtable]$Query = @{}
)

# Get database instance from global config
$dbConfig = $Global:PSWebServer.Config.Database ?? @{
    Type = 'SQLite'
    DatabasePath = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\app.db"
}

$db = New-PSWebHostDatabase -Config $dbConfig

try {
    # Query users
    $users = Invoke-PSWebHostDbQuery -Database $db -Query @"
SELECT ID, Name, Email, CreatedAt
FROM Users
WHERE Active = @Active
ORDER BY CreatedAt DESC
"@ -Parameters @{ Active = 1 }

    # Return JSON response
    $response = @{
        success = $true
        count = $users.Count
        users = $users
    }

    context_response -Response $Context.Response -String ($response | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    # Error response
    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    }

    context_response -Response $Context.Response -String ($errorResponse | ConvertTo-Json) -ContentType "application/json"

} finally {
    $db.Close()
}
```

---

## Migration Guide

### From Direct SQLite Calls

**Before:**
```powershell
$query = "SELECT * FROM Users WHERE ID = @ID"
$params = @{ ID = 123 }
$results = Invoke-PSWebSQLiteQuery -File $dbPath -Query $query -Parameters $params
```

**After:**
```powershell
$db = New-PSWebHostDatabase -Config @{ Type = 'SQLite'; DatabasePath = $dbPath }
$results = Invoke-PSWebHostDbQuery -Database $db -Query $query -Parameters @{ ID = 123 }
$db.Close()
```

### Switching Database Backends

To switch from SQLite to SQL Server, only the configuration changes:

```powershell
# Development (SQLite)
$config = @{
    Type = 'SQLite'
    DatabasePath = 'dev.db'
}

# Production (SQL Server)
$config = @{
    Type = 'SQLServer'
    Server = 'prod-sql.example.com'
    Database = 'PSWebHost'
    IntegratedSecurity = $true
}

# Application code remains identical
$db = New-PSWebHostDatabase -Config $config
$users = Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users"
$db.Close()
```

---

## Best Practices

### 1. Use Connection Pooling

Enable pooling for better performance with multiple requests:

```powershell
$config = @{
    Type = 'SQLite'
    DatabasePath = 'app.db'
    Pooling = $true  # ✓ Enable pooling
}
```

### 2. Always Close Connections

Use try/finally to ensure connections are closed:

```powershell
$db = New-PSWebHostDatabase -Config $config
try {
    # Database operations
} finally {
    $db.Close()
}
```

### 3. Use Parameterized Queries

Always use parameters to prevent SQL injection:

```powershell
# ✓ Good - Parameterized
Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users WHERE Name = @Name" -Parameters @{ Name = $userName }

# ✗ Bad - String concatenation (SQL injection risk!)
Invoke-PSWebHostDbQuery -Database $db -Query "SELECT * FROM Users WHERE Name = '$userName'"
```

### 4. Handle Errors Gracefully

Always wrap database operations in try/catch:

```powershell
try {
    $results = Invoke-PSWebHostDbQuery -Database $db -Query $query -Parameters $params
} catch {
    Write-Error "Database operation failed: $($_.Exception.Message)"
    # Log error, return error response, etc.
}
```

### 5. Use Transactions for Multiple Operations

Wrap related operations in transactions:

```powershell
$db.BeginTransaction()
try {
    Invoke-PSWebHostDbNonQuery -Database $db -Query "INSERT INTO Table1 ..." -Parameters @{ ... }
    Invoke-PSWebHostDbNonQuery -Database $db -Query "INSERT INTO Table2 ..." -Parameters @{ ... }
    $db.CommitTransaction()
} catch {
    $db.RollbackTransaction()
    throw
}
```

---

## Troubleshooting

### SQLite: Database is locked

**Cause:** Another process has the database locked.

**Solution:**
- Enable connection pooling
- Use shorter transactions
- Check for unclosed connections

### SQL Server: Login failed

**Cause:** Authentication issues.

**Solution:**
- Verify username/password
- Try IntegratedSecurity = $true
- Check SQL Server allows remote connections
- Verify firewall rules

### PostgreSQL/MySQL: Provider not available

**Cause:** Required assembly not installed.

**Solution:**
```powershell
# For PostgreSQL
Install-Package Npgsql -Source nuget.org

# For MySQL
Install-Package MySql.Data -Source nuget.org
```

---

## Roadmap

- [x] SQLite provider (fully implemented)
- [x] SQL Server provider (fully implemented)
- [ ] PostgreSQL provider (requires Npgsql assembly)
- [ ] MySQL provider (requires MySql.Data assembly)
- [ ] Connection pooling optimization
- [ ] Async query support
- [ ] Bulk insert operations
- [ ] Query builder helpers

---

**Last Updated:** 2026-01-17
**Maintainer:** PSWebHost Development Team
