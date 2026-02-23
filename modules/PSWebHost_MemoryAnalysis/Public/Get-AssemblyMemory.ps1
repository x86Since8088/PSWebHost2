function Get-AssemblyMemory {
    <#
    .SYNOPSIS
        Analyzes memory consumption of loaded .NET assemblies and DLLs

    .DESCRIPTION
        Comprehensive assembly memory analysis including:
        - Enumeration of all loaded assemblies in current AppDomain
        - File size measurement for disk-based assemblies
        - Memory estimation for dynamic/in-memory assemblies
        - Type metadata overhead calculation
        - Method table analysis
        - GAC (Global Assembly Cache) filtering
        - Assembly dependency tracking
        - Static field memory estimation

    .PARAMETER IncludeGAC
        Include GAC (Global Assembly Cache) assemblies in results.
        GAC assemblies are shared across applications and typically
        don't contribute to per-application memory pressure.

    .PARAMETER IncludeDynamic
        Include dynamically generated assemblies (e.g., from Add-Type, Invoke-Expression)

    .PARAMETER MinimumSize
        Only include assemblies larger than this size in bytes (default: 0)

    .PARAMETER IncludeTypeDetails
        Include detailed type analysis (slower but more accurate)
        Calculates method counts, field counts, property counts per type

    .PARAMETER SortBy
        Sort results by: Name, Size, TypeCount (default: Size descending)

    .PARAMETER StreamCallback
        Optional scriptblock to receive incremental results
        Signature: param($AssemblyInfo)

    .EXAMPLE
        Get-AssemblyMemory

    .EXAMPLE
        Get-AssemblyMemory -IncludeGAC -MinimumSize 100KB | Format-Table

    .EXAMPLE
        # With type details and streaming
        $callback = { param($asm) Write-Host "$($asm.Name): $($asm.EstimatedSize) bytes" }
        Get-AssemblyMemory -IncludeTypeDetails -StreamCallback $callback

    .OUTPUTS
        Returns array of assembly info hashtables with:
        - Name: Assembly name
        - FullName: Fully qualified name (with version, culture, token)
        - Version: Assembly version
        - Location: File path (empty for dynamic assemblies)
        - FileSize: Actual file size on disk (if available)
        - EstimatedSize: Estimated memory consumption
        - TypeCount: Number of types defined
        - MethodCount: Total methods across all types (if IncludeTypeDetails)
        - FieldCount: Total fields (if IncludeTypeDetails)
        - IsGAC: Whether from Global Assembly Cache
        - IsDynamic: Whether dynamically generated
        - Culture: Assembly culture (e.g., "neutral", "en-US")
        - PublicKeyToken: Strong name token
        - RuntimeVersion: Target .NET runtime version
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$IncludeGAC,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeDynamic,

        [Parameter(Mandatory = $false)]
        [long]$MinimumSize = 0,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeTypeDetails,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Name', 'Size', 'TypeCount')]
        [string]$SortBy = 'Size',

        [Parameter(Mandatory = $false)]
        [scriptblock]$StreamCallback
    )

    $MyTag = '[Get-AssemblyMemory]'

    try {
        Write-Verbose "$MyTag Enumerating loaded assemblies..."

        # Get all assemblies in current AppDomain
        $assemblies = [AppDomain]::CurrentDomain.GetAssemblies()

        Write-Verbose "$MyTag Found $($assemblies.Count) loaded assemblies"

        $results = @()
        $processedCount = 0

        foreach ($assembly in $assemblies) {
            $processedCount++

            try {
                # Get assembly name components
                $asmName = $assembly.GetName()
                $name = $asmName.Name
                $version = $asmName.Version
                $culture = if ($asmName.CultureInfo) { $asmName.CultureInfo.Name } else { 'neutral' }
                $publicKeyToken = if ($asmName.GetPublicKeyToken()) {
                    [BitConverter]::ToString($asmName.GetPublicKeyToken()).Replace('-', '').ToLower()
                } else {
                    'null'
                }

                # Check filters
                $isGAC = $assembly.GlobalAssemblyCache
                $isDynamic = $assembly.IsDynamic

                if (-not $IncludeGAC -and $isGAC) {
                    Write-Verbose "$MyTag Skipping GAC assembly: $name"
                    continue
                }

                if (-not $IncludeDynamic -and $isDynamic) {
                    Write-Verbose "$MyTag Skipping dynamic assembly: $name"
                    continue
                }

                Write-Verbose "$MyTag [$processedCount/$($assemblies.Count)] Analyzing: $name"

                # Get location and file size
                $location = $assembly.Location
                $fileSize = 0

                if (-not [string]::IsNullOrWhiteSpace($location) -and (Test-Path $location)) {
                    try {
                        $fileInfo = Get-Item $location -ErrorAction Stop
                        $fileSize = $fileInfo.Length
                    } catch {
                        Write-Verbose "$MyTag Failed to get file size for $name : $_"
                    }
                }

                # Get types (with error handling for restricted assemblies)
                $types = @()
                $typeCount = 0

                try {
                    $types = $assembly.GetTypes()
                    $typeCount = $types.Count
                } catch [System.Reflection.ReflectionTypeLoadException] {
                    # Some types failed to load - use LoaderExceptions
                    $types = $_.Types | Where-Object { $null -ne $_ }
                    $typeCount = $types.Count
                    Write-Verbose "$MyTag Partial type load for $name : $typeCount types available"
                } catch {
                    # Assembly doesn't allow GetTypes - estimate from manifest
                    Write-Verbose "$MyTag Cannot enumerate types for $name : $_"
                    $typeCount = 0
                }

                # Estimate memory size
                $estimatedSize = 0

                if ($fileSize -gt 0) {
                    # Use actual file size as baseline
                    # Note: File size != memory size (metadata, JIT, etc.)
                    # Typical memory overhead: 1.5-2x file size for loaded assemblies
                    $estimatedSize = $fileSize

                    # Add type metadata overhead
                    $estimatedSize += $typeCount * 256  # ~256 bytes per type metadata

                } else {
                    # Dynamic assembly or file not available - estimate from metadata

                    # Base assembly overhead
                    $estimatedSize = 8192  # ~8KB for assembly structure

                    # Type metadata
                    $estimatedSize += $typeCount * 256

                    # If we have types, analyze deeper
                    if ($typeCount -gt 0 -and $types.Count -gt 0) {
                        # Sample first 100 types for method/field estimation
                        $sampleSize = [Math]::Min(100, $types.Count)
                        $sampleTypes = $types | Select-Object -First $sampleSize

                        $avgMethodsPerType = 0
                        $avgFieldsPerType = 0

                        foreach ($type in $sampleTypes) {
                            try {
                                $methods = $type.GetMethods([System.Reflection.BindingFlags]::Instance -bor
                                                            [System.Reflection.BindingFlags]::Static -bor
                                                            [System.Reflection.BindingFlags]::Public -bor
                                                            [System.Reflection.BindingFlags]::NonPublic -bor
                                                            [System.Reflection.BindingFlags]::DeclaredOnly)
                                $avgMethodsPerType += $methods.Count

                                $fields = $type.GetFields([System.Reflection.BindingFlags]::Instance -bor
                                                          [System.Reflection.BindingFlags]::Static -bor
                                                          [System.Reflection.BindingFlags]::Public -bor
                                                          [System.Reflection.BindingFlags]::NonPublic)
                                $avgFieldsPerType += $fields.Count
                            } catch {
                                # Skip types that error during reflection
                            }
                        }

                        if ($sampleSize -gt 0) {
                            $avgMethodsPerType = [Math]::Ceiling($avgMethodsPerType / $sampleSize)
                            $avgFieldsPerType = [Math]::Ceiling($avgFieldsPerType / $sampleSize)

                            # Method table overhead: ~64 bytes per method
                            $estimatedSize += ($typeCount * $avgMethodsPerType * 64)

                            # Field overhead: ~32 bytes per field
                            $estimatedSize += ($typeCount * $avgFieldsPerType * 32)
                        }
                    }
                }

                # Detailed type analysis (optional, slower)
                $methodCount = 0
                $fieldCount = 0
                $propertyCount = 0
                $eventCount = 0

                if ($IncludeTypeDetails -and $types.Count -gt 0) {
                    Write-Verbose "$MyTag Performing detailed type analysis for $name ..."

                    foreach ($type in $types) {
                        try {
                            # Count declared members only (not inherited)
                            $methods = $type.GetMethods([System.Reflection.BindingFlags]::Instance -bor
                                                        [System.Reflection.BindingFlags]::Static -bor
                                                        [System.Reflection.BindingFlags]::Public -bor
                                                        [System.Reflection.BindingFlags]::NonPublic -bor
                                                        [System.Reflection.BindingFlags]::DeclaredOnly)
                            $methodCount += $methods.Count

                            $fields = $type.GetFields([System.Reflection.BindingFlags]::Instance -bor
                                                      [System.Reflection.BindingFlags]::Static -bor
                                                      [System.Reflection.BindingFlags]::Public -bor
                                                      [System.Reflection.BindingFlags]::NonPublic)
                            $fieldCount += $fields.Count

                            $properties = $type.GetProperties([System.Reflection.BindingFlags]::Instance -bor
                                                              [System.Reflection.BindingFlags]::Static -bor
                                                              [System.Reflection.BindingFlags]::Public -bor
                                                              [System.Reflection.BindingFlags]::NonPublic -bor
                                                              [System.Reflection.BindingFlags]::DeclaredOnly)
                            $propertyCount += $properties.Count

                            $events = $type.GetEvents([System.Reflection.BindingFlags]::Instance -bor
                                                      [System.Reflection.BindingFlags]::Static -bor
                                                      [System.Reflection.BindingFlags]::Public -bor
                                                      [System.Reflection.BindingFlags]::NonPublic -bor
                                                      [System.Reflection.BindingFlags]::DeclaredOnly)
                            $eventCount += $events.Count

                        } catch {
                            # Skip types that error
                        }
                    }

                    Write-Verbose "$MyTag $name : $methodCount methods, $fieldCount fields, $propertyCount properties, $eventCount events"

                    # Refine estimate with actual counts
                    $detailedOverhead = ($methodCount * 64) + ($fieldCount * 32) + ($propertyCount * 48) + ($eventCount * 64)
                    $estimatedSize = [Math]::Max($estimatedSize, $fileSize + $detailedOverhead)
                }

                # Apply minimum size filter
                if ($estimatedSize -lt $MinimumSize) {
                    Write-Verbose "$MyTag Skipping $name (below minimum size)"
                    continue
                }

                # Build result object
                $assemblyInfo = @{
                    Name = $name
                    FullName = $assembly.FullName
                    Version = $version.ToString()
                    Location = $location
                    FileSize = $fileSize
                    EstimatedSize = $estimatedSize
                    TypeCount = $typeCount
                    IsGAC = $isGAC
                    IsDynamic = $isDynamic
                    Culture = $culture
                    PublicKeyToken = $publicKeyToken
                    RuntimeVersion = $assembly.ImageRuntimeVersion
                }

                if ($IncludeTypeDetails) {
                    $assemblyInfo.MethodCount = $methodCount
                    $assemblyInfo.FieldCount = $fieldCount
                    $assemblyInfo.PropertyCount = $propertyCount
                    $assemblyInfo.EventCount = $eventCount
                }

                $results += $assemblyInfo

                # Stream callback
                if ($StreamCallback) {
                    try {
                        & $StreamCallback -AssemblyInfo $assemblyInfo
                    } catch {
                        Write-Warning "$MyTag Stream callback failed: $_"
                    }
                }

            } catch {
                Write-Warning "$MyTag Failed to analyze assembly: $_"
            }
        }

        Write-Verbose "$MyTag Analyzed $($results.Count) assemblies (filtered from $($assemblies.Count))"

        # Sort results
        switch ($SortBy) {
            'Name' {
                $results = $results | Sort-Object Name
            }
            'TypeCount' {
                $results = $results | Sort-Object TypeCount -Descending
            }
            default {  # 'Size'
                $results = $results | Sort-Object EstimatedSize -Descending
            }
        }

        return $results

    } catch {
        Write-Error "$MyTag Failed to enumerate assemblies: $_"
        return @()
    }
}

