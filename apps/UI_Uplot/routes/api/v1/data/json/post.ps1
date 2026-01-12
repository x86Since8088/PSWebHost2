#Requires -Version 7

<#
.SYNOPSIS
    JSON Data Source Handler
.DESCRIPTION
    Processes JSON data (from REST API or static) and converts to uPlot format
    uPlot format: [[timestamps], [series1], [series2], ...]
#>

param($Request, $Response, $Session)

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    $config = $bodyJson | ConvertFrom-Json

    $jsonData = $null

    # Determine JSON source
    if ($config.url) {
        # Fetch JSON from REST endpoint
        Write-Verbose "[UI_Uplot] Fetching JSON from URL: $($config.url)"

        try {
            $headers = @{}
            if ($config.headers) {
                $config.headers.PSObject.Properties | ForEach-Object {
                    $headers[$_.Name] = $_.Value
                }
            }

            $params = @{
                Uri = $config.url
                Method = 'GET'
                TimeoutSec = 30
            }

            if ($headers.Count -gt 0) {
                $params['Headers'] = $headers
            }

            $response = Invoke-RestMethod @params
            $jsonData = $response

        } catch {
            throw "Failed to fetch JSON from URL: $_"
        }

    } elseif ($config.data) {
        # Use provided JSON data directly
        $jsonData = $config.data

    } else {
        throw "No JSON data source provided (url or data required)"
    }

    # Validate JSON data is an array
    if ($jsonData -isnot [array]) {
        # Try to find array property
        if ($jsonData.data -is [array]) {
            $jsonData = $jsonData.data
        } elseif ($jsonData.results -is [array]) {
            $jsonData = $jsonData.results
        } elseif ($jsonData.items -is [array]) {
            $jsonData = $jsonData.items
        } else {
            throw "JSON data must be an array or contain 'data', 'results', or 'items' array property"
        }
    }

    if ($jsonData.Count -eq 0) {
        throw "JSON data array is empty"
    }

    # Get properties from first object
    $firstObject = $jsonData[0]
    $properties = $firstObject.PSObject.Properties.Name

    if ($properties.Count -lt 2) {
        throw "JSON objects must have at least 2 properties (x-axis and at least one data series)"
    }

    # Detect x-axis property (timestamp, time, date, x, or first property)
    $xAxisProperty = $null
    $timestampCandidates = @('timestamp', 'time', 'datetime', 'date', 't', 'x')

    foreach ($candidate in $timestampCandidates) {
        if ($properties -contains $candidate) {
            $xAxisProperty = $candidate
            break
        }
    }

    # If no timestamp property found, use first property
    if (-not $xAxisProperty) {
        $xAxisProperty = $properties[0]
        Write-Verbose "[UI_Uplot] No timestamp property found, using first property: $xAxisProperty"
    }

    # Initialize uPlot data structure
    $uplotData = @()

    # Add x-axis data
    $xAxisData = @()

    foreach ($obj in $jsonData) {
        $xValue = $obj.$xAxisProperty

        # Try to parse as Unix timestamp
        if ($xValue -is [long] -or $xValue -is [int]) {
            $xAxisData += [long]$xValue
        }
        # Try to parse as ISO datetime
        elseif ($xValue -is [string] -and [datetime]::TryParse($xValue, [ref]$null)) {
            $dt = [datetime]::Parse($xValue)
            $unixTime = [long]($dt.ToUniversalTime() - [datetime]'1970-01-01').TotalSeconds
            $xAxisData += $unixTime
        }
        # Try to parse as number
        elseif ([double]::TryParse($xValue, [ref]$null)) {
            $xAxisData += [double]$xValue
        }
        # Use as-is (for categories)
        else {
            $xAxisData += $xValue
        }
    }

    $uplotData += ,$xAxisData

    # Add data series (all properties except x-axis)
    $seriesProperties = $properties | Where-Object { $_ -ne $xAxisProperty }

    foreach ($seriesProperty in $seriesProperties) {
        $seriesData = @()

        foreach ($obj in $jsonData) {
            $value = $obj.$seriesProperty

            # Try to parse as number
            if ($value -is [long] -or $value -is [int] -or $value -is [double]) {
                $seriesData += [double]$value
            } elseif ([double]::TryParse($value, [ref]$null)) {
                $seriesData += [double]$value
            } else {
                # Non-numeric value - use null
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
            rowCount = $jsonData.Count
            columnCount = $properties.Count
            columns = $properties
            xAxisLabel = $xAxisProperty
            seriesLabels = $seriesProperties
            dataPoints = $jsonData.Count
        }
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "[UI_Uplot] Converted JSON: $($jsonData.Count) rows, $($properties.Count) columns"

    # Update statistics
    $appNamespace = $Global:PSWebServer['UI_Uplot']
    if ($appNamespace.Stats) {
        $appNamespace.Stats['DataPointsServed'] += $jsonData.Count
    }

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] JSON data processing error: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
