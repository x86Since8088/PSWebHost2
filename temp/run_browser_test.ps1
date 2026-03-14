# Run browser test
$script = Get-Content -Raw -Path 'C:\SC\PsWebHost\temp\test_metrics_e2e.js'
$result = & 'C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1' -Command $script -Type eval -Wait -TimeoutSeconds 120
$result | Format-List
if ($result.Result) {
    Write-Host "`nResult content:" -ForegroundColor Cyan
    $result.Result | ConvertTo-Json -Depth 5
}
