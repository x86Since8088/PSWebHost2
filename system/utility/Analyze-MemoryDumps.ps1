# Analyze-MemoryDumps.ps1
# Automated analysis of all memory dumps in the dumps directory

<#
.SYNOPSIS
    Analyzes all memory dump files using the MemoryAnalyzer tool.

.DESCRIPTION
    Scans the dumps directory for .dmp files and runs comprehensive analysis
    on each one, exporting results to CSV and text logs.

.PARAMETER DumpDirectory
    Directory containing dump files. Default: C:\SC\PsWebHost\dumps

.PARAMETER AnalyzerPath
    Path to MemoryAnalyzer.exe. If not specified, will auto-detect or build.

.PARAMETER TopCount
    Number of top types to show. Default: 100

.PARAMETER SkipStrings
    Skip string analysis (faster for large dumps).

.PARAMETER CompareMode
    Compare multiple dumps to find growth patterns.

.EXAMPLE
    .\Analyze-MemoryDumps.ps1

    Analyze all dumps with default settings.

.EXAMPLE
    .\Analyze-MemoryDumps.ps1 -CompareMode

    Compare dumps to find memory growth patterns.

.EXAMPLE
    .\Analyze-MemoryDumps.ps1 -SkipStrings -TopCount 50

    Quick analysis skipping string analysis.
#>

[CmdletBinding()]
param(
    [string]$DumpDirectory = "C:\SC\PsWebHost\dumps",

    [string]$AnalyzerPath = "",

    [int]$TopCount = 100,

    [switch]$SkipStrings,

    [switch]$CompareMode
)

$ErrorActionPreference = 'Stop'

# Find or build MemoryAnalyzer
if ([string]::IsNullOrEmpty($AnalyzerPath)) {
    $possiblePaths = @(
        "C:\SC\PsWebHost\system\utility\MemoryAnalyzer\bin\Release\net8.0\MemoryAnalyzer.exe",
        "C:\SC\PsWebHost\system\utility\MemoryAnalyzer\bin\Debug\net8.0\MemoryAnalyzer.exe"
    )

    $AnalyzerPath = $possiblePaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if (-not $AnalyzerPath) {
        Write-Host "MemoryAnalyzer not found. Building..." -ForegroundColor Yellow
        $buildScript = "C:\SC\PsWebHost\system\utility\MemoryAnalyzer\build.ps1"

        if (Test-Path $buildScript) {
            & $buildScript
            $AnalyzerPath = $possiblePaths[0]
        }
        else {
            Write-Host "ERROR: Cannot find or build MemoryAnalyzer" -ForegroundColor Red
            Write-Host "Please run: cd C:\SC\PsWebHost\system\utility\MemoryAnalyzer; dotnet build -c Release" -ForegroundColor Yellow
            exit 1
        }
    }
}

