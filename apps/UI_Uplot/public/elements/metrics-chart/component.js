// Generic uPlot Component
// Provides reusable charting with configurable data sources and polling
// 4x better performance than Chart.js (10% CPU vs 40%, 12MB vs 77MB)

const UPlotComponent = ({ element, onError }) => {
    // State variables - minimized for performance (chart instance stored in ref only)
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [isPaused, setIsPaused] = React.useState(false);
    const [selectedTimeRange, setSelectedTimeRange] = React.useState('1h');
    const [selectedGranularity, setSelectedGranularity] = React.useState('15s');
    const containerRef = React.useRef(null);
    const pollTimerRef = React.useRef(null);
    const historyRefreshTimerRef = React.useRef(null);
    const configRef = React.useRef({});
    const adapterRef = React.useRef(null);
    const uplotInstanceRef = React.useRef(null);  // Ref for immediate access to chart instance
    const incrementalFetchCountRef = React.useRef(0);  // Track incremental fetch count for debug logging
    const metricsDbRef = React.useRef(null);  // sql.js MetricsDatabase instance
    const lastHistoryFetchRef = React.useRef(null);  // Track last history fetch time
    const isMountedRef = React.useRef(true);  // Track if component is mounted
    const fetchLockRef = React.useRef(false);  // Timer mutex to prevent overlapping fetches

    // Performance tracking refs
    const timerMutexHitCountRef = React.useRef(0);
    const unmountAbortCountRef = React.useRef(0);
    const chartUpdateCountRef = React.useRef(0);
    const rafTimingsRef = React.useRef([]);

    /**
     * Helper to log to server - uses window.logToServer (capital T)
     * Signature: window.logToServer(message, category, level, data)
     */
    const logToServer = React.useCallback((level, message, context = {}) => {
        if (typeof window !== 'undefined' && window.logToServer) {
            try {
                window.logToServer(message, 'MetricsChart', level, context);
            } catch (e) {
                console.warn('[MetricsChart] Failed to log to server:', e);
            }
        }
    }, []);

    // Parse configuration from element.url
    React.useEffect(() => {
        if (!element || !element.url) {
            if (!isMountedRef.current) return; // Component unmounted
            setError('No configuration URL provided');
            setLoading(false);
            return;
        }

        const url = new URL(element.url, window.location.origin);
        const params = url.searchParams;

        const initialTimeRange = params.get('timerange') || '1h';
        const initialGranularity = params.get('granularity') || '15s';

        setSelectedTimeRange(initialTimeRange);
        setSelectedGranularity(initialGranularity);

        configRef.current = {
            source: params.get('source') || '',
            sourceMethod: params.get('sourcemethod') || 'GET',
            contentType: params.get('contenttype') || 'json',
            delay: Math.max(5, parseInt(params.get('delay') || '5', 10)),
            title: params.get('title') || 'Chart',
            xAxisLabel: params.get('xlabel') || 'Time',
            yAxisLabel: params.get('ylabel') || 'Value',
            timeRange: initialTimeRange,  // Display window (default: 1 hour)
            granularity: initialGranularity,  // Data collection interval (default: 15 seconds)
            metric: params.get('metric') || 'cpu',
            height: parseInt(params.get('height') || '300', 10),
            historyEndpoint: params.get('historyEndpoint') || '/apps/WebHostMetrics/api/v1/metrics/history',
            realtimeEndpoint: params.get('realtimeEndpoint') || '/apps/WebHostMetrics/api/v1/metrics',
            sourceParams: {}
        };

        // Collect other params to pass to source
        for (const [key, value] of params.entries()) {
            if (!['source', 'sourcemethod', 'contenttype', 'delay', 'title', 'xlabel', 'ylabel', 'height'].includes(key)) {
                configRef.current.sourceParams[key] = value;
            }
        }

        if (!configRef.current.source) {
            if (!isMountedRef.current) return; // Component unmounted
            setError('No data source specified. Use ?source=/api/...');
            setLoading(false);
            return;
        }
    }, [element?.url]);

    // State to track if libraries are loaded
    const [librariesLoaded, setLibrariesLoaded] = React.useState(false);

    // Load uPlot and dependencies if not already loaded
    React.useEffect(() => {
        const loadScripts = async () => {
            // Check if uPlot is already loaded
            if (typeof uPlot !== 'undefined' && window.UPlotDataAdapter) {
                console.log('uPlot libraries already loaded');
                if (!isMountedRef.current) return; // Component unmounted
                setLibrariesLoaded(true);
                return;
            }

            try {
                // Load CSS first
                if (!document.querySelector('link[href="/public/lib/uPlot.min.css"]')) {
                    const cssLink = document.createElement('link');
                    cssLink.rel = 'stylesheet';
                    cssLink.href = '/public/lib/uPlot.min.css';
                    document.head.appendChild(cssLink);
                }

                // Load uPlot library
                if (typeof uPlot === 'undefined') {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/uPlot.iife.min.js';
                        script.onload = () => {
                            console.log('uPlot loaded');
                            resolve();
                        };
                        script.onerror = () => reject(new Error('Failed to load uPlot'));
                        document.head.appendChild(script);
                    });
                }

                // Load UPlotDataAdapter
                if (!window.UPlotDataAdapter) {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/uplot-data-adapter.js';
                        script.onload = () => {
                            console.log('UPlotDataAdapter loaded');
                            resolve();
                        };
                        script.onerror = () => reject(new Error('Failed to load UPlotDataAdapter'));
                        document.head.appendChild(script);
                    });
                }

                if (!isMountedRef.current) return; // Component unmounted
                setLibrariesLoaded(true);
            } catch (err) {
                console.error('Script loading error:', err);
                if (!isMountedRef.current) return; // Component unmounted
                setError(err.message);
                setLoading(false);
            }
        };

        loadScripts();
    }, []);

    // Initialize sql.js database and fetch initial data
    React.useEffect(() => {
        if (!librariesLoaded) return;

        const initializeDatabase = async () => {
            try {
                // Load MetricsDatabase if not already loaded
                if (!window.MetricsDatabase) {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/metrics-database.js';
                        script.onload = resolve;
                        script.onerror = reject;
                        document.head.appendChild(script);
                    });
                }

                // Initialize database instance
                metricsDbRef.current = new window.MetricsDatabase({ dbName: `uplot_${configRef.current.metric}` });
                await metricsDbRef.current.initialize();
                console.log(`[uPlot DEBUG] 💾 sql.js database initialized for ${configRef.current.metric}`);

                // Fetch initial history data
                await fetchHistoryData();

                // Start incremental polling (CSV data every 5 seconds)
                startIncrementalPolling();

                // Start history refresh (every 15 minutes)
                startHistoryRefresh();

            } catch (err) {
                console.error('[uPlot] Database initialization error:', err);
                if (!isMountedRef.current) return; // Component unmounted
                setError(err.message);
                setLoading(false);
            }
        };

        initializeDatabase();

        return () => {
            if (pollTimerRef.current) {
                clearInterval(pollTimerRef.current);
            }
            if (historyRefreshTimerRef.current) {
                clearInterval(historyRefreshTimerRef.current);
            }
            if (metricsDbRef.current) {
                metricsDbRef.current.close();
            }
        };
    }, [librariesLoaded, element?.url]);

    // Cleanup on unmount only
    React.useEffect(() => {
        isMountedRef.current = true;
        logToServer('Info', 'Component mounted', {
            metric: configRef.current.metric || 'unknown'
        });

        return () => {
            isMountedRef.current = false;

            // Log final statistics on unmount
            const avgRafDelay = rafTimingsRef.current.length > 0
                ? (rafTimingsRef.current.reduce((a, b) => a + b, 0) / rafTimingsRef.current.length).toFixed(2)
                : 0;

            logToServer('Info', 'Component unmounting - final stats', {
                metric: configRef.current.metric || 'unknown',
                chartUpdates: chartUpdateCountRef.current,
                timerMutexHits: timerMutexHitCountRef.current,
                unmountAborts: unmountAbortCountRef.current,
                avgRafDelay: avgRafDelay,
                incrementalFetches: incrementalFetchCountRef.current
            });

            if (uplotInstanceRef.current) {
                console.log('[uPlot DEBUG] ❌ Chart DESTROYED on component unmount');
                uplotInstanceRef.current.destroy();
                uplotInstanceRef.current = null;
            }
            if (adapterRef.current) {
                adapterRef.current.destroy();
                adapterRef.current = null;
            }
        };
    }, [logToServer]);

    // Fetch historical data from /apps/WebHostMetrics/api/v1/metrics/history (called once on load, then every 15 min)
    const fetchHistoryData = async () => {
        // Prevent overlapping fetches with timer mutex
        if (fetchLockRef.current) {
            timerMutexHitCountRef.current++;
            console.log('[uPlot] Skipping overlapping history fetch');
            logToServer('Warn', 'Timer mutex hit - skipping overlapping history fetch', {
                mutexHitCount: timerMutexHitCountRef.current,
                metric: configRef.current.metric
            });
            return;
        }

        if (isPaused) return;

        fetchLockRef.current = true;
        const fetchStartTime = performance.now();
        try {
            const config = configRef.current;
            const historyUrl = new URL(config.historyEndpoint, window.location.origin);
            historyUrl.searchParams.set('metric', config.metric);
            historyUrl.searchParams.set('timerange', config.timeRange);
            historyUrl.searchParams.set('granularity', config.granularity);

            const response = await window.psweb_fetchWithAuthHandling(historyUrl.toString());
            if (!isMountedRef.current) {
                unmountAbortCountRef.current++;
                logToServer('Warn', 'Unmount protection triggered - aborting history fetch', {
                    abortCount: unmountAbortCountRef.current,
                    stage: 'after-fetch'
                });
                return;
            }

            if (!response.ok) {
                const error = new Error(`History endpoint returned ${response.status}`);
                error.status = response.status;
                error.statusText = response.statusText;
                throw error;
            }

            const responseData = await response.json();
            if (!isMountedRef.current) {
                unmountAbortCountRef.current++;
                logToServer('Warn', 'Unmount protection triggered - aborting history parse', {
                    abortCount: unmountAbortCountRef.current,
                    stage: 'after-json-parse'
                });
                return;
            }

            // DEBUG: Log history response details
            let totalRecords = 0;
            if (responseData.data && responseData.data.datasets) {
                responseData.data.datasets.forEach(dataset => {
                    if (dataset.data && Array.isArray(dataset.data)) {
                        totalRecords += dataset.data.length;
                    }
                });
            }
            const fetchDuration = performance.now() - fetchStartTime;
            console.log(`[uPlot DEBUG] 📥 /apps/WebHostMetrics/api/v1/metrics/history response: ${totalRecords} total data points, ${responseData.data?.datasets?.length || 0} datasets, granularity: ${responseData.granularity}, sampleCount: ${responseData.sampleCount}`);

            logToServer('Info', 'History data fetched', {
                totalRecords: totalRecords,
                datasets: responseData.data?.datasets?.length || 0,
                granularity: responseData.granularity,
                sampleCount: responseData.sampleCount,
                fetchDuration: fetchDuration.toFixed(2)
            });

            // Insert into sql.js database
            if (totalRecords > 0 && metricsDbRef.current) {
                await insertDataIntoSqlJs(responseData, 'history');
                if (!isMountedRef.current) return;  // Check after await
            }

            lastHistoryFetchRef.current = new Date();

            // Update chart from sql.js
            await updateChartFromSqlJs();
            if (!isMountedRef.current) return;  // Check after await

            setError(null);
            setLoading(false);
        } catch (err) {
            if (isMountedRef.current) {
                console.error('[uPlot] History fetch error:', err);
                setError(err.message);
                setLoading(false);
            }
        } finally {
            fetchLockRef.current = false;
        }
    };

    // Fetch incremental data from /apps/WebHostMetrics/api/v1/metrics (CSV files, called every 5 seconds)
    const fetchIncrementalData = async () => {
        // Prevent overlapping fetches with timer mutex
        if (fetchLockRef.current) {
            timerMutexHitCountRef.current++;
            console.log('[uPlot] Skipping overlapping incremental fetch');
            logToServer('Warn', 'Timer mutex hit - skipping overlapping incremental fetch', {
                mutexHitCount: timerMutexHitCountRef.current,
                metric: configRef.current.metric
            });
            return;
        }

        if (isPaused || !metricsDbRef.current) return;

        fetchLockRef.current = true;
        const fetchStartTime = performance.now();
        try {
            const config = configRef.current;
            const incrementalUrl = new URL(config.realtimeEndpoint, window.location.origin);
            incrementalUrl.searchParams.set('action', 'realtime');
            incrementalUrl.searchParams.set('metric', config.metric);
            incrementalUrl.searchParams.set('granularity', config.granularity);

            // Only fetch last 1 minute of CSV data
            const lastMinute = new Date(Date.now() - 60000).toISOString();
            incrementalUrl.searchParams.set('starting', lastMinute);

            const response = await window.psweb_fetchWithAuthHandling(incrementalUrl.toString());
            if (!isMountedRef.current) {
                unmountAbortCountRef.current++;
                logToServer('Warn', 'Unmount protection triggered - aborting incremental fetch', {
                    abortCount: unmountAbortCountRef.current,
                    stage: 'after-fetch'
                });
                return;
            }

            if (!response.ok) return; // Silently skip if no new data

            const responseData = await response.json();
            if (!isMountedRef.current) {
                unmountAbortCountRef.current++;
                logToServer('Warn', 'Unmount protection triggered - aborting incremental parse', {
                    abortCount: unmountAbortCountRef.current,
                    stage: 'after-json-parse'
                });
                return;
            }

            // Count incremental fetches (reduced logging)
            incrementalFetchCountRef.current++;
            if (incrementalFetchCountRef.current === 1) {
                let totalRecords = 0;
                if (responseData.data) {
                    Object.values(responseData.data).forEach(tableData => {
                        if (Array.isArray(tableData)) {
                            totalRecords += tableData.length;
                        }
                    });
                }
                console.log(`[uPlot DEBUG] 📊 First incremental fetch: ${totalRecords} CSV records`);
            }

            // Insert into sql.js database (with deduplication)
            if (responseData.data && Object.keys(responseData.data).length > 0) {
                await insertDataIntoSqlJs(responseData, 'incremental');
                if (!isMountedRef.current) return;  // Check after await

                // Update chart from sql.js
                await updateChartFromSqlJs();
                if (!isMountedRef.current) return;  // Check after await
            }

        } catch (err) {
            // Silently log incremental errors (don't disrupt the UI)
            if (isMountedRef.current && incrementalFetchCountRef.current <= 5) {
                console.warn('[uPlot] Incremental fetch error:', err.message);
            }
        } finally {
            fetchLockRef.current = false;
        }
    };

    // Insert API data into sql.js database
    const insertDataIntoSqlJs = async (responseData, source) => {
        if (!metricsDbRef.current || !isMountedRef.current) return;

        const metric = configRef.current.metric;
        let insertCount = 0;

        try {
            if (source === 'history') {
                // History format: { data: { cpu: "CSV string..." } }
                // Parse CSV data from history endpoint
                const csvData = responseData.data?.[metric];
                if (!csvData || typeof csvData !== 'string') return;

                const lines = csvData.split('\n').filter(line => line.trim());
                if (lines.length < 2) return; // Need at least header + 1 row

                // Parse header
                const header = lines[0].replace(/"/g, '').split(',');
                const timestampIdx = header.indexOf('Timestamp');
                const percentAvgIdx = header.indexOf('Percent_Avg');
                const hostIdx = header.indexOf('Host');

                if (timestampIdx === -1 || percentAvgIdx === -1) {
                    console.warn('[uPlot] CSV header missing required columns');
                    return;
                }

                // OPTIMIZATION: Collect all rows for batch insert (35-70x faster)
                const batchData = [];
                for (let i = 1; i < lines.length; i++) {
                    const values = lines[i].match(/(".*?"|[^,]+)(?=\s*,|\s*$)/g);
                    if (!values || values.length < header.length) continue;

                    const timestamp = values[timestampIdx].replace(/"/g, '');
                    const percentAvg = parseFloat(values[percentAvgIdx].replace(/"/g, ''));
                    const host = hostIdx >= 0 ? values[hostIdx].replace(/"/g, '') : 'local';

                    if (!timestamp || isNaN(percentAvg)) continue;

                    // Convert timestamp format: "2026-02-09_22-16-00" -> ISO
                    let isoTimestamp = timestamp;
                    if (timestamp.includes('_') && timestamp.includes('-')) {
                        const localTimeStr = timestamp.replace('_', 'T').replace(/-/g, (match, offset) => {
                            const dashCount = (timestamp.substring(0, offset).match(/-/g) || []).length;
                            return dashCount < 2 ? '-' : ':';
                        });
                        const localDate = new Date(localTimeStr);
                        isoTimestamp = localDate.toISOString();
                    }

                    batchData.push({
                        timestamp: isoTimestamp,
                        hostname: host,
                        cpu: {
                            total: percentAvg
                        }
                    });
                    insertCount++;
                }

                // Insert all at once (35-70x faster than individual inserts)
                if (batchData.length > 0) {
                    await metricsDbRef.current.insertMetricsBatch(batchData);
                    if (!isMountedRef.current) return;  // Check after await
                    console.log(`[uPlot DEBUG] 📊 Batch inserted ${insertCount} history records`);
                }

            } else if (source === 'incremental') {
                // Incremental format: { data: { Perf_CPUCore: [{Timestamp, ...}] } }
                for (const [tableName, records] of Object.entries(responseData.data)) {
                    if (!Array.isArray(records)) continue;
                    if (!isMountedRef.current) return;  // Check before processing each table

                    for (let idx = 0; idx < records.length; idx++) {
                        const record = records[idx];
                        const timestamp = record.Timestamp;
                        if (!timestamp) continue;

                        // Convert Windows filename format to ISO 8601
                        // Input: "2026-01-08_23-24-00" (LOCAL TIME from server)
                        // Output: "2026-01-09T05:24:00.000Z" (converted to UTC)
                        let isoTimestamp = timestamp;
                        if (timestamp.includes('_') && timestamp.includes('-')) {
                            // Format: yyyy-MM-dd_HH-mm-ss -> parse as local time, convert to UTC
                            const localTimeStr = timestamp.replace('_', 'T').replace(/-/g, (match, offset) => {
                                const dashCount = (timestamp.substring(0, offset).match(/-/g) || []).length;
                                return dashCount < 2 ? '-' : ':';
                            });
                            // Parse as local time (server's timezone) and convert to UTC ISO string
                            const localDate = new Date(localTimeStr);
                            isoTimestamp = localDate.toISOString();
                        }

                        // DIAGNOSTIC: Log first record's timestamp conversion
                        if (insertCount === 0 && idx === 0 && incrementalFetchCountRef.current <= 2) {
                            console.log(`[uPlot DEBUG] 🔬 CSV timestamp: "${timestamp}" -> ISO: "${isoTimestamp}"`);
                        }

                        const metricsData = {
                            timestamp: isoTimestamp,
                            hostname: record.Host || 'local',
                            cpu: tableName === 'Perf_CPUCore' ? {
                                total: record.Percent_Avg,
                                cores: [record.Percent_Avg]
                            } : undefined,
                            memory: tableName === 'Perf_MemoryUsage' ? {
                                usedMB: record.MB_Avg
                            } : undefined
                        };

                        await metricsDbRef.current.insertMetrics(metricsData);
                        if (!isMountedRef.current) return;  // Check after await
                        insertCount++;
                    }
                }
            }

            if (insertCount > 0 && isMountedRef.current) {
                console.log(`[uPlot DEBUG] 💾 Inserted ${insertCount} records into sql.js from ${source}`);
            }

        } catch (err) {
            if (isMountedRef.current) {
                console.error(`[uPlot] sql.js insert error (${source}):`, err);
            }
        }
    };

    // Query sql.js and update chart
    const updateChartFromSqlJs = async () => {
        if (!metricsDbRef.current || !containerRef.current || !isMountedRef.current) return;

        try {
            const config = configRef.current;
            const timeRangeMs = getTimeWindowMs(config.timeRange);
            const endTime = new Date().toISOString();
            const startTime = new Date(Date.now() - timeRangeMs).toISOString();

            // Query sql.js for chart data
            let chartData;
            const sqlQuery = `
                SELECT timestamp, cpu_total
                FROM cpu_metrics
                WHERE timestamp BETWEEN '${startTime}' AND '${endTime}'
                ORDER BY timestamp ASC
            `;

            // FIX: Add await - query() returns Promise
            const results = await metricsDbRef.current.query(sqlQuery);
            if (!isMountedRef.current) return;  // Check after await

            // Auto-prune data outside the display time range (only every 10th update to save CPU)
            if (!window._pruneCounter) window._pruneCounter = 0;
            window._pruneCounter++;
            if (window._pruneCounter >= 10) {
                window._pruneCounter = 0;
                const pruneQuery = `DELETE FROM cpu_metrics WHERE timestamp < '${startTime}'`;
                // FIX: Add await - db.run() is async
                await metricsDbRef.current.db.run(pruneQuery);
                if (!isMountedRef.current) return;  // Check after await

                // FIX: Add await - query() is async
                const countResults = await metricsDbRef.current.query('SELECT COUNT(*) as count FROM cpu_metrics');
                if (!isMountedRef.current) return;  // Check after await

                const totalRows = countResults[0]?.count || 0;
                console.log(`[uPlot DEBUG] 🗑️  Pruned old data, ${totalRows} rows remain`);
            }

            if (results.length === 0) {
                // No data in time range - only log first time
                if (!window._noDataLogged) {
                    window._noDataLogged = true;
                    console.log('[uPlot DEBUG] ⏳ No data yet, waiting for metrics...');
                }
                return;
            } else {
                window._noDataLogged = false;
            }

            // Transform to Chart.js format for compatibility with existing transformDataForUPlot
            chartData = {
                data: {
                    datasets: [{
                        label: `${config.metric.toUpperCase()} Average`,
                        data: results.map(row => ({
                            x: row.timestamp,
                            y: row.cpu_total
                        }))
                    }]
                }
            };

            updateChart(chartData);

        } catch (err) {
            if (isMountedRef.current) {
                console.error('[uPlot] sql.js query error:', err);
            }
        }
    };

    // Start incremental polling (every 5 seconds)
    const startIncrementalPolling = () => {
        const delay = configRef.current.delay * 1000;
        pollTimerRef.current = setInterval(() => {
            if (!isPaused) {
                fetchIncrementalData();
            }
        }, delay);
        console.log(`[uPlot DEBUG] ⏱️  Started incremental polling (every ${configRef.current.delay}s)`);
    };

    // Start history refresh (every 15 minutes)
    const startHistoryRefresh = () => {
        historyRefreshTimerRef.current = setInterval(() => {
            if (!isPaused) {
                console.log('[uPlot DEBUG] 🔄 Refreshing history data (15-minute interval)');
                fetchHistoryData();
            }
        }, 15 * 60 * 1000);  // 15 minutes
        console.log('[uPlot DEBUG] ⏱️  Started history refresh (every 15 minutes)');
    };

    // Update or create chart
    const updateChart = (chartData) => {
        if (!containerRef.current || typeof uPlot === 'undefined' || !window.UPlotDataAdapter || !isMountedRef.current) {
            if (!isMountedRef.current) {
                unmountAbortCountRef.current++;
                logToServer('Warn', 'Unmount protection triggered - aborting chart update', {
                    abortCount: unmountAbortCountRef.current,
                    stage: 'updateChart-entry'
                });
            }
            return;
        }

        chartUpdateCountRef.current++;
        const updateStartTime = performance.now();

        const config = configRef.current;
        const transformedData = transformDataForUPlot(chartData, config);

        // Handle empty data - clear existing chart or show empty state
        if (!transformedData || !transformedData.data || transformedData.data[0].length === 0) {
            if (uplotInstanceRef.current && adapterRef.current) {
                // Clear existing chart data - wrap in requestAnimationFrame to prevent frame drops
                const emptyData = [[], ...transformedData?.series?.slice(1).map(() => []) || []];
                const rafStartTime = performance.now();
                requestAnimationFrame(() => {
                    if (!isMountedRef.current) {
                        unmountAbortCountRef.current++;
                        logToServer('Warn', 'Unmount protection in RAF - aborting chart clear', {
                            abortCount: unmountAbortCountRef.current
                        });
                        return;
                    }
                    const rafExecuteTime = performance.now() - rafStartTime;
                    rafTimingsRef.current.push(rafExecuteTime);
                    // Keep only last 100 timings
                    if (rafTimingsRef.current.length > 100) {
                        rafTimingsRef.current.shift();
                    }
                    adapterRef.current.replaceData(emptyData, true);
                    console.log('[uPlot] Chart cleared - no data available');
                });
            }
            return;
        }

        // If chart doesn't exist yet, create it
        if (!uplotInstanceRef.current || !adapterRef.current) {
            const width = containerRef.current.clientWidth;
            const height = config.height;

            const opts = {
                width: width,
                height: height,
                series: transformedData.series,
                axes: [
                    {
                        label: config.xAxisLabel,
                        scale: 'x',
                        space: 60,
                        values: (self, ticks) => ticks.map(t => {
                            const d = new Date(t * 1000);
                            return d.toLocaleTimeString('en-US', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
                        })
                    },
                    {
                        label: config.yAxisLabel,
                        scale: 'y',
                        space: 40
                    }
                ],
                scales: {
                    x: { time: true },
                    y: { auto: true, range: (self, dataMin, dataMax) => {
                        // Add 10% padding to y-axis
                        const padding = (dataMax - dataMin) * 0.1;
                        return [Math.max(0, dataMin - padding), dataMax + padding];
                    }}
                },
                legend: {
                    show: true,
                    live: false
                },
                cursor: {
                    sync: { key: 'metrics' }
                }
            };

            // Create chart in requestAnimationFrame for smooth rendering
            const rafStartTime = performance.now();
            requestAnimationFrame(() => {
                if (!isMountedRef.current || !containerRef.current) {
                    if (!isMountedRef.current) {
                        unmountAbortCountRef.current++;
                        logToServer('Warn', 'Unmount protection in RAF - aborting chart creation', {
                            abortCount: unmountAbortCountRef.current
                        });
                    }
                    return;
                }

                const rafExecuteTime = performance.now() - rafStartTime;
                rafTimingsRef.current.push(rafExecuteTime);
                if (rafTimingsRef.current.length > 100) {
                    rafTimingsRef.current.shift();
                }

                const newChart = new uPlot(opts, transformedData.data, containerRef.current);
                uplotInstanceRef.current = newChart;  // Set ref immediately for synchronous access

                // Create adapter for incremental updates
                const timeWindowMs = getTimeWindowMs(config.timeRange);
                adapterRef.current = new window.UPlotDataAdapter(newChart, {
                    maxDataPoints: 1000,
                    timeWindow: timeWindowMs
                });

                const totalUpdateTime = performance.now() - updateStartTime;

                // DEBUG: Log chart creation details
                console.log(`[uPlot DEBUG] ✅ Chart CREATED - ${transformedData.data[0].length} timestamps, ${transformedData.series.length - 1} series, timeWindow: ${config.timeRange}, dimensions: ${width}x${height}px`);

                logToServer('Info', 'Chart created', {
                    timestamps: transformedData.data[0].length,
                    series: transformedData.series.length - 1,
                    timeWindow: config.timeRange,
                    width: width,
                    height: height,
                    rafDelay: rafExecuteTime.toFixed(2),
                    totalTime: totalUpdateTime.toFixed(2)
                });
            });
        } else {
            // Chart exists - use adapter to replace data, wrapped in requestAnimationFrame
            const rafStartTime = performance.now();
            requestAnimationFrame(() => {
                if (!isMountedRef.current || !adapterRef.current) {
                    if (!isMountedRef.current) {
                        unmountAbortCountRef.current++;
                        logToServer('Warn', 'Unmount protection in RAF - aborting chart update', {
                            abortCount: unmountAbortCountRef.current
                        });
                    }
                    return;
                }

                const rafExecuteTime = performance.now() - rafStartTime;
                rafTimingsRef.current.push(rafExecuteTime);
                if (rafTimingsRef.current.length > 100) {
                    rafTimingsRef.current.shift();
                }

                adapterRef.current.replaceData(transformedData.data, false);

                const totalUpdateTime = performance.now() - updateStartTime;

                console.log(`[uPlot DEBUG] 🔄 Chart UPDATED incrementally - ${transformedData.data[0].length} timestamps, ${transformedData.series.length - 1} series`);

                // Log every 10th update to avoid spam
                if (chartUpdateCountRef.current % 10 === 0) {
                    const avgRafDelay = rafTimingsRef.current.length > 0
                        ? (rafTimingsRef.current.reduce((a, b) => a + b, 0) / rafTimingsRef.current.length).toFixed(2)
                        : 0;

                    logToServer('Info', 'Chart update (periodic)', {
                        timestamps: transformedData.data[0].length,
                        series: transformedData.series.length - 1,
                        updateCount: chartUpdateCountRef.current,
                        rafDelay: rafExecuteTime.toFixed(2),
                        avgRafDelay: avgRafDelay,
                        totalTime: totalUpdateTime.toFixed(2),
                        timerMutexHits: timerMutexHitCountRef.current,
                        unmountAborts: unmountAbortCountRef.current
                    });
                }
            });
        }
    };

    // Transform data for uPlot format
    const transformDataForUPlot = (sourceData, config) => {
        // Expected API format: { data: { datasets: [{ data: [{ x, y }] }] } }
        // OR direct Chart.js format: { datasets: [{ data: [{ x, y }] }] }

        let datasets = [];
        if (sourceData && sourceData.data && sourceData.data.datasets) {
            datasets = sourceData.data.datasets;
        } else if (sourceData && sourceData.datasets) {
            datasets = sourceData.datasets;
        } else {
            // Return empty structure with basic series config
            return {
                data: [[]],
                series: [{ label: 'Time' }]
            };
        }

        if (!datasets || datasets.length === 0) {
            // Return empty structure with basic series config
            return {
                data: [[]],
                series: [{ label: 'Time' }]
            };
        }

        // Convert from Chart.js {x, y} format to uPlot [[timestamps], [values1], [values2], ...] format
        const timestamps = [];
        const seriesData = datasets.map(() => []);

        // Collect all unique timestamps
        const timestampSet = new Set();
        datasets.forEach(dataset => {
            if (dataset.data) {
                dataset.data.forEach(point => {
                    if (point.x) {
                        const timestamp = new Date(point.x).getTime() / 1000;
                        timestampSet.add(timestamp);
                    }
                });
            }
        });

        // Sort timestamps
        const sortedTimestamps = Array.from(timestampSet).sort((a, b) => a - b);

        // If no timestamps, return empty structure with series from datasets
        if (sortedTimestamps.length === 0) {
            const series = [{ label: 'Time' }];
            const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];
            datasets.forEach((dataset, index) => {
                const color = dataset.borderColor || colors[index % colors.length];
                series.push({
                    label: dataset.label || `Series ${index + 1}`,
                    stroke: color,
                    width: dataset.borderWidth || 2,
                    spanGaps: true
                });
            });
            return {
                data: [[], ...datasets.map(() => [])],
                series: series
            };
        }

        // Build data arrays
        datasets.forEach((dataset, datasetIndex) => {
            const dataMap = new Map();
            if (dataset.data) {
                dataset.data.forEach(point => {
                    if (point.x && point.y !== undefined) {
                        const timestamp = new Date(point.x).getTime() / 1000;
                        dataMap.set(timestamp, point.y);
                    }
                });
            }

            sortedTimestamps.forEach(timestamp => {
                seriesData[datasetIndex].push(dataMap.get(timestamp) || null);
            });
        });

        // Build series configuration
        const series = [{ label: 'Time' }];
        const colors = ['#3b82f6', '#ef4444', '#22c55e', '#f59e0b', '#8b5cf6', '#ec4899', '#06b6d4', '#84cc16'];

        datasets.forEach((dataset, index) => {
            const color = dataset.borderColor || colors[index % colors.length];
            series.push({
                label: dataset.label || `Series ${index + 1}`,
                stroke: color,
                width: dataset.borderWidth || 2,
                fill: dataset.fill ? `${color}40` : undefined,
                spanGaps: true
            });
        });

        return {
            data: [sortedTimestamps, ...seriesData],
            series: series
        };
    };

    // Convert time range string to milliseconds
    const getTimeWindowMs = (timeRange) => {
        const match = timeRange.match(/^(\d+)([mh])$/);
        if (!match) return 5 * 60 * 1000; // Default 5 minutes

        const value = parseInt(match[1]);
        const unit = match[2];

        if (unit === 'm') return value * 60 * 1000;
        if (unit === 'h') return value * 60 * 60 * 1000;
        return 5 * 60 * 1000;
    };

    const togglePause = () => {
        setIsPaused(!isPaused);
        if (isPaused) {
            // Resume - fetch immediately
            fetchIncrementalData();
        }
    };

    const refreshNow = () => {
        logToServer('Info', 'Manual refresh triggered', {
            metric: configRef.current.metric,
            timerMutexHits: timerMutexHitCountRef.current
        });
        // Refresh both history and incremental data
        fetchHistoryData();
        fetchIncrementalData();
    };

    const changeTimeRange = (newRange) => {
        logToServer('Info', 'Time range changed', {
            oldRange: selectedTimeRange,
            newRange: newRange,
            metric: configRef.current.metric
        });
        setSelectedTimeRange(newRange);
        configRef.current.timeRange = newRange;
        // Force immediate refresh with new time range
        fetchHistoryData();
    };

    const changeGranularity = (newGranularity) => {
        logToServer('Info', 'Granularity changed', {
            oldGranularity: selectedGranularity,
            newGranularity: newGranularity,
            metric: configRef.current.metric
        });
        setSelectedGranularity(newGranularity);
        configRef.current.granularity = newGranularity;
        // Force immediate refresh with new granularity
        fetchHistoryData();
    };

    if (loading) {
        return React.createElement('div', {
            className: 'uplot-component loading',
            style: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }
        },
            React.createElement('div', { className: 'spinner' }),
            React.createElement('p', null, 'Loading chart...')
        );
    }

    if (error) {
        return React.createElement('div', {
            className: 'uplot-component error',
            style: { padding: '20px', color: '#d73a49' }
        },
            React.createElement('h3', null, 'Chart Error'),
            React.createElement('p', null, error),
            React.createElement('p', null, `Source: ${configRef.current.source}`)
        );
    }

    return React.createElement('div', {
        className: 'uplot-component',
        style: { height: '100%', display: 'flex', flexDirection: 'column', padding: '8px' }
    },
        // Controls row
        React.createElement('div', {
            className: 'chart-controls',
            style: { display: 'flex', gap: '12px', marginBottom: '8px', padding: '4px', alignItems: 'center', flexWrap: 'wrap' }
        },
            // Action buttons
            React.createElement('div', { style: { display: 'flex', gap: '4px' } },
                React.createElement('button', {
                    onClick: togglePause,
                    style: {
                        padding: '4px 10px',
                        fontSize: '11px',
                        cursor: 'pointer',
                        border: '1px solid #ddd',
                        borderRadius: '3px',
                        backgroundColor: isPaused ? '#ffc107' : '#28a745',
                        color: '#fff',
                        fontWeight: '600'
                    }
                }, isPaused ? 'Resume' : 'Pause'),
                React.createElement('button', {
                    onClick: refreshNow,
                    style: {
                        padding: '4px 10px',
                        fontSize: '11px',
                        cursor: 'pointer',
                        border: '1px solid #ddd',
                        borderRadius: '3px',
                        backgroundColor: '#007bff',
                        color: '#fff',
                        fontWeight: '600'
                    }
                }, 'Refresh')
            ),

            // Time Range selector
            React.createElement('div', { style: { display: 'flex', gap: '4px', alignItems: 'center' } },
                React.createElement('span', { style: { fontSize: '11px', fontWeight: '600', color: '#444' } }, 'Range:'),
                ['5m', '15m', '30m', '1h', '3h', '6h', '12h', '24h'].map(range =>
                    React.createElement('button', {
                        key: range,
                        onClick: () => changeTimeRange(range),
                        style: {
                            padding: '3px 8px',
                            fontSize: '11px',
                            cursor: 'pointer',
                            border: '1px solid #ddd',
                            borderRadius: '3px',
                            backgroundColor: selectedTimeRange === range ? '#0366d6' : '#fff',
                            color: selectedTimeRange === range ? '#fff' : '#24292e',
                            fontWeight: selectedTimeRange === range ? '600' : '400'
                        }
                    }, range)
                )
            ),

            // Granularity selector
            React.createElement('div', { style: { display: 'flex', gap: '4px', alignItems: 'center' } },
                React.createElement('span', { style: { fontSize: '11px', fontWeight: '600', color: '#444' } }, 'Sample:'),
                ['5s', '15s', '30s', '1m'].map(gran =>
                    React.createElement('button', {
                        key: gran,
                        onClick: () => changeGranularity(gran),
                        style: {
                            padding: '3px 8px',
                            fontSize: '11px',
                            cursor: 'pointer',
                            border: '1px solid #ddd',
                            borderRadius: '3px',
                            backgroundColor: selectedGranularity === gran ? '#0366d6' : '#fff',
                            color: selectedGranularity === gran ? '#fff' : '#24292e',
                            fontWeight: selectedGranularity === gran ? '600' : '400'
                        }
                    }, gran)
                )
            ),

            // Status indicator
            React.createElement('span', {
                style: { marginLeft: 'auto', fontSize: '11px', color: '#666', alignSelf: 'center' }
            }, `${configRef.current.metric.toUpperCase()} • Updates every ${configRef.current.delay}s`)
        ),
        React.createElement('div', {
            ref: containerRef,
            className: 'uplot-container',
            style: { flex: 1, minHeight: '200px' }
        })
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['metrics-chart'] = UPlotComponent;
