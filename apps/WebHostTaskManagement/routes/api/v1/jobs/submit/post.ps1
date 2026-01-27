param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Submits a job for execution

.DESCRIPTION
    Accepts job submissions from users with appropriate roles.
    Supports three execution modes:
    - MainLoop: Execute in main loop (debug role only)
    - Runspace: Execute in dedicated runspace
    - BackgroundJob: Execute as PowerShell background job
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
        context_response -Response $Response -StatusCode 401 -String '{"error":"Unauthorized"}' -ContentType "application/json"
        return
    }

    # Read request body
    $reader = New-Object System.IO.StreamReader($Request.InputStream)
    $body = $reader.ReadToEnd()
    $reader.Close()

    $data = $body | ConvertFrom-Json

    # Validate required fields
    if (-not $data.jobName) {
        throw "Missing required field: jobName"
    }
    if (-not $data.command) {
        throw "Missing required field: command"
    }
    if (-not $data.executionMode) {
        throw "Missing required field: executionMode"
    }

    # Validate execution mode
    $validModes = @('MainLoop', 'Runspace', 'BackgroundJob')
    if ($data.executionMode -notin $validModes) {
        throw "Invalid execution mode. Must be one of: $($validModes -join ', ')"
    }

    # Get SessionID (use bearer token or generate one if missing)
    $sessionID = if ($sessiondata.SessionID) {
        $sessiondata.SessionID
    } elseif ($sessiondata.BearerToken) {
        "bearer_$($sessiondata.UserID)_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    } else {
        "api_$(New-Guid)"
    }

    # Submit job
    $result = Submit-PSWebHostJob `
        -UserID $sessiondata.UserID `
        -SessionID $sessionID `
        -JobName $data.jobName `
        -Command $data.command `
        -Description ($data.description -or '') `
        -ExecutionMode $data.executionMode `
        -Roles $sessiondata.Roles

    $responseData = @{
        success = $true
        jobId = $result.JobID
        message = "Job submitted successfully"
        executionMode = $data.executionMode
    }

    $json = $responseData | ConvertTo-Json -Depth 10 -Compress
    context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Error submitting job: $($_.Exception.Message)" -Data @{
        UserID = $sessiondata.UserID
        Error = $_.Exception.ToString()
    }

    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
