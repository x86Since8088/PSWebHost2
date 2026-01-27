#Requires -Version 7

<#
.SYNOPSIS
    Schedules memory analysis to run every 30 minutes via job submission system

.DESCRIPTION
    This script runs as a background job and submits memory analysis jobs
    every 30 minutes. It uses the WebHostTaskManagement job submission API.

.PARAMETER IntervalMinutes
    How often to run memory analysis (default: 30 minutes)

.PARAMETER RunOnce
    Run analysis once and exit

.EXAMPLE
    # Submit this script as a BackgroundJob that schedules recurring analysis:
    POST /apps/WebHostTaskManagement/api/v1/jobs/submit
    {
        "jobName": "MemoryAnalysisScheduler",
        "command": "& 'C:\\SC\\PsWebHost\\system\\utility\\Schedule-MemoryAnalysis.ps1' -IntervalMinutes 30",
        "executionMode": "BackgroundJob"
    }
#>

[CmdletBinding()]
param(
    [int]$IntervalMinutes = 30,
    [switch]$RunOnce
)

$ErrorActionPreference = 'Continue'

Write-Output ""
Write-Output "=== Memory Analysis Scheduler Started ==="
Write-Output "Interval: $IntervalMinutes minutes"
Write-Output "Run Once: $RunOnce"
Write-Output "Started at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output ""

# Import job execution module
$projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
    $Global:PSWebServer.Project_Root.Path
} else {
    Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

$modulePath = Join-Path $projectRoot "modules\PSWebHost_JobExecution\PSWebHost_JobExecution.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -DisableNameChecking -Force
    Write-Output "Loaded job execution module"
} else {
    Write-Output "ERROR: Job execution module not found at: $modulePath"
    exit 1
}

$analysisScript = Join-Path $projectRoot "system\utility\Analyze-LiveMemory.ps1"
if (-not (Test-Path $analysisScript)) {
    Write-Output "ERROR: Analysis script not found at: $analysisScript"
    exit 1
}

# Function to submit memory analysis job
function Submit-MemoryAnalysisJob {
    [CmdletBinding()]
    param()

    try {
        # Get data directory
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $projectRoot "PsWebHost_Data"
        }

        $submissionDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission\system"
        if (-not (Test-Path $submissionDir)) {
            New-Item -Path $submissionDir -ItemType Directory -Force | Out-Null
        }

        # Create submission
        $jobGuid = [Guid]::NewGuid().ToString()
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $fileName = "scheduler_MemoryAnalysis_${timestamp}_${jobGuid}.json"
        $filePath = Join-Path $submissionDir $fileName

        $csvName = "memory_analysis_${timestamp}.csv"

        $submission = @{
            JobID = $jobGuid
            UserID = 'system'
            SessionID = 'scheduler'
            JobName = "MemoryAnalysis_${timestamp}"
            Command = "& '$analysisScript' -Deep -TopCount 30 -ExportCSV"
            Description = "Scheduled memory analysis (every ${IntervalMinutes}min)"
            ExecutionMode = 'MainLoop'
            Roles = @('system_admin', 'debug')
            SubmittedAt = (Get-Date).ToString('o')
            Status = 'Pending'
        }

        $submission | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Force

        Write-Output "[$(Get-Date -Format 'HH:mm:ss')] Submitted memory analysis job: $jobGuid"
        return $jobGuid
    }
    catch {
        Write-Output "[$(Get-Date -Format 'HH:mm:ss')] ERROR submitting job: $($_.Exception.Message)"
        return $null
    }
}

# Main scheduling loop
if ($RunOnce) {
    Write-Output "Running analysis once..."
    $jobId = Submit-MemoryAnalysisJob
    if ($jobId) {
        Write-Output "Job submitted successfully: $jobId"
    } else {
        Write-Output "Job submission failed"
        exit 1
    }
} else {
    Write-Output "Starting continuous scheduler..."
    Write-Output ""

    $iteration = 0
    while ($true) {
        $iteration++
        Write-Output "--- Iteration $iteration ---"

        $jobId = Submit-MemoryAnalysisJob

        if ($jobId) {
            Write-Output "Next run in $IntervalMinutes minutes ($($(Get-Date).AddMinutes($IntervalMinutes).ToString('HH:mm:ss')))"
        } else {
            Write-Output "Job submission failed, will retry"
        }

        Write-Output ""

        # Sleep for interval
        Start-Sleep -Seconds ($IntervalMinutes * 60)
    }
}

Write-Output ""
Write-Output "=== Scheduler Stopped ==="
