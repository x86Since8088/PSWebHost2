# PSWebHost Migration Roadmap

**Last Updated**: 2026-01-16
**Current Phase**: Phase 2 - Core App Migrations

---

## Overview

This document tracks the migration of PSWebHost to a fully modular app-based architecture with standardized patterns for initialization, routing, and task scheduling.

---

## Phase 1: Pattern Establishment ✅ COMPLETE

**Timeline**: 2026-01-01 to 2026-01-16
**Status**: ✅ **COMPLETE**

### Completed Tasks

- [x] **App framework pattern defined**
  - Standard app structure documented
  - app.yaml manifest format
  - app_init.ps1 initialization pattern

- [x] **Routing pattern established**
  - Apps use `/apps/AppName/` prefix
  - Route security via .security.json files
  - Component paths explicitly specified

- [x] **Reference migrations completed**
  - WebHostMetrics fully migrated
  - WebhostRealtimeEvents migrated
  - Documented in individual MIGRATION.md files

- [x] **System cleanup**
  - Removed app-specific code from system/init.ps1
  - App framework auto-discovers app_init.ps1 files
  - Module paths auto-configured

- [x] **Documentation created**
  - ARCHITECTURE.md (system-wide)
  - Per-app ARCHITECTURE.md files
  - MIGRATION.md for migrated apps

### Lessons Learned

**What Worked Well**:
- App-specific initialization in app_init.ps1 keeps system/init.ps1 clean
- Explicit component paths prevent routing confusion
- Test mode (-Test switch) makes endpoint testing easy

**Challenges**:
- Legacy component references in old locations
- Need clear decommissioning timeline
- Multiple naming patterns (kebab-case vs PascalCase)

---

## Phase 2: Core App Migrations 🔄 IN PROGRESS

**Timeline**: 2026-01-17 to 2026-02-15
**Status**: 🔄 **IN PROGRESS**

### Goals

1. Standardize all existing apps to app framework pattern
2. Verify route prefixes for all apps
3. Move UI components to app directories
4. Implement task scheduling system

### Priority Matrix

#### 🔴 High Priority (Critical Apps)

| App | Status | Route Prefix | app_init.ps1 | UI in App | Tasks | Owner |
|-----|--------|--------------|--------------|-----------|-------|-------|
| **vault** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **SQLiteManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **UI_Uplot** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **UnitTests** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | N/A | - |

#### 🟡 Medium Priority (Infrastructure Apps)

| App | Status | Route Prefix | app_init.ps1 | UI in App | Tasks | Owner |
|-----|--------|--------------|--------------|-----------|-------|-------|
| **DockerManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **KubernetesManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **WindowsAdmin** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **LinuxAdmin** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **WSLManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |

#### 🟢 Low Priority (Database Apps)

| App | Status | Route Prefix | app_init.ps1 | UI in App | Tasks | Owner |
|-----|--------|--------------|--------------|-----------|-------|-------|
| **MySQLManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **SQLServerManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |
| **RedisManager** | 🔄 Review needed | ❓ Verify | ✅ Yes | ✅ Yes | ⭕ Add | - |

### New Apps to Create

| App | Purpose | Priority | Status | Target Date |
|-----|---------|----------|--------|-------------|
| **WebHostTaskManagement** | Task scheduler UI and management | 🔴 High | 📋 Planned | 2026-01-20 |

### Migration Checklist (Per App)

For each app, complete these steps:

- [ ] **1. Audit Current State**
  - [ ] List all routes and verify they use `/apps/AppName/` prefix
  - [ ] Check for routes in core `routes/` directory (should not exist)
  - [ ] Verify UI components are in app's `public/elements/` directory
  - [ ] Check for components in core `public/elements/` (mark for deprecation)
  - [ ] Document current background jobs

- [ ] **2. Standardize Structure**
  - [ ] Create `config/` directory
  - [ ] Create `config/default/` with default configuration
  - [ ] Add `config/tasks.yaml` if app needs scheduled tasks
  - [ ] Ensure `README.md` exists with user documentation
  - [ ] Create `ARCHITECTURE.md` if complex app

- [ ] **3. Add Task Support** (if needed)
  - [ ] Identify tasks that should be scheduled
  - [ ] Create `tasks/` directory in app root
  - [ ] Write task scripts following standard pattern
  - [ ] Define tasks in `config/tasks.yaml`
  - [ ] Test tasks with task engine

- [ ] **4. Update Code**
  - [ ] Verify all fetch/API calls use app-prefixed paths
  - [ ] Update component references in layout.json
  - [ ] Add test mode support to all endpoints (-Test switch)
  - [ ] Update any hardcoded paths

