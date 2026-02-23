const { useState, useEffect } = React;

const AppsManager = () => {
    const [apps, setApps] = useState([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState(null);
    const [nodeGuid, setNodeGuid] = useState('');

    useEffect(() => {
        loadApps();
    }, []);

    const loadApps = async () => {
        try {
            setLoading(true);
            // Fetch apps data from server using PSWebHost's built-in auth handling
            const response = await window.psweb_fetchWithAuthHandling('/api/v1/apps/list');

            if (!response.ok) {
                const error = new Error(`Failed to load apps: ${response.statusText}`);
                error.status = response.status;
                error.statusText = response.statusText;
                throw error;
            }

            const data = await response.json();
            setApps(data.apps || []);
            setNodeGuid(data.nodeGuid || 'Unknown');
            setError(null);
        } catch (err) {
            window.logToServer(`Error loading apps: ${err.message}`, 'AppsManager', 'Error', { error: err.toString() });
            setError(err.message);
        } finally {
            setLoading(false);
        }
    };

    const openApp = (name) => {
        // Navigate to app's main interface
        window.location.href = `/apps/${name}/`;
    };

    const viewDetails = (app) => {
        alert(`App Details:\n\nName: ${app.name}\nVersion: ${app.version}\nPath: ${app.path}`);
    };

    if (loading) {
        return React.createElement('div', { className: 'apps-manager loading' },
            React.createElement('div', { style: { textAlign: 'center', padding: '40px' } },
                React.createElement('div', { className: 'spinner' }),
                React.createElement('p', null, 'Loading apps...')
            )
        );
    }

    if (error) {
        return React.createElement('div', { className: 'apps-manager error' },
            React.createElement('div', { style: { padding: '20px', color: '#ef4444' } },
                React.createElement('h3', null, 'Error Loading Apps'),
                React.createElement('p', null, error)
            )
        );
    }

    return React.createElement('div', { className: 'apps-manager' },
        // Node GUID section
        React.createElement('div', { className: 'node-guid' },
            React.createElement('span', { className: 'node-guid-label' }, 'Node GUID:'),
            React.createElement('code', { className: 'node-guid-value' }, nodeGuid)
        ),

        // Header
        React.createElement('div', { className: 'apps-header' },
            React.createElement('h2', null, 'Installed Apps'),
            React.createElement('span', { className: 'apps-count' }, `${apps.length} app(s)`)
        ),

        // Apps grid
        React.createElement('div', { className: 'apps-grid' },
            apps.length === 0 ?
                React.createElement('div', { className: 'empty-state', style: { gridColumn: '1 / -1' } },
                    React.createElement('div', { className: 'empty-state-icon' }, '📦'),
                    React.createElement('h3', null, 'No Apps Installed'),
                    React.createElement('p', null, 'Install apps by adding them to the /apps directory.')
                )
                :
                apps.map((app, idx) =>
                    React.createElement('div', { className: 'app-card', key: `app-${idx}` },
                        // Card header
                        React.createElement('div', { className: 'app-card-header' },
                            React.createElement('div', null,
                                React.createElement('span', { className: 'app-name' }, app.name),
                                React.createElement('span', { className: 'app-version' }, `v${app.version}`)
                            ),
                            React.createElement('span', {
                                className: `app-status ${app.enabled ? 'enabled' : 'disabled'}`
                            },
                                React.createElement('span', { className: 'app-status-dot' }),
                                app.enabled ? 'Enabled' : 'Disabled'
                            )
                        ),

                        // Card body
                        React.createElement('div', { className: 'app-card-body' },
                            React.createElement('div', { className: 'app-description' },
                                app.description || 'No description available.'
                            ),
                            React.createElement('div', { className: 'app-meta' },
                                React.createElement('div', { className: 'app-meta-item' },
                                    React.createElement('span', { className: 'app-meta-label' }, 'Required Roles'),
                                    React.createElement('span', { className: 'app-meta-value' },
                                        app.requiredRoles || 'None'
                                    )
                                ),
                                React.createElement('div', { className: 'app-meta-item' },
                                    React.createElement('span', { className: 'app-meta-label' }, 'Loaded At'),
                                    React.createElement('span', { className: 'app-meta-value' }, app.loaded)
                                )
                            )
                        ),

                        // Card footer
                        React.createElement('div', { className: 'app-card-footer' },
                            React.createElement('button', {
                                className: 'app-btn primary',
                                onClick: () => openApp(app.name)
                            }, 'Open'),
                            React.createElement('button', {
                                className: 'app-btn',
                                onClick: () => viewDetails(app)
                            }, 'Details')
                        )
                    )
                )
        )
    );
};

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['apps-manager'] = AppsManager;
