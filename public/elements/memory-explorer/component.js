/**
 * Memory Explorer Component
 * Advanced memory analysis UI with streaming NDJSON support
 *
 * Features:
 * - Real-time streaming memory analysis
 * - Tree view for object hierarchy
 * - Reference tracking and circular reference detection
 * - Assembly memory analysis
 * - Filtering and sorting
 * - Size visualization
 * - Export to JSON/CSV
 */

class MemoryExplorer extends HTMLElement {
    constructor() {
        super();

        this.state = {
            analyzing: false,
            variables: [],
            assemblies: [],
            summary: null,
            progress: { current: 0, total: 0, percentComplete: 0 },
            filters: {
                minSize: 0,
                searchTerm: '',
                showCircularOnly: false,
                showReferencesOnly: false
            },
            sortBy: 'size', // 'size', 'name', 'refcount'
            sortDesc: true,
            expandedPaths: new Set(),
            streamMessages: []
        };

        this.abortController = null;
    }

    connectedCallback() {
        this.render();
        this.attachEventListeners();
    }

    render() {
        this.innerHTML = `
            <div class="memory-explorer">
                <div class="explorer-header">
                    <h2>Memory Analysis</h2>
                    <div class="header-actions">
                        <button id="analyze-all-btn" class="btn-primary">
                            <span class="icon">🔍</span>
                            Analyze All Variables
                        </button>
                        <button id="analyze-custom-btn" class="btn-secondary">
                            <span class="icon">⚙️</span>
                            Custom Analysis
                        </button>
                        <button id="stop-analysis-btn" class="btn-danger" style="display: none;">
                            <span class="icon">⏹️</span>
                            Stop
                        </button>
                    </div>
                </div>

                <div class="progress-section" style="display: none;">
                    <div class="progress-bar-container">
                        <div class="progress-bar" id="progress-bar" style="width: 0%"></div>
                    </div>
                    <div class="progress-text" id="progress-text">Preparing analysis...</div>
                </div>

                <div class="controls-section">
                    <div class="control-group">
                        <label>
                            <span class="icon">🔎</span>
                            Search:
                        </label>
                        <input type="text" id="search-input" placeholder="Filter by name..." />
                    </div>

                    <div class="control-group">
                        <label>
                            <span class="icon">📏</span>
                            Min Size:
                        </label>
                        <input type="number" id="min-size-input" value="0" min="0" placeholder="Bytes" />
                        <select id="size-unit-select">
                            <option value="1">Bytes</option>
                            <option value="1024">KB</option>
                            <option value="1048576" selected>MB</option>
                        </select>
                    </div>

                    <div class="control-group">
                        <label>
                            <span class="icon">↕️</span>
                            Sort By:
                        </label>
                        <select id="sort-select">
                            <option value="size">Size</option>
                            <option value="name">Name</option>
                            <option value="refcount">Reference Count</option>
                        </select>
                        <button id="sort-direction-btn" class="btn-icon" title="Toggle sort direction">
                            <span class="icon">⬇️</span>
                        </button>
                    </div>

                    <div class="control-group">
                        <label>
                            <input type="checkbox" id="show-circular-only" />
                            Circular Refs Only
                        </label>
                        <label>
                            <input type="checkbox" id="show-references-only" />
                            Shared Refs Only
                        </label>
                    </div>

                    <div class="control-group">
                        <button id="expand-all-btn" class="btn-secondary">Expand All</button>
                        <button id="collapse-all-btn" class="btn-secondary">Collapse All</button>
                        <button id="export-json-btn" class="btn-secondary">Export JSON</button>
                        <button id="export-csv-btn" class="btn-secondary">Export CSV</button>
                    </div>
                </div>

                <div class="summary-section" id="summary-section" style="display: none;">
                    <h3>Summary</h3>
                    <div class="summary-grid">
                        <div class="summary-card">
                            <div class="summary-label">Total Objects</div>
                            <div class="summary-value" id="total-objects">0</div>
                        </div>
                        <div class="summary-card">
                            <div class="summary-label">Total Size</div>
                            <div class="summary-value" id="total-size">0 B</div>
                        </div>
                        <div class="summary-card">
                            <div class="summary-label">References</div>
                            <div class="summary-value" id="total-references">0</div>
                        </div>
                        <div class="summary-card circular">
                            <div class="summary-label">Circular Refs</div>
                            <div class="summary-value" id="circular-references">0</div>
                        </div>
                        <div class="summary-card">
                            <div class="summary-label">Assemblies</div>
                            <div class="summary-value" id="assembly-count">0</div>
                        </div>
                        <div class="summary-card">
                            <div class="summary-label">Assembly Size</div>
                            <div class="summary-value" id="assembly-size">0 B</div>
                        </div>
                    </div>
                </div>

                <div class="results-section">
                    <div class="results-tabs">
                        <button class="tab-btn active" data-tab="variables">
                            Variables (<span id="variable-count">0</span>)
                        </button>
                        <button class="tab-btn" data-tab="assemblies">
                            Assemblies (<span id="assembly-tab-count">0</span>)
                        </button>
                        <button class="tab-btn" data-tab="stream-log">
                            Stream Log (<span id="stream-log-count">0</span>)
                        </button>
                    </div>

                    <div class="tab-content active" id="variables-tab">
                        <div id="variables-tree"></div>
                    </div>

                    <div class="tab-content" id="assemblies-tab">
                        <div id="assemblies-list"></div>
                    </div>

                    <div class="tab-content" id="stream-log-tab">
                        <div id="stream-log"></div>
                    </div>
                </div>
            </div>
        `;
    }

