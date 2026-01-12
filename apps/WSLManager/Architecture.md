# WSL Manager App - Architecture & Implementation Status

**Version:** 1.0.0
**Created:** 2026-01-10
**Category:** Containers > WSL
**Status:** 🟡 Read-Only Display (35% Complete)

---

## Executive Summary

The WSL Manager app provides a **read-only** interface for viewing Windows Subsystem for Linux distributions. The distro detection and rendering functionality is **fully working**, but **all interactive controls** (start/stop, install, remove, configure) are **not implemented**. The app currently serves as an information dashboard rather than a management tool.

**Current Capabilities:**
- ✅ Detect if WSL is installed
- ✅ Parse and display WSL distribution list
- ✅ Show distro name, state, version, default status
- ✅ Platform detection (Windows-only)

**Missing Capabilities:**
- ❌ Start/stop distributions
- ❌ Set default distribution
- ❌ Install new distributions
- ❌ Remove distributions
- ❌ Run commands in distributions
- ❌ Configuration management

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        WSL Manager                           │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │   Home       │         │   WSL Distro │                 │
│  │  Component   │         │    Viewer    │                 │
│  │              │         │              │                 │
│  │  ⚠️  Broken  │         │  ✅ Working  │                 │
│  └──────────────┘         └──────────────┘                 │
│         │                         │                         │
│         │                         │                         │
│  ┌──────▼──────────────────────────▼──────┐                │
│  │         API Layer (PowerShell)          │                │
│  ├─────────────────────────────────────────┤                │
│  │ Status API           ✅ Working         │                │
│  │ Distro Detection     ✅ Working         │                │
│  │ Management APIs      ❌ Not Implemented │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
│  Windows Subsystem for Linux (wsl.exe)                      │
│  └─ Distributions (read-only)                               │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Implementation Status

### 1. WSL Manager View ✅ **90% Complete (Read-Only)**

**Location:** `routes/api/v1/ui/elements/wsl-manager/get.ps1`

**Implemented Features:**
- ✅ Platform detection using `$IsWindows`
- ✅ WSL availability check (tests if `wsl.exe` exists)
- ✅ Distribution list parsing via `wsl.exe --list --verbose`
- ✅ Responsive grid layout (CSS Grid)
- ✅ Distro card display with:
  - Name
  - State (Running/Stopped)
  - WSL Version (1 or 2)
  - Default indicator (shows "★ Default" badge)
- ✅ Empty state handling:
  - Non-Windows platforms
  - WSL not installed
  - No distributions installed
- ✅ Embedded CSS styling
- ✅ Professional card-based UI

**Features Shown But Not Functional:**
- Displays current state without interaction
- No buttons or controls rendered
- Read-only information dashboard

**Code Quality:**
- Clean PowerShell with proper error handling
- Platform-specific logic (`if ($IsWindows)`)
- Regex parsing of wsl.exe output
- Proper HTML escaping for security

**Rating:** A- (excellent for display, but no interactivity)

---

### 2. WSLManagerHome React Component ⚠️ **50% Complete**

**Location:** `public/elements/wslmanager-home/component.js`

**Implemented:**
- ✅ React class component structure
- ✅ State management (status, loading, error)
- ✅ Async data fetching via `componentDidMount()`
- ✅ Calls `/apps/wslmanager/api/v1/status` endpoint
- ✅ Loading and error states
- ✅ Theme-aware styling

**Critical Bug:**
- 🐛 **Line 49:** Incomplete template literal
  ```javascript
  React.createElement('p', null, `SubCategory: ``)  // Missing ${status.subCategory}
  ```
- Currently displays "SubCategory: " without value

**Functionality Gaps:**
- ❌ Not integrated with WSL distro data
- ❌ Duplicates functionality of wsl-manager view
- ❌ Only shows static status metadata
- ❌ No connection to distribution information

**Status:** Stub component with limited value

**Rating:** C (functional but redundant and buggy)

---

## API Endpoints

### ✅ Implemented & Working

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/api/v1/status` | GET | App metadata | ✅ Working |
| `/api/v1/ui/elements/wsl-manager` | GET | Distro viewer UI | ✅ Working |
| `/api/v1/ui/elements/wslmanager-home` | GET | Home component loader | ⚠️ Working but buggy |

