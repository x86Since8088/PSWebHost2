param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Get variable path from query parameter
    $varPath = $Request.QueryString['path']

    # Exclude known problematic variables
    $excludeVars = @('PSWebServer', 'Host', 'ExecutionContext', 'true', 'false', 'null',
                     'Context', 'Request', 'Response', 'SessionData', 'PSBoundParameters',
                     'LogHistory', 'PSWebHostLogQueue', 'PSHostUIQueue', 'Error', 'StackTrace',
                     'MyInvocation', 'PSScriptRoot', 'PSCommandPath')

    # If no path specified, return root variables
    if (-not $varPath) {
        $allVars = Get-Variable -Scope Global -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -notin $excludeVars }

        $varList = $allVars | ForEach-Object {
            $type = if ($null -ne $_.Value) { $_.Value.GetType().FullName } else { 'null' }
            $isExpandable = $false

            if ($null -ne $_.Value) {
                if ($_.Value -is [System.Collections.IDictionary]) {
                    $isExpandable = $_.Value.Count -gt 0
                } elseif ($_.Value -is [System.Collections.IEnumerable] -and $_.Value -isnot [string]) {
                    $isExpandable = @($_.Value).Count -gt 0
                } elseif ($_.Value.PSObject -and $_.Value.PSObject.Properties -and $_.Value.PSObject.Properties.Count -gt 0) {
                    $isExpandable = $true
                }
            }

            [pscustomobject]@{
                Name = $_.Name
                Type = $type
                IsExpandable = $isExpandable
                Path = $_.Name
                Value = if ($isExpandable) {
                    if ($_.Value -is [System.Collections.IDictionary]) {
                        "[Dictionary] $($_.Value.Count) keys"
                    } elseif ($_.Value -is [System.Collections.IEnumerable]) {
                        "[Array] $(@($_.Value).Count) items"
                    } else {
                        "[Object]"
                    }
                } else {
                    if ($null -eq $_.Value) { "null" }
                    elseif ($_.Value -is [string]) {
                        if ($_.Value.Length -gt 100) { $_.Value.Substring(0, 100) + "..." } else { $_.Value }
                    }
                    else {
                        try { ($_.Value | ConvertTo-Json -Compress -Depth 1).Substring(0, [Math]::Min(200, ($_.Value | ConvertTo-Json -Compress -Depth 1).Length)) }
                        catch { $_.Value.ToString() }
                    }
                }
            }
        }

        $json = $varList | ConvertTo-Json -Depth 3 -Compress
        if ($json -in @('null', '')) { $json = '[]' }
        context_response -Response $Response -String $json -ContentType "application/json"
        return
    }

    # Navigate to nested property
    $pathParts = $varPath -split '\.'
    $rootVarName = $pathParts[0]

    $currentObj = Get-Variable -Name $rootVarName -Scope Global -ErrorAction Stop -ValueOnly

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

    # Dictionary/Hashtable
    if ($currentObj -is [System.Collections.IDictionary]) {
        foreach ($key in $currentObj.Keys) {
            $val = $currentObj[$key]
            $childType = if ($null -ne $val) { $val.GetType().FullName } else { 'null' }
            $childPath = "$varPath.$key"

            $isExpandable = $false
            if ($null -ne $val) {
                if ($val -is [System.Collections.IDictionary]) {
                    $isExpandable = $val.Count -gt 0
                } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                    $isExpandable = @($val).Count -gt 0
                } elseif ($val.PSObject -and $val.PSObject.Properties -and $val.PSObject.Properties.Count -gt 0) {
                    $isExpandable = $true
                }
            }

            $displayValue = if ($null -eq $val) { 'null' }
            elseif ($val -is [string]) {
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
    # Array/List
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
            $childPath = "$varPath.[$index]"

            $isExpandable = $false
            if ($null -ne $item) {
                if ($item -is [System.Collections.IDictionary]) {
                    $isExpandable = $item.Count -gt 0
                } elseif ($item -is [System.Collections.IEnumerable] -and $item -isnot [string]) {
                    $isExpandable = @($item).Count -gt 0
                } elseif ($item.PSObject -and $item.PSObject.Properties -and $item.PSObject.Properties.Count -gt 0) {
                    $isExpandable = $true
                }
            }

            $displayValue = if ($null -eq $item) { 'null' }
            elseif ($item -is [string]) {
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
    # Object with properties
    elseif ($null -ne $currentObj -and $currentObj.PSObject -and $currentObj.PSObject.Properties -and $currentObj.PSObject.Properties.Count -gt 0) {
        foreach ($prop in $currentObj.PSObject.Properties) {
            $val = $prop.Value
            $childType = if ($null -ne $val) { $val.GetType().FullName } else { 'null' }
            $childPath = "$varPath.$($prop.Name)"

            $isExpandable = $false
            if ($null -ne $val) {
                if ($val -is [System.Collections.IDictionary]) {
                    $isExpandable = $val.Count -gt 0
                } elseif ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                    $isExpandable = @($val).Count -gt 0
                } elseif ($val.PSObject -and $val.PSObject.Properties -and $val.PSObject.Properties.Count -gt 0) {
                    $isExpandable = $true
                }
            }

            $displayValue = if ($null -eq $val) { 'null' }
            elseif ($val -is [string]) {
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
        $displayValue = if ($null -eq $currentObj) { 'null' }
        elseif ($currentObj -is [string]) { $currentObj }
        else {
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

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugVariables' -Message "Error in variables endpoint: $($_.Exception.Message)"

    $json = @{
        error = "Failed to retrieve variables: $($_.Exception.Message)"
    } | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 500 -String $json -ContentType "application/json"
}
