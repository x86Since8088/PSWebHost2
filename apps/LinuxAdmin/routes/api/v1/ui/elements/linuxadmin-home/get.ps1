param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $SessionData
)

# Serve the UI element HTML
$html = @`"
<link rel="stylesheet" href="/apps/linuxadmin/public/elements/linuxadmin-home/style.css">
<script src="/apps/linuxadmin/public/elements/linuxadmin-home/component.js"></script>
<linuxadmin-home></linuxadmin-home>
`"@

context_response -Response $Response -String $html -ContentType 'text/html' -StatusCode 200
