// Generic ChartJS Component
// Provides reusable charting with configurable data sources and polling

const ChartJsComponent = ({ element, onError }) => {
    const [chartInstance, setChartInstance] = React.useState(null);
    const [data, setData] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [isPaused, setIsPaused] = React.useState(false);
    const canvasRef = React.useRef(null);
    const pollTimerRef = React.useRef(null);
    const configRef = React.useRef({});
    const chartAdapterRef = React.useRef(null);

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
            chartType: params.get('charttype') || 'line',
            title: params.get('title') || 'Chart',
            xAxisLabel: params.get('xlabel') || '',
            yAxisLabel: params.get('ylabel') || '',
            timeRange: params.get('timerange') || '5m',
            decimation: params.get('decimation') === 'true',
            // Pass through all other params
            sourceParams: {}
        };

        // Collect other params to pass to source
        // Note: timerange, metric, etc. should be passed to the source API
        for (const [key, value] of params.entries()) {
            if (!['source', 'sourcemethod', 'contenttype', 'delay', 'charttype', 'title', 'xlabel', 'ylabel'].includes(key)) {
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

    // Load Chart.js and dependencies if not already loaded
    React.useEffect(() => {
        const loadScripts = async () => {
            // Check if all libraries are already loaded
            if (typeof Chart !== 'undefined' &&
                window._chartDateAdapterLoaded &&
                window.ChartDataAdapter) {
                console.log('Chart.js libraries already loaded');
                setLibrariesLoaded(true);
                return;
            }

            // Load Chart.js first
            if (typeof Chart === 'undefined') {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/chart.min.js';
                    script.onload = () => {
                        console.log('Chart.js loaded');
                        resolve();
                    };
                    script.onerror = () => reject(new Error('Failed to load Chart.js'));
                    document.head.appendChild(script);
                });
            }

            // Load date adapter for time scale
            if (!window._chartDateAdapterLoaded) {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/chartjs-adapter-date-fns.min.js';
                    script.onload = () => {
                        console.log('Chart.js date adapter loaded');
                        window._chartDateAdapterLoaded = true;
                        resolve();
                    };
                    script.onerror = () => reject(new Error('Failed to load date adapter'));
                    document.head.appendChild(script);
                });
            }

            // Load ChartDataAdapter for incremental updates
            if (!window.ChartDataAdapter) {
                await new Promise((resolve, reject) => {
                    const script = document.createElement('script');
                    script.src = '/public/lib/chart-data-adapter.js';
                    script.onload = () => {
                        console.log('ChartDataAdapter loaded');
                        resolve();
                    };
                    script.onerror = () => reject(new Error('Failed to load ChartDataAdapter'));
                    document.head.appendChild(script);
                });
            }

            setLibrariesLoaded(true);
        };

        loadScripts().catch(err => {
            console.error('Script loading error:', err);
            setError(err.message);
            setLoading(false);
        });
    }, []);

    // Fetch data once libraries are loaded and when element.url changes
    React.useEffect(() => {
        if (!librariesLoaded) return;

        fetchData();

        return () => {
            if (pollTimerRef.current) {
                clearInterval(pollTimerRef.current);
            }
            // Only destroy chart on unmount, not on config changes
        };
    }, [librariesLoaded, element?.url]);

    // Cleanup on unmount only
    React.useEffect(() => {
        return () => {
            if (chartInstance) {
                chartInstance.destroy();
            }
            chartAdapterRef.current = null;
        };
    }, []);

    // Fetch data from source
    const fetchData = async () => {
        if (!configRef.current.source || isPaused) return;

        try {
            const config = configRef.current;

            // Build source URL with params
            const sourceUrl = new URL(config.source, window.location.origin);
            for (const [key, value] of Object.entries(config.sourceParams)) {
                sourceUrl.searchParams.set(key, value);
            }

            const options = {
                method: config.sourceMethod,
                headers: {}
            };

            if (config.sourceMethod !== 'GET' && config.sourceMethod !== 'HEAD') {
                options.headers['Content-Type'] = `application/${config.contentType}`;
            }

            const response = await window.psweb_fetchWithAuthHandling(sourceUrl.toString(), options);

            if (!response.ok) {
                throw new Error(`Data source returned ${response.status}`);
            }

            let responseData;
            if (config.contentType === 'json') {
                responseData = await response.json();
            } else if (config.contentType === 'yaml') {
                const text = await response.text();
                // TODO: Add YAML parser if needed
                responseData = { raw: text };
            } else if (config.contentType === 'csv') {
                const text = await response.text();
                responseData = parseCSV(text);
            } else {
                responseData = await response.json();
            }

            setData(responseData);
            setError(null);
            updateChart(responseData);
        } catch (err) {
            console.error('Chart data fetch error:', err);
            setError(err.message);
            if (onError) onError(err);
        } finally {
            setLoading(false);
        }
    };

    // Update or create chart with incremental updates
    const updateChart = (chartData) => {
        if (!canvasRef.current || typeof Chart === 'undefined' || !window.ChartDataAdapter) return;

        const config = configRef.current;
        const transformedData = transformDataForChart(chartData, config);

        // If chart doesn't exist yet, create it with adapter
        if (!chartInstance || !chartAdapterRef.current) {
            const ctx = canvasRef.current.getContext('2d');

            // Prepare chart configuration
            const chartConfig = {
                type: config.chartType,
                data: transformedData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: false,  // Disable animations for better performance with large datasets
                    parsing: false,     // Data is already parsed
                    plugins: {
                        title: {
                            display: !!config.title,
                            text: config.title
                        },
                        legend: {
                            display: true,
                            position: 'top'
                        },
                        decimation: config.decimation ? {
                            enabled: true,
                            algorithm: 'lttb',  // Largest-Triangle-Three-Buckets algorithm
                            samples: 500        // Target number of points to display
                        } : {
                            enabled: false
                        }
                    },
                    scales: {
                        x: {
                            display: true,
                            type: 'time',  // Use time scale for time-series data
                            time: {
                                displayFormats: {
                                    second: 'HH:mm:ss',
                                    minute: 'HH:mm',
                                    hour: 'HH:mm'
                                }
                            },
                            title: {
                                display: !!config.xAxisLabel,
                                text: config.xAxisLabel
                            }
                        },
                        y: {
                            display: true,
                            title: {
                                display: !!config.yAxisLabel,
                                text: config.yAxisLabel
                            },
                            beginAtZero: true
                        }
                    },
                    elements: {
                        point: {
                            radius: 0  // Don't show individual points for better performance
                        },
                        line: {
                            borderWidth: 2
                        }
                    }
                }
            };

            const newChart = new Chart(ctx, chartConfig);
            setChartInstance(newChart);

            // Create adapter for incremental updates
            chartAdapterRef.current = new window.ChartDataAdapter(newChart, {
                maxDataPoints: 1000,
                updateMode: 'none',  // No animation for performance
                timeWindow: null     // No time-based trimming (handled by backend)
            });

            console.log('[ChartJS] Chart created with incremental update adapter');
        } else {
            // Chart exists - use adapter to replace data incrementally
            // Use replaceData for full refreshes (time range changes, etc.)
            chartAdapterRef.current.replaceData(transformedData);
            console.log('[ChartJS] Chart updated incrementally');
        }
    };

    // Transform data for Chart.js format
    const transformDataForChart = (sourceData, config) => {
        // Expected format from source:
        // { labels: [...], datasets: [{ label: "", data: [...] }] }
        // OR auto-transform from common formats

        if (sourceData.labels && sourceData.datasets) {
            // Already in Chart.js format
            return sourceData;
        }

        // Try to auto-transform
        if (Array.isArray(sourceData)) {
            // Array of objects like [{ time: ..., value: ... }]
            // For time scale, use {x, y} format
            return {
                datasets: [{
                    label: config.title,
                    data: sourceData.map(d => ({
                        x: d.time || d.Timestamp || d.timestamp || d.label || d.x,
                        y: d.value || d.y
                    })),
                    borderColor: 'rgb(75, 192, 192)',
                    backgroundColor: 'rgba(75, 192, 192, 0.2)',
                    fill: false
                }]
            };
        }

        // Fallback to empty
        return { datasets: [] };
    };

    // Parse CSV data
    const parseCSV = (csvText) => {
        const lines = csvText.trim().split('\n');
        if (lines.length < 2) return { labels: [], datasets: [] };

        const headers = lines[0].split(',').map(h => h.trim());
        const data = lines.slice(1).map(line => {
            const values = line.split(',').map(v => v.trim());
            const row = {};
            headers.forEach((h, i) => {
                row[h] = values[i];
            });
            return row;
        });

        return data;
    };

    // Setup polling
    React.useEffect(() => {
        if (!configRef.current.source || isPaused) return;

        const delay = configRef.current.delay * 1000;
        pollTimerRef.current = setInterval(fetchData, delay);

        return () => {
            if (pollTimerRef.current) {
                clearInterval(pollTimerRef.current);
            }
        };
    }, [isPaused]);

    const togglePause = () => {
        setIsPaused(!isPaused);
        if (isPaused) {
            fetchData(); // Resume and fetch immediately
        }
    };

    const refreshNow = () => {
        fetchData();
    };

    if (loading) {
        return React.createElement('div', {
            className: 'chartjs-component loading',
            style: { display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%' }
        },
            React.createElement('div', { className: 'spinner' }),
            React.createElement('p', null, 'Loading chart...')
        );
    }

    if (error) {
        return React.createElement('div', {
            className: 'chartjs-component error',
            style: { padding: '20px', color: '#d73a49' }
        },
            React.createElement('h3', null, 'Chart Error'),
            React.createElement('p', null, error),
            React.createElement('p', null, `Source: ${configRef.current.source}`)
        );
    }

    return React.createElement('div', {
        className: 'chartjs-component',
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
            className: 'chart-container',
            style: { flex: 1, position: 'relative', minHeight: '200px' }
        },
            React.createElement('canvas', { ref: canvasRef })
        )
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['chartjs'] = ChartJsComponent;
