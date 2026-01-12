# PSWebHost_Metrics Module
# Provides system metrics collection, aggregation, and persistence

$script:MetricsConfig = @{
    SampleIntervalSeconds = 5
    AggregationIntervalMinutes = 1
    RetentionHours = 24
    CsvRetentionDays = 30
    MetricsDirectory = $null  # Set during initialization
}

#region Initialization

function Initialize-PSWebMetrics {
    <#
    .SYNOPSIS
        Initializes the metrics collection system
    .DESCRIPTION
        Sets up the global metrics storage, starts the collection job, and loads historical data
    #>
    param(
        [int]$SampleIntervalSeconds = 5,
        [int]$RetentionHours = 24,
        [int]$CsvRetentionDays = 30
    )

    $MyTag = '[Initialize-PSWebMetrics]'

    # Update config
    $script:MetricsConfig.SampleIntervalSeconds = $SampleIntervalSeconds
    $script:MetricsConfig.RetentionHours = $RetentionHours
    $script:MetricsConfig.CsvRetentionDays = $CsvRetentionDays

    # Set up metrics directory
    $projectRoot = if ($Global:PSWebServer.Project_Root) { $Global:PSWebServer.Project_Root.Path } else { $PSScriptRoot | Split-Path | Split-Path }
    $script:MetricsConfig.MetricsDirectory = Join-Path $projectRoot "PsWebHost_Data\metrics"

    if (-not (Test-Path $script:MetricsConfig.MetricsDirectory)) {
        New-Item -Path $script:MetricsConfig.MetricsDirectory -ItemType Directory -Force | Out-Null
        Write-Host "$MyTag Created metrics directory: $($script:MetricsConfig.MetricsDirectory)"
    }

    # Initialize global metrics storage
    if (-not $Global:PSWebServer.Metrics) {
        $Global:PSWebServer.Metrics = [hashtable]::Synchronized(@{
            # Current/latest metrics snapshot
            Current = [hashtable]::Synchronized(@{
                Timestamp = $null
                Hostname = $env:COMPUTERNAME
                Cpu = @{}
                Memory = @{}
                Disk = @{}
                Network = @{}
                System = @{}
                Uptime = @{}
                TopProcessesCPU = @()
                TopProcessesMem = @()
            })

            # Raw samples (5-second intervals, last hour)
            Samples = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

            # Aggregated per-minute metrics (with avg, min, max)
            Aggregated = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())

            # Collection job state
            JobState = [hashtable]::Synchronized(@{
                Running = $false
                LastCollection = $null
                LastAggregation = $null
                LastCsvWrite = $null
                Errors = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
            })

            # Configuration
            Config = $script:MetricsConfig
        })
    }

    Write-Host "$MyTag Metrics system initialized"
    return $true
}

#endregion

#region Collection Functions

function Get-SystemMetricsSnapshot {
    <#
    .SYNOPSIS
        Collects a single snapshot of system metrics
    .DESCRIPTION
        Gathers CPU, memory, disk, network, process, and system metrics
    #>
    param(
        [int]$TimeoutSeconds = 3
    )

    $MyTag = '[Get-SystemMetricsSnapshot]'
    $timestamp = Get-Date

    $snapshot = @{
        Timestamp = $timestamp.ToString("yyyy-MM-dd HH:mm:ss")
        TimestampUtc = $timestamp.ToUniversalTime().ToString("o")
        Hostname = $env:COMPUTERNAME
    }

    # CPU Usage (per logical processor) with temperature
    try {
        $cpuCounters = Get-Counter -Counter '\Processor(*)\% Processor Time' -ErrorAction Stop
        $cpuData = @{}
        $cpuValues = @()

        foreach ($sample in $cpuCounters.CounterSamples) {
            if ($sample.InstanceName -eq '_total') {
                $cpuData.TotalPercent = [math]::Round($sample.CookedValue, 1)
            } else {
                $cpuValues += [math]::Round($sample.CookedValue, 1)
            }
        }

        $cpuData.Cores = $cpuValues
        $cpuData.CoreCount = $cpuValues.Count
        $cpuData.AvgPercent = if ($cpuValues.Count -gt 0) { [math]::Round(($cpuValues | Measure-Object -Average).Average, 1) } else { 0 }

        # Add temperature if available
        $temp = Get-CPUTemperature
        if ($temp) {
            $cpuData.Temperature = $temp
        }

        $snapshot.Cpu = $cpuData
    }
    catch {
        $snapshot.Cpu = @{ Error = $_.Exception.Message; CoreCount = 0; Cores = @(); TotalPercent = 0; AvgPercent = 0 }
    }

    # Memory Usage
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $totalMemoryGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
        $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        $usedMemoryGB = [math]::Round($totalMemoryGB - $freeMemoryGB, 2)
        $memoryPercent = [math]::Round(($usedMemoryGB / $totalMemoryGB) * 100, 1)

        $snapshot.Memory = @{
            TotalGB = $totalMemoryGB
            UsedGB = $usedMemoryGB
            FreeGB = $freeMemoryGB
            PercentUsed = $memoryPercent
        }
    }
    catch {
        $snapshot.Memory = @{ Error = $_.Exception.Message; TotalGB = 0; UsedGB = 0; FreeGB = 0; PercentUsed = 0 }
    }

    # Disk Usage and I/O
    try {
        $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" -ErrorAction Stop
        $diskData = @{}

        # Get disk I/O metrics
        $diskIO = Get-DiskIOMetrics

        foreach ($drive in $drives) {
            $totalGB = [math]::Round($drive.Size / 1GB, 2)
            $freeGB = [math]::Round($drive.FreeSpace / 1GB, 2)
            $usedGB = [math]::Round($totalGB - $freeGB, 2)
            $percentUsed = if ($totalGB -gt 0) { [math]::Round(($usedGB / $totalGB) * 100, 1) } else { 0 }

            $driveEntry = @{
                TotalGB = $totalGB
                UsedGB = $usedGB
                FreeGB = $freeGB
                PercentUsed = $percentUsed
            }

            # Add I/O metrics if available for this drive
            if ($diskIO.ContainsKey($drive.DeviceID)) {
                $driveEntry.KBPerSec = $diskIO[$drive.DeviceID].KBPerSec
                $driveEntry.IOPerSec = $diskIO[$drive.DeviceID].IOPerSec
            }

            $diskData[$drive.DeviceID] = $driveEntry
        }
        $snapshot.Disk = $diskData
    }
    catch {
        $snapshot.Disk = @{ Error = $_.Exception.Message }
    }

    # Network with Adapter Metadata
    try {
        $netCounters = Get-Counter -Counter '\Network Interface(*)\Bytes Total/sec' -ErrorAction Stop
        $netData = @{}

        # Get adapter metadata (type, vendor, MAC)
        $adapterMetadata = Get-NetworkAdapterMetadata

        foreach ($sample in $netCounters.CounterSamples) {
            if ($sample.InstanceName -notmatch 'Loopback|isatap') {
                $adapterEntry = @{
                    BytesPerSec = [math]::Round($sample.CookedValue, 0)
                    KBPerSec = [math]::Round($sample.CookedValue / 1KB, 1)
                }

                # Add metadata if available for this adapter
                if ($adapterMetadata.ContainsKey($sample.InstanceName)) {
                    $meta = $adapterMetadata[$sample.InstanceName]
                    $adapterEntry.Type = $meta.Type
                    $adapterEntry.Vendor = $meta.Vendor
                    $adapterEntry.MAC = $meta.MAC
                    $adapterEntry.Description = $meta.Description
                }

                $netData[$sample.InstanceName] = $adapterEntry
            }
        }
        $snapshot.Network = $netData
    }
    catch {
        $snapshot.Network = @{ Error = $_.Exception.Message }
    }

    # System Info (processes, threads, handles)
    try {
        $allProcesses = Get-Process -ErrorAction SilentlyContinue
        $processCount = $allProcesses.Count
        $handleCount = ($allProcesses | Measure-Object -Property Handles -Sum -ErrorAction SilentlyContinue).Sum

        # Get thread count via CIM (faster than enumerating process threads)
        $threadCount = 0
        try {
            $perfData = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_System -ErrorAction Stop
            $threadCount = $perfData.Threads
        }
        catch {
            # Fallback: estimate from process count
            $threadCount = $processCount * 5  # rough estimate
        }

        $snapshot.System = @{
            Processes = $processCount
            Threads = $threadCount
            Handles = $handleCount
        }
    }
    catch {
        $snapshot.System = @{ Error = $_.Exception.Message; Processes = 0; Threads = 0; Handles = 0 }
    }

    # Uptime
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $uptime = (Get-Date) - $os.LastBootUpTime

        $snapshot.Uptime = @{
            Days = $uptime.Days
            Hours = $uptime.Hours
            Minutes = $uptime.Minutes
            TotalHours = [math]::Round($uptime.TotalHours, 1)
            TotalMinutes = [math]::Round($uptime.TotalMinutes, 0)
        }
    }
    catch {
        $snapshot.Uptime = @{ Error = $_.Exception.Message; Days = 0; Hours = 0; Minutes = 0; TotalHours = 0 }
    }

    # Top Processes by CPU
    try {
        $topCpu = @(Get-Process -ErrorAction SilentlyContinue |
            Where-Object { $_.CPU -gt 0 } |
            Sort-Object CPU -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                @{
                    Name = $_.ProcessName
                    Cpu = [math]::Round($_.CPU, 2)
                    MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                    Id = $_.Id
                }
            })
        $snapshot.TopProcessesCPU = $topCpu
    }
    catch {
        $snapshot.TopProcessesCPU = @()
    }

    # Top Processes by Memory
    try {
        $topMem = @(Get-Process -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                @{
                    Name = $_.ProcessName
                    MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
                    Cpu = [math]::Round($_.CPU, 2)
                    Id = $_.Id
                }
            })
        $snapshot.TopProcessesMem = $topMem
    }
    catch {
        $snapshot.TopProcessesMem = @()
    }

    return $snapshot
}

