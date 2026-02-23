# Delete Docker Container Endpoint
# Removes a Docker container

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Check if Docker is available
    if (-not $Global:PSWebServer.DockerManager.DockerAvailable) {
        $errorResponse = @{
            success = $false
            error = 'Docker daemon is not available'
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 503 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Extract container ID from URL path
    $pathParts = $Request.Url.AbsolutePath -split '/'
    $containerId = $pathParts[-2]

    # Validate container ID
    if ([string]::IsNullOrWhiteSpace($containerId)) {
        $errorResponse = @{
            success = $false
            error = 'Container ID is required'
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Get force parameter (query string)
    $force = $false
    if ($Request.QueryString['force']) {
        $force = $Request.QueryString['force'] -eq 'true'
    }

    # Validate container ID format and existence
    try {
        $isValid = Test-DockerContainerId -Id $containerId
        if (-not $isValid) {
            $errorResponse = @{
                success = $false
                error = 'Container not found'
                containerId = $containerId
            } | ConvertTo-Json

            context_response -Response $Response -StatusCode 404 -String $errorResponse -ContentType 'application/json'
            return
        }
    } catch {
        $errorResponse = @{
            success = $false
            error = $_.Exception.Message
            containerId = $containerId
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 400 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Remove the container
    $result = Remove-DockerContainer -ContainerId $containerId -Force:$force

    # Log the operation
    if ($result.success) {
        $forceText = if ($force) { " (forced)" } else { "" }
        Write-PSWebHostLog -Message "Container deleted$forceText: $containerId by $($sessiondata.Email)" -Level 'Info' -Facility 'DockerManager'
    }

    # Return result
    $statusCode = if ($result.success) { 200 } else {
        # Check if it's a conflict (container still running)
        if ($result.error -like "*stop the container*" -or $result.error -like "*container is running*") {
            409  # Conflict
        } else {
            500
        }
    }
    $jsonResponse = $result | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode $statusCode -String $jsonResponse -ContentType 'application/json'

} catch {
    Write-PSWebHostLog -Message "Error deleting container: $($_.Exception.Message)" -Level 'Error' -Facility 'DockerManager'

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
