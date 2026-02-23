function Get-TypeMemoryOverhead {
    <#
    .SYNOPSIS
        Calculates memory overhead for a PowerShell object type

    .DESCRIPTION
        Hybrid approach that first checks CSV database for known type overhead,
        then falls back to runtime reflection measurement for unknown types.
        Results are cached for subsequent lookups.

    .PARAMETER Object
        The object to analyze (can be any PowerShell object including $null)

    .PARAMETER TypeName
        Alternatively, provide type name directly (e.g., "System.String")

    .PARAMETER UseRuntimeOnly
        Skip CSV lookup and force runtime measurement

    .EXAMPLE
        $overhead = Get-TypeMemoryOverhead -Object $myHashtable

    .EXAMPLE
        $overhead = Get-TypeMemoryOverhead -TypeName "System.Collections.Hashtable"

    .OUTPUTS
        Returns hashtable with:
        - TypeName: Full type name
        - BaseSize: Base object size in bytes
        - PerItemOverhead: Overhead per collection item (if applicable)
        - IsFixedSize: Whether size is fixed regardless of content
        - PlatformDependent: Whether size varies by platform (32-bit vs 64-bit)
        - Notes: Additional information
        - Source: "CSV" or "Runtime"
    #>
    [CmdletBinding(DefaultParameterSetName = 'Object')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Object', ValueFromPipeline = $true)]
        [AllowNull()]
        $Object,

        [Parameter(Mandatory = $true, ParameterSetName = 'TypeName')]
        [string]$TypeName,

        [Parameter(Mandatory = $false)]
        [switch]$UseRuntimeOnly
    )

    $MyTag = '[Get-TypeMemoryOverhead]'

    try {
        # Determine type name
        $actualTypeName = $null

        if ($PSCmdlet.ParameterSetName -eq 'TypeName') {
            $actualTypeName = $TypeName
        } elseif ($null -eq $Object) {
            # Special case: null object
            return @{
                TypeName = 'null'
                BaseSize = 8  # Null reference is still 8 bytes
                PerItemOverhead = 0
                IsFixedSize = $true
                PlatformDependent = $true
                Notes = 'Null reference'
                Source = 'Hardcoded'
            }
        } else {
            $actualTypeName = $Object.GetType().FullName
        }

        Write-Verbose "$MyTag Analyzing type: $actualTypeName"

        # Check cache first (unless UseRuntimeOnly)
        if (-not $UseRuntimeOnly) {
            $cachedOverhead = Get-CachedTypeOverhead -TypeName $actualTypeName

            if ($cachedOverhead) {
                Write-Verbose "$MyTag Found in cache: $actualTypeName (Source: $($cachedOverhead.Source))"
                return $cachedOverhead
            }
        }

        # Cache miss - perform runtime measurement
        Write-Verbose "$MyTag Performing runtime measurement for: $actualTypeName"
        $runtimeOverhead = Measure-TypeOverheadRuntime -Object $Object -TypeName $actualTypeName

        # Cache the result for future use
        Add-RuntimeTypeOverhead -TypeName $actualTypeName -TypeOverhead $runtimeOverhead

        return $runtimeOverhead

    } catch {
        Write-Error "$MyTag Failed to calculate overhead for type: $_"

        # Return safe default
        return @{
            TypeName = $actualTypeName ?? 'Unknown'
            BaseSize = 24  # Minimum object overhead
            PerItemOverhead = 0
            IsFixedSize = $false
            PlatformDependent = $true
            Notes = "Error during measurement: $($_.Exception.Message)"
            Source = 'Error'
        }
    }
}