**WSL Manager View Endpoint Details:**

**PowerShell Execution:**
```powershell
# Detection
if (-not $IsWindows) { return "Not supported on non-Windows platforms" }
if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    return "WSL not installed"
}

# List distributions
$wslOutput = wsl.exe --list --verbose 2>&1

# Parse output with regex
foreach ($line in $wslOutput) {
    if ($line -match '^\s*[*]?\s*(.+?)\s+(Stopped|Running)\s+(\d+)\s*$') {
        $distros += @{
            Name = $matches[1].Trim()
            State = $matches[2]
            Version = $matches[3]
            IsDefault = $line.StartsWith('*')
        }
    }
}
```

**Response Format (HTML):**
- Embedded CSS and JavaScript
- Grid layout with distro cards
- Color-coded state badges (green=running, gray=stopped)
- Default distribution marked with star icon

---

### ❌ Not Implemented (Critical)

**Distribution Management:**

| Endpoint | Method | Purpose | Priority |
|----------|--------|---------|----------|
| `/api/v1/wsl/distributions` | GET | List distros (JSON API) | 🔴 Critical |
| `/api/v1/wsl/distributions/{name}/start` | POST | Start distribution | 🔴 Critical |
| `/api/v1/wsl/distributions/{name}/stop` | POST | Stop/shutdown distribution | 🔴 Critical |
| `/api/v1/wsl/distributions/{name}/terminate` | POST | Force-terminate distribution | 🟡 High |
| `/api/v1/wsl/distributions/{name}/set-default` | POST | Set as default distro | 🟡 High |
| `/api/v1/wsl/distributions/{name}` | DELETE | Unregister distribution | 🟡 High |
| `/api/v1/wsl/distributions/{name}/export` | POST | Export distribution to .tar | 🟢 Medium |
| `/api/v1/wsl/install` | POST | Install new distribution | 🟡 High |
| `/api/v1/wsl/distributions/{name}/exec` | POST | Execute command in distro | 🟡 High |
| `/api/v1/wsl/distributions/{name}/config` | GET/PUT | Get/set distro configuration | 🟢 Medium |
| `/api/v1/wsl/import` | POST | Import distribution from .tar | 🟢 Low |
| `/api/v1/wsl/update` | POST | Update WSL kernel | 🟢 Low |

**System Configuration:**

| Endpoint | Method | Purpose | Priority |
|----------|--------|---------|----------|
| `/api/v1/wsl/config` | GET | Get global WSL config (.wslconfig) | 🟢 Medium |
| `/api/v1/wsl/config` | PUT | Update global WSL config | 🟢 Medium |
| `/api/v1/wsl/version` | GET | Get WSL version info | 🟢 Low |
| `/api/v1/wsl/shutdown` | POST | Shutdown all distributions | 🟡 High |

---

## Development Roadmap

### Phase 1: Fix Bugs & Consolidate (1-2 days)
**Priority:** 🟡 High

