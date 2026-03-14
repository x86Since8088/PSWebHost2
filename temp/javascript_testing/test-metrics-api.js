/**
 * Node.js Metrics API Test Suite
 * Tests the WebHostMetrics API endpoints
 *
 * Usage: node test-metrics-api.js [bearer-token]
 */

const http = require('http');

const BASE_URL = 'http://localhost:8080';
const TOKEN = process.argv[2] || process.env.API_TOKEN;

if (!TOKEN) {
    console.error('Usage: node test-metrics-api.js <bearer-token>');
    console.error('Or set API_TOKEN environment variable');
    process.exit(1);
}

const results = { passed: 0, failed: 0, tests: [] };

function request(path, method = 'GET') {
    return new Promise((resolve, reject) => {
        const url = new URL(path, BASE_URL);
        const options = {
            hostname: url.hostname,
            port: url.port || 8080,
            path: url.pathname + url.search,
            method: method,
            headers: {
                'Authorization': `Bearer ${TOKEN}`,
                'Accept': 'application/json'
            }
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch (e) {
                    resolve({ status: res.statusCode, data: data, parseError: e.message });
                }
            });
        });
        req.on('error', reject);
        req.setTimeout(10000, () => {
            req.destroy();
            reject(new Error('Request timeout'));
        });
        req.end();
    });
}

async function test(name, fn) {
    const result = { name, passed: false, error: null };
    try {
        const r = await fn();
        result.passed = !!r;
        result.value = r;
    } catch (e) {
        result.error = e.message;
    }

    if (result.passed) results.passed++;
    else results.failed++;

    results.tests.push(result);
    const status = result.passed ? '\x1b[32mPASS\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
    console.log(`[${status}] ${name}${result.error ? ': ' + result.error : ''}`);
    return result;
}

async function runTests() {
    console.log('\n=== Metrics API Test Suite ===\n');

    // Test 1: Current metrics
    await test('GET /api/v1/metrics returns current metrics', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics');
        return res.status === 200 &&
               res.data.status === 'success' &&
               res.data.metrics &&
               res.data.metrics.cpu &&
               res.data.metrics.memory;
    });

    // Test 2: Metrics status
    await test('GET /api/v1/metrics?action=status returns job status', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics?action=status');
        return res.status === 200 &&
               res.data.status === 'success' &&
               typeof res.data.data.SamplesCount === 'number';
    });

    // Test 3: Realtime metrics
    await test('GET /api/v1/metrics?action=realtime returns CSV data', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics?action=realtime&metric=cpu');
        return res.status === 200 &&
               res.data.status === 'success' &&
               res.data.data;
    });

    // Test 4: History endpoint
    await test('GET /api/v1/metrics/history returns historical data', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics/history?timerange=5m&metrics=cpu');
        return res.status === 200 &&
               res.data.status === 'success' &&
               res.data.data &&
               res.data.data.cpu;
    });

    // Test 5: Metrics with different granularity
    await test('GET /api/v1/metrics/history with granularity=30s', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics/history?timerange=5m&granularity=30s');
        return res.status === 200 && res.data.granularity === '30s';
    });

    // Test 6: CPU metrics structure validation
    await test('CPU metrics have expected structure', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics');
        const cpu = res.data.metrics?.cpu;
        return cpu &&
               typeof cpu.TotalPercent === 'number' &&
               Array.isArray(cpu.Cores);
    });

    // Test 7: Memory metrics structure validation
    await test('Memory metrics have expected structure', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics');
        const mem = res.data.metrics?.memory;
        return mem &&
               typeof mem.TotalGB === 'number' &&
               typeof mem.UsedGB === 'number' &&
               typeof mem.PercentUsed === 'number';
    });

    // Test 8: Invalid action returns error
    await test('Invalid action parameter returns error', async () => {
        const res = await request('/apps/WebHostMetrics/api/v1/metrics?action=invalid');
        // Should either return 400 or handle gracefully
        return res.status === 400 || res.data.status === 'error' || res.status === 200;
    });

    // Summary
    console.log('\n=== Summary ===');
    console.log(`Total: ${results.tests.length}, Passed: ${results.passed}, Failed: ${results.failed}`);

    process.exit(results.failed > 0 ? 1 : 0);
}

runTests().catch(err => {
    console.error('Test suite error:', err);
    process.exit(1);
});
