#Requires -Version 7

<#
.SYNOPSIS
    CSV Data Source Handler
.DESCRIPTION
    Processes CSV data (from URL or upload) and converts to uPlot format
    uPlot format: [[timestamps], [series1], [series2], ...]
#>

param($Request, $Response, $Session)

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    $config = $bodyJson | ConvertFrom-Json

    $csvData = $null

    # Determine CSV source
    if ($config.url) {
        # Fetch CSV from REST endpoint
        Write-Verbose "[UI_Uplot] Fetching CSV from URL: $($config.url)"

        try {
            $response = Invoke-WebRequest -Uri $config.url -Method Get -TimeoutSec 30
            $csvData = $response.Content
        } catch {
            throw "Failed to fetch CSV from URL: $_"
        }

    } elseif ($config.csvData) {
        # Use provided CSV data directly
        $csvData = $config.csvData

    } else {
        throw "No CSV data source provided (url or csvData required)"
    }

    # Parse CSV
    $hasHeaders = $config.hasHeaders ?? $true

    if ($hasHeaders) {
        # Import CSV with headers
        $csvObjects = $csvData | ConvertFrom-Csv
    } else {
        # Import CSV without headers - generate column names
        $lines = $csvData -split "`n" | Where-Object { $_ -match '\S' }
        $firstLine = $lines[0] -split ','
        $columnCount = $firstLine.Count

        # Generate headers: Column1, Column2, etc.
        $headers = 1..$columnCount | ForEach-Object { "Column$_" }
        $headerLine = $headers -join ','
        $csvWithHeaders = $headerLine + "`n" + $csvData
        $csvObjects = $csvWithHeaders | ConvertFrom-Csv
    }

    if (-not $csvObjects -or $csvObjects.Count -eq 0) {
        throw "No data found in CSV"
    }

    # Convert to uPlot format: [[timestamps], [series1], [series2], ...]
    # First column is assumed to be x-axis (timestamps or categories)

    $properties = $csvObjects[0].PSObject.Properties.Name
    if ($properties.Count -lt 2) {
        throw "CSV must have at least 2 columns (x-axis and at least one data series)"
    }

    # Initialize uPlot data structure
    $uplotData = @()

    # Add x-axis (first column) - try to parse as timestamps
    $xAxisProperty = $properties[0]
    $xAxisData = @()

    foreach ($row in $csvObjects) {
        $xValue = $row.$xAxisProperty

        # Try to parse as Unix timestamp
        if ($xValue -match '^\d+$') {
            $xAxisData += [long]$xValue
        }
        # Try to parse as ISO datetime
        elseif ([datetime]::TryParse($xValue, [ref]$null)) {
            $dt = [datetime]::Parse($xValue)
            $unixTime = [long]($dt.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
            $xAxisData += $unixTime
        }
        # Use as string/category (for bar charts, etc.)
        else {
            $xAxisData += $xValue
        }
    }

    $uplotData += ,$xAxisData

    # Add data series (remaining columns)
    for ($i = 1; $i -lt $properties.Count; $i++) {
        $seriesProperty = $properties[$i]
        $seriesData = @()

        foreach ($row in $csvObjects) {
            $value = $row.$seriesProperty

            # Try to parse as number
            if ([double]::TryParse($value, [ref]$null)) {
                $seriesData += [double]$value
            } else {
                # Non-numeric value - use null or 0
                $seriesData += $null
            }
        }

        $uplotData += ,$seriesData
    }

    # Build response with metadata
    $responseData = @{
        success = $true
        data = $uplotData
        metadata = @{
            rowCount = $csvObjects.Count
            columnCount = $properties.Count
            columns = $properties
            xAxisLabel = $properties[0]
            seriesLabels = $properties[1..($properties.Count - 1)]
            dataPoints = $csvObjects.Count
        }
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "[UI_Uplot] Converted CSV: $($csvObjects.Count) rows, $($properties.Count) columns"

    # Update statistics
    $appNamespace = $Global:PSWebServer['UI_Uplot']
    if ($appNamespace.Stats) {
        $appNamespace.Stats['DataPointsServed'] += $csvObjects.Count
    }

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] CSV data processing error: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
