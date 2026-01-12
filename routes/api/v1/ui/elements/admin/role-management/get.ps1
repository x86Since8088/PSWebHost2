param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Role Management API Endpoint
# Returns the card HTML with the role-management component

try {
    $componentPath = Join-Path $global:PSWebServer.Project_Root.Path "public/elements/admin/role-management/component.js"

    if (-not (Test-Path $componentPath)) {
        context_reponse -Response $Response -StatusCode 404 -String "Component not found" -ContentType "text/plain"
        return
    }

    $componentJS = Get-Content $componentPath -Raw

    $html = @"
<div id="role-management-root"></div>
<script>
$componentJS

// Render the component
const container = document.getElementById('role-management-root');
if (container && window.cardComponents && window.cardComponents['role-management']) {
    ReactDOM.render(
        React.createElement(window.cardComponents['role-management'], {
            url: '/api/v1/ui/elements/admin/role-management',
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
    Write-PSWebHostLog -Severity 'Error' -Category 'RoleManagement' -Message "Error loading role management: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
