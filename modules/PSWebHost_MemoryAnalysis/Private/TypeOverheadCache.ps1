# Private helper for loading and caching type overhead data from CSV

# Module-scoped cache for type overhead calculations
$script:TypeOverheadCache = $null
$script:TypeOverheadCachePath = $null

function Initialize-TypeOverheadCache {
    <#
    .SYNOPSIS
        Loads type overhead calculations from CSV into memory cache

    .DESCRIPTION
        Reads PS_Object_Memory_Calculations.csv and creates a hashtable lookup
        for O(1) type overhead retrieval. Cache is module-scoped and persists
        for the lifetime of the module.

    .PARAMETER Force
        Force reload of the cache even if already loaded

    .OUTPUTS
        Returns hashtable with type overhead data
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $MyTag = '[Initialize-TypeOverheadCache]'

    # Return existing cache if already loaded
    if ($script:TypeOverheadCache -and -not $Force) {
        Write-Verbose "$MyTag Using cached type overhead data ($($script:TypeOverheadCache.Count) types)"
        return $script:TypeOverheadCache
    }

    try {
        # Locate CSV file
        $csvPath = $null

        # Try relative to PSWebServer root
        if ($Global:PSWebServer -and $Global:PSWebServer.Project_Root -and $Global:PSWebServer.Project_Root.Path) {
            $csvPath = Join-Path $Global:PSWebServer.Project_Root.Path "system\data\PS_Object_Memory_Calculations.csv"
        }

        # Fallback: search upward from module root
        if (-not $csvPath -or -not (Test-Path $csvPath)) {
            $moduleRoot = $PSScriptRoot | Split-Path -Parent
            $projectRoot = $moduleRoot | Split-Path -Parent | Split-Path -Parent
            $csvPath = Join-Path $projectRoot "system\data\PS_Object_Memory_Calculations.csv"
        }

        if (-not (Test-Path $csvPath)) {
            Write-Warning "$MyTag CSV file not found at: $csvPath"
            Write-Warning "$MyTag Will use runtime reflection only"
            $script:TypeOverheadCache = @{}
            return $script:TypeOverheadCache
        }

        Write-Verbose "$MyTag Loading type overhead data from: $csvPath"
        $script:TypeOverheadCachePath = $csvPath

        # Parse CSV
        $csvData = Import-Csv -Path $csvPath -ErrorAction Stop

        # Build hashtable for O(1) lookup
        $cache = @{}

        foreach ($row in $csvData) {
            $typeName = $row.TypeName

            if ([string]::IsNullOrWhiteSpace($typeName)) {
                continue
            }

            # Parse numeric values
            $baseSize = 0
            $perItemOverhead = 0
            [int]::TryParse($row.BaseSize, [ref]$baseSize) | Out-Null
            [int]::TryParse($row.PerItemOverhead, [ref]$perItemOverhead) | Out-Null

            # Parse boolean flags
            $isFixedSize = $row.IsFixedSize -eq 'True'
            $platformDependent = $row.PlatformDependent -eq 'True'

            $cache[$typeName] = @{
                TypeName = $typeName
                BaseSize = $baseSize
                PerItemOverhead = $perItemOverhead
                IsFixedSize = $isFixedSize
                PlatformDependent = $platformDependent
                Notes = $row.Notes
                Source = 'CSV'
            }
        }

        $script:TypeOverheadCache = $cache

        Write-Verbose "$MyTag Loaded $($cache.Count) type overhead entries from CSV"
        return $cache

    } catch {
        Write-Error "$MyTag Failed to load type overhead CSV: $_"
        $script:TypeOverheadCache = @{}
        return $script:TypeOverheadCache
    }
}

function Get-CachedTypeOverhead {
    <#
    .SYNOPSIS
        Retrieves type overhead from cache

    .PARAMETER TypeName
        Full type name (e.g., "System.String", "System.Collections.Hashtable")

    .OUTPUTS
        Returns hashtable with type overhead data or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName
    )

    # Ensure cache is loaded
    if (-not $script:TypeOverheadCache) {
        Initialize-TypeOverheadCache | Out-Null
    }

    # Lookup in cache
    if ($script:TypeOverheadCache.ContainsKey($TypeName)) {
        return $script:TypeOverheadCache[$TypeName]
    }

    return $null
}

function Add-RuntimeTypeOverhead {
    <#
    .SYNOPSIS
        Adds runtime-measured type overhead to cache

    .PARAMETER TypeName
        Full type name

    .PARAMETER TypeOverhead
        Hashtable with type overhead data

    .OUTPUTS
        None
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [Parameter(Mandatory = $true)]
        [hashtable]$TypeOverhead
    )

    $MyTag = '[Add-RuntimeTypeOverhead]'

    # Ensure cache exists
    if (-not $script:TypeOverheadCache) {
        Initialize-TypeOverheadCache | Out-Null
    }

    # Add to cache with runtime source marker
    $TypeOverhead.Source = 'Runtime'
    $script:TypeOverheadCache[$TypeName] = $TypeOverhead

    Write-Verbose "$MyTag Cached runtime overhead for: $TypeName"
}

function Get-TypeOverheadCacheStats {
    <#
    .SYNOPSIS
        Returns statistics about the type overhead cache

    .OUTPUTS
        Hashtable with cache statistics
    #>
    [CmdletBinding()]
    param()

    if (-not $script:TypeOverheadCache) {
        return @{
            Loaded = $false
            TotalEntries = 0
            CSVEntries = 0
            RuntimeEntries = 0
            CachePath = $null
        }
    }

    $csvEntries = ($script:TypeOverheadCache.Values | Where-Object { $_.Source -eq 'CSV' }).Count
    $runtimeEntries = ($script:TypeOverheadCache.Values | Where-Object { $_.Source -eq 'Runtime' }).Count

    return @{
        Loaded = $true
        TotalEntries = $script:TypeOverheadCache.Count
        CSVEntries = $csvEntries
        RuntimeEntries = $runtimeEntries
        CachePath = $script:TypeOverheadCachePath
    }
}
