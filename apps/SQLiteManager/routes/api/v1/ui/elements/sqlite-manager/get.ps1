param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# SQLite Manager - Placeholder

try {
    # Get info about the main PSWebHost database
    $dbFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data/pswebhost.db"
    $dbExists = Test-Path $dbFile
    $dbSize = 0
    $tables = @()

    if ($dbExists) {
        $dbSize = [math]::Round((Get-Item $dbFile).Length / 1KB, 2)

        try {
            $tablesQuery = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
            $tables = @(Get-PSWebSQLiteData -File $dbFile -Query $tablesQuery | ForEach-Object { $_.name })
        } catch {}
    }

    $tablesJson = ($tables | ConvertTo-Json -Compress)
    if (-not $tablesJson) { $tablesJson = "[]" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SQLite Manager</title>
    <style>
        .sqlite-manager {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 20px;
            max-width: 900px;
            margin: 0 auto;
        }
        .header { margin-bottom: 24px; }
        .header h2 { margin: 0 0 8px 0; color: #1f2937; }
        .header p { color: #6b7280; margin: 0; }

        .db-info {
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 20px;
            margin-bottom: 24px;
        }
        .db-info-grid {
            display: grid;
            grid-template-columns: repeat(3, 1fr);
            gap: 20px;
        }
        .info-item { text-align: center; }
        .info-value { font-size: 24px; font-weight: 600; color: #1f2937; }
        .info-label { font-size: 12px; color: #6b7280; text-transform: uppercase; }

        .tables-section { margin-top: 24px; }
        .tables-section h3 { color: #374151; margin-bottom: 16px; }
        .tables-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
            gap: 12px;
        }
        .table-card {
            background: white;
            border-radius: 8px;
            padding: 12px 16px;
            box-shadow: 0 1px 2px rgba(0,0,0,0.05);
            border: 1px solid #e5e7eb;
            font-family: monospace;
            color: #374151;
        }
        .table-card:hover {
            border-color: #3b82f6;
            background: #f0f9ff;
        }

        .coming-soon {
            background: #fef3c7;
            color: #92400e;
            padding: 12px 20px;
            border-radius: 8px;
            margin-top: 24px;
        }
    </style>
</head>
<body>
    <div class="sqlite-manager">
        <div class="header">
            <h2>SQLite Database Manager</h2>
            <p>Manage the PSWebHost SQLite database</p>
        </div>

        <div class="db-info">
            <div class="db-info-grid">
                <div class="info-item">
                    <div class="info-value">$($dbExists ? '✓' : '✗')</div>
                    <div class="info-label">Database Status</div>
                </div>
                <div class="info-item">
                    <div class="info-value">$dbSize KB</div>
                    <div class="info-label">Database Size</div>
                </div>
                <div class="info-item">
                    <div class="info-value">$($tables.Count)</div>
                    <div class="info-label">Tables</div>
                </div>
            </div>
        </div>

        <div class="tables-section">
            <h3>Database Tables</h3>
            <div class="tables-grid" id="tables-grid">
            </div>
        </div>

        <div class="coming-soon">
            <strong>Coming Soon:</strong> Query editor, table browser, data export/import, and database backup tools.
        </div>
    </div>

    <script>
        const tables = $tablesJson;

        function renderTables() {
            const grid = document.getElementById('tables-grid');
            if (tables.length === 0) {
                grid.innerHTML = '<p style="color: #6b7280;">No tables found</p>';
                return;
            }
            grid.innerHTML = tables.map(t => \`<div class="table-card">\${t}</div>\`).join('');
        }

        renderTables();
    </script>
</body>
</html>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLiteManager' -Message "Error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
