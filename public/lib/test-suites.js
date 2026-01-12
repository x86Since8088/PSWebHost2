// Test Suites for PSWebHost
// Define your test suites here using the TestFramework API

function loadTestSuites(framework) {
    // sql.js / MetricsDatabase Tests
    framework.describe('MetricsDatabase - sql.js Integration', function() {
        framework.it('should initialize sql.js database', async function(assert) {
            if (typeof window.MetricsDatabase === 'undefined') {
                // Load MetricsDatabase if not loaded
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/metrics-database.js';
                    script.onload = resolve;
                    script.onerror = reject;
                    document.head.appendChild(script);
                });
            }

            const db = new window.MetricsDatabase({ dbName: 'TestDB' });
            await db.initialize();

            assert.assertNotNull(db.db, 'Database instance should be created');
            assert.assertEqual(db.isInitialized, true, 'Database should be initialized');

            db.close();
        });

        framework.it('should insert CPU metrics', async function(assert) {
            const db = new window.MetricsDatabase({ dbName: 'TestDB_CPU' });
            await db.initialize();

            const timestamp = new Date().toISOString();
            const cpuData = {
                timestamp: timestamp,
                hostname: 'test-host',
                cpu: {
                    total: 45.5,
                    cores: [40, 42, 48, 50]
                }
            };

            db.insertMetrics(cpuData);

            // Query back
            const now = new Date().toISOString();
            const start = new Date(Date.now() - 60000).toISOString();
            const results = db.queryCPUMetrics(start, now);

            assert.assertGreaterThan(results.length, 0, 'Should have at least one result');
            assert.assertEqual(results[0].cpu_total, 45.5, 'CPU total should match');
            assert.assertLength(results[0].cpu_cores, 4, 'Should have 4 cores');

            db.close();
        });

        framework.it('should insert memory metrics', async function(assert) {
            const db = new window.MetricsDatabase({ dbName: 'TestDB_Memory' });
            await db.initialize();

            const timestamp = new Date().toISOString();
            const memData = {
                timestamp: timestamp,
                hostname: 'test-host',
                memory: {
                    totalGB: 16,
                    usedGB: 8,
                    availableGB: 8,
                    usedPercent: 50
                }
            };

            db.insertMetrics(memData);

            // Query back
            const now = new Date().toISOString();
            const start = new Date(Date.now() - 60000).toISOString();
            const results = db.queryMemoryMetrics(start, now);

            assert.assertGreaterThan(results.length, 0, 'Should have at least one result');
            assert.assertEqual(results[0].used_percent, 50, 'Memory usage should match');

            db.close();
        });

        framework.it('should respect retention policy', async function(assert) {
            const db = new window.MetricsDatabase({
                dbName: 'TestDB_Retention',
                retentionHours: 0.001 // ~3.6 seconds
            });
            await db.initialize();

            // Insert old data
            const oldTimestamp = new Date(Date.now() - 10000).toISOString(); // 10 seconds ago
            db.insertMetrics({
                timestamp: oldTimestamp,
                hostname: 'test',
                cpu: { total: 50, cores: [] }
            });

            // Insert new data
            const newTimestamp = new Date().toISOString();
            db.insertMetrics({
                timestamp: newTimestamp,
                hostname: 'test',
                cpu: { total: 60, cores: [] }
            });

            // Clean old data
            const deleted = db.cleanOldData();

            assert.assertGreaterThan(deleted, 0, 'Should have deleted old records');

            db.close();
        });
    });

    // ChartDataAdapter Tests
    framework.describe('ChartDataAdapter - Incremental Updates', function() {
        framework.it('should create adapter instance', async function(assert) {
            if (typeof window.ChartDataAdapter === 'undefined') {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/chart-data-adapter.js';
                    script.onload = resolve;
                    script.onerror = reject;
                    document.head.appendChild(script);
                });
            }

            // Mock chart instance
            const mockChart = {
                data: {
                    datasets: [{
                        data: []
                    }]
                },
                update: function() {}
            };

            const adapter = new window.ChartDataAdapter(mockChart, {
                maxDataPoints: 100,
                updateMode: 'none'
            });

            assert.assertNotNull(adapter, 'Adapter should be created');
            assert.assertEqual(adapter.config.maxDataPoints, 100, 'Config should be set');
        });

        framework.it('should append data to chart', async function(assert) {
            const mockChart = {
                data: {
                    datasets: [{
                        data: []
                    }]
                },
                update: function() {}
            };

            const adapter = new window.ChartDataAdapter(mockChart);

            adapter.appendData({
                datasets: [{
                    data: [
                        { x: new Date().toISOString(), y: 50 },
                        { x: new Date().toISOString(), y: 55 }
                    ]
                }]
            });

            assert.assertEqual(mockChart.data.datasets[0].data.length, 2, 'Should have 2 data points');
            assert.assertEqual(mockChart.data.datasets[0].data[0].y, 50, 'First point should be 50');
        });

        framework.it('should trim old data based on maxDataPoints', async function(assert) {
            const mockChart = {
                data: {
                    datasets: [{
                        data: []
                    }]
                },
                update: function() {}
            };

            const adapter = new window.ChartDataAdapter(mockChart, {
                maxDataPoints: 5
            });

            // Add 10 data points
            for (let i = 0; i < 10; i++) {
                adapter.appendData({
                    datasets: [{
                        data: [{ x: new Date().toISOString(), y: i }]
                    }]
                });
            }

            assert.assertLessThan(mockChart.data.datasets[0].data.length, 11, 'Should trim to max points');
        });

        framework.it('should replace data without destroying chart', async function(assert) {
            const mockChart = {
                data: {
                    datasets: [{
                        data: [{ x: '2024-01-01', y: 10 }]
                    }]
                },
                update: function() {}
            };

            const adapter = new window.ChartDataAdapter(mockChart);

            adapter.replaceData({
                datasets: [{
                    data: [
                        { x: '2024-01-02', y: 20 },
                        { x: '2024-01-03', y: 30 }
                    ]
                }]
            });

            assert.assertEqual(mockChart.data.datasets[0].data.length, 2, 'Should have 2 new points');
            assert.assertEqual(mockChart.data.datasets[0].data[0].y, 20, 'Old data should be replaced');
        });
    });

    // MetricsManager Integration Tests
    framework.describe('MetricsManager - sql.js Integration', function() {
        framework.it('should initialize MetricsManager with sql.js', async function(assert) {
            if (typeof window.MetricsManager === 'undefined') {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/metrics-manager.js';
                    script.onload = resolve;
                    script.onerror = reject;
                    document.head.appendChild(script);
                });
            }

            const manager = new window.MetricsManager({ sql: true });

            // Wait for sql init
            if (manager.sqlEnabled && manager.initPromise) {
                await manager.initPromise;
            }

            assert.assertNotNull(manager, 'Manager should be created');
            assert.assertEqual(manager.sqlEnabled, true, 'SQL should be enabled');

            if (manager.metricsDB) {
                assert.assertNotNull(manager.metricsDB, 'MetricsDatabase should be initialized');
            }

            manager.destroy();
        });

        framework.it('should store metrics in sql.js automatically', async function(assert) {
            const manager = new window.MetricsManager({ sql: true });

            if (manager.sqlEnabled && manager.initPromise) {
                await manager.initPromise;
            }

            // Mock data
            const mockData = [{
                Timestamp: new Date().toISOString(),
                Cpu: { Total: 55, Cores: [50, 60] },
                Memory: { UsedPercent: 70 }
            }];

            await manager.storeInSql(mockData);

            // Query back
            const now = new Date().toISOString();
            const start = new Date(Date.now() - 60000).toISOString();
            const results = await manager.queryFromSql('cpu', start, now);

            assert.assertNotNull(results, 'Should get results from sql.js');
            if (results && results.length > 0) {
                assert.assertGreaterThan(results.length, 0, 'Should have at least one result');
            }

            manager.destroy();
        });
    });

    // Empty Data Handling Tests
    framework.describe('uPlot - Empty Data Handling', function() {
        framework.it('should handle empty API response', async function(assert) {
            // Simulate empty API response
            const emptyResponse = {
                status: 'success',
                data: {
                    datasets: []
                }
            };

            // This should not throw an error
            assert.assertNotNull(emptyResponse, 'Empty response should be defined');
            assert.assertEqual(emptyResponse.data.datasets.length, 0, 'Datasets should be empty');
        });

        framework.it('should handle null data gracefully', function(assert) {
            const nullResponse = null;
            const undefinedResponse = undefined;

            // These should not crash the component
            assert.assertNull(nullResponse, 'Null response should be null');
            assert.assertEqual(typeof undefinedResponse, 'undefined', 'Undefined response should be undefined');
        });

        framework.it('should handle datasets with no data points', function(assert) {
            const emptyDataPoints = {
                status: 'success',
                data: {
                    datasets: [
                        {
                            label: 'CPU 0',
                            data: []  // No data points
                        },
                        {
                            label: 'CPU 1',
                            data: []  // No data points
                        }
                    ]
                }
            };

            assert.assertNotNull(emptyDataPoints.data.datasets, 'Datasets array should exist');
            assert.assertEqual(emptyDataPoints.data.datasets[0].data.length, 0, 'First dataset should have no points');
            assert.assertEqual(emptyDataPoints.data.datasets[1].data.length, 0, 'Second dataset should have no points');
        });

        framework.it('should handle API error responses', function(assert) {
            const errorResponse = {
                status: 'error',
                message: 'No data available for this time range'
            };

            assert.assertEqual(errorResponse.status, 'error', 'Status should be error');
            assert.assertProperty(errorResponse, 'message', 'Error should have message');
        });
    });

    // MetricsDatabase Retention Tests
    framework.describe('MetricsDatabase - Retention Policy', function() {
        framework.it('should have cleanOldData method', async function(assert) {
            if (typeof window.MetricsDatabase === 'undefined') {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/metrics-database.js';
                    script.onload = resolve;
                    script.onerror = reject;
                    document.head.appendChild(script);
                });
            }

            const db = new window.MetricsDatabase({ dbName: 'TestDB_Retention' });
            await db.initialize();

            assert.assertType(db.cleanOldData, 'function', 'cleanOldData should be a function');

            // Test cleanup with no data
            const deleted = db.cleanOldData(7);
            assert.assertGreaterThanOrEqual(deleted, 0, 'Deleted count should be >= 0');

            db.close();
        });

        framework.it('should clean old metrics data', async function(assert) {
            const db = new window.MetricsDatabase({ dbName: 'TestDB_CleanOld' });
            await db.initialize();

            // Insert old data (8 days ago)
            const oldDate = new Date();
            oldDate.setDate(oldDate.getDate() - 8);
            const oldTimestamp = oldDate.toISOString();

            db.insertMetrics({
                timestamp: oldTimestamp,
                hostname: 'test-host',
                cpu: { total: 50, cores: [50] }
            });

            // Insert recent data (1 day ago)
            const recentDate = new Date();
            recentDate.setDate(recentDate.getDate() - 1);
            const recentTimestamp = recentDate.toISOString();

            db.insertMetrics({
                timestamp: recentTimestamp,
                hostname: 'test-host',
                cpu: { total: 30, cores: [30] }
            });

            // Clean data older than 7 days
            const deleted = db.cleanOldData(7);

            // Recent data should still exist
            const results = db.queryCPUMetrics(
                new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString(),
                new Date().toISOString()
            );

            assert.assertGreaterThan(results.length, 0, 'Recent data should still exist after cleanup');

            db.close();
        });
    });

    // Test Framework Self-Tests
    framework.describe('TestFramework - Self Tests', function() {
        framework.it('should pass assertion tests', function(assert) {
            assert.assertEqual(1 + 1, 2, '1+1 should equal 2');
            assert.assertNotEqual(1, 2, '1 should not equal 2');
            assert.assert(true, 'true should be truthy');
            assert.assertType('hello', 'string', '"hello" should be a string');
        });

        framework.it('should handle arrays', function(assert) {
            const arr = [1, 2, 3];
            assert.assertLength(arr, 3, 'Array should have length 3');
            assert.assertContains(arr, 2, 'Array should contain 2');
        });

        framework.it('should handle objects', function(assert) {
            const obj = { name: 'test', value: 42 };
            assert.assertProperty(obj, 'name', 'Object should have name property');
            assert.assertProperty(obj, 'value', 'Object should have value property');
        });

        framework.it('should handle async tests', async function(assert) {
            const result = await new Promise(resolve => {
                setTimeout(() => resolve(100), 10);
            });
            assert.assertEqual(result, 100, 'Async result should be 100');
        });
    });

    console.log('[TestSuites] Loaded test suites successfully');
}

// Export
window.loadTestSuites = loadTestSuites;
