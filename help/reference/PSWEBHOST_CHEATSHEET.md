# PSWebHost Development Cheat Sheet

**Last Updated:** 2026-02-01
**Purpose:** Essential patterns and configurations for PSWebHost development

---

## Security Configuration Format

### Endpoint Security Files: `[method].security.json`

**Location:** `routes/api/v1/*/[method].security.json`

**Correct Format:**
```json
{
  "RequireAuthentication": true,
  "AllowAnonymous": false,
  "RequiredRoles": ["user", "admin", "debug", "system_admin"]
}
```

**Common Mistakes:**
- ❌ `"RequireAuth"` - WRONG property name
- ❌ `"Allowed_Roles"` - WRONG property name
- ✅ `"RequireAuthentication"` - CORRECT
- ✅ `"RequiredRoles"` - CORRECT

---

## Card Architecture

### Two-Tier System

1. **Metadata Endpoint** - Returns card configuration
   - Path: `/api/v1/ui/elements/[card-name]/get.ps1`
   - Returns: JSON metadata (NOT HTML)
   - Purpose: Card loader fetches this to know how to load the card

2. **Data Endpoints** - Return actual data
   - Path: `/api/v1/[resource]/[method].ps1`
   - Returns: JSON data
   - Purpose: Card components call these to get/update data

### Metadata Endpoint Pattern

**Correct Format (RETURN JSON, NOT HTML):**
```powershell
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'card-name'
        scriptPath = '/public/elements/card-name/component.js'
        stylePath = '/public/elements/card-name/style.css'
        title = 'Card Title'
        description = 'Card description'
        version = '1.0.0'
        width = 12
        height = 8
        features = @(
            'Feature 1'
            'Feature 2'
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'CardName' -Message "Error loading card: $($_.Exception.Message)"

    $errorResponse = @{
        error = $_.Exception.Message
        stackTrace = $_.ScriptStackTrace
    }

    context_response -Response $Response -StatusCode 500 -String ($errorResponse | ConvertTo-Json) -ContentType "application/json"
}
```

**Common Mistake:**
- ❌ Returning full HTML page with embedded component
- ✅ Returning JSON metadata only

---

## Authentication Patterns

### Browser/Session Authentication (Most Common)

**Client-Side:**
```javascript
const response = await window.psweb_fetchWithAuthHandling('/api/v1/resource');
```

**Server-Side:**
- Authentication handled automatically via `$sessiondata` parameter
- Roles checked against `[method].security.json`

### API Key Authentication (External/Automation)

**Client-Side:**
```javascript
const response = await fetch('/api/v1/resource', {
    headers: {
        'Authorization': `Bearer ${apiKey}`
    }
});
```

**When to Use:**
- External applications
- Automation scripts
- NOT for browser-based cards

---

## React Component Registration

**Location:** `public/elements/[card-name]/component.js`

**Pattern:**
```javascript
const { useState, useEffect } = React;

const CardName = () => {
    // Component implementation
    return React.createElement('div', { className: 'card-name' },
        // Component content
    );
};

// MUST register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['card-name'] = CardName;
```

**Common Issues:**
- Component not registered in `window.cardComponents`
- Component name mismatch with metadata `component` field
- Missing React destructuring

---

## File Structure

### App Directory Structure
```
apps/[AppName]/
├── app.yaml                    # App manifest
├── app_init.ps1               # Initialization script
├── menu.yaml                  # Menu configuration
├── routes/
│   └── api/v1/
│       └── [resource]/
│           ├── get.ps1
│           ├── get.security.json
│           ├── post.ps1
│           └── post.security.json
├── public/
│   └── elements/
│       └── [card-name]/
│           ├── component.js
│           └── style.css
└── modules/
    └── [ModuleName]/
        ├── [ModuleName].psd1
        └── [ModuleName].psm1
```

### Core System Paths
- **Project Root:** `C:\SC\PsWebHost\`
- **Data Root:** `C:\SC\PsWebHost\PsWebHost_Data\`
- **Logs:** `C:\SC\PsWebHost\PsWebHost_Data\Logs\`
- **Database:** `C:\SC\PsWebHost\PsWebHost_Data\psweb.db`
- **Apps:** `C:\SC\PsWebHost\apps\`
- **Modules:** `C:\SC\PsWebHost\modules\`

---

## Common PowerShell Patterns

### Response Helper
```powershell
# Success response
context_response -Response $Response -String ($data | ConvertTo-Json) -ContentType "application/json"

# Error response
context_response -Response $Response -StatusCode 500 -String ($error | ConvertTo-Json) -ContentType "application/json"
```

### Logging
```powershell
Write-PSWebHostLog -Severity 'Info' -Category 'CategoryName' -Message "Log message"
Write-PSWebHostLog -Severity 'Error' -Category 'CategoryName' -Message "Error: $($_.Exception.Message)"
Write-PSWebHostLog -Severity 'Warning' -Category 'CategoryName' -Message "Warning message"
```

### Session Data Access
```powershell
param($sessiondata)

# User information
$userId = $sessiondata.User.UserID
$username = $sessiondata.User.Username
$roles = $sessiondata.User.Roles
```

---

## Client-Side Utilities

### Available Functions

```javascript
// Authenticated fetch (uses session cookies)
window.psweb_fetchWithAuthHandling(url)

