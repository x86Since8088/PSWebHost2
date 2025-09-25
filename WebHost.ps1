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
    . (Join-Path $PSScriptRoot 'system/init.ps1')
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
        Write-Verbose "Calling validateInstall.ps1 with -ShowVariables..." -Verbose
        . (Join-Path $Global:PSWebServer.Project_Root.Path "system\validateInstall.ps1") -ShowVariables
        return # Exit after showing variables
    }
    elseif ($ReloadOnScriptUpdate.IsPresent) {
        # Launch this script in a while ($true) loop with -StopOnScriptUpdate added to the other parameters except for -ReloadOnScriptUpdate.
        while($true) {
            $splat = @{}
            $PSBoundParameters.Keys|Where-Object{$_ -ne 'ReloadOnScriptUpdate'}|ForEach-Object{$splat[$_]=$PSBoundParameters[$_]}
            [string[]]$ArgumentList = @("-ExecutionPolicy","RemoteSigned","-Command", "$PSScriptRoot\WebHost.ps1", "-StopOnScriptUpdate") +  ($splat.keys|ForEach-Object{$_,$splat[$_]}) +
            {
                2>&1 |Where-Object{$_}|ForEach-Object{
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
        Write-Host "Starting pwsh directly so that output is directly parsed.`n`tpwsh.exe $ArgumentList"
            pwsh.exe $ArgumentList 
        }
        return
    }

    # Listener setup
    $listener = New-Object System.Net.HttpListener
    if ($Port -notmatch '\d') {
        $port = $Global:PSWebServer.Config.WebServer.Port
    }
    $prefix = "http://+:$port/"
    $listener.Prefixes.Add($prefix)
    $listener.AuthenticationSchemes = [System.Net.AuthenticationSchemes]::$AuthenticationSchemes

    try {
        $listener.Start()
        Write-Host "Listening on $($prefix -replace '\+:','localhost:')"
    } catch {
        Write-Error "Failed to start listener: $($_.Exception.Message)"
        exit 1
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
                Write-Host "Module '$moduleName' has changed. Reloading..."
                try {
                    Remove-Module -Name $moduleName -Force -ErrorAction Stop
                    $reloadedModuleInfo = Import-Module -Name $moduleData.Path -Force -PassThru -ErrorAction Continue -DisableNameChecking 2>&1
                    $newFileInfo = Get-Item -Path $moduleData.Path
                    $Global:PSWebServer.Modules[$moduleName].LastWriteTime = $newFileInfo.LastWriteTime
                    $Global:PSWebServer.Modules[$moduleName].Loaded = (Get-Date)
                    Write-Host "Module '$moduleName' reloaded successfully."
                } catch {
                    Write-Error "Failed to reload module '$moduleName': $_"
                }
            }
        }
    }

    Write-Verbose "Entering listener loop." -Verbose
    if ($Null -eq $Logpos) {$Logpos = 0}
    if ($Null -eq $UIQueuePos) {$UIQueuePos = 0}
    $Loop_Start = Get-Date
    $lastSettingsCheck = Get-Date
    $lastSessionSync = Get-Date
    while ($script:ListenerInstance.IsListening) {
        if ((Get-Date) - $lastSessionSync -gt [TimeSpan]::FromMinutes(1)) {
            Sync-SessionStateToDatabase
            $lastSessionSync = Get-Date
        }

        if ((Get-Date) - $lastSettingsCheck -gt [TimeSpan]::FromSeconds(30)) {
            $settingsFilePath = Join-Path $Global:PSWebServer.Project_Root.Path "config\settings.json"
            $currentSettingsWriteTime = (Get-Item $settingsFilePath).LastWriteTime
            if ($currentSettingsWriteTime -gt $global:PSWebServer.SettingsLastWriteTime) {
                Write-Host "settings.json has changed. Reloading..."
                $global:PSWebServer.SettingsLastWriteTime = $currentSettingsWriteTime
                $Global:PSWebServer.Config = (Get-Content $settingsFilePath) | ConvertFrom-Json
            }
            $lastSettingsCheck = Get-Date
        }
        
        . Invoke-ModuleRefreshAsNeeded

        $LogEnd = $PSWebHostLogQueue.count
        if ($LogEnd -lt $Logpos) {
            $Logpos = 0
        }
        if ([int]$Logpos -lt $LogEnd) {
            $LogPos .. ($LogEnd -1)|ForEach-Object{$PSWebHostLogQueue[$_]}| Select-Object * | Format-Table -AutoSize -Wrap
            $Logpos = $LogEnd
        }

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

        #try {
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
                        Process-HttpRequest -Context $context -Async -HostUIQueue $global:PSHostUIQueue
                        
                        # Reset the task to be ready for the next request.
                        $contextTask = $null
                    }
                }
                
                # Pause briefly to prevent a tight loop.
                Start-Sleep -Milliseconds 100
            } else {
                $Loop_End = Get-Date
                Write-Host "Sync request loop completed: $(($Loop_End - $Loop_Start).TotalMilliseconds)ms $($Context.request.HttpMethod) $($Context.request.Url.AbsoluteUri)"
                $global:PSHostUIQueue.Enqueue("Sync request loop completed: $(($Loop_End - $Loop_Start).TotalMilliseconds)ms $($Context.request.HttpMethod) $($Context.request.Url.AbsoluteUri)")
                $context = $script:ListenerInstance.GetContext()
                $Loop_Start = Get-Date
                Process-HttpRequest -Context $context -HostUIQueue $global:PSHostUIQueue
            }
        if ($StopOnScriptUpdate.IsPresent) {
            $FileDate = (get-item $MyInvocation.MyCommand.Path).LastWriteTime # This is the current script's last write time
            if ($InitialFileDate -ne $FileDate) { # If the script file has been updated
                # If the script has been updated, stop the listener and exit.
                # This allows the parent script (if -ReloadOnScriptUpdate was used) to restart it.
                # Stopping the listener will stop this loop after completion.
                
                # Stop pending async operations.
                # This is important to prevent new requests from being processed while the script is
                # preparing to exit or reload.
                # This ensures a clean shutdown and avoids orphaned processes.
                # This also allows the parent process to restart the script cleanly.
                # This is crucial for maintaining application stability and resource management.
                # This also ensures that any pending HTTP responses are sent before the script exits.
                # This is especially important for long-running requests or streaming responses.
                # This helps prevent client-side errors due to abrupt connection closures.
                # This also ensures that any resources held by the script are properly released.

                $script:ListenerInstance.Stop()
                Write-PSWebHostLog -Message "Script file updated. Stopping listener for reload." -Severity 'Information' -Category 'ScriptUpdate'
            }
        }

        #} catch [System.Net.HttpListenerException] {
        #    # This exception can be thrown if the listener is stopped while GetContextAsync is pending.
        #    Write-Verbose "Listener was stopped. Exiting loop." -Verbose
        #} catch {
        #    $logData = @{ Error = $_.Exception.Message; StackTrace = $_.Exception.StackTrace }
        #    Write-PSWebHostLog -Severity 'Error' -Category 'Listener' -Message "Error in listener loop" -Data $logData
        #}
    }
    Write-Verbose "Exiting listener loop." -Verbose

    # --- Cleanup ---
    if ($script:ListenerInstance -and $script:ListenerInstance.IsListening) {
        $script:ListenerInstance.Stop()
        $script:ListenerInstance.Close()
        Write-Host "Listener stopped."
    }

    # Stop the logging job
    $global:StopLogging = $true
    if (! $ShowVariables.ispresent) {
        $global:PSWebServer.LoggingJob.AsyncWaitHandle.WaitOne(2000) | Out-Null # Wait up to 2s for it to stop
    }
    if ($loggingPowerShell) {
        $loggingPowerShell.Dispose()
        Write-Verbose "Logging job stopped." -Verbose
    }
    else {
        Write-Verbose "Logging job was not started." -Verbose
    }

    # Stop the output monitor job
    $global:StopOutputMonitor = $true
    if ($script:OutputMonitorJob){
        $script:OutputMonitorJob.AsyncWaitHandle.WaitOne(2000) | Out-Null
        $outputMonitorPowerShell.Dispose()
    }
    else{
        Write-Host "script:OutputMonitorJob is null."
    }
    Write-Verbose "Runspace output monitor job stopped." -Verbose
}