function Update-CurrentMetrics {
    <#
    .SYNOPSIS
        Updates the current metrics in global storage
    #>
    param(
        [hashtable]$Snapshot
    )

    if (-not $Global:PSWebServer.Metrics) { return }

    $current = $Global:PSWebServer.Metrics.Current

    $current.Timestamp = $Snapshot.Timestamp
    $current.TimestampUtc = $Snapshot.TimestampUtc
    $current.Hostname = $Snapshot.Hostname
    $current.Cpu = $Snapshot.Cpu
    $current.Memory = $Snapshot.Memory
    $current.Disk = $Snapshot.Disk
    $current.Network = $Snapshot.Network
    $current.System = $Snapshot.System
    $current.Uptime = $Snapshot.Uptime
    $current.TopProcessesCPU = $Snapshot.TopProcessesCPU
    $current.TopProcessesMem = $Snapshot.TopProcessesMem

    $Global:PSWebServer.Metrics.JobState.LastCollection = Get-Date
}

function Add-MetricsSample {
    <#
    .SYNOPSIS
        Adds a metrics sample to the samples collection
    #>
    param(
        [hashtable]$Snapshot
    )

    if (-not $Global:PSWebServer.Metrics) { return }

    # Add to samples
    [void]$Global:PSWebServer.Metrics.Samples.Add($Snapshot)

    # Trim old samples (keep last hour of 5-second samples = 720 samples)
    $maxSamples = 720
    while ($Global:PSWebServer.Metrics.Samples.Count -gt $maxSamples) {
        $Global:PSWebServer.Metrics.Samples.RemoveAt(0)
    }
}

#endregion

#region Enhanced Collection Functions

function Get-OSPlatform {
    <#
    .SYNOPSIS
        Detects the operating system platform
    #>
    if ($IsWindows -or ($PSVersionTable.PSVersion.Major -le 5)) {
        return 'Windows'
    } elseif ($IsLinux) {
        return 'Linux'
    } elseif ($IsMacOS) {
        return 'macOS'
    }
    return 'Unknown'
}

function Get-CPUTemperature {
    <#
    .SYNOPSIS
        Gets CPU temperature if available
    .DESCRIPTION
        Attempts to retrieve CPU temperature using OS-specific methods
        Returns null if temperature data is unavailable
    #>
    param()

    $platform = Get-OSPlatform

    try {
        switch ($platform) {
            'Windows' {
                # Try WMI thermal zone (may not be available on all systems)
                $temps = Get-CimInstance -Namespace root/wmi -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction SilentlyContinue
                if ($temps) {
                    # Convert from tenths of Kelvin to Celsius
                    $tempValues = @($temps | ForEach-Object {
                        [math]::Round(($_.CurrentTemperature / 10) - 273.15, 1)
                    })
                    if ($tempValues.Count -gt 0) {
                        return @{
                            Min = ($tempValues | Measure-Object -Minimum).Minimum
                            Max = ($tempValues | Measure-Object -Maximum).Maximum
                            Avg = [math]::Round(($tempValues | Measure-Object -Average).Average, 1)
                        }
                    }
                }
            }
            'Linux' {
                # Read from /sys/class/thermal/thermal_zone*/temp
                $tempFiles = Get-ChildItem -Path '/sys/class/thermal/thermal_zone*/temp' -ErrorAction SilentlyContinue
                if ($tempFiles) {
                    $tempValues = @($tempFiles | ForEach-Object {
                        $content = Get-Content $_.FullName -ErrorAction SilentlyContinue
                        if ($content) {
                            # Convert from millidegrees to Celsius
                            [math]::Round([int]$content / 1000, 1)
                        }
                    } | Where-Object { $_ })

                    if ($tempValues.Count -gt 0) {
                        return @{
                            Min = ($tempValues | Measure-Object -Minimum).Minimum
                            Max = ($tempValues | Measure-Object -Maximum).Maximum
                            Avg = [math]::Round(($tempValues | Measure-Object -Average).Average, 1)
                        }
                    }
                }
            }
            'macOS' {
                # macOS temperature requires external tools (not implemented)
                return $null
            }
        }
    }
    catch {
        # Temperature unavailable
        return $null
    }

    return $null
}

function Get-DiskIOMetrics {
    <#
    .SYNOPSIS
        Gets disk I/O metrics (KB/sec and operations/sec)
    #>
    param()

    $platform = Get-OSPlatform
    $diskIO = @{}

    try {
        switch ($platform) {
            'Windows' {
                # Get disk I/O counters
                $diskCounters = Get-Counter -Counter '\PhysicalDisk(*)\Disk Bytes/sec', '\PhysicalDisk(*)\Disk Transfers/sec' -ErrorAction Stop

                # Group by instance (drive)
                $instances = @($diskCounters.CounterSamples | ForEach-Object { $_.InstanceName } | Where-Object { $_ -ne '_total' } | Select-Object -Unique)

                foreach ($instance in $instances) {
                    $bytesPerSec = ($diskCounters.CounterSamples | Where-Object {
                        $_.InstanceName -eq $instance -and $_.Path -match 'Bytes/sec'
                    }).CookedValue

                    $transfersPerSec = ($diskCounters.CounterSamples | Where-Object {
                        $_.InstanceName -eq $instance -and $_.Path -match 'Transfers/sec'
                    }).CookedValue

                    $diskIO[$instance] = @{
                        KBPerSec = [math]::Round($bytesPerSec / 1KB, 1)
                        IOPerSec = [math]::Round($transfersPerSec, 1)
                    }
                }
            }
            'Linux' {
                # Read from /proc/diskstats
                if (Test-Path '/proc/diskstats') {
                    $diskstats = Get-Content '/proc/diskstats' -ErrorAction SilentlyContinue
                    # Note: This requires calculating delta from previous sample
                    # For now, return empty (would need state tracking)
                }
            }
        }
    }
    catch {
        # Disk I/O metrics unavailable
    }

    return $diskIO
}

