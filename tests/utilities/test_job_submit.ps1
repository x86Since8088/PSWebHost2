$apiKey = 'ZAVSsdtvXNR6jGWYIg9drAgQF7aVDnbKX3LEMSNWvh8='
$body = @{
    jobName = 'TestJob'
    command = 'Get-Date'
    description = 'Test job'
    executionMode = 'MainLoop'
} | ConvertTo-Json

try {
    $response = Invoke-RestMethod -Uri 'http://localhost:8080/apps/WebHostTaskManagement/api/v1/jobs/submit' `
        -Method POST `
        -Headers @{ 'Authorization' = "Bearer $apiKey" } `
        -ContentType 'application/json' `
        -Body $body

    Write-Host 'Success!' -ForegroundColor Green
    $response | ConvertTo-Json
} catch {
    Write-Host 'Error:' -ForegroundColor Red
    Write-Host $_.Exception.Message
    if ($_.ErrorDetails) {
        Write-Host 'Details:' $_.ErrorDetails.Message
    }
}
