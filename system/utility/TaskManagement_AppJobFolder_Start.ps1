#Requires -Version 7

<#
.SYNOPSIS
    Starts a job from an app's jobs folder

.DESCRIPTION
    Starts a job using the new PSWebHost_Jobs module
    Requires the server to be running with the module loaded

.PARAMETER AppName
    The app name where the job is located

.PARAMETER JobName
    The name of the job to start

.PARAMETER UserID
    The user ID starting the job (default: current user or 'system')

.PARAMETER SessionID
    Optional session ID

.PARAMETER Variables
    Hashtable of variables for template substitution

.PARAMETER Roles
    User roles for permission checking (default: @('admin'))

.EXAMPLE
    .\TaskManagement_AppJobFolder_Start.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics"

.EXAMPLE
    .\TaskManagement_AppJobFolder_Start.ps1 -AppName "WebHostMetrics" -JobName "CollectMetrics" -Variables @{Interval=60}
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppName,

    [Parameter(Mandatory)]
    [string]$JobName,

    [string]$UserID,

    [string]$SessionID,

    [hashtable]$Variables = @{},

    [string[]]$Roles = @('admin')
)

$MyTag = '[TaskManagement:AppJobFolder:Start]'

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

    # Initialize job system if not already done
    if (-not $Global:PSWebServer.Jobs) {
        Initialize-PSWebHostJobSystem
        Write-Verbose "$MyTag Initialized job system"
    }

    # Refresh catalog
    $catalog = Get-PSWebHostJobCatalog -ProjectRoot $projectRoot
    $Global:PSWebServer.Jobs.Catalog = $catalog
    Write-Verbose "$MyTag Refreshed job catalog (found $($catalog.Count) jobs)"

    # Build JobID
    $jobID = "$AppName/$JobName"

    # Check if job exists
    if (-not $catalog.ContainsKey($jobID)) {
        throw "Job not found: $jobID"
    }

    # Get UserID
    if (-not $UserID) {
        $UserID = if ($env:USERNAME) { $env:USERNAME } else { 'system' }
    }

    Write-Host "$MyTag Starting job: $jobID" -ForegroundColor Cyan
    Write-Host "$MyTag UserID: $UserID" -ForegroundColor Gray
    if ($Variables.Count -gt 0) {
        Write-Host "$MyTag Variables: $($Variables.Keys -join ', ')" -ForegroundColor Gray
    }

    # Start the job
    $result = Start-PSWebHostJob -JobID $jobID -UserID $UserID -SessionID $SessionID -Variables $Variables -Roles $Roles

    Write-Host ""
    Write-Host "$MyTag Job started successfully!" -ForegroundColor Green
    Write-Host "$MyTag ExecutionID: $($result.ExecutionID)" -ForegroundColor Green
    Write-Host "$MyTag Status: $($result.Status)" -ForegroundColor Green
    Write-Host ""

    # Process command queue to actually start the job
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
