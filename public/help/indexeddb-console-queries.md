# IndexedDB Console Queries Guide

## Overview

IndexedDB can be queried directly from the browser's developer console for debugging and inspection.

## Basic Database Operations

### 1. List All Databases

```javascript
// Modern browsers
indexedDB.databases().then(dbs => {
    console.table(dbs);
    dbs.forEach(db => console.log(`${db.name} (v${db.version})`));
});
```

**Output**:
```
MetricsManagerDB (v1)
MetricsCacheDB (v1)
```

### 2. Open a Database

```javascript
const dbName = 'MetricsManagerDB';
const request = indexedDB.open(dbName);

request.onsuccess = (event) => {
    const db = event.target.result;
    console.log('Database opened:', db.name);
    console.log('Version:', db.version);
    console.log('Object Stores:', Array.from(db.objectStoreNames));

    // Store in global variable for easy access
    window.db = db;
};

request.onerror = (event) => {
    console.error('Error opening database:', event.target.error);
};
```

### 3. List Object Stores

```javascript
// After opening database
const db = window.db;
console.log('Object Stores:', Array.from(db.objectStoreNames));

// Example output: ["historical", "samples"]
```

## Reading Data

### 4. Get All Records from Object Store

```javascript
const getAllRecords = (storeName) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const request = store.getAll();

        request.onsuccess = () => {
            console.log(`${storeName} records:`, request.result);
            console.log(`Total count: ${request.result.length}`);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
getAllRecords('historical').then(records => {
    console.table(records);
});
```

### 5. Get All Keys

```javascript
const getAllKeys = (storeName) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const request = store.getAllKeys();

        request.onsuccess = () => {
            console.log(`${storeName} keys:`, request.result);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
getAllKeys('historical');
```

### 6. Get Single Record by Key

```javascript
const getRecord = (storeName, key) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const request = store.get(key);

        request.onsuccess = () => {
            console.log(`Record for key "${key}":`, request.result);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
getRecord('historical', 'system_metrics_2026-01-06T01:30:00.000Z');
```

### 7. Count Records

```javascript
const countRecords = (storeName) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const request = store.count();

        request.onsuccess = () => {
            console.log(`${storeName} count:`, request.result);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
countRecords('historical');
```

### 8. Query by Index

```javascript
const queryByIndex = (storeName, indexName, value) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const index = store.index(indexName);
        const request = index.getAll(value);

        request.onsuccess = () => {
            console.log(`Records where ${indexName} = ${value}:`, request.result);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage - Find all records for a specific dataset
queryByIndex('historical', 'dataset', 'system_metrics');

// Find records by timestamp
queryByIndex('historical', 'timestamp', '2026-01-06T01:30:00.000Z');
```

### 9. Query with Cursor (Filter Records)

```javascript
const filterRecords = (storeName, filterFn) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const request = store.openCursor();
        const results = [];

        request.onsuccess = (event) => {
            const cursor = event.target.result;
            if (cursor) {
                if (filterFn(cursor.value)) {
                    results.push(cursor.value);
                }
                cursor.continue();
            } else {
                console.log('Filtered results:', results);
                console.log(`Found ${results.length} matches`);
                resolve(results);
            }
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage - Find records with CPU > 80%
filterRecords('historical', record => {
    return record.data?.Cpu?.Total > 80;
}).then(records => {
    console.table(records);
});

// Find recent records (last hour)
const oneHourAgo = new Date(Date.now() - 60*60*1000).toISOString();
filterRecords('historical', record => {
    return record.timestamp > oneHourAgo;
});
```

### 10. Query by Time Range

```javascript
const getTimeRange = (storeName, startTime, endTime) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);
        const index = store.index('timestamp');

        // Create key range
        const range = IDBKeyRange.bound(startTime, endTime);
        const request = index.getAll(range);

        request.onsuccess = () => {
            console.log(`Records from ${startTime} to ${endTime}:`, request.result);
            console.log(`Count: ${request.result.length}`);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
const start = '2026-01-06T00:00:00.000Z';
const end = '2026-01-06T01:00:00.000Z';
getTimeRange('historical', start, end);
```

## Writing Data

### 11. Add Single Record

```javascript
const addRecord = (storeName, record) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        const request = store.add(record);

        request.onsuccess = () => {
            console.log('Record added with key:', request.result);
            resolve(request.result);
        };

        request.onerror = () => {
            console.error('Error adding record:', request.error);
            reject(request.error);
        };
    });
};

// Usage
addRecord('historical', {
    id: 'test_' + Date.now(),
    dataset: 'test_data',
    timestamp: new Date().toISOString(),
    data: { value: 123 }
});
```

### 12. Update Record

```javascript
const updateRecord = (storeName, record) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        const request = store.put(record);  // put = add or update

        request.onsuccess = () => {
            console.log('Record updated:', request.result);
            resolve(request.result);
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
updateRecord('historical', {
    id: 'existing_key',
    dataset: 'system_metrics',
    timestamp: new Date().toISOString(),
    data: { value: 456 }
});
```

