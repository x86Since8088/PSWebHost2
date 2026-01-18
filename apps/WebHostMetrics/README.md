# WebHost Metrics

Real-time system performance metrics collection, aggregation, visualization, and historical analysis for PSWebHost.

## Overview

WebHost Metrics provides comprehensive system monitoring with:
- **Real-time collection** of CPU, memory, disk, and network metrics
- **High-frequency sampling** (5-second intervals)
- **Historical data retention** (24 hours in-memory, 30 days on disk)
- **Interactive visualization** dashboard with charts
- **CSV export** for long-term storage and analysis
- **Background job management** for reliable collection

## Features

### Metrics Collection

- **CPU Monitoring**
  - Per-core usage percentages
  - Total CPU utilization
  - Average CPU across all cores
  - CPU temperature (when available)

- **Memory Monitoring**
  - Total physical memory
  - Used memory
  - Free memory
  - Memory usage percentage

- **Disk I/O**
  - Read/write operations per second
  - Bytes read/written per second
  - Per-drive statistics

- **Network Traffic**
  - Bytes sent/received per second
  - Packets sent/received per second
  - Per-interface statistics

### Data Storage

- **In-Memory Storage**
  - Raw samples: 5-second intervals, last hour
  - Aggregated data: 1-minute intervals, last 24 hours
  - Thread-safe synchronized collections

- **Disk Storage**
  - CSV files with timestamps in filename
  - Separate files per metric type
  - Automatic cleanup after retention period
  - Format: `Perf_CPUCore_YYYY-MM-DD_HH-MM-SS.csv`

### API Endpoints

All endpoints require authentication (`authenticated` role).

#### GET `/apps/WebHostMetrics/api/v1/metrics`

Current system metrics snapshot.

**Response:**
```json
{
  "status": "success",
  "timestamp": "2026-01-16 13:15:00",
  "hostname": "SERVERNAME",
  "metrics": {
    "cpu": {
      "totalPercent": 25.3,
      "avgPercent": 24.8,
      "cores": [22.1, 25.4, 26.8, 24.9],
      "coreCount": 4,
      "temperature": 65.5
    },
    "memory": {
      "totalGB": 16.0,
      "usedGB": 8.2,
      "freeGB": 7.8,
      "percentUsed": 51.3
    },
    "disk": { ... },
    "network": { ... }
  }
}
```

#### GET `/apps/WebHostMetrics/api/v1/metrics?action=realtime&metric=cpu&starting=...`

Real-time metrics from interim CSV files.

**Parameters:**
- `action=realtime` - Fetch real-time data
- `metric` - Metric type: `cpu`, `memory`, `disk`, `network`
- `starting` - ISO 8601 timestamp (e.g., `2026-01-16T19:10:00Z`)

**Response:**
```json
{
  "status": "success",
  "startTime": "2026-01-16T13:10:00-06:00",
  "endTime": "2026-01-16T13:15:00-06:00",
  "granularity": "5s",
  "data": {
    "Perf_CPUCore": [
      { "Timestamp": "2026-01-16T13:10:00", "Core0": 25.3, "Core1": 24.8, ... },
      ...
    ]
  }
}
```

#### GET `/apps/WebHostMetrics/api/v1/metrics/history?metric=cpu&timerange=5m`

Historical metrics aggregated data.

**Parameters:**
- `metric` - Metric type
- `timerange` - Time range: `5m`, `15m`, `30m`, `1h`, `4h`, `12h`, `24h`

## UI Component

### Server Metrics Dashboard

Access via: `/api/v1/ui/elements/server-heatmap`

**Features:**
- Real-time CPU, memory, disk, and network charts
- Per-core CPU usage visualization
- Interactive time range selection
- Auto-refresh with pause capability
- Responsive layout
- Color-coded status indicators

**Layout Integration:**
```json
{
  "server-heatmap": {
    "Type": "Heatmap",
    "Title": "Server Metrics",
    "componentPath": "/apps/WebHostMetrics/public/elements/server-heatmap/component.js"
  }
}
```