    attachEventListeners() {
        // Analyze buttons
        this.querySelector('#analyze-all-btn').addEventListener('click', () => {
            this.startAnalysis({ path: '', depth: 5, includeAssemblies: true });
        });

        this.querySelector('#analyze-custom-btn').addEventListener('click', () => {
            this.showCustomAnalysisDialog();
        });

        this.querySelector('#stop-analysis-btn').addEventListener('click', () => {
            this.stopAnalysis();
        });

        // Filters
        this.querySelector('#search-input').addEventListener('input', (e) => {
            this.state.filters.searchTerm = e.target.value.toLowerCase();
            this.applyFiltersAndRender();
        });

        this.querySelector('#min-size-input').addEventListener('change', (e) => {
            const value = parseInt(e.target.value) || 0;
            const unit = parseInt(this.querySelector('#size-unit-select').value);
            this.state.filters.minSize = value * unit;
            this.applyFiltersAndRender();
        });

        this.querySelector('#size-unit-select').addEventListener('change', () => {
            const value = parseInt(this.querySelector('#min-size-input').value) || 0;
            const unit = parseInt(this.querySelector('#size-unit-select').value);
            this.state.filters.minSize = value * unit;
            this.applyFiltersAndRender();
        });

        this.querySelector('#sort-select').addEventListener('change', (e) => {
            this.state.sortBy = e.target.value;
            this.applyFiltersAndRender();
        });

        this.querySelector('#sort-direction-btn').addEventListener('click', () => {
            this.state.sortDesc = !this.state.sortDesc;
            const icon = this.querySelector('#sort-direction-btn .icon');
            icon.textContent = this.state.sortDesc ? '⬇️' : '⬆️';
            this.applyFiltersAndRender();
        });

        this.querySelector('#show-circular-only').addEventListener('change', (e) => {
            this.state.filters.showCircularOnly = e.target.checked;
            this.applyFiltersAndRender();
        });

        this.querySelector('#show-references-only').addEventListener('change', (e) => {
            this.state.filters.showReferencesOnly = e.target.checked;
            this.applyFiltersAndRender();
        });

        // Expand/Collapse
        this.querySelector('#expand-all-btn').addEventListener('click', () => this.expandAll());
        this.querySelector('#collapse-all-btn').addEventListener('click', () => this.collapseAll());

        // Export
        this.querySelector('#export-json-btn').addEventListener('click', () => this.exportJSON());
        this.querySelector('#export-csv-btn').addEventListener('click', () => this.exportCSV());

        // Tabs
        this.querySelectorAll('.tab-btn').forEach(btn => {
            btn.addEventListener('click', (e) => {
                const tab = e.target.dataset.tab;
                this.switchTab(tab);
            });
        });
    }

