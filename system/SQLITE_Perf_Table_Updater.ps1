<#
.SYNOPSIS
    Performance monitoring job manager for PSWebHost.

.DESCRIPTION
    Manages a background job that updates performance metrics in pswebhost_perf.db.
    The job processes performance data from a thread-safe queue and writes to SQLite.

.PARAMETER StartJob
    Starts the performance monitoring background job.

.PARAMETER ReceiveJob
    Receives output from the background job.

.PARAMETER StopJob
    Stops, receives output, and removes the background job.

.PARAMETER QueueData
    Hashtable containing performance data to queue for processing.

.EXAMPLE
    .\SQLITE_Perf_Table_Updater.ps1 -StartJob

.EXAMPLE
    .\SQLITE_Perf_Table_Updater.ps1 -QueueData @{ Type='WebRequest'; Data=@{...} }

.EXAMPLE
    .\SQLITE_Perf_Table_Updater.ps1 -StopJob
#>

param (
    [switch]$StartJob,
    [switch]$ReceiveJob,
    [switch]$StopJob,
    [hashtable]$QueueData
)

$ProjectRoot = $Global:PSWebServer.Project_Root.Path
$perfDbPath = Join-Path $ProjectRoot "PsWebHost_Data\pswebhost_perf.db"
$schemaPath = Join-Path $ProjectRoot "system\db\sqlite\pswebhost_perf_schema.sql"

# Initialize performance queue if not exists
if (-not $Global:PSWebPerfQueue) {
    $Global:PSWebPerfQueue = [System.Collections.Concurrent.ConcurrentQueue[hashtable]]::new()
}

# Queue data for processing
if ($QueueData) {
    $Global:PSWebPerfQueue.Enqueue($QueueData)
    Write-Verbose "Queued performance data: $($QueueData.Type)"
    return
}