function Get-NetworkAdapterMetadata {
    <#
    .SYNOPSIS
        Gets detailed network adapter information including type, vendor, and MAC
    #>
    param()

    $platform = Get-OSPlatform
    $adapters = @{}

    try {
        switch ($platform) {
            'Windows' {
                $netAdapters = Get-CimInstance -ClassName Win32_NetworkAdapter -ErrorAction Stop |
                    Where-Object { $_.PhysicalAdapter -eq $true -or $_.NetEnabled -eq $true }

                foreach ($adapter in $netAdapters) {
                    $adapterName = $adapter.NetConnectionID
                    if (-not $adapterName) { $adapterName = $adapter.Name }

                    # Determine adapter type
                    $adapterType = 'other'
                    if ($adapter.Name -match 'Docker|vEthernet') {
                        $adapterType = 'docker'
                    } elseif ($adapter.Name -match 'VPN|TAP|OpenVPN') {
                        $adapterType = 'vpn'
                    } elseif ($adapter.Name -match 'WSL|vEthernet \(WSL\)') {
                        $adapterType = 'wsl'
                    } elseif ($adapter.Name -match 'Virtual|Hyper-V') {
                        $adapterType = 'virtual'
                    } elseif ($adapter.PhysicalAdapter -eq $true) {
                        $adapterType = 'physical'
                    }

                    $adapters[$adapterName] = @{
                        Type = $adapterType
                        Vendor = $adapter.Manufacturer
                        MAC = $adapter.MACAddress
                        Description = $adapter.Description
                    }
                }
            }
            'Linux' {
                # Get adapter info from /sys/class/net
                $netInterfaces = Get-ChildItem -Path '/sys/class/net' -ErrorAction SilentlyContinue
                foreach ($iface in $netInterfaces) {
                    $ifaceName = $iface.Name

                    $adapterType = 'other'
                    if ($ifaceName -match '^lo') {
                        continue  # Skip loopback
                    } elseif ($ifaceName -match '^docker|^br-') {
                        $adapterType = 'docker'
                    } elseif ($ifaceName -match '^tun|^tap|^vpn') {
                        $adapterType = 'vpn'
                    } elseif ($ifaceName -match '^veth|^virbr') {
                        $adapterType = 'virtual'
                    } else {
                        $adapterType = 'physical'
                    }

                    $macPath = Join-Path $iface.FullName 'address'
                    $mac = if (Test-Path $macPath) { Get-Content $macPath -ErrorAction SilentlyContinue } else { $null }

                    $adapters[$ifaceName] = @{
                        Type = $adapterType
                        Vendor = $null  # Not easily available on Linux
                        MAC = $mac
                        Description = $null
                    }
                }
            }
        }
    }
    catch {
        # Network metadata unavailable
    }

    return $adapters
}

#endregion

#region Aggregation Functions

function Invoke-MetricsAggregation {
    <#
    .SYNOPSIS
        Aggregates raw samples into per-minute metrics with avg, min, max
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Invoke-MetricsAggregation]'

    if (-not $Global:PSWebServer.Metrics -or $Global:PSWebServer.Metrics.Samples.Count -eq 0) {
        return
    }

    $now = Get-Date
    $lastAgg = $Global:PSWebServer.Metrics.JobState.LastAggregation

    # Only aggregate once per minute unless forced
    if (-not $Force -and $lastAgg -and ($now - $lastAgg).TotalSeconds -lt 60) {
        return
    }

    # Get samples from the last minute
    $oneMinuteAgo = $now.AddMinutes(-1)
    $minuteStart = [datetime]::new($oneMinuteAgo.Year, $oneMinuteAgo.Month, $oneMinuteAgo.Day, $oneMinuteAgo.Hour, $oneMinuteAgo.Minute, 0)
    $minuteEnd = $minuteStart.AddMinutes(1)

    $samplesToAggregate = @($Global:PSWebServer.Metrics.Samples | Where-Object {
        $ts = [datetime]::Parse($_.Timestamp)
        $ts -ge $minuteStart -and $ts -lt $minuteEnd
    })

    if ($samplesToAggregate.Count -eq 0) {
        return
    }

    # Create aggregated record
    $aggregated = @{
        MinuteTimestamp = $minuteStart.ToString("yyyy-MM-dd HH:mm:00")
        MinuteTimestampUtc = $minuteStart.ToUniversalTime().ToString("o")
        SampleCount = $samplesToAggregate.Count
        Hostname = $env:COMPUTERNAME
    }

    # Aggregate CPU
    $cpuTotals = @($samplesToAggregate | Where-Object { $_.Cpu.TotalPercent } | ForEach-Object { $_.Cpu.TotalPercent })
    if ($cpuTotals.Count -gt 0) {
        $aggregated.Cpu = @{
            Avg = [math]::Round(($cpuTotals | Measure-Object -Average).Average, 1)
            Min = [math]::Round(($cpuTotals | Measure-Object -Minimum).Minimum, 1)
            Max = [math]::Round(($cpuTotals | Measure-Object -Maximum).Maximum, 1)
            CoreCount = $samplesToAggregate[0].Cpu.CoreCount
        }
    }

    # Aggregate Memory
    $memPercents = @($samplesToAggregate | Where-Object { $_.Memory.PercentUsed } | ForEach-Object { $_.Memory.PercentUsed })
    if ($memPercents.Count -gt 0) {
        $lastMem = $samplesToAggregate[-1].Memory
        $aggregated.Memory = @{
            TotalGB = $lastMem.TotalGB
            PercentUsed_Avg = [math]::Round(($memPercents | Measure-Object -Average).Average, 1)
            PercentUsed_Min = [math]::Round(($memPercents | Measure-Object -Minimum).Minimum, 1)
            PercentUsed_Max = [math]::Round(($memPercents | Measure-Object -Maximum).Maximum, 1)
        }
    }

    # Aggregate Disk (take last snapshot)
    $lastDisk = $samplesToAggregate[-1].Disk
    if ($lastDisk -and -not $lastDisk.Error) {
        $aggregated.Disk = $lastDisk
    }

    # Aggregate Network
    $netKeys = @()
    foreach ($sample in $samplesToAggregate) {
        if ($sample.Network -and -not $sample.Network.Error) {
            $netKeys += $sample.Network.Keys
        }
    }
    $netKeys = $netKeys | Select-Object -Unique

    $netAgg = @{}
    foreach ($key in $netKeys) {
        $kbValues = @($samplesToAggregate | Where-Object { $_.Network[$key] } | ForEach-Object { $_.Network[$key].KBPerSec })
        if ($kbValues.Count -gt 0) {
            $netAgg[$key] = @{
                KBPerSec_Avg = [math]::Round(($kbValues | Measure-Object -Average).Average, 1)
                KBPerSec_Min = [math]::Round(($kbValues | Measure-Object -Minimum).Minimum, 1)
                KBPerSec_Max = [math]::Round(($kbValues | Measure-Object -Maximum).Maximum, 1)
            }
        }
    }
    $aggregated.Network = $netAgg

    # Aggregate System
    $procCounts = @($samplesToAggregate | Where-Object { $_.System.Processes } | ForEach-Object { $_.System.Processes })
    $threadCounts = @($samplesToAggregate | Where-Object { $_.System.Threads -and $_.System.Threads -is [int] } | ForEach-Object { $_.System.Threads })

    $aggregated.System = @{
        Processes_Avg = if ($procCounts.Count -gt 0) { [math]::Round(($procCounts | Measure-Object -Average).Average, 0) } else { 0 }
        Threads_Avg = if ($threadCounts.Count -gt 0) { [math]::Round(($threadCounts | Measure-Object -Average).Average, 0) } else { 0 }
    }

    # Add to aggregated collection
    [void]$Global:PSWebServer.Metrics.Aggregated.Add($aggregated)

    # Trim old aggregated data (keep 24 hours = 1440 minutes)
    $maxAggregated = 1440
    while ($Global:PSWebServer.Metrics.Aggregated.Count -gt $maxAggregated) {
        $Global:PSWebServer.Metrics.Aggregated.RemoveAt(0)
    }

    $Global:PSWebServer.Metrics.JobState.LastAggregation = $now

    Write-Verbose "$MyTag Aggregated $($samplesToAggregate.Count) samples for $($minuteStart.ToString('HH:mm'))"
}

