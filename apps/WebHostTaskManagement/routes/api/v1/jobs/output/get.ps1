#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/jobs/output?jobId={guid}

.DESCRIPTION
    Gets live output from a running job (BackgroundJob mode only)
    Returns current output without removing it from the job stream
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

$MyTag = '[WebHostTaskManagement:API:Jobs:Output]'

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

    # Get live output
    $outputData = Get-PSWebHostJobOutput -JobID $jobId -UserID $sessiondata.UserID

    $response_data = @{
        success = $outputData.Success
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        jobId = $jobId
        output = $outputData.Output
        runtime = $outputData.Runtime
        state = $outputData.State
        message = $outputData.Message
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
