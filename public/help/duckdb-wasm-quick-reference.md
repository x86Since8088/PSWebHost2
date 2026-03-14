# DuckDB-WASM Quick Reference

PSWebHost uses DuckDB-WASM for in-browser metrics storage and analytics.

## Architecture

```
Browser                                     Server
┌────────────────────────────────────┐     ┌─────────────────┐
│  metrics-chart component           │     │ WebHostMetrics  │
│         │                          │     │    API          │
│         ▼                          │     │                 │
│  MetricsDatabase                   │◄────┤ /api/v1/metrics │
│  (metrics-database.js)             │     │ /api/v1/history │
│         │                          │     └─────────────────┘
│         ▼ postMessage              │
│  ┌──────────────────────────┐      │
│  │  Web Worker               │      │
│  │  (metrics-worker.js)      │      │
│  │         │                 │      │
│  │         ▼                 │      │
│  │  DuckDB-WASM              │      │
│  │  (AsyncDuckDB)            │      │
│  │  - cpu_metrics            │      │
│  │  - memory_metrics         │      │
│  │  - disk_metrics           │      │
│  │  - network_metrics        │      │
│  └──────────────────────────┘      │
└────────────────────────────────────┘
```

## Files

| File | Purpose |
|------|---------|
| `public/lib/metrics-database.js` | Main API wrapper - use this from your code |
| `public/lib/metrics-worker.js` | Web Worker with DuckDB-WASM integration |
| `public/lib/metrics/duckdb-core.js` | Core DuckDB initialization |
| `public/lib/metrics/metrics-schema.js` | Table schemas and validation |
| `public/lib/metrics/metrics-queries.js` | Safe parameterized query builders |
| `public/lib/metrics/metrics-transforms.js` | Data transformation utilities |
| `public/lib/uplot/uplot-metrics-wrapper.js` | uPlot + DuckDB wrapper |
| `public/lib/uplot/uplot-subscription.js` | Multi-chart subscription manager |

## Basic Usage

```javascript
// Create and initialize database
const db = new MetricsDatabase({
    dbName: 'MyMetrics',
    retentionHours: 24,
    maxRecords: 100000
});
await db.initialize();

// Insert metrics
await db.insertMetrics({
    timestamp: new Date().toISOString(),
    hostname: 'server1',
    cpu: { total: 45.2 },
    memory: {
        used_mb: 4096,
        total_mb: 8192,
        percent_used: 50
    }
});

// Query data
const results = await db.query('SELECT * FROM cpu_metrics ORDER BY timestamp DESC LIMIT 100');

// Query for charts (optimized with downsampling)
const chartData = await db.queryForChart({
    table: 'cpu_metrics',
    valueColumn: 'cpu_total',
    startTime: '2024-01-01T00:00:00Z',
    endTime: '2024-01-01T01:00:00Z',
    pixelWidth: 800
});
// Returns: { timestamps: Float64Array, values: Float64Array }

// Cleanup
await db.destroy();
```

## Tables

### cpu_metrics
| Column | Type | Description |
|--------|------|-------------|
| timestamp | TIMESTAMP | Sample time (PK) |
| hostname | VARCHAR | Server hostname (PK) |
| cpu_total | DOUBLE | Total CPU % |

### memory_metrics
| Column | Type | Description |
|--------|------|-------------|
| timestamp | TIMESTAMP | Sample time (PK) |
| hostname | VARCHAR | Server hostname (PK) |
| used_mb | DOUBLE | Used memory in MB |
| total_mb | DOUBLE | Total memory in MB |
| percent_used | DOUBLE | Memory usage % |

### disk_metrics
| Column | Type | Description |
|--------|------|-------------|
| timestamp | TIMESTAMP | Sample time (PK) |
| hostname | VARCHAR | Server hostname (PK) |
| drive | VARCHAR | Drive letter/path (PK) |
| used_gb | DOUBLE | Used space in GB |
| total_gb | DOUBLE | Total space in GB |
| percent_used | DOUBLE | Disk usage % |

### network_metrics
| Column | Type | Description |
|--------|------|-------------|
| timestamp | TIMESTAMP | Sample time (PK) |
| hostname | VARCHAR | Server hostname (PK) |
| interface | VARCHAR | Network interface (PK) |
| bytes_per_sec | DOUBLE | Throughput |

## Query Builders

Use `MetricsQueries` for safe parameterized queries:

```javascript
// Chart query with auto-downsampling
const { sql, params } = MetricsQueries.buildChartQuery({
    table: 'cpu_metrics',
    column: 'cpu_total',
    startTime: '2024-01-01T00:00:00Z',
    endTime: '2024-01-01T01:00:00Z',
    pixelWidth: 800,
    hostname: 'server1'
});

// Insert query
const { sql, params } = MetricsQueries.buildInsertQuery('cpu_metrics', {
    timestamp: new Date().toISOString(),
    hostname: 'server1',
    cpu_total: 45.2
});

// Prune old data
const { sql, params } = MetricsQueries.buildPruneQuery('cpu_metrics', 24); // 24 hours
```

## uPlot Wrapper

For chart integration:

```javascript
const chart = new UPlotMetricsWrapper({
    container: document.getElementById('cpu-chart'),
    metric: 'cpu',
    timeRange: '1h',
    pollInterval: 5000,
    historyEndpoint: '/apps/WebHostMetrics/api/v1/metrics/history',
    realtimeEndpoint: '/apps/WebHostMetrics/api/v1/metrics'
});

await chart.initialize();
chart.start();

// Events
chart.on('data', (data) => console.log('New data:', data));
chart.on('error', (err) => console.error('Error:', err));

// Controls
chart.pause();
chart.resume();
await chart.setTimeRange('24h');

// Cleanup
chart.destroy();
```

## Subscription Manager

For multiple charts:

```javascript
const manager = new UPlotSubscriptionManager({
    pollInterval: 5000
});
await manager.initialize();

manager.subscribe('cpu-chart', {
    metric: 'cpu',
    onData: (data) => cpuChart.update(data)
});

manager.subscribe('mem-chart', {
    metric: 'memory',
    onData: (data) => memChart.update(data)
});

// Status
console.log(manager.getStatus());

// Cleanup
manager.destroy();
```

## Performance

| Operation | Typical Time |
|-----------|-------------|
| Insert 1000 rows | ~5ms |
| Query 1h window | ~2ms |
| Downsample for chart | ~1ms |

## Security

- All table/column names validated against whitelist
- Parameterized queries prevent SQL injection
- Validation in `metrics-schema.js`:
  - `validateTable(name)` - throws if invalid
  - `validateColumn(name)` - throws if invalid

## Browser Requirements

- Chrome 61+
- Firefox 60+
- Safari 11+
- Edge 79+

DuckDB-WASM requires WebAssembly support.
