function Get-MemoryConsumption {
    <#
    .SYNOPSIS
        Orchestrates comprehensive memory analysis with streaming results

    .DESCRIPTION
        Main entry point for memory consumption analysis. Coordinates:
        - Variable path resolution (supports dotted paths like "PSWebServer.Apps")
        - Object graph traversal with reference tracking
        - Circular reference detection
        - Assembly memory enumeration (optional)
        - Streaming NDJSON output for real-time browser updates
        - Timeout protection to prevent long-running analysis

    .PARAMETER VariablePath
        Path to variable(s) to analyze. Supports:
        - Empty/"" = Analyze all global variables
        - "PSWebServer" = Analyze specific variable
        - "PSWebServer.Apps" = Analyze nested property
        - Multiple paths via array

    .PARAMETER Depth
        Maximum recursion depth (1-20, default: 5)

    .PARAMETER MinSize
        Minimum object size in bytes to include in results (default: 0)

    .PARAMETER IncludeAssemblies
        Include loaded assembly/DLL memory analysis

    .PARAMETER StreamCallback
        Scriptblock to receive incremental NDJSON messages
        Signature: param($Message) where $Message is hashtable

    .PARAMETER TimeoutSeconds
        Maximum analysis time in seconds (default: 60, max: 300)

    .PARAMETER ExcludePatterns
        Array of variable name patterns to exclude (supports wildcards)

    .PARAMETER IncludeMethodOverhead
        Calculate method ownership overhead (slower but more accurate)

    .EXAMPLE
        # Analyze all global variables with streaming
        $callback = { param($m) Write-Host ($m | ConvertTo-Json -Compress) }
        Get-MemoryConsumption -StreamCallback $callback

    .EXAMPLE
        # Analyze specific variable path
        Get-MemoryConsumption -VariablePath "PSWebServer.Apps" -Depth 5 -MinSize 1024

    .EXAMPLE
        # Full analysis with assemblies
        Get-MemoryConsumption -VariablePath "PSWebServer" -IncludeAssemblies -TimeoutSeconds 120

    .OUTPUTS
        Returns summary hashtable with:
        - TotalObjects: Number of unique objects analyzed
        - TotalSize: Total memory consumption in bytes
        - TotalReferences: Total reference count
        - CircularReferences: Count of circular references detected
        - Duration: Analysis duration in seconds
        - TimedOut: Whether analysis hit timeout
        - Variables: Array of variable analysis results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string[]]$VariablePath = @(""),

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$Depth = 5,

        [Parameter(Mandatory = $false)]
        [int]$MinSize = 0,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeAssemblies,

        [Parameter(Mandatory = $false)]
        [scriptblock]$StreamCallback,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 300)]
        [int]$TimeoutSeconds = 60,

        [Parameter(Mandatory = $false)]
        [string[]]$ExcludePatterns = @(
            'Host', 'ExecutionContext', 'PSBoundParameters',
            'Error', 'StackTrace', 'MyInvocation', 'PSScriptRoot', 'PSCommandPath',
            'true', 'false', 'null', 'args', 'input'
        ),

        [Parameter(Mandatory = $false)]
        [switch]$IncludeMethodOverhead
    )

    $MyTag = '[Get-MemoryConsumption]'

    # Analysis state
    $startTime = Get-Date
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $timeoutMs = $TimeoutSeconds * 1000

    # Tracking structures (shared across all variable analyses)
    $seenObjects = @{}
    $parentChain = [System.Collections.Generic.Stack[int]]::new()

    # Results
    $summary = @{
        StartTime = $startTime
        EndTime = $null
        Duration = 0
        TotalVariables = 0
        TotalObjects = 0
        TotalSize = 0
        TotalReferences = 0
        CircularReferences = 0
        TimedOut = $false
        Variables = @()
        Errors = @()
    }

    try {
        Write-Verbose "$MyTag Starting memory analysis..."
        Write-Verbose "$MyTag   Depth: $Depth, MinSize: $MinSize bytes, Timeout: $TimeoutSeconds seconds"

        # Stream start message
        if ($StreamCallback) {
            & $StreamCallback -Message @{
                type = 'start'
                timestamp = $startTime.ToString('o')
                config = @{
                    depth = $Depth
                    minSize = $MinSize
                    timeout = $TimeoutSeconds
                    includeAssemblies = $IncludeAssemblies.IsPresent
                }
            }
        }

        # Resolve variable paths
        $variablesToAnalyze = @()

        foreach ($path in $VariablePath) {
            if ([string]::IsNullOrWhiteSpace($path)) {
                # Empty path = analyze all global variables
                Write-Verbose "$MyTag Enumerating all global variables..."

                $globalVars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
                    Where-Object {
                        $varName = $_.Name

                        # Apply exclude patterns
                        $excluded = $false
                        foreach ($pattern in $ExcludePatterns) {
                            if ($varName -like $pattern) {
                                $excluded = $true
                                break
                            }
                        }

                        -not $excluded
                    }

                foreach ($var in $globalVars) {
                    $variablesToAnalyze += @{
                        Name = $var.Name
                        Path = $var.Name
                        Value = $var.Value
                    }
                }

            } else {
                # Specific path - resolve it
                Write-Verbose "$MyTag Resolving path: $path"

                try {
                    # Split path into segments (e.g., "PSWebServer.Apps" -> ["PSWebServer", "Apps"])
                    $segments = $path -split '\.'

                    # Start with global variable
                    $currentValue = Get-Variable -Name $segments[0] -Scope Global -ValueOnly -ErrorAction Stop

                    # Traverse nested properties
                    for ($i = 1; $i -lt $segments.Count; $i++) {
                        $segment = $segments[$i]

                        if ($currentValue -is [hashtable] -or $currentValue -is [System.Collections.IDictionary]) {
                            $currentValue = $currentValue[$segment]
                        } else {
                            $currentValue = $currentValue.$segment
                        }

                        if ($null -eq $currentValue) {
                            throw "Path segment '$segment' resolved to null"
                        }
                    }

                    $variablesToAnalyze += @{
                        Name = $path
                        Path = $path
                        Value = $currentValue
                    }

                } catch {
                    $errorMsg = "Failed to resolve path '$path': $($_.Exception.Message)"
                    Write-Warning "$MyTag $errorMsg"

                    $summary.Errors += $errorMsg

                    if ($StreamCallback) {
                        & $StreamCallback -Message @{
                            type = 'error'
                            path = $path
                            message = $errorMsg
                            timestamp = (Get-Date).ToString('o')
                        }
                    }
                }
            }
        }

        $summary.TotalVariables = $variablesToAnalyze.Count

        Write-Verbose "$MyTag Analyzing $($variablesToAnalyze.Count) variables..."

        # Analyze each variable
        $varNumber = 0

        foreach ($varInfo in $variablesToAnalyze) {
            $varNumber++

            # Check timeout
            if ($stopwatch.ElapsedMilliseconds -gt $timeoutMs) {
                Write-Warning "$MyTag Timeout reached after $TimeoutSeconds seconds"
                $summary.TimedOut = $true

                if ($StreamCallback) {
                    & $StreamCallback -Message @{
                        type = 'timeout'
                        message = "Analysis timeout after $TimeoutSeconds seconds"
                        variablesAnalyzed = $varNumber - 1
                        variablesRemaining = $variablesToAnalyze.Count - $varNumber + 1
                        timestamp = (Get-Date).ToString('o')
                    }
                }

                break
            }

            Write-Verbose "$MyTag [$varNumber/$($variablesToAnalyze.Count)] Analyzing: $($varInfo.Path)"

            # Stream progress
            if ($StreamCallback) {
                & $StreamCallback -Message @{
                    type = 'progress'
                    variable = $varInfo.Path
                    current = $varNumber
                    total = $variablesToAnalyze.Count
                    percentComplete = [math]::Round(($varNumber / $variablesToAnalyze.Count) * 100, 1)
                    timestamp = (Get-Date).ToString('o')
                }
            }

            try {
                # Measure object graph
                $graphResult = Measure-ObjectGraph `
                    -RootObject $varInfo.Value `
                    -Path $varInfo.Path `
                    -SeenObjects $seenObjects `
                    -ParentChain $parentChain `
                    -MaxDepth $Depth `
                    -CurrentDepth 0 `
                    -StreamCallback $StreamCallback `
                    -IncludeMethodOverhead:$IncludeMethodOverhead

                # Apply size filter
                if ($graphResult.TotalSize -ge $MinSize) {
                    $summary.Variables += $graphResult

                    # Stream variable result
                    if ($StreamCallback) {
                        & $StreamCallback -Message @{
                            type = 'variable'
                            name = $varInfo.Name
                            path = $varInfo.Path
                            result = $graphResult
                            timestamp = (Get-Date).ToString('o')
                        }
                    }
                }

            } catch {
                $errorMsg = "Error analyzing $($varInfo.Path): $($_.Exception.Message)"
                Write-Warning "$MyTag $errorMsg"
                $summary.Errors += $errorMsg
            }
        }

        # Assembly analysis (if requested)
        if ($IncludeAssemblies -and -not $summary.TimedOut) {
            Write-Verbose "$MyTag Analyzing loaded assemblies..."

            if ($StreamCallback) {
                & $StreamCallback -Message @{
                    type = 'assemblies_start'
                    timestamp = (Get-Date).ToString('o')
                }
            }

            try {
                # Use full Get-AssemblyMemory implementation
                $assemblyStreamCallback = {
                    param($AssemblyInfo)

                    # Forward assembly info to main stream if callback exists
                    if ($StreamCallback) {
                        & $StreamCallback -Message @{
                            type = 'assembly'
                            assembly = $AssemblyInfo
                            timestamp = (Get-Date).ToString('o')
                        }
                    }
                }

                $assemblyResults = Get-AssemblyMemory `
                    -IncludeGAC:$false `
                    -IncludeDynamic:$true `
                    -MinimumSize 0 `
                    -IncludeTypeDetails:$IncludeMethodOverhead `
                    -SortBy 'Size' `
                    -StreamCallback $assemblyStreamCallback `
                    -ErrorAction Continue

                $summary.Assemblies = $assemblyResults
                $summary.AssemblyCount = $assemblyResults.Count
                $summary.TotalAssemblySize = ($assemblyResults | Measure-Object -Property EstimatedSize -Sum).Sum ?? 0

                # Generate assembly summary
                if ($assemblyResults.Count -gt 0) {
                    $assemblySummary = Get-AssemblyMemorySummary -AssemblyData $assemblyResults
                    $summary.AssemblySummary = $assemblySummary
                }

                # Stream complete assembly list
                if ($StreamCallback) {
                    & $StreamCallback -Message @{
                        type = 'assemblies_complete'
                        count = $assemblyResults.Count
                        totalSize = $summary.TotalAssemblySize
                        summary = $summary.AssemblySummary
                        timestamp = (Get-Date).ToString('o')
                    }
                }

            } catch {
                Write-Warning "$MyTag Assembly analysis failed: $_"
                $summary.Errors += "Assembly analysis failed: $($_.Exception.Message)"
            }
        }

        # Calculate summary statistics
        $summary.TotalObjects = $seenObjects.Count
        $summary.TotalSize = ($summary.Variables | Measure-Object -Property TotalSize -Sum).Sum ?? 0

        # Count references and circular refs
        $totalRefs = 0
        $circularRefs = 0

        foreach ($objId in $seenObjects.Keys) {
            $totalRefs += $seenObjects[$objId].RefCount
        }

        function Count-CircularRefs {
            param($Node)

            $count = 0

            if ($Node.IsCircular) {
                $count++
            }

            foreach ($child in $Node.Children) {
                $count += Count-CircularRefs -Node $child
            }

            return $count
        }

        foreach ($varResult in $summary.Variables) {
            $circularRefs += Count-CircularRefs -Node $varResult
        }

        $summary.TotalReferences = $totalRefs
        $summary.CircularReferences = $circularRefs

    } catch {
        Write-Error "$MyTag Critical error during analysis: $_"
        $summary.Errors += "Critical error: $($_.Exception.Message)"

    } finally {
        # Finalize
        $stopwatch.Stop()
        $summary.EndTime = Get-Date
        $summary.Duration = $stopwatch.Elapsed.TotalSeconds

        Write-Verbose "$MyTag Analysis complete: $($summary.TotalVariables) variables, $($summary.TotalObjects) objects, $($summary.TotalSize) bytes"
        Write-Verbose "$MyTag   Duration: $([math]::Round($summary.Duration, 2))s, References: $($summary.TotalReferences), Circular: $($summary.CircularReferences)"

        # Stream completion
        if ($StreamCallback) {
            & $StreamCallback -Message @{
                type = 'complete'
                summary = $summary
                timestamp = $summary.EndTime.ToString('o')
            }
        }
    }

    return $summary
}
