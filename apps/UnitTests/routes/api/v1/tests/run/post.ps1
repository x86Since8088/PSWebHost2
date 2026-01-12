param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Parse request body
    $bodyText = Get-HttpBody -Request $Request
    $body = $bodyText | ConvertFrom-Json

    $testPaths = $body.testPaths  # Array of test file paths
    $tags = $body.tags
    $excludeTags = $body.excludeTags
    $output = if ($body.output) { $body.output } else { 'Detailed' }

    if (-not $testPaths -or $testPaths.Count -eq 0) {
        context_reponse -Response $Response -StatusCode 400 -String (@{
            error = "testPaths parameter is required"
        } | ConvertTo-Json) -ContentType "application/json"
        return
    }

    # Generate job ID
    $jobId = [guid]::NewGuid().ToString()
    $projectRoot = $Global:PSWebServer.UnitTests.ProjectRoot
    $testsPath = $Global:PSWebServer.UnitTests.TestsPath

    # Convert relative paths to full paths
    $fullPaths = $testPaths | ForEach-Object {
        if ($_ -match '\.Tests\.ps1$') {
            Join-Path $testsPath $_
        } else {
            $_
        }
    }

    # Build Pester command arguments
    $pesterArgs = @{
        Path = $fullPaths
        Output = $output
    }
    if ($tags) { $pesterArgs.Tag = $tags }
    if ($excludeTags) { $pesterArgs.ExcludeTag = $excludeTags }

    Write-PSWebHostLog -Message "Starting test execution: JobID=$jobId, Paths=$($testPaths -join ', ')" -Level 'Info' -Facility 'UnitTests'

    # Start test execution in background job
    $testJob = Start-Job -ScriptBlock {
        param($ProjectRoot, $TestsPath, $PesterArgs, $JobId)

        Set-Location $ProjectRoot

        # Capture process IDs before test
        $initialProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id

        try {
            # Run the test script
            $testScript = Join-Path $TestsPath 'Run-AllTwinTests.ps1'

            # Execute with arguments
            $result = & $testScript @PesterArgs

            # Capture process IDs after test
            $finalProcesses = Get-Process pwsh -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id
            $newProcesses = $finalProcesses | Where-Object { $_ -notin $initialProcesses }

            # Read process tracking report if exists
            $reportPath = Join-Path $TestsPath 'process-tracking-report.txt'
            $processReport = if (Test-Path $reportPath) {
                Get-Content $reportPath -Raw
            } else { $null }

            # Return results
            @{
                success = $true
                result = $result
                processLeaks = @{
                    detected = $newProcesses.Count -gt 0
                    pids = $newProcesses
                    report = $processReport
                }
                completedAt = Get-Date -Format 'o'
            }
        } catch {
            @{
                success = $false
                error = $_.Exception.Message
                stackTrace = $_.ScriptStackTrace
                completedAt = Get-Date -Format 'o'
            }
        }
    } -ArgumentList $projectRoot, $testsPath, $pesterArgs, $jobId

    # Store job information
    $Global:PSWebServer.UnitTests.Jobs[$jobId] = @{
        Job = $testJob
        JobId = $jobId
        StartTime = Get-Date
        TestPaths = $testPaths
        Tags = $tags
        ExcludeTags = $excludeTags
        Output = $output
        Status = 'Running'
        UserId = $sessiondata.UserID
        UserName = $sessiondata.Email
    }

    # Return job ID immediately (202 Accepted - processing)
    context_reponse -Response $Response -StatusCode 202 -String (@{
        jobId = $jobId
        message = "Test execution started"
        testCount = $testPaths.Count
        estimatedDuration = "30-60 seconds"
    } | ConvertTo-Json) -ContentType "application/json"

} catch {
    Write-PSWebHostLog -Message "Error starting test execution: $($_.Exception.Message)" -Level 'Error' -Facility 'UnitTests'

    context_reponse -Response $Response -StatusCode 500 -String (@{
        error = "Failed to start test execution"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
