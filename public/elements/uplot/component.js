// Generic uPlot Component
// Provides reusable charting with configurable data sources and polling
// 4x better performance than Chart.js (10% CPU vs 40%, 12MB vs 77MB)

const UPlotComponent = ({ element, onError }) => {
    const [uplotInstance, setUplotInstance] = React.useState(null);
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [isPaused, setIsPaused] = React.useState(false);
    const containerRef = React.useRef(null);
    const pollTimerRef = React.useRef(null);
    const historyRefreshTimerRef = React.useRef(null);
    const configRef = React.useRef({});
    const adapterRef = React.useRef(null);
    const uplotInstanceRef = React.useRef(null);  // Ref for immediate access to chart instance
    const incrementalFetchCountRef = React.useRef(0);  // Track incremental fetch count for debug logging
    const metricsDbRef = React.useRef(null);  // sql.js MetricsDatabase instance
    const lastHistoryFetchRef = React.useRef(null);  // Track last history fetch time

    // Parse configuration from element.url
    React.useEffect(() => {
        if (!element || !element.url) {
            setError('No configuration URL provided');
            setLoading(false);
            return;
        }

        const url = new URL(element.url, window.location.origin);
        const params = url.searchParams;

        configRef.current = {
            source: params.get('source') || '',
            sourceMethod: params.get('sourcemethod') || 'GET',
            contentType: params.get('contenttype') || 'json',
            delay: Math.max(5, parseInt(params.get('delay') || '5', 10)),
            title: params.get('title') || 'Chart',
            xAxisLabel: params.get('xlabel') || 'Time',
            yAxisLabel: params.get('ylabel') || 'Value',
            timeRange: params.get('timerange') || '5m',
            metric: params.get('metric') || 'cpu',
            height: parseInt(params.get('height') || '300', 10),
            sourceParams: {}
        };

        // Collect other params to pass to source
        for (const [key, value] of params.entries()) {
            if (!['source', 'sourcemethod', 'contenttype', 'delay', 'title', 'xlabel', 'ylabel', 'height'].includes(key)) {
                configRef.current.sourceParams[key] = value;
            }
        }

        if (!configRef.current.source) {
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

                setLibrariesLoaded(true);
            } catch (err) {
                console.error('Script loading error:', err);
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
        return () => {
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
    }, []);

    // Fetch historical data from /api/v1/metrics/history (called once on load, then every 15 min)
    const fetchHistoryData = async () => {
        if (isPaused) return;

        try {
            const config = configRef.current;
            const historyUrl = new URL('/api/v1/metrics/history', window.location.origin);
            historyUrl.searchParams.set('metric', config.metric);
            historyUrl.searchParams.set('timerange', config.timeRange);

            const response = await window.psweb_fetchWithAuthHandling(historyUrl.toString());
            if (!response.ok) throw new Error(`History endpoint returned ${response.status}`);

            const responseData = await response.json();

            // DEBUG: Log history response details
            let totalRecords = 0;
            if (responseData.data && responseData.data.datasets) {
                responseData.data.datasets.forEach(dataset => {
                    if (dataset.data && Array.isArray(dataset.data)) {
                        totalRecords += dataset.data.length;
                    }
                });
            }
            console.log(`[uPlot DEBUG] 📥 /api/v1/metrics/history response: ${totalRecords} total data points, ${responseData.data?.datasets?.length || 0} datasets, granularity: ${responseData.granularity}, sampleCount: ${responseData.sampleCount}`);

            // Insert into sql.js database
            if (totalRecords > 0 && metricsDbRef.current) {
                await insertDataIntoSqlJs(responseData, 'history');
            }

            lastHistoryFetchRef.current = new Date();

            // Update chart from sql.js
            await updateChartFromSqlJs();

            setError(null);
            setLoading(false);
        } catch (err) {
            console.error('[uPlot] History fetch error:', err);
            setError(err.message);
            setLoading(false);
        }
    };

    // Fetch incremental data from /api/v1/metrics (CSV files, called every 5 seconds)
    const fetchIncrementalData = async () => {
        if (isPaused || !metricsDbRef.current) return;

        try {
            const config = configRef.current;
            const incrementalUrl = new URL('/api/v1/metrics', window.location.origin);
            incrementalUrl.searchParams.set('action', 'realtime');
            incrementalUrl.searchParams.set('metric', config.metric);

            // Only fetch last 1 minute of CSV data
            const lastMinute = new Date(Date.now() - 60000).toISOString();
            incrementalUrl.searchParams.set('starting', lastMinute);

            const response = await window.psweb_fetchWithAuthHandling(incrementalUrl.toString());
            if (!response.ok) return; // Silently skip if no new data

            const responseData = await response.json();

            // DEBUG: Log first 5 incremental fetches
            incrementalFetchCountRef.current++;
            if (incrementalFetchCountRef.current <= 5) {
                let totalRecords = 0;
                if (responseData.data) {
                    Object.values(responseData.data).forEach(tableData => {
                        if (Array.isArray(tableData)) {
                            totalRecords += tableData.length;
                        }
                    });
                }
                console.log(`[uPlot DEBUG] 📊 Incremental fetch #${incrementalFetchCountRef.current} from /api/v1/metrics: ${totalRecords} CSV records`);
            }

            // Insert into sql.js database (with deduplication)
            if (responseData.data && Object.keys(responseData.data).length > 0) {
                await insertDataIntoSqlJs(responseData, 'incremental');
                // Update chart from sql.js
                await updateChartFromSqlJs();
            }

        } catch (err) {
            // Silently log incremental errors (don't disrupt the UI)
            if (incrementalFetchCountRef.current <= 5) {
                console.warn('[uPlot] Incremental fetch error:', err.message);
            }
        }
    };

    // Insert API data into sql.js database
    const insertDataIntoSqlJs = async (responseData, source) => {
        if (!metricsDbRef.current) return;

        const metric = configRef.current.metric;
        let insertCount = 0;

        try {
            if (source === 'history') {
                // History format: { data: { datasets: [{ data: [{x, y}] }] } }
                const datasets = responseData.data?.datasets || [];

                datasets.forEach((dataset, seriesIndex) => {
                    if (!dataset.data) return;

                    dataset.data.forEach(point => {
                        if (!point.x || point.y === undefined) return;

                        const timestamp = new Date(point.x).toISOString();
                        const metricsData = {
                            timestamp: timestamp,
                            hostname: 'local',
                            [metric]: {
                                total: point.y,
                                cores: seriesIndex !== undefined ? [point.y] : []
                            }
                        };

                        metricsDbRef.current.insertMetrics(metricsData);
                        insertCount++;
                    });
                });

            } else if (source === 'incremental') {
                // Incremental format: { data: { Perf_CPUCore: [{Timestamp, ...}] } }
                Object.entries(responseData.data).forEach(([tableName, records]) => {
                    if (!Array.isArray(records)) return;

                    records.forEach((record, idx) => {
                        const timestamp = record.Timestamp;
                        if (!timestamp) return;

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

                        metricsDbRef.current.insertMetrics(metricsData);
                        insertCount++;
                    });
                });
            }

            if (insertCount > 0) {
                console.log(`[uPlot DEBUG] 💾 Inserted ${insertCount} records into sql.js from ${source}`);
            }

        } catch (err) {
            console.error(`[uPlot] sql.js insert error (${source}):`, err);
        }
    };

    // Query sql.js and update chart
    const updateChartFromSqlJs = async () => {
        if (!metricsDbRef.current || !containerRef.current) return;

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

            console.log(`[uPlot DEBUG] 🔍 SQL Query: ${sqlQuery}`);
            const results = metricsDbRef.current.query(sqlQuery);
            console.log(`[uPlot DEBUG] 📊 SQL returned ${results.length} rows`);

            if (results.length === 0) {
                // DIAGNOSTIC: Check what's actually in the table
                const diagnosticQuery = `SELECT timestamp, cpu_total FROM cpu_metrics ORDER BY timestamp DESC LIMIT 5`;
                const allRows = metricsDbRef.current.query(diagnosticQuery);
                console.log(`[uPlot DEBUG] 🔬 Total rows in cpu_metrics: ${metricsDbRef.current.query('SELECT COUNT(*) as count FROM cpu_metrics')[0]?.count || 0}`);
                console.log(`[uPlot DEBUG] 🔬 Sample timestamps in database:`, allRows.map(r => r.timestamp));
                console.log(`[uPlot DEBUG] 🔬 Query looking for range: ${startTime} to ${endTime}`);

                // No data yet - show empty chart
                if (!uplotInstance) {
                    console.log('[uPlot DEBUG] ⏳ No data yet, waiting for metrics...');
                }
                return;
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
            console.error('[uPlot] sql.js query error:', err);
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
        if (!containerRef.current || typeof uPlot === 'undefined' || !window.UPlotDataAdapter) return;

        const config = configRef.current;
        const transformedData = transformDataForUPlot(chartData, config);

        // Handle empty data - clear existing chart or show empty state
        if (!transformedData || !transformedData.data || transformedData.data[0].length === 0) {
            if (uplotInstanceRef.current && adapterRef.current) {
                // Clear existing chart data
                const emptyData = [[], ...transformedData?.series?.slice(1).map(() => []) || []];
                adapterRef.current.replaceData(emptyData, true);
                console.log('[uPlot] Chart cleared - no data available');
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

            const newChart = new uPlot(opts, transformedData.data, containerRef.current);
            uplotInstanceRef.current = newChart;  // Set ref immediately for synchronous access
            setUplotInstance(newChart);

            // Create adapter for incremental updates
            const timeWindowMs = getTimeWindowMs(config.timeRange);
            adapterRef.current = new window.UPlotDataAdapter(newChart, {
                maxDataPoints: 1000,
                timeWindow: timeWindowMs
            });

            // DEBUG: Log chart creation details
            console.log(`[uPlot DEBUG] ✅ Chart CREATED - ${transformedData.data[0].length} timestamps, ${transformedData.series.length - 1} series, timeWindow: ${config.timeRange}, dimensions: ${width}x${height}px`);
        } else {
            // Chart exists - use adapter to replace data
            adapterRef.current.replaceData(transformedData.data, false);
            console.log(`[uPlot DEBUG] 🔄 Chart UPDATED incrementally - ${transformedData.data[0].length} timestamps, ${transformedData.series.length - 1} series`);
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
        // Refresh both history and incremental data
        fetchHistoryData();
        fetchIncrementalData();
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
        React.createElement('div', {
            className: 'chart-controls',
            style: { display: 'flex', gap: '8px', marginBottom: '8px', padding: '4px' }
        },
            React.createElement('button', {
                onClick: togglePause,
                style: {
                    padding: '4px 12px',
                    fontSize: '12px',
                    cursor: 'pointer',
                    border: '1px solid #ddd',
                    borderRadius: '3px',
                    backgroundColor: isPaused ? '#ffc107' : '#28a745',
                    color: '#fff'
                }
            }, isPaused ? 'Resume' : 'Pause'),
            React.createElement('button', {
                onClick: refreshNow,
                style: {
                    padding: '4px 12px',
                    fontSize: '12px',
                    cursor: 'pointer',
                    border: '1px solid #ddd',
                    borderRadius: '3px',
                    backgroundColor: '#007bff',
                    color: '#fff'
                }
            }, 'Refresh'),
            React.createElement('span', {
                style: { marginLeft: 'auto', fontSize: '12px', color: '#666', alignSelf: 'center' }
            }, `Updates every ${configRef.current.delay}s`)
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
window.cardComponents['uplot'] = UPlotComponent;
