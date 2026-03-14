# Diagnose Runspace Pool Deadlock
# Run this from the server console to understand why all runspaces are stuck

Write-Host "`n=== Runspace Pool Diagnostic ===" -ForegroundColor Cyan
Write-Host "This script analyzes the AsyncRunspacePool to identify deadlocks`n" -ForegroundColor Gray

# 1. Check pool initialization
Write-Host "1. Pool Initialization Status:" -ForegroundColor Yellow
Write-Host "   Initialized: $($AsyncRunspacePool.Initialized)"
Write-Host "   StopRequested: $($AsyncRunspacePool.StopRequested)"
Write-Host "   PoolSize: $($AsyncRunspacePool.PoolSize)"
Write-Host "   Listener: $($AsyncRunspacePool.ListenerInstance -ne $null)"
Write-Host "   Total Workers: $($AsyncRunspacePool.Workers.Count)"

# 2. Check worker states
Write-Host "`n2. Worker States:" -ForegroundColor Yellow
$workerStates = $AsyncRunspacePool.Workers.Values | ForEach-Object {
    $worker = $_
    $rsInfo = $worker.RunspaceInfo
    $stats = $AsyncRunspacePool.Stats[$rsInfo.Index]

    [PSCustomObject]@{
        Index = $rsInfo.Index
        RunspaceId = $rsInfo.Runspace.InstanceId
        RunspaceState = $rsInfo.Runspace.RunspaceStateInfo.State
        Availability = $rsInfo.Runspace.RunspaceAvailability
        PowerShellState = $worker.PowerShell.InvocationStateInfo.State
        IsCompleted = $worker.AsyncHandle.IsCompleted
        WorkerState = $stats.State
        RequestCount = $stats.RequestCount
        Errors = $stats.Errors
        LastRequest = $stats.LastRequest
    }
}

$workerStates | Format-Table -AutoSize

# 3. Count states
Write-Host "`n3. State Summary:" -ForegroundColor Yellow
$grouped = $workerStates | Group-Object -Property WorkerState
$grouped | ForEach-Object {
    Write-Host "   $($_.Name): $($_.Count) workers"
}

$availGrouped = $workerStates | Group-Object -Property Availability
$availGrouped | ForEach-Object {
    Write-Host "   Availability=$($_.Name): $($_.Count) workers"
}

# 4. Check if workers are actually running
Write-Host "`n4. Worker Execution State:" -ForegroundColor Yellow
$runningCount = ($workerStates | Where-Object { -not $_.IsCompleted }).Count
$completedCount = ($workerStates | Where-Object { $_.IsCompleted }).Count
Write-Host "   Running (not completed): $runningCount"
Write-Host "   Completed: $completedCount"

if ($runningCount -gt 0) {
    Write-Host "   ✓ Workers are running their loops" -ForegroundColor Green
} else {
    Write-Host "   ✗ All workers have stopped!" -ForegroundColor Red
}

# 5. Check listener state
Write-Host "`n5. Listener State:" -ForegroundColor Yellow
$listener = $AsyncRunspacePool.ListenerInstance
if ($listener) {
    Write-Host "   IsListening: $($listener.IsListening)"
    Write-Host "   Prefixes: $($listener.Prefixes -join ', ')"
    Write-Host "   Type: $($listener.GetType().FullName)"
} else {
    Write-Host "   ✗ Listener is NULL!" -ForegroundColor Red
}

