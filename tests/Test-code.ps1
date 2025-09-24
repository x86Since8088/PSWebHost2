<#
.SYNOPSIS
  Lightweight test runner that executes a scriptblock or script file in an isolated PowerShell runspace,
  captures all output streams, computes variable diffs, walks objects safely and writes structured results
  to an output folder.

.PARAMETER Name
  Required name for the test — used to create the output folder.

.PARAMETER Description
  Required description for the test — saved into metadata.

.PARAMETER BeforeTesting
  Optional scriptblock to run before the test script (setup). Runs in the same isolated runspace used for the
  test script (so side-effects are contained to that runspace process).

.PARAMETER Script
  ScriptBlock to test. Either -Script or -Path must be provided.

.PARAMETER Path
  Path to a script file to execute as the test.

.PARAMETER OutRoot
  Root folder under which test output folders are created. Defaults to ./tests/output

Examples:
  .\Test-code.ps1 -Name MyTest -Description "Verify X" -Script { Get-Process | Select-Object -First 3 }

#>
param(
    [Parameter(Mandatory=$false)][string]$Name,
    [Parameter(Mandatory=$false)][string]$Description,
    [scriptblock]$BeforeTesting,
    [scriptblock]$Script,
    [string]$Path,
    [string]$OutRoot = (Join-Path $PSScriptRoot 'output')
param(

function New-OutputFolder {
    param([string]$base, [string]$name)
    $ts = (Get-Date).ToString('yyyyMMdd-HHmmss')
    $safe = ($name -replace '[^A-Za-z0-9_.-]','_')
    $dir = Join-Path $base "$safe`_$ts"
    New-Item -Path $dir -ItemType Directory -Force | Out-Null
    return $dir
}

function Safe-WalkObject {
    param(
        [Parameter(Mandatory=$true)] $InputObject,
        [int]$MaxDepth = 5,
# Prepare output area
$outDir = New-OutputFolder -base $OutRoot -name $Name
# create human readable log files inside the test output folder
$logStdout = Join-Path $outDir 'stdout.log'
$logStderr = Join-Path $outDir 'stderr.log'

# If this test is the web-routes test, attempt to start a temporary WebHost and inject variables
        [int]$MaxProperties = 60
    )
    # blacklist full names for types we don't want to record
    $blacklist = @(
        'System.IO.Stream', 'System.IO.FileStream', 'System.Management.Automation.PSObject',
        'System.Management.Automation.Runspaces.Runspace', 'System.Management.Automation.Runspaces.Pipeline',
        'System.Threading.Tasks.Task', 'FileSystemProvider', 
        'PSDriveInfo', 'ProviderInfo'

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
            $list += Safe-WalkObject -InputObject $it -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth+1) -MaxEnumerable $MaxEnumerable -MaxProperties $MaxProperties
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
            #$o[$p.Name] = Safe-WalkObject -InputObject $val -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth+1) -MaxEnumerable $MaxEnumerable -MaxProperties $MaxProperties
        } catch {
            #$o[$p.Name] = "[ErrorReadingProperty: $($_.Exception.Message)]"
        }
    }
    return $o
}

# Determine if an object should be walked further
function Test-Walkable {
    param([Parameter(Mandatory=$true)] $InputObject)
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

# Inspect-Object walks an object into a hashtable keyed by property/member names
function Inspect-Object {
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)] $InputObject,
        [int]$Depth = 3,
        [int]$MaxEnumerable = 20,
        [switch]$IncludeNull
    )
    if ($null -eq $InputObject) { return $null }
    if ($Depth -le 0) { return ($InputObject | Out-String).Trim() }

    $blacklist = @(
        'System.IO.Stream', 'System.IO.FileStream', 'System.Management.Automation.PSObject',
        'System.Management.Automation.Runspaces.Runspace', 'System.Management.Automation.Runspaces.Pipeline',
        'System.Threading.Tasks.Task', 'FileSystemProvider', 
        'PSDriveInfo', 'ProviderInfo', 'DirectoryInfo'

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
    try { $members = ($InputObject | Get-Member -MemberType Property,NoteProperty,AliasProperty) } catch { $members = @() }
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

# Return a map (hashtable) of global variables keyed by variable name using Inspect-Object for values
function Capture-VariableSnapshotMap {
    $map = @{}
    Get-Variable -Scope Global -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $val = $_.Value
            $type = try { $val.GetType().FullName } catch { 'System.Object' }
            $map[$_.Name] = @{ Type = $type; Value = Inspect-Object -InputObject $val }
        } catch {
            $map[$_.Name] = @{ Type = 'Error'; Value = $_.Exception.Message }
        }
    }
    return $map
}

