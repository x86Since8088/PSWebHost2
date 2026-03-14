/**
 * uPlot Data Format Test Suite
 * Tests data transformation for uPlot charts
 *
 * Usage: node test-uplot-data-format.js
 */

const results = { passed: 0, failed: 0, tests: [] };

/**
 * Transform metrics data to uPlot format
 * uPlot expects: [[timestamps], [series1], [series2], ...]
 */
function toUplotFormat(data, valueKey = 'value') {
    if (!Array.isArray(data) || data.length === 0) {
        return [[], []];
    }

    const timestamps = [];
    const values = [];

    data.forEach(row => {
        // Convert timestamp to epoch seconds
        const ts = new Date(row.timestamp || row.Timestamp).getTime() / 1000;
        if (!isNaN(ts)) {
            timestamps.push(ts);
            values.push(row[valueKey] ?? null);
        }
    });

    return [timestamps, values];
}

/**
 * Transform multi-series data to uPlot format
 */
function toUplotMultiSeries(data, seriesKeys) {
    if (!Array.isArray(data) || data.length === 0) {
        return [[], ...seriesKeys.map(() => [])];
    }

    const timestamps = [];
    const series = seriesKeys.map(() => []);

    data.forEach(row => {
        const ts = new Date(row.timestamp || row.Timestamp).getTime() / 1000;
        if (!isNaN(ts)) {
            timestamps.push(ts);
            seriesKeys.forEach((key, i) => {
                series[i].push(row[key] ?? null);
            });
        }
    });

    return [timestamps, ...series];
}

/**
 * Parse CSV to row objects
 */
function parseCSV(csv) {
    const lines = csv.trim().split('\n');
    if (lines.length < 2) return [];

    const headers = lines[0].split(',').map(h => h.trim());
    const rows = [];

    for (let i = 1; i < lines.length; i++) {
        const values = lines[i].split(',');
        const row = {};
        headers.forEach((h, idx) => {
            let val = values[idx]?.trim() || '';
            const num = parseFloat(val);
            row[h] = isNaN(num) ? val : num;
        });
        rows.push(row);
    }

    return rows;
}

/**
 * Fill gaps in time series data
 */
function fillGaps(data, intervalMs = 5000) {
    if (data[0].length < 2) return data;

    const [timestamps, ...series] = data;
    const filledTimestamps = [];
    const filledSeries = series.map(() => []);

    for (let i = 0; i < timestamps.length; i++) {
        const ts = timestamps[i];
        filledTimestamps.push(ts);
        series.forEach((s, si) => filledSeries[si].push(s[i]));

        // Check for gap
        if (i < timestamps.length - 1) {
            const nextTs = timestamps[i + 1];
            const gap = (nextTs - ts) * 1000; // Convert to ms

            if (gap > intervalMs * 1.5) {
                // Fill with nulls
                let fillTs = ts + intervalMs / 1000;
                while (fillTs < nextTs - intervalMs / 2000) {
                    filledTimestamps.push(fillTs);
                    series.forEach((_, si) => filledSeries[si].push(null));
                    fillTs += intervalMs / 1000;
                }
            }
        }
    }

    return [filledTimestamps, ...filledSeries];
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
    console.log('\n=== uPlot Data Format Test Suite ===\n');

    // Sample test data
    const sampleData = [
        { timestamp: '2026-02-24T10:00:00Z', value: 45.5 },
        { timestamp: '2026-02-24T10:00:05Z', value: 48.2 },
        { timestamp: '2026-02-24T10:00:10Z', value: 52.1 },
        { timestamp: '2026-02-24T10:00:15Z', value: 49.8 }
    ];

    // Test 1: Basic conversion
    test('toUplotFormat returns correct structure', () => {
        const result = toUplotFormat(sampleData);
        return Array.isArray(result) &&
               result.length === 2 &&
               Array.isArray(result[0]) &&
               Array.isArray(result[1]);
    });

    // Test 2: Timestamps are epoch seconds
    test('Timestamps are in epoch seconds', () => {
        const [timestamps] = toUplotFormat(sampleData);
        // 2026-02-24T10:00:00Z should be > 1700000000
        return timestamps[0] > 1700000000 && timestamps[0] < 2000000000;
    });

    // Test 3: Values are preserved
    test('Values are correctly mapped', () => {
        const [_, values] = toUplotFormat(sampleData);
        return values[0] === 45.5 && values[2] === 52.1;
    });

    // Test 4: Empty data handling
    test('Empty array returns empty uPlot data', () => {
        const result = toUplotFormat([]);
        return result[0].length === 0 && result[1].length === 0;
    });

    // Test 5: Multi-series data
    test('Multi-series conversion works', () => {
        const multiData = [
            { timestamp: '2026-02-24T10:00:00Z', cpu: 45, memory: 60 },
            { timestamp: '2026-02-24T10:00:05Z', cpu: 48, memory: 62 }
        ];
        const result = toUplotMultiSeries(multiData, ['cpu', 'memory']);
        return result.length === 3 &&
               result[1][0] === 45 &&
               result[2][0] === 60;
    });

    // Test 6: CSV parsing
    test('CSV parsing extracts rows', () => {
        const csv = 'Timestamp,Value\n2026-02-24T10:00:00Z,45.5\n2026-02-24T10:00:05Z,48.2';
        const rows = parseCSV(csv);
        return rows.length === 2 && rows[0].Value === 45.5;
    });

    // Test 7: Numeric values in CSV are parsed
    test('CSV numeric values are numbers', () => {
        const csv = 'Timestamp,CPU,Memory\n2026-02-24T10:00:00Z,45.5,8192';
        const rows = parseCSV(csv);
        return typeof rows[0].CPU === 'number' && typeof rows[0].Memory === 'number';
    });

    // Test 8: Gap filling
    test('fillGaps inserts nulls for missing data', () => {
        const gappyData = [
            [1708764000, 1708764020], // 20 second gap at 5s interval
            [45, 50]
        ];
        const filled = fillGaps(gappyData, 5000);
        // Should have inserted ~3 null points
        return filled[0].length > 2 && filled[1].includes(null);
    });

    // Test 9: Handle null values
    test('Null values are preserved', () => {
        const dataWithNull = [
            { timestamp: '2026-02-24T10:00:00Z', value: 45 },
            { timestamp: '2026-02-24T10:00:05Z', value: null }
        ];
        const [_, values] = toUplotFormat(dataWithNull);
        return values[1] === null;
    });

    // Test 10: Timestamp column name variations
    test('Handles Timestamp vs timestamp', () => {
        const data1 = [{ Timestamp: '2026-02-24T10:00:00Z', value: 45 }];
        const data2 = [{ timestamp: '2026-02-24T10:00:00Z', value: 45 }];
        const [ts1] = toUplotFormat(data1);
        const [ts2] = toUplotFormat(data2);
        return ts1[0] === ts2[0];
    });

    // Summary
    console.log('\n=== Summary ===');
    console.log(`Total: ${results.tests.length}, Passed: ${results.passed}, Failed: ${results.failed}`);

    // Demo output
    console.log('\n=== Sample uPlot Data ===');
    const uplotData = toUplotFormat(sampleData);
    console.log('Timestamps:', uplotData[0]);
    console.log('Values:', uplotData[1]);

    process.exit(results.failed > 0 ? 1 : 0);
}

runTests();