### 13. Delete Record

```javascript
const deleteRecord = (storeName, key) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        const request = store.delete(key);

        request.onsuccess = () => {
            console.log(`Record with key "${key}" deleted`);
            resolve();
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
deleteRecord('historical', 'test_1234567890');
```

### 14. Clear All Records

```javascript
const clearStore = (storeName) => {
    return new Promise((resolve, reject) => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readwrite');
        const store = tx.objectStore(storeName);
        const request = store.clear();

        request.onsuccess = () => {
            console.log(`All records cleared from ${storeName}`);
            resolve();
        };

        request.onerror = () => reject(request.error);
    });
};

// Usage
clearStore('historical');
```

## Analysis and Statistics

### 15. Analyze Dataset

```javascript
const analyzeDataset = async (storeName) => {
    const db = window.db;
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);

    // Get all records
    const records = await new Promise((resolve) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result);
    });

    // Calculate statistics
    const stats = {
        totalRecords: records.length,
        datasets: {},
        timeRange: {
            earliest: null,
            latest: null
        },
        sizeEstimate: JSON.stringify(records).length
    };

    // Group by dataset
    records.forEach(record => {
        const ds = record.dataset || 'unknown';
        if (!stats.datasets[ds]) {
            stats.datasets[ds] = 0;
        }
        stats.datasets[ds]++;

        // Track time range
        if (record.timestamp) {
            if (!stats.timeRange.earliest || record.timestamp < stats.timeRange.earliest) {
                stats.timeRange.earliest = record.timestamp;
            }
            if (!stats.timeRange.latest || record.timestamp > stats.timeRange.latest) {
                stats.timeRange.latest = record.timestamp;
            }
        }
    });

    console.log('Dataset Analysis:', stats);
    console.log('Size:', (stats.sizeEstimate / 1024).toFixed(2), 'KB');
    return stats;
};

// Usage
analyzeDataset('historical');
```

### 16. Find Duplicate Records

```javascript
const findDuplicates = async (storeName, keyProperty = 'timestamp') => {
    const db = window.db;
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);

    const records = await new Promise((resolve) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result);
    });

    const seen = new Map();
    const duplicates = [];

    records.forEach(record => {
        const key = record[keyProperty];
        if (seen.has(key)) {
            duplicates.push({ key, records: [seen.get(key), record] });
        } else {
            seen.set(key, record);
        }
    });

    console.log(`Found ${duplicates.length} duplicate ${keyProperty} values`);
    console.table(duplicates);
    return duplicates;
};

// Usage
findDuplicates('historical', 'timestamp');
```

## Utility Functions

### 17. Database Inspector (All-in-One)

```javascript
const inspectDB = async (dbName) => {
    // Open database
    const db = await new Promise((resolve, reject) => {
        const req = indexedDB.open(dbName);
        req.onsuccess = () => resolve(req.target.result);
        req.onerror = () => reject(req.error);
    });

    console.log('=== Database Info ===');
    console.log('Name:', db.name);
    console.log('Version:', db.version);
    console.log('Object Stores:', Array.from(db.objectStoreNames));

    // Inspect each object store
    for (const storeName of db.objectStoreNames) {
        console.log(`\n=== Object Store: ${storeName} ===`);

        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);

        // Get count
        const count = await new Promise((resolve) => {
            const req = store.count();
            req.onsuccess = () => resolve(req.result);
        });
        console.log('Record count:', count);

        // Get indexes
        console.log('Indexes:', Array.from(store.indexNames));

        // Get sample records
        const samples = await new Promise((resolve) => {
            const req = store.getAll(null, 5);  // Get first 5
            req.onsuccess = () => resolve(req.result);
        });
        console.log('Sample records:');
        console.table(samples);
    }

    db.close();
};

// Usage
inspectDB('MetricsManagerDB');
```

### 18. Export to JSON

```javascript
const exportToJSON = async (storeName) => {
    const db = window.db;
    const tx = db.transaction(storeName, 'readonly');
    const store = tx.objectStore(storeName);

    const records = await new Promise((resolve) => {
        const req = store.getAll();
        req.onsuccess = () => resolve(req.result);
    });

    const json = JSON.stringify(records, null, 2);

    // Copy to clipboard
    navigator.clipboard.writeText(json).then(() => {
        console.log('Exported to clipboard!');
        console.log(`${records.length} records exported`);
    });

    // Or download as file
    const blob = new Blob([json], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `${storeName}_export_${Date.now()}.json`;
    a.click();

    return records;
};

// Usage
exportToJSON('historical');
```

### 19. Import from JSON

