param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

try {
    # Build list of installed apps
    $appsData = @()

    if ($Global:PSWebServer.Apps -and $Global:PSWebServer.Apps.Count -gt 0) {
        foreach ($appName in $Global:PSWebServer.Apps.Keys) {
            $app = $Global:PSWebServer.Apps[$appName]
            $manifest = $app.Manifest

            # Skip apps without manifests
            if (-not $manifest) {
                Write-Verbose "Skipping app '$appName' - no manifest"
                continue
            }

            $appsData += @{
                name = $manifest.name ?? $appName
                version = $manifest.version ?? 'Unknown'
                description = $manifest.description ?? 'No description'
                enabled = $manifest.enabled ?? $true
                requiredRoles = if ($manifest.requiredRoles) { ($manifest.requiredRoles -join ', ') } else { 'None' }
                loaded = if ($app.Loaded) { $app.Loaded.ToString('yyyy-MM-dd HH:mm:ss') } else { 'Unknown' }
                path = $app.Path ?? 'Unknown'
            }
        }
    }

    $result = @{
        apps = $appsData
        nodeGuid = $Global:PSWebServer.NodeGuid ?? 'Unknown'
        totalApps = $appsData.Count
    }

    context_response -Response $Response -String ($result | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'AppsManager' -Message "Error loading apps list: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