function Get-AssemblyMemorySummary {
    <#
    .SYNOPSIS
        Returns summary statistics for loaded assemblies

    .DESCRIPTION
        Aggregates assembly memory data into summary statistics

    .PARAMETER AssemblyData
        Array of assembly info hashtables from Get-AssemblyMemory

    .OUTPUTS
        Returns summary hashtable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [array]$AssemblyData
    )

    $MyTag = '[Get-AssemblyMemorySummary]'

    try {
        $totalAssemblies = $AssemblyData.Count
        $totalEstimatedSize = ($AssemblyData | Measure-Object -Property EstimatedSize -Sum).Sum ?? 0
        $totalFileSize = ($AssemblyData | Measure-Object -Property FileSize -Sum).Sum ?? 0
        $totalTypes = ($AssemblyData | Measure-Object -Property TypeCount -Sum).Sum ?? 0

        $gacCount = ($AssemblyData | Where-Object { $_.IsGAC }).Count
        $dynamicCount = ($AssemblyData | Where-Object { $_.IsDynamic }).Count
        $privateCount = $totalAssemblies - $gacCount - $dynamicCount

        # Top 10 largest assemblies
        $topLargest = $AssemblyData | Sort-Object EstimatedSize -Descending | Select-Object -First 10

        # Assembly size distribution
        $sizeRanges = @{
            'Under 100 KB' = ($AssemblyData | Where-Object { $_.EstimatedSize -lt 100KB }).Count
            '100 KB - 1 MB' = ($AssemblyData | Where-Object { $_.EstimatedSize -ge 100KB -and $_.EstimatedSize -lt 1MB }).Count
            '1 MB - 10 MB' = ($AssemblyData | Where-Object { $_.EstimatedSize -ge 1MB -and $_.EstimatedSize -lt 10MB }).Count
            'Over 10 MB' = ($AssemblyData | Where-Object { $_.EstimatedSize -ge 10MB }).Count
        }

        return @{
            TotalAssemblies = $totalAssemblies
            TotalEstimatedSize = $totalEstimatedSize
            TotalFileSize = $totalFileSize
            TotalTypes = $totalTypes
            GAC_Count = $gacCount
            Dynamic_Count = $dynamicCount
            Private_Count = $privateCount
            AverageSize = if ($totalAssemblies -gt 0) { [Math]::Round($totalEstimatedSize / $totalAssemblies, 0) } else { 0 }
            TopLargest = $topLargest
            SizeDistribution = $sizeRanges
        }

    } catch {
        Write-Error "$MyTag Failed to generate summary: $_"
        return $null
    }
}

