#Requires -Version 7

<#
.SYNOPSIS
    Static File Server for UI_Uplot Public Elements
.DESCRIPTION
    Serves component.js, style.css, and other static files from the public/elements directory
#>

param($Request, $Response, $Session)

try {
    # Extract the full path after /public/elements/
    $fullPath = $Request.Url.AbsolutePath

    # Remove the route prefix to get the relative path
    # Expected format: /apps/uplot/public/elements/{component-name}/{file}
    if ($fullPath -match '/apps/uplot/public/elements/(.+)$') {
        $relativePath = $matches[1]
    }
    else {
        $Response.StatusCode = 400
        $Response.ContentType = 'text/plain'
        $Response.Write('Invalid path format')
        return
    }

    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']
    $appRoot = $appNamespace.App_Root.Path

    # Build full file path
    $filePath = Join-Path $appRoot "public/elements/$relativePath"

    # Security check - prevent directory traversal
    $filePath = [System.IO.Path]::GetFullPath($filePath)
    $appPublicPath = [System.IO.Path]::GetFullPath((Join-Path $appRoot "public"))

    if (-not $filePath.StartsWith($appPublicPath, [StringComparison]::OrdinalIgnoreCase)) {
        Write-PSWebHostLog -Severity 'Warning' -Category 'UI_Uplot' -Message "Directory traversal attempt blocked: $filePath"
        $Response.StatusCode = 403
        $Response.ContentType = 'text/plain'
        $Response.Write('Access denied')
        return
    }

    # Check if file exists
    if (-not (Test-Path $filePath -PathType Leaf)) {
        Write-PSWebHostLog -Severity 'Debug' -Category 'UI_Uplot' -Message "File not found: $filePath"
        $Response.StatusCode = 404
        $Response.ContentType = 'text/plain'
        $Response.Write('File not found')
        return
    }

    # Determine content type based on file extension
    $extension = [System.IO.Path]::GetExtension($filePath).ToLower()
    $contentType = switch ($extension) {
        '.js'   { 'application/javascript; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.html' { 'text/html; charset=utf-8' }
        '.txt'  { 'text/plain; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        '.woff' { 'font/woff' }
        '.woff2' { 'font/woff2' }
        '.ttf'  { 'font/ttf' }
        default { 'application/octet-stream' }
    }

    # Read and serve the file
    $fileContent = Get-Content $filePath -Raw -Encoding UTF8

    $Response.StatusCode = 200
    $Response.ContentType = $contentType

    # Add caching headers for static assets (cache for 1 hour)
    $Response.Headers.Add('Cache-Control', 'public, max-age=3600')
    $Response.Headers.Add('X-Content-Type-Options', 'nosniff')

    $Response.Write($fileContent)

    Write-PSWebHostLog -Severity 'Debug' -Category 'UI_Uplot' -Message "Served static file: $relativePath"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'UI_Uplot' -Message "Error serving static file: $($_.Exception.Message)"
    $Response.StatusCode = 500
    $Response.ContentType = 'text/plain'
    $Response.Write("Internal server error: $($_.Exception.Message)")
}
