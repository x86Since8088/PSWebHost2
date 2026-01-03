# Error Modal System - Complete Implementation

## Overview

The PSWebHost error modal system provides **role-based error reporting** with **automatic modal display** in the frontend. When backend endpoints encounter errors, they can now instruct the frontend to display a beautifully formatted modal with appropriate detail level based on user access.

## Architecture

```
┌─────────────────┐
│  User Action    │
│  (API Request)  │
└────────┬────────┘
         │
         ↓
┌─────────────────────────────────┐
│  Backend Endpoint               │
│  ┌─────────────────────────┐   │
│  │  try {                   │   │
│  │    // endpoint logic     │   │
│  │  } catch {               │   │
│  │    $Report =             │   │
│  │      Get-PSWebHostError  │   │
│  │      Report(...)         │   │
│  │  }                       │   │
│  └─────────────────────────┘   │
└────────┬────────────────────────┘
         │
         ↓
┌──────────────────────────────────┐
│  Error Report Generated          │
│  {                               │
│    showModal: true,              │
│    modalTitle: "...",            │
│    modalType: "error-admin",     │
│    error: {...},                 │
│    callStack: [...],             │
│    variables: {...}              │
│  }                               │
└────────┬─────────────────────────┘
         │
         ↓
┌──────────────────────────────────┐
│  Frontend (psweb_spa.js)         │
│  ┌────────────────────────────┐ │
│  │  fetch(url)                │ │
│  │    .then(response =>       │ │
│  │      if (!response.ok) {   │ │
│  │        const data =        │ │
│  │          response.json()   │ │
│  │        if (data.showModal) │ │
│  │          showErrorModal()  │ │
│  │      }                     │ │
│  │    )                       │ │
│  └────────────────────────────┘ │
└────────┬─────────────────────────┘
         │
         ↓
┌──────────────────────────────────┐
│  Beautiful Modal Displayed       │
│  ┌────────────────────────────┐ │
│  │  Error Report (Admin)      │ │
│  │  ──────────────────────    │ │
│  │  Error Details             │ │
│  │  Call Stack                │ │
│  │  Variables                 │ │
│  │  Request Info              │ │
│  │                            │ │
│  │  [Close]                   │ │
│  └────────────────────────────┘ │
└──────────────────────────────────┘
```

## Backend Implementation

### Function: `Get-PSWebHostErrorReport`

**Location**: `C:\SC\PsWebHost\system\Functions.ps1:99-321`

**Usage in Endpoints**:
```powershell
try {
    # Your endpoint logic here

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'YourCategory' `
        -Message "Error description: $($_.Exception.Message)"

    # Generate role-based error report with modal instruction
    $Report = Get-PSWebHostErrorReport `
        -ErrorRecord $_ `
        -Context $Context `
        -Request $Request `
        -sessiondata $sessiondata

    context_reponse -Response $Response `
        -StatusCode $Report.statusCode `
        -String $Report.body `
        -ContentType $Report.contentType
}
```

### Response Structure

The function automatically adds these fields to error responses:

```json
{
  "showModal": true,
  "modalTitle": "Error Report (Admin)" | "Error Occurred" | "Error",
  "modalType": "error-admin" | "error-basic" | "error-minimal",
  // ... rest of error details based on user role
}
```

## Frontend Implementation

### Modal Component

**Location**: `C:\SC\PsWebHost\public\psweb_spa.js:50-419`

**Key Features**:
- React-based modal component
- Three distinct presentation styles
- Responsive design
- Smooth animations
- Accessible (keyboard & screen reader friendly)
- Auto-cleanup on close

### Automatic Detection

**Location**: `C:\SC\PsWebHost\public\psweb_spa.js:4-29`

The `psweb_fetchWithAuthHandling` function automatically:
1. Detects non-OK responses (status >= 400)
2. Checks if response contains `showModal: true`
3. Parses the error data
4. Displays the appropriate modal

```javascript
// Automatically integrated - no changes needed to component code
async function psweb_fetchWithAuthHandling(url, options) {
    const response = await fetch(url, options);

    if (!response.ok && response.status >= 400) {
        const errorData = await response.clone().json();
        if (errorData.showModal) {
            window.showErrorModal(errorData);
        }
    }

    return response;
}
```

## Modal Types

### 1. Admin/Debug Modal (`error-admin`)

**Triggers**: User has `Admin`, `Debug`, `site_admin`, or `system_admin` role

**Displays**:
- ✅ Full error message and exception type
- ✅ Code position (file, line, column)
- ✅ Complete call stack with file paths
- ✅ All variables in scope (name and value)
- ✅ Request details (method, URL, query params)
- ✅ HTTP headers
- ✅ Request body (POST/PUT/PATCH)
- ✅ User ID and roles
- ✅ Timestamp

**Visual Style**: Red header, expandable sections, syntax-highlighted code blocks

### 2. Basic Modal (`error-basic`)

