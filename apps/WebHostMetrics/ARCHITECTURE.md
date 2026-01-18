# WebHost Metrics - Architecture Documentation

## System Overview

WebHost Metrics is a comprehensive system monitoring solution for PSWebHost, providing real-time and historical performance data collection, aggregation, storage, and visualization.

## Core Components

### 1. Metrics Collection Module
**Location:** `apps/WebHostMetrics/modules/PSWebHost_Metrics/PSWebHost_Metrics.psm1`

**Purpose:** PowerShell module providing all metrics collection, storage, and maintenance functions.

**Key Functions:**

- `Initialize-PSWebMetrics` - Sets up global storage structures and configuration
- `Get-SystemMetricsSnapshot` - Collects current system metrics
- `Update-MetricsStorage` - Writes metrics to in-memory storage and CSV files
- `Invoke-MetricJobMaintenance` - Periodic cleanup and aggregation
- `Get-MetricsHistory` - Retrieves historical data
- `Get-CurrentMetrics` - Returns current metrics snapshot
- `Get-MetricsJobStatus` - Job health and statistics

### 2. Background Collection Job
**Location:** Started in `system/init.ps1` (lines 798-850)

**Purpose:** Continuously collects metrics in a PowerShell background job.

**Execution Flow:**
```
Start-Job "PSWebHost_MetricsCollection"
  ↓
Import-Module PSWebHost_Metrics
  ↓
Loop (every 5 seconds):
  ├─ Check ShouldStop flag
  ├─ Check IsExecuting lock
  ├─ Set execution lock
  ├─ Invoke-MetricJobMaintenance
  │   ├─ Get-SystemMetricsSnapshot
  │   ├─ Update-MetricsStorage
  │   └─ Cleanup old data
  ├─ Release execution lock
  └─ Sleep 5 seconds
```

**State Management:**
```powershell
$Global:PSWebServer.Metrics.JobState = @{
    Running = $true/$false
    ShouldStop = $true/$false  # Graceful shutdown signal
    IsExecuting = $true/$false  # Prevents concurrent execution
    ExecutionStartTime = [DateTime]
    LastCollection = [DateTime]
    LastAggregation = [DateTime]
    LastCsvWrite = [DateTime]
    Errors = [ArrayList]  # Last 100 errors
}
```

### 3. Data Storage System

#### In-Memory Storage
**Location:** `$Global:PSWebServer.Metrics`

**Structure:**
```powershell
$Global:PSWebServer.Metrics = @{
    # Latest metrics snapshot
    Current = @{
        Timestamp = [DateTime]
        Hostname = [String]
        Cpu = @{ TotalPercent, AvgPercent, Cores[], CoreCount, Temperature }
        Memory = @{ TotalGB, UsedGB, FreeGB, PercentUsed }
        Disk = @{ ... }
        Network = @{ ... }
        System = @{ ... }
        Uptime = @{ ... }
        TopProcessesCPU = [Array]
        TopProcessesMem = [Array]
    }

    # Raw 5-second samples (last hour, ~720 items)
    Samples = [ArrayList::Synchronized]

    # Aggregated 1-minute data (last 24 hours, ~1440 items)
    Aggregated = [ArrayList::Synchronized]

    # Job state (see above)
    JobState = @{ ... }

    # Configuration
    Config = @{
        SampleIntervalSeconds = 5
        RetentionHours = 24
        CsvRetentionDays = 30
        MetricsDirectory = "PsWebHost_Data/metrics"
    }
}
```

**Thread Safety:**
- `Current` - Synchronized hashtable (atomic updates)
- `Samples` - ArrayList.Synchronized (thread-safe collection)
- `Aggregated` - ArrayList.Synchronized (thread-safe collection)
- `JobState` - Synchronized hashtable (shared with background job)

#### CSV Storage
**Location:** `PsWebHost_Data/metrics/`

**File Naming Convention:**
```
{MetricType}_{YYYY-MM-DD}_{HH-MM-SS}.csv
```

**Examples:**
- `Perf_CPUCore_2026-01-16_13-15-00.csv`
- `Perf_MemoryUsage_2026-01-16_13-15-00.csv`
- `Perf_DiskIO_2026-01-16_13-15-00.csv`
- `Network_2026-01-16_13-15-00.csv`

**CSV Format (Perf_CPUCore):**
```csv
Timestamp,Core0,Core1,Core2,Core3,Total,Average
2026-01-16T13:15:00,22.1,25.4,26.8,24.9,24.8,24.8
2026-01-16T13:15:05,23.2,24.1,25.9,23.8,24.3,24.3
```

