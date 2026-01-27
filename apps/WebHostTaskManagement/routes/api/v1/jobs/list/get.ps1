param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Lists all jobs for the current user (pending, running, completed)

.DESCRIPTION
    Returns comprehensive job information across all states:
    - Pending: Jobs waiting in submission queue
    - Running: Jobs currently executing
    - Completed: Jobs that have finished (success or failure)
#>

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
        context_response -Response $Response -StatusCode 401 -String '{" error":"Unauthorized"}' -ContentType "application/json"
        return
    }

    # Get query parameters
    $includePending = $true
    $includeRunning = $true
    $includeCompleted = $true
    $maxResults = 100

    if ($Request.QueryString['includePending'] -eq 'false') { $includePending = $false }
    if ($Request.QueryString['includeRunning'] -eq 'false') { $includeRunning = $false }
    if ($Request.QueryString['includeCompleted'] -eq 'false') { $includeCompleted = $false }

    if ($Request.QueryString['maxResults']) {
        $maxResults = [int]$Request.QueryString['maxResults']
    }

    # Get all jobs
    $jobs = Get-PSWebHostJobs `
        -UserID $sessiondata.UserID `
        -IncludePending:$includePending `
        -IncludeRunning:$includeRunning `
        -IncludeCompleted:$includeCompleted `
        -MaxResults $maxResults

    $responseData = @{
        success = $true
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

    $json = $responseData | ConvertTo-Json -Depth 10 -Compress
    context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Error listing jobs: $($_.Exception.Message)" -Data @{
        UserID = $sessiondata.UserID
        Error = $_.Exception.ToString()
    }

    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
