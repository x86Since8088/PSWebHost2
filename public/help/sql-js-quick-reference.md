# sql.js Quick Reference Guide

## Quick Start

### Initialize Database

```javascript
const db = new MetricsDatabase();
await db.initialize();
```

### Insert Metrics

```javascript
db.insertMetrics({
    timestamp: new Date().toISOString(),
    hostname: 'server-01',
    cpu: { total: 45.5, cores: [40, 42, 48, 50] },
    memory: { totalGB: 16, usedGB: 8, usedPercent: 50 }
});
```

### Query Metrics

```javascript
const startTime = new Date(Date.now() - 3600000).toISOString(); // 1 hour ago
const endTime = new Date().toISOString();

const cpuData = db.queryCPUMetrics(startTime, endTime);
const memData = db.queryMemoryMetrics(startTime, endTime);
```

## Chart Integration

### Create Chart with Adapter

```javascript
// Create chart
const chart = new Chart(ctx, chartConfig);

// Create adapter
const adapter = new ChartDataAdapter(chart, {
    maxDataPoints: 1000,
    updateMode: 'none',
    timeWindow: 3600000 // 1 hour
});
```

### Update Chart Incrementally

```javascript
// Append new data (no destroy/recreate)
adapter.appendData({
    datasets: [{
        data: [{ x: timestamp, y: value }]
    }]
});

// Replace all data
adapter.replaceData({
    datasets: [{
        data: [/* array of points */]
    }]
});
```

## MetricsManager Usage

### Initialize with sql.js

```javascript
const manager = new MetricsManager({ sql: true });
await manager.initSqlDatabase();
```

### Load Historical Data

```javascript
await manager.loadHistorical({
    datasetname: 'metrics_history',
    starttime: startTime,
    endtime: endTime,
    metrics: ['cpu', 'memory']
});
```

### Start Polling

```javascript
manager.startPolling({
    datasetname: 'current',
    interval: 5000,
    metrics: ['cpu', 'memory'],
    onUpdate: (data) => {
        // Handle new data
    }
});
```

### Query from sql.js

```javascript
const data = await manager.queryFromSql('cpu', startTime, endTime);
```

## ChartDataManager Usage

### Register Chart

```javascript
const dataManager = new ChartDataManager(metricsDB);

const adapter = dataManager.registerChart('chart-id', chartInstance, {
    metricType: 'cpu',
    autoUpdate: true,
    updateInterval: 5000
});
```

### Load Historical to Chart

```javascript
await dataManager.loadHistoricalData('chart-id', startTime, endTime);
```

## Console Commands

### Get Database Stats

```javascript
const stats = db.getStats();
console.log(stats);
```

### Query Raw SQL

```javascript
const stmt = db.db.prepare('SELECT * FROM cpu_metrics LIMIT 10');
while (stmt.step()) {
    console.log(stmt.getAsObject());
}
stmt.free();
```

### Export Database

```javascript
const jsonExport = await db.exportToJSON();
console.log(jsonExport);
```

### Clean Old Data

```javascript
const deletedCount = db.cleanOldData();
console.log(`Deleted ${deletedCount} old records`);
```

### Manual Save

```javascript
await db.saveToIndexedDB();
```

## Common Patterns

### Pattern 1: Chart with Auto-Updates

```javascript
// 1. Initialize manager
const manager = new MetricsManager({ sql: true });
await manager.initSqlDatabase();

// 2. Create chart
const chart = new Chart(ctx, config);

// 3. Create data manager
const dataManager = new ChartDataManager(manager.metricsDB);

// 4. Register with auto-updates
const adapter = dataManager.registerChart('my-chart', chart, {
    metricType: 'cpu',
    autoUpdate: true,
    updateInterval: 5000
});

// 5. Load historical
await dataManager.loadHistoricalData('my-chart', startTime, endTime);
```

### Pattern 2: Manual Chart Updates

