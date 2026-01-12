param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Serve the UI element HTML
$html = @`"
<link rel="stylesheet" href="/apps/kubernetesmanager/public/elements/kubernetesmanager-home/style.css">
<script src="/apps/kubernetesmanager/public/elements/kubernetesmanager-home/component.js"></script>
<kubernetesmanager-home></kubernetesmanager-home>
`"@

context_reponse -Response $Response -String $html -ContentType 'text/html' -StatusCode 200
