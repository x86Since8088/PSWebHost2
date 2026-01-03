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
    # Formats: list (names/types only), table (Out-String), detailed (full inspection with YAML)
    $format = $Request.QueryString['format']
    if (-not $format) { $format = 'list' }

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
        context_reponse -Response $Response -String $json -ContentType "application/json"
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

                context_reponse -Response $Response -String $json -ContentType "application/json"
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

                context_reponse -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
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

                    context_reponse -Response $Response -String $json -ContentType "application/json"
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

                    context_reponse -Response $Response -StatusCode 500 -String $json -ContentType "application/json"
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

            context_reponse -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
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

    # Unknown format
    $json = @{
        error = "Unknown format '$format'. Valid formats: list, table, detailed"
    } | ConvertTo-Json -Compress
    context_reponse -Response $Response -StatusCode 400 -String $json -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVars' -Message "Error in /api/v1/debug/vars: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_reponse -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
