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
            currentView: 'tasks',  // 'tasks', 'jobs', or 'runspaces'
            loading: false,
            tasks: [],
            jobs: [],
            runspaces: [],
            error: null,
            selectedTask: null
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
                case 'runspaces':
                    await this.loadRunspaces();
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
        this.setState({ jobs: data.jobs || [], error: null });
    }

    async loadRunspaces() {
        const response = await fetch('/apps/WebHostTaskManagement/api/v1/runspaces');
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const data = await response.json();
        this.setState({ runspaces: data.runspaces || [], error: null });
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

    async stopJob(jobId) {
        if (!confirm(`Stop and remove job ${jobId}?`)) return;

        try {
            const response = await fetch(`/apps/WebHostTaskManagement/api/v1/jobs?jobId=${jobId}`, {
                method: 'DELETE'
            });

            if (!response.ok) throw new Error(`HTTP ${response.status}`);

            // Reload jobs
            await this.loadJobs();
        } catch (error) {
            console.error('[TaskManager] Failed to stop job:', error);
            alert('Failed to stop job: ' + error.message);
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
        `;

        this.attachEventListeners();
    }

    renderMenu() {
        const items = [
            { id: 'tasks', icon: '📋', label: 'Tasks' },
            { id: 'jobs', icon: '⚡', label: 'Jobs' },
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
            case 'tasks':
                return this.renderTasksView();
            case 'jobs':
                return this.renderJobsView();
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
        const jobs = this.state.jobs;
        const running = jobs.filter(j => j.state === 'Running').length;
        const completed = jobs.filter(j => j.state === 'Completed').length;
        const failed = jobs.filter(j => j.state === 'Failed').length;

        return `
            <div class="header">
                <h1 class="title">Background Jobs</h1>
                <div class="subtitle">Monitor and manage PowerShell background jobs</div>
            </div>

            <div class="stats">
                <div class="stat-card">
                    <div class="stat-value">${running}</div>
                    <div class="stat-label">Running</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${completed}</div>
                    <div class="stat-label">Completed</div>
                </div>
                <div class="stat-card">
                    <div class="stat-value">${failed}</div>
                    <div class="stat-label">Failed</div>
                </div>
            </div>

            <div class="card">
                ${jobs.length === 0 ? `
                    <div class="empty-state">
                        <div class="empty-state-icon">⚡</div>
                        <div>No background jobs</div>
                    </div>
                ` : `
                    <table>
                        <thead>
                            <tr>
                                <th>ID</th>
                                <th>Name</th>
                                <th>Task</th>
                                <th>State</th>
                                <th>Running Time</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody>
                            ${jobs.map(job => `
                                <tr>
                                    <td>#${job.id}</td>
                                    <td>${job.name}</td>
                                    <td>${job.taskName || '<i>Not a task job</i>'}</td>
                                    <td>
                                        <span class="badge badge-${
                                            job.state === 'Running' ? 'info' :
                                            job.state === 'Completed' ? 'success' :
                                            job.state === 'Failed' ? 'danger' :
                                            'secondary'
                                        }">${job.state}</span>
                                    </td>
                                    <td>${job.runningTime ? Math.round(job.runningTime) + 's' : 'N/A'}</td>
                                    <td>
                                        ${job.state === 'Running' ?
                                            `<button class="btn btn-sm btn-danger" data-job-stop="${job.id}">Stop</button>` :
                                            `<button class="btn btn-sm btn-danger" data-job-remove="${job.id}">Remove</button>`
                                        }
                                    </td>
                                </tr>
                            `).join('')}
                        </tbody>
                    </table>
                `}
            </div>
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

        // Job stop/remove buttons
        this.shadowRoot.querySelectorAll('[data-job-stop], [data-job-remove]').forEach(btn => {
            btn.addEventListener('click', () => {
                const jobId = btn.getAttribute('data-job-stop') || btn.getAttribute('data-job-remove');
                this.stopJob(parseInt(jobId));
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
