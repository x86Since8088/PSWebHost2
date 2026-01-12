# system\AsyncRunspacePool.ps1
# Dedicated async runspace pool management for PSWebHost
# Goal: Maintain 15 pre-initialized runspaces that directly acquire contexts from the listener
#
# Architecture (v2 - Direct Context Acquisition):
# - Each runspace runs a continuous worker loop
# - Worker loops call $ListenerInstance.GetContextAsync() directly
# - When a context arrives, it's processed immediately in that runspace
# - This mirrors synchronous operation flow but runs in parallel
# - Main thread monitors runspace health and collects output streams

# Global synchronized hashtable for the runspace pool
if ($null -eq $global:AsyncRunspacePool) {
    $global:AsyncRunspacePool = [hashtable]::Synchronized(@{
        Runspaces = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
        Workers = [hashtable]::Synchronized(@{})  # PowerShell instances running worker loops
        # ListenerInstance: shared HttpListener - set during initialization
        ListenerInstance = $null
        # StopRequested: signal to workers to exit their loops
        StopRequested = $false
        # Functions: Store function references so modules can access them
        Functions = [hashtable]::Synchronized(@{})
        # Stats: per-runspace statistics
        Stats = [hashtable]::Synchronized(@{})
        PoolSize = 15
        Initialized = $false
        LastCleanup = [datetime]::MinValue
    })
}

function Initialize-AsyncRunspacePool {
    <#
    .SYNOPSIS
        Initializes the async runspace pool with worker runspaces that directly acquire HTTP contexts.

    .DESCRIPTION
        Creates and opens the specified number of runspaces (default: 15) that are
        pre-configured with access to global variables. Each runspace runs a continuous
        worker loop that calls GetContextAsync() on the shared HttpListener.

    .PARAMETER PoolSize
        The number of runspaces to create. Default is 15.

    .PARAMETER ListenerInstance
        The HttpListener instance to share with runspaces for context acquisition.

    .PARAMETER Force
        Force re-initialization even if pool is already initialized.
    #>
    [CmdletBinding()]
    param(
        [int]$PoolSize = 15,
        [Parameter(Mandatory)]
        [System.Net.HttpListener]$ListenerInstance,
        [switch]$Force
    )

    $MyTag = '[Initialize-AsyncRunspacePool]'

    if ($global:AsyncRunspacePool.Initialized -and -not $Force) {
        Write-Verbose "$MyTag Runspace pool already initialized with $($global:AsyncRunspacePool.Runspaces.Count) runspaces"
        return
    }

    # Clean up existing runspaces if forcing re-init
    if ($Force -and $global:AsyncRunspacePool.Runspaces.Count -gt 0) {
        Stop-AsyncRunspacePool -TimeoutSeconds 5
    }

    # Store the listener instance for runspaces to access
    $global:AsyncRunspacePool.ListenerInstance = $ListenerInstance
    $global:AsyncRunspacePool.StopRequested = $false
    $global:AsyncRunspacePool.PoolSize = $PoolSize

    Write-Verbose "$MyTag Creating $PoolSize worker runspaces for async request handling"

    for ($i = 1; $i -le $PoolSize; $i++) {
        $rsInfo = New-AsyncRunspace -Index $i
        if ($rsInfo) {
            [void]$global:AsyncRunspacePool.Runspaces.Add($rsInfo)
            $global:AsyncRunspacePool.Stats[$i] = [hashtable]::Synchronized(@{
                RequestCount = 0
                LastRequest = $null
                Errors = 0
                State = 'Initializing'
            })
            Write-Verbose "$MyTag Created runspace $i of $PoolSize (ID: $($rsInfo.Runspace.InstanceId))"
        }
    }

    # Start worker loops in each runspace
    foreach ($rsInfo in $global:AsyncRunspacePool.Runspaces) {
        Start-AsyncWorker -RunspaceInfo $rsInfo
    }

    $global:AsyncRunspacePool.Initialized = $true
    $global:AsyncRunspacePool.LastCleanup = Get-Date

    # Store function references in the synchronized hashtable so modules can access them
    $global:AsyncRunspacePool.Functions['Update-AsyncWorkerStatus'] = ${function:Update-AsyncWorkerStatus}
    $global:AsyncRunspacePool.Functions['Repair-AsyncRunspacePool'] = ${function:Repair-AsyncRunspacePool}
    $global:AsyncRunspacePool.Functions['Get-AsyncPoolStatus'] = ${function:Get-AsyncPoolStatus}

    Write-Host "$MyTag Async runspace pool initialized with $($global:AsyncRunspacePool.Runspaces.Count) worker runspaces"
}

