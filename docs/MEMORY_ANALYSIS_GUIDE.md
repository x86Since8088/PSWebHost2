# PowerShell Memory Dump Analysis Guide

**Date**: 2026-01-23

---

## Overview

This guide covers methods for analyzing PowerShell process memory to identify consumption issues.

---

## Option 1: Windows Performance Analyzer (WPA) - Timeline Analysis

**Best For**: Understanding memory growth over time, allocation patterns

**Prerequisites**:
```powershell
# Install Windows Performance Toolkit (part of Windows SDK)
# Download from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/
```

**Capture Process Dump**:
```powershell
# Method 1: Task Manager
# Right-click pwsh.exe process → Create dump file

# Method 2: ProcDump (SysInternals)
procdump -ma <PID> pwsh_dump.dmp

# Method 3: dotnet-dump (for .NET analysis)
dotnet-dump collect -p <PID> -o pwsh_dump.dmp
```

**Analyze with WPA**:
```powershell
# Open dump in WPA
wpa.exe pwsh_dump.dmp

# Focus areas:
# - Memory → VirtualAlloc
# - Memory → HeapAlloc
# - CPU → Stacks
```

---

## Option 2: dotnet-dump + dotnet-sos - .NET Heap Analysis

**Best For**: Analyzing managed .NET objects, finding reference chains

**Install Tools**:
```powershell
# Install dotnet-dump
dotnet tool install -g dotnet-dump

# Install dotnet-sos for SOS debugging commands
dotnet tool install -g dotnet-sos
dotnet sos install
```

**Capture and Analyze**:
```powershell
# 1. Capture dump
dotnet-dump collect -p <PID>

# 2. Analyze dump
dotnet-dump analyze pwsh_dump.dmp

# Key SOS commands:
> dumpheap -stat                    # Show object counts by type
> dumpheap -mt <MethodTable>        # Show instances of specific type
> dumpheap -min 85000               # Show large objects (LOH)
> gcroot <address>                  # Find what's keeping object alive
> eeheap -gc                        # GC heap statistics
> dumpobj <address>                 # Examine specific object
> !FindRoots <address>              # Find GC roots
```

**Example Analysis Session**:
```
# Find largest objects
> dumpheap -stat

Statistics:
      MT    Count    TotalSize Class Name
...
00007ff8a1234567    1234     12345678 System.String
00007ff8a2345678    5678     56789012 System.Collections.Hashtable

# Examine hashtables
> dumpheap -mt 00007ff8a2345678 -min 100000

# Find what's keeping large hashtable alive
> gcroot 00007ff8a3456789
```

---

## Option 3: WinDbg + SOS - Advanced Debugging

**Best For**: Deep debugging, understanding native memory, complex scenarios

**Prerequisites**:
```powershell
# Install WinDbg Preview from Microsoft Store
# Or download from: https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/
```

**Analyze Dump**:
```powershell
# Open dump
windbg.exe -z pwsh_dump.dmp

# Load SOS extension
.loadby sos clr
# Or for .NET Core/5+:
.loadby sos coreclr

# Key commands:
!eeheap -gc                         # GC heap info
!dumpheap -stat                     # Object statistics
!dumpheap -strings                  # All strings
!gcroot <address>                   # Root path
!finalizerqueue                     # Objects waiting for finalization
!gchandles                          # GC handles (potential leaks)
!address -summary                   # Memory regions summary
!heap -s                            # Native heap summary
.dumpcab output.cab                 # Export for sharing
```

**Finding Memory Leaks**:
```
# 1. Look for objects with high instance counts
!dumpheap -stat

# 2. Find specific type instances
!dumpheap -type System.Collections.Hashtable

# 3. Check what's keeping them alive
!gcroot <address>

# 4. Look for event handlers not unregistered
!gchandles
```

---

## Option 4: PerfView - ETW Tracing + Heap Analysis

**Best For**: Allocation profiling, understanding allocation call stacks

**Download**: https://github.com/microsoft/perfview/releases

**Capture Allocations**:
```powershell
# Start collection
PerfView.exe /GCCollectOnly /AcceptEULA /MaxCollectSec:300 collect

# Stop collection (or wait for timeout)
# This creates a .etl file
```

**Analyze**:
```
1. Open .etl file in PerfView
2. GC Heap Alloc Stacks → Select process
3. Sort by "Exc %" to find hot allocation paths
4. Double-click to see call stacks
5. Look for:
   - High allocation rates
   - Unexpected allocations in loops
   - Large object allocations
```

---

## Option 5: PowerShell Memory Profiling (Live Process)

**Best For**: Quick checks without dumps, PowerShell-specific analysis