**Tasks:**
1. Fix template literal bug in wslmanager-home component (line 49)
2. Decide between two component approaches:
   - **Option A:** Keep wsl-manager view, remove redundant home component
   - **Option B:** Enhance home component with distro data, remove wsl-manager
   - **Recommendation:** Keep wsl-manager (it's more complete), deprecate home component
3. Create unified data API endpoint (`GET /api/v1/wsl/distributions`) that returns JSON
4. Update wsl-manager view to fetch from JSON API instead of embedding data

**Deliverable:** Clean, bug-free distro viewer with proper API separation

---

### Phase 2: Interactive Controls (5-7 days)
**Priority:** 🔴 Critical

**Backend Tasks:**
1. Create POST `/api/v1/wsl/distributions/{name}/start`:
   ```powershell
   wsl.exe -d $DistroName
   # Wait for startup and verify
   ```

2. Create POST `/api/v1/wsl/distributions/{name}/stop`:
   ```powershell
   wsl.exe --terminate $DistroName
   ```

3. Create POST `/api/v1/wsl/distributions/{name}/set-default`:
   ```powershell
   wsl.exe --setdefault $DistroName
   ```

4. Create DELETE `/api/v1/wsl/distributions/{name}`:
   ```powershell
   wsl.exe --unregister $DistroName
   # Confirm operation completed
   ```

5. Add proper error handling:
   - Validate distro exists before operations
   - Handle WSL errors and return meaningful messages
   - Add operation confirmation/status checks

**Frontend Tasks:**
1. Convert wsl-manager view to React component:
   - Fetch distro data from JSON API
   - Add action buttons to each card:
     - Start (when stopped)
     - Stop (when running)
     - Set as Default (with confirmation)
     - Unregister (with double confirmation)
   - Add loading states for async operations
   - Show success/error toast notifications
   - Auto-refresh list after operations

2. Add confirmation dialogs:
   - Stop distribution: "Are you sure?"
   - Unregister: "This will permanently delete the distribution. Type the name to confirm."

**Deliverable:** Functional start/stop/unregister operations

---

### Phase 3: Distribution Installation (3-5 days)
**Priority:** 🟡 High

**Backend Tasks:**
1. Create GET `/api/v1/wsl/available-distributions`:
   - Query Microsoft Store or known distro list
   - Return: name, version, description, size
   - Curated list of common distros (Ubuntu, Debian, Kali, Alpine, etc.)

2. Create POST `/api/v1/wsl/install`:
   ```powershell
   # Install from Microsoft Store
   wsl.exe --install -d $DistroName

   # Or custom installation
   wsl.exe --import $DistroName $InstallPath $TarballPath
   ```
   - Track installation progress
   - Return job ID for status polling
   - Handle installation failures

3. Create GET `/api/v1/wsl/install/{jobId}/status`:
   - Poll installation progress
   - Return: percentage, status message, errors

**Frontend Tasks:**
1. Add "Install Distribution" button
2. Create installation modal:
   - List available distributions
   - Show distro descriptions and sizes
   - Installation location picker
   - Progress bar during installation
3. Handle installation errors gracefully

**Deliverable:** Ability to install new WSL distributions

---

### Phase 4: Advanced Features (5-7 days)
**Priority:** 🟢 Medium

**Command Execution:**
1. Create POST `/api/v1/wsl/distributions/{name}/exec`:
   ```powershell
   wsl.exe -d $DistroName -e $Command
   ```
   - Execute commands and return output
   - Support interactive commands
   - Stream output for long-running commands

2. Frontend terminal emulator:
   - Embed xterm.js or similar
   - Connect to exec API via WebSocket
   - Provide shell access to distros

**Configuration Management:**
1. Create GET/PUT `/api/v1/wsl/distributions/{name}/config`:
   - Read/write `/etc/wsl.conf`
   - Manage memory, swap, kernel parameters
   - Set network configuration

2. Create GET/PUT `/api/v1/wsl/config`:
   - Manage global `.wslconfig` file
   - Control WSL 2 VM settings
   - Configure nested virtualization

**Export/Import:**
1. Create POST `/api/v1/wsl/distributions/{name}/export`:
   ```powershell
   wsl.exe --export $DistroName $OutputPath
   ```
   - Generate downloadable .tar backup
   - Track export progress

2. Create POST `/api/v1/wsl/import`:
   ```powershell
   wsl.exe --import $DistroName $InstallPath $TarballPath --version 2
   ```
   - Upload .tar file
   - Import as new distribution

**Resource Monitoring:**
1. Track CPU/memory usage per distro
2. Show running processes
3. Disk space usage
4. Network connections

**Deliverable:** Full-featured WSL management platform

---

## Security Considerations

**Current State:**
- ✅ Windows platform validation
- ✅ Read-only operations (safe)
- ✅ Role-based access (admin, system_admin)

**Required for Management Features:**

1. **Command Validation:**
   - Sanitize distribution names (regex: `[a-zA-Z0-9_-]+`)
   - Prevent path traversal in export/import
   - Validate command injection in exec operations
   - Whitelist allowed WSL operations

2. **Permissions:**
   - Verify user has Windows admin rights
   - Check WSL feature is enabled
   - Validate distro ownership before operations

3. **Destructive Operations:**
   - Require confirmation tokens for unregister
   - Add rate limiting for start/stop operations
   - Audit log all management operations
   - Prevent accidental deletion of default distro

4. **Command Execution:**
   - Sandbox exec operations
   - Limit execution time
   - Restrict dangerous commands (rm -rf /, format, etc.)
   - Log all executed commands

---

## Testing Requirements

### Unit Tests
- WSL output parsing
- Distribution name sanitization
- Platform detection logic
- Error message formatting

### Integration Tests
- Distribution start/stop
- Default distro setting
- Installation process
- Export/import operations
- Command execution
- Configuration changes

### UI Tests
- Component rendering
- Button state management
- Confirmation dialogs
- Loading states
- Error handling

---

## Known Issues & Bugs

### 🐛 Critical Bugs

1. **Template Literal Bug in wslmanager-home** (High Priority)
   - **Location:** `public/elements/wslmanager-home/component.js:49`
   - **Issue:** Incomplete template literal `\`SubCategory: \`\``
   - **Fix:** Change to `\`SubCategory: ${status.subCategory}\``
   - **Impact:** Missing subCategory value in display

### ⚠️ Design Issues

2. **Duplicate Component Implementations** (Medium Priority)
   - Two different approaches to showing WSL data
   - wsl-manager (embedded HTML with full data)
   - wslmanager-home (React component with just status)
   - Causes confusion and maintenance burden
   - **Recommendation:** Deprecate wslmanager-home, keep wsl-manager

3. **No API Separation** (Medium Priority)
   - Distro data embedded in HTML response
   - Should have separate JSON API endpoint
   - Makes it hard for other components to use data
   - **Fix:** Create GET `/api/v1/wsl/distributions` JSON API

### 📝 Limitations

4. **Windows-Only** (By Design)
   - Explicitly checks `$IsWindows`
   - Returns "not supported" message on Linux/Mac
   - This is correct behavior but could show more gracefully

5. **No Real-Time Updates**
   - Distribution state changes not reflected until manual refresh
   - Need WebSocket or polling for live status

6. **Limited Error Handling**
   - WSL errors not surfaced to user
   - Generic "failed" messages
   - Should parse WSL error output and display meaningful messages

---

## PowerShell Integration

**Current WSL Commands Used:**
```powershell
# List distributions
wsl.exe --list --verbose

# Output format:
#   NAME            STATE           VERSION
# * Ubuntu          Running         2
#   Debian          Stopped         2
```

**Required WSL Commands for Management:**
```powershell
# Distribution control
wsl.exe -d {distro}                      # Start distribution
wsl.exe --terminate {distro}              # Stop distribution
wsl.exe --shutdown                        # Stop all distributions
wsl.exe --setdefault {distro}             # Set default distribution
wsl.exe --unregister {distro}             # Remove distribution

# Installation
wsl.exe --install                         # Install WSL
wsl.exe --install -d {distro}             # Install specific distribution
wsl.exe --list --online                   # List available distributions

# Import/Export
wsl.exe --export {distro} {file.tar}      # Export distribution
wsl.exe --import {name} {path} {tar}      # Import distribution

# Configuration
wsl.exe --set-version {distro} {1|2}      # Change WSL version
wsl.exe --set-default-version {1|2}       # Set default WSL version

# Command execution
wsl.exe -d {distro} -e {command}          # Execute command
wsl.exe -d {distro} -u {user} {command}   # Execute as specific user

# Status
wsl.exe --status                          # Show WSL status
```

**PowerShell Helper Module Structure:**
```powershell
# modules/PSWSLManager.psm1

function Get-WSLDistributions {
    # Parse wsl.exe --list --verbose
    # Return structured object array
}

function Start-WSLDistribution {
    param([string]$Name)
    # Start distro and wait for ready state
}

function Stop-WSLDistribution {
    param([string]$Name)
    # Gracefully terminate distribution
}

function Set-WSLDefaultDistribution {
    param([string]$Name)
    # Set default and verify
}

function Remove-WSLDistribution {
    param([string]$Name, [switch]$Force)
    # Unregister with safety checks
}
```

---

## File Structure

```
apps/WSLManager/
├── app.yaml                                    # ✅ Configuration
├── menu.yaml                                   # ✅ Menu entry
├── app_init.ps1                                # ✅ Initialization
├── data/                                       # ❌ Empty
├── modules/                                    # ❌ Empty (should add PSWSLManager.psm1)
├── public/elements/
│   └── wslmanager-home/
│       ├── component.js                        # ⚠️  Buggy, redundant
│       └── style.css                           # ✅ Working
└── routes/api/v1/
    ├── status/
    │   ├── get.ps1                             # ✅ Working
    │   └── get.security.json                   # ✅ Configured
    └── ui/elements/
        ├── wsl-manager/get.ps1                 # ✅ Read-only working
        └── wslmanager-home/get.ps1             # ⚠️  Working but buggy
```

**Missing Directories to Create:**
```
routes/api/v1/wsl/
├── distributions/
│   ├── get.ps1                                 # List all distros (JSON)
│   └── {name}/
│       ├── start/post.ps1                      # Start distro
│       ├── stop/post.ps1                       # Stop distro
│       ├── set-default/post.ps1                # Set as default
│       ├── delete.ps1                          # Unregister
│       └── exec/post.ps1                       # Execute command
├── install/post.ps1                            # Install new distro
└── available/get.ps1                           # List available distros
```

---

## Dependencies

**System Requirements:**
- Windows 10/11 with WSL enabled
- wsl.exe command-line tool
- Administrator privileges for distro management

**PowerShell Modules:**
- None (should create PSWSLManager.psm1)

**Frontend Libraries:**
- React (global PSWebHost dependency)
- Optional: xterm.js (for terminal emulator in Phase 4)

---

## Completion Estimates

| Phase | Estimated Effort | Complexity |
|-------|------------------|------------|
| Phase 1: Bug Fixes & Consolidation | 1-2 days | Low |
| Phase 2: Interactive Controls | 5-7 days | Medium |
| Phase 3: Distribution Installation | 3-5 days | Medium |
| Phase 4: Advanced Features | 5-7 days | High |

**Total to MVP (Phases 1-2):** 6-9 days
**Total to Full Implementation (All Phases):** 14-21 days

---

## Implementation Rating by Component

| Component | Completeness | Functionality | Quality | Overall |
|-----------|--------------|---------------|---------|---------|
| WSL Distro Viewer | 90% | ✅ Read-Only | A | **B+** |
| Status API | 100% | ✅ Working | A | **A** |
| Home Component | 50% | ⚠️ Buggy | C | **D+** |
| Management APIs | 0% | ❌ Missing | N/A | **F** |
| Interactive UI | 0% | ❌ Missing | N/A | **F** |
| Overall App | 35% | 🟡 Display Only | B | **D+** |

---

## Conclusion

The WSL Manager app has a **strong foundation** for viewing WSL distributions but lacks all management capabilities:

**Strengths:**
- ✅ Solid read-only distro viewer
- ✅ Clean UI with responsive design
- ✅ Proper platform detection
- ✅ Good WSL output parsing

**Weaknesses:**
- ❌ No interactive controls
- ❌ No management operations
- ❌ Duplicate/redundant home component
- 🐛 Template literal bug in home component
- ❌ No JSON API for distro data

**Recommended Next Steps:**
1. Fix template literal bug (30 minutes)
2. Create JSON API for distro data (Phase 1)
3. Implement start/stop/unregister operations (Phase 2)
4. Build interactive UI controls (Phase 2)

**Time to MVP:** 6-9 days (Phases 1-2)
**Risk Level:** Low (WSL CLI is stable, operations straightforward)
**Maintainability:** High (clean code structure, follows PSWebHost patterns)
