param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

<#
.SYNOPSIS
    Gets job execution results for the current user

.DESCRIPTION
    Returns job execution results including:
    - Job ID and name
    - Execution status and timing
    - Command executed
    - Output captured
    - Success/failure status
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

    # Get query parameters
    $maxResults = if ($Request.QueryString['maxResults']) {
        [int]$Request.QueryString['maxResults']
    } else {
        100
    }

    # Get results
    $results = Get-PSWebHostJobResults -UserID $sessiondata.UserID -MaxResults $maxResults

    $responseData = @{
        success = $true
        results = $results
        count = $results.Count
    }

    $json = $responseData | ConvertTo-Json -Depth 10 -Compress
    context_response -Response $Response -StatusCode 200 -String $json -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Error getting job results: $($_.Exception.Message)" -Data @{
        UserID = $sessiondata.UserID
        Error = $_.Exception.ToString()
    }

    $errorResponse = @{
        success = $false
        error = $_.Exception.Message
    } | ConvertTo-Json -Compress

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
