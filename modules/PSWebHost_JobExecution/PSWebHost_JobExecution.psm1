#Requires -Version 7

<#
.SYNOPSIS
    Job submission and execution system for PSWebHost

.DESCRIPTION
    Provides functions to submit, execute, and manage jobs in PSWebHost.
    Supports three execution modes:
    - Main loop (debug role only)
    - Dedicated runspace (task_manager, debug, system_admin, site_admin)
    - Background job (same roles as runspace)
#>

$ErrorActionPreference = 'Stop'

#region Job Tracking

# Initialize global job tracking (synchronized for thread safety)
if (-not $Global:PSWebServer.RunningJobs) {
    $Global:PSWebServer.RunningJobs = [hashtable]::Synchronized(@{})
}

function Register-RunningJob {
    <#
    .SYNOPSIS
        Registers a job in the running jobs tracker
    #>
    param(
        [string]$JobID,
        [hashtable]$JobSubmission,
        [object]$JobObject = $null,  # PowerShell Job object for BackgroundJob mode
        [System.Management.Automation.Runspaces.Runspace]$Runspace = $null  # Runspace for Runspace mode
    )

    $Global:PSWebServer.RunningJobs[$JobID] = @{
        JobID = $JobID
        JobName = $JobSubmission.JobName
        UserID = $JobSubmission.UserID
        SessionID = $JobSubmission.SessionID
        Command = $JobSubmission.Command
        Description = $JobSubmission.Description
        ExecutionMode = $JobSubmission.ExecutionMode
        StartTime = Get-Date
        Status = 'Running'
        JobObject = $JobObject
        Runspace = $Runspace
    }
}

function Unregister-RunningJob {
    <#
    .SYNOPSIS
        Removes a job from the running jobs tracker
    #>
    param([string]$JobID)

    if ($Global:PSWebServer.RunningJobs.ContainsKey($JobID)) {
        $Global:PSWebServer.RunningJobs.Remove($JobID)
    }
}

#endregion

#region Job Submission

function Submit-PSWebHostJob {
    <#
    .SYNOPSIS
        Submits a job for execution in PSWebHost

    .PARAMETER UserID
        User ID submitting the job

    .PARAMETER SessionID
        Session ID for tracking

    .PARAMETER JobName
        Name of the job

    .PARAMETER Command
        PowerShell command to execute

    .PARAMETER Description
        Description of the job

    .PARAMETER ExecutionMode
        Execution mode: MainLoop, Runspace, or BackgroundJob

    .PARAMETER Roles
        User roles for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [Parameter(Mandatory)]
        [string]$SessionID,

        [Parameter(Mandatory)]
        [string]$JobName,

        [Parameter(Mandatory)]
        [string]$Command,

        [string]$Description = '',

        [Parameter(Mandatory)]
        [ValidateSet('MainLoop', 'Runspace', 'BackgroundJob')]
        [string]$ExecutionMode,

        [Parameter(Mandatory)]
        [string[]]$Roles
    )

    try {
        # Validate execution mode against roles
        $isDebug = $Roles -contains 'debug'
        $hasElevatedRoles = ($Roles -contains 'task_manager') -or
                           ($Roles -contains 'system_admin') -or
                           ($Roles -contains 'site_admin') -or
                           $isDebug

        if ($ExecutionMode -eq 'MainLoop' -and -not $isDebug) {
            throw "MainLoop execution mode requires 'debug' role"
        }

        if ($ExecutionMode -in @('Runspace', 'BackgroundJob') -and -not $hasElevatedRoles) {
            throw "Runspace/BackgroundJob execution requires elevated roles (task_manager, debug, system_admin, or site_admin)"
        }

        # Get data directory
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        $submissionDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission\$UserID"
        if (-not (Test-Path $submissionDir)) {
            New-Item -Path $submissionDir -ItemType Directory -Force | Out-Null
        }

        # Create submission file
        $jobGuid = [Guid]::NewGuid().ToString()
        $fileName = "${SessionID}_${JobName}_${jobGuid}.json"
        $filePath = Join-Path $submissionDir $fileName

        $submission = @{
            JobID = $jobGuid
            UserID = $UserID
            SessionID = $SessionID
            JobName = $JobName
            Command = $Command
            Description = $Description
            ExecutionMode = $ExecutionMode
            Roles = $Roles
            SubmittedAt = (Get-Date).ToString('o')
            Status = 'Pending'
        }

        $submission | ConvertTo-Json -Depth 10 | Set-Content -Path $filePath -Force

        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "Job submitted: $JobName" -Data @{
            JobID = $jobGuid
            UserID = $UserID
            ExecutionMode = $ExecutionMode
        }

        return @{
            Success = $true
            JobID = $jobGuid
            SubmissionFile = $filePath
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to submit job: $($_.Exception.Message)" -Data @{
            UserID = $UserID
            JobName = $JobName
            Error = $_.Exception.ToString()
        }
        throw
    }
}

