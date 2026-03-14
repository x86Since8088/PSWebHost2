$data = Import-Csv 'C:\SC\PsWebHost\PsWebHost_Data\metrics\metrics_2026-02-25.csv'
Write-Host "Total rows: $($data.Count)"
Write-Host ""

$startTime = (Get-Date).AddHours(-1)
$endTime = Get-Date
Write-Host "Query range: $startTime to $endTime"
Write-Host ""

Write-Host "First 5 timestamps from file:"
$data | Select-Object -First 5 | ForEach-Object {
    Write-Host "  Raw: '$($_.Timestamp)'"
    try {
        $parsed = [datetime]::Parse($_.Timestamp)
        Write-Host "    Parsed: $parsed"
        Write-Host "    >= startTime: $($parsed -ge $startTime)"
        Write-Host "    <= endTime: $($parsed -le $endTime)"
    } catch {
        Write-Host "    PARSE ERROR: $($_.Exception.Message)"
    }
}

Write-Host ""
Write-Host "Last 5 timestamps from file:"
$data | Select-Object -Last 5 | ForEach-Object {
    Write-Host "  Raw: '$($_.Timestamp)'"
    try {
        $parsed = [datetime]::Parse($_.Timestamp)
        Write-Host "    Parsed: $parsed"
        Write-Host "    >= startTime: $($parsed -ge $startTime)"
        Write-Host "    <= endTime: $($parsed -le $endTime)"
    } catch {
        Write-Host "    PARSE ERROR: $($_.Exception.Message)"
    }
}
