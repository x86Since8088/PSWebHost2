$csvDir = "C:\SC\PsWebHost\PsWebHost_Data\metrics"
$startTime = (Get-Date).AddHours(-1)
$endTime = Get-Date
Write-Host "Time range: $startTime to $endTime"
Write-Host "Start date: $($startTime.Date)"
Write-Host "End date: $($endTime.Date)"

$dailyFiles = Get-ChildItem -Path $csvDir -Filter "metrics_*.csv" | Where-Object {
    if ($_.BaseName -match 'metrics_(\d{4}-\d{2}-\d{2})$') {
        $fileDate = [datetime]::Parse($matches[1])
        Write-Host "  File: $($_.Name) -> Date: $fileDate -> $($fileDate.Date) vs $($startTime.Date)"
        return $fileDate.Date -ge $startTime.Date -and $fileDate.Date -le $endTime.Date
    }
    return $false
}
Write-Host "Daily files found: $($dailyFiles.Count)"
$dailyFiles | ForEach-Object { Write-Host "  $($_.Name)" }

if ($dailyFiles) {
    Write-Host "`nReading first file..."
    $fileData = Import-Csv -Path $dailyFiles[0].FullName
    Write-Host "Rows in file: $($fileData.Count)"

    $colMapping = @{ ValueColumn = 'Cpu_Avg'; MinColumn = 'Cpu_Min'; MaxColumn = 'Cpu_Max' }
    $matchedRows = 0
    foreach ($row in $fileData) {
        try {
            $rowTime = [datetime]::Parse($row.Timestamp)
            if ($rowTime -ge $startTime -and $rowTime -le $endTime) {
                $matchedRows++
            }
        } catch {}
    }
    Write-Host "Rows in time range: $matchedRows"
}