**Script for Live Analysis**:
```powershell
# Get PowerShell process memory details
$proc = Get-Process -Name pwsh -IncludeUserName | Where-Object { $_.Id -eq $PID }

[PSCustomObject]@{
    ProcessId = $proc.Id
    WorkingSet_MB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
    PrivateMemory_MB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
    VirtualMemory_MB = [math]::Round($proc.VirtualMemorySize64 / 1MB, 2)
    Threads = $proc.Threads.Count
    Handles = $proc.HandleCount
    GC_Gen0 = [GC]::CollectionCount(0)
    GC_Gen1 = [GC]::CollectionCount(1)
    GC_Gen2 = [GC]::CollectionCount(2)
    GC_TotalMemory_MB = [math]::Round([GC]::GetTotalMemory($false) / 1MB, 2)
}

# Enumerate all variables and their sizes
Get-Variable | ForEach-Object {
    try {
        $size = ($_ | ConvertTo-Json -Depth 3 -Compress).Length
        [PSCustomObject]@{
            Name = $_.Name
            Type = $_.Value.GetType().Name
            SizeKB = [math]::Round($size / 1KB, 2)
        }
    }
    catch {
        [PSCustomObject]@{
            Name = $_.Name
            Type = $_.Value.GetType().Name
            SizeKB = "Error"
        }
    }
} | Sort-Object SizeKB -Descending | Select-Object -First 20
```

---

## Option 6: CLR MD (ClrMD) - Programmatic Heap Analysis

**Best For**: Automated analysis, custom tools, CI/CD integration

**Example C# Tool**:
```csharp
using Microsoft.Diagnostics.Runtime;

// Open dump file
using DataTarget dt = DataTarget.LoadDump(@"pwsh_dump.dmp");
using ClrRuntime runtime = dt.ClrVersions[0].CreateRuntime();

// Enumerate heap
var stats = new Dictionary<string, (int count, long size)>();

foreach (ClrObject obj in runtime.Heap.EnumerateObjects())
{
    var typeName = obj.Type?.Name ?? "Unknown";
    if (!stats.ContainsKey(typeName))
        stats[typeName] = (0, 0);

    stats[typeName] = (
        stats[typeName].count + 1,
        stats[typeName].size + obj.Size
    );
}

// Top 20 by size
foreach (var (type, (count, size)) in stats.OrderByDescending(x => x.Value.size).Take(20))
{
    Console.WriteLine($"{type}: {count} objects, {size / 1024.0 / 1024.0:F2} MB");
}
```

---

## Recommended Workflow for Your PSWebHost Server

### Step 1: Capture Baseline Metrics

```powershell
# Create monitoring script
.\system\utility\Monitor-MemoryBaseline.ps1

# Run periodically
while ($true) {
    $mem = Get-Process -Id $PID | Select-Object WorkingSet64, PrivateMemorySize64
    $gc = [GC]::GetTotalMemory($false)

    Write-Host "$(Get-Date -Format 'HH:mm:ss') - WS: $([math]::Round($mem.WorkingSet64/1MB, 2)) MB, GC: $([math]::Round($gc/1MB, 2)) MB"

    Start-Sleep -Seconds 60
}
```

### Step 2: Capture Dump When Memory is High

```powershell
# Monitor and auto-capture
$threshold = 1GB
$proc = Get-Process -Id $PID

if ($proc.WorkingSet64 -gt $threshold) {
    $dumpPath = "C:\SC\PsWebHost\dumps\pwsh_high_memory_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"

    # Using dotnet-dump (best for PowerShell)
    dotnet-dump collect -p $PID -o $dumpPath

    Write-Host "Dump captured: $dumpPath" -ForegroundColor Yellow
}
```

### Step 3: Analyze with dotnet-dump (Recommended for PowerShell)

```powershell
# Analyze
dotnet-dump analyze $dumpPath

# In the analyzer:
> dumpheap -stat | Select-String "Hashtable|String|Array|Object\[\]" > hashtables.txt
> eeheap -gc
> finalizequeue
> gchandles
```

### Step 4: Look for Specific Issues

**Common PowerShell Memory Issues**:

1. **Hashtable Leaks**:
```
> dumpheap -type System.Collections.Hashtable -min 100000
> gcroot <address>
```

2. **String Accumulation**:
```
> dumpheap -strings -min 10000
```

3. **Event Handler Leaks**:
```
> gchandles
# Look for EventHandlerList or Delegate counts
```

4. **Runspace Leaks**:
```
> dumpheap -type System.Management.Automation.Runspaces
> gcroot <address>
```

---

## Quick Start: Recommended Approach

For your PSWebHost server, here's the quickest path:

