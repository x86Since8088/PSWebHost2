# Unit Test Runner API Endpoint
# Returns the unit test runner component for debug users

$response = @{
    component = "unit-test-runner"
    title = "Unit Test Runner"
    description = "In-browser testing framework for PSWebHost components"
}

# Return JSON response
$jsonResponse = $response | ConvertTo-Json -Depth 10
$context.Response.ContentType = "application/json"
$context.Response.StatusCode = 200
$writer = New-Object System.IO.StreamWriter($context.Response.OutputStream)
$writer.Write($jsonResponse)
$writer.Close()
