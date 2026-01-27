#Requires -Version 7

<#
.SYNOPSIS
    Memory analysis job for WebHostTaskManagement integration

.DESCRIPTION
    This script is designed to be executed via the WebHostTaskManagement job system.
    It performs live memory analysis and returns formatted results that can be
    viewed through the job results API.

.PARAMETER Deep
    Perform deep analysis including string duplication detection

.PARAMETER TopCount
    Number of top items to show in each category (default: 20)

.PARAMETER ExportCSV
    If specified, exports detailed analysis to CSV in JobResults directory

.EXAMPLE
    # Submitted via API:
    POST /apps/WebHostTaskManagement/api/v1/jobs/submit
    {
        "jobName": "MemoryAnalysis",
        "command": "& 'C:\\SC\\PsWebHost\\system\\utility\\MemoryAnalysis-Job.ps1' -Deep -TopCount 30",
        "executionMode": "MainLoop"
    }
#>

[CmdletBinding()]
param(
    [switch]$Deep,
    [int]$TopCount = 20,
    [switch]$ExportCSV
)

$ErrorActionPreference = 'Continue'

# Start output
Write-Output ""
Write-Output "=== PSWebHost Memory Analysis ==="
Write-Output "Process ID: $PID"
Write-Output "Analysis Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output ""

# ===========================================================================
# Section 1: GC Heap Statistics
# ===========================================================================

Write-Output "=== GC Heap Statistics ==="
Write-Output ""

$proc = Get-Process -Id $PID
$gcTotalMemory = [GC]::GetTotalMemory($false)

$stats = [PSCustomObject]@{
    "Working Set (MB)" = [math]::Round($proc.WorkingSet64 / 1MB, 2)
    "Private Memory (MB)" = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
    "Virtual Memory (MB)" = [math]::Round($proc.VirtualMemorySize64 / 1MB, 2)
    "GC Total Memory (MB)" = [math]::Round($gcTotalMemory / 1MB, 2)
    "Gen 0 Collections" = [GC]::CollectionCount(0)
    "Gen 1 Collections" = [GC]::CollectionCount(1)
    "Gen 2 Collections" = [GC]::CollectionCount(2)
    "Threads" = $proc.Threads.Count
    "Handles" = $proc.HandleCount
}

$stats | Format-List | Out-String | Write-Output

# ===========================================================================
# Section 2: Global Variables Analysis
# ===========================================================================

Write-Output "=== Global Variable Sizes ==="
Write-Output ""

$globalVars = Get-Variable -Scope Global | ForEach-Object {
    $varName = $_.Name
    $value = $_.Value

    try {
        # Get type
        $typeName = if ($value) { $value.GetType().Name } else { "null" }

        # Get count for collections
        $count = if ($value -is [System.Collections.ICollection]) { $value.Count } else { "N/A" }

        # Try to measure JSON size with timeout (shorter for job execution)
        $jsonSize = "N/A"
        $job = Start-Job -ScriptBlock {
            param($Val)
            try {
                ($Val | ConvertTo-Json -Depth 3 -Compress).Length
            }
            catch {
                -1
            }
        } -ArgumentList $value

        $completed = Wait-Job -Job $job -Timeout 1
        if ($completed) {
            $result = Receive-Job -Job $job
            if ($result -ge 0) {
                $jsonSize = $result
            }
        }
        else {
            Stop-Job -Job $job
            $jsonSize = "TIMEOUT"
        }
        Remove-Job -Job $job -Force

        [PSCustomObject]@{
            Name = $varName
            Type = $typeName
            Count = $count
            JSONSizeKB = if ($jsonSize -is [int]) { [math]::Round($jsonSize / 1KB, 2) } else { $jsonSize }
        }
    }
    catch {
        [PSCustomObject]@{
            Name = $varName
            Type = "ERROR"
            Count = "N/A"
            JSONSizeKB = "ERROR"
        }
    }
}

# Show top variables by size
$globalVars |
    Where-Object { $_.JSONSizeKB -is [double] } |
    Sort-Object JSONSizeKB -Descending |
    Select-Object -First $TopCount |
    Format-Table -Property Name, Type, Count, JSONSizeKB -AutoSize |
    Out-String |
    Write-Output

# ===========================================================================
# Section 3: Hashtable Analysis
# ===========================================================================

Write-Output "=== Hashtable Analysis ==="
Write-Output ""

