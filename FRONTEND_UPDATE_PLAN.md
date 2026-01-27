# Frontend Update Plan - Task Manager Component

## Summary
Update the task-manager component to integrate with the new PSWebHost_Jobs system, adding job catalog browsing and improved job management.

## Changes Required

### 1. State Updates
Add to component state:
```javascript
{
    currentView: 'tasks' | 'jobs' | 'catalog' | 'results' | 'runspaces',
    catalog: [],           // Job catalog from new system
    showStartModal: false, // Start job modal visibility
    selectedCatalogJob: null, // Job selected for starting
    jobVariables: {}       // Template variables for job start
}
```

### 2. New API Calls
- `loadCatalog()` - GET /api/v1/jobs/catalog
- `startJob(jobId, variables)` - POST /api/v1/jobs/start
- `stopJob(jobId)` - POST /api/v1/jobs/stop

### 3. New UI Views
- **Job Catalog View**: Browse available jobs, see permissions, start jobs
- **Job Start Modal**: Input template variables when starting a job

### 4. Menu Updates
Add "Job Catalog" menu item:
```javascript
{ id: 'catalog', icon: '📦', label: 'Job Catalog' }
```

### 5. Job Catalog View Features
- List all jobs from apps/*/jobs/
- Show job metadata (name, description, schedule)
- Display template variables
- Show user permissions (can start/stop/restart)
- Role badges
- "Start Job" button (opens modal if variables needed)
- Schedule display

### 6. Job Start Modal Features
- Job name and description
- Template variable inputs (dynamic based on job)
- Variable descriptions/hints
- Validation
- Start button
- Cancel button

## API Endpoints Created
- ✅ GET `/apps/WebHostTaskManagement/api/v1/jobs/catalog`
- ✅ POST `/apps/WebHostTaskManagement/api/v1/jobs/start`
- ✅ POST `/apps/WebHostTaskManagement/api/v1/jobs/stop`

## Implementation Steps

1. Update state initialization
2. Add loadCatalog() method
3. Add startJob() and stopJob() methods
4. Update menu to include catalog view
5. Create renderCatalogView() method
6. Create renderStartJobModal() method
7. Update render() to show start modal
8. Add event listeners for new buttons
9. Update styles for new elements

## File Locations
- Component: `apps/WebHostTaskManagement/public/elements/task-manager/component.js`
- Styles: `apps/WebHostTaskManagement/public/elements/task-manager/style.css`
- API Endpoints: `apps/WebHostTaskManagement/routes/api/v1/jobs/`
