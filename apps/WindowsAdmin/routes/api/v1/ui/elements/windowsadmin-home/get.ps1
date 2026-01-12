param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Serve the UI element HTML
$html = @`"
<link rel="stylesheet" href="/apps/windowsadmin/public/elements/windowsadmin-home/style.css">
<script src="/apps/windowsadmin/public/elements/windowsadmin-home/component.js"></script>
<windowsadmin-home></windowsadmin-home>
`"@

context_reponse -Response $Response -String $html -ContentType 'text/html' -StatusCode 200
