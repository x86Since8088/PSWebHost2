# Analyze-LiveMemory.ps1
# Analyzes memory usage of the current PowerShell process in real-time
# This runs WITHIN the webserver environment for live analysis

<#
.SYNOPSIS
    Analyzes memory usage of the current PowerShell process without requiring dumps.

.DESCRIPTION
    This script analyzes memory consumption by examining:
    - .NET GC heap statistics
    - Global variable sizes
    - Hashtable contents and sizes
    - String duplication
    - Large objects in memory

    Unlike dump-based analysis, this runs live within the process and can
    directly inspect PowerShell variables.

.PARAMETER ExportPath
    Optional path to export detailed analysis to CSV.

.PARAMETER Deep
    Perform deep analysis of hashtable and array contents.

.PARAMETER TopCount
    Number of top items to show in each category. Default: 20

.EXAMPLE
    .\Analyze-LiveMemory.ps1

    Quick memory analysis of current process.

.EXAMPLE
    .\Analyze-LiveMemory.ps1 -Deep -ExportPath "memory_analysis.csv"

    Deep analysis with CSV export.

.EXAMPLE
    .\Analyze-LiveMemory.ps1 -TopCount 50

    Show top 50 items in each category.
#>

[CmdletBinding()]
param(
    [string]$ExportPath,

    [switch]$Deep,

    [int]$TopCount = 20
)

$ErrorActionPreference = 'Continue'

Write-Host "`n=== Live Memory Analysis ===" -ForegroundColor Cyan
Write-Host "Process ID: $PID" -ForegroundColor Gray
Write-Host "Analysis Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# ===========================================================================
# Section 1: GC Heap Statistics
# ===========================================================================

Write-Host "=== GC Heap Statistics ===" -ForegroundColor Yellow

$proc = Get-Process -Id $PID
$gcTotalMemory = [GC]::GetTotalMemory($false)

[PSCustomObject]@{
    "Working Set (MB)" = [math]::Round($proc.WorkingSet64 / 1MB, 2)
    "Private Memory (MB)" = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
    "Virtual Memory (MB)" = [math]::Round($proc.VirtualMemorySize64 / 1MB, 2)
    "GC Total Memory (MB)" = [math]::Round($gcTotalMemory / 1MB, 2)
    "Gen 0 Collections" = [GC]::CollectionCount(0)
    "Gen 1 Collections" = [GC]::CollectionCount(1)
    "Gen 2 Collections" = [GC]::CollectionCount(2)
    "Threads" = $proc.Threads.Count
    "Handles" = $proc.HandleCount
} | Format-List

# ===========================================================================
# Section 2: Global Variables Analysis
# ===========================================================================

Write-Host "`n=== Global Variable Sizes ===" -ForegroundColor Yellow

$globalVars = Get-Variable -Scope Global | ForEach-Object {
    $varName = $_.Name
    $value = $_.Value

    try {
        # Get type
        $typeName = if ($value) { $value.GetType().Name } else { "null" }

        # Get count for collections
        $count = if ($value -is [System.Collections.ICollection]) { $value.Count } else { "N/A" }

        # Try to measure JSON size with timeout
        $jsonSize = "N/A"
        $job = Start-Job -ScriptBlock {
            param($Val)
            try {
                ($Val | ConvertTo-Json -Depth 5 -Compress).Length
            }
            catch {
                -1
            }
        } -ArgumentList $value

        $completed = Wait-Job -Job $job -Timeout 2
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
            JSONSizeBytes = $jsonSize
            JSONSizeKB = if ($jsonSize -is [int]) { [math]::Round($jsonSize / 1KB, 2) } else { $jsonSize }
        }
    }
    catch {
        [PSCustomObject]@{
            Name = $varName
            Type = "ERROR"
            Count = "N/A"
            JSONSizeBytes = "ERROR"
            JSONSizeKB = "ERROR"
        }
    }
}

# Show top variables by size
$globalVars |
    Where-Object { $_.JSONSizeBytes -is [int] } |
    Sort-Object JSONSizeBytes -Descending |
    Select-Object -First $TopCount |
    Format-Table -Property Name, Type, Count, JSONSizeKB -AutoSize

