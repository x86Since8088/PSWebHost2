#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/jobs

.DESCRIPTION
    Returns all PowerShell background jobs (running and recent)
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

$MyTag = '[WebHostTaskManagement:API:Jobs:Get]'

try {
    # Get all jobs
    $allJobs = Get-Job

    $jobData = foreach ($job in $allJobs) {
        # Find associated task if this is a task job
        $taskInfo = $Global:PSWebServer.Tasks.RunningJobs.Values | Where-Object { $_.Job.Id -eq $job.Id } | Select-Object -First 1

        [PSCustomObject]@{
            id = $job.Id
            name = $job.Name
            state = $job.State.ToString()
            hasMoreData = $job.HasMoreData
            location = $job.Location
            command = $job.Command
            startTime = if ($taskInfo) { $taskInfo.StartTime } else { $null }
            runningTime = if ($taskInfo) { ((Get-Date) - $taskInfo.StartTime).TotalSeconds } else { $null }
            taskName = if ($taskInfo) { $taskInfo.Task.name } else { $null }
            appName = if ($taskInfo) { $taskInfo.Task.appName } else { $null }
            childJobs = $job.ChildJobs.Count
        }
    }

    $response_data = @{
        success = $true
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        jobs = @($jobData)
        count = $jobData.Count
        running = @($jobData | Where-Object { $_.state -eq 'Running' }).Count
        completed = @($jobData | Where-Object { $_.state -eq 'Completed' }).Count
        failed = @($jobData | Where-Object { $_.state -eq 'Failed' }).Count
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
