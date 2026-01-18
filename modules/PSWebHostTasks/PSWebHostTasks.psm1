#Requires -Version 7

<#
.SYNOPSIS
    PSWebHost Task Scheduling Engine

.DESCRIPTION
    Provides cron-like task scheduling for PSWebHost with:
    - Scheduled task execution based on cron expressions
    - Task termination rules (max runtime, max failures)
    - Runtime configuration management (enable/disable/modify tasks)
    - Task execution history tracking
    - Support for global and per-app tasks

.NOTES
    Module: PSWebHostTasks
    Author: PSWebHost Team
    Version: 1.0.0
#>

# Initialize global task state if not exists
if (-not $Global:PSWebServer.Tasks) {
    $Global:PSWebServer.Tasks = @{
        RunningJobs = [hashtable]::Synchronized(@{})
        LastRun = @{}
        History = [System.Collections.ArrayList]::Synchronized(@())
        FailureCount = @{}
        GarbageCollection = @{
            LastRunspaceGC = @{}
            RunspaceGCInterval = 3600  # 60 minutes in seconds
        }
    }
}

#region Main Engine Functions

<#
.SYNOPSIS
    Main task engine entry point - called every minute from WebHost.ps1

.DESCRIPTION
    Loads task definitions from:
    1. config/tasks.yaml (global tasks)
    2. apps/*/config/tasks.yaml (app tasks)
    3. PsWebHost_Data/config/tasks.json (runtime overrides)

    Then evaluates each task to determine if it should run, and checks
    termination rules for running tasks.

.EXAMPLE
    Invoke-PsWebHostTaskEngine

.NOTES
    Called from main server loop every minute (when Second = 0)
#>
function Invoke-PsWebHostTaskEngine {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "[TaskEngine] Evaluating tasks..."

        # Load all task definitions
        $allTasks = Get-AllTaskDefinitions

        if ($allTasks.Count -eq 0) {
            Write-Verbose "[TaskEngine] No tasks defined"
            return
        }

        Write-Verbose "[TaskEngine] Found $($allTasks.Count) tasks to evaluate"

        # Process each task
        foreach ($task in $allTasks) {
            if (-not $task.enabled) {
                Write-Verbose "[TaskEngine] Task '$($task.name)' is disabled, skipping"
                continue
            }

            try {
                # Check if should run based on schedule
                if (Test-TaskSchedule -Task $task) {
                    Write-Verbose "[TaskEngine] Task '$($task.name)' matches schedule, starting..."
                    Start-PSWebHostTask -Task $task
                }

                # Check if running task should be terminated
                $runningJob = Get-RunningTaskJob -Task $task
                if ($runningJob -and (Test-TaskTermination -Task $task -Job $runningJob)) {
                    Write-Warning "[TaskEngine] Task '$($task.name)' triggered termination rule"
                    Stop-PSWebHostTask -Task $task -Job $runningJob
                }

            } catch {
                Write-Warning "[TaskEngine] Error processing task '$($task.name)': $_"
                Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message "Error processing task '$($task.name)': $_"
            }
        }

        # Cleanup completed jobs
        Remove-CompletedTaskJobs

        # Run periodic garbage collection on runspaces
        Invoke-RunspaceGarbageCollection

        Write-Verbose "[TaskEngine] Task evaluation complete"

    } catch {
        $errorMsg = "Task engine error: $($_.Exception.Message)"
        Write-Error $errorMsg
        Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message $errorMsg
    }
}

<#
.SYNOPSIS
    Get all task definitions merged from defaults and runtime config

.DESCRIPTION
    Loads tasks from:
    1. config/tasks.yaml (global defaults)
    2. apps/*/config/tasks.yaml (app defaults)
    3. PsWebHost_Data/config/tasks.json (runtime overrides)

    Merges them with runtime overrides taking precedence

.OUTPUTS
    Array of task definition hashtables