# Start the background job
if ($StartJob) {
    # Check if job already running
    if ($Global:PSWebPerfJob -and $Global:PSWebPerfJob.State -eq 'Running') {
        Write-Warning "Performance job is already running (Job ID: $($Global:PSWebPerfJob.Id))"
        return
    }

    # Ensure database directory exists
    $perfDbDir = Split-Path $perfDbPath -Parent
    if (-not (Test-Path $perfDbDir)) {
        New-Item -Path $perfDbDir -ItemType Directory -Force | Out-Null
    }

    # Ensure init.ps1 is loaded for global variables
    if (-not $Global:PSWebServer) {
        Write-Verbose "Loading init.ps1..."
        . (Join-Path $ProjectRoot 'system/init.ps1') -Loadvariables
    }

    # Validate database schema using validatetables.ps1
    Write-Verbose "Validating performance database schema..."
    $validateTablesScript = Join-Path $ProjectRoot "system\db\sqlite\validatetables.ps1"
    $perfConfigPath = Join-Path $ProjectRoot "system\db\sqlite\sqlite_pswebhost_perf_config.json"

    if (Test-Path $validateTablesScript) {
        if (Test-Path $perfConfigPath) {
            & $validateTablesScript -DatabaseFile $perfDbPath -ConfigFile $perfConfigPath
            Write-Verbose "Performance database schema validated."
        } else {
            Write-Warning "Performance config file not found: $perfConfigPath"
            Write-Warning "Falling back to SQL schema file..."

            # Fallback to old method if config not found
            if (-not (Test-Path $perfDbPath)) {
                [System.IO.File]::Create($perfDbPath).Dispose()
            }
            if (Test-Path $schemaPath) {
                $schemaContent = Get-Content $schemaPath -Raw
                $sqlite3Path = Join-Path $ProjectRoot "system\db\sqlite\sqlite3.exe"
                if (Test-Path $sqlite3Path) {
                    $schemaContent | & $sqlite3Path $perfDbPath
                }
            }
        }
    } else {
        Write-Warning "validatetables.ps1 not found at: $validateTablesScript"
    }

    # Script block for background job
    $jobScript = {
        param($perfDbPath, $perfQueue, $projectRoot)

        $sqlite3Path = Join-Path $projectRoot "system\db\sqlite\sqlite3.exe"

        function Write-PerfData {
            param($DbPath, $Query, $Sqlite3Path)

            try {
                $Query | & $Sqlite3Path $DbPath 2>&1 | Out-Null
                return $true
            }
            catch {
                Write-Error "Failed to write perf data: $($_.Exception.Message)"
                return $false
            }
        }

        Write-Output "Performance monitoring job started at $(Get-Date)"

        $processedCount = 0
        $lastReport = Get-Date

        while ($true) {
            $item = $null
            $hasItem = $perfQueue.TryDequeue([ref]$item)

            if ($hasItem -and $item) {
                try {
                    switch ($item.Type) {
                        'WebRequest' {
                            $data = $item.Data

                            if ($data.Action -eq 'Start') {
                                # Insert new request record
                                $query = @"
INSERT INTO WebRequestPerformance (
    RequestID, StartTime, FilePath, HttpMethod,
    IPAddress, UserAgent, SessionID, LogFileSizeBefore
) VALUES (
    '$($data.RequestID)',
    '$($data.StartTime)',
    '$($data.FilePath -replace "'", "''")',
    '$($data.HttpMethod)',
    '$($data.IPAddress -replace "'", "''")',
    '$($data.UserAgent -replace "'", "''")',
    '$($data.SessionID)',
    $($data.LogFileSizeBefore)
);
"@
                                Write-PerfData -DbPath $perfDbPath -Query $query -Sqlite3Path $sqlite3Path
                            }
                            elseif ($data.Action -eq 'Complete') {
                                # Update request record
                                $execTimeMicroseconds = $data.ExecutionTimeMicroseconds
                                $logDelta = $data.LogFileSizeAfter - $data.LogFileSizeBefore

                                $statusCodeValue = if ($data.StatusCode) { $data.StatusCode } else { 'NULL' }
                                $statusTextValue = if ($data.StatusText) { "'$($data.StatusText -replace "'", "''")'" } else { 'NULL' }

                                $query = @"
UPDATE WebRequestPerformance SET
    EndTime = '$($data.EndTime)',
    UserID = '$($data.UserID -replace "'", "''")',
    AuthenticationProvider = '$($data.AuthenticationProvider -replace "'", "''")',
    ExecutionTimeMicroseconds = $execTimeMicroseconds,
    LogFileSizeBefore = $($data.LogFileSizeBefore),
    LogFileSizeAfter = $($data.LogFileSizeAfter),
    LogFileSizeDelta = $logDelta,
    StatusCode = $statusCodeValue,
    StatusText = $statusTextValue,
    Completed = 1
WHERE RequestID = '$($data.RequestID)';
"@
                                Write-PerfData -DbPath $perfDbPath -Query $query -Sqlite3Path $sqlite3Path
                            }
                        }

                        'SystemMetrics' {
                            $data = $item.Data
                            $query = @"
INSERT INTO SystemPerformance (
    Timestamp, CPUPercent, MemoryUsedGB, MemoryPercentUsed,
    ProcessCount, ThreadCount, HandleCount
) VALUES (
    '$($data.Timestamp)',
    $($data.CPUPercent),
    $($data.MemoryUsedGB),
    $($data.MemoryPercentUsed),
    $($data.ProcessCount),
    $($data.ThreadCount),
    $($data.HandleCount)
);
"@
                            Write-PerfData -DbPath $perfDbPath -Query $query -Sqlite3Path $sqlite3Path
                        }
                    }

                    $processedCount++
                }
                catch {
                    Write-Error "Error processing perf item: $($_.Exception.Message)"
                }
            }
            else {
                # No items in queue, sleep
                Start-Sleep -Milliseconds 100
            }

            # Report stats every 5 minutes
            if (((Get-Date) - $lastReport).TotalMinutes -ge 5) {
                Write-Output "Performance job stats: Processed $processedCount records. Queue size: $($perfQueue.Count)"
                $lastReport = Get-Date
            }
        }
    }

    # Start the job
    $Global:PSWebPerfJob = Start-Job -ScriptBlock $jobScript -ArgumentList $perfDbPath, $Global:PSWebPerfQueue, $ProjectRoot
    Write-Host "Performance monitoring job started (Job ID: $($Global:PSWebPerfJob.Id))"
    return $Global:PSWebPerfJob
}

# Receive job output
if ($ReceiveJob) {
    if (-not $Global:PSWebPerfJob) {
        Write-Warning "No performance job is running"
        return
    }

    $output = Receive-Job -Job $Global:PSWebPerfJob
    if ($output) {
        Write-Output $output
    }
    return
}

# Stop the job
if ($StopJob) {
    if (-not $Global:PSWebPerfJob) {
        Write-Warning "No performance job to stop"
        return
    }

    Write-Host "Stopping performance job (ID: $($Global:PSWebPerfJob.Id))..."

    # Receive any pending output
    $output = Receive-Job -Job $Global:PSWebPerfJob
    if ($output) {
        Write-Output "Job output:"
        Write-Output $output
    }

    # Stop and remove job
    Stop-Job -Job $Global:PSWebPerfJob -ErrorAction SilentlyContinue
    Remove-Job -Job $Global:PSWebPerfJob -Force -ErrorAction SilentlyContinue

    Write-Host "Performance job stopped. Queue had $($Global:PSWebPerfQueue.Count) pending items."

    $Global:PSWebPerfJob = $null
    return
}

# If no parameters provided, show status
if (-not $StartJob -and -not $ReceiveJob -and -not $StopJob -and -not $QueueData) {
    $status = @{
        JobRunning = ($Global:PSWebPerfJob -and $Global:PSWebPerfJob.State -eq 'Running')
        JobState = if ($Global:PSWebPerfJob) { $Global:PSWebPerfJob.State } else { 'Not Started' }
        QueueSize = $Global:PSWebPerfQueue.Count
        DatabasePath = $perfDbPath
        DatabaseExists = (Test-Path $perfDbPath)
    }

    Write-Output "Performance Job Status:"
    $status | Format-List
}
