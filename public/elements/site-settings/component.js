// Site Settings Component
// Design Intentions:
// - Categorized settings interface (General, Security, Appearance, Performance)
// - Read/Write access to config/settings.json
// - Real-time validation of settings
// - Settings history/rollback capability
// - Import/Export settings
// - Settings search functionality

const SiteSettingsComponent = ({ url, element }) => {
    const [settings, setSettings] = React.useState({});
    const [loading, setLoading] = React.useState(true);
    const [activeCategory, setActiveCategory] = React.useState('general');
    const [searchTerm, setSearchTerm] = React.useState('');

    React.useEffect(() => {
        // TODO: Fetch from /api/v1/settings
        setLoading(false);
        setSettings({
            general: {
                siteName: 'PSWebHost',
                siteDescription: 'PowerShell Web Application Server',
                defaultLanguage: 'en-US',
                timezone: 'UTC'
            },
            security: {
                sessionTimeout: 3600,
                maxLoginAttempts: 5,
                requireHttps: false,
                corsEnabled: true
            },
            appearance: {
                theme: 'dark',
                accentColor: '#0366d6',
                logoUrl: '/public/logo.png'
            },
            performance: {
                cacheEnabled: true,
                cacheDuration: 300,
                compressionEnabled: true,
                maxRequestSize: 10485760
            }
        });
    }, []);

    const categories = [
        { id: 'general', label: '⚙️ General', icon: '⚙️' },
        { id: 'security', label: '🔒 Security', icon: '🔒' },
        { id: 'appearance', label: '🎨 Appearance', icon: '🎨' },
        { id: 'performance', label: '⚡ Performance', icon: '⚡' }
    ];

    if (loading) {
        return React.createElement('div', { className: 'site-settings loading' },
            React.createElement('p', null, 'Loading settings...')
        );
    }

    const renderSettingInput = (key, value, category) => {
        const inputType = typeof value === 'boolean' ? 'checkbox' :
                         typeof value === 'number' ? 'number' : 'text';

        return React.createElement('div', {
            key: key,
            style: {
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                padding: '12px',
                borderBottom: '1px solid var(--border-color)'
            }
        },
            React.createElement('label', { style: { fontWeight: 'bold' } },
                key.replace(/([A-Z])/g, ' $1').replace(/^./, str => str.toUpperCase())
            ),
            React.createElement('input', {
                type: inputType,
                value: inputType === 'checkbox' ? undefined : value,
                checked: inputType === 'checkbox' ? value : undefined,
                disabled: true,
                style: {
                    padding: '6px 10px',
                    border: '1px solid var(--border-color)',
                    borderRadius: '4px',
                    background: 'var(--bg-secondary)',
                    cursor: 'not-allowed',
                    opacity: 0.7
                }
            })
        );
    };

    return React.createElement('div', {
        className: 'site-settings',
        style: { display: 'flex', height: '100%' }
    },
        // Design note
        React.createElement('div', {
            style: {
                position: 'absolute',
                top: '8px',
                right: '8px',
                left: '8px',
                background: 'var(--bg-secondary)',
                padding: '12px',
                borderRadius: '8px',
                border: '2px dashed var(--accent-color)',
                zIndex: 10
            }
        },
            React.createElement('h4', { style: { margin: '0 0 4px 0' } }, '🚧 Implementation Pending'),
            React.createElement('p', { style: { margin: 0, fontSize: '0.9em' } },
                'This component will provide site-wide configuration management.'
            )
        ),

        // Category sidebar
        React.createElement('div', {
            style: {
                width: '180px',
                borderRight: '1px solid var(--border-color)',
                paddingTop: '80px'
            }
        },
            categories.map(cat =>
                React.createElement('div', {
                    key: cat.id,
                    onClick: () => setActiveCategory(cat.id),
                    style: {
                        padding: '12px 16px',
                        cursor: 'pointer',
                        borderLeft: activeCategory === cat.id ? '3px solid var(--accent-color)' : '3px solid transparent',
                        backgroundColor: activeCategory === cat.id ? 'var(--bg-secondary)' : 'transparent'
                    }
                }, cat.label)
            )
        ),

        // Settings content
        React.createElement('div', {
            style: {
                flex: 1,
                padding: '16px',
                paddingTop: '80px',
                overflow: 'auto'
            }
        },
            React.createElement('h3', { style: { marginTop: 0 } },
                categories.find(c => c.id === activeCategory)?.label || 'Settings'
            ),

            settings[activeCategory] && Object.entries(settings[activeCategory]).map(([key, value]) =>
                renderSettingInput(key, value, activeCategory)
            ),

            React.createElement('div', { style: { marginTop: '20px', opacity: 0.5 } },
                React.createElement('button', {
                    disabled: true,
                    style: { marginRight: '8px', padding: '8px 16px', cursor: 'not-allowed' }
                }, 'Save Changes'),
                React.createElement('button', {
                    disabled: true,
                    style: { padding: '8px 16px', cursor: 'not-allowed' }
                }, 'Reset to Defaults')
            )
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['site-settings'] = SiteSettingsComponent;
