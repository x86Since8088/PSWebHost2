# Metrics Manager - Unified Data Architecture

## Overview

The `MetricsManager` provides a unified interface for loading historical metrics and polling current metrics, with automatic caching and Chart.js integration.

## Architecture

```mermaid
graph TB
    A[MetricsManager] -->|Historical| B[/api/v1/perfhistorylogs]
    A -->|Current Polling| C[/api/v1/metrics]
    A -->|Cache| D[(IndexedDB)]

    E[CPU Histogram] -->|Request| A
    F[Memory Chart] -->|Request| A
    G[Disk Chart] -->|Request| A

    A -->|Chart.js Format| E
    A -->|Chart.js Format| F
    A -->|Chart.js Format| G

    style A fill:#3b82f6
    style B fill:#22c55e
    style C fill:#f59e0b
    style D fill:#8b5cf6
```

## Two-Tier Data Strategy

### Tier 1: Historical Data (On Demand)
**Source**: `/api/v1/perfhistorylogs`
**Use**: Load past data when user opens chart or changes time range

```javascript
await manager.loadHistorical({
    datasetname: 'system_metrics',
    starttime: '2026-01-04T00:00:00Z',
    endtime: '2026-01-05T00:00:00Z',
    granularity: '5s',
    metrics: ['cpu', 'memory']
});
```

### Tier 2: Current Metrics (Continuous Polling)
**Source**: `/api/v1/metrics`
**Use**: Keep charts updated with latest data every 5 seconds

```javascript
manager.startPolling({
    datasetname: 'current_metrics',
    interval: 5000,
    metrics: ['cpu', 'memory', 'disk', 'network'],
    onUpdate: (data) => {
        console.log('New metrics:', data);
    }
});
```

## Usage Examples

### Example 1: CPU Histogram with Historical + Polling

```javascript
// Initialize manager
const manager = new MetricsManager();

// Load last 24 hours of historical data
const historicalData = await manager.loadHistorical({
    datasetname: 'cpu_history',
    starttime: new Date(Date.now() - 24*60*60*1000).toISOString(),
    endtime: new Date().toISOString(),
    granularity: '5s',
    metrics: ['cpu']
});

// Convert to Chart.js format
const chartData = manager.toChartFormat('cpu_history', 'cpu_cores', {
    includeAverage: true
});

// Create chart
const chart = new Chart(ctx, {
    type: 'line',
    data: chartData,
    options: {
        scales: { x: { type: 'time' } }
    }
});

// Start polling for updates
manager.startPolling({
    datasetname: 'cpu_current',
    interval: 5000,
    metrics: ['cpu'],
    onUpdate: (data) => {
        // Append to chart
        const timestamp = new Date();
        data.metrics.cpu.forEach((core, i) => {
            chart.data.datasets[i].data.push({
                x: timestamp,
                y: core.value
            });
        });
        chart.update('none'); // Update without animation
    }
});
```

### Example 2: Memory Usage Chart

```javascript
const manager = new MetricsManager();

// Load historical memory data
await manager.loadHistorical({
    datasetname: 'memory_history',
    starttime: new Date(Date.now() - 12*60*60*1000).toISOString(),
    granularity: '30s',
    metrics: ['memory']
});

// Get Chart.js format
const chartData = manager.toChartFormat('memory_history', 'memory_used', {
    label: 'Memory Usage %',
    borderColor: '#ef4444',
    backgroundColor: 'rgba(239, 68, 68, 0.2)',
    fill: true
});

// Create chart
const memChart = new Chart(memCtx, {
    type: 'line',
    data: chartData,
    options: {
        scales: {
            x: { type: 'time' },
            y: {
                min: 0,
                max: 100,
                title: { display: true, text: 'Usage %' }
            }
        }
    }
});

// Poll for updates
manager.startPolling({
    datasetname: 'memory_current',
    interval: 5000,
    metrics: ['memory'],
    onUpdate: (data) => {
        const memUsed = data.metrics.memory?.usedPercent || 0;
        memChart.data.datasets[0].data.push({
            x: new Date(),
            y: memUsed
        });

        // Keep only last 1000 points
        if (memChart.data.datasets[0].data.length > 1000) {
            memChart.data.datasets[0].data.shift();
        }

        memChart.update('none');
    }
});
```

