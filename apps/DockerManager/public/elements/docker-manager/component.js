// Docker Manager Component
// Design Intentions:
// - Display Docker containers and their status
// - Show Docker images
// - Container management: start, stop, restart, remove
// - View container logs
// - Display resource usage per container
// - Network and volume management
// - Docker Compose support

const DockerManagerComponent = ({ url, element }) => {
    const [containers, setContainers] = React.useState([]);
    const [images, setImages] = React.useState([]);
    const [loading, setLoading] = React.useState(true);
    const [activeTab, setActiveTab] = React.useState('containers');

    React.useEffect(() => {
        // TODO: Fetch from Docker API via /api/v1/docker/...
        setLoading(false);
        setContainers([
            { id: 'abc123', name: 'web-app', image: 'nginx:latest', status: 'running', ports: '80:80', created: '2 days ago' },
            { id: 'def456', name: 'database', image: 'postgres:15', status: 'running', ports: '5432:5432', created: '1 week ago' },
            { id: 'ghi789', name: 'cache', image: 'redis:7', status: 'exited', ports: '6379:6379', created: '3 days ago' },
            { id: 'jkl012', name: 'worker', image: 'app-worker:v2', status: 'running', ports: '-', created: '1 day ago' }
        ]);
        setImages([
            { id: 'img001', repository: 'nginx', tag: 'latest', size: '142 MB', created: '1 week ago' },
            { id: 'img002', repository: 'postgres', tag: '15', size: '379 MB', created: '2 weeks ago' },
            { id: 'img003', repository: 'redis', tag: '7', size: '130 MB', created: '1 month ago' },
            { id: 'img004', repository: 'app-worker', tag: 'v2', size: '256 MB', created: '2 days ago' }
        ]);
    }, []);

    const getStatusColor = (status) => {
        if (status.includes('running')) return '#4caf50';
        if (status.includes('exited')) return '#f44336';
        return '#ff9800';
    };

    if (loading) {
        return React.createElement('div', { className: 'docker-manager loading' },
            React.createElement('p', null, 'Loading Docker info...')
        );
    }

    const tabs = [
        { id: 'containers', label: '📦 Containers', count: containers.length },
        { id: 'images', label: '🖼️ Images', count: images.length }
    ];

    return React.createElement('div', {
        className: 'docker-manager',
        style: { display: 'flex', flexDirection: 'column', height: '100%' }
    },
        // Design note
        React.createElement('div', { className: 'design-note', style: {
            background: 'var(--bg-secondary)',
            padding: '16px',
            borderRadius: '8px',
            margin: '16px',
            border: '2px dashed var(--accent-color)'
        }},
            React.createElement('h3', { style: { margin: '0 0 8px 0' } }, '🚧 Implementation Pending'),
            React.createElement('p', { style: { margin: 0 } },
                'This component will provide Docker container and image management. ',
                'Requires Docker daemon to be running and accessible.'
            )
        ),

        // Header
        React.createElement('div', { style: { padding: '0 16px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' } },
            React.createElement('h2', { style: { margin: '0 0 12px 0' } }, '🐳 Docker Manager'),
            React.createElement('span', { style: { opacity: 0.7 } }, 'Docker Engine v24.0.0')
        ),

        // Tabs
        React.createElement('div', { style: { display: 'flex', borderBottom: '1px solid var(--border-color)', padding: '0 16px' } },
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
                        cursor: 'pointer',
                        fontWeight: activeTab === tab.id ? 'bold' : 'normal'
                    }
                }, `${tab.label} (${tab.count})`)
            )
        ),

        // Content
        React.createElement('div', { style: { flex: 1, padding: '16px', overflow: 'auto' } },
            activeTab === 'containers' && React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
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
                                React.createElement('div', { style: { fontSize: '0.8em', opacity: 0.6 } }, container.id)
                            ),
                            React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace', fontSize: '0.9em' } }, container.image),
                            React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                                React.createElement('span', { style: {
                                    display: 'inline-flex',
                                    alignItems: 'center',
                                    gap: '6px'
                                }},
                                    React.createElement('span', { style: {
                                        width: '8px', height: '8px', borderRadius: '50%',
                                        backgroundColor: getStatusColor(container.status)
                                    }}),
                                    container.status
                                )
                            ),
                            React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace', fontSize: '0.9em' } }, container.ports),
                            React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                                React.createElement('button', { disabled: true, style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 } },
                                    container.status === 'running' ? '⏹️' : '▶️'
                                ),
                                React.createElement('button', { disabled: true, style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 } }, '🔄'),
                                React.createElement('button', { disabled: true, style: { padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 } }, '📋')
                            )
                        )
                    )
                )
            ),

            activeTab === 'images' && React.createElement('table', { style: { width: '100%', borderCollapse: 'collapse' } },
                React.createElement('thead', null,
                    React.createElement('tr', { style: { borderBottom: '2px solid var(--border-color)' } },
                        React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Repository'),
                        React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Tag'),
                        React.createElement('th', { style: { textAlign: 'right', padding: '10px' } }, 'Size'),
                        React.createElement('th', { style: { textAlign: 'left', padding: '10px' } }, 'Created'),
                        React.createElement('th', { style: { textAlign: 'center', padding: '10px' } }, 'Actions')
                    )
                ),
                React.createElement('tbody', null,
                    images.map(image =>
                        React.createElement('tr', { key: image.id, style: { borderBottom: '1px solid var(--border-color)' } },
                            React.createElement('td', { style: { padding: '10px', fontWeight: 'bold' } }, image.repository),
                            React.createElement('td', { style: { padding: '10px', fontFamily: 'monospace' } }, image.tag),
                            React.createElement('td', { style: { textAlign: 'right', padding: '10px' } }, image.size),
                            React.createElement('td', { style: { padding: '10px', opacity: 0.7 } }, image.created),
                            React.createElement('td', { style: { textAlign: 'center', padding: '10px' } },
                                React.createElement('button', { disabled: true, style: { marginRight: '4px', padding: '4px 8px', cursor: 'not-allowed', opacity: 0.5 } }, '🗑️')
                            )
                        )
                    )
                )
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['docker-manager'] = DockerManagerComponent;