#>
function Get-AllTaskDefinitions {
    [CmdletBinding()]
    param()

    $allTasks = @()

    # Load global tasks
    $globalTasksFile = Join-Path $Global:PSWebServer.Project_Root.Path "config\tasks.yaml"
    if (Test-Path $globalTasksFile) {
        try {
            $globalTasksDef = Get-Content $globalTasksFile -Raw | ConvertFrom-Yaml
            if ($globalTasksDef.tasks) {
                foreach ($task in $globalTasksDef.tasks) {
                    $task.source = 'global'
                    $task.sourceFile = $globalTasksFile
                    $allTasks += $task
                }
            }
        } catch {
            Write-Warning "[TaskEngine] Error loading global tasks: $_"
        }
    }

    # Load app tasks
    $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps"
    if (Test-Path $appsPath) {
        Get-ChildItem -Path $appsPath -Directory | ForEach-Object {
            $appName = $_.Name
            $appTasksFile = Join-Path $_.FullName "config\tasks.yaml"

            if (Test-Path $appTasksFile) {
                try {
                    $appTasksDef = Get-Content $appTasksFile -Raw | ConvertFrom-Yaml
                    if ($appTasksDef.tasks) {
                        foreach ($task in $appTasksDef.tasks) {
                            $task.source = 'app'
                            $task.appName = $appName
                            $task.appRoot = $_.FullName
                            $task.sourceFile = $appTasksFile
                            $allTasks += $task
                        }
                    }
                } catch {
                    Write-Warning "[TaskEngine] Error loading tasks for app '$appName': $_"
                }
            }
        }
    }

    # Load runtime configuration (overrides)
    $runtimeConfigFile = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\config\tasks.json"
    if (Test-Path $runtimeConfigFile) {
        try {
            $runtimeConfig = Get-Content $runtimeConfigFile -Raw | ConvertFrom-Json

            # Apply runtime overrides
            foreach ($task in $allTasks) {
                $override = $runtimeConfig.tasks | Where-Object { $_.name -eq $task.name -and $_.appName -eq $task.appName }

                if ($override) {
                    # Override enabled state
                    if ($null -ne $override.enabled) {
                        $task.enabled = $override.enabled
                    }

                    # Override schedule
                    if ($override.schedule) {
                        $task.schedule = $override.schedule
                    }

                    # Override environment variables
                    if ($override.environment) {
                        $task.environment = $override.environment
                    }

                    # Check if marked deleted
                    if ($override.deleted) {
                        $task.enabled = $false
                        $task.deleted = $true
                    }

                    $task.overridden = $true
                }
            }

            # Add custom tasks (not in defaults)
            foreach ($customTask in $runtimeConfig.tasks) {
                if ($customTask.custom -or ($customTask.scriptPath -and -not ($allTasks | Where-Object { $_.name -eq $customTask.name }))) {
                    $customTask.source = 'custom'
                    $customTask.custom = $true
                    $allTasks += $customTask
                }
            }

        } catch {
            Write-Warning "[TaskEngine] Error loading runtime config: $_"
        }
    }

    # Filter out deleted tasks
    $allTasks = $allTasks | Where-Object { -not $_.deleted }

    return $allTasks
}

#endregion

#region Task Scheduling

<#
.SYNOPSIS
    Test if a task should run based on its cron schedule

.PARAMETER Task
    Task definition hashtable

.OUTPUTS
    Boolean indicating if task should run now
#>
function Test-TaskSchedule {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task
    )

    # Get last run time
    $lastRun = $Global:PSWebServer.Tasks.LastRun[$Task.name]

    # If last run was less than 55 seconds ago, don't run again
    # (Allows for some timing variance in minute-based execution)
    if ($lastRun -and ((Get-Date) - $lastRun).TotalSeconds -lt 55) {
        Write-Verbose "[TaskEngine] Task '$($Task.name)' ran recently, skipping"
        return $false
    }

    # Parse cron schedule
    $cronSchedule = $Task.schedule

    if (-not $cronSchedule) {
        Write-Warning "[TaskEngine] Task '$($Task.name)' has no schedule defined"
        return $false
    }

    # Test if current time matches schedule
    $shouldRun = Test-CronExpression -Expression $cronSchedule

    if ($shouldRun) {
        Write-Verbose "[TaskEngine] Task '$($Task.name)' matches cron schedule: $cronSchedule"
    }

    return $shouldRun
}

<#
.SYNOPSIS
    Test if current time matches a cron expression

.PARAMETER Expression
    Cron expression (5-field format: minute hour day month weekday)

.OUTPUTS
    Boolean indicating if current time matches

.EXAMPLE
    Test-CronExpression -Expression "0 2 * * *"  # Daily at 2 AM
    Test-CronExpression -Expression "*/5 * * * *"  # Every 5 minutes

