# Linux Code Extraction Plan - WindowsAdmin App

**Date:** 2026-02-23
**Status:** PENDING COORDINATION WITH LINUXADMIN AGENT
**Priority:** HIGH - Code organization and maintainability

---

## Executive Summary

The WindowsAdmin app currently contains significant Linux-specific code that should be extracted to a shared cross-platform module. This document identifies all Linux code, proposes extraction strategy, and outlines the refactoring plan.

**Key Finding:** 5 files contain Linux code totaling approximately 150 lines that should be moved to shared module.

---

## Files Containing Linux Code

### 1. `/routes/api/v1/system/services/get.ps1`
**Lines to Extract:** 51-72 (22 lines)

```powershell
# LINUX CODE - Lines 51-72
elseif ($IsLinux) {
    $result.platform = 'Linux'

    # Get systemd services
    $systemctlOutput = & systemctl list-units --type=service --all --no-pager --plain 2>/dev/null
    if ($LASTEXITCODE -eq 0 -and $systemctlOutput) {
        $lines = $systemctlOutput -split "`n" | Where-Object { $_ -match '\.service' }
        foreach ($line in $lines | Select-Object -First 50) {
            $parts = $line -split '\s+', 5
            if ($parts.Count -ge 4) {
                $result.services += @{
                    name = $parts[0] -replace '\.service$', ''
                    displayName = $parts[0]
                    status = $parts[3]
                    load = $parts[1]
                    active = $parts[2]
                    description = if ($parts.Count -ge 5) { $parts[4] } else { '' }
                }
            }
        }
    }
}
```

**Functionality:**
- Uses `systemctl list-units --type=service` to enumerate Linux services
- Parses systemd output to extract service properties
- Returns service name, status, load state, active state, description

---

### 2. `/routes/api/v1/system/tasks/get.ps1`
**Lines to Extract:** 71-105 (35 lines)

```powershell
# LINUX CODE - Lines 71-105
elseif ($IsLinux) {
    $result.platform = 'Linux'

    # Get cron jobs for current user
    try {
        $cronOutput = & crontab -l 2> /dev/null
        if ($LASTEXITCODE -eq 0 -and $cronOutput) {
            $lines = $cronOutput -split "`n" | Where-Object { $_ -and $_ -notmatch '^#' }
            foreach ($line in $lines) {
                if ($line -match '^([^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+\s+[^\s]+)\s+(.+)$') {
                    $result.tasks += @{
                        name = $matches[2].Substring(0, [Math]::Min(50, $matches[2].Length))
                        schedule = $matches[1]
                        command = $matches[2]
                        enabled = $true
                        state = 'Scheduled'
                    }
                }
            }
        }

        # Also check system cron
        $systemCron = Get-ChildItem /etc/cron.d/ -ErrorAction SilentlyContinue
        foreach ($file in $systemCron) {
            $result.tasks += @{
                name = $file.Name
                path = $file.FullName
                enabled = $true
                state = 'System'
            }
        }
    }
    catch {
        $result.error = "Failed to read cron: $($_.Exception.Message)"
    }
}
```

**Functionality:**
- Reads user crontab with `crontab -l`
- Parses cron entries (schedule + command)
- Reads system-wide cron jobs from `/etc/cron.d/`
- Returns task name, schedule, command, enabled state

---

### 3. `/routes/api/v1/system/services/{name}/start/post.ps1`
**Lines to Extract:** 67-88 (22 lines)

```powershell
# LINUX CODE - Lines 67-88
elseif ($IsLinux) {
    $result.platform = 'Linux'

    # Try to start with systemctl
    try {
        $output = & systemctl start "$serviceName.service" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result.success = $true
            $result.message = "Service '$serviceName' started successfully"
            $result.status = 'active'
            Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service started: $serviceName by $($sessiondata.User.Username)"
        }
        else {
            $result.error = $output -join ' '
            $result.message = "Failed to start service: $($output -join ' ')"
            Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to start service $serviceName : $($output -join ' ')"
        }
    }
    catch {
        $result.error = $_.Exception.Message
        $result.message = "Failed to start service: $($_.Exception.Message)"
    }
}
```

**Functionality:**
- Executes `systemctl start <service>`
- Captures success/failure status
- Returns standardized result object

---

### 4. `/routes/api/v1/system/services/{name}/stop/post.ps1`
**Lines to Extract:** 76-97 (22 lines)

```powershell
# LINUX CODE - Lines 76-97
elseif ($IsLinux) {
    $result.platform = 'Linux'

    # Try to stop with systemctl
    try {
        $output = & systemctl stop "$serviceName.service" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result.success = $true
            $result.message = "Service '$serviceName' stopped successfully"
            $result.status = 'inactive'
            Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service stopped: $serviceName by $($sessiondata.User.Username)"
        }
        else {
            $result.error = $output -join ' '
            $result.message = "Failed to stop service: $($output -join ' ')"
            Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to stop service $serviceName : $($output -join ' ')"
        }
    }
    catch {
        $result.error = $_.Exception.Message
        $result.message = "Failed to stop service: $($_.Exception.Message)"
    }
}
```

**Functionality:**
- Executes `systemctl stop <service>`
- Captures success/failure status
- Returns standardized result object

---

### 5. `/routes/api/v1/system/services/{name}/restart/post.ps1`
**Lines to Extract:** 76-97 (22 lines)

```powershell
# LINUX CODE - Lines 76-97
elseif ($IsLinux) {
    $result.platform = 'Linux'

    # Try to restart with systemctl
    try {
        $output = & systemctl restart "$serviceName.service" 2>&1
        if ($LASTEXITCODE -eq 0) {
            $result.success = $true
            $result.message = "Service '$serviceName' restarted successfully"
            $result.status = 'active'
            Write-PSWebHostLog -Severity 'Info' -Category 'ServiceControl' -Message "Service restarted: $serviceName by $($sessiondata.User.Username)"
        }
        else {
            $result.error = $output -join ' '
            $result.message = "Failed to restart service: $($output -join ' ')"
            Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Failed to restart service $serviceName : $($output -join ' ')"
        }
    }
    catch {
        $result.error = $_.Exception.Message
        $result.message = "Failed to restart service: $($_.Exception.Message)"
    }
}
```

**Functionality:**
- Executes `systemctl restart <service>`
- Captures success/failure status
- Returns standardized result object

---

## Proposed Shared Module

### Module Name: `PSCrossPlatformOSManagement.psm1`

**Location:** `/system/modules/PSCrossPlatformOSManagement/PSCrossPlatformOSManagement.psm1`

**Purpose:** Provide unified cross-platform abstractions for OS-level service and task management

---

## Proposed Functions

### 1. `Get-OSServices`

**Purpose:** Get list of services (Windows Services or Linux systemd)

**Parameters:**
- `[int]$MaxResults = 50` - Maximum number of services to return
- `[switch]$IncludeAll` - Include all services (not just running/important)

**Returns:** Array of service objects with standardized properties:
```powershell
@{
    Name = [string]
    DisplayName = [string]
    Status = [string]  # Normalized: Running, Stopped, Unknown
    Platform = [string]  # Windows, Linux, Unknown
    CanStop = [bool]
    CanPause = [bool]
    AdditionalProperties = @{}  # Platform-specific properties
}
```

**Implementation:**
- Detect platform with `$IsWindows` / `$IsLinux`
- Windows: Use `Get-Service`
- Linux: Use `systemctl list-units --type=service`
- Normalize output to common schema

---

### 2. `Start-OSService`

**Purpose:** Start a service (Windows or Linux)

**Parameters:**
- `[string]$ServiceName` (required) - Service name
- `[string]$Username` - User performing action (for logging)

**Returns:** Standardized result object:
```powershell
@{
    Success = [bool]
    ServiceName = [string]
    Platform = [string]
    Message = [string]
    Status = [string]  # Running, active, etc.
    Error = [string]
}
```

**Implementation:**
- Windows: `Start-Service`
- Linux: `systemctl start <service>.service`
- Unified error handling
- Audit logging

---

### 3. `Stop-OSService`

**Purpose:** Stop a service (Windows or Linux)

**Parameters:**
- `[string]$ServiceName` (required)
- `[switch]$Force` - Force stop
- `[string]$Username` - User performing action (for logging)

**Returns:** Same as `Start-OSService`

**Implementation:**
- Windows: `Stop-Service -Force`
- Linux: `systemctl stop <service>.service`
- Check if service can be stopped (Windows)

---

### 4. `Restart-OSService`

**Purpose:** Restart a service (Windows or Linux)

**Parameters:**
- `[string]$ServiceName` (required)
- `[switch]$Force` - Force restart
- `[string]$Username` - User performing action (for logging)

**Returns:** Same as `Start-OSService`

**Implementation:**
- Windows: `Restart-Service -Force` or `Start-Service` if stopped
- Linux: `systemctl restart <service>.service`

---

### 5. `Get-OSScheduledTasks`

**Purpose:** Get list of scheduled tasks (Windows Task Scheduler or Linux cron)

**Parameters:**
- `[int]$MaxResults = 50` - Maximum tasks to return
- `[int]$MaxDepth = 3` - Maximum folder depth for Windows Task Scheduler

**Returns:** Array of task objects:
```powershell
@{
    Name = [string]
    Path = [string]
    Enabled = [bool]
    State = [string]  # Ready, Running, Disabled, Scheduled
    LastRun = [string]  # ISO date or "Never"
    NextRun = [string]  # ISO date or "N/A"
    Schedule = [string]  # Cron expression or description
    Command = [string]
    Platform = [string]
}
```

**Implementation:**
- Windows: COM interface `Schedule.Service`, recursive folder traversal
- Linux: Parse `crontab -l` and `/etc/cron.d/*`
- Normalize date formats

---

### 6. `New-OSScheduledTask` (Future)

**Purpose:** Create scheduled task (cross-platform)

**Status:** NOT INCLUDED IN INITIAL EXTRACTION - Future enhancement

---

### 7. `Remove-OSScheduledTask` (Future)

**Purpose:** Delete scheduled task (cross-platform)

**Status:** NOT INCLUDED IN INITIAL EXTRACTION - Future enhancement

---

## Extraction Strategy

### Phase 1: Create Shared Module (DO NOT EXECUTE YET)

1. Create module directory:
   ```
   /system/modules/PSCrossPlatformOSManagement/
   ├── PSCrossPlatformOSManagement.psm1
   ├── PSCrossPlatformOSManagement.psd1
   └── README.md
   ```

2. Implement functions:
   - Extract Linux code from WindowsAdmin
   - Extract Linux code from LinuxAdmin (coordination required)
   - Combine into unified functions
   - Add comprehensive error handling
   - Add parameter validation
   - Add help documentation

3. Write module manifest (`.psd1`):
   - Export functions
   - Define dependencies
   - Set version to 1.0.0

---

### Phase 2: Update WindowsAdmin App

**Files to modify:**
1. `/routes/api/v1/system/services/get.ps1`
   - Remove lines 51-72 (Linux code)
   - Replace with: `$services = Get-OSServices -MaxResults 50`
   - Update result mapping

2. `/routes/api/v1/system/tasks/get.ps1`
   - Remove lines 71-105 (Linux code)
   - Replace with: `$tasks = Get-OSScheduledTasks -MaxResults 50`
   - Update result mapping

3. `/routes/api/v1/system/services/{name}/start/post.ps1`
   - Remove lines 67-88 (Linux code)
   - Replace with: `$result = Start-OSService -ServiceName $serviceName -Username $sessiondata.User.Username`

4. `/routes/api/v1/system/services/{name}/stop/post.ps1`
   - Remove lines 76-97 (Linux code)
   - Replace with: `$result = Stop-OSService -ServiceName $serviceName -Username $sessiondata.User.Username -Force`

5. `/routes/api/v1/system/services/{name}/restart/post.ps1`
   - Remove lines 76-97 (Linux code)
   - Replace with: `$result = Restart-OSService -ServiceName $serviceName -Username $sessiondata.User.Username -Force`

6. `/app_init.ps1`
   - Add import: `Import-Module PSCrossPlatformOSManagement`

---

### Phase 3: Update LinuxAdmin App (Coordination Required)

**CRITICAL:** Must coordinate with LinuxAdmin agent before modifying LinuxAdmin app.

**Expected files to modify:**
- Check for duplicate service/task management routes
- Replace Linux-specific code with shared module functions
- Update imports in `app_init.ps1`

---

### Phase 4: Testing

**Test both apps:**
1. Windows environment:
   - WindowsAdmin should work exactly as before
   - LinuxAdmin should gracefully handle Windows platform

2. Linux environment (if available):
   - WindowsAdmin should use Linux service management
   - LinuxAdmin should work exactly as before

3. Cross-platform compatibility:
   - Verify platform detection logic
   - Test error handling for unsupported platforms

---

## Benefits of Extraction

### 1. Code Reusability
- Single implementation of Linux service management
- Used by both WindowsAdmin and LinuxAdmin apps
- Future apps can leverage same module

### 2. Maintainability
- Fix bugs once, benefits both apps
- Easier to add new features (e.g., macOS support)
- Clear separation of concerns

### 3. Testing
- Module can be unit tested independently
- Reduces duplication in app-level tests

### 4. Consistency
- Standardized return objects
- Unified error handling
- Common logging patterns

### 5. Documentation
- Single source of truth for API
- Comprehensive help documentation in module
- Easier onboarding for new developers

---

## Risks and Mitigations

### Risk 1: Breaking Changes
**Impact:** WindowsAdmin app stops working after refactor
**Mitigation:**
- Create comprehensive test suite before refactoring
- Test on Windows before committing changes
- Keep original code in git history for rollback

### Risk 2: LinuxAdmin Conflicts
**Impact:** LinuxAdmin app may have different implementation
**Mitigation:**
- Coordinate with LinuxAdmin agent first
- Review LinuxAdmin code before creating shared module
- Ensure shared module meets both apps' requirements

### Risk 3: Platform Detection Issues
**Impact:** Wrong code path executed on certain systems
**Mitigation:**
- Use consistent platform detection (`$IsWindows`, `$IsLinux`)
- Add fallback for unknown platforms
- Test on multiple environments

### Risk 4: Missing Dependencies
**Impact:** Module fails on systems without systemctl/crontab
**Mitigation:**
- Check for command availability before execution
- Return helpful error messages
- Document system requirements

---

## Timeline and Dependencies

### Prerequisites
1. Review LinuxAdmin app code (coordinate with LinuxAdmin agent)
2. Identify all duplicate Linux code
3. Design unified API for shared module
4. Get approval for module creation

### Estimated Effort
- **Module Creation:** 3-5 hours
- **WindowsAdmin Refactoring:** 2-3 hours
- **LinuxAdmin Coordination:** 2-4 hours
- **Testing:** 2-3 hours
- **Documentation:** 1-2 hours

**Total:** 10-17 hours

### Critical Path
1. LinuxAdmin agent completes their analysis
2. Compare findings from both agents
3. Finalize shared module API design
4. Create module with functions
5. Refactor WindowsAdmin (this agent)
6. Refactor LinuxAdmin (LinuxAdmin agent)
7. Integration testing
8. Documentation updates

---

## Open Questions

1. **Module Location:** Should module be in `/system/modules/` or `/apps/shared/modules/`?
   - Recommendation: `/system/modules/` for system-level functionality

2. **Logging Strategy:** How should module log actions?
   - Recommendation: Use `Write-PSWebHostLog` with category 'OSManagement'

3. **Security Context:** Should module enforce role-based access control?
   - Recommendation: No, let calling routes handle security

4. **Error Handling:** How verbose should errors be?
   - Recommendation: Return detailed errors, let routes decide what to expose to users

5. **Testing Framework:** What test framework should be used?
   - Recommendation: Pester for PowerShell module testing

---

## Next Steps

### Immediate Actions (DO NOT EXECUTE - FOR PLANNING ONLY)
1. Share this plan with LinuxAdmin agent
2. Wait for LinuxAdmin agent's extraction plan
3. Compare both plans and identify overlaps
4. Finalize shared module API design
5. Get approval from project maintainer

### After Coordination
1. Create shared module with agreed-upon API
2. Refactor WindowsAdmin routes (this agent)
3. Update WindowsAdmin documentation
4. Test WindowsAdmin with new module
5. Create pull request with changes

---

## Conclusion

The WindowsAdmin app contains 150+ lines of Linux-specific code across 5 files that should be extracted to a shared module. The proposed `PSCrossPlatformOSManagement` module will provide unified abstractions for service and task management across Windows and Linux platforms.

**Benefits:**
- Eliminates code duplication
- Improves maintainability
- Enables easier testing
- Provides consistent API

**Blockers:**
- Requires coordination with LinuxAdmin agent
- Needs approval for new shared module
- Requires testing on both Windows and Linux

**Recommendation:** Proceed with coordination phase before implementing extraction.

---

**Document Status:** DRAFT - Pending LinuxAdmin Agent Review
**Last Updated:** 2026-02-23
**Author:** WindowsAdmin Implementation Agent
