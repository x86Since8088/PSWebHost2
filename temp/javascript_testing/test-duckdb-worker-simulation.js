/**
 * DuckDB Worker Message Simulation
 * Tests the message protocol used by metrics-worker.js
 *
 * Usage: node test-duckdb-worker-simulation.js
 */

const results = { passed: 0, failed: 0, tests: [] };

// Simulated worker message handlers
const WorkerMessages = {
    // INIT message
    createInitMessage(options = {}) {
        return {
            type: 'INIT',
            id: options.id || Date.now(),
            dbName: options.dbName || 'metrics',
            retentionHours: options.retentionHours || 24,
            maxRecords: options.maxRecords || 10000
        };
    },

    // INSERT message
    createInsertMessage(table, data, options = {}) {
        return {
            type: 'INSERT',
            id: options.id || Date.now(),
            table: table,
            data: data
        };
    },

    // QUERY message
    createQueryMessage(sql, options = {}) {
        return {
            type: 'QUERY',
            id: options.id || Date.now(),
            sql: sql
        };
    },

    // QUERY_FOR_CHART message
    createChartQueryMessage(options = {}) {
        return {
            type: 'QUERY_FOR_CHART',
            id: options.id || Date.now(),
            table: options.table || 'cpu_metrics',
            column: options.column || 'cpu_total',
            startTime: options.startTime || new Date(Date.now() - 3600000).toISOString(),
            endTime: options.endTime || new Date().toISOString(),
            pixelWidth: options.pixelWidth || 800
        };
    },

    // PRUNE message
    createPruneMessage(options = {}) {
        return {
            type: 'PRUNE',
            id: options.id || Date.now(),
            retentionHours: options.retentionHours || 24
        };
    },

    // CLOSE message
    createCloseMessage(options = {}) {
        return {
            type: 'CLOSE',
            id: options.id || Date.now()
        };
    }
};

// Simulated stub storage for testing
class StubStorage {
    constructor() {
        this.tables = {
            cpu_metrics: [],
            memory_metrics: [],
            disk_metrics: [],
            network_metrics: []
        };
    }

    insert(table, data) {
        if (!this.tables[table]) {
            throw new Error(`Unknown table: ${table}`);
        }
        this.tables[table].push({
            ...data,
            timestamp: data.timestamp || new Date().toISOString()
        });
        return { rowsAffected: 1 };
    }

    query(table, startTime, endTime) {
        if (!this.tables[table]) return [];
        return this.tables[table].filter(row => {
            const ts = new Date(row.timestamp);
            return ts >= new Date(startTime) && ts <= new Date(endTime);
        });
    }

    prune(table, cutoffTime) {
        if (!this.tables[table]) return 0;
        const before = this.tables[table].length;
        this.tables[table] = this.tables[table].filter(row => {
            return new Date(row.timestamp) >= new Date(cutoffTime);
        });
        return before - this.tables[table].length;
    }

    getCount(table) {
        return this.tables[table]?.length || 0;
    }
}

function test(name, fn) {
    const result = { name, passed: false, error: null };
    try {
        result.passed = !!fn();
    } catch (e) {
        result.error = e.message;
    }
    if (result.passed) results.passed++;
    else results.failed++;
    results.tests.push(result);
    const status = result.passed ? '\x1b[32mPASS\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
    console.log(`[${status}] ${name}${result.error ? ': ' + result.error : ''}`);
}

function runTests() {
    console.log('\n=== DuckDB Worker Message Simulation ===\n');

    const storage = new StubStorage();

    // Test 1: INIT message structure
    test('INIT message has required fields', () => {
        const msg = WorkerMessages.createInitMessage();
        return msg.type === 'INIT' &&
               typeof msg.id === 'number' &&
               typeof msg.dbName === 'string' &&
               typeof msg.retentionHours === 'number';
    });

    // Test 2: INSERT message structure
    test('INSERT message has required fields', () => {
        const msg = WorkerMessages.createInsertMessage('cpu_metrics', { cpu_total: 50 });
        return msg.type === 'INSERT' &&
               msg.table === 'cpu_metrics' &&
               typeof msg.data === 'object';
    });

    // Test 3: Insert operation
    test('Stub storage accepts INSERT', () => {
        const result = storage.insert('cpu_metrics', {
            timestamp: new Date().toISOString(),
            hostname: 'test',
            cpu_total: 45.5
        });
        return result.rowsAffected === 1;
    });

    // Test 4: Query operation
    test('Stub storage returns query results', () => {
        // Insert some data first
        const now = new Date();
        storage.insert('cpu_metrics', {
            timestamp: now.toISOString(),
            hostname: 'test',
            cpu_total: 55.0
        });

        const results = storage.query(
            'cpu_metrics',
            new Date(now.getTime() - 60000).toISOString(),
            new Date(now.getTime() + 60000).toISOString()
        );
        return results.length >= 1;
    });

    // Test 5: QUERY_FOR_CHART message structure
    test('QUERY_FOR_CHART message has chart params', () => {
        const msg = WorkerMessages.createChartQueryMessage({
            table: 'memory_metrics',
            column: 'used_mb',
            pixelWidth: 1200
        });
        return msg.type === 'QUERY_FOR_CHART' &&
               msg.table === 'memory_metrics' &&
               msg.pixelWidth === 1200;
    });

    // Test 6: PRUNE operation
    test('Stub storage prunes old records', () => {
        // Insert old data
        const oldTime = new Date(Date.now() - 86400000 * 2); // 2 days ago
        storage.tables.cpu_metrics.push({
            timestamp: oldTime.toISOString(),
            hostname: 'test',
            cpu_total: 10.0
        });

        const beforeCount = storage.getCount('cpu_metrics');
        const cutoff = new Date(Date.now() - 86400000); // 1 day ago
        const pruned = storage.prune('cpu_metrics', cutoff.toISOString());
        const afterCount = storage.getCount('cpu_metrics');

        return pruned > 0 && afterCount < beforeCount;
    });

    // Test 7: Invalid table handling
    test('Insert to invalid table throws error', () => {
        try {
            storage.insert('invalid_table', {});
            return false;
        } catch (e) {
            return e.message.includes('Unknown table');
        }
    });

    // Test 8: Memory metrics insert
    test('Memory metrics insert works', () => {
        const result = storage.insert('memory_metrics', {
            timestamp: new Date().toISOString(),
            hostname: 'test',
            used_mb: 8192,
            total_mb: 16384,
            percent_used: 50.0
        });
        return result.rowsAffected === 1 && storage.getCount('memory_metrics') > 0;
    });

    // Test 9: Network metrics insert
    test('Network metrics insert works', () => {
        const result = storage.insert('network_metrics', {
            timestamp: new Date().toISOString(),
            hostname: 'test',
            interface: 'eth0',
            bytes_per_sec: 1024000
        });
        return result.rowsAffected === 1;
    });

    // Test 10: Disk metrics insert
    test('Disk metrics insert works', () => {
        const result = storage.insert('disk_metrics', {
            timestamp: new Date().toISOString(),
            hostname: 'test',
            drive: 'C:',
            used_gb: 350.5,
            total_gb: 500.0,
            percent_used: 70.1
        });
        return result.rowsAffected === 1;
    });

    // Summary
    console.log('\n=== Summary ===');
    console.log(`Total: ${results.tests.length}, Passed: ${results.passed}, Failed: ${results.failed}`);

    // Show storage state
    console.log('\n=== Storage State ===');
    Object.entries(storage.tables).forEach(([table, rows]) => {
        console.log(`${table}: ${rows.length} rows`);
    });

    process.exit(results.failed > 0 ? 1 : 0);
}

runTests();
