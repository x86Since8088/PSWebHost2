# DuckDB-WASM vs RxDB: Architecture Decision
**Date**: 2026-02-09
**Use Case**: Real-time metrics charting for PSWebHost

---

## Option 1: DuckDB-WASM + Worker-Thread Persistence Pattern

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│ Main Thread (UI)                                        │
│ ┌─────────────┐    postMessage    ┌─────────────────┐ │
│ │   uPlot     │ ←─────────────────│ Arrow Buffer    │ │
│ │   Chart     │                    │ (Transferable)  │ │
│ └─────────────┘                    └─────────────────┘ │
│       ↑                                      ↑           │
│       │ setData([timestamps, values])       │           │
│       └──────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────┘
                          │
                    postMessage({ startTime, endTime, pixelWidth })
                          │
                          ↓
┌─────────────────────────────────────────────────────────┐
│ Web Worker Thread                                       │
│ ┌───────────────────────────────────────────────────┐  │
│ │ DuckDB-WASM                                       │  │
│ │   ↓                                               │  │
│ │ OPFS File: metrics.db                            │  │
│ │   - Columnar storage                             │  │
│ │   - SQL queries with downsampling                │  │
│ │   - Automatic aggregation                        │  │
│ └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Pros
✅ **Zero main thread blocking**
  - All database operations in worker
  - UI stays responsive during heavy queries
  - Perfect for zooming/panning

✅ **Optimal for analytics**
  - Built-in SQL aggregations (MIN, MAX, AVG, LTTB)
  - Time bucketing: `time_bucket(INTERVAL '15s', timestamp)`
  - Resolution-aware downsampling automatic

✅ **True columnar performance**
  - 10-100x faster than row-based for time-series
  - Perfect for "show me 1 hour of CPU data"

✅ **Apache Arrow zero-copy**
  - Direct TypedArray transfer to uPlot
  - No JSON serialization overhead
  - Transferable ArrayBuffers (instant, no copy)

✅ **OPFS persistence**
  - Faster than IndexedDB (native file system)
  - Survives page reloads
  - Works offline

✅ **Mature and stable**
  - DuckDB is production-grade (used by Observable, Hex, etc.)
  - Well-documented
  - Active development

### Cons
❌ **Initial complexity**
  - Need to set up Web Worker
  - Message passing protocol
  - Arrow IPC serialization

❌ **Not reactive by default**
  - Polling-based updates (query every 5s)
  - No automatic invalidation
  - Must manually trigger re-queries

❌ **No built-in sync**
  - Need to handle API → Worker data flow manually
  - No automatic conflict resolution
  - No remote replication

❌ **Browser compatibility**
  - OPFS requires recent browsers (Chrome 86+, Safari 15.2+)
  - SharedArrayBuffer needs COOP/COEP headers
  - Fallback to IndexedDB needed for older browsers

### Best For
- **Analytical queries** ("show me last 24h with 1m granularity")
- **Large datasets** (millions of rows)
- **Historical data exploration** (zooming, panning)
- **Batch processing** (loading hour of data at once)

---

## Option 2: RxDB + Reactive Hot-Path Pattern

