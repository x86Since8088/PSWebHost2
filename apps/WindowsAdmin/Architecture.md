# Windows Administration App - Architecture & Implementation Status

**Version:** 1.0.0
**Created:** 2026-01-10
**Category:** Operating Systems > Windows
**Status:** 🟡 Partially Implemented (40% Complete)

---

## Executive Summary

The Windows Administration app provides Windows service and task scheduler management capabilities within PSWebHost. The backend APIs for reading service/task data are **fully functional**, but the frontend UI components are **stubbed with mock data** and control operations (start/stop/restart) are **not implemented**.

**Critical Gaps:**
- Frontend components not connected to backend APIs
- Service control operations (start/stop/restart) missing
- Task management operations (create/edit/delete/run) missing

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Windows Administration                    │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────┐         ┌──────────────┐                 │
│  │   Home       │         │  Services    │                 │
│  │  Dashboard   │         │   Control    │                 │
│  │              │         │              │                 │
│  │  ✅ Working  │         │ 🟡 Partial   │                 │
│  └──────────────┘         └──────────────┘                 │
│         │                         │                         │
│         │                         │                         │
│  ┌──────▼──────────────────────────▼──────┐                │
│  │         API Layer (PowerShell)          │                │
│  ├─────────────────────────────────────────┤                │
│  │ Status API    ✅ Working                │                │
│  │ Services API  ✅ Working                │                │
│  │ Tasks API     ✅ Working                │                │
│  │ Control APIs  ❌ Not Implemented        │                │
│  └─────────────────────────────────────────┘                │
│                                                              │
│  ┌──────────────┐                                           │
│  │    Task      │                                           │
│  │  Scheduler   │                                           │
│  │              │                                           │
│  │ 🟡 Partial   │                                           │
│  └──────────────┘                                           │
└─────────────────────────────────────────────────────────────┘
```

---

## Component Implementation Status

### 1. Home Dashboard Component ✅ **100% Complete**

**Location:** `public/elements/windowsadmin-home/`

**Status:** Fully functional React component

**Features:**
- Fetches app status from `/apps/windowsadmin/api/v1/status`
- Displays metadata (category, subcategory, version, status)
- Loading states and error handling
- Theme-aware styling with CSS variables

**Rating:** Production Ready

---

### 2. Service Control Component 🟡 **30% Complete**

**Location:** `public/elements/service-control/component.js`

**Implemented:**
- ✅ UI framework (table layout, filtering, buttons)
- ✅ Platform indicator (Windows/Linux toggle)
- ✅ Service filter/search functionality
- ✅ Status color coding (running=green, stopped=red, starting=orange)
- ✅ Mock data rendering

**Not Implemented:**
- ❌ Connection to `/api/v1/system/services` endpoint
- ❌ Start/stop/restart functionality (all buttons disabled)
- ❌ Health metrics collection
- ❌ Dependency visualization
- ❌ Real-time service status updates

**Blockers:**
- Frontend component hardcoded with mock data (5 sample services)
- Action buttons have `disabled` attribute and 50% opacity
- No fetch calls to backend API

**Next Steps:**
1. Replace mock data with fetch to `/apps/windowsadmin/api/v1/system/services`
2. Implement POST endpoints for service control operations
3. Enable action buttons and wire to control APIs
4. Add real-time status polling (WebSocket or periodic fetch)

**Rating:** UI Shell Complete, Logic Missing

---

### 3. Task Scheduler Component 🟡 **30% Complete**

**Location:** `public/elements/task-scheduler/component.js`

**Implemented:**
- ✅ Table layout with task information
- ✅ Platform-aware headers (Windows Task Scheduler vs Cron Jobs)
- ✅ Status and result color coding
- ✅ Mock data rendering (4 sample tasks)
- ✅ Disabled tasks shown at 50% opacity

**Not Implemented:**
- ❌ Connection to `/api/v1/system/tasks` endpoint
- ❌ Task creation/editing UI and backend
- ❌ Task execution (run now) functionality
- ❌ Task deletion
- ❌ Log viewing functionality

**Blockers:**
- Frontend uses hardcoded mock task data
- All action buttons disabled
- No backend endpoints for task modification

**Next Steps:**
1. Connect to `/apps/windowsadmin/api/v1/system/tasks` API
2. Implement task CRUD endpoints (POST/PUT/DELETE)
3. Add task execution endpoint (POST to trigger manual run)
4. Implement log viewer modal/component
5. Enable all action buttons

**Rating:** UI Shell Complete, Logic Missing

---

## API Endpoints

### ✅ Implemented & Working

| Endpoint | Method | Purpose | Status |
|----------|--------|---------|--------|
| `/api/v1/status` | GET | App metadata | ✅ Working |
| `/api/v1/system/services` | GET | List Windows/Linux services | ✅ Working |
| `/api/v1/system/tasks` | GET | List Windows tasks/Linux cron | ✅ Working |
| `/api/v1/ui/elements/windowsadmin-home` | GET | Home component | ✅ Working |
| `/api/v1/ui/elements/service-control` | GET | Service UI component | ✅ Working |
| `/api/v1/ui/elements/task-scheduler` | GET | Task UI component | ✅ Working |

**Details:**

**System Services API** (`routes/api/v1/system/services/get.ps1`):
- Cross-platform (Windows/Linux)
- Windows: Uses `Get-Service` to retrieve important + running services (max 50)
- Linux: Uses `systemctl list-units` for systemd services
- Returns: name, displayName, status, startType, canStop, canPause

**System Tasks API** (`routes/api/v1/system/tasks/get.ps1`):
- Cross-platform (Windows/Linux)
- Windows: COM interface to Schedule.Service (recursive, max depth 3)
- Linux: Reads crontab + system cron in `/etc/cron.d/`
- Returns: name, path, enabled, state, lastRun, nextRun, schedule, command

---

### ❌ Not Implemented (Required)

| Endpoint | Method | Purpose | Priority |
|----------|--------|---------|----------|
| `/api/v1/system/services/{name}/start` | POST | Start service | 🔴 High |
| `/api/v1/system/services/{name}/stop` | POST | Stop service | 🔴 High |
| `/api/v1/system/services/{name}/restart` | POST | Restart service | 🔴 High |
| `/api/v1/system/tasks` | POST | Create task | 🟡 Medium |
| `/api/v1/system/tasks/{id}` | PUT | Edit task | 🟡 Medium |
| `/api/v1/system/tasks/{id}` | DELETE | Delete task | 🟡 Medium |
| `/api/v1/system/tasks/{id}/run` | POST | Execute task | 🟡 Medium |
| `/api/v1/system/tasks/{id}/logs` | GET | View task logs | 🟢 Low |

---

## Development Roadmap

### Phase 1: Connect Frontend to Backend (2-3 days)
**Priority:** 🔴 Critical

**Tasks:**
1. Service Control Component:
   - Remove mock data from component.js
   - Add fetch call to `/api/v1/system/services` on component mount
   - Handle loading/error states
   - Update state with real service data
   - Test cross-platform display (Windows/Linux)

2. Task Scheduler Component:
   - Remove mock data from component.js
   - Add fetch call to `/api/v1/system/tasks`
   - Parse Windows Task Scheduler vs Linux cron formats
   - Display real task data
   - Test cross-platform functionality

**Deliverable:** Components display real data from backend

---

### Phase 2: Service Control Operations (3-5 days)
**Priority:** 🔴 Critical

**Tasks:**
1. Backend Implementation:
   - Create POST endpoint: `/api/v1/system/services/{name}/start`
     - Windows: `Start-Service`
     - Linux: `systemctl start`
   - Create POST endpoint: `/api/v1/system/services/{name}/stop`
     - Windows: `Stop-Service`
     - Linux: `systemctl stop`
   - Create POST endpoint: `/api/v1/system/services/{name}/restart`
     - Windows: `Restart-Service`
     - Linux: `systemctl restart`
   - Add error handling and permissions checks
   - Add security validation (require admin/system_admin roles)

2. Frontend Implementation:
   - Enable action buttons
   - Wire buttons to POST endpoints
   - Add confirmation dialogs for destructive actions
   - Implement success/error toast notifications
   - Auto-refresh service list after operations

**Deliverable:** Functional service start/stop/restart

---

### Phase 3: Task Management CRUD (5-7 days)
**Priority:** 🟡 High

**Tasks:**
1. Backend Endpoints:
   - POST `/api/v1/system/tasks` - Create task
     - Windows: Use Schedule.Service COM interface
     - Linux: Add crontab entry
   - PUT `/api/v1/system/tasks/{id}` - Edit task
   - DELETE `/api/v1/system/tasks/{id}` - Delete task
   - POST `/api/v1/system/tasks/{id}/run` - Execute task manually

2. Frontend UI:
   - Create task creation modal
   - Schedule builder UI (cron expression helper)
   - Edit task modal with pre-populated data
   - Delete confirmation dialog
   - Run now button with confirmation

**Deliverable:** Full task CRUD operations

---

### Phase 4: Enhancements (Optional)

**Medium Priority:**
- Real-time service status updates (WebSocket or polling)
- Service dependency visualization
- Task history and logging viewer
- Bulk operations (start/stop multiple services)
- Export service/task reports
- Performance metrics (CPU, memory per service)

**Low Priority:**
- Service configuration editor
- Task scheduling wizard
- Advanced filtering and search
- Custom service groups
- Notification system for failed tasks

---

## Security Considerations

**Current Implementation:**
- ✅ Role-based access control (admin, system_admin, site_admin)
- ✅ Security configuration files (`.security.json`) per endpoint
- ✅ Session-based authentication

**Required for Service Control:**
- Validate user has Windows admin rights before service operations
- Audit logging for all service control actions
- Rate limiting to prevent abuse
- Confirmation tokens for destructive operations

**Required for Task Management:**
- Validate task ownership (prevent unauthorized task modification)
- Sandbox task execution (prevent code injection)
- Validate cron expressions and paths
- Audit logging for task creation/modification

---

## Testing Requirements

### Unit Tests
- Service enumeration (Windows/Linux)
- Task enumeration (Windows/Linux)
- Service state parsing
- Cron expression parsing
- Error handling for missing services/tasks

### Integration Tests
- Service start/stop/restart operations
- Task creation with valid/invalid data
- Cross-platform compatibility
- Permission denied scenarios
- Concurrent operations handling

### UI Tests
- Component rendering with real data
- Button state management
- Form validation
- Error message display
- Loading states

---

## Known Issues

1. **Component.js Template Literal Bug** (Low Priority)
   - Home component has incomplete template string on line 49
   - Missing `${status.subCategory}` value
   - Currently displays "SubCategory: " without value

2. **No Real-time Updates**
   - Service status changes not reflected until manual refresh
   - Need WebSocket or polling mechanism

3. **Limited Error Handling**
   - No retry mechanism for failed API calls
   - Generic error messages

---

## Performance Considerations

**Current:**
- Services API limited to 50 results (Windows)
- Task enumeration capped at depth 3 (Windows)
- No pagination

**Recommendations:**
- Add pagination for large service/task lists
- Implement server-side filtering
- Cache service/task lists with TTL
- Lazy-load task details
- Add search indexing for faster filtering

---

## Dependencies

**PowerShell Modules:**
- Built-in cmdlets: `Get-Service`, `Start-Service`, `Stop-Service`, `Restart-Service`
- COM interface: `Schedule.Service` (Windows Task Scheduler)

**External Tools:**
- `systemctl` (Linux)
- `crontab` (Linux)

**Frontend Libraries:**
- React (loaded globally by PSWebHost)
- None required beyond framework

---

## File Structure

```
apps/WindowsAdmin/
├── app.yaml                                    # App configuration
├── menu.yaml                                   # Menu entries
├── app_init.ps1                                # Initialization
├── public/elements/
│   ├── windowsadmin-home/
│   │   ├── component.js                        # ✅ Working
│   │   └── style.css
│   ├── service-control/
│   │   └── component.js                        # 🟡 Stub
│   └── task-scheduler/
│       └── component.js                        # 🟡 Stub
└── routes/api/v1/
    ├── status/get.ps1                          # ✅ Working
    ├── system/
    │   ├── services/get.ps1                    # ✅ Working
    │   └── tasks/get.ps1                       # ✅ Working
    └── ui/elements/
        ├── windowsadmin-home/get.ps1           # ✅ Working
        ├── service-control/get.ps1             # ✅ Working
        └── task-scheduler/get.ps1              # ✅ Working
