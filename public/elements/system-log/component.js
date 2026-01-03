const { useState, useEffect } = React;

const SystemLogCard = ({ onError }) => {
    const [events, setEvents] = useState([]);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [lastUpdate, setLastUpdate] = useState(null);
    const [lines, setLines] = useState(100);
    const [filter, setFilter] = useState('');
    const [jobStatus, setJobStatus] = useState([]);

    const fetchLogRef = React.useRef();

    const fetchLog = () => {
        if (fetchLogRef.current) {
            fetchLogRef.current();
        }
    };

    useEffect(() => {
        let isMounted = true;

        fetchLogRef.current = () => {
            // Fetch job status
            window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/job-status')
                .then(res => res.json())
                .then(data => {
                    if (isMounted) {
                        setJobStatus(data || []);
                    }
                })
                .catch(err => {
                    console.error("Failed to fetch job status:", err);
                });

            const params = new URLSearchParams({
                lines: lines,
                ...(filter && { filter: filter })
            });

            window.psweb_fetchWithAuthHandling(`/api/v1/ui/elements/system-log?${params}`)
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch log", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.json();
                })
                .then(data => {
                    if (isMounted) {
                        setEvents(data.entries || []);
                        setLastUpdate(new Date());
                    }
                })
                .catch(err => {
                    if (isMounted && err.name !== 'Unauthorized') {
                        console.error("SystemLogCard fetch error:", err);
                        onError({ message: err.message, name: err.name });
                    }
                });
        };

        fetchLog();

        const interval = autoRefresh ? setInterval(fetchLog, 5000) : null;

        return () => {
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh, lines, filter]);

    const toggleAutoRefresh = () => {
        setAutoRefresh(!autoRefresh);
    };

    const escapeHtml = (text) => {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    };

    const styles = `
        .log-controls {
            display: flex;
            gap: 10px;
            align-items: center;
            margin-bottom: 10px;
            padding: 8px;
            background: var(--title-bar-color);
            border-radius: 3px;
        }
        .log-controls label {
            font-size: 0.85em;
            display: flex;
            align-items: center;
            gap: 5px;
        }
        .log-controls input[type="text"],
        .log-controls input[type="number"] {
            padding: 4px 8px;
            border: 1px solid var(--border-color);
            background: var(--bg-color);
            color: var(--text-color);
            border-radius: 3px;
            font-size: 0.85em;
        }
        .log-controls input[type="number"] {
            width: 80px;
        }
        .log-controls button {
            padding: 4px 12px;
            border: 1px solid var(--border-color);
            background: var(--bg-color);
            color: var(--text-color);
            border-radius: 3px;
            cursor: pointer;
            font-size: 0.85em;
        }
        .log-controls button:hover {
            background: var(--accent-primary);
        }
        .log-container {
            background: var(--bg-color);
            border: 1px solid var(--border-color);
            border-radius: 3px;
            padding: 10px;
            height: calc(100% - 60px);
            overflow-y: auto;
            font-family: 'Consolas', 'Monaco', monospace;
            font-size: 0.8em;
        }
        .log-entry {
            padding: 4px 0;
            border-bottom: 1px solid rgba(255,255,255,0.05);
            white-space: pre-wrap;
            word-break: break-all;
        }
        .log-entry:hover {
            background: var(--title-bar-color);
        }
        .log-timestamp {
            color: var(--accent-primary);
            font-weight: bold;
        }
        .log-level {
            display: inline-block;
            padding: 2px 6px;
            border-radius: 2px;
            font-size: 0.75em;
            font-weight: bold;
            margin: 0 5px;
        }
        .log-level.Info { background: #4a9eff; color: #000; }
        .log-level.Warning { background: #fbbf24; color: #000; }
        .log-level.Error { background: #ef4444; color: #fff; }
        .log-category {
            color: #a78bfa;
            font-weight: 500;
        }
        .log-message {
            color: var(--text-color);
        }
        .log-empty {
            text-align: center;
            padding: 20px;
            color: var(--text-secondary);
        }
    `;

    return (
        <>
            <style>{styles}</style>
            <div className="log-controls">
                <label>
                    Lines:
                    <input
                        type="number"
                        value={lines}
                        min="10"
                        max="1000"
                        step="10"
                        onChange={(e) => setLines(parseInt(e.target.value))}
                    />
                </label>
                <label>
                    Filter:
                    <input
                        type="text"
                        value={filter}
                        placeholder="Search..."
                        onChange={(e) => setFilter(e.target.value)}
                    />
                </label>
                <button onClick={fetchLog}>Refresh</button>
                <button onClick={toggleAutoRefresh}>
                    {autoRefresh ? '⏸ Pause' : '▶ Resume'}
                </button>
                {jobStatus.length > 0 && (
                    <div style={{ fontSize: '0.75em', marginLeft: 'auto', display: 'flex', gap: '8px', alignItems: 'center' }}>
                        <span>Jobs:</span>
                        {jobStatus.map(job => (
                            <span key={job.Id} style={{
                                padding: '2px 6px',
                                borderRadius: '3px',
                                background: job.State === 'Running' ? '#10b981' : job.State === 'Failed' ? '#ef4444' : '#6b7280',
                                color: '#fff',
                                fontSize: '0.9em'
                            }}>
                                {job.Name.replace(/^Log_Tail: .*[\\\/]/, '')} - {job.State} {job.RunningTime && `(${job.RunningTime})`}
                            </span>
                        ))}
                    </div>
                )}
            </div>
            <div className="log-container">
                {events && events.length > 0 ? (
                    events.map((entry, index) => {
                        if (entry.raw) {
                            return (
                                <div key={index} className="log-entry">
                                    {entry.raw}
                                </div>
                            );
                        }

                        return (
                            <div key={index} className="log-entry">
                                <span className="log-timestamp">{entry.timestamp}</span>
                                <span className={`log-level ${entry.level}`}>{entry.level}</span>
                                <span className="log-category">[{entry.category}]</span>
                                <span className="log-message">{entry.message}</span>
                                {entry.data && (
                                    <div style={{ marginLeft: '20px', color: '#94a3b8' }}>
                                        {entry.data}
                                    </div>
                                )}
                            </div>
                        );
                    })
                ) : (
                    <div className="log-empty">No log entries found</div>
                )}
            </div>
        </>
    );
};

window.cardComponents['system-log'] = SystemLogCard;
