param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# SQLite Query Editor UI Element Endpoint

try {
    # Read component JavaScript
    $componentPath = Join-Path $Global:PSWebServer['SQLiteManager'].App_Root.Path "public/elements/sqlite-query-editor/component.js"

    if (-not (Test-Path $componentPath)) {
        $errorHtml = "<div style='padding: 20px; color: red;'>Component file not found: $componentPath</div>"
        context_reponse -Response $Response -StatusCode 404 -String $errorHtml -ContentType "text/html"
        return
    }

    $componentJs = Get-Content $componentPath -Raw

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SQLite Query Editor</title>
    <style>
        :root {
            --bg-primary: #ffffff;
            --bg-secondary: #f9fafb;
            --bg-tertiary: #f3f4f6;
            --text-primary: #1f2937;
            --text-secondary: #6b7280;
            --border-color: #e5e7eb;
            --accent-color: #3b82f6;
            --accent-color-muted: #93c5fd;
        }

        @media (prefers-color-scheme: dark) {
            :root {
                --bg-primary: #1f2937;
                --bg-secondary: #111827;
                --bg-tertiary: #374151;
                --text-primary: #f9fafb;
                --text-secondary: #9ca3af;
                --border-color: #374151;
                --accent-color: #3b82f6;
                --accent-color-muted: #1e40af;
            }
        }

        * {
            box-sizing: border-box;
        }

        body {
            margin: 0;
            padding: 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            background: var(--bg-primary);
            color: var(--text-primary);
        }

        .sqlite-query-editor {
            height: 100vh;
        }

        select, textarea, button, input {
            font-family: inherit;
        }

        /* Custom scrollbar */
        ::-webkit-scrollbar {
            width: 10px;
            height: 10px;
        }

        ::-webkit-scrollbar-track {
            background: var(--bg-secondary);
        }

        ::-webkit-scrollbar-thumb {
            background: var(--border-color);
            border-radius: 5px;
        }

        ::-webkit-scrollbar-thumb:hover {
            background: var(--text-secondary);
        }
    </style>
</head>
<body>
    <div id="root"></div>

    <script crossorigin src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
    <script crossorigin src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>

    <script>
    $componentJs
    </script>

    <script>
        const root = ReactDOM.createRoot(document.getElementById('root'));
        root.render(React.createElement(SQLiteQueryEditorComponent, {
            url: window.location.href,
            element: document.getElementById('root')
        }));
    </script>
</body>
</html>
"@

    context_reponse -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'SQLiteManager' -Message "Error serving query editor: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
