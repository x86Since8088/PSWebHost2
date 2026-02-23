#Requires -Version 7

<#
.SYNOPSIS
    Legacy GET /jobs endpoint - works without module restart

.DESCRIPTION
    Temporary fallback that queries file system directly
    Use this until server is restarted with new module functions
#>

param (
    [System.Net.HttpListenerContext]$Context,
    [System.Net.HttpListenerRequest]$Request=$Context.Request,
    [System.Net.HttpListenerResponse]$Response=$Context.Response,
    $sessiondata,
    [switch]$Test,
    [string[]]$Roles = @(),
    [hashtable]$Query = @{}
)

$MyTag = '[WebHostTaskManagement:API:Jobs:GetLegacy]'

try {
    # Validate session
    if (-not $sessiondata.UserID) {
        throw "Unauthorized: No user ID in session"
    }

    # Get data root
    $dataRoot = if ($Global:PSWebServer.DataPath) {
        $Global:PSWebServer.DataPath
    } else {
        Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data"
    }

    # Initialize result structure
    $jobs = @{
        pending = @()
        running = @()
        completed = @()
    }

    # Get pending jobs from file system
    $submissionDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission\$($sessiondata.UserID)"
    if (Test-Path $submissionDir) {
        $pendingFiles = Get-ChildItem -Path $submissionDir -Filter "*.json" -File | Sort-Object LastWriteTime -Descending

        foreach ($file in $pendingFiles) {
            try {
                $submission = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                $jobs.pending += @{
                    JobID = $submission.JobID
                    JobName = $submission.JobName
                    Description = $submission.Description
                    ExecutionMode = $submission.ExecutionMode
                    SubmittedAt = $submission.SubmittedAt
                    Status = 'Pending'
                }
            } catch {
                Write-Warning "Failed to read pending job: $($file.Name)"
            }
        }
    }

    # Get running jobs from global tracker
    if ($Global:PSWebServer.RunningJobs) {
        $runningJobs = $Global:PSWebServer.RunningJobs.Values | Where-Object { $_.UserID -eq $sessiondata.UserID }

        foreach ($job in $runningJobs) {
            $runtime = ((Get-Date) - $job.StartTime).TotalSeconds
            $jobs.running += @{
                JobID = $job.JobID
                JobName = $job.JobName
                Description = $job.Description
                ExecutionMode = $job.ExecutionMode
                StartedAt = $job.StartTime.ToString('o')
                Runtime = [math]::Round($runtime, 2)
                Status = 'Running'
            }
        }
    }

    # Get completed jobs
    $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"
    if (Test-Path $resultsDir) {
        $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 100

        foreach ($file in $resultFiles) {
            try {
                $result = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json

                # Filter by user
                if ($result.UserID -eq $sessiondata.UserID) {
                    $jobs.completed += @{
                        JobID = $result.JobID
                        JobName = $result.JobName
                        Description = $result.Description
                        ExecutionMode = $result.ExecutionMode
                        DateStarted = $result.DateStarted
                        DateCompleted = $result.DateCompleted
                        Runtime = $result.Runtime
                        Success = $result.Success
                        Output = $result.Output
                    }
                }
            } catch {
                Write-Warning "Failed to read completed job: $($file.Name)"
            }
        }
    }

    $response_data = @{
        success = $true
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
        jobs = @{
            pending = $jobs.pending
            running = $jobs.running
            completed = $jobs.completed
        }
        counts = @{
            pending = $jobs.pending.Count
            running = $jobs.running.Count
            completed = $jobs.completed.Count
            total = $jobs.pending.Count + $jobs.running.Count + $jobs.completed.Count
        }
        note = "Using legacy endpoint - restart server to use enhanced module functions"
    }

    # Test mode
    if ($Test) {
        Write-Host "`n=== API Endpoint Test Results ===" -ForegroundColor Cyan
        Write-Host "Status: 200 OK" -ForegroundColor Green
        $response_data | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    # Normal HTTP response
    $Response.StatusCode = 200
    $Response.ContentType = "application/json"
    $json = $response_data | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()

} catch {
    Write-Error "$MyTag $_"

    $error_response = @{
        success = $false
        error = $_.Exception.Message
        timestamp = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    }

    if ($Test) {
        Write-Host "Status: 500 Internal Server Error" -ForegroundColor Red
        $error_response | ConvertTo-Json -Depth 10 | Write-Host
        return
    }

    $Response.StatusCode = 500
    $Response.ContentType = "application/json"
    $json = $error_response | ConvertTo-Json -Depth 10
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}