    showCustomAnalysisDialog() {
        const path = prompt('Enter variable path (e.g., "PSWebServer.Apps"):\nLeave empty for all variables', '');
        if (path === null) return; // Cancelled

        const depthStr = prompt('Enter depth (1-20):', '5');
        if (depthStr === null) return;

        const depth = parseInt(depthStr) || 5;
        const includeAssemblies = confirm('Include assembly analysis?');

        this.startAnalysis({ path, depth, includeAssemblies });
    }

    async startAnalysis(options) {
        const { path = '', depth = 5, includeAssemblies = false } = options;

        // Reset state
        this.state.variables = [];
        this.state.assemblies = [];
        this.state.summary = null;
        this.state.streamMessages = [];
        this.state.analyzing = true;

        // Show progress
        this.querySelector('.progress-section').style.display = 'block';
        this.querySelector('#analyze-all-btn').style.display = 'none';
        this.querySelector('#analyze-custom-btn').style.display = 'none';
        this.querySelector('#stop-analysis-btn').style.display = 'inline-block';

        // Create abort controller
        this.abortController = new AbortController();

        try {
            // Build URL
            const url = new URL('/api/v1/debug/vars', window.location.origin);
            url.searchParams.set('format', 'memory');
            if (path) url.searchParams.set('path', path);
            url.searchParams.set('depth', depth);
            url.searchParams.set('includeAssemblies', includeAssemblies);

            this.logStreamMessage({ type: 'info', message: `Starting analysis: ${url}` });

            // Start streaming fetch
            const response = await fetch(url, { signal: this.abortController.signal });

            if (!response.ok) {
                const error = new Error(`HTTP ${response.status}: ${response.statusText}`);
                error.status = response.status;
                error.statusText = response.statusText;
                throw error;
            }

            // Read NDJSON stream
            await this.processNDJSONStream(response.body);

            this.logStreamMessage({ type: 'success', message: 'Analysis complete!' });

        } catch (error) {
            if (error.name === 'AbortError') {
                this.logStreamMessage({ type: 'warning', message: 'Analysis stopped by user' });
            } else {
                this.logStreamMessage({ type: 'error', message: `Error: ${error.message}` });
                console.error('Analysis error:', error);
            }
        } finally {
            this.state.analyzing = false;
            this.querySelector('.progress-section').style.display = 'none';
            this.querySelector('#analyze-all-btn').style.display = 'inline-block';
            this.querySelector('#analyze-custom-btn').style.display = 'inline-block';
            this.querySelector('#stop-analysis-btn').style.display = 'none';
        }
    }

    async processNDJSONStream(readableStream) {
        const reader = readableStream.getReader();
        const decoder = new TextDecoder();

        let buffer = '';

        while (true) {
            const { done, value } = await reader.read();

            if (done) break;

            // Decode chunk
            buffer += decoder.decode(value, { stream: true });

            // Split by newlines
            const lines = buffer.split('\n');
            buffer = lines.pop(); // Keep incomplete line

            // Process complete lines
            for (const line of lines) {
                if (line.trim()) {
                    try {
                        const message = JSON.parse(line);
                        this.handleStreamMessage(message);
                    } catch (error) {
                        console.error('Failed to parse NDJSON line:', line, error);
                    }
                }
            }
        }

        // Process remaining buffer
        if (buffer.trim()) {
            try {
                const message = JSON.parse(buffer);
                this.handleStreamMessage(message);
            } catch (error) {
                console.error('Failed to parse final NDJSON:', buffer, error);
            }
        }
    }