#endregion

#region CSV Persistence

function Write-MetricsToCsv {
    <#
    .SYNOPSIS
        Writes aggregated metrics to CSV files for long-term storage
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Write-MetricsToCsv]'

    if (-not $Global:PSWebServer.Metrics -or -not $script:MetricsConfig.MetricsDirectory) {
        return
    }

    $now = Get-Date
    $lastWrite = $Global:PSWebServer.Metrics.JobState.LastCsvWrite

    # Write once per minute unless forced
    if (-not $Force -and $lastWrite -and ($now - $lastWrite).TotalMinutes -lt 1) {
        return
    }

    $metricsDir = $script:MetricsConfig.MetricsDirectory
    $dateStr = $now.ToString("yyyy-MM-dd")
    $csvPath = Join-Path $metricsDir "metrics_$dateStr.csv"

    # Get aggregated metrics that haven't been written yet
    $toWrite = @()
    if ($Global:PSWebServer.Metrics.Aggregated.Count -gt 0) {
        # Get the last few minutes of aggregated data
        $cutoff = $now.AddMinutes(-5)
        $toWrite = @($Global:PSWebServer.Metrics.Aggregated | Where-Object {
            $ts = [datetime]::Parse($_.MinuteTimestamp)
            $ts -ge $cutoff
        })
    }

    if ($toWrite.Count -eq 0) {
        return
    }

    # Build CSV records
    $csvRecords = foreach ($agg in $toWrite) {
        [PSCustomObject]@{
            Timestamp = $agg.MinuteTimestamp
            Hostname = $agg.Hostname
            SampleCount = $agg.SampleCount
            Cpu_Avg = $agg.Cpu.Avg
            Cpu_Min = $agg.Cpu.Min
            Cpu_Max = $agg.Cpu.Max
            Cpu_CoreCount = $agg.Cpu.CoreCount
            Memory_TotalGB = $agg.Memory.TotalGB
            Memory_PercentUsed_Avg = $agg.Memory.PercentUsed_Avg
            Memory_PercentUsed_Min = $agg.Memory.PercentUsed_Min
            Memory_PercentUsed_Max = $agg.Memory.PercentUsed_Max
            Processes_Avg = $agg.System.Processes_Avg
            Threads_Avg = $agg.System.Threads_Avg
        }
    }

    # Append to CSV
    $fileExists = Test-Path $csvPath
    try {
        if ($fileExists) {
            # Check if these timestamps already exist
            $existingData = Import-Csv $csvPath -ErrorAction SilentlyContinue
            $existingTimestamps = @($existingData | ForEach-Object { $_.Timestamp })
            $newRecords = @($csvRecords | Where-Object { $_.Timestamp -notin $existingTimestamps })

            if ($newRecords.Count -gt 0) {
                $newRecords | Export-Csv -Path $csvPath -Append -NoTypeInformation
            }
        }
        else {
            $csvRecords | Export-Csv -Path $csvPath -NoTypeInformation
        }

        $Global:PSWebServer.Metrics.JobState.LastCsvWrite = $now
    }
    catch {
        Write-Warning "$MyTag Failed to write metrics CSV: $($_.Exception.Message)"
    }
}

function Remove-OldMetricsCsvFiles {
    <#
    .SYNOPSIS
        Removes CSV files older than retention period
    #>
    param(
        [int]$RetentionDays = 30
    )

    $MyTag = '[Remove-OldMetricsCsvFiles]'

    if (-not $script:MetricsConfig.MetricsDirectory) { return }

    $metricsDir = $script:MetricsConfig.MetricsDirectory
    if (-not (Test-Path $metricsDir)) { return }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)

    Get-ChildItem -Path $metricsDir -Filter "metrics_*.csv" | ForEach-Object {
        if ($_.LastWriteTime -lt $cutoffDate) {
            Remove-Item $_.FullName -Force
            Write-Verbose "$MyTag Removed old metrics file: $($_.Name)"
        }
    }
}

function Get-MetricsFromCsv {
    <#
    .SYNOPSIS
        Retrieves historical metrics from CSV files
    #>
    param(
        [datetime]$StartDate = (Get-Date).AddDays(-1),
        [datetime]$EndDate = (Get-Date),
        [int]$MaxRecords = 1440
    )

    if (-not $script:MetricsConfig.MetricsDirectory) { return @() }

    $metricsDir = $script:MetricsConfig.MetricsDirectory
    if (-not (Test-Path $metricsDir)) { return @() }

    $results = @()
    $currentDate = $StartDate.Date

    while ($currentDate -le $EndDate.Date) {
        $dateStr = $currentDate.ToString("yyyy-MM-dd")
        $csvPath = Join-Path $metricsDir "metrics_$dateStr.csv"

        if (Test-Path $csvPath) {
            $dayData = Import-Csv $csvPath -ErrorAction SilentlyContinue
            if ($dayData) {
                $results += $dayData | Where-Object {
                    $ts = [datetime]::Parse($_.Timestamp)
                    $ts -ge $StartDate -and $ts -le $EndDate
                }
            }
        }

        $currentDate = $currentDate.AddDays(1)
    }

    # Limit results
    if ($results.Count -gt $MaxRecords) {
        $results = $results | Select-Object -Last $MaxRecords
    }

    return $results
}

