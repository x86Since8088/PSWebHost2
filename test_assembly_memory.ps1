#Requires -Version 7

# Test script for Get-AssemblyMemory

Import-Module "$PSScriptRoot\modules\PSWebHost_MemoryAnalysis\PSWebHost_MemoryAnalysis.psd1" -Force

Write-Host "`n=== Test 1: Basic Assembly Enumeration ===" -ForegroundColor Cyan
$assemblies = Get-AssemblyMemory
Write-Host "Total Assemblies (excluding GAC): $($assemblies.Count)"

$top5 = $assemblies | Select-Object -First 5
foreach ($asm in $top5) {
    Write-Host "  - $($asm.Name) v$($asm.Version)"
    Write-Host "      Size: $([Math]::Round($asm.EstimatedSize / 1KB, 2)) KB"
    Write-Host "      Types: $($asm.TypeCount)"
    Write-Host "      Source: $(if ($asm.IsGAC) { 'GAC' } elseif ($asm.IsDynamic) { 'Dynamic' } else { 'Private' })"
}

Write-Host "`n=== Test 2: Include GAC Assemblies ===" -ForegroundColor Cyan
$allAssemblies = Get-AssemblyMemory -IncludeGAC
Write-Host "Total Assemblies (including GAC): $($allAssemblies.Count)"

$gacCount = ($allAssemblies | Where-Object { $_.IsGAC }).Count
$privateCount = ($allAssemblies | Where-Object { -not $_.IsGAC -and -not $_.IsDynamic }).Count
$dynamicCount = ($allAssemblies | Where-Object { $_.IsDynamic }).Count

Write-Host "  GAC Assemblies: $gacCount"
Write-Host "  Private Assemblies: $privateCount"
Write-Host "  Dynamic Assemblies: $dynamicCount"

Write-Host "`n=== Test 3: Assembly Memory Summary ===" -ForegroundColor Cyan
$summary = Get-AssemblyMemorySummary -AssemblyData $assemblies
Write-Host "Summary Statistics:"
Write-Host "  Total Assemblies: $($summary.TotalAssemblies)"
Write-Host "  Total Estimated Size: $([Math]::Round($summary.TotalEstimatedSize / 1MB, 2)) MB"
Write-Host "  Total File Size: $([Math]::Round($summary.TotalFileSize / 1MB, 2)) MB"
Write-Host "  Total Types: $($summary.TotalTypes)"
Write-Host "  Average Size: $([Math]::Round($summary.AverageSize / 1KB, 2)) KB"
Write-Host ""
Write-Host "Size Distribution:"
foreach ($range in $summary.SizeDistribution.Keys | Sort-Object) {
    Write-Host "  $($range.PadRight(15)) : $($summary.SizeDistribution[$range]) assemblies"
}

Write-Host "`n=== Test 4: Top Largest Assemblies ===" -ForegroundColor Cyan
Write-Host "Top 10 Largest Assemblies:"
foreach ($asm in $summary.TopLargest) {
    $sizeMB = [Math]::Round($asm.EstimatedSize / 1MB, 2)
    Write-Host "  $($asm.Name.PadRight(40)) : $sizeMB MB ($($asm.TypeCount) types)"
}

Write-Host "`n=== Test 5: Detailed Type Analysis ===" -ForegroundColor Cyan
Write-Host "Analyzing assemblies with detailed type information..."
$detailedAssemblies = Get-AssemblyMemory -IncludeTypeDetails -MinimumSize 100KB | Select-Object -First 5
foreach ($asm in $detailedAssemblies) {
    Write-Host ""
    Write-Host "Assembly: $($asm.Name)"
    Write-Host "  Types: $($asm.TypeCount)"
    Write-Host "  Methods: $($asm.MethodCount)"
    Write-Host "  Fields: $($asm.FieldCount)"
    Write-Host "  Properties: $($asm.PropertyCount)"
    Write-Host "  Events: $($asm.EventCount)"
    Write-Host "  Size: $([Math]::Round($asm.EstimatedSize / 1KB, 2)) KB"
}

Write-Host "`n=== Test 6: Streaming Callback ===" -ForegroundColor Cyan
$streamCount = 0
$streamCallback = {
    param($AssemblyInfo)
    $script:streamCount++
    if ($script:streamCount -le 5) {
        $sizeKB = [Math]::Round($AssemblyInfo.EstimatedSize / 1KB, 2)
        Write-Host "  Stream [$script:streamCount]: $($AssemblyInfo.Name) = $sizeKB KB"
    }
}

$result = Get-AssemblyMemory -StreamCallback $streamCallback -MinimumSize 10KB
Write-Host "  Total assemblies streamed: $streamCount"

Write-Host "`n=== Test 7: Formatted Report ===" -ForegroundColor Cyan
$report = Format-AssemblyMemoryReport -AssemblyData $assemblies -IncludeSummary -IncludeTopN 10
Write-Host $report

Write-Host "`n=== Test 8: Filtering by Size ===" -ForegroundColor Cyan
$largeAssemblies = Get-AssemblyMemory -MinimumSize 1MB
Write-Host "Assemblies larger than 1 MB: $($largeAssemblies.Count)"
foreach ($asm in $largeAssemblies) {
    $sizeMB = [Math]::Round($asm.EstimatedSize / 1MB, 2)
    Write-Host "  - $($asm.Name): $sizeMB MB"
}

Write-Host "`n=== Test 9: Sorting Options ===" -ForegroundColor Cyan
Write-Host "Sort by Name (first 5):"
$byName = Get-AssemblyMemory -SortBy Name | Select-Object -First 5
foreach ($asm in $byName) {
    Write-Host "  - $($asm.Name)"
}

Write-Host ""
Write-Host "Sort by Type Count (top 5):"
$byTypes = Get-AssemblyMemory -SortBy TypeCount | Select-Object -First 5
foreach ($asm in $byTypes) {
    Write-Host "  - $($asm.Name): $($asm.TypeCount) types"
}

Write-Host "`n=== All Tests Complete ===" -ForegroundColor Green
