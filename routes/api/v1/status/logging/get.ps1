param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response
)

$status = @{
    LoggingJobPresent = $false;
    LoggingJobState = $null;
    LoggingJobHadErrors = $false;
    LoggingJobErrors = @();
    LogQueueCount = $null;
    Error = $null;
}

try {
    if ($global:PSWebServer.LoggingJob) {
        $status.LoggingJobPresent = $true
        $status.LoggingJobState = $global:PSWebServer.LoggingJob.State.ToString()
    }

    if ($global:LoggingPS) {
        $status.LoggingJobHadErrors = $global:LoggingPS.HadErrors
        if ($global:LoggingPS.HadErrors) {
            $status.LoggingJobErrors = $global:LoggingPS.Streams.Error | ForEach-Object { $_.ToString() }
        }
    }

    if ($global:PSWebHostLogQueue) {
        $status.LogQueueCount = $global:PSWebHostLogQueue.Count
    }

} catch {
    $status.Error = $_.Exception.Message
}

$responseString = $status | ConvertTo-Json -Depth 5
context_response -Response $Response -String $responseString -ContentType "application/json"