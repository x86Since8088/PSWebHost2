# Check metrics collection status
Write-Host "Waiting 8 seconds for metrics collection..." -ForegroundColor Cyan
Start-Sleep -Seconds 8

if ($Global:PSWebServer.MetricsJob) {
    Write-Host "`nJob State:" -ForegroundColor Yellow
    $Global:PSWebServer.MetricsJob | Format-List Id, Name, State

    Write-Host "`nJob output (last 20 lines):" -ForegroundColor Yellow
    Receive-Job -Job $Global:PSWebServer.MetricsJob -Keep 2>&1 | Select-Object -Last 20

    Write-Host "`nCurrent metrics:" -ForegroundColor Yellow
    $Global:PSWebServer.Metrics.Current | Format-List Timestamp, Hostname

    Write-Host "`nSample count:" $Global:PSWebServer.Metrics.Samples.Count -ForegroundColor Yellow

    Write-Host "`nJobState errors:" $Global:PSWebServer.Metrics.JobState.Errors.Count -ForegroundColor Yellow

    if ($Global:PSWebServer.Metrics.JobState.Errors.Count -gt 0) {
        Write-Host "`nRecent errors:" -ForegroundColor Red
        $Global:PSWebServer.Metrics.JobState.Errors | Select-Object -Last 3 | Format-List
    }
} else {
    Write-Host "No metrics job found" -ForegroundColor Red
}
