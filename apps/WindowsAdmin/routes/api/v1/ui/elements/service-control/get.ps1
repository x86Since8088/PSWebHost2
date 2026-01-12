param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Service Control API Endpoint
# Returns the card HTML with the service-control component

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "apps/WindowsAdmin/public/elements/service-control/component.js"

    if (-not (Test-Path $componentPath)) {
        context_reponse -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="service-control-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('service-control-root');
if (container && window.cardComponents && window.cardComponents['service-control']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['service-control'], {
            url: '/api/v1/ui/elements/service-control',
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
    Write-PSWebHostLog -Severity 'Error' -Category 'ServiceControl' -Message "Error loading service control: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
