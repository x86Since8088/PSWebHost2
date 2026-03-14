# Frontend Update Summary - Task Manager Component

## ✅ Completed Updates

### 1. API Endpoints Created
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/catalog` (GET) - Browse available jobs
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/start` (POST) - Start a job
- ✅ `/apps/WebHostTaskManagement/api/v1/jobs/stop` (POST) - Stop a job
- ✅ Security.json files for all endpoints

### 2. Component State Updated
- ✅ Added `catalog: []` for job catalog data
- ✅ Added `selectedCatalogJob: null` for job selection
- ✅ Added `showStartModal: false` for start modal visibility
- ✅ Added `jobVariables: {}` for template variable inputs
- ✅ Changed default view to 'catalog'

### 3. Data Loading Updated
- ✅ Added `loadCatalog()` method
- ✅ Updated `loadData()` switch to include 'catalog' case

### 4. Job Control Methods Added
- ✅ `openStartJobModal(job)` - Open start modal with job details
- ✅ `closeStartJobModal()` - Close start modal
- ✅ `updateJobVariable(varName, value)` - Update template variable
- ✅ `startJobFromCatalog(job, variables)` - Start job via API
- ✅ `stopJobFromCatalog(jobId)` - Stop job via API

### 5. Menu Updated
- ✅ Added 'Job Catalog' menu item
- ✅ Reordered menu: Catalog, Jobs, Results, Tasks, Runspaces
- ✅ Updated icons and labels

### 6. Content Routing Updated
- ✅ Updated `renderContent()` switch to include 'catalog' case

## 📋 Remaining Tasks

### 1. Add Render Methods
Need to add these two methods to component.js:

**Location:** After `renderTasksView()` method (around line 490)

```javascript
renderCatalogView() {
    // See CATALOG_VIEW_CODE.js for full implementation
}
```

**Location:** After `renderOutputModal()` method (around line 380)

```javascript
renderStartJobModal() {
    // See CATALOG_VIEW_CODE.js for full implementation
}
```

### 2. Update Main render() Method
**Location:** Around line 345

Change:
```javascript
${this.state.showOutputModal ? this.renderOutputModal() : ''}
```

To:
```javascript
${this.state.showOutputModal ? this.renderOutputModal() : ''}
${this.state.showStartModal ? this.renderStartJobModal() : ''}
```

### 3. Add Event Listeners
**Location:** In `attachEventListeners()` method (around line 850)

Add:
```javascript
// Start job from catalog
this.shadowRoot.querySelectorAll('[data-start-job]').forEach(btn => {
    btn.addEventListener('click', (e) => {
        const jobIndex = e.target.dataset.jobIndex;
        const job = this.state.catalog[parseInt(jobIndex)];
        if (job) {
            if (job.templateVariables && job.templateVariables.length > 0) {
                this.openStartJobModal(job);
            } else {
                // Start immediately if no variables needed
                this.startJobFromCatalog(job, {});
            }
        }
    });
});

// Close start modal
this.shadowRoot.querySelectorAll('[data-close-start-modal]').forEach(btn => {
    btn.addEventListener('click', () => this.closeStartJobModal());
});

// Confirm start job
this.shadowRoot.querySelectorAll('[data-confirm-start-job]').forEach(btn => {
    btn.addEventListener('click', () => {
        const job = this.state.selectedCatalogJob;
        const variables = { ...this.state.jobVariables };
        this.startJobFromCatalog(job, variables);
    });
});

// Update job variables
this.shadowRoot.querySelectorAll('[data-variable-name]').forEach(input => {
    input.addEventListener('input', (e) => {
        this.updateJobVariable(e.target.dataset.variableName, e.target.value);
    });
});
```

### 4. Optional: Add Styles for New Elements
**Location:** `style.css`

Add if needed:
```css
.form-input {
    width: 100%;
    padding: 8px 12px;
    border: 1px solid var(--tm-border);
    border-radius: 4px;
    font-size: 14px;
    background: var(--tm-bg);
    color: var(--tm-text);
}

.form-input:focus {
    outline: none;
    border-color: var(--tm-primary);
}

.badge-secondary {
    background: var(--tm-bg-secondary);
    color: var(--tm-text-secondary);
}
```