- [ ] **5. Testing**
  - [ ] Test all API endpoints
  - [ ] Test UI components load correctly
  - [ ] Test background jobs (if any)
  - [ ] Test scheduled tasks (if any)
  - [ ] Run existing tests in `tests/` directory

- [ ] **6. Documentation**
  - [ ] Update app's README.md
  - [ ] Create/update ARCHITECTURE.md
  - [ ] Document API endpoints
  - [ ] Document configuration options
  - [ ] Add troubleshooting section

- [ ] **7. Deprecation**
  - [ ] Mark old files/directories for decommission
  - [ ] Add to decommission schedule
  - [ ] Update COMPONENT_DECOMMISSIONING_PLAN.md

### Weekly Goals

#### Week of 2026-01-20
- [ ] Create WebHostTaskManagement app
- [ ] Implement PSWebHostTasks module
- [ ] Review and standardize vault app
- [ ] Review and standardize UI_Uplot app

#### Week of 2026-01-27
- [ ] Review and standardize SQLiteManager
- [ ] Review and standardize DockerManager
- [ ] Review and standardize WindowsAdmin
- [ ] Test task engine with multiple apps

#### Week of 2026-02-03
- [ ] Review and standardize remaining database apps
- [ ] Review and standardize LinuxAdmin/WSLManager
- [ ] Complete all route prefix verifications

#### Week of 2026-02-10
- [ ] Final testing of all apps
- [ ] Documentation review
- [ ] Prepare for Phase 3 cleanup

---

## Phase 3: Cleanup & Decommissioning 📋 PLANNED

**Timeline**: 2026-02-16 to 2026-03-01
**Status**: 📋 **PLANNED**

### Goals

1. Remove all deprecated code and directories
2. Clean up legacy route handlers
3. Optimize app loading and initialization
4. Performance tuning

### Decommission Schedule

#### Week of 2026-01-23 (After WebHostMetrics stabilization)

**Safe to Delete**:
```
modules/PSWebHost_Metrics/          → Moved to apps/WebHostMetrics/modules/
routes/api/v1/metrics/              → Moved to apps/WebHostMetrics/routes/
public/elements/server-heatmap/     → Moved to apps/WebHostMetrics/public/
public/elements/event-stream/       → Replaced by realtime-events
public/elements/realtime-events/    → Moved to apps/WebhostRealtimeEvents/public/
```

**Procedure**:
```powershell
# 1. Rename to mark as deprecated (safety measure)
Rename-Item modules/PSWebHost_Metrics modules/_DEPRECATED_PSWebHost_Metrics
Rename-Item routes/api/v1/metrics routes/api/v1/_DEPRECATED_metrics
Rename-Item public/elements/server-heatmap public/elements/_DEPRECATED_server-heatmap

# 2. Test for 48 hours - verify no errors

# 3. Move to archive
$archiveDir = "archive/deprecated-2026-01-23"
New-Item -Path $archiveDir -ItemType Directory
Move-Item modules/_DEPRECATED_* $archiveDir/
Move-Item routes/api/v1/_DEPRECATED_* $archiveDir/
Move-Item public/elements/_DEPRECATED_* $archiveDir/

# 4. After 30 days - delete archive
Remove-Item $archiveDir -Recurse -Force
```

#### Week of 2026-02-16 (After all apps standardized)

**Review for Deletion**:
- Any remaining routes in `routes/` not in `routes/api/v1/session|registration|debug`
- Any remaining UI components in `public/elements/` not part of core UI
- Legacy initialization code if any remains

### Optimization Tasks

- [ ] Profile app loading times
- [ ] Optimize module imports (lazy loading?)
- [ ] Review global state structure for consolidation
- [ ] Database query optimization
- [ ] Implement response caching where appropriate
- [ ] Review and optimize background job memory usage

---

## Phase 4: Task Engine & Advanced Features 💡 FUTURE

**Timeline**: 2026-03-01 onwards
**Status**: 💡 **FUTURE**

### Planned Features

#### Task Engine Enhancements
- [ ] Web UI for task management (WebHostTaskManagement app)
- [ ] Task dependency chains (Task B runs after Task A)
- [ ] Task output streaming to UI
- [ ] Email notifications on task failure
- [ ] Task execution history dashboard
- [ ] Manual task triggering from UI

#### App Store / Registry
- [ ] App marketplace/catalog
- [ ] One-click app installation
- [ ] App versioning and updates
- [ ] App dependency resolution
- [ ] App templates in registry

