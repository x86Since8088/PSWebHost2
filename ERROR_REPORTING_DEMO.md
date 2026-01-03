# Error Reporting System - Role-Based Response Examples

## Overview
The `Get-PSWebHostErrorReport` function provides three levels of error detail based on user roles:
1. **Admin/Debug Users** - Full diagnostic information
2. **Localhost Non-Admin** - Basic error with guidance
3. **Remote Users** - Minimal error for security

## Example Scenario
**Endpoint**: `/api/v1/ui/elements/system-log`
**Error**: Variable name collision (`$response` vs `$Response`)
**Request**: `GET /api/v1/ui/elements/system-log?lines=100`

---

## Response Level 1: Admin/Debug User (Full Diagnostics)

**User Roles**: `Admin`, `Debug`, `site_admin`, or `system_admin`

```json
{
  "timestamp": "2026-01-03T01:00:00.0000000Z",
  "userID": "6ec71a85-fb79-4ebc-aa1d-587c7f8b403c",
  "roles": ["authenticated", "site_admin"],
  "request": {
    "Method": "GET",
    "URL": "http://localhost:8080/api/v1/ui/elements/system-log?lines=100",
    "RawUrl": "/api/v1/ui/elements/system-log?lines=100",
    "QueryString": {
      "lines": "100"
    },
    "Headers": {
      "Host": "localhost:8080",
      "User-Agent": "Mozilla/5.0...",
      "Accept": "application/json",
      "Cookie": "PSWebSessionID=..."
    },
    "RequestBody": null
  },
  "error": {
    "Message": "Cannot convert the \"System.Collections.Hashtable\" value of type \"System.Collections.Hashtable\" to type \"System.Net.HttpListenerResponse\".",
    "Type": "System.Management.Automation.RuntimeException",
    "StackTrace": "at System.Management.Automation.ExceptionHandlingOps.CheckActionPreference...",
    "PositionMessage": "At C:\\sc\\PsWebHost\\routes\\api\\v1\\ui\\elements\\system-log\\get.ps1:44 char:22\n+ … ogFiles = @($logFiles | Select-Object Name, LastWriteTime, @{N='Size' …\n+               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  },
  "callStack": [
    {
      "Command": "<ScriptBlock>",
      "Location": "get.ps1: line 44",
      "ScriptName": "C:\\sc\\PsWebHost\\routes\\api\\v1\\ui\\elements\\system-log\\get.ps1",
      "ScriptLineNumber": 44,
      "FunctionName": "<ScriptBlock>"
    },
    {
      "Command": "<ScriptBlock>",
      "Location": "WebHost.ps1: line 256",
      "ScriptName": "C:\\sc\\PsWebHost\\WebHost.ps1",
      "ScriptLineNumber": 256,
      "FunctionName": "<ScriptBlock>"
    }
  ],
  "variables": {
    "logsDir": "C:\\SC\\PsWebHost\\PsWebHost_Data\\Logs",
    "currentLogFile": "C:\\SC\\PsWebHost\\PsWebHost_Data\\Logs\\log_2026-01-01T052250_1205918-0600.tsv",
    "lines": 100,
    "filter": "$null",
    "logFiles": "[Array with 18 items]",
    "responseData": "[Hashtable with 3 entries]"
  }
}
```

**Key Features**:
- ✅ Complete call stack with file paths and line numbers
- ✅ All variables in scope at the time of error
- ✅ Full request details including headers
- ✅ Request body (for POST/PUT/PATCH)
- ✅ Detailed error information

---

## Response Level 2: Localhost User (Basic Error + Guidance)

**Access**: From `localhost` (127.0.0.1, ::1) without Admin/Debug role

```json
{
  "timestamp": "2026-01-03T01:00:00.0000000Z",
  "error": {
    "message": "Cannot convert the \"System.Collections.Hashtable\" value of type \"System.Collections.Hashtable\" to type \"System.Net.HttpListenerResponse\".",
    "type": "System.Management.Automation.RuntimeException",
    "position": "At C:\\sc\\PsWebHost\\routes\\api\\v1\\ui\\elements\\system-log\\get.ps1:44 char:22\n+ … ogFiles = @($logFiles | Select-Object Name, LastWriteTime, @{N='Size' …\n+               ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
  },
  "request": {
    "method": "GET",
    "url": "http://localhost:8080/api/v1/ui/elements/system-log?lines=100"
  },
  "guidance": "You are accessing from localhost. For detailed diagnostics including call stack and variable enumeration, please use an account with Admin or Debug role."
}
```

