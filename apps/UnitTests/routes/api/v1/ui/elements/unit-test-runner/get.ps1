param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata
)

# Unit Test Runner UI Element Endpoint
# Returns metadata for the unit test runner component

try {
    $response = @{
        component = "unit-test-runner"
        scriptPath = "/apps/UnitTests/public/elements/unit-test-runner/component.js"
        title = "Unit Test Runner"
        description = "In-browser testing framework for PSWebHost components"
        version = "1.0.0"
    }

    # Return JSON response using context_response helper
    context_response -Response $Response -String ($response | ConvertTo-Json -Depth 10) -ContentType "application/json"
}
catch {
    Write-PSWebHostLog -Severity 'Error' -Category 'UnitTests' -Message "Error loading unit-test-runner endpoint: $($_.Exception.Message)"
    $Report = Get-PSWebHostErrorReport -ErrorRecord $_ -Context $Context -Request $Request -sessiondata $sessiondata
    context_response -Response $Response -StatusCode $Report.statusCode -String $Report.body -ContentType $Report.contentType
}
