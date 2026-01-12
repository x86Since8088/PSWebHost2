param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Task Scheduler API Endpoint
# Returns the card HTML with the task-scheduler component

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "apps/WindowsAdmin/public/elements/task-scheduler/component.js"

    if (-not (Test-Path $componentPath)) {
        context_reponse -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="task-scheduler-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('task-scheduler-root');
if (container && window.cardComponents && window.cardComponents['task-scheduler']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['task-scheduler'], {
            url: '/api/v1/ui/elements/task-scheduler',
            element: container
        }),
        container
    );
}
</script>
"@

    context_reponse -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'TaskScheduler' -Message "Error loading task scheduler: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
