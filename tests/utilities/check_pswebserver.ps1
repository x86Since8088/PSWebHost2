$apiKey = '0Vqgs6LaygeHj9pb1LyQxWPKL32CGiEjpZHEXTml05E='

try {
    $body = @{
        script = @"
# Check PSWebServer structure
\$info = @{
    HasProjectRoot = [bool]\$Global:PSWebServer.Project_Root
    ProjectRootType = if (\$Global:PSWebServer.Project_Root) { \$Global:PSWebServer.Project_Root.GetType().Name } else { 'null' }
    ProjectRootPath = \$Global:PSWebServer.Project_Root.Path
    Keys = \$Global:PSWebServer.Keys | Sort-Object
}
\$info | ConvertTo-Json -Depth 3
"@
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri 'http://localhost:8080/api/v1/cli' `
        -Method POST `
        -Headers @{ 'Authorization' = "Bearer $apiKey" } `
        -ContentType 'application/json' `
        -Body $body `
        -TimeoutSec 10

    Write-Host "PSWebServer Structure:" -ForegroundColor Cyan
    $response
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}
