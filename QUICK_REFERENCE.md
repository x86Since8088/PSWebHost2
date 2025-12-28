# PsWebHost Quick Reference Card

## 🚀 Getting Started

### Start the Server
```powershell
cd e:\sc\git\PsWebHost
.\WebHost.ps1 -Port 8080 -Async
```

### Configuration
```powershell
# Edit settings
notepad config/settings.json

# Enable debug logging for /api/v1/auth
{
  "debug_url": {
    "/api/v1/auth": {
      "VerbosePreference": "Continue"
    }
  }
}
```

---

## 🔐 Authentication Flow (5 Steps)

```
1. GET /api/v1/auth/getauthtoken
   └─ Display login form

2. POST /api/v1/auth/getauthtoken
   └─ Submit email → Show auth methods

3. POST /api/v1/authprovider/password
   └─ Submit credentials → Validate

4. GET /api/v1/auth/getaccesstoken
   └─ Issue token (disabled)

5. GET /api/v1/auth/sessionid
   └─ Check session
```

---

## 📁 Key File Locations

| Component | Location |
|-----------|----------|
| Main Server | `WebHost.ps1` |
| Route Handlers | `routes/api/v1/` |
| Modules | `modules/` |
| Static Files | `public/` |
| Config | `config/settings.json` |
| Logs | `PsWebHost_Data/Logs/` |
| Database | `PsWebHost_Data/pswebhost.db` |

---

## 🔧 Core Functions

### HTTP Handling
| Function | Purpose |
|----------|---------|
| `Process-HttpRequest` | Route dispatcher |
| `context_reponse` | Send HTTP response |
| `Get-RequestBody` | Extract POST data |

### Authentication
| Function | Purpose |
|----------|---------|
| `Invoke-AuthenticationMethod` | Authenticate user |
| `Set-PSWebSession` | Create session |
| `Test-LoginLockout` | Check brute force |

### Logging
| Function | Purpose |
|----------|---------|
| `Write-PSWebHostLog` | Log to queue |
| `New-PSWebHostResult` | Standardized error object |
| `PSWebLogon` | Log auth events |

---

## 📊 HTTP Status Codes

| Code | Meaning | Example |
|------|---------|---------|
| 200 | OK | GET successful |
| 302 | Redirect | Auth success |
| 400 | Bad Request | Invalid email |
| 401 | Unauthorized | Wrong password |
| 404 | Not Found | Unknown route |
| 429 | Too Many Requests | Lockout active |
| 500 | Server Error | Exception thrown |

---

## 🧪 Testing Commands

### Test Login Form
```bash
curl http://localhost:8080/api/v1/auth/getauthtoken/get
```

### Submit Email
```bash
curl -X POST http://localhost:8080/api/v1/auth/getauthtoken/post \
  -d "email=user@example.com&password=TestPassword123"
```

### Check Session
```bash
curl http://localhost:8080/api/v1/auth/sessionid/get \
  -H "Cookie: PSWebSessionID=<guid>"
```

### Authenticate
```bash
curl -X POST http://localhost:8080/api/v1/authprovider/password/post \
  -d "username=user@example.com&password=TestPassword123" \
  -H "Cookie: PSWebSessionID=<guid>"
```

---

## 🛡️ Security Features

| Feature | Implementation |
|---------|-----------------|
| Session Security | HttpOnly, Secure, 7-day expiry |
| Input Validation | Email, password, file paths |
| Brute Force | Login lockout (IP + username) |
| Authorization | RBAC via .security.json files |
| Logging | Comprehensive audit trail |

---

## 📝 Creating New Routes

### 1. Create Handler File
```powershell
# routes/api/v1/myfeature/get.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $SessionData
)

# Your logic here
context_reponse -Response $Response -StatusCode 200 -String "Hello"
```

### 2. Auto-Created Security File
```json
{
  "Allowed_Roles": ["unauthenticated"]
}
```

---

## 📚 Documentation

| File | Purpose |
|------|---------|
| `AUTHENTICATION_ARCHITECTURE.md` | Complete auth system trace |
| `DOCUMENTATION_INDEX.md` | Documentation guide |
| `SESSION_SUMMARY.md` | This session summary |
| `COMPLETION_REPORT.md` | Project completion report |
| `MODULES_REVIEW.md` | Module compliance review |

