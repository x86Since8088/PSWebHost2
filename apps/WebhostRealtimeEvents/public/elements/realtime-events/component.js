const { useState, useEffect, useRef } = React;

const RealtimeEventsCard = ({ onError }) => {
    const [logs, setLogs] = useState([]);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [lastUpdate, setLastUpdate] = useState(null);
    const [selectedLogs, setSelectedLogs] = useState(new Set());
    const [filterText, setFilterText] = useState('');
    const [wordWrap, setWordWrap] = useState(false);
    const [loading, setLoading] = useState(false);

    // Time range controls
    const [timeRange, setTimeRange] = useState(15); // minutes
    const [customTimeRange, setCustomTimeRange] = useState(false);
    const [startTime, setStartTime] = useState('');
    const [endTime, setEndTime] = useState('');

    // Advanced filters
    const [categoryFilter, setCategoryFilter] = useState('');
    const [severityFilter, setSeverityFilter] = useState('');
    const [sourceFilter, setSourceFilter] = useState('');
    const [userIDFilter, setUserIDFilter] = useState('');
    const [sessionIDFilter, setSessionIDFilter] = useState('');

    // Sorting
    const [sortBy, setSortBy] = useState('Date');
    const [sortOrder, setSortOrder] = useState('desc');

    // Display options
    const [maxEvents, setMaxEvents] = useState(1000);
    const [visibleColumns, setVisibleColumns] = useState({
        checkbox: true,
        LocalTime: true,
        Severity: true,
        Category: true,
        Message: true,
        Source: true,
        ActivityName: false,
        PercentComplete: false,
        UserID: false,
        SessionID: false,
        RunspaceID: false,
        Data: false
    });

    const [columnWidths, setColumnWidths] = useState({
        checkbox: 40,
        LocalTime: 180,
        Severity: 100,
        Category: 120,
        Message: 300,
        Source: 200,
        ActivityName: 150,
        PercentComplete: 80,
        UserID: 150,
        SessionID: 120,
        RunspaceID: 80,
        Data: 200
    });

    const resizingColumn = useRef(null);
    const fetchDataRef = useRef();

    const fetchData = () => {
        if (fetchDataRef.current) {
            fetchDataRef.current();
        }
    };

    const handleClearLogs = () => {
        setLogs([]);
        setSelectedLogs(new Set());
        setLastUpdate(new Date());

        // Set time filter to next 24 hours
        const now = new Date();
        const futureTime = new Date(now.getTime() + (24 * 60 * 60 * 1000)); // 24 hours from now

        // Format for datetime-local input: YYYY-MM-DDThh:mm
        const formatDateTime = (date) => {
            const year = date.getFullYear();
            const month = String(date.getMonth() + 1).padStart(2, '0');
            const day = String(date.getDate()).padStart(2, '0');
            const hours = String(date.getHours()).padStart(2, '0');
            const minutes = String(date.getMinutes()).padStart(2, '0');
            return `${year}-${month}-${day}T${hours}:${minutes}`;
        };

        setCustomTimeRange(true);
        setStartTime(formatDateTime(now));
        setEndTime(formatDateTime(futureTime));
    };

    const handleSelectAll = (checked) => {
        if (checked) {
            setSelectedLogs(new Set(logs.map(log => log._id)));
        } else {
            setSelectedLogs(new Set());
        }
    };

    const handleSelectLog = (logId, checked) => {
        setSelectedLogs(prev => {
            const newSet = new Set(prev);
            if (checked) {
                newSet.add(logId);
            } else {
                newSet.delete(logId);
            }
            return newSet;
        });
    };

    const handleExportCSV = () => {
        const selectedData = logs.filter(log => selectedLogs.has(log._id));

        if (selectedData.length === 0) {
            alert('Please select logs to export');
            return;
        }

        const headers = ['LocalTime', 'Severity', 'Category', 'Message', 'Source', 'ActivityName', 'PercentComplete', 'UserID', 'SessionID', 'RunspaceID', 'Data'];
        const csvContent = [
            headers.join(','),
            ...selectedData.map(log => [
                `"${log.LocalTime || ''}"`,
                `"${log.Severity || ''}"`,
                `"${log.Category || ''}"`,
                `"${(log.Message || '').replace(/"/g, '""')}"`,
                `"${log.Source || ''}"`,
                `"${log.ActivityName || ''}"`,
                `"${log.PercentComplete || ''}"`,
                `"${log.UserID || ''}"`,
                `"${log.SessionID || ''}"`,
                `"${log.RunspaceID || ''}"`,
                `"${(log.Data || '').replace(/"/g, '""')}"`
            ].join(','))
        ].join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `realtime-events-${new Date().toISOString().slice(0,19).replace(/:/g,'-')}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const handleCopyTSV = () => {
        const selectedData = logs.filter(log => selectedLogs.has(log._id));

        if (selectedData.length === 0) {
            alert('Please select logs to copy');
            return;
        }

        const headers = ['LocalTime', 'Severity', 'Category', 'Message', 'Source', 'ActivityName', 'PercentComplete', 'UserID', 'SessionID', 'RunspaceID', 'Data'];
        const tsvContent = [
            headers.join('\t'),
            ...selectedData.map(log => [
                log.LocalTime || '',
                log.Severity || '',
                log.Category || '',
                log.Message || '',
                log.Source || '',
                log.ActivityName || '',
                log.PercentComplete || '',
                log.UserID || '',
                log.SessionID || '',
                log.RunspaceID || '',
                log.Data || ''
            ].join('\t'))
        ].join('\n');

        navigator.clipboard.writeText(tsvContent).then(() => {
            alert(`Copied ${selectedData.length} logs to clipboard as TSV`);
        }).catch(err => {
            console.error('Failed to copy:', err);
            alert('Failed to copy to clipboard');
        });
    };

    const handleToggleColumn = (columnKey) => {
        setVisibleColumns(prev => ({
            ...prev,
            [columnKey]: !prev[columnKey]
        }));
    };

    const handleSort = (column) => {
        if (sortBy === column) {
            setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
        } else {
            setSortBy(column);
            setSortOrder('desc');
        }
    };

    useEffect(() => {
        let isMounted = true;

        fetchDataRef.current = () => {
            setLoading(true);

            // Build query string
            const params = new URLSearchParams();

            // Time range
            if (customTimeRange && startTime && endTime) {
                // Send as local datetime string (server will interpret as its local time)
                // Format: YYYY-MM-DDThh:mm:ss
                const formatForServer = (dateTimeLocal) => {
                    return dateTimeLocal + ':00'; // Add seconds if not present
                };
                params.append('earliest', formatForServer(startTime));
                params.append('latest', formatForServer(endTime));
            } else {
                params.append('timeRange', timeRange);
            }

            // Filters
            if (filterText) params.append('filter', filterText);
            if (categoryFilter) params.append('category', categoryFilter);
            if (severityFilter) params.append('severity', severityFilter);
            if (sourceFilter) params.append('source', sourceFilter);
            if (userIDFilter) params.append('userID', userIDFilter);
            if (sessionIDFilter) params.append('sessionID', sessionIDFilter);

            // Sorting
            params.append('sortBy', sortBy);
            params.append('sortOrder', sortOrder);

            // Count
            params.append('count', maxEvents);

            const url = `/apps/WebhostRealtimeEvents/api/v1/logs?${params.toString()}`;

            window.psweb_fetchWithAuthHandling(url)
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch event logs", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.json();
                })
                .then(data => {
                    if (!isMounted) return;

                    const logsArray = (data.logs || []).map((log, index) => ({
                        ...log,
                        _id: `log-${Date.now()}-${index}`,
                        Data: typeof log.Data === 'object' ? JSON.stringify(log.Data) : log.Data
                    }));

                    setLogs(logsArray);
                    setLastUpdate(new Date());
                    setLoading(false);

                    // Clear selections that are no longer in the list
                    setSelectedLogs(prev => {
                        const newSet = new Set();
                        const logIds = new Set(logsArray.map(log => log._id));
                        prev.forEach(id => {
                            if (logIds.has(id)) newSet.add(id);
                        });
                        return newSet;
                    });
                })
                .catch(err => {
                    if (isMounted && err.name !== 'Unauthorized') {
                        console.error("RealtimeEventsCard fetch error:", err);
                        setLoading(false);
                    }
                });
        };

        fetchData();

        const interval = autoRefresh ? setInterval(fetchData, 5000) : null;

        return () => {
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh, filterText, categoryFilter, severityFilter, sourceFilter, userIDFilter, sessionIDFilter, timeRange, customTimeRange, startTime, endTime, sortBy, sortOrder, maxEvents]);

    const handleMouseDown = (columnKey, e) => {
        e.preventDefault();
        resizingColumn.current = {
            columnKey,
            startX: e.clientX,
            startWidth: columnWidths[columnKey]
        };

        const handleMouseMove = (e) => {
            if (resizingColumn.current) {
                const diff = e.clientX - resizingColumn.current.startX;
                const newWidth = Math.max(50, resizingColumn.current.startWidth + diff);
                setColumnWidths(prev => ({
                    ...prev,
                    [resizingColumn.current.columnKey]: newWidth
                }));
            }
        };

        const handleMouseUp = () => {
            resizingColumn.current = null;
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);
        };

        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);
    };

    const allColumns = [
        { key: 'checkbox', label: '', width: columnWidths.checkbox, noResize: true, sortable: false },
        { key: 'LocalTime', label: 'Time', width: columnWidths.LocalTime, sortable: true },
        { key: 'Severity', label: 'Severity', width: columnWidths.Severity, sortable: true },
        { key: 'Category', label: 'Category', width: columnWidths.Category, sortable: true },
        { key: 'Message', label: 'Message', width: columnWidths.Message, sortable: false },
        { key: 'Source', label: 'Source', width: columnWidths.Source, sortable: true },
        { key: 'ActivityName', label: 'Activity', width: columnWidths.ActivityName, sortable: false },
        { key: 'PercentComplete', label: 'Progress', width: columnWidths.PercentComplete, sortable: false },
        { key: 'UserID', label: 'User ID', width: columnWidths.UserID, sortable: true },
        { key: 'SessionID', label: 'Session ID', width: columnWidths.SessionID, sortable: true },
        { key: 'RunspaceID', label: 'Runspace', width: columnWidths.RunspaceID, sortable: false },
        { key: 'Data', label: 'Details', width: columnWidths.Data, sortable: false },
    ];

    const columns = allColumns.filter(col => visibleColumns[col.key]);

    const allLogsSelected = logs.length > 0 && logs.every(log => selectedLogs.has(log._id));
    const someLogsSelected = logs.some(log => selectedLogs.has(log._id)) && !allLogsSelected;

    const getSeverityColor = (severity) => {
        switch (severity?.toLowerCase()) {
            case 'critical': return '#dc2626';
            case 'error': return '#ef4444';
            case 'warning': return '#f59e0b';
            case 'info': return '#3b82f6';
            case 'verbose': return '#6b7280';
            case 'debug': return '#8b5cf6';
            default: return 'var(--text-color)';
        }
    };

    const styles = `
        .realtime-events-container {
            width: 100%;
            overflow: auto;
        }
        .realtime-events-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
            padding-bottom: 5px;
            border-bottom: 1px solid var(--border-color);
        }
        .realtime-events-title {
            font-weight: bold;
            font-size: 1.1em;
        }
        .realtime-events-controls {
            display: flex;
            gap: 10px;
            align-items: center;
        }
        .realtime-events-toolbar {
            display: flex;
            gap: 8px;
            align-items: center;
            margin-bottom: 8px;
            padding: 8px;
            background: var(--title-bar-color);
            border-radius: 3px;
            flex-wrap: wrap;
        }
        .realtime-events-timestamp {
            font-size: 0.85em;
            color: var(--text-secondary);
        }
        .refresh-btn {
            cursor: pointer;
            padding: 4px 10px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            font-size: 0.9em;
            background: var(--bg-color);
            color: var(--text-color);
        }
        .refresh-btn:hover {
            background: var(--title-bar-color);
        }
        .refresh-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .filter-input {
            padding: 4px 8px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            background: var(--bg-color);
            color: var(--text-color);
            font-size: 0.9em;
            min-width: 150px;
        }
        .filter-section {
            display: flex;
            gap: 8px;
            align-items: center;
            flex-wrap: wrap;
        }
        .toolbar-label {
            font-size: 0.85em;
            color: var(--text-secondary);
            white-space: nowrap;
        }
        .time-range-select {
            padding: 4px 8px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            background: var(--bg-color);
            color: var(--text-color);
            font-size: 0.9em;
        }
        .resizable-table {
            width: 100%;
            border-collapse: collapse;
            table-layout: fixed;
        }
        .resizable-table th,
        .resizable-table td {
            border: 1px solid var(--border-color);
            padding: 6px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
            position: relative;
        }
        .resizable-table.word-wrap th,
        .resizable-table.word-wrap td {
            white-space: normal;
            word-wrap: break-word;
            overflow-wrap: break-word;
        }
        .resizable-table th {
            background: var(--title-bar-color);
            font-weight: bold;
            user-select: none;
        }
        .resizable-table th.sortable {
            cursor: pointer;
        }
        .resizable-table th.sortable:hover {
            background: var(--accent-primary);
        }
        .resizable-table tr:hover {
            background: var(--title-bar-color);
        }
        .resize-handle {
            position: absolute;
            right: 0;
            top: 0;
            bottom: 0;
            width: 5px;
            cursor: col-resize;
            background: transparent;
            z-index: 1;
        }
        .resize-handle:hover {
            background: var(--accent-primary);
        }
        .sort-indicator {
            margin-left: 4px;
            font-size: 0.8em;
        }
        .loading-indicator {
            display: inline-block;
            margin-left: 8px;
            animation: spin 1s linear infinite;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    `;

    return (
        <>
            <style>{styles}</style>
            <div className="realtime-events-container">
                <div className="realtime-events-header">
                    <div className="realtime-events-title">
                        Real-time Events ({logs.length} logs{selectedLogs.size > 0 ? `, ${selectedLogs.size} selected` : ''})
                        {loading && <span className="loading-indicator">↻</span>}
                    </div>
                    <div className="realtime-events-controls">
                        {lastUpdate && (
                            <div className="realtime-events-timestamp">
                                Updated: {lastUpdate.toLocaleTimeString()}
                            </div>
                        )}
                        <button className="refresh-btn" onClick={fetchData} disabled={loading}>
                            ↻ Refresh
                        </button>
                        <button className="refresh-btn" onClick={handleClearLogs}>
                            🗑 Clear
                        </button>
                        <button className="refresh-btn" onClick={() => setAutoRefresh(!autoRefresh)}>
                            {autoRefresh ? '⏸ Pause' : '▶ Resume'}
                        </button>
                    </div>
                </div>

                {/* Time Range Controls */}
                <div className="realtime-events-toolbar">
                    <span className="toolbar-label">Time Range:</span>
                    <select
                        className="time-range-select"
                        value={customTimeRange ? 'custom' : timeRange}
                        onChange={(e) => {
                            if (e.target.value === 'custom') {
                                setCustomTimeRange(true);
                            } else {
                                setCustomTimeRange(false);
                                setTimeRange(parseInt(e.target.value));
                            }
                        }}
                    >
                        <option value="5">Last 5 minutes</option>
                        <option value="15">Last 15 minutes</option>
                        <option value="30">Last 30 minutes</option>
                        <option value="60">Last hour</option>
                        <option value="240">Last 4 hours</option>
                        <option value="1440">Last 24 hours</option>
                        <option value="custom">Custom Range</option>
                    </select>
                    {customTimeRange && (
                        <>
                            <input
                                type="datetime-local"
                                className="filter-input"
                                value={startTime}
                                onChange={(e) => setStartTime(e.target.value)}
                                placeholder="Start time"
                            />
                            <input
                                type="datetime-local"
                                className="filter-input"
                                value={endTime}
                                onChange={(e) => setEndTime(e.target.value)}
                                placeholder="End time"
                            />
                        </>
                    )}
                </div>

                {/* Filter Controls */}
                <div className="realtime-events-toolbar">
                    <span className="toolbar-label">Filters:</span>
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Search all fields..."
                        value={filterText}
                        onChange={(e) => setFilterText(e.target.value)}
                    />
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Category..."
                        value={categoryFilter}
                        onChange={(e) => setCategoryFilter(e.target.value)}
                        style={{ minWidth: '120px' }}
                    />
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Severity..."
                        value={severityFilter}
                        onChange={(e) => setSeverityFilter(e.target.value)}
                        style={{ minWidth: '120px' }}
                    />
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Source..."
                        value={sourceFilter}
                        onChange={(e) => setSourceFilter(e.target.value)}
                        style={{ minWidth: '120px' }}
                    />
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="User ID..."
                        value={userIDFilter}
                        onChange={(e) => setUserIDFilter(e.target.value)}
                        style={{ minWidth: '120px' }}
                    />
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Session ID..."
                        value={sessionIDFilter}
                        onChange={(e) => setSessionIDFilter(e.target.value)}
                        style={{ minWidth: '120px' }}
                    />
                </div>

                {/* Action Toolbar */}
                <div className="realtime-events-toolbar">
                    <span className="toolbar-label">Max Events:</span>
                    <input
                        type="number"
                        className="filter-input"
                        style={{ width: '80px' }}
                        min="10"
                        max="10000"
                        value={maxEvents}
                        onChange={(e) => setMaxEvents(Math.max(10, parseInt(e.target.value) || 1000))}
                    />
                    <button className="refresh-btn" onClick={handleExportCSV}>
                        💾 Export CSV
                    </button>
                    <button className="refresh-btn" onClick={handleCopyTSV}>
                        📋 Copy TSV
                    </button>
                    <button className="refresh-btn" onClick={() => setWordWrap(!wordWrap)}>
                        {wordWrap ? '📝 Wrap: On' : '📝 Wrap: Off'}
                    </button>
                    <details style={{ position: 'relative', display: 'inline-block' }}>
                        <summary style={{ cursor: 'pointer', padding: '4px 8px', border: '1px solid var(--border-color)', borderRadius: '3px', fontSize: '0.85em', listStyle: 'none' }}>
                            ⚙ Columns
                        </summary>
                        <div style={{ position: 'absolute', right: 0, top: '100%', background: 'var(--card-bg-color)', border: '1px solid var(--border-color)', borderRadius: '3px', padding: '8px', marginTop: '2px', zIndex: 1000, minWidth: '150px' }}>
                            {allColumns.filter(col => col.key !== 'checkbox').map(col => (
                                <label key={col.key} style={{ display: 'block', padding: '4px', cursor: 'pointer', whiteSpace: 'nowrap' }}>
                                    <input
                                        type="checkbox"
                                        checked={visibleColumns[col.key]}
                                        onChange={() => handleToggleColumn(col.key)}
                                        style={{ marginRight: '8px' }}
                                    />
                                    {col.label}
                                </label>
                            ))}
                        </div>
                    </details>
                </div>

                {logs.length > 0 ? (
                    <table className={`resizable-table ${wordWrap ? 'word-wrap' : ''}`}>
                        <thead>
                            <tr>
                                {columns.map((col) => (
                                    <th
                                        key={col.key}
                                        style={{ width: col.width }}
                                        className={col.sortable ? 'sortable' : ''}
                                        onClick={() => col.sortable && handleSort(col.key)}
                                    >
                                        {col.key === 'checkbox' ? (
                                            <input
                                                type="checkbox"
                                                checked={allLogsSelected}
                                                ref={input => {
                                                    if (input) input.indeterminate = someLogsSelected;
                                                }}
                                                onChange={(e) => handleSelectAll(e.target.checked)}
                                                title="Select all"
                                            />
                                        ) : (
                                            <>
                                                {col.label}
                                                {col.sortable && sortBy === col.key && (
                                                    <span className="sort-indicator">
                                                        {sortOrder === 'asc' ? '▲' : '▼'}
                                                    </span>
                                                )}
                                            </>
                                        )}
                                        {!col.noResize && (
                                            <div
                                                className="resize-handle"
                                                onMouseDown={(e) => handleMouseDown(col.key, e)}
                                            />
                                        )}
                                    </th>
                                ))}
                            </tr>
                        </thead>
                        <tbody>
                            {logs.map((log) => (
                                <tr key={log._id}>
                                    {columns.map((col) => (
                                        <td key={col.key} title={col.key !== 'checkbox' ? log[col.key] : ''}>
                                            {col.key === 'checkbox' ? (
                                                <input
                                                    type="checkbox"
                                                    checked={selectedLogs.has(log._id)}
                                                    onChange={(e) => handleSelectLog(log._id, e.target.checked)}
                                                />
                                            ) : col.key === 'Severity' ? (
                                                <span style={{ color: getSeverityColor(log.Severity), fontWeight: 'bold' }}>
                                                    {log.Severity}
                                                </span>
                                            ) : col.key === 'PercentComplete' && log.PercentComplete ? (
                                                <span>{log.PercentComplete}%</span>
                                            ) : (
                                                log[col.key]
                                            )}
                                        </td>
                                    ))}
                                </tr>
                            ))}
                        </tbody>
                    </table>
                ) : (
                    <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-secondary)' }}>
                        {loading ? (
                            <p>Loading logs...</p>
                        ) : lastUpdate ? (
                            <p>No logs found in the selected time range. {filterText ? 'Try adjusting your filters.' : ''}</p>
                        ) : (
                            <p>Loading...</p>
                        )}
                    </div>
                )}
            </div>
        </>
    );
};

window.cardComponents['realtime-events'] = RealtimeEventsCard;