### Architecture
```
┌─────────────────────────────────────────────────────────┐
│ Main Thread                                             │
│ ┌─────────────┐   Observable    ┌─────────────────┐   │
│ │   uPlot     │ ←───────────────│  RxDB Query     │   │
│ │   Chart     │   (auto-update) │  .subscribe()   │   │
│ └─────────────┘                  └────────┬────────┘   │
│                                            │             │
│                                    ┌───────▼───────┐    │
│                                    │  RxDB Collection│   │
│                                    │  cpu_metrics    │   │
│                                    │   - IndexedDB   │   │
│                                    │   - Reactive    │   │
│                                    └────────┬────────┘   │
│                                            │             │
│                      ┌─────────────────────▼─────────┐  │
│                      │ Replication Plugin             │  │
│                      │ - GraphQL/REST sync            │  │
│                      │ - Conflict resolution          │  │
│                      │ - Offline-first                │  │
│                      └────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Pros
✅ **True reactivity**
  - Observable queries: `db.cpu_metrics.find().$.subscribe()`
  - Automatic UI updates when data changes
  - Perfect for live streaming ("new data just arrived!")

✅ **Simple mental model**
  - Just insert data, chart auto-updates
  - No manual refresh logic needed
  - Declarative: "show last 1000 points, always"

✅ **Built-in sync**
  - Automatic replication to/from server
  - Conflict resolution strategies
  - Offline-first by design

✅ **Change streams**
  - Know exactly what changed (insert/update/delete)
  - Can use `incrementalPatch()` for efficient updates
  - Only re-render what's necessary

✅ **No worker complexity**
  - Runs in main thread (with optional worker plugin)
  - Simpler codebase
  - Easier debugging

✅ **MongoDB-like API**
  - Familiar syntax: `.find().where('timestamp').gt()`
  - Composable queries
  - Easy to learn

### Cons
❌ **IndexedDB limitations**
  - Not as fast as OPFS/columnar storage
  - Row-based, not columnar
  - Query performance degrades with size

❌ **No built-in downsampling**
  - Must implement LTTB/aggregation yourself
  - Complex for time-bucket queries
  - Can't do `SELECT AVG(cpu) GROUP BY time_bucket()`

❌ **Memory overhead**
  - Keeps queries in memory for reactivity
  - RxJS observable chains
  - More GC pressure

❌ **Main thread execution**
  - Queries block UI (unless using worker plugin)
  - Heavy queries cause jank
  - Not ideal for "query 1M rows then downsample"

❌ **Overkill for our use case**
  - Replication not needed (metrics are local)
  - Conflict resolution not needed (single source)
  - Observables add complexity for polling data

### Best For
- **Live streaming data** (WebSocket → RxDB → Chart)
- **Multi-device sync** (changes replicate across tabs/devices)
- **Document databases** (storing JSON objects, not time-series)
- **CRUD applications** (forms, lists, editing)

---

## Decision Matrix

| Criteria | DuckDB-WASM | RxDB | Winner |
|----------|-------------|------|--------|
| **Time-series queries** | ⭐⭐⭐⭐⭐ Columnar | ⭐⭐ Row-based | **DuckDB** |
| **Downsampling/aggregation** | ⭐⭐⭐⭐⭐ Built-in SQL | ⭐ Manual | **DuckDB** |
| **Large datasets (>100k rows)** | ⭐⭐⭐⭐⭐ Blazing | ⭐⭐ Slow | **DuckDB** |
| **Reactivity** | ⭐⭐ Polling | ⭐⭐⭐⭐⭐ Observables | **RxDB** |
| **UI responsiveness** | ⭐⭐⭐⭐⭐ Worker | ⭐⭐⭐ Main thread | **DuckDB** |
| **Setup complexity** | ⭐⭐ Worker setup | ⭐⭐⭐⭐ Simple | **RxDB** |
| **Real-time streaming** | ⭐⭐⭐ Polling | ⭐⭐⭐⭐⭐ Observables | **RxDB** |
| **Persistence speed** | ⭐⭐⭐⭐⭐ OPFS | ⭐⭐⭐ IndexedDB | **DuckDB** |
| **Arrow/TypedArray output** | ⭐⭐⭐⭐⭐ Native | ⭐ Manual | **DuckDB** |
| **Offline/sync** | ⭐ None | ⭐⭐⭐⭐⭐ Built-in | **RxDB** |

---

## Recommendation for PSWebHost Metrics

### ✅ Choose: **DuckDB-WASM + Worker-Thread Persistence**

**Why?**

1. **Our access pattern is analytical, not reactive**
   - User wants: "Show me last 1 hour of CPU data"
   - Not: "Tell me instantly when CPU changes"
   - Polling every 5s is acceptable

2. **We need heavy aggregation**
   - Downsampling 10,000 points → 240 points for 1h view
   - Time bucketing: 5s data → 15s buckets
   - MIN/MAX/AVG calculations
   - DuckDB does this natively, RxDB requires manual implementation

3. **Performance is critical**
   - Charts are already slow with sql.js
   - Need columnar storage for time-series
   - Need worker thread to avoid UI blocking
   - RxDB in main thread will still cause jank

4. **No sync needed**
   - Metrics come from local server API
   - No multi-device replication
   - No offline editing
   - RxDB's killer features aren't used

5. **uPlot needs TypedArrays**
   - DuckDB → Arrow → TypedArray is zero-copy
   - RxDB → objects → TypedArray requires conversion
   - Performance difference is massive

---

## Hybrid Approach (Best of Both Worlds)

**What if we need reactivity later?**

We can combine both:
```javascript
// DuckDB for storage and queries (in worker)
const worker = new Worker('metrics-worker.js');

// RxJS for reactive updates (in main thread)
const metricsStream$ = new Subject();