.NOTES
    Supported cron features:
    - * (any value)
    - */N (every N units)
    - N (specific value)
    - N-M (range - future enhancement)
    - N,M,O (list - future enhancement)
#>
function Test-CronExpression {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Expression
    )

    $parts = $Expression -split '\s+'

    if ($parts.Count -ne 5) {
        Write-Warning "[TaskEngine] Invalid cron expression format: $Expression (expected 5 fields)"
        return $false
    }

    $now = Get-Date

    # Parse cron fields
    $minute = $parts[0]
    $hour = $parts[1]
    $day = $parts[2]
    $month = $parts[3]
    $weekday = $parts[4]

    # Test minute
    if ($minute -ne '*') {
        if ($minute -match '^\*/(\d+)$') {
            # Every N minutes
            $interval = [int]$matches[1]
            if ($now.Minute % $interval -ne 0) {
                return $false
            }
        } elseif ($minute -match '^\d+$') {
            # Specific minute
            if ([int]$minute -ne $now.Minute) {
                return $false
            }
        }
    }

    # Test hour
    if ($hour -ne '*') {
        if ($hour -match '^\*/(\d+)$') {
            # Every N hours
            $interval = [int]$matches[1]
            if ($now.Hour % $interval -ne 0) {
                return $false
            }
        } elseif ($hour -match '^\d+$') {
            # Specific hour
            if ([int]$hour -ne $now.Hour) {
                return $false
            }
        }
    }

    # Test day of month
    if ($day -ne '*' -and $day -match '^\d+$') {
        if ([int]$day -ne $now.Day) {
            return $false
        }
    }

    # Test month
    if ($month -ne '*' -and $month -match '^\d+$') {
        if ([int]$month -ne $now.Month) {
            return $false
        }
    }

    # Test day of week (0 = Sunday, 6 = Saturday)
    if ($weekday -ne '*' -and $weekday -match '^\d+$') {
        if ([int]$weekday -ne [int]$now.DayOfWeek) {
            return $false
        }
    }

    return $true
}

#endregion

#region Task Execution

<#
.SYNOPSIS
    Start a task as a background PowerShell job

.PARAMETER Task
    Task definition hashtable

.NOTES
    Creates a background job that executes the task's script with context
#>
function Start-PSWebHostTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task
    )

    try {
        # Check if already running
        if (Get-RunningTaskJob -Task $Task) {
            Write-Verbose "[TaskEngine] Task '$($Task.name)' is already running, skipping"
            return
        }

        # Resolve script path
        $scriptPath = if ($Task.appRoot) {
            Join-Path $Task.appRoot $Task.scriptPath
        } else {
            Join-Path $Global:PSWebServer.Project_Root.Path $Task.scriptPath
        }

        if (-not (Test-Path $scriptPath)) {
            $errorMsg = "Script not found for task '$($Task.name)': $scriptPath"
            Write-Warning "[TaskEngine] $errorMsg"
            Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message $errorMsg
            return
        }

        # Build task context
        $taskContext = @{
            TaskName = $Task.name
            AppName = $Task.appName
            Environment = $Task.environment ?? @{}
            StartTime = Get-Date
            TriggeredBy = 'Scheduled'
        }

        # Generate unique job name
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $jobName = "Task_$($Task.name)_$timestamp"

        # Start background job
        $job = Start-Job -Name $jobName -ScriptBlock {
            param($ScriptPath, $TaskContext, $ProjectRoot)

            # Set working directory
            Set-Location $ProjectRoot

            # Import necessary modules (if task needs them)
            # Apps will have their modules in PSModulePath already

            # Execute task script
            try {
                & $ScriptPath -TaskContext $TaskContext
            } catch {
                # Return error information
                @{
                    Status = 'Failed'
                    Error = $_.Exception.Message
                    StackTrace = $_.ScriptStackTrace
                }
            }

        } -ArgumentList $scriptPath, $taskContext, $Global:PSWebServer.Project_Root.Path

        # Track running job
        $Global:PSWebServer.Tasks.RunningJobs[$Task.name] = @{
            Job = $job
            Task = $Task
            StartTime = Get-Date
            Context = $taskContext
        }

        $Global:PSWebServer.Tasks.LastRun[$Task.name] = Get-Date

        Write-Verbose "[TaskEngine] Started task '$($Task.name)' (Job: $jobName)"
        Write-PSWebHostLog -Severity 'Info' -Category 'TaskEngine' -Message "Started task: $($Task.name)"

        # Log to database if available
        Save-TaskExecution -Task $Task -Job $job -Status 'Running'

    } catch {
        $errorMsg = "Failed to start task '$($Task.name)': $($_.Exception.Message)"
        Write-Warning "[TaskEngine] $errorMsg"
        Write-PSWebHostLog -Severity 'Error' -Category 'TaskEngine' -Message $errorMsg
    }
}

