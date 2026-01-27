#Requires -Version 7

<#
.SYNOPSIS
    Job System Architecture - Global Structure Initialization

.DESCRIPTION
    Defines the new job system architecture:
    - Jobs stored in apps/[appname]/jobs/[JobName]/
    - Central command queue for job control
    - Role-based access control from job.json
    - Template variable substitution
#>

function Initialize-PSWebHostJobSystem {
    <#
    .SYNOPSIS
        Initializes the global job system structure
    #>
    [CmdletBinding()]
    param()

    if (-not $Global:PSWebServer.Jobs) {
        $Global:PSWebServer.Jobs = [hashtable]::Synchronized(@{
            # PowerShell background jobs
            Jobs = @()

            # Command queue for job operations
            CommandQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()

            # Discovered jobs from all apps
            Catalog = @{}

            # Running job tracking
            Running = [hashtable]::Synchronized(@{})

            # Job history/results
            History = @()
        })
    }

    Write-Verbose "[JobSystem] Initialized global job structure"
}

function Get-PSWebHostJobCatalog {
    <#
    .SYNOPSIS
        Discovers all jobs from apps/*/jobs/ directories

    .DESCRIPTION
        Scans all enabled apps for job definitions
        Returns catalog of available jobs with metadata
    #>
    [CmdletBinding()]
    param(
        [string]$ProjectRoot = $Global:PSWebServer.Project_Root.Path
    )

    $catalog = @{}
    $appsDir = Join-Path $ProjectRoot "apps"

    if (-not (Test-Path $appsDir)) {
        Write-Warning "[JobSystem] Apps directory not found: $appsDir"
        return $catalog
    }

    # Scan each app
    $apps = Get-ChildItem -Path $appsDir -Directory

    foreach ($app in $apps) {
        $jobsDir = Join-Path $app.FullName "jobs"

        if (-not (Test-Path $jobsDir)) {
            continue
        }

        # Find all job directories (each contains job.json + script)
        $jobDirs = Get-ChildItem -Path $jobsDir -Directory

        foreach ($jobDir in $jobDirs) {
            $jobJsonPath = Join-Path $jobDir.FullName "job.json"

            if (-not (Test-Path $jobJsonPath)) {
                Write-Warning "[JobSystem] Missing job.json in: $($jobDir.FullName)"
                continue
            }

            try {
                # Load job metadata
                $jobJson = Get-Content -Path $jobJsonPath -Raw | ConvertFrom-Json

                # Build job ID (unique identifier)
                $jobId = "$($app.Name)/$($jobDir.Name)"

                $catalog[$jobId] = @{
                    JobID = $jobId
                    AppName = $app.Name
                    JobName = $jobDir.Name
                    Name = $jobJson.Name
                    Description = $jobJson.Description
                    ScriptPath = Join-Path $jobDir.FullName $jobJson.ScriptRelativePath
                    JobDirectory = $jobDir.FullName
                    Metadata = $jobJson
                    LastScanned = Get-Date
                }

                Write-Verbose "[JobSystem] Discovered job: $jobId"
            }
            catch {
                Write-Warning "[JobSystem] Failed to load job metadata from $jobJsonPath : $($_.Exception.Message)"
            }
        }
    }

    return $catalog
}

function Initialize-PSWebHostJob {
    <#
    .SYNOPSIS
        Initializes a job by running init-job.ps1 and parsing job.json with variable substitution

    .PARAMETER JobID
        The job identifier (AppName/JobName)

    .PARAMETER Variables
        Hashtable of variables for template substitution
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [hashtable]$Variables = @{}
    )

    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog.ContainsKey($JobID)) {
        throw "Job not found in catalog: $JobID"
    }

    $jobInfo = $catalog[$JobID]
    $jobDir = $jobInfo.JobDirectory

    # Run init-job.ps1 if it exists
    $initScript = Join-Path $jobDir "init-job.ps1"
    if (Test-Path $initScript) {
        Write-Verbose "[JobSystem] Running init script: $initScript"

        try {
            # Execute init script in current scope to populate variables
            . $initScript -Variables $Variables
        }
        catch {
            Write-Error "[JobSystem] Init script failed for $JobID : $($_.Exception.Message)"
            throw
        }
    }

    # Parse job.json with template substitution
    $jobJsonPath = Join-Path $jobDir "job.json"
    $jobJsonRaw = Get-Content -Path $jobJsonPath -Raw

    # Find all template variables {{VarName}}
    $templateVars = [regex]::Matches($jobJsonRaw, '\{\{(\w+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique

    # Check for missing variables
    $missingVars = @()
    foreach ($varName in $templateVars) {
        if (-not $Variables.ContainsKey($varName)) {
            $missingVars += $varName
        }
    }

    if ($missingVars.Count -gt 0) {
        Write-Error "[JobSystem] Job $JobID requires variables that are not set: $($missingVars -join ', ')"
        throw "Missing required variables: $($missingVars -join ', ')"
    }

    # Perform substitution
    $jobJsonProcessed = $jobJsonRaw
    foreach ($varName in $templateVars) {
        $value = $Variables[$varName]
        $jobJsonProcessed = $jobJsonProcessed -replace "\{\{$varName\}\}", $value
    }

    # Parse processed JSON
    $jobMetadata = $jobJsonProcessed | ConvertFrom-Json

    return @{
        JobID = $JobID
        Metadata = $jobMetadata
        ScriptPath = Join-Path $jobDir $jobMetadata.ScriptRelativePath
        Variables = $Variables
    }
}

function Test-PSWebHostJobPermission {
    <#
    .SYNOPSIS
        Checks if user has permission to perform action on job

    .PARAMETER JobID
        The job identifier

    .PARAMETER Action
        Action to check: start, stop, restart

    .PARAMETER Roles
        User's roles
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [ValidateSet('start', 'stop', 'restart')]
        [string]$Action,

        [Parameter(Mandatory)]
        [string[]]$Roles
    )

    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog.ContainsKey($JobID)) {
        return $false
    }

    $jobMetadata = $catalog[$JobID].Metadata

    # Get required roles for action
    $requiredRoles = switch ($Action) {
        'start' { $jobMetadata.roles_start }
        'stop' { $jobMetadata.roles_stop }
        'restart' { $jobMetadata.roles_restart }
    }

    if (-not $requiredRoles) {
        # No roles specified = allow all authenticated users
        return $true
    }

    # Check if user has any of the required roles
    foreach ($role in $Roles) {
        if ($requiredRoles -contains $role) {
            return $true
        }
    }

    return $false
}

function Get-PSWebHostJobDefinition {
    <#
    .SYNOPSIS
        Gets a job definition from the catalog
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID
    )

    $catalog = $Global:PSWebServer.Jobs.Catalog

    if (-not $catalog.ContainsKey($JobID)) {
        throw "Job not found in catalog: $JobID"
    }

    return $catalog[$JobID]
}

function Start-PSWebHostJob {
    <#
    .SYNOPSIS
        Starts a job by adding it to the command queue
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID,

        [string]$SessionID,

        [hashtable]$Variables = @{},

        [string[]]$Roles = @()
    )

    # Check permissions
    if (-not (Test-PSWebHostJobPermission -JobID $JobID -Action 'start' -Roles $Roles)) {
        throw "User does not have permission to start job: $JobID"
    }

    # Initialize job
    $jobInit = Initialize-PSWebHostJob -JobID $JobID -Variables $Variables

    # Generate unique execution ID
    $executionID = [guid]::NewGuid().ToString()

    # Add to command queue
    $command = @{
        Command = 'start'
        JobID = $JobID
        ExecutionID = $executionID
        UserID = $UserID
        SessionID = $SessionID
        ScriptPath = $jobInit.ScriptPath
        Metadata = $jobInit.Metadata
        Variables = $Variables
        Timestamp = Get-Date
    }

    $Global:PSWebServer.Jobs.CommandQueue.Enqueue($command)

    Write-Verbose "[JobSystem] Queued start command for job: $JobID (ExecutionID: $executionID)"

    return @{
        JobID = $JobID
        ExecutionID = $executionID
        Status = 'Queued'
    }
}

function Stop-PSWebHostJob {
    <#
    .SYNOPSIS
        Stops a running job by adding stop command to queue
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID,

        [string[]]$Roles = @()
    )

    # Check permissions
    if (-not (Test-PSWebHostJobPermission -JobID $JobID -Action 'stop' -Roles $Roles)) {
        throw "User does not have permission to stop job: $JobID"
    }

    # Add to command queue
    $command = @{
        Command = 'stop'
        JobID = $JobID
        UserID = $UserID
        Timestamp = Get-Date
    }

    $Global:PSWebServer.Jobs.CommandQueue.Enqueue($command)

    Write-Verbose "[JobSystem] Queued stop command for job: $JobID"

    return @{
        JobID = $JobID
        Status = 'StopQueued'
    }
}

function Restart-PSWebHostJob {
    <#
    .SYNOPSIS
        Restarts a job (stop then start)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$JobID,

        [Parameter(Mandatory)]
        [string]$UserID,

        [string]$SessionID,

        [hashtable]$Variables = @{},

        [string[]]$Roles = @()
    )

    # Check permissions
    if (-not (Test-PSWebHostJobPermission -JobID $JobID -Action 'restart' -Roles $Roles)) {
        throw "User does not have permission to restart job: $JobID"
    }

    # Add to command queue
    $command = @{
        Command = 'restart'
        JobID = $JobID
        UserID = $UserID
        SessionID = $SessionID
        Variables = $Variables
        Timestamp = Get-Date
    }

    $Global:PSWebServer.Jobs.CommandQueue.Enqueue($command)

    Write-Verbose "[JobSystem] Queued restart command for job: $JobID"

    return @{
        JobID = $JobID
        Status = 'RestartQueued'
    }
}

function Get-PSWebHostJobOutput {
    <#
    .SYNOPSIS
        Gets output from a running or completed job
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    # Add to command queue
    $command = @{
        Command = 'receive'
        ExecutionID = $ExecutionID
        UserID = $UserID
        Timestamp = Get-Date
    }

    $Global:PSWebServer.Jobs.CommandQueue.Enqueue($command)

    Write-Verbose "[JobSystem] Queued receive command for execution: $ExecutionID"

    # Check if output is already available in history
    $historyEntry = $Global:PSWebServer.Jobs.History | Where-Object { $_.ExecutionID -eq $ExecutionID -and $_.UserID -eq $UserID } | Select-Object -First 1

    if ($historyEntry) {
        return $historyEntry.Output
    }

    return $null
}

function Get-PSWebHostJobStatus {
    <#
    .SYNOPSIS
        Gets the status of a job execution
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionID,

        [Parameter(Mandatory)]
        [string]$UserID
    )

    # Check running jobs
    if ($Global:PSWebServer.Jobs.Running.ContainsKey($ExecutionID)) {
        $runningJob = $Global:PSWebServer.Jobs.Running[$ExecutionID]

        if ($runningJob.UserID -eq $UserID) {
            return @{
                ExecutionID = $ExecutionID
                JobID = $runningJob.JobID
                Status = 'Running'
                StartTime = $runningJob.StartTime
                UserID = $runningJob.UserID
            }
        }
    }

    # Check history
    $historyEntry = $Global:PSWebServer.Jobs.History | Where-Object { $_.ExecutionID -eq $ExecutionID -and $_.UserID -eq $UserID } | Select-Object -First 1

    if ($historyEntry) {
        return @{
            ExecutionID = $ExecutionID
            JobID = $historyEntry.JobID
            Status = $historyEntry.Status
            StartTime = $historyEntry.StartTime
            EndTime = $historyEntry.EndTime
            Output = $historyEntry.Output
            Success = $historyEntry.Success
            UserID = $historyEntry.UserID
        }
    }

    return $null
}

function Get-PSWebHostRunningJobs {
    <#
    .SYNOPSIS
        Gets all running jobs for a user
    #>
    [CmdletBinding()]
    param(
        [string]$UserID
    )

    $runningJobs = @()

    foreach ($executionID in $Global:PSWebServer.Jobs.Running.Keys) {
        $job = $Global:PSWebServer.Jobs.Running[$executionID]

        if (-not $UserID -or $job.UserID -eq $UserID) {
            $runningJobs += @{
                ExecutionID = $executionID
                JobID = $job.JobID
                StartTime = $job.StartTime
                UserID = $job.UserID
                PSJobID = $job.PSJobID
            }
        }
    }

    return $runningJobs
}

function Process-PSWebHostJobCommandQueue {
    <#
    .SYNOPSIS
        Processes commands from the job command queue
        Should be called from the main server loop
    #>
    [CmdletBinding()]
    param()

    $processedCount = 0
    $maxProcessPerCycle = 10

    while ($Global:PSWebServer.Jobs.CommandQueue.Count -gt 0 -and $processedCount -lt $maxProcessPerCycle) {
        $command = $null

        if ($Global:PSWebServer.Jobs.CommandQueue.TryDequeue([ref]$command)) {
            $processedCount++

            try {
                switch ($command.Command) {
                    'start' {
                        # Start the job
                        $jobScript = Get-Content -Path $command.ScriptPath -Raw

                        $job = Start-Job -ScriptBlock ([scriptblock]::Create($jobScript)) -ArgumentList $command.Variables

                        # Track running job
                        $Global:PSWebServer.Jobs.Running[$command.ExecutionID] = @{
                            ExecutionID = $command.ExecutionID
                            JobID = $command.JobID
                            PSJobID = $job.Id
                            UserID = $command.UserID
                            SessionID = $command.SessionID
                            StartTime = Get-Date
                            Metadata = $command.Metadata
                        }

                        Write-Verbose "[JobSystem] Started job: $($command.JobID) (ExecutionID: $($command.ExecutionID), PSJobID: $($job.Id))"
                    }

                    'stop' {
                        # Find and stop the job
                        $runningJob = $Global:PSWebServer.Jobs.Running.Values | Where-Object { $_.JobID -eq $command.JobID -and $_.UserID -eq $command.UserID } | Select-Object -First 1

                        if ($runningJob) {
                            $psJob = Get-Job -Id $runningJob.PSJobID -ErrorAction SilentlyContinue

                            if ($psJob) {
                                Stop-Job -Id $psJob.Id
                                Remove-Job -Id $psJob.Id -Force

                                # Move to history
                                $Global:PSWebServer.Jobs.History += @{
                                    ExecutionID = $runningJob.ExecutionID
                                    JobID = $runningJob.JobID
                                    UserID = $runningJob.UserID
                                    StartTime = $runningJob.StartTime
                                    EndTime = Get-Date
                                    Status = 'Stopped'
                                    Success = $false
                                    Output = 'Job stopped by user'
                                }

                                $Global:PSWebServer.Jobs.Running.Remove($runningJob.ExecutionID)

                                Write-Verbose "[JobSystem] Stopped job: $($command.JobID) (ExecutionID: $($runningJob.ExecutionID))"
                            }
                        }
                    }

                    'restart' {
                        # Stop then start
                        # First stop
                        $stopCommand = @{
                            Command = 'stop'
                            JobID = $command.JobID
                            UserID = $command.UserID
                            Timestamp = Get-Date
                        }
                        $Global:PSWebServer.Jobs.CommandQueue.Enqueue($stopCommand)

                        # Then start
                        Start-PSWebHostJob -JobID $command.JobID -UserID $command.UserID -SessionID $command.SessionID -Variables $command.Variables
                    }

                    'receive' {
                        # Get job output
                        $runningJob = $Global:PSWebServer.Jobs.Running[$command.ExecutionID]

                        if ($runningJob -and $runningJob.UserID -eq $command.UserID) {
                            $psJob = Get-Job -Id $runningJob.PSJobID -ErrorAction SilentlyContinue

                            if ($psJob) {
                                $output = Receive-Job -Id $psJob.Id -Keep *>&1 | Out-String

                                # Update running job with latest output
                                $runningJob.LatestOutput = $output
                            }
                        }
                    }
                }
            }
            catch {
                Write-Error "[JobSystem] Error processing command: $_"
            }
        }
    }

    # Cleanup completed jobs
    $completedJobs = @()

    foreach ($executionID in $Global:PSWebServer.Jobs.Running.Keys) {
        $runningJob = $Global:PSWebServer.Jobs.Running[$executionID]
        $psJob = Get-Job -Id $runningJob.PSJobID -ErrorAction SilentlyContinue

        if ($psJob -and $psJob.State -in @('Completed', 'Failed', 'Stopped')) {
            $output = Receive-Job -Id $psJob.Id *>&1 | Out-String

            # Move to history
            $Global:PSWebServer.Jobs.History += @{
                ExecutionID = $runningJob.ExecutionID
                JobID = $runningJob.JobID
                UserID = $runningJob.UserID
                StartTime = $runningJob.StartTime
                EndTime = Get-Date
                Status = $psJob.State
                Success = ($psJob.State -eq 'Completed')
                Output = $output
            }

            Remove-Job -Id $psJob.Id -Force
            $completedJobs += $executionID

            Write-Verbose "[JobSystem] Job completed: $($runningJob.JobID) (ExecutionID: $executionID, State: $($psJob.State))"
        }
    }

    # Remove completed jobs from running tracker
    foreach ($executionID in $completedJobs) {
        $Global:PSWebServer.Jobs.Running.Remove($executionID)
    }

    return $processedCount
}

Export-ModuleMember -Function @(
    'Initialize-PSWebHostJobSystem',
    'Get-PSWebHostJobCatalog',
    'Get-PSWebHostJobDefinition',
    'Initialize-PSWebHostJob',
    'Test-PSWebHostJobPermission',
    'Start-PSWebHostJob',
    'Stop-PSWebHostJob',
    'Restart-PSWebHostJob',
    'Get-PSWebHostJobOutput',
    'Get-PSWebHostJobStatus',
    'Get-PSWebHostRunningJobs',
    'Process-PSWebHostJobCommandQueue'
)
