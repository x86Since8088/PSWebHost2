// Database Status Component
// Design Intentions:
// - Display database connection status and health
// - Show table sizes and row counts
// - Display query performance statistics
// - Show database file size and location
// - Provide maintenance actions (vacuum, analyze, backup)
// - Display recent query log
// - Monitor active connections

const DatabaseStatusComponent = ({ url, element }) => {
    const [dbInfo, setDbInfo] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [activeTab, setActiveTab] = React.useState('overview');

    React.useEffect(() => {
        // TODO: Fetch from /api/v1/database/status
        setLoading(false);
        setDbInfo({
            status: 'healthy',
            type: 'SQLite',
            version: '3.42.0',
            fileSize: '2.4 MB',
            filePath: 'PsWebHost_Data/pswebhost.db',
            lastBackup: '2024-01-02 03:00:00',
            tables: [
                { name: 'Users', rows: 25, size: '48 KB' },
                { name: 'Sessions', rows: 142, size: '256 KB' },
                { name: 'Logs', rows: 15420, size: '1.8 MB' },
                { name: 'CardSettings', rows: 87, size: '32 KB' },
                { name: 'Roles', rows: 5, size: '4 KB' }
            ],
            performance: {
                avgQueryTime: '12ms',
                queriesPerSecond: 45,
                cacheHitRate: '94%',
                activeConnections: 1
            }
        });
    }, []);

    const getStatusColor = (status) => {
        switch (status) {
            case 'healthy': return '#4caf50';
            case 'warning': return '#ff9800';
            case 'error': return '#f44336';
            default: return '#9e9e9e';
        }
    };

    if (loading || !dbInfo) {
        return React.createElement('div', { className: 'database-status loading' },
            React.createElement('p', null, 'Loading database status...')
        );
    }

    const tabs = [
        { id: 'overview', label: 'Overview' },
        { id: 'tables', label: 'Tables' },
        { id: 'performance', label: 'Performance' }
    ];

    return React.createElement('div', {
        className: 'database-status',
        style: { padding: '16px', height: '100%', overflow: 'auto' }
    },
        // Design note
        React.createElement('div', { className: 'design-note', style: {
            background: 'var(--bg-secondary)',
            padding: '16px',
            borderRadius: '8px',
            marginBottom: '16px',
            border: '2px dashed var(--accent-color)'
        }},
            React.createElement('h3', { style: { margin: '0 0 8px 0' } }, 'Implementation Pending'),
            React.createElement('p', { style: { margin: 0 } },
                'This component will display database health, statistics, and maintenance tools.'
            )
        ),

        // Header with status
        React.createElement('div', {
            style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' }
        },
            React.createElement('h2', { style: { margin: 0 } }, 'Database Status'),
            React.createElement('span', { style: {
                display: 'inline-flex',
                alignItems: 'center',
                gap: '8px',
                padding: '6px 12px',
                borderRadius: '16px',
                backgroundColor: getStatusColor(dbInfo.status) + '22',
                color: getStatusColor(dbInfo.status)
            }},
                React.createElement('span', { style: {
                    width: '10px', height: '10px', borderRadius: '50%',
                    backgroundColor: getStatusColor(dbInfo.status)
                }}),
                dbInfo.status.charAt(0).toUpperCase() + dbInfo.status.slice(1)
            )
        ),

        // Quick info cards
        React.createElement('div', {
            style: { display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: '12px', marginBottom: '20px' }
        },
            [
                { label: 'Database Type', value: dbInfo.type },
                { label: 'Version', value: dbInfo.version },
                { label: 'File Size', value: dbInfo.fileSize },
                { label: 'Queries/sec', value: dbInfo.performance.queriesPerSecond }
            ].map(item =>
                React.createElement('div', {
                    key: item.label,
                    style: {
                        padding: '12px',
                        background: 'var(--bg-secondary)',
                        borderRadius: '8px',
                        textAlign: 'center'
                    }
                },
                    React.createElement('div', { style: { fontSize: '0.85em', opacity: 0.7 } }, item.label),
                    React.createElement('div', { style: { fontSize: '1.2em', fontWeight: 'bold' } }, item.value)
                )
            )
        ),

        // Tabs
        React.createElement('div', { style: { display: 'flex', borderBottom: '1px solid var(--border-color)', marginBottom: '16px' } },
            tabs.map(tab =>
                React.createElement('button', {
                    key: tab.id,
                    onClick: () => setActiveTab(tab.id),
                    style: {
                        padding: '10px 16px',
                        border: 'none',
                        background: 'none',
                        borderBottom: activeTab === tab.id ? '2px solid var(--accent-color)' : '2px solid transparent',
                        color: activeTab === tab.id ? 'var(--accent-color)' : 'var(--text-color)',
                        cursor: 'pointer'
                    }
                }, tab.label)
            )
        ),

        // Tab content - Overview
        activeTab === 'overview' && React.createElement('div', null,
            React.createElement('p', null, React.createElement('strong', null, 'File Path: '), dbInfo.filePath),
            React.createElement('p', null, React.createElement('strong', null, 'Last Backup: '), dbInfo.lastBackup),
            React.createElement('div', { style: { marginTop: '16px' } },
                React.createElement('button', { disabled: true, style: { marginRight: '8px', padding: '8px 16px', cursor: 'not-allowed', opacity: 0.5 } }, 'Backup Now'),
                React.createElement('button', { disabled: true, style: { marginRight: '8px', padding: '8px 16px', cursor: 'not-allowed', opacity: 0.5 } }, 'Vacuum'),
                React.createElement('button', { disabled: true, style: { padding: '8px 16px', cursor: 'not-allowed', opacity: 0.5 } }, 'Analyze')
            )
        ),

        // Tab content - Tables
        activeTab === 'tables' && React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
            React.createElement('thead', null,
                React.createElement('tr', { style: { borderBottom: '2px solid var(--border-color)' } },
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Table'),
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'Rows'),
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'Size')
                )
            ),
            React.createElement('tbody', null,
                dbInfo.tables.map(table =>
                    React.createElement('tr', { key: table.name, style: { borderBottom: '1px solid var(--border-color)' } },
                        React.createElement('td', { style: { padding: '10px', fontWeight: 'bold' } }, table.name),
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, table.rows.toLocaleString()),
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, table.size)
                    )
                )
            )
        ),

        // Tab content - Performance
        activeTab === 'performance' && React.createElement('div', null,
            Object.entries(dbInfo.performance).map(([key, value]) =>
                React.createElement('div', {
                    key: key,
                    style: { display: 'flex', justifyContent: 'space-between', padding: '10px', borderBottom: '1px solid var(--border-color)' }
                },
                    React.createElement('span', null, key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase())),
                    React.createElement('strong', null, value)
                )
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['database-status'] = DatabaseStatusComponent;
