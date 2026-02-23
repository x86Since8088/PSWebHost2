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

// CPU Histogram Card - Standalone component for CPU usage tracking
const CpuHistogramCard = ({ onError, autoRefresh = true }) => {
    const [cpuData, setCpuData] = useState(null);
    const [cpuHistory, setCpuHistory] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);

    useEffect(() => {
        const fetchCpuData = async () => {
            try {
                const res = await window.psweb_fetchWithAuthHandling('/apps/WebHostMetrics/cards/cpu-histogram');
                if (!res.ok) {
                    const error = new Error(`HTTP error! status: ${res.status}`);
                    error.status = res.status;
                    error.statusText = res.statusText;
                    throw error;
                }

                const data = await res.json();
                setCpuData(data);

                // Track CPU history for chart
                if (data.cpu && data.cpu.length > 0) {
                    const coreValues = data.cpu.map(core => core.value);
                    const avgValue = coreValues.reduce((sum, val) => sum + val, 0) / coreValues.length;
                    const now = new Date();
                    const timeStr = now.toLocaleTimeString('en-US', { hour12: false });

                    setCpuHistory(prev => [...prev, {
                        time: timeStr,
                        cores: coreValues,
                        avg: avgValue
                    }].slice(-60)); // Keep last 60 points (5 minutes)
                }

                setLoading(false);
                setError(null);
            } catch (err) {
                console.error('[CpuHistogram] Fetch error:', err);
                setError(err.message);
                setLoading(false);
                if (onError) onError(err);
            }
        };

        // Initial fetch
        fetchCpuData();

        // Set up polling if autoRefresh is enabled
        let interval;
        if (autoRefresh) {
            interval = setInterval(fetchCpuData, 5000); // Poll every 5 seconds
        }

        return () => {
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh, onError]);

    if (loading) {
        return <div style={{ padding: '20px', textAlign: 'center' }}>Loading CPU data...</div>;
    }

    if (error) {
        return (
            <div style={{ padding: '20px', color: 'var(--error-color)' }}>
                <strong>Error loading CPU data:</strong> {error}
            </div>
        );
    }

    if (!cpuData || !cpuData.cpu) {
        return <div style={{ padding: '20px' }}>No CPU data available</div>;
    }

    const coreCount = cpuData.cpu.length;

    return (
        <div style={{ padding: '10px' }}>
            <h3 style={{ margin: '0 0 10px 0', fontSize: '1em' }}>CPU Usage History</h3>

            {/* CPU History Chart */}
            <CpuHistoryChart cpuHistory={cpuHistory} coreCount={coreCount} />

            {/* Current CPU Stats */}
            <div style={{ marginTop: '15px', fontSize: '0.85em' }}>
                <div style={{ marginBottom: '5px' }}>
                    <strong>CPU Cores:</strong> {coreCount}
                </div>
                <div style={{ marginBottom: '5px' }}>
                    <strong>Average Usage:</strong> {cpuHistory.length > 0 ? cpuHistory[cpuHistory.length - 1].avg.toFixed(1) : '0'}%
                </div>
                <div style={{ fontSize: '0.75em', color: 'var(--text-secondary)' }}>
                    Showing last {Math.min(cpuHistory.length, 60)} samples (5 second intervals)
                </div>
            </div>
        </div>
    );
};

// Register component globally
window.cardComponents = window.cardComponents || {};
window.cardComponents['cpu-histogram'] = CpuHistogramCard;