function Capture-VariableSnapshot {
    Get-Variable -Scope Global -ErrorAction SilentlyContinue | ForEach-Object {
        $val = $_.Value
        $type = try { $val.GetType().FullName } catch { 'System.Object' }
        [pscustomobject]@{ Name = $_.Name; Type = $type; Value = Safe-WalkObject -InputObject $val }
    }
}

function Compute-VariableDiff($before, $after) {
    $beforeMap = @{}
    foreach ($b in $before) { $beforeMap[$b.Name] = $b }
    $changed = @()
    foreach ($a in $after) {
        if (-not $beforeMap.ContainsKey($a.Name)) {
            $changed += [pscustomobject]@{ Name=$a.Name; Change='Added'; Before=$null; After=$a }
        } else {
            $b = $beforeMap[$a.Name]
            if ($b.Type -ne $a.Type -or (ConvertTo-Json $b.Value -Depth 5) -ne (ConvertTo-Json $a.Value -Depth 5)) {
                $changed += [pscustomobject]@{ Name=$a.Name; Change='Modified'; Before=$b; After=$a }
            }
            $beforeMap.Remove($a.Name) | Out-Null
        }
    }
    foreach ($left in $beforeMap.GetEnumerator()) {
        $changed += [pscustomobject]@{ Name=$left.Key; Change='Removed'; Before=$left.Value; After=$null }
    }
    return $changed
}

function Invoke-Isolated {
    param([scriptblock]$sb)
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.AddScript($sb.ToString()) | Out-Null
    # Use default format for output objects; they will be returned as objects
    $async = $ps.BeginInvoke()
    $out = $ps.EndInvoke($async)
    # Capture streams
    $streams = [ordered]@{
        Output = $out
        Error = @($ps.Streams.Error)
        Verbose = @($ps.Streams.Verbose)
        Warning = @($ps.Streams.Warning)
        Debug = @($ps.Streams.Debug)
        Progress = @($ps.Streams.Progress)
        RunspaceVariables = @()
    }

    # Attempt to capture global variables from the runspace that executed the script
    try {
        $ps.Commands.Clear()
        $ps.AddScript("Get-Variable -Scope Global -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Type = (try{ $_.Value.GetType().FullName } catch { 'System.Object' }); Value = $_.Value } } | ConvertTo-Json -Depth 6") | Out-Null
        $varsJson = $ps.Invoke()
        $varsText = ($varsJson | Out-String).Trim()
        if ($varsText) {
            try { $streams.RunspaceVariables = ConvertFrom-Json $varsText } catch { $streams.RunspaceVariables = @() }
        }
    } catch {
        # ignore runspace variable capture errors
        $streams.RunspaceVariables = @()
    }

    return $streams
}

if (-not $Script -and -not $Path) { throw 'Either -Script or -Path must be provided.' }
if ($Path) {
    if (-not (Test-Path $Path)) { throw "Script file not found: $Path" }
    $raw = Get-Content -Path $Path -Raw
    $Script = [scriptblock]::Create($raw)
}

# Prepare output area
$outDir = New-OutputFolder -base $OutRoot -name $Name
$meta = [pscustomobject]@{ Name=$Name; Description=$Description; Time=(Get-Date).ToString('o'); ScriptPath = $Path }
$meta | ConvertTo-Json -Depth 4 | Out-File -FilePath (Join-Path $outDir 'meta.json') -Encoding utf8

