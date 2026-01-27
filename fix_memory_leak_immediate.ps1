# Immediate Memory Leak Fix
# Run this in the PSWebHost server console to free memory

Write-Host "`n=== PSWebHost Memory Leak Fix ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Gray

# 1. Check current memory usage
$beforeMem = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
Write-Host "Memory Before: $beforeMem MB" -ForegroundColor Yellow

# 2. Check sizes before cleanup
if ($global:PSWebServer.eventGuid) {
    $eventGuidCount = $global:PSWebServer.eventGuid.Count
    Write-Host "`nEventGuid hashtable: $eventGuidCount entries" -ForegroundColor Red
} else {
    $eventGuidCount = 0
}

if ($global:PSWebServer.events) {
    $eventsCount = $global:PSWebServer.events.Count
    Write-Host "Events hashtable: $eventsCount entries" -ForegroundColor $(if ($eventsCount -gt 1000) { 'Red' } else { 'Yellow' })
} else {
    $eventsCount = 0
}

if ($global:PSWebHostLogQueue) {
    $logQueueCount = $global:PSWebHostLogQueue.Count
    Write-Host "Log Queue: $logQueueCount entries" -ForegroundColor $(if ($logQueueCount -gt 5000) { 'Red' } else { 'Yellow' })
} else {
    $logQueueCount = 0
}

# 3. Clear the leaking eventGuid hashtable
if ($global:PSWebServer.eventGuid -and $global:PSWebServer.eventGuid.Count -gt 0) {
    Write-Host "`nClearing eventGuid hashtable ($eventGuidCount entries)..." -ForegroundColor Yellow
    $global:PSWebServer.eventGuid.Clear()
    Write-Host "  Done!" -ForegroundColor Green
}

# 4. Trim events hashtable to 500 entries (smaller than the 1000 limit)
if ($global:PSWebServer.events -and $global:PSWebServer.events.Count -gt 500) {
    Write-Host "Trimming events hashtable to 500 entries..." -ForegroundColor Yellow
    $entriesToRemove = $global:PSWebServer.events.Count - 500
    $global:PSWebServer.events.Keys |
        Select-Object -First $entriesToRemove |
        ForEach-Object { $global:PSWebServer.events.Remove($_) }
    Write-Host "  Removed $entriesToRemove entries" -ForegroundColor Green
}

# 5. Clean up old sessions (older than 24 hours)
if ($global:PSWebSessions) {
    Write-Host "Checking for stale sessions..." -ForegroundColor Yellow
    $cutoffTime = (Get-Date).AddHours(-24)
    $staleSessions = @()

    foreach ($sessionId in @($global:PSWebSessions.Keys)) {
        $session = $global:PSWebSessions[$sessionId]
        if ($session.LastUpdated -lt $cutoffTime) {
            $staleSessions += $sessionId
        }
    }

    if ($staleSessions.Count -gt 0) {
        Write-Host "  Removing $($staleSessions.Count) stale sessions..." -ForegroundColor Yellow
        foreach ($sessionId in $staleSessions) {
            $global:PSWebSessions.Remove($sessionId)
        }
        Write-Host "  Done!" -ForegroundColor Green
    } else {
        Write-Host "  No stale sessions found" -ForegroundColor Gray
    }
}

# 6. Force garbage collection
Write-Host "`nForcing garbage collection..." -ForegroundColor Yellow
[GC]::Collect()
[GC]::WaitForPendingFinalizers()
[GC]::Collect()
Write-Host "  Done!" -ForegroundColor Green

Start-Sleep -Seconds 2

# 7. Check memory after
$afterMem = [math]::Round((Get-Process -Id $PID).WorkingSet64 / 1MB, 2)
$freedMem = [math]::Round($beforeMem - $afterMem, 2)

Write-Host "`n=== Results ===" -ForegroundColor Cyan
Write-Host "Memory Before: $beforeMem MB" -ForegroundColor Yellow
Write-Host "Memory After:  $afterMem MB" -ForegroundColor Green
Write-Host "Memory Freed:  $freedMem MB" -ForegroundColor $(if ($freedMem -gt 0) { 'Green' } else { 'Yellow' })

Write-Host "`nCleanup Statistics:" -ForegroundColor Cyan
Write-Host "  EventGuid entries cleared: $eventGuidCount" -ForegroundColor Gray
Write-Host "  Events hashtable size now: $($global:PSWebServer.events.Count)" -ForegroundColor Gray
Write-Host "  Sessions count: $($global:PSWebSessions.Count)" -ForegroundColor Gray

Write-Host "`nNote: Freed memory may not show immediately due to .NET garbage collection." -ForegroundColor Gray
Write-Host "Run again in 30 seconds to see updated memory usage.`n" -ForegroundColor Gray
