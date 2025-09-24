param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

function Return-JsonError {
    param ([string]$Message)
    $errorResponse = @{ error = $Message } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 200 -String $errorResponse -ContentType "application/json"
}

# 1. Check for request body
$body = Get-RequestBody -Request $Request
if ([string]::IsNullOrEmpty($body)) {
    Return-JsonError -Message "Request body is empty."
    return
}

# 2. Check for JSON parsing errors
$data = $body | ConvertFrom-Json -ErrorAction SilentlyContinue
if (-not $data) {
    Return-JsonError -Message "Invalid JSON format in request body."
    return
}

$path = $data.path
$filter = $data.filter

# 3. Default path if not provided
if (-not $path) {
    $path = $Global:PSWebServer.Project_Root.Path
}

# 4. Sanitize the path
$sanitizedPath = Sanitize-FilePath -FilePath $path -BaseDirectory $Global:PSWebServer.Project_Root.Path
if ($sanitizedPath.Score -ne 'pass') {
    Return-JsonError -Message "Invalid path specified."
    return
}

$actualPath = $sanitizedPath.Path

# 5. Check if path exists
if (-not (Test-Path -Path $actualPath -PathType Container)) {
    Return-JsonError -Message "Directory not found: $actualPath"
    return
}

# 6. Execute directory listing with robust error handling
try {
    $filterString = if ($filter) { $filter -replace '[^\w\.\*]' } else { '*' }
    $items = Get-ChildItem -Path $actualPath -Filter $filterString -ErrorAction Stop | Select-Object Name, FullName, Length, LastWriteTime, @{Name="IsDirectory"; Expression={$_.PSIsContainer}}
    $responseString = $items | ConvertTo-Json
    context_reponse -Response $Response -String $responseString -ContentType "application/json"
} catch {
    $errorMessage = "Error reading directory '$actualPath'. Details: $($_.Exception.Message)"
    Return-JsonError -Message $errorMessage
}
