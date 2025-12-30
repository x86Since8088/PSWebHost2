# PSWebHost_Support.psm1

Core support module providing HTTP request processing, session management, logging, and utility functions for the PsWebHost web server.

## Overview

This PowerShell module forms the backbone of PsWebHost, providing essential infrastructure for handling HTTP requests, managing user sessions, logging application events, and serving responses. All routing and request processing flows through this module.

## Module Initialization

```powershell
# Global hashtable for session management
if ($null -eq $global:PSWebSessions) {
    $global:PSWebSessions = [hashtable]::Synchronized(@{})
}
```

Creates a thread-safe in-memory session cache for performance optimization.

## Functions

### HTTP Request Processing

#### `Get-RequestBody`

Reads the body content from an HTTP POST/PUT request.

```powershell
Get-RequestBody -Request <HttpListenerRequest>
```

**Parameters:**
- `-Request`: System.Net.HttpListenerRequest object

**Returns:** String containing request body, or `$null` if no body present

**Implementation:**
- Checks `$Request.HasEntityBody`
- Reads using `StreamReader` with request's content encoding
- Closes stream in `finally` block for cleanup

**Usage:**
```powershell
$bodyContent = Get-RequestBody -Request $Request
$parsedBody = [System.Web.HttpUtility]::ParseQueryString($bodyContent)
```

#### `context_reponse`

Sends an HTTP response with the specified status code, content, and headers.

```powershell
context_reponse -Response <HttpListenerResponse> -StatusCode <int> [-String <string>] [-Bytes <byte[]>] [-File <string>] [-ContentType <string>] [-RedirectLocation <string>]
```

**Parameters:**
- `-Response`: HttpListenerResponse object
- `-StatusCode`: HTTP status code (200, 404, 500, etc.)
- `-String`: Response content as string (optional)
- `-Bytes`: Response content as byte array (optional)
- `-File`: Path to file to send (optional)
- `-ContentType`: MIME type (auto-detected for files)
- `-RedirectLocation`: URL for 3xx redirects

**Usage Examples:**
```powershell
# JSON response
context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"

# File download
context_reponse -Response $Response -StatusCode 200 -File "C:\files\document.pdf"

# Redirect
context_reponse -Response $Response -StatusCode 302 -RedirectLocation "/dashboard"
```

**MIME Type Detection:**
Automatically sets Content-Type based on file extension:
- `.html`, `.htm` → `text/html`
- `.css` → `text/css`
- `.js` → `application/javascript`
- `.json` → `application/json`
- `.png`, `.jpg`, `.gif`, etc. → appropriate `image/*` type

#### `Resolve-RouteScriptPath`

Resolves a URL path and HTTP method to a route script file.

```powershell
Resolve-RouteScriptPath -UrlPath <string> -HttpMethod <string> -BaseDirectory <string>
```

**Parameters:**
- `-UrlPath`: Request URL path (e.g., `/api/v1/users`)
- `-HttpMethod`: HTTP method (GET, POST, PUT, DELETE)
- `-BaseDirectory`: Routes base directory (usually `routes/`)

**Returns:** Full path to route script if found, `$null` otherwise

**Mapping Logic:**
```
URL: /api/v1/users
Method: GET
Result: {BaseDirectory}/api/v1/users/get.ps1
```

**Usage:**
```powershell
$scriptPath = Resolve-RouteScriptPath -UrlPath "/api/v1/users" -HttpMethod "GET" -BaseDirectory "C:\sc\PsWebHost\routes"
if ($scriptPath) {
    & $scriptPath -Context $Context
}
```

#### `Process-HttpRequest`

**Main request routing engine.** Processes incoming HTTP requests by:
1. Managing session cookies
2. Checking security/authorization
3. Serving static files or executing route scripts

```powershell
Process-HttpRequest -Context <HttpListenerContext>
```

**Parameters:**
- `-Context`: System.Net.HttpListenerContext object

