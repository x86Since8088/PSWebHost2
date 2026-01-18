// Role Management Component
// Design Intentions:
// - Display all available roles in the system
// - Show role hierarchy and permissions
// - Allow creating, editing, and deleting roles
// - Manage role-to-permission mappings
// - Show users assigned to each role
// - Audit trail for role changes

const RoleManagementComponent = ({ url, element }) => {
    const [roles, setRoles] = React.useState([]);
    const [loading, setLoading] = React.useState(true);
    const [selectedRole, setSelectedRole] = React.useState(null);

    React.useEffect(() => {
        // TODO: Fetch from /api/v1/admin/roles
        setLoading(false);
        setRoles([
            {
                id: 'admin',
                name: 'Administrator',
                description: 'Full system access',
                userCount: 1,
                permissions: ['all']
            },
            {
                id: 'site_admin',
                name: 'Site Administrator',
                description: 'Manage site settings and users',
                userCount: 2,
                permissions: ['users.manage', 'settings.view', 'settings.edit']
            },
            {
                id: 'system_admin',
                name: 'System Administrator',
                description: 'Manage system configuration',
                userCount: 1,
                permissions: ['system.view', 'system.edit', 'logs.view']
            },
            {
                id: 'authenticated',
                name: 'Authenticated User',
                description: 'Basic authenticated access',
                userCount: 15,
                permissions: ['profile.view', 'profile.edit', 'cards.use']
            },
            {
                id: 'debug',
                name: 'Debug User',
                description: 'Access to debugging tools',
                userCount: 2,
                permissions: ['debug.view', 'debug.vars', 'errors.detailed']
            }
        ]);
    }, []);

    if (loading) {
        return React.createElement('div', { className: 'role-management loading' },
            React.createElement('p', null, 'Loading roles...')
        );
    }

    return React.createElement('div', {
        className: 'role-management',
        style: { display: 'flex', height: '100%' }
    },
        // Roles list
        React.createElement('div', {
            className: 'roles-list',
            style: {
                width: '300px',
                borderRight: '1px solid var(--border-color)',
                overflow: 'auto'
            }
        },
            React.createElement('div', { style: { padding: '12px', borderBottom: '1px solid var(--border-color)' } },
                React.createElement('h3', { style: { margin: 0 } }, 'Roles'),
                React.createElement('button', {
                    disabled: true,
                    style: { marginTop: '8px', padding: '6px 12px', cursor: 'not-allowed', opacity: 0.5 }
                }, '+ Add Role')
            ),
            roles.map(role =>
                React.createElement('div', {
                    key: role.id,
                    className: `role-item ${selectedRole?.id === role.id ? 'selected' : ''}`,
                    onClick: () => setSelectedRole(role),
                    style: {
                        padding: '12px',
                        cursor: 'pointer',
                        borderBottom: '1px solid var(--border-color)',
                        backgroundColor: selectedRole?.id === role.id ? 'var(--accent-color)' : 'transparent'
                    }
                },
                    React.createElement('div', { style: { fontWeight: 'bold' } }, role.name),
                    React.createElement('div', { style: { fontSize: '0.85em', opacity: 0.7 } },
                        `${role.userCount} user${role.userCount !== 1 ? 's' : ''}`
                    )
                )
            )
        ),

        // Role details
        React.createElement('div', {
            className: 'role-details',
            style: { flex: 1, padding: '16px', overflow: 'auto' }
        },
            React.createElement('div', { className: 'design-note', style: {
                background: 'var(--bg-secondary)',
                padding: '16px',
                borderRadius: '8px',
                marginBottom: '16px',
                border: '2px dashed var(--accent-color)'
            }},
                React.createElement('h3', { style: { margin: '0 0 8px 0' } }, '🚧 Implementation Pending'),
                React.createElement('p', { style: { margin: 0 } },
                    'This component will provide role and permission management. ',
                    'Roles control access to features throughout the application.'
                )
            ),

            selectedRole ? React.createElement(React.Fragment, null,
                React.createElement('h2', null, selectedRole.name),
                React.createElement('p', { style: { opacity: 0.7 } }, selectedRole.description),
                React.createElement('h4', null, 'Permissions'),
                React.createElement('ul', null,
                    selectedRole.permissions.map(perm =>
                        React.createElement('li', { key: perm }, perm)
                    )
                )
            ) : React.createElement('p', { style: { opacity: 0.7 } }, 'Select a role to view details')
        )
    );
};

window.cardComponents = window.cardComponents || {};
window.cardComponents['admin/role-management'] = RoleManagementComponent;
