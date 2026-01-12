# In-Browser SQL Frameworks

## Overview

Several JavaScript libraries provide full SQL database capabilities that run entirely in the browser, with no server required.

## Top Options

### 1. sql.js - SQLite Compiled to WebAssembly ⭐ RECOMMENDED

**What it is**: Official SQLite compiled to WebAssembly/JavaScript

**GitHub**: https://github.com/sql-js/sql.js
**Size**: ~800 KB (wasm file)
**License**: MIT

**Pros**:
- ✅ Full SQLite implementation (complete SQL support)
- ✅ Fast (native SQLite performance via WASM)
- ✅ Actively maintained
- ✅ Works offline
- ✅ Export/import to file
- ✅ Works with existing SQLite tools

**Cons**:
- ⚠️ In-memory by default (need to save to file/IndexedDB)
- ⚠️ Larger file size
- ⚠️ Synchronous API (blocks during queries)

**Installation**:
```bash
npm install sql.js
# OR download from CDN
```

**Basic Usage**:
```javascript
// Load sql.js
const initSqlJs = window.initSqlJs;

initSqlJs({
    locateFile: file => `/public/lib/${file}`
}).then(SQL => {
    // Create database
    const db = new SQL.Database();

    // Create table
    db.run(`
        CREATE TABLE metrics (
            id INTEGER PRIMARY KEY,
            timestamp TEXT,
            cpu REAL,
            memory REAL
        )
    `);

    // Insert data
    db.run(`
        INSERT INTO metrics (timestamp, cpu, memory)
        VALUES (?, ?, ?)
    `, ['2026-01-06T01:00:00Z', 45.2, 68.5]);

    // Query data
    const result = db.exec(`
        SELECT * FROM metrics
        WHERE cpu > 40
        ORDER BY timestamp DESC
    `);

    console.log(result);
    // Output: [{ columns: [...], values: [[...]] }]

    // Export database to file
    const data = db.export();
    const blob = new Blob([data], { type: 'application/x-sqlite3' });
    // Save blob to file...

    // Close database
    db.close();
});
```

**Advanced Usage**:
```javascript
// Prepared statements
const stmt = db.prepare('SELECT * FROM metrics WHERE cpu > ?');
stmt.bind([40]);
while (stmt.step()) {
    const row = stmt.getAsObject();
    console.log(row);
}
stmt.free();

// Transactions
db.run('BEGIN TRANSACTION');
try {
    db.run('INSERT INTO metrics ...');
    db.run('UPDATE metrics ...');
    db.run('COMMIT');
} catch (e) {
    db.run('ROLLBACK');
}

// Persist to IndexedDB
const exportData = db.export();
const request = indexedDB.open('MyDatabase', 1);
request.onsuccess = (event) => {
    const idb = event.target.result;
    const tx = idb.transaction(['databases'], 'readwrite');
    tx.objectStore('databases').put({ id: 'main', data: exportData });
};

// Load from IndexedDB
const request = indexedDB.open('MyDatabase', 1);
request.onsuccess = (event) => {
    const idb = event.target.result;
    const tx = idb.transaction(['databases'], 'readonly');
    const req = tx.objectStore('databases').get('main');
    req.onsuccess = () => {
        const db = new SQL.Database(new Uint8Array(req.result.data));
        // Use database...
    };
};
```

### 2. AlaSQL - JavaScript SQL Database

**What it is**: Pure JavaScript SQL database with Excel/CSV support

**GitHub**: https://github.com/AlaSQL/alasql
**Size**: ~500 KB
**License**: MIT

**Pros**:
- ✅ Pure JavaScript (no WASM)
- ✅ Extended SQL syntax (JOIN, GROUP BY, etc.)
- ✅ Import/export CSV, JSON, Excel
- ✅ Works with existing arrays/objects
- ✅ Can query localStorage, IndexedDB
- ✅ Asynchronous queries

**Cons**:
- ⚠️ Slower than sql.js
- ⚠️ Less compatible with standard SQLite
- ⚠️ Occasional bugs

**Installation**:
```html
<script src="https://cdn.jsdelivr.net/npm/alasql"></script>
```

