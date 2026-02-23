param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Help Viewer API endpoint
# Returns card metadata when no parameters, or markdown content for client-side rendering

# Get the requested help file path
$filePath = $Request.QueryString["file"]

# If no file parameter, return card metadata
if ([string]::IsNullOrEmpty($filePath)) {
    $metadata = @{
        component = 'help-viewer'
        scriptPath = '/apps/WebHostHelpViewer/public/elements/help-viewer/component.js'
        stylePath = '/apps/WebHostHelpViewer/public/elements/help-viewer/style.css'
        title = 'Help Viewer'
        width = 12
        height = 600
        features = @{
            resize = $true
            minimize = $true
        }
    } | ConvertTo-Json -Depth 10

    context_response -Response $Response -String $metadata -ContentType "application/json"
    return
}

# Security: Sanitize the file path to prevent directory traversal
$filePath = $filePath -replace '\.\.', '' -replace '//', '/'
$filePath = $filePath.TrimStart('/', '\')

# Look for the file in multiple locations
$searchPaths = @(
    (Join-Path $Global:PSWebServer.Project_Root.Path "public/help/$filePath"),
    (Join-Path $Global:PSWebServer.Project_Root.Path $filePath),
    (Join-Path $Global:PSWebServer.Project_Root.Path "docs/$filePath")
)

# Add app-specific help directories
try {
    $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
    if (Test-Path $appsPath) {
        $appDirs = Get-ChildItem -Path $appsPath -Directory -ErrorAction SilentlyContinue
        foreach ($appDir in $appDirs) {
            $searchPaths += Join-Path $appDir.FullName "help/$filePath"
            $searchPaths += Join-Path $appDir.FullName "docs/$filePath"
        }
    }
} catch {
    # Silently continue if can't read apps directory
}

$foundPath = $null
foreach ($path in $searchPaths) {
    if (Test-Path $path -PathType Leaf) {
        $foundPath = $path
        break
    }
}

if (-not $foundPath) {
    $errorResponse = @{
        status = 'error'
        message = "Help file not found: $filePath"
        searched = $searchPaths
    } | ConvertTo-Json -Depth 5
    context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType "application/json"
    return
}

# Read the markdown content
try {
    $markdownContent = Get-Content -Path $foundPath -Raw -ErrorAction Stop

    $successResponse = @{
        status = 'success'
        file = $filePath
        content = $markdownContent
        path = $foundPath
    } | ConvertTo-Json -Depth 10

    context_response -Response $Response -String $successResponse -ContentType "application/json"
} catch {
    $errorResponse = @{
        status = 'error'
        message = "Error reading help file: $($_.Exception.Message)"
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
