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
    const [actionMessage, setActionMessage] = React.useState(null);
    const [actionInProgress, setActionInProgress] = React.useState(null);

    const loadServices = React.useCallback(() => {
        setLoading(true);
        fetch('/apps/windowsadmin/api/v1/system/services')
            .then(response => {
                if (!response.ok) throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                return response.json();
            })
            .then(data => {
                setPlatform(data.platform.toLowerCase());
                // Map backend data to component format
                const mappedServices = data.services.map(svc => ({
                    name: svc.displayName || svc.name,
                    serviceName: svc.name,
                    status: svc.status.toLowerCase(),
                    startType: svc.startType,
                    canStop: svc.canStop,
                    canPause: svc.canPause,
                    pid: null, // Not provided by backend yet
                    memory: '-',
                    cpu: '-'
                }));
                setServices(mappedServices);
                setLoading(false);
            })
            .catch(error => {
                console.error('Failed to load services:', error);
                setActionMessage({ type: 'error', text: `Failed to load services: ${error.message}` });
                setLoading(false);
            });
    }, []);

    React.useEffect(() => {
        loadServices();
    }, [loadServices]);

    const handleServiceAction = (serviceName, action) => {
        setActionInProgress(`${serviceName}-${action}`);
        setActionMessage(null);

        const actionText = action === 'start' ? 'start' : (action === 'stop' ? 'stop' : 'restart');

        fetch(`/apps/windowsadmin/api/v1/system/services/${serviceName}/${action}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    setActionMessage({ type: 'success', text: data.message });
                    // Refresh services list after a short delay
                    setTimeout(() => loadServices(), 1000);
                } else {
                    setActionMessage({ type: 'error', text: data.error || data.message });
                }
                setActionInProgress(null);
            })
            .catch(error => {
                console.error(`Failed to ${actionText} service:`, error);
                setActionMessage({ type: 'error', text: `Failed to ${actionText} service: ${error.message}` });
                setActionInProgress(null);
            });
    };

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
        // Action message banner
        actionMessage && React.createElement('div', {
            style: {
                background: actionMessage.type === 'success' ? 'rgba(76, 175, 80, 0.2)' : 'rgba(244, 67, 54, 0.2)',
                color: actionMessage.type === 'success' ? '#4caf50' : '#f44336',
                padding: '12px 16px',
                borderRadius: '8px',
                marginBottom: '16px',
                border: `1px solid ${actionMessage.type === 'success' ? '#4caf50' : '#f44336'}`,
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center'
            }
        },
            React.createElement('span', null, actionMessage.text),
            React.createElement('button', {
                onClick: () => setActionMessage(null),
                style: {
                    background: 'transparent',
                    border: 'none',
                    color: 'inherit',
                    cursor: 'pointer',
                    fontSize: '1.2em',
                    padding: '0 4px'
                }
            }, '×')
        ),

        // Header with platform indicator
        React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '16px' } },
            React.createElement('h2', { style: { margin: 0 } }, 'System Services'),
            React.createElement('div', { style: { display: 'flex', gap: '12px', alignItems: 'center' } },
                React.createElement('button', {
                    onClick: loadServices,
                    style: {
                        padding: '6px 12px',
                        borderRadius: '4px',
                        border: '1px solid var(--border-color)',
                        background: 'var(--bg-secondary)',
                        cursor: 'pointer'
                    }
                }, '🔄 Refresh'),
                React.createElement('span', { style: {
                    padding: '4px 12px',
                    borderRadius: '12px',
                    background: 'var(--accent-color)',
                    fontSize: '0.85em'
                }}, platform === 'windows' ? '🪟 Windows' : '🐧 Linux')
            )
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
                    React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'Start Type'),
                    React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Actions')
                )
            ),
            React.createElement('tbody', null,
                filteredServices.map(service => {
                    const isActionInProgress = actionInProgress && actionInProgress.startsWith(service.serviceName);

                    return React.createElement('tr', {
                        key: service.serviceName,
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
                        React.createElement('td', { style: { textAlign: 'right', padding: '10px', fontSize: '0.9em' } },
                            service.startType || '-'
                        ),
                        React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                            React.createElement('div', { style: { display: 'flex', gap: '4px', justifyContent: 'center' } },
                                // Start/Stop button
                                React.createElement('button', {
                                    onClick: () => handleServiceAction(service.serviceName, service.status === 'running' ? 'stop' : 'start'),
                                    disabled: isActionInProgress || (service.status === 'running' && !service.canStop),
                                    title: service.status === 'running' ?
                                        (service.canStop ? 'Stop Service' : 'Cannot stop this service') :
                                        'Start Service',
                                    style: {
                                        padding: '4px 8px',
                                        cursor: isActionInProgress || (service.status === 'running' && !service.canStop) ? 'not-allowed' : 'pointer',
                                        opacity: isActionInProgress || (service.status === 'running' && !service.canStop) ? 0.5 : 1,
                                        border: '1px solid var(--border-color)',
                                        borderRadius: '4px',
                                        background: 'var(--bg-secondary)'
                                    }
                                }, service.status === 'running' ? '⏹️' : '▶️'),
                                // Restart button
                                React.createElement('button', {
                                    onClick: () => handleServiceAction(service.serviceName, 'restart'),
                                    disabled: isActionInProgress || (service.status === 'running' && !service.canStop),
                                    title: service.canStop ? 'Restart Service' : 'Cannot restart this service',
                                    style: {
                                        padding: '4px 8px',
                                        cursor: isActionInProgress || (service.status === 'running' && !service.canStop) ? 'not-allowed' : 'pointer',
                                        opacity: isActionInProgress || (service.status === 'running' && !service.canStop) ? 0.5 : 1,
                                        border: '1px solid var(--border-color)',
                                        borderRadius: '4px',
                                        background: 'var(--bg-secondary)'
                                    }
                                }, '🔄')
                            )
                        )
                    );
                })
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['service-control'] = ServiceControlComponent;
