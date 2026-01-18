#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $SessionData
)

<#
.SYNOPSIS
    Vault Manager UI Endpoint
.DESCRIPTION
    Serves the vault credential manager interface for secure credential storage
#>

try {
    # Get component path from current app
    $appNamespace = $Global:PSWebServer['vault']
    $componentPath = Join-Path $appNamespace.AppRoot "public\elements\vault-manager\component.js"

    # Read the component JS
    $componentJs = ""
    if (Test-Path $componentPath) {
        $componentJs = Get-Content $componentPath -Raw
    } else {
        throw "Vault manager component not found at: $componentPath"
    }

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Vault Manager - Secure Credential Storage</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
    </style>
</head>
<body>
    <vault-manager></vault-manager>

    <script>
$componentJs
    </script>
</body>
</html>
"@

    context_response -Response $Response -StatusCode 200 -String $html -ContentType "text/html"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Vault' -Message "Error loading vault manager: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -SessionData $SessionData
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
