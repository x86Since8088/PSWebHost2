#Requires -Version 7

<#
.SYNOPSIS
    Delete Chart Configuration
.DESCRIPTION
    Deletes a specific chart configuration
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

    # Get chart for ownership verification
    $chart = $appNamespace.Charts[$chartId]

    # If not in memory, try loading from disk
    if (-not $chart) {
        $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"

        if (Test-Path $chartFile) {
            $chartJson = Get-Content $chartFile -Raw
            $chart = $chartJson | ConvertFrom-Json | ConvertTo-Hashtable
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

    # Remove from memory
    $appNamespace.Charts.Remove($chartId)

    # Delete from disk
    $chartFile = Join-Path $appNamespace.DataPath "dashboards\$chartId.json"
    if (Test-Path $chartFile) {
        Remove-Item -Path $chartFile -Force
    }

    # Update statistics
    $appNamespace.Stats['ChartsDeleted']++

    Write-Verbose "[UI_Uplot] Deleted chart: $chartId"

    # Return success response
    $responseData = @{
        success = $true
        chartId = $chartId
        message = "Chart deleted successfully"
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] Error deleting chart: $_"

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