#endregion

#region Job Execution

function Invoke-PSWebHostJobInMainLoop {
    <#
    .SYNOPSIS
        Executes a job in the main loop (blocking, debug role only)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$JobSubmission,

        [Parameter(Mandatory)]
        [string]$ResultsDir
    )

    $startTime = Get-Date
    $output = @()
    $errorOccurred = $false
    $errorMessage = $null

    try {
        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[MainLoop] Starting job: $($JobSubmission.JobName)" -Data @{
            JobID = $JobSubmission.JobID
            UserID = $JobSubmission.UserID
        }

        # Register as running (even though it's blocking)
        Register-RunningJob -JobID $JobSubmission.JobID -JobSubmission $JobSubmission

        # Execute in current runspace, capturing all output
        $output = Invoke-Expression -Command $JobSubmission.Command 2>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) {
                $errorOccurred = $true
                "[ERROR] $($_.Exception.Message)`n$($_.ScriptStackTrace)"
            } else {
                $_.ToString()
            }
        }
    }
    catch {
        $errorOccurred = $true
        $errorMessage = $_.Exception.Message
        $output += "[EXCEPTION] $errorMessage`n$($_.ScriptStackTrace)"
    }
    finally {
        # Unregister job
        Unregister-RunningJob -JobID $JobSubmission.JobID

        $endTime = Get-Date
        $runtime = ($endTime - $startTime).TotalSeconds

        # Save results
        Save-PSWebHostJobResult -JobSubmission $JobSubmission -StartTime $startTime -EndTime $endTime -Runtime $runtime -Output $output -Success (-not $errorOccurred) -ResultsDir $ResultsDir
    }
}

function Invoke-PSWebHostJobInRunspace {
    <#
    .SYNOPSIS
        Executes a job in a dedicated runspace (non-blocking)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$JobSubmission,

        [Parameter(Mandatory)]
        [string]$ResultsDir
    )

    try {
        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[Runspace] Starting job: $($JobSubmission.JobName)" -Data @{
            JobID = $JobSubmission.JobID
            UserID = $JobSubmission.UserID
        }

        # Create runspace
        $runspace = [runspacefactory]::CreateRunspace()
        $runspace.Open()

        # Set global variables in runspace
        $runspace.SessionStateProxy.SetVariable('PSWebServer', $global:PSWebServer)
        $runspace.SessionStateProxy.SetVariable('JobSubmission', $JobSubmission)
        $runspace.SessionStateProxy.SetVariable('ResultsDir', $ResultsDir)

        # Create script block
        $scriptBlock = {
            $startTime = Get-Date
            $output = @()
            $errorOccurred = $false

            try {
                # Import required modules
                if ($global:PSWebServer.Project_Root.Path) {
                    $modulePath = Join-Path $global:PSWebServer.Project_Root.Path "modules\PSWebHost_Support\PSWebHost_Support.psd1"
                    if (Test-Path $modulePath) {
                        Import-Module $modulePath -DisableNameChecking -ErrorAction SilentlyContinue
                    }
                }

                # Execute command
                $output = Invoke-Expression -Command $JobSubmission.Command 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        $errorOccurred = $true
                        "[ERROR] $($_.Exception.Message)`n$($_.ScriptStackTrace)"
                    } else {
                        $_.ToString()
                    }
                }
            }
            catch {
                $errorOccurred = $true
                $output += "[EXCEPTION] $($_.Exception.Message)`n$($_.ScriptStackTrace)"
            }
            finally {
                $endTime = Get-Date
                $runtime = ($endTime - $startTime).TotalSeconds

                # Save result
                $resultFile = Join-Path $ResultsDir "$($JobSubmission.JobID).json"
                $result = @{
                    JobID = $JobSubmission.JobID
                    UserID = $JobSubmission.UserID
                    SessionID = $JobSubmission.SessionID
                    JobName = $JobSubmission.JobName
                    Command = $JobSubmission.Command
                    Description = $JobSubmission.Description
                    ExecutionMode = $JobSubmission.ExecutionMode
                    DateStarted = $startTime.ToString('o')
                    DateCompleted = $endTime.ToString('o')
                    Runtime = $runtime
                    Output = ($output -join "`n")
                    Success = (-not $errorOccurred)
                }

                $result | ConvertTo-Json -Depth 10 | Set-Content -Path $resultFile -Force
            }
        }

        # Execute in runspace
        $powershell = [powershell]::Create()
        $powershell.Runspace = $runspace
        $powershell.AddScript($scriptBlock) | Out-Null
        $asyncResult = $powershell.BeginInvoke()

        # Store runspace info for tracking
        $runspaceId = $runspace.InstanceId
        if (-not $global:PSWebServer.Runspaces) {
            $global:PSWebServer.Runspaces = [hashtable]::Synchronized(@{})
        }

        $global:PSWebServer.Runspaces[$runspaceId] = @{
            Runspace = $runspace
            PowerShell = $powershell
            AsyncResult = $asyncResult
            JobID = $JobSubmission.JobID
            StartTime = Get-Date
            Type = 'JobExecution'
        }

        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[Runspace] Job started in runspace" -Data @{
            JobID = $JobSubmission.JobID
            RunspaceID = $runspaceId
        }

        return @{
            Success = $true
            RunspaceID = $runspaceId
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "[Runspace] Failed to start job: $($_.Exception.Message)" -Data @{
            JobID = $JobSubmission.JobID
            Error = $_.Exception.ToString()
        }
        throw
    }
}