**Retention:**
- Automatic cleanup of files older than `csvRetentionDays` (default: 30)
- Cleanup runs during `Invoke-MetricJobMaintenance`
- Prevents disk space exhaustion

### 4. API Endpoints

#### Main Metrics Endpoint
**Location:** `apps/WebHostMetrics/routes/api/v1/metrics/get.ps1`

**Routes:**
- `/apps/WebHostMetrics/api/v1/metrics` - Current snapshot
- `/apps/WebHostMetrics/api/v1/metrics?action=status` - Job status
- `/apps/WebHostMetrics/api/v1/metrics?action=history` - In-memory history
- `/apps/WebHostMetrics/api/v1/metrics?action=samples` - Raw samples
- `/apps/WebHostMetrics/api/v1/metrics?action=csv` - CSV data
- `/apps/WebHostMetrics/api/v1/metrics?action=realtime` - Real-time CSV streaming

**Request Flow (realtime action):**
```
Client Request:
  GET /apps/WebHostMetrics/api/v1/metrics?action=realtime&metric=cpu&starting=2026-01-16T19:10:00Z
    ↓
Parse query parameters:
  - action = realtime
  - metric = cpu
  - starting = ISO 8601 timestamp
    ↓
Scan CSV directory:
  PsWebHost_Data/metrics/*.csv
    ↓
Filter files by:
  - Metric type (Perf_CPUCore for cpu)
  - Timestamp in filename >= starting
    ↓
Read matching CSV files:
  Import-Csv -Path $file.FullName
    ↓
Group by table type:
  $data['Perf_CPUCore'] = [Array of CSV records]
    ↓
Return JSON response:
  {
    status: "success",
    startTime: "...",
    endTime: "...",
    granularity: "5s",
    data: { ... }
  }
```

#### Historical Metrics Endpoint
**Location:** `apps/WebHostMetrics/routes/api/v1/metrics/history/get.ps1`

**Purpose:** Returns aggregated historical data for time-series visualization.

**Query Parameters:**
- `metric` - Metric type (cpu, memory, disk, network)
- `timerange` - Duration (5m, 15m, 30m, 1h, 4h, 12h, 24h)
- `delay` - Refresh delay in seconds (for auto-updating charts)

### 5. UI Component
**Location:** `apps/WebHostMetrics/public/elements/server-heatmap/component.js`

**Technology:** React component (JSX transformed via Babel)

**Component Structure:**
```javascript
ServerHeatmapCard
  ├─ useState hooks (metrics, loading, error states)
  ├─ useEffect hooks (polling, data fetching)
  ├─ useRef hooks (polling timer management)
  │
  ├─ fetchMetrics() - API data retrieval
  │   └─ GET /apps/WebHostMetrics/api/v1/metrics?action=realtime
  │
  ├─ UI Sections:
  │   ├─ Header (title, time range selector, refresh controls)
  │   ├─ CPU Section
  │   │   ├─ Per-core usage bars
  │   │   ├─ Total/Average displays
  │   │   └─ UPlot chart (historical)
  │   ├─ Memory Section
  │   │   ├─ Usage bar
  │   │   ├─ Used/Free/Total displays
  │   │   └─ UPlot chart (historical)
  │   ├─ Disk I/O Section
  │   │   ├─ Read/Write rates
  │   │   └─ UPlot chart (historical)
  │   └─ Network Section
  │       ├─ Sent/Received rates
  │       └─ UPlot chart (historical)
  │
  └─ Auto-refresh timer (5-second interval)
```

**UPlot Integration:**
```javascript
// Loads uplot component with metrics data
React.createElement(window.cardComponents.uplot, {
    element: {
        url: `/api/v1/ui/elements/uplot?source=/apps/WebHostMetrics/api/v1/metrics/history&metric=cpu&timerange=5m&delay=5&title=CPU Usage&ylabel=Usage %&height=200`
    }
})
```

**State Management:**
```javascript
const [metrics, setMetrics] = useState(null);  // Current metrics data
const [loading, setLoading] = useState(true);   // Loading state
const [autoRefresh, setAutoRefresh] = useState(true);  // Polling enabled
const [timeRange, setTimeRange] = useState('5m');  // Time range selection
const pollingRef = useRef(null);  // Timer reference for cleanup
```