    handleStreamMessage(message) {
        this.state.streamMessages.push(message);
        this.logStreamMessage(message);

        const { type } = message;

        switch (type) {
            case 'start':
                this.updateProgress({ current: 0, total: 1, percentComplete: 0 });
                break;

            case 'progress':
                this.updateProgress({
                    current: message.current || 0,
                    total: message.total || 1,
                    percentComplete: message.percentComplete || 0
                });
                this.querySelector('#progress-text').textContent =
                    `Analyzing: ${message.variable} (${message.current}/${message.total})`;
                break;

            case 'variable':
                this.state.variables.push(message.result);
                this.renderVariablesTree();
                break;

            case 'assembly':
                this.state.assemblies.push(message.assembly);
                this.renderAssembliesList();
                break;

            case 'assemblies_complete':
                this.renderAssembliesList();
                break;

            case 'complete':
                this.state.summary = message.summary;
                this.renderSummary();
                this.renderVariablesTree();
                this.renderAssembliesList();
                break;

            case 'error':
                console.error('Stream error:', message.message);
                break;
        }

        // Update stream log count
        this.querySelector('#stream-log-count').textContent = this.state.streamMessages.length;
    }

    updateProgress(progress) {
        this.state.progress = progress;
        const progressBar = this.querySelector('#progress-bar');
        progressBar.style.width = `${progress.percentComplete}%`;
    }

    renderSummary() {
        const summary = this.state.summary;
        if (!summary) return;

        this.querySelector('#summary-section').style.display = 'block';

        this.querySelector('#total-objects').textContent = summary.TotalObjects?.toLocaleString() || '0';
        this.querySelector('#total-size').textContent = this.formatSize(summary.TotalSize || 0);
        this.querySelector('#total-references').textContent = summary.TotalReferences?.toLocaleString() || '0';
        this.querySelector('#circular-references').textContent = summary.CircularReferences?.toLocaleString() || '0';
        this.querySelector('#assembly-count').textContent = summary.AssemblyCount?.toLocaleString() || '0';
        this.querySelector('#assembly-size').textContent = this.formatSize(summary.TotalAssemblySize || 0);
    }

    renderVariablesTree() {
        const container = this.querySelector('#variables-tree');
        const filtered = this.filterAndSortVariables();

        this.querySelector('#variable-count').textContent = filtered.length;

        if (filtered.length === 0) {
            container.innerHTML = '<div class="empty-state">No variables match the current filters</div>';
            return;
        }

        container.innerHTML = filtered.map(variable => this.renderVariableNode(variable, 0)).join('');

        // Attach toggle listeners
        container.querySelectorAll('.tree-node-toggle').forEach(toggle => {
            toggle.addEventListener('click', (e) => {
                e.stopPropagation();
                const path = toggle.dataset.path;
                this.toggleExpanded(path);
            });
        });
    }

    renderVariableNode(node, depth) {
        const path = node.Path || 'Unknown';
        const isExpanded = this.state.expandedPaths.has(path);
        const hasChildren = node.Children && node.Children.length > 0;

        const indent = depth * 20;

        let classes = ['tree-node'];
        if (node.IsCircular) classes.push('circular');
        if (node.IsReference) classes.push('reference');

        const toggleIcon = hasChildren ? (isExpanded ? '▼' : '▶') : '•';

        let badges = [];
        if (node.IsCircular) badges.push('<span class="badge circular">CIRCULAR</span>');
        if (node.IsReference) badges.push('<span class="badge reference">REF</span>');
        if (node.RefCount > 1) badges.push(`<span class="badge refcount">×${node.RefCount}</span>`);

        let html = `
            <div class="${classes.join(' ')}" style="padding-left: ${indent}px;">
                <span class="tree-node-toggle" data-path="${path}">${toggleIcon}</span>
                <span class="tree-node-name">${this.escapeHtml(path)}</span>
                ${badges.join(' ')}
                <span class="tree-node-type">${this.escapeHtml(node.Type || 'Unknown')}</span>
                <span class="tree-node-size">${this.formatSize(node.TotalSize || 0)}</span>
            </div>
        `;

        if (isExpanded && hasChildren) {
            html += node.Children.map(child => this.renderVariableNode(child, depth + 1)).join('');
        }

        return html;
    }

