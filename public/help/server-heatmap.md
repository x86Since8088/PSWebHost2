# Server Load Heatmap

The Server Heatmap card provides real-time system performance metrics with historical tracking and persistence.

## Features

- **Real-time Metrics**: CPU, memory, disk, network, and process information
- **Color-coded Visualization**: Quick identification of resource usage levels
- **Historical Data**: View aggregated performance history (up to 24 hours in memory, 30 days in CSV)
- **Background Collection**: Metrics collected every 5 seconds by a dedicated background job
- **Pause/Resume**: Toggle auto-refresh to pause data updates
- **History View**: Click the chart icon to view historical metrics

## Metrics Displayed

### CPU
- Per-core utilization percentages
- Total/average CPU usage
- Core count display

### Memory
- Total, used, and free memory in GB
- Percentage used with progress bar

### Disk
- Per-drive usage statistics
- Total, used, and free space in GB

### System Info
- System uptime (days/hours)
- Process count
- Thread count
- Handle count

### Network
- Per-interface bandwidth (KB/s)
- Top 3 most active interfaces

### Top Processes
- Top 5 processes by CPU time
- Process name, CPU time, and memory usage

## Color Legend

| Color | Range | Status |
|-------|-------|--------|
| Green | < 50% | Normal |
| Yellow | 50-75% | Elevated |
| Orange | 75-90% | Warning |
| Red | > 90% | Critical |

## Data Collection Architecture

The metrics system uses a background timer-based collection:

1. **Samples** (5-second intervals): Raw metrics stored in memory for 1 hour (720 samples max)
2. **Aggregated** (per-minute): Samples collapsed into min/avg/max values, stored for 24 hours
3. **CSV Persistence**: Per-minute data written to daily CSV files, retained for 30 days

### Global Storage

Metrics are stored in `$Global:PSWebServer.Metrics`:
- `Current`: Latest snapshot
- `Samples`: Raw 5-second samples (last hour)
- `Aggregated`: Per-minute aggregations (last 24 hours)

### CSV Storage

Daily metrics files are stored in:
```
PsWebHost_Data\metrics\metrics_YYYY-MM-DD.csv
```

## API Endpoints

### Current Metrics
```
GET /api/v1/ui/elements/server-heatmap
```

### Historical Data
```
GET /api/v1/ui/elements/server-heatmap?history=60
```
Returns aggregated metrics for the last N minutes (max 1440 = 24 hours)

### Metrics API
```
GET /api/v1/metrics                    # Current metrics
GET /api/v1/metrics?action=status      # Collection job status
GET /api/v1/metrics?action=history&minutes=60    # Aggregated history
GET /api/v1/metrics?action=samples&minutes=5     # Raw samples
GET /api/v1/metrics?action=csv&start=2024-01-01  # CSV data
```

## Troubleshooting

### No Data Displayed
1. Check if the metrics timer is running: `$Global:PSWebServer.MetricsTimer.Enabled`
2. Verify metrics are being collected: `$Global:PSWebServer.Metrics.JobState.LastCollection`
3. Check for collection errors: `$Global:PSWebServer.Metrics.JobState.Errors`

### Threads Showing as Error
The thread count uses `Win32_PerfFormattedData_PerfOS_System` which may require administrative permissions. If unavailable, an estimate is provided.

### CPU Cores Not Updating
The CPU counter `\Processor(*)\% Processor Time` requires the Performance Counter service to be running. Check Windows Event Log for performance counter errors.

### High Latency
The metrics collection runs in the main runspace. If collection takes too long, it may indicate:
- WMI/CIM service issues
- High system load affecting counter queries
- Network interface enumeration delays

## Configuration

Metrics system configuration (set during initialization):
- **SampleIntervalSeconds**: 5 (collection frequency)
- **RetentionHours**: 24 (in-memory aggregation retention)
- **CsvRetentionDays**: 30 (CSV file retention)

To modify, update the call in `system/init.ps1`:
```powershell
Initialize-PSWebMetrics -SampleIntervalSeconds 5 -RetentionHours 24 -CsvRetentionDays 30
```
