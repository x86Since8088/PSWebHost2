param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# SQL Server Manager - Placeholder

try {
    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>SQL Server Manager</title>
    <style>
        .placeholder {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            padding: 40px;
            text-align: center;
            max-width: 600px;
            margin: 0 auto;
        }
        .placeholder-icon { font-size: 64px; margin-bottom: 20px; }
        .placeholder h2 { color: #1f2937; margin-bottom: 16px; }
        .placeholder p { color: #6b7280; line-height: 1.6; }
        .feature-list {
            text-align: left;
            background: #f9fafb;
            padding: 20px;
            border-radius: 8px;
            margin-top: 24px;
        }
        .feature-list h4 { margin: 0 0 12px 0; color: #374151; }
        .feature-list ul { margin: 0; padding-left: 20px; color: #6b7280; }
        .feature-list li { margin-bottom: 8px; }
    </style>
</head>
<body>
    <div class="placeholder">
        <div class="placeholder-icon">🗃️</div>
        <h2>Microsoft SQL Server Manager</h2>
        <p>Connect to and manage SQL Server databases.</p>

        <div class="feature-list">
            <h4>Planned Features:</h4>
            <ul>
                <li>Windows and SQL authentication</li>
                <li>Database browser and object explorer</li>
                <li>T-SQL query editor</li>
                <li>Stored procedure management</li>
                <li>Database backup and restore</li>
            </ul>
        </div>
    </div>
</body>
</html>
"@

    context_reponse -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLServerManager' -Message "Error: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
