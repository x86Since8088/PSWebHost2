param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Linux Services Manager - Placeholder
# Manages systemd services on Linux systems

try {
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Linux Service Control</title>
    <style>
        .placeholder {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 40px;
            text-align: center;
            max-width: 600px;
            margin: 0 auto;
        }
        .placeholder-icon {
            font-size: 64px;
            margin-bottom: 20px;
        }
        .placeholder h2 {
            color: #1f2937;
            margin-bottom: 16px;
        }
        .placeholder p {
            color: #6b7280;
            line-height: 1.6;
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
        .feature-list {
            text-align: left;
            background: #f9fafb;
            padding: 20px;
            border-radius: 8px;
            margin-top: 24px;
        }
        .feature-list h4 {
            margin: 0 0 12px 0;
            color: #374151;
        }
        .feature-list ul {
            margin: 0;
            padding-left: 20px;
            color: #6b7280;
        }
        .feature-list li {
            margin-bottom: 8px;
        }
    </style>
</head>
<body>
    <div class="placeholder">
        <div class="placeholder-icon">🐧</div>
        <h2>Linux Service Control</h2>
        <p>Manage systemd services on Linux systems. Start, stop, restart, and monitor service status.</p>
        <span class="platform-badge">Linux Only</span>

        <div class="feature-list">
            <h4>Planned Features:</h4>
            <ul>
                <li>List all systemd services with status</li>
                <li>Start, stop, restart, and reload services</li>
                <li>Enable/disable services on boot</li>
                <li>View service logs (journalctl)</li>
                <li>Service dependency visualization</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@

    context_reponse -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'LinuxServices' -Message "Error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
