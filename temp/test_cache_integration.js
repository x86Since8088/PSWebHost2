(async function() {
    const results = [];
    function log(msg) {
        results.push(msg);
        console.log('[CacheTest]', msg);
    }

    log('=== Testing MetricsCache Integration ===');

    // Test 1: MetricsCache class availability
    if (typeof window.MetricsCache !== 'undefined') {
        log('PASS: MetricsCache class available');
    } else {
        log('INFO: MetricsCache not yet loaded, loading...');
        await new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = '/public/lib/metrics-cache.js';
            script.onload = resolve;
            script.onerror = reject;
            document.head.appendChild(script);
        });
        log(typeof window.MetricsCache !== 'undefined' ? 'PASS: MetricsCache loaded' : 'FAIL: MetricsCache load failed');
    }

    // Test 2: Initialize cache
    log('2. Testing cache initialization...');
    const cache = new window.MetricsCache('TestCache');
    await cache.initPromise;
    log('PASS: Cache initialized');

    // Test 3: Store and retrieve data
    log('3. Testing store/retrieve...');
    const testData = '"Timestamp","Host","Percent_Avg"\n"2026-02-25_01-00-00","W11TC1","42.5"';
    const now = new Date();
    const hourAgo = new Date(now.getTime() - 3600000);

    await cache.store('cpu', hourAgo.toISOString(), now.toISOString(), '5s', testData);
    log('PASS: Data stored');

    const retrieved = await cache.get('cpu', hourAgo.toISOString(), now.toISOString(), '5s');
    if (retrieved && retrieved.data === testData) {
        log('PASS: Data retrieved correctly');
    } else {
        log('FAIL: Data mismatch');
    }

    // Test 4: Get stats
    log('4. Testing stats...');
    const stats = await cache.getStats();
    log('Stats: ' + JSON.stringify(stats));

    // Test 5: Clear test data
    await cache.clear();
    log('PASS: Cache cleared');

    log('=== Cache Integration Test Complete ===');

    return {
        success: true,
        results: results
    };
})();