**Request Flow:**
1. **Session Cookie Management**: Ensures PSWebSessionID cookie exists
2. **Static File Serving**: Serves files from `/public` directory
3. **Route Resolution**: Maps URL + method to script path
4. **Security Check**: Validates against `.security.json` (if present)
5. **Script Execution**: Invokes route handler with context
6. **Error Handling**: Returns 500 on unhandled exceptions

**Static File Serving:**
```
URL: /style.css
File: {ProjectRoot}/public/style.css
```

**Route Execution:**
```
URL: /api/v1/users
Method: GET
Script: {ProjectRoot}/routes/api/v1/users/get.ps1
```

**Security JSON Format:**
```json
{
  "requiresAuth": true,
  "requiredRoles": ["Admin", "User"]
}
```

**See:** modules/PSWebHost_Support/PSWebHost_Support.psm1:334 for full implementation

### Session Management

#### `Ensure-SessionCookie`

Ensures a PSWebSessionID cookie exists for the request.

```powershell
Ensure-SessionCookie -Request <HttpListenerRequest> -Response <HttpListenerResponse>
```

**Returns:** Hashtable with `@{ SessionID=..., SessionCookie=... }`

**Cookie Settings:**
- **Name**: `PSWebSessionID`
- **Value**: GUID
- **Path**: `/`
- **HttpOnly**: `true` (prevents JavaScript access)
- **Secure**: Set if HTTPS
- **Expires**: 7 days from creation
- **Domain**: Set to hostname (except localhost/IPs)

**Usage:**
```powershell
$sessionInfo = Ensure-SessionCookie -Request $Request -Response $Response
$sessionID = $sessionInfo.SessionID
```

#### `Get-PSWebSessions`

Retrieves a session by SessionID, with in-memory caching.

```powershell
Get-PSWebSessions -SessionID <string>
```

**Parameters:**
- `-SessionID`: Session GUID

**Returns:** Hashtable containing session data, or `$null` if not found

**Lookup Order:**
1. Check in-memory cache (`$global:PSWebSessions`)
2. Query database (`LoginSessions` table)
3. Deserialize compressed session data
4. Cache in memory for subsequent requests

**Session Data Structure:**
```powershell
@{
    SessionID = "guid"
    UserID = "user-guid"
    Roles = @("Admin", "User")
    State = "completed"
    Provider = "Password"
    Created = [DateTime]
    LastAccessed = [DateTime]
    UserAgent = "Mozilla/5.0..."
    IPAddress = "192.168.1.100"
}
```

**Usage:**
```powershell
$session = Get-PSWebSessions -SessionID $sessionID
if ($session -and $session.UserID) {
    Write-Host "Authenticated as $($session.UserID)"
}
```

#### `Set-PSWebSession`

Updates or creates a session with new data.

```powershell
Set-PSWebSession -SessionID <string> [-UserID <string>] [-Roles <string[]>] [-State <string>] [-Provider <string>] [-Request <HttpListenerRequest>]
```

**Parameters:**
- `-SessionID`: Session GUID
- `-UserID`: User GUID (optional)
- `-Roles`: Array of role names (optional)
- `-State`: Session state (optional)
- `-Provider`: Auth provider name (optional)
- `-Request`: HttpListenerRequest for IP/UserAgent (optional)

**Behavior:**
- Updates existing session or creates new one
- Preserves existing values if parameters not provided
- Updates `LastAccessed` timestamp
- Compresses session data with `ConvertTo-CompressedBase64`
- Writes to database (`LoginSessions` table)
- Updates in-memory cache

**Usage:**
```powershell
# Set user after successful authentication
Set-PSWebSession -SessionID $sessionID -UserID $user.UserID -Roles $user.Roles -Provider 'Password' -Request $Request
```

#### `Remove-PSWebSession`

Deletes a session from both cache and database.

```powershell
Remove-PSWebSession -SessionID <string>
```

**Parameters:**
- `-SessionID`: Session GUID to delete

**Actions:**
1. Removes from `$global:PSWebSessions` cache
2. Deletes from `LoginSessions` database table

**Usage:**
```powershell
# Logout
Remove-PSWebSession -SessionID $sessionID
```

