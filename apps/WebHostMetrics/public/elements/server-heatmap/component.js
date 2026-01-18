const { useState, useEffect, useRef } = React;

// CPU History Chart Component - Shows per-core CPU usage over time
const CpuHistoryChart = ({ cpuHistory, coreCount }) => {
    const chartWidth = 300;
    const chartHeight = 100;
    const padding = { top: 10, right: 10, bottom: 20, left: 30 };
    const plotWidth = chartWidth - padding.left - padding.right;
    const plotHeight = chartHeight - padding.top - padding.bottom;

    // Color palette for CPU cores (will cycle if more cores than colors)
    const coreColors = [
        '#3b82f6', // blue
        '#ef4444', // red
        '#22c55e', // green
        '#f59e0b', // amber
        '#8b5cf6', // violet
        '#ec4899', // pink
        '#06b6d4', // cyan
        '#f97316', // orange
        '#84cc16', // lime
        '#6366f1', // indigo
        '#14b8a6', // teal
        '#a855f7', // purple
    ];

    if (!cpuHistory || cpuHistory.length < 2) {
        return (
            <div style={{
                width: chartWidth,
                height: chartHeight,
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center',
                backgroundColor: 'var(--bg-color)',
                borderRadius: '4px',
                fontSize: '0.8em',
                color: 'var(--text-secondary)'
            }}>
                Collecting CPU history...
            </div>
        );
    }

    const maxPoints = 60; // Show last 60 data points (5 minutes at 5-second intervals)
    const dataPoints = cpuHistory.slice(-maxPoints);
    const xScale = plotWidth / (maxPoints - 1);

    // Generate paths for each CPU core
    const corePaths = [];
    for (let coreIdx = 0; coreIdx < coreCount; coreIdx++) {
        const pathData = dataPoints.map((point, i) => {
            const value = point.cores && point.cores[coreIdx] !== undefined ? point.cores[coreIdx] : 0;
            const x = padding.left + (i * xScale);
            const y = padding.top + plotHeight - (value / 100 * plotHeight);
            return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
        }).join(' ');

        if (pathData) {
            corePaths.push({
                coreIdx,
                path: pathData,
                color: coreColors[coreIdx % coreColors.length]
            });
        }
    }

    // Generate average line
    const avgPathData = dataPoints.map((point, i) => {
        const avg = point.avg !== undefined ? point.avg : 0;
        const x = padding.left + (i * xScale);
        const y = padding.top + plotHeight - (avg / 100 * plotHeight);
        return `${i === 0 ? 'M' : 'L'} ${x.toFixed(1)} ${y.toFixed(1)}`;
    }).join(' ');

    // Y-axis labels
    const yLabels = [0, 25, 50, 75, 100];

    // Time labels (show start and end)
    const startTime = dataPoints[0]?.time || '';
    const endTime = dataPoints[dataPoints.length - 1]?.time || '';

    return (
        <div style={{ position: 'relative' }}>
            <svg width={chartWidth} height={chartHeight} style={{ backgroundColor: 'var(--bg-color)', borderRadius: '4px' }}>
                {/* Grid lines */}
                {yLabels.map(val => {
                    const y = padding.top + plotHeight - (val / 100 * plotHeight);
                    return (
                        <g key={`grid-${val}`}>
                            <line
                                x1={padding.left}
                                y1={y}
                                x2={chartWidth - padding.right}
                                y2={y}
                                stroke="rgba(255,255,255,0.1)"
                                strokeDasharray="2,2"
                            />
                            <text
                                x={padding.left - 5}
                                y={y + 3}
                                fontSize="8"
                                fill="var(--text-secondary)"
                                textAnchor="end"
                            >
                                {val}%
                            </text>
                        </g>
                    );
                })}

                {/* Per-core lines */}
                {corePaths.map(({ coreIdx, path, color }) => (
                    <path
                        key={`core-${coreIdx}`}
                        d={path}
                        fill="none"
                        stroke={color}
                        strokeWidth="1"
                        strokeOpacity="0.6"
                    />
                ))}

                {/* Average line (thicker, white) */}
                <path
                    d={avgPathData}
                    fill="none"
                    stroke="white"
                    strokeWidth="2"
                    strokeOpacity="0.9"
                />

                {/* X-axis time labels */}
                <text
                    x={padding.left}
                    y={chartHeight - 3}
                    fontSize="8"
                    fill="var(--text-secondary)"
                >
                    {startTime}
                </text>
                <text
                    x={chartWidth - padding.right}
                    y={chartHeight - 3}
                    fontSize="8"
                    fill="var(--text-secondary)"
                    textAnchor="end"
                >
                    {endTime}
                </text>
            </svg>

            {/* Legend */}
            <div style={{
                display: 'flex',
                flexWrap: 'wrap',
                gap: '4px',
                marginTop: '4px',
                fontSize: '0.65em'
            }}>
                <span style={{ display: 'flex', alignItems: 'center', gap: '2px' }}>
                    <span style={{ width: '12px', height: '2px', backgroundColor: 'white', display: 'inline-block' }}></span>
                    <span style={{ color: 'var(--text-secondary)' }}>Avg</span>
                </span>
                {corePaths.slice(0, 8).map(({ coreIdx, color }) => (
                    <span key={`legend-${coreIdx}`} style={{ display: 'flex', alignItems: 'center', gap: '2px' }}>
                        <span style={{ width: '8px', height: '2px', backgroundColor: color, display: 'inline-block' }}></span>
                        <span style={{ color: 'var(--text-secondary)' }}>C{coreIdx}</span>
                    </span>
                ))}
                {coreCount > 8 && <span style={{ color: 'var(--text-secondary)' }}>+{coreCount - 8}</span>}
            </div>
        </div>
    );
};

