$script = Get-Content -Raw -Path 'C:\SC\PsWebHost\temp\test_full_chart.js'
$result = & 'C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1' -Command $script -Type eval -Wait -TimeoutSeconds 30

Write-Host "`nTest Results:" -ForegroundColor Cyan
if ($result.Result) {
    $parsed = $result.Result | ConvertFrom-Json
    Write-Host "API Response Time: $($parsed.apiTime.ToString('F0'))ms" -ForegroundColor $(if ($parsed.apiTime -lt 500) { 'Green' } else { 'Yellow' })
    Write-Host "Data Lines: $($parsed.lineCount)" -ForegroundColor Green
    Write-Host "`nDetails:" -ForegroundColor Cyan
    $parsed.results | ForEach-Object { Write-Host "  $_" }
} else {
    $result | Format-List
}
