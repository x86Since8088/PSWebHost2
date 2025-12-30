# PSWebHost_Database.psm1

Core database module providing SQLite data access, user management, and session persistence for the PsWebHost application.

## Overview

This module handles all database interactions using `sqlite3.exe` command-line tool. It provides both generic SQL operations and high-level abstractions for user management, authentication, roles, and sessions.

## Database Architecture

**Database File:** `PsWebHost_Data/pswebhost.db`

**Key Tables:**
- `Users` - User accounts
- `User_Groups` - User groups for role inheritance
- `User_Groups_Map` - User-to-group membership
- `PSWeb_Roles` - Role assignments (users/groups → roles)
- `LoginSessions` - User sessions (with compressed data)
- `auth_user_provider` - Authentication provider mappings
- `LogonAttempts` - Failed login tracking for lockout
- `LoginLockoutViolations` - Lockout violation records
- `AppSettings` - Application configuration
- `CardSettings` - UI dashboard settings

## Functions

### Generic Database Operations

#### `Get-PSWebSQLiteData`

Executes a SELECT query and returns results as PowerShell objects.

```powershell
Get-PSWebSQLiteData -File <string> -Query <string>
```

**Parameters:**
- `-File`: Full path to SQLite database file
- `-Query`: SQL SELECT statement

**Returns:** Array of PSCustomObjects with properties matching column names

**Usage:**
```powershell
$users = Get-PSWebSQLiteData -File "C:\sc\PsWebHost\PsWebHost_Data\pswebhost.db" -Query "SELECT * FROM Users WHERE Email = 'user@example.com';"
```

**Implementation:**
- Executes query via `sqlite3.exe -csv -header`
- Converts CSV output to PSCustomObjects
- Handles empty results gracefully

**SQL Injection Warning:** This function does not sanitize input. Use `Sanitize-SqlQueryString` for user input.

#### `Invoke-PSWebSQLiteNonQuery`

Executes INSERT, UPDATE, DELETE, or other non-SELECT statements.

```powershell
Invoke-PSWebSQLiteNonQuery -File <string> -Query <string>
```

**Parameters:**
- `-File`: Full path to SQLite database file
- `-Query`: SQL statement (INSERT, UPDATE, DELETE, etc.)

**Returns:** `$true` on success, `$false` on failure

**Usage:**
```powershell
$query = "UPDATE Users SET LastLogin = '$((Get-Date).ToString('o'))' WHERE UserID = '$userID';"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
```

**Implementation:**
- Executes via `sqlite3.exe`
- Captures stderr for error detection
- Returns boolean success indicator

#### `New-PSWebSQLiteData`

Inserts a new record into a table.

```powershell
New-PSWebSQLiteData -File <string> -TableName <string> -Data <hashtable>
```

**Parameters:**
- `-File`: Full path to SQLite database file
- `-TableName`: Table name
- `-Data`: Hashtable of column→value mappings

**Returns:** `$true` on success, `$false` on failure

**Usage:**
```powershell
$userData = @{
    UserID = [Guid]::NewGuid().ToString()
    Email = 'newuser@example.com'
    Created = (Get-Date).ToString('o')
}
New-PSWebSQLiteData -File $dbFile -TableName 'Users' -Data $userData
```

**Implementation:**
- Builds INSERT statement from hashtable
- Values are SQL-escaped (single quotes doubled)
- NULL values handled correctly

#### `Sanitize-SqlQueryString`

Escapes special characters in SQL strings to prevent injection.

```powershell
Sanitize-SqlQueryString -Input <string>
```

**Parameters:**
- `-Input`: String to sanitize

**Returns:** Sanitized string safe for SQL queries

