# Card Endpoint Migration Plan
**Date**: 2026-02-03
**Goal**: Move all card endpoints from `/api/v1/ui/elements/` to `/cards/`

## Overview

Migrating card endpoints to a dedicated `/cards/` namespace for better separation between:
- **Card endpoints**: UI component configurations (JSON)
- **Data endpoints**: Business logic APIs (CRUD operations)

## URL Changes

### Core Cards
```
OLD: /api/v1/ui/elements/{card-name}
NEW: /cards/{card-name}

OLD: /api/v1/ui/elements/admin/{card-name}
NEW: /cards/admin/{card-name}
```

### App Cards
```
OLD: /apps/{app}/api/v1/ui/elements/{card-name}
NEW: /apps/{app}/cards/{card-name}
```

## Inventory

### Core Card Endpoints (13 files)
1. routes/api/v1/ui/elements/help-viewer/get.ps1 → routes/cards/help-viewer/get.ps1
2. routes/api/v1/ui/elements/job-status/get.ps1 → routes/cards/job-status/get.ps1
3. routes/api/v1/ui/elements/markdown-viewer/get.ps1 → routes/cards/markdown-viewer/get.ps1
4. routes/api/v1/ui/elements/nodes-manager/get.ps1 → routes/cards/nodes-manager/get.ps1
5. routes/api/v1/ui/elements/site-settings/get.ps1 → routes/cards/site-settings/get.ps1
6. routes/api/v1/ui/elements/system-status/get.ps1 → routes/cards/system-status/get.ps1
7. routes/api/v1/ui/elements/main-menu/get.ps1 → routes/cards/main-menu/get.ps1
8. routes/api/v1/ui/elements/event-stream/get.ps1 → routes/cards/event-stream/get.ps1
9. routes/api/v1/ui/elements/memory-explorer/get.ps1 → routes/cards/memory-explorer/get.ps1
10. routes/api/v1/ui/elements/system-log/get.ps1 → routes/cards/system-log/get.ps1
11. routes/api/v1/ui/elements/card-validation/get.ps1 → routes/cards/card-validation/get.ps1
12. routes/api/v1/ui/elements/admin/role-management/get.ps1 → routes/cards/admin/role-management/get.ps1
13. routes/api/v1/ui/elements/admin/users-management/get.ps1 → routes/cards/admin/users-management/get.ps1

### App Card Endpoints (29 files)

**UI_Uplot (7 cards)**
1. apps/UI_Uplot/routes/api/v1/ui/elements/uplot-home/get.ps1 → apps/UI_Uplot/routes/cards/uplot-home/get.ps1
2. apps/UI_Uplot/routes/api/v1/ui/elements/time-series/get.ps1 → apps/UI_Uplot/routes/cards/time-series/get.ps1
3. apps/UI_Uplot/routes/api/v1/ui/elements/area-chart/get.ps1 → apps/UI_Uplot/routes/cards/area-chart/get.ps1
4. apps/UI_Uplot/routes/api/v1/ui/elements/bar-chart/get.ps1 → apps/UI_Uplot/routes/cards/bar-chart/get.ps1
5. apps/UI_Uplot/routes/api/v1/ui/elements/scatter-plot/get.ps1 → apps/UI_Uplot/routes/cards/scatter-plot/get.ps1
6. apps/UI_Uplot/routes/api/v1/ui/elements/multi-axis/get.ps1 → apps/UI_Uplot/routes/cards/multi-axis/get.ps1
7. apps/UI_Uplot/routes/api/v1/ui/elements/heatmap/get.ps1 → apps/UI_Uplot/routes/cards/heatmap/get.ps1

**WebhostRealtimeEvents (1 card)**
8. apps/WebhostRealtimeEvents/routes/api/v1/ui/elements/realtime-events/get.ps1 → apps/WebhostRealtimeEvents/routes/cards/realtime-events/get.ps1

**WSLManager (2 cards)**
9. apps/WSLManager/routes/api/v1/ui/elements/wslmanager-home/get.ps1 → apps/WSLManager/routes/cards/wslmanager-home/get.ps1
10. apps/WSLManager/routes/api/v1/ui/elements/wsl-manager/get.ps1 → apps/WSLManager/routes/cards/wsl-manager/get.ps1

**SQLiteManager (2 cards)**
11. apps/SQLiteManager/routes/api/v1/ui/elements/sqlite-manager/get.ps1 → apps/SQLiteManager/routes/cards/sqlite-manager/get.ps1
12. apps/SQLiteManager/routes/api/v1/ui/elements/sqlite-query-editor/get.ps1 → apps/SQLiteManager/routes/cards/sqlite-query-editor/get.ps1

**vault (1 card)**
13. apps/vault/routes/api/v1/ui/elements/vault-manager/get.ps1 → apps/vault/routes/cards/vault-manager/get.ps1

**WindowsAdmin (3 cards)**
14. apps/WindowsAdmin/routes/api/v1/ui/elements/service-control/get.ps1 → apps/WindowsAdmin/routes/cards/service-control/get.ps1
15. apps/WindowsAdmin/routes/api/v1/ui/elements/task-scheduler/get.ps1 → apps/WindowsAdmin/routes/cards/task-scheduler/get.ps1
16. apps/WindowsAdmin/routes/api/v1/ui/elements/windowsadmin-home/get.ps1 → apps/WindowsAdmin/routes/cards/windowsadmin-home/get.ps1

**DockerManager (2 cards)**
17. apps/DockerManager/routes/api/v1/ui/elements/docker-manager/get.ps1 → apps/DockerManager/routes/cards/docker-manager/get.ps1
18. apps/DockerManager/routes/api/v1/ui/elements/dockermanager-home/get.ps1 → apps/DockerManager/routes/cards/dockermanager-home/get.ps1