function New-AsyncRunspace {
    <#
    .SYNOPSIS
        Creates a new runspace configured for async HTTP context processing.

    .DESCRIPTION
        Creates an opened runspace with access to required global variables
        and modules for processing HTTP requests. The runspace receives
        synchronized hashtables that allow it to communicate with the main thread.

    .PARAMETER Index
        The index number for this runspace (for logging/identification).
    #>
    [CmdletBinding()]
    param(
        [int]$Index = 0
    )

    $MyTag = '[New-AsyncRunspace]'

    try {
        # Create initial session state with required modules and variables
        $iss = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()

        # Import required modules into the session state
        $modulesPath = Join-Path $global:PSWebServer.Project_Root.Path "modules"
        $moduleFiles = @(
            (Join-Path $modulesPath "PSWebHost_Support\PSWebHost_Support.psd1"),
            (Join-Path $modulesPath "PSWebHost_Users\PSWebHost_Users.psd1"),
            (Join-Path $modulesPath "PSWebHost_Logging\PSWebHost_Logging.psd1"),
            (Join-Path $modulesPath "PSWebHost_Database\PSWebHost_Database.psd1"),
            (Join-Path $modulesPath "PSWebHost_Authentication\PSWebHost_Authentication.psd1")
        )

        foreach ($modPath in $moduleFiles) {
            if (Test-Path $modPath) {
                $iss.ImportPSModule($modPath)
            }
        }

        # Create the runspace with the initial session state
        $rs = [runspacefactory]::CreateRunspace($iss)
        $rs.ApartmentState = [System.Threading.ApartmentState]::MTA
        $rs.ThreadOptions = [System.Management.Automation.Runspaces.PSThreadOptions]::ReuseThread
        $rs.Open()

        # Inject thread-safe global variables into the runspace
        # These are the SAME synchronized/concurrent objects from the main thread
        # Changes made in the runspace are visible to the main thread and vice versa
        #
        # Thread-safe types used:
        # - PSWebServer:        [hashtable]::Synchronized(@{})
        # - PSWebSessions:      [hashtable]::Synchronized(@{})
        # - PSWebHostLogQueue:  [ConcurrentQueue[string]]
        # - PSHostUIQueue:      [ConcurrentQueue[string]]
        # - PSWebPerfQueue:     [ConcurrentQueue[hashtable]]
        # - AsyncRunspacePool:  [hashtable]::Synchronized(@{})
        #
        # IMPORTANT: We must run a script in the runspace to set $global: variables
        # because SessionStateProxy.SetVariable only sets session variables, not globals.
        # The modules loaded during Open() may have already set their own $global: vars.
        #
        $setupScript = {
            param($PSWebServer, $PSWebSessions, $PSWebHostLogQueue, $PSHostUIQueue, $PSWebPerfQueue, $AsyncRunspacePool)
            $global:PSWebServer = $PSWebServer
            $global:PSWebSessions = $PSWebSessions
            $global:PSWebHostLogQueue = $PSWebHostLogQueue
            $global:PSHostUIQueue = $PSHostUIQueue
            $global:PSWebPerfQueue = $PSWebPerfQueue
            $global:AsyncRunspacePool = $AsyncRunspacePool
        }

        $setupPs = [powershell]::Create()
        $setupPs.Runspace = $rs
        [void]$setupPs.AddScript($setupScript)
        [void]$setupPs.AddArgument($global:PSWebServer)
        [void]$setupPs.AddArgument($global:PSWebSessions)
        [void]$setupPs.AddArgument($global:PSWebHostLogQueue)
        [void]$setupPs.AddArgument($global:PSHostUIQueue)
        [void]$setupPs.AddArgument($global:PSWebPerfQueue)
        [void]$setupPs.AddArgument($global:AsyncRunspacePool)
        $setupPs.Invoke()
        $setupPs.Dispose()

        return @{
            Runspace = $rs
            Index = $Index
            CreatedAt = Get-Date
            InUse = $false
            LastUsed = [datetime]::MinValue
            RequestCount = 0
        }
    } catch {
        Write-Warning "$MyTag Failed to create runspace $Index`: $($_.Exception.Message)"
        return $null
    }
}

