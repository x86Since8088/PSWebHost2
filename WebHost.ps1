[cmdletbinding()]
param (
    [switch]$RunInProcess,
    [switch]$InitializeEnvironmentOnly, # For validateInstall.ps1
    [string]$AuthenticationSchemes = "Anonymous",
    [switch]$Async, # New parameter for asynchronous handling
    [int]$Port = 8080,
    [switch]$ReloadOnScriptUpdate,
    [switch]$StopOnScriptUpdate,
    [switch]$Resume,
    [switch]$ForceInit
)

begin {

# ============================================================================
# PowerShell Version Check - Require PowerShell 7 or later
# ============================================================================
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Host "`n========================================================================================================" -ForegroundColor Red
        Write-Host "  ERROR: PowerShell 7 or later is required to run PSWebHost" -ForegroundColor Red
        Write-Host "========================================================================================================" -ForegroundColor Red
        Write-Host "`nCurrent version: PowerShell $($PSVersionTable.PSVersion.ToString())" -ForegroundColor Yellow
        Write-Host "Required version: PowerShell 7.0 or later`n" -ForegroundColor Yellow

        Write-Host "Installation Instructions:" -ForegroundColor Cyan
        Write-Host "-------------------------`n" -ForegroundColor Cyan

        # Use built-in OS detection variables (available in PowerShell 6+)
        # Note: These are read-only automatic variables, don't assign to them
        if ($IsWindows) {
            Write-Host "Windows - Option 1 (Recommended): Using Winget" -ForegroundColor Green
            Write-Host "  winget install --id Microsoft.Powershell --source winget`n" -ForegroundColor White

            Write-Host "Windows - Option 2: Using MSI Installer" -ForegroundColor Green
            Write-Host "  Download from: https://aka.ms/powershell-release?tag=stable`n" -ForegroundColor White

            Write-Host "Windows - Option 3: Using Windows Package Manager" -ForegroundColor Green
            Write-Host "  Install from Microsoft Store: search for 'PowerShell'`n" -ForegroundColor White
        } elseif ($IsLinux) {
            Write-Host "Linux - Detect your distribution and use the appropriate command:`n" -ForegroundColor Green

            Write-Host "Ubuntu/Debian:" -ForegroundColor Cyan
            Write-Host "  sudo apt-get update" -ForegroundColor White
            Write-Host "  sudo apt-get install -y wget apt-transport-https software-properties-common" -ForegroundColor White
            Write-Host "  wget -q https://packages.microsoft.com/config/ubuntu/22.04/packages-microsoft-prod.deb" -ForegroundColor White
            Write-Host "  sudo dpkg -i packages-microsoft-prod.deb" -ForegroundColor White
            Write-Host "  sudo apt-get update" -ForegroundColor White
            Write-Host "  sudo apt-get install -y powershell`n" -ForegroundColor White

            Write-Host "RHEL/CentOS/Fedora:" -ForegroundColor Cyan
            Write-Host "  sudo dnf install -y powershell`n" -ForegroundColor White

            Write-Host "Arch Linux:" -ForegroundColor Cyan
            Write-Host "  yay -S powershell-bin`n" -ForegroundColor White
        } elseif ($IsMacOS) {
            Write-Host "macOS - Using Homebrew:" -ForegroundColor Green
            Write-Host "  brew install --cask powershell`n" -ForegroundColor White
        }

        Write-Host "After installation, run this script again using:" -ForegroundColor Yellow
        Write-Host "  pwsh $($MyInvocation.MyCommand.Path)`n" -ForegroundColor White

        Write-Host "For more information, visit:" -ForegroundColor Cyan
        Write-Host "  https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell`n" -ForegroundColor White

        Write-Host "========================================================================================================`n" -ForegroundColor Red
        exit 1
    }
    $Start = Get-Date

    if ($null -ne $global:PSWebServer -and -not $ForceInit.IsPresent) {
        return Get-Variable -Scope Global -Name *web* | %{Get-ObjectSafeWalk $_}| ConvertTo-Json -Depth 20
    }

    $WebHostRoot = $PSScriptRoot  # Save before dot-sourcing changes context
    if ($null -ne $global:PSWebServer -and (! $ForceInit.IsPresent)) {
        Write-Host "Using the previously loaded environment..."
    }
    else {
        . (Join-Path $WebHostRoot 'system/init.ps1')
        Write-Host "Init.ps1 completed after $(((Get-date) - $start).TotalMilliseconds) milliseconds"
    }

    if (!$Resume.IsPresent) {
        Write-Verbose 'Starting init.ps1...'

        # Load and initialize PSWebHost_Jobs module
        Write-Verbose 'Loading PSWebHost_Jobs module...'
        $jobsModulePath = Join-Path $Global:PSWebServer.Project_Root.Path "modules\PSWebHost_Jobs"

        if($InitializeEnvironmentOnly.IsPresent) {
            Write-Host "Skipping Jobs initialization while -InitializeEnvironmentOnly is present."
        }
        elseif (Test-Path $jobsModulePath) {
            try {
                Import-Module $jobsModulePath -DisableNameChecking -Force -ErrorAction Stop
                Write-Host "✓ PSWebHost_Jobs module imported" -ForegroundColor Green

                # Initialize job system
                Initialize-PSWebHostJobSystem
                Write-Host "✓ Job system initialized" -ForegroundColor Green

                # Discover jobs from all apps
                $catalog = Get-PSWebHostJobCatalog -ProjectRoot $Global:PSWebServer.Project_Root.Path
                $Global:PSWebServer.Jobs.Catalog = $catalog

                Write-Host "PSWebHost_Jobs module loaded (discovered $($catalog.Count) jobs)" -ForegroundColor Cyan
            } catch {
                Write-Host "❌ Failed to load PSWebHost_Jobs module: $($_.Exception.Message)" -ForegroundColor Red
                Write-Host "   Error details: $($_.Exception.ToString())" -ForegroundColor Yellow
                Write-PSWebHostLog -Severity 'Error' -Category 'Startup' -Message "Failed to load PSWebHost_Jobs: $($_.Exception.Message)" -Data @{
                    ModulePath = $jobsModulePath
                    Error = $_.Exception.ToString()
                }
            }
        } else {
            Write-Warning "PSWebHost_Jobs module not found at: $jobsModulePath"
            Write-PSWebHostLog -Severity 'Warning' -Category 'Startup' -Message "PSWebHost_Jobs module not found at: $jobsModulePath"
        }

        # Load async runspace pool module if -Async is specified
        if ($Async) {
            Write-Verbose 'Loading AsyncRunspacePool module...'
            . (Join-Path $WebHostRoot 'system/AsyncRunspacePool.ps1')
            Write-Host "AsyncRunspacePool module loaded."
        }
        $InitialFileDate = (get-item $MyInvocation.MyCommand.Path).LastWriteTime # This is the initial script's last write time

        # Replace API key placeholder in spa-shell.html
        $spaShellPath = Join-Path $Global:PSWebServer.Project_Root.Path "public/spa-shell.html"
        if (Test-Path $spaShellPath) {
            $apiKey = $Global:PSWebServer.Config.GoogleMaps.ApiKey
            if (-not [string]::IsNullOrEmpty($apiKey)) {
                $spaShellContent = Get-Content -Path $spaShellPath -Raw
                $spaShellContent = $spaShellContent -replace "YOUR_API_KEY", $apiKey
                Set-Content -Path $spaShellPath -Value $spaShellContent -NoNewline
            }
        }

        # Call validateInstall.ps1 if -InitializeEnvironmentOnly is present
        if ($InitializeEnvironmentOnly.IsPresent) {
            Write-Verbose "Calling validateInstall.ps1 with -InitializeEnvironmentOnly..."
            . (Join-Path $Global:PSWebServer.Project_Root.Path "system\validateInstall.ps1") -InitializeEnvironmentOnly
            return # Exit after showing variables
        }
        elseif ($ReloadOnScriptUpdate.IsPresent) {
            # Launch this script in a while ($true) loop with -StopOnScriptUpdate added to the other parameters except for -ReloadOnScriptUpdate.
            while($true) {
                $splat = @{}
                $PSBoundParameters.Keys|Where-Object{$_ -ne 'ReloadOnScriptUpdate'}|ForEach-Object{$splat[$_]=$PSBoundParameters[$_]}
                [string[]]$ArgumentList = @("-ExecutionPolicy","RemoteSigned","-Command", "$PSScriptRoot\WebHost.ps1", "-StopOnScriptUpdate") +  
                    (
                        $splat.keys|ForEach-Object{
                            if ($PSBoundParameters[$_] -is [switch]) {
                                "-$_`:([bool]$([int]$splat[$_].ispresent))"
                            }
                            else {
                                "-$_",$splat[$_]
                            }
                        }
                    ) + '2>&1 |' +
                {
                    Where-Object{$_}|ForEach-Object{
                        .{
                            $OutputItem = $_ 
                            if ($OutputItem -is [System.Management.Automation.ErrorRecord]) {
                                $OutputItem.gettype()|Format-Table
                                $_
                                Get-PSCallStack | Select-Object Command, Arguments, Location,@{ 
                                        N='Source';
                                        E={$_.InvocationInfo.MyCommand.Source}
                                    }
                            }
                            ELSE {$_}
                        }
                    }
            }.tostring()
            Write-Verbose "Starting pwsh directly so that output is directly parsed.`n`tpwsh.exe $ArgumentList"
                pwsh.exe $ArgumentList 
            }
            return
        }

        # Listener setup
        Write-Verbose "Creating HttpListener object..."
        $listener = New-Object System.Net.HttpListener
        Write-Verbose "HttpListener object created."
        if ($Port -notmatch '\d') {
            $port = $Global:PSWebServer.Config.WebServer.Port
            Write-Verbose "Using port from config: $port"
        }
        
        # Check if running as admin
        $isAdmin = ([System.Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)

        # Try localhost first (works without URL ACL), then fall back to + (requires URL ACL or admin)
        $prefixesToTry = @()
        $prefixesToTry += "http://localhost:$port/"
        if ($isAdmin) {
            $prefixesToTry += "http://+:$port/"
        }
        
        $listenerStarted = $false
        $lastError = $null
    
        foreach ($prefix in $prefixesToTry) {
            try {
                Write-Verbose "Adding prefix: $prefix"
                $listener.Prefixes.Add($prefix)
                Write-Verbose "Prefix '$prefix' added."
                Write-Verbose "Setting AuthenticationSchemes to: $AuthenticationSchemes"
                $listener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::$AuthenticationSchemes
                Write-Verbose "AuthenticationSchemes set."
                
                Write-Verbose "Starting listener with prefix: $prefix"
                $listener.Start()
                Write-Verbose "Listener started successfully on $prefix"
                $listenerStarted = $true
                break
            } catch {
                $lastError = $_
                Write-Verbose "Failed to bind to $prefix - Error: $($_.Exception.Message)"
                # Dispose current listener and create a new one for next attempt
                if ($listener) {
                    try { $listener.Dispose() } catch { }
                    $listener = New-Object System.Net.HttpListener
                }
            }
        }
        
        if (-not $listenerStarted) {
            $errMsg = if ($lastError) { $lastError.Exception.ToString() } else { "Unable to bind to any prefix" }
            Write-Error "Failed to start listener. Error: $errMsg"
            # Record failure info for callers to inspect instead of terminating the process
            $script:ListenerStartResult = @{ ExitCode = 1; Message = $errMsg }
            return
        }

        $script:ListenerInstance = $listener # Store for cleanup

        # Initialize async runspace pool if -Async mode
        # This must happen AFTER listener starts since workers need the ListenerInstance
        if ($Async) {
            Write-Host "Initializing async runspace pool with 15 worker runspaces..."
            # Force re-initialization to clean up any old runspaces from previous runs
            # This prevents runspace jamming on server restart
            Initialize-AsyncRunspacePool -PoolSize 15 -ListenerInstance $script:ListenerInstance -Force
            Write-Host "Async workers are now handling requests directly from the listener."
        }

        # Start performance monitoring job
        Write-Host "Starting performance monitoring job..."
        $perfJobScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1"
        if (Test-Path $perfJobScript) {
            & $perfJobScript -StartJob
            Write-Host "Performance monitoring job started."
        } else {
            Write-Warning "Performance monitoring script not found: $perfJobScript"
        }

        # Start log tail job for real-time event stream
        Write-Host "Starting log tail job for event stream..."

        # Use improved log selection to find most recent log file
        $logsDir = Join-Path $Global:PSWebServer.Project_Root.Path "PsWebHost_Data\Logs"
        $LogBaseNames = (Get-ChildItem $logsDir -ErrorAction SilentlyContinue |
            Where-Object { $_.basename -match '_\d{4}-\d\d-\d\dT\d{6}[_\.]\d+-\d{4}' }) -replace '_\d{4}-\d\d-\d\dT\d{6}[_\.]\d+-\d{4}', '*' |
            Sort-Object -Unique

        if ($LogBaseNames) {
            $mostRecentLog = Get-ChildItem $LogBaseNames |
                Where-Object { $_.basename -match '_\d{4}-\d\d-\d\dT\d{6}[_\.]\d+-\d{4}' } |
                Sort-Object LastWriteTime -Descending |
                Select-Object -First 1

            if ($mostRecentLog) {
                $logPath = $mostRecentLog.FullName
                Write-Host "Selected log file: $($mostRecentLog.Name)"
            } else {
                $logPath = $Global:PSWebServer.LogFilePath
                Write-Warning "No timestamped log files found, using configured path: $logPath"
            }
        } else {
            $logPath = $Global:PSWebServer.LogFilePath
            Write-Warning "No timestamped log files found, using configured path: $logPath"
        }

        $tailScriptBlock = {
            param($FilePath)

            $fileStream = New-Object System.IO.FileStream(
                $FilePath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::ReadWrite
            )

            try {
                # Seek to end of file to only show new lines
                [void]$fileStream.Seek(0, [System.IO.SeekOrigin]::End)
                $reader = New-Object System.IO.StreamReader($fileStream, [System.Text.Encoding]::UTF8)

                $lineNumber = 0
                while ($true) {
                    $line = $reader.ReadLine()

                    if ($null -ne $line) {
                        $lineNumber++
                        [PSCustomObject]@{
                            Path = $FilePath
                            Date = Get-Date
                            LineNumber = $lineNumber
                            Line = $line
                        }
                    } else {
                        Start-Sleep -Milliseconds 100
                    }
                }
            }
            finally {
                if ($reader) { $reader.Close() }
                if ($fileStream) { $fileStream.Close() }
            }
        }

        $jobName = "Log_Tail:$logPath"

        # Check for existing job (suppress all errors)
        $existingJob = Get-Job | Where-Object { $_.Name -eq $jobName }
        if ($existingJob) {
            Stop-Job -Job $existingJob -ErrorAction SilentlyContinue
            Remove-Job -Job $existingJob -Force -ErrorAction SilentlyContinue
        }

        $job = Start-Job -Name $jobName -ScriptBlock $tailScriptBlock -ArgumentList $logPath
        Write-Host "Log tail job started: $jobName (Job ID: $($job.Id))"

        # Note: Async runspace pool is initialized later after listener starts
    }
}

