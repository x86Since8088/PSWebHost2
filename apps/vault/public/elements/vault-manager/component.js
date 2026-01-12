// Vault Manager Component
// UI for managing secure credentials

class VaultManagerElement extends HTMLElement {
    constructor() {
        super();
        this.credentials = [];
        this.selectedScope = '';
    }

    connectedCallback() {
        this.render();
        this.loadCredentials();
    }

    render() {
        this.innerHTML = `
            <div class="vault-manager">
                <div class="vault-header">
                    <h2>Vault Credential Manager</h2>
                    <div class="vault-status" id="vault-status">
                        <span class="status-indicator loading"></span>
                        <span class="status-text">Loading...</span>
                    </div>
                </div>

                <div class="vault-toolbar">
                    <button class="btn btn-primary" id="add-credential-btn">
                        <span class="icon">+</span> Add Credential
                    </button>
                    <select id="scope-filter" class="scope-filter">
                        <option value="">All Scopes</option>
                        <option value="global">Global</option>
                        <option value="node">Node</option>
                        <option value="service">Service</option>
                    </select>
                    <button class="btn btn-secondary" id="refresh-btn">Refresh</button>
                </div>

                <div class="credentials-table-container">
                    <table class="credentials-table">
                        <thead>
                            <tr>
                                <th>Name</th>
                                <th>Username</th>
                                <th>Scope</th>
                                <th>Description</th>
                                <th>Created</th>
                                <th>Actions</th>
                            </tr>
                        </thead>
                        <tbody id="credentials-body">
                            <tr><td colspan="6" class="loading-row">Loading credentials...</td></tr>
                        </tbody>
                    </table>
                </div>

                <!-- Add/Edit Modal -->
                <div class="modal" id="credential-modal" style="display: none;">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h3 id="modal-title">Add Credential</h3>
                            <button class="close-btn" id="close-modal">&times;</button>
                        </div>
                        <form id="credential-form">
                            <div class="form-group">
                                <label for="cred-name">Name *</label>
                                <input type="text" id="cred-name" required placeholder="e.g., node_server1">
                            </div>
                            <div class="form-group">
                                <label for="cred-username">Username</label>
                                <input type="text" id="cred-username" placeholder="Optional username">
                            </div>
                            <div class="form-group">
                                <label for="cred-password">Password *</label>
                                <input type="password" id="cred-password" required>
                            </div>
                            <div class="form-group">
                                <label for="cred-scope">Scope</label>
                                <select id="cred-scope">
                                    <option value="global">Global</option>
                                    <option value="node">Node</option>
                                    <option value="service">Service</option>
                                </select>
                            </div>
                            <div class="form-group">
                                <label for="cred-description">Description</label>
                                <textarea id="cred-description" rows="2" placeholder="Optional description"></textarea>
                            </div>
                            <div class="form-actions">
                                <button type="button" class="btn btn-secondary" id="cancel-btn">Cancel</button>
                                <button type="submit" class="btn btn-primary">Save</button>
                            </div>
                        </form>
                    </div>
                </div>
            </div>

            <style>
                .vault-manager {
                    padding: 20px;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                }

                .vault-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 20px;
                }

                .vault-header h2 {
                    margin: 0;
                    color: #333;
                }

                .vault-status {
                    display: flex;
                    align-items: center;
                    gap: 8px;
                }

                .status-indicator {
                    width: 12px;
                    height: 12px;
                    border-radius: 50%;
                }

                .status-indicator.healthy { background: #22c55e; }
                .status-indicator.error { background: #ef4444; }
                .status-indicator.loading {
                    background: #f59e0b;
                    animation: pulse 1s infinite;
                }

                @keyframes pulse {
                    0%, 100% { opacity: 1; }
                    50% { opacity: 0.5; }
                }

                .vault-toolbar {
                    display: flex;
                    gap: 10px;
                    margin-bottom: 20px;
                }

                .btn {
                    padding: 8px 16px;
                    border: none;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 14px;
                    display: flex;
                    align-items: center;
                    gap: 6px;
                }

                .btn-primary {
                    background: #3b82f6;
                    color: white;
                }

                .btn-primary:hover {
                    background: #2563eb;
                }

                .btn-secondary {
                    background: #e5e7eb;
                    color: #374151;
                }

                .btn-secondary:hover {
                    background: #d1d5db;
                }

                .btn-danger {
                    background: #ef4444;
                    color: white;
                }

                .btn-danger:hover {
                    background: #dc2626;
                }

                .scope-filter {
                    padding: 8px 12px;
                    border: 1px solid #d1d5db;
                    border-radius: 4px;
                    font-size: 14px;
                }

                .credentials-table-container {
                    overflow-x: auto;
                }

                .credentials-table {
                    width: 100%;
                    border-collapse: collapse;
                    background: white;
                    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
                    border-radius: 8px;
                    overflow: hidden;
                }

                .credentials-table th,
                .credentials-table td {
                    padding: 12px 16px;
                    text-align: left;
                    border-bottom: 1px solid #e5e7eb;
                }

                .credentials-table th {
                    background: #f9fafb;
                    font-weight: 600;
                    color: #374151;
                }

                .credentials-table tbody tr:hover {
                    background: #f9fafb;
                }

                .loading-row {
                    text-align: center;
                    color: #6b7280;
                    padding: 40px !important;
                }

                .scope-badge {
                    display: inline-block;
                    padding: 2px 8px;
                    border-radius: 12px;
                    font-size: 12px;
                    font-weight: 500;
                }

                .scope-badge.global { background: #dbeafe; color: #1e40af; }
                .scope-badge.node { background: #dcfce7; color: #166534; }
                .scope-badge.service { background: #fef3c7; color: #92400e; }

                .action-buttons {
                    display: flex;
                    gap: 8px;
                }

                .action-btn {
                    padding: 4px 8px;
                    border: 1px solid #d1d5db;
                    border-radius: 4px;
                    background: white;
                    cursor: pointer;
                    font-size: 12px;
                }

                .action-btn:hover {
                    background: #f3f4f6;
                }

                .action-btn.delete:hover {
                    background: #fee2e2;
                    border-color: #fca5a5;
                    color: #dc2626;
                }

                /* Modal styles */
                .modal {
                    position: fixed;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    background: rgba(0,0,0,0.5);
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    z-index: 1000;
                }

                .modal-content {
                    background: white;
                    border-radius: 8px;
                    width: 100%;
                    max-width: 500px;
                    box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1);
                }

                .modal-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    padding: 16px 20px;
                    border-bottom: 1px solid #e5e7eb;
                }

                .modal-header h3 {
                    margin: 0;
                }

                .close-btn {
                    background: none;
                    border: none;
                    font-size: 24px;
                    cursor: pointer;
                    color: #6b7280;
                }

                .close-btn:hover {
                    color: #374151;
                }

                #credential-form {
                    padding: 20px;
                }

                .form-group {
                    margin-bottom: 16px;
                }

                .form-group label {
                    display: block;
                    margin-bottom: 4px;
                    font-weight: 500;
                    color: #374151;
                }

                .form-group input,
                .form-group select,
                .form-group textarea {
                    width: 100%;
                    padding: 8px 12px;
                    border: 1px solid #d1d5db;
                    border-radius: 4px;
                    font-size: 14px;
                    box-sizing: border-box;
                }

                .form-group input:focus,
                .form-group select:focus,
                .form-group textarea:focus {
                    outline: none;
                    border-color: #3b82f6;
                    box-shadow: 0 0 0 3px rgba(59,130,246,0.1);
                }

                .form-actions {
                    display: flex;
                    justify-content: flex-end;
                    gap: 10px;
                    margin-top: 20px;
                }

                .empty-state {
                    text-align: center;
                    padding: 40px;
                    color: #6b7280;
                }
            </style>
        `;

        this.bindEvents();
    }