function Start-AsyncWorker {
    <#
    .SYNOPSIS
        Starts a worker loop in a runspace that directly acquires and processes HTTP contexts.

    .DESCRIPTION
        Launches a continuous loop in the specified runspace that:
        1. Calls GetContextAsync() on the shared HttpListener
        2. Processes the received context using Process-HttpRequest
        3. Repeats until StopRequested is signaled

        This mirrors synchronous operation but runs in parallel across multiple runspaces.

    .PARAMETER RunspaceInfo
        The runspace info hashtable containing the runspace to start the worker in.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$RunspaceInfo
    )

    $MyTag = '[Start-AsyncWorker]'
    $rsIndex = $RunspaceInfo.Index

    # The worker script that runs continuously in the runspace
    $workerScript = {
        param(
            $RunspaceIndex,
            $AsyncRunspacePool,
            $PSWebServer,
            $PSWebSessions,
            $PSWebHostLogQueue,
            $PSHostUIQueue,
            $PSWebPerfQueue
        )

        $rsTag = "[Runspace $RunspaceIndex]"

        # Set global variables in this runspace
        $global:PSWebServer = $PSWebServer
        $global:PSWebSessions = $PSWebSessions
        $global:PSWebHostLogQueue = $PSWebHostLogQueue
        $global:PSHostUIQueue = $PSHostUIQueue
        $global:PSWebPerfQueue = $PSWebPerfQueue
        $global:AsyncRunspacePool = $AsyncRunspacePool

        # Load additional functions not in modules (e.g., Get-PSWebHostErrorReport)
        $functionsScript = Join-Path $PSWebServer.Project_Root.Path "system\Functions.ps1"
        if (Test-Path $functionsScript) {
            . $functionsScript
        }

        # Update stats
        $AsyncRunspacePool.Stats[$RunspaceIndex].State = 'Running'

        # Log startup
        if ($null -ne $PSWebHostLogQueue) {
            $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tVerbose`tAsyncWorker`t$rsTag Worker started`t`t`t"
            $PSWebHostLogQueue.Enqueue($logEntry)
        }

        $listener = $AsyncRunspacePool.ListenerInstance

        # Main worker loop
        while (-not $AsyncRunspacePool.StopRequested) {
            try {
                $AsyncRunspacePool.Stats[$RunspaceIndex].State = 'Waiting'

                # Get context asynchronously with a timeout so we can check StopRequested
                $contextTask = $listener.GetContextAsync()

                # Wait up to 500ms for a request, then loop to check StopRequested
                while (-not $contextTask.IsCompleted -and -not $AsyncRunspacePool.StopRequested) {
                    Start-Sleep -Milliseconds 100
                }

                if ($AsyncRunspacePool.StopRequested) {
                    break
                }

                if ($contextTask.IsFaulted) {
                    $AsyncRunspacePool.Stats[$RunspaceIndex].Errors++
                    if ($null -ne $PSWebHostLogQueue) {
                        $errMsg = $contextTask.Exception.InnerException.Message
                        $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tWarning`tAsyncWorker`t$rsTag GetContextAsync failed: $errMsg`t`t`t"
                        $PSWebHostLogQueue.Enqueue($logEntry)
                    }
                    continue
                }

                # Got a context - process it
                $context = $contextTask.Result
                $AsyncRunspacePool.Stats[$RunspaceIndex].State = 'Processing'
                $AsyncRunspacePool.Stats[$RunspaceIndex].RequestCount++
                $AsyncRunspacePool.Stats[$RunspaceIndex].LastRequest = Get-Date

                $requestUrl = $context.Request.RawUrl
                if ($null -ne $PSWebHostLogQueue) {
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tVerbose`tAsyncWorker`t$rsTag Processing: $requestUrl`t`t`t"
                    $PSWebHostLogQueue.Enqueue($logEntry)
                }

                try {
                    # Process the request - same as sync mode but in this runspace
                    Process-HttpRequest -Context $context -HostUIQueue $PSHostUIQueue -InlineExecute
                } catch {
                    $AsyncRunspacePool.Stats[$RunspaceIndex].Errors++
                    $errMsg = $_.Exception.Message

                    if ($null -ne $PSWebHostLogQueue) {
                        $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tError`tAsyncWorker`t$rsTag Request error: $errMsg`t`t`t"
                        $PSWebHostLogQueue.Enqueue($logEntry)
                    }

                    # Try to send error response if possible
                    try {
                        if ($context.Response.OutputStream.CanWrite) {
                            $context.Response.StatusCode = 500
                            $context.Response.ContentType = "application/json"
                            $errorJson = @{
                                status = 'error'
                                message = 'An unexpected error occurred.'
                                details = $errMsg
                            } | ConvertTo-Json -Compress
                            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                            $context.Response.ContentLength64 = $errorBytes.Length
                            $context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
                        }
                    } catch { }
                } finally {
                    # Ensure response is closed
                    try {
                        $context.Response.OutputStream.Close()
                    } catch { }
                }

            } catch {
                $AsyncRunspacePool.Stats[$RunspaceIndex].Errors++
                if ($null -ne $PSWebHostLogQueue) {
                    $errMsg = $_.Exception.Message
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tError`tAsyncWorker`t$rsTag Worker loop error: $errMsg`t`t`t"
                    $PSWebHostLogQueue.Enqueue($logEntry)
                }
                # Brief pause before retry
                Start-Sleep -Milliseconds 500
            }
        }

        # Worker is exiting
        $AsyncRunspacePool.Stats[$RunspaceIndex].State = 'Stopped'
        if ($null -ne $PSWebHostLogQueue) {
            $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tVerbose`tAsyncWorker`t$rsTag Worker stopped`t`t`t"
            $PSWebHostLogQueue.Enqueue($logEntry)
        }
    }

    # Create PowerShell instance and attach to runspace
    $ps = [powershell]::Create()
    $ps.Runspace = $RunspaceInfo.Runspace

    [void]$ps.AddScript($workerScript)
    [void]$ps.AddParameter('RunspaceIndex', $rsIndex)
    [void]$ps.AddParameter('AsyncRunspacePool', $global:AsyncRunspacePool)
    [void]$ps.AddParameter('PSWebServer', $global:PSWebServer)
    [void]$ps.AddParameter('PSWebSessions', $global:PSWebSessions)
    [void]$ps.AddParameter('PSWebHostLogQueue', $global:PSWebHostLogQueue)
    [void]$ps.AddParameter('PSHostUIQueue', $global:PSHostUIQueue)
    [void]$ps.AddParameter('PSWebPerfQueue', $global:PSWebPerfQueue)

    # Start the worker asynchronously
    $asyncHandle = $ps.BeginInvoke()

    # Store the worker info
    $global:AsyncRunspacePool.Workers[$rsIndex] = @{
        PowerShell = $ps
        AsyncHandle = $asyncHandle
        RunspaceInfo = $RunspaceInfo
        StartedAt = Get-Date
    }

    Write-Verbose "$MyTag Started worker in runspace $rsIndex"
}

