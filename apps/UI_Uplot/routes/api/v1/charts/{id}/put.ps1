#Requires -Version 7

<#
.SYNOPSIS
    Update Chart Configuration
.DESCRIPTION
    Updates an existing chart configuration
#>

param($Request, $Response, $Session)

try {
    # Extract chart ID from URL path
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $chartId = $pathParts[-1]

    if ([string]::IsNullOrWhiteSpace($chartId)) {
        $Response.StatusCode = 400
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "Chart ID is required"}')
        return
    }

    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    if ([string]::IsNullOrWhiteSpace($bodyJson)) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "Empty request body"}')
        return
    }

    # Parse JSON payload
    $updates = $bodyJson | ConvertFrom-Json

    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']

    # Get existing chart
    $chart = $appNamespace.Charts[$chartId]

    # If not in memory, try loading from disk
    if (-not $chart) {
        $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"

        if (Test-Path $chartFile) {
            $chartJson = Get-Content $chartFile -Raw
            $chart = $chartJson | ConvertFrom-Json | ConvertTo-Hashtable
            $appNamespace.Charts[$chartId] = [hashtable]::Synchronized($chart)
        }
    }

    if (-not $chart) {
        $Response.StatusCode = 404
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "Chart not found"}')
        return
    }

    # Verify ownership
    if ($chart.userId -ne $Session.User.UserId) {
        $Response.StatusCode = 403
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "Access denied"}')
        return
    }

    # Validate chart type if provided
    if ($updates.chartType) {
        $validChartTypes = @('time-series', 'area-chart', 'bar-chart', 'scatter-plot', 'multi-axis', 'heatmap')
        if ($updates.chartType -notin $validChartTypes) {
            $Response.StatusCode = 400
            $Response.Write('{"error": "Invalid chart type"}')
            return
        }
        $chart.chartType = $updates.chartType
    }

    # Validate data source if provided
    if ($updates.dataSource) {
        if ($updates.dataSource.type) {
            $validDataSources = @('rest-json', 'rest-csv', 'sql-js', 'metrics-db', 'static-json', 'upload-csv')
            if ($updates.dataSource.type -notin $validDataSources) {
                $Response.StatusCode = 400
                $Response.Write('{"error": "Invalid data source type"}')
                return
            }
        }
        $chart.dataSource = ConvertTo-Hashtable $updates.dataSource
    }

    # Update allowed fields
    $allowedUpdates = @('title', 'width', 'height', 'realTime', 'refreshInterval')

    foreach ($field in $allowedUpdates) {
        if ($null -ne $updates.$field) {
            $chart.$field = $updates.$field
        }
    }

    # Update metadata
    $chart.updatedAt = Get-Date -Format 'o'
    $chart.updatedBy = $Session.User.Username
    $chart.lastAccessed = Get-Date -Format 'o'

    # Save to disk
    $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"
    $chart | ConvertTo-Json -Depth 10 | Set-Content -Path $chartFile -Encoding UTF8

    Write-Verbose "[UI_Uplot] Updated chart: $chartId"

    # Return updated chart
    $responseData = @{
        success = $true
        chartId = $chartId
        message = "Chart updated successfully"
        chart = $chart
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json -Depth 10

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] Error updating chart: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}

# Helper function to convert PSCustomObject to Hashtable
function ConvertTo-Hashtable {
    param([Parameter(ValueFromPipeline)]$InputObject)

    process {
        if ($null -eq $InputObject) { return $null }

        if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
            $collection = @(
                foreach ($object in $InputObject) {
                    ConvertTo-Hashtable -InputObject $object
                }
            )
            return ,$collection
        }
        elseif ($InputObject -is [psobject]) {
            $hash = @{}
            foreach ($property in $InputObject.PSObject.Properties) {
                $hash[$property.Name] = ConvertTo-Hashtable -InputObject $property.Value
            }
            return $hash
        }
        else {
            return $InputObject
        }
    }
}