---

## ⚙️ Error Handling Pattern

```powershell
# ✅ CORRECT - Safe pattern
$result = Command -ErrorAction SilentlyContinue -ErrorVariable err
if ($err) {
    Write-PSWebHostLog -Severity 'Error' -Message "Command failed: $err"
    context_reponse -Response $Response -StatusCode 500 -String "Error"
    return
}

# ❌ WRONG - Throws exceptions
$result = Command -ErrorAction Stop  # DON'T USE

# ❌ WRONG - Unhandled exceptions
try { $result = Command }  # DON'T USE without proper error handling
```

---

## 🐛 Troubleshooting

### Server Won't Start
```powershell
# Check port already in use
netstat -ano | findstr :8080

# Check HttpListener exception
Get-EventLog -LogName System -Source "PowerShell" -Newest 10
```

### Authentication Failing
```powershell
# Enable verbose logging
# Edit config/settings.json and restart

# Check auth logs
Get-ChildItem PsWebHost_Data/Logs | Select-Object -Last 5 | Select-Object FullName
```

### Module Import Errors
```powershell
# Re-load modules manually
Get-Module | Remove-Module
& system/init.ps1
```

---

## 📋 Module Dependencies

```
WebHost.ps1
├─ PSWebHost_Support (core routing/sessions)
├─ PSWebHost_Authentication (user/auth logic)
├─ PSWebHost_Database (persistence)
├─ PSWebHost_Formatters (data conversion)
├─ Sanitization (input validation)
└─ smtp (email service)
```

---

## 🔐 Authentication Providers

| Provider | Status | Files |
|----------|--------|-------|
| Password | ✅ Ready | `authprovider/password/` |
| Windows | ✅ Ready | `authprovider/windows/` |
| Google | ⚠️ Partial | `authprovider/google/` |
| O365 | ⚠️ Partial | `authprovider/o365/` |
| Entra ID | ⚠️ Partial | `authprovider/entraid/` |
| Certificate | ⚠️ Partial | `authprovider/certificate/` |
| YubiKey | ⚠️ Partial | `authprovider/yubikey/` |

---

## 📊 Session Object Structure

```powershell
$session = @{
    SessionID = "guid-string"
    UserID = "user@example.com"  # null if not authenticated
    Roles = @("user", "admin")
    Provider = "Password"         # Auth provider used
    IsAuthenticated = $true
    CreatedAt = [DateTime]
    LastActivity = [DateTime]
    Runspaces = @{}              # Async runspace tracking
}
```

---

## 🚦 Route Resolution Algorithm

```
1. Extract requested path: /api/v1/auth/getauthtoken
2. Extract HTTP method: get, post, put, delete
3. Resolve file: routes/api/v1/auth/getauthtoken/{method}.ps1
4. Load security config: routes/api/v1/auth/getauthtoken/{method}.security.json
5. Check user roles against Allowed_Roles
6. If authorized: invoke handler
7. If not: return 401 Unauthorized
```

---

## 📞 Common Issues

| Problem | Solution |
|---------|----------|
| Port already in use | Change port or kill existing process |
| Session not persisting | Check database: `PsWebHost_Data/pswebhost.db` |
| Auth provider failing | Check module imports in `system/init.ps1` |
| Verbose output missing | Enable in `config/settings.json` `debug_url` |
| Static files not loading | Check path in `/public/` directory |

---

## 💡 Tips & Tricks

1. **Hot Module Reloading:** Modules reload automatically every 30 seconds
2. **Settings Reloading:** Config reloads every 30 seconds
3. **Session Persistence:** Syncs to database every 1 minute
4. **Async Processing:** Enable `-Async` for production
5. **Debug Endpoints:** Configure per-URL in `config/settings.json`

---

## 📖 Learn More

- Full architecture: `AUTHENTICATION_ARCHITECTURE.md`
- Project overview: `README.md`
- Settings reference: `config/settings.json.md`
- All documentation: `DOCUMENTATION_INDEX.md`

---

**PsWebHost v1.0 - Quick Reference | Last Updated: 2024**