function Get-AvailableRunspace {
    <#
    .SYNOPSIS
        Gets an available runspace from the pool.

    .DESCRIPTION
        Returns the first available runspace that is opened and not currently in use.
        If no runspace is available, returns $null.

    .OUTPUTS
        Hashtable with runspace info, or $null if none available.
    #>
    [CmdletBinding()]
    param()

    $MyTag = '[Get-AvailableRunspace]'

    foreach ($rsInfo in $global:AsyncRunspacePool.Runspaces) {
        if (-not $rsInfo.InUse -and
            $rsInfo.Runspace.RunspaceStateInfo.State -eq 'Opened' -and
            $rsInfo.Runspace.RunspaceAvailability -eq 'Available') {

            $rsInfo.InUse = $true
            $rsInfo.LastUsed = Get-Date
            Write-Verbose "$MyTag Found available runspace $($rsInfo.Index) (ID: $($rsInfo.Runspace.InstanceId))"
            return $rsInfo
        }
    }

    Write-Verbose "$MyTag No available runspace in pool"
    return $null
}

function Invoke-AsyncHttpRequest {
    <#
    .SYNOPSIS
        Processes an HTTP request asynchronously in a pooled runspace.

    .DESCRIPTION
        Takes an HTTP context and processes it in an available runspace from the pool.
        The runspace has access to global variables via synchronized hashtables that
        were injected when the runspace was created.

    .PARAMETER Context
        The System.Net.HttpListenerContext to process.

    .PARAMETER ScriptPath
        The path to the route handler script to execute.

    .PARAMETER ScriptParams
        Hashtable of parameters to pass to the script.

    .PARAMETER SessionID
        The session ID for tracking.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.HttpListenerContext]$Context,

        [Parameter(Mandatory)]
        [string]$ScriptPath,

        [hashtable]$ScriptParams = @{},

        [string]$SessionID
    )

    $MyTag = '[Invoke-AsyncHttpRequest]'

    # Get an available runspace
    $rsInfo = Get-AvailableRunspace

    if (-not $rsInfo) {
        # No runspace available - return 503
        Write-Warning "$MyTag No available runspace in pool. Returning 503 Service Unavailable."
        try {
            $Context.Response.StatusCode = 503
            $Context.Response.StatusDescription = "Service Unavailable - Server Busy"
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes("Server is busy. Please try again.")
            $Context.Response.ContentLength64 = $errorBytes.Length
            $Context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
            $Context.Response.OutputStream.Close()
        } catch {
            Write-Warning "$MyTag Error sending 503 response: $($_.Exception.Message)"
        }
        return
    }

    try {
        Write-Verbose "$MyTag Processing request in runspace $($rsInfo.Index)"

        # The script block that runs in the runspace
        # Global variables ($global:PSWebServer, $global:PSWebSessions, etc.) were already
        # set during runspace creation via the setup script in New-AsyncRunspace.
        # They point to the same synchronized/concurrent objects as the main thread.
        $scriptBlock = {
            param(
                $ScriptPath,
                $Context,
                $SessionData,
                $CardSettings,
                $VerboseOutput,
                $RunspaceIndex
            )

            $rsTag = "[Runspace $RunspaceIndex]"

            try {
                # Build script parameters
                $params = @{
                    Context = $Context
                    SessionData = $SessionData
                }

                if ($CardSettings) {
                    $params['CardSettings'] = $CardSettings
                }

                if ($VerboseOutput) {
                    $params['Verbose'] = $true
                }

                # Execute the route handler script
                & $ScriptPath @params
            } catch {
                # Log the error to the queue if available
                $errorMsg = "$rsTag Error in async request handler: $($_.Exception.Message)"
                if ($null -ne $global:PSWebHostLogQueue) {
                    $logEntry = "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ')`t$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`tError`tAsyncHandler`t$errorMsg`t`t`t"
                    $global:PSWebHostLogQueue.Enqueue($logEntry)
                }

                # Try to send JSON error response
                try {
                    # Check if response has already been started
                    if (-not $Context.Response.OutputStream.CanWrite) {
                        return
                    }

                    $Context.Response.StatusCode = 500
                    $Context.Response.StatusDescription = "Internal Server Error"
                    $Context.Response.ContentType = "application/json"

                    # Format as JSON for API consistency
                    $errorJson = @{
                        status = 'error'
                        message = 'An unexpected error occurred. Please try again.'
                        details = $_.Exception.Message
                    } | ConvertTo-Json -Compress

                    $errorBytes = [System.Text.Encoding]::UTF8.GetBytes($errorJson)
                    $Context.Response.ContentLength64 = $errorBytes.Length
                    $Context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
                } catch {
                    # Response may have already been sent or client disconnected
                }
            } finally {
                # Ensure response is closed
                try {
                    if ($Context.Response.OutputStream) {
                        $Context.Response.OutputStream.Close()
                    }
                } catch {
                    # Ignore close errors
                }
            }
        }

        # Create PowerShell instance and attach to runspace
        $ps = [powershell]::Create()
        $ps.Runspace = $rsInfo.Runspace

        # Add the script block with parameters
        # Note: We only pass the request-specific data as parameters
        # The global synchronized hashtables are already in the runspace
        [void]$ps.AddScript($scriptBlock)
        [void]$ps.AddParameter('ScriptPath', $ScriptPath)
        [void]$ps.AddParameter('Context', $Context)
        [void]$ps.AddParameter('SessionData', $ScriptParams.SessionData)
        [void]$ps.AddParameter('CardSettings', $ScriptParams.CardSettings)
        [void]$ps.AddParameter('VerboseOutput', $VerbosePreference -eq 'Continue')
        [void]$ps.AddParameter('RunspaceIndex', $rsInfo.Index)

        # Begin async invocation
        $asyncHandle = $ps.BeginInvoke()

        # Track the active job
        $jobId = [Guid]::NewGuid().ToString()
        $global:AsyncRunspacePool.ActiveJobs[$jobId] = @{
            PowerShell = $ps
            AsyncHandle = $asyncHandle
            RunspaceInfo = $rsInfo
            StartTime = Get-Date
            SessionID = $SessionID
            ScriptPath = $ScriptPath
        }

        $rsInfo.RequestCount++
        Write-Verbose "$MyTag Started async job $jobId in runspace $($rsInfo.Index)"

        return $jobId

    } catch {
        # Release the runspace on error
        $rsInfo.InUse = $false
        Write-Warning "$MyTag Error invoking async request: $($_.Exception.Message)"

        # Try to send error response
        try {
            $Context.Response.StatusCode = 500
            $Context.Response.StatusDescription = "Internal Server Error"
            $errorBytes = [System.Text.Encoding]::UTF8.GetBytes("Internal Server Error")
            $Context.Response.ContentLength64 = $errorBytes.Length
            $Context.Response.OutputStream.Write($errorBytes, 0, $errorBytes.Length)
            $Context.Response.OutputStream.Close()
        } catch {
            Write-Warning "$MyTag Error sending error response: $($_.Exception.Message)"
        }

        return $null
    }
}

