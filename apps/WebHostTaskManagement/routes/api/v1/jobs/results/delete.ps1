param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Deletes a job execution result

.DESCRIPTION
    Removes a job result from the system.
    Users can only delete their own job results.
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

    # Get job ID from query string
    $jobId = $Request.QueryString['jobId']
    if (-not $jobId) {
        throw "Missing required parameter: jobId"
    }

    # Verify ownership before deletion
    $results = Get-PSWebHostJobResults -UserID $sessiondata.UserID -MaxResults 1000
    $jobResult = $results | Where-Object { $_.JobID -eq $jobId }

    if (-not $jobResult) {
        throw "Job result not found or access denied"
    }

    # Delete result
    $deleted = Remove-PSWebHostJobResults -JobID $jobId

    $response = @{
        success = $deleted
        message = if ($deleted) { "Job result deleted successfully" } else { "Job result not found" }
    }

    $json = $response | ConvertTo-Json -Compress
    context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Error deleting job result: $($_.Exception.Message)" -Data @{
        UserID = $sessiondata.UserID
        Error = $_.Exception.ToString()
    }

    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