#### `Validate-UserSession`

Validates a session for security (expiration, UserAgent matching).

```powershell
Validate-UserSession -SessionData <hashtable> -Request <HttpListenerRequest>
```

**Parameters:**
- `-SessionData`: Session hashtable from `Get-PSWebSessions`
- `-Request`: Current HTTP request

**Returns:** `$true` if valid, `$false` otherwise

**Validation Checks:**
1. **Session Exists**: `$SessionData` is not null
2. **Not Expired**: `LastAccessed` within 30 minutes
3. **UserAgent Match**: Current request UserAgent == session UserAgent

**Security Note:** UserAgent validation prevents session hijacking.

**Usage:**
```powershell
$session = Get-PSWebSessions -SessionID $sessionID
if (Validate-UserSession -SessionData $session -Request $Request) {
    # Session is valid
} else {
    # Session invalid/expired
    Remove-PSWebSession -SessionID $sessionID
}
```

#### `Sync-SessionStateToDatabase`

Periodically synchronizes in-memory sessions to database.

```powershell
Sync-SessionStateToDatabase
```

**No parameters.** Intended to be called from a background job or timer.

**Actions:**
1. Iterates through `$global:PSWebSessions`
2. For each session, compresses data and writes to database
3. Updates `LastAccessed` timestamp

**Usage:**
```powershell
# In background job
while ($true) {
    Sync-SessionStateToDatabase
    Start-Sleep -Seconds 300  # Every 5 minutes
}
```

### Authorization

#### `Authorize-Request`

Checks if a session has required authorization for a route.

```powershell
Authorize-Request -SessionData <hashtable> -SecurityConfig <hashtable>
```

**Parameters:**
- `-SessionData`: Session hashtable
- `-SecurityConfig`: Hashtable from `.security.json`

**Returns:** `$true` if authorized, `$false` otherwise

**Security Config Format:**
```powershell
@{
    requiresAuth = $true
    requiredRoles = @("Admin", "Moderator")
}
```

**Authorization Logic:**
1. If `requiresAuth = $false`, return `$true` (public route)
2. If `requiresAuth = $true`, check session has UserID
3. If `requiredRoles` specified, check session.Roles contains at least one

**Usage:**
```powershell
$securityFile = Join-Path $routePath ".security.json"
if (Test-Path $securityFile) {
    $securityConfig = Get-Content $securityFile | ConvertFrom-Json
    $session = Get-PSWebSessions -SessionID $sessionID
    if (-not (Authorize-Request -SessionData $session -SecurityConfig $securityConfig)) {
        context_reponse -Response $Response -StatusCode 401 -String "Unauthorized"
        return
    }
}
```

### Logging and Events

#### `Write-PSWebHostLog`

Queues a log entry to the application log file.

```powershell
Write-PSWebHostLog -Severity <string> -Category <string> -Message <string> [-Data <hashtable>] [-WriteHost]
```

**Parameters:**
- `-Severity`: Log level (`Verbose`, `Information`, `Warning`, `Error`)
- `-Category`: Log category (`Auth`, `HTTP`, `Session`, `Database`, etc.)
- `-Message`: Log message
- `-Data`: Optional hashtable of structured data
- `-WriteHost`: If present, also writes to console

**Log Format:** Tab-separated values (TSV)
```
Date\tSeverity\tCategory\tMessage\tData(JSON)
```

**Log File:** `PsWebHost_Data/Logs/log.tsv`

**Usage:**
```powershell
Write-PSWebHostLog -Severity 'Warning' -Category 'Auth' -Message "Failed login attempt" -Data @{
    IPAddress = "192.168.1.100"
    Username = "user@example.com"
} -WriteHost
```

#### `Read-PSWebHostLog`

Reads and filters log entries from the log file.

```powershell
Read-PSWebHostLog [-Severity <string>] [-Category <string>] [-After <DateTime>] [-Before <DateTime>]
```