**Triggers**: User accessing from localhost without admin privileges

**Displays**:
- ✅ Error message
- ✅ Exception type
- ✅ Code position
- ✅ Basic request info (method, URL)
- ✅ Helpful guidance message
- ✅ Timestamp

**Visual Style**: Red header, blue guidance box, friendly messaging

### 3. Minimal Modal (`error-minimal`)

**Triggers**: User accessing from remote IP without admin privileges

**Displays**:
- ✅ Generic error message
- ✅ Request ID
- ✅ Timestamp

**Visual Style**: Red header, minimal content, focused on user action

## Testing the System

### Option 1: Demo Page
Open in browser:
```
http://localhost:8080/public/error-modal-demo.html
```

Features:
- Test all three modal types
- See sample data
- Trigger real errors
- Interactive demonstration

### Option 2: SPA Components
1. Open http://localhost:8080/spa
2. Try loading components (System Log, File Explorer, etc.)
3. Errors will automatically display modals

### Option 3: Direct API Call
```bash
# Trigger test error
curl http://localhost:8080/api/v1/debug/test-error

# With different error types
curl http://localhost:8080/api/v1/debug/test-error?type=division
curl http://localhost:8080/api/v1/debug/test-error?type=null
curl http://localhost:8080/api/v1/debug/test-error?type=file
```

## Customization

### Custom Modal Titles
```powershell
# In your error handler
$Report = Get-PSWebHostErrorReport -ErrorRecord $_ ...
# Backend automatically sets modalTitle based on access level
```

### Custom Error Categories
```powershell
Write-PSWebHostLog -Severity 'Error' -Category 'CustomCategory' ...
```

### Styling
Edit the CSS in `public/psweb_spa.js:212-418` to customize:
- Colors
- Fonts
- Spacing
- Animations
- Layout

## Benefits

### For Developers
- **Instant Visibility**: Errors appear immediately with full context
- **Rich Diagnostics**: Call stack, variables, and request details
- **No Console Digging**: Everything in one organized modal
- **Copy-Paste Ready**: Code blocks formatted for easy sharing

### For Users
- **Clear Communication**: Errors explained in user-friendly language
- **Actionable Guidance**: Told exactly what to do next
- **Professional Look**: Polished, modern modal design
- **No Confusion**: Appropriate detail for their access level

### For Security
- **Information Control**: Remote users see minimal details
- **No Leakage**: Stack traces hidden from potential attackers
- **Audit Trail**: Request IDs allow support correlation
- **Role Enforcement**: Access level strictly enforced

## Updated Endpoints (11 total)

All these endpoints now support error modals:

### Debug APIs
- `/api/v1/debug/var` - Variable inspection
- `/api/v1/debug/vars` - Variable listing
- `/api/v1/debug/client-log` - Client error logging
- `/api/v1/debug/test-error` - Error testing (NEW)

### UI Elements
- `/api/v1/ui/elements/system-log` - System logs
- `/api/v1/ui/elements/job-status` - Background jobs
- `/api/v1/ui/elements/file-explorer` (GET & POST) - File operations
- `/api/v1/ui/elements/server-heatmap` - System metrics
- `/api/v1/ui/elements/event-stream` - Event log

### Authentication
- `/api/v1/authprovider/password` - Password login
- `/api/v1/authprovider/windows` - Windows auth

## Files Modified/Created

### Backend
- ✅ `system/Functions.ps1` - Added `Get-PSWebHostErrorReport` with modal support
- ✅ 11 endpoint files - Updated error handlers

### Frontend
- ✅ `public/psweb_spa.js` - Added modal component and auto-detection
- ✅ `public/error-modal-demo.html` - Interactive demo page (NEW)

### Documentation
- ✅ `ERROR_REPORTING_DEMO.md` - Response examples
- ✅ `ERROR_MODAL_SYSTEM.md` - This file

## Next Steps

### Immediate
1. **Test the demo page**: http://localhost:8080/public/error-modal-demo.html
2. **Trigger a real error**: Try loading System Log in the SPA
3. **Review the modal**: Check formatting and content

### Future Enhancements
1. **Add "Copy Error" button** - One-click copy to clipboard
2. **Error history** - Keep last N errors accessible
3. **Screenshot capture** - Auto-capture screen state on error
4. **Email error report** - Send details to admin
5. **Search/filter in modals** - For large call stacks/variables
6. **Dark mode support** - Match user preferences
7. **Export to JSON** - Download full error report
8. **Severity levels** - Warning, Error, Critical with color coding

## Summary

The error modal system is now **fully operational** and provides:
- ✅ Role-based error detail levels
- ✅ Automatic modal display
- ✅ Beautiful, professional UI
- ✅ 11 production endpoints updated
- ✅ Demo page for testing
- ✅ Complete documentation

Users will now see helpful, well-formatted error modals instead of cryptic console messages, while developers get the full diagnostic information they need to debug issues quickly.