# Initialize script-level output collector
$Script:PSWebTesting = [System.Collections.ArrayList]::new()
$Script:PSWebTesting.Variables = @{}

# Snapshot before
$beforeVars = Capture-VariableSnapshot

if ($BeforeTesting) {
    Write-Host "Running BeforeTesting scriptblock..."
    $beforeStreams = Invoke-Isolated -sb $BeforeTesting
    # Record before testing streams (variable snapshot from the isolated runspace)
    foreach ($e in $beforeStreams.Output) {
        $ts = (Get-Date).ToString('o')
        $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Output'; OutputObjectData=Safe-WalkObject -InputObject $e; VariableChanges = @() }) | Out-Null
    }
    # store runspace final variables for BeforeTesting if provided
    if ($beforeStreams.RunspaceVariables -and $beforeStreams.RunspaceVariables.Count -gt 0) {
        $tsb = "BeforeTesting_" + (Get-Date).ToString('o')
        $Script:PSWebTesting.Variables[$tsb] = ($beforeStreams.RunspaceVariables | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Type=$_.Type; Value = Safe-WalkObject -InputObject $_.Value } })
    }
}

Write-Host "Running test script..."
$beforeVarsForRun = Capture-VariableSnapshotMap
$streams = Invoke-Isolated -sb $Script

# Record outputs without attempting per-output variable diffs (see notes)
foreach ($o in $streams.Output) {
    $ts = (Get-Date).ToString('o')
    $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Output'; OutputObjectData=Safe-WalkObject -InputObject $o; VariableChanges = @() }) | Out-Null
}
foreach ($er in $streams.Error) {
    $ts = (Get-Date).ToString('o')
    $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Error'; OutputObjectData=Safe-WalkObject -InputObject $er; VariableChanges = @() }) | Out-Null
}
foreach ($v in $streams.Verbose) {
    $ts = (Get-Date).ToString('o')
    $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Verbose'; OutputObjectData = Safe-WalkObject -InputObject $v; VariableChanges = @() }) | Out-Null
}
foreach ($w in $streams.Warning) {
    $ts = (Get-Date).ToString('o')
    $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Warning'; OutputObjectData = Safe-WalkObject -InputObject $w; VariableChanges = @() }) | Out-Null
}
foreach ($d in $streams.Debug) {
    $ts = (Get-Date).ToString('o')
    $Script:PSWebTesting.Add([pscustomobject]@{ Time=$ts; Stream='Debug'; OutputObjectData = Safe-WalkObject -InputObject $d; VariableChanges = @() }) | Out-Null
}

# Use runspace-captured variables for final diff (accurate for the isolated run)
if ($streams.RunspaceVariables -and $streams.RunspaceVariables.Count -gt 0) {
    $finalVars = $streams.RunspaceVariables | ForEach-Object { [pscustomobject]@{ Name=$_.Name; Type=$_.Type; Value = Safe-WalkObject -InputObject $_.Value } }
    $varDiff = Compute-VariableDiff -before $beforeVarsForRun -after $finalVars
    $tsFinal = "Final_" + (Get-Date).ToString('o')
    $Script:PSWebTesting.Variables[$tsFinal] = $finalVars
} else {
    $afterVars = Capture-VariableSnapshot
    $varDiff = Compute-VariableDiff -before $beforeVars -after $afterVars
}

# Snapshot after
$afterVars = Capture-VariableSnapshot

$varDiff = Compute-VariableDiff -before $beforeVars -after $afterVars

# Add a final summary entry
$Script:PSWebTesting.Add(
    [pscustomobject]@{
        Time = (Get-Date).ToString('o')
        Stream = 'Summary'
        VariableDiff = $varDiff
        OutputCount = $streams.Output.Count
        ErrorCount = $streams.Error.Count
    }
) | Out-Null

# Persist results
$resultFile = Join-Path $outDir 'results.json'
$Script:PSWebTesting | ConvertTo-Json -Depth 10 | Out-File -FilePath $resultFile -Encoding utf8

Write-Host "Test completed. Results written to: $outDir"
Write-Output $outDir