**KubernetesManager (2 cards)**
19. apps/KubernetesManager/routes/api/v1/ui/elements/kubernetes-status/get.ps1 → apps/KubernetesManager/routes/cards/kubernetes-status/get.ps1
20. apps/KubernetesManager/routes/api/v1/ui/elements/kubernetesmanager-home/get.ps1 → apps/KubernetesManager/routes/cards/kubernetesmanager-home/get.ps1

**LinuxAdmin (3 cards)**
21. apps/LinuxAdmin/routes/api/v1/ui/elements/linux-cron/get.ps1 → apps/LinuxAdmin/routes/cards/linux-cron/get.ps1
22. apps/LinuxAdmin/routes/api/v1/ui/elements/linux-services/get.ps1 → apps/LinuxAdmin/routes/cards/linux-services/get.ps1
23. apps/LinuxAdmin/routes/api/v1/ui/elements/linuxadmin-home/get.ps1 → apps/LinuxAdmin/routes/cards/linuxadmin-home/get.ps1

**MySQLManager (1 card)**
24. apps/MySQLManager/routes/api/v1/ui/elements/mysql-manager/get.ps1 → apps/MySQLManager/routes/cards/mysql-manager/get.ps1

**RedisManager (1 card)**
25. apps/RedisManager/routes/api/v1/ui/elements/redis-manager/get.ps1 → apps/RedisManager/routes/cards/redis-manager/get.ps1

**SQLServerManager (1 card)**
26. apps/SQLServerManager/routes/api/v1/ui/elements/sqlserver-manager/get.ps1 → apps/SQLServerManager/routes/cards/sqlserver-manager/get.ps1

**Maps (1 card)**
27. apps/Maps/routes/api/v1/ui/elements/world-map/get.ps1 → apps/Maps/routes/cards/world-map/get.ps1

**WebHostMetrics (2 cards)**
28. apps/WebHostMetrics/routes/api/v1/ui/elements/memory-histogram/get.ps1 → apps/WebHostMetrics/routes/cards/memory-histogram/get.ps1
29. apps/WebHostMetrics/routes/api/v1/ui/elements/server-heatmap/get.ps1 → apps/WebHostMetrics/routes/cards/server-heatmap/get.ps1

**WebhostFileExplorer (4 cards)**
30. apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-explorer/get.ps1 → apps/WebhostFileExplorer/routes/cards/file-explorer/get.ps1
31. apps/WebhostFileExplorer/routes/api/v1/ui/elements/text-editor/get.ps1 → apps/WebhostFileExplorer/routes/cards/text-editor/get.ps1
32. apps/WebhostFileExplorer/routes/api/v1/ui/elements/hex-editor/get.ps1 → apps/WebhostFileExplorer/routes/cards/hex-editor/get.ps1
33. apps/WebhostFileExplorer/routes/api/v1/ui/elements/file-sharing-modal/get.ps1 → apps/WebhostFileExplorer/routes/cards/file-sharing-modal/get.ps1

**WebHostDebugExtensions (1 card)**
34. apps/WebHostDebugExtensions/routes/api/v1/ui/elements/debug-console/get.ps1 → apps/WebHostDebugExtensions/routes/cards/debug-console/get.ps1

**WebHostAppManager (1 card)**
35. apps/WebHostAppManager/routes/api/v1/ui/elements/apps-manager/get.ps1 → apps/WebHostAppManager/routes/cards/apps-manager/get.ps1

**WebHostDebugVariables (1 card)**
36. apps/WebHostDebugVariables/routes/api/v1/ui/elements/debug-variables/get.ps1 → apps/WebHostDebugVariables/routes/cards/debug-variables/get.ps1

**WebHostHelpViewer (1 card)**
37. apps/WebHostHelpViewer/routes/api/v1/ui/elements/help-viewer/get.ps1 → apps/WebHostHelpViewer/routes/cards/help-viewer/get.ps1

**WebHostTaskManagement (1 card)**
38. apps/WebHostTaskManagement/routes/api/v1/ui/elements/task-manager/get.ps1 → apps/WebHostTaskManagement/routes/cards/task-manager/get.ps1

**UnitTests (1 card)**
39. apps/UnitTests/routes/api/v1/ui/elements/unit-test-runner/get.ps1 → apps/UnitTests/routes/cards/unit-test-runner/get.ps1

**Total: 42 card endpoints**

## Files Requiring Updates

### Configuration Files
- routes/api/v1/ui/elements/main-menu/main-menu.yaml (13 URL references)
- apps/*/menu.yaml (19 files, ~40 URL references)

### Frontend JavaScript Files
- public/psweb_spa.js (card loading logic)
- public/*.html (hardcoded card URLs)
- apps/*/public/**/*.js (component files)
- apps/*/public/**/*.html (HTML files)

### PowerShell Backend Files
- Any .ps1 files that redirect or reference card URLs
- Test files
- Documentation

### Documentation
- README.md files
- Architecture.md files
- API.md files

## Migration Process (Per Endpoint)

For each card endpoint:
1. **Create new directory structure**
2. **Move the get.ps1 file**
3. **Move associated files** (main-menu.yaml, component.js, styles.css, etc.)
4. **Find all references** to old URL path
5. **Update all references** to new URL path
6. **Verify** no broken references remain

## Execution Order

1. Core cards first (most referenced)
2. App cards by app (grouped migration)
3. Final verification pass

## Rollback Plan

If issues arise:
- Git revert available
- Old directory structure preserved temporarily
- Can run both old and new paths simultaneously with routing aliases

---

## Status: Ready to Execute
**Next**: Begin migration with main-menu card (most critical)
