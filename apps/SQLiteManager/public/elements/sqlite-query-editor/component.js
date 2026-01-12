// SQLite Query Editor Component
// Provides SQL query execution interface with results display

const SQLiteQueryEditorComponent = ({ url, element }) => {
    const [query, setQuery] = React.useState('SELECT name FROM sqlite_master WHERE type=\'table\' ORDER BY name;');
    const [results, setResults] = React.useState(null);
    const [loading, setLoading] = React.useState(false);
    const [error, setError] = React.useState(null);
    const [dbInfo, setDbInfo] = React.useState(null);

    // Load database info on mount
    React.useEffect(() => {
        fetch('/apps/sqlitemanager/api/v1/status')
            .then(response => response.json())
            .then(data => setDbInfo(data))
            .catch(err => console.error('Failed to load DB info:', err));
    }, []);

    const sampleQueries = [
        { label: 'List all tables', query: 'SELECT name FROM sqlite_master WHERE type=\'table\' ORDER BY name;' },
        { label: 'Show table schema', query: 'SELECT sql FROM sqlite_master WHERE type=\'table\' AND name=\'sessions\';' },
        { label: 'Count rows in sessions', query: 'SELECT COUNT(*) as count FROM sessions;' },
        { label: 'Recent sessions', query: 'SELECT * FROM sessions ORDER BY created_at DESC LIMIT 10;' },
        { label: 'All indexes', query: 'SELECT name, tbl_name FROM sqlite_master WHERE type=\'index\';' }
    ];

    const executeQuery = () => {
        if (!query.trim()) {
            setError('Please enter a SQL query');
            return;
        }

        setLoading(true);
        setError(null);
        setResults(null);

        fetch('/apps/sqlitemanager/api/v1/sqlite/query', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ query: query })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    setResults(data);
                } else {
                    setError(data.error || 'Query execution failed');
                }
                setLoading(false);
            })
            .catch(err => {
                setError(`Network error: ${err.message}`);
                setLoading(false);
            });
    };

    const loadSampleQuery = (sampleQuery) => {
        setQuery(sampleQuery);
        setResults(null);
        setError(null);
    };

    const handleKeyDown = (e) => {
        // Execute on Ctrl+Enter or Cmd+Enter
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            executeQuery();
        }
    };

    return React.createElement('div', {
        className: 'sqlite-query-editor',
        style: { padding: '16px', height: '100%', overflow: 'auto', display: 'flex', flexDirection: 'column' }
    },
        // Header
        React.createElement('div', { style: { marginBottom: '16px' } },
            React.createElement('h2', { style: { margin: '0 0 8px 0' } }, '🗃️ SQLite Query Editor'),
            React.createElement('p', { style: { margin: 0, fontSize: '0.9em', color: 'var(--text-secondary)' } },
                'Execute SQL queries against the PSWebHost database',
                dbInfo && ` • ${dbInfo.name || 'pswebhost.db'}`
            )
        ),

        // Sample queries dropdown
        React.createElement('div', { style: { marginBottom: '12px' } },
            React.createElement('label', { style: { fontSize: '0.9em', marginRight: '8px', color: 'var(--text-secondary)' } },
                'Sample Queries:'
            ),
            React.createElement('select', {
                onChange: (e) => {
                    if (e.target.value) {
                        loadSampleQuery(e.target.value);
                        e.target.value = '';
                    }
                },
                style: {
                    padding: '6px 12px',
                    borderRadius: '4px',
                    border: '1px solid var(--border-color)',
                    background: 'var(--bg-secondary)',
                    cursor: 'pointer'
                }
            },
                React.createElement('option', { value: '' }, '-- Select a sample query --'),
                sampleQueries.map((sample, idx) =>
                    React.createElement('option', { key: idx, value: sample.query }, sample.label)
                )
            )
        ),

        // Query editor
        React.createElement('div', { style: { marginBottom: '12px', flex: '0 0 auto' } },
            React.createElement('textarea', {
                value: query,
                onChange: (e) => setQuery(e.target.value),
                onKeyDown: handleKeyDown,
                placeholder: 'Enter SQL query...',
                style: {
                    width: '100%',
                    minHeight: '120px',
                    padding: '12px',
                    fontFamily: 'monospace',
                    fontSize: '0.95em',
                    border: '1px solid var(--border-color)',
                    borderRadius: '4px',
                    background: 'var(--bg-secondary)',
                    resize: 'vertical',
                    color: 'var(--text-primary)'
                }
            }),
            React.createElement('div', { style: { marginTop: '8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
                React.createElement('button', {
                    onClick: executeQuery,
                    disabled: loading,
                    style: {
                        padding: '8px 20px',
                        borderRadius: '4px',
                        border: 'none',
                        background: loading ? 'var(--accent-color-muted)' : 'var(--accent-color)',
                        color: 'white',
                        cursor: loading ? 'not-allowed' : 'pointer',
                        fontWeight: '500'
                    }
                }, loading ? '⏳ Executing...' : '▶️ Execute Query'),
                React.createElement('span', { style: { fontSize: '0.85em', color: 'var(--text-secondary)' } },
                    'Tip: Press Ctrl+Enter to execute'
                )
            )
        ),

        // Error message
        error && React.createElement('div', {
            style: {
                background: 'rgba(244, 67, 54, 0.1)',
                border: '1px solid #f44336',
                color: '#f44336',
                padding: '12px 16px',
                borderRadius: '8px',
                marginBottom: '16px',
                fontFamily: 'monospace',
                fontSize: '0.9em'
            }
        }, `❌ Error: ${error}`),

        // Results
        results && React.createElement('div', {
            style: {
                flex: '1 1 auto',
                overflow: 'auto',
                background: 'var(--bg-secondary)',
                borderRadius: '8px',
                padding: '16px'
            }
        },
            // Results header
            React.createElement('div', {
                style: {
                    display: 'flex',
                    justifyContent: 'space-between',
                    alignItems: 'center',
                    marginBottom: '12px',
                    paddingBottom: '12px',
                    borderBottom: '2px solid var(--border-color)'
                }
            },
                React.createElement('div', null,
                    React.createElement('span', { style: { fontWeight: 'bold', fontSize: '1.1em' } },
                        results.queryType === 'SELECT' ? `📊 ${results.rowCount} row${results.rowCount !== 1 ? 's' : ''}` : '✅ Query executed successfully'
                    ),
                    React.createElement('span', { style: { marginLeft: '16px', color: 'var(--text-secondary)', fontSize: '0.9em' } },
                        `⏱️ ${results.executionTime}ms`
                    )
                )
            ),

            // Results table (for SELECT queries)
            results.queryType === 'SELECT' && results.rows.length > 0 && React.createElement('div', {
                style: { overflow: 'auto' }
            },
                React.createElement('table', {
                    style: {
                        width: '100%',
                        borderCollapse: 'collapse',
                        fontSize: '0.9em'
                    }
                },
                    React.createElement('thead', null,
                        React.createElement('tr', { style: { background: 'var(--bg-primary)', borderBottom: '2px solid var(--border-color)' } },
                            results.columns.map(col =>
                                React.createElement('th', {
                                    key: col,
                                    style: {
                                        padding: '10px 12px',
                                        textAlign: 'left',
                                        fontWeight: '600',
                                        position: 'sticky',
                                        top: 0,
                                        background: 'var(--bg-primary)',
                                        zIndex: 1
                                    }
                                }, col)
                            )
                        )
                    ),
                    React.createElement('tbody', null,
                        results.rows.map((row, rowIdx) =>
                            React.createElement('tr', {
                                key: rowIdx,
                                style: {
                                    borderBottom: '1px solid var(--border-color)',
                                    background: rowIdx % 2 === 0 ? 'transparent' : 'var(--bg-tertiary)'
                                }
                            },
                                results.columns.map(col =>
                                    React.createElement('td', {
                                        key: col,
                                        style: {
                                            padding: '8px 12px',
                                            fontFamily: 'monospace',
                                            fontSize: '0.9em'
                                        }
                                    }, row[col] !== null && row[col] !== undefined ? String(row[col]) : '(null)')
                                )
                            )
                        )
                    )
                )
            ),

            // No results message
            results.queryType === 'SELECT' && results.rows.length === 0 && React.createElement('p', {
                style: { color: 'var(--text-secondary)', fontStyle: 'italic', margin: 0 }
            }, 'No rows returned')
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['sqlite-query-editor'] = SQLiteQueryEditorComponent;