```

---

## Completion Estimates

| Phase | Estimated Effort | Complexity |
|-------|------------------|------------|
| Phase 1: Connect Frontend | 2-3 days | Low |
| Phase 2: Service Control | 3-5 days | Medium |
| Phase 3: Task Management | 5-7 days | High |
| Phase 4: Enhancements | 10-15 days | Medium |

**Total to MVP (Phases 1-2):** 5-8 days
**Total to Full Implementation (Phases 1-3):** 10-15 days

---

## Implementation Rating by Component

| Component | Completeness | Functionality | Quality | Overall |
|-----------|--------------|---------------|---------|---------|
| Home Dashboard | 100% | ✅ Working | A | **A** |
| Status API | 100% | ✅ Working | A | **A** |
| Services API | 100% | ✅ Working | A | **A** |
| Tasks API | 100% | ✅ Working | A | **A** |
| Service UI | 30% | ❌ Stub | B | **D** |
| Task UI | 30% | ❌ Stub | B | **D** |
| Control APIs | 0% | ❌ Missing | N/A | **F** |
| Overall App | 40% | 🟡 Partial | B | **C+** |

---

## Conclusion

The Windows Administration app has a **solid foundation** with fully functional backend APIs for reading service and task data. The primary blockers are:

1. **Frontend-backend disconnect:** UI components use mock data instead of real APIs
2. **Missing control operations:** No start/stop/restart/edit/delete functionality
3. **No mutation endpoints:** All current APIs are read-only

**Recommended Next Step:** Connect frontend components to existing backend APIs (Phase 1) to demonstrate working data flow, then implement service control operations (Phase 2) to achieve MVP status.

**Time to MVP:** 5-8 days of focused development
**Risk Level:** Low (foundation is solid, well-structured code)
**Maintainability:** High (follows PSWebHost patterns, clean separation of concerns)

---

## Code Refactoring Notice

**IMPORTANT:** This app contains Linux-specific code that should be extracted to a shared cross-platform module.

See: `LINUX_CODE_EXTRACTION_PLAN.md` for detailed extraction plan.

**Files with Linux Code:**
- `/routes/api/v1/system/services/get.ps1` (lines 51-72)
- `/routes/api/v1/system/tasks/get.ps1` (lines 71-105)
- `/routes/api/v1/system/services/{name}/start/post.ps1` (lines 67-88)
- `/routes/api/v1/system/services/{name}/stop/post.ps1` (lines 76-97)
- `/routes/api/v1/system/services/{name}/restart/post.ps1` (lines 76-97)

**Proposed Shared Module:** `PSCrossPlatformOSManagement.psm1`

**Status:** Pending coordination with LinuxAdmin agent before extraction.

**Benefits:**
- Eliminates code duplication between WindowsAdmin and LinuxAdmin apps
- Improves maintainability with single source of truth
- Enables easier testing and future enhancements
- Provides consistent cross-platform API