## Data Flow Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                   Background Collection Job                       │
│                 (Every 5 seconds, continuously)                  │
└──────────────────────────────────────────────────────────────────┘
                              ↓
            ┌─────────────────────────────────────┐
            │  Get-SystemMetricsSnapshot          │
            │  - Query performance counters       │
            │  - Get WMI/CIM data                 │
            │  - Calculate derived metrics        │
            └─────────────────────────────────────┘
                              ↓
            ┌─────────────────────────────────────┐
            │  Update-MetricsStorage               │
            │  1. Update $Global:..Metrics.Current│
            │  2. Add to Samples array            │
            │  3. Write to CSV files              │
            │  4. Aggregate per-minute data       │
            └─────────────────────────────────────┘
                              ↓
   ┌──────────────────────────────────────────────────────┐
   │              Storage Layers                           │
   ├──────────────────────────────────────────────────────┤
   │  In-Memory (Fast)              │  Disk (Persistent)   │
   │  - Current snapshot            │  - CSV files         │
   │  - Samples (last hour)         │  - Timestamped       │
   │  - Aggregated (last 24h)       │  - Auto-cleanup      │
   └──────────────────────────────────────────────────────┘
                              ↓
            ┌─────────────────────────────────────┐
            │      API Endpoints                   │
            │  /apps/WebHostMetrics/api/v1/metrics│
            │  - action=realtime (CSV files)       │
            │  - action=history (in-memory)        │
            │  - action=status (job status)        │
            └─────────────────────────────────────┘
                              ↓
            ┌─────────────────────────────────────┐
            │  UI Component (server-heatmap)       │
            │  - Polls API every 5 seconds         │
            │  - Renders real-time charts          │
            │  - Integrates with UPlot             │
            └─────────────────────────────────────┘
```

## Performance Characteristics

### Memory Usage

**In-Memory Storage Bounds:**
```
Samples (last hour at 5s interval):
  12 samples/min × 60 min = 720 samples
  Estimate: ~500 bytes per sample = ~360 KB

Aggregated (last 24 hours at 1min interval):
  60 aggregates/hour × 24 hours = 1440 aggregates
  Estimate: ~800 bytes per aggregate = ~1.15 MB

Current snapshot:
  Single object with all metrics = ~5 KB