$hashtables = Get-Variable -Scope Global | Where-Object {
    $_.Value -is [hashtable] -or $_.Value -is [System.Collections.IDictionary]
}

Write-Output "Found $($hashtables.Count) hashtables in global scope"
Write-Output ""

$hashtableStats = foreach ($ht in $hashtables) {
    try {
        $value = $ht.Value
        $jsonSize = "N/A"

        # Try to measure (short timeout)
        $job = Start-Job -ScriptBlock {
            param($Val)
            try {
                ($Val | ConvertTo-Json -Depth 2 -Compress).Length
            }
            catch {
                -1
            }
        } -ArgumentList $value

        $completed = Wait-Job -Job $job -Timeout 1
        if ($completed) {
            $result = Receive-Job -Job $job
            if ($result -ge 0) {
                $jsonSize = $result
            }
        }
        else {
            Stop-Job -Job $job
        }
        Remove-Job -Job $job -Force

        [PSCustomObject]@{
            Name = $ht.Name
            Count = $value.Count
            Type = $value.GetType().Name
            JSONSizeKB = if ($jsonSize -is [int]) { [math]::Round($jsonSize / 1KB, 2) } else { "TIMEOUT" }
        }
    }
    catch {
        [PSCustomObject]@{
            Name = $ht.Name
            Count = "ERROR"
            Type = "ERROR"
            JSONSizeKB = "ERROR"
        }
    }
}

$hashtableStats |
    Where-Object { $_.JSONSizeKB -is [double] } |
    Sort-Object JSONSizeKB -Descending |
    Select-Object -First $TopCount |
    Format-Table -AutoSize |
    Out-String |
    Write-Output

# ===========================================================================
# Section 4: PSWebServer Specific Analysis
# ===========================================================================

if ($Global:PSWebServer) {
    Write-Output "=== PSWebServer Specific Analysis ==="
    Write-Output ""

    # Analyze PSWebServer hashtable
    if ($Global:PSWebServer -is [hashtable]) {
        Write-Output "PSWebServer Keys:"
        Write-Output ""

        foreach ($key in ($Global:PSWebServer.Keys | Sort-Object)) {
            $value = $Global:PSWebServer[$key]
            $typeName = if ($value) { $value.GetType().Name } else { "null" }
            $count = if ($value -is [System.Collections.ICollection]) { $value.Count } else { "N/A" }

            $output = "  $key [$typeName]"
            if ($count -ne "N/A") {
                $output += " (Count: $count)"
            }
            Write-Output $output
        }
        Write-Output ""
    }

    # Analyze Apps
    if ($Global:PSWebServer.Apps) {
        Write-Output "Loaded Apps: $($Global:PSWebServer.Apps.Count)"
        $Global:PSWebServer.Apps.Keys | Sort-Object | ForEach-Object {
            Write-Output "  - $_"
        }
        Write-Output ""
    }

    # Analyze Sessions
    if ($Global:PSWebSessions) {
        Write-Output "Active Sessions: $($Global:PSWebSessions.Count)"
        Write-Output ""
    }

    # Analyze LogHistory
    if ($Global:LogHistory) {
        Write-Output "Log History Entries: $($Global:LogHistory.Count)"
        Write-Output ""
    }

    # Analyze Runspaces
    if ($Global:PSWebServer.Runspaces) {
        Write-Output "Tracked Runspaces: $($Global:PSWebServer.Runspaces.Count)"
        Write-Output ""
    }
}

# ===========================================================================
# Section 5: Deep Analysis (if requested)
# ===========================================================================

