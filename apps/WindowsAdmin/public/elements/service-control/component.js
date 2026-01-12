// Service Control Component
// Design Intentions:
// - Display status of system services (Windows Services / Linux systemd)
// - Allow starting, stopping, and restarting services
// - Show service health metrics and resource usage
// - Display service dependencies
// - Cross-platform support (Windows/Linux detection)
// - Filter and search services

const ServiceControlComponent = ({ url, element }) => {
    const [services, setServices] = React.useState([]);
    const [loading, setLoading] = React.useState(true);
    const [filter, setFilter] = React.useState('');
    const [platform, setPlatform] = React.useState('windows');

    React.useEffect(() => {
        // TODO: Fetch from /api/v1/system/services
        // Detect platform and fetch appropriate services
        setLoading(false);
        setServices([
            { name: 'PSWebHost', status: 'running', pid: 1234, memory: '125 MB', cpu: '2.1%' },
            { name: 'SQLite', status: 'running', pid: 5678, memory: '45 MB', cpu: '0.3%' },
            { name: 'Scheduler', status: 'stopped', pid: null, memory: '-', cpu: '-' },
            { name: 'BackupService', status: 'running', pid: 9012, memory: '32 MB', cpu: '0.1%' },
            { name: 'LogCollector', status: 'running', pid: 3456, memory: '18 MB', cpu: '0.5%' }
        ]);
    }, []);

    const getStatusColor = (status) => {
        switch (status) {
            case 'running': return '#4caf50';
            case 'stopped': return '#f44336';
            case 'starting': return '#ff9800';
            default: return '#9e9e9e';
        }
    };

    const filteredServices = services.filter(s =>
        s.name.toLowerCase().includes(filter.toLowerCase())
    );

    if (loading) {
        return React.createElement('div', { className: 'service-control loading' },
            React.createElement('p', null, 'Loading services...')
        );
    }

    return React.createElement('div', {
        className: 'service-control',
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
            React.createElement('h3', { style: { margin: '0 0 8px 0' } }, '🚧 Implementation Pending'),
            React.createElement('p', { style: { margin: 0 } },
                'This component will provide service management capabilities. ',
                'Start, stop, and monitor system services from this interface.'
            )
        ),

        // Header with platform indicator
        React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' } },
            React.createElement('h2', { style: { margin: 0 } }, 'System Services'),
            React.createElement('span', { style: {
                padding: '4px 12px',
                borderRadius: '12px',
                background: 'var(--accent-color)',
                fontSize: '0.85em'
            }}, platform === 'windows' ? '🪟 Windows' : '🐧 Linux')
        ),

        // Search filter
        React.createElement('input', {
            type: 'text',
            placeholder: 'Filter services...',
            value: filter,
            onChange: (e) => setFilter(e.target.value),
            style: {
                width: '100%',
                padding: '8px 12px',
                marginBottom: '16px',
                border: '1px solid var(--border-color)',
                borderRadius: '4px',
                background: 'var(--bg-secondary)'
            }
        }),

        // Services table
        React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
            React.createElement('thead', null,
                React.createElement('tr', { style: { borderBottom: '2px solid var(--border-color)' } },
                    React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Service'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Status'),
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'PID'),
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'Memory'),
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'CPU'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Actions')
                )
            ),
            React.createElement('tbody', null,
                filteredServices.map(service =>
                    React.createElement('tr', {
                        key: service.name,
                        style: { borderBottom: '1px solid var(--border-color)' }
                    },
                        React.createElement('td', { style: { padding: '10px', fontWeight: 'bold' } }, service.name),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('span', { style: {
                                display: 'inline-flex',
                                alignItems: 'center',
                                gap: '6px'
                            }},
                                React.createElement('span', { style: {
                                    width: '8px', height: '8px', borderRadius: '50%',
                                    backgroundColor: getStatusColor(service.status)
                                }}),
                                service.status
                            )
                        ),
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, service.pid || '-'),
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, service.memory),
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, service.cpu),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('button', {
                                disabled: true,
                                style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 }
                            }, service.status === 'running' ? '⏹️' : '▶️'),
                            React.createElement('button', {
                                disabled: true,
                                style: { padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 }
                            }, '🔄')
                        )
                    )
                )
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['service-control'] = ServiceControlComponent;