```powershell
# 1. Install dotnet-dump
dotnet tool install -g dotnet-dump

# 2. Get PID of your server
$serverPID = Get-Process -Name pwsh | Where-Object { $_.MainWindowTitle -like "*WebHost*" } | Select-Object -ExpandProperty Id

# 3. Capture dump
dotnet-dump collect -p $serverPID -o "C:\SC\PsWebHost\dumps\server_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"

# 4. Analyze
dotnet-dump analyze "C:\SC\PsWebHost\dumps\server_*.dmp"

# 5. Run these commands in order:
> eeheap -gc                        # Overall heap stats
> dumpheap -stat                    # Top objects
> dumpheap -type Hashtable          # All hashtables
> dumpheap -min 85000               # Large objects
> finalizequeue                     # Pending finalizers
> gchandles                         # GC handles (look for high counts)
```

---

## Interpreting Results

### Red Flags:

1. **High instance counts** (>10,000) of:
   - `System.String`
   - `System.Collections.Hashtable`
   - `System.Object[]`
   - `System.Management.Automation.*`

2. **Large Object Heap (LOH)** growth:
   - Objects >85KB go to LOH
   - LOH is only compacted occasionally
   - Look for: `dumpheap -min 85000`

3. **Finalizer queue backlog**:
   - Objects waiting to be finalized
   - Can prevent GC collection

4. **GC Handle leaks**:
   - High WeakReference counts
   - EventHandlerList not released

### Good Signs:

1. Most objects in Gen0/Gen1 (short-lived)
2. Low finalizer queue
3. Reasonable GC handle counts (<1000)
4. No single object type dominating (>50%)

---

## Automation Script

Here's a complete monitoring and dump capture script:

```powershell
# Monitor-AndCaptureDumps.ps1
param(
    [int]$ThresholdMB = 1024,
    [int]$CheckIntervalSeconds = 60,
    [string]$DumpDirectory = "C:\SC\PsWebHost\dumps"
)

if (-not (Test-Path $DumpDirectory)) {
    New-Item -ItemType Directory -Path $DumpDirectory -Force | Out-Null
}

$PID = $PID
$dumpCount = 0
$maxDumps = 3

Write-Host "Monitoring process $PID for memory threshold: ${ThresholdMB}MB" -ForegroundColor Cyan

while ($dumpCount -lt $maxDumps) {
    $proc = Get-Process -Id $PID -ErrorAction SilentlyContinue

    if (-not $proc) {
        Write-Host "Process ended" -ForegroundColor Red
        break
    }

    $workingSetMB = [math]::Round($proc.WorkingSet64 / 1MB, 2)
    $privateMB = [math]::Round($proc.PrivateMemorySize64 / 1MB, 2)
    $gcMB = [math]::Round([GC]::GetTotalMemory($false) / 1MB, 2)

    $timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$timestamp] WS: ${workingSetMB}MB | Private: ${privateMB}MB | GC: ${gcMB}MB" -ForegroundColor Gray

    if ($workingSetMB -gt $ThresholdMB) {
        $dumpPath = Join-Path $DumpDirectory "high_memory_$(Get-Date -Format 'yyyyMMdd_HHmmss').dmp"

        Write-Host "`n[ALERT] Memory threshold exceeded! Capturing dump..." -ForegroundColor Yellow

        try {
            & dotnet-dump collect -p $PID -o $dumpPath --type Full

            if (Test-Path $dumpPath) {
                $dumpSizeMB = [math]::Round((Get-Item $dumpPath).Length / 1MB, 2)
                Write-Host "✓ Dump captured: $dumpPath (${dumpSizeMB}MB)" -ForegroundColor Green
                $dumpCount++

                # Wait longer after capturing dump
                Start-Sleep -Seconds 300
            }
        }
        catch {
            Write-Host "✗ Failed to capture dump: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    Start-Sleep -Seconds $CheckIntervalSeconds
}

Write-Host "`nMonitoring complete. Captured $dumpCount dumps." -ForegroundColor Cyan
```

---

## Next Steps

1. **Immediate**: Use dotnet-dump to capture and analyze current state
2. **Short-term**: Set up automated monitoring with threshold-based dump capture
3. **Long-term**: Integrate memory profiling into CI/CD for regression testing

---

## Additional Resources

- [dotnet-dump documentation](https://learn.microsoft.com/en-us/dotnet/core/diagnostics/dotnet-dump)
- [SOS Debugging Extension](https://learn.microsoft.com/en-us/dotnet/framework/tools/sos-dll-sos-debugging-extension)
- [WinDbg documentation](https://learn.microsoft.com/en-us/windows-hardware/drivers/debugger/)
- [CLR MD GitHub](https://github.com/microsoft/clrmd)
- [PerfView Tutorial](https://github.com/microsoft/perfview/blob/main/documentation/Downloading.md)

---

**Status**: Ready to use - Install dotnet-dump and start capturing!