function Invoke-PSWebHostJobAsBackgroundJob {
    <#
    .SYNOPSIS
        Executes a job as a PowerShell background job
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$JobSubmission,

        [Parameter(Mandatory)]
        [string]$ResultsDir
    )

    try {
        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[BackgroundJob] Starting job: $($JobSubmission.JobName)" -Data @{
            JobID = $JobSubmission.JobID
            UserID = $JobSubmission.UserID
        }

        $job = Start-Job -Name "PSWebHostJob_$($JobSubmission.JobID)" -ScriptBlock {
            param($JobSubmission, $ResultsDir, $PSWebServerPath)

            $startTime = Get-Date
            $output = @()
            $errorOccurred = $false

            try {
                # Import modules if available
                if ($PSWebServerPath) {
                    $modulePath = Join-Path $PSWebServerPath "modules\PSWebHost_Support\PSWebHost_Support.psd1"
                    if (Test-Path $modulePath) {
                        Import-Module $modulePath -DisableNameChecking -ErrorAction SilentlyContinue
                    }
                }

                # Execute command
                $output = Invoke-Expression -Command $JobSubmission.Command 2>&1 | ForEach-Object {
                    if ($_ -is [System.Management.Automation.ErrorRecord]) {
                        $errorOccurred = $true
                        "[ERROR] $($_.Exception.Message)"
                    } else {
                        $_.ToString()
                    }
                }
            }
            catch {
                $errorOccurred = $true
                $output += "[EXCEPTION] $($_.Exception.Message)"
            }
            finally {
                $endTime = Get-Date
                $runtime = ($endTime - $startTime).TotalSeconds

                # Save result
                $resultFile = Join-Path $ResultsDir "$($JobSubmission.JobID).json"
                $result = @{
                    JobID = $JobSubmission.JobID
                    UserID = $JobSubmission.UserID
                    SessionID = $JobSubmission.SessionID
                    JobName = $JobSubmission.JobName
                    Command = $JobSubmission.Command
                    Description = $JobSubmission.Description
                    ExecutionMode = $JobSubmission.ExecutionMode
                    DateStarted = $startTime.ToString('o')
                    DateCompleted = $endTime.ToString('o')
                    Runtime = $runtime
                    Output = ($output -join "`n")
                    Success = (-not $errorOccurred)
                }

                $result | ConvertTo-Json -Depth 10 | Set-Content -Path $resultFile -Force
            }
        } -ArgumentList $JobSubmission, $ResultsDir, $Global:PSWebServer.Project_Root.Path

        # Register the running job with the PowerShell Job object
        Register-RunningJob -JobID $JobSubmission.JobID -JobSubmission $JobSubmission -JobObject $job

        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[BackgroundJob] Job started" -Data @{
            JobID = $JobSubmission.JobID
            PSJobID = $job.Id
        }

        # Start a background cleanup task to unregister when complete
        Start-Job -Name "Cleanup_$($JobSubmission.JobID)" -ScriptBlock {
            param($JobID, $PSJobObject)
            # Wait for job to complete
            Wait-Job -Job $PSJobObject | Out-Null
            # Signal completion (the job will be unregistered by the cleanup process)
        } -ArgumentList $JobSubmission.JobID, $job | Out-Null

        return @{
            Success = $true
            PSJobID = $job.Id
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "[BackgroundJob] Failed to start job: $($_.Exception.Message)" -Data @{
            JobID = $JobSubmission.JobID
            Error = $_.Exception.ToString()
        }
        throw
    }
}