function Update-AsyncWorkerStatus {
    <#
    .SYNOPSIS
        Monitors worker runspaces and collects their output streams.

    .DESCRIPTION
        Checks all worker runspaces for health and relays any output streams
        (Verbose, Warning, Error, Information) to the main console with
        runspace prefix for identification.
    #>
    [CmdletBinding()]
    param()

    $MyTag = '[Update-AsyncWorkerStatus]'

    foreach ($rsIndex in @($global:AsyncRunspacePool.Workers.Keys)) {
        $worker = $global:AsyncRunspacePool.Workers[$rsIndex]

        if ($null -eq $worker -or $null -eq $worker.PowerShell) {
            continue
        }

        $rsTag = "[Runspace $rsIndex]"
        $ps = $worker.PowerShell

        # Relay output streams to console with runspace prefix
        # Verbose stream
        while ($ps.Streams.Verbose.Count -gt 0) {
            $msg = $ps.Streams.Verbose[0]
            $ps.Streams.Verbose.RemoveAt(0)
            Write-Verbose "$rsTag $($msg.Message)"
        }

        # Warning stream
        while ($ps.Streams.Warning.Count -gt 0) {
            $msg = $ps.Streams.Warning[0]
            $ps.Streams.Warning.RemoveAt(0)
            Write-Warning "$rsTag $($msg.Message)"
        }

        # Information stream (includes Write-Host output)
        while ($ps.Streams.Information.Count -gt 0) {
            $msg = $ps.Streams.Information[0]
            $ps.Streams.Information.RemoveAt(0)
            Write-Host "$rsTag $($msg.MessageData)" -ForegroundColor Cyan
        }

        # Error stream
        while ($ps.Streams.Error.Count -gt 0) {
            $err = $ps.Streams.Error[0]
            $ps.Streams.Error.RemoveAt(0)
            Write-Warning "$rsTag Error: $($err.Exception.Message)"
        }

        # Check if worker has unexpectedly completed (crashed)
        if ($worker.AsyncHandle.IsCompleted) {
            try {
                $ps.EndInvoke($worker.AsyncHandle)
            } catch {
                Write-Warning "$MyTag Worker $rsIndex crashed: $($_.Exception.Message)"
            }

            # Worker has stopped - restart it
            Write-Warning "$MyTag Worker $rsIndex has stopped, restarting..."
            $rsInfo = $worker.RunspaceInfo

            # Check runspace health
            if ($rsInfo.Runspace.RunspaceStateInfo.State -ne 'Opened') {
                # Need new runspace
                $rsInfo = New-AsyncRunspace -Index $rsIndex
                if ($rsInfo) {
                    # Update in pool
                    for ($i = 0; $i -lt $global:AsyncRunspacePool.Runspaces.Count; $i++) {
                        if ($global:AsyncRunspacePool.Runspaces[$i].Index -eq $rsIndex) {
                            $global:AsyncRunspacePool.Runspaces[$i] = $rsInfo
                            break
                        }
                    }
                }
            }

            if ($rsInfo) {
                try { $ps.Dispose() } catch {}
                Start-AsyncWorker -RunspaceInfo $rsInfo
            }
        }
    }
}

