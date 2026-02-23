#Requires -Version 7

<#
.SYNOPSIS
    DELETE /apps/WebHostTaskManagement/api/v1/jobs?jobId={guid}

.DESCRIPTION
    Stops a running job OR deletes a completed job result
    - For running jobs: Stops and saves result
    - For completed jobs: Deletes the result file
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
    # Import job execution module
    $modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_JobExecution\PSWebHost_JobExecution.psd1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -DisableNameChecking -Force
    } else {
        throw "Job execution module not found"
    }

    # Validate session
    if (-not $sessiondata.UserID) {
        throw "Unauthorized: No user ID in session"
    }

    # Get query parameters
    $queryParams = if ($Test -and $Query.Count -gt 0) {
        $Query
    } elseif ($Request) {
        $params = @{}
        foreach ($key in $Request.QueryString.AllKeys) {
            if ($key) {
                $params[$key] = $Request.QueryString[$key]
            }
        }
        $params
    } else {
        @{}
    }

    if (-not $queryParams.jobId) {
        throw "Missing required parameter: jobId"
    }

    $jobId = $queryParams.jobId

    # Try to stop if running
    $message = ""
    try {
        $result = Stop-PSWebHostJob -JobID $jobId -UserID $sessiondata.UserID
        $message = "Job stopped successfully"
    }
    catch {
        # If not running, try to delete result
        $deleted = Remove-PSWebHostJobResults -JobID $jobId
        if ($deleted) {
            $message = "Job result deleted successfully"
        } else {
            throw "Job not found or already deleted"
        }
    }

    $response_data = @{
        success = $true
        message = $message
        jobId = $jobId
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