    renderAssembliesList() {
        const container = this.querySelector('#assemblies-list');
        const assemblies = this.state.assemblies;

        this.querySelector('#assembly-tab-count').textContent = assemblies.length;

        if (assemblies.length === 0) {
            container.innerHTML = '<div class="empty-state">No assemblies analyzed yet</div>';
            return;
        }

        // Sort by size
        const sorted = [...assemblies].sort((a, b) => (b.EstimatedSize || 0) - (a.EstimatedSize || 0));

        container.innerHTML = `
            <table class="assemblies-table">
                <thead>
                    <tr>
                        <th>Name</th>
                        <th>Version</th>
                        <th>Size</th>
                        <th>Types</th>
                        <th>Source</th>
                    </tr>
                </thead>
                <tbody>
                    ${sorted.map(asm => `
                        <tr>
                            <td class="assembly-name">${this.escapeHtml(asm.Name)}</td>
                            <td>${this.escapeHtml(asm.Version || '')}</td>
                            <td class="assembly-size">${this.formatSize(asm.EstimatedSize || 0)}</td>
                            <td>${(asm.TypeCount || 0).toLocaleString()}</td>
                            <td>
                                <span class="badge ${asm.IsGAC ? 'gac' : asm.IsDynamic ? 'dynamic' : 'private'}">
                                    ${asm.IsGAC ? 'GAC' : asm.IsDynamic ? 'Dynamic' : 'Private'}
                                </span>
                            </td>
                        </tr>
                    `).join('')}
                </tbody>
            </table>
        `;
    }

    filterAndSortVariables() {
        let filtered = [...this.state.variables];

        // Apply filters
        if (this.state.filters.searchTerm) {
            filtered = filtered.filter(v =>
                (v.Path || '').toLowerCase().includes(this.state.filters.searchTerm)
            );
        }

        if (this.state.filters.minSize > 0) {
            filtered = filtered.filter(v => (v.TotalSize || 0) >= this.state.filters.minSize);
        }

        if (this.state.filters.showCircularOnly) {
            filtered = filtered.filter(v => v.IsCircular || this.hasCircularChild(v));
        }

        if (this.state.filters.showReferencesOnly) {
            filtered = filtered.filter(v => (v.RefCount || 0) > 1);
        }

        // Apply sorting
        filtered.sort((a, b) => {
            let aVal, bVal;

            switch (this.state.sortBy) {
                case 'name':
                    aVal = (a.Path || '').toLowerCase();
                    bVal = (b.Path || '').toLowerCase();
                    return this.state.sortDesc ? bVal.localeCompare(aVal) : aVal.localeCompare(bVal);

                case 'refcount':
                    aVal = a.RefCount || 0;
                    bVal = b.RefCount || 0;
                    break;

                default: // 'size'
                    aVal = a.TotalSize || 0;
                    bVal = b.TotalSize || 0;
                    break;
            }

            return this.state.sortDesc ? bVal - aVal : aVal - bVal;
        });

        return filtered;
    }

    hasCircularChild(node) {
        if (node.IsCircular) return true;
        if (!node.Children) return false;

        return node.Children.some(child => this.hasCircularChild(child));
    }

    toggleExpanded(path) {
        if (this.state.expandedPaths.has(path)) {
            this.state.expandedPaths.delete(path);
        } else {
            this.state.expandedPaths.add(path);
        }

        this.renderVariablesTree();
    }

