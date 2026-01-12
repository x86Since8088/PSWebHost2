param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Site Settings API Endpoint
# Returns the card HTML with the site-settings component

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "public/elements/site-settings/component.js"

    if (-not (Test-Path $componentPath)) {
        context_reponse -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="site-settings-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('site-settings-root');
if (container && window.cardComponents && window.cardComponents['site-settings']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['site-settings'], {
            url: '/api/v1/ui/elements/site-settings',
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
    Write-PSWebHostLog -Severity 'Error' -Category 'SiteSettings' -Message "Error loading site settings: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
