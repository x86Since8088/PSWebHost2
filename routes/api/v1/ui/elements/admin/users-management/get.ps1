param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>User Management</title>
    <link rel="stylesheet" href="/public/style.css">
</head>
<body>
    <div id="user-management-root"></div>
    <script src="/public/lib/react.development.js"></script>
    <script src="/public/lib/react-dom.development.js"></script>
    <script src="/public/lib/babel.min.js"></script>
    <script type="text/babel" src="/public/elements/admin/users-management/component.js"></script>
</body>
</html>
"@

context_reponse -Response $Response -String $html -ContentType "text/html"