function Repair-AsyncRunspacePool {
    <#
    .SYNOPSIS
        Repairs the runspace pool by replacing broken or closed runspaces.

    .DESCRIPTION
        Checks each runspace in the pool and replaces any that are in a broken
        or closed state. Ensures the pool always has the configured number of
        healthy runspaces.
    #>
    [CmdletBinding()]
    param()

    $MyTag = '[Repair-AsyncRunspacePool]'

    $targetSize = $global:AsyncRunspacePool.PoolSize
    $currentCount = $global:AsyncRunspacePool.Runspaces.Count

    # Check for and remove broken runspaces
    $toRemove = @()
    foreach ($rsInfo in $global:AsyncRunspacePool.Runspaces) {
        $state = $rsInfo.Runspace.RunspaceStateInfo.State
        if ($state -in @('Broken', 'Closed')) {
            Write-Verbose "$MyTag Runspace $($rsInfo.Index) is in state '$state', marking for removal"
            try {
                $rsInfo.Runspace.Dispose()
            } catch {}
            $toRemove += $rsInfo
        }
    }

    foreach ($rsInfo in $toRemove) {
        [void]$global:AsyncRunspacePool.Runspaces.Remove($rsInfo)
    }

    # Create replacements to reach target size
    $needed = $targetSize - $global:AsyncRunspacePool.Runspaces.Count
    if ($needed -gt 0) {
        Write-Verbose "$MyTag Creating $needed replacement runspaces"
        $nextIndex = ($global:AsyncRunspacePool.Runspaces | Measure-Object -Property Index -Maximum).Maximum + 1
        if (-not $nextIndex) { $nextIndex = 1 }

        for ($i = 0; $i -lt $needed; $i++) {
            $rsInfo = New-AsyncRunspace -Index $nextIndex
            if ($rsInfo) {
                [void]$global:AsyncRunspacePool.Runspaces.Add($rsInfo)
                Write-Verbose "$MyTag Created replacement runspace $nextIndex"
                $nextIndex++
            }
        }
    }

    if ($toRemove.Count -gt 0 -or $needed -gt 0) {
        Write-Host "$MyTag Repaired pool: removed $($toRemove.Count), added $needed. Pool now has $($global:AsyncRunspacePool.Runspaces.Count) runspaces."
    }
}

