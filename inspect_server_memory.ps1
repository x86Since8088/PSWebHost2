# Run this script from within the PSWebHost server console
# This will inspect memory usage of key data structures

Write-Host "`n=== PSWebHost Memory Inspection ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "Process: PID $PID`n" -ForegroundColor Gray

# Function to estimate object size
function Get-ObjectSizeEstimate {
    param($Object, $Name)

    $estimate = @{
        Name = $Name
        Type = $null
        Count = 0
        EstimatedMB = 0
        Details = ""
    }

    if ($null -eq $Object) {
        $estimate.Type = "null"
        return $estimate
    }

    $estimate.Type = $Object.GetType().Name

    try {
        if ($Object -is [string]) {
            $estimate.Count = $Object.Length
            $estimate.EstimatedMB = [math]::Round($Object.Length / 1MB, 2)
        }
        elseif ($Object -is [System.Collections.ICollection]) {
            $estimate.Count = $Object.Count

            # For hashtables/dictionaries, estimate based on keys and sample values
            if ($Object -is [hashtable] -or $Object -is [System.Collections.IDictionary]) {
                $sampleSize = [math]::Min(10, $Object.Count)
                $avgKeySize = 0
                $avgValueSize = 0

                $keys = @($Object.Keys)
                for ($i = 0; $i -lt $sampleSize; $i++) {
                    $key = $keys[$i]
                    if ($key -is [string]) {
                        $avgKeySize += $key.Length
                    } else {
                        $avgKeySize += 50  # Estimate for non-string keys
                    }

                    $value = $Object[$key]
                    if ($value -is [string]) {
                        $avgValueSize += $value.Length
                    } elseif ($value -is [hashtable] -or $value -is [System.Collections.IDictionary]) {
                        $avgValueSize += 500  # Estimate for nested objects
                    } else {
                        $avgValueSize += 100  # Estimate for objects
                    }
                }

                if ($sampleSize -gt 0) {
                    $avgKeySize = $avgKeySize / $sampleSize
                    $avgValueSize = $avgValueSize / $sampleSize
                    $estimate.EstimatedMB = [math]::Round((($avgKeySize + $avgValueSize) * $Object.Count) / 1MB, 2)
                    $estimate.Details = "Avg Key: $([math]::Round($avgKeySize)) bytes, Avg Value: $([math]::Round($avgValueSize)) bytes"
                }
            }
            else {
                # For arrays/lists, estimate based on sample
                $sampleSize = [math]::Min(10, $Object.Count)
                $avgItemSize = 0

                for ($i = 0; $i -lt $sampleSize; $i++) {
                    $item = $Object[$i]
                    if ($item -is [string]) {
                        $avgItemSize += $item.Length
                    } else {
                        $avgItemSize += 100  # Estimate
                    }
                }

                if ($sampleSize -gt 0) {
                    $avgItemSize = $avgItemSize / $sampleSize
                    $estimate.EstimatedMB = [math]::Round(($avgItemSize * $Object.Count) / 1MB, 2)
                    $estimate.Details = "Avg Item: $([math]::Round($avgItemSize)) bytes"
                }
            }
        }
        else {
            $estimate.Count = 1
            $estimate.EstimatedMB = 0.001  # Minimal
        }
    }
    catch {
        $estimate.Details = "Error estimating: $($_.Exception.Message)"
    }

    return $estimate
}

# Inspect key data structures
$inspections = @()

# 1. Events collection
Write-Host "Inspecting PSWebServer.events..." -ForegroundColor Yellow
if ($global:PSWebServer.events) {
    $eventsInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.events -Name "PSWebServer.events"
    $inspections += $eventsInfo
    Write-Host "  Count: $($eventsInfo.Count) | Estimated: $($eventsInfo.EstimatedMB) MB" -ForegroundColor $(if ($eventsInfo.EstimatedMB -gt 100) { 'Red' } else { 'Gray' })
    Write-Host "  $($eventsInfo.Details)" -ForegroundColor Gray
}

# 2. Log queue
Write-Host "Inspecting PSWebHostLogQueue..." -ForegroundColor Yellow
if ($global:PSWebHostLogQueue) {
    $logInfo = Get-ObjectSizeEstimate -Object $global:PSWebHostLogQueue -Name "PSWebHostLogQueue"
    $inspections += $logInfo
    Write-Host "  Count: $($logInfo.Count) | Estimated: $($logInfo.EstimatedMB) MB" -ForegroundColor $(if ($logInfo.EstimatedMB -gt 50) { 'Red' } else { 'Gray' })
}

# 3. Sessions
Write-Host "Inspecting PSWebSessions..." -ForegroundColor Yellow
if ($global:PSWebSessions) {
    $sessionsInfo = Get-ObjectSizeEstimate -Object $global:PSWebSessions -Name "PSWebSessions"
    $inspections += $sessionsInfo
    Write-Host "  Count: $($sessionsInfo.Count) | Estimated: $($sessionsInfo.EstimatedMB) MB" -ForegroundColor $(if ($sessionsInfo.EstimatedMB -gt 50) { 'Red' } else { 'Gray' })

    # Show oldest sessions
    if ($sessionsInfo.Count -gt 0) {
        $oldSessions = $global:PSWebSessions.GetEnumerator() |
            Where-Object { $_.Value.LastUpdated } |
            Sort-Object { $_.Value.LastUpdated } |
            Select-Object -First 5

        if ($oldSessions) {
            Write-Host "  Oldest sessions:" -ForegroundColor Gray
            foreach ($session in $oldSessions) {
                $age = (Get-Date) - $session.Value.LastUpdated
                Write-Host "    - $($session.Key): Last activity $([math]::Round($age.TotalHours, 1)) hours ago" -ForegroundColor Gray
            }
        }
    }
}

# 4. Metrics
Write-Host "Inspecting Metrics..." -ForegroundColor Yellow
if ($global:PSWebServer.Metrics) {
    if ($global:PSWebServer.Metrics.History) {
        $metricsInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Metrics.History -Name "Metrics.History"
        $inspections += $metricsInfo
        Write-Host "  History Count: $($metricsInfo.Count) | Estimated: $($metricsInfo.EstimatedMB) MB" -ForegroundColor $(if ($metricsInfo.EstimatedMB -gt 50) { 'Red' } else { 'Gray' })
    }

    if ($global:PSWebServer.Metrics.DataPoints) {
        $dataPointsInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Metrics.DataPoints -Name "Metrics.DataPoints"
        $inspections += $dataPointsInfo
        Write-Host "  DataPoints Count: $($dataPointsInfo.Count) | Estimated: $($dataPointsInfo.EstimatedMB) MB" -ForegroundColor $(if ($dataPointsInfo.EstimatedMB -gt 50) { 'Red' } else { 'Gray' })
    }
}

# 5. Runspaces
Write-Host "Inspecting Runspaces..." -ForegroundColor Yellow
if ($global:PSWebServer.Runspaces) {
    $runspacesInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Runspaces -Name "PSWebServer.Runspaces"
    $inspections += $runspacesInfo
    Write-Host "  Count: $($runspacesInfo.Count) | Estimated: $($runspacesInfo.EstimatedMB) MB" -ForegroundColor Gray
}

# 6. Track collections
Write-Host "Inspecting Track collections..." -ForegroundColor Yellow
if ($global:PSWebServer.Track_HashTables) {
    $trackHTInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Track_HashTables -Name "Track_HashTables"
    Write-Host "  Track_HashTables Count: $($trackHTInfo.Count)" -ForegroundColor Gray
}
if ($global:PSWebServer.Track_Arrays) {
    $trackArrInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Track_Arrays -Name "Track_Arrays"
    Write-Host "  Track_Arrays Count: $($trackArrInfo.Count)" -ForegroundColor Gray
}

# 7. Jobs
Write-Host "Inspecting Jobs..." -ForegroundColor Yellow
if ($global:PSWebServer.Jobs) {
    $jobsInfo = Get-ObjectSizeEstimate -Object $global:PSWebServer.Jobs -Name "PSWebServer.Jobs"
    $inspections += $jobsInfo
    Write-Host "  Count: $($jobsInfo.Count) | Estimated: $($jobsInfo.EstimatedMB) MB" -ForegroundColor Gray
}

# Summary
Write-Host "`n=== Summary (Largest Collections) ===" -ForegroundColor Cyan
$inspections |
    Sort-Object EstimatedMB -Descending |
    Select-Object -First 10 |
    Format-Table Name, Count, EstimatedMB, Type -AutoSize

