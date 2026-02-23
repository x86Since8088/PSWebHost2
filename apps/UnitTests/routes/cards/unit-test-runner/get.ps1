param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Unit Test Runner UI Element Endpoint
# Returns metadata for the unit test runner component

try {
    $metadata = @{
        component = "unit-test-runner"
        scriptPath = "/apps/UnitTests/public/elements/unit-test-runner/component.js"
        title = "Unit Test Runner"
        description = "In-browser testing framework for PSWebHost components"
        version = "1.0.0"
        width = 12
        height = 600
    }

    # Return JSON response using context_response helper
    context_response -Response $Response -String ($metadata | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-Warning "Error loading unit-test-runner endpoint: $($_.Exception.Message)"

    # Simple error response without requiring Get-PSWebHostErrorReport
    $errorResponse = @{
        status = "error"
        message = $_.Exception.Message
    } | ConvertTo-Json

    context_response -Response $Response -StatusCode 500 -String $errorResponse -ContentType "application/json"
}
