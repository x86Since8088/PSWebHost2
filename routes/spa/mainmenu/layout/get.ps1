param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$layoutJsonPath = Join-Path $Global:PSWebServer.Project_Root.Path "public/layout.json"
$layoutJsonContent = Get-Content -Path $layoutJsonPath -Raw

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Layout Editor</title>
    <style>
        body { font-family: sans-serif; }
        textarea {
            width: 100%;
            height: 500px;
        }
    </style>
</head>
<body>
    <h1>Layout Editor</h1>
    <textarea id="layout-editor">$layoutJsonContent</textarea>
    <button id="save-button">Save</button>
    <div id="status"></div>

    <script>
        document.getElementById('save-button').addEventListener('click', () => {
            const editor = document.getElementById('layout-editor');
            const newContent = editor.value;

            fetch('/spa/mainmenu/layout',
            {
                method: 'PUT',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: newContent
            })
            .then(response => response.json())
            .then(data => {
                const statusDiv = document.getElementById('status');
                if (data.status === 'success') {
                    statusDiv.innerText = 'Save successful!';
                } else {
                    statusDiv.innerText = 'Save failed: ' + data.message;
                }
            });
        });
    </script>
</body>
</html>
"@

context_reponse -Response $Response -String $html -ContentType "text/html"