**Key Features**:
- ✅ Error message and type
- ✅ Error position in code
- ✅ Basic request info
- ✅ Helpful guidance to get more details
- ❌ No call stack
- ❌ No variables
- ❌ No headers

---

## Response Level 3: Remote User (Minimal Error)

**Access**: From remote IP address without Admin/Debug role

```json
{
  "timestamp": "2026-01-03T01:00:00.0000000Z",
  "error": "An internal error occurred. Please contact the administrator.",
  "requestId": "a7f3e9d1-4b2c-4a8e-9f1d-3e7b9c2d8f1a"
}
```

**Key Features**:
- ✅ Generic error message
- ✅ Timestamp
- ✅ Request ID for correlation
- ❌ No technical details
- ❌ No stack traces
- ❌ No variable information

**Security**: Prevents information disclosure to potential attackers

---

## Testing the Error Reporting

### Method 1: Check Browser Console (Current Implementation)
The client-side logging is already capturing errors:

```javascript
// Error automatically logged from browser
window.logToServer('Error', 'system-log', 'Failed to fetch log', {
    elementId: 'system-log',
    status: 500,
    statusText: 'Internal Server Error'
});
```

### Method 2: Trigger a Test Error
Access the test endpoint (requires authentication):
```
GET http://localhost:8080/api/v1/debug/test-error
GET http://localhost:8080/api/v1/debug/test-error?type=division
GET http://localhost:8080/api/v1/debug/test-error?type=null
GET http://localhost:8080/api/v1/debug/test-error?type=file
```

### Method 3: Check Server Logs
Errors are logged to the server regardless of response level:
```powershell
Get-Content "C:\SC\PsWebHost\PsWebHost_Data\Logs\log_*.tsv" |
    Where-Object { $_ -match "Error" } |
    Select-Object -Last 10
```

---

## Updated Endpoints (11 total)

All these endpoints now use `Get-PSWebHostErrorReport`:

### Debug APIs
- `/api/v1/debug/var` - Variable inspection
- `/api/v1/debug/vars` - Variable listing
- `/api/v1/debug/client-log` - Client error logging

### UI Elements
- `/api/v1/ui/elements/system-log` - System logs
- `/api/v1/ui/elements/job-status` - Background jobs
- `/api/v1/ui/elements/file-explorer` (GET & POST) - File operations
- `/api/v1/ui/elements/server-heatmap` - System metrics
- `/api/v1/ui/elements/event-stream` - Event log

### Authentication
- `/api/v1/authprovider/password` - Password login
- `/api/v1/authprovider/windows` - Windows auth

---

## Benefits

### For Developers (Admin/Debug Role)
- **Instant Diagnostics**: See exactly what went wrong, where, and why
- **Variable State**: Know the values of all variables at error time
- **Call Stack**: Trace the execution path leading to the error
- **Request Context**: Full details of what was requested

### For Users (Localhost)
- **Clear Guidance**: Told how to get more information
- **Basic Context**: Enough info to report the issue
- **Privacy**: Sensitive data not exposed in basic view

### For Security (Remote)
- **Information Hiding**: No technical details leaked
- **Attack Prevention**: Stack traces can't be used for reconnaissance
- **Traceability**: Request IDs for support escalation

---

## Implementation Pattern

All endpoints now follow this pattern:

```powershell
try {
    # Endpoint logic here

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CategoryName' -Message "Error description: $($_.Exception.Message)"

    # Generate role-based error report
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
```

## Next Steps

1. **Create Admin/Debug Role**: Assign yourself Admin or Debug role to see full diagnostics
2. **Test in Browser**: Navigate to http://localhost:8080/spa and try loading components
3. **Review Errors**: Check browser console and server logs for captured errors
4. **Apply to More Endpoints**: Standardize error handling across remaining endpoints