```javascript
const importFromJSON = async (storeName, jsonData) => {
    const db = window.db;
    const tx = db.transaction(storeName, 'readwrite');
    const store = tx.objectStore(storeName);

    const records = typeof jsonData === 'string' ? JSON.parse(jsonData) : jsonData;

    let count = 0;
    for (const record of records) {
        await new Promise((resolve, reject) => {
            const req = store.add(record);
            req.onsuccess = () => {
                count++;
                resolve();
            };
            req.onerror = () => reject(req.error);
        });
    }

    console.log(`Imported ${count} records into ${storeName}`);
    return count;
};

// Usage
const data = [...];  // Your JSON data
importFromJSON('historical', data);
```

### 20. Delete Database

```javascript
const deleteDatabase = (dbName) => {
    return new Promise((resolve, reject) => {
        const request = indexedDB.deleteDatabase(dbName);

        request.onsuccess = () => {
            console.log(`Database "${dbName}" deleted successfully`);
            resolve();
        };

        request.onerror = () => {
            console.error('Error deleting database:', request.error);
            reject(request.error);
        };

        request.onblocked = () => {
            console.warn('Delete blocked. Close all tabs using this database.');
        };
    });
};

// Usage
deleteDatabase('MetricsManagerDB');
```

## Debugging Helpers

### 21. Watch for Changes

```javascript
const watchStore = (storeName, interval = 5000) => {
    let lastCount = 0;

    const check = async () => {
        const db = window.db;
        const tx = db.transaction(storeName, 'readonly');
        const store = tx.objectStore(storeName);

        const count = await new Promise((resolve) => {
            const req = store.count();
            req.onsuccess = () => resolve(req.result);
        });

        if (count !== lastCount) {
            console.log(`${storeName} changed: ${lastCount} → ${count} (${count - lastCount > 0 ? '+' : ''}${count - lastCount})`);
            lastCount = count;
        }
    };

    check();
    const intervalId = setInterval(check, interval);

    console.log(`Watching ${storeName} every ${interval}ms. Stop with: clearInterval(${intervalId})`);
    return intervalId;
};

// Usage
const watchId = watchStore('historical', 5000);
// Stop watching: clearInterval(watchId);
```

### 22. Performance Test

```javascript
const performanceTest = async (storeName, operationCount = 1000) => {
    const db = window.db;

    console.log(`Running performance test: ${operationCount} operations`);

    // Test writes
    const writeStart = performance.now();
    const tx1 = db.transaction(storeName, 'readwrite');
    const store1 = tx1.objectStore(storeName);

    for (let i = 0; i < operationCount; i++) {
        store1.add({
            id: `perf_test_${Date.now()}_${i}`,
            dataset: 'performance_test',
            timestamp: new Date().toISOString(),
            data: { value: Math.random() * 100 }
        });
    }

    await new Promise((resolve) => {
        tx1.oncomplete = resolve;
    });

    const writeEnd = performance.now();
    console.log(`Write: ${operationCount} records in ${(writeEnd - writeStart).toFixed(2)}ms`);
    console.log(`Average: ${((writeEnd - writeStart) / operationCount).toFixed(2)}ms per record`);

    // Test reads
    const readStart = performance.now();
    const tx2 = db.transaction(storeName, 'readonly');
    const store2 = tx2.objectStore(storeName);

    await new Promise((resolve) => {
        const req = store2.getAll();
        req.onsuccess = resolve;
    });

    const readEnd = performance.now();
    console.log(`Read: All records in ${(readEnd - readStart).toFixed(2)}ms`);

    // Cleanup
    const tx3 = db.transaction(storeName, 'readwrite');
    const store3 = tx3.objectStore(storeName);
    const index = store3.index('dataset');
    const range = IDBKeyRange.only('performance_test');

    await new Promise((resolve) => {
        const req = index.openCursor(range);
        req.onsuccess = (event) => {
            const cursor = event.target.result;
            if (cursor) {
                cursor.delete();
                cursor.continue();
            } else {
                resolve();
            }
        };
    });

    console.log('Cleanup complete');
};

// Usage
performanceTest('historical', 1000);
```

## Quick Reference

```javascript
// Open database and store globally
const openDB = (name) => {
    const req = indexedDB.open(name);
    req.onsuccess = () => { window.db = req.result; console.log('DB ready'); };
};

// Essential queries
openDB('MetricsManagerDB');
getAllRecords('historical');
countRecords('historical');
queryByIndex('historical', 'dataset', 'system_metrics');
analyzeDataset('historical');
inspectDB('MetricsManagerDB');
```

## Browser DevTools Alternative

You can also use the browser's built-in IndexedDB inspector:

1. Open DevTools (F12)
2. Go to **Application** tab (Chrome/Edge) or **Storage** tab (Firefox)
3. Expand **IndexedDB** in the left sidebar
4. Browse databases, object stores, and records visually

This provides:
- Visual tree view of data
- Easy record inspection
- Quick delete operations
- No code required