    bindEvents() {
        // Add credential button
        this.querySelector('#add-credential-btn').addEventListener('click', () => this.showModal());

        // Refresh button
        this.querySelector('#refresh-btn').addEventListener('click', () => this.loadCredentials());

        // Scope filter
        this.querySelector('#scope-filter').addEventListener('change', (e) => {
            this.selectedScope = e.target.value;
            this.loadCredentials();
        });

        // Modal events
        this.querySelector('#close-modal').addEventListener('click', () => this.hideModal());
        this.querySelector('#cancel-btn').addEventListener('click', () => this.hideModal());

        // Form submission
        this.querySelector('#credential-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.saveCredential();
        });

        // Close modal on backdrop click
        this.querySelector('.modal').addEventListener('click', (e) => {
            if (e.target.classList.contains('modal')) {
                this.hideModal();
            }
        });
    }

    async loadCredentials() {
        const tbody = this.querySelector('#credentials-body');
        tbody.innerHTML = '<tr><td colspan="6" class="loading-row">Loading credentials...</td></tr>';

        try {
            const scopeParam = this.selectedScope ? `?scope=${this.selectedScope}` : '';
            const response = await fetch(`/apps/vault/api/v1/credentials${scopeParam}`);
            const data = await response.json();

            if (data.success) {
                this.credentials = data.credentials || [];
                this.renderCredentials();
            } else {
                throw new Error(data.error || 'Failed to load credentials');
            }

            // Update status
            await this.loadStatus();
        } catch (error) {
            console.error('Error loading credentials:', error);
            tbody.innerHTML = `<tr><td colspan="6" class="loading-row" style="color: #ef4444;">Error: ${error.message}</td></tr>`;
        }
    }

    async loadStatus() {
        try {
            const response = await fetch('/apps/vault/api/v1/status');
            const data = await response.json();

            const statusEl = this.querySelector('#vault-status');
            const indicator = statusEl.querySelector('.status-indicator');
            const text = statusEl.querySelector('.status-text');

            indicator.className = `status-indicator ${data.status}`;
            text.textContent = `${data.totalCredentials || 0} credentials stored`;
        } catch (error) {
            console.error('Error loading status:', error);
        }
    }

    renderCredentials() {
        const tbody = this.querySelector('#credentials-body');

        if (this.credentials.length === 0) {
            tbody.innerHTML = `
                <tr>
                    <td colspan="6" class="empty-state">
                        <p>No credentials stored yet.</p>
                        <p>Click "Add Credential" to store your first credential.</p>
                    </td>
                </tr>
            `;
            return;
        }

        tbody.innerHTML = this.credentials.map(cred => `
            <tr data-name="${cred.name}" data-scope="${cred.scope}">
                <td><strong>${this.escapeHtml(cred.name)}</strong></td>
                <td>${this.escapeHtml(cred.username || '-')}</td>
                <td><span class="scope-badge ${cred.scope}">${cred.scope}</span></td>
                <td>${this.escapeHtml(cred.description || '-')}</td>
                <td>${this.formatDate(cred.createdAt)}</td>
                <td class="action-buttons">
                    <button class="action-btn edit-btn" data-name="${cred.name}" data-scope="${cred.scope}">Edit</button>
                    <button class="action-btn delete delete-btn" data-name="${cred.name}" data-scope="${cred.scope}">Delete</button>
                </td>
            </tr>
        `).join('');

        // Bind action buttons
        tbody.querySelectorAll('.edit-btn').forEach(btn => {
            btn.addEventListener('click', () => this.editCredential(btn.dataset.name, btn.dataset.scope));
        });

        tbody.querySelectorAll('.delete-btn').forEach(btn => {
            btn.addEventListener('click', () => this.deleteCredential(btn.dataset.name, btn.dataset.scope));
        });
    }

    showModal(editing = false) {
        const modal = this.querySelector('#credential-modal');
        const title = this.querySelector('#modal-title');

        title.textContent = editing ? 'Edit Credential' : 'Add Credential';
        modal.style.display = 'flex';

        if (!editing) {
            this.querySelector('#credential-form').reset();
        }
    }

    hideModal() {
        this.querySelector('#credential-modal').style.display = 'none';
    }

    async saveCredential() {
        const form = this.querySelector('#credential-form');
        const data = {
            name: form.querySelector('#cred-name').value,
            username: form.querySelector('#cred-username').value,
            password: form.querySelector('#cred-password').value,
            scope: form.querySelector('#cred-scope').value,
            description: form.querySelector('#cred-description').value
        };

        try {
            const response = await fetch('/apps/vault/api/v1/credentials', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(data)
            });

            const result = await response.json();

            if (result.success) {
                this.hideModal();
                this.loadCredentials();
            } else {
                alert('Error: ' + result.error);
            }
        } catch (error) {
            console.error('Error saving credential:', error);
            alert('Error saving credential: ' + error.message);
        }
    }

    async editCredential(name, scope) {
        // Load the credential and show in modal
        try {
            const response = await fetch(`/apps/vault/api/v1/credentials?name=${encodeURIComponent(name)}&scope=${encodeURIComponent(scope)}`);
            const data = await response.json();

            if (data.success && data.credential) {
                const form = this.querySelector('#credential-form');
                form.querySelector('#cred-name').value = data.credential.name;
                form.querySelector('#cred-username').value = data.credential.username || '';
                form.querySelector('#cred-password').value = ''; // Don't populate password
                form.querySelector('#cred-scope').value = data.credential.scope;
                form.querySelector('#cred-description').value = data.credential.description || '';

                this.showModal(true);
            }
        } catch (error) {
            console.error('Error loading credential:', error);
            alert('Error loading credential: ' + error.message);
        }
    }

    async deleteCredential(name, scope) {
        if (!confirm(`Are you sure you want to delete the credential "${name}"?`)) {
            return;
        }

        try {
            const response = await fetch('/apps/vault/api/v1/credentials', {
                method: 'DELETE',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ name, scope })
            });

            const result = await response.json();

            if (result.success) {
                this.loadCredentials();
            } else {
                alert('Error: ' + result.error);
            }
        } catch (error) {
            console.error('Error deleting credential:', error);
            alert('Error deleting credential: ' + error.message);
        }
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    formatDate(dateStr) {
        if (!dateStr) return '-';
        const date = new Date(dateStr);
        return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
    }
}

customElements.define('vault-manager', VaultManagerElement);
