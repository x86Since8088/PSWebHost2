function Convert-ObjectToYaml {
    [cmdletbinding()]
    param(
        $InputObject,
        [int]$Depth = 0,
        [int]$MaxDepth = 5 # Added MaxDepth to prevent infinite recursion
    )
    if (-not $PSBoundParameters.ContainsKey('InputObject')) { Write-Error "The -InputObject parameter is required."; return }
    if ($Depth -ge $MaxDepth) { return "[Max Depth Reached]`n" } # Added depth check

    $indent = "  " * $Depth
    $output = ""

    if ($InputObject -is [hashtable] -or $InputObject -is [pscustomobject]) {
        $properties = if ($InputObject -is [hashtable]) { $InputObject.Keys } else { $InputObject.psobject.properties | ForEach-Object { $_.Name } }
        foreach ($key in $properties) {
            $value = if ($InputObject -is [hashtable]) { $InputObject[$key] } else { $InputObject.$key }
            $output += "$indent$key`:
"
            # Pass MaxDepth down in recursive call
            $output += Convert-ObjectToYaml -InputObject $value -Depth ($Depth + 1) -MaxDepth $MaxDepth
        }
    } elseif ($InputObject -is [array]) {
        foreach ($item in $InputObject) {
            $output += "$indent- "
            # Pass MaxDepth down in recursive call
            $output += (Convert-ObjectToYaml -InputObject $item -Depth ($Depth + 1) -MaxDepth $MaxDepth).TrimStart()
        }
    } elseif ($InputObject -is [string]) {
        $output += "$indent`"$InputObject`"`n"
    } elseif ($null -eq $InputObject) {
        $output += "$indent`null`n"
    } else {
        try {
            $output += "$indent$($InputObject.ToString())`n"
        } catch {
            $output += "$indent`(unwalkable value)`n"
        }
    }

    return $output
}

# NOTE: This function appears to be incomplete or obsolete. 
# The main logic for recursively walking properties is commented out.
# The Inspect-Object function provides similar, more robust functionality.
function Get-ObjectSafeWalk {
    param(
        $InputObject,
        [int]$MaxDepth = 5,
        [int]$CurrentDepth = 0,
        [int]$MaxEnumerable = 20,
        [int]$MaxProperties = 60
    )
    if (-not $PSBoundParameters.ContainsKey('InputObject')) { Write-Error "The -InputObject parameter is required."; return }

    # blacklist full names for types we don't want to record
    $blacklist = @(
        'System.IO.Stream', 'System.IO.FileStream', 'System.Management.Automation.PSObject',
        'System.Management.Automation.Runspaces.Runspace', 'System.Management.Automation.Runspaces.Pipeline',
        'System.Threading.Tasks.Task', 'FileSystemProvider', 
        'PSDriveInfo', 'ProviderInfo',
        'PSCredential'
    )

    if ($CurrentDepth -ge $MaxDepth) { return '[MaxDepth]' }
    if ($null -eq $InputObject) { return @{ Type = 'System.Nullable'; Value = $null } }
    try {
        $t = $InputObject.GetType().FullName
        $tn = $InputObject.GetType().Name
    } catch { $t = 'Unknown' }

    if ($blacklist -contains $t -or ($blacklist -contains $tn)) { return "[Blacklisted: $t]" }
    if ($InputObject -is [string] -or $InputObject -is [ValueType]) { return $InputObject }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @()
        $count = 0
        foreach ($it in $InputObject) {
            if ($count -ge $MaxEnumerable) { $list += "[Truncated: more items]"; break }
            $list += Get-ObjectSafeWalk -InputObject $it -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth+1) -MaxEnumerable $MaxEnumerable -MaxProperties $MaxProperties
            $count++
        }
        return $list
    }

    # For POCOs, pull properties but limit to MaxProperties
    $props = @()
    try { $props = $InputObject.psobject.Properties } catch { $props = @() }
    if ($props.Count -gt $MaxProperties) { return "[TooManyProperties: $($props.Count)]" }
    $o = [ordered]@{ __type = $t }
    foreach ($p in $props) {
        try {
            $val = $p.Value
            #$o[$p.Name] = Get-ObjectSafeWalk -InputObject $val -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth+1) -MaxEnumerable $MaxEnumerable -MaxProperties $MaxProperties
        } catch {
            #$o[$p.Name] = "[ErrorReadingProperty: $($_.Exception.Message)]"
        }
    }
    return $o
}

# Determine if an object should be walked further
function Test-Walkable {
    param($InputObject)
    if (-not $PSBoundParameters.ContainsKey('InputObject')) { Write-Error "The -InputObject parameter is required."; return }

    if ($null -eq $InputObject) { return $false }
    try {
        $t = $InputObject.GetType()
    } catch { return $false }
    # Value types are not walkable
    if ($t.BaseType -and $t.BaseType.Name -eq 'ValueType') { return $false }
    # Strings are not walkable
    if ($InputObject -is [string]) { return $false }
    # Blacklist some heavy types
    $blacklist = @('System.IO.Stream','System.IO.FileStream','System.Management.Automation.Runspaces.Runspace','System.Threading.Tasks.Task')
    if ($blacklist -contains $t.FullName) { return $false }
    return $true
}

