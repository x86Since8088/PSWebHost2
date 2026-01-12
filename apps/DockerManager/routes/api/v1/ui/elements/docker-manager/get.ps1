param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Docker Manager API Endpoint
# Returns the card HTML with the docker-manager component
# Note: This endpoint is intended for Linux platforms only

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "apps/DockerManager/public/elements/docker-manager/component.js"

    if (-not (Test-Path $componentPath)) {
        context_reponse -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="docker-manager-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('docker-manager-root');
if (container && window.cardComponents && window.cardComponents['docker-manager']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['docker-manager'], {
            url: '/api/v1/ui/elements/docker-manager',
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
    Write-PSWebHostLog -Severity 'Error' -Category 'DockerManager' -Message "Error loading docker manager: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
