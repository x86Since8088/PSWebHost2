#Requires -Version 7

<#
.SYNOPSIS
    UI_Uplot App Configuration Endpoint
.DESCRIPTION
    Returns the app configuration including settings from app.yaml
#>

param($Request, $Response, $Session)

try {
    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']

    if (-not $appNamespace) {
        $Response.StatusCode = 500
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "App not initialized"}')
        return
    }

    # Get manifest (app.yaml configuration)
    $manifest = $appNamespace.Manifest

    # Build configuration response
    $config = @{
        name = $manifest.name
        version = $manifest.version
        description = $manifest.description
        author = $manifest.author
        routePrefix = $manifest.routePrefix
        settings = $manifest.settings
        features = $manifest.features
        parentCategory = $manifest.parentCategory
        subCategory = $manifest.subCategory
    }

    $Response.StatusCode = 200
    $Response.ContentType = 'application/json'
    $Response.Write(($config | ConvertTo-Json -Depth 10))
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'UI_Uplot' -Message "Error getting config: $($_.Exception.Message)"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
