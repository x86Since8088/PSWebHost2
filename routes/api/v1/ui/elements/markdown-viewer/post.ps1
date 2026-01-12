param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

# Markdown Viewer POST endpoint
# Saves markdown content (requires admin/editor role)

$filePath = $Request.QueryString["file"]

if ([string]::IsNullOrEmpty($filePath)) {
    $errorResponse = @{
        status = 'error'
        message = 'No file specified. Use ?file=path/to/file.md'
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
    return
}

# Check authorization
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

if (-not $canEdit) {
    $errorResponse = @{
        status = 'error'
        message = 'Unauthorized: You do not have permission to edit this file'
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 403 -String $errorResponse -ContentType "application/json"
    return
}

# Security: Sanitize the file path to prevent directory traversal
$filePath = $filePath -replace '\.\.', '' -replace '//', '/'
$filePath = $filePath.TrimStart('/', '\')

# Only allow saving to specific directories
$allowedPrefixes = @('public/help/', 'public/docs/', 'docs/')
$isAllowed = $false
foreach ($prefix in $allowedPrefixes) {
    if ($filePath.StartsWith($prefix)) {
        $isAllowed = $true
        break
    }
}

if (-not $isAllowed) {
    $errorResponse = @{
        status = 'error'
        message = "Cannot save to this location. Allowed paths: $($allowedPrefixes -join ', ')"
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 403 -String $errorResponse -ContentType "application/json"
    return
}

# Read the request body
$reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
$body = $reader.ReadToEnd()
$reader.Close()

try {
    $data = $body | ConvertFrom-Json
} catch {
    $errorResponse = @{
        status = 'error'
        message = 'Invalid JSON in request body'
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
    return
}

if (-not $data.content) {
    $errorResponse = @{
        status = 'error'
        message = 'No content provided'
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 400 -String $errorResponse -ContentType "application/json"
    return
}

# Construct full path
$fullPath = Join-Path $Global:PSWebServer.Project_Root.Path $filePath

# Ensure directory exists
$directory = [System.IO.Path]::GetDirectoryName($fullPath)
if (-not (Test-Path $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

# Save the file
try {
    # Create backup if file exists
    if (Test-Path $fullPath) {
        $backupPath = "$fullPath.backup"
        Copy-Item -Path $fullPath -Destination $backupPath -Force
    }

    # Write new content
    Set-Content -Path $fullPath -Value $data.content -Encoding UTF8 -NoNewline

    Write-PSWebHostLog -Severity 'Info' -Category 'Content' -Message "Markdown file saved: $filePath by $($sessiondata.UserID)"

    $successResponse = @{
        status = 'success'
        message = 'File saved successfully'
        file = $filePath
        path = $fullPath
    } | ConvertTo-Json

    context_reponse -Response $Response -String $successResponse -ContentType "application/json"
} catch {
    $errorResponse = @{
        status = 'error'
        message = "Error saving file: $($_.Exception.Message)"
    } | ConvertTo-Json
    context_reponse -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