function Write-MetricsToInterimCsv {
    <#
    .SYNOPSIS
        Writes 1-minute aggregated metrics to per-table/per-timestamp CSV files (new architecture)
    .DESCRIPTION
        Aggregates the last 12×5-second samples into 1-minute aggregates and writes to CSV.
        Format: Perf_CPUCore_2026-01-06T10:24:00.csv
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Write-MetricsToInterimCsv]'

    if (-not $Global:PSWebServer.Metrics -or -not $script:MetricsConfig.MetricsDirectory) {
        return
    }

    $now = Get-Date
    $lastWrite = $Global:PSWebServer.Metrics.JobState.LastInterimCsvWrite

    # Write every minute at :00 seconds unless forced
    if (-not $Force -and $lastWrite -and ($now - $lastWrite).TotalSeconds -lt 60) {
        return
    }

    # Only run at :00 seconds (or within 6 seconds of it to accommodate 5-second timer)
    if (-not $Force -and $now.Second -gt 6) {
        return
    }

    $metricsDir = $script:MetricsConfig.MetricsDirectory
    if (-not (Test-Path $metricsDir)) {
        New-Item -Path $metricsDir -ItemType Directory -Force | Out-Null
    }

    # Get the last 12 samples (1 minute at 5-second intervals)
    $oneMinuteAgo = $now.AddSeconds(-60)
    $samplesToAggregate = @($Global:PSWebServer.Metrics.Samples | Where-Object {
        $ts = [datetime]::Parse($_.Timestamp)
        $ts -ge $oneMinuteAgo
    } | Select-Object -Last 12)

    if ($samplesToAggregate.Count -eq 0) {
        Write-Verbose "$MyTag No samples to aggregate"
        return
    }

    # Round to nearest minute for timestamp
    $minuteTimestamp = [datetime]::new($now.Year, $now.Month, $now.Day, $now.Hour, $now.Minute, 0)
    # Use underscore instead of colon for Windows-compatible filenames
    $timestampStr = $minuteTimestamp.ToString("yyyy-MM-dd_HH-mm-ss")
    $hostname = $env:COMPUTERNAME

    # Aggregate CPU metrics (per-core)
    $cpuCoreData = @{}
    foreach ($sample in $samplesToAggregate) {
        if ($sample.Cpu -and $sample.Cpu.Cores) {
            for ($i = 0; $i -lt $sample.Cpu.Cores.Count; $i++) {
                if (-not $cpuCoreData.ContainsKey($i)) {
                    $cpuCoreData[$i] = @()
                }
                $cpuCoreData[$i] += $sample.Cpu.Cores[$i]
            }
        }
    }

    # Write Perf_CPUCore CSV
    if ($cpuCoreData.Count -gt 0) {
        $cpuCsvPath = Join-Path $metricsDir "Perf_CPUCore_$timestampStr.csv"
        $cpuRecords = foreach ($coreNum in $cpuCoreData.Keys) {
            $values = $cpuCoreData[$coreNum]
            $temps = @($samplesToAggregate | Where-Object { $_.Cpu.Temperature } | ForEach-Object { $_.Cpu.Temperature })

            [PSCustomObject]@{
                Timestamp = $timestampStr
                Host = $hostname
                CoreNumber = $coreNum
                Percent_Min = [math]::Round(($values | Measure-Object -Minimum).Minimum, 1)
                Percent_Max = [math]::Round(($values | Measure-Object -Maximum).Maximum, 1)
                Percent_Avg = [math]::Round(($values | Measure-Object -Average).Average, 1)
                Temp_Min = if ($temps.Count -gt 0) { ($temps | ForEach-Object { $_.Min } | Measure-Object -Minimum).Minimum } else { $null }
                Temp_Max = if ($temps.Count -gt 0) { ($temps | ForEach-Object { $_.Max } | Measure-Object -Maximum).Maximum } else { $null }
                Temp_Avg = if ($temps.Count -gt 0) { [math]::Round(($temps | ForEach-Object { $_.Avg } | Measure-Object -Average).Average, 1) } else { $null }
                Seconds = 5
            }
        }
        $cpuRecords | Export-Csv -Path $cpuCsvPath -NoTypeInformation
        Write-Verbose "$MyTag Wrote CPU metrics to $cpuCsvPath"
    }

    # Aggregate Memory metrics
    $memValues = @($samplesToAggregate | Where-Object { $_.Memory -and -not $_.Memory.Error } | ForEach-Object { $_.Memory })
    if ($memValues.Count -gt 0) {
        $memCsvPath = Join-Path $metricsDir "Perf_MemoryUsage_$timestampStr.csv"
        $memRecord = [PSCustomObject]@{
            Timestamp = $timestampStr
            Host = $hostname
            MB_Min = [math]::Round(($memValues | ForEach-Object { $_.UsedGB * 1024 } | Measure-Object -Minimum).Minimum, 1)
            MB_Max = [math]::Round(($memValues | ForEach-Object { $_.UsedGB * 1024 } | Measure-Object -Maximum).Maximum, 1)
            MB_Avg = [math]::Round(($memValues | ForEach-Object { $_.UsedGB * 1024 } | Measure-Object -Average).Average, 1)
            Seconds = 5
        }
        $memRecord | Export-Csv -Path $memCsvPath -NoTypeInformation
        Write-Verbose "$MyTag Wrote Memory metrics to $memCsvPath"
    }

    # Aggregate Disk I/O metrics (per-drive)
    $diskIOData = @{}
    foreach ($sample in $samplesToAggregate) {
        if ($sample.Disk -and -not $sample.Disk.Error) {
            foreach ($drive in $sample.Disk.Keys) {
                $driveData = $sample.Disk[$drive]
                if ($driveData.KBPerSec -or $driveData.IOPerSec) {
                    if (-not $diskIOData.ContainsKey($drive)) {
                        $diskIOData[$drive] = @{ KBPerSec = @(); IOPerSec = @() }
                    }
                    if ($driveData.KBPerSec) { $diskIOData[$drive].KBPerSec += $driveData.KBPerSec }
                    if ($driveData.IOPerSec) { $diskIOData[$drive].IOPerSec += $driveData.IOPerSec }
                }
            }
        }
    }

    if ($diskIOData.Count -gt 0) {
        $diskCsvPath = Join-Path $metricsDir "Perf_DiskIO_$timestampStr.csv"
        $diskRecords = foreach ($drive in $diskIOData.Keys) {
            $kbValues = $diskIOData[$drive].KBPerSec
            $ioValues = $diskIOData[$drive].IOPerSec

            [PSCustomObject]@{
                Timestamp = $timestampStr
                Host = $hostname
                Drive = $drive
                KBPerSec_Min = if ($kbValues.Count -gt 0) { [math]::Round(($kbValues | Measure-Object -Minimum).Minimum, 1) } else { $null }
                KBPerSec_Max = if ($kbValues.Count -gt 0) { [math]::Round(($kbValues | Measure-Object -Maximum).Maximum, 1) } else { $null }
                KBPerSec_Avg = if ($kbValues.Count -gt 0) { [math]::Round(($kbValues | Measure-Object -Average).Average, 1) } else { $null }
                KBPerSec_Total = if ($kbValues.Count -gt 0) { [math]::Round(($kbValues | Measure-Object -Sum).Sum, 1) } else { $null }
                IOPerSec_Min = if ($ioValues.Count -gt 0) { [math]::Round(($ioValues | Measure-Object -Minimum).Minimum, 1) } else { $null }
                IOPerSec_Max = if ($ioValues.Count -gt 0) { [math]::Round(($ioValues | Measure-Object -Maximum).Maximum, 1) } else { $null }
                IOPerSec_Avg = if ($ioValues.Count -gt 0) { [math]::Round(($ioValues | Measure-Object -Average).Average, 1) } else { $null }
                IO_Total = if ($ioValues.Count -gt 0) { [int](($ioValues | Measure-Object -Sum).Sum) } else { $null }
                Seconds = 5
            }
        }
        $diskRecords | Export-Csv -Path $diskCsvPath -NoTypeInformation
        Write-Verbose "$MyTag Wrote Disk I/O metrics to $diskCsvPath"
    }

    # Aggregate Network metrics (per-adapter)
    $networkData = @{}
    foreach ($sample in $samplesToAggregate) {
        if ($sample.Network -and -not $sample.Network.Error) {
            foreach ($adapter in $sample.Network.Keys) {
                $adapterData = $sample.Network[$adapter]
                if (-not $networkData.ContainsKey($adapter)) {
                    $networkData[$adapter] = @{
                        IngressKB = @()
                        EgressKB = @()
                        Type = $adapterData.Type
                        Vendor = $adapterData.Vendor
                        MAC = $adapterData.MAC
                    }
                }
                # Note: For now we only have BytesPerSec total, not ingress/egress separately
                # We'll split it 50/50 as a placeholder until we get separate counters
                $kbPerSec = $adapterData.KBPerSec
                $networkData[$adapter].IngressKB += ($kbPerSec / 2)
                $networkData[$adapter].EgressKB += ($kbPerSec / 2)
            }
        }
    }

    if ($networkData.Count -gt 0) {
        $netCsvPath = Join-Path $metricsDir "Network_$timestampStr.csv"
        $netRecords = foreach ($adapter in $networkData.Keys) {
            $ingressValues = $networkData[$adapter].IngressKB
            $egressValues = $networkData[$adapter].EgressKB

            [PSCustomObject]@{
                Timestamp = $timestampStr
                Host = $hostname
                AdapterName = $adapter
                AdapterType = $networkData[$adapter].Type
                VendorName = $networkData[$adapter].Vendor
                MACAddress = $networkData[$adapter].MAC
                IngressKB_Min = [math]::Round(($ingressValues | Measure-Object -Minimum).Minimum, 1)
                IngressKB_Max = [math]::Round(($ingressValues | Measure-Object -Maximum).Maximum, 1)
                IngressKB_Avg = [math]::Round(($ingressValues | Measure-Object -Average).Average, 1)
                IngressKB_Total = [math]::Round(($ingressValues | Measure-Object -Sum).Sum, 1)
                EgressKB_Min = [math]::Round(($egressValues | Measure-Object -Minimum).Minimum, 1)
                EgressKB_Max = [math]::Round(($egressValues | Measure-Object -Maximum).Maximum, 1)
                EgressKB_Avg = [math]::Round(($egressValues | Measure-Object -Average).Average, 1)
                EgressKB_Total = [math]::Round(($egressValues | Measure-Object -Sum).Sum, 1)
                Seconds = 5
            }
        }
        $netRecords | Export-Csv -Path $netCsvPath -NoTypeInformation
        Write-Verbose "$MyTag Wrote Network metrics to $netCsvPath"
    }

    # Clean up old CSV files (keep last 5 minutes)
    $fiveMinutesAgo = $now.AddMinutes(-5)
    Get-ChildItem -Path $metricsDir -Filter "Perf_*.csv" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.LastWriteTime -lt $fiveMinutesAgo) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }
    Get-ChildItem -Path $metricsDir -Filter "Network_*.csv" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.LastWriteTime -lt $fiveMinutesAgo) {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    $Global:PSWebServer.Metrics.JobState.LastInterimCsvWrite = $now
}

