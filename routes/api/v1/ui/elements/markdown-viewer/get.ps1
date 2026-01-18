param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Markdown Viewer API endpoint
# Returns raw markdown content for client-side rendering

$filePath = $Request.QueryString["file"]

if ([string]::IsNullOrEmpty($filePath)) {
    $errorResponse = @{
        status = 'error'
        message = 'No file specified. Use ?file=path/to/file.md'
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
    return
}

# Security: Sanitize the file path to prevent directory traversal
$filePath = $filePath -replace '\.\.', '' -replace '//', '/'
$filePath = $filePath.TrimStart('/', '\')

# Look for the file in allowed locations
$searchPaths = @(
    (Join-Path $Global:PSWebServer.Project_Root.Path "public/help/$filePath"),
    (Join-Path $Global:PSWebServer.Project_Root.Path "public/$filePath"),
    (Join-Path $Global:PSWebServer.Project_Root.Path "docs/$filePath")
)

# Also check if full path was provided (within allowed directories)
if ($filePath -match '^public/' -or $filePath -match '^docs/') {
    $searchPaths = @((Join-Path $Global:PSWebServer.Project_Root.Path $filePath)) + $searchPaths
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
        message = "File not found: $filePath"
        searched = $searchPaths
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType "application/json"
    return
}

# Check if user can edit (must have 'admin' or 'editor' role)
$canEdit = $false
if ($sessiondata -and $sessiondata.Roles) {
    $editRoles = @('admin', 'editor', 'content-editor')
    foreach ($role in $editRoles) {
        if ($sessiondata.Roles -contains $role) {
            $canEdit = $true
            break
        }
    }
}

# Read the markdown content
try {
    $markdownContent = Get-Content -Path $foundPath -Raw -ErrorAction Stop

    $successResponse = @{
        status = 'success'
        file = $filePath
        path = $foundPath
        content = $markdownContent
        canEdit = $canEdit
    } | ConvertTo-Json -Depth 10

    context_response -Response $Response -String $successResponse -ContentType "application/json"
} catch {
    $errorResponse = @{
        status = 'error'
        message = "Error reading file: $($_.Exception.Message)"
    } | ConvertTo-Json
    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
