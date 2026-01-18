param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $projectRoot = $Global:PSWebServer.UnitTests.ProjectRoot
    $testsPath = $Global:PSWebServer.UnitTests.TestsPath
    $routesPath = Join-Path $projectRoot 'routes'

    # Find all route files
    $routeFiles = Get-ChildItem -Path $routesPath -Filter "*.ps1" -Recurse | Where-Object {
        $_.Name -match '^(get|post|put|delete|patch)\.ps1$'
    } | ForEach-Object {
        $relativePath = $_.DirectoryName.Replace($routesPath, '').TrimStart('\', '/')
        $method = $_.BaseName.ToUpper()

        @{
            method = $method
            path = $relativePath
            fullPath = $_.FullName
            fileName = $_.Name
        }
    }

    # Find all test files
    $testFiles = Get-ChildItem -Path $testsPath -Filter "*.Tests.ps1" -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Replace($testsPath, '').TrimStart('\', '/')
        @{
            path = $relativePath
            fullPath = $_.FullName
            name = $_.Name
        }
    }

    # Match routes to tests
    $tested = @()
    $untested = @()

    foreach ($route in $routeFiles) {
        # Expected test path: tests/twin/routes/{routepath}/{method}.Tests.ps1
        $expectedTestPath = "routes\$($route.path)\$($route.method).Tests.ps1"

        $hasTest = $testFiles | Where-Object { $_.path -like "*$expectedTestPath" }

        if ($hasTest) {
            $tested += @{
                method = $route.method
                path = $route.path
                testFile = $hasTest[0].path
            }
        } else {
            $untested += @{
                method = $route.method
                path = $route.path
                expectedTestPath = $expectedTestPath
            }
        }
    }

    # Calculate coverage statistics
    $totalRoutes = $routeFiles.Count
    $testedRoutes = $tested.Count
    $untestedRoutes = $untested.Count
    $coveragePercent = if ($totalRoutes -gt 0) {
        [math]::Round(($testedRoutes / $totalRoutes) * 100, 2)
    } else { 0 }

    # Group untested by directory
    $untestedByDir = $untested | Group-Object {
        if ($_.path -match '^([^\\]+(?:\\[^\\]+)?)') {
            $matches[1]
        } else {
            'root'
        }
    } | ForEach-Object {
        @{
            directory = $_.Name
            count = $_.Count
            routes = $_.Group
        }
    } | Sort-Object -Property count -Descending

    $result = @{
        totalRoutes = $totalRoutes
        testedRoutes = $testedRoutes
        untestedRoutes = $untestedRoutes
        coveragePercent = $coveragePercent
        tested = $tested | Sort-Object -Property path
        untested = $untested | Sort-Object -Property path
        untestedByDirectory = $untestedByDir
        generatedAt = Get-Date -Format 'o'
    }

    context_response -Response $Response -StatusCode 200 -String ($result | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Message "Error generating coverage report: $($_.Exception.Message)" -Level 'Error' -Facility 'UnitTests'

    context_response -Response $Response -StatusCode 500 -String (@{
        error = "Failed to generate coverage report"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