# 6. Test if we can inspect a runspace's variables
Write-Host "`n6. Inspecting First Runspace Variables:" -ForegroundColor Yellow
$firstWorker = $AsyncRunspacePool.Workers.Values | Select-Object -First 1
if ($firstWorker) {
    try {
        $ps = [powershell]::Create()
        $ps.Runspace = $firstWorker.RunspaceInfo.Runspace

        $script = {
            [PSCustomObject]@{
                HasAsyncRunspacePool = $null -ne $global:AsyncRunspacePool
                HasListener = $null -ne $global:AsyncRunspacePool.ListenerInstance
                StopRequested = $global:AsyncRunspacePool.StopRequested
                HasPSWebServer = $null -ne $global:PSWebServer
                RunspaceId = $Host.Runspace.InstanceId
            }
        }

        $result = $ps.AddScript($script).Invoke()
        $result | Format-List
        $ps.Dispose()
    } catch {
        Write-Host "   ✗ Error inspecting runspace: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "   ✗ No workers available" -ForegroundColor Red
}

# 7. Check recent log entries
Write-Host "`n7. Recent Log Entries (last 20 with 'AsyncWorker'):" -ForegroundColor Yellow
if ($PSWebHostLogQueue) {
    $logEntries = @()
    $tempQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

    # Drain queue to array
    while ($PSWebHostLogQueue.TryDequeue([ref]$null)) {
        $entry = $null
        if ($PSWebHostLogQueue.TryDequeue([ref]$entry)) {
            $logEntries += $entry
            $tempQueue.Enqueue($entry)
        }
    }

    # Restore queue
    foreach ($entry in $logEntries) {
        $PSWebHostLogQueue.Enqueue($entry)
    }

    # Show async worker entries
    $asyncEntries = $logEntries | Where-Object { $_ -match 'AsyncWorker' } | Select-Object -Last 20
    if ($asyncEntries) {
        $asyncEntries | ForEach-Object {
            $fields = $_ -split "`t"
            if ($fields.Count -ge 5) {
                $timestamp = $fields[1]
                $severity = $fields[2]
                $message = $fields[4]
                $color = switch ($severity) {
                    'Error' { 'Red' }
                    'Warning' { 'Yellow' }
                    'Info' { 'Cyan' }
                    default { 'Gray' }
                }
                Write-Host "   [$timestamp] $message" -ForegroundColor $color
            }
        }
    } else {
        Write-Host "   (No AsyncWorker log entries found)" -ForegroundColor Gray
    }
} else {
    Write-Host "   ✗ PSWebHostLogQueue not available" -ForegroundColor Red
}

# 8. Recommendations
Write-Host "`n8. Analysis:" -ForegroundColor Yellow

$allBusy = ($workerStates | Where-Object { $_.Availability -eq 'Busy' }).Count -eq $workerStates.Count
$allWaiting = ($workerStates | Where-Object { $_.WorkerState -eq 'Waiting' }).Count -eq $workerStates.Count
$noneCompleted = ($workerStates | Where-Object { -not $_.IsCompleted }).Count -eq $workerStates.Count

if ($allBusy -and $allWaiting -and $noneCompleted) {
    Write-Host "   ⚠️  DEADLOCK DETECTED:" -ForegroundColor Red
    Write-Host "   - All runspaces show Availability=Busy (expected for running loops)" -ForegroundColor Gray
    Write-Host "   - All workers show State=Waiting (waiting for GetContextAsync)" -ForegroundColor Gray
    Write-Host "   - None have completed (workers still running)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "   PROBLEM: All 15 workers are calling GetContextAsync() simultaneously!" -ForegroundColor Yellow
    Write-Host "   HttpListener is not designed for multiple concurrent GetContextAsync() calls." -ForegroundColor Yellow
    Write-Host "   This causes them to compete for contexts, creating a race condition." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "   SOLUTION: Implement a coordinator pattern:" -ForegroundColor Cyan
    Write-Host "   1. ONE thread calls GetContextAsync() in a loop" -ForegroundColor Cyan
    Write-Host "   2. When context arrives, enqueue it" -ForegroundColor Cyan
    Write-Host "   3. Worker runspaces dequeue and process" -ForegroundColor Cyan
    Write-Host "   4. This prevents multiple simultaneous listener calls" -ForegroundColor Cyan
} elseif ($completedCount -gt 0) {
    Write-Host "   ⚠️  WORKERS ARE STOPPING:" -ForegroundColor Yellow
    Write-Host "   $completedCount workers have completed their loops" -ForegroundColor Gray
    Write-Host "   Check if they hit max requests or encountered errors" -ForegroundColor Gray
} else {
    Write-Host "   ℹ️  Workers appear to be running normally" -ForegroundColor Green
    Write-Host "   Check logs to see if contexts are being acquired" -ForegroundColor Gray
}

Write-Host "`n=== End Diagnostic ===`n" -ForegroundColor Cyan

# 9. Provide testing command
Write-Host "To test if contexts can be acquired, try making a request:" -ForegroundColor Yellow
Write-Host "  Invoke-WebRequest http://localhost:$($PSWebServer.Port)/ -TimeoutSec 5" -ForegroundColor Cyan
Write-Host ""
Write-Host "Then run this again to see if any worker progressed." -ForegroundColor Yellow