function Measure-TypeOverheadRuntime {
    <#
    .SYNOPSIS
        Measures type overhead using runtime reflection

    .DESCRIPTION
        Uses reflection and heuristics to estimate object size when
        CSV data is not available. This is approximate but useful for
        unknown types.

    .PARAMETER Object
        Object instance to measure

    .PARAMETER TypeName
        Type name (for when object is $null)

    .OUTPUTS
        Hashtable with type overhead data
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Object,

        [string]$TypeName
    )

    $MyTag = '[Measure-TypeOverheadRuntime]'

    try {
        # Get type object
        $type = if ($Object) {
            $Object.GetType()
        } elseif ($TypeName) {
            [Type]::GetType($TypeName)
        } else {
            throw "Must provide either Object or TypeName"
        }

        if (-not $type) {
            throw "Could not resolve type: $TypeName"
        }

        # Base overhead calculation
        $baseSize = 0
        $perItemOverhead = 0
        $isFixedSize = $false
        $notes = "Runtime measurement"

        # Value types vs reference types
        if ($type.IsValueType) {
            # Value types: size is the struct size (no heap overhead when boxed inline)
            $baseSize = [System.Runtime.InteropServices.Marshal]::SizeOf($type)
            $isFixedSize = $true
            $notes = "Value type - inline storage"

        } else {
            # Reference types: base object overhead + fields

            # Object header overhead (sync block + method table pointer)
            # 64-bit: 8 bytes (sync block index) + 8 bytes (method table) = 16 bytes minimum
            # But CLR adds padding, so typical minimum is 24 bytes
            $baseSize = 24

            # Try to estimate field sizes
            $fields = $type.GetFields(
                [System.Reflection.BindingFlags]::Instance -bor
                [System.Reflection.BindingFlags]::Public -bor
                [System.Reflection.BindingFlags]::NonPublic
            )

            foreach ($field in $fields) {
                $fieldType = $field.FieldType

                if ($fieldType.IsValueType) {
                    try {
                        $baseSize += [System.Runtime.InteropServices.Marshal]::SizeOf($fieldType)
                    } catch {
                        $baseSize += 8  # Default estimate
                    }
                } else {
                    # Reference type field: just a pointer
                    $baseSize += 8  # 64-bit pointer
                }
            }

            # Check for collection types
            if ($Object -is [System.Collections.ICollection]) {
                # Collections have per-item overhead
                $isFixedSize = $false

                # Estimate per-item overhead based on collection type
                if ($type.IsGenericType) {
                    $genericDef = $type.GetGenericTypeDefinition().FullName

                    switch -Wildcard ($genericDef) {
                        'System.Collections.Generic.List*' {
                            $perItemOverhead = 8  # Array of references
                            $notes = "Generic List - array-backed"
                        }
                        'System.Collections.Generic.Dictionary*' {
                            $perItemOverhead = 24  # Entry struct (hash + key ref + value ref + next)
                            $notes = "Generic Dictionary - hash table"
                        }
                        'System.Collections.Concurrent.ConcurrentQueue*' {
                            $perItemOverhead = 16  # Segment + node overhead
                            $notes = "ConcurrentQueue - segment-based"
                        }
                        'System.Collections.Concurrent.ConcurrentDictionary*' {
                            $perItemOverhead = 32  # Node + lock overhead
                            $notes = "ConcurrentDictionary - lock-striped"
                        }
                        default {
                            $perItemOverhead = 8  # Default reference
                            $notes = "Generic collection - estimated"
                        }
                    }
                } else {
                    # Non-generic collections
                    switch ($type.FullName) {
                        'System.Collections.Hashtable' {
                            $perItemOverhead = 16  # Bucket entry
                            $notes = "Hashtable - bucket array"
                        }
                        'System.Collections.ArrayList' {
                            $perItemOverhead = 8  # Array of references
                            $notes = "ArrayList - array-backed"
                        }
                        'System.Array' {
                            $perItemOverhead = 8  # Array element
                            $notes = "Array - reference elements"
                        }
                        default {
                            $perItemOverhead = 8  # Default
                            $notes = "Collection - estimated"
                        }
                    }
                }
            } else {
                $isFixedSize = $true
                $notes = "Reference type - fixed size"
            }

            # Round up to 8-byte alignment (CLR requirement)
            if ($baseSize % 8 -ne 0) {
                $baseSize = [Math]::Ceiling($baseSize / 8) * 8
            }
        }

        return @{
            TypeName = $type.FullName
            BaseSize = $baseSize
            PerItemOverhead = $perItemOverhead
            IsFixedSize = $isFixedSize
            PlatformDependent = $true  # Runtime measurements are always platform-dependent
            Notes = $notes
            Source = 'Runtime'
        }

    } catch {
        Write-Warning "$MyTag Runtime measurement failed: $_"

        # Return conservative estimate
        return @{
            TypeName = $TypeName ?? 'Unknown'
            BaseSize = 64  # Conservative default
            PerItemOverhead = 8
            IsFixedSize = $false
            PlatformDependent = $true
            Notes = "Measurement error - using conservative estimate"
            Source = 'Runtime'
        }
    }
}

function Get-ObjectEstimatedSize {
    <#
    .SYNOPSIS
        Calculates estimated total size for an object including content

    .DESCRIPTION
        Combines type overhead with actual object content size.
        For collections, multiplies per-item overhead by count.
        For strings, adds character data size.

    .PARAMETER Object
        Object to measure

    .EXAMPLE
        $size = Get-ObjectEstimatedSize -Object $myHashtable

    .OUTPUTS
        Returns hashtable with:
        - BaseSize: Type overhead
        - ContentSize: Size of actual data
        - TotalSize: BaseSize + ContentSize
        - ItemCount: For collections
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        $Object
    )

    $MyTag = '[Get-ObjectEstimatedSize]'

    try {
        if ($null -eq $Object) {
            return @{
                BaseSize = 8
                ContentSize = 0
                TotalSize = 8
                ItemCount = 0
            }
        }

        # Get type overhead
        $overhead = Get-TypeMemoryOverhead -Object $Object

        $baseSize = $overhead.BaseSize
        $contentSize = 0
        $itemCount = 0

        # Calculate content size based on type
        $type = $Object.GetType()

        # String: add character data
        if ($type -eq [string]) {
            $contentSize = $Object.Length * 2  # UTF-16 (2 bytes per char)
            Write-Verbose "$MyTag String length: $($Object.Length) chars = $contentSize bytes"
        }
        # Collection: add per-item overhead
        elseif ($Object -is [System.Collections.ICollection]) {
            $itemCount = $Object.Count
            $contentSize = $itemCount * $overhead.PerItemOverhead
            Write-Verbose "$MyTag Collection count: $itemCount items = $contentSize bytes overhead"
        }
        # Array: special handling
        elseif ($type.IsArray) {
            $itemCount = $Object.Length
            $contentSize = $itemCount * $overhead.PerItemOverhead
            Write-Verbose "$MyTag Array length: $itemCount items = $contentSize bytes"
        }

        $totalSize = $baseSize + $contentSize

        return @{
            BaseSize = $baseSize
            ContentSize = $contentSize
            TotalSize = $totalSize
            ItemCount = $itemCount
            TypeOverhead = $overhead
        }

    } catch {
        Write-Error "$MyTag Failed to estimate size: $_"

        return @{
            BaseSize = 0
            ContentSize = 0
            TotalSize = 0
            ItemCount = 0
            Error = $_.Exception.Message
        }
    }
}