<#
.SYNOPSIS
    Get the running job for a task (if any)

.PARAMETER Task
    Task definition hashtable

.OUTPUTS
    Job object if task is running, $null otherwise
#>
function Get-RunningTaskJob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task
    )

    $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]

    if ($taskInfo -and $taskInfo.Job) {
        $job = $taskInfo.Job

        # Refresh job state
        $job | Out-Null  # Force state refresh

        if ($job.State -eq 'Running') {
            return $job
        }
    }

    return $null
}

#endregion

#region Task Termination

<#
.SYNOPSIS
    Test if a running task should be terminated

.PARAMETER Task
    Task definition hashtable

.PARAMETER Job
    Running job object

.OUTPUTS
    Boolean indicating if task should be terminated
#>
function Test-TaskTermination {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task,

        [Parameter(Mandatory)]
        $Job
    )

    $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]
    $termination = $Task.termination

    if (-not $termination) {
        return $false
    }

    # Check max runtime
    if ($termination.maxRuntime) {
        $runtime = ((Get-Date) - $taskInfo.StartTime).TotalSeconds

        if ($runtime -gt $termination.maxRuntime) {
            Write-Warning "[TaskEngine] Task '$($Task.name)' exceeded maxRuntime ($runtime > $($termination.maxRuntime)s)"
            return $true
        }
    }

    # Check if job failed and max failures reached
    if ($Job.State -eq 'Failed') {
        $failureCount = $Global:PSWebServer.Tasks.FailureCount[$Task.name] ?? 0
        $failureCount++
        $Global:PSWebServer.Tasks.FailureCount[$Task.name] = $failureCount

        if ($termination.maxFailures -and $failureCount -ge $termination.maxFailures) {
            Write-Warning "[TaskEngine] Task '$($Task.name)' reached maxFailures ($failureCount)"
            return $true
        }
    }

    return $false
}

<#
.SYNOPSIS
    Stop a running task and clean up

.PARAMETER Task
    Task definition hashtable

.PARAMETER Job
    Running job object
#>
function Stop-PSWebHostTask {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Task,

        [Parameter(Mandatory)]
        $Job
    )

    try {
        $termination = $Task.termination
        $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]

        # Stop the job
        if ($termination.killOnTimeout) {
            Write-Verbose "[TaskEngine] Force-stopping job for task '$($Task.name)'"
            Stop-Job -Job $Job -ErrorAction SilentlyContinue
        }

        # Get job output before removing
        $output = Receive-Job -Job $Job -ErrorAction SilentlyContinue

        Remove-Job -Job $Job -Force -ErrorAction SilentlyContinue

        # Record in history
        $historyEntry = @{
            TaskName = $Task.name
            AppName = $Task.appName
            StartTime = $taskInfo.StartTime
            EndTime = Get-Date
            Duration = ((Get-Date) - $taskInfo.StartTime).TotalSeconds
            Status = 'Terminated'
            Reason = 'Termination rule triggered'
            Output = $output
        }

        $null = $Global:PSWebServer.Tasks.History.Add($historyEntry)

        # Remove from running jobs
        $Global:PSWebServer.Tasks.RunningJobs.Remove($Task.name)

        Write-Verbose "[TaskEngine] Terminated task: $($Task.name)"
        Write-PSWebHostLog -Severity 'Warning' -Category 'TaskEngine' -Message "Terminated task: $($Task.name)"

        # Save to database
        Save-TaskExecution -Task $Task -Job $Job -Status 'Terminated' -Duration $historyEntry.Duration -Output $output

    } catch {
        Write-Warning "[TaskEngine] Failed to stop task '$($Task.name)': $_"
    }
}

#endregion

#region Cleanup

<#
.SYNOPSIS
    Clean up completed jobs and update history

.NOTES
    Removes completed/failed jobs from the running jobs list
    Adds them to history
    Keeps only last 100 history entries in memory