```javascript
// 1. Create chart with adapter
const chart = new Chart(ctx, config);
const adapter = new ChartDataAdapter(chart, {
    maxDataPoints: 1000,
    updateMode: 'none'
});

// 2. Poll for new data
setInterval(async () => {
    const newData = await fetchMetrics();

    // 3. Append incrementally
    adapter.appendData({
        datasets: [{
            data: newData.map(d => ({ x: d.timestamp, y: d.value }))
        }]
    });
}, 5000);
```

### Pattern 3: Query and Display

```javascript
// 1. Initialize database
const db = new MetricsDatabase();
await db.initialize();

// 2. Query metrics
const cpuData = db.queryCPUMetrics(startTime, endTime);

// 3. Process results
cpuData.forEach(sample => {
    console.log(`${sample.timestamp}: ${sample.cpu_total}%`);
    console.log(`Cores: ${sample.cpu_cores.join(', ')}`);
});
```

## Configuration Options

### MetricsDatabase

```javascript
new MetricsDatabase({
    dbName: 'PSWebHostMetrics',      // Database name
    indexedDBName: 'PSWebHostMetricsDB', // IndexedDB name
    autoSaveInterval: 30000,          // Save every 30s
    retentionHours: 24,               // Keep 24 hours
    maxRecords: 100000                // Max 100k records
})
```

### ChartDataAdapter

```javascript
new ChartDataAdapter(chart, {
    maxDataPoints: 1000,    // Max points per dataset
    updateMode: 'none',     // Chart.js update mode
    timeWindow: 3600000     // Time window in ms
})
```

### ChartDataManager

```javascript
dataManager.registerChart(chartId, chart, {
    metricType: 'cpu',      // cpu, memory, disk, network
    updateInterval: 5000,   // Poll interval in ms
    autoUpdate: true,       // Enable auto-updates
    query: null             // Custom SQL query (optional)
})
```

## Troubleshooting

### Chart not updating?
```javascript
// Check adapter exists
console.log(chartAdapterRef.current);

// Check adapter stats
console.log(adapter.getStats());

// Check data count
console.log(adapter.getDataCount());
```

### Database not saving?
```javascript
// Check auto-save is running
console.log(db.autoSaveTimer);

// Check changes count
console.log(db.changesSinceLastSave);

// Manual save
await db.saveToIndexedDB();
```

### Out of storage?
```javascript
// Check database size
const stats = db.getStats();
console.log(stats);

// Clean old data
db.cleanOldData();

// Reduce retention
db.config.retentionHours = 12;
```

## Best Practices

### DO:
- ✅ Use incremental updates (appendData)
- ✅ Set appropriate retention periods
- ✅ Use indexed queries (timestamp-based)
- ✅ Clean old data regularly
- ✅ Check browser storage limits

### DON'T:
- ❌ Store sensitive data in sql.js
- ❌ Destroy/recreate charts on updates
- ❌ Query without time bounds
- ❌ Exceed browser storage quotas
- ❌ Disable auto-save in production

## Testing

### Run Unit Tests

1. Navigate to **Admin Tools > Unit Test Runner**
2. Select "All Test Suites"
3. Click "Run Tests"
4. View results in Summary or Details view

### Write Custom Tests

```javascript
framework.describe('My Tests', function() {
    framework.it('should test something', async function(assert) {
        // Your test code
        assert.assertEqual(actual, expected);
    });
});
```

## Performance Tips

1. **Limit Data Points**: Set `maxDataPoints` appropriately
2. **Reduce Polling**: Increase `updateInterval` if possible
3. **Enable Decimation**: Use Chart.js decimation for large datasets
4. **Batch Inserts**: Insert multiple metrics at once
5. **Index Usage**: Always query with time ranges

## File Locations

- Libraries: `/public/lib/`
- Components: `/public/elements/`
- Tests: `/public/lib/test-suites.js`
- Docs: `/public/help/`

## Links

- [Full Architecture Docs](./sql-js-architecture.md)
- [Security Analysis](./in-browser-sql-security-analysis.md)
- [Framework Comparison](./in-browser-sql.md)

---

**Last Updated**: 2026-01-06
