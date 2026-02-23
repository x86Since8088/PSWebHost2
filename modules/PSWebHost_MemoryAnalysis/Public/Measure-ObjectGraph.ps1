function Measure-ObjectGraph {
    <#
    .SYNOPSIS
        Recursively measures memory consumption of an object graph with reference tracking

    .DESCRIPTION
        Performs deep traversal of an object graph while tracking object identity to:
        - Count each unique object exactly once
        - Track reference overhead separately
        - Detect circular references (parent-child cycles)
        - Measure method ownership (declared vs inherited)
        - Support incremental streaming of results

    .PARAMETER RootObject
        The object to analyze (can be any PowerShell object)

    .PARAMETER Path
        Current path in object graph (e.g., "PSWebServer.Apps.FileExplorer")

    .PARAMETER SeenObjects
        Hashtable tracking visited objects by GetHashCode
        Key: object ID, Value: metadata (path, refcount, size)

    .PARAMETER ParentChain
        Stack tracking parent object IDs for circular reference detection

    .PARAMETER MaxDepth
        Maximum recursion depth (default: 10, max: 20)

    .PARAMETER CurrentDepth
        Current depth in traversal (internal use)

    .PARAMETER StreamCallback
        Optional scriptblock to receive incremental results
        Signature: param($Result)

    .PARAMETER IncludeMethodOverhead
        Calculate method ownership overhead (only at shallow depths)

    .PARAMETER MaxEnumeration
        Maximum items to enumerate in collections (default: 1000)

    .EXAMPLE
        $seen = @{}
        $chain = [System.Collections.Generic.Stack[int]]::new()
        $result = Measure-ObjectGraph -RootObject $Global:PSWebServer -Path "PSWebServer" `
                                       -SeenObjects $seen -ParentChain $chain -MaxDepth 5

    .EXAMPLE
        # With streaming callback
        $callback = { param($r) Write-Host "Found: $($r.Path) = $($r.TotalSize) bytes" }
        Measure-ObjectGraph -RootObject $obj -StreamCallback $callback

    .OUTPUTS
        Returns hashtable with:
        - Path: Object path in graph
        - Type: Full type name
        - ObjectId: GetHashCode value
        - IsReference: True if object already seen
        - IsCircular: True if circular reference detected
        - BaseSize: Type overhead
        - ContentSize: Collection/string content size
        - MethodOverhead: Declared method overhead
        - ReferenceOverhead: Pointer size (8 bytes on 64-bit)
        - TotalSize: Sum of all sizes
        - RefCount: Number of references to this object
        - Children: Array of child object results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        $RootObject,

        [Parameter(Mandatory = $false)]
        [string]$Path = 'Root',

        [Parameter(Mandatory = $false)]
        [hashtable]$SeenObjects,

        [Parameter(Mandatory = $false)]
        [System.Collections.Generic.Stack[int]]$ParentChain,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$MaxDepth = 10,

        [Parameter(Mandatory = $false)]
        [int]$CurrentDepth = 0,

        [Parameter(Mandatory = $false)]
        [scriptblock]$StreamCallback,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMethodOverhead,

        [Parameter(Mandatory = $false)]
        [int]$MaxEnumeration = 1000
    )

    $MyTag = '[Measure-ObjectGraph]'

    # Initialize tracking structures if not provided
    if (-not $SeenObjects) {
        $SeenObjects = @{}
    }

    if (-not $ParentChain) {
        $ParentChain = [System.Collections.Generic.Stack[int]]::new()
    }

    try {
        # Handle null objects
        if ($null -eq $RootObject) {
            return @{
                Path = $Path
                Type = 'null'
                ObjectId = 0
                IsReference = $false
                IsCircular = $false
                BaseSize = 8  # Null reference size
                ContentSize = 0
                MethodOverhead = 0
                ReferenceOverhead = 0
                TotalSize = 8
                RefCount = 0
                Children = @()
            }
        }

        # Get object identity (works for ALL objects)
        $objectId = [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($RootObject)

        Write-Verbose "$MyTag [$CurrentDepth] Analyzing: $Path (ID: $objectId)"

        # Check for circular reference (parent-child cycle)
        if ($ParentChain.Contains($objectId)) {
            Write-Verbose "$MyTag CIRCULAR REFERENCE DETECTED: $Path"

            $circularPath = ($ParentChain.ToArray() | ForEach-Object { $_ }) -join ' -> '

            return @{
                Path = $Path
                Type = $RootObject.GetType().FullName
                ObjectId = $objectId
                IsReference = $true
                IsCircular = $true
                BaseSize = 0
                ContentSize = 0
                MethodOverhead = 0
                ReferenceOverhead = 8  # Still counts as a reference
                TotalSize = 8
                RefCount = 0
                CircularPath = $circularPath
                Children = @()
            }
        }

        # Check if already seen (not circular, just multiple references)
        if ($SeenObjects.ContainsKey($objectId)) {
            Write-Verbose "$MyTag Already seen: $Path (original: $($SeenObjects[$objectId].Path))"

            # Increment reference count
            $SeenObjects[$objectId].RefCount++

            return @{
                Path = $Path
                Type = $RootObject.GetType().FullName
                ObjectId = $objectId
                IsReference = $true
                IsCircular = $false
                BaseSize = 0  # Already counted at original location
                ContentSize = 0
                MethodOverhead = 0
                ReferenceOverhead = 8  # This reference pointer
                TotalSize = 8
                RefCount = $SeenObjects[$objectId].RefCount
                OriginalPath = $SeenObjects[$objectId].Path
                Children = @()
            }
        }

        # First encounter - mark as seen
        $SeenObjects[$objectId] = @{
            Object = $RootObject
            Path = $Path
            RefCount = 1
            Depth = $CurrentDepth
        }

        # Add to parent chain for circular detection
        $ParentChain.Push($objectId)

        try {
            # Get type information
            $type = $RootObject.GetType()
            $typeName = $type.FullName

            # Get type overhead
            $typeOverhead = Get-TypeMemoryOverhead -Object $RootObject

            # Initialize result
            $result = @{
                Path = $Path
                Type = $typeName
                ObjectId = $objectId
                IsReference = $false
                IsCircular = $false
                BaseSize = $typeOverhead.BaseSize
                ContentSize = 0
                MethodOverhead = 0
                ReferenceOverhead = 0
                TotalSize = 0
                RefCount = 1
                Children = @()
            }

            # Calculate content size based on type
            $contentSize = 0
            $itemCount = 0

            # String: character data
            if ($type -eq [string]) {
                $contentSize = $RootObject.Length * $typeOverhead.PerItemOverhead
                $result.ItemCount = $RootObject.Length
                Write-Verbose "$MyTag String: $($RootObject.Length) chars = $contentSize bytes"
            }
            # Hashtable: special handling for key-value pairs
            elseif ($RootObject -is [System.Collections.Hashtable] -or $RootObject -is [System.Collections.IDictionary]) {
                $itemCount = $RootObject.Count
                $contentSize = $itemCount * $typeOverhead.PerItemOverhead
                $result.ItemCount = $itemCount
                Write-Verbose "$MyTag Hashtable: $itemCount entries = $contentSize bytes overhead"
            }
            # Generic collections
            elseif ($RootObject -is [System.Collections.ICollection]) {
                $itemCount = $RootObject.Count
                $contentSize = $itemCount * $typeOverhead.PerItemOverhead
                $result.ItemCount = $itemCount
                Write-Verbose "$MyTag Collection: $itemCount items = $contentSize bytes overhead"
            }
            # Arrays
            elseif ($type.IsArray) {
                $itemCount = $RootObject.Length
                $contentSize = $itemCount * $typeOverhead.PerItemOverhead
                $result.ItemCount = $itemCount
                Write-Verbose "$MyTag Array: $itemCount elements = $contentSize bytes"
            }

            $result.ContentSize = $contentSize

            # Method ownership analysis (only at shallow depths to avoid overhead)
            if ($IncludeMethodOverhead -and $CurrentDepth -le 2) {
                try {
                    $declaredMethods = $type.GetMethods(
                        [System.Reflection.BindingFlags]::Instance -bor
                        [System.Reflection.BindingFlags]::Public -bor
                        [System.Reflection.BindingFlags]::DeclaredOnly
                    )

                    $methodOverhead = $declaredMethods.Count * 8  # 8 bytes per method pointer
                    $result.MethodOverhead = $methodOverhead
                    $result.DeclaredMethodCount = $declaredMethods.Count

                    Write-Verbose "$MyTag Methods: $($declaredMethods.Count) declared = $methodOverhead bytes"
                } catch {
                    Write-Verbose "$MyTag Method analysis failed: $_"
                }
            }

            # Recursively traverse children (if not at max depth)
            if ($CurrentDepth -lt $MaxDepth) {
                $children = @()

                # Traverse based on type
                if ($RootObject -is [System.Collections.Hashtable] -or $RootObject -is [System.Collections.IDictionary]) {
                    # Hashtable: traverse keys and values
                    $enumCount = 0
                    foreach ($key in $RootObject.Keys) {
                        if (++$enumCount -gt $MaxEnumeration) {
                            Write-Verbose "$MyTag Hashtable enumeration truncated at $MaxEnumeration items"
                            $result.Truncated = $true
                            break
                        }

                        $value = $RootObject[$key]

                        # Traverse key
                        if ($null -ne $key -and -not ($key -is [System.ValueType])) {
                            $childPath = "$Path.Keys['$key']"
                            $childResult = Measure-ObjectGraph `
                                -RootObject $key `
                                -Path $childPath `
                                -SeenObjects $SeenObjects `
                                -ParentChain $ParentChain `
                                -MaxDepth $MaxDepth `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -StreamCallback $StreamCallback `
                                -IncludeMethodOverhead:$IncludeMethodOverhead `
                                -MaxEnumeration $MaxEnumeration

                            $children += $childResult
                        }

                        # Traverse value
                        if ($null -ne $value -and -not ($value -is [System.ValueType])) {
                            $childPath = "$Path['$key']"
                            $childResult = Measure-ObjectGraph `
                                -RootObject $value `
                                -Path $childPath `
                                -SeenObjects $SeenObjects `
                                -ParentChain $ParentChain `
                                -MaxDepth $MaxDepth `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -StreamCallback $StreamCallback `
                                -IncludeMethodOverhead:$IncludeMethodOverhead `
                                -MaxEnumeration $MaxEnumeration

                            $children += $childResult
                        }
                    }
                }
                elseif ($RootObject -is [System.Collections.IEnumerable] -and $type -ne [string]) {
                    # Collections/Arrays: traverse items
                    $enumCount = 0
                    $index = 0

                    foreach ($item in $RootObject) {
                        if (++$enumCount -gt $MaxEnumeration) {
                            Write-Verbose "$MyTag Collection enumeration truncated at $MaxEnumeration items"
                            $result.Truncated = $true
                            break
                        }

                        if ($null -ne $item -and -not ($item -is [System.ValueType])) {
                            $childPath = "$Path[$index]"
                            $childResult = Measure-ObjectGraph `
                                -RootObject $item `
                                -Path $childPath `
                                -SeenObjects $SeenObjects `
                                -ParentChain $ParentChain `
                                -MaxDepth $MaxDepth `
                                -CurrentDepth ($CurrentDepth + 1) `
                                -StreamCallback $StreamCallback `
                                -IncludeMethodOverhead:$IncludeMethodOverhead `
                                -MaxEnumeration $MaxEnumeration

                            $children += $childResult
                        }

                        $index++
                    }
                }
                else {
                    # Regular objects: traverse properties
                    $properties = $type.GetProperties(
                        [System.Reflection.BindingFlags]::Instance -bor
                        [System.Reflection.BindingFlags]::Public
                    )

                    foreach ($prop in $properties) {
                        # Skip properties that are likely to cause issues
                        if ($prop.Name -in @('SyncRoot', 'Host', 'Runspace', 'Context')) {
                            continue
                        }

                        try {
                            $propValue = $prop.GetValue($RootObject)

                            if ($null -ne $propValue -and -not ($propValue -is [System.ValueType])) {
                                $childPath = "$Path.$($prop.Name)"
                                $childResult = Measure-ObjectGraph `
                                    -RootObject $propValue `
                                    -Path $childPath `
                                    -SeenObjects $SeenObjects `
                                    -ParentChain $ParentChain `
                                    -MaxDepth $MaxDepth `
                                    -CurrentDepth ($CurrentDepth + 1) `
                                    -StreamCallback $StreamCallback `
                                    -IncludeMethodOverhead:$IncludeMethodOverhead `
                                    -MaxEnumeration $MaxEnumeration

                                $children += $childResult
                            }
                        } catch {
                            # Property access failed - skip it
                            Write-Verbose "$MyTag Property $($prop.Name) access failed: $_"
                        }
                    }
                }

                $result.Children = $children

                # Calculate total size including children
                $childrenTotalSize = ($children | Measure-Object -Property TotalSize -Sum).Sum ?? 0
                $result.ChildrenTotalSize = $childrenTotalSize
            } else {
                Write-Verbose "$MyTag Max depth reached at: $Path"
                $result.MaxDepthReached = $true
            }

            # Calculate total size
            $result.TotalSize = $result.BaseSize + $result.ContentSize + $result.MethodOverhead

            # Stream result if callback provided
            if ($StreamCallback) {
                try {
                    & $StreamCallback -Result $result
                } catch {
                    Write-Warning "$MyTag Stream callback failed: $_"
                }
            }

            return $result

        } finally {
            # Remove from parent chain
            $ParentChain.Pop() | Out-Null
        }

    } catch {
        Write-Error "$MyTag Failed to measure object at $Path : $_"

        return @{
            Path = $Path
            Type = 'Error'
            ObjectId = $objectId ?? 0
            IsReference = $false
            IsCircular = $false
            BaseSize = 0
            ContentSize = 0
            MethodOverhead = 0
            ReferenceOverhead = 0
            TotalSize = 0
            RefCount = 0
            Children = @()
            Error = $_.Exception.Message
        }
    }
}
