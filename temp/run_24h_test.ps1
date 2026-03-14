$script = Get-Content -Raw -Path 'C:\SC\PsWebHost\temp\test_24h_performance.js'
$result = & 'C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1' -Command $script -Type eval -Wait -TimeoutSeconds 60

Write-Host "`n=== Performance Test Results ===" -ForegroundColor Cyan
if ($result.Result) {
    $parsed = $result.Result | ConvertFrom-Json

    Write-Host "`nQuery Performance:" -ForegroundColor Yellow
    foreach ($key in @('24h', '24h@1m', '1h')) {
        $perf = $parsed.performance.$key
        $color = if ($perf.time -lt 500) { 'Green' } elseif ($perf.time -lt 1000) { 'Yellow' } else { 'Red' }
        Write-Host "  $key`: $($perf.time.ToString('F0'))ms ($($perf.lines) lines)" -ForegroundColor $color
    }

    Write-Host "`nDetails:" -ForegroundColor Cyan
    $parsed.results | ForEach-Object { Write-Host "  $_" }
} else {
    $result | Format-List
}