### Example 3: Multiple Metrics Dashboard

```javascript
const manager = new MetricsManager();

// Load all metrics for last hour
await manager.loadHistorical({
    datasetname: 'system_dashboard',
    starttime: new Date(Date.now() - 60*60*1000).toISOString(),
    granularity: '5s',
    metrics: ['cpu', 'memory', 'disk', 'network']
});

// Create CPU chart
const cpuData = manager.toChartFormat('system_dashboard', 'cpu_total', {
    label: 'CPU %',
    borderColor: '#3b82f6'
});

// Create Memory chart
const memData = manager.toChartFormat('system_dashboard', 'memory_used', {
    label: 'Memory %',
    borderColor: '#ef4444'
});

// Create Network chart
const netData = manager.toChartFormat('system_dashboard', 'network_bytes', {
    label: 'Network MB/s',
    borderColor: '#22c55e'
});

// Start single polling session for all metrics
manager.startPolling({
    datasetname: 'dashboard_current',
    interval: 5000,
    metrics: ['cpu', 'memory', 'disk', 'network'],
    onUpdate: (data) => {
        const timestamp = new Date();

        // Update CPU chart
        cpuChart.data.datasets[0].data.push({
            x: timestamp,
            y: data.metrics.cpu?.total || 0
        });

        // Update Memory chart
        memChart.data.datasets[0].data.push({
            x: timestamp,
            y: data.metrics.memory?.usedPercent || 0
        });

        // Update Network chart
        netChart.data.datasets[0].data.push({
            x: timestamp,
            y: (data.metrics.network?.bytesPerSec || 0) / 1048576 // Convert to MB/s
        });

        // Update all charts
        cpuChart.update('none');
        memChart.update('none');
        netChart.update('none');
    }
});
```

## API Reference

### Constructor

```javascript
const manager = new MetricsManager(options);
```

**Options**:
- `cache` (boolean): Enable IndexedDB caching (default: true)
- `historicalEndpoint` (string): Override historical API endpoint
- `pollingEndpoint` (string): Override polling API endpoint
- `defaultPollInterval` (number): Default polling interval in ms (default: 5000)

### Methods

#### `loadHistorical(options)`

Load historical data from `/api/v1/perfhistorylogs`.

**Parameters**:
```javascript
{
    datasetname: 'system_metrics',     // Dataset identifier
    starttime: '2026-01-04T00:00:00Z', // ISO 8601 start time
    endtime: '2026-01-05T00:00:00Z',   // ISO 8601 end time
    granularity: '5s',                 // 5s, 1m, 1h, 1d, etc.
    metrics: ['cpu', 'memory'],        // Array of metrics to load
    format: 'json',                    // json, compact, csv
    aggregation: 'avg'                 // avg, min, max, sum, p50, p95, p99
}
```

**Returns**: Promise<Array> - Historical data samples

#### `startPolling(options)`

Start periodic polling of current metrics.

**Parameters**:
```javascript
{
    datasetname: 'current_metrics',    // Dataset identifier
    interval: 5000,                    // Polling interval in ms
    metrics: ['cpu', 'memory'],        // Metrics to poll
    onUpdate: (data) => { }            // Callback for each update
}
```

**Returns**: intervalId - ID of the polling interval

#### `stopPolling(datasetname)`

Stop polling for a dataset.

**Parameters**:
- `datasetname` (string): Dataset to stop polling

#### `getData(datasetname)`

Get raw data for a dataset.

**Returns**: Object with type ('historical' or 'polling') and data

#### `getMetric(datasetname, metricName)`

Extract specific metric from dataset.

**Metric Names**:
- `cpu_total` - Average CPU usage
- `cpu_cores` - Per-core CPU usage array
- `memory_used` - Memory usage percentage
- `memory_total` - Total memory in GB
- `memory_available` - Available memory in GB
- `disk` - Disk information array
- `network_bytes` - Network bytes per second

