# Inspect Runspace State - Verify variables and execution state
# Run this to prove each runspace has proper setup

param(
    [int]$RunspaceIndex = 1
)

Write-Host "`n=== Inspecting Runspace $RunspaceIndex ===" -ForegroundColor Cyan

$worker = $AsyncRunspacePool.Workers[$RunspaceIndex]

if (-not $worker) {
    Write-Host "Worker $RunspaceIndex not found!" -ForegroundColor Red
    Write-Host "Available workers: $($AsyncRunspacePool.Workers.Keys -join ', ')" -ForegroundColor Yellow
    exit 1
}

$rsInfo = $worker.RunspaceInfo
$rs = $rsInfo.Runspace

Write-Host "`n1. Runspace Metadata:" -ForegroundColor Yellow
Write-Host "   Index: $($rsInfo.Index)"
Write-Host "   InstanceId: $($rs.InstanceId)"
Write-Host "   State: $($rs.RunspaceStateInfo.State)"
Write-Host "   Availability: $($rs.RunspaceAvailability)"
Write-Host "   ThreadOptions: $($rs.ThreadOptions)"
Write-Host "   CreatedAt: $($rsInfo.CreatedAt)"
Write-Host "   RequestCount: $($rsInfo.RequestCount)"

Write-Host "`n2. Worker Info:" -ForegroundColor Yellow
Write-Host "   PowerShell State: $($worker.PowerShell.InvocationStateInfo.State)"
Write-Host "   Reason: $($worker.PowerShell.InvocationStateInfo.Reason)"
Write-Host "   AsyncHandle IsCompleted: $($worker.AsyncHandle.IsCompleted)"
Write-Host "   AsyncHandle CompletedSynchronously: $($worker.AsyncHandle.CompletedSynchronously)"
Write-Host "   StartedAt: $($worker.StartedAt)"
Write-Host "   Running Duration: $((Get-Date) - $worker.StartedAt)"

Write-Host "`n3. Worker Stats:" -ForegroundColor Yellow
$stats = $AsyncRunspacePool.Stats[$RunspaceIndex]
if ($stats) {
    Write-Host "   State: $($stats.State)"
    Write-Host "   RequestCount: $($stats.RequestCount)"
    Write-Host "   Errors: $($stats.Errors)"
    Write-Host "   LastRequest: $($stats.LastRequest)"
}

Write-Host "`n4. Executing Commands in Runspace to Check Variables:" -ForegroundColor Yellow

