#Requires -Version 7

<#
.SYNOPSIS
    Generates periodic memory analysis reports with trend comparison

.DESCRIPTION
    Analyzes all saved memory analysis job results and generates:
    - Trend analysis (memory growth/decline over time)
    - Comparison between time periods
    - Anomaly detection (sudden spikes)
    - Summary statistics

.PARAMETER Days
    Number of days to include in report (default: 7)

.PARAMETER ExportPath
    Path to export report (default: PsWebHost_Data/reports/)

.PARAMETER Format
    Report format: Text, JSON, CSV, or HTML (default: Text)

.EXAMPLE
    .\Generate-MemoryAnalysisReport.ps1 -Days 7 -Format HTML
#>

[CmdletBinding()]
param(
    [int]$Days = 7,
    [string]$ExportPath,
    [ValidateSet('Text', 'JSON', 'CSV', 'HTML')]
    [string]$Format = 'Text'
)

$ErrorActionPreference = 'Stop'

# Get project root and data directory
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataRoot = Join-Path $projectRoot "PsWebHost_Data"
$resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"

Write-Host "`n=== Memory Analysis Report Generator ===" -ForegroundColor Cyan
Write-Host "Report Period: Last $Days days" -ForegroundColor Gray
Write-Host "Results Directory: $resultsDir" -ForegroundColor Gray
Write-Host ""

# Load all job results
if (-not (Test-Path $resultsDir)) {
    Write-Host "ERROR: Results directory not found: $resultsDir" -ForegroundColor Red
    exit 1
}

$allResults = Get-ChildItem -Path $resultsDir -Filter "*.json" -File | ForEach-Object {
    try {
        $content = Get-Content $_.FullName -Raw | ConvertFrom-Json
        $content | Add-Member -NotePropertyName FilePath -NotePropertyValue $_.FullName -PassThru
    } catch {
        Write-Warning "Failed to read: $($_.FullName)"
        $null
    }
} | Where-Object { $_ -ne $null }

Write-Host "Total job results found: $($allResults.Count)" -ForegroundColor Cyan

# Filter to memory analysis jobs only
$memoryResults = $allResults | Where-Object {
    $_.JobName -like "*MemoryAnalysis*" -and
    $_.Success -eq $true
}

Write-Host "Successful memory analysis jobs: $($memoryResults.Count)" -ForegroundColor Cyan

if ($memoryResults.Count -eq 0) {
    Write-Host "`nNo successful memory analysis results found." -ForegroundColor Yellow
    Write-Host "Run memory analysis jobs first using:" -ForegroundColor Gray
    Write-Host "  .\Test-MemoryAnalysisWorkflow.ps1" -ForegroundColor White
    exit 0
}

# Filter by date range
$cutoffDate = (Get-Date).AddDays(-$Days)
$recentResults = $memoryResults | Where-Object {
    [datetime]$_.DateStarted -gt $cutoffDate
} | Sort-Object DateStarted

Write-Host "Results in last $Days days: $($recentResults.Count)" -ForegroundColor Cyan
Write-Host ""

if ($recentResults.Count -eq 0) {
    Write-Host "No results in the last $Days days." -ForegroundColor Yellow
    exit 0
}

# Parse memory metrics from output
function Parse-MemoryMetrics {
    param([string]$Output)

    $metrics = @{
        WorkingSetMB = $null
        PrivateMemoryMB = $null
        GCTotalMemoryMB = $null
        Gen0Collections = $null
        Gen1Collections = $null
        Gen2Collections = $null
        Threads = $null
        Handles = $null
    }

    if ($Output -match "Working Set \(MB\)\s*:\s*([\d\.]+)") {
        $metrics.WorkingSetMB = [double]$matches[1]
    }
    if ($Output -match "Private Memory \(MB\)\s*:\s*([\d\.]+)") {
        $metrics.PrivateMemoryMB = [double]$matches[1]
    }
    if ($Output -match "GC Total Memory \(MB\)\s*:\s*([\d\.]+)") {
        $metrics.GCTotalMemoryMB = [double]$matches[1]
    }
    if ($Output -match "Gen 0 Collections\s*:\s*(\d+)") {
        $metrics.Gen0Collections = [int]$matches[1]
    }
    if ($Output -match "Gen 1 Collections\s*:\s*(\d+)") {
        $metrics.Gen1Collections = [int]$matches[1]
    }
    if ($Output -match "Gen 2 Collections\s*:\s*(\d+)") {
        $metrics.Gen2Collections = [int]$matches[1]
    }
    if ($Output -match "Threads\s*:\s*(\d+)") {
        $metrics.Threads = [int]$matches[1]
    }
    if ($Output -match "Handles\s*:\s*(\d+)") {
        $metrics.Handles = [int]$matches[1]
    }

    return $metrics
}

