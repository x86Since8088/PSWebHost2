// Add this method after renderJobsView()

renderCatalogView() {
    const catalog = this.state.catalog;

    // Count jobs by permission
    const canStart = catalog.filter(j => j.permissions.canStart).length;

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

// Add this method after renderOutputModal()

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

// Update the render() method to include the start modal
// Change this line:
//   ${this.state.showOutputModal ? this.renderOutputModal() : ''}
// To:
//   ${this.state.showOutputModal ? this.renderOutputModal() : ''}
//   ${this.state.showStartModal ? this.renderStartJobModal() : ''}
