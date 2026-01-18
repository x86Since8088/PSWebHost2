// User Management Component
// Manages site users, their roles, and authentication

const UserManagementComponent = ({ url, element }) => {
    const [users, setUsers] = React.useState([]);
    const [isModalOpen, setIsModalOpen] = React.useState(false);
    const [currentUser, setCurrentUser] = React.useState(null);
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);

    React.useEffect(() => {
        fetchUsers();
    }, []);

    const fetchUsers = () => {
        setLoading(true);
        setError(null);
        fetch("/api/v1/users")
            .then(response => {
                if (!response.ok) {
                    throw new Error(`HTTP ${response.status}: ${response.statusText}`);
                }
                return response.json();
            })
            .then(data => {
                setUsers(data);
                setLoading(false);
            })
            .catch(err => {
                setError(err.message);
                setLoading(false);
            });
    };

    const handleOpenModal = (user) => {
        setCurrentUser(user);
        setIsModalOpen(true);
    };

    const handleCloseModal = () => {
        setCurrentUser(null);
        setIsModalOpen(false);
    };

    const handleDeleteUser = (userId) => {
        if (!confirm('Are you sure you want to delete this user?')) {
            return;
        }

        fetch(`/api/v1/users?UserID=${userId}`, { method: 'DELETE' })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Failed to delete user');
                }
                return fetchUsers();
            })
            .catch(err => {
                setError(err.message);
            });
    };

    const handleSaveUser = (userData, file) => {
        const formData = new FormData();
        formData.append("UserName", userData.UserName);
        formData.append("Email", userData.Email);
        formData.append("Phone", userData.Phone);
        if (file) {
            formData.append("profileImage", file);
        }

        const url = userData.UserID ? `/api/v1/users?UserID=${userData.UserID}` : '/api/v1/users';
        const method = userData.UserID ? 'POST' : 'PUT';

        fetch(url, { method: method, body: formData })
            .then(response => {
                if (!response.ok) {
                    throw new Error('Failed to save user');
                }
                return fetchUsers();
            })
            .then(() => {
                handleCloseModal();
            })
            .catch(err => {
                setError(err.message);
            });
    };

    if (loading) {
        return React.createElement('div', {
            className: 'user-management loading',
            style: { padding: '20px', textAlign: 'center' }
        },
            React.createElement('p', null, 'Loading users...')
        );
    }

    if (error) {
        return React.createElement('div', {
            className: 'user-management error',
            style: { padding: '20px' }
        },
            React.createElement('h3', null, 'Error'),
            React.createElement('p', { style: { color: 'var(--error-color)' } }, error),
            React.createElement('button', { onClick: fetchUsers }, 'Retry')
        );
    }

    return React.createElement('div', {
        className: 'user-management',
        style: { padding: '20px', height: '100%', overflow: 'auto' }
    },
        React.createElement('div', {
            style: {
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                marginBottom: '20px'
            }
        },
            React.createElement('h1', { style: { margin: 0 } }, 'User Management'),
            React.createElement('button', {
                onClick: () => handleOpenModal(null),
                style: { padding: '8px 16px' }
            }, '+ Create User')
        ),

        React.createElement('table', {
            style: {
                width: '100%',
                borderCollapse: 'collapse',
                backgroundColor: 'var(--bg-secondary)',
                borderRadius: '8px'
            }
        },
            React.createElement('thead', null,
                React.createElement('tr', null,
                    React.createElement('th', { style: { padding: '12px', textAlign: 'left', borderBottom: '2px solid var(--border-color)' } }, 'Username'),
                    React.createElement('th', { style: { padding: '12px', textAlign: 'left', borderBottom: '2px solid var(--border-color)' } }, 'Email'),
                    React.createElement('th', { style: { padding: '12px', textAlign: 'left', borderBottom: '2px solid var(--border-color)' } }, 'Phone'),
                    React.createElement('th', { style: { padding: '12px', textAlign: 'left', borderBottom: '2px solid var(--border-color)' } }, 'Actions')
                )
            ),
            React.createElement('tbody', null,
                users.length === 0 ?
                    React.createElement('tr', null,
                        React.createElement('td', {
                            colSpan: 4,
                            style: { padding: '20px', textAlign: 'center', opacity: 0.7 }
                        }, 'No users found')
                    ) :
                    users.map(user =>
                        React.createElement('tr', { key: user.UserID },
                            React.createElement('td', { style: { padding: '12px', borderBottom: '1px solid var(--border-color)' } }, user.UserName),
                            React.createElement('td', { style: { padding: '12px', borderBottom: '1px solid var(--border-color)' } }, user.Email),
                            React.createElement('td', { style: { padding: '12px', borderBottom: '1px solid var(--border-color)' } }, user.Phone || '-'),
                            React.createElement('td', { style: { padding: '12px', borderBottom: '1px solid var(--border-color)' } },
                                React.createElement('button', {
                                    onClick: () => handleOpenModal(user),
                                    style: { marginRight: '8px', padding: '4px 8px' }
                                }, 'Edit'),
                                React.createElement('button', {
                                    onClick: () => handleDeleteUser(user.UserID),
                                    style: { padding: '4px 8px', backgroundColor: 'var(--error-color)', color: 'white', border: 'none', borderRadius: '4px' }
                                }, 'Delete')
                            )
                        )
                    )
            )
        ),

        isModalOpen && React.createElement(UserModal, {
            user: currentUser,
            onClose: handleCloseModal,
            onSave: handleSaveUser
        })
    );
};