function Save-PSWebHostJobResult {
    <#
    .SYNOPSIS
        Saves job execution results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$JobSubmission,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [Parameter(Mandatory)]
        [double]$Runtime,

        [Parameter(Mandatory)]
        $Output,

        [Parameter(Mandatory)]
        [bool]$Success,

        [Parameter(Mandatory)]
        [string]$ResultsDir
    )

    try {
        $resultFile = Join-Path $ResultsDir "$($JobSubmission.JobID).json"

        $result = @{
            JobID = $JobSubmission.JobID
            UserID = $JobSubmission.UserID
            SessionID = $JobSubmission.SessionID
            JobName = $JobSubmission.JobName
            Command = $JobSubmission.Command
            Description = $JobSubmission.Description
            ExecutionMode = $JobSubmission.ExecutionMode
            DateStarted = $StartTime.ToString('o')
            DateCompleted = $EndTime.ToString('o')
            Runtime = $Runtime
            Output = if ($Output -is [array]) { $Output -join "`n" } else { $Output.ToString() }
            Success = $Success
        }

        $result | ConvertTo-Json -Depth 10 | Set-Content -Path $resultFile -Force

        Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "Job result saved: $($JobSubmission.JobName)" -Data @{
            JobID = $JobSubmission.JobID
            Success = $Success
            Runtime = $Runtime
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to save job result: $($_.Exception.Message)" -Data @{
            JobID = $JobSubmission.JobID
            Error = $_.Exception.ToString()
        }
    }
}

#endregion

#region Job Processing

function Process-PSWebHostJobSubmissions {
    <#
    .SYNOPSIS
        Processes pending job submissions (called from main loop)
    #>
    [CmdletBinding()]
    param()

    try {
        # First, clean up completed running jobs
        Update-PSWebHostRunningJobs

        # Get data directory
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        $submissionRoot = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission"
        if (-not (Test-Path $submissionRoot)) {
            return
        }

        $outputDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobOutput"
        $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"

        # Ensure output and results directories exist
        if (-not (Test-Path $outputDir)) {
            New-Item -Path $outputDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $resultsDir)) {
            New-Item -Path $resultsDir -ItemType Directory -Force | Out-Null
        }

        # Get all submission files
        $submissionFiles = Get-ChildItem -Path $submissionRoot -Filter "*.json" -Recurse -File

        foreach ($file in $submissionFiles) {
            try {
                # Read submission
                $submission = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json

                # Convert to hashtable for easier manipulation
                $submissionHash = @{}
                $submission.PSObject.Properties | ForEach-Object {
                    $submissionHash[$_.Name] = $_.Value
                }

                # Move file to output directory
                $outputFile = Join-Path $outputDir $file.Name
                Move-Item -Path $file.FullName -Destination $outputFile -Force

                # Execute based on mode
                switch ($submissionHash.ExecutionMode) {
                    'MainLoop' {
                        # Execute in main loop (blocking)
                        Invoke-PSWebHostJobInMainLoop -JobSubmission $submissionHash -ResultsDir $resultsDir
                    }
                    'Runspace' {
                        # Execute in dedicated runspace (non-blocking)
                        Invoke-PSWebHostJobInRunspace -JobSubmission $submissionHash -ResultsDir $resultsDir
                    }
                    'BackgroundJob' {
                        # Execute as background job (non-blocking)
                        Invoke-PSWebHostJobAsBackgroundJob -JobSubmission $submissionHash -ResultsDir $resultsDir
                    }
                }
            }
            catch {
                Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to process job submission: $($_.Exception.Message)" -Data @{
                    File = $file.FullName
                    Error = $_.Exception.ToString()
                }
            }
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to process job submissions: $($_.Exception.Message)"
    }
}