**Sanitization:**
- Single quotes → Doubled (`'` → `''`)
- Does NOT add outer quotes (caller's responsibility)

**Usage:**
```powershell
$safeEmail = Sanitize-SqlQueryString -Input $userEmail
$query = "SELECT * FROM Users WHERE Email = '$safeEmail';"
```

**Security Note:** This is basic escaping. For complex queries, use parameterized queries when available.

### User Management

#### `Get-PSWebUser`

Retrieves a user record by Email or UserID.

```powershell
Get-PSWebUser -Email <string>
Get-PSWebUser -UserID <string>
```

**Parameters:**
- `-Email`: User email address (UPN)
- `-UserID`: User GUID

**Returns:** PSCustomObject with user properties, or `$null` if not found

**User Properties:**
```powershell
@{
    UserID = "guid"
    Email = "user@example.com"
    PasswordHash = "salt:hash" (if Password provider)
    Phone = "555-1234"
    Created = "2025-01-01T00:00:00"
    Updated = "2025-01-15T12:30:00"
    LastLogin = "2025-12-29T09:00:00"
}
```

**Usage:**
```powershell
# Lookup by email
$user = Get-PSWebUser -Email 'user@example.com'

# Lookup by UserID
$user = Get-PSWebUser -UserID '12345678-1234-1234-1234-123456789012'

if ($user) {
    Write-Host "Found user: $($user.Email)"
}
```

**See:** modules/PSWebHost_Database/PSWebHost_Database.psm1:221

#### `Set-PSWebUser`

Updates or creates a user record.

```powershell
Set-PSWebUser -Email <string> -UserID <string> [-Phone <string>] [-PasswordHash <string>] [-Updated <DateTime>] [-LastLogin <DateTime>]
```

**Parameters:**
- `-Email`: User email (required)
- `-UserID`: User GUID (required)
- `-Phone`: Phone number (optional)
- `-PasswordHash`: Password hash in `salt:hash` format (optional)
- `-Updated`: Last updated timestamp (optional, defaults to now)
- `-LastLogin`: Last login timestamp (optional)

**Behavior:**
- If user exists (by UserID), updates fields
- If user doesn't exist, creates new record
- Preserves existing values for unprovided parameters

**Usage:**
```powershell
# Create new user
Set-PSWebUser -Email 'newuser@example.com' -UserID (New-Guid).ToString()

# Update last login
Set-PSWebUser -Email $user.Email -UserID $user.UserID -LastLogin (Get-Date)

# Update password hash
Set-PSWebUser -Email $user.Email -UserID $user.UserID -PasswordHash "salt:hash"
```

**See:** modules/PSWebHost_Database/PSWebHost_Database.psm1:268

#### `Set-PSWebHostRole`

Assigns a role to a user or group.

```powershell
Set-PSWebHostRole -PrincipalID <string> -PrincipalType <string> -Role <string>
```

**Parameters:**
- `-PrincipalID`: UserID or GroupID
- `-PrincipalType`: `"User"` or `"Group"`
- `-Role`: Role name (e.g., "Admin", "Moderator", "User")

**Behavior:**
- Checks if role assignment already exists
- If not, creates new entry in `PSWeb_Roles` table
- If exists, no action taken (idempotent)

**Usage:**
```powershell
# Assign role to user
Set-PSWebHostRole -PrincipalID $user.UserID -PrincipalType "User" -Role "Admin"

# Assign role to group
Set-PSWebHostRole -PrincipalID $group.GroupID -PrincipalType "Group" -Role "Moderator"
```

**Role Inheritance:**
Users automatically inherit roles from groups they belong to (via `User_Groups_Map`).

**See:** modules/PSWebHost_Database/PSWebHost_Database.psm1:300

### Token and Authentication

#### `Invoke-TestToken`

Manages authentication tokens during multi-step login processes.

```powershell
Invoke-TestToken -action <string> -token <string> [-data <string>] [-type <string>]
```

**Parameters:**
- `-action`: Action to perform (`"create"`, `"get"`, `"update"`, `"validate"`)
- `-token`: Token GUID
- `-data`: Token payload data (for create/update)
- `-type`: Token type identifier (optional)

**Actions:**

**create** - Creates a new token
```powershell
$token = Invoke-TestToken -action "create" -token (New-Guid).ToString() -data "user@example.com" -type "email-confirmation"
```

**get** - Retrieves token data
```powershell
$tokenData = Invoke-TestToken -action "get" -token $tokenGuid
```

**update** - Updates token data
```powershell
Invoke-TestToken -action "update" -token $tokenGuid -data "updated-data"
```

**validate** - Checks if token exists and is valid
```powershell
$isValid = Invoke-TestToken -action "validate" -token $tokenGuid
if ($isValid) { Write-Host "Token valid" }
```

**Token Expiration:** Tokens are typically validated against a timestamp in the `data` field.

**Use Cases:**
- Email confirmation tokens
- Password reset tokens
- Two-factor authentication temporary tokens
- OAuth state validation

**Database Table:** `auth_tokens` (if exists) or similar structure

**See:** modules/PSWebHost_Database/PSWebHost_Database.psm1:145

## Database Initialization

### Schema Creation

The database schema is defined in `system/db/sqlite/sqliteconfig.json` and created by:

```powershell
.\system\db\sqlite\validatetables.ps1
```

**Key Tables:**

**Users**
```sql
CREATE TABLE Users (
    UserID TEXT PRIMARY KEY NOT NULL,
    Email TEXT NOT NULL UNIQUE,
    PasswordHash TEXT,
    Phone TEXT,
    Created TEXT DEFAULT CURRENT_TIMESTAMP,
    Updated TEXT DEFAULT CURRENT_TIMESTAMP,
    LastLogin TEXT
);
```

**LoginSessions**
```sql
CREATE TABLE LoginSessions (
    SessionID TEXT PRIMARY KEY NOT NULL,
    UserID TEXT,
    SessionData TEXT,  -- Compressed JSON
    Created TEXT DEFAULT CURRENT_TIMESTAMP,
    LastAccessed TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE CASCADE
);
```

**auth_user_provider**
```sql
CREATE TABLE auth_user_provider (
    UserID TEXT NOT NULL,
    provider TEXT NOT NULL,
    data TEXT,
    enabled INTEGER DEFAULT 1,
    locked_out INTEGER DEFAULT 0,
    created TEXT DEFAULT CURRENT_TIMESTAMP,
    updated TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (UserID) REFERENCES Users(UserID) ON DELETE CASCADE,
    PRIMARY KEY (UserID, provider)
);
```

**PSWeb_Roles**
```sql
CREATE TABLE PSWeb_Roles (
    PrincipalID TEXT NOT NULL,      -- UserID or GroupID
    PrincipalType TEXT NOT NULL,    -- 'User' or 'Group'
    Role TEXT NOT NULL,
    Created TEXT DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (PrincipalID, PrincipalType, Role)
);
```

## Database File Access

### Connection Management

**No persistent connections.** Each function call:
1. Executes `sqlite3.exe` with database file path
2. Runs SQL command
3. Captures output
4. Process exits

**Thread Safety:** SQLite provides file-level locking. Multiple PowerShell processes can safely access the database.

### Database File Path

Typically stored in global variable:
```powershell
$dbFile = $Global:PSWebServer.Project_Root.Path + "\PsWebHost_Data\pswebhost.db"
```

Or determined dynamically:
```powershell
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dbFile = Join-Path $projectRoot "PsWebHost_Data\pswebhost.db"
```

## Data Serialization

### Compression

Session data and large objects are compressed before storage:

```powershell
# From PSWebHost_Support module
$sessionJson = $sessionData | ConvertTo-Json
$compressed = ConvertTo-CompressedBase64 -InputString $sessionJson

# Store in database
$query = "UPDATE LoginSessions SET SessionData = '$compressed' WHERE SessionID = '$sessionID';"
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query
```

Decompression (if implemented):
```powershell
function ConvertFrom-CompressedBase64 {
    param([string]$CompressedBase64)
    # Decode Base64 → decompress GZip → JSON string
}
```

**Compression Ratio:** Typically 70-90% reduction for JSON session data.

## Security Considerations

1. **SQL Injection Prevention**
   - Use `Sanitize-SqlQueryString` for user input
   - Consider prepared statements for complex queries
   - Never concatenate raw user input into SQL

2. **Password Storage**
   - Passwords hashed with PBKDF2 (10,000 iterations)
   - Format: `salt:hash` both in Base64
   - Stored in `Users.PasswordHash` column

3. **Session Security**
   - Session data compressed to reduce storage
   - SessionID is random GUID
   - UserAgent validation prevents hijacking

4. **Database File Permissions**
   - Ensure `pswebhost.db` has appropriate file permissions
   - Limit access to web server process account

5. **Sensitive Data**
   - Email addresses stored in plain text (required for lookup)
   - Phone numbers stored in plain text
   - Consider encryption for PII if needed

## Performance Considerations

1. **Indexing**
   - Create indexes on frequently queried columns:
     ```sql
     CREATE INDEX idx_users_email ON Users(Email);
     CREATE INDEX idx_sessions_userid ON LoginSessions(UserID);
     ```

2. **Connection Overhead**
   - Each query spawns new `sqlite3.exe` process
   - For high-throughput, consider PowerShell SQLite module instead
   - Current design suitable for 10-100 req/sec

3. **Query Optimization**
   - Use specific columns instead of `SELECT *`
   - Add WHERE clauses to limit result sets
   - Avoid N+1 query patterns

4. **Database Size**
   - Compressed sessions reduce storage needs
   - Implement log rotation for `LogonAttempts`
   - Consider archiving old sessions

## Error Handling

### Database Locked

SQLite locks database during writes. If concurrent access high:

**Error:** `database is locked`

**Solutions:**
1. Enable WAL mode: `PRAGMA journal_mode=WAL;`
2. Increase busy timeout: `PRAGMA busy_timeout=5000;`
3. Retry with exponential backoff

### File Not Found

**Error:** `unable to open database file`

**Cause:** Database file doesn't exist

**Solution:**
```powershell
if (-not (Test-Path $dbFile)) {
    .\system\db\sqlite\validatetables.ps1  # Create database
}
```

### Constraint Violations

**Error:** `UNIQUE constraint failed: Users.Email`

**Cause:** Attempting to create user with existing email

**Solution:** Check for existence before insert:
```powershell
$existing = Get-PSWebUser -Email $email
if ($existing) {
    Write-Error "User already exists"
    return
}
```

## Usage Examples

### Complete User Registration

```powershell
# Generate UserID
$userID = [Guid]::NewGuid().ToString()

# Hash password
$salt = Get-RandomBytes -Length 16 | ConvertTo-Base64
$hash = Get-PBKDF2Hash -Password $password -Salt $salt -Iterations 10000 | ConvertTo-Base64
$passwordHash = "$salt:$hash"

# Create user
Set-PSWebUser -Email $email -UserID $userID -PasswordHash $passwordHash

# Add authentication provider
$query = @"
INSERT INTO auth_user_provider (UserID, provider, enabled, locked_out)
VALUES ('$userID', 'Password', 1, 0);
"@
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query

# Assign default role
Set-PSWebHostRole -PrincipalID $userID -PrincipalType "User" -Role "User"
```

### Session Persistence

```powershell
# Create session
$sessionID = [Guid]::NewGuid().ToString()
$sessionData = @{
    UserID = $user.UserID
    Roles = @("Admin", "User")
    Created = Get-Date
    LastAccessed = Get-Date
    UserAgent = $Request.UserAgent
} | ConvertTo-Json | ConvertTo-CompressedBase64

$query = @"
INSERT INTO LoginSessions (SessionID, UserID, SessionData, Created, LastAccessed)
VALUES ('$sessionID', '$($user.UserID)', '$sessionData', '$((Get-Date).ToString('o'))', '$((Get-Date).ToString('o'))');
"@
Invoke-PSWebSQLiteNonQuery -File $dbFile -Query $query

# Retrieve session
$sessions = Get-PSWebSQLiteData -File $dbFile -Query "SELECT * FROM LoginSessions WHERE SessionID = '$sessionID';"
$session = $sessions[0]
$decompressed = ConvertFrom-CompressedBase64 -CompressedBase64 $session.SessionData
$sessionData = $decompressed | ConvertFrom-Json
```

### Query Users by Role

```powershell
# Find all admins
$query = @"
SELECT DISTINCT u.* FROM Users u
INNER JOIN PSWeb_Roles r ON u.UserID = r.PrincipalID
WHERE r.PrincipalType = 'User' AND r.Role = 'Admin';
"@
$admins = Get-PSWebSQLiteData -File $dbFile -Query $query
```

## Troubleshooting

### Database Corruption

**Symptom:** Errors like `database disk image is malformed`

**Recovery:**
```powershell
# Backup database
Copy-Item $dbFile "$dbFile.backup"

# Check integrity
sqlite3 $dbFile "PRAGMA integrity_check;"

# If corrupted, dump and restore
sqlite3 $dbFile ".dump" | sqlite3 "$dbFile.new"
Move-Item "$dbFile.new" $dbFile -Force
```

### Slow Queries

**Symptom:** Queries taking >1 second

**Diagnosis:**
```sql
EXPLAIN QUERY PLAN SELECT * FROM Users WHERE Email = 'user@example.com';
```

**Solutions:**
1. Add indexes
2. Analyze query plan
3. Vacuum database: `PRAGMA vacuum;`

### Cannot Write to Database

**Symptom:** `attempt to write a readonly database`

**Cause:** File permissions or read-only database

**Solution:**
```powershell
# Check file permissions
(Get-Item $dbFile).IsReadOnly  # Should be $false

# Set writable
Set-ItemProperty $dbFile -Name IsReadOnly -Value $false
```

## Dependencies

### Required Executables
- **sqlite3.exe** - Must be in PATH or specified location
- Included in project at: `system/db/sqlite/sqlite3.exe`

### Required Modules
- **PSWebHost_Support** - For `ConvertTo-CompressedBase64`
- **PSWebHost_Authentication** - For password hashing (PBKDF2)

### Database Tables
All tables must exist before use. Create with:
```powershell
.\system\db\sqlite\validatetables.ps1
```

## Related Files

- `system/db/sqlite/sqliteconfig.json` - Database schema definition
- `system/db/sqlite/validatetables.ps1` - Schema creation script
- `system/db/sqlite/sqlite3.exe` - SQLite command-line tool
- `PsWebHost_Data/pswebhost.db` - Database file
- `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` - User auth functions
- `modules/PSWebHost_Support/PSWebHost_Support.psm1` - Session compression

## Future Enhancements

1. **Connection Pooling** - Reduce `sqlite3.exe` process overhead
2. **Prepared Statements** - Better SQL injection protection
3. **Query Caching** - Cache frequent queries in memory
4. **Async Operations** - Background database writes
5. **Migration System** - Version database schema changes
6. **Replication** - Multi-node database support
7. **Encryption at Rest** - SQLite encryption extension

## See Also

- User retrieval: modules/PSWebHost_Database/PSWebHost_Database.psm1:221
- User updates: modules/PSWebHost_Database/PSWebHost_Database.psm1:268
- Role assignment: modules/PSWebHost_Database/PSWebHost_Database.psm1:300
- Token management: modules/PSWebHost_Database/PSWebHost_Database.psm1:145
- Generic queries: modules/PSWebHost_Database/PSWebHost_Database.psm1:1
