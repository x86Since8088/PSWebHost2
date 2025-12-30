# routes\spa\post.ps1
param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Read request body
$reader = New-Object System.IO.StreamReader($Request.InputStream, $Request.ContentEncoding)
$bodyContent = $reader.ReadToEnd()
$reader.Close()

$responseObj = @{
    message = "SPA POST Route. Method: $($Request.HttpMethod), Path: $($Request.Url.LocalPath)"
}
if ($bodyContent) {
    $responseObj.body = $bodyContent
}

# Get card settings if user is authenticated
$userId = $SessionData['UserID'] | Out-String
if ($userId) {
    $endpointGuid = (Get-Content (Join-Path $PSScriptRoot 'post.json') | ConvertFrom-Json).guid
    $cardSettings = Get-CardSettings -EndpointGuid $endpointGuid -UserId $userId
    if ($cardSettings) {
        $responseObj.settings = $cardSettings | ConvertFrom-Json
    }
}

$responseJson = $responseObj | ConvertTo-Json -Depth 5
context_reponse -Response $Response -String $responseJson -ContentType "application/json"