# ===========================================================================
# Section 3: Hashtable Analysis
# ===========================================================================

Write-Host "`n=== Hashtable Analysis ===" -ForegroundColor Yellow

$hashtables = Get-Variable -Scope Global | Where-Object {
    $_.Value -is [hashtable] -or $_.Value -is [System.Collections.IDictionary]
}

Write-Host "Found $($hashtables.Count) hashtables in global scope`n" -ForegroundColor Gray

$hashtableStats = foreach ($ht in $hashtables) {
    try {
        $value = $ht.Value
        $jsonSize = "N/A"

        # Try to measure
        $job = Start-Job -ScriptBlock {
            param($Val)
            try {
                ($Val | ConvertTo-Json -Depth 3 -Compress).Length
            }
            catch {
                -1
            }
        } -ArgumentList $value

        $completed = Wait-Job -Job $job -Timeout 2
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
    Format-Table -AutoSize

# ===========================================================================
# Section 4: String Analysis (if Deep mode)
# ===========================================================================

if ($Deep) {
    Write-Host "`n=== String Analysis (Deep Mode) ===" -ForegroundColor Yellow
    Write-Host "Analyzing strings in global variables..." -ForegroundColor Gray

    $strings = @{}
    $totalStrings = 0

    function Analyze-Object {
        param($obj, $depth = 0)

        if ($depth -gt 3) { return }

        if ($obj -is [string]) {
            $script:totalStrings++
            $key = if ($obj.Length -gt 100) { $obj.Substring(0, 100) } else { $obj }

            if (-not $script:strings.ContainsKey($key)) {
                $script:strings[$key] = 0
            }
            $script:strings[$key]++
        }
        elseif ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
            foreach ($item in $obj) {
                Analyze-Object -obj $item -depth ($depth + 1)
            }
        }
        elseif ($obj -is [hashtable] -or $obj -is [System.Collections.IDictionary]) {
            foreach ($key in $obj.Keys) {
                Analyze-Object -obj $key -depth ($depth + 1)
                Analyze-Object -obj $obj[$key] -depth ($depth + 1)
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

    Write-Host "Total Strings Found: $($totalStrings.ToString('N0'))" -ForegroundColor White
    Write-Host "Unique Strings: $($strings.Count.ToString('N0'))" -ForegroundColor White
    if ($totalStrings -gt 0) {
        $dupRate = (1.0 - ($strings.Count / $totalStrings)) * 100
        $color = if ($dupRate -gt 70) { 'Red' } elseif ($dupRate -gt 50) { 'Yellow' } else { 'Green' }
        Write-Host "Duplication Rate: " -NoNewline
        Write-Host "$($dupRate.ToString('F2'))%" -ForegroundColor $color
    }

    Write-Host "`nTop $TopCount Duplicated Strings:" -ForegroundColor Gray
    $strings.GetEnumerator() |
        Sort-Object Value -Descending |
        Select-Object -First $TopCount |
        ForEach-Object {
            $displayStr = $_.Key -replace "`r", "\r" -replace "`n", "\n"
            if ($displayStr.Length -gt 50) {
                $displayStr = $displayStr.Substring(0, 47) + "..."
            }
            $color = if ($_.Value -gt 1000) { 'Red' } elseif ($_.Value -gt 100) { 'Yellow' } else { 'White' }
            Write-Host "  $($_.Value.ToString().PadLeft(6)) x " -NoNewline -ForegroundColor $color
            Write-Host $displayStr -ForegroundColor Gray
        }
}

# ===========================================================================
# Section 5: PSWebServer Specific Analysis
# ===========================================================================

if ($Global:PSWebServer) {
    Write-Host "`n=== PSWebServer Specific Analysis ===" -ForegroundColor Yellow

    # Analyze PSWebServer hashtable
    if ($Global:PSWebServer -is [hashtable]) {
        Write-Host "`nPSWebServer Keys:" -ForegroundColor Gray

        foreach ($key in ($Global:PSWebServer.Keys | Sort-Object)) {
            $value = $Global:PSWebServer[$key]
            $typeName = if ($value) { $value.GetType().Name } else { "null" }
            $count = if ($value -is [System.Collections.ICollection]) { $value.Count } else { "N/A" }

            Write-Host "  $key" -NoNewline -ForegroundColor White
            Write-Host " [$typeName]" -NoNewline -ForegroundColor Gray
            if ($count -ne "N/A") {
                Write-Host " (Count: $count)" -ForegroundColor Gray
            }
            else {
                Write-Host ""
            }
        }
    }

    # Analyze Apps
    if ($Global:PSWebServer.Apps) {
        Write-Host "`nLoaded Apps: $($Global:PSWebServer.Apps.Count)" -ForegroundColor Gray
        $Global:PSWebServer.Apps.Keys | Sort-Object | ForEach-Object {
            Write-Host "  - $_" -ForegroundColor Gray
        }
    }

    # Analyze Metrics
    if ($Global:PSWebServer.Metrics) {
        Write-Host "`nMetrics: $($Global:PSWebServer.Metrics.Count) entries" -ForegroundColor Gray
    }

    # Analyze Sessions
    if ($Global:PSWebSessions) {
        Write-Host "`nActive Sessions: $($Global:PSWebSessions.Count)" -ForegroundColor Gray
    }

    # Analyze LogHistory
    if ($Global:LogHistory) {
        Write-Host "Log History Entries: $($Global:LogHistory.Count)" -ForegroundColor Gray
    }
}

# ===========================================================================
# Section 6: Export to CSV
# ===========================================================================

if ($ExportPath) {
    Write-Host "`n=== Exporting Analysis ===" -ForegroundColor Yellow

    $exportData = @()

    # Add global variables
    foreach ($var in $globalVars) {
        $exportData += [PSCustomObject]@{
            Category = "GlobalVariable"
            Name = $var.Name
            Type = $var.Type
            Count = $var.Count
            SizeBytes = if ($var.JSONSizeBytes -is [int]) { $var.JSONSizeBytes } else { 0 }
            SizeKB = if ($var.JSONSizeKB -is [double]) { $var.JSONSizeKB } else { 0 }
        }
    }

    # Add hashtables
    foreach ($ht in $hashtableStats) {
        $exportData += [PSCustomObject]@{
            Category = "Hashtable"
            Name = $ht.Name
            Type = $ht.Type
            Count = $ht.Count
            SizeBytes = if ($ht.JSONSizeKB -is [double]) { $ht.JSONSizeKB * 1024 } else { 0 }
            SizeKB = if ($ht.JSONSizeKB -is [double]) { $ht.JSONSizeKB } else { 0 }
        }
    }

    $exportData | Export-Csv -Path $ExportPath -NoTypeInformation

    Write-Host "✓ Analysis exported to: $ExportPath" -ForegroundColor Green
}

# ===========================================================================
# Section 7: Recommendations
# ===========================================================================

Write-Host "`n=== Recommendations ===" -ForegroundColor Yellow

$recommendations = @()

# Check for large hashtables
$largeHashtables = $hashtableStats | Where-Object { $_.JSONSizeKB -is [double] -and $_.JSONSizeKB -gt 1024 }
if ($largeHashtables) {
    $recommendations += "⚠ Found $($largeHashtables.Count) hashtable(s) larger than 1MB - consider cleanup"
}

# Check string duplication
if ($Deep -and $totalStrings -gt 0) {
    $dupRate = (1.0 - ($strings.Count / $totalStrings)) * 100
    if ($dupRate -gt 70) {
        $recommendations += "⚠ High string duplication rate ($($dupRate.ToString('F2'))%) - consider string interning"
    }
}

# Check GC Gen2 collections
$gen2 = [GC]::CollectionCount(2)
if ($gen2 -gt 100) {
    $recommendations += "⚠ High Gen2 collection count ($gen2) - may indicate memory pressure"
}

# Check working set
$wsMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
if ($wsMB -gt 1024) {
    $recommendations += "⚠ Working set is ${wsMB}MB - consider capturing dump for offline analysis"
}

if ($recommendations.Count -eq 0) {
    Write-Host "✓ No issues detected" -ForegroundColor Green
}
else {
    foreach ($rec in $recommendations) {
        Write-Host $rec -ForegroundColor Yellow
    }
}

Write-Host "`n=== Analysis Complete ===" -ForegroundColor Cyan
Write-Host ""
