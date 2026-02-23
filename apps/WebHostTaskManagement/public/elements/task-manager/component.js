/**
 * Task Manager Component
 *
 * Main UI for managing scheduled tasks, background jobs, and runspaces
 * Features left-side navigation menu for switching between views
 */

class TaskManagerComponent extends HTMLElement {
    constructor() {
        super();
        this.attachShadow({ mode: 'open' });

        this.state = {
            currentView: 'catalog',  // 'tasks', 'jobs', 'catalog', 'runspaces', or 'results'
            loading: false,
            tasks: [],
            jobs: {
                pending: [],
                running: [],
                completed: []
            },
            catalog: [],           // Job catalog from new PSWebHost_Jobs system
            runspaces: [],
            results: [],
            error: null,
            selectedTask: null,
            selectedResult: null,
            selectedJob: null,
            selectedCatalogJob: null,  // Job selected from catalog for starting
            showOutputModal: false,
            showStartModal: false,     // Start job modal visibility
            jobVariables: {},          // Template variables for job start
            liveOutput: ''
        };

        this.refreshInterval = null;
    }

    connectedCallback() {
        this.render();
        this.loadData();
        this.startAutoRefresh();
    }

    disconnectedCallback() {
        this.stopAutoRefresh();
    }

    startAutoRefresh() {
        // Refresh every 5 seconds
        this.refreshInterval = setInterval(() => {
            this.loadData();
        }, 5000);
    }

