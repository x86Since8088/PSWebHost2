const { useState, useEffect } = React;

const ServerHeatmapCard = ({ onError }) => {
    const [systemData, setSystemData] = useState(null);
    const [autoRefresh, setAutoRefresh] = useState(true);

    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/server-heatmap')
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
    }, [autoRefresh]);

    const isError = (value) => {
        return value === "Error" || value === "error";
    };

    const formatValue = (value, suffix = '') => {
        if (isError(value)) {
            return <span style={{color: '#ef4444', fontWeight: 'bold'}}>Error</span>;
        }
        return `${value}${suffix}`;
    };

    const getColorForPercent = (percent) => {
        if (isError(percent)) return '#ef4444'; // red for errors
        if (percent < 50) return '#4ade80'; // green
        if (percent < 75) return '#fbbf24'; // yellow
        if (percent < 90) return '#fb923c'; // orange
        return '#ef4444'; // red
    };

    const styles = `
        .system-stats { font-size: 0.85em; }
        .stats-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 10px; padding-bottom: 5px; border-bottom: 1px solid var(--border-color); }
        .stats-title { font-weight: bold; font-size: 1.1em; }
        .stats-timestamp { font-size: 0.9em; color: var(--text-secondary); }
        .refresh-toggle { cursor: pointer; padding: 3px 8px; border: 1px solid var(--border-color); border-radius: 3px; font-size: 0.85em; }
        .refresh-toggle:hover { background-color: var(--title-bar-color); }
        .stats-section { margin-bottom: 12px; }
        .section-title { font-weight: bold; margin-bottom: 5px; color: var(--accent-primary); }
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
    `;

    if (!systemData) {
        return <div>Loading system stats...</div>;
    }

    const metrics = systemData.metrics || {};

    return (
        <>
            <style>{styles}</style>
            <div className="system-stats">
                <div className="stats-header">
                    <div className="stats-title">{systemData.hostname}</div>
                    <div style={{display: 'flex', gap: '10px', alignItems: 'center'}}>
                        <div className="stats-timestamp">{systemData.timestamp}</div>
                        <div className="refresh-toggle" onClick={() => setAutoRefresh(!autoRefresh)}>
                            {autoRefresh ? '⏸ Pause' : '▶ Resume'}
                        </div>
                    </div>
                </div>

                {/* CPU Cores */}
                {metrics.cpu && (
                    <div className="stats-section">
                        <div className="section-title">CPU Cores ({metrics.cpu.length})</div>
                        <div className="cpu-grid">
                            {metrics.cpu.map((core, idx) => (
                                <div key={idx} className="cpu-core" style={{backgroundColor: getColorForPercent(core.value)}}>
                                    <div style={{fontSize: '0.7em', opacity: 0.8}}>{core.name}</div>
                                    <div style={{fontWeight: 'bold'}}>
                                        {isError(core.value) ? <span className="error-value">Error</span> : `${core.value}%`}
                                    </div>
                                </div>
                            ))}
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
                                    width: isError(metrics.memory.percentUsed) ? '100%' : `${metrics.memory.percentUsed}%`,
                                    backgroundColor: getColorForPercent(metrics.memory.percentUsed)
                                }}>
                                    {isError(metrics.memory.percentUsed) ?
                                        <span className="error-value">Error</span> :
                                        `${metrics.memory.percentUsed}%`
                                    }
                                </div>
                            </div>
                        </div>
                    </div>
                )}

                {/* Disks */}
                {metrics.disk && (
                    <div className="stats-section">
                        <div className="section-title">Disk Usage</div>
                        {metrics.disk.map((disk, idx) => (
                            <div key={idx} className="metric-bar">
                                <div className="metric-label">
                                    {disk.name} {formatValue(disk.used)}/{formatValue(disk.total, ' GB')}
                                </div>
                                <div className="metric-progress">
                                    <div className="metric-fill" style={{
                                        width: isError(disk.percentUsed) ? '100%' : `${disk.percentUsed}%`,
                                        backgroundColor: getColorForPercent(disk.percentUsed)
                                    }}>
                                        {isError(disk.percentUsed) ?
                                            <span className="error-value">Error</span> :
                                            `${disk.percentUsed}%`
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
                                        `${metrics.uptime.days}d ${metrics.uptime.hours}h`
                                    }
                                </div>
                                <div className="info-label">Uptime</div>
                            </div>
                            <div className="info-box">
                                <div className="info-value">{formatValue(metrics.system.processes)}</div>
                                <div className="info-label">Processes</div>
                            </div>
                            <div className="info-box">
                                <div className="info-value" style={{color: isError(metrics.system.threads) ? '#ef4444' : 'var(--accent-primary)'}}>
                                    {formatValue(metrics.system.threads)}
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
                            <div key={idx} className="metric-bar">
                                <div className="metric-label" style={{fontSize: '0.75em'}}>{iface.name}</div>
                                <div style={{
                                    fontWeight: 'bold',
                                    minWidth: '60px',
                                    textAlign: 'right',
                                    color: isError(iface.value) ? '#ef4444' : 'inherit'
                                }}>
                                    {isError(iface.value) ? 'Error' : `${iface.value} ${iface.unit}`}
                                </div>
                            </div>
                        ))}
                    </div>
                )}

                {/* Top Processes by CPU */}
                {metrics.topProcessesCPU && (
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
                                    <tr key={idx}>
                                        <td>{proc.name}</td>
                                        <td>{proc.cpu}</td>
                                        <td>{proc.memory}</td>
                                    </tr>
                                ))}
                            </tbody>
                        </table>
                    </div>
                )}
            </div>
        </>
    );
};

window.cardComponents['server-heatmap'] = ServerHeatmapCard;