function Inspect-Object {
    param(
        [Parameter(ValueFromPipeline=$true)] $InputObject,
        [int]$Depth = 3,
        [int]$MaxEnumerable = 20,
        [switch]$IncludeNull
    )
    if (-not $PSBoundParameters.ContainsKey('InputObject')) { Write-Error "The -InputObject parameter is required."; return }

    if ($null -eq $InputObject) { return $null }
    if ($Depth -le 0) { return ($InputObject | Out-String).Trim() }

    $blacklist = @(
        'System.IO.Stream', 'System.IO.FileStream', 'System.Management.Automation.PSObject',
        'System.Management.Automation.Runspaces.Runspace', 'System.Management.Automation.Runspaces.Pipeline',
        'System.Threading.Tasks.Task', 'FileSystemProvider', 
        'PSDriveInfo', 'ProviderInfo', 'DirectoryInfo',
        'PSCredential'
    )

    if ($null -eq $InputObject) { return @{ Type = 'System.Nullable'; Value = $null } }
    try { $t = $InputObject.GetType() } catch { $t = $null }
    # If value type or string return scalar
    if ($blacklist -contains $t.FullName -or ($blacklist -contains $t.Name)) { return } 
    
    if ($t -and $t.BaseType -and $t.BaseType.Name -eq 'ValueType') { return @{ Type = $t.Name; Value = $InputObject } }
    if ($InputObject -is [string]) { return @{ Type = 'String'; Value = $InputObject } }

    # If IDictionary-like (has .Keys), walk keys
    if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [hashtable]) {
        $h = @{}
        foreach ($k in $InputObject.Keys) {
            try {
                $v = $InputObject[$k]
                # If value type or string return scalar
                if ($null -ne $v -and -not $IncludeNull.IsPresent) {
                    try { $vt = $InputObject.GetType() } catch { $vt = $null }
                    if ($blacklist -contains $vt.FullName -or ($blacklist -contains $vt.Name)) {} 
                    else{
                        $val = if (Test-Walkable $v) { Inspect-Object -InputObject $v -Depth ($Depth - 1) -MaxEnumerable $MaxEnumerable } else { $v }
                        $h[$k.ToString()] = @{ Type = try { $v.GetType().Name } catch { 'Object' }; Value = $val }
                    }
                }
            } catch { $h[$k.ToString()] = @{ Type = 'Error'; Value = "Error reading key: $($_.Exception.Message)" } }
        }
        return @{ Type = try { $t.Name } catch { 'Dictionary' }; Value = $h }
    }

    # If IEnumerable (but not string), enumerate a limited list
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @()
        $count = 0
        foreach ($it in $InputObject) {
            if ($count -ge $MaxEnumerable) { $list += '[Truncated: more items]'; break }
            $list += if (Test-Walkable $it) { Inspect-Object -InputObject $it -Depth ($Depth - 1) -MaxEnumerable $MaxEnumerable } else { $it }
            $count++
        }
        return @{ Type = try { $t.Name } catch { 'Enumerable' }; Value = $list }
    }

    # For POCOs, use Get-Member to discover properties (exclude methods and ParameterizedProperty)
    $members = @()
    if ($null -eq $InputObject) { return }
    try {
        [array]$members = ($InputObject | 
            Where-Object{$null -ne $_} | 
            Get-Member -MemberType Property,NoteProperty,AliasProperty -ErrorAction Ignore) 
    } catch { $members = @() }
    $h = @{}
    foreach ($m in $members) {
        $name = $m.Name
        try {
            $val = $InputObject.$name
            if ($null -eq $val -and -not $IncludeNull.IsPresent) {}
            else {
                try { $vt = $val.GetType() } catch { $vt = $null }
                if ($blacklist -contains $vt.FullName -or ($blacklist -contains $vt.Name)) {} 
                else {
                    $valOut = if (Test-Walkable $val) { Inspect-Object -InputObject $val -Depth ($Depth - 1) -MaxEnumerable $MaxEnumerable } else { $val }
                    $h[$name] = @{ Type = try { $val.GetType().Name } catch { 'Object' }; Value = $valOut }
                }
            }
        } catch { 
            if ($_.Exception.Message -like '*because it is null.') {
                $h[$name] = @{ Type = 'System.Nullable'; Value = $null }
            } else {
                $h[$name] = @{ Type = 'Error'; Value = "Error reading property: $($_.Exception.Message)" }
            }
        }
    }
    return @{ Type = try { $t.Name } catch { 'Object' }; Value = $h }
}