    stopAutoRefresh() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
            this.refreshInterval = null;
        }
    }

    async loadData() {
        try {
            // Load data based on current view
            switch (this.state.currentView) {
                case 'tasks':
                    await this.loadTasks();
                    break;
                case 'jobs':
                    await this.loadJobs();
                    break;
                case 'catalog':
                    await this.loadCatalog();
                    break;
                case 'runspaces':
                    await this.loadRunspaces();
                    break;
                case 'results':
                    await this.loadResults();
                    break;
            }
        } catch (error) {
            console.error('[TaskManager] Failed to load data:', error);
            this.setState({ error: error.message });
        }
    }

    async loadTasks() {
        const response = await fetch('/apps/WebHostTaskManagement/api/v1/tasks');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        this.setState({ tasks: data.tasks || [], error: null });
    }

    async loadJobs() {
        const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        this.setState({
            jobs: data.jobs || { pending: [], running: [], completed: [] },
            error: null
        });
    }

    async loadCatalog() {
        try {
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs/catalog');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            const data = await response.json();

            // Ensure jobs is always an array
            const jobs = Array.isArray(data.jobs) ? data.jobs : [];

            window.logToServer(`Loaded catalog: ${jobs.length} jobs`, 'TaskManager', 'Info');
            this.setState({ catalog: jobs, error: null });
        } catch (error) {
            window.logToServer(`Failed to load catalog: ${error.message}`, 'TaskManager', 'Error', { error: error.toString() });
            this.setState({ catalog: [], error: error.message });
        }
    }

    async stopJob(jobId) {
        if (!confirm('Are you sure you want to stop this job?')) return;

        try {
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs/stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ jobId: jobId })
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            const result = await response.json();
            if (!result.success) throw new Error(result.error || 'Failed to stop job');

            // Refresh job list
            await this.loadJobs();
        } catch (error) {
            console.error('[TaskManager] Failed to stop job:', error);
            this.setState({ error: error.message });
        }
    }

    async viewJobOutput(jobId) {
        try {
            this.setState({ selectedJob: jobId, showOutputModal: true, liveOutput: 'Loading...' });

            const response = await fetch(`/apps/WebHostTaskManagement/api/v1/jobs/output?jobId=${jobId}`);
            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            const data = await response.json();

            if (data.success) {
                this.setState({ liveOutput: data.output || '(No output yet)' });
            } else {
                this.setState({ liveOutput: data.message || 'Output not available' });
            }
        } catch (error) {
            console.error('[TaskManager] Failed to get job output:', error);
            this.setState({ liveOutput: `Error: ${error.message}` });
        }
    }

    closeOutputModal() {
        this.setState({ showOutputModal: false, selectedJob: null, liveOutput: '' });
    }

    openStartJobModal(job) {
        // Initialize variables with empty values
        const variables = {};
        if (job.templateVariables && job.templateVariables.length > 0) {
            job.templateVariables.forEach(v => {
                variables[v.name] = '';
            });
        }

        this.setState({
            showStartModal: true,
            selectedCatalogJob: job,
            jobVariables: variables
        });
    }

    closeStartJobModal() {
        this.setState({
            showStartModal: false,
            selectedCatalogJob: null,
            jobVariables: {}
        });
    }

    updateJobVariable(varName, value) {
        const newVariables = { ...this.state.jobVariables };
        newVariables[varName] = value;
        this.setState({ jobVariables: newVariables });
    }

    async startJobFromCatalog(job, variables) {
        try {
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs/start', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    jobId: job.jobId,
                    variables: variables || {}
                })
            });

            if (!response.ok) {
                const data = await response.json();
                throw new Error(data.error || `HTTP ${response.status}`);
            }

            const data = await response.json();

            // Close modal and show success
            this.closeStartJobModal();
            alert(`Job started successfully!\nExecution ID: ${data.executionId}`);

            // Refresh jobs list
            if (this.state.currentView === 'jobs') {
                await this.loadJobs();
            }
        } catch (error) {
            console.error('[TaskManager] Failed to start job:', error);
            alert('Failed to start job: ' + error.message);
        }
    }

    async stopJobFromCatalog(jobId) {
        if (!confirm(`Stop job ${jobId}?`)) return;

        try {
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs/stop', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ jobId: jobId })
            });

            if (!response.ok) {
                const data = await response.json();
                throw new Error(data.error || `HTTP ${response.status}`);
            }

            alert('Job stop command queued successfully');

            // Refresh jobs list
            if (this.state.currentView === 'jobs') {
                await this.loadJobs();
            }
        } catch (error) {
            console.error('[TaskManager] Failed to stop job:', error);
            alert('Failed to stop job: ' + error.message);
        }
    }

    async deleteJob(jobId) {
        if (!confirm('Are you sure you want to delete this job result?')) return;

        try {
            const response = await fetch(`/apps/WebHostTaskManagement/api/v1/jobs?jobId=${jobId}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            // Refresh job list
            await this.loadJobs();
        } catch (error) {
            console.error('[TaskManager] Failed to delete job:', error);
            this.setState({ error: error.message });
        }
    }

    async loadRunspaces() {
        const response = await fetch('/apps/WebHostTaskManagement/api/v1/runspaces');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        this.setState({ runspaces: data.runspaces || [], error: null });
    }

    async loadResults() {
        const response = await fetch('/apps/WebHostTaskManagement/api/v1/jobs/results?maxResults=100');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        this.setState({ results: data.results || [], error: null });
    }

    async toggleTaskEnabled(task) {
        try {
            const response = await fetch('/apps/WebHostTaskManagement/api/v1/tasks', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    taskName: task.name,
                    appName: task.appName,
                    enabled: !task.enabled
                })
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            // Reload tasks
            await this.loadTasks();
        } catch (error) {
            console.error('[TaskManager] Failed to toggle task:', error);
            alert('Failed to update task: ' + error.message);
        }
    }


    viewResult(jobId) {
        const result = this.state.results.find(r => r.JobID === jobId);
        if (result) {
            this.setState({ selectedResult: result });
        }
    }

    backToResults() {
        this.setState({ selectedResult: null });
    }

    async deleteResult(jobId) {
        if (!confirm(`Delete result for job ${jobId}?`)) return;

        try {
            const response = await fetch(`/apps/WebHostTaskManagement/api/v1/jobs/results?jobId=${jobId}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            // Reload results or go back to list if viewing detail
            if (this.state.selectedResult && this.state.selectedResult.JobID === jobId) {
                this.setState({ selectedResult: null });
            }
            await this.loadResults();
        } catch (error) {
            console.error('[TaskManager] Failed to delete result:', error);
            alert('Failed to delete result: ' + error.message);
        }
    }

    switchView(view) {
        this.setState({ currentView: view });
        this.loadData();
    }

    setState(newState) {
        this.state = { ...this.state, ...newState };
        this.render();
    }

    render() {
        this.shadowRoot.innerHTML = `
            <link rel="stylesheet" href="/apps/WebHostTaskManagement/public/elements/task-manager/style.css">

            <div class="container">
                <div class="sidebar">
                    <div class="sidebar-title">Task Management</div>
                    ${this.renderMenu()}
                </div>
                <div class="content">
                    ${this.renderContent()}
                </div>
            </div>

            ${this.state.showOutputModal ? this.renderOutputModal() : ''}
            ${this.state.showStartModal ? this.renderStartJobModal() : ''}
        `;

        this.attachEventListeners();
    }

    renderOutputModal() {
        return `
            <div class="modal-overlay">
                <div class="modal">
                    <div class="modal-header">
                        <h2>Live Job Output</h2>
                        <button class="btn btn-sm" data-close-modal>✕ Close</button>
                    </div>
                    <div class="modal-body">
                        <div class="job-output-container">
                            <pre><code>${this.escapeHtml(this.state.liveOutput)}</code></pre>
                        </div>
                        <div class="modal-footer">
                            <span class="text-muted">Job ID: ${this.state.selectedJob}</span>
                            <button class="btn btn-sm btn-info" data-refresh-output="${this.state.selectedJob}">🔄 Refresh</button>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderStartJobModal() {
        const job = this.state.selectedCatalogJob;
        if (!job) return '';

        const hasVariables = job.templateVariables && job.templateVariables.length > 0;

        return `
            <div class="modal-overlay">
                <div class="modal" style="max-width: 600px;">
                    <div class="modal-header">
                        <h2>▶ Start Job</h2>
                        <button class="btn btn-sm" data-close-start-modal>✕ Close</button>
                    </div>
                    <div class="modal-body">
                        <div style="margin-bottom: 20px; padding: 15px; background: var(--tm-bg-secondary); border-radius: 8px;">
                            <div style="font-weight: 600; font-size: 16px; margin-bottom: 8px;">${this.escapeHtml(job.displayName)}</div>
                            <div style="color: var(--tm-text-secondary); margin-bottom: 12px;">${this.escapeHtml(job.description)}</div>
                            <div style="font-size: 13px;">
                                <span class="badge badge-info">${job.appName}</span>
                                <code style="margin-left: 8px; font-size: 11px; opacity: 0.7;">${job.jobId}</code>
                            </div>
                        </div>

                        ${hasVariables ? `
                            <div style="margin-bottom: 20px;">
                                <h3 style="font-size: 14px; font-weight: 600; margin-bottom: 12px;">Template Variables</h3>
                                ${job.templateVariables.map(variable => `
                                    <div style="margin-bottom: 16px;">
                                        <label style="display: block; font-weight: 500; margin-bottom: 6px; font-size: 13px;">
                                            ${variable.name}
                                            <span style="color: var(--tm-text-secondary); font-weight: 400; font-size: 12px;">
                                                — ${this.escapeHtml(variable.description)}
                                            </span>
                                        </label>
                                        <input
                                            type="text"
                                            class="form-input"
                                            data-variable-name="${variable.name}"
                                            placeholder="Enter ${variable.name}"
                                            value="${this.escapeHtml(this.state.jobVariables[variable.name] || '')}"
                                            style="width: 100%; padding: 8px 12px; border: 1px solid var(--tm-border); border-radius: 4px; font-size: 14px;"
                                        />
                                    </div>
                                `).join('')}
                            </div>
                        ` : `
                            <div style="padding: 12px; background: var(--tm-bg-secondary); border-radius: 4px; color: var(--tm-text-secondary); font-size: 13px;">
                                This job has no template variables.
                            </div>
                        `}

                        <div style="margin-top: 24px; display: flex; gap: 10px; justify-content: flex-end;">
                            <button class="btn btn-secondary" data-close-start-modal>Cancel</button>
                            <button class="btn btn-success" data-confirm-start-job style="min-width: 100px;">
                                ▶ Start Job
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;
    }

    renderMenu() {
        const items = [
            { id: 'catalog', icon: '📦', label: 'Job Catalog' },
            { id: 'jobs', icon: '⚡', label: 'Active Jobs' },
            { id: 'results', icon: '📊', label: 'Job Results' },
            { id: 'tasks', icon: '📋', label: 'Scheduled Tasks' },
            { id: 'runspaces', icon: '🔄', label: 'Runspaces' }
        ];

        return items.map(item => `
            <div class="menu-item ${this.state.currentView === item.id ? 'active' : ''}" data-view="${item.id}">
                <span class="menu-icon">${item.icon}</span>
                <span>${item.label}</span>
            </div>
        `).join('');
    }

    renderContent() {
        if (this.state.error) {
            return `<div class="error">Error: ${this.state.error}</div>`;
        }

        switch (this.state.currentView) {
            case 'catalog':
                return this.renderCatalogView();
            case 'tasks':
                return this.renderTasksView();
            case 'jobs':
                return this.renderJobsView();
            case 'results':
                return this.renderResultsView();
            case 'runspaces':
                return this.renderRunspacesView();
            default:
                return '<div>Unknown view</div>';
        }
    }

    renderTasksView() {
        const tasks = this.state.tasks;
        const enabled = tasks.filter(t => t.enabled).length;
        const running = tasks.filter(t => t.isRunning).length;

        return `
            <div class="header">
                <h1 class="title">Scheduled Tasks</h1>
                <div class="subtitle">Manage and monitor scheduled background tasks</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${tasks.length}</div>
                    <div class="stat-label">Total Tasks</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${enabled}</div>
                    <div class="stat-label">Enabled</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${running}</div>
                    <div class="stat-label">Running Now</div>
                </div>
            </div>

            <div class="card">
                ${tasks.length === 0 ? `
                    <div class="empty-state">
                        <div class="empty-state-icon">📋</div>
                        <div>No tasks defined</div>
                    </div>
                ` : `
                    <table>
                        <thead>
                            <tr>
                                <th>Task Name</th>
                                <th>App</th>
                                <th>Schedule</th>
                                <th>Status</th>
                                <th>Last Run</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${tasks.map(task => `
                                <tr>
                                    <td>
                                        <strong>${task.name}</strong><br>
                                        <small class="task-description">${task.description || 'No description'}</small>
                                    </td>
                                    <td>${task.appName || 'Global'}</td>
                                    <td><code class="schedule-code">${task.schedule || 'N/A'}</code></td>
                                    <td>
                                        ${task.enabled ?
                                            (task.isRunning ?
                                                '<span class="badge badge-info">Running</span>' :
                                                '<span class="badge badge-success">Enabled</span>') :
                                            '<span class="badge badge-secondary">Disabled</span>'
                                        }
                                    </td>
                                    <td>${task.lastRun ? new Date(task.lastRun).toLocaleString() : 'Never'}</td>
                                    <td>
                                        <button class="btn btn-sm ${task.enabled ? 'btn-danger' : 'btn-success'}" data-task-toggle="${task.name}" data-task-app="${task.appName || ''}">
                                            ${task.enabled ? 'Disable' : 'Enable'}
                                        </button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `}
            </div>
        `;
    }

    renderJobsView() {
        const { pending, running, completed } = this.state.jobs;
        const totalJobs = pending.length + running.length + completed.length;

        return `
            <div class="header">
                <h1 class="title">Job Execution</h1>
                <div class="subtitle">Monitor and manage job submissions</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${pending.length}</div>
                    <div class="stat-label">Pending</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${running.length}</div>
                    <div class="stat-label">Running</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${completed.length}</div>
                    <div class="stat-label">Completed</div>
                </div>
            </div>

            ${totalJobs === 0 ? `
                <div class="card">
                    <div class="empty-state">
                        <div class="empty-state-icon">⚡</div>
                        <div>No jobs submitted yet</div>
                        <div style="margin-top: 10px; font-size: 14px; color: var(--tm-text-secondary);">
                            Jobs will appear here when submitted through the job execution API
                        </div>
                    </div>
                </div>
            ` : ''}

            ${pending.length > 0 ? `
                <div class="card">
                    <div class="card-header">
                        <h2>Pending Jobs (${pending.length})</h2>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>Job Name</th>
                                <th>Description</th>
                                <th>Execution Mode</th>
                                <th>Submitted</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${pending.map(job => `
                                <tr>
                                    <td><strong>${this.escapeHtml(job.JobName)}</strong></td>
                                    <td>${this.escapeHtml(job.Description || '')}</td>
                                    <td><span class="badge badge-info">${job.ExecutionMode}</span></td>
                                    <td>${this.formatDate(job.SubmittedAt)}</td>
                                    <td>
                                        <span class="badge badge-warning">Waiting</span>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            ` : ''}

            ${running.length > 0 ? `
                <div class="card">
                    <div class="card-header">
                        <h2>Running Jobs (${running.length})</h2>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>Job Name</th>
                                <th>Description</th>
                                <th>Execution Mode</th>
                                <th>Runtime</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${running.map(job => `
                                <tr>
                                    <td><strong>${this.escapeHtml(job.JobName)}</strong></td>
                                    <td>${this.escapeHtml(job.Description || '')}</td>
                                    <td><span class="badge badge-info">${job.ExecutionMode}</span></td>
                                    <td>${Math.round(job.Runtime)}s</td>
                                    <td>
                                        ${job.ExecutionMode === 'BackgroundJob' ?
                                            `<button class="btn btn-sm btn-info" data-job-output="${job.JobID}">View Output</button>` : ''
                                        }
                                        ${job.ExecutionMode !== 'MainLoop' ?
                                            `<button class="btn btn-sm btn-danger" data-job-stop="${job.JobID}">Stop</button>` :
                                            `<span class="badge badge-secondary">MainLoop</span>`
                                        }
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            ` : ''}

            ${completed.length > 0 ? `
                <div class="card">
                    <div class="card-header">
                        <h2>Recent Completed Jobs (${completed.length})</h2>
                    </div>
                    <table>
                        <thead>
                            <tr>
                                <th>Job Name</th>
                                <th>Status</th>
                                <th>Execution Mode</th>
                                <th>Runtime</th>
                                <th>Completed</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${completed.map(job => `
                                <tr>
                                    <td><strong>${this.escapeHtml(job.JobName)}</strong></td>
                                    <td>
                                        <span class="badge badge-${job.Success ? 'success' : 'danger'}">
                                            ${job.Success ? 'Success' : 'Failed'}
                                        </span>
                                    </td>
                                    <td><span class="badge badge-info">${job.ExecutionMode}</span></td>
                                    <td>${Math.round(job.Runtime)}s</td>
                                    <td>${this.formatDate(job.DateCompleted)}</td>
                                    <td>
                                        <button class="btn btn-sm btn-info" data-result-view="${job.JobID}">View Details</button>
                                        <button class="btn btn-sm btn-danger" data-job-delete="${job.JobID}">Delete</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            ` : ''}
        `;
    }

    formatDate(dateString) {
        if (!dateString) return 'N/A';
        const date = new Date(dateString);
        return date.toLocaleString();
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    renderCatalogView() {
        const catalog = Array.isArray(this.state.catalog) ? this.state.catalog : [];

        // Count jobs by permission
        const canStart = catalog.filter(j => j.permissions && j.permissions.canStart).length;

        return `
            <div class="header">
                <h1 class="title">📦 Job Catalog</h1>
                <div class="subtitle">Browse and start available jobs from all apps</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${catalog.length}</div>
                    <div class="stat-label">Total Jobs</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${canStart}</div>
                    <div class="stat-label">Can Start</div>
                </div>
            </div>

            ${catalog.length === 0 ? `
                <div class="card">
                    <div class="empty-state">
                        <div class="empty-state-icon">📦</div>
                        <div>No jobs available</div>
                        <div style="margin-top: 10px; font-size: 14px; color: var(--tm-text-secondary);">
                            Jobs will appear here when defined in apps/*/jobs/ directories
                        </div>
                    </div>
                </div>
            ` : `
                <div class="card">
                    <table>
                        <thead>
                            <tr>
                                <th style="width: 30%">Job</th>
                                <th style="width: 35%">Description</th>
                                <th style="width: 15%">Schedule</th>
                                <th style="width: 10%">Variables</th>
                                <th style="width: 10%">Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${catalog.map(job => `
                                <tr>
                                    <td>
                                        <div style="font-weight: 600; margin-bottom: 4px;">${this.escapeHtml(job.displayName)}</div>
                                        <div style="font-size: 12px; color: var(--tm-text-secondary);">
                                            <span class="badge badge-info">${job.appName}</span>
                                            <code style="margin-left: 8px; font-size: 11px;">${job.jobId}</code>
                                        </div>
                                    </td>
                                    <td>
                                        <div style="font-size: 13px;">${this.escapeHtml(job.description)}</div>
                                        ${job.templateVariables && job.templateVariables.length > 0 ? `
                                            <div style="margin-top: 6px;">
                                                ${job.templateVariables.map(v => `
                                                    <span class="badge badge-secondary" style="margin-right: 4px; font-size: 11px;">
                                                        {{${v.name}}}
                                                    </span>
                                                `).join('')}
                                            </div>
                                        ` : ''}
                                    </td>
                                    <td>
                                        ${job.schedule ? `<code class="schedule-code">${job.schedule}</code>` : '<span class="text-muted">Manual</span>'}
                                    </td>
                                    <td>
                                        ${job.hasInitScript ? '<span title="Has init-job.ps1">✓</span>' : ''}
                                        ${job.templateVariables && job.templateVariables.length > 0 ?
                                            `<span class="badge badge-info">${job.templateVariables.length}</span>` :
                                            '<span class="text-muted">—</span>'}
                                    </td>
                                    <td>
                                        ${job.permissions.canStart ? `
                                            <button class="btn btn-sm btn-success" data-start-job="${job.jobId}" data-job-index="${catalog.indexOf(job)}">
                                                ▶ Start
                                            </button>
                                        ` : `
                                            <span class="badge badge-secondary" title="No permission">🔒</span>
                                        `}
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                </div>
            `}
        `;
    }

    renderRunspacesView() {
        const runspaces = this.state.runspaces;
        const available = runspaces.filter(r => r.availability === 'Available').length;
        const busy = runspaces.filter(r => r.availability === 'Busy').length;

        return `
            <div class="header">
                <h1 class="title">Runspaces</h1>
                <div class="subtitle">Monitor PowerShell runspace usage and detect leaks</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${runspaces.length}</div>
                    <div class="stat-label">Total Runspaces</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${available}</div>
                    <div class="stat-label">Available</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${busy}</div>
                    <div class="stat-label">Busy</div>
                </div>
            </div>

            <div class="card">
                ${runspaces.length === 0 ? `
                    <div class="empty-state">
                        <div class="empty-state-icon">🔄</div>
                        <div>No runspaces detected</div>
                    </div>
                ` : `
                    <table>
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Name</th>
                                <th>Job</th>
                                <th>State</th>
                                <th>Availability</th>
                                <th>Thread Options</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${runspaces.map(rs => `
                                <tr>
                                    <td>#${rs.id}</td>
                                    <td>${rs.name}</td>
                                    <td>${rs.jobName || 'N/A'}</td>
                                    <td>
                                        <span class="badge badge-${rs.state === 'Opened' ? 'success' : 'secondary'}">${rs.state}</span>
                                    </td>
                                    <td>
                                        <span class="badge badge-${rs.availability === 'Available' ? 'success' : 'warning'}">${rs.availability}</span>
                                    </td>
                                    <td><code>${rs.threadOptions}</code></td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `}
            </div>
        `;
    }

    renderResultsView() {
        const results = this.state.results;
        const successful = results.filter(r => r.Success).length;
        const failed = results.filter(r => !r.Success).length;
        const totalRuntime = results.reduce((sum, r) => sum + (r.Runtime || 0), 0);
        const avgRuntime = results.length > 0 ? (totalRuntime / results.length).toFixed(2) : 0;

        // If a result is selected, show detail view
        if (this.state.selectedResult) {
            const result = this.state.selectedResult;
            return `
                <div class="header">
                    <button class="btn btn-sm" data-back-to-results>← Back to Results</button>
                    <h1 class="title">${this.escapeHtml(result.JobName)}</h1>
                    <div class="subtitle">Job ID: ${result.JobID}</div>
                </div>

                <div class="card">
                    <div class="result-detail">
                        <div class="result-meta">
                            <div class="meta-item">
                                <strong>Status:</strong>
                                <span class="badge badge-${result.Success ? 'success' : 'danger'}">
                                    ${result.Success ? 'Success' : 'Failed'}
                                </span>
                            </div>
                            <div class="meta-item">
                                <strong>Execution Mode:</strong> ${result.ExecutionMode}
                            </div>
                            <div class="meta-item">
                                <strong>Started:</strong> ${new Date(result.DateStarted).toLocaleString()}
                            </div>
                            <div class="meta-item">
                                <strong>Completed:</strong> ${new Date(result.DateCompleted).toLocaleString()}
                            </div>
                            <div class="meta-item">
                                <strong>Runtime:</strong> ${result.Runtime.toFixed(3)}s
                            </div>
                            <div class="meta-item">
                                <strong>Description:</strong> ${this.escapeHtml(result.Description || 'N/A')}
                            </div>
                        </div>

                        <div class="result-command">
                            <strong>Command:</strong>
                            <pre><code>${this.escapeHtml(result.Command)}</code></pre>
                        </div>

                        <div class="result-output">
                            <strong>Output:</strong>
                            <pre><code>${this.escapeHtml(result.Output || '(no output)')}</code></pre>
                        </div>

                        <div class="result-actions">
                            <button class="btn btn-sm btn-danger" data-delete-result="${result.JobID}">Delete Result</button>
                        </div>
                    </div>
                </div>
            `;
        }

        // List view
        return `
            <div class="header">
                <h1 class="title">Job Results</h1>
                <div class="subtitle">View output and results from executed jobs</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${results.length}</div>
                    <div class="stat-label">Total Results</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${successful}</div>
                    <div class="stat-label">Successful</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${failed}</div>
                    <div class="stat-label">Failed</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${avgRuntime}s</div>
                    <div class="stat-label">Avg Runtime</div>
                </div>
            </div>

            <div class="card">
                ${results.length === 0 ? `
                    <div class="empty-state">
                        <div class="empty-state-icon">📊</div>
                        <div>No job results yet</div>
                        <small>Results will appear here after jobs complete</small>
                    </div>
                ` : `
                    <table>
                        <thead>
                            <tr>
                                <th>Job Name</th>
                                <th>Status</th>
                                <th>Started</th>
                                <th>Runtime</th>
                                <th>Mode</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${results.map(result => `
                                <tr>
                                    <td>
                                        <strong>${this.escapeHtml(result.JobName)}</strong><br>
                                        <small style="color: #888;">${result.JobID.substring(0, 8)}...</small>
                                    </td>
                                    <td>
                                        <span class="badge badge-${result.Success ? 'success' : 'danger'}">
                                            ${result.Success ? 'Success' : 'Failed'}
                                        </span>
                                    </td>
                                    <td>${new Date(result.DateStarted).toLocaleString()}</td>
                                    <td>${result.Runtime ? result.Runtime.toFixed(3) + 's' : 'N/A'}</td>
                                    <td><code style="font-size: 0.85em;">${result.ExecutionMode}</code></td>
                                    <td>
                                        <button class="btn btn-sm" data-view-result="${result.JobID}">View</button>
                                        <button class="btn btn-sm btn-danger" data-delete-result="${result.JobID}">Delete</button>
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `}
            </div>
        `;
    }

    escapeHtml(text) {
        if (!text) return '';
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    attachEventListeners() {
        // Menu items
        this.shadowRoot.querySelectorAll('.menu-item').forEach(item => {
            item.addEventListener('click', () => {
                const view = item.getAttribute('data-view');
                this.switchView(view);
            });
        });

        // Task toggle buttons
        this.shadowRoot.querySelectorAll('[data-task-toggle]').forEach(btn => {
            btn.addEventListener('click', () => {
                const taskName = btn.getAttribute('data-task-toggle');
                const appName = btn.getAttribute('data-task-app') || null;
                const task = this.state.tasks.find(t => t.name === taskName && (t.appName || '') === appName);
                if (task) {
                    this.toggleTaskEnabled(task);
                }
            });
        });

        // Job stop buttons (new API)
        this.shadowRoot.querySelectorAll('[data-job-stop]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-job-stop');
                this.stopJob(jobId);
            });
        });

        // Job output view buttons
        this.shadowRoot.querySelectorAll('[data-job-output]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-job-output');
                this.viewJobOutput(jobId);
            });
        });

        // Job delete buttons (for completed jobs)
        this.shadowRoot.querySelectorAll('[data-job-delete]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-job-delete');
                this.deleteJob(jobId);
            });
        });

        // Result view buttons
        this.shadowRoot.querySelectorAll('[data-view-result], [data-result-view]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-view-result') || btn.getAttribute('data-result-view');
                this.viewResult(jobId);
            });
        });

        // Result delete buttons
        this.shadowRoot.querySelectorAll('[data-delete-result]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-delete-result');
                this.deleteResult(jobId);
            });
        });

        // Back to results button
        this.shadowRoot.querySelectorAll('[data-back-to-results]').forEach(btn => {
            btn.addEventListener('click', () => {
                this.backToResults();
            });
        });

        // Modal close button
        this.shadowRoot.querySelectorAll('[data-close-modal]').forEach(btn => {
            btn.addEventListener('click', () => {
                this.closeOutputModal();
            });
        });

        // Refresh output button in modal
        this.shadowRoot.querySelectorAll('[data-refresh-output]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-refresh-output');
                this.viewJobOutput(jobId);
            });
        });

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
    }
}

// Only define if not already registered
if (!customElements.get('task-manager')) {
    customElements.define('task-manager', TaskManagerComponent);
}

// Register in window.cardComponents for the SPA framework
// This needs to be a React component, not a function returning HTML
window.cardComponents = window.cardComponents || {};
window.cardComponents['task-manager'] = function TaskManagerCard(props) {
    // Create a ref to hold the custom element
    const containerRef = React.useRef(null);

    // Mount the custom element when the component mounts
    React.useEffect(() => {
        if (containerRef.current && !containerRef.current.querySelector('task-manager')) {
            const element = document.createElement('task-manager');
            containerRef.current.appendChild(element);

            // Cleanup when component unmounts
            return () => {
                if (containerRef.current && containerRef.current.contains(element)) {
                    containerRef.current.removeChild(element);
                }
            };
        }
    }, []);

    return React.createElement('div', {
        ref: containerRef,
        style: { width: '100%', height: '100%' }
    });
};
