(async function() {
    const results = [];
    function log(msg) {
        results.push(msg);
        console.log('[ChartTest]', msg);
    }

    log('=== Testing Chart Data Loading ===');

    // Test 1: Fetch history API
    log('1. Fetching history API (1h CPU)...');
    try {
        const response = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/metrics/history?timerange=1h&metrics=cpu');
        const data = await response.json();
        log('Status: ' + data.status);
        log('Sources: ' + data.sources);
        if (data.data && data.data.cpu) {
            const lines = data.data.cpu.split('\n');
            log('CPU data lines: ' + lines.length);
            log('Header: ' + lines[0]);
            log('First row: ' + lines[1]);
        } else {
            log('ERROR: No CPU data in response');
        }
    } catch (e) {
        log('ERROR: ' + e.message);
    }

    // Test 2: Check MetricsDatabase
    log('');
    log('2. Checking MetricsDatabase...');
    if (typeof window.MetricsDatabase !== 'undefined') {
        log('MetricsDatabase class available');
    } else {
        log('MetricsDatabase class NOT available');
    }

    // Test 3: Check for existing chart instance
    log('');
    log('3. Checking for chart instances...');
    const chartContainers = document.querySelectorAll('.uplot');
    log('uPlot instances found: ' + chartContainers.length);

    log('');
    log('=== Test Complete ===');

    return {
        success: true,
        results: results
    };
})();
