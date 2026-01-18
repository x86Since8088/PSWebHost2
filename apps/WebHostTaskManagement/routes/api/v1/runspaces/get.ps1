#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/runspaces

.DESCRIPTION
    Returns information about PowerShell runspaces for monitoring and debugging
#>

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

$MyTag = '[WebHostTaskManagement:API:Runspaces:Get]'

try {
    # Use global cached runspace data from main thread
    # This avoids the issue of querying from within a listener runspace
    # where Get-Job only sees the current runspace's jobs
    $runspaceData = @()

    if ($Global:PSWebServer.Runspaces) {
        # Convert cached hashtable to array of objects
        foreach ($instanceId in $Global:PSWebServer.Runspaces.Keys) {
            $cachedData = $Global:PSWebServer.Runspaces[$instanceId]

            $runspaceData += [PSCustomObject]@{
                id = $cachedData.Id
                instanceId = $cachedData.InstanceId
                name = $cachedData.Name
                availability = $cachedData.Availability
                state = $cachedData.State
                reason = $cachedData.Reason
                jobId = $cachedData.JobId
                jobName = $cachedData.JobName
                jobState = $cachedData.JobState
                threadOptions = $cachedData.ThreadOptions ?? "N/A"
                apartmentState = $cachedData.ApartmentState ?? "N/A"
                # Include worker-specific fields if present
                workerId = $cachedData.WorkerId
                workerState = $cachedData.WorkerState
                isProcessing = $cachedData.IsProcessing
                requestsProcessed = $cachedData.RequestsProcessed
            }
        }
    } else {
        Write-Verbose "$MyTag Global runspace cache not initialized yet. Returning empty result."
    }

    # Add current listener runspace info
    $currentRunspace = [runspace]::DefaultRunspace
    if ($currentRunspace) {
        $runspaceData += [PSCustomObject]@{
            id = $currentRunspace.Id
            instanceId = $currentRunspace.InstanceId
            name = "Current Listener Runspace"
            availability = $currentRunspace.RunspaceAvailability.ToString()
            state = $currentRunspace.RunspaceStateInfo.State.ToString()
            reason = $currentRunspace.RunspaceStateInfo.Reason
            jobId = $null
            jobName = "HTTP Listener"
            jobState = "Running"
            threadOptions = if ($currentRunspace.ThreadOptions) { $currentRunspace.ThreadOptions.ToString() } else { "N/A" }
            apartmentState = if ($currentRunspace.ApartmentState) { $currentRunspace.ApartmentState.ToString() } else { "N/A" }
        }
    }

    $response_data = @{
        success = $true
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        source = "global_cache"  # Indicate data source
        cacheAge = if ($Global:PSWebServer.Runspaces) {
            "Updated every 10 seconds from main thread"
        } else {
            "Cache not initialized"
        }
        runspaces = @($runspaceData)
        count = $runspaceData.Count
        available = @($runspaceData | Where-Object { $_.availability -eq 'Available' }).Count
        busy = @($runspaceData | Where-Object { $_.availability -eq 'Busy' }).Count
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        $response_data | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $Response.StatusCode = 200
    $Response.ContentType = "application/json"
    $json = $response_data | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()

} catch {
    Write-Error "$MyTag $_"

    $error_response = @{
        success = $false
        error = $_.Exception.Message
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($Test) {
        Write-Host "Status: 500 Internal Server Error" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 500
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