## 🔍 How to Apply Remaining Changes

### Option 1: Manual Integration (Recommended for Review)
1. Open `CATALOG_VIEW_CODE.js`
2. Copy `renderCatalogView()` method
3. Insert after `renderTasksView()` in `component.js`
4. Copy `renderStartJobModal()` method
5. Insert after `renderOutputModal()` in `component.js`
6. Update `render()` method to include start modal
7. Add event listeners to `attachEventListeners()`

### Option 2: Complete File Replacement
Create a new version of component.js with all changes integrated.

## 🧪 Testing Checklist

Once changes are applied:

- [ ] Server running with PSWebHost_Jobs module loaded
- [ ] Navigate to Task Manager component
- [ ] Verify "Job Catalog" appears in menu
- [ ] Click "Job Catalog" - should see WebHostMetrics/CollectMetrics
- [ ] Click "Start" button - should open modal with Interval variable
- [ ] Enter interval value (e.g., "30")
- [ ] Click "Start Job" - should succeed
- [ ] Navigate to "Active Jobs" - should see running job
- [ ] Test stopping job
- [ ] Verify permissions (try with non-admin user if possible)

## 📝 Files Modified

### Backend
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/catalog/get.ps1`
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/catalog/get.security.json`
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/start/post.ps1`
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/start/post.security.json`
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/stop/post.ps1`
- ✅ `apps/WebHostTaskManagement/routes/api/v1/jobs/stop/post.security.json`

### Frontend
- ⚠️ `apps/WebHostTaskManagement/public/elements/task-manager/component.js` (Partially updated)
  - ✅ State updated
  - ✅ Load methods added
  - ✅ Job control methods added
  - ✅ Menu updated
  - ⏳ Render methods need to be added
  - ⏳ Event listeners need to be added
- ⏳ `apps/WebHostTaskManagement/public/elements/task-manager/style.css` (Optional updates)

## 🚀 Quick Start After Integration

1. Ensure server is running with PSWebHost_Jobs module loaded
2. Navigate to http://localhost:8080
3. Open Task Management card
4. Default view should now be "Job Catalog"
5. You should see "WebHostMetrics/CollectMetrics" job
6. Click "Start" to open the job start modal
7. Enter an interval (e.g., "15" for 15 seconds)
8. Click "Start Job" to launch it
9. Switch to "Active Jobs" to see it running
10. Use "Stop" button to stop the job

## 💡 Key Features Implemented

- **Job Catalog Browsing**: View all available jobs from apps/*/jobs/
- **Permission Display**: See which jobs you can start/stop/restart
- **Template Variables**: Dynamic input fields for job configuration
- **Role-Based Access**: Permissions enforced per-job
- **Job Start Modal**: Clean UI for configuring and starting jobs
- **Job Control**: Start/stop jobs directly from the UI
- **Real-time Updates**: Auto-refresh every 5 seconds

## 🔐 Security Features

- All endpoints require authentication
- Per-job permission checking based on job.json roles
- User roles passed from session to API
- 403 Forbidden responses for unauthorized actions
- Permission badges in UI show what user can do

## 📊 Data Flow

1. **Catalog Loading**: Component calls `/api/v1/jobs/catalog`
2. **Permission Check**: Server checks user roles against job.json
3. **Display**: Component shows jobs with appropriate controls
4. **Start Job**: User clicks Start → Modal opens (if variables needed)
5. **Submit**: Component posts to `/api/v1/jobs/start` with variables
6. **Execution**: Server starts job via PSWebHost_Jobs module
7. **Queue Processing**: Main loop processes command queue
8. **Status**: Job appears in "Active Jobs" view

## 🎯 Next Steps

1. Complete the render method integration (see above)
2. Test with the running server
3. Verify job start/stop functionality
4. Add more example jobs to demonstrate features
5. Consider adding job scheduling UI
6. Add job history viewing
