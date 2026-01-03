// System Log Element
console.log('System Log element loaded.');

class SystemLogElement extends HTMLElement {
    constructor() {
        super();
        this.refreshInterval = null;
        this.autoRefresh = true;
        this.lines = 100; // Default number of lines to show
        this.filter = '';
    }

    connectedCallback() {
        this.render();
        this.loadLog();

        // Auto-refresh every 5 seconds
        if (this.autoRefresh) {
            this.refreshInterval = setInterval(() => this.loadLog(), 5000);
        }
    }

    disconnectedCallback() {
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
    }

    render() {
        this.innerHTML = `
            <style>
                .log-controls {
                    display: flex;
                    gap: 10px;
                    align-items: center;
                    margin-bottom: 10px;
                    padding: 8px;
                    background: var(--title-bar-color);
                    border-radius: 3px;
                }
                .log-controls label {
                    font-size: 0.85em;
                    display: flex;
                    align-items: center;
                    gap: 5px;
                }
                .log-controls input[type="text"],
                .log-controls input[type="number"] {
                    padding: 4px 8px;
                    border: 1px solid var(--border-color);
                    background: var(--bg-color);
                    color: var(--text-color);
                    border-radius: 3px;
                    font-size: 0.85em;
                }
                .log-controls input[type="number"] {
                    width: 80px;
                }
                .log-controls button {
                    padding: 4px 12px;
                    border: 1px solid var(--border-color);
                    background: var(--bg-color);
                    color: var(--text-color);
                    border-radius: 3px;
                    cursor: pointer;
                    font-size: 0.85em;
                }
                .log-controls button:hover {
                    background: var(--accent-primary);
                }
                .log-container {
                    background: var(--bg-color);
                    border: 1px solid var(--border-color);
                    border-radius: 3px;
                    padding: 10px;
                    height: calc(100% - 60px);
                    overflow-y: auto;
                    font-family: 'Consolas', 'Monaco', monospace;
                    font-size: 0.8em;
                }
                .log-entry {
                    padding: 4px 0;
                    border-bottom: 1px solid rgba(255,255,255,0.05);
                    white-space: pre-wrap;
                    word-break: break-all;
                }
                .log-entry:hover {
                    background: var(--title-bar-color);
                }
                .log-timestamp {
                    color: var(--accent-primary);
                    font-weight: bold;
                }
                .log-level {
                    display: inline-block;
                    padding: 2px 6px;
                    border-radius: 2px;
                    font-size: 0.75em;
                    font-weight: bold;
                    margin: 0 5px;
                }
                .log-level.Info { background: #4a9eff; color: #000; }
                .log-level.Warning { background: #fbbf24; color: #000; }
                .log-level.Error { background: #ef4444; color: #fff; }
                .log-category {
                    color: #a78bfa;
                    font-weight: 500;
                }
                .log-message {
                    color: var(--text-color);
                }
                .log-empty {
                    text-align: center;
                    padding: 20px;
                    color: var(--text-secondary);
                }
            </style>
            <div class="log-controls">
                <label>
                    Lines:
                    <input type="number" id="log-lines" value="${this.lines}" min="10" max="1000" step="10">
                </label>
                <label>
                    Filter:
                    <input type="text" id="log-filter" value="${this.filter}" placeholder="Search...">
                </label>
                <button id="log-refresh">Refresh</button>
                <button id="log-toggle-auto">${this.autoRefresh ? '⏸ Pause' : '▶ Resume'}</button>
            </div>
            <div class="log-container" id="log-content">
                <div class="log-empty">Loading log entries...</div>
            </div>
        `;

        // Attach event listeners
        this.querySelector('#log-refresh').addEventListener('click', () => this.loadLog());
        this.querySelector('#log-toggle-auto').addEventListener('click', () => this.toggleAutoRefresh());
        this.querySelector('#log-lines').addEventListener('change', (e) => {
            this.lines = parseInt(e.target.value);
            this.loadLog();
        });
        this.querySelector('#log-filter').addEventListener('input', (e) => {
            this.filter = e.target.value;
            this.loadLog();
        });
    }

    toggleAutoRefresh() {
        this.autoRefresh = !this.autoRefresh;
        const btn = this.querySelector('#log-toggle-auto');
        btn.textContent = this.autoRefresh ? '⏸ Pause' : '▶ Resume';

        if (this.autoRefresh) {
            this.refreshInterval = setInterval(() => this.loadLog(), 5000);
            this.loadLog();
        } else {
            if (this.refreshInterval) {
                clearInterval(this.refreshInterval);
                this.refreshInterval = null;
            }
        }
    }

    async loadLog() {
        try {
            const params = new URLSearchParams({
                lines: this.lines,
                ...(this.filter && { filter: this.filter })
            });

            const response = await fetch(`/api/v1/ui/elements/system-log?${params}`);
            const data = await response.json();

            if (response.ok) {
                this.renderLog(data);
            } else {
                this.showError(data.error || 'Failed to load log');
            }
        } catch (error) {
            this.showError(error.message);
        }
    }

    renderLog(data) {
        const container = this.querySelector('#log-content');

        if (!data.entries || data.entries.length === 0) {
            container.innerHTML = '<div class="log-empty">No log entries found</div>';
            return;
        }

        const html = data.entries.map(entry => {
            if (entry.raw) {
                // Raw unformatted line
                return `<div class="log-entry">${this.escapeHtml(entry.raw)}</div>`;
            }

            // Formatted TSV entry
            return `
                <div class="log-entry">
                    <span class="log-timestamp">${this.escapeHtml(entry.timestamp)}</span>
                    <span class="log-level ${entry.level}">${this.escapeHtml(entry.level)}</span>
                    <span class="log-category">[${this.escapeHtml(entry.category)}]</span>
                    <span class="log-message">${this.escapeHtml(entry.message)}</span>
                    ${entry.data ? `<div style="margin-left: 20px; color: #94a3b8;">${this.escapeHtml(entry.data)}</div>` : ''}
                </div>
            `;
        }).join('');

        container.innerHTML = html;

        // Auto-scroll to bottom if not manually scrolled
        if (container.scrollHeight - container.scrollTop - container.clientHeight < 100) {
            container.scrollTop = container.scrollHeight;
        }
    }

    showError(message) {
        const container = this.querySelector('#log-content');
        container.innerHTML = `
            <div class="log-empty" style="color: #ef4444;">
                Error: ${this.escapeHtml(message)}
            </div>
        `;
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// Register the custom element
customElements.define('system-log-element', SystemLogElement);
