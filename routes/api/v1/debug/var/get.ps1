param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Get variable name from query parameter
    $name = $Request.QueryString['name']
    if (-not $name) {
        $json = @{ error = "Missing 'name' parameter" } | ConvertTo-Json -Compress
        context_response -Response $Response -StatusCode 400 -String $json -ContentType "application/json"
        return
    }

    # Remove leading $ if present
    $name = $name -replace '^\$', ''

    # Get format (default: detailed)
    $format = $Request.QueryString['format']
    if (-not $format) { $format = 'detailed' }

    # Check if variable exists
    $var = Get-Variable -Name $name -Scope Global -ErrorAction SilentlyContinue
    if (-not $var) {
        $json = @{
            error = "Variable '$name' not found in global scope"
        } | ConvertTo-Json -Compress
        context_response -Response $Response -StatusCode 404 -String $json -ContentType "application/json"
        return
    }

    # --- FORMAT: simple (type and basic info only) ---
    if ($format -eq 'simple') {
        $valueType = if ($null -ne $var.Value) { $var.Value.GetType().FullName } else { 'null' }

        $result = @{
            Name = $var.Name
            Type = $valueType
            IsCollection = $var.Value -is [System.Collections.ICollection]
            Count = if ($var.Value -is [System.Collections.ICollection]) { $var.Value.Count } else { $null }
        }

        $json = $result | ConvertTo-Json -Compress
        context_response -Response $Response -String $json -ContentType "application/json"
        return
    }

    # --- FORMAT: string (Out-String representation) ---
    if ($format -eq 'string') {
        $timeout = 15000  # 15 second timeout
        $job = $null

        try {
            $job = Start-Job -ScriptBlock {
            param($VarName)

            $v = Get-Variable -Name $VarName -Scope Global -ErrorAction SilentlyContinue
            if ($v -and $null -ne $v.Value) {
                try {
                    $v.Value | Out-String -Width 120
                } catch {
                    "Error converting to string: $($_.Exception.Message)"
                }
            } else {
                'null'
            }
            } -ArgumentList $name

            # Wait with timeout
            $completed = Wait-Job -Job $job -Timeout ($timeout / 1000)

            if ($completed) {
                $result = Receive-Job -Job $job
                Remove-Job -Job $job -Force
                $job = $null

                $json = @{
                    status = 'success'
                    format = 'string'
                    name = $name
                    output = $result
                } | ConvertTo-Json -Compress

                context_response -Response $Response -String $json -ContentType "application/json"
            } else {
                Remove-Job -Job $job -Force
                $job = $null

                $json = @{
                    status = 'timeout'
                    format = 'string'
                    message = "Operation timed out after $($timeout/1000) seconds"
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

    # --- FORMAT: detailed (full YAML inspection with job timeout) ---
    if ($format -eq 'detailed') {
        Import-Module (Join-Path $Global:PSWebServer.Project_Root.Path "modules/PSWebHost_Formatters/PSWebHost_Formatters.psd1") -DisableNameChecking
        Import-Module powershell-yaml -DisableNameChecking

        $timeout = 30000  # 30 second timeout
        $job = $null

        try {
            $job = Start-Job -ScriptBlock {
            param($VarName, $ProjectRoot)

            # Import modules in job context
            Import-Module (Join-Path $ProjectRoot "modules/PSWebHost_Formatters/PSWebHost_Formatters.psd1") -DisableNameChecking
            Import-Module powershell-yaml -DisableNameChecking

            $v = Get-Variable -Name $VarName -Scope Global -ErrorAction SilentlyContinue

            if (-not $v -or $null -eq $v.Value) {
                return @{
                    Name = $VarName
                    Type = 'null'
                    RawValue = 'null'
                }
            }

            $valueType = $v.Value.GetType().FullName
            $isSizeableCollection = $v.Value -is [System.Collections.ICollection]
            $maxValueSize = 100000  # 100KB max for single variable

            try {
                # For very large collections, provide summary
                if ($isSizeableCollection -and $v.Value.Count -gt 500) {
                    $yamlValue = "[$valueType] Collection with $($v.Value.Count) items (too large - use PowerShell console to inspect or reduce size)"
                }
                # For synchronized hashtables
                elseif ($valueType -match 'Hashtable' -and $v.Value.GetType().Name -eq 'Hashtable' -and $v.Value.IsSynchronized) {
                    $yamlValue = "Synchronized Hashtable with $($v.Value.Count) entries (use PowerShell console to inspect)"
                }
                # For concurrent collections
                elseif ($valueType -match 'Concurrent') {
                    $count = if ($v.Value | Get-Member -Name 'Count') { $v.Value.Count } else { 'unknown' }
                    $yamlValue = "[$valueType] Concurrent collection with $count items (thread-safe)"
                }
                # Normal inspection
                else {
                    $inspected = Inspect-Object -InputObject $v.Value
                    $yamlValue = $inspected | ConvertTo-Yaml

                    # Truncate if too large
                    if ($yamlValue.Length -gt $maxValueSize) {
                        $truncated = $yamlValue.Substring(0, $maxValueSize)
                        $yamlValue = "$truncated`n... (truncated, original size: $($yamlValue.Length) characters)"
                    }
                }

                return @{
                    Name = $v.Name
                    Type = $valueType
                    RawValue = $yamlValue
                    IsCollection = $isSizeableCollection
                    Count = if ($isSizeableCollection) { $v.Value.Count } else { $null }
                }
            } catch {
                return @{
                    Name = $v.Name
                    Type = 'Error'
                    RawValue = "Error processing variable: $($_.Exception.Message)"
                }
            }
            } -ArgumentList $name, $Global:PSWebServer.Project_Root.Path

            # Wait with timeout
            $startTime = Get-Date

            while (((Get-Date) - $startTime).TotalMilliseconds -lt $timeout) {
                if ($job.State -eq 'Completed') {
                    $result = Receive-Job -Job $job
                    Remove-Job -Job $job -Force
                    $job = $null

                    $json = $result | ConvertTo-Json -Depth 10 -Compress
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

            # Timeout
            Remove-Job -Job $job -Force
            $job = $null

            $json = @{
                status = 'timeout'
                message = "Variable inspection timed out after $($timeout/1000) seconds"
                name = $name
            } | ConvertTo-Json -Compress

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

    # Unknown format
    $json = @{
        error = "Unknown format '$format'. Valid formats: simple, string, detailed"
    } | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 400 -String $json -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVar' -Message "Error in /api/v1/debug/var GET: $($_.Exception.Message)"

    # Generate detailed error report based on user role
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata

    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