const UserModal = ({ user, onClose, onSave }) => {
    const [userData, setUserData] = React.useState(user || {});
    const [profileImage, setProfileImage] = React.useState(null);

    const handleChange = (e) => {
        const { name, value } = e.target;
        setUserData(prev => ({ ...prev, [name]: value }));
    };

    const handleFileChange = (e) => {
        setProfileImage(e.target.files[0]);
    };

    const handleSave = () => {
        onSave(userData, profileImage);
    };

    return React.createElement('div', {
        className: 'modal-overlay',
        style: {
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            backgroundColor: 'rgba(0, 0, 0, 0.5)',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            zIndex: 1000
        },
        onClick: onClose
    },
        React.createElement('div', {
            className: 'modal-content',
            style: {
                backgroundColor: 'var(--bg-primary)',
                padding: '24px',
                borderRadius: '8px',
                maxWidth: '500px',
                width: '90%',
                maxHeight: '80vh',
                overflow: 'auto'
            },
            onClick: (e) => e.stopPropagation()
        },
            React.createElement('h2', { style: { marginTop: 0 } }, user ? 'Edit User' : 'Create User'),

            React.createElement('div', { style: { marginBottom: '16px' } },
                React.createElement('label', { style: { display: 'block', marginBottom: '4px' } }, 'Username:'),
                React.createElement('input', {
                    type: 'text',
                    name: 'UserName',
                    value: userData.UserName || '',
                    onChange: handleChange,
                    style: { width: '100%', padding: '8px', borderRadius: '4px', border: '1px solid var(--border-color)' }
                })
            ),

            React.createElement('div', { style: { marginBottom: '16px' } },
                React.createElement('label', { style: { display: 'block', marginBottom: '4px' } }, 'Email:'),
                React.createElement('input', {
                    type: 'email',
                    name: 'Email',
                    value: userData.Email || '',
                    onChange: handleChange,
                    style: { width: '100%', padding: '8px', borderRadius: '4px', border: '1px solid var(--border-color)' }
                })
            ),

            React.createElement('div', { style: { marginBottom: '16px' } },
                React.createElement('label', { style: { display: 'block', marginBottom: '4px' } }, 'Phone:'),
                React.createElement('input', {
                    type: 'text',
                    name: 'Phone',
                    value: userData.Phone || '',
                    onChange: handleChange,
                    style: { width: '100%', padding: '8px', borderRadius: '4px', border: '1px solid var(--border-color)' }
                })
            ),

            React.createElement('div', { style: { marginBottom: '16px' } },
                React.createElement('label', { style: { display: 'block', marginBottom: '4px' } }, 'Profile Picture:'),
                React.createElement('input', {
                    type: 'file',
                    onChange: handleFileChange,
                    style: { width: '100%' }
                })
            ),

            React.createElement('div', { style: { display: 'flex', gap: '8px', justifyContent: 'flex-end' } },
                React.createElement('button', {
                    onClick: onClose,
                    style: { padding: '8px 16px' }
                }, 'Cancel'),
                React.createElement('button', {
                    onClick: handleSave,
                    style: { padding: '8px 16px', backgroundColor: 'var(--accent-color)', color: 'white', border: 'none', borderRadius: '4px' }
                }, 'Save')
            )
        )
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['admin/users-management'] = UserManagementComponent;