**Returns**: Array of `{ timestamp, value }` objects

#### `toChartFormat(datasetname, metricName, options)`

Convert metric data to Chart.js format.

**Parameters**:
```javascript
{
    label: 'CPU Usage',                // Chart label
    borderColor: '#3b82f6',           // Line color
    backgroundColor: 'rgba(...)',      // Fill color
    fill: false,                       // Fill under line
    includeAverage: true               // For cpu_cores only
}
```

**Returns**: Object with `datasets` array ready for Chart.js

#### `destroy()`

Stop all polling and clean up resources.

## Data Format Examples

### Historical Data Format (from perfhistorylogs)

```json
[
    {
        "Timestamp": "2026-01-05T00:00:00Z",
        "Cpu": {
            "Total": 45.2,
            "Cores": [44.1, 46.3, 45.0, 45.4]
        },
        "Memory": {
            "UsedPercent": 68.5,
            "TotalGB": 16.0,
            "AvailableGB": 5.04
        },
        "Disk": {
            "Drives": [
                {
                    "Drive": "C:",
                    "UsedPercent": 72.3,
                    "TotalGB": 256
                }
            ]
        },
        "Network": {
            "BytesPerSec": 1234567
        }
    }
]
```

### Current Metrics Format (from /metrics)

```json
{
    "status": "success",
    "timestamp": "2026-01-05T01:00:00Z",
    "metrics": {
        "cpu": [
            { "core": 0, "value": 44.1 },
            { "core": 1, "value": 46.3 }
        ],
        "memory": {
            "usedPercent": 68.5,
            "totalGB": 16.0,
            "availableGB": 5.04
        },
        "disk": [ ],
        "network": {
            "bytesPerSec": 1234567
        }
    }
}
```

### Chart.js Format (output)

```json
{
    "datasets": [
        {
            "label": "CPU 0",
            "data": [
                { "x": "2026-01-05T00:00:00Z", "y": 44.1 },
                { "x": "2026-01-05T00:00:05Z", "y": 44.5 }
            ],
            "borderColor": "#3b82f6",
            "backgroundColor": "#3b82f640",
            "fill": false,
            "borderWidth": 2,
            "tension": 0.4,
            "pointRadius": 0
        }
    ]
}
```

## Integration with Existing Components

### Update Server Heatmap to Use MetricsManager

```javascript
// In server-heatmap component
const manager = new MetricsManager();

useEffect(() => {
    // Load historical data
    const loadData = async () => {
        const now = new Date();
        const start = new Date(now - parseTimeRange(timeRange));

        await manager.loadHistorical({
            datasetname: 'cpu_history',
            starttime: start.toISOString(),
            endtime: now.toISOString(),
            granularity: timeRange === '5m' || timeRange === '15m' ? '5s' : '1m',
            metrics: ['cpu']
        });

        const chartData = manager.toChartFormat('cpu_history', 'cpu_cores');
        updateChart(chartData);
    };

    loadData();

    // Start polling
    const pollId = manager.startPolling({
        datasetname: 'cpu_current',
        interval: 5000,
        metrics: ['cpu'],
        onUpdate: (data) => {
            // Append to chart
            appendToChart(data);
        }
    });

    return () => manager.stopPolling('cpu_current');
}, [timeRange]);
```

## Performance Considerations

1. **Caching**: Historical data cached in IndexedDB reduces API calls
2. **Single Polling**: Use one polling session for multiple charts
3. **Data Limits**: Keep only necessary data in memory (e.g., last 1000 points)
4. **Update Mode**: Use `chart.update('none')` to skip animations
5. **Decimation**: Enable Chart.js decimation for large datasets

## Best Practices

1. **Load historical first**: Get context before starting polling
2. **Stop polling**: Always stop polling when component unmounts
3. **Time alignment**: Ensure historical and polling data timestamps align
4. **Error handling**: Handle API failures gracefully
5. **Memory management**: Periodically trim old data from charts