function Move-CsvToSqlite {
    <#
    .SYNOPSIS
        Moves CSV metrics files to SQLite database (new architecture)
    .DESCRIPTION
        Reads all CSV files older than 30 seconds, batch inserts to pswebhost_perf.db, then deletes CSV.
        Runs every 5 minutes (at :00-:10 seconds).
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Move-CsvToSqlite]'

    if (-not $script:MetricsConfig.MetricsDirectory) {
        return
    }

    $now = Get-Date
    $lastMove = $Global:PSWebServer.Metrics.JobState.LastCsvToSqliteMove

    # Run every 5 minutes unless forced
    if (-not $Force -and $lastMove -and ($now - $lastMove).TotalMinutes -lt 5) {
        return
    }

    # Only run at :00-:10 seconds on 5-minute boundaries
    if (-not $Force) {
        if ($now.Minute % 5 -ne 0 -or $now.Second -gt 10) {
            return
        }
    }

    $metricsDir = $script:MetricsConfig.MetricsDirectory
    if (-not (Test-Path $metricsDir)) {
        return
    }

    # Get CSV files older than 30 seconds
    $cutoffTime = $now.AddSeconds(-30)
    $csvFiles = Get-ChildItem -Path $metricsDir -Filter "*.csv" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffTime }

    if ($csvFiles.Count -eq 0) {
        Write-Verbose "$MyTag No CSV files to process"
        return
    }

    Write-Verbose "$MyTag Processing $($csvFiles.Count) CSV files"

    # Group files by table type
    $filesByTable = @{}
    foreach ($file in $csvFiles) {
        $baseName = $file.BaseName
        # Extract table name from filename (e.g., "Perf_CPUCore_2026-01-06_15-18-00" -> "Perf_CPUCore")
        if ($baseName -match '^(Perf_\w+|Network)_\d{4}') {
            $tableName = $matches[1]
            if (-not $filesByTable.ContainsKey($tableName)) {
                $filesByTable[$tableName] = @()
            }
            $filesByTable[$tableName] += $file
        }
    }

    # Process each table type
    foreach ($tableName in $filesByTable.Keys) {
        $tableFiles = $filesByTable[$tableName]
        $allRecords = @()

        # Read all CSV files for this table
        foreach ($file in $tableFiles) {
            try {
                $records = Import-Csv -Path $file.FullName -ErrorAction Stop
                $allRecords += $records
            }
            catch {
                Write-Warning "$MyTag Failed to read $($file.Name): $($_.Exception.Message)"
            }
        }

        if ($allRecords.Count -eq 0) {
            continue
        }

        Write-Verbose "$MyTag Inserting $($allRecords.Count) records into $tableName"

        # Build INSERT query based on table structure
        try {
            switch ($tableName) {
                'Perf_CPUCore' {
                    $insertQuery = @"
BEGIN TRANSACTION;
$(foreach ($record in $allRecords) {
    "INSERT INTO Perf_CPUCore (Timestamp, Host, CoreNumber, Percent_Min, Percent_Max, Percent_Avg, Temp_Min, Temp_Max, Temp_Avg, Seconds) VALUES ('$($record.Timestamp)', '$($record.Host)', $($record.CoreNumber), $($record.Percent_Min), $($record.Percent_Max), $($record.Percent_Avg), $(if ($record.Temp_Min) { $record.Temp_Min } else { 'NULL' }), $(if ($record.Temp_Max) { $record.Temp_Max } else { 'NULL' }), $(if ($record.Temp_Avg) { $record.Temp_Avg } else { 'NULL' }), $($record.Seconds));"
})
COMMIT;
"@
                }
                'Perf_MemoryUsage' {
                    $insertQuery = @"
BEGIN TRANSACTION;
$(foreach ($record in $allRecords) {
    "INSERT INTO Perf_MemoryUsage (Timestamp, Host, MB_Min, MB_Max, MB_Avg, Seconds) VALUES ('$($record.Timestamp)', '$($record.Host)', $($record.MB_Min), $($record.MB_Max), $($record.MB_Avg), $($record.Seconds));"
})
COMMIT;
"@
                }
                'Perf_DiskIO' {
                    $insertQuery = @"
BEGIN TRANSACTION;
$(foreach ($record in $allRecords) {
    "INSERT INTO Perf_DiskIO (Timestamp, Host, Drive, KBPerSec_Min, KBPerSec_Max, KBPerSec_Avg, KBPerSec_Total, IOPerSec_Min, IOPerSec_Max, IOPerSec_Avg, IO_Total, Seconds) VALUES ('$($record.Timestamp)', '$($record.Host)', '$($record.Drive)', $(if ($record.KBPerSec_Min) { $record.KBPerSec_Min } else { 'NULL' }), $(if ($record.KBPerSec_Max) { $record.KBPerSec_Max } else { 'NULL' }), $(if ($record.KBPerSec_Avg) { $record.KBPerSec_Avg } else { 'NULL' }), $(if ($record.KBPerSec_Total) { $record.KBPerSec_Total } else { 'NULL' }), $(if ($record.IOPerSec_Min) { $record.IOPerSec_Min } else { 'NULL' }), $(if ($record.IOPerSec_Max) { $record.IOPerSec_Max } else { 'NULL' }), $(if ($record.IOPerSec_Avg) { $record.IOPerSec_Avg } else { 'NULL' }), $(if ($record.IO_Total) { $record.IO_Total } else { 'NULL' }), $($record.Seconds));"
})
COMMIT;
"@
                }
                'Network' {
                    $insertQuery = @"
BEGIN TRANSACTION;
$(foreach ($record in $allRecords) {
    $adapterName = $record.AdapterName -replace "'", "''"
    $vendorName = if ($record.VendorName) { "'$($record.VendorName -replace "'", "''")'" } else { 'NULL' }
    $macAddress = if ($record.MACAddress) { "'$($record.MACAddress)'" } else { 'NULL' }
    "INSERT INTO Network (Timestamp, Host, AdapterName, AdapterType, VendorName, MACAddress, IngressKB_Min, IngressKB_Max, IngressKB_Avg, IngressKB_Total, EgressKB_Min, EgressKB_Max, EgressKB_Avg, EgressKB_Total, Seconds) VALUES ('$($record.Timestamp)', '$($record.Host)', '$adapterName', '$($record.AdapterType)', $vendorName, $macAddress, $($record.IngressKB_Min), $($record.IngressKB_Max), $($record.IngressKB_Avg), $($record.IngressKB_Total), $($record.EgressKB_Min), $($record.EgressKB_Max), $($record.EgressKB_Avg), $($record.EgressKB_Total), $($record.Seconds));"
})
COMMIT;
"@
                }
            }

            # Execute the batch insert
            Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $insertQuery

            # Delete CSV files after successful insert
            foreach ($file in $tableFiles) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Verbose "$MyTag Deleted $($file.Name)"
                }
                catch {
                    Write-Warning "$MyTag Failed to delete $($file.Name): $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Warning "$MyTag Failed to insert $tableName records: $($_.Exception.Message)"
            # CSV files preserved for retry on next run
        }
    }

    $Global:PSWebServer.Metrics.JobState.LastCsvToSqliteMove = $now
}

