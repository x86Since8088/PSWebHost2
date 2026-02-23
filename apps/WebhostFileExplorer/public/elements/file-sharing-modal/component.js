/**
 * FileSharingModal Component
 *
 * Comprehensive modal for managing storage paths and permissions.
 * Features:
 * - Register new storage paths
 * - Auto-create Owner, Read, Write groups
 * - Assign permissions to Roles, Groups, or Users
 * - List and manage existing storage paths
 * - Update permissions for registered paths
 */

const FileSharingModal = ({ visible, initialPath, onClose, onPathRegistered }) => {
    const React = window.React;
    const { useState, useEffect, useCallback, useRef } = React;

    // State management
    const [activeTab, setActiveTab] = useState('register'); // 'register' or 'manage'
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);

    // Registration form state
    const [logicalPath, setLogicalPath] = useState(initialPath || '');
    const [physicalPath, setPhysicalPath] = useState('');
    const [name, setName] = useState('');
    const [description, setDescription] = useState('');
    const [autoCreateGroups, setAutoCreateGroups] = useState(true);

    // Permission state - each permission type has array of principals
    const [ownerPermissions, setOwnerPermissions] = useState([]);
    const [readPermissions, setReadPermissions] = useState([]);
    const [writePermissions, setWritePermissions] = useState([]);

    // Manage tab state
    const [storagePaths, setStoragePaths] = useState([]);
    const [selectedPath, setSelectedPath] = useState(null);

    // Principal selector state
    const [principalType, setPrincipalType] = useState('role'); // 'role', 'group', 'user'
    const [principalId, setPrincipalId] = useState('');
    const [availableRoles, setAvailableRoles] = useState(['admin', 'site_admin', 'system_admin', 'authenticated']);
    const [availableGroups, setAvailableGroups] = useState([]);
    const [newGroupName, setNewGroupName] = useState('');

    // Fetch available groups on mount
    useEffect(() => {
        if (visible) {
            fetchAvailableGroups();
            if (activeTab === 'manage') {
                fetchStoragePaths();
            }
        }
    }, [visible, activeTab]);

    const fetchAvailableGroups = async () => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/groups',
                { method: 'GET' }
            );

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();
            if (data.success && data.groups) {
                setAvailableGroups(data.groups);
            } else {
                console.warn('Groups endpoint returned unexpected format:', data);
                setAvailableGroups([]);
            }
        } catch (err) {
            console.error('Failed to fetch groups:', err);
            setAvailableGroups([]);
        }
    };

    const fetchStoragePaths = async () => {
        setLoading(true);
        setError(null);

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/storage/paths',
                { method: 'GET' }
            );

            if (!response.ok) {
                throw new Error(`Failed to fetch storage paths: ${response.status}`);
            }

            const result = await response.json();
            if (result.status === 'success') {
                setStoragePaths(result.data.paths || []);
            } else {
                throw new Error(result.message || 'Failed to fetch storage paths');
            }
        } catch (err) {
            setError(err.message);
            window.logToServer?.(`FileSharingModal: Error fetching storage paths: ${err.message}`, 'Error');
        } finally {
            setLoading(false);
        }
    };

    const addPrincipal = useCallback((permissionType) => {
        if (!principalId.trim()) {
            window.showToast?.('Please enter a principal ID', 'warning');
            return;
        }

        const principal = {
            principalType,
            principalId: principalId.trim(),
            name: principalId.trim()
        };

        switch (permissionType) {
            case 'owner':
                setOwnerPermissions(prev => [...prev, principal]);
                break;
            case 'read':
                setReadPermissions(prev => [...prev, principal]);
                break;
            case 'write':
                setWritePermissions(prev => [...prev, principal]);
                break;
        }

        setPrincipalId('');
    }, [principalType, principalId]);

    const removePrincipal = useCallback((permissionType, index) => {
        switch (permissionType) {
            case 'owner':
                setOwnerPermissions(prev => prev.filter((_, i) => i !== index));
                break;
            case 'read':
                setReadPermissions(prev => prev.filter((_, i) => i !== index));
                break;
            case 'write':
                setWritePermissions(prev => prev.filter((_, i) => i !== index));
                break;
        }
    }, []);

    const handleRegisterPath = async () => {
        // Validation
        if (!logicalPath.trim()) {
            setError('Logical path is required');
            return;
        }
        if (!physicalPath.trim()) {
            setError('Physical path is required');
            return;
        }
        if (!name.trim()) {
            setError('Name is required');
            return;
        }

        setLoading(true);
        setError(null);

        try {
            // Build permissions array
            const permissions = [];

            if (ownerPermissions.length > 0) {
                permissions.push({
                    type: 'owner',
                    principals: ownerPermissions
                });
            }

            if (readPermissions.length > 0) {
                permissions.push({
                    type: 'read',
                    principals: readPermissions
                });
            }

            if (writePermissions.length > 0) {
                permissions.push({
                    type: 'write',
                    principals: writePermissions
                });
            }

            const requestBody = {
                logicalPath: logicalPath.trim(),
                physicalPath: physicalPath.trim(),
                name: name.trim(),
                description: description.trim(),
                autoCreateGroups,
                permissions: permissions.length > 0 ? permissions : null
            };

            window.logToServer?.(`FileSharingModal: Registering storage path`, 'Info', { data: requestBody });

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/storage/paths',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(requestBody)
                }
            );

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.message || `HTTP ${response.status}`);
            }

            const result = await response.json();

            if (result.status === 'success') {
                window.showToast?.('Storage path registered successfully', 'success');
                window.logToServer?.(`FileSharingModal: Path registered successfully`, 'Info', { data: result.data });

                // Call callback
                if (onPathRegistered) {
                    onPathRegistered(result.data);
                }

                // Reset form
                setLogicalPath('');
                setPhysicalPath('');
                setName('');
                setDescription('');
                setOwnerPermissions([]);
                setReadPermissions([]);
                setWritePermissions([]);
                setAutoCreateGroups(true);

                // Switch to manage tab
                setActiveTab('manage');
                fetchStoragePaths();
            } else {
                throw new Error(result.message || 'Registration failed');
            }
        } catch (err) {
            setError(err.message);
            window.showToast?.(err.message, 'error');
            window.logToServer?.(`FileSharingModal: Error registering path: ${err.message}`, 'Error');
        } finally {
            setLoading(false);
        }
    };

    const handleUpdatePermissions = async (pathID) => {
        if (!selectedPath) return;

        setLoading(true);
        setError(null);

        try {
            const permissions = [];

            if (ownerPermissions.length > 0) {
                permissions.push({
                    type: 'owner',
                    principals: ownerPermissions
                });
            }

            if (readPermissions.length > 0) {
                permissions.push({
                    type: 'read',
                    principals: readPermissions
                });
            }

            if (writePermissions.length > 0) {
                permissions.push({
                    type: 'write',
                    principals: writePermissions
                });
            }

            const requestBody = {
                pathID,
                permissions
            };

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/storage/paths',
                {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(requestBody)
                }
            );

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.message || `HTTP ${response.status}`);
            }

            const result = await response.json();

            if (result.status === 'success') {
                window.showToast?.('Permissions updated successfully', 'success');
                fetchStoragePaths();
                setSelectedPath(null);
            } else {
                throw new Error(result.message || 'Update failed');
            }
        } catch (err) {
            setError(err.message);
            window.showToast?.(err.message, 'error');
        } finally {
            setLoading(false);
        }
    };

    const handleDeletePath = async (pathID) => {
        if (!confirm('Are you sure you want to deactivate this storage path?')) {
            return;
        }

        setLoading(true);
        setError(null);

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/WebhostFileExplorer/api/v1/storage/paths?pathID=${encodeURIComponent(pathID)}`,
                { method: 'DELETE' }
            );

            if (!response.ok) {
                const errorData = await response.json().catch(() => ({}));
                throw new Error(errorData.message || `HTTP ${response.status}`);
            }

            const result = await response.json();

            if (result.status === 'success') {
                window.showToast?.('Storage path deactivated', 'success');
                fetchStoragePaths();
                if (selectedPath?.pathID === pathID) {
                    setSelectedPath(null);
                }
            } else {
                throw new Error(result.message || 'Delete failed');
            }
        } catch (err) {
            setError(err.message);
            window.showToast?.(err.message, 'error');
        } finally {
            setLoading(false);
        }
    };

    const selectPathForEdit = (path) => {
        setSelectedPath(path);

        // Populate permission fields from selected path
        const owners = path.permissions?.owner || [];
        const readers = path.permissions?.read || [];
        const writers = path.permissions?.write || [];

        setOwnerPermissions(owners.map(p => ({
            principalType: p.principalType,
            principalId: p.principalId,
            name: p.name || p.principalId
        })));

        setReadPermissions(readers.map(p => ({
            principalType: p.principalType,
            principalId: p.principalId,
            name: p.name || p.principalId
        })));

        setWritePermissions(writers.map(p => ({
            principalType: p.principalType,
            principalId: p.principalId,
            name: p.name || p.principalId
        })));
    };

    const renderPrincipalList = (permissions, permissionType) => {
        if (permissions.length === 0) {
            return <div className="no-principals">No principals assigned</div>;
        }

        return (
            <div className="principal-list">
                {permissions.map((principal, index) => (
                    <div key={index} className="principal-item">
                        <span className={`principal-badge ${principal.principalType}`}>
                            {principal.principalType === 'role' && '🔑'}
                            {principal.principalType === 'group' && '👥'}
                            {principal.principalType === 'user' && '👤'}
                            {principal.name}
                        </span>
                        <button
                            className="remove-button"
                            onClick={() => removePrincipal(permissionType, index)}
                            title="Remove"
                        >
                            ×
                        </button>
                    </div>
                ))}
            </div>
        );
    };

    const renderPrincipalSelector = (permissionType, label) => {
        return (
            <div className="permission-section">
                <h4>{label}</h4>
                {renderPrincipalList(
                    permissionType === 'owner' ? ownerPermissions :
                    permissionType === 'read' ? readPermissions :
                    writePermissions,
                    permissionType
                )}

                <div className="add-principal-form">
                    <select
                        value={principalType}
                        onChange={(e) => setPrincipalType(e.target.value)}
                        className="principal-type-select"
                    >
                        <option value="role">Role</option>
                        <option value="group">Group</option>
                        <option value="user">User</option>
                    </select>

                    {principalType === 'role' ? (
                        <select
                            value={principalId}
                            onChange={(e) => setPrincipalId(e.target.value)}
                            className="principal-id-input"
                        >
                            <option value="">Select role...</option>
                            {availableRoles.map(role => (
                                <option key={role} value={role}>{role}</option>
                            ))}
                        </select>
                    ) : principalType === 'group' ? (
                        <input
                            type="text"
                            value={principalId}
                            onChange={(e) => setPrincipalId(e.target.value)}
                            placeholder="Group ID or name..."
                            className="principal-id-input"
                        />
                    ) : (
                        <input
                            type="text"
                            value={principalId}
                            onChange={(e) => setPrincipalId(e.target.value)}
                            placeholder="User ID or email..."
                            className="principal-id-input"
                        />
                    )}

                    <button
                        onClick={() => addPrincipal(permissionType)}
                        className="add-button"
                        disabled={!principalId.trim()}
                    >
                        Add
                    </button>
                </div>
            </div>
        );
    };

    if (!visible) return null;

    return (
        <div className="dialog-overlay file-sharing-overlay" onClick={onClose}>
            <div className="dialog-box file-sharing-modal" onClick={(e) => e.stopPropagation()}>
                <div className="modal-header">
                    <h2>Storage Path Management</h2>
                    <button className="close-button" onClick={onClose}>×</button>
                </div>

                <div className="modal-tabs">
                    <button
                        className={`tab-button ${activeTab === 'register' ? 'active' : ''}`}
                        onClick={() => setActiveTab('register')}
                    >
                        Register New Path
                    </button>
                    <button
                        className={`tab-button ${activeTab === 'manage' ? 'active' : ''}`}
                        onClick={() => { setActiveTab('manage'); fetchStoragePaths(); }}
                    >
                        Manage Paths
                    </button>
                </div>

                {error && (
                    <div className="error-message">
                        <span>⚠️ {error}</span>
                        <button onClick={() => setError(null)}>×</button>
                    </div>
                )}

                {activeTab === 'register' && (
                    <div className="tab-content register-tab">
                        <div className="form-section">
                            <h3>Path Information</h3>

                            <label>
                                <span className="label-text">Logical Path *</span>
                                <input
                                    type="text"
                                    value={logicalPath}
                                    onChange={(e) => setLogicalPath(e.target.value)}
                                    placeholder="User:me or Bucket:abc-123 or System:C"
                                    disabled={!!initialPath}
                                />
                                <span className="hint">The logical path as used in FileExplorer</span>
                            </label>

                            <label>
                                <span className="label-text">Physical Path *</span>
                                <input
                                    type="text"
                                    value={physicalPath}
                                    onChange={(e) => setPhysicalPath(e.target.value)}
                                    placeholder="C:\Users\example\Documents"
                                />
                                <span className="hint">The actual filesystem path</span>
                            </label>

                            <label>
                                <span className="label-text">Name *</span>
                                <input
                                    type="text"
                                    value={name}
                                    onChange={(e) => setName(e.target.value)}
                                    placeholder="My Documents"
                                />
                                <span className="hint">Display name for this storage path</span>
                            </label>

                            <label>
                                <span className="label-text">Description</span>
                                <textarea
                                    value={description}
                                    onChange={(e) => setDescription(e.target.value)}
                                    placeholder="Optional description"
                                    rows={3}
                                />
                            </label>

                            <label className="checkbox-label">
                                <input
                                    type="checkbox"
                                    checked={autoCreateGroups}
                                    onChange={(e) => setAutoCreateGroups(e.target.checked)}
                                />
                                <span>Auto-create Owner, Read, and Write groups</span>
                            </label>

                            {autoCreateGroups && (
                                <div className="info-message">
                                    ℹ️ Will create groups: <strong>{name.replace(/[^a-zA-Z0-9_-]/g, '_')}_owners</strong>,{' '}
                                    <strong>{name.replace(/[^a-zA-Z0-9_-]/g, '_')}_readers</strong>,{' '}
                                    <strong>{name.replace(/[^a-zA-Z0-9_-]/g, '_')}_writers</strong>
                                </div>
                            )}
                        </div>

                        {!autoCreateGroups && (
                            <div className="form-section">
                                <h3>Permissions</h3>
                                <p className="section-hint">Assign roles, groups, or users to each permission level</p>

                                {renderPrincipalSelector('owner', 'Owner Permissions')}
                                {renderPrincipalSelector('read', 'Read Permissions')}
                                {renderPrincipalSelector('write', 'Write Permissions')}
                            </div>
                        )}

                        <div className="modal-actions">
                            <button onClick={onClose} className="cancel-button" disabled={loading}>
                                Cancel
                            </button>
                            <button onClick={handleRegisterPath} className="primary-button" disabled={loading}>
                                {loading ? 'Registering...' : 'Register Storage Path'}
                            </button>
                        </div>
                    </div>
                )}

                {activeTab === 'manage' && (
                    <div className="tab-content manage-tab">
                        {loading && <div className="loading-indicator">Loading storage paths...</div>}

                        {!loading && storagePaths.length === 0 && (
                            <div className="empty-state">
                                <p>No storage paths registered yet.</p>
                                <button onClick={() => setActiveTab('register')} className="primary-button">
                                    Register Your First Path
                                </button>
                            </div>
                        )}

                        {!loading && storagePaths.length > 0 && (
                            <div className="storage-paths-list">
                                {storagePaths.map(path => (
                                    <div key={path.pathID} className={`storage-path-item ${selectedPath?.pathID === path.pathID ? 'selected' : ''}`}>
                                        <div className="path-header">
                                            <div className="path-info">
                                                <h4>{path.name}</h4>
                                                <div className="path-details">
                                                    <span className="logical-path">{path.logicalPath}</span>
                                                    <span className="separator">→</span>
                                                    <span className="physical-path">{path.physicalPath}</span>
                                                </div>
                                                {path.description && <p className="path-description">{path.description}</p>}
                                                <div className="path-meta">
                                                    <span>Your permissions: {path.userPermissions?.join(', ') || 'none'}</span>
                                                </div>
                                            </div>
                                            <div className="path-actions">
                                                <button
                                                    onClick={() => selectPathForEdit(path)}
                                                    className="edit-button"
                                                    title="Edit permissions"
                                                >
                                                    ✏️
                                                </button>
                                                <button
                                                    onClick={() => handleDeletePath(path.pathID)}
                                                    className="delete-button"
                                                    title="Deactivate"
                                                >
                                                    🗑️
                                                </button>
                                            </div>
                                        </div>

                                        {selectedPath?.pathID === path.pathID && (
                                            <div className="path-edit-form">
                                                <h4>Edit Permissions</h4>
                                                {renderPrincipalSelector('owner', 'Owner Permissions')}
                                                {renderPrincipalSelector('read', 'Read Permissions')}
                                                {renderPrincipalSelector('write', 'Write Permissions')}

                                                <div className="edit-actions">
                                                    <button
                                                        onClick={() => setSelectedPath(null)}
                                                        className="cancel-button"
                                                    >
                                                        Cancel
                                                    </button>
                                                    <button
                                                        onClick={() => handleUpdatePermissions(path.pathID)}
                                                        className="primary-button"
                                                        disabled={loading}
                                                    >
                                                        {loading ? 'Updating...' : 'Update Permissions'}
                                                    </button>
                                                </div>
                                            </div>
                                        )}
                                    </div>
                                ))}
                            </div>
                        )}
                    </div>
                )}
            </div>
        </div>
    );
};

// Register component globally
if (typeof window !== 'undefined') {
    window.FileSharingModal = FileSharingModal;
}
