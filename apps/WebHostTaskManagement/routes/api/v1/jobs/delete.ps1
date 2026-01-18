#Requires -Version 7

<#
.SYNOPSIS
    DELETE /apps/WebHostTaskManagement/api/v1/jobs?jobId=123

.DESCRIPTION
    Stops and removes a background job
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

$MyTag = '[WebHostTaskManagement:API:Jobs:Delete]'

try {
    # Get query parameters
    if ($Test -and $Query.Count -gt 0) {
        $queryParams = $Query
    } elseif ($Request) {
        $queryParams = @{}
        foreach ($key in $Request.QueryString.AllKeys) {
            $queryParams[$key] = $Request.QueryString[$key]
        }
    } else {
        $queryParams = @{}
    }

    $jobId = [int]$queryParams.jobId

    if (-not $jobId) {
        throw "Missing required parameter: jobId"
    }

    # Get the job
    $job = Get-Job -Id $jobId -ErrorAction Stop

    # Stop the job if running
    if ($job.State -eq 'Running') {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500  # Give it time to stop
    }

    # Remove from task tracking if it's a task job
    $taskEntry = $Global:PSWebServer.Tasks.RunningJobs.Keys | Where-Object {
        $Global:PSWebServer.Tasks.RunningJobs[$_].Job.Id -eq $jobId
    } | Select-Object -First 1

    if ($taskEntry) {
        $Global:PSWebServer.Tasks.RunningJobs.Remove($taskEntry)
    }

    # Remove the job
    Remove-Job -Job $job -Force

    $response_data = @{
        success = $true
        message = "Job $jobId stopped and removed"
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
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
        Write-Host "Status: 400 Bad Request" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 400
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
