param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Apps Manager UI Endpoint
# Returns HTML card for managing PSWebHost apps

try {
    # Build list of installed apps
    $appsHtml = ""
    $appsData = @()

    if ($Global:PSWebServer.Apps -and $Global:PSWebServer.Apps.Count -gt 0) {
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $app = $Global:PSWebServer.Apps[$appName]
            $manifest = $app.Manifest

            $appsData += @{
                name = $manifest.name
                version = $manifest.version
                description = $manifest.description
                enabled = $manifest.enabled
                requiredRoles = ($manifest.requiredRoles -join ', ')
                loaded = $app.Loaded.ToString('yyyy-MM-dd HH:mm:ss')
                path = $app.Path
            }
        }
    }

    $appsJson = ($appsData | ConvertTo-Json -Compress -Depth 3)
    if (-not $appsJson) { $appsJson = "[]" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Apps Manager</title>
    <style>
        .apps-manager {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 20px;
        }

        .apps-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 20px;
        }

        .apps-header h2 {
            margin: 0;
            color: #1f2937;
        }

        .apps-count {
            background: #3b82f6;
            color: white;
            padding: 4px 12px;
            border-radius: 16px;
            font-size: 14px;
        }

        .apps-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(350px, 1fr));
            gap: 20px;
        }

        .app-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            overflow: hidden;
            transition: box-shadow 0.2s;
        }

        .app-card:hover {
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }

        .app-card-header {
            padding: 16px 20px;
            border-bottom: 1px solid #e5e7eb;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }

        .app-name {
            font-size: 18px;
            font-weight: 600;
            color: #1f2937;
        }

        .app-version {
            font-size: 12px;
            color: #6b7280;
            background: #f3f4f6;
            padding: 2px 8px;
            border-radius: 8px;
        }

        .app-status {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            font-size: 12px;
            padding: 4px 10px;
            border-radius: 12px;
        }

        .app-status.enabled {
            background: #dcfce7;
            color: #166534;
        }

        .app-status.disabled {
            background: #fee2e2;
            color: #991b1b;
        }

        .app-status-dot {
            width: 8px;
            height: 8px;
            border-radius: 50%;
        }

        .app-status.enabled .app-status-dot {
            background: #22c55e;
        }

        .app-status.disabled .app-status-dot {
            background: #ef4444;
        }

        .app-card-body {
            padding: 16px 20px;
        }

        .app-description {
            color: #4b5563;
            margin-bottom: 16px;
            line-height: 1.5;
        }

        .app-meta {
            display: grid;
            grid-template-columns: repeat(2, 1fr);
            gap: 12px;
            font-size: 13px;
        }

        .app-meta-item {
            display: flex;
            flex-direction: column;
        }

        .app-meta-label {
            color: #9ca3af;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }

        .app-meta-value {
            color: #374151;
            margin-top: 2px;
        }

        .app-card-footer {
            padding: 12px 20px;
            background: #f9fafb;
            border-top: 1px solid #e5e7eb;
            display: flex;
            gap: 8px;
        }

        .app-btn {
            padding: 6px 12px;
            border: 1px solid #d1d5db;
            border-radius: 6px;
            background: white;
            color: #374151;
            font-size: 13px;
            cursor: pointer;
            transition: all 0.2s;
        }

        .app-btn:hover {
            background: #f3f4f6;
        }

        .app-btn.primary {
            background: #3b82f6;
            border-color: #3b82f6;
            color: white;
        }

        .app-btn.primary:hover {
            background: #2563eb;
        }

        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #6b7280;
        }

        .empty-state-icon {
            font-size: 48px;
            margin-bottom: 16px;
        }

        .empty-state h3 {
            color: #374151;
            margin-bottom: 8px;
        }

        .node-guid {
            background: #f3f4f6;
            padding: 12px 16px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: flex;
            align-items: center;
            gap: 12px;
        }

        .node-guid-label {
            font-weight: 500;
            color: #374151;
        }

        .node-guid-value {
            font-family: monospace;
            color: #6b7280;
            background: white;
            padding: 4px 8px;
            border-radius: 4px;
            border: 1px solid #e5e7eb;
        }
    </style>
</head>
<body>
    <div class="apps-manager">
        <div class="node-guid">
            <span class="node-guid-label">Node GUID:</span>
            <code class="node-guid-value">$($Global:PSWebServer.NodeGuid)</code>
        </div>

        <div class="apps-header">
            <h2>Installed Apps</h2>
            <span class="apps-count">$($Global:PSWebServer.Apps.Count) app(s)</span>
        </div>

        <div class="apps-grid" id="apps-grid">
        </div>
    </div>

    <script>
        const apps = $appsJson;

        function renderApps() {
            const grid = document.getElementById('apps-grid');

            if (apps.length === 0) {
                grid.innerHTML = \`
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <div class="empty-state-icon">📦</div>
                        <h3>No Apps Installed</h3>
                        <p>Install apps by adding them to the /apps directory.</p>
                    </div>
                \`;
                return;
            }

            grid.innerHTML = apps.map(app => \`
                <div class="app-card">
                    <div class="app-card-header">
                        <div>
                            <span class="app-name">\${app.name}</span>
                            <span class="app-version">v\${app.version}</span>
                        </div>
                        <span class="app-status \${app.enabled ? 'enabled' : 'disabled'}">
                            <span class="app-status-dot"></span>
                            \${app.enabled ? 'Enabled' : 'Disabled'}
                        </span>
                    </div>
                    <div class="app-card-body">
                        <div class="app-description">\${app.description || 'No description available.'}</div>
                        <div class="app-meta">
                            <div class="app-meta-item">
                                <span class="app-meta-label">Required Roles</span>
                                <span class="app-meta-value">\${app.requiredRoles || 'None'}</span>
                            </div>
                            <div class="app-meta-item">
                                <span class="app-meta-label">Loaded At</span>
                                <span class="app-meta-value">\${app.loaded}</span>
                            </div>
                        </div>
                    </div>
                    <div class="app-card-footer">
                        <button class="app-btn primary" onclick="openApp('\${app.name}')">Open</button>
                        <button class="app-btn" onclick="viewDetails('\${app.name}')">Details</button>
                    </div>
                </div>
            \`).join('');
        }

        function openApp(name) {
            // Navigate to app's main interface
            window.location.href = '/apps/' + name + '/public/elements/vault-manager/component.js';
        }

        function viewDetails(name) {
            const app = apps.find(a => a.name === name);
            if (app) {
                alert('App Details:\\n\\nName: ' + app.name + '\\nVersion: ' + app.version + '\\nPath: ' + app.path);
            }
        }

        renderApps();
    </script>
</body>
</html>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppsManager' -Message "Error loading apps manager: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
