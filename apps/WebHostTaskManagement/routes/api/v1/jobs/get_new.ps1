#Requires -Version 7

<#
.SYNOPSIS
    GET /apps/WebHostTaskManagement/api/v1/jobs
    GET /apps/WebHostTaskManagement/api/v1/jobs?jobId={guid}

.DESCRIPTION
    Lists all jobs for the current user OR gets a specific job status
    - Without jobId: Returns all jobs (pending, running, completed)
    - With jobId: Returns specific job status and details
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
    # Import job execution module
    $modulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_JobExecution\PSWebHost_JobExecution.psd1"
    if (Test-Path $modulePath) {
        Import-Module $modulePath -DisableNameChecking -Force -ErrorAction Stop
    } else {
        Write-Error "Job execution module not found at: $modulePath"
        throw "Job execution module not found"
    }

    # Validate session
    if (-not $sessiondata.UserID) {
        Write-Error "Session validation failed: No UserID in sessiondata"
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

    # Check if requesting specific job
    if ($queryParams.jobId) {
        # Get specific job status
        $jobStatus = Get-PSWebHostJobStatus -JobID $queryParams.jobId -UserID $sessiondata.UserID

        $response_data = @{
            success = $true
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            job = $jobStatus
        }
    }
    else {
        # List all jobs
        $includePending = $queryParams.includePending -ne 'false'
        $includeRunning = $queryParams.includeRunning -ne 'false'
        $includeCompleted = $queryParams.includeCompleted -ne 'false'
        $maxResults = if ($queryParams.maxResults) { [int]$queryParams.maxResults } else { 100 }

        # Check if function exists
        if (-not (Get-Command Get-PSWebHostJobs -ErrorAction SilentlyContinue)) {
            Write-Error "Get-PSWebHostJobs function not found. Module may not be loaded correctly."
            throw "Job management functions not available. Server may need restart."
        }

        $jobs = Get-PSWebHostJobs `
            -UserID $sessiondata.UserID `
            -IncludePending:$includePending `
            -IncludeRunning:$includeRunning `
            -IncludeCompleted:$includeCompleted `
            -MaxResults $maxResults

        $response_data = @{
            success = $true
            timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
            jobs = @{
                pending = $jobs.Pending
                running = $jobs.Running
                completed = $jobs.Completed
            }
            counts = @{
                pending = $jobs.Pending.Count
                running = $jobs.Running.Count
                completed = $jobs.Completed.Count
                total = $jobs.Pending.Count + $jobs.Running.Count + $jobs.Completed.Count
            }
        }
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