try {
    $testPs = [powershell]::Create()
    $testPs.Runspace = $rs

    # Test 1: Check global variables existence
    Write-Host "   Testing global variable existence..." -ForegroundColor Gray
    $checkVarsScript = {
        [PSCustomObject]@{
            AsyncRunspacePool = $null -ne $global:AsyncRunspacePool
            PSWebServer = $null -ne $global:PSWebServer
            PSWebSessions = $null -ne $global:PSWebSessions
            PSWebHostLogQueue = $null -ne $global:PSWebHostLogQueue
            PSHostUIQueue = $null -ne $global:PSHostUIQueue
            PSWebPerfQueue = $null -ne $global:PSWebPerfQueue
        }
    }
    $result1 = $testPs.AddScript($checkVarsScript).Invoke()
    $result1 | Format-List
    $testPs.Commands.Clear()

    # Test 2: Check listener instance
    Write-Host "   Checking listener instance..." -ForegroundColor Gray
    $checkListenerScript = {
        $listener = $global:AsyncRunspacePool.ListenerInstance
        [PSCustomObject]@{
            HasListener = $null -ne $listener
            ListenerType = if ($listener) { $listener.GetType().FullName } else { 'NULL' }
            IsListening = if ($listener) { $listener.IsListening } else { $false }
            Prefixes = if ($listener) { $listener.Prefixes -join ', ' } else { 'N/A' }
        }
    }
    $result2 = $testPs.AddScript($checkListenerScript).Invoke()
    $result2 | Format-List
    $testPs.Commands.Clear()

    # Test 3: Check if functions are available
    Write-Host "   Checking available functions..." -ForegroundColor Gray
    $checkFunctionsScript = {
        $functions = @(
            'Process-HttpRequest',
            'Set-WebHostRunSpaceInfo',
            'Get-SystemMetricsSnapshot'
        )
        $results = foreach ($func in $functions) {
            [PSCustomObject]@{
                Function = $func
                Exists = $null -ne (Get-Command $func -ErrorAction SilentlyContinue)
            }
        }
        $results
    }
    $result3 = $testPs.AddScript($checkFunctionsScript).Invoke()
    $result3 | Format-Table -AutoSize
    $testPs.Commands.Clear()

    # Test 4: Check PSWebServer structure
    Write-Host "   Checking PSWebServer structure..." -ForegroundColor Gray
    $checkPSWebServerScript = {
        [PSCustomObject]@{
            HasProjectRoot = $null -ne $global:PSWebServer.Project_Root
            ProjectRootPath = $global:PSWebServer.Project_Root.Path
            HasMetrics = $null -ne $global:PSWebServer.Metrics
            HasRunspaces = $null -ne $global:PSWebServer.Runspaces
            HasListener = $null -ne $global:PSWebServer.Listener
            Port = $global:PSWebServer.Port
        }
    }
    $result4 = $testPs.AddScript($checkPSWebServerScript).Invoke()
    $result4 | Format-List
    $testPs.Commands.Clear()

    # Test 5: Check AsyncRunspacePool state within runspace
    Write-Host "   Checking AsyncRunspacePool state..." -ForegroundColor Gray
    $checkPoolScript = {
        [PSCustomObject]@{
            StopRequested = $global:AsyncRunspacePool.StopRequested
            Initialized = $global:AsyncRunspacePool.Initialized
            PoolSize = $global:AsyncRunspacePool.PoolSize
            WorkerCount = $global:AsyncRunspacePool.Workers.Count
            RunspaceCount = $global:AsyncRunspacePool.Runspaces.Count
        }
    }
    $result5 = $testPs.AddScript($checkPoolScript).Invoke()
    $result5 | Format-List

    $testPs.Dispose()

    Write-Host "`n5. PowerShell Streams:" -ForegroundColor Yellow
    Write-Host "   Verbose messages: $($worker.PowerShell.Streams.Verbose.Count)"
    Write-Host "   Warning messages: $($worker.PowerShell.Streams.Warning.Count)"
    Write-Host "   Error messages: $($worker.PowerShell.Streams.Error.Count)"
    Write-Host "   Information messages: $($worker.PowerShell.Streams.Information.Count)"

    if ($worker.PowerShell.Streams.Error.Count -gt 0) {
        Write-Host "`n   Recent Errors:" -ForegroundColor Red
        $worker.PowerShell.Streams.Error | Select-Object -Last 5 | ForEach-Object {
            Write-Host "     - $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    if ($worker.PowerShell.Streams.Warning.Count -gt 0) {
        Write-Host "`n   Recent Warnings:" -ForegroundColor Yellow
        $worker.PowerShell.Streams.Warning | Select-Object -Last 5 | ForEach-Object {
            Write-Host "     - $($_.Message)" -ForegroundColor Yellow
        }
    }

} catch {
    Write-Host "   ✗ Error executing commands in runspace: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "   Stack: $($_.ScriptStackTrace)" -ForegroundColor DarkGray
}

Write-Host "`n6. Runspace Debugging:" -ForegroundColor Yellow
Write-Host "   To see the actual worker scriptblock, inspect:"
Write-Host "   `$AsyncRunspacePool.Workers[$RunspaceIndex].PowerShell.Commands" -ForegroundColor Cyan
Write-Host ""
Write-Host "   To see what the runspace is currently executing:"
Write-Host "   `$AsyncRunspacePool.Workers[$RunspaceIndex].PowerShell.InvocationStateInfo" -ForegroundColor Cyan

Write-Host "`n=== End Inspection ===`n" -ForegroundColor Cyan

# Summary
Write-Host "Summary:" -ForegroundColor Yellow
if ($result1[0].AsyncRunspacePool -and $result1[0].PSWebServer -and $result2[0].HasListener) {
    Write-Host "  ✓ Runspace has all required variables" -ForegroundColor Green
    Write-Host "  ✓ Listener is available" -ForegroundColor Green
    if ($result5[0].StopRequested) {
        Write-Host "  ⚠️  StopRequested is TRUE - worker should be exiting" -ForegroundColor Yellow
    } else {
        Write-Host "  ✓ StopRequested is FALSE - worker should be running" -ForegroundColor Green
    }
    Write-Host ""
    Write-Host "  This runspace appears properly configured." -ForegroundColor Cyan
    Write-Host "  If it's stuck, check the diagnostic script for listener issues." -ForegroundColor Cyan
} else {
    Write-Host "  ✗ Runspace is missing required variables!" -ForegroundColor Red
}
