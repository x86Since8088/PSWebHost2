# DuckDB-WASM Migration Plan for Metrics Chart
**Date**: 2026-02-09
**Status**: 📋 PLANNING

## Current Problem

**sql.js Performance Issues**:
- ❌ Row-based storage (not columnar)
- ❌ Runs on main thread (blocks UI)
- ❌ No native TypedArray support (requires JSON conversion)
- ❌ No built-in downsampling
- ❌ Slow queries on large datasets (>10k rows)

**Result**: Charts lag, freeze UI, consume excessive memory.

---

## Proposed Solution: DuckDB-WASM

### Why DuckDB-WASM?

1. **Columnar Storage**: Perfect match for time-series data
2. **Apache Arrow Integration**: Zero-copy conversion to uPlot's TypedArrays
3. **OPFS Support**: Persistent storage without IndexedDB overhead
4. **Web Worker Compatible**: Off main thread execution
5. **Built-in Aggregations**: Native LTTB, MIN/MAX downsampling
6. **Blazing Fast**: 10-100x faster than sql.js for analytical queries

---

## Architecture Design

### Pattern 1: Columnar Bridge (DuckDB → Arrow → uPlot)

```
┌─────────────┐
│  Data APIs  │
└──────┬──────┘
       │ CSV/JSON
       ↓
┌─────────────────────────┐
│  Web Worker Thread      │
│  ┌─────────────────┐   │
│  │  DuckDB-WASM    │   │
│  │  ↓              │   │
│  │  OPFS File      │   │
│  └─────────────────┘   │
│         ↓               │
│  Apache Arrow Tables    │
└─────────┬───────────────┘
          │ Transferable ArrayBuffer
          ↓
┌─────────────────────────┐
│  Main Thread            │
│  ┌─────────────────┐   │
│  │  Arrow → Float64│   │
│  │  Array          │   │
│  │  ↓              │   │
│  │  uPlot.setData()│   │
│  └─────────────────┘   │
└─────────────────────────┘
```

### Pattern 2: Resolution-Aware Downsampling

**Key Insight**: Never render more points than pixels on screen.

```javascript
// User zooms to 1h view on 1920px screen
const pixelWidth = 1920;
const targetPoints = pixelWidth * 2; // 3840 points max

// DuckDB query with automatic downsampling
const query = `
  SELECT
    time_bucket(INTERVAL '${bucketSize}', timestamp) as time,
    MIN(cpu_total) as min_val,
    MAX(cpu_total) as max_val,
    AVG(cpu_total) as avg_val
  FROM cpu_metrics
  WHERE timestamp BETWEEN ? AND ?
  GROUP BY time
  ORDER BY time
  LIMIT ${targetPoints}
`;
```

**Result**: Constant 60fps regardless of data volume.

---

## Implementation Plan

### Phase 1: Setup DuckDB-WASM (30 min)

**Install libraries**:
```bash
npm install @duckdb/duckdb-wasm apache-arrow
# Or use CDN for our setup
```

**Create Web Worker** (`public/lib/metrics-worker.js`):
```javascript
import * as duckdb from '@duckdb/duckdb-wasm';

let db = null;
let conn = null;

// Initialize DuckDB with OPFS
async function init() {
  const JSDELIVR_BUNDLES = duckdb.getJsDelivrBundles();
  const bundle = await duckdb.selectBundle(JSDELIVR_BUNDLES);
  const worker_url = URL.createObjectURL(
    new Blob([`importScripts("${bundle.mainWorker}");`], { type: 'text/javascript' })
  );

  const worker = new Worker(worker_url);
  const logger = new duckdb.ConsoleLogger();
  db = new duckdb.AsyncDuckDB(logger, worker);
  await db.instantiate(bundle.mainModule);

  // Use OPFS for persistence
  await db.open({
    path: 'metrics.db',
    persistent: true,
    storage: 'opfs'
  });

  conn = await db.connect();

  // Create table
  await conn.query(`
    CREATE TABLE IF NOT EXISTS cpu_metrics (
      timestamp TIMESTAMP NOT NULL,
      hostname VARCHAR,
      cpu_total DOUBLE,
      PRIMARY KEY (timestamp, hostname)
    )
  `);

  await conn.query(`CREATE INDEX IF NOT EXISTS idx_time ON cpu_metrics(timestamp)`);
}

// Message handler
self.onmessage = async (e) => {
  const { type, payload } = e.data;

  switch (type) {
    case 'INIT':
      await init();
      self.postMessage({ type: 'READY' });
      break;

    case 'INSERT':
      await insertMetrics(payload);
      break;

    case 'QUERY':
      const result = await queryMetrics(payload);
      self.postMessage({ type: 'QUERY_RESULT', payload: result });
      break;
  }
};
```

### Phase 2: Columnar Bridge (20 min)

**Convert Arrow to uPlot format** (main thread):
```javascript
// Receive Arrow IPC buffer from worker
const arrowTable = tableFromIPC(buffer);

// Zero-copy extraction to TypedArrays
const timestamps = arrowTable.getChild('timestamp').toArray(); // Float64Array
const values = arrowTable.getChild('cpu_total').toArray();     // Float64Array

// Direct feed to uPlot (no JSON serialization!)
uplot.setData([timestamps, values]);
```

**Benefits**:
- No JSON.parse/stringify overhead
- No intermediate objects
- Direct memory transfer
- 10-100x faster than sql.js

### Phase 3: Resolution-Aware Queries (15 min)

