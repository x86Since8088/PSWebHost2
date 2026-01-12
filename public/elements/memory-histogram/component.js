// Memory Histogram Component
// Displays memory usage over time with historical loading and real-time updates

const MemoryHistogramComponent = ({ element, onError }) => {
    const [manager, setManager] = React.useState(null);
    const [timeRange, setTimeRange] = React.useState('1h');
    const [chartInstance, setChartInstance] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [chartHeight, setChartHeight] = React.useState(250);

    const canvasRef = React.useRef(null);
    const isResizing = React.useRef(false);
    const chartAdapterRef = React.useRef(null);

    // Initialize MetricsManager
    React.useEffect(() => {
        // Load MetricsManager if not already loaded
        if (typeof window.MetricsManager === 'undefined') {
            const script = document.createElement('script');
            script.src = '/public/lib/metrics-manager.js';
            script.onload = () => {
                console.log('MetricsManager loaded');
                setManager(new window.MetricsManager());
            };
            script.onerror = () => {
                console.error('Failed to load MetricsManager');
                onError({ message: 'Failed to load MetricsManager' });
            };
            document.head.appendChild(script);
        } else {
            setManager(new window.MetricsManager());
        }

        return () => {
            if (manager) {
                manager.stopPolling('memory_current');
                manager.destroy();
            }
        };
    }, []);

    // Load Chart.js, date adapter, and ChartDataAdapter
    React.useEffect(() => {
        const loadScripts = async () => {
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

            // Load date adapter
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
        };

        loadScripts().catch(err => {
            console.error('Script loading error:', err);
            onError({ message: err.message });
        });
    }, []);

    // Load data when manager or timeRange changes
    React.useEffect(() => {
        if (!manager || typeof Chart === 'undefined') return;

        loadData();
    }, [manager, timeRange]);

    const parseTimeRange = (range) => {
        const match = range.match(/^(\d+)([mh])$/);
        if (!match) return 60 * 60 * 1000; // Default 1h

        const value = parseInt(match[1]);
        const unit = match[2];

        return unit === 'm' ? value * 60 * 1000 : value * 60 * 60 * 1000;
    };

    const loadData = async () => {
        try {
            setLoading(true);

            const now = new Date();
            const milliseconds = parseTimeRange(timeRange);
            const start = new Date(now - milliseconds);

            // Determine granularity based on time range
            let granularity = '5s';
            if (milliseconds > 60 * 60 * 1000) { // > 1 hour
                granularity = '1m';
            }

            console.log(`Loading memory history: ${start.toISOString()} to ${now.toISOString()}`);

            // Load historical data
            await manager.loadHistorical({
                datasetname: 'memory_history',
                starttime: start.toISOString(),
                endtime: now.toISOString(),
                granularity: granularity,
                metrics: ['memory']
            });

            // Convert to Chart.js format
            const chartData = manager.toChartFormat('memory_history', 'memory_used', {
                label: 'Memory Usage %',
                borderColor: '#ef4444',
                backgroundColor: 'rgba(239, 68, 68, 0.2)',
                fill: true
            });

            // Create or update chart
            updateChart(chartData);

            // Stop existing polling
            manager.stopPolling('memory_current');

            // Start polling for real-time updates
            manager.startPolling({
                datasetname: 'memory_current',
                interval: 5000,
                metrics: ['memory'],
                onUpdate: handleMemoryUpdate
            });

            setLoading(false);

        } catch (error) {
            console.error('Error loading memory data:', error);
            onError({ message: error.message });
            setLoading(false);
        }
    };

    const handleMemoryUpdate = (data) => {
        if (!chartAdapterRef.current) return;

        const timestamp = new Date().toISOString();
        const memUsed = data.metrics?.memory?.usedPercent || 0;

        // Use adapter to append data incrementally
        chartAdapterRef.current.appendData({
            datasets: [{
                data: [{
                    x: timestamp,
                    y: memUsed
                }]
            }]
        });
    };

    const updateChart = (chartData) => {
        if (!canvasRef.current || typeof Chart === 'undefined' || !window.ChartDataAdapter) return;

        // If chart doesn't exist yet, create it with adapter
        if (!chartInstance || !chartAdapterRef.current) {
            const ctx = canvasRef.current.getContext('2d');

            // Create new chart
            const chart = new Chart(ctx, {
                type: 'line',
                data: chartData,
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    animation: false,
                    parsing: false,
                    plugins: {
                        title: {
                            display: true,
                            text: 'Memory Usage History',
                            color: '#f0f0f0'
                        },
                        legend: {
                            display: true,
                            position: 'top',
                            labels: { color: '#f0f0f0' }
                        },
                        decimation: {
                            enabled: true,
                            algorithm: 'lttb',
                            samples: 500
                        }
                    },
                    scales: {
                        x: {
                            type: 'time',
                            time: {
                                displayFormats: {
                                    second: 'HH:mm:ss',
                                    minute: 'HH:mm',
                                    hour: 'HH:mm'
                                }
                            },
                            ticks: { color: '#f0f0f0' },
                            grid: { color: '#444' }
                        },
                        y: {
                            min: 0,
                            max: 100,
                            title: {
                                display: true,
                                text: 'Usage %',
                                color: '#f0f0f0'
                            },
                            ticks: { color: '#f0f0f0' },
                            grid: { color: '#444' }
                        }
                    },
                    elements: {
                        point: { radius: 0 },
                        line: { borderWidth: 2 }
                    }
                }
            });

            setChartInstance(chart);

            // Create adapter with time window based on current time range
            const timeWindowMs = parseTimeRange(timeRange);
            chartAdapterRef.current = new window.ChartDataAdapter(chart, {
                maxDataPoints: 1000,
                updateMode: 'none',
                timeWindow: timeWindowMs
            });

            console.log('[MemoryHistogram] Chart created with incremental update adapter');
        } else {
            // Chart exists - use adapter to replace data incrementally
            // Update time window based on current time range
            const timeWindowMs = parseTimeRange(timeRange);
            chartAdapterRef.current.setTimeWindow(timeWindowMs);
            chartAdapterRef.current.replaceData(chartData);
            console.log('[MemoryHistogram] Chart updated incrementally');
        }
    };

    if (loading) {
        return React.createElement('div', {
            style: {
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                height: '200px',
                color: '#f0f0f0'
            }
        }, 'Loading memory histogram...');
    }

    return React.createElement('div', {
        style: {
            display: 'flex',
            flexDirection: 'column',
            height: '100%',
            padding: '8px'
        }
    },
        // Time range selector
        React.createElement('div', {
            style: {
                display: 'flex',
                gap: '8px',
                marginBottom: '8px',
                alignItems: 'center'
            }
        },
            React.createElement('span', {
                style: { color: '#f0f0f0', fontSize: '0.9em', fontWeight: '600' }
            }, 'Time Range:'),
            ['5m', '15m', '30m', '1h', '3h', '6h', '12h', '24h'].map(range =>
                React.createElement('button', {
                    key: range,
                    onClick: () => setTimeRange(range),
                    style: {
                        padding: '4px 12px',
                        fontSize: '12px',
                        cursor: 'pointer',
                        border: '1px solid #ddd',
                        borderRadius: '3px',
                        backgroundColor: timeRange === range ? '#ef4444' : '#fff',
                        color: timeRange === range ? '#fff' : '#24292e',
                        fontWeight: timeRange === range ? '600' : '400'
                    }
                }, range)
            ),
            React.createElement('span', {
                style: { marginLeft: 'auto', fontSize: '0.75em', color: '#999' }
            }, timeRange === '5m' || timeRange === '15m' || timeRange === '30m' || timeRange === '1h'
                ? '5s samples'
                : '1m averages'
            )
        ),

        // Chart container
        React.createElement('div', {
            style: {
                height: chartHeight + 'px',
                position: 'relative',
                backgroundColor: '#2a2a2a',
                borderRadius: '4px',
                border: '1px solid #444',
                padding: '8px'
            }
        },
            React.createElement('canvas', { ref: canvasRef })
        ),

        // Resize handle
        React.createElement('div', {
            style: {
                height: '8px',
                cursor: 'ns-resize',
                backgroundColor: 'transparent',
                borderTop: '2px solid #444',
                marginTop: '4px',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
            },
            onMouseDown: (e) => {
                e.preventDefault();
                isResizing.current = true;
                const startY = e.clientY;
                const startHeight = chartHeight;

                const handleMouseMove = (e) => {
                    if (!isResizing.current) return;
                    const deltaY = e.clientY - startY;
                    const newHeight = Math.max(150, Math.min(600, startHeight + deltaY));
                    setChartHeight(newHeight);
                };

                const handleMouseUp = () => {
                    isResizing.current = false;
                    document.removeEventListener('mousemove', handleMouseMove);
                    document.removeEventListener('mouseup', handleMouseUp);
                };

                document.addEventListener('mousemove', handleMouseMove);
                document.addEventListener('mouseup', handleMouseUp);
            }
        },
            React.createElement('span', {
                style: { fontSize: '10px', color: '#666' }
            }, '⋮⋮⋮')
        )
    );
};

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['memory-histogram'] = MemoryHistogramComponent;
