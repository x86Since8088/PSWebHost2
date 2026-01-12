param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $testsPath = $Global:PSWebServer.UnitTests.TestsPath

    if (-not (Test-Path $testsPath)) {
        context_reponse -Response $Response -StatusCode 404 -String (@{
            error = "Tests directory not found"
            path = $testsPath
        } | ConvertTo-Json) -ContentType "application/json"
        return
    }

    # Find all .Tests.ps1 files
    $testFiles = Get-ChildItem -Path $testsPath -Filter "*.Tests.ps1" -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Replace($testsPath, '').TrimStart('\', '/')
        $category = if ($relativePath -match '^routes') { 'Routes' }
                    elseif ($relativePath -match '^modules') { 'Modules' }
                    elseif ($relativePath -match '^system') { 'System' }
                    else { 'Other' }

        @{
            name = $_.Name
            path = $relativePath
            fullPath = $_.FullName
            category = $category
            directory = $_.Directory.Name
            size = $_.Length
            lastModified = $_.LastWriteTime.ToString('o')
        }
    }

    # Group tests by category
    $groupedTests = $testFiles | Group-Object -Property category | ForEach-Object {
        @{
            category = $_.Name
            count = $_.Count
            tests = $_.Group
        }
    }

    $result = @{
        totalTests = $testFiles.Count
        categories = $groupedTests
        testsPath = $testsPath
    }

    context_reponse -Response $Response -StatusCode 200 -String ($result | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Message "Error listing tests: $($_.Exception.Message)" -Level 'Error' -Facility 'UnitTests'

    context_reponse -Response $Response -StatusCode 500 -String (@{
        error = "Failed to list tests"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