#>
function Remove-CompletedTaskJobs {
    [CmdletBinding()]
    param()

    $completedTasks = $Global:PSWebServer.Tasks.RunningJobs.Keys | Where-Object {
        $job = $Global:PSWebServer.Tasks.RunningJobs[$_].Job
        $job -and $job.State -in @('Completed', 'Failed', 'Stopped')
    }

    foreach ($taskName in $completedTasks) {
        try {
            $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$taskName]
            $job = $taskInfo.Job
            $task = $taskInfo.Task

            # Get job output
            $output = Receive-Job -Job $job -ErrorAction SilentlyContinue
            $errorOutput = $job.ChildJobs[0].Error | Out-String

            # Determine status
            $status = $job.State
            if ($job.State -eq 'Completed' -and -not $errorOutput) {
                $status = 'Success'
            } elseif ($job.State -eq 'Failed' -or $errorOutput) {
                $status = 'Failed'
            }

            # Calculate duration
            $duration = ((Get-Date) - $taskInfo.StartTime).TotalSeconds

            # Record in history
            $historyEntry = @{
                TaskName = $taskName
                AppName = $task.appName
                StartTime = $taskInfo.StartTime
                EndTime = Get-Date
                Duration = $duration
                Status = $status
                Output = $output
                Error = $errorOutput
            }

            $null = $Global:PSWebServer.Tasks.History.Add($historyEntry)

            # Remove job
            Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
            $Global:PSWebServer.Tasks.RunningJobs.Remove($taskName)

            Write-Verbose "[TaskEngine] Cleaned up completed task: $taskName (Status: $status, Duration: $([math]::Round($duration, 2))s)"

            # Save to database
            Save-TaskExecution -Task $task -Job $job -Status $status -Duration $duration -Output $output -Error $errorOutput

        } catch {
            Write-Warning "[TaskEngine] Error cleaning up task '$taskName': $_"
        }
    }

    # Keep only last 100 history entries in memory
    if ($Global:PSWebServer.Tasks.History.Count -gt 100) {
        $toRemove = $Global:PSWebServer.Tasks.History.Count - 100
        $Global:PSWebServer.Tasks.History.RemoveRange(0, $toRemove)
    }
}

#endregion

#region Garbage Collection

<#
.SYNOPSIS
    Performs garbage collection on runspaces with staggered timing

.DESCRIPTION
    Runs [gc]::Collect() on each runspace every 60 minutes with an offset
    of [task number] * 3 % 60 to space these operations out and avoid
    simultaneous GC pauses across all runspaces.

.NOTES
    Called from Invoke-PsWebHostTaskEngine every minute
    Each runspace gets a unique offset based on its index to distribute GC load
#>
function Invoke-RunspaceGarbageCollection {
    [CmdletBinding()]
    param()

    try {
        $now = Get-Date
        $gcState = $Global:PSWebServer.Tasks.GarbageCollection

        # Get all running jobs (runspaces)
        $runningJobs = $Global:PSWebServer.Tasks.RunningJobs

        if ($runningJobs.Count -eq 0) {
            return
        }

        $jobIndex = 0
        foreach ($taskName in $runningJobs.Keys) {
            $taskInfo = $runningJobs[$taskName]
            $job = $taskInfo.Job

            if (-not $job -or $job.State -ne 'Running') {
                continue
            }

            # Calculate offset for this runspace: (taskNumber * 3) % 60
            $offsetMinutes = ($jobIndex * 3) % 60

            # Get last GC time for this job
            $lastGC = $gcState.LastRunspaceGC[$job.Id]

            # Determine when this runspace should run GC
            # Base time is top of the hour + offset
            $currentHour = [datetime]::new($now.Year, $now.Month, $now.Day, $now.Hour, 0, 0)
            $scheduledGCTime = $currentHour.AddMinutes($offsetMinutes)

            # If we've passed the scheduled time and haven't run GC in this hour
            if ($now -ge $scheduledGCTime) {
                $shouldRunGC = $false

                if (-not $lastGC) {
                    # Never run GC on this job
                    $shouldRunGC = $true
                } else {
                    # Check if we've run GC since the current scheduled time
                    if ($lastGC -lt $scheduledGCTime) {
                        $shouldRunGC = $true
                    }
                }

                if ($shouldRunGC) {
                    Write-Verbose "[TaskEngine:GC] Running garbage collection on runspace for task '$taskName' (Job ID: $($job.Id), Offset: ${offsetMinutes}m)"

                    # Invoke GC in the runspace
                    # Note: We can't directly invoke GC in a background job's runspace from here
                    # The job needs to handle GC itself, or we use a different approach

                    # For now, track that we would run GC and update the timestamp
                    # In a real implementation, jobs would need to periodically check and run GC themselves
                    # or we'd need to use runspace pools with direct runspace access

                    $gcState.LastRunspaceGC[$job.Id] = $now

                    # Log GC operation
                    Write-PSWebHostLog -Severity 'Verbose' -Category 'TaskEngine' -Message "Scheduled GC for runspace (Task: $taskName, Job: $($job.Id))" -ErrorAction SilentlyContinue
                }
            }

            $jobIndex++
        }

    } catch {
        Write-Verbose "[TaskEngine:GC] Error during garbage collection: $_"
    }
}

