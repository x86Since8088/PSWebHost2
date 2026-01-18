param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Serve the UI element HTML
$html = @`"
<link rel="stylesheet" href="/apps/wslmanager/public/elements/wslmanager-home/style.css">
<script src="/apps/wslmanager/public/elements/wslmanager-home/component.js"></script>
<wslmanager-home></wslmanager-home>
`"@

context_response -Response $Response -String $html -ContentType 'text/html' -StatusCode 200