$totalEstimated = ($inspections | Measure-Object -Property EstimatedMB -Sum).Sum
Write-Host "Total Estimated: $([math]::Round($totalEstimated, 2)) MB" -ForegroundColor Yellow

# Recommendations
Write-Host "`n=== Cleanup Recommendations ===" -ForegroundColor Cyan
$hasLeak = $false

if ($global:PSWebServer.events -and $global:PSWebServer.events.Count -gt 10000) {
    Write-Host "[CRITICAL] PSWebServer.events has $($global:PSWebServer.events.Count) entries!" -ForegroundColor Red
    Write-Host "  Recommended action: Clear old events" -ForegroundColor Yellow
    Write-Host '  Command: $global:PSWebServer.events.Clear()' -ForegroundColor White
    $hasLeak = $true
}

if ($global:PSWebHostLogQueue -and $global:PSWebHostLogQueue.Count -gt 5000) {
    Write-Host "[WARNING] PSWebHostLogQueue has $($global:PSWebHostLogQueue.Count) entries" -ForegroundColor Red
    Write-Host "  This indicates logs are not being flushed to disk" -ForegroundColor Yellow
    $hasLeak = $true
}

if ($global:PSWebSessions -and $global:PSWebSessions.Count -gt 100) {
    Write-Host "[WARNING] PSWebSessions has $($global:PSWebSessions.Count) sessions" -ForegroundColor Yellow
    Write-Host "  Check for stale sessions that should be cleaned up" -ForegroundColor Yellow
}

if (-not $hasLeak) {
    Write-Host "No obvious memory leaks detected in monitored collections." -ForegroundColor Green
    Write-Host "Memory usage may be in untracked variables or .NET objects." -ForegroundColor Gray
}

Write-Host "`nInspection complete.`n" -ForegroundColor Cyan
