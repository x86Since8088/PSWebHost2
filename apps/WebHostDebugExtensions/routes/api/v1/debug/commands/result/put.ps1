#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$MyTag = '[DebugExtensions:Commands:Result:PUT]'

try {
    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()

    $resultData = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $resultData.CommandID) {
        throw "Missing required field: CommandID"
    }

    # Create inbox directory if it doesn't exist
    # Use 'all' session ID since commands are typically broadcast
    $inboxRoot = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\apps\WebHostDebugExtensions\inbox"
    $sessionID = if ($sessiondata.SessionID) { $sessiondata.SessionID } else { "all" }
    $resultsDir = Join-Path $inboxRoot $sessionID

    if (-not (Test-Path $resultsDir)) {
        New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
        Write-PSWebHostLog -Severity 'Info' -Category 'DebugExtensions' -Message "Created inbox directory: $resultsDir"
    }

    # Support both ExecutionTime and ExecutionTimeMs
    $execTime = if ($resultData.ExecutionTimeMs) { $resultData.ExecutionTimeMs } else { $resultData.ExecutionTime }

    # Create result object
    $resultObj = @{
        CommandID = $resultData.CommandID
        SessionID = $sessiondata.SessionID
        UserID = $sessiondata.UserID
        Status = if ($resultData.Error) { 'failed' } else { 'completed' }
        CompletedAt = (Get-Date).ToString('o')
        CompletedTime = (Get-Date).ToString('o')
        Result = $resultData.Result
        Error = $resultData.Error
        ExecutionTime = $execTime
        ExecutionTimeMs = $execTime
        SavedToDisk = $true
        FilePath = $null
    }

    # Generate safe filename from CommandID
    $safeFileName = "$($resultData.CommandID).json"
    $filePath = Join-Path $resultsDir $safeFileName
    $resultObj.FilePath = $filePath

    # Write to disk
    $resultObj | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Encoding UTF8

    # Also add to in-memory history for backwards compatibility
    $Global:PSWebServer.DebugCommands.History.Add($resultObj)

    # Trim history if too large (but keep disk files)
    if ($Global:PSWebServer.DebugCommands.History.Count -gt $Global:PSWebServer.DebugCommands.MaxHistorySize) {
        $historyArray = $Global:PSWebServer.DebugCommands.History.ToArray() |
            Sort-Object CompletedAt -Descending |
            Select-Object -First $Global:PSWebServer.DebugCommands.MaxHistorySize

        $Global:PSWebServer.DebugCommands.History = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
        foreach ($item in $historyArray) {
            $Global:PSWebServer.DebugCommands.History.Add($item)
        }
    }

    Write-PSWebHostLog -Severity 'Info' -Category 'DebugExtensions' -Message "Command result saved to disk: $($resultObj.CommandID) | Status: $($resultObj.Status) | File: $safeFileName"

    $responseData = @{
        status = 'success'
        saved = 'disk'
        filePath = $safeFileName
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "$MyTag Error: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
