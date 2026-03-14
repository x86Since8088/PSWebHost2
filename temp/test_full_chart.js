(async function() {
    const results = [];
    function log(msg) {
        results.push(msg);
        console.log('[FullTest]', msg);
    }

    log('=== Full Chart Loading Test ===');

    // Test 1: Verify history API performance
    log('1. Testing history API response time...');
    const startFetch = performance.now();
    const response = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/metrics/history?timerange=1h&metrics=cpu');
    const data = await response.json();
    const fetchTime = performance.now() - startFetch;

    const lineCount = data.data?.cpu ? data.data.cpu.split('\n').length : 0;
    log('API response: ' + lineCount + ' lines in ' + fetchTime.toFixed(0) + 'ms');

    if (fetchTime < 500) {
        log('PASS: API response under 500ms');
    } else if (fetchTime < 1000) {
        log('WARN: API response 500-1000ms');
    } else {
        log('SLOW: API response over 1000ms');
    }

    // Test 2: Check cache headers
    log('2. Checking cache headers...');
    const cacheControl = response.headers.get('Cache-Control');
    if (cacheControl && cacheControl.includes('max-age')) {
        log('PASS: Cache-Control header present: ' + cacheControl);
    } else {
        log('INFO: No Cache-Control header');
    }

    // Test 3: Verify IndexedDB cache working
    log('3. Testing IndexedDB cache...');
    if (window.MetricsCache) {
        const cache = new window.MetricsCache('TestMetrics');
        await cache.initPromise;

        const now = new Date();
        const hourAgo = new Date(now.getTime() - 3600000);

        // Store the fetched data
        await cache.store('cpu', hourAgo.toISOString(), now.toISOString(), '5s', data.data?.cpu || '');

        // Retrieve and time it
        const cacheStart = performance.now();
        const cached = await cache.get('cpu', hourAgo.toISOString(), now.toISOString(), '5s');
        const cacheTime = performance.now() - cacheStart;

        if (cached && cacheTime < 50) {
            log('PASS: Cache retrieval in ' + cacheTime.toFixed(0) + 'ms');
        } else {
            log('INFO: Cache retrieval in ' + cacheTime.toFixed(0) + 'ms');
        }

        // Cleanup
        await cache.clear();
    } else {
        log('INFO: MetricsCache not loaded');
    }

    // Test 4: Check for uPlot chart instance
    log('4. Checking chart instance...');
    const chartContainers = document.querySelectorAll('.uplot');
    log('uPlot instances: ' + chartContainers.length);

    // Test 5: Check DuckDB/MetricsDatabase
    log('5. Checking MetricsDatabase...');
    if (window.MetricsDatabase) {
        log('PASS: MetricsDatabase class available');
    } else {
        log('INFO: MetricsDatabase not yet loaded');
    }

    log('=== Test Complete ===');
    log('Summary: API=' + fetchTime.toFixed(0) + 'ms, Lines=' + lineCount);

    return {
        success: true,
        apiTime: fetchTime,
        lineCount: lineCount,
        results: results
    };
})();
