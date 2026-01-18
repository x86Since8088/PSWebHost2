param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# WSL Manager - Placeholder

try {
    # Try to get WSL distros if available
    $wslDistros = @()
    $wslAvailable = $false

    if ($IsWindows) {
        try {
            $wslOutput = & wsl.exe --list --verbose 2>$null
            if ($LASTEXITCODE -eq 0 -and $wslOutput) {
                $wslAvailable = $true
                # Parse WSL output (skip header line)
                $lines = $wslOutput -split "`n" | Select-Object -Skip 1 | Where-Object { $_.Trim() }
                foreach ($line in $lines) {
                    if ($line -match '^\s*(\*?)\s*(\S+)\s+(\S+)\s+(\d+)') {
                        $wslDistros += @{
                            default = $matches[1] -eq '*'
                            name = $matches[2]
                            state = $matches[3]
                            version = $matches[4]
                        }
                    }
                }
            }
        } catch {
            # WSL not available
        }
    }

    $distrosJson = ($wslDistros | ConvertTo-Json -Compress)
    if (-not $distrosJson) { $distrosJson = "[]" }

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>WSL Manager</title>
    <style>
        .wsl-manager {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 20px;
            max-width: 900px;
            margin: 0 auto;
        }
        .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; }
        .header h2 { margin: 0; color: #1f2937; }
        .status-badge {
            padding: 6px 12px;
            border-radius: 16px;
            font-size: 12px;
        }
        .status-badge.available { background: #dcfce7; color: #166534; }
        .status-badge.unavailable { background: #fee2e2; color: #991b1b; }

        .distros-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 16px;
        }
        .distro-card {
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            padding: 20px;
        }
        .distro-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 12px; }
        .distro-name { font-weight: 600; color: #1f2937; }
        .distro-default { font-size: 10px; background: #3b82f6; color: white; padding: 2px 8px; border-radius: 8px; }
        .distro-state { font-size: 13px; color: #6b7280; }
        .distro-state.Running { color: #22c55e; }
        .distro-state.Stopped { color: #6b7280; }
        .distro-version { font-size: 12px; color: #9ca3af; margin-top: 8px; }

        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: #6b7280;
            background: white;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
        }
        .platform-badge {
            display: inline-block;
            background: #dbeafe;
            color: #1e40af;
            padding: 4px 12px;
            border-radius: 16px;
            font-size: 12px;
            margin-top: 16px;
        }
    </style>
</head>
<body>
    <div class="wsl-manager">
        <div class="header">
            <h2>Windows Subsystem for Linux</h2>
            <span class="status-badge $($wslAvailable ? 'available' : 'unavailable')">
                $($wslAvailable ? 'WSL Available' : 'WSL Not Available')
            </span>
        </div>

        <div class="distros-grid" id="distros-grid">
        </div>
    </div>

    <script>
        const distros = $distrosJson;
        const wslAvailable = $($wslAvailable.ToString().ToLower());

        function renderDistros() {
            const grid = document.getElementById('distros-grid');

            if (!wslAvailable) {
                grid.innerHTML = \`
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <h3>WSL Not Available</h3>
                        <p>Windows Subsystem for Linux is not installed or not running.</p>
                        <span class="platform-badge">Windows Only</span>
                    </div>
                \`;
                return;
            }

            if (distros.length === 0) {
                grid.innerHTML = \`
                    <div class="empty-state" style="grid-column: 1 / -1;">
                        <h3>No WSL Distributions</h3>
                        <p>Install a Linux distribution from the Microsoft Store.</p>
                    </div>
                \`;
                return;
            }

            grid.innerHTML = distros.map(d => \`
                <div class="distro-card">
                    <div class="distro-header">
                        <span class="distro-name">\${d.name}</span>
                        \${d.default ? '<span class="distro-default">Default</span>' : ''}
                    </div>
                    <div class="distro-state \${d.state}">\${d.state}</div>
                    <div class="distro-version">WSL Version \${d.version}</div>
                </div>
            \`).join('');
        }

        renderDistros();
    </script>
</body>
</html>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'WSLManager' -Message "Error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
