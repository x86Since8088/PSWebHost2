param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Import required modules
    Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Formatters/PSWebHost_Formatters.psd1") -DisableNameChecking
    Import-Module powershell-yaml -DisableNameChecking

    # Get format from query parameter (default: list)
    # Formats: list (names/types only), table (Out-String), detailed (full inspection with YAML), tree (hierarchical browsing), memory (advanced memory analysis)
    $format = $Request.QueryString['format']
    if (-not $format) { $format = 'list' }

    # --- FORMAT: memory (advanced memory analysis with streaming NDJSON) ---
    if ($format -eq 'memory') {
        # Import memory analysis module
        Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_MemoryAnalysis/PSWebHost_MemoryAnalysis.psd1") -DisableNameChecking

        # Parse query parameters
        $varPath = $Request.QueryString['path']
        $depth = [int]($Request.QueryString['depth'] ?? 5)
        $minSize = [int]($Request.QueryString['minSize'] ?? 0)
        $includeAssemblies = $Request.QueryString['includeAssemblies'] -eq 'true'
        $includeMethodOverhead = $Request.QueryString['includeMethodOverhead'] -eq 'true'
        $timeoutSeconds = [int]($Request.QueryString['timeout'] ?? 60)

        # Validate parameters
        if ($depth -lt 1) { $depth = 1 }
        if ($depth -gt 20) { $depth = 20 }
        if ($timeoutSeconds -lt 1) { $timeoutSeconds = 1 }
        if ($timeoutSeconds -gt 300) { $timeoutSeconds = 300 }

        # Set streaming headers (NDJSON format)
        $Response.ContentType = 'application/x-ndjson; charset=utf-8'
        $Response.SendChunked = $true
        $Response.AddHeader('Cache-Control', 'no-store, no-cache, must-revalidate')
        $Response.AddHeader('X-Content-Type-Options', 'nosniff')
        $Response.AddHeader('X-Accel-Buffering', 'no')  # Disable nginx buffering

        # Streaming callback - writes NDJSON to response stream
        $streamCallback = {
            param($Message)

            try {
                $json = $Message | ConvertTo-Json -Compress -Depth 10
                $line = "$json`n"
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($line)
                $Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $Response.OutputStream.Flush()
            } catch {
                Write-Warning "[MemoryAnalysis] Stream write failed: $_"
            }
        }

        # Execute analysis with streaming
        try {
            # Build variable path array
            $pathArray = if ([string]::IsNullOrWhiteSpace($varPath)) {
                @("")  # Empty = analyze all globals
            } else {
                @($varPath)
            }

            # Run analysis
            Get-MemoryConsumption `
                -VariablePath $pathArray `
                -Depth $depth `
                -MinSize $minSize `
                -IncludeAssemblies:$includeAssemblies `
                -StreamCallback $streamCallback `
                -TimeoutSeconds $timeoutSeconds `
                -IncludeMethodOverhead:$includeMethodOverhead `
                -ErrorAction Stop | Out-Null

        } catch {
            # Stream error message
            $errorMsg = @{
                type = 'error'
                message = $_.Exception.Message
                stackTrace = $_.ScriptStackTrace
                timestamp = (Get-Date).ToString('o')
            }

            try {
                & $streamCallback -Message $errorMsg
            } catch {
                Write-Error "[MemoryAnalysis] Failed to send error message: $_"
            }

        } finally {
            # Close response
            try {
                $Response.Close()
            } catch {
                # Response already closed
            }
        }

        return
    }

    # Exclude known problematic variables
    $excludeVars = @('PSWebServer', 'Host', 'ExecutionContext', 'true', 'false', 'null',
                     'Context', 'Request', 'Response', 'SessionData', 'PSBoundParameters',
                     'LogHistory', 'PSWebHostLogQueue', 'PSHostUIQueue', 'Error', 'StackTrace',
                     'MyInvocation', 'PSScriptRoot', 'PSCommandPath')

    # Get variable list
    $allVars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -notin $excludeVars }

    # --- FORMAT: list (lightweight, names and types only) ---
    if ($format -eq 'list') {
        $varList = $allVars | ForEach-Object {
            [pscustomobject]@{
                Name = $_.Name
                Type = if ($null -ne $_.Value) { $_.Value.GetType().FullName } else { 'null' }
            }
        } | Select-Object Name, Type

        $json = $varList | ConvertTo-Json -Depth 2 -Compress
        context_response -Response $Response -String $json -ContentType "application/json"
        return
    }

    # --- FORMAT: table (Out-String representation) ---
    if ($format -eq 'table') {
        $timeout = 30000  # 30 second timeout for table format
        $job = $null

        try {
            # Run in background job with timeout
            $job = Start-Job -ScriptBlock {
            param($ExcludeVars)

            $vars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin $ExcludeVars }

            # Create objects for table display
            $tableData = $vars | ForEach-Object {
                $valueStr = if ($null -eq $_.Value) {
                    'null'
                } elseif ($_.Value -is [string]) {
                    if ($_.Value.Length -gt 100) { $_.Value.Substring(0, 100) + '...' } else { $_.Value }
                } elseif ($_.Value -is [System.Collections.ICollection] -and $_.Value.Count -gt 50) {
                    "[$($_.Value.GetType().Name)] Count: $($_.Value.Count)"
                } else {
                    try {
                        $str = ($_.Value | Out-String -Width 120).Trim()
                        if ($str.Length -gt 200) { $str.Substring(0, 200) + '...' } else { $str }
                    } catch {
                        "[$($_.Value.GetType().Name)]"
                    }
                }

                [pscustomobject]@{
                    Name  = $_.Name
                    Type  = if ($null -ne $_.Value) { $_.Value.GetType().Name } else { 'null' }
                    Value = $valueStr
                }
            }

            $tableData | Format-Table -AutoSize | Out-String -Width 200
            } -ArgumentList (,$excludeVars)

            # Wait for job with timeout
            $completed = Wait-Job -Job $job -Timeout ($timeout / 1000)

            if ($completed) {
                $result = Receive-Job -Job $job
                Remove-Job -Job $job -Force

                $json = @{
                    status = 'success'
                    format = 'table'
                    output = $result
                } | ConvertTo-Json -Compress

                context_response -Response $Response -String $json -ContentType "application/json"
            } else {
                # Timeout - get partial results
                $partial = Receive-Job -Job $job
                Remove-Job -Job $job -Force

                $json = @{
                    status = 'timeout'
                    format = 'table'
                    message = 'Operation timed out after 30 seconds'
                    output = if ($partial) { $partial } else { 'No data received before timeout' }
                } | ConvertTo-Json -Compress

                context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
            }
        } finally {
            # Ensure job is cleaned up even if client disconnects
            if ($null -ne $job -and (Get-Job -Id $job.Id -ErrorAction SilentlyContinue)) {
                try {
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Verbose "Job cleanup failed: $($_.Exception.Message)"
                }
            }
        }
        return
    }

    # --- FORMAT: detailed (full inspection with YAML, job-based with timeout) ---
    if ($format -eq 'detailed') {
        $timeout = 45000  # 45 second timeout for detailed inspection
        $job = $null

        try {
            # Run inspection in background job
            $job = Start-Job -ScriptBlock {
            param($ExcludeVars, $ProjectRoot)

            # Import formatter module in job context
            Import-Module (Join-Path $ProjectRoot "modules/PSWebHost_Formatters/PSWebHost_Formatters.psd1") -DisableNameChecking
            Import-Module powershell-yaml -DisableNameChecking

            $maxValueSize = 50000
            $vars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notin $ExcludeVars }

            $results = @()
            foreach ($V in $vars) {
                if ($null -ne $V.Value) {
                    try {
                        $valueType = $V.Value.GetType().FullName
                        $isSizeableCollection = $V.Value -is [System.Collections.ICollection]

                        # For large collections, provide summary
                        if ($isSizeableCollection -and $V.Value.Count -gt 100) {
                            $yamlValue = "[$valueType] Collection with $($V.Value.Count) items (too large - use PowerShell console to inspect)"
                        }
                        # For synchronized hashtables
                        elseif ($valueType -match 'Hashtable' -and $V.Value.GetType().Name -eq 'Hashtable' -and $V.Value.IsSynchronized) {
                            $yamlValue = "Synchronized Hashtable with $($V.Value.Count) entries (use PowerShell console to inspect)"
                        }
                        # For concurrent collections
                        elseif ($valueType -match 'Concurrent') {
                            $count = if ($V.Value | Get-Member -Name 'Count') { $V.Value.Count } else { 'unknown' }
                            $yamlValue = "[$valueType] Concurrent collection with $count items (thread-safe, use PowerShell console)"
                        }
                        # Normal inspection
                        else {
                            $inspected = Inspect-Object -InputObject $V.Value
                            $yamlValue = $inspected | ConvertTo-Yaml

                            # Truncate if too large
                            if ($yamlValue.Length -gt $maxValueSize) {
                                $truncated = $yamlValue.Substring(0, $maxValueSize)
                                $yamlValue = "$truncated`n... (truncated, original size: $($yamlValue.Length) characters)"
                            }
                        }

                        $results += [pscustomobject]@{
                            Name     = $V.Name
                            Type     = $valueType
                            RawValue = $yamlValue
                        }
                    } catch {
                        # Return error info for variables that fail to process
                        $results += [pscustomobject]@{
                            Name     = $V.Name
                            Type     = "Error"
                            RawValue = "Error processing: $($_.Exception.Message)"
                        }
                    }
                }
            }

            return $results
            } -ArgumentList (,$excludeVars), $Global:PSWebServer.Project_Root.Path

            # Wait with timeout and collect results as they come
            $startTime = Get-Date
            $results = @()

            while (((Get-Date) - $startTime).TotalMilliseconds -lt $timeout) {
                if ($job.State -eq 'Completed') {
                    $results = Receive-Job -Job $job
                    Remove-Job -Job $job -Force
                    $job = $null

                    $json = $results | ConvertTo-Json -Depth 5 -Compress
                    if ($json -in @('null', '')) { $json = '[]' }

                    context_response -Response $Response -String $json -ContentType "application/json"
                    return
                }

                if ($job.State -in @('Failed', 'Stopped')) {
                    $error = Receive-Job -Job $job -ErrorAction SilentlyContinue
                    Remove-Job -Job $job -Force
                    $job = $null

                    $json = @{
                        status = 'error'
                        message = "Job failed: $error"
                    } | ConvertTo-Json -Compress

                    context_response -Response $Response -StatusCode 500 -String $json -ContentType "application/json"
                    return
                }

                Start-Sleep -Milliseconds 100
            }

            # Timeout - attempt to get partial results
            $partial = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            $job = $null

            if ($partial -and $partial.Count -gt 0) {
                $json = @{
                    status = 'timeout'
                    message = 'Operation timed out after 45 seconds, returning partial results'
                    data = $partial
                } | ConvertTo-Json -Depth 5 -Compress
            } else {
                $json = @{
                    status = 'timeout'
                    message = 'Operation timed out with no results'
                    data = @()
                } | ConvertTo-Json -Compress
            }

            context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
        } finally {
            # Ensure job is cleaned up even if client disconnects
            if ($null -ne $job -and (Get-Job -Id $job.Id -ErrorAction SilentlyContinue)) {
                try {
                    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Verbose "Job cleanup failed: $($_.Exception.Message)"
                }
            }
        }
        return
    }

    # --- FORMAT: tree (hierarchical variable browsing with expandable nodes) ---
    if ($format -eq 'tree') {
        $varName = $Request.QueryString['var']

        # If no variable specified, return list of root variables
        if (-not $varName) {
            $varList = $allVars | ForEach-Object {
                $type = if ($null -ne $_.Value) { $_.Value.GetType().FullName } else { 'null' }
                $isExpandable = $false

                # Check if expandable (has properties, keys, or is an array)
                if ($null -ne $_.Value) {
                    if ($_.Value -is [System.Collections.IDictionary]) {
                        $isExpandable = $_.Value.Count -gt 0
                    } elseif ($_.Value -is [System.Collections.IEnumerable] -and $_.Value -isnot [string]) {
                        $isExpandable = @($_.Value).Count -gt 0
                    } elseif ($_.Value.PSObject.Properties.Count -gt 0) {
                        $isExpandable = $true
                    }
                }

                [pscustomobject]@{
                    Name = $_.Name
                    Type = $type
                    IsExpandable = $isExpandable
                    Path = $_.Name
                }
            } | Select-Object Name, Type, IsExpandable, Path

            $json = $varList | ConvertTo-Json -Depth 2 -Compress
            context_response -Response $Response -String $json -ContentType "application/json"
            return
        }

        # If variable specified, inspect its contents
        try {
            # Parse the path (e.g., "PSWebServer.Apps.WebHostMetrics")
            $pathParts = $varName -split '\.'
            $rootVarName = $pathParts[0]

            # Get root variable
            $currentObj = Get-Variable -Name $rootVarName -Scope Global -ErrorAction Stop -ValueOnly

            # Navigate to nested property if path has multiple parts
            for ($i = 1; $i -lt $pathParts.Count; $i++) {
                $propName = $pathParts[$i]

                if ($currentObj -is [System.Collections.IDictionary]) {
                    $currentObj = $currentObj[$propName]
                } elseif ($currentObj -is [System.Collections.IList]) {
                    if ($propName -match '^\[(\d+)\]$') {
                        $index = [int]$Matches[1]
                        $currentObj = $currentObj[$index]
                    } else {
                        throw "Invalid array index: $propName"
                    }
                } else {
                    $currentObj = $currentObj.$propName
                }
            }

            $children = @()

            # If it's a dictionary/hashtable, return keys as children
            if ($currentObj -is [System.Collections.IDictionary]) {
                foreach ($key in $currentObj.Keys) {
                    $val = $currentObj[$key]
                    $childType = if ($null -ne $val) { $val.GetType().FullName } else { 'null' }
                    $childPath = "$varName.$key"

                    $isExpandable = $false
                    if ($null -ne $val) {
                        if ($val -is [System.Collections.IDictionary]) {
                            $isExpandable = $val.Count -gt 0
                        } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                            $isExpandable = @($val).Count -gt 0
                        } elseif ($val.PSObject.Properties.Count -gt 0) {
                            $isExpandable = $true
                        }
                    }

                    $displayValue = if ($null -eq $val) {
                        'null'
                    } elseif ($val -is [string]) {
                        if ($val.Length -gt 100) { $val.Substring(0, 100) + '...' } else { $val }
                    } elseif ($val -is [System.Collections.ICollection]) {
                        "[$childType] Count: $($val.Count)"
                    } else {
                        try {
                            ($val | ConvertTo-Json -Compress -Depth 1).Substring(0, [Math]::Min(200, ($val | ConvertTo-Json -Compress -Depth 1).Length))
                        } catch {
                            "[$childType]"
                        }
                    }

                    $children += [pscustomobject]@{
                        Name = $key
                        Type = $childType
                        Value = $displayValue
                        IsExpandable = $isExpandable
                        Path = $childPath
                    }
                }
            }
            # If it's an array/list, return indexed items
            elseif ($currentObj -is [System.Collections.IEnumerable] -and $currentObj -isnot [string]) {
                $index = 0
                foreach ($item in $currentObj) {
                    if ($index -ge 1000) {
                        $children += [pscustomobject]@{
                            Name = "[...]"
                            Type = "info"
                            Value = "Array has more items (showing first 1000)"
                            IsExpandable = $false
                            Path = ""
                        }
                        break
                    }

                    $itemType = if ($null -ne $item) { $item.GetType().FullName } else { 'null' }
                    $childPath = "$varName.[$index]"

                    $isExpandable = $false
                    if ($null -ne $item) {
                        if ($item -is [System.Collections.IDictionary]) {
                            $isExpandable = $item.Count -gt 0
                        } elseif ($item -is [System.Collections.IEnumerable] -and $item -isnot [string]) {
                            $isExpandable = @($item).Count -gt 0
                        } elseif ($item.PSObject.Properties.Count -gt 0) {
                            $isExpandable = $true
                        }
                    }

                    $displayValue = if ($null -eq $item) {
                        'null'
                    } elseif ($item -is [string]) {
                        if ($item.Length -gt 100) { $item.Substring(0, 100) + '...' } else { $item }
                    } else {
                        try {
                            ($item | ConvertTo-Json -Compress -Depth 1).Substring(0, [Math]::Min(200, ($item | ConvertTo-Json -Compress -Depth 1).Length))
                        } catch {
                            "[$itemType]"
                        }
                    }

                    $children += [pscustomobject]@{
                        Name = "[$index]"
                        Type = $itemType
                        Value = $displayValue
                        IsExpandable = $isExpandable
                        Path = $childPath
                    }
                    $index++
                }
            }
            # If it's an object with properties
            elseif ($null -ne $currentObj -and $currentObj.PSObject.Properties.Count -gt 0) {
                foreach ($prop in $currentObj.PSObject.Properties) {
                    $val = $prop.Value
                    $childType = if ($null -ne $val) { $val.GetType().FullName } else { 'null' }
                    $childPath = "$varName.$($prop.Name)"

                    $isExpandable = $false
                    if ($null -ne $val) {
                        if ($val -is [System.Collections.IDictionary]) {
                            $isExpandable = $val.Count -gt 0
                        } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                            $isExpandable = @($val).Count -gt 0
                        } elseif ($val.PSObject.Properties.Count -gt 0) {
                            $isExpandable = $true
                        }
                    }

                    $displayValue = if ($null -eq $val) {
                        'null'
                    } elseif ($val -is [string]) {
                        if ($val.Length -gt 100) { $val.Substring(0, 100) + '...' } else { $val }
                    } else {
                        try {
                            ($val | ConvertTo-Json -Compress -Depth 1).Substring(0, [Math]::Min(200, ($val | ConvertTo-Json -Compress -Depth 1).Length))
                        } catch {
                            "[$childType]"
                        }
                    }

                    $children += [pscustomobject]@{
                        Name = $prop.Name
                        Type = $childType
                        Value = $displayValue
                        IsExpandable = $isExpandable
                        Path = $childPath
                    }
                }
            }
            # Primitive value
            else {
                $displayValue = if ($null -eq $currentObj) {
                    'null'
                } elseif ($currentObj -is [string]) {
                    $currentObj
                } else {
                    try {
                        $currentObj | ConvertTo-Json -Compress -Depth 2
                    } catch {
                        $currentObj.ToString()
                    }
                }

                $children += [pscustomobject]@{
                    Name = "Value"
                    Type = if ($null -ne $currentObj) { $currentObj.GetType().FullName } else { 'null' }
                    Value = $displayValue
                    IsExpandable = $false
                    Path = ""
                }
            }

            $json = $children | ConvertTo-Json -Depth 3 -Compress
            if ($json -in @('null', '')) { $json = '[]' }
            context_response -Response $Response -String $json -ContentType "application/json"
            return
        } catch {
            $json = @{
                error = "Failed to inspect variable '$varName': $($_.Exception.Message)"
            } | ConvertTo-Json -Compress
            context_response -Response $Response -StatusCode 400 -String $json -ContentType "application/json"
            return
        }
    }

    # Unknown format
    $json = @{
        error = "Unknown format '$format'. Valid formats: list, table, detailed, tree"
    } | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 400 -String $json -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVars' -Message "Error in /api/v1/debug/vars: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