**Parameters:**
- `-Severity`: Filter by severity level
- `-Category`: Filter by category
- `-After`: Filter to entries after this date
- `-Before`: Filter to entries before this date

**Returns:** Array of log entry objects

**Usage:**
```powershell
# Get all errors from last hour
$errors = Read-PSWebHostLog -Severity 'Error' -After (Get-Date).AddHours(-1)

# Get all auth logs
$authLogs = Read-PSWebHostLog -Category 'Auth'
```

#### `Start-PSWebHostEvent`

Creates a new application event for tracking long-running operations.

```powershell
Start-PSWebHostEvent -Name <string> [-Data <hashtable>]
```

**Parameters:**
- `-Name`: Event name (e.g., "DatabaseBackup", "SessionSync")
- `-Data`: Optional metadata

**Returns:** Event object with EventID (GUID)

**Usage:**
```powershell
$event = Start-PSWebHostEvent -Name "DatabaseBackup" -Data @{ Tables = "Users,Roles" }
# ... perform operation ...
Complete-PSWebHostEvent -EventID $event.EventID -Status "Success"
```

#### `Complete-PSWebHostEvent`

Marks an event as completed with status and result.

```powershell
Complete-PSWebHostEvent -EventID <string> -Status <string> [-Result <hashtable>]
```

**Parameters:**
- `-EventID`: Event GUID from `Start-PSWebHostEvent`
- `-Status`: Completion status (`Success`, `Failure`, `Warning`)
- `-Result`: Optional result data

**Usage:**
```powershell
Complete-PSWebHostEvent -EventID $event.EventID -Status "Success" -Result @{
    RecordsProcessed = 1500
    Duration = "00:02:15"
}
```

#### `Get-PSWebHostEvents`

Retrieves application events from the event log.

```powershell
Get-PSWebHostEvents [-Name <string>] [-Status <string>] [-After <DateTime>]
```

**Parameters:**
- `-Name`: Filter by event name
- `-Status`: Filter by status
- `-After`: Filter to events after this date

**Returns:** Array of event objects

**Usage:**
```powershell
# Get all failed events
$failures = Get-PSWebHostEvents -Status "Failure"

# Get recent backup events
$backups = Get-PSWebHostEvents -Name "DatabaseBackup" -After (Get-Date).AddDays(-7)
```

#### `New-PSWebHostResult`

Creates a standardized result object for operations.

```powershell
New-PSWebHostResult -Success <bool> -Message <string> [-Data <object>]
```

**Parameters:**
- `-Success`: `$true` or `$false`
- `-Message`: Result message
- `-Data`: Optional result data

**Returns:** PSCustomObject with `Success`, `Message`, `Data` properties

**Usage:**
```powershell
if ($user) {
    return New-PSWebHostResult -Success $true -Message "User found" -Data $user
} else {
    return New-PSWebHostResult -Success $false -Message "User not found"
}
```

### Utility Functions

#### `ConvertTo-CompressedBase64`

Compresses a string using GZip and Base64 encodes it.

```powershell
ConvertTo-CompressedBase64 -InputString <string>
```

**Parameters:**
- `-InputString`: String to compress

**Returns:** Base64-encoded compressed string

**Usage:**
```powershell
$sessionData = @{ UserID = "guid"; Roles = @("Admin") } | ConvertTo-Json
$compressed = ConvertTo-CompressedBase64 -InputString $sessionData
# Store $compressed in database (much smaller than original JSON)
```

**Compression Ratio:** Typically 70-90% reduction for JSON data

## Dependencies

### Required PowerShell Modules
- None (uses built-in .NET classes)

### Required .NET Assemblies
- `System.Net` - HttpListener classes
- `System.IO` - StreamReader, FileStream
- `System.IO.Compression` - GZipStream
- `System.Web` - HttpUtility for query string parsing

### Database Tables Used
- `LoginSessions` - Session persistence
- `PSWeb_Events` - Application event log (if implemented)

## Configuration

### Session Settings

**Session Timeout:** 30 minutes (configurable in `Validate-UserSession`)
**Cookie Expiration:** 7 days (configurable in `Ensure-SessionCookie`)
**In-Memory Cache:** Unlimited size (uses synchronized hashtable)