#endregion

#region Job Results

function Get-PSWebHostJobResults {
    <#
    .SYNOPSIS
        Gets job execution results for a user
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [int]$MaxResults = 100
    )

    try {
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"
        if (-not (Test-Path $resultsDir)) {
            return @()
        }

        # Get all result files for user
        $resultFiles = Get-ChildItem -Path $resultsDir -Filter "*.json" -File |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First $MaxResults

        $results = @()
        foreach ($file in $resultFiles) {
            try {
                $result = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                if ($result.UserID -eq $UserID) {
                    $results += $result
                }
            }
            catch {
                Write-PSWebHostLog -Severity 'Warning' -Category 'JobExecution' -Message "Failed to read result file: $($file.FullName)"
            }
        }

        return $results
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to get job results: $($_.Exception.Message)"
        return @()
    }
}

function Remove-PSWebHostJobResults {
    <#
    .SYNOPSIS
        Removes job execution results
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID
    )

    try {
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"
        $resultFile = Join-Path $resultsDir "$JobID.json"

        if (Test-Path $resultFile) {
            Remove-Item -Path $resultFile -Force
            Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "Job result deleted: $JobID"
            return $true
        }

        return $false
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to remove job result: $($_.Exception.Message)"
        return $false
    }
}

#endregion

#region Job Cleanup

function Update-PSWebHostRunningJobs {
    <#
    .SYNOPSIS
        Updates the running jobs tracker by removing completed jobs
        Should be called periodically from the main loop
    #>
    [CmdletBinding()]
    param()

    if (-not $Global:PSWebServer.RunningJobs) {
        return
    }

    $jobsToRemove = @()

    foreach ($jobEntry in $Global:PSWebServer.RunningJobs.GetEnumerator()) {
        $job = $jobEntry.Value

        # Check if BackgroundJob has completed
        if ($job.ExecutionMode -eq 'BackgroundJob' -and $job.JobObject) {
            $psJob = Get-Job -Id $job.JobObject.Id -ErrorAction SilentlyContinue

            if (-not $psJob -or $psJob.State -in @('Completed', 'Failed', 'Stopped')) {
                $jobsToRemove += $job.JobID

                # Clean up the PowerShell job
                if ($psJob) {
                    Remove-Job -Job $psJob -Force -ErrorAction SilentlyContinue
                }

                Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "[Cleanup] Removed completed job from tracker: $($job.JobName)" -Data @{
                    JobID = $job.JobID
                    ExecutionMode = $job.ExecutionMode
                }
            }
        }
    }

    # Remove completed jobs from tracker
    foreach ($jobID in $jobsToRemove) {
        Unregister-RunningJob -JobID $jobID
    }
}

#endregion

#region Job Manipulation