#### Advanced Monitoring
- [ ] Real-time metrics WebSocket streaming
- [ ] Alert system for threshold breaches
- [ ] Metrics aggregation and downsampling
- [ ] Long-term metrics storage (TimescaleDB?)
- [ ] Metrics dashboard builder

#### Developer Experience
- [ ] App scaffolding CLI: `New-PSWebHostApp -Name MyApp`
- [ ] Live reload for development
- [ ] Better error reporting and debugging
- [ ] API documentation generator
- [ ] Automated testing framework

#### Security Enhancements
- [ ] API key management
- [ ] OAuth/SSO integration
- [ ] Rate limiting per app
- [ ] Audit logging for sensitive operations
- [ ] Role-based field-level permissions

---

## Success Metrics

### Phase 1 Metrics ✅ ACHIEVED
- [x] 2 reference apps fully migrated
- [x] 0 app-specific code in system/init.ps1
- [x] 100% of active components use explicit paths
- [x] Full documentation coverage for pattern

### Phase 2 Metrics 🎯 TARGETS
- [ ] 100% of apps follow standard structure (14 apps)
- [ ] 100% of routes use app prefix
- [ ] Task engine functional for 3+ apps
- [ ] 0 routes in core routes/ directory (except auth/debug)
- [ ] All apps have config/tasks.yaml (if applicable)

### Phase 3 Metrics 🎯 TARGETS
- [ ] 0 deprecated directories in codebase
- [ ] 0 legacy component references
- [ ] App loading time < 2 seconds
- [ ] All apps have comprehensive tests

---

## Risk Assessment

### High Risk Items 🔴

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Breaking existing functionality during migration | High | Medium | - Test mode for all endpoints<br>- Incremental migration<br>- Keep old files until verified |
| Task engine bugs affecting server stability | High | Medium | - Comprehensive error handling<br>- Task termination rules<br>- Isolated job execution |
| Performance degradation with task engine | Medium | Low | - Minute-based evaluation only<br>- Job cleanup<br>- Resource monitoring |

### Medium Risk Items 🟡

| Risk | Impact | Probability | Mitigation |
|------|--------|-------------|------------|
| Inconsistent app patterns across apps | Medium | Medium | - Clear documentation<br>- App templates<br>- Code review checklist |
| Old route references in external docs/scripts | Medium | Low | - Grep for old paths<br>- Update docs proactively |
| Database schema changes during migration | Medium | Low | - Schema versioning<br>- Migration scripts |

---

## Rollback Procedures

### If Phase 2 Migration Fails

**For a specific app**:
```powershell
# 1. Disable app
# Edit apps/AppName/app.yaml
enabled: false

# 2. Restart server to stop app jobs

# 3. Restore old files if needed
git checkout HEAD~1 -- routes/api/v1/appresource/
git checkout HEAD~1 -- public/elements/appcomponent/

# 4. Update layout.json to point to old paths

# 5. Restart server
```

**For task engine**:
```powershell
# 1. Comment out task engine call in WebHost.ps1
# if ((Get-Date).Second -eq 0) {
#     Invoke-PsWebHostTaskEngine
# }

# 2. Stop all task jobs
Get-Job | Where-Object { $_.Name -like "Task_*" } | Stop-Job

# 3. Restart server
```

---

## Communication Plan

### Stakeholder Updates

**Weekly Status Updates** (Every Friday):
- Progress on migration checklist
- Issues encountered and resolutions
- Upcoming week's focus

**Major Milestone Announcements**:
- Phase completion
- New feature availability (task engine)
- Decommission warnings (1 week before)

---

## Resources

### Documentation
- [ARCHITECTURE.md](./ARCHITECTURE.md) - System architecture
- [NAMING_CONVENTIONS.md](./NAMING_CONVENTIONS.md) - Naming standards
- [FEATURE_INDEX.md](./FEATURE_INDEX.md) - Feature location map
- [apps/APP_INITIALIZATION_STATUS.md](./apps/APP_INITIALIZATION_STATUS.md) - App init status

### Tools
- **Test Mode**: All endpoints support `-Test` switch
- **App Template**: `modules/PSWebHostAppManagement/New_App_Template/`
- **Task Templates**: `system/tasks/templates/`

### Support
- GitHub Issues: [https://github.com/user/pswebhost/issues](./issues)
- Discussion: Team channel
- Documentation: This file and ARCHITECTURE.md

---

## Change Log

### 2026-01-16
- Created initial migration roadmap
- Documented Phase 1 completion
- Defined Phase 2 scope and goals
- Added WebHostTaskManagement to app creation list

---

**Document Status**: Living Document - Update weekly
**Next Review**: 2026-01-20 (Weekly status meeting)
**Owner**: System Architect
