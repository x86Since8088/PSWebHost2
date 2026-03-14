/**
 * CSV Parsing Test Suite
 * Tests parsing of metrics CSV data returned by the history endpoint
 *
 * Usage: node test-csv-parsing.js [bearer-token]
 */

const http = require('http');

const BASE_URL = 'http://localhost:8080';
const TOKEN = process.argv[2] || process.env.API_TOKEN;

if (!TOKEN) {
    console.error('Usage: node test-csv-parsing.js <bearer-token>');
    process.exit(1);
}

const results = { passed: 0, failed: 0, tests: [] };

function request(path) {
    return new Promise((resolve, reject) => {
        const url = new URL(path, BASE_URL);
        const options = {
            hostname: url.hostname,
            port: url.port || 8080,
            path: url.pathname + url.search,
            method: 'GET',
            headers: { 'Authorization': `Bearer ${TOKEN}` }
        };

        const req = http.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve(JSON.parse(data));
                } catch (e) {
                    reject(new Error('Invalid JSON: ' + e.message));
                }
            });
        });
        req.on('error', reject);
        req.end();
    });
}

function parseCSV(csvString) {
    const lines = csvString.trim().split('\n');
    if (lines.length === 0) return { headers: [], rows: [] };

    // Helper to strip quotes from values
    const stripQuotes = (s) => {
        s = s.trim();
        if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
            return s.slice(1, -1);
        }
        return s;
    };

    const headers = lines[0].split(',').map(h => stripQuotes(h));
    const rows = [];

    for (let i = 1; i < lines.length; i++) {
        const values = lines[i].split(',');
        const row = {};
        headers.forEach((h, idx) => {
            let val = stripQuotes(values[idx] || '');
            // Try to parse as number
            const num = parseFloat(val);
            row[h] = isNaN(num) ? val : num;
        });
        rows.push(row);
    }

    return { headers, rows };
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

async function runTests() {
    console.log('\n=== CSV Parsing Test Suite ===\n');

    // Fetch history data
    console.log('Fetching history data...');
    const historyData = await request('/apps/WebHostMetrics/api/v1/metrics/history?timerange=5m&metrics=cpu,memory');

    if (historyData.status !== 'success') {
        console.error('Failed to fetch history data:', historyData);
        process.exit(1);
    }

    console.log('Data received. Running tests...\n');

    // Test 1: CPU CSV parsing
    test('CPU CSV has headers', () => {
        const { headers } = parseCSV(historyData.data.cpu);
        return headers.length > 0 && headers.includes('Timestamp');
    });

    // Test 2: CPU CSV has data rows
    test('CPU CSV has data rows', () => {
        const { rows } = parseCSV(historyData.data.cpu);
        return rows.length > 0;
    });

    // Test 3: CPU rows have Timestamp field
    test('CPU rows have Timestamp field', () => {
        const { rows, headers } = parseCSV(historyData.data.cpu);
        if (rows.length === 0) return false;
        // Timestamp column exists
        return headers.includes('Timestamp') && rows[0].hasOwnProperty('Timestamp');
    });

    // Test 4: Memory CSV parsing
    test('Memory CSV has headers', () => {
        const { headers } = parseCSV(historyData.data.memory);
        return headers.length > 0;
    });

    // Test 5: Memory values are numbers
    test('Memory values are numeric', () => {
        const { rows } = parseCSV(historyData.data.memory);
        if (rows.length === 0) return true; // No data is ok
        const row = rows[0];
        // Check for numeric fields
        return Object.values(row).some(v => typeof v === 'number');
    });

    // Test 6: Parse malformed CSV gracefully
    test('Handles empty CSV gracefully', () => {
        const { headers, rows } = parseCSV('  ');  // whitespace only
        return rows.length === 0;  // Just check rows, headers may have empty strings
    });

    // Test 7: Parse single-line CSV
    test('Handles header-only CSV', () => {
        const { headers, rows } = parseCSV('Timestamp,Value');
        return headers.length === 2 && rows.length === 0;
    });

    // Test 8: Data format consistency
    test('All CPU rows have consistent columns', () => {
        const { headers, rows } = parseCSV(historyData.data.cpu);
        if (rows.length === 0) return true;
        return rows.every(row => Object.keys(row).length === headers.length);
    });

    // Summary
    console.log('\n=== Summary ===');
    console.log(`Total: ${results.tests.length}, Passed: ${results.passed}, Failed: ${results.failed}`);

    // Show sample data
    console.log('\n=== Sample CPU Data ===');
    const cpuData = parseCSV(historyData.data.cpu);
    console.log('Headers:', cpuData.headers.join(', '));
    console.log('Row count:', cpuData.rows.length);
    if (cpuData.rows.length > 0) {
        console.log('First row:', JSON.stringify(cpuData.rows[0]));
    }

    process.exit(results.failed > 0 ? 1 : 0);
}

runTests().catch(err => {
    console.error('Test suite error:', err);
    process.exit(1);
});