if ($Deep) {
    Write-Output "=== String Analysis (Deep Mode) ==="
    Write-Output "Analyzing strings in global variables..."
    Write-Output ""

    $strings = @{}
    $totalStrings = 0

    function Analyze-Object {
        param($obj, $depth = 0)

        if ($depth -gt 2) { return }  # Shallow depth for job execution

        if ($obj -is [string]) {
            $script:totalStrings++
            $key = if ($obj.Length -gt 100) { $obj.Substring(0, 100) } else { $obj }

            if (-not $script:strings.ContainsKey($key)) {
                $script:strings[$key] = 0
            }
            $script:strings[$key]++
        }
        elseif ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
            $itemCount = 0
            foreach ($item in $obj) {
                $itemCount++
                if ($itemCount -gt 100) { break }  # Limit for performance
                Analyze-Object -obj $item -depth ($depth + 1)
            }
        }
        elseif ($obj -is [hashtable] -or $obj -is [System.Collections.IDictionary]) {
            $keyCount = 0
            foreach ($htkey in $obj.Keys) {
                $keyCount++
                if ($keyCount -gt 100) { break }  # Limit for performance
                Analyze-Object -obj $htkey -depth ($depth + 1)
                Analyze-Object -obj $obj[$htkey] -depth ($depth + 1)
            }
        }
    }

    Get-Variable -Scope Global | ForEach-Object {
        try {
            Analyze-Object -obj $_.Value
        }
        catch {
            # Skip errors
        }
    }

    Write-Output "Total Strings Found: $($totalStrings.ToString('N0'))"
    Write-Output "Unique Strings: $($strings.Count.ToString('N0'))"

    if ($totalStrings -gt 0) {
        $dupRate = (1.0 - ($strings.Count / $totalStrings)) * 100
        $indicator = if ($dupRate -gt 70) { '[HIGH]' } elseif ($dupRate -gt 50) { '[MEDIUM]' } else { '[LOW]' }
        Write-Output "Duplication Rate: $($dupRate.ToString('F2'))% $indicator"
    }
    Write-Output ""

    Write-Output "Top $TopCount Duplicated Strings:"
    $strings.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First $TopCount |
        ForEach-Object {
            $displayStr = $_.Key -replace "`r", "\r" -replace "`n", "\n"
            if ($displayStr.Length -gt 50) {
                $displayStr = $displayStr.Substring(0, 47) + "..."
            }
            $indicator = if ($_.Value -gt 1000) { '[!!!]' } elseif ($_.Value -gt 100) { '[!!]' } else { '[!]' }
            Write-Output "  $($_.Value.ToString().PadLeft(6)) x $indicator $displayStr"
        }
    Write-Output ""
}

# ===========================================================================
# Section 6: Recommendations
# ===========================================================================

Write-Output "=== Recommendations ==="
Write-Output ""

$recommendations = @()

# Check for large hashtables
$largeHashtables = $hashtableStats | Where-Object { $_.JSONSizeKB -is [double] -and $_.JSONSizeKB -gt 1024 }
if ($largeHashtables) {
    $recommendations += "[WARNING] Found $($largeHashtables.Count) hashtable(s) larger than 1MB - consider cleanup"
}

# Check string duplication
if ($Deep -and $totalStrings -gt 0) {
    $dupRate = (1.0 - ($strings.Count / $totalStrings)) * 100
    if ($dupRate -gt 70) {
        $recommendations += "[WARNING] High string duplication rate ($($dupRate.ToString('F2'))%) - consider string interning"
    }
}

# Check GC Gen2 collections
$gen2 = [GC]::CollectionCount(2)
if ($gen2 -gt 100) {
    $recommendations += "[WARNING] High Gen2 collection count ($gen2) - may indicate memory pressure"
}

# Check working set
$wsMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
if ($wsMB -gt 1024) {
    $recommendations += "[WARNING] Working set is ${wsMB}MB - consider memory optimization"
}

if ($recommendations.Count -eq 0) {
    Write-Output "[OK] No issues detected"
}
else {
    foreach ($rec in $recommendations) {
        Write-Output $rec
    }
}

Write-Output ""
Write-Output "=== Analysis Complete ==="
Write-Output ""

# Export CSV if requested
if ($ExportCSV) {
    try {
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            "PsWebHost_Data"
        }

        $csvPath = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults\MemoryAnalysis_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"

        $exportData = @()

        # Add global variables
        foreach ($var in $globalVars) {
            if ($var.JSONSizeKB -is [double]) {
                $exportData += [PSCustomObject]@{
                    Category = "GlobalVariable"
                    Name = $var.Name
                    Type = $var.Type
                    Count = $var.Count
                    SizeKB = $var.JSONSizeKB
                }
            }
        }

        # Add hashtables
        foreach ($ht in $hashtableStats) {
            if ($ht.JSONSizeKB -is [double]) {
                $exportData += [PSCustomObject]@{
                    Category = "Hashtable"
                    Name = $ht.Name
                    Type = $ht.Type
                    Count = $ht.Count
                    SizeKB = $ht.JSONSizeKB
                }
            }
        }

        $exportData | Export-Csv -Path $csvPath -NoTypeInformation
        Write-Output "CSV exported to: $csvPath"
    }
    catch {
        Write-Output "Failed to export CSV: $($_.Exception.Message)"
    }
}