// Client-side logging to server (batched, 15-second intervals)
window.logToServer(message, severity)
// Severities: 'debug', 'info', 'warn', 'error'
// Endpoint: /api/v1/debug/client-log

// Card management
window.addCard(cardName, config)
window.removeCard(cardId)
```

---

## Testing & Debugging

### Server Commands
```powershell
# Start server
pwsh -File C:\SC\PsWebHost\WebHost.ps1

# Stop server (from PowerShell)
Get-Process -Name pwsh | Where-Object { $_.CommandLine -like "*WebHost.ps1*" } | Stop-Process -Force

# Check port 8080
Test-NetConnection -ComputerName localhost -Port 8080
```

### Log Analysis
```powershell
# View recent logs
Get-Content "C:\SC\PsWebHost\PsWebHost_Data\Logs\log_*.tsv" | Select-Object -Last 50

# Filter by category
Get-Content "C:\SC\PsWebHost\PsWebHost_Data\Logs\log_*.tsv" | Select-String "Error"

# Filter by specific card
Get-Content "C:\SC\PsWebHost\PsWebHost_Data\Logs\log_*.tsv" | Select-String "memory-explorer"
```

### Common Error Codes
- **401 Unauthorized** - Authentication failure (check security.json and session)
- **403 Forbidden** - Role/permission issue
- **404 Not Found** - Endpoint doesn't exist or route not registered
- **500 Internal Server Error** - Server-side exception

---

## Common Issues & Solutions

### Issue: Card returns 401 Unauthorized
**Causes:**
1. Wrong security.json property names (`RequireAuth` instead of `RequireAuthentication`)
2. Wrong role property (`Allowed_Roles` instead of `RequiredRoles`)
3. Card using API key auth instead of session auth

**Solution:**
1. Fix security.json format
2. Use `window.psweb_fetchWithAuthHandling()` in client code
3. Restart server to reload security configuration

### Issue: Card shows "Component not found"
**Causes:**
1. Metadata endpoint returning HTML instead of JSON
2. `scriptPath` or `stylePath` incorrect
3. Component not registered in `window.cardComponents`

**Solution:**
1. Verify metadata endpoint returns JSON (not HTML)
2. Check paths match actual file locations
3. Ensure component registration at end of JS file

### Issue: Duplicate React keys warning
**Causes:**
1. Same card loaded multiple times
2. Card ID generation collision

**Solution:**
1. Check card isn't duplicated in menu configuration
2. Review card key generation logic

### Issue: Component timeout after 5000ms
**Causes:**
1. Component JS has syntax error
2. Component never calls React.createElement
3. scriptPath points to non-existent file

**Solution:**
1. Check browser console for JS errors
2. Verify component implementation
3. Confirm file exists at scriptPath

---

## Server Configuration

### Port Configuration
- **Default HTTP Port:** 8080
- **HTTPS Support:** Configurable in WebHost.ps1

### Admin Session Notes
- Running as admin allows HTTP.SYS URL ACL management
- Use `netsh http show urlacl` to view reservations
- Use `netsh http delete urlacl url=http://+:8080/` to clean up

---

## Database Schema

### Common Tables
- **Users** - User accounts
- **LoginSessions** - Active sessions
- **PSWeb_Roles** - Role definitions
- **User_Groups** - User group membership
- **API_Keys** - API authentication tokens
- **CardSessions** - Card state persistence

---

## Module System

### Hot Reload Pattern
```powershell
# In app_init.ps1
Import-Module "$appRoot\modules\ModuleName" -Force -Global

# The -Force flag enables hot reload during development
```

### Module Discovery
- Modules in `C:\SC\PsWebHost\modules\` are auto-added to PSModulePath
- App-specific modules in `apps\[AppName]\modules\`

---

## Known Working Cards

1. **apps-manager** - Fixed authentication, returns JSON metadata
2. **memory-explorer** - Fixed authentication, returns JSON metadata
3. **file-explorer** - Working with session auth
4. **task-manager** - Working
5. **debug-console** - Working
6. **help-viewer** - Working

## Known Issues

1. **unit-test-runner** - Has 500 error (not yet investigated)
   - Component uses `customElements.define` instead of `window.cardComponents`
2. **iframe-card** - Missing scriptPath architectural issue
   - Built-in component in psweb_spa.js, no separate metadata endpoint
3. **Component timeouts** - Some cards timeout after 5000ms
4. **Duplicate React keys** - Warning about duplicate key instances
5. Multiple app_init.ps1 warnings about null DataRoot paths

---

## Quick Reference

### When Adding a New Card

1. Create metadata endpoint: `routes/api/v1/ui/elements/[name]/get.ps1` (returns JSON)
2. Create security file: `routes/api/v1/ui/elements/[name]/get.security.json`
3. Create component: `public/elements/[name]/component.js` (register in window.cardComponents)
4. Create styles: `public/elements/[name]/style.css`
5. Create data endpoints as needed: `routes/api/v1/[resource]/[method].ps1`
6. Test authentication with browser tools
7. Restart server to pick up changes

### When Fixing Authentication

1. Check security.json uses correct property names
2. Verify client uses `window.psweb_fetchWithAuthHandling()`
3. Confirm metadata endpoint returns JSON, not HTML
4. Restart server after changes

---

## End of Cheat Sheet
