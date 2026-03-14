/**
 * In-Browser Metrics System Test Suite
 * Execute via Debug_Client_Command_Enqueue.ps1 -Type eval
 * Results logged via window.logToServer() to server TSV logs
 */

(async function runMetricsTests() {
    const results = {
        timestamp: new Date().toISOString(),
        tests: [],
        passed: 0,
        failed: 0
    };

    function log(msg, level = 'Info', data = null) {
        if (window.logToServer) {
            window.logToServer(msg, 'MetricsTest', level, data);
        }
        console.log('[MetricsTest]', level, msg, data || '');
    }

    function test(name, fn) {
        const result = { name, passed: false, error: null };
        try {
            const r = fn();
            result.passed = !!r;
            result.value = r;
            if (result.passed) results.passed++;
            else results.failed++;
        } catch (e) {
            result.error = e.message;
            results.failed++;
        }
        results.tests.push(result);
        log('Test: ' + name + ' - ' + (result.passed ? 'PASS' : 'FAIL'),
            result.passed ? 'Info' : 'Warning',
            { passed: result.passed, error: result.error });
        return result;
    }

    async function testAsync(name, fn) {
        const result = { name, passed: false, error: null };
        try {
            const r = await fn();
            result.passed = !!r;
            result.value = r;
            if (result.passed) results.passed++;
            else results.failed++;
        } catch (e) {
            result.error = e.message;
            results.failed++;
        }
        results.tests.push(result);
        log('Test: ' + name + ' - ' + (result.passed ? 'PASS' : 'FAIL'),
            result.passed ? 'Info' : 'Warning',
            { passed: result.passed, error: result.error });
        return result;
    }

    log('=== Starting Metrics Test Suite ===');

    // Test 1: API Data Retrieval
    await testAsync('API metrics endpoint returns data', async () => {
        const resp = await fetch('/apps/WebHostMetrics/api/v1/metrics');
        if (!resp.ok) return false;
        const data = await resp.json();
        return data.status === 'success' && data.metrics;
    });

    // Test 2: API History endpoint
    await testAsync('API history endpoint returns CSV data', async () => {
        const resp = await fetch('/apps/WebHostMetrics/api/v1/metrics/history?timerange=5m');
        if (!resp.ok) return false;
        const data = await resp.json();
        return data.status === 'success' && data.data;
    });

    // Test 3: MetricsDatabase class availability
    test('MetricsDatabase class is defined', () => {
        return typeof window.MetricsDatabase !== 'undefined';
    });

    // Test 4: uPlot library availability
    test('uPlot library is loaded', () => {
        return typeof window.uPlot !== 'undefined';
    });

    // Test 5: Worker availability check
    test('Metrics worker exists or can be created', () => {
        // Check if there's already a worker
        if (window._metricsWorker) return true;
        // Check if Worker is supported
        return typeof Worker !== 'undefined';
    });

    // Test 6: DuckDB-WASM file accessibility
    await testAsync('DuckDB WASM module is accessible', async () => {
        const resp = await fetch('/public/lib/duckdb-browser.mjs', { method: 'HEAD' });
        return resp.ok;
    });

    // Test 7: DuckDB WASM binary accessibility
    await testAsync('DuckDB WASM binary is accessible', async () => {
        const resp = await fetch('/public/lib/duckdb-mvp.wasm', { method: 'HEAD' });
        return resp.ok;
    });

    // Test 8: Metrics worker JS accessibility
    await testAsync('Metrics worker script is accessible', async () => {
        const resp = await fetch('/public/lib/metrics-worker.js', { method: 'HEAD' });
        return resp.ok;
    });

    // Summary
    log('=== Test Suite Complete ===', 'Info', {
        total: results.tests.length,
        passed: results.passed,
        failed: results.failed
    });

    return results;
})();
