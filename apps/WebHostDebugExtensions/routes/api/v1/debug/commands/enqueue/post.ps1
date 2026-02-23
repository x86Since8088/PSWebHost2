#Requires -Version 7

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

$MyTag = '[DebugExtensions:Commands:Enqueue]'

try {
    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()

    $commandData = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $commandData.Command) {
        throw "Missing required field: Command"
    }

    # Default values
    $type = if ($commandData.Type) { $commandData.Type } else { 'eval' }
    $targetSession = if ($commandData.SessionID) { $commandData.SessionID } else { $sessiondata.SessionID }
    $params = if ($commandData.Params) { $commandData.Params } else { @{} }

    # Create command object
    $commandObj = @{
        CommandID = [guid]::NewGuid().ToString()
        SessionID = $targetSession
        UserID = $sessiondata.UserID
        Type = $type
        Command = $commandData.Command
        Params = $params
        Status = 'pending'
        EnqueuedAt = (Get-Date).ToString('o')
        ExecutedAt = $null
        CompletedAt = $null
        Result = $null
        Error = $null
        TimeoutAt = (Get-Date).AddSeconds(60).ToString('o')
    }

    # Check queue size
    if ($Global:PSWebServer.DebugCommands.Queue.Count -ge $Global:PSWebServer.DebugCommands.MaxQueueSize) {
        throw "Command queue is full (max: $($Global:PSWebServer.DebugCommands.MaxQueueSize))"
    }

    # Enqueue
    $Global:PSWebServer.DebugCommands.Queue.Enqueue($commandObj)

    Write-PSWebHostLog -Severity 'Info' -Category 'DebugExtensions' -Message "Command enqueued: $($commandObj.CommandID) | Type: $type | User: $($sessiondata.UserID) | Target: $targetSession"

    # Return command ID
    $responseData = @{
        status = 'success'
        commandID = $commandObj.CommandID
        queuePosition = $Global:PSWebServer.DebugCommands.Queue.Count
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 200 -String $responseData -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'DebugExtensions' -Message "$MyTag Error: $($_.Exception.Message)"

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
