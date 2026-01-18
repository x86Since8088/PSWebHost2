param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Nodes Manager UI Endpoint
# Returns HTML card for managing linked PSWebHost nodes

try {
    $thisNodeGuid = $Global:PSWebServer.NodeGuid
    $thisNodePort = $Global:PSWebServer.Config.WebServer.Port

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Nodes Manager</title>
    <style>
        .nodes-manager {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 20px;
        }

        .this-node {
            background: linear-gradient(135deg, #3b82f6 0%, #1d4ed8 100%);
            color: white;
            padding: 20px;
            border-radius: 12px;
            margin-bottom: 24px;
        }

        .this-node h3 {
            margin: 0 0 8px 0;
            font-size: 14px;
            opacity: 0.9;
            text-transform: uppercase;
            letter-spacing: 1px;
        }

        .this-node-guid {
            font-family: monospace;
            font-size: 18px;
            background: rgba(255,255,255,0.2);
            padding: 8px 16px;
            border-radius: 6px;
            display: inline-block;
        }

        .nodes-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .nodes-header h2 {
            margin: 0;
            color: #1f2937;
        }

        .btn {
            padding: 10px 16px;
            border: none;
            border-radius: 6px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: all 0.2s;
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

        .nodes-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(400px, 1fr));
            gap: 16px;
        }

        .node-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
        }

        .node-card-header {
            padding: 16px 20px;
            border-bottom: 1px solid #e5e7eb;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .node-url {
            font-weight: 600;
            color: #1f2937;
        }

        .node-status {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            padding: 4px 10px;
            border-radius: 12px;
        }

        .node-status.connected {
            background: #dcfce7;
            color: #166534;
        }

        .node-status.disconnected {
            background: #fee2e2;
            color: #991b1b;
        }

        .node-status.pending {
            background: #fef3c7;
            color: #92400e;
        }

        .node-card-body {
            padding: 16px 20px;
        }

        .node-info {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 12px;
            font-size: 13px;
        }

        .node-info-item {
            display: flex;
            flex-direction: column;
        }

        .node-info-label {
            color: #9ca3af;
            font-size: 11px;
            text-transform: uppercase;
        }

        .node-info-value {
            color: #374151;
            font-family: monospace;
            word-break: break-all;
        }

        .node-card-footer {
            padding: 12px 20px;
            background: #f9fafb;
            border-top: 1px solid #e5e7eb;
            display: flex;
            gap: 8px;
        }

        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #6b7280;
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }

        .empty-state h3 {
            color: #374151;
            margin-bottom: 8px;
        }

        /* Modal */
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
            border-radius: 12px;
            width: 100%;
            max-width: 500px;
            box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1);
        }

        .modal-header {
            padding: 16px 20px;
            border-bottom: 1px solid #e5e7eb;
            display: flex;
            justify-content: space-between;
            align-items: center;
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

        .modal-body {
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

        .form-group input {
            width: 100%;
            padding: 10px 12px;
            border: 1px solid #d1d5db;
            border-radius: 6px;
            font-size: 14px;
            box-sizing: border-box;
        }

        .form-group input:focus {
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

        .hidden {
            display: none !important;
        }
    </style>
</head>
<body>
    <div class="nodes-manager">
        <div class="this-node">
            <h3>This Node</h3>
            <code class="this-node-guid">$thisNodeGuid</code>
            <p style="margin: 8px 0 0 0; opacity: 0.8;">Running on port $thisNodePort</p>
        </div>

        <div class="nodes-header">
            <h2>Linked Nodes</h2>
            <button class="btn btn-primary" id="add-node-btn">+ Add Node</button>
        </div>

        <div class="nodes-grid" id="nodes-grid">
            <div class="empty-state">
                <h3>Loading...</h3>
            </div>
        </div>

        <!-- Add Node Modal -->
        <div class="modal hidden" id="add-modal">
            <div class="modal-content">
                <div class="modal-header">
                    <h3>Add Node</h3>
                    <button class="close-btn" id="close-modal">&times;</button>
                </div>
                <div class="modal-body">
                    <form id="add-node-form">
                        <div class="form-group">
                            <label>Node URL *</label>
                            <input type="url" id="node-url" required placeholder="https://node-server:8080">
                        </div>
                        <div class="form-group">
                            <label>Node GUID *</label>
                            <input type="text" id="node-guid" required placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx">
                        </div>
                        <div class="form-group">
                            <label>Username (optional)</label>
                            <input type="text" id="node-user" placeholder="node_username">
                        </div>
                        <div class="form-group">
                            <label>Password (optional)</label>
                            <input type="password" id="node-password" placeholder="Node password">
                        </div>
                        <div class="form-actions">
                            <button type="button" class="btn btn-secondary" id="cancel-btn">Cancel</button>
                            <button type="submit" class="btn btn-primary">Add Node</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <script>
        let nodes = [];

        async function loadNodes() {
            try {
                const response = await fetch('/api/v1/nodes');
                const data = await response.json();

                if (data.success) {
                    nodes = data.nodes || [];
                    renderNodes();
                } else {
                    throw new Error(data.error);
                }
            } catch (error) {
                console.error('Error loading nodes:', error);
                document.getElementById('nodes-grid').innerHTML = \`
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <h3>Error Loading Nodes</h3>
                        <p>\${error.message}</p>
                    </div>
                \`;
            }
        }

        function renderNodes() {
            const grid = document.getElementById('nodes-grid');

            if (nodes.length === 0) {
                grid.innerHTML = \`
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <h3>No Linked Nodes</h3>
                        <p>Add remote PSWebHost nodes to manage them from here.</p>
                    </div>
                \`;
                return;
            }

            grid.innerHTML = nodes.map(node => \`
                <div class="node-card">
                    <div class="node-card-header">
                        <span class="node-url">\${node.url}</span>
                        <span class="node-status \${node.status || 'pending'}">\${node.status || 'Pending'}</span>
                    </div>
                    <div class="node-card-body">
                        <div class="node-info">
                            <div class="node-info-item">
                                <span class="node-info-label">GUID</span>
                                <span class="node-info-value">\${node.guid.substring(0, 8)}...</span>
                            </div>
                            <div class="node-info-item">
                                <span class="node-info-label">User</span>
                                <span class="node-info-value">\${node.user || '-'}</span>
                            </div>
                            <div class="node-info-item">
                                <span class="node-info-label">Registered</span>
                                <span class="node-info-value">\${formatDate(node.registered)}</span>
                            </div>
                            <div class="node-info-item">
                                <span class="node-info-label">Last Sync</span>
                                <span class="node-info-value">\${node.lastSync ? formatDate(node.lastSync) : 'Never'}</span>
                            </div>
                        </div>
                    </div>
                    <div class="node-card-footer">
                        <button class="btn btn-secondary" onclick="testConnection('\${node.guid}')">Test</button>
                        <button class="btn btn-danger" onclick="deleteNode('\${node.guid}')">Remove</button>
                    </div>
                </div>
            \`).join('');
        }

        function formatDate(dateStr) {
            if (!dateStr) return '-';
            const date = new Date(dateStr);
            return date.toLocaleDateString() + ' ' + date.toLocaleTimeString([], {hour: '2-digit', minute: '2-digit'});
        }

        function showModal() {
            document.getElementById('add-modal').classList.remove('hidden');
        }

        function hideModal() {
            document.getElementById('add-modal').classList.add('hidden');
            document.getElementById('add-node-form').reset();
        }

        async function addNode(event) {
            event.preventDefault();

            const data = {
                url: document.getElementById('node-url').value,
                guid: document.getElementById('node-guid').value,
                user: document.getElementById('node-user').value,
                password: document.getElementById('node-password').value
            };

            try {
                const response = await fetch('/api/v1/nodes', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(data)
                });

                const result = await response.json();

                if (result.success) {
                    hideModal();
                    loadNodes();
                } else {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error adding node: ' + error.message);
            }
        }

        async function deleteNode(guid) {
            if (!confirm('Are you sure you want to remove this node?')) {
                return;
            }

            try {
                const response = await fetch('/api/v1/nodes', {
                    method: 'DELETE',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ guid })
                });

                const result = await response.json();

                if (result.success) {
                    loadNodes();
                } else {
                    alert('Error: ' + result.error);
                }
            } catch (error) {
                alert('Error removing node: ' + error.message);
            }
        }

        async function testConnection(guid) {
            const node = nodes.find(n => n.guid === guid);
            if (!node) return;

            try {
                // Try to fetch the node's status endpoint
                const response = await fetch(node.url + '/api/v1/status', {
                    mode: 'cors',
                    credentials: 'omit'
                });

                if (response.ok) {
                    alert('Connection successful!');
                } else {
                    alert('Connection failed: HTTP ' + response.status);
                }
            } catch (error) {
                alert('Connection failed: ' + error.message);
            }
        }

        // Event listeners
        document.getElementById('add-node-btn').addEventListener('click', showModal);
        document.getElementById('close-modal').addEventListener('click', hideModal);
        document.getElementById('cancel-btn').addEventListener('click', hideModal);
        document.getElementById('add-node-form').addEventListener('submit', addNode);
        document.getElementById('add-modal').addEventListener('click', (e) => {
            if (e.target.classList.contains('modal')) hideModal();
        });

        // Load nodes on page load
        loadNodes();
    </script>
</body>
</html>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'NodesManager' -Message "Error loading nodes manager: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