function Invoke-Metrics60sAggregation {
    <#
    .SYNOPSIS
        Aggregates 5-second metrics into 60-second samples (new architecture)
    .DESCRIPTION
        Queries all rows with Seconds = 5 older than 1 hour, aggregates into 1-minute samples,
        inserts with Seconds = 60, then deletes original 5-second rows.
        Runs every 15 minutes.
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Invoke-Metrics60sAggregation]'

    $now = Get-Date
    $lastAgg = $Global:PSWebServer.Metrics.JobState.Last60sAggregation

    # Run every 15 minutes unless forced
    if (-not $Force -and $lastAgg -and ($now - $lastAgg).TotalMinutes -lt 15) {
        return
    }

    # Only run at :00 seconds on 15-minute boundaries
    if (-not $Force) {
        if ($now.Minute % 15 -ne 0 -or $now.Second -gt 10) {
            return
        }
    }

    $oneHourAgo = $now.AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Verbose "$MyTag Aggregating 5-second samples older than $oneHourAgo"

    try {
        # Aggregate Perf_CPUCore: Group by 1-minute buckets and core number
        $aggCpuQuery = @"
INSERT INTO Perf_CPUCore (Timestamp, Host, CoreNumber, Percent_Min, Percent_Max, Percent_Avg, Temp_Min, Temp_Max, Temp_Avg, Seconds)
SELECT
    strftime('%Y-%m-%d %H:%M:00', Timestamp) AS MinuteTimestamp,
    Host,
    CoreNumber,
    MIN(Percent_Min) AS Percent_Min,
    MAX(Percent_Max) AS Percent_Max,
    AVG(Percent_Avg) AS Percent_Avg,
    MIN(Temp_Min) AS Temp_Min,
    MAX(Temp_Max) AS Temp_Max,
    AVG(Temp_Avg) AS Temp_Avg,
    60 AS Seconds
FROM Perf_CPUCore
WHERE Seconds = 5 AND Timestamp < '$oneHourAgo'
GROUP BY strftime('%Y-%m-%d %H:%M:00', Timestamp), Host, CoreNumber;
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $aggCpuQuery
        Write-Verbose "$MyTag Aggregated CPU metrics"

        # Delete original 5-second CPU records
        $deleteCpuQuery = "DELETE FROM Perf_CPUCore WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';"
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $deleteCpuQuery

        # Aggregate Perf_MemoryUsage
        $aggMemQuery = @"
INSERT INTO Perf_MemoryUsage (Timestamp, Host, MB_Min, MB_Max, MB_Avg, Seconds)
SELECT
    strftime('%Y-%m-%d %H:%M:00', Timestamp) AS MinuteTimestamp,
    Host,
    MIN(MB_Min) AS MB_Min,
    MAX(MB_Max) AS MB_Max,
    AVG(MB_Avg) AS MB_Avg,
    60 AS Seconds
FROM Perf_MemoryUsage
WHERE Seconds = 5 AND Timestamp < '$oneHourAgo'
GROUP BY strftime('%Y-%m-%d %H:%M:00', Timestamp), Host;
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $aggMemQuery
        Write-Verbose "$MyTag Aggregated Memory metrics"

        $deleteMemQuery = "DELETE FROM Perf_MemoryUsage WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';"
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $deleteMemQuery

        # Aggregate Perf_DiskIO
        $aggDiskQuery = @"
INSERT INTO Perf_DiskIO (Timestamp, Host, Drive, KBPerSec_Min, KBPerSec_Max, KBPerSec_Avg, KBPerSec_Total, IOPerSec_Min, IOPerSec_Max, IOPerSec_Avg, IO_Total, Seconds)
SELECT
    strftime('%Y-%m-%d %H:%M:00', Timestamp) AS MinuteTimestamp,
    Host,
    Drive,
    MIN(KBPerSec_Min) AS KBPerSec_Min,
    MAX(KBPerSec_Max) AS KBPerSec_Max,
    AVG(KBPerSec_Avg) AS KBPerSec_Avg,
    SUM(KBPerSec_Total) AS KBPerSec_Total,
    MIN(IOPerSec_Min) AS IOPerSec_Min,
    MAX(IOPerSec_Max) AS IOPerSec_Max,
    AVG(IOPerSec_Avg) AS IOPerSec_Avg,
    SUM(IO_Total) AS IO_Total,
    60 AS Seconds
FROM Perf_DiskIO
WHERE Seconds = 5 AND Timestamp < '$oneHourAgo'
GROUP BY strftime('%Y-%m-%d %H:%M:00', Timestamp), Host, Drive;
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $aggDiskQuery
        Write-Verbose "$MyTag Aggregated Disk I/O metrics"

        $deleteDiskQuery = "DELETE FROM Perf_DiskIO WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';"
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $deleteDiskQuery

        # Aggregate Network
        $aggNetQuery = @"
INSERT INTO Network (Timestamp, Host, AdapterName, AdapterType, VendorName, MACAddress, IngressKB_Min, IngressKB_Max, IngressKB_Avg, IngressKB_Total, EgressKB_Min, EgressKB_Max, EgressKB_Avg, EgressKB_Total, Seconds)
SELECT
    strftime('%Y-%m-%d %H:%M:00', Timestamp) AS MinuteTimestamp,
    Host,
    AdapterName,
    MAX(AdapterType) AS AdapterType,
    MAX(VendorName) AS VendorName,
    MAX(MACAddress) AS MACAddress,
    MIN(IngressKB_Min) AS IngressKB_Min,
    MAX(IngressKB_Max) AS IngressKB_Max,
    AVG(IngressKB_Avg) AS IngressKB_Avg,
    SUM(IngressKB_Total) AS IngressKB_Total,
    MIN(EgressKB_Min) AS EgressKB_Min,
    MAX(EgressKB_Max) AS EgressKB_Max,
    AVG(EgressKB_Avg) AS EgressKB_Avg,
    SUM(EgressKB_Total) AS EgressKB_Total,
    60 AS Seconds
FROM Network
WHERE Seconds = 5 AND Timestamp < '$oneHourAgo'
GROUP BY strftime('%Y-%m-%d %H:%M:00', Timestamp), Host, AdapterName;
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $aggNetQuery
        Write-Verbose "$MyTag Aggregated Network metrics"

        $deleteNetQuery = "DELETE FROM Network WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';"
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $deleteNetQuery

        $Global:PSWebServer.Metrics.JobState.Last60sAggregation = $now
        Write-Verbose "$MyTag Aggregation complete"
    }
    catch {
        Write-Warning "$MyTag Aggregation failed: $($_.Exception.Message)"
    }
}

function Invoke-MetricsCleanup {
    <#
    .SYNOPSIS
        Cleans old metrics data with 7-day retention (new architecture)
    .DESCRIPTION
        Deletes 5-second data older than 1 hour and 60-second data older than 7 days.
        Runs daily at 2:00 AM or can be forced.
    #>
    param(
        [switch]$Force
    )

    $MyTag = '[Invoke-MetricsCleanup]'

    $now = Get-Date
    $lastCleanup = $Global:PSWebServer.Metrics.JobState.LastCleanup

    # Run daily unless forced
    if (-not $Force -and $lastCleanup -and ($now - $lastCleanup).TotalHours -lt 24) {
        return
    }

    # Only run at 2:00 AM unless forced
    if (-not $Force -and $now.Hour -ne 2) {
        return
    }

    Write-Verbose "$MyTag Starting cleanup"

    try {
        # Delete 5-second data older than 1 hour
        $oneHourAgo = $now.AddHours(-1).ToString('yyyy-MM-dd HH:mm:ss')
        $delete5sQuery = @"
DELETE FROM Perf_CPUCore WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';
DELETE FROM Perf_MemoryUsage WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';
DELETE FROM Perf_DiskIO WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';
DELETE FROM Network WHERE Seconds = 5 AND Timestamp < '$oneHourAgo';
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $delete5sQuery
        Write-Verbose "$MyTag Deleted 5-second data older than 1 hour"

        # Delete 60-second data older than 7 days
        $sevenDaysAgo = $now.AddDays(-7).ToString('yyyy-MM-dd HH:mm:ss')
        $delete60sQuery = @"
DELETE FROM Perf_CPUCore WHERE Seconds = 60 AND Timestamp < '$sevenDaysAgo';
DELETE FROM Perf_MemoryUsage WHERE Seconds = 60 AND Timestamp < '$sevenDaysAgo';
DELETE FROM Perf_DiskIO WHERE Seconds = 60 AND Timestamp < '$sevenDaysAgo';
DELETE FROM Network WHERE Seconds = 60 AND Timestamp < '$sevenDaysAgo';
"@
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query $delete60sQuery
        Write-Verbose "$MyTag Deleted 60-second data older than 7 days"

        # Vacuum to reclaim space
        Invoke-PSWebSQLiteNonQuery -File 'pswebhost_perf.db' -Query "VACUUM;"
        Write-Verbose "$MyTag Database vacuumed"

        $Global:PSWebServer.Metrics.JobState.LastCleanup = $now
        Write-Verbose "$MyTag Cleanup complete"
    }
    catch {
        Write-Warning "$MyTag Cleanup failed: $($_.Exception.Message)"
    }
}

