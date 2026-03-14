$csvDir = "C:\SC\PsWebHost\PsWebHost_Data\metrics"
$startTime = (Get-Date).AddHours(-1)
$endTime = Get-Date
$metricName = 'cpu'

Write-Host "Time range: $startTime to $endTime"

$dailyMetricColumns = @{
    'cpu' = @{ ValueColumn = 'Cpu_Avg'; MinColumn = 'Cpu_Min'; MaxColumn = 'Cpu_Max' }
}

$colMapping = $dailyMetricColumns[$metricName]
Write-Host "ColMapping: ValueColumn=$($colMapping.ValueColumn), MinColumn=$($colMapping.MinColumn), MaxColumn=$($colMapping.MaxColumn)"

$fileData = Import-Csv -Path "$csvDir\metrics_2026-02-25.csv"
Write-Host "Total rows: $($fileData.Count)"

$matchedRows = 0
$failedParse = 0
$outOfRange = 0
$emptyValue = 0

foreach ($row in $fileData) {
    try {
        $rowTime = [datetime]::Parse($row.Timestamp)

        if ($rowTime -lt $startTime -or $rowTime -gt $endTime) {
            $outOfRange++
            continue
        }

        $percentAvg = $row.($colMapping.ValueColumn)

        if ([string]::IsNullOrWhiteSpace($percentAvg)) {
            $emptyValue++
            continue
        }

        $matchedRows++
    }
    catch {
        $failedParse++
    }
}

Write-Host ""
Write-Host "Results:"
Write-Host "  Matched rows: $matchedRows"
Write-Host "  Out of range: $outOfRange"
Write-Host "  Empty value: $emptyValue"
Write-Host "  Failed parse: $failedParse"

# Test column access directly
Write-Host ""
Write-Host "Testing column access on first row:"
$firstRow = $fileData[0]
Write-Host "  Columns available: $($firstRow.PSObject.Properties.Name -join ', ')"
Write-Host "  Direct Cpu_Avg: '$($firstRow.Cpu_Avg)'"
Write-Host "  Via colMapping: '$($firstRow.($colMapping.ValueColumn))'"