**Basic Usage**:
```javascript
// Create table
alasql('CREATE TABLE metrics (id INT, timestamp STRING, cpu REAL, memory REAL)');

// Insert data
alasql('INSERT INTO metrics VALUES (?, ?, ?, ?)', [1, '2026-01-06T01:00:00Z', 45.2, 68.5]);

// Query
const result = alasql('SELECT * FROM metrics WHERE cpu > 40');
console.log(result);
// Output: [{ id: 1, timestamp: '...', cpu: 45.2, memory: 68.5 }]

// Query JavaScript arrays directly
const data = [
    { timestamp: '2026-01-06T01:00:00Z', cpu: 45.2, memory: 68.5 },
    { timestamp: '2026-01-06T01:00:05Z', cpu: 46.1, memory: 68.7 }
];

const filtered = alasql('SELECT * FROM ? WHERE cpu > 45', [data]);
console.log(filtered);

// Aggregate queries
const avg = alasql('SELECT AVG(cpu) as avgCpu FROM ? GROUP BY DATE(timestamp)', [data]);

// Export to CSV
alasql('SELECT * INTO CSV("metrics.csv") FROM metrics');

// Import from CSV
alasql('SELECT * INTO metrics FROM CSV("data.csv", {headers: true})');
```

**Advanced Usage**:
```javascript
// Async queries
alasql.promise('SELECT * FROM metrics WHERE cpu > 40')
    .then(result => console.log(result));

// Persist to localStorage
alasql('CREATE localStorage DATABASE IF NOT EXISTS mydb');
alasql('ATTACH localStorage DATABASE mydb');
alasql('USE mydb');
alasql('CREATE TABLE IF NOT EXISTS metrics (...)');

// Query IndexedDB directly
alasql('SELECT * FROM indexedDB.mydb.metrics WHERE cpu > 40')
    .then(result => console.log(result));

// Complex joins
alasql(`
    SELECT m.timestamp, m.cpu, a.threshold
    FROM metrics m
    JOIN alerts a ON m.cpu > a.threshold
    WHERE m.timestamp > '2026-01-06'
`);
```

### 3. Lovefield - Structured Data Store

**What it is**: Google's relational database for web apps

**GitHub**: https://github.com/google/lovefield
**Size**: ~200 KB
**License**: Apache 2.0

**Status**: ⚠️ No longer actively maintained (archived in 2020)

**Pros**:
- ✅ Fast, optimized queries
- ✅ IndexedDB backend
- ✅ Schema-based
- ✅ Transaction support

**Cons**:
- ⚠️ Not maintained
- ⚠️ No SQL syntax (uses API)
- ⚠️ More complex API

**Usage** (for reference):
```javascript
// Define schema
const schemaBuilder = lf.schema.create('metrics_db', 1);
schemaBuilder.createTable('metrics')
    .addColumn('id', lf.Type.INTEGER)
    .addColumn('timestamp', lf.Type.STRING)
    .addColumn('cpu', lf.Type.NUMBER)
    .addPrimaryKey(['id']);

// Connect
schemaBuilder.connect().then(db => {
    const metricsTable = db.getSchema().table('metrics');

    // Insert
    const row = metricsTable.createRow({
        id: 1,
        timestamp: '2026-01-06T01:00:00Z',
        cpu: 45.2
    });

    db.insert().into(metricsTable).values([row]).exec();

    // Query
    db.select()
        .from(metricsTable)
        .where(metricsTable.cpu.gt(40))
        .exec()
        .then(results => console.log(results));
});
```

### 4. Absurd-SQL - SQLite for IndexedDB

**What it is**: sql.js + backend that persists to IndexedDB

**GitHub**: https://github.com/jlongster/absurd-sql
**License**: MIT

**Pros**:
- ✅ Full SQLite + automatic persistence
- ✅ Uses IndexedDB as backend
- ✅ Fast queries
- ✅ Large databases (gigabytes)

**Cons**:
- ⚠️ Requires Web Worker
- ⚠️ More complex setup
- ⚠️ Less mature

**Usage**:
```javascript
// In main thread
const worker = new Worker('/absurd-sql-worker.js');

// In worker
import initSqlJs from '@jlongster/sql.js';
import { SQLiteFS } from 'absurd-sql';
import IndexedDBBackend from 'absurd-sql/dist/indexeddb-backend';

initSqlJs({ locateFile: file => `/${file}` }).then(SQL => {
    const sqlFS = new SQLiteFS(SQL.FS, new IndexedDBBackend());
    SQL.register_for_idb(sqlFS);

    SQL.FS.mkdir('/sql');
    SQL.FS.mount(sqlFS, {}, '/sql');

    const db = new SQL.Database('/sql/metrics.db', { filename: true });

    // Use db normally - automatically persists to IndexedDB
    db.run('CREATE TABLE IF NOT EXISTS metrics (...)');
    db.run('INSERT INTO metrics VALUES (...)');
});
```

### 5. PGlite - PostgreSQL in Browser

**What it is**: PostgreSQL compiled to WASM

**GitHub**: https://github.com/electric-sql/pglite
**Size**: ~3 MB
**License**: Apache 2.0

**Pros**:
- ✅ Full PostgreSQL (most advanced SQL)
- ✅ Fast
- ✅ Modern, actively maintained
- ✅ Supports extensions