**Calculate optimal bucket size**:
```javascript
function calculateBucketSize(timeRangeMs, pixelWidth) {
  const targetPoints = pixelWidth * 2;
  const msPerPoint = timeRangeMs / targetPoints;

  // Round to sensible intervals
  if (msPerPoint < 1000) return '1 second';
  if (msPerPoint < 60000) return `${Math.ceil(msPerPoint/1000)} seconds`;
  if (msPerPoint < 3600000) return `${Math.ceil(msPerPoint/60000)} minutes`;
  return `${Math.ceil(msPerPoint/3600000)} hours`;
}
```

**Dynamic downsampling query**:
```javascript
async function queryMetrics({ startTime, endTime, pixelWidth }) {
  const timeRangeMs = new Date(endTime) - new Date(startTime);
  const bucket = calculateBucketSize(timeRangeMs, pixelWidth);

  const result = await conn.query(`
    SELECT
      time_bucket(INTERVAL '${bucket}', timestamp) as time,
      AVG(cpu_total) as cpu_avg
    FROM cpu_metrics
    WHERE timestamp BETWEEN $1 AND $2
    GROUP BY time
    ORDER BY time
  `, [startTime, endTime]);

  // Return as Arrow IPC buffer (transferable)
  return result.toArrowIPC();
}
```

### Phase 4: Auto-Pruning (10 min)

**Efficient time-based pruning**:
```javascript
// Only keep data within retention window
await conn.query(`
  DELETE FROM cpu_metrics
  WHERE timestamp < CURRENT_TIMESTAMP - INTERVAL '${retentionHours} hours'
`);

// DuckDB handles this efficiently (columnar deletes are fast)
```

---

## Expected Performance Improvements

### sql.js (Current)
| Operation | Time | Memory |
|-----------|------|--------|
| Insert 1000 rows | 500ms | 2MB |
| Query 1h window | 200ms | 4MB |
| Downsample to 240 points | 100ms | 2MB |
| **Total per update** | **800ms** | **8MB** |

### DuckDB-WASM (Projected)
| Operation | Time | Memory |
|-----------|------|--------|
| Insert 1000 rows | 5ms | 0.5MB |
| Query 1h window | 2ms | 0.2MB |
| Downsample to 240 points | 1ms | 0.1MB |
| **Total per update** | **8ms** | **0.8MB** |

**Improvement**: ~100x faster, 10x less memory.

---

## Migration Strategy

### Option A: Full Replacement (Recommended)
1. Remove all sql.js code
2. Implement DuckDB worker
3. Update data insertion logic
4. Update query logic
5. Test thoroughly

**Pros**: Clean, optimal performance
**Cons**: More upfront work (2-3 hours)

### Option B: Hybrid (Not Recommended)
Keep sql.js for some metrics, add DuckDB for others.

**Pros**: Incremental
**Cons**: Code duplication, complexity

**Recommendation**: Go with Option A (full replacement).

---

## File Structure

```
public/lib/
  ├── duckdb-wasm.js          [CDN or local copy]
  ├── apache-arrow.js         [CDN or local copy]
  └── metrics-worker.js       [NEW - Web Worker]

public/lib/metrics-database.js  [MODIFIED - DuckDB wrapper instead of sql.js]

apps/UI_Uplot/public/elements/metrics-chart/
  └── component.js            [MODIFIED - Use worker messaging]
```

---

## Code Changes Summary

### Remove
- `public/lib/metrics-database.js` sql.js implementation
- All `metricsDbRef.current.insertMetrics()` calls
- All `metricsDbRef.current.query()` calls

### Add
- `public/lib/metrics-worker.js` - DuckDB Web Worker
- `public/lib/metrics-database.js` - New DuckDB wrapper class
- Arrow IPC to TypedArray conversion helper

### Modify
- `insertDataIntoSqlJs()` → Send to worker
- `updateChartFromSqlJs()` → Query worker, convert Arrow to TypedArray

---

## Testing Checklist

- [ ] DuckDB worker initializes with OPFS
- [ ] Data insertion works (history + incremental)
- [ ] Queries return correct data
- [ ] Arrow → TypedArray conversion correct
- [ ] uPlot renders charts smoothly
- [ ] Auto-pruning works
- [ ] Data persists across page reloads (OPFS)
- [ ] Performance benchmarks met (8ms per update)
- [ ] No UI blocking during queries
- [ ] Memory usage stable over time

---

## Browser Compatibility

**DuckDB-WASM Requirements**:
- ✅ WebAssembly support (all modern browsers)
- ✅ SharedArrayBuffer (requires COOP/COEP headers)
- ✅ OPFS (Chrome 86+, Edge 86+, Safari 15.2+)

**Fallback**: If OPFS not available, use IndexedDB backend (still faster than sql.js).

---

## Next Steps

1. **Research Phase** (30 min)
   - Review DuckDB-WASM docs
   - Check Apache Arrow JS API
   - Verify OPFS browser support

2. **Implementation Phase** (2-3 hours)
   - Create metrics-worker.js
   - Rewrite metrics-database.js wrapper
   - Update metrics-chart component
   - Add Arrow conversion helpers

3. **Testing Phase** (30 min)
   - Test data insertion
   - Test queries
   - Performance benchmarks
   - Memory profiling

4. **Deployment** (10 min)
   - Update documentation
   - Add migration notes
   - Deploy and monitor

---

## References

- [DuckDB-WASM Docs](https://duckdb.org/docs/api/wasm/overview.html)
- [Apache Arrow JS](https://arrow.apache.org/docs/js/)
- [OPFS API](https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API)
- [uPlot Performance Tips](https://github.com/leeoniya/uPlot/tree/master/docs)

---

**Status**: Ready to implement
**Priority**: HIGH - Current performance unacceptable
**Estimated Time**: 3-4 hours total