function Stop-AsyncRunspacePool {
    <#
    .SYNOPSIS
        Stops and disposes all worker runspaces in the pool.

    .DESCRIPTION
        Gracefully shuts down the async runspace pool by signaling workers to stop,
        waiting for them to exit (with timeout), and disposing all resources.

    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for workers to stop. Default is 10.
    #>
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 10
    )

    $MyTag = '[Stop-AsyncRunspacePool]'

    Write-Host "$MyTag Stopping async runspace pool..."

    # Signal all workers to stop
    $global:AsyncRunspacePool.StopRequested = $true

    # Wait for workers to exit gracefully
    $startWait = Get-Date
    $allStopped = $false
    while (-not $allStopped -and ((Get-Date) - $startWait).TotalSeconds -lt $TimeoutSeconds) {
        $allStopped = $true
        foreach ($rsIndex in @($global:AsyncRunspacePool.Workers.Keys)) {
            $worker = $global:AsyncRunspacePool.Workers[$rsIndex]
            if ($worker -and $worker.AsyncHandle -and -not $worker.AsyncHandle.IsCompleted) {
                $allStopped = $false
                break
            }
        }
        if (-not $allStopped) {
            Start-Sleep -Milliseconds 100
        }
    }

    # Force stop any remaining workers
    foreach ($rsIndex in @($global:AsyncRunspacePool.Workers.Keys)) {
        $worker = $global:AsyncRunspacePool.Workers[$rsIndex]
        if ($worker -and $worker.PowerShell) {
            try {
                $worker.PowerShell.Stop()
                $worker.PowerShell.Dispose()
            } catch {}
        }
    }
    $global:AsyncRunspacePool.Workers.Clear()

    # Dispose all runspaces
    foreach ($rsInfo in $global:AsyncRunspacePool.Runspaces) {
        try {
            if ($rsInfo.Runspace.RunspaceStateInfo.State -ne 'Closed') {
                $rsInfo.Runspace.Close()
            }
            $rsInfo.Runspace.Dispose()
        } catch {
            Write-Warning "$MyTag Error disposing runspace $($rsInfo.Index): $($_.Exception.Message)"
        }
    }
    $global:AsyncRunspacePool.Runspaces.Clear()
    $global:AsyncRunspacePool.Stats.Clear()
    $global:AsyncRunspacePool.Initialized = $false
    $global:AsyncRunspacePool.ListenerInstance = $null

    Write-Host "$MyTag Async runspace pool stopped."
}

