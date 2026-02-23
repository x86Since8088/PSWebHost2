#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$MyTag = '[DebugExtensions:Commands:Result]'

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

    # Get session ID
    $currentSessionID = $sessiondata.SessionID

    # Support both ExecutionTime and ExecutionTimeMs for backwards compatibility
    $execTime = if ($resultData.ExecutionTimeMs) { $resultData.ExecutionTimeMs } else { $resultData.ExecutionTime }

    # Create result object
    $resultObj = @{
        CommandID = $resultData.CommandID
        SessionID = $currentSessionID
        UserID = $sessiondata.UserID
        Status = if ($resultData.Error) { 'failed' } else { 'completed' }
        CompletedAt = (Get-Date).ToString('o')
        CompletedTime = (Get-Date).ToString('o')  # Alias for utility scripts
        Result = $resultData.Result
        Error = $resultData.Error
        ExecutionTime = $execTime
        ExecutionTimeMs = $execTime
    }

    # Write to inbox folder
    $inboxRoot = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\apps\WebHostDebugExtensions\inbox"
    $sessionInbox = Join-Path $inboxRoot $currentSessionID

    if (-not (Test-Path $sessionInbox)) {
        New-Item -Path $sessionInbox -ItemType Directory -Force | Out-Null
    }

    $inboxFile = Join-Path $sessionInbox "$($resultObj.CommandID).json"
    $resultObj | ConvertTo-Json -Depth 10 | Out-File -FilePath $inboxFile -Encoding UTF8 -Force

    Write-PSWebHostLog -Severity 'Info' -Category 'DebugExtensions' -Message "$MyTag Command result written to inbox: $($resultObj.CommandID) | Status: $($resultObj.Status)"

    # Also maintain in-memory history for backward compatibility
    if ($Global:PSWebServer.DebugCommands -and $Global:PSWebServer.DebugCommands.History) {
        $Global:PSWebServer.DebugCommands.History.Add($resultObj)

        # Trim history if too large
        if ($Global:PSWebServer.DebugCommands.History.Count -gt $Global:PSWebServer.DebugCommands.MaxHistorySize) {
            $historyArray = $Global:PSWebServer.DebugCommands.History.ToArray() |
                Sort-Object CompletedAt -Descending |
                Select-Object -First $Global:PSWebServer.DebugCommands.MaxHistorySize

            $Global:PSWebServer.DebugCommands.History = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()
            foreach ($item in $historyArray) {
                $Global:PSWebServer.DebugCommands.History.Add($item)
            }
        }
    }

    $responseData = @{ status = 'success' } | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "$MyTag Error: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
