#Requires -Version 7

<#
.SYNOPSIS
    Stops a running job from an app's jobs folder

.DESCRIPTION
    Stops a running job using the new PSWebHost_Jobs module
    Requires the server to be running with the module loaded

.PARAMETER AppName
    The app name where the job is located

.PARAMETER JobName
    The name of the job to stop

.PARAMETER UserID
    The user ID stopping the job (default: current user or 'system')

.PARAMETER Roles
    User roles for permission checking (default: @('admin'))

.EXAMPLE
    .\TaskManagement_AppJobFolder_Stop.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppName,

    [Parameter(Mandatory)]
    [string]$JobName,

    [string]$UserID,

    [string[]]$Roles = @('admin')
)

$MyTag = '[TaskManagement:AppJobFolder:Stop]'

try {
    # Get project root
    $projectRoot = if ($Global:PSWebServer.Project_Root.Path) {
        $Global:PSWebServer.Project_Root.Path
    } else {
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    }

    # Import PSWebHost_Jobs module
    $modulePath = Join-Path $projectRoot "modules\PSWebHost_Jobs\PSWebHost_Jobs.psd1"
    if (-not (Test-Path $modulePath)) {
        throw "PSWebHost_Jobs module not found at: $modulePath"
    }

    Import-Module $modulePath -DisableNameChecking -Force -ErrorAction Stop
    Write-Verbose "$MyTag Imported PSWebHost_Jobs module"

    # Build JobID
    $jobID = "$AppName/$JobName"

    # Get UserID
    if (-not $UserID) {
        $UserID = if ($env:USERNAME) { $env:USERNAME } else { 'system' }
    }

    Write-Host "$MyTag Stopping job: $jobID" -ForegroundColor Cyan
    Write-Host "$MyTag UserID: $UserID" -ForegroundColor Gray

    # Check if job is running
    $runningJobs = Get-PSWebHostRunningJobs -UserID $UserID
    $isRunning = $runningJobs | Where-Object { $_.JobID -eq $jobID }

    if (-not $isRunning) {
        Write-Warning "$MyTag Job is not currently running: $jobID"
        return @{
            JobID = $jobID
            Status = 'NotRunning'
        }
    }

    # Stop the job
    $result = Stop-PSWebHostJob -JobID $jobID -UserID $UserID -Roles $Roles

    Write-Host ""
    Write-Host "$MyTag Stop command queued successfully!" -ForegroundColor Green
    Write-Host "$MyTag Status: $($result.Status)" -ForegroundColor Green
    Write-Host ""

    # Process command queue to actually stop the job
    Write-Host "$MyTag Processing command queue..." -ForegroundColor Yellow
    $processed = Process-PSWebHostJobCommandQueue
    Write-Host "$MyTag Processed $processed command(s)" -ForegroundColor Yellow
    Write-Host ""

    # Show running jobs
    Write-Host "$MyTag Running jobs:" -ForegroundColor Cyan
    $runningJobs = Get-PSWebHostRunningJobs -UserID $UserID
    if ($runningJobs.Count -eq 0) {
        Write-Host "  No running jobs" -ForegroundColor Gray
    } else {
        foreach ($job in $runningJobs) {
            Write-Host "  - $($job.JobID) (ExecutionID: $($job.ExecutionID), Started: $($job.StartTime))" -ForegroundColor Gray
        }
    }
    Write-Host ""

    return $result
}
catch {
    Write-Error "$MyTag $_"
    throw
}
