# List Docker Containers Endpoint
# Returns all Docker containers (running and stopped)

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
            message = $Global:PSWebServer.DockerManager.DockerError
        } | ConvertTo-Json

        context_response -Response $Response -StatusCode 503 -String $errorResponse -ContentType 'application/json'
        return
    }

    # Get all containers
    $containers = Get-DockerContainers

    $response = @{
        success = $true
        count = $containers.Count
        containers = $containers
    }

    $jsonResponse = $response | ConvertTo-Json -Depth 5 -Compress
    context_response -Response $Response -StatusCode 200 -String $jsonResponse -ContentType 'application/json'

} catch {
    Write-PSWebHostLog -Message "Error listing Docker containers: $($_.Exception.Message)" -Level 'Error' -Facility 'DockerManager'

    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
