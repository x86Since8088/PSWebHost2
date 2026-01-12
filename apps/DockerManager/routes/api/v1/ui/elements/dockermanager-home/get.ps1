param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Serve the UI element HTML
$html = @`"
<link rel="stylesheet" href="/apps/dockermanager/public/elements/dockermanager-home/style.css">
<script src="/apps/dockermanager/public/elements/dockermanager-home/component.js"></script>
<dockermanager-home></dockermanager-home>
`"@

context_reponse -Response $Response -String $html -ContentType 'text/html' -StatusCode 200