# Extract metrics from each result
$metricsData = $recentResults | ForEach-Object {
    $metrics = Parse-MemoryMetrics -Output $_.Output

    [PSCustomObject]@{
        DateTime = [datetime]$_.DateStarted
        JobID = $_.JobID
        JobName = $_.JobName
        Runtime = $_.Runtime
        WorkingSetMB = $metrics.WorkingSetMB
        PrivateMemoryMB = $metrics.PrivateMemoryMB
        GCTotalMemoryMB = $metrics.GCTotalMemoryMB
        Gen0Collections = $metrics.Gen0Collections
        Gen1Collections = $metrics.Gen1Collections
        Gen2Collections = $metrics.Gen2Collections
        Threads = $metrics.Threads
        Handles = $metrics.Handles
    }
} | Where-Object { $_.WorkingSetMB -ne $null }

if ($metricsData.Count -eq 0) {
    Write-Host "No valid metrics found in job outputs." -ForegroundColor Yellow
    exit 0
}

# Calculate statistics
$stats = @{
    Count = $metricsData.Count
    FirstRun = $metricsData[0].DateTime
    LastRun = $metricsData[-1].DateTime

    WorkingSet = @{
        Min = ($metricsData.WorkingSetMB | Measure-Object -Minimum).Minimum
        Max = ($metricsData.WorkingSetMB | Measure-Object -Maximum).Maximum
        Avg = ($metricsData.WorkingSetMB | Measure-Object -Average).Average
        Current = $metricsData[-1].WorkingSetMB
    }

    PrivateMemory = @{
        Min = ($metricsData.PrivateMemoryMB | Measure-Object -Minimum).Minimum
        Max = ($metricsData.PrivateMemoryMB | Measure-Object -Maximum).Maximum
        Avg = ($metricsData.PrivateMemoryMB | Measure-Object -Average).Average
        Current = $metricsData[-1].PrivateMemoryMB
    }

    GCMemory = @{
        Min = ($metricsData.GCTotalMemoryMB | Measure-Object -Minimum).Minimum
        Max = ($metricsData.GCTotalMemoryMB | Measure-Object -Maximum).Maximum
        Avg = ($metricsData.GCTotalMemoryMB | Measure-Object -Average).Average
        Current = $metricsData[-1].GCTotalMemoryMB
    }

    Gen2Collections = @{
        First = $metricsData[0].Gen2Collections
        Last = $metricsData[-1].Gen2Collections
        Delta = $metricsData[-1].Gen2Collections - $metricsData[0].Gen2Collections
    }
}

# Calculate trends (comparing first half to second half)
$halfPoint = [math]::Floor($metricsData.Count / 2)
$firstHalf = $metricsData[0..($halfPoint-1)]
$secondHalf = $metricsData[$halfPoint..($metricsData.Count-1)]

$trends = @{
    WorkingSet = @{
        FirstHalfAvg = ($firstHalf.WorkingSetMB | Measure-Object -Average).Average
        SecondHalfAvg = ($secondHalf.WorkingSetMB | Measure-Object -Average).Average
    }
    PrivateMemory = @{
        FirstHalfAvg = ($firstHalf.PrivateMemoryMB | Measure-Object -Average).Average
        SecondHalfAvg = ($secondHalf.PrivateMemoryMB | Measure-Object -Average).Average
    }
}

$trends.WorkingSet.PercentChange = if ($trends.WorkingSet.FirstHalfAvg -gt 0) {
    (($trends.WorkingSet.SecondHalfAvg - $trends.WorkingSet.FirstHalfAvg) / $trends.WorkingSet.FirstHalfAvg) * 100
} else { 0 }

$trends.PrivateMemory.PercentChange = if ($trends.PrivateMemory.FirstHalfAvg -gt 0) {
    (($trends.PrivateMemory.SecondHalfAvg - $trends.PrivateMemory.FirstHalfAvg) / $trends.PrivateMemory.FirstHalfAvg) * 100
} else { 0 }

