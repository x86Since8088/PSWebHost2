# Implementation Pending Items

This document tracks components and features that are not yet fully implemented.

## Components with "Implementation Pending" Status

### 1. Task Scheduler (WindowsAdmin)
**File**: `apps/WindowsAdmin/public/elements/task-scheduler/component.js:72`
**Status**: Mock UI only
**TODO**:
- Fetch from `/api/v1/system/tasks`
- Implement task creation, editing, deletion
- Add scheduling interface

### 2. Docker Manager
**File**: `apps/DockerManager/public/elements/docker-manager/component.js:63`
**Status**: Mock UI only
**TODO**:
- Fetch from Docker API via `/api/v1/docker/...`
- Implement container management (start/stop/restart)
- Add image management
- Volume and network configuration

### 3. Database Status
**File**: `public/elements/database-status/component.js:75`
**Status**: Mock UI only
**TODO**:
- Fetch from `/api/v1/database/status`
- Show connection status for all databases
- Display query performance metrics
- Add database health monitoring

### 4. Role Management
**File**: `public/elements/admin/role-management/component.js:115`
**Status**: Read-only mock data
**TODO**:
- Fetch from `/api/v1/admin/roles`
- Implement role creation/editing/deletion
- Permission mapping interface
- User-to-role assignment

### 5. Site Settings
**File**: `public/elements/site-settings/component.js:111`
**Status**: Mock UI only
**TODO**:
- Fetch from `/api/v1/settings`
- Implement settings persistence
- Add validation for configuration values
- Hot-reload capability for settings changes

## Library TODOs

### Chart.js Integration
**File**: `public/elements/chartjs/component.js:181`
**TODO**: Add YAML parser for chart configurations

### Metrics Fetcher
**File**: `public/lib/metrics-fetcher.js:281`
**TODO**: Implement selective cache deletion (currently clears all cache)

### SQL.js
**File**: `public/lib/sql-wasm.js:13`
**TODO**: Avoid declaring global variables in browser context

## Backend Endpoints Needed

The following endpoints are referenced in components but may not exist:

1. `/api/v1/system/tasks` (GET) - Task scheduler data
2. `/api/v1/docker/...` (various) - Docker management API
3. `/api/v1/database/status` (GET) - Database health status
4. `/api/v1/admin/roles` (GET/POST/PUT/DELETE) - Role management CRUD
5. `/api/v1/settings` (GET/POST) - Site-wide settings management

## Priority Recommendations

### High Priority
- **Role Management**: Critical for security and access control
- **Site Settings**: Required for production configuration

### Medium Priority
- **Database Status**: Useful for monitoring and troubleshooting
- **Task Scheduler**: Automation and scheduled operations

### Low Priority
- **Docker Manager**: Specialized use case
- **Library TODOs**: Nice-to-have optimizations

## Notes

- Most stub components have mock data structures in place
- UI designs are generally complete, only backend integration needed
- All components have proper error handling and loading states
- Components follow consistent React patterns with the rest of the application

---

**Last Updated**: 2026-01-12
