# Test metrics initialization
$projectRoot = $PSScriptRoot
$appRoot = Join-Path $projectRoot "apps\WebHostMetrics"

Write-Host "Project Root: $projectRoot" -ForegroundColor Cyan
Write-Host "App Root: $appRoot" -ForegroundColor Cyan

try {
    . "$appRoot\app_init.ps1" -PSWebServer @{
        Project_Root = @{ Path = $projectRoot }
    } -AppRoot $appRoot

    Write-Host "`nInit completed successfully" -ForegroundColor Green

    Start-Sleep -Seconds 3

    if ($Global:PSWebServer.MetricsJob) {
        Write-Host "`nJob is running!" -ForegroundColor Green
        $Global:PSWebServer.MetricsJob | Format-List Id, Name, State

        Write-Host "`nJob output:" -ForegroundColor Cyan
        Receive-Job -Job $Global:PSWebServer.MetricsJob -Keep | Select-Object -Last 10

        Write-Host "`nMetrics JobState:" -ForegroundColor Cyan
        $Global:PSWebServer.Metrics.JobState
    } else {
        Write-Host "`nJob not found" -ForegroundColor Yellow
    }
} catch {
    Write-Host "`nInit failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Gray
}