// Every 5s, query DuckDB and push to stream
setInterval(async () => {
  const data = await queryWorker({ startTime, endTime });
  metricsStream$.next(data);
}, 5000);

// Chart subscribes to stream
metricsStream$.subscribe(data => {
  uplot.setData(data);
});
```

**Benefits**:
- DuckDB handles heavy lifting (queries, aggregation)
- RxJS provides clean reactive API
- Best of both worlds

---

## Implementation Recommendation

### Phase 1: DuckDB Worker (Core)
```javascript
// public/lib/metrics-worker.js
import * as duckdb from '@duckdb/duckdb-wasm';

let db, conn;

async function init() {
  // Initialize DuckDB with OPFS
  db = await duckdb.AsyncDuckDB(...);
  await db.open({ path: 'metrics.db', storage: 'opfs' });
  conn = await db.connect();

  await conn.query(`
    CREATE TABLE cpu_metrics (
      timestamp TIMESTAMP,
      cpu_total DOUBLE
    )
  `);
}

self.onmessage = async ({ data }) => {
  switch (data.type) {
    case 'QUERY':
      const { startTime, endTime, pixelWidth } = data.payload;

      // Calculate optimal downsampling
      const bucket = calculateBucket(startTime, endTime, pixelWidth);

      // Query with aggregation
      const result = await conn.query(`
        SELECT
          time_bucket(INTERVAL '${bucket}', timestamp) as time,
          AVG(cpu_total) as value
        FROM cpu_metrics
        WHERE timestamp BETWEEN $1 AND $2
        GROUP BY time
        ORDER BY time
      `, [startTime, endTime]);

      // Convert to Arrow IPC (transferable)
      const arrowBuffer = result.toArrowIPC();

      self.postMessage({
        type: 'QUERY_RESULT',
        payload: arrowBuffer
      }, [arrowBuffer]); // Transfer ownership
      break;
  }
};
```

### Phase 2: Main Thread Integration
```javascript
// metrics-chart component
const worker = new Worker('/public/lib/metrics-worker.js');

async function updateChart() {
  // Send query to worker
  worker.postMessage({
    type: 'QUERY',
    payload: {
      startTime: new Date(Date.now() - 3600000).toISOString(),
      endTime: new Date().toISOString(),
      pixelWidth: containerRef.current.offsetWidth
    }
  });
}

worker.onmessage = ({ data }) => {
  if (data.type === 'QUERY_RESULT') {
    // Convert Arrow to TypedArrays
    const table = tableFromIPC(data.payload);
    const timestamps = table.getChild('time').toArray();
    const values = table.getChild('value').toArray();

    // Feed directly to uPlot (zero-copy!)
    uplot.setData([timestamps, values]);
  }
};

// Poll every 5s
setInterval(updateChart, 5000);
```

---

## Size Comparison

### DuckDB-WASM
- **Main bundle**: ~3.5 MB (gzipped: ~1.2 MB)
- **Worker bundle**: ~2.8 MB (gzipped: ~900 KB)
- **Total**: ~6.3 MB (~2.1 MB gzipped)

### RxDB
- **RxDB core**: ~200 KB (gzipped: ~60 KB)
- **RxJS**: ~150 KB (gzipped: ~45 KB)
- **IndexedDB adapter**: ~20 KB (gzipped: ~7 KB)
- **Total**: ~370 KB (~112 KB gzipped)

**Winner**: RxDB is 20x smaller

**However**: DuckDB's size is justified by its performance. One-time download, massive gains.

---

## Final Decision

### ✅ **Go with DuckDB-WASM + Worker Pattern**

**Rationale**:
1. Solves our actual performance problem (slow queries)
2. Perfect fit for time-series analytics
3. Zero-copy to uPlot via Arrow
4. Off main thread execution
5. Built-in downsampling
6. OPFS persistence

**When to reconsider RxDB**:
- If we add WebSocket live streaming
- If we need multi-tab sync
- If we add user annotations that need conflict resolution
- If bundle size becomes critical (<2MB total)

**Next Steps**:
1. ✅ Decision made: DuckDB-WASM
2. ⏭️ Implement metrics-worker.js
3. ⏭️ Add Arrow conversion helpers
4. ⏭️ Update metrics-chart component
5. ⏭️ Test and benchmark

---

**Status**: ✅ Architecture Decision Complete
**Recommendation**: DuckDB-WASM + Worker-Thread Persistence Pattern
**Estimated Implementation**: 3-4 hours
**Expected Performance**: 100x improvement over sql.js
