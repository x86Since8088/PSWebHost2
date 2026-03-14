$script = Get-Content -Raw -Path 'C:\SC\PsWebHost\temp\test_cache_integration.js'
$result = & 'C:\SC\PsWebHost\apps\WebHostDebugExtensions\system\utility\Debug_Client_Command_Enqueue.ps1' -Command $script -Type eval -Wait -TimeoutSeconds 30
if ($result.Result) {
    $result.Result
} else {
    $result | ConvertTo-Json -Depth 3
}