if (-not (Test-Path $AnalyzerPath)) {
    Write-Host "ERROR: MemoryAnalyzer not found at: $AnalyzerPath" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Memory Dump Analysis ===" -ForegroundColor Cyan
Write-Host "Analyzer:  $AnalyzerPath" -ForegroundColor Gray
Write-Host "Directory: $DumpDirectory" -ForegroundColor Gray
Write-Host ""

# Create output directory
$outputDir = Join-Path $DumpDirectory "analysis"
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Find dumps
$dumps = Get-ChildItem -Path $DumpDirectory -Filter "*.dmp" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

if ($dumps.Count -eq 0) {
    Write-Host "No dump files found in $DumpDirectory" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $($dumps.Count) dump file(s)`n" -ForegroundColor Green

# Analyze each dump
$results = @()

foreach ($dump in $dumps) {
    Write-Host "=== Analyzing: $($dump.Name) ===" -ForegroundColor Cyan
    Write-Host "  Size: $([math]::Round($dump.Length / 1MB, 2)) MB" -ForegroundColor Gray
    Write-Host "  Created: $($dump.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($dump.Name)
    $csvPath = Join-Path $outputDir "${baseName}_analysis.csv"
    $logPath = Join-Path $outputDir "${baseName}_analysis.txt"

    # Build arguments
    $args = @($dump.FullName, "-top", $TopCount, "-hashtables", "-large", "85", "-export", $csvPath)

    if (-not $SkipStrings) {
        $args += "-strings"
    }

    try {
        $output = & $AnalyzerPath $args 2>&1

        # Save output to log file
        $output | Out-File -FilePath $logPath -Encoding UTF8

        Write-Host "  ✓ Analysis complete" -ForegroundColor Green
        Write-Host "    CSV: $csvPath" -ForegroundColor Gray
        Write-Host "    Log: $logPath" -ForegroundColor Gray

        # Extract key metrics from output
        $heapSize = ($output | Select-String "Total Heap Size:\s+(\d+\.\d+) MB").Matches.Groups[1].Value
        $objectCount = ($output | Select-String "Number of Objects:\s+([\d,]+)").Matches.Groups[1].Value

        $results += [PSCustomObject]@{
            DumpFile = $dump.Name
            CreationTime = $dump.CreationTime
            DumpSizeMB = [math]::Round($dump.Length / 1MB, 2)
            HeapSizeMB = if ($heapSize) { [double]$heapSize } else { 0 }
            ObjectCount = if ($objectCount) { [int]($objectCount -replace ',', '') } else { 0 }
            CSVPath = $csvPath
            LogPath = $logPath
        }
    }
    catch {
        Write-Host "  ✗ Analysis failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

# Show summary
Write-Host "=== Analysis Summary ===" -ForegroundColor Cyan
$results | Format-Table -Property DumpFile, CreationTime, DumpSizeMB, HeapSizeMB, ObjectCount -AutoSize

# Compare mode
if ($CompareMode -and $results.Count -gt 1) {
    Write-Host "`n=== Comparing Dumps for Growth Patterns ===" -ForegroundColor Cyan

    # Sort by creation time
    $sortedResults = $results | Sort-Object CreationTime

    for ($i = 1; $i -lt $sortedResults.Count; $i++) {
        $prev = $sortedResults[$i - 1]
        $curr = $sortedResults[$i]

        Write-Host "`n$($prev.DumpFile) → $($curr.DumpFile)" -ForegroundColor Yellow

        $heapGrowth = $curr.HeapSizeMB - $prev.HeapSizeMB
        $objectGrowth = $curr.ObjectCount - $prev.ObjectCount

        $heapColor = if ($heapGrowth -gt 100) { 'Red' } elseif ($heapGrowth -gt 10) { 'Yellow' } else { 'Green' }
        $objColor = if ($objectGrowth -gt 10000) { 'Red' } elseif ($objectGrowth -gt 1000) { 'Yellow' } else { 'Green' }

        Write-Host "  Heap Growth:   " -NoNewline
        Write-Host "$([math]::Round($heapGrowth, 2)) MB" -ForegroundColor $heapColor

        Write-Host "  Object Growth: " -NoNewline
        Write-Host "$($objectGrowth.ToString('N0')) objects" -ForegroundColor $objColor

        # Compare CSV files to find type growth
        if ((Test-Path $prev.CSVPath) -and (Test-Path $curr.CSVPath)) {
            $prevData = Import-Csv $prev.CSVPath
            $currData = Import-Csv $curr.CSVPath

            Write-Host "`n  Top Growing Types:" -ForegroundColor Cyan

            $growth = @{}

            foreach ($currType in $currData) {
                $prevType = $prevData | Where-Object { $_.TypeName -eq $currType.TypeName }

                if ($prevType) {
                    $countGrowth = [int]$currType.Count - [int]$prevType.Count
                    $sizeGrowth = [double]$currType.TotalSizeMB - [double]$prevType.TotalSizeMB

                    if ($countGrowth -gt 0) {
                        $growth[$currType.TypeName] = [PSCustomObject]@{
                            TypeName = $currType.TypeName
                            CountGrowth = $countGrowth
                            SizeGrowthMB = $sizeGrowth
                        }
                    }
                }
            }

            # Show top 10 growing types
            $growth.Values | Sort-Object SizeGrowthMB -Descending | Select-Object -First 10 | ForEach-Object {
                $color = if ($_.SizeGrowthMB -gt 10) { 'Red' } elseif ($_.SizeGrowthMB -gt 1) { 'Yellow' } else { 'White' }
                Write-Host "    $($_.TypeName)" -NoNewline -ForegroundColor $color
                Write-Host " : +$($_.CountGrowth.ToString('N0')) objects, +$([math]::Round($_.SizeGrowthMB, 2)) MB" -ForegroundColor $color
            }
        }
    }
}

# Summary CSV
$summaryPath = Join-Path $outputDir "analysis_summary.csv"
$results | Export-Csv -Path $summaryPath -NoTypeInformation

Write-Host "`n=== Complete ===" -ForegroundColor Green
Write-Host "Summary: $summaryPath" -ForegroundColor White
Write-Host "Analyzed $($results.Count) dump file(s)" -ForegroundColor White
Write-Host ""
