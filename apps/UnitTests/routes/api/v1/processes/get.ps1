param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    $testsPath = $Global:PSWebServer.UnitTests.TestsPath
    $reportPath = Join-Path $testsPath 'process-tracking-report.txt'

    if (-not (Test-Path $reportPath)) {
        context_response -Response $Response -StatusCode 404 -String (@{
            error = "No process tracking report found"
            message = "Run tests to generate process tracking data"
            reportPath = $reportPath
        } | ConvertTo-Json) -ContentType "application/json"
        return
    }

    # Read and parse the report
    $reportContent = Get-Content $reportPath -Raw

    # Extract key metrics using regex
    $initialProcesses = if ($reportContent -match 'Initial Processes:\s+(\d+)') { [int]$matches[1] } else { 0 }
    $finalProcesses = if ($reportContent -match 'Final Processes:\s+(\d+)') { [int]$matches[1] } else { 0 }
    $newProcesses = if ($reportContent -match 'New Processes:\s+(\d+)') { [int]$matches[1] } else { 0 }
    $cleaned = if ($reportContent -match 'Cleaned:\s+(\d+)') { [int]$matches[1] } else { 0 }
    $failed = if ($reportContent -match 'Failed to Clean:\s+(\d+)') { [int]$matches[1] } else { 0 }

    # Extract test-to-PID mappings
    $testsWithLeaks = @()
    if ($reportContent -match '(?s)Tests that Created Processes.*?\n\n(.*?)\n\n') {
        $section = $matches[1]
        $section -split "`r?`n" | Where-Object { $_ -match '^\[([^\]]+)\]\s+(.+)$' } | ForEach-Object {
            $testsWithLeaks += @{
                pids = $matches[1] -split ',\s*'
                testPath = $matches[2].Trim()
            }
        }
    }

    # Extract areas for improvement
    $problematicFiles = @()
    if ($reportContent -match '(?s)Test files with process leaks.*?\n\n(.*?)$') {
        $section = $matches[1]
        $section -split "`r?`n" | Where-Object { $_ -match '^\s+(.+?):\s+(\d+)\s+test' } | ForEach-Object {
            $problematicFiles += @{
                file = $matches[1].Trim()
                count = [int]$matches[2]
            }
        }
    }

    # Get file modification time
    $reportFile = Get-Item $reportPath
    $generatedAt = $reportFile.LastWriteTime.ToString('o')

    $result = @{
        summary = @{
            initialProcesses = $initialProcesses
            finalProcesses = $finalProcesses
            newProcesses = $newProcesses
            cleaned = $cleaned
            failed = $failed
            leaksDetected = $newProcesses -gt 0
        }
        testsWithLeaks = $testsWithLeaks
        problematicFiles = $problematicFiles
        generatedAt = $generatedAt
        reportPath = $reportPath
        rawReport = $reportContent
    }

    context_response -Response $Response -StatusCode 200 -String ($result | ConvertTo-Json -Depth 10) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Message "Error retrieving process tracking data: $($_.Exception.Message)" -Level 'Error' -Facility 'UnitTests'

    context_response -Response $Response -StatusCode 500 -String (@{
        error = "Failed to retrieve process tracking data"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