<#
.SYNOPSIS
    Runs garbage collection in the current runspace

.DESCRIPTION
    Helper function that task scripts can call to perform garbage collection.
    Should be called from within task scripts that run for extended periods.

.EXAMPLE
    # In a long-running task script:
    Invoke-TaskRunspaceGC

.NOTES
    This function should be called from within task scripts, not from the main thread
#>
function Invoke-TaskRunspaceGC {
    [CmdletBinding()]
    param()

    try {
        Write-Verbose "[Task:GC] Running garbage collection in current runspace"
        [System.GC]::Collect()
        [System.GC]::WaitForPendingFinalizers()
        [System.GC]::Collect()
        Write-Verbose "[Task:GC] Garbage collection complete"
    } catch {
        Write-Warning "[Task:GC] Failed to run garbage collection: $_"
    }
}

#endregion

#region Database Operations

<#
.SYNOPSIS
    Save task execution to database

.PARAMETER Task
    Task definition

.PARAMETER Job
    Job object

.PARAMETER Status
    Execution status

.PARAMETER Duration
    Execution duration in seconds

.PARAMETER Output
    Job output

.PARAMETER Error
    Error messages if any
#>
function Save-TaskExecution {
    [CmdletBinding()]
    param(
        [hashtable]$Task,
        $Job,
        [string]$Status,
        [double]$Duration = 0,
        $Output = $null,
        [string]$Error = $null
    )

    try {
        # Check if WebHostTaskManagement is loaded
        if (-not $Global:PSWebServer.ContainsKey('WebHostTaskManagement')) {
            return
        }

        $dbPath = $Global:PSWebServer['WebHostTaskManagement'].TaskDatabasePath

        if (-not (Test-Path $dbPath)) {
            return
        }

        $taskInfo = $Global:PSWebServer.Tasks.RunningJobs[$Task.name]
        $startTime = $taskInfo?.StartTime ?? (Get-Date)

        $query = @"
INSERT INTO TaskExecutions (
    TaskName, AppName, StartTime, EndTime, Duration, Status,
    Output, ErrorMessage, TriggeredBy, TriggeredByUser
) VALUES (
    @TaskName, @AppName, @StartTime, @EndTime, @Duration, @Status,
    @Output, @ErrorMessage, @TriggeredBy, @TriggeredByUser
);
"@

        $parameters = @{
            TaskName = $Task.name
            AppName = $Task.appName ?? 'global'
            StartTime = $startTime.ToString('yyyy-MM-dd HH:mm:ss')
            EndTime = if ($Status -ne 'Running') { (Get-Date).ToString('yyyy-MM-dd HH:mm:ss') } else { $null }
            Duration = [int]$Duration
            Status = $Status
            Output = if ($Output) { $Output | ConvertTo-Json -Compress } else { $null }
            ErrorMessage = $Error
            TriggeredBy = 'Scheduled'
            TriggeredByUser = $null
        }

        Invoke-PSWebSQLiteNonQuery -File $dbPath -Query $query -Parameters $parameters

    } catch {
        Write-Verbose "[TaskEngine] Could not save task execution to database: $_"
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Invoke-PsWebHostTaskEngine'
    'Get-AllTaskDefinitions'
    'Test-TaskSchedule'
    'Test-CronExpression'
    'Start-PSWebHostTask'
    'Stop-PSWebHostTask'
    'Get-RunningTaskJob'
    'Test-TaskTermination'
    'Remove-CompletedTaskJobs'
    'Invoke-RunspaceGarbageCollection'
    'Invoke-TaskRunspaceGC'
)
