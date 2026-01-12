#Requires -Version 7

<#
.SYNOPSIS
    List Chart Configurations
.DESCRIPTION
    Lists all chart configurations for the current user with optional filtering
#>

param($Request, $Response, $Session)

try {
    # Get app namespace
    $appNamespace = $Global:PSWebServer['UI_Uplot']

    # Parse query parameters
    $queryParams = @{}
    if ($Request.Url.Query) {
        $Request.Url.Query.TrimStart('?') -split '&' | ForEach-Object {
            $parts = $_ -split '=', 2
            if ($parts.Count -eq 2) {
                $queryParams[$parts[0]] = [System.Web.HttpUtility]::UrlDecode($parts[1])
            }
        }
    }

    $chartType = $queryParams['chartType']
    $offset = [int]($queryParams['offset'] ?? 0)
    $limit = [int]($queryParams['limit'] ?? 50)
    $sortBy = $queryParams['sortBy'] ?? 'lastAccessed'
    $sortOrder = $queryParams['sortOrder'] ?? 'desc'

    # Ensure dashboards directory exists
    $dashboardsPath = Join-Path $appNamespace.DataPath "dashboards"
    if (-not (Test-Path $dashboardsPath)) {
        New-Item -Path $dashboardsPath -ItemType Directory -Force | Out-Null
    }

    # Load all chart files from disk
    $chartFiles = Get-ChildItem -Path $dashboardsPath -Filter "*.json" -ErrorAction SilentlyContinue

    $userCharts = @()

    foreach ($file in $chartFiles) {
        try {
            $chartJson = Get-Content $file.FullName -Raw
            $chart = $chartJson | ConvertFrom-Json | ConvertTo-Hashtable

            # Filter by user
            if ($chart.userId -eq $Session.User.UserId) {
                # Filter by chart type if specified
                if (-not $chartType -or $chart.chartType -eq $chartType) {
                    # Create summary object
                    $summary = @{
                        chartId = $chart.chartId
                        title = $chart.title
                        chartType = $chart.chartType
                        width = $chart.width
                        height = $chart.height
                        realTime = $chart.realTime
                        refreshInterval = $chart.refreshInterval
                        createdAt = $chart.createdAt
                        createdBy = $chart.createdBy
                        updatedAt = $chart.updatedAt
                        updatedBy = $chart.updatedBy
                        lastAccessed = $chart.lastAccessed
                        viewCount = $chart.viewCount ?? 0
                        dataSource = @{
                            type = $chart.dataSource.type
                        }
                    }

                    $userCharts += $summary
                }
            }
        }
        catch {
            Write-Warning "[UI_Uplot] Failed to load chart from $($file.Name): $_"
        }
    }

    # Sort charts
    $userCharts = switch ($sortBy) {
        'createdAt' {
            if ($sortOrder -eq 'desc') {
                $userCharts | Sort-Object { [DateTime]$_.createdAt } -Descending
            } else {
                $userCharts | Sort-Object { [DateTime]$_.createdAt }
            }
        }
        'lastAccessed' {
            if ($sortOrder -eq 'desc') {
                $userCharts | Sort-Object { [DateTime]$_.lastAccessed } -Descending
            } else {
                $userCharts | Sort-Object { [DateTime]$_.lastAccessed }
            }
        }
        'title' {
            if ($sortOrder -eq 'desc') {
                $userCharts | Sort-Object title -Descending
            } else {
                $userCharts | Sort-Object title
            }
        }
        'viewCount' {
            if ($sortOrder -eq 'desc') {
                $userCharts | Sort-Object viewCount -Descending
            } else {
                $userCharts | Sort-Object viewCount
            }
        }
        default {
            if ($sortOrder -eq 'desc') {
                $userCharts | Sort-Object { [DateTime]$_.lastAccessed } -Descending
            } else {
                $userCharts | Sort-Object { [DateTime]$_.lastAccessed }
            }
        }
    }

    # Apply pagination
    $totalCount = $userCharts.Count
    $userCharts = $userCharts | Select-Object -Skip $offset -First $limit

    # Build response
    $responseData = @{
        success = $true
        charts = $userCharts
        pagination = @{
            total = $totalCount
            offset = $offset
            limit = $limit
            returned = $userCharts.Count
        }
        filters = @{
            chartType = $chartType
            sortBy = $sortBy
            sortOrder = $sortOrder
        }
        timestamp = Get-Date -Format 'o'
    } | ConvertTo-Json -Depth 10

    Write-Verbose "[UI_Uplot] Listed $($userCharts.Count) charts for user $($Session.User.Username)"

    $Response.ContentType = 'application/json'
    $Response.StatusCode = 200
    $Response.Write($responseData)

} catch {
    Write-Error "[UI_Uplot] Error listing charts: $_"

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
