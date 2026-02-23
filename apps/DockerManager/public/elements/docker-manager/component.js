// Docker Manager Component
// Provides Docker container management functionality

const DockerManagerComponent = ({ url, element }) => {
    const [containers, setContainers] = React.useState([]);
    const [dockerInfo, setDockerInfo] = React.useState(null);
    const [dockerError, setDockerError] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [logsModal, setLogsModal] = React.useState(null);
    const [activeTab, setActiveTab] = React.useState('containers');

    React.useEffect(() => {
        fetchDockerInfo();
        fetchContainers();
    }, []);

    const fetchDockerInfo = async () => {
        try {
            const response = await window.psweb_fetchWithAuthHandling('/apps/dockermanager/api/v1/docker/info');
            if (!response.ok) {
                if (response.status === 503) {
                    const data = await response.json();
                    setDockerError(data.error || 'Docker daemon not available');
                } else {
                    setDockerError(`HTTP ${response.status}: ${response.statusText}`);
                }
                setLoading(false);
                return;
            }
            const data = await response.json();
            setDockerInfo(data);
        } catch (error) {
            setDockerError(`Failed to connect: ${error.message}`);
            setLoading(false);
        }
    };

    const fetchContainers = async () => {
        try {
            const response = await window.psweb_fetchWithAuthHandling('/apps/dockermanager/api/v1/docker/containers');
            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }
            const data = await response.json();
            setContainers(data.containers || []);
            setLoading(false);
        } catch (error) {
            console.error('Failed to load containers:', error);
            setLoading(false);
        }
    };

    const handleStartContainer = async (containerId) => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/dockermanager/api/v1/docker/containers/${containerId}/start`,
                { method: 'POST' }
            );
            const result = await response.json();
            if (result.success) {
                await fetchContainers();
            } else {
                alert(`Failed to start container: ${result.error || result.message}`);
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    };

    const handleStopContainer = async (containerId) => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/dockermanager/api/v1/docker/containers/${containerId}/stop`,
                { method: 'POST' }
            );
            const result = await response.json();
            if (result.success) {
                await fetchContainers();
            } else {
                alert(`Failed to stop container: ${result.error || result.message}`);
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    };

    const handleRestartContainer = async (containerId) => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/dockermanager/api/v1/docker/containers/${containerId}/restart`,
                { method: 'POST' }
            );
            const result = await response.json();
            if (result.success) {
                await fetchContainers();
            } else {
                alert(`Failed to restart container: ${result.error || result.message}`);
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    };

    const handleDeleteContainer = async (containerId, containerName) => {
        if (!confirm(`Delete container "${containerName}"? This cannot be undone.`)) return;

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/dockermanager/api/v1/docker/containers/${containerId}?force=false`,
                { method: 'DELETE' }
            );
            const result = await response.json();

            if (result.success) {
                await fetchContainers();
            } else {
                // If container is running, ask if force delete
                if (response.status === 409 || result.error?.includes('running')) {
                    if (confirm(`Container is running. Force delete?`)) {
                        const forceResponse = await window.psweb_fetchWithAuthHandling(
                            `/apps/dockermanager/api/v1/docker/containers/${containerId}?force=true`,
                            { method: 'DELETE' }
                        );
                        const forceResult = await forceResponse.json();
                        if (forceResult.success) {
                            await fetchContainers();
                        } else {
                            alert(`Failed to delete: ${forceResult.error || forceResult.message}`);
                        }
                    }
                } else {
                    alert(`Failed to delete: ${result.error || result.message}`);
                }
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    };

    const handleViewLogs = async (containerId) => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/dockermanager/api/v1/docker/containers/${containerId}/logs?tail=100`
            );
            const result = await response.json();
            if (result.success) {
                setLogsModal({ containerId, lines: result.lines });
            } else {
                alert(`Failed to get logs: ${result.error || result.message}`);
            }
        } catch (error) {
            alert(`Error: ${error.message}`);
        }
    };

    const getStatusColor = (state) => {
        if (state === 'running') return '#4caf50';
        if (state === 'exited') return '#f44336';
        if (state === 'paused') return '#ff9800';
        return '#9e9e9e';
    };

    // Docker not available - show error banner
    if (dockerError) {
        return React.createElement('div', { className: 'docker-manager' },
            React.createElement('div', { style: {
                background: '#ffebee', padding: '16px', margin: '16px',
                borderRadius: '8px', border: '1px solid #f44336'
            }},
                React.createElement('h3', { style: { color: '#d32f2f', margin: '0 0 8px 0' } },
                    '⚠️ Docker Not Available'),
                React.createElement('p', { style: { margin: '0 0 8px 0' } }, dockerError),
                React.createElement('p', { style: { margin: 0, fontSize: '0.9em' } },
                    'Ensure Docker Desktop is running or Docker daemon is accessible.')
            )
        );
    }

    if (loading) {
        return React.createElement('div', { className: 'docker-manager loading' },
            React.createElement('p', null, 'Loading Docker info...')
        );
    }

    return React.createElement('div', {
        className: 'docker-manager',
        style: { display: 'flex', flexDirection: 'column', height: '100%' }
    },
        // Header
        React.createElement('div', { style: {
            padding: '0 16px',
            display: 'flex',
            justifyContent: 'space-between',
            alignItems: 'center',
            marginBottom: '12px'
        }},
            React.createElement('h2', { style: { margin: 0 } }, '🐳 Docker Manager'),
            React.createElement('span', { style: { opacity: 0.7, fontSize: '0.9em' } },
                dockerInfo ? `Docker v${dockerInfo.serverVersion || 'Unknown'}` : 'Loading...'
            )
        ),

        // Stats bar
        dockerInfo && React.createElement('div', { style: {
            display: 'flex',
            gap: '16px',
            padding: '12px 16px',
            background: 'var(--bg-secondary)',
            margin: '0 16px 16px 16px',
            borderRadius: '8px'
        }},
            React.createElement('div', null,
                React.createElement('strong', null, dockerInfo.containers || 0), ' Total'
            ),
            React.createElement('div', { style: { color: '#4caf50' } },
                React.createElement('strong', null, dockerInfo.containersRunning || 0), ' Running'
            ),
            React.createElement('div', { style: { color: '#f44336' } },
                React.createElement('strong', null, dockerInfo.containersStopped || 0), ' Stopped'
            ),
            dockerInfo.images && React.createElement('div', { style: { marginLeft: 'auto' } },
                React.createElement('strong', null, dockerInfo.images), ' Images'
            )
        ),

        // Container table
        React.createElement('div', { style: { flex: 1, overflow: 'auto', padding: '0 16px' } },
            containers.length === 0 ?
                React.createElement('div', { style: {
                    textAlign: 'center',
                    padding: '40px',
                    color: 'var(--text-secondary)'
                }},
                    React.createElement('p', null, 'No containers found'),
                    React.createElement('p', { style: { fontSize: '0.9em' } },
                        'Start a container using docker run or docker-compose')
                )
            :
                React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
                    React.createElement('thead', null,
                        React.createElement('tr', { style: { borderBottom: '2px solid var(--border-color)' } },
                            React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Container'),
                            React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Image'),
                            React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Status'),
                            React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Ports'),
                            React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Actions')
                        )
                    ),
                    React.createElement('tbody', null,
                        containers.map(container =>
                            React.createElement('tr', { key: container.id, style: { borderBottom: '1px solid var(--border-color)' } },
                                React.createElement('td', { style: { padding: '10px' } },
                                    React.createElement('div', { style: { fontWeight: 'bold' } }, container.name),
                                    React.createElement('div', {
                                        style: { fontSize: '0.75em', opacity: 0.6, fontFamily: 'monospace' }
                                    }, container.id.substring(0, 12))
                                ),
                                React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace', fontSize: '0.9em' } },
                                    container.image
                                ),
                                React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                                    React.createElement('span', { style: {
                                        display: 'inline-flex',
                                        alignItems: 'center',
                                        gap: '6px'
                                    }},
                                        React.createElement('span', { style: {
                                            width: '8px', height: '8px', borderRadius: '50%',
                                            backgroundColor: getStatusColor(container.state)
                                        }}),
                                        container.status
                                    )
                                ),
                                React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace', fontSize: '0.85em' } },
                                    container.ports || '-'
                                ),
                                React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                                    // Start/Stop button
                                    React.createElement('button', {
                                        onClick: () => container.state === 'running'
                                            ? handleStopContainer(container.id)
                                            : handleStartContainer(container.id),
                                        style: { marginRight: '4px', padding: '4px 8px', cursor: 'pointer' },
                                        title: container.state === 'running' ? 'Stop' : 'Start'
                                    }, container.state === 'running' ? '⏹️' : '▶️'),

                                    // Restart button
                                    React.createElement('button', {
                                        onClick: () => handleRestartContainer(container.id),
                                        style: { marginRight: '4px', padding: '4px 8px', cursor: 'pointer' },
                                        title: 'Restart'
                                    }, '🔄'),

                                    // Logs button
                                    React.createElement('button', {
                                        onClick: () => handleViewLogs(container.id),
                                        style: { marginRight: '4px', padding: '4px 8px', cursor: 'pointer' },
                                        title: 'View Logs'
                                    }, '📋'),

                                    // Delete button
                                    React.createElement('button', {
                                        onClick: () => handleDeleteContainer(container.id, container.name),
                                        style: { padding: '4px 8px', cursor: 'pointer', color: '#f44336' },
                                        title: 'Delete'
                                    }, '🗑️')
                                )
                            )
                        )
                    )
                )
        ),

        // Logs modal
        logsModal && React.createElement(LogsModal, {
            containerId: logsModal.containerId,
            logs: logsModal.lines,
            onClose: () => setLogsModal(null)
        })
    );
};

// Logs Modal Component
function LogsModal({ containerId, logs, onClose }) {
    return React.createElement('div', {
        style: {
            position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
            background: 'rgba(0,0,0,0.5)', display: 'flex',
            alignItems: 'center', justifyContent: 'center', zIndex: 1000
        },
        onClick: onClose
    },
        React.createElement('div', {
            style: {
                background: 'var(--bg-primary)', padding: '20px',
                borderRadius: '8px', maxWidth: '80%', maxHeight: '80%',
                overflow: 'auto', minWidth: '600px'
            },
            onClick: (e) => e.stopPropagation()
        },
            React.createElement('div', { style: { display: 'flex', justifyContent: 'space-between', marginBottom: '10px' } },
                React.createElement('h3', { style: { margin: 0 } }, `Logs: ${containerId.substring(0, 12)}`),
                React.createElement('button', {
                    onClick: onClose,
                    style: { padding: '4px 12px', cursor: 'pointer' }
                }, '✕')
            ),
            React.createElement('pre', {
                style: {
                    background: '#000', color: '#0f0', padding: '10px',
                    fontFamily: 'monospace', fontSize: '12px', overflow: 'auto',
                    maxHeight: '500px', margin: 0, borderRadius: '4px'
                }
            }, logs && logs.length > 0 ? logs.join('\n') : 'No logs available')
        )
    );
}

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['docker-manager'] = DockerManagerComponent;
