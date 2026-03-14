(async function() {
    const results = { tests: [], passed: 0, failed: 0 };

    function test(name, passed, error) {
        error = error || null;
        results.tests.push({ name, passed, error });
        if (passed) results.passed++;
        else results.failed++;
        console.log('[Test]', name, passed ? 'PASS' : 'FAIL', error || '');
    }

    // Test 1: MetricsDatabase class exists
    test('MetricsDatabase class exists', typeof window.MetricsDatabase !== 'undefined');

    // Test 2: Create new instance
    var db = null;
    try {
        db = new MetricsDatabase({
            dbName: 'TestMetrics',
            retentionHours: 1,
            maxRecords: 1000
        });
        test('MetricsDatabase constructor works', true);
    } catch (e) {
        test('MetricsDatabase constructor works', false, e.message);
    }

    // Test 3: Initialize (this triggers DuckDB worker)
    if (db) {
        try {
            await db.initialize();
            test('MetricsDatabase.initialize() succeeds', true);
            test('Worker ready flag is true', db.workerReady === true);
        } catch (e) {
            test('MetricsDatabase.initialize() succeeds', false, e.message);
            test('Worker ready flag is true', false, 'Init failed');
        }
    }

    // Test 4: Cleanup
    if (db && db.workerReady) {
        try {
            await db.destroy();
            test('MetricsDatabase.destroy() succeeds', true);
        } catch (e) {
            test('MetricsDatabase.destroy() succeeds', false, e.message);
        }
    }

    return {
        summary: results.passed + '/' + results.tests.length + ' tests passed',
        tests: results.tests
    };
})();
