# Docker Info Endpoint
# Returns Docker daemon information and availability status

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Check if Docker is available from global state
    if (-not $Global:PSWebServer.DockerManager.DockerAvailable) {
        $errorResponse = @{
            available = $false
            error = $Global:PSWebServer.DockerManager.DockerError
            message = 'Docker daemon is not available'
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 503 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Get fresh Docker status
    $dockerInfo = Test-DockerAvailability

    if (-not $dockerInfo.available) {
        $errorResponse = @{
            available = $false
            error = $dockerInfo.error
            message = 'Docker daemon is not available'
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 503 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Return Docker information
    $response = @{
        available = $true
        version = $dockerInfo.version
        serverVersion = $dockerInfo.serverVersion
        containers = $dockerInfo.containers
        containersRunning = $dockerInfo.containersRunning
        containersStopped = $dockerInfo.containersStopped
        containersPaused = $dockerInfo.containersPaused
        images = $dockerInfo.images
    }

    $jsonResponse = $response | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType 'application/json'

} catch {
    Write-PSWebHostLog -Message "Error in Docker info endpoint: $($_.Exception.Message)" -Level 'Error' -Facility 'DockerManager'

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