const ServerHeatmapCard = ({ onError }) => {
    const [systemData, setSystemData] = useState(null);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [historyData, setHistoryData] = useState(null);
    const [showHistory, setShowHistory] = useState(false);
    const [cpuHistory, setCpuHistory] = useState([]);
    const [timeRange, setTimeRange] = useState('5m');
    const [chartHeight, setChartHeight] = useState(250);
    const maxHistoryPoints = 60; // 5 minutes of data at 5-second intervals
    const chartResizeRef = useRef(null);
    const isResizing = useRef(false);

    // Load uPlot component if not already loaded
    useEffect(() => {
        if (!window.cardComponents || !window.cardComponents.uplot) {
            const script = document.createElement('script');
            script.src = '/public/elements/uplot/component.js';
            script.onload = () => console.log('uPlot component loaded');
            script.onerror = () => console.error('Failed to load uPlot component');
            document.head.appendChild(script);
        }
    }, []);

    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/api/v1/ui/elements/server-heatmap')
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch system stats", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.json();
                })
                .then(data => {
                    if (isMounted) {
                        setSystemData(data);

                        // Update CPU history for the chart
                        if (data.metrics && data.metrics.cpu && data.metrics.cpu.length > 0) {
                            const now = new Date();
                            const timeStr = now.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' });

                            const coreValues = data.metrics.cpu.map(c =>
                                typeof c.value === 'number' ? c.value : 0
                            );
                            const avgValue = coreValues.length > 0
                                ? coreValues.reduce((a, b) => a + b, 0) / coreValues.length
                                : 0;

                            setCpuHistory(prev => {
                                const newHistory = [...prev, {
                                    time: timeStr,
                                    cores: coreValues,
                                    avg: avgValue
                                }];
                                // Keep only last N points
                                return newHistory.slice(-maxHistoryPoints);
                            });
                        }
                    }
                })
                .catch(err => {
                    if (isMounted && err.name !== 'Unauthorized') {
                        console.error("ServerHeatmapCard fetch error:", err);
                    }
                });
        };

        fetchData();

        const interval = autoRefresh ? setInterval(fetchData, 5000) : null;

        return () => {
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh, onError]);

    // Fetch history data when requested
    const fetchHistory = (minutes = 60) => {
        window.psweb_fetchWithAuthHandling(`/apps/WebHostMetrics/api/v1/ui/elements/server-heatmap?history=${minutes}`)
            .then(res => res.json())
            .then(data => {
                setHistoryData(data);
                setShowHistory(true);
            })
            .catch(err => console.error("Failed to fetch history:", err));
    };

    const isError = (value) => {
        if (value === null || value === undefined) return false;
        if (typeof value === 'object') return false;
        return value === "Error" || value === "error";
    };

    const formatValue = (value, suffix = '') => {
        if (value === null || value === undefined) return 'N/A';
        if (typeof value === 'object') {
            if (value.toString && value.toString() !== '[object Object]') {
                return value.toString();
            }
            return 'N/A';
        }
        if (isError(value)) {
            return <span style={{color: '#ef4444', fontWeight: 'bold'}}>Error</span>;
        }
        return `${value}${suffix}`;
    };

    const formatNumber = (value) => {
        if (value === null || value === undefined) return 'N/A';
        if (typeof value === 'object') return 'N/A';
        if (isError(value)) return <span style={{color: '#ef4444', fontWeight: 'bold'}}>Error</span>;
        if (typeof value === 'number') {
            return value.toLocaleString();
        }
        return value;
    };

    const getColorForPercent = (percent) => {
        if (isError(percent) || typeof percent !== 'number') return '#ef4444';
        if (percent < 50) return '#4ade80';
        if (percent < 75) return '#fbbf24';
        if (percent < 90) return '#fb923c';
        return '#ef4444';
    };

    const styles = `
        .system-stats { font-size: 0.85em; }
        .stats-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; padding-bottom: 5px; border-bottom: 1px solid var(--border-color); }
        .stats-title { font-weight: bold; font-size: 1.1em; }
        .stats-timestamp { font-size: 0.9em; color: var(--text-secondary); }
        .refresh-toggle { cursor: pointer; padding: 3px 8px; border: 1px solid var(--border-color); border-radius: 3px; font-size: 0.85em; margin-left: 5px; }
        .refresh-toggle:hover { background-color: var(--title-bar-color); }
        .stats-section { margin-bottom: 12px; }
        .section-title { font-weight: bold; margin-bottom: 5px; color: var(--accent-primary); display: flex; justify-content: space-between; align-items: center; }
        .section-subtitle { font-size: 0.8em; color: var(--text-secondary); font-weight: normal; }
        .cpu-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(60px, 1fr)); gap: 4px; }
        .cpu-core { padding: 8px 4px; text-align: center; border-radius: 3px; font-size: 0.8em; }
        .metric-bar { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
        .metric-label { min-width: 80px; font-weight: 500; }
        .metric-progress { flex: 1; height: 20px; background: var(--bg-color); border-radius: 3px; overflow: hidden; position: relative; }
        .metric-fill { height: 100%; transition: width 0.3s ease; display: flex; align-items: center; justify-content: center; font-size: 0.75em; font-weight: bold; }
        .process-table { width: 100%; border-collapse: collapse; font-size: 0.8em; }
        .process-table th { text-align: left; padding: 4px; border-bottom: 1px solid var(--border-color); background: var(--title-bar-color); }
        .process-table td { padding: 3px 4px; border-bottom: 1px solid rgba(255,255,255,0.05); }
        .process-table tr:hover { background: var(--title-bar-color); }
        .info-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
        .info-box { padding: 8px; background: var(--title-bar-color); border-radius: 3px; text-align: center; }
        .info-value { font-size: 1.3em; font-weight: bold; color: var(--accent-primary); }
        .info-label { font-size: 0.8em; color: var(--text-secondary); margin-top: 3px; }
        .error-value { color: #ef4444; font-weight: bold; }
        .metrics-status { font-size: 0.7em; color: var(--text-secondary); margin-top: 10px; padding-top: 5px; border-top: 1px solid var(--border-color); }
        .cpu-section-layout { display: flex; gap: 12px; flex-wrap: wrap; }
        .cpu-cores-container { flex: 1; min-width: 200px; }
        .cpu-chart-container { flex: 1; min-width: 300px; }
    `;

    if (!systemData) {
        return <div>Loading system stats...</div>;
    }

    const metrics = systemData.metrics || {};
    const metricsStatus = systemData.metricsStatus || {};
    const cpuCoreCount = metrics.cpu ? metrics.cpu.length : (metrics.cpuCoreCount || 0);

    return (
        <>
            <style>{styles}</style>
            <div className="system-stats">
                <div className="stats-header">
                    <div className="stats-title">{systemData.hostname}</div>
                    <div style={{display: 'flex', gap: '5px', alignItems: 'center'}}>
                        <div className="stats-timestamp">{systemData.timestamp}</div>
                        <div className="refresh-toggle" onClick={() => setAutoRefresh(!autoRefresh)}>
                            {autoRefresh ? '⏸' : '▶'}
                        </div>
                        <div className="refresh-toggle" onClick={() => fetchHistory(60)} title="Show 1hr history">
                            📊
                        </div>
                    </div>
                </div>

                {/* CPU Section - Cores + History Chart */}
                {metrics.cpu && metrics.cpu.length > 0 && (
                    <div className="stats-section">
                        <div className="section-title">
                            <span>CPU</span>
                            <span className="section-subtitle">{cpuCoreCount} cores</span>
                        </div>
                        {/* CPU Cores Grid - Full Width */}
                        <div className="cpu-cores-container" style={{marginBottom: '12px'}}>
                            <div className="cpu-grid">
                                {metrics.cpu.map((core, idx) => (
                                    <div key={`cpu-core-${idx}`} className="cpu-core" style={{backgroundColor: getColorForPercent(core.value)}}>
                                        <div style={{fontSize: '0.7em', opacity: 0.8}}>{core.name}</div>
                                        <div style={{fontWeight: 'bold'}}>
                                            {isError(core.value) ? <span className="error-value">Error</span> : `${core.value}%`}
                                        </div>
                                    </div>
                                ))}
                            </div>
                        </div>

                        {/* CPU History Chart - Full Width Below */}
                        <div className="cpu-chart-section" style={{borderTop: '1px solid var(--border-color, #ddd)', paddingTop: '12px'}}>
                            <div className="chart-controls" style={{display: 'flex', gap: '8px', marginBottom: '8px', alignItems: 'center'}}>
                                <span style={{fontSize: '0.9em', fontWeight: '600'}}>CPU History</span>
                                <span style={{fontSize: '0.75em', color: '#666', marginLeft: '8px'}}>
                                    {timeRange === '5m' || timeRange === '15m' || timeRange === '30m' || timeRange === '1h' ? '5s samples' : '1m averages'}
                                </span>
                                <div style={{display: 'flex', gap: '4px', marginLeft: 'auto'}}>
                                    {['5m', '15m', '30m', '1h', '3h', '6h', '12h', '24h'].map(range => (
                                        <button
                                            key={range}
                                            onClick={() => setTimeRange(range)}
                                            style={{
                                                padding: '3px 8px',
                                                fontSize: '11px',
                                                cursor: 'pointer',
                                                border: '1px solid #ddd',
                                                borderRadius: '3px',
                                                backgroundColor: timeRange === range ? '#0366d6' : '#fff',
                                                color: timeRange === range ? '#fff' : '#24292e',
                                                fontWeight: timeRange === range ? '600' : '400'
                                            }}
                                        >
                                            {range}
                                        </button>
                                    ))}
                                </div>
                            </div>
                            <div style={{height: chartHeight + 'px', position: 'relative', backgroundColor: '#fff', borderRadius: '4px', border: '1px solid #e1e4e8'}}>
                                {window.cardComponents && window.cardComponents.uplot ?
                                    React.createElement(window.cardComponents.uplot, {
                                        element: {
                                            url: `/api/v1/ui/elements/uplot?source=/apps/WebHostMetrics/api/v1/metrics/history&metric=cpu&timerange=${timeRange}&delay=5&title=CPU Usage&ylabel=Usage %&height=${chartHeight}`
                                        },
                                        onError: onError
                                    })
                                    :
                                    <div style={{display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100%', color: '#666'}}>
                                        Loading chart component...
                                    </div>
                                }
                            </div>
                            <div
                                ref={chartResizeRef}
                                style={{
                                    height: '8px',
                                    cursor: 'ns-resize',
                                    backgroundColor: 'transparent',
                                    borderTop: '2px solid #e1e4e8',
                                    marginTop: '4px',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center'
                                }}
                                onMouseDown={(e) => {
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
                                }}
                            >
                                <div style={{width: '40px', height: '3px', backgroundColor: '#cbd5e0', borderRadius: '2px'}}></div>
                            </div>
                        </div>
                    </div>
                )}

                {/* Memory */}
                {metrics.memory && (
                    <div className="stats-section">
                        <div className="section-title">Memory</div>
                        <div className="metric-bar">
                            <div className="metric-label">
                                {formatValue(metrics.memory.used, ' ')} / {formatValue(metrics.memory.total, ' GB')}
                            </div>
                            <div className="metric-progress">
                                <div className="metric-fill" style={{
                                    width: isError(metrics.memory.percentUsed) ? '100%' : `${metrics.memory.percentUsed || 0}%`,
                                    backgroundColor: getColorForPercent(metrics.memory.percentUsed)
                                }}>
                                    {isError(metrics.memory.percentUsed) ?
                                        <span className="error-value">Error</span> :
                                        `${metrics.memory.percentUsed || 0}%`
                                    }
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                {/* Disks */}
                {metrics.disk && metrics.disk.length > 0 && (
                    <div className="stats-section">
                        <div className="section-title">Disk Usage</div>
                        {metrics.disk.map((disk, idx) => (
                            <div key={`disk-${idx}`} className="metric-bar">
                                <div className="metric-label">
                                    {disk.name} {formatValue(disk.used)}/{formatValue(disk.total, ' GB')}
                                </div>
                                <div className="metric-progress">
                                    <div className="metric-fill" style={{
                                        width: isError(disk.percentUsed) ? '100%' : `${disk.percentUsed || 0}%`,
                                        backgroundColor: getColorForPercent(disk.percentUsed)
                                    }}>
                                        {isError(disk.percentUsed) ?
                                            <span className="error-value">Error</span> :
                                            `${disk.percentUsed || 0}%`
                                        }
                                    </div>
                                </div>
                            </div>
                        ))}
                    </div>
                )}

                {/* System Info */}
                {metrics.uptime && metrics.system && (
                    <div className="stats-section">
                        <div className="section-title">System Info</div>
                        <div className="info-grid">
                            <div className="info-box">
                                <div className="info-value" style={{color: isError(metrics.uptime.days) ? '#ef4444' : 'var(--accent-primary)'}}>
                                    {isError(metrics.uptime.days) ?
                                        'Error' :
                                        `${metrics.uptime.days || 0}d ${metrics.uptime.hours || 0}h`
                                    }
                                </div>
                                <div className="info-label">Uptime</div>
                            </div>
                            <div className="info-box">
                                <div className="info-value">{formatNumber(metrics.system.processes)}</div>
                                <div className="info-label">Processes</div>
                            </div>
                            <div className="info-box">
                                <div className="info-value" style={{color: isError(metrics.system.threads) || typeof metrics.system.threads !== 'number' ? '#ef4444' : 'var(--accent-primary)'}}>
                                    {formatNumber(metrics.system.threads)}
                                </div>
                                <div className="info-label">Threads</div>
                            </div>
                        </div>
                    </div>
                )}

                {/* Network */}
                {metrics.network && metrics.network.length > 0 && (
                    <div className="stats-section">
                        <div className="section-title">Network Activity</div>
                        {metrics.network.slice(0, 3).map((iface, idx) => (
                            <div key={`net-${idx}`} className="metric-bar">
                                <div className="metric-label" style={{fontSize: '0.75em', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '150px'}} title={iface.name}>
                                    {iface.name}
                                </div>
                                <div style={{
                                    fontWeight: 'bold',
                                    minWidth: '80px',
                                    textAlign: 'right',
                                    color: isError(iface.value) ? '#ef4444' : 'inherit'
                                }}>
                                    {isError(iface.value) ? 'Error' : `${iface.value || 0} ${iface.unit}`}
                                </div>
                            </div>
                        ))}
                    </div>
                )}

                {/* Top Processes by CPU */}
                {metrics.topProcessesCPU && metrics.topProcessesCPU.length > 0 && (
                    <div className="stats-section">
                        <div className="section-title">Top Processes (CPU)</div>
                        <table className="process-table">
                            <thead>
                                <tr>
                                    <th>Process</th>
                                    <th>CPU Time</th>
                                    <th>Memory (MB)</th>
                                </tr>
                            </thead>
                            <tbody>
                                {metrics.topProcessesCPU.slice(0, 5).map((proc, idx) => (
                                    <tr key={`proc-${idx}`}>
                                        <td>{proc.name}</td>
                                        <td>{proc.cpu}</td>
                                        <td>{proc.memory}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}

                {/* Metrics Collection Status */}
                {metricsStatus && (
                    <div className="metrics-status">
                        Samples: {metricsStatus.samplesCollected || 0} |
                        Aggregated: {metricsStatus.aggregatedMinutes || 0} min |
                        Last: {metricsStatus.lastCollection || 'N/A'}
                        {metricsStatus.errorCount > 0 && <span style={{color: '#ef4444'}}> | Errors: {metricsStatus.errorCount}</span>}
                    </div>
                )}

                {/* History Modal */}
                {showHistory && historyData && (
                    <div style={{
                        position: 'fixed',
                        top: 0, left: 0, right: 0, bottom: 0,
                        backgroundColor: 'rgba(0,0,0,0.8)',
                        display: 'flex',
                        alignItems: 'center',
                        justifyContent: 'center',
                        zIndex: 1000
                    }} onClick={() => setShowHistory(false)}>
                        <div style={{
                            backgroundColor: 'var(--bg-color)',
                            padding: '20px',
                            borderRadius: '8px',
                            maxWidth: '90%',
                            maxHeight: '80%',
                            overflow: 'auto'
                        }} onClick={e => e.stopPropagation()}>
                            <h3>Metrics History ({historyData.minutes} minutes, {historyData.recordCount} records)</h3>
                            <table className="process-table">
                                <thead>
                                    <tr>
                                        <th>Time</th>
                                        <th>CPU Avg</th>
                                        <th>CPU Max</th>
                                        <th>Mem %</th>
                                        <th>Processes</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    {historyData.data && historyData.data.slice(-30).map((row, idx) => (
                                        <tr key={`hist-${idx}`}>
                                            <td>{row.MinuteTimestamp}</td>
                                            <td style={{color: getColorForPercent(row.Cpu?.Avg)}}>{row.Cpu?.Avg || 'N/A'}%</td>
                                            <td style={{color: getColorForPercent(row.Cpu?.Max)}}>{row.Cpu?.Max || 'N/A'}%</td>
                                            <td style={{color: getColorForPercent(row.Memory?.PercentUsed_Avg)}}>{row.Memory?.PercentUsed_Avg || 'N/A'}%</td>
                                            <td>{row.System?.Processes_Avg || 'N/A'}</td>
                                        </tr>
                                    ))}
                                </tbody>
                            </table>
                            <button onClick={() => setShowHistory(false)} style={{marginTop: '10px', padding: '5px 15px'}}>Close</button>
                        </div>
                    </div>
                )}
            </div>
        </>
    );
};

window.cardComponents['server-heatmap'] = ServerHeatmapCard;
