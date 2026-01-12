#Requires -Version 7

<#
.SYNOPSIS
    Create New Chart Instance
.DESCRIPTION
    Creates a new chart configuration with specified data source
#>

param($Request, $Response, $Session)

try {
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
    $chartConfig = $bodyJson | ConvertFrom-Json

    # Validate required fields
    if (-not $chartConfig.chartType) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "chartType is required"}')
        return
    }

    if (-not $chartConfig.title) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "title is required"}')
        return
    }

    if (-not $chartConfig.dataSource -or -not $chartConfig.dataSource.type) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "dataSource configuration is required"}')
        return
    }

    # Generate unique chart ID
    $chartId = [guid]::NewGuid().ToString('N').Substring(0, 12)

    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']

    # Build chart object
    $chart = @{
        chartId = $chartId
        chartType = $chartConfig.chartType
        title = $chartConfig.title
        width = $chartConfig.width ?? 800
        height = $chartConfig.height ?? 400
        dataSource = $chartConfig.dataSource
        realTime = $chartConfig.realTime ?? $false
        refreshInterval = $chartConfig.refreshInterval ?? 5
        createdAt = Get-Date -Format 'o'
        createdBy = $Session.User.Username
        userId = $Session.User.UserId
        lastAccessed = Get-Date -Format 'o'
        viewCount = 0
    }

    # Validate data source configuration
    $dataSourceType = $chart.dataSource.type
    $validDataSources = @('rest-json', 'rest-csv', 'sql-js', 'metrics-db', 'static-json', 'upload-csv')

    if ($dataSourceType -notin $validDataSources) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "Invalid data source type: ' + $dataSourceType + '"}')
        return
    }

    # Validate chart type
    $validChartTypes = @('time-series', 'area-chart', 'bar-chart', 'scatter-plot', 'multi-axis', 'heatmap')
    if ($chart.chartType -notin $validChartTypes) {
        $Response.StatusCode = 400
        $Response.Write('{"error": "Invalid chart type: ' + $chart.chartType + '"}')
        return
    }

    # Store chart in registry
    $appNamespace.Charts[$chartId] = [hashtable]::Synchronized($chart)

    # Persist chart configuration to disk
    $chartsDir = Join-Path $appNamespace.DataPath 'dashboards'
    if (-not (Test-Path $chartsDir)) {
        New-Item -Path $chartsDir -ItemType Directory -Force | Out-Null
    }

    $chartFile = Join-Path $chartsDir "$chartId.json"
    $chart | ConvertTo-Json -Depth 10 | Set-Content -Path $chartFile -Encoding UTF8

    # Update statistics
    $appNamespace.Stats['ChartsCreated']++

    Write-Verbose "[UI_Uplot] Created chart: $chartId (type: $($chart.chartType), source: $dataSourceType)"

    # Return success response
    $responseData = @{
        success = $true
        chartId = $chartId
        chartType = $chart.chartType
        title = $chart.title
        viewUrl = "/apps/uplot/api/v1/ui/elements/$($chart.chartType)?chartId=$chartId"
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 201
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] Error creating chart: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