function Get-AsyncPoolStatus {
    <#
    .SYNOPSIS
        Returns the current status of the async runspace pool.

    .OUTPUTS
        Hashtable with pool statistics.
    #>
    [CmdletBinding()]
    param()

    $waiting = 0
    $processing = 0
    $stopped = 0
    $totalRequests = 0
    $totalErrors = 0

    foreach ($rsIndex in @($global:AsyncRunspacePool.Stats.Keys)) {
        $stats = $global:AsyncRunspacePool.Stats[$rsIndex]
        if ($stats) {
            switch ($stats.State) {
                'Waiting' { $waiting++ }
                'Processing' { $processing++ }
                'Stopped' { $stopped++ }
            }
            $totalRequests += $stats.RequestCount
            $totalErrors += $stats.Errors
        }
    }

    return @{
        Initialized = $global:AsyncRunspacePool.Initialized
        PoolSize = $global:AsyncRunspacePool.PoolSize
        TotalRunspaces = $global:AsyncRunspacePool.Runspaces.Count
        WorkersWaiting = $waiting
        WorkersProcessing = $processing
        WorkersStopped = $stopped
        TotalRequestsHandled = $totalRequests
        TotalErrors = $totalErrors
        StopRequested = $global:AsyncRunspacePool.StopRequested
        LastCleanup = $global:AsyncRunspacePool.LastCleanup
        WorkerStats = $global:AsyncRunspacePool.Stats.Clone()
    }
}

# When dot-sourced, functions are automatically available in the calling scope
# No Export-ModuleMember needed since this is not a .psm1 module file