    expandAll() {
        const addAllPaths = (node) => {
            if (node.Path) this.state.expandedPaths.add(node.Path);
            if (node.Children) {
                node.Children.forEach(child => addAllPaths(child));
            }
        };

        this.state.variables.forEach(v => addAllPaths(v));
        this.renderVariablesTree();
    }

    collapseAll() {
        this.state.expandedPaths.clear();
        this.renderVariablesTree();
    }

    switchTab(tabName) {
        // Update tab buttons
        this.querySelectorAll('.tab-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.tab === tabName);
        });

        // Update tab content
        this.querySelectorAll('.tab-content').forEach(content => {
            content.classList.toggle('active', content.id === `${tabName}-tab`);
        });
    }

    logStreamMessage(message) {
        const logContainer = this.querySelector('#stream-log');
        const timestamp = new Date().toLocaleTimeString();

        let typeClass = 'info';
        let typeIcon = 'ℹ️';

        if (message.type === 'error') {
            typeClass = 'error';
            typeIcon = '❌';
        } else if (message.type === 'warning') {
            typeClass = 'warning';
            typeIcon = '⚠️';
        } else if (message.type === 'success') {
            typeClass = 'success';
            typeIcon = '✅';
        } else if (message.type === 'progress') {
            typeIcon = '⏳';
        }

        const entry = document.createElement('div');
        entry.className = `log-entry ${typeClass}`;
        entry.innerHTML = `
            <span class="log-time">${timestamp}</span>
            <span class="log-icon">${typeIcon}</span>
            <span class="log-type">[${message.type}]</span>
            <span class="log-message">${this.escapeHtml(message.message || JSON.stringify(message))}</span>
        `;

        logContainer.appendChild(entry);
        logContainer.scrollTop = logContainer.scrollHeight;
    }

    stopAnalysis() {
        if (this.abortController) {
            this.abortController.abort();
        }
    }

    applyFiltersAndRender() {
        this.renderVariablesTree();
    }

    exportJSON() {
        const data = {
            summary: this.state.summary,
            variables: this.state.variables,
            assemblies: this.state.assemblies,
            exportedAt: new Date().toISOString()
        };

        const json = JSON.stringify(data, null, 2);
        const blob = new Blob([json], { type: 'application/json' });
        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `memory-analysis-${Date.now()}.json`;
        a.click();

        URL.revokeObjectURL(url);
    }

    exportCSV() {
        // Flatten variables for CSV export
        const rows = [];
        rows.push(['Path', 'Type', 'TotalSize', 'BaseSize', 'ContentSize', 'RefCount', 'IsCircular', 'IsReference']);

        const flatten = (node) => {
            rows.push([
                node.Path || '',
                node.Type || '',
                node.TotalSize || 0,
                node.BaseSize || 0,
                node.ContentSize || 0,
                node.RefCount || 0,
                node.IsCircular ? 'Yes' : 'No',
                node.IsReference ? 'Yes' : 'No'
            ]);

            if (node.Children) {
                node.Children.forEach(child => flatten(child));
            }
        };

        this.state.variables.forEach(v => flatten(v));

        const csv = rows.map(row => row.map(cell => `"${cell}"`).join(',')).join('\n');
        const blob = new Blob([csv], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);

        const a = document.createElement('a');
        a.href = url;
        a.download = `memory-analysis-${Date.now()}.csv`;
        a.click();

        URL.revokeObjectURL(url);
    }

    formatSize(bytes) {
        if (bytes === 0) return '0 B';
        if (bytes < 1024) return `${bytes} B`;
        if (bytes < 1048576) return `${(bytes / 1024).toFixed(2)} KB`;
        if (bytes < 1073741824) return `${(bytes / 1048576).toFixed(2)} MB`;
        return `${(bytes / 1073741824).toFixed(2)} GB`;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Register custom element
customElements.define('memory-explorer', MemoryExplorer);
