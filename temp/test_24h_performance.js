(async function() {
    const results = [];
    function log(msg) {
        results.push(msg);
        console.log('[24hTest]', msg);
    }

    log('=== 24-Hour Query Performance Test ===');

    // Test 24h query
    log('1. Testing 24h API query...');
    const start24h = performance.now();
    const response24h = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/metrics/history?timerange=24h&metrics=cpu');
    const data24h = await response24h.json();
    const time24h = performance.now() - start24h;

    const lines24h = data24h.data?.cpu ? data24h.data.cpu.split('\n').length : 0;
    log('24h: ' + lines24h + ' lines in ' + time24h.toFixed(0) + 'ms');

    // Test 24h with 1m granularity (downsampled)
    log('2. Testing 24h with 1m granularity...');
    const start24h1m = performance.now();
    const response24h1m = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/metrics/history?timerange=24h&metrics=cpu&granularity=1m');
    const data24h1m = await response24h1m.json();
    const time24h1m = performance.now() - start24h1m;

    const lines24h1m = data24h1m.data?.cpu ? data24h1m.data.cpu.split('\n').length : 0;
    log('24h@1m: ' + lines24h1m + ' lines in ' + time24h1m.toFixed(0) + 'ms');

    // Test 1h query for comparison
    log('3. Testing 1h query...');
    const start1h = performance.now();
    const response1h = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/metrics/history?timerange=1h&metrics=cpu');
    const data1h = await response1h.json();
    const time1h = performance.now() - start1h;

    const lines1h = data1h.data?.cpu ? data1h.data.cpu.split('\n').length : 0;
    log('1h: ' + lines1h + ' lines in ' + time1h.toFixed(0) + 'ms');

    log('=== Summary ===');
    log('24h raw: ' + time24h.toFixed(0) + 'ms (' + lines24h + ' lines)');
    log('24h@1m:  ' + time24h1m.toFixed(0) + 'ms (' + lines24h1m + ' lines)');
    log('1h raw:  ' + time1h.toFixed(0) + 'ms (' + lines1h + ' lines)');

    return {
        success: true,
        results: results,
        performance: {
            '24h': { time: time24h, lines: lines24h },
            '24h@1m': { time: time24h1m, lines: lines24h1m },
            '1h': { time: time1h, lines: lines1h }
        }
    };
})();