# Generate report based on format
switch ($Format) {
    'Text' {
        $report = @"

=== MEMORY ANALYSIS REPORT ===
Report Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Period: Last $Days days
Samples: $($stats.Count)
First Sample: $($stats.FirstRun.ToString('yyyy-MM-dd HH:mm:ss'))
Last Sample: $($stats.LastRun.ToString('yyyy-MM-dd HH:mm:ss'))

=== WORKING SET MEMORY ===
Current:  $($stats.WorkingSet.Current.ToString('N2')) MB
Minimum:  $($stats.WorkingSet.Min.ToString('N2')) MB
Maximum:  $($stats.WorkingSet.Max.ToString('N2')) MB
Average:  $($stats.WorkingSet.Avg.ToString('N2')) MB

=== PRIVATE MEMORY ===
Current:  $($stats.PrivateMemory.Current.ToString('N2')) MB
Minimum:  $($stats.PrivateMemory.Min.ToString('N2')) MB
Maximum:  $($stats.PrivateMemory.Max.ToString('N2')) MB
Average:  $($stats.PrivateMemory.Avg.ToString('N2')) MB

=== GC MANAGED MEMORY ===
Current:  $($stats.GCMemory.Current.ToString('N2')) MB
Minimum:  $($stats.GCMemory.Min.ToString('N2')) MB
Maximum:  $($stats.GCMemory.Max.ToString('N2')) MB
Average:  $($stats.GCMemory.Avg.ToString('N2')) MB

=== GC COLLECTIONS ===
Gen 2 (First):  $($stats.Gen2Collections.First)
Gen 2 (Last):   $($stats.Gen2Collections.Last)
Gen 2 (Delta):  $($stats.Gen2Collections.Delta)

=== TREND ANALYSIS ===
Working Set Trend:    $($trends.WorkingSet.PercentChange.ToString('+0.00;-0.00;0.00'))%
  First Half Avg:     $($trends.WorkingSet.FirstHalfAvg.ToString('N2')) MB
  Second Half Avg:    $($trends.WorkingSet.SecondHalfAvg.ToString('N2')) MB

Private Memory Trend: $($trends.PrivateMemory.PercentChange.ToString('+0.00;-0.00;0.00'))%
  First Half Avg:     $($trends.PrivateMemory.FirstHalfAvg.ToString('N2')) MB
  Second Half Avg:    $($trends.PrivateMemory.SecondHalfAvg.ToString('N2')) MB

=== RECOMMENDATIONS ===
"@

        # Add recommendations based on trends
        if ($trends.WorkingSet.PercentChange -gt 10) {
            $report += "`n[WARNING] Working Set increased by $($trends.WorkingSet.PercentChange.ToString('N2'))% - investigate memory growth"
        }
        elseif ($trends.WorkingSet.PercentChange -lt -10) {
            $report += "`n[INFO] Working Set decreased by $([math]::Abs($trends.WorkingSet.PercentChange).ToString('N2'))% - memory usage improving"
        }

        if ($stats.WorkingSet.Current -gt 1024) {
            $report += "`n[WARNING] Current working set ($($stats.WorkingSet.Current.ToString('N2')) MB) exceeds 1 GB"
        }

        if ($stats.Gen2Collections.Delta -gt 100) {
            $report += "`n[WARNING] High Gen2 collection rate ($($stats.Gen2Collections.Delta) collections) - possible memory pressure"
        }

        if ($trends.WorkingSet.PercentChange -ge -5 -and $trends.WorkingSet.PercentChange -le 5) {
            $report += "`n[OK] Memory usage is stable"
        }

        $report += "`n"
        $report += "`n=== DETAILED HISTORY ==="
        $report += "`n"
        $report += ($metricsData | Format-Table -Property DateTime, WorkingSetMB, PrivateMemoryMB, GCTotalMemoryMB, Gen2Collections -AutoSize | Out-String)

        Write-Host $report

        # Export if path specified
        if ($ExportPath) {
            $reportFile = Join-Path $ExportPath "MemoryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            $report | Set-Content -Path $reportFile
            Write-Host "Report exported to: $reportFile" -ForegroundColor Green
        }
    }

    'JSON' {
        $reportData = @{
            Generated = Get-Date -Format 'o'
            Period = "$Days days"
            Statistics = $stats
            Trends = $trends
            DetailedMetrics = $metricsData
        }

        $json = $reportData | ConvertTo-Json -Depth 10

        if ($ExportPath) {
            $reportFile = Join-Path $ExportPath "MemoryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
            $json | Set-Content -Path $reportFile
            Write-Host "Report exported to: $reportFile" -ForegroundColor Green
        } else {
            Write-Host $json
        }
    }

    'CSV' {
        if ($ExportPath) {
            $reportFile = Join-Path $ExportPath "MemoryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
            $metricsData | Export-Csv -Path $reportFile -NoTypeInformation
            Write-Host "Report exported to: $reportFile" -ForegroundColor Green
        } else {
            $metricsData | Format-Table -AutoSize | Out-String | Write-Host
        }
    }

    'HTML' {
        $trend_color = if ($trends.WorkingSet.PercentChange -gt 10) { 'red' } elseif ($trends.WorkingSet.PercentChange -lt -5) { 'green' } else { 'orange' }

        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>Memory Analysis Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #2c3e50; border-bottom: 3px solid #3498db; padding-bottom: 10px; }
        h2 { color: #34495e; margin-top: 30px; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 15px; margin: 20px 0; }
        .metric-card { background: #ecf0f1; padding: 15px; border-radius: 5px; border-left: 4px solid #3498db; }
        .metric-card h3 { margin: 0 0 10px 0; color: #2c3e50; font-size: 14px; }
        .metric-value { font-size: 24px; font-weight: bold; color: #2980b9; }
        .metric-label { font-size: 12px; color: #7f8c8d; margin-top: 5px; }
        .trend { padding: 15px; margin: 20px 0; border-radius: 5px; background: #e8f4f8; border-left: 4px solid $trend_color; }
        .warning { background: #fee; border-left-color: #c00; }
        .info { background: #efe; border-left-color: #090; }
        table { width: 100%; border-collapse: collapse; margin: 20px 0; }
        th { background: #34495e; color: white; padding: 10px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
    </style>
</head>
<body>
    <div class="container">
        <h1>Memory Analysis Report</h1>
        <p><strong>Generated:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Period:</strong> Last $Days days ($($stats.Count) samples)</p>

        <h2>Current Memory Status</h2>
        <div class="metric-grid">
            <div class="metric-card">
                <h3>Working Set</h3>
                <div class="metric-value">$($stats.WorkingSet.Current.ToString('N2')) MB</div>
                <div class="metric-label">Min: $($stats.WorkingSet.Min.ToString('N2')) | Max: $($stats.WorkingSet.Max.ToString('N2')) | Avg: $($stats.WorkingSet.Avg.ToString('N2'))</div>
            </div>
            <div class="metric-card">
                <h3>Private Memory</h3>
                <div class="metric-value">$($stats.PrivateMemory.Current.ToString('N2')) MB</div>
                <div class="metric-label">Min: $($stats.PrivateMemory.Min.ToString('N2')) | Max: $($stats.PrivateMemory.Max.ToString('N2')) | Avg: $($stats.PrivateMemory.Avg.ToString('N2'))</div>
            </div>
            <div class="metric-card">
                <h3>GC Memory</h3>
                <div class="metric-value">$($stats.GCMemory.Current.ToString('N2')) MB</div>
                <div class="metric-label">Min: $($stats.GCMemory.Min.ToString('N2')) | Max: $($stats.GCMemory.Max.ToString('N2')) | Avg: $($stats.GCMemory.Avg.ToString('N2'))</div>
            </div>
            <div class="metric-card">
                <h3>Gen2 Collections</h3>
                <div class="metric-value">$($stats.Gen2Collections.Last)</div>
                <div class="metric-label">Delta: +$($stats.Gen2Collections.Delta) since first sample</div>
            </div>
        </div>

        <h2>Trend Analysis</h2>
        <div class="trend">
            <strong>Working Set Trend:</strong> $($trends.WorkingSet.PercentChange.ToString('+0.00;-0.00;0.00'))%<br>
            <small>First Half Avg: $($trends.WorkingSet.FirstHalfAvg.ToString('N2')) MB | Second Half Avg: $($trends.WorkingSet.SecondHalfAvg.ToString('N2')) MB</small>
        </div>

        <h2>Detailed History</h2>
        <table>
            <thead>
                <tr>
                    <th>Date Time</th>
                    <th>Working Set (MB)</th>
                    <th>Private (MB)</th>
                    <th>GC Memory (MB)</th>
                    <th>Gen2 Collections</th>
                </tr>
            </thead>
            <tbody>
"@
        foreach ($metric in $metricsData) {
            $html += @"
                <tr>
                    <td>$($metric.DateTime.ToString('yyyy-MM-dd HH:mm:ss'))</td>
                    <td>$($metric.WorkingSetMB.ToString('N2'))</td>
                    <td>$($metric.PrivateMemoryMB.ToString('N2'))</td>
                    <td>$($metric.GCTotalMemoryMB.ToString('N2'))</td>
                    <td>$($metric.Gen2Collections)</td>
                </tr>
"@
        }

        $html += @"
            </tbody>
        </table>
    </div>
</body>
</html>
"@

        if ($ExportPath) {
            $reportFile = Join-Path $ExportPath "MemoryReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
            $html | Set-Content -Path $reportFile
            Write-Host "Report exported to: $reportFile" -ForegroundColor Green
            Write-Host "Open in browser: file:///$($reportFile -replace '\\', '/')" -ForegroundColor Cyan
        } else {
            Write-Host $html
        }
    }
}

Write-Host "`n=== Report Generation Complete ===" -ForegroundColor Green
Write-Host ""