## Architecture

### Module Structure

```
apps/WebHostMetrics/
├── app.yaml                          # App manifest
├── menu.yaml                         # Menu integration
├── README.md                         # This file
├── Restart-MetricsCollection.ps1    # Utility script
│
├── modules/
│   └── PSWebHost_Metrics/
│       └── PSWebHost_Metrics.psm1   # Core metrics module
│
├── routes/api/v1/
│   ├── metrics/
│   │   ├── get.ps1                  # Main metrics API
│   │   ├── get.security.json
│   │   └── history/
│   │       ├── get.ps1              # Historical metrics API
│   │       └── get.security.json
│   └── ui/elements/server-heatmap/
│       ├── get.ps1                  # Component metadata endpoint
│       └── get.security.json
│
├── public/elements/
│   └── server-heatmap/
│       └── component.js             # React dashboard component
│
└── tests/twin/
    └── (test files)
```

### Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     Background Job                               │
│  PSWebHost_MetricsCollection (runs every 5 seconds)             │
│                                                                  │
│  1. Get-SystemMetricsSnapshot                                   │
│  2. Update-MetricsStorage (in-memory + CSV)                     │
│  3. Invoke-MetricJobMaintenance (cleanup, aggregation)          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
        ┌──────────────────────────────────────────┐
        │        Data Storage                       │
        ├──────────────────────────────────────────┤
        │  In-Memory:                              │
        │    - $Global:PSWebServer.Metrics.Current │
        │    - $Global:PSWebServer.Metrics.Samples │
        │    - $Global:PSWebServer.Metrics.Aggregated│
        │                                          │
        │  Disk:                                   │
        │    - PsWebHost_Data/metrics/*.csv        │
        └──────────────────────────────────────────┘
                              ↓
        ┌──────────────────────────────────────────┐
        │         API Endpoints                     │
        │  /apps/WebHostMetrics/api/v1/metrics     │
        └──────────────────────────────────────────┘
                              ↓
        ┌──────────────────────────────────────────┐
        │      UI Component (server-heatmap)        │
        │  Real-time charts and visualizations     │
        └──────────────────────────────────────────┘
```

### Background Job

The metrics collection job runs continuously:

```powershell
# Started in system/init.ps1
$Global:PSWebServer.MetricsJob = Start-Job -Name "PSWebHost_MetricsCollection" -ScriptBlock {
    # Import module
    Import-Module PSWebHost_Metrics -Force

    # Collection loop (every 5 seconds)
    while (-not $MetricsState.ShouldStop) {
        Invoke-MetricJobMaintenance
        Start-Sleep -Seconds 5
    }
}
```

**Job Management:**
```powershell
# Check job status
Get-Job -Name "PSWebHost_MetricsCollection"

# View recent output
Receive-Job -Job $Global:PSWebServer.MetricsJob

# Restart job
.\apps\WebHostMetrics\Restart-MetricsCollection.ps1
```

## Configuration

Edit `apps/WebHostMetrics/app.yaml`:

```yaml
config:
  # Collection interval
  sampleIntervalSeconds: 5

  # In-memory retention
  retentionHours: 24

  # CSV file retention
  csvRetentionDays: 30

  # Storage location
  metricsDirectory: PsWebHost_Data/metrics
```

## Troubleshooting

### No Data Appearing

1. **Check if job is running:**
   ```powershell
   Get-Job -Name "PSWebHost_MetricsCollection"
   # Should show State: Running
   ```

2. **Check for recent CSV files:**
   ```powershell
   Get-ChildItem PsWebHost_Data/metrics/*.csv |
       Sort-Object LastWriteTime -Descending |
       Select-Object -First 5
   ```

3. **Check job errors:**
   ```powershell
   $Global:PSWebServer.Metrics.JobState.Errors
   ```

4. **Restart collection:**
   ```powershell
   .\apps\WebHostMetrics\Restart-MetricsCollection.ps1 -Force
   ```

### Job Crashed or Stopped

**Symptoms:**
- No new CSV files
- API returns empty data
- Dashboard shows no metrics

**Fix:**
```powershell
# Restart PSWebHost server (recommended)
# Or manually restart job:
.\apps\WebHostMetrics\Restart-MetricsCollection.ps1 -Force
```

### High Memory Usage

The in-memory storage is bounded:
- Raw samples: ~12 data points per minute × 60 minutes = ~720 samples
- Aggregated: 60 aggregated points (1 per minute for 1 hour)

If memory usage is high:
1. Reduce `retentionHours` in app.yaml
2. Check for CSV file accumulation (should auto-cleanup)
3. Verify `csvRetentionDays` cleanup is working

### Missing Metrics

Some metrics require elevated permissions:
- **CPU Temperature**: Requires WMI access (may not work on all systems)
- **Disk I/O**: Requires performance counter access
- **Network**: Requires network adapter access

Check Windows Event Log for permission errors.

## Performance Impact

**CPU Usage:**
- Collection: ~1-2% per collection cycle (5 seconds)
- Background job: Minimal when idle
- Peak: During CSV writes (~2-3% spike)

**Memory Usage:**
- Module: ~10-20 MB
- In-memory storage: ~5-10 MB
- Background job: ~20-30 MB

**Disk Usage:**
- CSV files: ~1-2 MB per day
- 30-day retention: ~30-60 MB

## Integration

### Add to Layout

Update `public/layout.json`:

```json
{
  "elements": {
    "server-heatmap": {
      "Type": "Heatmap",
      "Title": "Server Metrics",
      "componentPath": "/apps/WebHostMetrics/public/elements/server-heatmap/component.js"
    }
  },
  "layout": {
    "mainPane": {
      "content": ["server-heatmap"]
    }
  }
}
```

### Programmatic Access

```powershell
# Get current metrics
$current = $Global:PSWebServer.Metrics.Current

# Access specific metric
$cpuPercent = $current.Cpu.TotalPercent
$memoryUsedGB = $current.Memory.UsedGB

# Get last N samples
$recent = $Global:PSWebServer.Metrics.Samples | Select-Object -Last 12  # Last minute

# Get aggregated data
$aggregated = $Global:PSWebServer.Metrics.Aggregated  # Last hour
```

### Custom Alerts

```powershell
# Example: Alert on high CPU
if ($Global:PSWebServer.Metrics.Current.Cpu.TotalPercent -gt 90) {
    Write-PSWebHostLog -Severity Warning -Category Metrics -Message "High CPU usage: $($Global:PSWebServer.Metrics.Current.Cpu.TotalPercent)%"
}
```

## Development

### Adding New Metrics

1. Update `Get-SystemMetricsSnapshot` in `PSWebHost_Metrics.psm1`
2. Add new CSV table structure in `Update-MetricsStorage`
3. Update API endpoint to expose new metric
4. Update UI component to visualize

### Testing

Run twin tests:
```powershell
Invoke-Pester -Path apps/WebHostMetrics/tests/twin/
```

### Debugging

Enable verbose logging:
```powershell
$VerbosePreference = 'Continue'
Import-Module apps/WebHostMetrics/modules/PSWebHost_Metrics -Force -Verbose
```

## Dependencies

- **PowerShell 5.1+**
- **Windows Performance Counters**
- **WMI/CIM access** (for CPU temperature)
- **PSWebHost Core** modules:
  - PSWebHost_Support
  - PSWebHost_Database
  - PSWebHost_Authentication

## Version History

### 1.0.0 (2026-01-16)
- Initial release as standalone app
- Migrated from core `modules/PSWebHost_Metrics`
- Consolidated API endpoints under app route prefix
- Updated UI component for app integration
- Added comprehensive documentation

## License

Part of PSWebHost project.

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review server logs in `PsWebHost_Data/Logs/`
3. Check background job errors: `$Global:PSWebServer.Metrics.JobState.Errors`
4. Restart collection: `.\apps\WebHostMetrics\Restart-MetricsCollection.ps1 -Force`