function Get-PSWebHostJobs {
    <#
    .SYNOPSIS
        Gets all jobs (pending, running, completed) for a user

    .PARAMETER UserID
        User ID to filter jobs

    .PARAMETER IncludePending
        Include pending jobs from JobSubmission directory

    .PARAMETER IncludeRunning
        Include running jobs from tracking hashtable

    .PARAMETER IncludeCompleted
        Include completed jobs from JobResults directory

    .PARAMETER MaxResults
        Maximum number of completed results to include
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$UserID,

        [switch]$IncludePending,
        [switch]$IncludeRunning,
        [switch]$IncludeCompleted,
        [int]$MaxResults = 100
    )

    $jobs = @{
        Pending = @()
        Running = @()
        Completed = @()
    }

    try {
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        # Get pending jobs
        if ($IncludePending) {
            $submissionDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission\$UserID"
            if (Test-Path $submissionDir) {
                $pendingFiles = Get-ChildItem -Path $submissionDir -Filter "*.json" -File | Sort-Object LastWriteTime -Descending

                foreach ($file in $pendingFiles) {
                    try {
                        $submission = Get-Content -Path $file.FullName -Raw | ConvertFrom-Json
                        $jobs.Pending += @{
                            JobID = $submission.JobID
                            JobName = $submission.JobName
                            Description = $submission.Description
                            ExecutionMode = $submission.ExecutionMode
                            SubmittedAt = $submission.SubmittedAt
                            Status = 'Pending'
                        }
                    } catch {
                        Write-PSWebHostLog -Severity 'Warning' -Category 'JobExecution' -Message "Failed to read pending job: $($file.Name)"
                    }
                }
            }
        }

        # Get running jobs
        if ($IncludeRunning -and $Global:PSWebServer.RunningJobs) {
            $runningJobs = $Global:PSWebServer.RunningJobs.Values | Where-Object { $_.UserID -eq $UserID }

            foreach ($job in $runningJobs) {
                $runtime = ((Get-Date) - $job.StartTime).TotalSeconds
                $jobs.Running += @{
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
        if ($IncludeCompleted) {
            $jobs.Completed = Get-PSWebHostJobResults -UserID $UserID -MaxResults $MaxResults
        }

        return $jobs
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to get jobs: $($_.Exception.Message)"
        return $jobs
    }
}

function Get-PSWebHostJobStatus {
    <#
    .SYNOPSIS
        Gets the status of a specific job

    .PARAMETER JobID
        The job ID to query

    .PARAMETER UserID
        User ID for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    try {
        # Check if running
        if ($Global:PSWebServer.RunningJobs -and $Global:PSWebServer.RunningJobs.ContainsKey($JobID)) {
            $job = $Global:PSWebServer.RunningJobs[$JobID]

            # Verify user owns this job
            if ($job.UserID -ne $UserID) {
                throw "Access denied: Job belongs to different user"
            }

            $runtime = ((Get-Date) - $job.StartTime).TotalSeconds
            return @{
                JobID = $job.JobID
                JobName = $job.JobName
                Description = $job.Description
                ExecutionMode = $job.ExecutionMode
                StartedAt = $job.StartTime.ToString('o')
                Runtime = [math]::Round($runtime, 2)
                Status = 'Running'
                CanStop = ($job.JobObject -ne $null)  # Can stop BackgroundJob and Runspace modes
            }
        }

        # Check if completed
        $dataRoot = if ($Global:PSWebServer.DataPath) {
            $Global:PSWebServer.DataPath
        } else {
            Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
        }

        $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"
        $resultFile = Join-Path $resultsDir "$JobID.json"

        if (Test-Path $resultFile) {
            $result = Get-Content -Path $resultFile -Raw | ConvertFrom-Json

            # Verify user owns this job
            if ($result.UserID -ne $UserID) {
                throw "Access denied: Job belongs to different user"
            }

            return @{
                JobID = $result.JobID
                JobName = $result.JobName
                Description = $result.Description
                ExecutionMode = $result.ExecutionMode
                StartedAt = $result.DateStarted
                CompletedAt = $result.DateCompleted
                Runtime = $result.Runtime
                Status = if ($result.Success) { 'Completed' } else { 'Failed' }
                Success = $result.Success
                Output = $result.Output
            }
        }

        # Check if pending
        $submissionDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobSubmission\$UserID"
        if (Test-Path $submissionDir) {
            $pendingFiles = @(Get-ChildItem -Path $submissionDir -Filter "*$JobID*.json" -File)

            if ($pendingFiles -and $pendingFiles.Count -gt 0) {
                $submission = Get-Content -Path $pendingFiles[0].FullName -Raw | ConvertFrom-Json
                return @{
                    JobID = $submission.JobID
                    JobName = $submission.JobName
                    Description = $submission.Description
                    ExecutionMode = $submission.ExecutionMode
                    SubmittedAt = $submission.SubmittedAt
                    Status = 'Pending'
                }
            }
        }

        # Job not found
        throw "Job not found: $JobID"
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to get job status: $($_.Exception.Message)"
        throw
    }
}

function Stop-PSWebHostJob {
    <#
    .SYNOPSIS
        Stops a running job

    .PARAMETER JobID
        The job ID to stop

    .PARAMETER UserID
        User ID for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    try {
        # Check if job is running
        if (-not $Global:PSWebServer.RunningJobs -or -not $Global:PSWebServer.RunningJobs.ContainsKey($JobID)) {
            throw "Job is not running: $JobID"
        }

        $job = $Global:PSWebServer.RunningJobs[$JobID]

        # Verify user owns this job
        if ($job.UserID -ne $UserID) {
            throw "Access denied: Job belongs to different user"
        }

        $stopped = $false

        # Stop based on execution mode
        switch ($job.ExecutionMode) {
            'BackgroundJob' {
                if ($job.JobObject) {
                    Stop-Job -Job $job.JobObject -ErrorAction SilentlyContinue
                    Remove-Job -Job $job.JobObject -Force -ErrorAction SilentlyContinue
                    $stopped = $true
                }
            }
            'Runspace' {
                if ($job.Runspace) {
                    $job.Runspace.Close()
                    $job.Runspace.Dispose()
                    $stopped = $true
                }
            }
            'MainLoop' {
                # Cannot stop main loop jobs (they block)
                throw "Cannot stop MainLoop jobs - they execute synchronously"
            }
        }

        if ($stopped) {
            # Save a result indicating the job was stopped
            $dataRoot = if ($Global:PSWebServer.DataPath) {
                $Global:PSWebServer.DataPath
            } else {
                Join-Path $PSScriptRoot "..\..\PsWebHost_Data"
            }

            $resultsDir = Join-Path $dataRoot "apps\WebHostTaskManagement\JobResults"
            $resultFile = Join-Path $resultsDir "$JobID.json"

            $result = @{
                JobID = $job.JobID
                UserID = $job.UserID
                SessionID = $job.SessionID
                JobName = $job.JobName
                Command = $job.Command
                Description = $job.Description
                ExecutionMode = $job.ExecutionMode
                DateStarted = $job.StartTime.ToString('o')
                DateCompleted = (Get-Date).ToString('o')
                Runtime = ((Get-Date) - $job.StartTime).TotalSeconds
                Output = "[Job stopped by user]"
                Success = $false
            }

            $result | ConvertTo-Json -Depth 10 | Set-Content -Path $resultFile -Force

            # Unregister the job
            Unregister-RunningJob -JobID $JobID

            Write-PSWebHostLog -Severity 'Info' -Category 'JobExecution' -Message "Job stopped: $($job.JobName)" -Data @{
                JobID = $JobID
                UserID = $UserID
            }

            return @{
                Success = $true
                Message = "Job stopped successfully"
            }
        }

        throw "Failed to stop job"
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to stop job: $($_.Exception.Message)"
        throw
    }
}

function Get-PSWebHostJobOutput {
    <#
    .SYNOPSIS
        Gets live output from a running job (BackgroundJob mode only)

    .PARAMETER JobID
        The job ID to get output from

    .PARAMETER UserID
        User ID for permission checking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    try {
        # Check if job is running
        if (-not $Global:PSWebServer.RunningJobs -or -not $Global:PSWebServer.RunningJobs.ContainsKey($JobID)) {
            throw "Job is not running: $JobID"
        }

        $job = $Global:PSWebServer.RunningJobs[$JobID]

        # Verify user owns this job
        if ($job.UserID -ne $UserID) {
            throw "Access denied: Job belongs to different user"
        }

        # Only BackgroundJob mode supports live output via Receive-Job
        if ($job.ExecutionMode -ne 'BackgroundJob' -or -not $job.JobObject) {
            return @{
                Success = $false
                Message = "Live output only available for BackgroundJob execution mode"
                Output = ""
            }
        }

        # Get output without removing it from the job (using -Keep)
        $output = Receive-Job -Job $job.JobObject -Keep 2>&1 | Out-String

        return @{
            Success = $true
            Output = $output
            Runtime = ((Get-Date) - $job.StartTime).TotalSeconds
            State = $job.JobObject.State
        }
    }
    catch {
        Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Failed to get job output: $($_.Exception.Message)"
        throw
    }
}

#endregion

Export-ModuleMember -Function @(
    'Submit-PSWebHostJob',
    'Get-PSWebHostJobResults',
    'Remove-PSWebHostJobResults',
    'Process-PSWebHostJobSubmissions',
    'Invoke-PSWebHostJobInMainLoop',
    'Invoke-PSWebHostJobInRunspace',
    'Invoke-PSWebHostJobAsBackgroundJob',
    'Update-PSWebHostRunningJobs',
    'Get-PSWebHostJobs',
    'Get-PSWebHostJobStatus',
    'Stop-PSWebHostJob',
    'Get-PSWebHostJobOutput'
)
