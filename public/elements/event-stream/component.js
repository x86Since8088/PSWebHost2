const { useState, useEffect, useRef } = React;

const EventStreamCard = ({ onError }) => {
    const [events, setEvents] = useState([]);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [lastUpdate, setLastUpdate] = useState(null);
    const [maxEvents, setMaxEvents] = useState(1000);
    const [selectedEvents, setSelectedEvents] = useState(new Set());
    const [filterText, setFilterText] = useState('');
    const [wordWrap, setWordWrap] = useState(false);
    const [jobStatus, setJobStatus] = useState([]);
    const [visibleColumns, setVisibleColumns] = useState({
        checkbox: true,
        Date: true,
        state: true,
        UserID: true,
        Provider: true,
        Data: true
    });
    const [columnWidths, setColumnWidths] = useState({
        checkbox: 40,
        Date: 180,
        state: 100,
        UserID: 150,
        Provider: 120,
        Data: 300
    });
    const resizingColumn = useRef(null);

    const fetchDataRef = React.useRef();

    const fetchData = () => {
        if (fetchDataRef.current) {
            fetchDataRef.current();
        }
    };

    const handleClearEvents = () => {
        // Clear frontend events
        setEvents([]);
        setSelectedEvents(new Set());
        setLastUpdate(new Date());

        // Note: Backend buffer will continue to accumulate from log tail
        // To truly clear backend buffer, would need a separate API endpoint
    };

    const handleSelectAll = (checked) => {
        if (checked) {
            setSelectedEvents(new Set(filteredEvents.map(e => e._id)));
        } else {
            setSelectedEvents(new Set());
        }
    };

    const handleSelectEvent = (eventId, checked) => {
        setSelectedEvents(prev => {
            const newSet = new Set(prev);
            if (checked) {
                newSet.add(eventId);
            } else {
                newSet.delete(eventId);
            }
            return newSet;
        });
    };

    const handleExportCSV = () => {
        const selectedData = events.filter(e => selectedEvents.has(e._id));

        if (selectedData.length === 0) {
            alert('Please select events to export');
            return;
        }

        const headers = ['Date', 'State', 'UserID', 'Provider', 'Data'];
        const csvContent = [
            headers.join(','),
            ...selectedData.map(event => [
                `"${event.Date}"`,
                `"${event.state || ''}"`,
                `"${event.UserID || ''}"`,
                `"${event.Provider || ''}"`,
                `"${(event.Data || '').replace(/"/g, '""')}"`
            ].join(','))
        ].join('\n');

        const blob = new Blob([csvContent], { type: 'text/csv' });
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = `events-${new Date().toISOString().slice(0,19).replace(/:/g,'-')}.csv`;
        a.click();
        URL.revokeObjectURL(url);
    };

    const handleCopyTSV = () => {
        const selectedData = events.filter(e => selectedEvents.has(e._id));

        if (selectedData.length === 0) {
            alert('Please select events to copy');
            return;
        }

        const headers = ['Date', 'State', 'UserID', 'Provider', 'Data'];
        const tsvContent = [
            headers.join('\t'),
            ...selectedData.map(event => [
                event.Date,
                event.state || '',
                event.UserID || '',
                event.Provider || '',
                event.Data || ''
            ].join('\t'))
        ].join('\n');

        navigator.clipboard.writeText(tsvContent).then(() => {
            alert(`Copied ${selectedData.length} events to clipboard as TSV`);
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

    // Backend filtering is now used, so filteredEvents is just events
    const filteredEvents = events;

    useEffect(() => {
        let isMounted = true;

        fetchDataRef.current = () => {
            // Fetch job status
            psweb_fetchWithAuthHandling('/api/v1/ui/elements/job-status')
                .then(res => res.json())
                .then(data => {
                    if (isMounted) {
                        setJobStatus(data || []);
                    }
                })
                .catch(err => {
                    console.error("Failed to fetch job status:", err);
                });

            // Build query string with filter parameters
            const params = new URLSearchParams();
            if (filterText) {
                params.append('filter', filterText);
            }
            params.append('count', maxEvents);

            const url = `/api/v1/ui/elements/event-stream?${params.toString()}`;

            psweb_fetchWithAuthHandling(url)
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch event stream", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.text();
                })
                .then(text => {
                    if (!isMounted) return;

                    const data = text ? JSON.parse(text) : [];
                    const eventsArray = (Array.isArray(data) ? data : [data]).map((event, index) => ({
                        ...event,
                        _id: `event-${Date.now()}-${index}`,
                        Data: typeof event.Data === 'object' ? JSON.stringify(event.Data) : event.Data
                    }));
                    setEvents(eventsArray);
                    setLastUpdate(new Date());
                    // Clear selections that are no longer in the list
                    setSelectedEvents(prev => {
                        const newSet = new Set();
                        const eventIds = new Set(eventsArray.map(e => e._id));
                        prev.forEach(id => {
                            if (eventIds.has(id)) newSet.add(id);
                        });
                        return newSet;
                    });
                })
                .catch(err => {
                    if (isMounted && err.name !== 'Unauthorized') {
                        console.error("EventStreamCard fetch error:", err);
                    }
                });
        };

        fetchData();

        const interval = autoRefresh ? setInterval(fetchData, 5000) : null;

        return () => {
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh, filterText, maxEvents]);

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
        { key: 'checkbox', label: '', width: columnWidths.checkbox, noResize: true },
        { key: 'Date', label: 'Date', width: columnWidths.Date },
        { key: 'state', label: 'State', width: columnWidths.state },
        { key: 'UserID', label: 'User ID', width: columnWidths.UserID },
        { key: 'Provider', label: 'Provider', width: columnWidths.Provider },
        { key: 'Data', label: 'Details', width: columnWidths.Data },
    ];

    const columns = allColumns.filter(col => visibleColumns[col.key]);

    const allFilteredSelected = filteredEvents.length > 0 && filteredEvents.every(e => selectedEvents.has(e._id));
    const someFilteredSelected = filteredEvents.some(e => selectedEvents.has(e._id)) && !allFilteredSelected;

    const styles = `
        .event-stream-container {
            width: 100%;
            overflow: auto;
        }
        .event-stream-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 8px;
            padding-bottom: 5px;
            border-bottom: 1px solid var(--border-color);
        }
        .event-stream-title {
            font-weight: bold;
            font-size: 1.1em;
        }
        .event-stream-controls {
            display: flex;
            gap: 10px;
            align-items: center;
        }
        .event-stream-toolbar {
            display: flex;
            gap: 8px;
            align-items: center;
            margin-bottom: 8px;
            padding: 5px;
            background: var(--title-bar-color);
            border-radius: 3px;
        }
        .event-stream-timestamp {
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
        .refresh-toggle {
            cursor: pointer;
            padding: 3px 8px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            font-size: 0.85em;
        }
        .refresh-toggle:hover {
            background: var(--title-bar-color);
        }
        .filter-input {
            padding: 4px 8px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            background: var(--bg-color);
            color: var(--text-color);
            font-size: 0.9em;
            min-width: 200px;
        }
        .max-events-input {
            width: 80px;
            padding: 4px 8px;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            background: var(--bg-color);
            color: var(--text-color);
            font-size: 0.9em;
        }
        .toolbar-label {
            font-size: 0.85em;
            color: var(--text-secondary);
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
            cursor: pointer;
            user-select: none;
        }
        .resizable-table th:hover {
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
    `;

    return (
        <>
            <style>{styles}</style>
            <div className="event-stream-container">
                <div className="event-stream-header">
                    <div className="event-stream-title">
                        Event Stream ({filteredEvents.length}/{events.length} events{selectedEvents.size > 0 ? `, ${selectedEvents.size} selected` : ''})
                        {jobStatus.length > 0 && (
                            <div style={{ fontSize: '0.75em', marginTop: '4px', color: 'var(--text-secondary)' }}>
                                Jobs: {jobStatus.map(job => (
                                    <span key={job.Id} style={{
                                        marginRight: '12px',
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
                    <div className="event-stream-controls">
                        {lastUpdate && (
                            <div className="event-stream-timestamp">
                                Updated: {lastUpdate.toLocaleTimeString()}
                            </div>
                        )}
                        <button className="refresh-btn" onClick={fetchData}>
                            ↻ Refresh
                        </button>
                        <button className="refresh-btn" onClick={handleClearEvents}>
                            🗑 Clear
                        </button>
                        <div className="refresh-toggle" onClick={() => setAutoRefresh(!autoRefresh)}>
                            {autoRefresh ? '⏸ Pause' : '▶ Resume'}
                        </div>
                    </div>
                </div>
                <div className="event-stream-toolbar">
                    <span className="toolbar-label">Filter:</span>
                    <input
                        type="text"
                        className="filter-input"
                        placeholder="Search events..."
                        value={filterText}
                        onChange={(e) => setFilterText(e.target.value)}
                    />
                    <span className="toolbar-label">Max Events:</span>
                    <input
                        type="number"
                        className="max-events-input"
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
                    <div className="refresh-toggle" onClick={() => setWordWrap(!wordWrap)} title="Toggle word wrap">
                        {wordWrap ? '📝 Wrap: On' : '📝 Wrap: Off'}
                    </div>
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
                {events.length > 0 ? (
                    <table className={`resizable-table ${wordWrap ? 'word-wrap' : ''}`}>
                        <thead>
                            <tr>
                                {columns.map((col) => (
                                    <th key={col.key} style={{ width: col.width }}>
                                        {col.key === 'checkbox' ? (
                                            <input
                                                type="checkbox"
                                                checked={allFilteredSelected}
                                                ref={input => {
                                                    if (input) input.indeterminate = someFilteredSelected;
                                                }}
                                                onChange={(e) => handleSelectAll(e.target.checked)}
                                                title="Select all"
                                            />
                                        ) : (
                                            col.label
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
                            {filteredEvents.map((item) => (
                                <tr key={item._id}>
                                    {columns.map((col) => (
                                        <td key={col.key} title={col.key !== 'checkbox' ? item[col.key] : ''}>
                                            {col.key === 'checkbox' ? (
                                                <input
                                                    type="checkbox"
                                                    checked={selectedEvents.has(item._id)}
                                                    onChange={(e) => handleSelectEvent(item._id, e.target.checked)}
                                                />
                                            ) : (
                                                item[col.key]
                                            )}
                                        </td>
                                    ))}
                                </tr>
                            ))}
                        </tbody>
                    </table>
                ) : (
                    <div style={{ padding: '20px', textAlign: 'center', color: 'var(--text-secondary)' }}>
                        {lastUpdate ? (
                            <p>No events found. {filterText ? 'Try adjusting your filter.' : 'Events will appear here as they are logged.'}</p>
                        ) : (
                            <p>Loading events...</p>
                        )}
                    </div>
                )}
            </div>
        </>
    );
};

window.cardComponents['event-stream'] = EventStreamCard;