Total in-memory: ~1.5 MB (bounded, won't grow indefinitely)
```

### CPU Usage

**Collection Cycle (every 5 seconds):**
- Performance counter queries: 10-20ms
- WMI/CIM queries: 50-100ms
- CSV writes: 5-10ms
- Total: ~100-150ms per cycle
- CPU impact: ~1-2% on modern systems

**Peak CPU During:**
- CSV writes (multiple files): 2-3%
- Aggregation (every minute): 1-2%
- Cleanup (every hour): 1-2%

### Disk I/O

**Write Operations:**
- Per collection cycle: 4-5 CSV files written
- File size: ~500 bytes to 2 KB per file
- Total writes: ~5-10 KB every 5 seconds
- Daily: ~100-200 MB of writes

**Read Operations:**
- API requests read CSV files
- `action=realtime` scans directory and reads matching files
- Typical read: 1-5 files, 5-20 KB total
- Minimal impact with SSD storage

### Network Traffic

**API Response Sizes:**
- Current snapshot: ~2-5 KB JSON
- Realtime data (5 min): ~50-100 KB JSON
- History data (24h aggregated): ~500 KB - 2 MB JSON

**Polling Impact:**
- Server-heatmap polls every 5 seconds
- Per user: ~0.5-1 KB/sec bandwidth
- 10 concurrent users: ~5-10 KB/sec

## Scalability Considerations

### Horizontal Scaling
- Each PSWebHost instance collects its own metrics
- No cross-instance dependencies
- Can monitor multiple servers independently

### Vertical Scaling
- In-memory storage is bounded by retention settings
- CSV files auto-cleanup prevents disk exhaustion
- Background job uses single thread (low CPU footprint)

### Tuning Parameters

**Reduce Memory Usage:**
```yaml
config:
  retentionHours: 12  # Reduce from 24
  sampleIntervalSeconds: 10  # Reduce from 5 (fewer samples)
```

**Reduce Disk Usage:**
```yaml
config:
  csvRetentionDays: 7  # Reduce from 30
```

**Reduce CPU Usage:**
```yaml
config:
  sampleIntervalSeconds: 10  # Increase from 5 (less frequent)
```

## Error Handling

### Collection Errors

**Scenario:** Performance counter unavailable
```powershell
try {
    $cpuCounters = Get-Counter -Counter '\Processor(*)\% Processor Time'
} catch {
    $snapshot.Cpu = @{ Error = $_.Exception.Message; Cores = @(); TotalPercent = 0 }
}
```

**Scenario:** WMI timeout
```powershell
$os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop -OperationTimeoutSec 3
```

### Job Failure Recovery

**Stuck Execution Lock:**
```powershell
if ($MetricsState.IsExecuting) {
    $elapsed = ((Get-Date) - $MetricsState.ExecutionStartTime).TotalSeconds
    if ($elapsed -gt 30) {
        Write-Warning "Force-releasing stuck execution lock after 30 seconds"
        $MetricsState.IsExecuting = $false
    }
}
```

**Error Accumulation:**
```powershell
# Limit error storage to prevent memory bloat
if ($MetricsState.Errors.Count -lt 100) {
    $MetricsState.Errors.Add(@{
        Timestamp = Get-Date
        Error = $_.Exception.Message
    })
}
```

### API Error Handling

**Missing CSV Directory:**
```powershell
if (-not (Test-Path $csvDir)) {
    $response_data = @{
        status = 'success'
        startTime = $starting.ToString('o')
        endTime = (Get-Date).ToString('o')
        granularity = '5s'
        data = @{}  # Empty data, not an error
    }
}
```

**CSV Parse Errors:**
```powershell
$csvData = Import-Csv -Path $file.FullName -ErrorAction SilentlyContinue
if ($csvData) {
    # Process data
}
# Silently skip unparseable files
```

## Security Considerations

### Authentication
- All API endpoints require `authenticated` role
- Security defined in `get.security.json` files
- Session validation via PSWebHost_Authentication module

### Data Privacy
- Metrics contain system-level data only (no user data)
- No sensitive information in CSV files
- CSV files readable only by PSWebHost process owner

### Permissions Required
- **Performance Counters:** Read access (usually available to all users)
- **WMI/CIM:** Read access (may require elevation for some queries)
- **Disk I/O:** Read access to performance counters
- **CSV Directory:** Write access to `PsWebHost_Data/metrics/`

## Monitoring and Diagnostics

### Job Health Check

```powershell
# Check if job is running
$job = Get-Job -Name "PSWebHost_MetricsCollection"
if ($job.State -ne 'Running') {
    Write-Warning "Metrics job is not running: $($job.State)"
}

# Check recent CSV files
$recentFiles = Get-ChildItem PsWebHost_Data/metrics/*.csv |
    Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-2) }

if (-not $recentFiles) {
    Write-Warning "No recent CSV files - collection may have stopped"
}
```

### Error Monitoring

```powershell
# View recent errors
$Global:PSWebServer.Metrics.JobState.Errors |
    Select-Object -Last 10 |
    Format-Table Timestamp, Error -AutoSize
```

### Performance Metrics

```powershell
# Collection statistics
$stats = @{
    LastCollection = $Global:PSWebServer.Metrics.JobState.LastCollection
    SamplesCount = $Global:PSWebServer.Metrics.Samples.Count
    AggregatedCount = $Global:PSWebServer.Metrics.Aggregated.Count
    ErrorCount = $Global:PSWebServer.Metrics.JobState.Errors.Count
}
$stats | Format-List
```

## Future Enhancements

### Potential Improvements

1. **Database Storage**
   - SQLite for structured queries
   - Better aggregation performance
   - SQL-based filtering and analysis

2. **Alerting System**
   - Threshold-based alerts
   - Email/webhook notifications
   - Alert history tracking

3. **Comparative Analysis**
   - Week-over-week comparisons
   - Anomaly detection
   - Baseline establishment

4. **Additional Metrics**
   - Process-level metrics
   - GPU usage (if available)
   - Custom application metrics

5. **Data Export**
   - Excel export
   - PDF reports
   - Grafana integration

6. **Multi-Instance Aggregation**
   - Centralized metrics collection
   - Cross-server dashboards
   - Cluster health monitoring

## References

### PowerShell Cmdlets Used

- `Get-Counter` - Performance counter data
- `Get-CimInstance` - WMI/CIM queries
- `Get-Process` - Process information
- `Import-Csv` / `Export-Csv` - CSV file operations
- `Start-Job` / `Get-Job` - Background job management
- `Measure-Object` - Statistical calculations

### External Dependencies

- **Performance Counters:** Windows built-in
- **WMI/CIM:** Windows built-in
- **PSWebHost Modules:** Internal dependencies
- **React**: UI framework (loaded via SPA)
- **UPlot**: Charting library (UI_Uplot app)

### Related Documentation

- [PSWebHost Apps Framework](../../docs/Apps.md)
- [API Security](../../docs/Security.md)
- [Background Jobs](../../docs/Jobs.md)
- [UI Component System](../../docs/UI-Components.md)