end {
    if ($ReloadOnScriptUpdate.IsPresent) {
        # return as this script mode does not need to run a listener
        return
    }

    if (!$Resume.IsPresent) {

        Write-Verbose "Entering listener loop."
        if ($Null -eq $Logpos) {$Logpos = 0}
        if ($Null -eq $UIQueuePos) {$UIQueuePos = 0}
        $Loop_Start = Get-Date
        $lastSettingsCheck = Get-Date
        $lastSessionSync = Get-Date
        $lastGlobalCacheUpdate = Get-Date
        $lastJobProcessing = Get-Date

    }
    else {
        # Resume mode - reinitialize ConcurrentQueue objects that were deserialized
        Write-Host "Resume mode: Reinitializing queue objects..." -ForegroundColor Yellow

        # Reinitialize log queue
        if ($global:PSWebHostLogQueue -and $global:PSWebHostLogQueue.GetType().Name -like "*Deserialized*") {
            $oldQueue = $global:PSWebHostLogQueue
            $global:PSWebHostLogQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
            Write-Host "  Reinitialized PSWebHostLogQueue" -ForegroundColor Green
        }

        # Reinitialize UI queue if it exists
        if ($global:PSHostUIQueue -and $global:PSHostUIQueue.GetType().Name -like "*Deserialized*") {
            $oldUIQueue = $global:PSHostUIQueue
            $global:PSHostUIQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
            Write-Host "  Reinitialized PSHostUIQueue" -ForegroundColor Green
        }

        # Ensure tracking variables exist
        if ($Null -eq $Logpos) {$Logpos = 0}
        if ($Null -eq $UIQueuePos) {$UIQueuePos = 0}
        if ($Null -eq $lastSettingsCheck) {$lastSettingsCheck = Get-Date}
        if ($Null -eq $lastSessionSync) {$lastSessionSync = Get-Date}
        if ($Null -eq $lastGlobalCacheUpdate) {$lastGlobalCacheUpdate = Get-Date}
        if ($Null -eq $lastJobProcessing) {$lastJobProcessing = Get-Date}

        Write-Host "Resume mode: Reinitialization complete" -ForegroundColor Green
    }

    # Initialize global cache structures
    if (-not $Global:PSWebServer.Jobs) {
        $Global:PSWebServer.Jobs = [hashtable]::Synchronized(@{})
    }
    if (-not $Global:PSWebServer.Runspaces) {
        $Global:PSWebServer.Runspaces = [hashtable]::Synchronized(@{})
    }
    if (-not $Global:PSWebServer.CachedTasks) {
        $Global:PSWebServer.CachedTasks = [hashtable]::Synchronized(@{})
    }

    function Update-GlobalCache {
        <#
        .SYNOPSIS
            Updates global cache with Jobs, Runspaces, and Tasks data from main thread
        .DESCRIPTION
            This function runs in the main server loop and caches data that listener
            runspaces need access to but cannot query directly (like Get-Job).

            For runspace data, this function MERGES with worker-reported data from
            Set-WebHostRunSpaceInfo rather than overwriting it. Worker-reported fields
            (Name, PoolName, Purpose, RequestCount, LastRequest, etc.) are preserved,
            while main-thread fields (Availability, RunspaceState, JobInfo) are updated.

            Data is stored in synchronized hashtables for thread-safe access.
        #>
        param()

        try {
            $updateStart = Get-Date

            # Cache Jobs - Get all PowerShell jobs and their details
            $allJobs = Get-Job -ErrorAction SilentlyContinue
            $jobsCache = @{}

            foreach ($job in $allJobs) {
                try {
                    $jobData = @{
                        Id = $job.Id
                        Name = $job.Name
                        State = $job.State.ToString()
                        HasMoreData = $job.HasMoreData
                        Location = $job.Location
                        Command = $job.Command
                        PSBeginTime = $job.PSBeginTime
                        PSEndTime = $job.PSEndTime
                        ChildJobs = @()
                    }

                    # Collect child job info
                    foreach ($childJob in $job.ChildJobs) {
                        $jobData.ChildJobs += @{
                            Id = $childJob.Id
                            State = $childJob.State.ToString()
                            HasMoreData = $childJob.HasMoreData
                            Output = if ($childJob.HasMoreData -and $childJob.Output.Count -gt 0) {
                                $childJob.Output.Count
                            } else { 0 }
                            Error = if ($childJob.Error.Count -gt 0) {
                                $childJob.Error.Count
                            } else { 0 }
                        }
                    }

                    $jobsCache[$job.Id] = $jobData
                } catch {
                    Write-PSWebHostLog -Severity 'Warning' -Category 'GlobalCache' -Message "Error caching job $($job.Id): $($_.Exception.Message)"
                }
            }

            # Update global cache
            $Global:PSWebServer.Jobs.Clear()
            foreach ($key in $jobsCache.Keys) {
                $Global:PSWebServer.Jobs[$key] = $jobsCache[$key]
            }

            # Cache Runspaces - Get runspace information from main thread
            $runspacesCache = @{}

            # Get runspaces from jobs
            foreach ($job in $allJobs) {
                foreach ($childJob in $job.ChildJobs) {
                    if ($childJob.Runspace) {
                        try {
                            $rs = $childJob.Runspace
                            $instanceId = $rs.InstanceId.ToString()

                            # Check if worker has already reported data via Set-WebHostRunSpaceInfo
                            $existingData = $Global:PSWebServer.Runspaces[$instanceId]

                            if ($existingData) {
                                # Merge: preserve worker-reported fields, update main-thread fields
                                $existingData.Availability = $rs.RunspaceAvailability.ToString()
                                $existingData.RunspaceState = $rs.RunspaceStateInfo.State.ToString()
                                $existingData.RunspaceReason = $rs.RunspaceStateInfo.Reason
                                $existingData.JobId = $job.Id
                                $existingData.JobName = $job.Name
                                $existingData.JobState = $job.State.ToString()
                                $existingData.ThreadOptions = if ($rs.ThreadOptions) { $rs.ThreadOptions.ToString() } else { $null }
                                $existingData.ApartmentState = if ($rs.ApartmentState) { $rs.ApartmentState.ToString() } else { $null }
                                $existingData.CacheLastUpdated = Get-Date
                            }
                            else {
                                # No worker-reported data yet - create minimal entry
                                $rsData = @{
                                    Id = $rs.Id
                                    InstanceId = $instanceId
                                    Name = $rs.Name
                                    Availability = $rs.RunspaceAvailability.ToString()
                                    RunspaceState = $rs.RunspaceStateInfo.State.ToString()
                                    RunspaceReason = $rs.RunspaceStateInfo.Reason
                                    JobId = $job.Id
                                    JobName = $job.Name
                                    JobState = $job.State.ToString()
                                    ThreadOptions = if ($rs.ThreadOptions) { $rs.ThreadOptions.ToString() } else { $null }
                                    ApartmentState = if ($rs.ApartmentState) { $rs.ApartmentState.ToString() } else { $null }
                                    CacheLastUpdated = Get-Date
                                }

                                $runspacesCache[$instanceId] = $rsData
                            }
                        } catch {
                            Write-PSWebHostLog -Severity 'Warning' -Category 'GlobalCache' -Message "Error caching runspace for job $($job.Id): $($_.Exception.Message)"
                        }
                    }
                }
            }

            # Include async worker runspaces if available
            if ($Async -and $global:AsyncRunspacePool -and $global:AsyncRunspacePool.Runspaces) {
                foreach ($rsInfo in $global:AsyncRunspacePool.Runspaces) {
                    if ($rsInfo.Runspace) {
                        try {
                            $rs = $rsInfo.Runspace
                            $instanceId = $rs.InstanceId.ToString()

                            # Check if worker has already reported data via Set-WebHostRunSpaceInfo
                            $existingData = $Global:PSWebServer.Runspaces[$instanceId]

                            if ($existingData) {
                                # Merge: preserve worker-reported fields, update main-thread fields
                                $existingData.Availability = $rs.RunspaceAvailability.ToString()
                                $existingData.RunspaceState = $rs.RunspaceStateInfo.State.ToString()
                                $existingData.RunspaceReason = $rs.RunspaceStateInfo.Reason
                                $existingData.ThreadOptions = if ($rs.ThreadOptions) { $rs.ThreadOptions.ToString() } else { $null }
                                $existingData.ApartmentState = if ($rs.ApartmentState) { $rs.ApartmentState.ToString() } else { $null }
                                $existingData.CacheLastUpdated = Get-Date
                            }
                            else {
                                # No worker-reported data yet - create minimal entry
                                $rsData = @{
                                    Id = $rs.Id
                                    InstanceId = $instanceId
                                    Name = "AsyncWorker_$($rsInfo.Index)"
                                    Availability = $rs.RunspaceAvailability.ToString()
                                    RunspaceState = $rs.RunspaceStateInfo.State.ToString()
                                    RunspaceReason = $rs.RunspaceStateInfo.Reason
                                    ThreadOptions = if ($rs.ThreadOptions) { $rs.ThreadOptions.ToString() } else { $null }
                                    ApartmentState = if ($rs.ApartmentState) { $rs.ApartmentState.ToString() } else { $null }
                                    CacheLastUpdated = Get-Date
                                }

                                $runspacesCache[$instanceId] = $rsData
                            }
                        } catch {
                            Write-PSWebHostLog -Severity 'Warning' -Category 'GlobalCache' -Message "Error caching async worker runspace: $($_.Exception.Message)"
                        }
                    }
                }
            }

            # Update global cache - ADD new entries only (don't clear worker-reported data)
            foreach ($key in $runspacesCache.Keys) {
                if (-not $Global:PSWebServer.Runspaces.ContainsKey($key)) {
                    $Global:PSWebServer.Runspaces[$key] = $runspacesCache[$key]
                }
            }

            # Cache Tasks - Get task information from PSWebHostTasks module
            $tasksCache = @{}

            if ($Global:PSWebServer.Tasks) {
                # Get all task definitions
                if (Get-Command Get-AllTaskDefinitions -ErrorAction SilentlyContinue) {
                    try {
                        $allTasks = Get-AllTaskDefinitions

                        foreach ($task in $allTasks) {
                            $taskName = $task.name

                            # Get running job info for this task
                            $runningInfo = $Global:PSWebServer.Tasks.RunningJobs[$taskName]
                            $lastRun = $Global:PSWebServer.Tasks.LastRun[$taskName]
                            $failureCount = $Global:PSWebServer.Tasks.FailureCount[$taskName] ?? 0

                            $taskData = @{
                                Name = $taskName
                                AppName = $task.appName
                                Source = $task.source
                                Enabled = $task.enabled
                                Schedule = $task.schedule
                                ScriptPath = $task.scriptPath
                                LastRun = $lastRun
                                FailureCount = $failureCount
                                IsRunning = $runningInfo -ne $null
                            }

                            if ($runningInfo) {
                                $taskData.RunningJobId = $runningInfo.Job.Id
                                $taskData.RunningJobState = $runningInfo.Job.State.ToString()
                                $taskData.StartTime = $runningInfo.StartTime
                                $taskData.RuntimeSeconds = ((Get-Date) - $runningInfo.StartTime).TotalSeconds
                            }

                            $tasksCache[$taskName] = $taskData
                        }
                    } catch {
                        Write-PSWebHostLog -Severity 'Warning' -Category 'GlobalCache' -Message "Error getting task definitions: $($_.Exception.Message)"
                    }
                }

                # Add recent task history (last 10 entries)
                if ($Global:PSWebServer.Tasks.History) {
                    $tasksCache['__History__'] = @{
                        RecentExecutions = $Global:PSWebServer.Tasks.History |
                            Select-Object -Last 10 |
                            ForEach-Object {
                                @{
                                    TaskName = $_.TaskName
                                    AppName = $_.AppName
                                    StartTime = $_.StartTime
                                    EndTime = $_.EndTime
                                    Duration = $_.Duration
                                    Status = $_.Status
                                }
                            }
                    }
                }
            }

            # Update global cache
            $Global:PSWebServer.CachedTasks.Clear()
            foreach ($key in $tasksCache.Keys) {
                $Global:PSWebServer.CachedTasks[$key] = $tasksCache[$key]
            }

            $updateDuration = ((Get-Date) - $updateStart).TotalMilliseconds
            Write-PSWebHostLog -Severity 'Debug' -Category 'GlobalCache' -Message "Updated cache: $($jobsCache.Count) jobs, $($runspacesCache.Count) runspaces, $($tasksCache.Count) tasks (${updateDuration}ms)"

        } catch {
            Write-PSWebHostLog -Severity 'Error' -Category 'GlobalCache' -Message "Error updating global cache: $($_.Exception.Message)" -Data @{ Error = $_.Exception.ToString() }
        }
    }

    function ProcessLogQueue {
        $now = Get-Date
        if ($global:PSWebServer.LogQueueFlushDate -gt $now.AddSeconds(-15)) {
            return
        }
        else {
            $global:PSWebServer.LogQueueFlushDate = $now
        }

        # This check is to watch for balooning and improperly managed arrays and hashtables..
        if ($null -eq $global:PSWebServer.Track_HashTables) {$global:PSWebServer.Track_HashTables = [hashtable]::Synchronized(@{})}
        Get-Variable -Scope Global |
            Where-Object{$null -ne $_.value -and ($_.value -is [hashtable])}| 
            Select-Object Name,@{N='Count';E={$i=0;$_.Value.Count,$_.Value.Value.Count,$_.Value.Value.Value.Count,$_.Value.Value.Value.Value.Coun|ForEach-Object{$I+=$_};$i}},@{N='LastSeen';E={(get-date).ToString('o')}}|
            ForEach-Object{$global:PSWebServer.Track_HashTables[$_.Name]=$_}
        Write-PSWebHostLog -Message "Track_HashTables" -Severity Info -Data $global:PSWebServer.Track_HashTables -Category MetricsData -UserID Webhost -SessionID MainLoop -Source WebHost.ps1
        if ($null -eq $global:PSWebServer.Track_Arrays) {$global:PSWebServer.Track_Arrays = [hashtable]::Synchronized(@{})}
            $global:PSWebServer.Track_Arrays = [hashtable]::Synchronized(@{})
        Get-Variable -Scope Global |?{$null -ne $_.value -and ($_.value -is [array])}|
            Select-Object Name,@{N='Count';E={$i=0;$_.Value.Count,$_.Value.Value.Count,$_.Value.Value.Value.Count,$_.Value.Value.Value.Value.Coun|ForEach-Object{$I+=$_};$i}},@{N='LastSeen';E={(get-date).ToString('o')}}|
            ForEach-Object{$global:PSWebServer.Track_Arrays[$_.Name]=$_}
        Write-PSWebHostLog -Message "Track_HashTables" -Severity Info -Data $global:PSWebServer.Track_Arrays -Category MetricsData -UserID Webhost -SessionID MainLoop -Source WebHost.ps1

        $LogEnd = $global:PSWebHostLogQueue.count
        if ($LogEnd -lt $script:Logpos) {
            $script:Logpos = 0
        }
        if ([int]$script:Logpos -lt $LogEnd) {
            [array]$logEntries = $script:Logpos .. ($LogEnd -1)|ForEach-Object{$global:PSWebHostLogQueue[$_]}
            if ($logEntries.Count) {
                try {
                    # Check if log file needs header row
                    if (Test-Path $global:PSWebServer.LogFilePath) {
                        $firstLine = Get-Content $global:PSWebServer.LogFilePath -First 1 -ErrorAction SilentlyContinue
                        if ($firstLine -notmatch "^$($global:PSWebServer.LogFileFields[0])") {
                            # Header missing - read content, rewrite with header
                            $existingContent = Get-Content $global:PSWebServer.LogFilePath -Raw -ErrorAction SilentlyContinue
                            Write-Host -ForegroundColor Cyan "Adding missing fields row to log. '$($global:PSWebServer.LogFileFields -join "','")'"

                            # Write header and existing content in single operation
                            $headerLine = $global:PSWebServer.LogFileFields -join "`t"
                            $combinedContent = $headerLine + "`n" + $existingContent
                            [System.IO.File]::WriteAllText($global:PSWebServer.LogFilePath, $combinedContent, [System.Text.Encoding]::UTF8)

                            # Force garbage collection to release file handle
                            $existingContent = $null
                            [gc]::Collect()
                            [gc]::WaitForPendingFinalizers()
                        }
                    }
                    else {
                        # Create new file with header
                        $headerLine = $global:PSWebServer.LogFileFields -join "`t"
                        [System.IO.File]::WriteAllText($global:PSWebServer.LogFilePath, $headerLine + "`n", [System.Text.Encoding]::UTF8)
                    }

                    # Retry logic for appending log entries (file may be briefly locked)
                    $maxRetries = 3
                    $retryCount = 0
                    $writeSuccess = $false

                    while (-not $writeSuccess -and $retryCount -lt $maxRetries) {
                        try {
                            # Use StreamWriter for more reliable append with explicit close
                            $sw = New-Object System.IO.StreamWriter($global:PSWebServer.LogFilePath, $true, [System.Text.Encoding]::UTF8)
                            foreach ($entry in $logEntries) {
                                $sw.WriteLine($entry)
                                Write-Host "`tLogging: $entry"
                            }
                            $sw.Close()
                            $sw.Dispose()
                            $writeSuccess = $true
                        }
                        catch {
                            $retryCount++
                            if ($retryCount -lt $maxRetries) {
                                Write-Verbose "[ProcessLogQueue] Log file locked, retry $retryCount/$maxRetries after 50ms..."
                                Start-Sleep -Milliseconds 50
                            }
                            else {
                                Write-Warning "[ProcessLogQueue] Failed to write log entries after $maxRetries retries: $($_.Exception.Message)"
                                # Ensure stream is disposed on error
                                if ($sw) { try { $sw.Dispose() } catch {} }
                            }
                        }
                    }
                }
                catch {
                    Write-Warning "[ProcessLogQueue] Error processing log queue: $($_.Exception.Message)"
                }
            }
            $script:Logpos = $LogEnd
        }
        [gc]::Collect()
    }

    while ($script:ListenerInstance.IsListening) {
        if ((Get-Date) - $lastSessionSync -gt [TimeSpan]::FromMinutes(1)) {
            Sync-SessionStateToDatabase
            $lastSessionSync = Get-Date
        }

        if ((Get-Date) - $lastSettingsCheck -gt [TimeSpan]::FromSeconds(30)) {
            $settingsFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "config\settings.json"
            $currentSettingsWriteTime = (Get-Item $settingsFilePath).LastWriteTime
            if ($currentSettingsWriteTime -gt $global:PSWebServer.SettingsLastWriteTime) {
                Write-Verbose "settings.json has changed. Reloading..."
                $global:PSWebServer.SettingsLastWriteTime = $currentSettingsWriteTime
                $Global:PSWebServer.Config = (Get-Content $settingsFilePath) | ConvertFrom-Json
            }

            # Refresh tracked modules if needed (hot reload)
            if (Get-Command Invoke-ModuleRefreshAsNeeded -ErrorAction SilentlyContinue) {
                Invoke-ModuleRefreshAsNeeded
            }

            $lastSettingsCheck = Get-Date
        }

        # Update global cache every 10 seconds
        if ((Get-Date) - $lastGlobalCacheUpdate -gt [TimeSpan]::FromSeconds(10)) {
            Update-GlobalCache
            $lastGlobalCacheUpdate = Get-Date
        }

        # Process job submissions every 2 seconds
        if ((Get-Date) - $lastJobProcessing -gt [TimeSpan]::FromSeconds(2)) {
            try {
                # Process app main_loop.ps1 files (cached scriptblock execution for efficiency)
                # This runs in the main loop context with direct access to $Global:PSWebServer.Jobs
                # Each app can have a main_loop.ps1 that runs every loop iteration

                # Initialize Apps scriptblock cache if not exists
                if (-not $Global:PSWebServer.Apps) {
                    $Global:PSWebServer.Apps = [hashtable]::Synchronized(@{})
                }

                # Get all app directories
                $appsPath = Join-Path $Global:PSWebServer.Project_Root.Path "apps" -Directory
                if (Test-Path $appsPath) {
                    $appDirs = Get-ChildItem -Path $appsPath -Directory

                    foreach ($appDir in $appDirs) {
                        $appName = $appDir.Name
                        $mainLoopPath = Join-Path $appDir.FullName "main_loop.ps1"

                        if (Test-Path $mainLoopPath) {
                            # Initialize app cache structure if not exists
                            if (-not $Global:PSWebServer.Apps.ContainsKey($appName)) {
                                $Global:PSWebServer.Apps[$appName] = [hashtable]::Synchronized(@{
                                    ScriptBlocks = [hashtable]::Synchronized(@{
                                        MainLoop = [hashtable]::Synchronized(@{
                                            Code = $null
                                            LastWriteTime = $null
                                        })
                                    })
                                })
                            }

                            # Get current file modification time
                            $currentWriteTime = (Get-Item $mainLoopPath).LastWriteTime
                            if (!$Global:PSWebServer.Apps[$appName].contains('ScriptBlocks') ) {
                                $Global:PSWebServer.Apps[$appName].ScriptBlock = [hashtable]::new{@{}}
                            }
                            if (!$Global:PSWebServer.Apps[$appName].ScriptBlocks.contains('MainLoop') ) {
                                $Global:PSWebServer.Apps[$appName].ScriptBlock.Mainloop  = [hashtable]::new(
                                    @{Code={};LastWriteTime=$null}
                                )
                            }

                            # Check if we need to reload the scriptblock
                            if ($Global:PSWebServer.Apps[$appName]['ScriptBlocks']['MainLoop']['LastWriteTime'] -ne $currentWriteTime) {
                                # File changed or first load - create new scriptblock
                                try {
                                    $scriptContent = Get-Content -Path $mainLoopPath -Raw
                                    $Global:PSWebServer.Apps[$appName]['ScriptBlocks']['MainLoop']['Code'] = [scriptblock]::Create($scriptContent)
                                    $Global:PSWebServer.Apps[$appName]['ScriptBlocks']['MainLoop']['LastWriteTime'] = $currentWriteTime
                                    Write-Verbose "[WebHost] Cached main_loop.ps1 scriptblock for app: $appName"
                                }
                                catch {
                                    Write-PSWebHostLog -Severity 'Error' -Category 'AppMainLoop' -Message "Failed to cache main_loop.ps1 for $appName : $($_.Exception.Message)"
                                }
                            }

                            # Execute cached scriptblock
                            if ($Global:PSWebServer.Apps[$appName]['ScriptBlocks']['MainLoop']['Code']) {
                                try {
                                    & $Global:PSWebServer.Apps[$appName]['ScriptBlocks']['MainLoop']['Code']
                                }
                                catch {
                                    Write-PSWebHostLog -Severity 'Error' -Category 'AppMainLoop' -Message "Error executing main_loop.ps1 for $appName : $($_.Exception.Message)"
                                }
                            }
                        }
                    }
                }
            }
            catch {
                Write-PSWebHostLog -Severity 'Error' -Category 'JobExecution' -Message "Error processing job submissions: $($_.Exception.Message)`n$($_.InvocationInfo.Line)"
            }
            $lastJobProcessing = Get-Date
        }

        . Invoke-ModuleRefreshAsNeeded

        . ProcessLogQueue

        $UIQueueEnd = $PSHostUIQueue.count
        if ($UIQueueEnd -lt $UIQueuePos) {
            $UIQueuePos = 0
        }
        if ([int]$UIQueuePos -lt $UIQueueEnd) {
            $UIQueuePos .. ($UIQueueEnd -1)|ForEach-Object{$PSHostUIQueue[$_]}| ForEach-Object {
                $Host.UI.WriteLine($_)
            }
            $UIQueuePos = $UIQueueEnd
        }

        if ($Async) {
            # In async mode, worker runspaces directly acquire and process contexts
            # Main thread just monitors health and collects output

            # Collect output streams from workers and relay to console
            Update-AsyncWorkerStatus

            # Repair any broken runspaces in the pool (check every 5 seconds)
            if (((Get-Date).Second % 5) -eq 0 -and $global:AsyncRunspacePool.LastCleanup -lt (Get-Date).AddSeconds(-5)) {
                Repair-AsyncRunspacePool
                $global:AsyncRunspacePool.LastCleanup = Get-Date
            }

            # Brief pause - workers handle requests independently
            Start-Sleep -Milliseconds 500
        } 
        else {
            try {
                $context = $script:ListenerInstance.GetContext()
                $Loop_Start = Get-Date
                Write-Verbose "Synchronous context received. Processing request $($context.Request.RawUrl)"
                Process-HttpRequest -Context $context -HostUIQueue $global:PSHostUIQueue -InlineExecute
            } catch {
                Write-PSWebHostLog -Severity 'Error' -Category 'RequestHandler' -Message "[WebHost.PS1] A terminating error occurred while processing a synchronous request: $($_.Exception.Message + "`n" + $_.InvocationInfo.PositionMessage)" -Data @{ Message = $_.Exception.Message; PositionMessage=$_.InvocationInfo.PositionMessage} -WriteHost
            }
            $I=0
            $Error | 
                Where-Object{$_} |
                ForEach-Object{
                    Write-PSWebHostLog -Severity 'Error' -Category 'ErrorArrayCheck' -Message "[WebHost.PS1] `$Error[$i] $($_.Exception.Message + "`n" + $_.InvocationInfo.PositionMessage)" -Data @{ Message = $_.Exception.Message; PositionMessage=$_.InvocationInfo.PositionMessage} -WriteHost
                    $I++
                }
            $Error.Clear()
        }
        if ($StopOnScriptUpdate.IsPresent) {
            $FileDate = (get-item $MyInvocation.MyCommand.Path).LastWriteTime # This is the current script's last write time
            if ($InitialFileDate -ne $FileDate) { # If the script file has been updated
                $script:ListenerInstance.Stop()
                Write-PSWebHostLog -Message "Script file updated. Stopping listener for reload." -Severity 'Information' -Category 'ScriptUpdate'
            }
        }
    }
    $logData = @{ Error = $_.Exception.Message; StackTrace = $_.Exception.StackTrace }
    Write-PSWebHostLog -Severity 'Error' -Category 'Listener' -Message "Error in listener loop" -Data $logData
    . ProcessLogQueue

    Write-Verbose "Exiting listener loop."

    # --- Cleanup ---

    # Stop async runspace pool if it was initialized
    if ($Async -and $global:AsyncRunspacePool -and $global:AsyncRunspacePool.Initialized) {
        Write-Host "Stopping async runspace pool..."
        Stop-AsyncRunspacePool -TimeoutSeconds 10
    }

    if ($script:ListenerInstance -and $script:ListenerInstance.IsListening) {
        $script:ListenerInstance.Stop()
        $script:ListenerInstance.Close()
        Write-Verbose "Listener stopped."
    }

    # Stop the performance monitoring job
    Write-Host "Stopping performance monitoring job..."
    $perfJobScript = Join-Path $Global:PSWebServer.Project_Root.Path "system\SQLITE_Perf_Table_Updater.ps1"
    if (Test-Path $perfJobScript) {
        & $perfJobScript -StopJob
        Write-Host "Performance monitoring job stopped."
    }

    # Stop the logging job
    $global:StopLogging = $true
    if (! $InitializeEnvironmentOnly.ispresent -and $global:PSWebServer.LoggingJob) {
        $global:PSWebServer.LoggingJob.AsyncWaitHandle.WaitOne(2000) | Out-Null # Wait up to 2s for it to stop
    }
    if ($loggingPowerShell) {
        $loggingPowerShell.Dispose()
        Write-Verbose "Logging job stopped."
    }
    else {
        Write-Verbose "Logging job was not started."
    }

    # Stop the output monitor job
    $global:StopOutputMonitor = $true
    if ($script:OutputMonitorJob){
        $script:OutputMonitorJob.AsyncWaitHandle.WaitOne(2000) | Out-Null
        $outputMonitorPowerShell.Dispose()
    }
    else{
        Write-Verbose "script:OutputMonitorJob is null."
    }
    Write-Verbose "Runspace output monitor job stopped."
}