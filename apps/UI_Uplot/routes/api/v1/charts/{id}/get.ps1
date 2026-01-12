#Requires -Version 7

<#
.SYNOPSIS
    Retrieve Chart Configuration
.DESCRIPTION
    Retrieves a specific chart configuration by ID
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

    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']

    # Try to get from memory first
    $chart = $appNamespace.Charts[$chartId]

    # If not in memory, try loading from disk
    if (-not $chart) {
        $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"

        if (Test-Path $chartFile) {
            $chartJson = Get-Content $chartFile -Raw
            $chart = $chartJson | ConvertFrom-Json | ConvertTo-Hashtable

            # Load into memory
            $appNamespace.Charts[$chartId] = [hashtable]::Synchronized($chart)

            Write-Verbose "[UI_Uplot] Loaded chart from disk: $chartId"
        }
    }

    if (-not $chart) {
        $Response.StatusCode = 404
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "Chart not found"}')
        return
    }

    # Verify ownership (users can only access their own charts)
    if ($chart.userId -ne $Session.User.UserId) {
        $Response.StatusCode = 403
        $Response.ContentType = 'application/json'
        $Response.Write('{"error": "Access denied"}')
        return
    }

    # Update access stats
    $chart.lastAccessed = Get-Date -Format 'o'
    $chart.viewCount++

    # Save updated stats to disk
    $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"
    $chart | ConvertTo-Json -Depth 10 | Set-Content -Path $chartFile -Encoding UTF8

    # Return chart configuration
    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write(($chart | ConvertTo-Json -Depth 10))

} catch {
    Write-Error "[UI_Uplot] Error retrieving chart: $_"

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
