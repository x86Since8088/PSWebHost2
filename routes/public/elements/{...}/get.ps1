#Requires -Version 7

<#
.SYNOPSIS
    Global Component Static File Proxy
.DESCRIPTION
    Searches for and serves component files from app public directories
    This handles the case where the SPA tries to load /public/elements/{component}/component.js
    but the files are actually in apps/{appname}/public/elements/{component}/component.js
#>

param($Request, $Response, $Session)

try {
    # Extract the requested path after /public/elements/
    $fullPath = $Request.Url.AbsolutePath

    if ($fullPath -match '/public/elements/(.+)$') {
        $relativePath = $matches[1]
    }
    else {
        $Response.StatusCode = 400
        $Response.ContentType = 'text/plain'
        $Response.Write('Invalid path format')
        return
    }

    # Parse component name and file path
    # Expected formats:
    # - /public/elements/uplot-home/component.js
    # - /public/elements/time-series/component.js
    # - /public/elements/service-control/component.js
    $pathParts = $relativePath -split '/', 2
    $componentName = $pathParts[0]
    $fileName = if ($pathParts.Count -gt 1) { $pathParts[1] } else { '' }

    if ([string]::IsNullOrWhiteSpace($componentName)) {
        $Response.StatusCode = 400
        $Response.ContentType = 'text/plain'
        $Response.Write('Component name is required')
        return
    }

    # Map of known components to their app directories
    # This could be made dynamic by scanning all apps, but for now we'll use a static map
    $componentAppMap = @{
        # UI_Uplot components
        'uplot-home' = 'UI_Uplot'
        'time-series' = 'UI_Uplot'
        'area-chart' = 'UI_Uplot'
        'bar-chart' = 'UI_Uplot'
        'scatter-plot' = 'UI_Uplot'
        'multi-axis' = 'UI_Uplot'
        'heatmap' = 'UI_Uplot'

        # WindowsAdmin components
        'windowsadmin-home' = 'WindowsAdmin'
        'service-control' = 'WindowsAdmin'
        'task-scheduler' = 'WindowsAdmin'

        # SQLiteManager components
        'sqlite-manager' = 'SQLiteManager'
        'sqlite-query-editor' = 'SQLiteManager'
    }

    # Try to find the component in the known apps
    $appName = $componentAppMap[$componentName]

    if (-not $appName) {
        # If not in map, try searching across all apps dynamically
        $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
        $appDirs = Get-ChildItem -Path $appsPath -Directory -ErrorAction SilentlyContinue

        foreach ($appDir in $appDirs) {
            $testPath = Join-Path $appDir.FullName "public/elements/$componentName"
            if (Test-Path $testPath -PathType Container) {
                $appName = $appDir.Name
                break
            }
        }
    }

    if (-not $appName) {
        Write-PSWebHostLog -Severity 'Debug' -Category 'StaticFiles' -Message "Component not found: $componentName"
        $Response.StatusCode = 404
        $Response.ContentType = 'text/plain'
        $Response.Write("Component not found: $componentName")
        return
    }

    # Build the full file path
    $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
    $filePath = Join-Path $appsPath "$appName/public/elements/$componentName/$fileName"

    # Security check - prevent directory traversal
    $filePath = [System.IO.Path]::GetFullPath($filePath)
    $appPublicPath = [System.IO.Path]::GetFullPath((Join-Path $appsPath "$appName/public"))

    if (-not $filePath.StartsWith($appPublicPath, [StringComparison]::OrdinalIgnoreCase)) {
        Write-PSWebHostLog -Severity 'Warning' -Category 'StaticFiles' -Message "Directory traversal attempt blocked: $filePath"
        $Response.StatusCode = 403
        $Response.ContentType = 'text/plain'
        $Response.Write('Access denied')
        return
    }

    # Check if file exists
    if (-not (Test-Path $filePath -PathType Leaf)) {
        Write-PSWebHostLog -Severity 'Debug' -Category 'StaticFiles' -Message "File not found: $filePath"
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
        default { 'application/octet-stream' }
    }

    # Read and serve the file
    $fileContent = Get-Content $filePath -Raw -Encoding UTF8

    $Response.StatusCode = 200
    $Response.ContentType = $contentType

    # Add caching headers
    $Response.Headers.Add('Cache-Control', 'public, max-age=3600')
    $Response.Headers.Add('X-Content-Type-Options', 'nosniff')

    $Response.Write($fileContent)

    Write-PSWebHostLog -Severity 'Debug' -Category 'StaticFiles' -Message "Served component file: $appName/$componentName/$fileName"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'StaticFiles' -Message "Error serving component file: $($_.Exception.Message)"
    $Response.StatusCode = 500
    $Response.ContentType = 'text/plain'
    $Response.Write("Internal server error: $($_.Exception.Message)")
}
