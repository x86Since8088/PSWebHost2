param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Database Status API Endpoint
# Returns the card HTML with the database-status component

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "public/elements/database-status/component.js"

    if (-not (Test-Path $componentPath)) {
        context_response -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="database-status-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('database-status-root');
if (container && window.cardComponents && window.cardComponents['database-status']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['database-status'], {
            url: '/api/v1/ui/elements/database-status',
            element: container
        }),
        container
    );
}
</script>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DatabaseStatus' -Message "Error loading database status: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