**Cons**:
- ⚠️ Larger size
- ⚠️ Newer/less tested
- ⚠️ Overkill for simple use cases

**Usage**:
```javascript
import { PGlite } from '@electric-sql/pglite';

const db = await PGlite.create();

await db.exec(`
    CREATE TABLE metrics (
        id SERIAL PRIMARY KEY,
        timestamp TIMESTAMPTZ,
        cpu REAL,
        memory REAL
    )
`);

await db.query(
    'INSERT INTO metrics (timestamp, cpu, memory) VALUES ($1, $2, $3)',
    ['2026-01-06T01:00:00Z', 45.2, 68.5]
);

const result = await db.query('SELECT * FROM metrics WHERE cpu > $1', [40]);
console.log(result.rows);
```

## Comparison Table

| Feature | sql.js | AlaSQL | Lovefield | Absurd-SQL | PGlite |
|---------|--------|--------|-----------|------------|--------|
| **Size** | 800 KB | 500 KB | 200 KB | 800 KB + worker | 3 MB |
| **SQL Standard** | ✅ SQLite | ⚠️ Extended | ❌ API only | ✅ SQLite | ✅ PostgreSQL |
| **Performance** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| **Persistence** | Manual | Manual | Auto | Auto | Auto |
| **Async** | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Maintenance** | ✅ Active | ✅ Active | ❌ Archived | ⚠️ Moderate | ✅ Active |
| **Learning Curve** | Easy | Easy | Medium | Hard | Easy |

## Recommendation for PSWebHost

### Best Choice: sql.js

**Why**:
1. ✅ Full SQLite - standard SQL syntax
2. ✅ Fast performance (WASM)
3. ✅ Can query metrics like you would in PowerShell
4. ✅ Export to .db file compatible with SQLite tools
5. ✅ Well-maintained and stable

**Implementation Example**:

```javascript
// Download sql.js
// https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.js
// https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.wasm

// Initialize once
let metricsDB = null;

const initMetricsDB = async () => {
    const SQL = await initSqlJs({
        locateFile: file => `/public/lib/${file}`
    });

    // Try to load from IndexedDB first
    const savedDB = await loadDBFromIndexedDB();

    if (savedDB) {
        metricsDB = new SQL.Database(savedDB);
    } else {
        metricsDB = new SQL.Database();

        // Create schema
        metricsDB.run(`
            CREATE TABLE metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                hostname TEXT,
                cpu_total REAL,
                cpu_cores TEXT,  -- JSON array
                memory_used_pct REAL,
                memory_total_gb REAL,
                memory_available_gb REAL,
                network_bytes_per_sec INTEGER,
                created_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
        `);

        // Create indexes
        metricsDB.run('CREATE INDEX idx_timestamp ON metrics(timestamp)');
        metricsDB.run('CREATE INDEX idx_cpu ON metrics(cpu_total)');
    }

    return metricsDB;
};

// Store metrics from polling
const storeMetric = (metricData) => {
    if (!metricsDB) return;

    metricsDB.run(`
        INSERT INTO metrics (
            timestamp, hostname, cpu_total, cpu_cores,
            memory_used_pct, memory_total_gb, memory_available_gb,
            network_bytes_per_sec
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `, [
        metricData.timestamp,
        metricData.hostname,
        metricData.cpu.total,
        JSON.stringify(metricData.cpu.cores),
        metricData.memory.usedPercent,
        metricData.memory.totalGB,
        metricData.memory.availableGB,
        metricData.network.bytesPerSec
    ]);

    // Cleanup old data (keep last 24 hours)
    metricsDB.run(`
        DELETE FROM metrics
        WHERE timestamp < datetime('now', '-24 hours')
    `);

    // Persist to IndexedDB periodically
    saveDBToIndexedDB();
};

// Query with SQL
const queryMetrics = (sqlQuery, params = []) => {
    if (!metricsDB) return [];

    const stmt = metricsDB.prepare(sqlQuery);
    stmt.bind(params);

    const results = [];
    while (stmt.step()) {
        results.push(stmt.getAsObject());
    }
    stmt.free();

    return results;
};

// Usage examples
const getHighCPU = () => {
    return queryMetrics(`
        SELECT timestamp, cpu_total, memory_used_pct
        FROM metrics
        WHERE cpu_total > 80
        ORDER BY timestamp DESC
        LIMIT 100
    `);
};

const getAverages = (minutes = 60) => {
    return queryMetrics(`
        SELECT
            strftime('%Y-%m-%d %H:%M', timestamp) as time_bucket,
            AVG(cpu_total) as avg_cpu,
            AVG(memory_used_pct) as avg_memory,
            MAX(cpu_total) as max_cpu,
            MIN(cpu_total) as min_cpu
        FROM metrics
        WHERE timestamp > datetime('now', '-' || ? || ' minutes')
        GROUP BY time_bucket
        ORDER BY time_bucket
    `, [minutes]);
};

const getCPUTrend = () => {
    return queryMetrics(`
        SELECT
            timestamp,
            cpu_total,
            AVG(cpu_total) OVER (
                ORDER BY timestamp
                ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
            ) as moving_avg
        FROM metrics
        ORDER BY timestamp DESC
        LIMIT 1000
    `);
};

// Persist to IndexedDB
const saveDBToIndexedDB = async () => {
    if (!metricsDB) return;

    const data = metricsDB.export();
    const request = indexedDB.open('PSWebHostMetrics', 1);

    request.onupgradeneeded = (event) => {
        const db = event.target.result;
        if (!db.objectStoreNames.contains('databases')) {
            db.createObjectStore('databases', { keyPath: 'id' });
        }
    };

    request.onsuccess = (event) => {
        const db = event.target.result;
        const tx = db.transaction(['databases'], 'readwrite');
        tx.objectStore('databases').put({ id: 'main', data: data });
    };
};

const loadDBFromIndexedDB = async () => {
    return new Promise((resolve) => {
        const request = indexedDB.open('PSWebHostMetrics', 1);

        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            if (!db.objectStoreNames.contains('databases')) {
                db.createObjectStore('databases', { keyPath: 'id' });
            }
        };

        request.onsuccess = (event) => {
            const db = event.target.result;
            const tx = db.transaction(['databases'], 'readonly');
            const req = tx.objectStore('databases').get('main');

            req.onsuccess = () => {
                resolve(req.result ? req.result.data : null);
            };

            req.onerror = () => resolve(null);
        };

        request.onerror = () => resolve(null);
    });
};
```

### Integration with MetricsManager

```javascript
class MetricsManager {
    constructor() {
        this.db = null;
        this.initSQL();
    }

    async initSQL() {
        this.db = await initMetricsDB();
    }

    startPolling(options) {
        // ... existing polling code ...

        const originalOnUpdate = options.onUpdate;
        options.onUpdate = (data) => {
            // Store to SQL database
            storeMetric(data);

            // Call original callback
            if (originalOnUpdate) originalOnUpdate(data);
        };
    }

    // New SQL query methods
    query(sql, params = []) {
        return queryMetrics(sql, params);
    }

    getAverages(minutes) {
        return getAverages(minutes);
    }

    getHighCPU() {
        return getHighCPU();
    }
}
```

## Alternative: Keep IndexedDB + Add Query Helper

If you don't want to add sql.js (800 KB), you can add a simple query helper for IndexedDB:

```javascript
class IndexedDBQueryHelper {
    constructor(db, storeName) {
        this.db = db;
        this.storeName = storeName;
    }

    // SQL-like WHERE clause
    where(filterFn) {
        return new Promise((resolve) => {
            const tx = this.db.transaction(this.storeName, 'readonly');
            const store = tx.objectStore(storeName);
            const request = store.openCursor();
            const results = [];

            request.onsuccess = (e) => {
                const cursor = e.target.result;
                if (cursor) {
                    if (filterFn(cursor.value)) {
                        results.push(cursor.value);
                    }
                    cursor.continue();
                } else {
                    resolve(results);
                }
            };
        });
    }

    // SQL-like ORDER BY
    orderBy(results, field, direction = 'ASC') {
        return results.sort((a, b) => {
            const aVal = a[field];
            const bVal = b[field];
            const comparison = aVal > bVal ? 1 : aVal < bVal ? -1 : 0;
            return direction === 'DESC' ? -comparison : comparison;
        });
    }

    // SQL-like LIMIT
    limit(results, count) {
        return results.slice(0, count);
    }

    // Chaining example
    async select() {
        return {
            where: async (fn) => {
                const results = await this.where(fn);
                return {
                    orderBy: (field, dir) => {
                        const sorted = this.orderBy(results, field, dir);
                        return {
                            limit: (count) => this.limit(sorted, count)
                        };
                    }
                };
            }
        };
    }
}

// Usage
const query = new IndexedDBQueryHelper(db, 'metrics');
const results = await query
    .select()
    .where(record => record.cpu > 80)
    .orderBy('timestamp', 'DESC')
    .limit(100);
```

## Summary

**For PSWebHost, I recommend sql.js** because:
1. Standard SQL syntax (familiar to developers)
2. Fast performance
3. Can export to SQLite files
4. Query complex metrics easily
5. Only 800 KB overhead

Download files and add to `/public/lib/`:
- https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.js
- https://cdnjs.cloudflare.com/ajax/libs/sql.js/1.8.0/sql-wasm.wasm