#endregion

#region Maintenance Function

function Invoke-MetricJobMaintenance {
    <#
    .SYNOPSIS
        Main maintenance function - collects metrics, aggregates, and persists to CSV
    .DESCRIPTION
        This function should be called periodically (every 5 seconds) to:
        1. Collect a new metrics snapshot
        2. Update current metrics
        3. Add to samples collection
        4. Aggregate samples older than 1 minute into per-minute records
        5. Write aggregated data to CSV
        6. Clean up old samples and CSV files
    #>
    param(
        [switch]$CollectOnly,
        [switch]$AggregateOnly,
        [switch]$PersistOnly
    )

    $MyTag = '[Invoke-MetricJobMaintenance]'

    # Ensure metrics system is initialized
    if (-not $Global:PSWebServer.Metrics) {
        Initialize-PSWebMetrics
    }

    try {
        # 1. Collect new snapshot
        if (-not $AggregateOnly -and -not $PersistOnly) {
            $snapshot = Get-SystemMetricsSnapshot
            Update-CurrentMetrics -Snapshot $snapshot
            Add-MetricsSample -Snapshot $snapshot
        }

        # 2. Aggregate old samples
        if (-not $CollectOnly -and -not $PersistOnly) {
            Invoke-MetricsAggregation
        }

        # 3. Persist to CSV (legacy)
        if (-not $CollectOnly -and -not $AggregateOnly) {
            Write-MetricsToCsv

            # Clean up old files once per hour
            $lastCleanup = $Global:PSWebServer.Metrics.JobState.LastCsvCleanup
            if (-not $lastCleanup -or ((Get-Date) - $lastCleanup).TotalHours -ge 1) {
                Remove-OldMetricsCsvFiles -RetentionDays $script:MetricsConfig.CsvRetentionDays
                $Global:PSWebServer.Metrics.JobState.LastCsvCleanup = Get-Date
            }
        }

        # 4. New SQLite pipeline (runs at specific intervals)
        if (-not $CollectOnly -and -not $AggregateOnly) {
            # Write to interim CSV files (every 1 minute at :00 seconds)
            Write-MetricsToInterimCsv

            # Move CSV to SQLite (every 5 minutes at :00-:10 seconds)
            Move-CsvToSqlite

            # Aggregate 5s → 60s (every 15 minutes)
            Invoke-Metrics60sAggregation

            # Cleanup old data (daily at 2:00 AM)
            Invoke-MetricsCleanup
        }
    }
    catch {
        $errorMsg = "$MyTag Error: $($_.Exception.Message)"
        Write-Warning $errorMsg
        if ($Global:PSWebServer.Metrics.JobState.Errors.Count -lt 100) {
            [void]$Global:PSWebServer.Metrics.JobState.Errors.Add(@{
                Timestamp = Get-Date
                Message = $_.Exception.Message
            })
        }
    }
}

#endregion

#region Query Functions

function Get-CurrentMetrics {
    <#
    .SYNOPSIS
        Returns the current/latest metrics snapshot
    #>

    if (-not $Global:PSWebServer.Metrics -or -not $Global:PSWebServer.Metrics.Current.Timestamp) {
        # No metrics collected yet, collect now
        Invoke-MetricJobMaintenance -CollectOnly
    }

    return $Global:PSWebServer.Metrics.Current
}

function Get-MetricsHistory {
    <#
    .SYNOPSIS
        Returns historical metrics data
    #>
    param(
        [ValidateSet('Samples', 'Aggregated', 'Csv')]
        [string]$Source = 'Aggregated',
        [int]$Minutes = 60,
        [datetime]$StartDate,
        [datetime]$EndDate
    )

    if (-not $Global:PSWebServer.Metrics) {
        return @()
    }

    switch ($Source) {
        'Samples' {
            $cutoff = (Get-Date).AddMinutes(-$Minutes)
            return @($Global:PSWebServer.Metrics.Samples | Where-Object {
                [datetime]::Parse($_.Timestamp) -ge $cutoff
            })
        }
        'Aggregated' {
            $cutoff = (Get-Date).AddMinutes(-$Minutes)
            return @($Global:PSWebServer.Metrics.Aggregated | Where-Object {
                [datetime]::Parse($_.MinuteTimestamp) -ge $cutoff
            })
        }
        'Csv' {
            $start = if ($StartDate) { $StartDate } else { (Get-Date).AddMinutes(-$Minutes) }
            $end = if ($EndDate) { $EndDate } else { Get-Date }
            return Get-MetricsFromCsv -StartDate $start -EndDate $end
        }
    }
}

function Get-MetricsJobStatus {
    <#
    .SYNOPSIS
        Returns the status of the metrics collection job
    #>

    if (-not $Global:PSWebServer.Metrics) {
        return @{ Initialized = $false }
    }

    return @{
        Initialized = $true
        SamplesCount = $Global:PSWebServer.Metrics.Samples.Count
        AggregatedCount = $Global:PSWebServer.Metrics.Aggregated.Count
        LastCollection = $Global:PSWebServer.Metrics.JobState.LastCollection
        LastAggregation = $Global:PSWebServer.Metrics.JobState.LastAggregation
        LastCsvWrite = $Global:PSWebServer.Metrics.JobState.LastCsvWrite
        ErrorCount = $Global:PSWebServer.Metrics.JobState.Errors.Count
        Config = $script:MetricsConfig
    }
}

#endregion

function Stop-PSWebMetrics {
    <#
    .SYNOPSIS
        Stops the metrics collection system
    .DESCRIPTION
        Stops the timer, writes final data to CSV, and cleans up
    #>

    $MyTag = '[Stop-PSWebMetrics]'

    try {
        # Stop and dispose timer
        if ($Global:PSWebServer.MetricsTimer) {
            $Global:PSWebServer.MetricsTimer.Stop()
            $Global:PSWebServer.MetricsTimer.Dispose()
            $Global:PSWebServer.MetricsTimer = $null
            Write-Host "$MyTag Metrics timer stopped"
        }

        # Unregister event
        Get-EventSubscriber -SourceIdentifier "PSWebHost_MetricsTimer" -ErrorAction SilentlyContinue |
            Unregister-Event -ErrorAction SilentlyContinue

        # Final aggregation and CSV write
        if ($Global:PSWebServer.Metrics) {
            Invoke-MetricsAggregation -Force
            Write-MetricsToCsv -Force
            Write-Host "$MyTag Final metrics written to CSV"
        }

        # Mark as not running
        if ($Global:PSWebServer.Metrics.JobState) {
            $Global:PSWebServer.Metrics.JobState.Running = $false
        }

        Write-Host "$MyTag Metrics system stopped"
    }
    catch {
        Write-Warning "$MyTag Error stopping metrics: $($_.Exception.Message)"
    }
}

# Export functions
Export-ModuleMember -Function @(
    'Initialize-PSWebMetrics',
    'Stop-PSWebMetrics',
    'Get-SystemMetricsSnapshot',
    'Update-CurrentMetrics',
    'Add-MetricsSample',
    'Invoke-MetricsAggregation',
    'Write-MetricsToCsv',
    'Remove-OldMetricsCsvFiles',
    'Get-MetricsFromCsv',
    'Invoke-MetricJobMaintenance',
    'Get-CurrentMetrics',
    'Get-MetricsHistory',
    'Get-MetricsJobStatus'
)
