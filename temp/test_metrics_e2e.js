(async function() {
    var results = [];
    function log(msg) {
        results.push(msg);
        console.log('[E2E]', msg);
    }
    function fail(msg) {
        results.push('FAIL: ' + msg);
        console.error('[E2E] FAIL:', msg);
    }
    function pass(msg) {
        results.push('PASS: ' + msg);
        console.log('[E2E] PASS:', msg);
    }

    log('=== MetricsDatabase End-to-End Test ===');

    // 1. Load script
    log('1. Loading metrics-database.js');
    await new Promise(function(resolve, reject) {
        if (typeof window.MetricsDatabase !== 'undefined') {
            log('Script already loaded');
            resolve();
            return;
        }
        var script = document.createElement('script');
        script.src = '/public/lib/metrics-database.js';
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
    });
    pass('Script loaded');

    // 2. Create and initialize
    log('2. Creating and initializing MetricsDatabase');
    var db = new window.MetricsDatabase({
        dbName: 'E2ETestDB',
        retentionHours: 1,
        maxRecords: 1000
    });
    await db.initialize();
    pass('Database initialized, workerReady=' + db.workerReady);

    // 3. Insert metrics
    log('3. Inserting test metrics');
    var timestamp = new Date().toISOString();
    await db.insertMetrics({
        timestamp: timestamp,
        hostname: 'test-host',
        cpu: { total: 42.5 },
        memory: { usedMB: 8192, totalMB: 16384, percentUsed: 50 }
    });
    pass('Metrics inserted');

    // 4. Query data
    log('4. Querying CPU metrics');
    var cpuRows = await db.query('SELECT * FROM cpu_metrics');
    if (cpuRows.length > 0) {
        pass('CPU query returned ' + cpuRows.length + ' rows');
        log('First row: ' + JSON.stringify(cpuRows[0]));
    } else {
        fail('CPU query returned 0 rows');
    }

    // 5. Query memory
    log('5. Querying Memory metrics');
    var memRows = await db.query('SELECT * FROM memory_metrics');
    if (memRows.length > 0) {
        pass('Memory query returned ' + memRows.length + ' rows');
    } else {
        fail('Memory query returned 0 rows');
    }

    // 6. Test batch insert
    log('6. Testing batch insert');
    var batchData = [];
    for (var i = 0; i < 5; i++) {
        batchData.push({
            timestamp: new Date(Date.now() + i * 1000).toISOString(),
            hostname: 'batch-test',
            cpu: { total: 30 + i * 5 }
        });
    }
    await db.insertMetricsBatch(batchData);
    var afterBatch = await db.query('SELECT * FROM cpu_metrics');
    if (afterBatch.length >= 6) {
        pass('Batch insert worked, total rows: ' + afterBatch.length);
    } else {
        fail('Batch insert may have failed, rows: ' + afterBatch.length);
    }

    // 7. Export to JSON
    log('7. Testing exportToJSON');
    var exportData = await db.exportToJSON();
    var parsed = JSON.parse(exportData);
    if (parsed.cpu_metrics && parsed.memory_metrics) {
        pass('Export contains cpu_metrics and memory_metrics');
    } else {
        fail('Export missing expected tables');
    }

    // 8. Cleanup
    log('8. Cleaning up');
    await db.destroy();
    pass('Database destroyed');

    // Summary
    var passed = results.filter(function(r) { return r.startsWith('PASS:'); }).length;
    var failed = results.filter(function(r) { return r.startsWith('FAIL:'); }).length;
    log('=== Summary: ' + passed + ' passed, ' + failed + ' failed ===');

    return {
        success: failed === 0,
        passed: passed,
        failed: failed,
        results: results
    };
})();
