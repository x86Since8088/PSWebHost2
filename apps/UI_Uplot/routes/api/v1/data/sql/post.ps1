#Requires -Version 7

<#
.SYNOPSIS
    SQL.js Query Handler
.DESCRIPTION
    Executes SQL queries against in-browser SQLite database and returns uPlot format
    Note: This endpoint assists with query building and metadata, actual SQL.js execution happens client-side
    uPlot format: [[timestamps], [series1], [series2], ...]
#>

param($Request, $Response, $Session)

try {
    # Read request body
    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $bodyJson = $reader.ReadToEnd()
    $reader.Close()

    $config = $bodyJson | ConvertFrom-Json

    if (-not $config.query) {
        throw "SQL query is required"
    }

    # Validate SQL query (basic security check)
    $query = $config.query.Trim()

    # Only allow SELECT statements
    if ($query -notmatch '^\s*SELECT\s+') {
        throw "Only SELECT queries are allowed"
    }

    # Block dangerous SQL keywords
    $dangerousKeywords = @('DROP', 'DELETE', 'INSERT', 'UPDATE', 'ALTER', 'CREATE', 'TRUNCATE', 'EXEC', 'EXECUTE')
    foreach ($keyword in $dangerousKeywords) {
        if ($query -match "\b$keyword\b") {
            throw "Query contains forbidden keyword: $keyword"
        }
    }

    # For SQL.js queries, we return query metadata and let the client execute
    # However, if the client sent results, we can convert them

    if ($config.results) {
        # Client executed query and sent results for conversion
        $results = $config.results

        if ($results.Count -eq 0) {
            throw "Query returned no results"
        }

        # Get columns from first result
        $firstResult = $results[0]
        $columns = $firstResult.PSObject.Properties.Name

        if ($columns.Count -lt 2) {
            throw "Query must return at least 2 columns"
        }

        # Convert to uPlot format
        $uplotData = @()

        # First column is x-axis
        $xAxisColumn = $columns[0]
        $xAxisData = @()

        foreach ($row in $results) {
            $xValue = $row.$xAxisColumn

            # Parse timestamps
            if ($xValue -is [long] -or $xValue -is [int]) {
                $xAxisData += [long]$xValue
            } elseif ([double]::TryParse($xValue, [ref]$null)) {
                $xAxisData += [double]$xValue
            } else {
                $xAxisData += $xValue
            }
        }

        $uplotData += ,$xAxisData

        # Add data series
        for ($i = 1; $i -lt $columns.Count; $i++) {
            $seriesColumn = $columns[$i]
            $seriesData = @()

            foreach ($row in $results) {
                $value = $row.$seriesColumn

                if ($value -is [long] -or $value -is [int] -or $value -is [double]) {
                    $seriesData += [double]$value
                } elseif ([double]::TryParse($value, [ref]$null)) {
                    $seriesData += [double]$value
                } else {
                    $seriesData += $null
                }
            }

            $uplotData += ,$seriesData
        }

        # Return converted data
        $responseData = @{
            success = $true
            data = $uplotData
            metadata = @{
                rowCount = $results.Count
                columnCount = $columns.Count
                columns = $columns
                xAxisLabel = $columns[0]
                seriesLabels = $columns[1..($columns.Count - 1)]
                dataPoints = $results.Count
            }
            timestamp = Get-Date -Format 'o'
        } | ConvertTo-Json -Depth 10 -Compress

        Write-Verbose "[UI_Uplot] Converted SQL.js results: $($results.Count) rows"

        # Update statistics
        $appNamespace = $Global:PSWebServer['UI_Uplot']
        if ($appNamespace.Stats) {
            $appNamespace.Stats['DataPointsServed'] += $results.Count
        }

        $Response.ContentType = 'application/json'
        $Response.StatusCode = 200
        $Response.Write($responseData)

    } else {
        # Return query metadata for client-side execution
        $responseData = @{
            success = $true
            mode = 'client-side-execution'
            query = $query
            params = $config.params ?? @()
            instructions = @{
                library = 'sql.js'
                execution = 'Execute this query in the browser using SQL.js'
                dataFormat = 'Return results as array of objects, then call this endpoint again with results property'
            }
            timestamp = Get-Date -Format 'o'
        } | ConvertTo-Json -Depth 10

        $Response.ContentType = 'application/json'
        $Response.StatusCode = 200
        $Response.Write($responseData)
    }

} catch {
    Write-Error "[UI_Uplot] SQL.js query processing error: $_"

    $Response.StatusCode = 500
    $Response.ContentType = 'application/json'
    $errorResponse = @{
        error = $_.Exception.Message
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.Write($errorResponse)
}
