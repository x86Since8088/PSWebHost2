param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $cardInfo = @{
        component = 'world-map'
        scriptPath = '/apps/Maps/public/elements/world-map/component.js'
        title = 'World Map'
        description = 'Interactive world map with location markers and geographic data visualization'
        version = '1.0.0'
        width = 12
        height = 14
        features = @(
            'Interactive world map with equirectangular projection'
            'Location markers with status indicators'
            'Geographic data visualization'
            'Pan and zoom capabilities'
            'Customizable map pins and overlays'
        )
        # Include map pins data
        mapPins = @(
            @{ id = 'ny'; title = 'New York'; status = 'Operational'; lat = 40.7128; lng = -74.0060 },
            @{ id = 'london'; title = 'London'; status = 'Operational'; lat = 51.5074; lng = -0.1278 },
            @{ id = 'tokyo'; title = 'Tokyo'; status = 'Degraded'; lat = 35.6895; lng = 139.6917 },
            @{ id = 'sydney'; title = 'Sydney'; status = 'Outage'; lat = -33.8688; lng = 151.2093 },
            @{ id = 'rio'; title = 'Rio de Janeiro'; status = 'Operational'; lat = -22.9068; lng = -43.1729 }
        )
    }

    context_response -Response $Response -String ($cardInfo | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'Maps' -Message "Error loading world-map UI endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
