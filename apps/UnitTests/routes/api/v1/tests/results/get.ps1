param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request = $Context.Request,
    [System.Net.HttpListenerResponse]$Response = $Context.Response,
    $sessiondata
)

try {
    # Get jobId from query string
    $queryParams = @{}
    if ($Request.Url.Query) {
        $Request.Url.Query.TrimStart('?').Split('&') | ForEach-Object {
            $parts = $_.Split('=')
            if ($parts.Count -eq 2) {
                $queryParams[$parts[0]] = [System.Web.HttpUtility]::UrlDecode($parts[1])
            }
        }
    }

    $jobId = $queryParams['jobId']

    if (-not $jobId) {
        # Return test history if no jobId specified
        $history = @($Global:PSWebServer.UnitTests.History)

        context_reponse -Response $Response -StatusCode 200 -String (@{
            history = $history | Select-Object -Last 50 | Sort-Object -Property startTime -Descending
            count = $history.Count
        } | ConvertTo-Json -Depth 10) -ContentType "application/json"
        return
    }

    # Check if job exists
    if (-not $Global:PSWebServer.UnitTests.Jobs.ContainsKey($jobId)) {
        context_reponse -Response $Response -StatusCode 404 -String (@{
            error = "Job not found"
            jobId = $jobId
        } | ConvertTo-Json) -ContentType "application/json"
        return
    }

    $jobInfo = $Global:PSWebServer.UnitTests.Jobs[$jobId]
    $job = $jobInfo.Job

    # Check job state
    $jobState = $job.JobStateInfo.State

    if ($jobState -eq 'Completed') {
        # Retrieve job results
        $jobResults = Receive-Job -Job $job -ErrorAction SilentlyContinue

        # Clean up job
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

        # Parse results
        $testResults = if ($jobResults.success) {
            @{
                status = 'Completed'
                success = $true
                totalTests = $jobResults.result.TotalCount
                passed = $jobResults.result.PassedCount
                failed = $jobResults.result.FailedCount
                skipped = $jobResults.result.SkippedCount
                duration = $jobResults.result.Duration.TotalSeconds
                processLeaks = $jobResults.processLeaks
                completedAt = $jobResults.completedAt
            }
        } else {
            @{
                status = 'Failed'
                success = $false
                error = $jobResults.error
                stackTrace = $jobResults.stackTrace
                completedAt = $jobResults.completedAt
            }
        }

        # Add to history
        $historyEntry = @{
            jobId = $jobId
            startTime = $jobInfo.StartTime.ToString('o')
            testPaths = $jobInfo.TestPaths
            userId = $jobInfo.UserId
            userName = $jobInfo.UserName
            results = $testResults
        }

        [void]$Global:PSWebServer.UnitTests.History.Add($historyEntry)

        # Save history to disk (async, don't block)
        $historyPath = Join-Path $Global:PSWebServer.UnitTests.DataPath 'test-history.json'
        try {
            $Global:PSWebServer.UnitTests.History | ConvertTo-Json -Depth 10 | Out-File -FilePath $historyPath -Encoding UTF8 -Force
        } catch {
            Write-PSWebHostLog -Message "Failed to save test history: $($_.Exception.Message)" -Level 'Warning' -Facility 'UnitTests'
        }

        # Remove from active jobs
        $Global:PSWebServer.UnitTests.Jobs.Remove($jobId)

        context_reponse -Response $Response -StatusCode 200 -String ($testResults | ConvertTo-Json -Depth 10) -ContentType "application/json"

    } elseif ($jobState -eq 'Running') {
        # Job still running
        $elapsed = (Get-Date) - $jobInfo.StartTime

        context_reponse -Response $Response -StatusCode 200 -String (@{
            status = 'Running'
            jobId = $jobId
            startTime = $jobInfo.StartTime.ToString('o')
            elapsedSeconds = [math]::Round($elapsed.TotalSeconds, 1)
            testPaths = $jobInfo.TestPaths
        } | ConvertTo-Json -Depth 10) -ContentType "application/json"

    } elseif ($jobState -eq 'Failed') {
        # Job failed
        $jobError = $job.ChildJobs[0].JobStateInfo.Reason.Message

        context_reponse -Response $Response -StatusCode 200 -String (@{
            status = 'Failed'
            success = $false
            error = $jobError
            jobId = $jobId
        } | ConvertTo-Json) -ContentType "application/json"

        # Clean up
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $Global:PSWebServer.UnitTests.Jobs.Remove($jobId)

    } else {
        # Unknown state
        context_reponse -Response $Response -StatusCode 200 -String (@{
            status = $jobState
            jobId = $jobId
        } | ConvertTo-Json) -ContentType "application/json"
    }

} catch {
    Write-PSWebHostLog -Message "Error retrieving test results: $($_.Exception.Message)" -Level 'Error' -Facility 'UnitTests'

    context_reponse -Response $Response -StatusCode 500 -String (@{
        error = "Failed to retrieve test results"
        message = $_.Exception.Message
    } | ConvertTo-Json) -ContentType "application/json"
}
