$csvDir = "C:\SC\PsWebHost\PsWebHost_Data\metrics"
$startTime = (Get-Date).AddHours(-1)
$endTime = Get-Date
$metricName = 'cpu'

Write-Host "Time range: $startTime to $endTime"

$dailyMetricColumns = @{
    'cpu' = @{ ValueColumn = 'Cpu_Avg'; MinColumn = 'Cpu_Min'; MaxColumn = 'Cpu_Max' }
    'memory' = @{ ValueColumn = 'Memory_PercentUsed_Avg'; MinColumn = 'Memory_PercentUsed_Min'; MaxColumn = 'Memory_PercentUsed_Max' }
}

$colMapping = $dailyMetricColumns[$metricName]
$csvContent = @()
$headerWritten = $false

$dailyFiles = Get-ChildItem -Path $csvDir -Filter "metrics_*.csv" | Where-Object {
    if ($_.BaseName -match 'metrics_(\d{4}-\d{2}-\d{2})$') {
        $fileDate = [datetime]::Parse($matches[1])
        return $fileDate.Date -ge $startTime.Date -and $fileDate.Date -le $endTime.Date
    }
    return $false
} | Sort-Object Name

Write-Host "Daily files found: $($dailyFiles.Count)"

if ($dailyFiles) {
    # Build CSV in the format expected by the client: Timestamp,Host,Percent_Avg
    $csvContent = @('"Timestamp","Host","Percent_Avg","Percent_Min","Percent_Max"')
    $headerWritten = $true

    foreach ($file in $dailyFiles) {
        Write-Host "Processing: $($file.Name)"
        $fileData = Import-Csv -Path $file.FullName -ErrorAction SilentlyContinue
        if (-not $fileData) {
            Write-Host "  No data imported"
            continue
        }
        Write-Host "  Rows in file: $($fileData.Count)"

        $matchedRows = 0
        foreach ($row in $fileData) {
            # Parse timestamp from daily file format: "2026-02-25 00:00:00"
            try {
                $rowTime = [datetime]::Parse($row.Timestamp)
                if ($rowTime -lt $startTime -or $rowTime -gt $endTime) { continue }

                # Transform to expected format: "2026-02-25_00-00-00"
                $formattedTimestamp = $rowTime.ToString('yyyy-MM-dd_HH-mm-ss')
                $hostName = $row.Hostname
                $percentAvg = $row.($colMapping.ValueColumn)
                $percentMin = $row.($colMapping.MinColumn)
                $percentMax = $row.($colMapping.MaxColumn)

                if ([string]::IsNullOrWhiteSpace($percentAvg)) { continue }

                $csvContent += "`"$formattedTimestamp`",`"$hostName`",`"$percentAvg`",`"$percentMin`",`"$percentMax`""
                $matchedRows++
            }
            catch {
                # Skip rows with invalid timestamps
                continue
            }
        }
        Write-Host "  Matched rows: $matchedRows"
    }
}

Write-Host "`nTotal csvContent lines: $($csvContent.Count)"
if ($csvContent.Count -gt 1) {
    Write-Host "First 5 lines:"
    $csvContent | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
}