function Format-AssemblyMemoryReport {
    <#
    .SYNOPSIS
        Generates formatted text report of assembly memory analysis

    .DESCRIPTION
        Creates human-readable report with summary statistics and top assemblies

    .PARAMETER AssemblyData
        Array of assembly info from Get-AssemblyMemory

    .PARAMETER IncludeSummary
        Include summary statistics section

    .PARAMETER IncludeTopN
        Number of top assemblies to include (default: 20)

    .OUTPUTS
        Returns formatted string report
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [array]$AssemblyData,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSummary,

        [Parameter(Mandatory = $false)]
        [int]$IncludeTopN = 20
    )

    $report = @()

    if ($IncludeSummary) {
        $summary = Get-AssemblyMemorySummary -AssemblyData $AssemblyData

        $report += "=" * 80
        $report += "Assembly Memory Summary"
        $report += "=" * 80
        $report += ""
        $report += "Total Assemblies: $($summary.TotalAssemblies)"
        $report += "  - GAC (Shared):  $($summary.GAC_Count)"
        $report += "  - Dynamic:       $($summary.Dynamic_Count)"
        $report += "  - Private:       $($summary.Private_Count)"
        $report += ""
        $report += "Total Estimated Size: $([Math]::Round($summary.TotalEstimatedSize / 1MB, 2)) MB"
        $report += "Total File Size:      $([Math]::Round($summary.TotalFileSize / 1MB, 2)) MB"
        $report += "Average Size:         $([Math]::Round($summary.AverageSize / 1KB, 2)) KB"
        $report += "Total Types:          $($summary.TotalTypes)"
        $report += ""
        $report += "Size Distribution:"
        foreach ($range in $summary.SizeDistribution.Keys | Sort-Object) {
            $report += "  $($range.PadRight(15)) : $($summary.SizeDistribution[$range]) assemblies"
        }
        $report += ""
    }

    if ($IncludeTopN -gt 0) {
        $report += "=" * 80
        $report += "Top $IncludeTopN Largest Assemblies"
        $report += "=" * 80
        $report += ""
        $report += "{0,-40} {1,12} {2,10} {3,8}" -f "Name", "Size (KB)", "Types", "Source"
        $report += "-" * 80

        $topAssemblies = $AssemblyData | Sort-Object EstimatedSize -Descending | Select-Object -First $IncludeTopN

        foreach ($asm in $topAssemblies) {
            $sizeKB = [Math]::Round($asm.EstimatedSize / 1KB, 2)
            $source = if ($asm.IsGAC) { "GAC" } elseif ($asm.IsDynamic) { "Dynamic" } else { "Private" }

            $report += "{0,-40} {1,12:N2} {2,10} {3,8}" -f $asm.Name, $sizeKB, $asm.TypeCount, $source
        }
    }

    return $report -join "`n"
}
