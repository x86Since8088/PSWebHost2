[cmdletbinding()]
param (
    [switch]$RunInProcess,
    [switch]$ShowVariables, # For validateInstall.ps1
    [string]$AuthenticationSchemes = "Anonymous",
    [switch]$Async, # New parameter for asynchronous handling
    [int]$Port = 8080,
    [switch]$ReloadOnScriptUpdate,
    [switch]$StopOnScriptUpdate
)
begin {
    Write-Verbose 'Starting init.ps1...'
    $Start = Get-Date
    . (Join-Path $PSScriptRoot 'system/init.ps1')
    Write-Host "Init.ps1 completed after $(((Get-date) - $start).TotalMilliseconds) milliseconds"
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

    # Call validateInstall.ps1 if -ShowVariables is present
    if ($ShowVariables.IsPresent) {
        Write-Verbose "Calling validateInstall.ps1 with -ShowVariables..."
        . (Join-Path $Global:PSWebServer.Project_Root.Path "system\validateInstall.ps1") -ShowVariables
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
                            $OutputItem.gettype()|ft
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
    
    # For non-admin users, try localhost first, then fall back to +
    $prefixesToTry = @()
    if (-not $isAdmin) {
        $prefixesToTry += "http://localhost:$port/"
    }
    $prefixesToTry += "http://+:$port/"
    
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
}

process {
    # This block is typically for pipeline input, but for a continuous listener,
    # we'll use a while loop here.
    # The actual listening loop is handled in the end block for proper cleanup.
}

end {
    if ($ReloadOnScriptUpdate.IsPresent) {
        # return as this script mode does not need to run a listener
        return
    }

    function Invoke-ModuleRefreshAsNeeded {
        if ($null -eq $script:ModuleRefreshAsNeeded) {
            $script:ModuleRefreshAsNeeded = (Get-Date).AddSeconds(30)
            return 
        }
        elseif ($Script:ModuleRefreshAsNeeded -lt (get-date)) {
            return
        }
        $script:ModuleRefreshAsNeeded = (Get-Date).AddSeconds(30)
        foreach ($entry in $Global:PSWebServer.Modules.GetEnumerator()) {
            $moduleName = $entry.Name
            $moduleData = $entry.Value
            $fileInfo = Get-Item -Path $moduleData.Path -ErrorAction SilentlyContinue
            if ($fileInfo -and $fileInfo.LastWriteTime -gt $moduleData.LastWriteTime) {
                Write-Verbose "Module '$moduleName' has changed. Reloading..."
                try {
                    Remove-Module -Name $moduleName -Force
                    if (-not $?) {
                        Write-Warning "Remove-Module reported failure for module '$moduleName' - continuing."
                    }
                    $reloadedModuleInfo = Import-Module -Name $moduleData.Path -Force -PassThru -ErrorAction Continue -DisableNameChecking 2>&1
                    $newFileInfo = Get-Item -Path $moduleData.Path
                    $Global:PSWebServer.Modules[$moduleName].LastWriteTime = $newFileInfo.LastWriteTime
                    $Global:PSWebServer.Modules[$moduleName].Loaded = (Get-Date)
                    Write-Verbose "Module '$moduleName' reloaded successfully."
                } catch {
                    Write-Error "Failed to reload module '$moduleName': $_"
                }
            }
        }
    }

    Write-Verbose "Entering listener loop."
    if ($Null -eq $Logpos) {$Logpos = 0}
    if ($Null -eq $UIQueuePos) {$UIQueuePos = 0}
    $Loop_Start = Get-Date
    $lastSettingsCheck = Get-Date
    $lastSessionSync = Get-Date
    
    function ProcessLogQueue {
        $LogEnd = $PSWebHostLogQueue.count
        if ($LogEnd -lt $Logpos) {
            $Logpos = 0
        }
        if ([int]$Logpos -lt $LogEnd) {
            [array]$logEntries = $LogPos .. ($LogEnd -1)|ForEach-Object{$PSWebHostLogQueue[$_]}
            if ($logEntries.Count) {
                $logEntries|Tee-Object -FilePath $global:PSWebServer.LogFilePath -Append|ForEach-Object{Write-Host "`tLogging: $_"}
            }
            $Logpos = $LogEnd
        }
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
            $lastSettingsCheck = Get-Date
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
            # Check for and clean up completed runspace jobs every 5 seconds.
            if (((get-date).Second % 5) -eq 0) {
                if ($global:PSWebSessions) {
                    $sessions = $global:PSWebSessions.Clone()
                    foreach ($sessionEntry in $sessions.GetEnumerator()) {
                        $sessionData = $sessionEntry.Value
                        if ($sessionData.Runspaces) {
                            $runspaceTable = $sessionData.Runspaces
                            $runspaceKeys = @($runspaceTable.Keys)
                            
                            foreach ($key in $runspaceKeys) {
                                if ($key -like "*_handle") {
                                    $handle = $runspaceTable[$key]
                                    if ($handle.IsCompleted) {
                                        $psInstanceKey = $key.Replace('_handle', '_ps')
                                        if ($runspaceTable.ContainsKey($psInstanceKey)) {
                                            $psInstance = $runspaceTable[$psInstanceKey]
                                            try {
                                                $psInstance.EndInvoke($handle)
                                            } catch {
                                                Write-Warning "Error in background runspace for session $($sessionEntry.Key): $($_.Exception.Message)"
                                            } finally {
                                                $psInstance.Dispose()
                                                $runspaceTable.Remove($key)
                                                $runspaceTable.Remove($psInstanceKey)
                                                Write-Verbose "Cleaned up completed runspace job for session $($sessionEntry.Key)."
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            # Use the modern Task-based Asynchronous Pattern (TAP)
            
            # If there is no active task to get a context, start one.
            if ($null -eq $contextTask) {
                $contextTask = $script:ListenerInstance.GetContextAsync()
                $msg = "Asynchronous listener waiting for a new request."
                Write-Verbose $msg
            }

            # Check if the task has completed.
            if ($contextTask.IsCompleted) {
                if ($contextTask.IsFaulted) {
                    # The async operation failed. Log the error and reset the task.
                    $msg = "An error occurred while waiting for a request: $($contextTask.Exception.InnerException.Message)"
                    Write-Warning $msg
                    $contextTask = $null
                } else {
                    # The operation completed successfully. Get the context.
                    $context = $contextTask.Result
                    $msg = "Asynchronous context received. Processing request."
                    Write-Verbose $msg
                    $contextTask = $null
                    # Process the request asynchronously in a separate runspace.
                    Process-HttpRequest -Context $context -Async -HostUIQueue $global:PSHostUIQueue -InlineExecute
                    
                    # Reset the task to be ready for the next request.
                    $contextTask = $null
                }
            }
            
            # Pause briefly to prevent a tight loop.
            Start-Sleep -Milliseconds 100
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
    if ($script:ListenerInstance -and $script:ListenerInstance.IsListening) {
        $script:ListenerInstance.Stop()
        $script:ListenerInstance.Close()
        Write-Verbose "Listener stopped."
    }

    # Stop the logging job
    $global:StopLogging = $true
    if (! $ShowVariables.ispresent -and $global:PSWebServer.LoggingJob) {
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