### Logging Settings

**Log File:** `PsWebHost_Data/Logs/log.tsv`
**Log Rotation:** Not implemented (manual cleanup required)
**Log Levels:** Verbose, Information, Warning, Error

## Security Considerations

1. **HttpOnly Cookies**: Session cookies marked HttpOnly prevent XSS attacks
2. **Secure Cookies**: Set for HTTPS connections
3. **UserAgent Validation**: Prevents session hijacking
4. **Session Timeout**: 30-minute inactivity timeout
5. **Route Authorization**: `.security.json` controls access
6. **Input Validation**: Use with authentication module's validation functions

## Performance Optimizations

1. **In-Memory Session Cache**: Avoids database queries for every request
2. **Session Compression**: GZip compression reduces database storage
3. **Synchronized Hashtable**: Thread-safe for concurrent requests
4. **Static File Caching**: Browser caching enabled for public files

## Usage Examples

### Complete Request Handling

```powershell
# In WebHost.ps1 listener loop
$context = $listener.GetContext()
Process-HttpRequest -Context $context
```

### Custom Route Script

```powershell
# routes/api/v1/data/get.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

# Get session
$sessionID = $Request.Cookies["PSWebSessionID"].Value
$session = Get-PSWebSessions -SessionID $sessionID

# Validate
if (-not (Validate-UserSession -SessionData $session -Request $Request)) {
    context_reponse -Response $Response -StatusCode 401 -String "Session expired"
    return
}

# Get data
$data = Get-Data -UserID $session.UserID

# Send response
$jsonData = $data | ConvertTo-Json
context_reponse -Response $Response -StatusCode 200 -String $jsonData -ContentType "application/json"
```

### Background Session Sync

```powershell
# Start background job
$syncJob = Start-Job -ScriptBlock {
    Import-Module PSWebHost_Support
    while ($true) {
        Sync-SessionStateToDatabase
        Start-Sleep -Seconds 300  # Every 5 minutes
    }
}
```

## Troubleshooting

### Sessions Not Persisting

**Symptom:** Users logged out after page refresh

**Causes:**
1. Cookie domain mismatch
2. Session timeout too short
3. UserAgent changes between requests

**Debug:**
```powershell
$session = Get-PSWebSessions -SessionID $sessionID
Write-Host "Session exists: $($null -ne $session)"
Write-Host "LastAccessed: $($session.LastAccessed)"
Write-Host "UserAgent match: $($session.UserAgent -eq $Request.UserAgent)"
```

### Static Files Not Serving

**Symptom:** 404 for CSS/JS files

**Cause:** Files not in `/public` directory

**Solution:** Move static assets to `{ProjectRoot}/public/`

### Memory Usage Growing

**Symptom:** PowerShell process memory increases over time

**Cause:** In-memory session cache never cleared

**Solution:** Implement session cleanup:
```powershell
# Remove expired sessions from cache
$now = Get-Date
$global:PSWebSessions.Keys | Where-Object {
    $session = $global:PSWebSessions[$_]
    ($now - $session.LastAccessed).TotalMinutes -gt 30
} | ForEach-Object {
    $global:PSWebSessions.Remove($_)
}
```

## Related Files

- `WebHost.ps1` - Main entry point that uses `Process-HttpRequest`
- `modules/PSWebHost_Database/PSWebHost_Database.psm1` - Database access
- `modules/PSWebHost_Authentication/PSWebHost_Authentication.psm1` - Authentication
- `routes/**/*.ps1` - Route handler scripts
- `public/**/*` - Static web assets

## See Also

- Request processing: modules/PSWebHost_Support/PSWebHost_Support.psm1:334
- Session validation: modules/PSWebHost_Support/PSWebHost_Support.psm1:283
- Authorization: modules/PSWebHost_Support/PSWebHost_Support.psm1:117
- Logging: modules/PSWebHost_Support/PSWebHost_Support.psm1:562
