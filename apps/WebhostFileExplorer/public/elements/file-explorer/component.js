/**
 * File Explorer Component - Four-Pane Layout with Incremental Tree Loading
 *
 * Architecture:
 * - Incremental tree loading via POST /api/v1/tree
 * - LRU caching for file details (10 folders) and VersionInfo (100 items)
 * - Four-pane layout: Tree Nav | File List + VersionInfo | Preview
 * - Path format: local|localhost|bucket
 */

const { useState, useEffect, useRef, useMemo, useCallback } = React;

// ============================================================================
// LRU CACHE IMPLEMENTATIONS
// ============================================================================

/**
 * LRU Cache for File Details
 * Caches folder contents with max 10 folders
 */
class FileDetailsCacheLRU {
    constructor(maxFolders = 10) {
        this.cache = new Map();
        this.order = [];
        this.maxFolders = maxFolders;
    }

    get(folderPath) {
        if (this.cache.has(folderPath)) {
            // Move to end (most recently used)
            this.order = this.order.filter(p => p !== folderPath);
            this.order.push(folderPath);
            return this.cache.get(folderPath);
        }
        return null;
    }

    set(folderPath, data) {
        // Add to cache
        this.cache.set(folderPath, {
            data: data,
            timestamp: Date.now()
        });

        // Update LRU order
        this.order = this.order.filter(p => p !== folderPath);
        this.order.push(folderPath);

        // Evict if over limit
        if (this.order.length > this.maxFolders) {
            const evictPath = this.order.shift();
            this.cache.delete(evictPath);
            // Note: Don't log cache evictions to server (too verbose)
            console.log(`[FileDetailsCache] Evicted folder: ${evictPath}`);
        }
    }

    clear() {
        this.cache.clear();
        this.order = [];
    }
}

/**
 * LRU Cache for VersionInfo
 * Caches file version info with max 100 items
 */
class VersionInfoCacheLRU {
    constructor(maxItems = 100) {
        this.cache = new Map();
        this.order = [];
        this.maxItems = maxItems;
    }

    get(filePath) {
        if (this.cache.has(filePath)) {
            // Move to end (most recently used)
            this.order = this.order.filter(p => p !== filePath);
            this.order.push(filePath);
            return this.cache.get(filePath);
        }
        return null;
    }

    set(filePath, data) {
        // Add to cache
        this.cache.set(filePath, {
            data: data,
            timestamp: Date.now()
        });

        // Update LRU order
        this.order = this.order.filter(p => p !== filePath);
        this.order.push(filePath);

        // Evict if over limit
        if (this.order.length > this.maxItems) {
            const evictPath = this.order.shift();
            this.cache.delete(evictPath);
            // Note: Don't log cache evictions to server (too verbose)
            console.log(`[VersionInfoCache] Evicted file: ${evictPath}`);
        }
    }

    clear() {
        this.cache.clear();
        this.order = [];
    }
}

// Initialize global caches
const fileDetailsCache = new FileDetailsCacheLRU(10);
const versionInfoCache = new VersionInfoCacheLRU(100);

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Extract display name from node or path
 * Prefers node.name if available, otherwise derives from path
 */
function getDisplayName(nodeOrPath) {
    // If it's a node object with a name, use it directly
    if (nodeOrPath && typeof nodeOrPath === 'object' && nodeOrPath.name) {
        return nodeOrPath.name;
    }

    // Otherwise treat as a path string
    const path = typeof nodeOrPath === 'string' ? nodeOrPath : (nodeOrPath?.path || '');
    if (!path) return '';

    // Format: local|localhost|LogicalPath
    const parts = path.split('|');
    if (parts.length === 3) {
        const logicalPath = parts[2];

        // Extract last segment for nested paths (folders within a root)
        const segments = logicalPath.split('/');
        if (segments.length > 1) {
            return segments[segments.length - 1] || logicalPath;
        }

        // For root paths, return the logical path as-is
        return logicalPath;
    }

    return path;
}

/**
 * Format file size
 */
function formatSize(bytes) {
    if (bytes === null || bytes === undefined) return '-';
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i];
}

/**
 * Format date
 */
function formatDate(isoString) {
    if (!isoString) return '-';
    const date = new Date(isoString);
    return date.toLocaleString();
}

// ============================================================================
// SUB-COMPONENTS
// ============================================================================

/**
 * MenuBar Component
 */
const MenuBar = ({ onAction }) => {
    const [activeMenu, setActiveMenu] = useState(null);

    const menus = {
        File: [
            { label: 'New Folder', action: 'newFolder', icon: '📁', shortcut: 'Ctrl+Shift+N' },
            { label: 'Upload Files', action: 'uploadFiles', icon: '📤', shortcut: 'Ctrl+U' },
            { label: 'Download Selected', action: 'downloadSelected', icon: '📥', shortcut: 'Ctrl+D' },
            { label: 'Refresh', action: 'refresh', icon: '🔄', shortcut: 'F5' }
        ],
        Edit: [
            { label: 'Rename', action: 'rename', icon: '✏️', shortcut: 'F2' },
            { label: 'Delete', action: 'delete', icon: '🗑️', shortcut: 'Delete' }
        ],
        View: [
            { label: 'Toggle Preview', action: 'togglePreview', icon: '👁️', shortcut: 'Ctrl+P' }
        ],
        Help: [
            { label: 'About', action: 'about', icon: 'ℹ️' }
        ]
    };

    return (
        <div className="menu-bar">
            {Object.keys(menus).map(menuName => (
                <div key={menuName} className="menu-item">
                    <button
                        className="menu-button"
                        onClick={() => setActiveMenu(activeMenu === menuName ? null : menuName)}
                    >
                        {menuName}
                    </button>
                    {activeMenu === menuName && (
                        <div className="menu-dropdown">
                            {menus[menuName].map(item => (
                                <div
                                    key={item.action}
                                    className="menu-dropdown-item"
                                    onClick={() => {
                                        onAction(item.action);
                                        setActiveMenu(null);
                                    }}
                                >
                                    <span className="menu-icon">{item.icon}</span>
                                    <span className="menu-label">{item.label}</span>
                                    {item.shortcut && (
                                        <span className="menu-shortcut">{item.shortcut}</span>
                                    )}
                                </div>
                            ))}
                        </div>
                    )}
                </div>
            ))}
        </div>
    );
};

/**
 * IconToolbar Component
 */
const IconToolbar = ({ onAction, previewVisible, enabledUploadMethods, toggleUploadMethod, usePipelining, onTogglePipelining, chunkSizeMB, updateChunkSize, showSettings, onToggleSettings }) => {
    const tools = [
        { action: 'newFolder', icon: '📁', title: 'New Folder (Ctrl+Shift+N)' },
        { action: 'uploadFiles', icon: '📤', title: 'Upload Files (Ctrl+U)' },
        { action: 'downloadSelected', icon: '📥', title: 'Download Selected (Ctrl+D)' },
        { action: 'delete', icon: '🗑️', title: 'Delete (Delete)' },
        { action: 'rename', icon: '✏️', title: 'Rename (F2)' },
        { action: 'refresh', icon: '🔄', title: 'Refresh (F5)' },
        { action: 'togglePreview', icon: previewVisible ? '👁️‍🗨️' : '👁️', title: 'Toggle Preview (Ctrl+P)' }
    ];

    return (
        <div className="icon-toolbar">
            {tools.map((tool, idx) => (
                <button
                    key={idx}
                    className="icon-toolbar-button"
                    onClick={() => onAction(tool.action)}
                    title={tool.title}
                >
                    {tool.icon}
                </button>
            ))}

            {/* Settings button with dropdown */}
            <div className="toolbar-settings-container">
                <button
                    className="icon-toolbar-button settings-button"
                    onClick={onToggleSettings}
                    title="Settings"
                >
                    ⚙️
                </button>

                {showSettings && (
                    <div className="settings-dropdown">
                        <div className="settings-section">
                            <h4>Upload Methods</h4>
                            <p className="settings-description">
                                Deselect to disable a method. System will auto-select the best available method.
                            </p>

                            <label className="settings-checkbox">
                                <input
                                    type="checkbox"
                                    checked={enabledUploadMethods.streaming}
                                    onChange={() => toggleUploadMethod('streaming')}
                                />
                                <span>Streaming Upload</span>
                                <span className="method-info">Best for files &gt;10MB (no resume)</span>
                            </label>

                            <label className="settings-checkbox">
                                <input
                                    type="checkbox"
                                    checked={enabledUploadMethods.websocket}
                                    onChange={() => toggleUploadMethod('websocket')}
                                />
                                <span>WebSocket Upload</span>
                                <span className="method-info">Resumable, supports pipelining</span>
                            </label>

                            {enabledUploadMethods.websocket && (
                                <>
                                    <label className="settings-checkbox settings-sub-checkbox">
                                        <input
                                            type="checkbox"
                                            checked={usePipelining}
                                            onChange={onTogglePipelining}
                                        />
                                        <span>Enable pipelining (experimental)</span>
                                    </label>
                                    <div className="settings-help">
                                        {usePipelining ? (
                                            <span className="settings-status status-enabled">✓ 5 chunks in parallel</span>
                                        ) : (
                                            <span className="settings-status status-info">Serial upload (more stable)</span>
                                        )}
                                    </div>
                                </>
                            )}

                            <label className="settings-checkbox">
                                <input
                                    type="checkbox"
                                    checked={enabledUploadMethods.putChunks}
                                    onChange={() => toggleUploadMethod('putChunks')}
                                />
                                <span>PUT Chunks Upload</span>
                                <span className="method-info">Resumable, HTTP fallback</span>
                            </label>

                            {!enabledUploadMethods.streaming && !enabledUploadMethods.websocket && !enabledUploadMethods.putChunks && (
                                <div className="settings-warning">
                                    ⚠️ At least one upload method must be enabled
                                </div>
                            )}

                            <label className="settings-label">
                                <span>Chunk Size: {chunkSizeMB}MB</span>
                                <input
                                    type="range"
                                    min="5"
                                    max="100"
                                    step="5"
                                    value={chunkSizeMB}
                                    onChange={(e) => updateChunkSize(e.target.value)}
                                    className="settings-slider"
                                />
                            </label>
                            <div className="settings-help">
                                <span className="settings-status status-info">
                                    Larger chunks = fewer round trips (but more memory)
                                </span>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};

/**
 * TreeNode Component - Recursive tree rendering with incremental loading
 */
const TreeNode = ({ node, level, onExpand, onSelect, selectedPath, expandingPath }) => {
    const isExpanded = node.isExpanded;
    const isSelected = node.path === selectedPath;
    const hasChildren = node.hasContent || (node.children && node.children.length > 0);
    const isLoading = expandingPath === node.path;

    const handleExpand = async (e) => {
        e.stopPropagation();
        if (!isExpanded && !isLoading) {
            await onExpand(node.path);
        } else if (isExpanded) {
            // Collapse
            onExpand(node.path, true);
        }
    };

    return (
        <div className="tree-node">
            <div
                className={`tree-node-content ${isSelected ? 'selected' : ''}`}
                style={{ paddingLeft: `${level * 16}px` }}
                onClick={() => onSelect(node.path)}
            >
                {hasChildren && (
                    <button
                        className="tree-expand-button"
                        onClick={handleExpand}
                        disabled={isLoading}
                    >
                        {isLoading ? '⌛' : isExpanded ? '▼' : '▶'}
                    </button>
                )}
                {!hasChildren && <span style={{ width: '16px', display: 'inline-block' }}></span>}
                <span className="tree-icon">📁</span>
                <span className="tree-name">{getDisplayName(node)}</span>
            </div>
            {isExpanded && node.children && node.children.length > 0 && (
                <div className="tree-children">
                    {node.children
                        .filter(c => c.type === 'folder')
                        .map(child => (
                            <TreeNode
                                key={child.path}
                                node={child}
                                level={level + 1}
                                onExpand={onExpand}
                                onSelect={onSelect}
                                selectedPath={selectedPath}
                                expandingPath={expandingPath}
                            />
                        ))}
                </div>
            )}
        </div>
    );
};

/**
 * TreeNavigation Component - Left pane with incremental tree
 */
const TreeNavigation = ({ treeState, onExpand, onSelect, selectedPath, expandingPath }) => {
    if (!treeState || !Array.isArray(treeState.nodes)) {
        return (
            <div className="tree-navigation">
                <div className="tree-header">Folders</div>
                <div className="tree-content">
                    <div style={{ padding: '10px', color: '#888' }}>Loading...</div>
                </div>
            </div>
        );
    }

    return (
        <div className="tree-navigation">
            <div className="tree-header">Folders</div>
            <div className="tree-content">
                {treeState.nodes.map(node => (
                    <TreeNode
                        key={node.path}
                        node={node}
                        level={0}
                        onExpand={onExpand}
                        onSelect={onSelect}
                        selectedPath={selectedPath}
                        expandingPath={expandingPath}
                    />
                ))}
            </div>
        </div>
    );
};

/**
 * FileList Component - Center pane with file list
 */
const FileList = ({ files, selectedFile, selectedFiles, onSelectFile, onToggleSelect, onToggleSelectAll, onDoubleClick, onDownload, columnWidths, handleColumnResize }) => {
    const allSelected = files.length > 0 && files.every(f => selectedFiles.includes(f.path));
    const someSelected = files.some(f => selectedFiles.includes(f.path));

    // Refs for column headers
    const nameHeaderRef = React.useRef(null);
    const modifiedHeaderRef = React.useRef(null);
    const sizeHeaderRef = React.useRef(null);
    const typeHeaderRef = React.useRef(null);

    // Column resize handle component
    const ColumnResizeHandle = ({ columnKey, headerRef }) => {
        return React.createElement('div', {
            className: 'column-resize-handle',
            onMouseDown: handleColumnResize(columnKey, headerRef.current),
            title: 'Drag to resize column'
        });
    };

    return (
        <div className="file-list">
            <div className="file-list-header">
                <div className="file-list-header-cell" style={{ width: columnWidths.checkbox + 'px' }}>
                    <input
                        type="checkbox"
                        checked={allSelected}
                        ref={input => {
                            if (input) input.indeterminate = someSelected && !allSelected;
                        }}
                        onChange={(e) => onToggleSelectAll(e.target.checked)}
                        title={allSelected ? 'Deselect all' : 'Select all'}
                    />
                </div>
                <div
                    ref={nameHeaderRef}
                    className="file-list-header-cell"
                    style={{
                        width: columnWidths.name ? columnWidths.name + 'px' : undefined,
                        flex: columnWidths.name ? undefined : 2,
                        position: 'relative'
                    }}
                >
                    Name
                    <ColumnResizeHandle columnKey="name" headerRef={nameHeaderRef} />
                </div>
                <div
                    ref={modifiedHeaderRef}
                    className="file-list-header-cell"
                    style={{
                        width: columnWidths.modified ? columnWidths.modified + 'px' : undefined,
                        flex: columnWidths.modified ? undefined : 1,
                        position: 'relative'
                    }}
                >
                    Modified
                    <ColumnResizeHandle columnKey="modified" headerRef={modifiedHeaderRef} />
                </div>
                <div
                    ref={sizeHeaderRef}
                    className="file-list-header-cell"
                    style={{
                        width: columnWidths.size ? columnWidths.size + 'px' : undefined,
                        flex: columnWidths.size ? undefined : 1,
                        position: 'relative'
                    }}
                >
                    Size
                    <ColumnResizeHandle columnKey="size" headerRef={sizeHeaderRef} />
                </div>
                <div
                    ref={typeHeaderRef}
                    className="file-list-header-cell"
                    style={{
                        width: columnWidths.type ? columnWidths.type + 'px' : undefined,
                        flex: columnWidths.type ? undefined : 1,
                        position: 'relative'
                    }}
                >
                    Type
                    <ColumnResizeHandle columnKey="type" headerRef={typeHeaderRef} />
                </div>
                <div className="file-list-header-cell" style={{ width: columnWidths.actions + 'px' }}>Actions</div>
            </div>
            <div className="file-list-body">
                {files.length === 0 && (
                    <div className="file-list-empty">No files in this folder</div>
                )}
                {files.map(file => {
                    const isChecked = selectedFiles.includes(file.path);
                    const isSelected = selectedFile?.path === file.path;
                    const isTempFile = file.type === 'file' && isTempUploadFile(file.name);

                    return (
                        <div
                            key={file.path}
                            className={`file-list-row ${isSelected ? 'selected' : ''} ${isChecked ? 'checked' : ''} ${isTempFile ? 'temp-upload-file' : ''}`}
                            onClick={() => onSelectFile(file)}
                            onDoubleClick={() => onDoubleClick(file)}
                        >
                            <div className="file-list-cell" style={{ width: columnWidths.checkbox + 'px' }}>
                                <input
                                    type="checkbox"
                                    checked={isChecked}
                                    onChange={(e) => {
                                        e.stopPropagation();
                                        onToggleSelect(file.path);
                                    }}
                                    onClick={(e) => e.stopPropagation()}
                                />
                            </div>
                            <div className="file-list-cell" style={{
                                width: columnWidths.name ? columnWidths.name + 'px' : undefined,
                                flex: columnWidths.name ? undefined : 2
                            }}>
                                <span className="file-icon">{file.type === 'folder' ? '📁' : (isTempFile ? '📤' : '📄')}</span>
                                <span className="file-name" title={isTempFile ? 'Incomplete upload - click to view or delete' : ''}>
                                    {file.name}
                                </span>
                                {isTempFile && (
                                    <span className="temp-file-badge" title="Incomplete upload">⚠️ Temp</span>
                                )}
                            </div>
                            <div className="file-list-cell" style={{
                                width: columnWidths.modified ? columnWidths.modified + 'px' : undefined,
                                flex: columnWidths.modified ? undefined : 1
                            }}>
                                {formatDate(file.modified)}
                            </div>
                            <div className="file-list-cell" style={{
                                width: columnWidths.size ? columnWidths.size + 'px' : undefined,
                                flex: columnWidths.size ? undefined : 1
                            }}>
                                {formatSize(file.size)}
                            </div>
                            <div className="file-list-cell" style={{
                                width: columnWidths.type ? columnWidths.type + 'px' : undefined,
                                flex: columnWidths.type ? undefined : 1
                            }}>
                                {file.type === 'folder' ? 'Folder' : (file.extension || '-')}
                            </div>
                            <div className="file-list-cell" style={{ width: columnWidths.actions + 'px' }}>
                                {file.type === 'file' && (
                                    <button
                                        className="file-action-button"
                                        onClick={(e) => {
                                            e.stopPropagation();
                                            onDownload(file);
                                        }}
                                        title="Download"
                                    >
                                        ⬇
                                    </button>
                                )}
                            </div>
                        </div>
                    );
                })}
            </div>
        </div>
    );
};

/**
 * CollapsibleSection Component - For nested VersionInfo data
 */
const CollapsibleSection = ({ title, summary, defaultExpanded = false, children }) => {
    const [isExpanded, setIsExpanded] = useState(defaultExpanded);

    return (
        <div className="collapsible-section">
            <div
                className="section-header"
                onClick={() => setIsExpanded(!isExpanded)}
            >
                <span className="expand-icon">{isExpanded ? '▼' : '▶'}</span>
                <span className="section-title">{title}</span>
                {!isExpanded && summary && (
                    <span className="section-summary"> — {summary}</span>
                )}
            </div>
            {isExpanded && (
                <div className="section-content">{children}</div>
            )}
        </div>
    );
};

/**
 * Property Component - Display key-value pair
 */
const Property = ({ name, value }) => {
    return (
        <div className="property-row">
            <span className="property-name">{name}:</span>
            <span className="property-value">{value || '-'}</span>
        </div>
    );
};

/**
 * TransferItem Component - Individual transfer in the list
 */
const TransferItem = ({ transfer, onCancel, onRetry, onRemove, onShowMetadata, onTransferClick, isSelected, onPause, onResume, onValidate }) => {
    const getStatusColor = () => {
        switch (transfer.status) {
            case 'completed': return '#4CAF50';
            case 'failed': return '#f44336';
            case 'uploading':
            case 'downloading': return '#2196F3';
            case 'queued': return '#999';
            default: return '#666';
        }
    };

    const getStatusIcon = () => {
        switch (transfer.status) {
            case 'completed': return '✓';
            case 'failed': return '✗';
            case 'uploading': return '⬆';
            case 'downloading': return '⬇';
            case 'queued': return '⏱';
            default: return '•';
        }
    };

    const getMethodBadge = () => {
        if (!transfer.method) return null;

        const badges = {
            streaming: { icon: '⚡', label: 'Streaming', className: 'method-streaming' },
            websocket: { icon: '🔌', label: 'WebSocket', className: 'method-websocket' },
            putChunks: { icon: '📤', label: 'PUT', className: 'method-putchunks' }
        };

        const badge = badges[transfer.method];
        if (!badge) return null;

        return (
            <span className={`transfer-method-badge ${badge.className}`} title={badge.label}>
                {badge.icon} {badge.label}
            </span>
        );
    };

    return (
        <div
            className={`transfer-item ${isSelected ? 'selected' : ''}`}
            onClick={() => onTransferClick && onTransferClick(transfer)}
            style={{ cursor: onTransferClick ? 'pointer' : 'default' }}
        >
            <div className="transfer-icon" style={{ color: getStatusColor() }}>
                {getStatusIcon()}
            </div>
            <div className="transfer-info">
                <div className="transfer-name">
                    {transfer.fileName}
                    {getMethodBadge()}
                </div>
                <div className="transfer-details">
                    {transfer.status === 'uploading' || transfer.status === 'downloading' ? (
                        <>
                            <div className="transfer-progress-bar">
                                <div className="transfer-progress-fill" style={{ width: `${transfer.progress}%` }}></div>
                            </div>
                            <span className="transfer-progress-text">
                                {transfer.progress}%
                                {transfer.speed > 0 && (
                                    <>
                                        {' • '}
                                        <span className="speed-current" title="Current speed (5-sec avg)">⚡{transfer.speed} MB/s</span>
                                        {transfer.speedAverage > 0 && (
                                            <>
                                                {' • '}
                                                <span className="speed-average" title="Average speed since start">📊{transfer.speedAverage} MB/s</span>
                                            </>
                                        )}
                                    </>
                                )}
                                {transfer.eta && (
                                    <> • ETA: {transfer.eta < 60 ? `${transfer.eta}s` : `${Math.floor(transfer.eta / 60)}m ${transfer.eta % 60}s`}</>
                                )}
                            </span>
                        </>
                    ) : transfer.validating ? (
                        <>
                            <div className="transfer-progress-bar">
                                <div className="transfer-progress-fill" style={{ width: `${transfer.validationProgress || 0}%`, backgroundColor: '#FFA500' }}></div>
                            </div>
                            <span className="transfer-progress-text">Validating... {transfer.validationProgress || 0}%</span>
                        </>
                    ) : transfer.validated ? (
                        <span className="transfer-status" style={{ color: transfer.validationPassed ? '#4CAF50' : '#f44336' }}>
                            {transfer.validationPassed ? '✓ Validated' : '✗ Validation Failed'}
                            {transfer.validationError && ` (${transfer.validationError})`}
                        </span>
                    ) : (
                        <span className="transfer-status">{transfer.status}</span>
                    )}
                </div>
            </div>
            <div className="transfer-actions">
                {transfer.metadata && (
                    <button onClick={() => onShowMetadata(transfer)} title="View transfer details" className="transfer-info-button">
                        ℹ️
                    </button>
                )}
                {transfer.status === 'failed' && transfer.type === 'download' && (
                    <button onClick={() => onRetry(transfer.id)} title="Retry download">⟳</button>
                )}
                {transfer.status === 'uploading' && onPause && (
                    <button onClick={() => onPause(transfer.id)} title="Pause upload">⏸</button>
                )}
                {transfer.status === 'paused' && onResume && (
                    <>
                        <button onClick={() => onResume(transfer.id, transfer.method)} title="Resume upload (file re-selection required)">▶</button>
                        <select
                            className="method-switch-select"
                            value={transfer.method || ''}
                            onChange={(e) => {
                                e.stopPropagation();
                                if (e.target.value !== transfer.method) {
                                    onResume(transfer.id, e.target.value);
                                }
                            }}
                            onClick={(e) => e.stopPropagation()}
                            title="Switch upload method"
                        >
                            <option value="streaming">⚡ Streaming</option>
                            <option value="websocket">🔌 WebSocket</option>
                            <option value="putChunks">📤 PUT Chunks</option>
                        </select>
                    </>
                )}
                {(transfer.status === 'uploading' || transfer.status === 'downloading' || transfer.status === 'paused') && (
                    <button onClick={() => onCancel(transfer.id)} title="Cancel">✕</button>
                )}
                {transfer.status === 'completed' && !transfer.validating && !transfer.validated && onValidate && transfer.type === 'upload' && (
                    <button onClick={(e) => { e.stopPropagation(); onValidate(transfer.id); }} title="Validate file integrity (compare hashes)">🔍</button>
                )}
                {(transfer.status === 'completed' || transfer.status === 'failed') && (
                    <button onClick={() => onRemove(transfer.id)} title="Remove from list">🗑</button>
                )}
            </div>
        </div>
    );
};

/**
 * TransferManager Component - Upload/Download manager
 */
const TransferManager = ({ transfers, onUpload, onCancel, onRetry, onRemove, currentPath, onShowMetadata, onTransferClick, selectedTransferId, onPause, onResume, onValidate }) => {
    const fileInputRef = React.useRef(null);
    const [isDragging, setIsDragging] = React.useState(false);

    const handleFileSelect = (files) => {
        if (files && files.length > 0) {
            Array.from(files).forEach(file => {
                onUpload(file, currentPath);
            });
        }
    };

    const handleDragEnter = (e) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(true);
    };

    const handleDragLeave = (e) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(false);
    };

    const handleDragOver = (e) => {
        e.preventDefault();
        e.stopPropagation();
    };

    const handleDrop = (e) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(false);

        const files = e.dataTransfer.files;
        handleFileSelect(files);
    };

    return (
        <div className="transfer-manager">
            {/* Transfer list shown first (above upload section) */}
            <div className="transfer-list">
                {transfers.length === 0 ? (
                    <div className="transfer-list-empty">No active transfers</div>
                ) : (
                    transfers.map(transfer => (
                        <TransferItem
                            key={transfer.id}
                            transfer={transfer}
                            onCancel={onCancel}
                            onRetry={onRetry}
                            onRemove={onRemove}
                            onShowMetadata={onShowMetadata}
                            onTransferClick={onTransferClick}
                            isSelected={selectedTransferId === transfer.id}
                            onPause={onPause}
                            onResume={onResume}
                            onValidate={onValidate}
                        />
                    ))
                )}
            </div>

            {/* Upload section shown below transfers */}
            <div
                className={`transfer-drop-zone ${isDragging ? 'dragging' : ''}`}
                onDragEnter={handleDragEnter}
                onDragLeave={handleDragLeave}
                onDragOver={handleDragOver}
                onDrop={handleDrop}
            >
                <input
                    ref={fileInputRef}
                    type="file"
                    multiple
                    style={{ display: 'none' }}
                    onChange={(e) => handleFileSelect(e.target.files)}
                />
                <button
                    className="transfer-select-button"
                    onClick={() => fileInputRef.current?.click()}
                >
                    📤 Select Files to Upload
                </button>
                <div className="transfer-drop-text">or drag and drop files here</div>
            </div>
        </div>
    );
};

/**
 * VersionInfoPanel Component - Bottom-left pane with file details
 */
const VersionInfoPanel = ({ versionInfo, loading }) => {
    if (loading) {
        return (
            <div className="version-info-panel">
                <div className="version-info-loading">Loading version info...</div>
            </div>
        );
    }

    if (!versionInfo) {
        return (
            <div className="version-info-panel">
                <div className="version-info-empty">Select a file to view details</div>
            </div>
        );
    }

    return (
        <div className="version-info-panel">
            <div className="version-info-content">
                {/* File Metadata */}
                <CollapsibleSection title="File Metadata" defaultExpanded={true}>
                    <Property name="Size" value={formatSize(versionInfo.fileMetadata.size)} />
                    <Property name="Modified" value={formatDate(versionInfo.fileMetadata.modified)} />
                    <Property name="Created" value={formatDate(versionInfo.fileMetadata.created)} />
                    <Property name="Accessed" value={formatDate(versionInfo.fileMetadata.accessed)} />
                    <Property name="Extension" value={versionInfo.fileMetadata.extension} />
                    <Property name="Attributes" value={versionInfo.fileMetadata.attributes?.join(', ')} />
                </CollapsibleSection>

                {/* PE Version Info */}
                {versionInfo.peVersionInfo && (
                    <CollapsibleSection
                        title="Version Information"
                        summary={`${versionInfo.peVersionInfo.fileVersion || 'N/A'} / ${versionInfo.peVersionInfo.productVersion || 'N/A'}`}
                        defaultExpanded={false}
                    >
                        <Property name="File Version" value={versionInfo.peVersionInfo.fileVersion} />
                        <Property name="Product Version" value={versionInfo.peVersionInfo.productVersion} />
                        <Property name="Company" value={versionInfo.peVersionInfo.companyName} />
                        <Property name="Description" value={versionInfo.peVersionInfo.fileDescription} />
                        <Property name="Product Name" value={versionInfo.peVersionInfo.productName} />
                        <Property name="Copyright" value={versionInfo.peVersionInfo.legalCopyright} />

                        <CollapsibleSection title="File Version Details">
                            <Property name="Major" value={versionInfo.peVersionInfo.fileVersionRaw?.major} />
                            <Property name="Minor" value={versionInfo.peVersionInfo.fileVersionRaw?.minor} />
                            <Property name="Build" value={versionInfo.peVersionInfo.fileVersionRaw?.build} />
                            <Property name="Revision" value={versionInfo.peVersionInfo.fileVersionRaw?.revision} />
                        </CollapsibleSection>

                        <CollapsibleSection title="Product Version Details">
                            <Property name="Major" value={versionInfo.peVersionInfo.productVersionRaw?.major} />
                            <Property name="Minor" value={versionInfo.peVersionInfo.productVersionRaw?.minor} />
                            <Property name="Build" value={versionInfo.peVersionInfo.productVersionRaw?.build} />
                            <Property name="Revision" value={versionInfo.peVersionInfo.productVersionRaw?.revision} />
                        </CollapsibleSection>
                    </CollapsibleSection>
                )}

                {/* Document Properties */}
                {versionInfo.documentProperties && (
                    <CollapsibleSection title="Document Properties" defaultExpanded={false}>
                        {Object.entries(versionInfo.documentProperties).map(([key, value]) => (
                            <Property key={key} name={key} value={value} />
                        ))}
                    </CollapsibleSection>
                )}

                {/* Image Properties */}
                {versionInfo.imageProperties && (
                    <CollapsibleSection title="Image Properties" defaultExpanded={false}>
                        <Property name="Dimensions" value={`${versionInfo.imageProperties.width} × ${versionInfo.imageProperties.height}`} />
                        <Property name="DPI" value={`${versionInfo.imageProperties.horizontalResolution} × ${versionInfo.imageProperties.verticalResolution}`} />
                        <Property name="Pixel Format" value={versionInfo.imageProperties.pixelFormat} />
                        <Property name="Format" value={versionInfo.imageProperties.rawFormat} />

                        {versionInfo.imageProperties.exif && (
                            <CollapsibleSection title="EXIF Data">
                                {Object.entries(versionInfo.imageProperties.exif).map(([key, value]) => (
                                    <Property key={key} name={key} value={String(value)} />
                                ))}
                            </CollapsibleSection>
                        )}
                    </CollapsibleSection>
                )}
            </div>
        </div>
    );
};

/**
 * FilePreview Component - Right pane
 */
const FilePreview = ({ file, visible }) => {
    const [previewContent, setPreviewContent] = React.useState(null);
    const [previewLoading, setPreviewLoading] = React.useState(false);
    const [previewError, setPreviewError] = React.useState(null);

    React.useEffect(() => {
        if (!file || !visible) return;

        const loadPreview = async () => {
            setPreviewLoading(true);
            setPreviewError(null);

            try {
                // Extract logical path from full path
                const logicalPath = file.path.split('|').length === 3 ? file.path.split('|')[2] : file.path;

                // Get file category
                const ext = (file.extension || '').toLowerCase();
                const isImage = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp', '.svg'].includes(ext);
                const isText = ['.txt', '.md', '.json', '.xml', '.csv', '.log', '.js', '.css', '.html', '.ps1', '.yaml', '.yml'].includes(ext);
                const isPdf = ext === '.pdf';

                if (isImage) {
                    // Load image preview
                    const url = `/apps/WebhostFileExplorer/api/v1/files/preview?path=${encodeURIComponent(logicalPath)}&mode=content`;
                    setPreviewContent({ type: 'image', url });
                } else if (isPdf) {
                    // Load PDF in iframe
                    const url = `/apps/WebhostFileExplorer/api/v1/files/preview?path=${encodeURIComponent(logicalPath)}&mode=content`;
                    setPreviewContent({ type: 'pdf', url });
                } else if (isText && file.size < 1024 * 1024) {
                    // Load text content (max 1MB)
                    const response = await window.psweb_fetchWithAuthHandling(
                        `/apps/WebhostFileExplorer/api/v1/files/preview?path=${encodeURIComponent(logicalPath)}&mode=content`
                    );
                    const text = await response.text();
                    setPreviewContent({ type: 'text', content: text });
                } else {
                    setPreviewContent({ type: 'unsupported', message: 'Preview not available for this file type' });
                }
            } catch (err) {
                setPreviewError(err.message);
            } finally {
                setPreviewLoading(false);
            }
        };

        loadPreview();
    }, [file, visible]);

    const handleUndock = () => {
        if (!file) return;

        const previewWindow = window.open('', `preview-${file.name}`, 'width=800,height=600,menubar=no,toolbar=no,location=no,status=no');

        if (previewWindow) {
            const contentHtml = previewContent?.type === 'image'
                ? `<img src="${previewContent.url}" style="max-width: 100%; max-height: 100%; object-fit: contain;" />`
                : previewContent?.type === 'pdf'
                ? `<iframe src="${previewContent.url}" style="width: 100%; height: 100%; border: none;"></iframe>`
                : previewContent?.type === 'text'
                ? `<pre style="background: #f5f5f5; padding: 15px; border-radius: 4px; overflow: auto; height: 100%; margin: 0; box-sizing: border-box;">${previewContent.content}</pre>`
                : '<p>Preview not available</p>';

            previewWindow.document.write(`
<!DOCTYPE html>
<html style="height: 100%;">
<head>
    <title>Preview: ${file.name}</title>
    <style>
        html, body {
            margin: 0;
            padding: 0;
            height: 100%;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #fff;
            overflow: hidden;
        }
        .mainContainer {
            display: flex;
            flex-direction: column;
            height: 100%;
            padding: 20px;
            box-sizing: border-box;
        }
        .preview-header {
            padding: 10px 0;
            border-bottom: 2px solid #0078d4;
            margin-bottom: 20px;
            flex-shrink: 0;
        }
        .preview-header h1 {
            margin: 0;
            font-size: 18px;
            color: #333;
        }
        .preview-header .file-info {
            font-size: 12px;
            color: #666;
            margin-top: 5px;
        }
        .preview-content {
            flex: 1;
            min-height: 0;
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }
        .preview-content > * {
            flex: 1;
            min-height: 0;
        }
        .preview-content img {
            display: block;
            margin: 0 auto;
        }
    </style>
</head>
<body>
    <div class="mainContainer">
        <div class="preview-header">
            <h1>${file.name}</h1>
            <div class="file-info">Type: ${file.extension || 'Unknown'} | Size: ${formatSize(file.size)}</div>
        </div>
        <div class="preview-content">${contentHtml}</div>
    </div>
</body>
</html>`);
            previewWindow.document.close();
        } else {
            alert('Failed to open preview window. Please check your popup blocker settings.');
        }
    };

    if (!visible) return null;

    return (
        <div className="file-preview">
            <div className="preview-header">
                <span>Preview</span>
                {file && (
                    <button className="preview-undock-button" onClick={handleUndock} title="Open in new window">⧉</button>
                )}
            </div>
            <div className="preview-content">
                {!file ? (
                    <div className="preview-empty">No file selected</div>
                ) : previewLoading ? (
                    <div className="preview-loading">Loading preview...</div>
                ) : previewError ? (
                    <div className="preview-error">Error: {previewError}</div>
                ) : previewContent?.type === 'image' ? (
                    <img src={previewContent.url} alt={file.name} style={{ maxWidth: '100%', height: 'auto' }} />
                ) : previewContent?.type === 'pdf' ? (
                    <iframe src={previewContent.url} style={{ width: '100%', height: '100%', border: 'none' }} title="PDF Preview"></iframe>
                ) : previewContent?.type === 'text' ? (
                    <pre style={{ background: '#f5f5f5', padding: '15px', borderRadius: '4px', overflow: 'auto', fontSize: '12px', margin: 0 }}>
                        {previewContent.content}
                    </pre>
                ) : (
                    <div className="preview-unsupported">{previewContent?.message || 'Preview not available'}</div>
                )}
            </div>
        </div>
    );
};

/**
 * TransferPreview Component - Shows transfer details in preview pane
 */
const TransferPreview = ({ transfer }) => {
    const formatBytes = (bytes) => {
        if (!bytes) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
    };

    const formatDuration = (seconds) => {
        if (!seconds) return 'N/A';
        const hours = Math.floor(seconds / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        const secs = Math.floor(seconds % 60);

        if (hours > 0) {
            return `${hours}h ${minutes}m ${secs}s`;
        } else if (minutes > 0) {
            return `${minutes}m ${secs}s`;
        } else {
            return `${secs}s`;
        }
    };

    const getMethodBadge = (method) => {
        const badges = {
            streaming: { icon: '⚡', label: 'Streaming', color: '#FF9800' },
            websocket: { icon: '🔌', label: 'WebSocket', color: '#4CAF50' },
            putChunks: { icon: '📤', label: 'PUT Chunks', color: '#2196F3' }
        };
        return badges[method] || { icon: '•', label: 'Unknown', color: '#999' };
    };

    const ChunkProgressBar = ({ totalChunks, receivedChunks }) => {
        if (!totalChunks) return null;

        // Show up to 100 blocks (each block represents multiple chunks if needed)
        const maxBlocks = 100;
        const chunksPerBlock = Math.max(1, Math.ceil(totalChunks / maxBlocks));
        const blockCount = Math.ceil(totalChunks / chunksPerBlock);

        const blocks = [];
        for (let i = 0; i < blockCount; i++) {
            const chunkStart = i * chunksPerBlock;
            const chunkEnd = Math.min((i + 1) * chunksPerBlock, totalChunks);
            const chunksInBlock = chunkEnd - chunkStart;
            const receivedInBlock = Math.min(chunksInBlock, Math.max(0, receivedChunks - chunkStart));
            const percentReceived = (receivedInBlock / chunksInBlock) * 100;

            blocks.push(
                <div
                    key={i}
                    className="chunk-block"
                    style={{
                        width: `${100 / blockCount}%`,
                        height: '20px',
                        background: percentReceived === 100 ? '#4CAF50' : percentReceived > 0 ? '#FFC107' : '#E0E0E0',
                        borderRight: '1px solid #fff'
                    }}
                    title={`Block ${i + 1}: ${Math.round(percentReceived)}% complete`}
                ></div>
            );
        }

        return (
            <div style={{ marginTop: '10px' }}>
                <div style={{ fontSize: '11px', color: '#666', marginBottom: '4px' }}>
                    Chunk Progress: {receivedChunks || 0} / {totalChunks} chunks
                </div>
                <div style={{ display: 'flex', width: '100%', height: '20px', border: '1px solid #ddd', borderRadius: '4px', overflow: 'hidden' }}>
                    {blocks}
                </div>
            </div>
        );
    };

    const SpeedGraph = ({ speedHistory }) => {
        if (!speedHistory || speedHistory.length < 2) {
            return (
                <div style={{ fontSize: '12px', color: '#999', padding: '10px 0' }}>
                    Collecting speed data...
                </div>
            );
        }

        // Simple text-based speed summary
        const speeds = speedHistory.map(h => {
            const prevIndex = speedHistory.indexOf(h) - 1;
            if (prevIndex < 0) return 0;
            const prev = speedHistory[prevIndex];
            const timeDiff = (h.timestamp - prev.timestamp) / 1000;
            const bytesDiff = h.bytes - prev.bytes;
            return timeDiff > 0 ? (bytesDiff / 1024 / 1024) / timeDiff : 0;
        }).filter(s => s > 0);

        const avgSpeed = speeds.reduce((a, b) => a + b, 0) / speeds.length;
        const maxSpeed = Math.max(...speeds);
        const minSpeed = Math.min(...speeds);

        return (
            <div style={{ fontSize: '12px', padding: '10px 0' }}>
                <div style={{ marginBottom: '5px', color: '#333' }}>
                    <strong>Speed Statistics (last 5 sec):</strong>
                </div>
                <div style={{ color: '#666' }}>Average: {avgSpeed.toFixed(2)} MB/s</div>
                <div style={{ color: '#666' }}>Peak: {maxSpeed.toFixed(2)} MB/s</div>
                <div style={{ color: '#666' }}>Lowest: {minSpeed.toFixed(2)} MB/s</div>
            </div>
        );
    };

    if (!transfer) {
        return (
            <div className="file-preview">
                <div className="preview-header">
                    <span>Transfer Details</span>
                </div>
                <div className="preview-content">
                    <div className="preview-empty">Select a transfer to view details</div>
                </div>
            </div>
        );
    }

    const badge = transfer.method ? getMethodBadge(transfer.method) : null;
    const elapsed = transfer.startTime ? (Date.now() - transfer.startTime) / 1000 : 0;

    return (
        <div className="file-preview">
            <div className="preview-header">
                <span>Transfer Details</span>
            </div>
            <div className="preview-content" style={{ padding: '15px', overflow: 'auto' }}>
                {/* Transfer Header */}
                <div style={{ marginBottom: '20px', borderBottom: '2px solid #0078d4', paddingBottom: '10px' }}>
                    <h3 style={{ margin: '0 0 5px 0', fontSize: '16px', color: '#333' }}>
                        {transfer.fileName}
                    </h3>
                    {badge && (
                        <div style={{ marginTop: '8px' }}>
                            <span style={{
                                display: 'inline-block',
                                padding: '4px 10px',
                                borderRadius: '12px',
                                fontSize: '11px',
                                fontWeight: '500',
                                background: badge.color,
                                color: '#fff'
                            }}>
                                {badge.icon} {badge.label}
                            </span>
                        </div>
                    )}
                </div>

                {/* Progress Section */}
                <div style={{ marginBottom: '20px' }}>
                    <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', color: '#555' }}>Progress</h4>
                    <div style={{ background: '#f0f0f0', padding: '12px', borderRadius: '6px' }}>
                        <div style={{ fontSize: '24px', fontWeight: 'bold', color: '#0078d4', marginBottom: '8px' }}>
                            {transfer.progress}%
                        </div>
                        <div style={{ fontSize: '13px', color: '#666', marginBottom: '4px' }}>
                            {formatBytes(transfer.bytesTransferred || 0)} / {formatBytes(transfer.fileSize)}
                        </div>
                        {transfer.status === 'uploading' && transfer.eta && (
                            <div style={{ fontSize: '12px', color: '#888' }}>
                                ETA: {transfer.eta < 60 ? `${transfer.eta}s` : `${Math.floor(transfer.eta / 60)}m ${transfer.eta % 60}s`}
                            </div>
                        )}

                        {/* Chunk visualization */}
                        {transfer.totalChunks && (
                            <ChunkProgressBar
                                totalChunks={transfer.totalChunks}
                                receivedChunks={transfer.currentChunk || transfer.metadata?.receivedChunks || 0}
                            />
                        )}
                    </div>
                </div>

                {/* Speed Section */}
                {transfer.speed > 0 && (
                    <div style={{ marginBottom: '20px' }}>
                        <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', color: '#555' }}>Transfer Speed</h4>
                        <div style={{ background: '#f0f0f0', padding: '12px', borderRadius: '6px' }}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '8px' }}>
                                <div>
                                    <div style={{ fontSize: '11px', color: '#888', marginBottom: '2px' }}>Current (5-sec avg)</div>
                                    <div style={{ fontSize: '18px', fontWeight: '500', color: '#2196F3' }}>
                                        ⚡ {transfer.speed} MB/s
                                    </div>
                                </div>
                                {transfer.speedAverage > 0 && (
                                    <div style={{ textAlign: 'right' }}>
                                        <div style={{ fontSize: '11px', color: '#888', marginBottom: '2px' }}>Overall Average</div>
                                        <div style={{ fontSize: '18px', fontWeight: '500', color: '#666' }}>
                                            📊 {transfer.speedAverage} MB/s
                                        </div>
                                    </div>
                                )}
                            </div>

                            {/* Speed graph */}
                            <SpeedGraph speedHistory={transfer.speedHistory} />
                        </div>
                    </div>
                )}

                {/* Metadata Section */}
                <div style={{ marginBottom: '20px' }}>
                    <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', color: '#555' }}>Transfer Information</h4>
                    <div style={{ background: '#f0f0f0', padding: '12px', borderRadius: '6px', fontSize: '12px' }}>
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '8px' }}>
                            <div style={{ color: '#666', fontWeight: '500' }}>Status:</div>
                            <div style={{ color: '#333' }}>{transfer.status}</div>

                            <div style={{ color: '#666', fontWeight: '500' }}>Type:</div>
                            <div style={{ color: '#333' }}>{transfer.type}</div>

                            {transfer.startTime && (
                                <>
                                    <div style={{ color: '#666', fontWeight: '500' }}>Duration:</div>
                                    <div style={{ color: '#333' }}>{formatDuration(elapsed)}</div>
                                </>
                            )}

                            {transfer.targetPath && (
                                <>
                                    <div style={{ color: '#666', fontWeight: '500' }}>Target:</div>
                                    <div style={{ color: '#333', wordBreak: 'break-all' }}>{transfer.targetPath}</div>
                                </>
                            )}
                        </div>
                    </div>
                </div>

                {/* Technical Metadata (if available) */}
                {transfer.metadata && (
                    <div>
                        <h4 style={{ margin: '0 0 10px 0', fontSize: '14px', color: '#555' }}>Technical Details</h4>
                        <div style={{ background: '#f0f0f0', padding: '12px', borderRadius: '6px', fontSize: '11px' }}>
                            <div style={{ display: 'grid', gridTemplateColumns: '1fr 2fr', gap: '6px' }}>
                                {transfer.metadata.uploadGuid && (
                                    <>
                                        <div style={{ color: '#666', fontWeight: '500' }}>Session ID:</div>
                                        <div style={{ color: '#333', fontFamily: 'monospace', fontSize: '10px' }}>{transfer.metadata.uploadGuid}</div>
                                    </>
                                )}

                                {transfer.metadata.chunkSize && (
                                    <>
                                        <div style={{ color: '#666', fontWeight: '500' }}>Chunk Size:</div>
                                        <div style={{ color: '#333' }}>{formatBytes(transfer.metadata.chunkSize)}</div>
                                    </>
                                )}

                                {transfer.metadata.totalChunks && (
                                    <>
                                        <div style={{ color: '#666', fontWeight: '500' }}>Total Chunks:</div>
                                        <div style={{ color: '#333' }}>{transfer.metadata.totalChunks}</div>
                                    </>
                                )}

                                {transfer.metadata.pipelineDepth && (
                                    <>
                                        <div style={{ color: '#666', fontWeight: '500' }}>Pipeline Depth:</div>
                                        <div style={{ color: '#333' }}>{transfer.metadata.pipelineDepth}</div>
                                    </>
                                )}

                                {transfer.metadata.retryCount !== undefined && (
                                    <>
                                        <div style={{ color: '#666', fontWeight: '500' }}>Retries:</div>
                                        <div style={{ color: '#333' }}>{transfer.metadata.retryCount}</div>
                                    </>
                                )}
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </div>
    );
};

// ============================================================================
// LOGGING UTILITY - Use global window.logToServer with batching
// ============================================================================

// Store reference to global logger before component defines its own
const _globalLogToServer = window.logToServer;

const logToServer = (message, level = 'Info', data = null) => {
    // Use global batching logger (defined in psweb_spa.js)
    if (_globalLogToServer) {
        _globalLogToServer(message, 'FileExplorer', level, data);
    } else {
        // Fallback if global logger not available
        console.log(`[FileExplorer][${new Date().toISOString()}] ${message}`);
    }
};

/**
 * Log transfer-specific events to server with enriched data
 * @param {string} action - Action type (e.g., 'upload_start', 'chunk_sent', 'upload_complete')
 * @param {object} transferData - Transfer details (fileName, method, guid, etc.)
 * @param {string} level - Log level (Info, Warning, Error)
 */
const logTransferAction = (action, transferData, level = 'Info') => {
    const enrichedData = {
        action: action,
        timestamp: new Date().toISOString(),
        ...transferData
    };

    logToServer(`Transfer Action: ${action} - ${transferData.fileName || 'unknown'}`, level, enrichedData);
};

// ============================================================================
// DIALOG COMPONENTS
// ============================================================================

/**
 * Delete Confirmation Dialog
 */
const DeleteConfirmDialog = ({ visible, files, onConfirm, onCancel }) => {
    const [confirmText, setConfirmText] = React.useState('');
    const isBulk = files && files.length > 1;
    const canConfirm = !isBulk || confirmText.toLowerCase() === 'bulk';

    React.useEffect(() => {
        if (visible) {
            setConfirmText('');
        }
    }, [visible]);

    if (!visible) return null;

    return (
        <div className="dialog-overlay" onClick={onCancel}>
            <div className="dialog-box" onClick={(e) => e.stopPropagation()}>
                <div className="dialog-header">
                    <h3>Confirm Delete</h3>
                    <button className="dialog-close" onClick={onCancel}>✕</button>
                </div>
                <div className="dialog-body">
                    <p>Are you sure you want to delete {files.length} item(s)?</p>
                    <ul className="delete-file-list">
                        {files.map(file => (
                            <li key={file.path}>
                                <span className="file-icon">{file.type === 'folder' ? '📁' : '📄'}</span>
                                {file.name}
                            </li>
                        ))}
                    </ul>
                    <p className="warning-text">⚠️ This action cannot be undone.</p>

                    {isBulk && (
                        <div className="bulk-confirm-section">
                            <label htmlFor="delete-confirm-input">
                                Type <strong>bulk</strong> to confirm:
                            </label>
                            <input
                                id="delete-confirm-input"
                                type="text"
                                className="bulk-confirm-input"
                                value={confirmText}
                                onChange={(e) => setConfirmText(e.target.value)}
                                placeholder="Type 'bulk' here"
                                autoFocus
                            />
                        </div>
                    )}
                </div>
                <div className="dialog-footer">
                    <button className="dialog-button dialog-button-secondary" onClick={onCancel}>
                        Cancel
                    </button>
                    <button
                        className="dialog-button dialog-button-danger"
                        onClick={() => onConfirm(files)}
                        disabled={!canConfirm}
                    >
                        Delete
                    </button>
                </div>
            </div>
        </div>
    );
};

/**
 * Batch Rename Dialog with Pattern/Replace and Live Preview
 */
const RenameDialog = ({ visible, files, pattern, replacement, mode, onChange, onConfirm, onCancel }) => {
    if (!visible || !files || files.length === 0) return null;

    const isSingle = files.length === 1;
    const [renameMode, setRenameMode] = React.useState(mode || 'wildcard');
    const [patternValue, setPatternValue] = React.useState(pattern || (isSingle ? files[0].name : '*'));
    const [replacementValue, setReplacementValue] = React.useState(replacement || '');
    const [confirmText, setConfirmText] = React.useState('');

    React.useEffect(() => {
        if (visible) {
            setConfirmText('');
        }
    }, [visible]);

    // Convert wildcard pattern to regex
    const wildcardToRegex = (wildcardPattern) => {
        // Escape regex special chars except * and ?
        let pattern = wildcardPattern.replace(/[.+^${}()|[\]\\]/g, '\\$&');
        // Replace * with .* (any characters) and ? with . (single character)
        pattern = pattern.replace(/\*/g, '.*').replace(/\?/g, '.');
        return new RegExp(pattern);
    };

    // Generate preview of renamed files
    const previewRenames = React.useMemo(() => {
        return files.map(file => {
            let newName = file.name;

            try {
                if (isSingle) {
                    // Single file: simple rename (pattern is the new name)
                    newName = patternValue;
                } else {
                    // Batch rename: pattern and replacement
                    if (renameMode === 'wildcard') {
                        const regex = wildcardToRegex(patternValue);
                        newName = file.name.replace(regex, replacementValue);
                    } else {
                        // Regex mode
                        const regex = new RegExp(patternValue);
                        newName = file.name.replace(regex, replacementValue);
                    }
                }
            } catch (err) {
                // Invalid regex/pattern - keep original name
                newName = file.name;
            }

            return {
                file: file,
                oldName: file.name,
                newName: newName,
                changed: newName !== file.name,
                error: newName === file.name && patternValue && replacementValue ? 'No match' : null
            };
        });
    }, [files, patternValue, replacementValue, renameMode, isSingle]);

    const hasChanges = previewRenames.some(r => r.changed);
    const canConfirm = hasChanges && (isSingle || confirmText.toLowerCase() === 'bulk');

    const handleConfirm = () => {
        // Pass rename operations to parent
        const renames = previewRenames.filter(r => r.changed).map(r => ({
            file: r.file,
            newName: r.newName
        }));
        onConfirm(renames, { pattern: patternValue, replacement: replacementValue, mode: renameMode });
    };

    const handleKeyPress = (e) => {
        if (e.key === 'Enter' && hasChanges) {
            handleConfirm();
        } else if (e.key === 'Escape') {
            onCancel();
        }
    };

    return (
        <div className="dialog-overlay" onClick={onCancel}>
            <div className="dialog-box dialog-box-large" onClick={(e) => e.stopPropagation()}>
                <div className="dialog-header">
                    <h3>{isSingle ? 'Rename File' : `Batch Rename (${files.length} items)`}</h3>
                    <button className="dialog-close" onClick={onCancel}>✕</button>
                </div>
                <div className="dialog-body">
                    {isSingle ? (
                        // Single file rename - simple mode
                        <>
                            <p>
                                <span className="file-icon">{files[0].type === 'folder' ? '📁' : '📄'}</span>
                                Current name: <strong>{files[0].name}</strong>
                            </p>
                            <label>
                                New name:
                                <input
                                    type="text"
                                    className="dialog-input"
                                    value={patternValue}
                                    onChange={(e) => setPatternValue(e.target.value)}
                                    onKeyDown={handleKeyPress}
                                    autoFocus
                                />
                            </label>
                        </>
                    ) : (
                        // Batch rename - pattern/replace mode
                        <>
                            {/* Mode selector */}
                            <div className="rename-mode-selector">
                                <label className="rename-mode-radio">
                                    <input
                                        type="radio"
                                        name="renameMode"
                                        value="wildcard"
                                        checked={renameMode === 'wildcard'}
                                        onChange={(e) => setRenameMode(e.target.value)}
                                    />
                                    <span>Wildcard (* = any chars, ? = single char)</span>
                                </label>
                                <label className="rename-mode-radio">
                                    <input
                                        type="radio"
                                        name="renameMode"
                                        value="regex"
                                        checked={renameMode === 'regex'}
                                        onChange={(e) => setRenameMode(e.target.value)}
                                    />
                                    <span>Regex (regular expressions)</span>
                                </label>
                            </div>

                            {/* Pattern and Replacement fields */}
                            <div className="rename-fields">
                                <label>
                                    Find pattern:
                                    <input
                                        type="text"
                                        className="dialog-input"
                                        value={patternValue}
                                        onChange={(e) => setPatternValue(e.target.value)}
                                        onKeyDown={handleKeyPress}
                                        placeholder={renameMode === 'wildcard' ? 'e.g., *.txt or file_*' : 'e.g., ^(.+)\\.txt$'}
                                        autoFocus
                                    />
                                </label>
                                <label>
                                    Replace with:
                                    <input
                                        type="text"
                                        className="dialog-input"
                                        value={replacementValue}
                                        onChange={(e) => setReplacementValue(e.target.value)}
                                        onKeyDown={handleKeyPress}
                                        placeholder={renameMode === 'wildcard' ? 'new name' : 'e.g., $1.md'}
                                    />
                                </label>
                            </div>

                            {/* Live Preview */}
                            <div className="rename-preview">
                                <h4>Preview:</h4>
                                <div className="rename-preview-list">
                                    {previewRenames.map((rename, idx) => (
                                        <div
                                            key={idx}
                                            className={`rename-preview-item ${rename.changed ? 'changed' : ''} ${rename.error ? 'error' : ''}`}
                                        >
                                            <span className="file-icon">{rename.file.type === 'folder' ? '📁' : '📄'}</span>
                                            <span className="rename-old-name">{rename.oldName}</span>
                                            <span className="rename-arrow">→</span>
                                            <span className="rename-new-name">{rename.newName}</span>
                                            {rename.error && <span className="rename-error">{rename.error}</span>}
                                        </div>
                                    ))}
                                </div>
                            </div>

                            {/* Bulk confirmation */}
                            <div className="bulk-confirm-section">
                                <label htmlFor="rename-confirm-input">
                                    Type <strong>bulk</strong> to confirm:
                                </label>
                                <input
                                    id="rename-confirm-input"
                                    type="text"
                                    className="bulk-confirm-input"
                                    value={confirmText}
                                    onChange={(e) => setConfirmText(e.target.value)}
                                    placeholder="Type 'bulk' here"
                                />
                            </div>
                        </>
                    )}
                </div>
                <div className="dialog-footer">
                    <button className="dialog-button dialog-button-secondary" onClick={onCancel}>
                        Cancel
                    </button>
                    <button
                        className="dialog-button dialog-button-primary"
                        onClick={handleConfirm}
                        disabled={!canConfirm}
                    >
                        Rename {isSingle ? '' : `(${previewRenames.filter(r => r.changed).length})`}
                    </button>
                </div>
            </div>
        </div>
    );
};

/**
 * TempFileDialog - Shows options for incomplete upload temp files
 */
const TempFileDialog = ({ visible, file, uploadGuid, onClose, onDelete, onViewTransfer }) => {
    if (!visible || !file) return null;

    const formatBytes = (bytes) => {
        if (!bytes) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
    };

    const formatDate = (dateString) => {
        if (!dateString) return 'Unknown';
        try {
            const date = new Date(dateString);
            return date.toLocaleString();
        } catch {
            return 'Unknown';
        }
    };

    return (
        <div className="dialog-overlay" onClick={onClose}>
            <div className="dialog-box temp-file-dialog" onClick={(e) => e.stopPropagation()}>
                <div className="dialog-header">
                    <h3>⚠️ Incomplete Upload File</h3>
                    <button className="dialog-close" onClick={onClose}>✕</button>
                </div>
                <div className="dialog-body">
                    <div className="temp-file-info">
                        <p style={{ marginBottom: '15px', color: '#666' }}>
                            This is a temporary file from an incomplete upload. You can delete it to free up space.
                        </p>

                        <div className="info-grid" style={{ background: '#f5f5f5', padding: '12px', borderRadius: '6px', marginBottom: '15px' }}>
                            <div style={{ display: 'grid', gridTemplateColumns: '120px 1fr', gap: '8px', fontSize: '13px' }}>
                                <div style={{ fontWeight: '500', color: '#555' }}>File Name:</div>
                                <div style={{ color: '#333', wordBreak: 'break-all' }}>{file.name}</div>

                                <div style={{ fontWeight: '500', color: '#555' }}>Size:</div>
                                <div style={{ color: '#333' }}>{formatBytes(file.size)}</div>

                                <div style={{ fontWeight: '500', color: '#555' }}>Modified:</div>
                                <div style={{ color: '#333' }}>{formatDate(file.modified)}</div>

                                {uploadGuid && (
                                    <>
                                        <div style={{ fontWeight: '500', color: '#555' }}>Upload ID:</div>
                                        <div style={{ color: '#333', fontFamily: 'monospace', fontSize: '11px' }}>{uploadGuid}</div>
                                    </>
                                )}
                            </div>
                        </div>

                        {onViewTransfer && (
                            <div style={{ padding: '10px', background: '#e3f2fd', borderRadius: '6px', marginBottom: '15px' }}>
                                <p style={{ margin: '0 0 8px 0', fontSize: '13px', color: '#0277bd' }}>
                                    ℹ️ This file belongs to an active transfer
                                </p>
                                <button
                                    className="dialog-button dialog-button-primary"
                                    onClick={() => {
                                        onViewTransfer();
                                        onClose();
                                    }}
                                    style={{ width: '100%' }}
                                >
                                    📊 View Transfer Details
                                </button>
                            </div>
                        )}

                        {!onViewTransfer && (
                            <div style={{ padding: '10px', background: '#fff3cd', borderRadius: '6px', marginBottom: '15px' }}>
                                <p style={{ margin: 0, fontSize: '13px', color: '#856404' }}>
                                    💡 This upload was interrupted. Resume functionality will be available in Phase 2.
                                </p>
                            </div>
                        )}
                    </div>
                </div>
                <div className="dialog-footer">
                    <button className="dialog-button dialog-button-secondary" onClick={onClose}>
                        Cancel
                    </button>
                    <button
                        className="dialog-button"
                        onClick={() => {
                            onDelete();
                            onClose();
                        }}
                        style={{ background: '#f44336', color: '#fff' }}
                    >
                        🗑️ Delete Temp File
                    </button>
                </div>
            </div>
        </div>
    );
};

const ResumeDialog = ({ visible, file, resumeData, onResume, onStartFresh, onCancel }) => {
    if (!visible || !file || !resumeData) return null;

    const formatBytes = (bytes) => {
        if (!bytes) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
    };

    const formatDuration = (milliseconds) => {
        const seconds = Math.floor(milliseconds / 1000);
        const minutes = Math.floor(seconds / 60);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);

        if (days > 0) return `${days}d ${hours % 24}h ago`;
        if (hours > 0) return `${hours}h ${minutes % 60}m ago`;
        if (minutes > 0) return `${minutes}m ${seconds % 60}s ago`;
        return `${seconds}s ago`;
    };

    const { receivedChunks, totalChunks, receivedBytes, bytesCommitted, missingChunks, uploadMethod, startTime, fileSize, percentComplete: providedPercent } = resumeData;

    // For streaming uploads, use bytesCommitted and percentComplete from server
    const isStreaming = uploadMethod === 'streaming';
    const percentComplete = isStreaming ? (providedPercent || 0) : Math.round((receivedChunks / totalChunks) * 100);
    const bytesUploaded = isStreaming ? bytesCommitted : receivedBytes;
    const timeAgo = startTime ? formatDuration(Date.now() - startTime) : 'Recently';

    const getMethodName = (method) => {
        if (method === 'streaming') return '⚡ Streaming';
        if (method === 'websocket') return '🔌 WebSocket';
        if (method === 'putChunks') return '📤 PUT Chunks';
        if (method === 'chunked') return '📤 Chunked';
        return '❓ Unknown';
    };

    return (
        <div className="dialog-overlay" onClick={onCancel}>
            <div className="dialog-box resume-dialog" onClick={(e) => e.stopPropagation()}>
                <div className="dialog-header">
                    <h3>📦 Resume Incomplete Upload?</h3>
                    <button className="dialog-close" onClick={onCancel}>✕</button>
                </div>
                <div className="dialog-body">
                    <div className="resume-info">
                        <p style={{ marginBottom: '15px', color: '#555', fontSize: '14px' }}>
                            An incomplete upload was found for this file. Would you like to resume from where it left off?
                        </p>

                        <div className="info-grid" style={{ background: '#f5f5f5', padding: '15px', borderRadius: '8px', marginBottom: '15px' }}>
                            <div style={{ display: 'grid', gridTemplateColumns: '140px 1fr', gap: '10px', fontSize: '13px' }}>
                                <div style={{ fontWeight: '600', color: '#555' }}>File Name:</div>
                                <div style={{ color: '#333', wordBreak: 'break-all', fontWeight: '500' }}>{file.name}</div>

                                <div style={{ fontWeight: '600', color: '#555' }}>File Size:</div>
                                <div style={{ color: '#333' }}>{formatBytes(file.size)}</div>

                                <div style={{ fontWeight: '600', color: '#555' }}>Progress:</div>
                                <div style={{ color: '#333' }}>
                                    <div style={{ marginBottom: '5px' }}>
                                        <span style={{ fontWeight: '600', color: '#2e7d32', fontSize: '15px' }}>{percentComplete}%</span>
                                        {!isStreaming && (
                                            <span style={{ color: '#666', marginLeft: '8px' }}>
                                                ({receivedChunks} of {totalChunks} chunks)
                                            </span>
                                        )}
                                    </div>
                                    <div className="progress-bar" style={{ background: '#e0e0e0', height: '8px', borderRadius: '4px', overflow: 'hidden' }}>
                                        <div
                                            style={{
                                                width: `${percentComplete}%`,
                                                height: '100%',
                                                background: 'linear-gradient(90deg, #4caf50, #66bb6a)',
                                                transition: 'width 0.3s ease'
                                            }}
                                        ></div>
                                    </div>
                                </div>

                                <div style={{ fontWeight: '600', color: '#555' }}>{isStreaming ? 'Bytes Committed:' : 'Bytes Received:'}</div>
                                <div style={{ color: '#333' }}>
                                    {formatBytes(bytesUploaded)} of {formatBytes(file.size || fileSize)}
                                </div>

                                {!isStreaming && (
                                    <>
                                        <div style={{ fontWeight: '600', color: '#555' }}>Remaining Chunks:</div>
                                        <div style={{ color: '#333' }}>{missingChunks.length}</div>
                                    </>
                                )}

                                <div style={{ fontWeight: '600', color: '#555' }}>Upload Method:</div>
                                <div style={{ color: '#333' }}>{getMethodName(uploadMethod)}</div>

                                <div style={{ fontWeight: '600', color: '#555' }}>Started:</div>
                                <div style={{ color: '#333' }}>{timeAgo}</div>
                            </div>
                        </div>

                        <div style={{ padding: '12px', background: '#e3f2fd', borderRadius: '6px', marginBottom: '15px', border: '1px solid #90caf9' }}>
                            <p style={{ margin: 0, fontSize: '13px', color: '#0d47a1', lineHeight: '1.5' }}>
                                💡 <strong>Resuming</strong> will {isStreaming ? `continue from ${formatBytes(bytesUploaded)}` : `upload only the remaining ${missingChunks.length} chunks`}, saving time and bandwidth.
                                <br />
                                <strong>Starting fresh</strong> will discard the progress and upload the entire file again.
                            </p>
                        </div>
                    </div>
                </div>
                <div className="dialog-footer" style={{ gap: '8px' }}>
                    <button
                        className="dialog-button dialog-button-secondary"
                        onClick={onCancel}
                        style={{ flex: '0 0 auto' }}
                    >
                        Cancel
                    </button>
                    <button
                        className="dialog-button"
                        onClick={onStartFresh}
                        style={{ flex: '0 0 auto', background: '#ff9800', color: '#fff' }}
                        title="Discard progress and upload entire file"
                    >
                        🔄 Start Fresh
                    </button>
                    <button
                        className="dialog-button dialog-button-primary"
                        onClick={onResume}
                        style={{ flex: '1 1 auto' }}
                        title={`Resume upload - ${missingChunks.length} chunks remaining`}
                    >
                        ▶️ Resume Upload
                    </button>
                </div>
            </div>
        </div>
    );
};

/**
 * FileActionModal - Shows action options for a file (Download, Edit, Share)
 */
const FileActionModal = ({ visible, file, onClose, onDownload, onEditText, onEditHex, onShare }) => {
    if (!visible || !file) return null;

    // Import getFileType from common_functions (assuming it's available)
    const getFileType = (fileName) => {
        if (!fileName) return 'binary';
        const ext = fileName.split('.').pop().toLowerCase();
        const textExts = ['txt', 'md', 'markdown', 'json', 'xml', 'html', 'htm', 'css', 'js', 'ts', 'jsx', 'tsx',
                          'py', 'java', 'c', 'cpp', 'h', 'hpp', 'cs', 'go', 'rs', 'php', 'rb', 'pl', 'sh', 'bat',
                          'ps1', 'psm1', 'psd1', 'yaml', 'yml', 'toml', 'ini', 'cfg', 'conf', 'log', 'csv', 'sql'];
        if (textExts.includes(ext)) return 'text';
        return 'binary';
    };

    const fileType = getFileType(file.name);
    const isTextFile = fileType === 'text';

    const formatBytes = (bytes) => {
        if (!bytes) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
    };

    return (
        <div className="dialog-overlay" onClick={onClose}>
            <div className="dialog-box file-action-modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: '500px' }}>
                <div className="dialog-header">
                    <h3>📄 File Actions</h3>
                    <button className="dialog-close" onClick={onClose}>✕</button>
                </div>
                <div className="dialog-body">
                    <div className="file-info" style={{ marginBottom: '20px', padding: '15px', background: '#f5f5f5', borderRadius: '8px' }}>
                        <div style={{ display: 'grid', gridTemplateColumns: 'auto 1fr', gap: '10px', fontSize: '13px' }}>
                            <div style={{ fontWeight: '600', color: '#555' }}>File Name:</div>
                            <div style={{ color: '#333', wordBreak: 'break-all', fontWeight: '500' }}>{file.name}</div>

                            <div style={{ fontWeight: '600', color: '#555' }}>Size:</div>
                            <div style={{ color: '#333' }}>{formatBytes(file.size)}</div>

                            <div style={{ fontWeight: '600', color: '#555' }}>Type:</div>
                            <div style={{ color: '#333' }}>{isTextFile ? '📝 Text File' : '📦 Binary File'}</div>
                        </div>
                    </div>

                    <div className="action-buttons" style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                        <button
                            className="action-button"
                            onClick={() => { onDownload(file); onClose(); }}
                            style={{
                                padding: '12px 20px',
                                background: '#2196f3',
                                color: '#fff',
                                border: 'none',
                                borderRadius: '6px',
                                fontSize: '14px',
                                fontWeight: '500',
                                cursor: 'pointer',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                gap: '8px',
                                transition: 'background 0.2s'
                            }}
                            onMouseOver={(e) => e.currentTarget.style.background = '#1976d2'}
                            onMouseOut={(e) => e.currentTarget.style.background = '#2196f3'}
                        >
                            <span style={{ fontSize: '18px' }}>📥</span>
                            <span>Download</span>
                        </button>

                        {isTextFile && onEditText && (
                            <button
                                className="action-button"
                                onClick={() => { onEditText(file); onClose(); }}
                                style={{
                                    padding: '12px 20px',
                                    background: '#4caf50',
                                    color: '#fff',
                                    border: 'none',
                                    borderRadius: '6px',
                                    fontSize: '14px',
                                    fontWeight: '500',
                                    cursor: 'pointer',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    gap: '8px',
                                    transition: 'background 0.2s'
                                }}
                                onMouseOver={(e) => e.currentTarget.style.background = '#388e3c'}
                                onMouseOut={(e) => e.currentTarget.style.background = '#4caf50'}
                            >
                                <span style={{ fontSize: '18px' }}>📝</span>
                                <span>Edit as Text</span>
                            </button>
                        )}

                        {onEditHex && (
                            <button
                                className="action-button"
                                onClick={() => { onEditHex(file); onClose(); }}
                                style={{
                                    padding: '12px 20px',
                                    background: '#ff9800',
                                    color: '#fff',
                                    border: 'none',
                                    borderRadius: '6px',
                                    fontSize: '14px',
                                    fontWeight: '500',
                                    cursor: 'pointer',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    gap: '8px',
                                    transition: 'background 0.2s'
                                }}
                                onMouseOver={(e) => e.currentTarget.style.background = '#f57c00'}
                                onMouseOut={(e) => e.currentTarget.style.background = '#ff9800'}
                            >
                                <span style={{ fontSize: '18px' }}>🔢</span>
                                <span>Edit as Hex</span>
                            </button>
                        )}

                        {onShare && (
                            <button
                                className="action-button"
                                onClick={() => { onShare(file); onClose(); }}
                                style={{
                                    padding: '12px 20px',
                                    background: '#9c27b0',
                                    color: '#fff',
                                    border: 'none',
                                    borderRadius: '6px',
                                    fontSize: '14px',
                                    fontWeight: '500',
                                    cursor: 'pointer',
                                    display: 'flex',
                                    alignItems: 'center',
                                    justifyContent: 'center',
                                    gap: '8px',
                                    transition: 'background 0.2s'
                                }}
                                onMouseOver={(e) => e.currentTarget.style.background = '#7b1fa2'}
                                onMouseOut={(e) => e.currentTarget.style.background = '#9c27b0'}
                            >
                                <span style={{ fontSize: '18px' }}>🔗</span>
                                <span>Share</span>
                            </button>
                        )}
                    </div>
                </div>
                <div className="dialog-footer">
                    <button
                        className="dialog-button dialog-button-secondary"
                        onClick={onClose}
                        style={{ width: '100%' }}
                    >
                        Cancel
                    </button>
                </div>
            </div>
        </div>
    );
};

/**
 * FileReselectionModal - Prompts user to re-select a file for resuming transfer
 */
const FileReselectionModal = ({ visible, transfer, onFileSelected, onCancel }) => {
    const fileInputRef = React.useRef(null);

    if (!visible || !transfer) return null;

    const formatBytes = (bytes) => {
        if (!bytes) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + sizes[i];
    };

    const handleFileSelect = (event) => {
        const file = event.target.files[0];
        if (!file) return;

        // Validate file name matches
        if (file.name !== transfer.fileName) {
            alert(`File name mismatch!\n\nExpected: ${transfer.fileName}\nSelected: ${file.name}\n\nPlease select the correct file.`);
            return;
        }

        // Validate file size matches
        if (file.size !== transfer.fileSize) {
            alert(`File size mismatch!\n\nExpected: ${formatBytes(transfer.fileSize)}\nSelected: ${formatBytes(file.size)}\n\nPlease select the correct file.`);
            return;
        }

        // File validated, proceed with resume
        onFileSelected(file);
    };

    return (
        <div className="dialog-overlay" onClick={onCancel}>
            <div className="dialog-box file-reselection-modal" onClick={(e) => e.stopPropagation()} style={{ maxWidth: '600px' }}>
                <div className="dialog-header">
                    <h3>📂 File Re-selection Required</h3>
                    <button className="dialog-close" onClick={onCancel}>✕</button>
                </div>
                <div className="dialog-body">
                    <div style={{ marginBottom: '20px' }}>
                        <p style={{ marginBottom: '15px', color: '#d32f2f', fontSize: '14px', lineHeight: '1.6' }}>
                            ⚠️ <strong>File Not Accessible</strong><br />
                            The browser cannot access the previously selected file. This happens when you refresh the page or close and reopen the browser.
                        </p>

                        <div style={{ padding: '15px', background: '#e3f2fd', borderRadius: '8px', marginBottom: '20px', border: '1px solid #90caf9' }}>
                            <p style={{ margin: '0 0 10px 0', fontSize: '13px', color: '#0d47a1', fontWeight: '600' }}>
                                💡 To resume this transfer, please re-select the same file:
                            </p>
                            <div style={{ background: '#fff', padding: '12px', borderRadius: '6px', fontSize: '13px' }}>
                                <div style={{ display: 'grid', gridTemplateColumns: '120px 1fr', gap: '8px', marginBottom: '8px' }}>
                                    <div style={{ fontWeight: '600', color: '#555' }}>File Name:</div>
                                    <div style={{ color: '#333', wordBreak: 'break-all', fontFamily: 'monospace', background: '#f5f5f5', padding: '4px 8px', borderRadius: '4px' }}>
                                        {transfer.fileName}
                                    </div>

                                    <div style={{ fontWeight: '600', color: '#555' }}>Expected Size:</div>
                                    <div style={{ color: '#333', fontFamily: 'monospace' }}>{formatBytes(transfer.fileSize)}</div>

                                    <div style={{ fontWeight: '600', color: '#555' }}>Progress:</div>
                                    <div style={{ color: '#2e7d32', fontWeight: '600' }}>
                                        {Math.round(transfer.progress || 0)}% ({formatBytes(transfer.bytesTransferred || 0)} uploaded)
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div style={{ padding: '12px', background: '#fff3e0', borderRadius: '6px', marginBottom: '20px', border: '1px solid #ffb74d' }}>
                            <p style={{ margin: 0, fontSize: '13px', color: '#e65100', lineHeight: '1.5' }}>
                                <strong>Important:</strong> The file you select must be <strong>exactly the same</strong> file (same name and size).
                                If you select a different file, the resume will fail.
                            </p>
                        </div>

                        <input
                            ref={fileInputRef}
                            type="file"
                            style={{ display: 'none' }}
                            onChange={handleFileSelect}
                            accept="*/*"
                        />
                    </div>
                </div>
                <div className="dialog-footer" style={{ gap: '8px' }}>
                    <button
                        className="dialog-button dialog-button-secondary"
                        onClick={onCancel}
                        style={{ flex: '0 0 auto' }}
                    >
                        Cancel
                    </button>
                    <button
                        className="dialog-button dialog-button-primary"
                        onClick={() => fileInputRef.current?.click()}
                        style={{ flex: '1 1 auto' }}
                    >
                        📂 Select File to Resume
                    </button>
                </div>
            </div>
        </div>
    );
};

/**
 * TransferMetadataModal - Shows detailed transfer information
 */
const TransferMetadataModal = ({ visible, transfer, onClose }) => {
    if (!visible || !transfer) return null;

    const formatDuration = (ms) => {
        const seconds = Math.floor(ms / 1000);
        if (seconds < 60) return `${seconds}s`;
        const minutes = Math.floor(seconds / 60);
        const remainingSeconds = seconds % 60;
        return `${minutes}m ${remainingSeconds}s`;
    };

    const formatBytes = (bytes) => {
        if (bytes === 0) return '0 B';
        const k = 1024;
        const sizes = ['B', 'KB', 'MB', 'GB'];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`;
    };

    const metadata = transfer.metadata || {};
    const duration = Date.now() - (transfer.startTime || Date.now());

    return (
        <div className="dialog-overlay" onClick={onClose}>
            <div className="dialog-box transfer-metadata-modal" onClick={(e) => e.stopPropagation()}>
                <div className="dialog-header">
                    <h3>Transfer Details</h3>
                    <button className="dialog-close" onClick={onClose}>✕</button>
                </div>
                <div className="dialog-body">
                    <div className="metadata-section">
                        <h4>File Information</h4>
                        <table className="metadata-table">
                            <tbody>
                                <tr>
                                    <td className="metadata-label">File Name:</td>
                                    <td className="metadata-value">{transfer.fileName}</td>
                                </tr>
                                <tr>
                                    <td className="metadata-label">File Size:</td>
                                    <td className="metadata-value">{formatBytes(transfer.fileSize)}</td>
                                </tr>
                                <tr>
                                    <td className="metadata-label">Transfer Type:</td>
                                    <td className="metadata-value">{transfer.type === 'upload' ? '↑ Upload' : '↓ Download'}</td>
                                </tr>
                                <tr>
                                    <td className="metadata-label">Status:</td>
                                    <td className="metadata-value">{transfer.status}</td>
                                </tr>
                                {transfer.targetPath ? (
                                    <tr>
                                        <td className="metadata-label">Target Path:</td>
                                        <td className="metadata-value" style={{ wordBreak: 'break-all' }}>{transfer.targetPath}</td>
                                    </tr>
                                ) : null}
                            </tbody>
                        </table>
                    </div>

                    {transfer.method ? (
                        <div className="metadata-section">
                            <h4>Transfer Method</h4>
                            <table className="metadata-table">
                                <tbody>
                                    <tr>
                                        <td className="metadata-label">Method:</td>
                                        <td className="metadata-value">
                                            {transfer.method === 'streaming' && '⚡ Streaming Upload'}
                                            {transfer.method === 'websocket' && '🔌 WebSocket Chunks'}
                                            {transfer.method === 'putChunks' && '📤 PUT Chunks'}
                                        </td>
                                    </tr>
                                    {metadata.uploadGuid ? (
                                        <tr>
                                            <td className="metadata-label">Upload GUID:</td>
                                            <td className="metadata-value" style={{ fontFamily: 'monospace', fontSize: '11px' }}>{metadata.uploadGuid}</td>
                                        </tr>
                                    ) : null}
                                </tbody>
                            </table>
                        </div>
                    ) : null}

                    {(metadata.chunkSize || metadata.totalChunks) ? (
                        <div className="metadata-section">
                            <h4>Chunk Information</h4>
                            <table className="metadata-table">
                                <tbody>
                                    {metadata.chunkSize ? (
                                        <tr>
                                            <td className="metadata-label">Chunk Size:</td>
                                            <td className="metadata-value">{formatBytes(metadata.chunkSize)}</td>
                                        </tr>
                                    ) : null}
                                    {metadata.totalChunks ? (
                                        <tr>
                                            <td className="metadata-label">Total Chunks:</td>
                                            <td className="metadata-value">{metadata.totalChunks}</td>
                                        </tr>
                                    ) : null}
                                    {metadata.receivedChunks !== undefined ? (
                                        <tr>
                                            <td className="metadata-label">Received Chunks:</td>
                                            <td className="metadata-value">{metadata.receivedChunks} / {metadata.totalChunks}</td>
                                        </tr>
                                    ) : null}
                                    {metadata.pipelineDepth ? (
                                        <tr>
                                            <td className="metadata-label">Pipeline Depth:</td>
                                            <td className="metadata-value">{metadata.pipelineDepth} chunks</td>
                                        </tr>
                                    ) : null}
                                </tbody>
                            </table>
                        </div>
                    ) : null}

                    <div className="metadata-section">
                        <h4>Performance</h4>
                        <table className="metadata-table">
                            <tbody>
                                <tr>
                                    <td className="metadata-label">Progress:</td>
                                    <td className="metadata-value">{transfer.progress}%</td>
                                </tr>
                                <tr>
                                    <td className="metadata-label">Bytes Transferred:</td>
                                    <td className="metadata-value">{formatBytes(transfer.bytesTransferred)} / {formatBytes(transfer.fileSize)}</td>
                                </tr>
                                {transfer.speed ? (
                                    <tr>
                                        <td className="metadata-label">Current Speed:</td>
                                        <td className="metadata-value">{formatBytes(transfer.speed * 1024 * 1024)}/s (5-sec avg)</td>
                                    </tr>
                                ) : null}
                                {transfer.speedAverage ? (
                                    <tr>
                                        <td className="metadata-label">Average Speed:</td>
                                        <td className="metadata-value">{formatBytes(transfer.speedAverage * 1024 * 1024)}/s (overall)</td>
                                    </tr>
                                ) : null}
                                <tr>
                                    <td className="metadata-label">Duration:</td>
                                    <td className="metadata-value">{formatDuration(duration)}</td>
                                </tr>
                                {transfer.eta ? (
                                    <tr>
                                        <td className="metadata-label">ETA:</td>
                                        <td className="metadata-value">
                                            {transfer.eta < 60 ? `${transfer.eta}s` : `${Math.floor(transfer.eta / 60)}m ${transfer.eta % 60}s`}
                                        </td>
                                    </tr>
                                ) : null}
                                {(metadata.retryCount !== undefined && metadata.retryCount > 0) ? (
                                    <tr>
                                        <td className="metadata-label">Retry Count:</td>
                                        <td className="metadata-value">{metadata.retryCount}</td>
                                    </tr>
                                ) : null}
                            </tbody>
                        </table>
                    </div>

                    {metadata.startTime ? (
                        <div className="metadata-section">
                            <h4>Timestamps</h4>
                            <table className="metadata-table">
                                <tbody>
                                    <tr>
                                        <td className="metadata-label">Start Time:</td>
                                        <td className="metadata-value">{new Date(metadata.startTime).toLocaleString()}</td>
                                    </tr>
                                    {metadata.lastChunkTime ? (
                                        <tr>
                                            <td className="metadata-label">Last Chunk:</td>
                                            <td className="metadata-value">{new Date(metadata.lastChunkTime).toLocaleString()}</td>
                                        </tr>
                                    ) : null}
                                </tbody>
                            </table>
                        </div>
                    ) : null}
                </div>
                <div className="dialog-footer">
                    <button className="dialog-button dialog-button-primary" onClick={onClose}>
                        Close
                    </button>
                </div>
            </div>
        </div>
    );
};

// ============================================================================
// HELPER FUNCTIONS - Temp File Detection
// ============================================================================

/**
 * Check if a filename is a temporary upload file
 * @param {string} fileName - The file name to check
 * @returns {boolean} True if this is a temp upload file
 */
const isTempUploadFile = (fileName) => {
    return /^newUploadTemp_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.tmp$/i.test(fileName);
};

/**
 * Extract upload GUID from temp file name
 * @param {string} fileName - The temp file name
 * @returns {string|null} The GUID or null if not found
 */
const extractUploadGuid = (fileName) => {
    const match = fileName.match(/^newUploadTemp_([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.tmp$/i);
    return match ? match[1] : null;
};

// ============================================================================
// MAIN COMPONENT
// ============================================================================

function FileExplorer({ cardId, cardInfo }) {
    // Disabled: Too verbose during uploads
    // logToServer(`=== COMPONENT FUNCTION CALLED ===`);
    const startTime = performance.now();

    const isMountedRef = useRef(true);

    // Tree state (incremental loading) - starts empty, loaded via useEffect
    const [treeState, setTreeState] = useState({
        nodes: []
    });
    const [treeLoading, setTreeLoading] = useState(true);

    const [expandingPath, setExpandingPath] = useState(null);
    const [selectedTreePath, setSelectedTreePath] = useState(null);
    const [currentFiles, setCurrentFiles] = useState([]);
    const [selectedFile, setSelectedFile] = useState(null);
    const [selectedFiles, setSelectedFiles] = useState([]); // Array of selected file paths for multi-select
    const [versionInfo, setVersionInfo] = useState(null);
    const [versionInfoLoading, setVersionInfoLoading] = useState(false);
    const [previewVisible, setPreviewVisible] = useState(() => {
        const saved = localStorage.getItem('fileExplorer_previewVisible');
        return saved !== null ? saved === 'true' : true; // Default: true (open)
    });
    const [toasts, setToasts] = useState([]);
    const [versionPaneHeight, setVersionPaneHeight] = useState(null); // Will be set based on card height
    const [detailsTab, setDetailsTab] = useState('info'); // 'info' or 'transfers'
    const [transfers, setTransfers] = useState([]); // Array of transfer objects
    const [settingsLoaded, setSettingsLoaded] = useState(false);

    // Column widths (in pixels, null = flex)
    const [columnWidths, setColumnWidths] = useState(() => {
        const saved = localStorage.getItem('fileExplorer_columnWidths');
        if (saved) {
            return JSON.parse(saved);
        }
        return {
            checkbox: 40,
            name: null,      // flex 2
            modified: null,  // flex 1
            size: null,      // flex 1
            type: null,      // flex 1
            actions: 80
        };
    });
    const [enabledUploadMethods, setEnabledUploadMethods] = useState(() => {
        // Load from localStorage with migration from old useWebSocket setting
        const saved = localStorage.getItem('fileExplorer_enabledUploadMethods');
        if (saved) {
            return JSON.parse(saved);
        }

        // Migration: Convert old useWebSocket setting to new format
        const oldUseWebSocket = localStorage.getItem('fileExplorer_useWebSocket');
        const defaultMethods = {
            streaming: true,   // New streaming method enabled by default
            websocket: oldUseWebSocket === null ? true : oldUseWebSocket === 'true',
            putChunks: true    // PUT chunks enabled by default
        };

        localStorage.setItem('fileExplorer_enabledUploadMethods', JSON.stringify(defaultMethods));
        return defaultMethods;
    });
    const [usePipelining, setUsePipelining] = useState(() => {
        // MIGRATION: Force default to false for existing users
        const saved = localStorage.getItem('fileExplorer_usePipelining');
        const migrated = localStorage.getItem('fileExplorer_pipelineMigrated');

        if (!migrated) {
            // First time after update - force to false and mark as migrated
            localStorage.setItem('fileExplorer_usePipelining', 'false');
            localStorage.setItem('fileExplorer_pipelineMigrated', 'true');
            window.logToServer('Migration: Disabled pipelining (was causing timeouts)', 'FileExplorer', 'Info');
            return false;
        }

        return saved === 'true'; // Default to false
    });
    const [chunkSizeMB, setChunkSizeMB] = useState(() => {
        const saved = localStorage.getItem('fileExplorer_chunkSizeMB');
        return saved ? parseInt(saved, 10) : 25; // Default 25MB (was 5MB)
    });
    const [showSettings, setShowSettings] = useState(false); // Settings dropdown visibility
    const fileUploadInputRef = useRef(null); // Reference to hidden file input
    const transferAbortControllers = useRef({}); // Map of transferId -> AbortController

    // Dialog states
    const [deleteConfirmDialog, setDeleteConfirmDialog] = useState({ visible: false, files: [] });
    const [renameDialog, setRenameDialog] = useState({
        visible: false,
        files: [],
        pattern: '',
        replacement: '',
        mode: 'wildcard',
        error: null
    });
    const [metadataModal, setMetadataModal] = useState({ visible: false, transfer: null });
    const [selectedTransfer, setSelectedTransfer] = useState(null); // Selected transfer for preview pane
    const [tempFileDialog, setTempFileDialog] = useState({ visible: false, file: null, uploadGuid: null });
    const [resumeDialog, setResumeDialog] = useState({
        visible: false,
        file: null,
        resumeData: null,
        onResume: null,
        onStartFresh: null
    });
    const [fileActionModal, setFileActionModal] = useState({ visible: false, file: null });
    const [fileSharingModal, setFileSharingModal] = useState({ visible: false, filePath: null });
    const [fileReselectionModal, setFileReselectionModal] = useState({
        visible: false,
        transfer: null,
        onFileSelected: null,
        onCancel: null
    });

    // Toast notification system
    const showToast = React.useCallback((message, type = 'info') => {
        const fnStart = performance.now();
        logToServer(`showToast START: type=${type}, message=${message}`);

        const id = Date.now() + Math.random();
        setToasts(prev => [...prev, { id, message, type }]);

        setTimeout(() => {
            setToasts(prev => prev.filter(t => t.id !== id));
        }, 5000);

        logToServer(`showToast END (${(performance.now() - fnStart).toFixed(2)}ms)`);
    }, []);

    // Persist preview visibility to localStorage
    useEffect(() => {
        localStorage.setItem('fileExplorer_previewVisible', previewVisible.toString());
    }, [previewVisible]);

    // Persist column widths to localStorage
    useEffect(() => {
        localStorage.setItem('fileExplorer_columnWidths', JSON.stringify(columnWidths));
    }, [columnWidths]);

    // Mark settings as loaded after a brief delay to ensure they're ready
    useEffect(() => {
        const timer = setTimeout(() => {
            setSettingsLoaded(true);
            logToServer(`Settings loaded: streaming=${enabledUploadMethods.streaming}, websocket=${enabledUploadMethods.websocket}, putChunks=${enabledUploadMethods.putChunks}`);
        }, 500); // 500ms delay as requested

        return () => clearTimeout(timer);
    }, [enabledUploadMethods]);

    // Load tree roots on mount
    useEffect(() => {
        const fnStart = performance.now();
        logToServer(`useEffect[mount] START - Loading tree roots`);
        isMountedRef.current = true;

        const loadRoots = async () => {
            try {
                const response = await window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/roots');

                if (!isMountedRef.current) {
                    logToServer(`loadRoots: Component unmounted, aborting`);
                    return;
                }

                if (!response.ok) {
                    throw new Error(`Failed to load roots: ${response.statusText}`);
                }

                const result = await response.json();
                logToServer(`loadRoots: Received ${result.roots?.length || 0} roots`);

                if (result.roots && Array.isArray(result.roots) && result.roots.length > 0) {
                    setTreeState({ nodes: result.roots });
                    // Select first root by default
                    setSelectedTreePath(result.roots[0].path);
                    logToServer(`loadRoots: Selected default root: ${result.roots[0].name}`);
                } else {
                    setTreeState({ nodes: [] });
                    showToast('No file locations available', 'error');
                }

                setTreeLoading(false);
            } catch (err) {
                logToServer(`loadRoots ERROR: ${err.message}`, 'Error', { error: err.toString() });
                showToast(`Failed to load file locations: ${err.message}`, 'error');
                setTreeLoading(false);
            }
        };

        loadRoots();

        logToServer(`useEffect[mount] Component mounted (${(performance.now() - fnStart).toFixed(2)}ms)`);

        return () => {
            logToServer(`useEffect[mount] CLEANUP - Component unmounting`);
            isMountedRef.current = false;
        };
    }, [showToast]);

    // Load persisted transfers on mount
    useEffect(() => {
        const loadTransfers = async () => {
            try {
                const response = await window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/transfers');

                if (!response.ok) {
                    logToServer(`loadTransfers: Failed to load (${response.statusText})`, 'Warning');
                    return;
                }

                const result = await response.json();

                if (result.data && result.data.transfers && result.data.transfers.length > 0) {
                    logToServer(`loadTransfers: Loaded ${result.data.transfers.length} persisted transfers`);

                    // Restore transfers with status changed to 'paused' (file not accessible)
                    // User will need to re-select file to resume
                    const restoredTransfers = result.data.transfers.map(t => ({
                        ...t,
                        status: 'paused', // Set to paused - file not accessible after page reload
                        startTime: Date.now() - ((t.progress || 0) / 100 * (t.fileSize / (t.speed || 1) / 1024 / 1024) * 1000),
                        error: null // Clear any errors
                    }));

                    setTransfers(restoredTransfers);
                    setDetailsTab('transfers'); // Auto-switch to transfers tab to show restored items

                    // Show informational toast
                    if (restoredTransfers.length === 1) {
                        showToast(`Restored 1 transfer - click ▶ to resume (file re-selection required)`, 'info');
                    } else {
                        showToast(`Restored ${restoredTransfers.length} transfers - click ▶ to resume (file re-selection required)`, 'info');
                    }
                }
            } catch (err) {
                logToServer(`loadTransfers ERROR: ${err.message}`, 'Error');
            }
        };

        loadTransfers();
    }, [showToast]);

    // Save transfers periodically (debounced)
    useEffect(() => {
        // Debounce save to avoid too frequent writes
        const saveTimer = setTimeout(async () => {
            // Only save if there are active or failed transfers
            const transfersToSave = transfers.filter(t =>
                t.status === 'uploading' || t.status === 'downloading' || t.status === 'failed'
            );

            if (transfersToSave.length === 0) {
                return; // Nothing to save
            }

            try {
                await window.psweb_fetchWithAuthHandling(
                    '/apps/WebhostFileExplorer/api/v1/transfers',
                    {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            transfers: transfersToSave
                        })
                    }
                );
                logToServer(`Saved ${transfersToSave.length} transfer(s) to persistence`, 'Debug');
            } catch (err) {
                logToServer(`saveTransfers ERROR: ${err.message}`, 'Warning');
            }
        }, 2000); // 2 second debounce

        return () => clearTimeout(saveTimer);
    }, [transfers]);

    // Initialize details pane height based on card height (half height initially)
    useEffect(() => {
        if (versionPaneHeight === null && cardInfo?.style?.gridRow) {
            // Extract grid row span from style (e.g., "span 20" -> 20 blocks)
            const rowMatch = cardInfo.style.gridRow.match(/span\s+(\d+)/);
            if (rowMatch) {
                const blocks = parseInt(rowMatch[1], 10);
                // Minimum 40 blocks, details pane = half of total height
                const effectiveBlocks = Math.max(blocks, 40);
                const blockHeight = 30; // Approximate block height in pixels
                const totalHeight = effectiveBlocks * blockHeight;
                const menuBarHeight = 60; // Approximate menu + toolbar height
                const contentHeight = totalHeight - menuBarHeight;
                const initialDetailsHeight = Math.floor(contentHeight / 2);
                setVersionPaneHeight(initialDetailsHeight);
                logToServer(`Details pane initialized: ${initialDetailsHeight}px (${effectiveBlocks} blocks total)`);
            }
        }
    }, [cardInfo, versionPaneHeight]);

    /**
     * Expand/collapse tree node
     */
    const handleTreeExpand = async (path, collapse = false) => {
        const fnStart = performance.now();
        logToServer(`handleTreeExpand START: path=${path}, collapse=${collapse}`);

        if (collapse) {
            logToServer(`handleTreeExpand: Collapsing node`);
            // Collapse: just update isExpanded flag
            setTreeState(prevState => {
                const updateNode = (nodes) => {
                    if (!Array.isArray(nodes)) {
                        console.warn('[handleTreeExpand:collapse] nodes is not an array:', nodes);
                        return [];
                    }
                    return nodes.map(node => {
                        if (node.path === path) {
                            return { ...node, isExpanded: false };
                        }
                        if (node.children) {
                            return { ...node, children: updateNode(node.children) };
                        }
                        return node;
                    });
                };
                return { ...prevState, nodes: updateNode(prevState.nodes) };
            });
            logToServer(`handleTreeExpand END (collapse) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        // Expand: fetch children if not already loaded
        logToServer(`handleTreeExpand: Expanding node, finding in tree...`);
        const node = findNodeByPath(treeState.nodes, path);
        logToServer(`handleTreeExpand: Found node with path=${node?.path}, hasChildren=${!!(node?.children?.length)}`);

        if (node && node.children && node.children.length > 0) {
            logToServer(`handleTreeExpand: Node has ${node.children.length} children, just expanding`);
            // Already loaded, just expand
            setTreeState(prevState => {
                const updateNode = (nodes) => {
                    if (!Array.isArray(nodes)) {
                        console.warn('[handleTreeExpand:expand] nodes is not an array:', nodes);
                        return [];
                    }
                    return nodes.map(n => {
                        if (n.path === path) {
                            return { ...n, isExpanded: true };
                        }
                        if (n.children) {
                            return { ...n, children: updateNode(n.children) };
                        }
                        return n;
                    });
                };
                return { ...prevState, nodes: updateNode(prevState.nodes) };
            });
            logToServer(`handleTreeExpand END (already loaded) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        // Fetch children from server
        logToServer(`handleTreeExpand: Fetching children from server...`);
        setExpandingPath(path);
        try {
            const fetchStart = performance.now();
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/tree',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        treeState: treeState,
                        expandPath: path
                    })
                }
            );
            logToServer(`handleTreeExpand: Fetch completed (${(performance.now() - fetchStart).toFixed(2)}ms)`);

            if (!isMountedRef.current) {
                logToServer(`handleTreeExpand: Component unmounted, aborting`);
                return;
            }

            if (!response.ok) {
                throw new Error(`Failed to expand tree: ${response.statusText}`);
            }

            const result = await response.json();
            logToServer(`handleTreeExpand: Tree expand result status=${result.status}, hasExpandedNode=${!!result.expandedNode}`);

            const expandedNode = result.expandedNode;
            logToServer(`handleTreeExpand: expandedNode has ${expandedNode.children.length} children`);

            // Update tree state with new children
            setTreeState(prevState => {
                const updateNode = (nodes) => {
                    if (!Array.isArray(nodes)) {
                        console.warn('[handleTreeExpand:fetch] nodes is not an array:', nodes);
                        return [];
                    }
                    return nodes.map(node => {
                        if (node.path === path) {
                            return {
                                ...node,
                                isExpanded: true,
                                children: expandedNode.children
                            };
                        }
                        if (node.children) {
                            return { ...node, children: updateNode(node.children) };
                        }
                        return node;
                    });
                };
                return { ...prevState, nodes: updateNode(prevState.nodes) };
            });

            // Also select the expanded folder to load its files in the center pane
            logToServer(`handleTreeExpand: Selecting expanded folder: ${path}`);
            setSelectedTreePath(path);

            logToServer(`handleTreeExpand END (success) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        } catch (err) {
            logToServer(`handleTreeExpand ERROR: ${err.message}`, 'Error', { error: err.toString(), path: path });
            showToast(`Failed to expand folder: ${err.message}`, 'error');
        } finally {
            if (isMountedRef.current) {
                setExpandingPath(null);
            }
            logToServer(`handleTreeExpand END (finally) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        }
    };

    /**
     * Select tree node
     */
    const handleTreeSelect = (path) => {
        const fnStart = performance.now();
        logToServer(`handleTreeSelect START: path=${path}`);

        setSelectedTreePath(path);
        setSelectedFile(null);
        setVersionInfo(null);

        logToServer(`handleTreeSelect END (${(performance.now() - fnStart).toFixed(2)}ms)`);
    };

    /**
     * Load folder contents for center pane
     */
    const loadFolderContents = React.useCallback(async (folderPath) => {
        const fnStart = performance.now();
        logToServer(`loadFolderContents START: folderPath=${folderPath}`);

        // Check cache first
        const cached = fileDetailsCache.get(folderPath);
        if (cached) {
            logToServer(`loadFolderContents: Using cached folder contents (${cached.data.length} items)`);
            setCurrentFiles(cached.data);
            logToServer(`loadFolderContents END (cached) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        try {
            // Extract logical path from full path
            const logicalPath = folderPath.split('|')[2] || folderPath;
            const url = `/apps/WebhostFileExplorer/api/v1/files?path=${encodeURIComponent(logicalPath)}`;

            logToServer(`loadFolderContents: Fetching ${url}`);
            const fetchStart = performance.now();
            const response = await window.psweb_fetchWithAuthHandling(url);
            logToServer(`loadFolderContents: Fetch completed (${(performance.now() - fetchStart).toFixed(2)}ms)`);

            if (!isMountedRef.current) {
                logToServer(`loadFolderContents: Component unmounted, aborting`);
                return;
            }

            if (!response.ok) {
                throw new Error(`Failed to load folder: ${response.statusText}`);
            }

            const result = await response.json();
            logToServer(`loadFolderContents: Received response status=${result.status}, childrenCount=${result.children?.length || 0}`);

            // Ensure children is always an array
            const files = Array.isArray(result.children) ? result.children : [];
            logToServer(`loadFolderContents: Setting ${files.length} files to currentFiles`);

            // Cache result
            fileDetailsCache.set(folderPath, files);
            setCurrentFiles(files);

            logToServer(`loadFolderContents END (success) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        } catch (err) {
            logToServer(`loadFolderContents ERROR: ${err.message}`, 'Error', { error: err.toString(), folderPath: folderPath });
            showToast(`Failed to load folder: ${err.message}`, 'error');
            setCurrentFiles([]);
            logToServer(`loadFolderContents END (error) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        }
    }, [showToast]);

    // Load folder contents when selectedTreePath changes
    useEffect(() => {
        if (!selectedTreePath) {
            logToServer(`useEffect[selectedTreePath] SKIP: No path selected yet`);
            return;
        }

        const fnStart = performance.now();
        logToServer(`useEffect[selectedTreePath] START: selectedTreePath=${selectedTreePath}`);
        loadFolderContents(selectedTreePath);
        logToServer(`useEffect[selectedTreePath] END (${(performance.now() - fnStart).toFixed(2)}ms)`);
    }, [selectedTreePath, loadFolderContents]);

    // Disabled: Too verbose during uploads
    // useEffect(() => {
    //     logToServer(`=== RENDER COMPLETE ===`);
    // });

    /**
     * Select file in center pane
     */
    const handleFileSelect = async (file) => {
        const fnStart = performance.now();
        logToServer(`handleFileSelect START: file=${file.name}, type=${file.type}`);

        setSelectedFile(file);

        // Only load VersionInfo for files (not folders)
        if (file.type !== 'file') {
            logToServer(`handleFileSelect: Not a file, skipping VersionInfo`);
            setVersionInfo(null);
            logToServer(`handleFileSelect END (not a file) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        // Check cache first
        const cached = versionInfoCache.get(file.path);
        if (cached) {
            logToServer(`handleFileSelect: Using cached version info`);
            setVersionInfo(cached.data);
            logToServer(`handleFileSelect END (cached) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        // Fetch from backend
        logToServer(`handleFileSelect: Fetching VersionInfo from backend...`);
        setVersionInfoLoading(true);
        try {
            // VersionInfo endpoint expects full path format (local|localhost|LogicalPath)
            const url = `/apps/WebhostFileExplorer/api/v1/versioninfo?path=${encodeURIComponent(file.path)}`;
            const fetchStart = performance.now();
            const response = await window.psweb_fetchWithAuthHandling(url);
            logToServer(`handleFileSelect: Fetch completed (${(performance.now() - fetchStart).toFixed(2)}ms)`);

            if (!isMountedRef.current) {
                logToServer(`handleFileSelect: Component unmounted, aborting`);
                return;
            }

            if (!response.ok) {
                throw new Error(`Failed to load version info: ${response.statusText}`);
            }

            const result = await response.json();
            logToServer(`handleFileSelect: VersionInfo received`);

            // Cache result
            versionInfoCache.set(file.path, result.versionInfo);
            setVersionInfo(result.versionInfo);

            logToServer(`handleFileSelect END (success) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        } catch (err) {
            logToServer(`handleFileSelect ERROR: ${err.message}`, 'Error', { error: err.toString(), file: file.name });
            showToast(`Failed to load file info: ${err.message}`, 'error');
            setVersionInfo(null);
            logToServer(`handleFileSelect END (error) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        } finally {
            if (isMountedRef.current) {
                setVersionInfoLoading(false);
            }
        }
    };

    /**
     * Handle clicking on a transfer to show in preview pane
     */
    const handleTransferClick = (transfer) => {
        setSelectedTransfer(transfer);
        setDetailsTab('transfers'); // Ensure transfers tab is active
        setPreviewVisible(true); // Ensure preview pane is visible
    };

    /**
     * Toggle selection of a single file/folder
     */
    const handleToggleSelect = (filePath) => {
        setSelectedFiles(prev => {
            if (prev.includes(filePath)) {
                return prev.filter(p => p !== filePath);
            } else {
                return [...prev, filePath];
            }
        });
    };

    /**
     * Toggle select all files in current folder
     */
    const handleToggleSelectAll = (checked) => {
        if (checked) {
            setSelectedFiles(currentFiles.map(f => f.path));
        } else {
            setSelectedFiles([]);
        }
    };

    /**
     * Clear all selections
     */
    const handleClearSelections = () => {
        setSelectedFiles([]);
    };

    /**
     * Double-click file (expand folder or open file)
     */
    const handleFileDoubleClick = (file) => {
        const fnStart = performance.now();
        logToServer(`handleFileDoubleClick START: file=${file.name}, type=${file.type}`);

        // Check if this is a temp upload file
        if (file.type === 'file' && isTempUploadFile(file.name)) {
            logToServer(`handleFileDoubleClick: Temp upload file detected`);
            handleTempFileClick(file);
            logToServer(`handleFileDoubleClick END (temp file) (${(performance.now() - fnStart).toFixed(2)}ms)`);
            return;
        }

        if (file.type === 'folder') {
            logToServer(`handleFileDoubleClick: Navigating into folder`);
            // Navigate into folder
            setSelectedTreePath(file.path);
        } else {
            // Show file action modal with options (Download, Edit, Share)
            logToServer(`handleFileDoubleClick: Showing file action modal for ${file.name}`);
            setFileActionModal({ visible: true, file: file });
        }

        logToServer(`handleFileDoubleClick END (${(performance.now() - fnStart).toFixed(2)}ms)`);
    };

    /**
     * Handle temp file click - show dialog with options
     */
    const handleTempFileClick = (file) => {
        const guid = extractUploadGuid(file.name);
        if (!guid) {
            showToast('Unable to extract upload ID from temp file', 'error');
            return;
        }

        logToServer(`handleTempFileClick: Temp file clicked, GUID=${guid}`);

        // Check if this GUID matches an active transfer
        const activeTransfer = transfers.find(t => t.metadata?.uploadGuid === guid);

        if (activeTransfer) {
            logToServer(`handleTempFileClick: Found active transfer for GUID=${guid}`);
            // Show the temp file dialog with view transfer option
            setTempFileDialog({
                visible: true,
                file: file,
                uploadGuid: guid,
                activeTransfer: activeTransfer
            });
        } else {
            logToServer(`handleTempFileClick: No active transfer found for GUID=${guid} (orphaned upload)`);
            // Show the temp file dialog without view transfer option (orphaned upload)
            setTempFileDialog({
                visible: true,
                file: file,
                uploadGuid: guid,
                activeTransfer: null
            });
        }
    };

    /**
     * Upload file with chunking
     */
    /**
     * Upload file via WebSocket (binary streaming)
     */
    const uploadViaWebSocket = useCallback(async (file, guid, transferId, abortController, chunkSize, totalChunks, enablePipelining = false) => {
        return new Promise((resolve, reject) => {
            // Convert http:// or https:// to ws:// or wss://
            const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
            const wsUrl = `${protocol}//${window.location.host}/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=${guid}`;

            logToServer(`uploadViaWebSocket: Connecting to ${wsUrl}`);
            logTransferAction('upload_start_websocket', { fileName: file.name, fileSize: file.size, method: 'websocket', guid, totalChunks, pipelineEnabled: enablePipelining });

            const ws = new WebSocket(wsUrl);
            ws.binaryType = 'arraybuffer';

            let currentChunkIndex = 0;
            let isComplete = false;
            let lastProgressLogTime = 0;
            let firstChunkConfirmed = false;
            let firstChunkTimeout = null;

            // Check for cancellation periodically
            const cancelCheckInterval = setInterval(() => {
                if (abortController.signal.aborted && ws.readyState === WebSocket.OPEN) {
                    logToServer(`uploadViaWebSocket: Cancellation detected, closing WebSocket`);
                    ws.close(1000, 'Upload cancelled');
                    clearInterval(cancelCheckInterval);
                }
            }, 100);

            // Chunk ACK tracking for pipelined uploads
            const pendingChunks = new Map();  // chunkIndex -> { resolve, reject, timeoutId }
            let currentAckResolver = null; // For serial mode ACK tracking

            ws.onopen = async () => {
                logToServer(`uploadViaWebSocket: WebSocket connection established (pipelining: ${enablePipelining})`);

                let lastLogTime = Date.now();

                try {
                    if (enablePipelining) {
                        // PIPELINED MODE: Multiple chunks in-flight
                        const MAX_IN_FLIGHT = 5;

                        const sendChunk = async (chunkIndex) => {
                            // Register promise BEFORE sending to avoid race condition
                            const chunkPromise = new Promise((res, rej) => {
                                const timeoutId = setTimeout(() => {
                                    pendingChunks.delete(chunkIndex);
                                    logToServer(`uploadViaWebSocket: Timeout for chunk ${chunkIndex}`, 'Error');
                                    rej(new Error(`Progress response timeout (60s) for chunk ${chunkIndex}`));
                                }, 60000);

                                pendingChunks.set(chunkIndex, { resolve: res, reject: rej, timeoutId });
                            });

                            const start = chunkIndex * chunkSize;
                            const end = Math.min(start + chunkSize, file.size);
                            const chunk = file.slice(start, end);
                            const bytesRemaining = file.size - end;

                            const metadata = JSON.stringify({
                                type: 'chunk',
                                chunkNumber: chunkIndex,
                                bytesRemaining: Math.max(0, bytesRemaining)
                            });

                            if (Date.now() - lastLogTime >= 15000 || chunkIndex === 0) {
                                logToServer(`uploadViaWebSocket: Sending chunk ${chunkIndex}/${totalChunks}`);
                                lastLogTime = Date.now();
                            }

                            // Set up 10-second timeout for first chunk confirmation
                            if (chunkIndex === 0) {
                                firstChunkTimeout = setTimeout(() => {
                                    if (!firstChunkConfirmed) {
                                        const errorMsg = 'First chunk confirmation timeout - no response within 10 seconds';
                                        logToServer(errorMsg, 'Error');
                                        logTransferAction('upload_timeout', { fileName: file.name, method: 'websocket', guid, chunkIndex: 0, timeoutSeconds: 10 }, 'Error');
                                        ws.close(1000, 'First chunk timeout');
                                        abortController.abort();
                                    }
                                }, 10000);

                                logTransferAction('first_chunk_sent', { fileName: file.name, method: 'websocket', guid, pipelineEnabled: enablePipelining });
                            }

                            ws.send(metadata);
                            const chunkData = await chunk.arrayBuffer();
                            ws.send(chunkData);

                            return chunkPromise;
                        };

                        const inflightPromises = [];
                        for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
                            if (abortController.signal.aborted) throw new Error('Upload cancelled by user');
                            currentChunkIndex = chunkIndex;

                            const chunkPromise = sendChunk(chunkIndex);
                            inflightPromises.push(chunkPromise);

                            if (inflightPromises.length >= MAX_IN_FLIGHT) {
                                await inflightPromises.shift();
                            }
                            if (isComplete) break;
                        }

                        if (!isComplete && inflightPromises.length > 0) {
                            await Promise.all(inflightPromises);
                        }
                    } else {
                        // SERIAL MODE: One chunk at a time (simpler, less overhead)
                        logToServer(`uploadViaWebSocket: Using serial mode (no pipelining)`);

                        for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
                            if (abortController.signal.aborted) throw new Error('Upload cancelled by user');
                            currentChunkIndex = chunkIndex;

                            const start = chunkIndex * chunkSize;
                            const end = Math.min(start + chunkSize, file.size);
                            const chunk = file.slice(start, end);
                            const bytesRemaining = file.size - end;

                            const metadata = JSON.stringify({
                                type: 'chunk',
                                chunkNumber: chunkIndex,
                                bytesRemaining: Math.max(0, bytesRemaining)
                            });

                            if (Date.now() - lastLogTime >= 15000 || chunkIndex === 0) {
                                logToServer(`uploadViaWebSocket: Sending chunk ${chunkIndex}/${totalChunks}`);
                                lastLogTime = Date.now();
                            }

                            // Set up 10-second timeout for first chunk confirmation (serial mode)
                            if (chunkIndex === 0) {
                                firstChunkTimeout = setTimeout(() => {
                                    if (!firstChunkConfirmed) {
                                        const errorMsg = 'First chunk confirmation timeout - no response within 10 seconds (serial mode)';
                                        logToServer(errorMsg, 'Error');
                                        logTransferAction('upload_timeout', { fileName: file.name, method: 'websocket', guid, chunkIndex: 0, timeoutSeconds: 10, mode: 'serial' }, 'Error');
                                        ws.close(1000, 'First chunk timeout');
                                        abortController.abort();
                                    }
                                }, 10000);

                                logTransferAction('first_chunk_sent', { fileName: file.name, method: 'websocket', guid, mode: 'serial' });
                            }

                            // Send metadata and binary chunk
                            ws.send(metadata);
                            const chunkData = await chunk.arrayBuffer();
                            ws.send(chunkData);

                            // Wait for ACK before sending next chunk
                            await new Promise((res, rej) => {
                                currentAckResolver = { resolve: res, reject: rej };
                                setTimeout(() => {
                                    if (currentAckResolver) {
                                        currentAckResolver = null;
                                        rej(new Error(`Progress timeout for chunk ${chunkIndex}`));
                                    }
                                }, 60000);
                            });

                            if (isComplete) break;
                        }
                    }

                } catch (err) {
                    logToServer(`uploadViaWebSocket: Upload loop error: ${err.message}`, 'Error');
                    ws.close(1000, 'Upload error');
                    clearInterval(cancelCheckInterval);
                    reject(err);
                }
            };

            ws.onmessage = (event) => {
                try {
                    const message = JSON.parse(event.data);

                    if (message.type === 'progress') {
                        // Log once per 15 seconds (time-based throttle)
                        const now = Date.now();
                        if (now - lastProgressLogTime >= 15000 || message.complete || lastProgressLogTime === 0) {
                            logToServer(`uploadViaWebSocket: Progress update - ${message.receivedChunks}/${message.totalChunks} chunks (${Math.round((message.receivedChunks / message.totalChunks) * 100)}%)`);
                            lastProgressLogTime = now;
                        }

                        // Update transfer progress with dual speeds and ETA
                        const progress = Math.round((message.receivedChunks / message.totalChunks) * 100);
                        setTransfers(prev => prev.map(t => {
                            if (t.id === transferId) {
                                const bytesTransferred = message.receivedBytes || (message.receivedChunks * chunkSize);
                                const speeds = calculateTransferSpeeds(t, bytesTransferred);
                                const remainingBytes = t.fileSize - bytesTransferred;
                                const eta = speeds.speedCurrent > 0 ? remainingBytes / (speeds.speedCurrent * 1024 * 1024) : null;

                                return {
                                    ...t,
                                    progress,
                                    currentChunk: message.receivedChunks,
                                    bytesTransferred,
                                    speed: speeds.speedCurrent,
                                    speedAverage: speeds.speedAverage,
                                    speedHistory: speeds.speedHistory,
                                    eta: eta ? Math.ceil(eta) : null
                                };
                            }
                            return t;
                        }));

                        // First chunk confirmed - clear timeout
                        if (message.chunkNumber === 0 && !firstChunkConfirmed) {
                            if (firstChunkTimeout) {
                                clearTimeout(firstChunkTimeout);
                                firstChunkConfirmed = true;
                                const elapsedMs = Date.now() - (message.receivedChunks > 0 ? Date.now() - 10000 : Date.now());
                                logTransferAction('first_chunk_confirmed', { fileName: file.name, method: 'websocket', guid, elapsedMs, mode: enablePipelining ? 'pipelined' : 'serial' });
                            }
                        }

                        // Resolve the pending chunk ACK
                        if (enablePipelining) {
                            // Pipelined mode: use pendingChunks map
                            if (message.chunkNumber !== undefined) {
                                const pending = pendingChunks.get(message.chunkNumber);
                                if (pending) {
                                    logToServer(`uploadViaWebSocket: PIPELINED - Resolved chunk ${message.chunkNumber}`, 'Debug');
                                    clearTimeout(pending.timeoutId);
                                    pending.resolve();
                                    pendingChunks.delete(message.chunkNumber);
                                } else {
                                    logToServer(`uploadViaWebSocket: PIPELINED - No pending promise for chunk ${message.chunkNumber}`, 'Warning');
                                }
                            }
                        } else {
                            // Serial mode: use currentAckResolver
                            logToServer(`uploadViaWebSocket: SERIAL - Resolving ACK (resolver exists: ${!!currentAckResolver})`, 'Debug');
                            if (currentAckResolver) {
                                currentAckResolver.resolve();
                                currentAckResolver = null;
                            } else {
                                logToServer(`uploadViaWebSocket: SERIAL - No currentAckResolver set!`, 'Warning');
                            }
                        }

                        // Check if complete
                        if (message.complete) {
                            logToServer(`uploadViaWebSocket: Upload complete`);
                            isComplete = true;
                            ws.close(1000, 'Upload complete');
                            clearInterval(cancelCheckInterval);
                            resolve();
                        }
                    } else if (message.type === 'complete') {
                        logToServer(`uploadViaWebSocket: Completion message received`);
                        isComplete = true;
                        ws.close(1000, 'Upload complete');
                        clearInterval(cancelCheckInterval);
                        resolve();
                    } else if (message.type === 'error') {
                        logToServer(`uploadViaWebSocket: Server error: ${message.message}`, 'Error');
                        ws.close(1000, 'Server error');
                        clearInterval(cancelCheckInterval);
                        reject(new Error(message.message));
                    }
                } catch (err) {
                    logToServer(`uploadViaWebSocket: Message parse error: ${err.message}`, 'Error');
                }
            };

            ws.onerror = (error) => {
                logToServer(`uploadViaWebSocket: WebSocket error`, 'Error', { error: error.toString() });
                clearInterval(cancelCheckInterval);
                reject(new Error('WebSocket connection error'));
            };

            ws.onclose = (event) => {
                logToServer(`uploadViaWebSocket: WebSocket closed (code: ${event.code}, reason: ${event.reason})`);
                clearInterval(cancelCheckInterval);
                if (!isComplete && !abortController.signal.aborted) {
                    reject(new Error('WebSocket connection closed unexpectedly'));
                }
            };
        });
    }, []);

    /**
     * Upload file via PUT chunks (binary transfer - fallback method)
     */
    const uploadViaPutChunks = useCallback(async (file, guid, transferId, abortController, chunkSize, totalChunks) => {
        logToServer(`uploadViaPutChunks: Starting PUT chunk upload`);
        logTransferAction('upload_start_put', { fileName: file.name, fileSize: file.size, method: 'putChunks', guid, totalChunks });

        let lastLogTime = Date.now();
        let firstChunkConfirmed = false;
        let firstChunkTimeout = null;

        for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
            // Check if upload was cancelled
            if (abortController.signal.aborted) {
                logToServer(`uploadViaPutChunks: Upload cancelled by user - ${file.name}`);
                throw new Error('Upload cancelled by user');
            }

            const start = chunkIndex * chunkSize;
            const end = Math.min(start + chunkSize, file.size);
            const chunk = file.slice(start, end);
            const chunkDataSize = chunk.size;
            const bytesRemaining = file.size - end;

            // Create binary header (10 bytes)
            const header = new ArrayBuffer(10);
            const headerView = new DataView(header);

            // Bytes 0-1: Constant value (random generation disabled for speed)
            headerView.setUint16(0, 0, true); // little-endian

            // Bytes 2-5: Chunk number uint32
            headerView.setUint32(2, chunkIndex, true); // little-endian

            // Bytes 6-9: Bytes remaining uint32
            headerView.setUint32(6, bytesRemaining, true); // little-endian

            // Combine header + chunk data
            const chunkArrayBuffer = await chunk.arrayBuffer();
            const binaryData = new Uint8Array(10 + chunkDataSize);
            binaryData.set(new Uint8Array(header), 0);
            binaryData.set(new Uint8Array(chunkArrayBuffer), 10);

            // Log once per 15 seconds (time-based throttle)
            const now = Date.now();
            if (now - lastLogTime >= 15000 || chunkIndex === 0) {
                logToServer(`uploadViaPutChunks: Sending chunk ${chunkIndex}/${totalChunks} (${Math.round((chunkIndex / totalChunks) * 100)}%)`);
                lastLogTime = now;
            }

            // Send binary chunk via PUT
            const uploadUrl = `/apps/WebhostFileExplorer/api/v1/files/upload-chunk?guid=${guid}`;

            // Set up 10-second timeout for first chunk confirmation
            if (chunkIndex === 0) {
                firstChunkTimeout = setTimeout(() => {
                    if (!firstChunkConfirmed) {
                        const errorMsg = 'First chunk confirmation timeout - no response within 10 seconds';
                        logToServer(errorMsg, 'Error');
                        logTransferAction('upload_timeout', { fileName: file.name, method: 'putChunks', guid, chunkIndex: 0, timeoutSeconds: 10 }, 'Error');
                        abortController.abort();
                    }
                }, 10000);

                logTransferAction('first_chunk_sent', { fileName: file.name, method: 'putChunks', guid, chunkSize: chunkDataSize });
            }

            const response = await window.psweb_fetchWithAuthHandling(
                uploadUrl,
                {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/octet-stream' },
                    body: binaryData,
                    signal: abortController.signal
                }
            );

            if (!response.ok) {
                if (firstChunkTimeout) clearTimeout(firstChunkTimeout);
                throw new Error(`Chunk upload failed: ${response.statusText}`);
            }

            const result = await response.json();

            // First chunk confirmed - clear timeout
            if (chunkIndex === 0 && firstChunkTimeout) {
                clearTimeout(firstChunkTimeout);
                firstChunkConfirmed = true;
                logTransferAction('first_chunk_confirmed', { fileName: file.name, method: 'putChunks', guid, elapsedMs: Date.now() - now });
            }

            // Update progress with dual speeds and ETA
            const progress = Math.round(((chunkIndex + 1) / totalChunks) * 100);
            setTransfers(prev => prev.map(t => {
                if (t.id === transferId) {
                    const bytesTransferred = (chunkIndex + 1) * chunkSize;
                    const speeds = calculateTransferSpeeds(t, bytesTransferred);
                    const remainingBytes = t.fileSize - bytesTransferred;
                    const eta = speeds.speedCurrent > 0 ? remainingBytes / (speeds.speedCurrent * 1024 * 1024) : null;

                    return {
                        ...t,
                        progress,
                        currentChunk: chunkIndex + 1,
                        bytesTransferred,
                        speed: speeds.speedCurrent,
                        speedAverage: speeds.speedAverage,
                        speedHistory: speeds.speedHistory,
                        eta: eta ? Math.ceil(eta) : null
                    };
                }
                return t;
            }));

            if (result.data && result.data.complete) {
                logToServer(`uploadViaPutChunks: Upload complete`);
                logTransferAction('upload_complete', { fileName: file.name, fileSize: file.size, method: 'putChunks', guid, totalChunks });
                return;
            }
        }

        logTransferAction('upload_complete', { fileName: file.name, fileSize: file.size, method: 'putChunks', guid, totalChunks });
    }, []);

    /**
     * Upload file via streaming (single request, no chunking, fastest method)
     * Sends entire file in one HTTP PUT request, server reads incrementally
     */
    const uploadViaStreaming = useCallback(async (file, transferId, targetPath, abortController, resumeGuid = null) => {
        logToServer(`uploadViaStreaming: Starting streaming upload of ${file.name} (${file.size} bytes)${resumeGuid ? ' (RESUME)' : ''}`);
        logTransferAction('upload_start_streaming', { fileName: file.name, fileSize: file.size, method: 'streaming', targetPath, resumeGuid });

        try {
            // Step 1: Initialize upload session (with optional resume GUID)
            const initResponse = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files/upload-stream',
                {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        fileName: file.name,
                        fileSize: file.size,
                        targetPath: targetPath,
                        resumeGuid: resumeGuid  // Include resume GUID if provided
                    }),
                    signal: abortController.signal
                }
            );

            if (!initResponse.ok) {
                const error = await initResponse.json();
                throw new Error(`Streaming upload init failed: ${error.message || initResponse.statusText}`);
            }

            const initResult = await initResponse.json();
            const uploadGuid = initResult.data.guid;
            let startOffset = initResult.data.startOffset || 0;
            const bytesReceived = initResult.data.bytesReceived || 0;

            // CRITICAL FIX: Override startOffset if we have validated bytes from progressive hash validation
            // The server reports the full temp file size, but hash validation may have found corruption
            // In that case, we need to resume from the end of the last validated range, not the end of the file
            if (window.pendingResumeUpload &&
                window.pendingResumeUpload.uploadGuid === uploadGuid &&
                typeof window.pendingResumeUpload.validatedBytes === 'number') {

                const validatedBytes = window.pendingResumeUpload.validatedBytes;
                logToServer(`uploadViaStreaming: Progressive hash validation found ${validatedBytes} validated bytes, overriding server startOffset ${startOffset}`);
                startOffset = validatedBytes;

                // Clear pendingResumeUpload now that we've used the validatedBytes
                delete window.pendingResumeUpload;
            }

            logToServer(`uploadViaStreaming: Session initialized with GUID ${uploadGuid}, startOffset: ${startOffset}`);

            // Step 2: Stream file data
            const uploadUrl = `/apps/WebhostFileExplorer/api/v1/files/upload-stream?guid=${uploadGuid}`;

            // Use XMLHttpRequest for upload progress tracking (fetch doesn't support upload progress yet)
            return new Promise((resolve, reject) => {
                const xhr = new XMLHttpRequest();

                // Track progress
                xhr.upload.addEventListener('progress', (e) => {
                    if (e.lengthComputable) {
                        const progress = Math.round((e.loaded / e.total) * 100);

                        // Update transfer state with dual speeds
                        setTransfers(prev => prev.map(t => {
                            if (t.id === transferId) {
                                const speeds = calculateTransferSpeeds(t, e.loaded);
                                const remainingBytes = e.total - e.loaded;
                                const eta = speeds.speedCurrent > 0 ? remainingBytes / (speeds.speedCurrent * 1024 * 1024) : null;

                                return {
                                    ...t,
                                    progress,
                                    bytesTransferred: e.loaded,
                                    speed: speeds.speedCurrent,
                                    speedAverage: speeds.speedAverage,
                                    speedHistory: speeds.speedHistory,
                                    eta: eta ? Math.ceil(eta) : null
                                };
                            }
                            return t;
                        }));
                    }
                });

                xhr.addEventListener('load', () => {
                    if (xhr.status === 200) {
                        logToServer(`uploadViaStreaming: Upload complete`);
                        logTransferAction('upload_complete', { fileName: file.name, fileSize: file.size, method: 'streaming', guid: uploadGuid });
                        resolve();
                    } else if (xhr.status === 503) {
                        // Connection lost but can resume
                        try {
                            const errorResponse = JSON.parse(xhr.responseText);
                            if (errorResponse.data && errorResponse.data.canResume) {
                                logToServer(`uploadViaStreaming: Connection lost at ${errorResponse.data.bytesCommitted} bytes, can resume with GUID ${errorResponse.data.uploadGuid}`);

                                // Store resume info for automatic retry
                                window.pendingResumeUpload = {
                                    fileName: file.name,
                                    fileSize: file.size,
                                    uploadGuid: errorResponse.data.uploadGuid,
                                    method: 'streaming',
                                    targetPath: targetPath,
                                    autoRetry: true  // Flag for automatic resume
                                };

                                logTransferAction('upload_connection_lost', {
                                    fileName: file.name,
                                    fileSize: file.size,
                                    method: 'streaming',
                                    bytesCommitted: errorResponse.data.bytesCommitted,
                                    canResume: true
                                }, 'Warning');

                                reject(new Error(`Connection lost. Resume available from ${errorResponse.data.bytesCommitted} bytes.`));
                            } else {
                                reject(new Error(`Upload failed: ${xhr.status} ${xhr.statusText}`));
                            }
                        } catch (e) {
                            reject(new Error(`Upload failed: ${xhr.status} ${xhr.statusText}`));
                        }
                    } else {
                        logTransferAction('upload_failed', { fileName: file.name, fileSize: file.size, method: 'streaming', status: xhr.status, statusText: xhr.statusText }, 'Error');
                        reject(new Error(`Upload failed: ${xhr.status} ${xhr.statusText}`));
                    }
                });

                xhr.addEventListener('error', () => {
                    reject(new Error('Network error during streaming upload'));
                });

                xhr.addEventListener('abort', () => {
                    reject(new Error('Upload cancelled by user'));
                });

                // Handle cancellation
                abortController.signal.addEventListener('abort', () => {
                    xhr.abort();
                });

                const startTime = Date.now();

                // Prepare file data (with resume support)
                let fileData = file;
                if (startOffset > 0) {
                    // Resume: Send only remaining bytes
                    fileData = file.slice(startOffset);
                    logToServer(`uploadViaStreaming: Resuming from offset ${startOffset}, sending ${fileData.size} bytes`);
                }

                // Open connection and send file
                xhr.open('PUT', uploadUrl);
                xhr.setRequestHeader('Authorization', `Bearer ${localStorage.getItem('auth_token') || ''}`);

                // Add Content-Range header for resume
                if (startOffset > 0) {
                    const endOffset = file.size - 1;
                    xhr.setRequestHeader('Content-Range', `bytes ${startOffset}-${endOffset}/${file.size}`);
                    logToServer(`uploadViaStreaming: Setting Content-Range header: bytes ${startOffset}-${endOffset}/${file.size}`);
                }

                // Store upload GUID in transfer metadata for pause/resume
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? {
                            ...t,
                            uploadGuid: uploadGuid,
                            metadata: { ...t.metadata, uploadGuid: uploadGuid, startOffset: startOffset }
                        }
                        : t
                ));

                xhr.send(fileData);  // Send file (entire or remaining bytes)
            });

        } catch (err) {
            logToServer(`uploadViaStreaming ERROR: ${err.message}`, 'Error');
            throw err;
        }
    }, []);

    /**
     * Calculate dual transfer speeds (average + current)
     * @param {Object} transfer - Transfer object
     * @param {number} bytesTransferred - Current bytes transferred
     * @returns {Object} - { speedAverage, speedCurrent, speedHistory }
     */
    const calculateTransferSpeeds = (transfer, bytesTransferred) => {
        const now = Date.now();
        const elapsedSeconds = (now - transfer.startTime) / 1000;

        // Calculate average speed (overall)
        const speedAverage = elapsedSeconds > 0 ? (bytesTransferred / 1024 / 1024) / elapsedSeconds : 0;

        // Update speed history (rolling 5-second window)
        const updatedHistory = [
            ...transfer.speedHistory,
            { timestamp: now, bytes: bytesTransferred }
        ].filter(h => now - h.timestamp < 5000); // Keep only last 5 seconds

        // Calculate current speed (5-second window)
        let speedCurrent = speedAverage; // Default to average if not enough data
        if (updatedHistory.length >= 2) {
            const oldest = updatedHistory[0];
            const newest = updatedHistory[updatedHistory.length - 1];
            const timeSpan = (newest.timestamp - oldest.timestamp) / 1000;
            const bytesDiff = newest.bytes - oldest.bytes;
            speedCurrent = timeSpan > 0 ? (bytesDiff / 1024 / 1024) / timeSpan : speedAverage;
        }

        return {
            speedAverage: parseFloat(speedAverage.toFixed(2)),
            speedCurrent: parseFloat(speedCurrent.toFixed(2)),
            speedHistory: updatedHistory
        };
    };

    /**
     * Upload file (tries streaming first, then WebSocket, then falls back to PUT chunks)
     */
    /**
     * Resume an interrupted upload with existing GUID, sending only missing chunks
     */
    const uploadFileWithResume = async (file, logicalPath, resumeData, transferId, chunkSize, totalChunks) => {
        // Wait for settings to load if not ready yet
        if (!settingsLoaded) {
            logToServer(`uploadFileWithResume: Waiting for settings to load...`);
            await new Promise(resolve => {
                const checkInterval = setInterval(() => {
                    if (settingsLoaded) {
                        clearInterval(checkInterval);
                        resolve();
                    }
                }, 50); // Check every 50ms

                // Timeout after 2 seconds
                setTimeout(() => {
                    clearInterval(checkInterval);
                    logToServer(`uploadFileWithResume: Settings load timeout, proceeding with current settings`, 'Warning');
                    resolve();
                }, 2000);
            });
        }

        const { guid, missingChunks, receivedBytes, receivedChunks, uploadMethod } = resumeData;

        logToServer(`uploadFileWithResume: Resuming ${file.name} with GUID ${guid}, ${missingChunks.length} chunks remaining. Enabled methods: streaming=${enabledUploadMethods.streaming}, websocket=${enabledUploadMethods.websocket}, putChunks=${enabledUploadMethods.putChunks}`);
        logTransferAction('resume_start', {
            fileName: file.name,
            fileSize: file.size,
            guid: guid,
            missingChunks: missingChunks.length,
            method: uploadMethod
        });

        // Create AbortController for this transfer
        const abortController = new AbortController();
        transferAbortControllers.current[transferId] = abortController;

        // Calculate progress based on received chunks
        const initialProgress = Math.round((receivedChunks / totalChunks) * 100);

        // Add transfer to list with existing progress
        const transferStartTime = Date.now();
        const newTransfer = {
            id: transferId,
            fileName: file.name,
            fileSize: file.size,
            type: 'upload',
            status: 'uploading',
            progress: initialProgress,
            currentChunk: receivedChunks,
            totalChunks: totalChunks,
            targetPath: logicalPath,
            startTime: transferStartTime,
            bytesTransferred: receivedBytes,
            speed: 0,
            speedAverage: 0,
            speedHistory: [],
            eta: null,
            method: uploadMethod === 'unknown' ? null : uploadMethod,
            metadata: {
                uploadGuid: guid,
                chunkSize: chunkSize,
                totalChunks: totalChunks,
                receivedChunks: receivedChunks,
                pipelineDepth: usePipelining ? 5 : 1,
                startTime: transferStartTime,
                lastChunkTime: transferStartTime,
                retryCount: 0
            }
        };

        setTransfers(prev => [...prev, newTransfer]);
        setDetailsTab('transfers');

        try {
            // Determine which method to use based on saved method and settings
            let actualMethod = uploadMethod;

            // If saved method is unknown or disabled, pick the best available (respecting user preferences)
            if (actualMethod === 'unknown' || (actualMethod === 'websocket' && !enabledUploadMethods.websocket) || (actualMethod === 'putChunks' && !enabledUploadMethods.putChunks)) {
                // Prefer putChunks over websocket (more reliable, works everywhere)
                if (enabledUploadMethods.putChunks) {
                    actualMethod = 'putChunks';
                } else if (enabledUploadMethods.websocket && window.WebSocket) {
                    actualMethod = 'websocket';
                } else {
                    throw new Error('No chunked upload methods enabled for resume');
                }
                logToServer(`uploadFileWithResume: Saved method "${uploadMethod}" not available, switching to ${actualMethod}`);
            }

            // Update transfer method
            setTransfers(prev => prev.map(t =>
                t.id === transferId ? { ...t, method: actualMethod } : t
            ));

            // Resume with the determined method
            if (actualMethod === 'websocket') {
                logToServer(`uploadFileWithResume: Using WebSocket to send ${missingChunks.length} missing chunks`);
                await uploadViaWebSocket(file, guid, transferId, abortController, chunkSize, totalChunks, usePipelining);
            } else if (actualMethod === 'putChunks') {
                logToServer(`uploadFileWithResume: Using PUT chunks to send ${missingChunks.length} missing chunks`);
                await uploadViaPutChunks(file, guid, transferId, abortController, chunkSize, totalChunks);
            }

            // Upload completed successfully
            logToServer(`uploadFileWithResume: Completed ${file.name} via ${actualMethod}`);
            logTransferAction('resume_complete', {
                fileName: file.name,
                fileSize: file.size,
                guid: guid,
                method: actualMethod
            });

            // Clean up localStorage on successful completion
            const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
            localStorage.removeItem(storageKey);

            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, status: 'completed', progress: 100 }
                    : t
            ));
            showToast(`Upload resumed and completed: ${file.name}`, 'success');

            // Refresh current folder
            const currentLogicalPath = extractLogicalPath(selectedTreePath);
            if (logicalPath === currentLogicalPath) {
                loadFolderContents(selectedTreePath);
            }

            // Cleanup AbortController
            delete transferAbortControllers.current[transferId];

        } catch (err) {
            const isCancelled = err.name === 'AbortError' || err.message.includes('cancelled');

            if (isCancelled) {
                logToServer(`uploadFileWithResume CANCELLED: ${file.name}`);
                if (guid) {
                    try {
                        await window.psweb_fetchWithAuthHandling(
                            '/apps/WebhostFileExplorer/api/v1/files/upload-chunk',
                            {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ action: 'cancel', guid: guid })
                            }
                        );
                    } catch (cancelErr) {
                        logToServer(`uploadFileWithResume: Cancel cleanup failed: ${cancelErr.message}`, 'Warning');
                    }
                }

                // Remove from localStorage on cancellation
                const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                localStorage.removeItem(storageKey);
            } else {
                logToServer(`uploadFileWithResume ERROR: ${err.message}`, 'Error', { fileName: file.name });
                // Keep in localStorage for retry
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? { ...t, status: 'failed', error: err.message }
                        : t
                ));
                showToast(`Upload resume failed: ${file.name} - ${err.message}`, 'error');
            }

            throw err;
        } finally {
            delete transferAbortControllers.current[transferId];
        }
    };

    /**
     * Check for resumable upload in localStorage and query server for status
     * @returns {Object|null} Resume data if available: { guid, chunkBitmap, missingChunks, receivedBytes }
     */
    const checkForResumableUpload = async (fileName, fileSize, targetPath) => {
        try {
            // Call server endpoint to check for existing uploads
            logToServer(`checkForResumableUpload: Checking server for existing uploads of ${fileName}...`);

            const checkResponse = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files/upload-check',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        fileName: fileName,
                        fileSize: fileSize,
                        targetPath: targetPath
                    })
                }
            );

            if (!checkResponse.ok) {
                logToServer(`checkForResumableUpload: Server check failed: ${checkResponse.status}`, 'Warning');
                return null;
            }

            const result = await checkResponse.json();
            if (result.status !== 'success' || !result.data.canResume) {
                logToServer(`checkForResumableUpload: No resumable upload found`);
                return null;
            }

            const upload = result.data.upload;
            logToServer(`checkForResumableUpload: Found resumable upload - ${upload.percentComplete}% complete (${upload.bytesCommitted || upload.bytesReceived} bytes)`);

            // For streaming uploads
            if (upload.uploadMethod === 'streaming') {
                return {
                    guid: upload.uploadGuid,
                    uploadMethod: 'streaming',
                    bytesCommitted: upload.bytesCommitted,
                    fileSize: upload.fileSize,
                    fileName: upload.fileName,
                    percentComplete: upload.percentComplete,
                    startTime: upload.startTime,
                    orphaned: upload.orphaned || false
                };
            }
            // For chunked uploads
            else if (upload.uploadMethod === 'chunked') {
                // Query detailed status for chunk bitmap
                const statusResponse = await window.psweb_fetchWithAuthHandling(
                    `/apps/WebhostFileExplorer/api/v1/files/upload-status?guid=${upload.uploadGuid}`
                );

                if (!statusResponse.ok) {
                    logToServer(`checkForResumableUpload: Could not get chunk status`, 'Warning');
                    return null;
                }

                const statusData = await statusResponse.json();
                if (statusData.status !== 'success') {
                    return null;
                }

                const data = statusData.data;
                const missingCount = data.missingChunks.length;

                if (missingCount === 0) {
                    logToServer(`checkForResumableUpload: Upload already complete`);
                    return null;
                }

                return {
                    guid: data.guid,
                    chunkBitmap: data.chunkBitmap,
                    missingChunks: data.missingChunks,
                    receivedBytes: data.receivedBytes,
                    receivedChunks: data.receivedChunks,
                    totalChunks: data.totalChunks,
                    chunkSize: data.chunkSize,
                    uploadMethod: 'chunked',
                    startTime: data.startTime
                };
            }

            return null;
        }
        catch (error) {
            logToServer(`checkForResumableUpload: Error checking for resumable upload: ${error.message}`, 'Error');
            return null;
        }
    };

    const uploadFile = useCallback(async (file, targetPath) => {
        // Wait for settings to load if not ready yet
        if (!settingsLoaded) {
            logToServer(`uploadFile: Waiting for settings to load...`);
            await new Promise(resolve => {
                const checkInterval = setInterval(() => {
                    if (settingsLoaded) {
                        clearInterval(checkInterval);
                        resolve();
                    }
                }, 50); // Check every 50ms

                // Timeout after 2 seconds
                setTimeout(() => {
                    clearInterval(checkInterval);
                    logToServer(`uploadFile: Settings load timeout, proceeding with current settings`, 'Warning');
                    resolve();
                }, 2000);
            });
        }

        // Check if this is a resume operation with existing transfer ID
        let transferId = null;
        let isResumeWithExistingTransfer = false;

        if (window.pendingResumeUpload &&
            window.pendingResumeUpload.fileName === file.name &&
            window.pendingResumeUpload.fileSize === file.size &&
            window.pendingResumeUpload.transferId) {

            transferId = window.pendingResumeUpload.transferId;
            isResumeWithExistingTransfer = true;
            logToServer(`uploadFile: Reusing existing transfer ID ${transferId} for resume`);
        } else {
            transferId = `upload-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        }

        const chunkSize = chunkSizeMB * 1024 * 1024; // Configurable chunk size (default 25MB)
        const totalChunks = Math.ceil(file.size / chunkSize);

        logToServer(`uploadFile: Starting upload of ${file.name} (${file.size} bytes, ${totalChunks} chunks). Enabled methods: streaming=${enabledUploadMethods.streaming}, websocket=${enabledUploadMethods.websocket}, putChunks=${enabledUploadMethods.putChunks}`);

        // Extract logical path from full path
        const logicalPath = extractLogicalPath(targetPath);

        // Check for resumable upload BEFORE creating transfer object
        const resumeData = await checkForResumableUpload(file.name, file.size, logicalPath);
        if (resumeData) {
            const isStreaming = resumeData.uploadMethod === 'streaming';
            const resumeMsg = isStreaming
                ? `Resume available for ${file.name} - ${resumeData.percentComplete}% complete (${resumeData.bytesCommitted} bytes)`
                : `Resume available for ${file.name} - ${resumeData.missingChunks.length} chunks remaining`;

            logToServer(`uploadFile: ${resumeMsg}`, 'Info');
            logTransferAction('resume_available', {
                fileName: file.name,
                fileSize: file.size,
                guid: resumeData.guid,
                uploadMethod: resumeData.uploadMethod,
                ...(isStreaming ? {
                    bytesCommitted: resumeData.bytesCommitted,
                    percentComplete: resumeData.percentComplete
                } : {
                    missingChunks: resumeData.missingChunks.length,
                    totalChunks: resumeData.totalChunks,
                    receivedChunks: resumeData.receivedChunks
                })
            });

            // Show resume confirmation dialog
            return new Promise((resolve, reject) => {
                setResumeDialog({
                    visible: true,
                    file: file,
                    resumeData: resumeData,
                    onResume: async () => {
                        setResumeDialog(prev => ({ ...prev, visible: false }));

                        try {
                            // Step 1: Check if file is still accessible, otherwise prompt for re-selection
                            let selectedFile = file;

                            // Test if we can still read from the file
                            let fileAccessible = false;
                            try {
                                // Try to read first byte to test accessibility
                                const testBlob = file.slice(0, 1);
                                await testBlob.arrayBuffer();
                                fileAccessible = true;
                                logToServer(`uploadFile: Original file still accessible, no need to re-select`);
                            } catch (err) {
                                logToServer(`uploadFile: Original file no longer accessible: ${err.message}`, 'Warning');
                                fileAccessible = false;
                            }

                            if (!fileAccessible) {
                                // Prompt user to re-select file for validation
                                logToServer(`uploadFile: Prompting user to re-select ${file.name} for validation...`);
                                showToast(`Please re-select "${file.name}" to validate before resuming...`, 'info');

                                // Create file input for user to select file
                                const fileInput = document.createElement('input');
                                fileInput.type = 'file';
                                fileInput.accept = '*/*';
                                fileInput.style.display = 'none';
                                document.body.appendChild(fileInput);

                                selectedFile = await new Promise((fileResolve, fileReject) => {
                                    fileInput.onchange = (e) => {
                                        const selectedFile = e.target.files[0];
                                        document.body.removeChild(fileInput);

                                        if (!selectedFile) {
                                            fileReject(new Error('No file selected'));
                                            return;
                                        }

                                        // Verify file name and size match
                                        if (selectedFile.name !== file.name) {
                                            fileReject(new Error(`File name mismatch: expected "${file.name}", got "${selectedFile.name}"`));
                                            return;
                                        }

                                        if (selectedFile.size !== file.size) {
                                            fileReject(new Error(`File size mismatch: expected ${file.size} bytes, got ${selectedFile.size} bytes`));
                                            return;
                                        }

                                        fileResolve(selectedFile);
                                    };

                                    fileInput.click();
                                });

                                logToServer(`uploadFile: User selected ${selectedFile.name} for validation`);
                            }

                            // Step 2: Perform progressive hash validation
                            const bytesToValidate = isStreaming ? resumeData.bytesCommitted : resumeData.receivedBytes;

                            logToServer(`uploadFile: Starting progressive hash validation of ${bytesToValidate} bytes...`);
                            showToast(`Validating uploaded data... This may take a moment.`, 'info');

                            const validationResult = await progressiveHashValidation(
                                selectedFile,
                                resumeData.guid,
                                bytesToValidate
                            );

                            if (validationResult.error) {
                                showToast(`Validation error: ${validationResult.error}`, 'error');
                                reject(new Error(validationResult.error));
                                return;
                            }

                            // Step 3: Handle validation results
                            if (validationResult.valid) {
                                // Data matches - proceed with resume
                                logToServer(`uploadFile: Validation passed - resuming upload`);
                                showToast(`✓ Validation passed - resuming upload`, 'success');

                                if (isStreaming) {
                                    // For streaming, set pendingResumeUpload and call uploadFile
                                    window.pendingResumeUpload = {
                                        fileName: selectedFile.name,
                                        fileSize: selectedFile.size,
                                        uploadGuid: resumeData.guid,
                                        method: 'streaming',
                                        targetPath: logicalPath,
                                        autoRetry: false  // Manual resume, not automatic
                                    };
                                    uploadFile(selectedFile, targetPath).then(resolve).catch(reject);
                                } else {
                                    // For chunked, use existing resume logic
                                    uploadFileWithResume(selectedFile, logicalPath, resumeData, transferId, chunkSize, totalChunks)
                                        .then(resolve)
                                        .catch(reject);
                                }
                            } else if (validationResult.isFirstMBDifferent) {
                                // First MB is different - show overwrite confirmation
                                logToServer(`uploadFile: First MB differs - asking for overwrite confirmation`, 'Warning');

                                const confirmOverwrite = await new Promise((confirmResolve) => {
                                    setConfirmDialog({
                                        visible: true,
                                        title: '⚠️ File Mismatch Detected',
                                        message: `The file you selected appears to be different from the partially uploaded file (difference detected in the first 1MB).\n\nThis may indicate:\n• The file has been modified since upload started\n• A different file with the same name was selected\n\nDo you want to OVERWRITE the existing upload and start fresh?`,
                                        confirmText: 'Overwrite & Start Fresh',
                                        cancelText: 'Cancel',
                                        onConfirm: () => {
                                            setConfirmDialog(prev => ({ ...prev, visible: false }));
                                            confirmResolve(true);
                                        },
                                        onCancel: () => {
                                            setConfirmDialog(prev => ({ ...prev, visible: false }));
                                            confirmResolve(false);
                                        }
                                    });
                                });

                                if (confirmOverwrite) {
                                    logToServer(`uploadFile: User confirmed overwrite - starting fresh upload`);
                                    // Delete temp file and start fresh
                                    if (resumeData.guid) {
                                        logToServer(`uploadFile: Deleting temp file for upload ${resumeData.guid}`);
                                        try {
                                            const deleteResponse = await window.psweb_fetchWithAuthHandling(
                                                `/apps/WebhostFileExplorer/api/v1/files/temp/${resumeData.guid}/`,
                                                { method: 'DELETE' }
                                            );
                                            if (deleteResponse.ok) {
                                                logToServer(`uploadFile: Temp file deleted successfully`);
                                            }
                                        } catch (err) {
                                            logToServer(`uploadFile: Failed to delete temp file: ${err.message}`, 'warning');
                                        }
                                    }
                                    uploadFile(selectedFile, targetPath).then(resolve).catch(reject);
                                } else {
                                    logToServer(`uploadFile: User canceled overwrite`);
                                    showToast('Upload canceled', 'info');
                                    reject(new Error('User canceled overwrite'));
                                }
                            } else {
                                // Data differs but not in first MB - likely corrupted during upload
                                logToServer(`uploadFile: Data corruption detected at byte ${validationResult.differenceStart}`, 'Error');

                                const confirmOverwrite = await new Promise((confirmResolve) => {
                                    setConfirmDialog({
                                        visible: true,
                                        title: '⚠️ Data Corruption Detected',
                                        message: `Data mismatch detected at byte ${validationResult.differenceStart.toLocaleString()}.\n\nThis suggests corruption occurred during the previous upload attempt.\n\nRecommendation: Start fresh to ensure data integrity.`,
                                        confirmText: 'Start Fresh',
                                        cancelText: 'Cancel',
                                        onConfirm: () => {
                                            setConfirmDialog(prev => ({ ...prev, visible: false }));
                                            confirmResolve(true);
                                        },
                                        onCancel: () => {
                                            setConfirmDialog(prev => ({ ...prev, visible: false }));
                                            confirmResolve(false);
                                        }
                                    });
                                });

                                if (confirmOverwrite) {
                                    logToServer(`uploadFile: User confirmed fresh upload after corruption detection`);
                                    if (resumeData.guid) {
                                        logToServer(`uploadFile: Deleting corrupted temp file for upload ${resumeData.guid}`);
                                        try {
                                            const deleteResponse = await window.psweb_fetchWithAuthHandling(
                                                `/apps/WebhostFileExplorer/api/v1/files/temp/${resumeData.guid}/`,
                                                { method: 'DELETE' }
                                            );
                                            if (deleteResponse.ok) {
                                                logToServer(`uploadFile: Corrupted temp file deleted successfully`);
                                            }
                                        } catch (err) {
                                            logToServer(`uploadFile: Failed to delete corrupted temp file: ${err.message}`, 'warning');
                                        }
                                    }
                                    uploadFile(selectedFile, targetPath).then(resolve).catch(reject);
                                } else {
                                    logToServer(`uploadFile: User canceled after corruption detection`);
                                    showToast('Upload canceled', 'info');
                                    reject(new Error('User canceled after corruption detection'));
                                }
                            }
                        } catch (error) {
                            logToServer(`uploadFile: Resume validation error: ${error.message}`, 'Error');
                            showToast(`Resume failed: ${error.message}`, 'error');
                            reject(error);
                        }
                    },
                    onStartFresh: () => {
                        setResumeDialog(prev => ({ ...prev, visible: false }));
                        // Delete temp file on server if possible
                        if (resumeData.guid) {
                            logToServer(`uploadFile: User chose to start fresh, deleting temp file ${resumeData.guid}`);
                            try {
                                const deleteResponse = await window.psweb_fetchWithAuthHandling(
                                    `/apps/WebhostFileExplorer/api/v1/files/temp/${resumeData.guid}/`,
                                    { method: 'DELETE' }
                                );
                                if (deleteResponse.ok) {
                                    logToServer(`uploadFile: Temp file deleted successfully before starting fresh`);
                                }
                            } catch (err) {
                                logToServer(`uploadFile: Failed to delete temp file: ${err.message}`, 'warning');
                            }
                        }
                        // Recursively call uploadFile to start fresh (no resume data this time)
                        uploadFile(file, targetPath).then(resolve).catch(reject);
                    }
                });
            });
        }

        // Create AbortController for this transfer
        const abortController = new AbortController();
        transferAbortControllers.current[transferId] = abortController;

        let uploadGuid = null;
        let uploadMethod = 'unknown';

        // Add transfer to list
        const transferStartTime = Date.now();
        const newTransfer = {
            id: transferId,
            fileName: file.name,
            fileSize: file.size,
            type: 'upload',
            status: 'uploading',
            progress: 0,
            currentChunk: 0,
            totalChunks: totalChunks,
            targetPath: logicalPath,
            startTime: transferStartTime,
            bytesTransferred: 0,
            speed: 0, // MB/s - current speed (5-sec window)
            speedAverage: 0, // MB/s - overall average since start
            speedHistory: [], // Array of {timestamp, bytes} for rolling window
            eta: null, // seconds remaining
            method: null, // Will be set when upload method is determined
            metadata: {
                uploadGuid: null,
                chunkSize: chunkSize,
                totalChunks: totalChunks,
                receivedChunks: 0,
                pipelineDepth: usePipelining ? 5 : 1,
                startTime: transferStartTime,
                lastChunkTime: transferStartTime,
                retryCount: 0
            }
        };

        // Only add transfer if not resuming with existing transfer
        if (!isResumeWithExistingTransfer) {
            setTransfers(prev => [...prev, newTransfer]);
            setDetailsTab('transfers'); // Auto-switch to transfers tab
        } else {
            // Update existing transfer to reset error and status
            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, status: 'uploading', error: null, progress: newTransfer.progress }
                    : t
            ));
            logToServer(`uploadFile: Updated existing transfer ${transferId} for resume`);
        }

        try {
            // Check for pending resume (from pause/resume button)
            let resumeGuid = null;
            if (window.pendingResumeUpload &&
                window.pendingResumeUpload.fileName === file.name &&
                window.pendingResumeUpload.fileSize === file.size) {

                resumeGuid = window.pendingResumeUpload.uploadGuid;
                const resumeMethod = window.pendingResumeUpload.method;
                logToServer(`uploadFile: Detected pending resume for ${file.name}, GUID: ${resumeGuid}, method: ${resumeMethod}`);

                // NOTE: Do NOT clear window.pendingResumeUpload yet
                // uploadViaStreaming needs to access validatedBytes from it
                // It will be cleared after the upload function reads it

                // Force the same method for resume
                if (resumeMethod === 'streaming') {
                    uploadMethod = 'streaming';
                }
            }

            // Try streaming upload first (if enabled and fastest - no chunking overhead!)
            if (enabledUploadMethods.streaming && (uploadMethod === 'streaming' || uploadMethod === 'unknown')) {
                try {
                    logToServer(`uploadFile: Trying streaming upload (single request, no chunking)${resumeGuid ? ' with RESUME' : ''}`);
                    uploadMethod = 'streaming';

                    // Update transfer with method
                    setTransfers(prev => prev.map(t =>
                        t.id === transferId
                            ? { ...t, method: 'streaming' }
                            : t
                    ));

                    await uploadViaStreaming(file, transferId, logicalPath, abortController, resumeGuid);

                    // Streaming succeeded - we're done!
                    logToServer(`uploadFile: Streaming upload completed successfully`);

                } catch (streamError) {
                    // Check if we have resume info from connection loss
                    if (window.pendingResumeUpload &&
                        window.pendingResumeUpload.autoRetry &&
                        window.pendingResumeUpload.fileName === file.name) {

                        const resumeInfo = window.pendingResumeUpload;
                        logToServer(`uploadFile: Connection lost during streaming, automatically retrying resume from ${resumeInfo.uploadGuid}`);

                        // Clear auto-retry flag to prevent infinite loop
                        delete window.pendingResumeUpload;

                        // Wait 2 seconds before retry
                        await new Promise(resolve => setTimeout(resolve, 2000));

                        // Retry with resume
                        try {
                            await uploadViaStreaming(file, transferId, logicalPath, abortController, resumeInfo.uploadGuid);
                            logToServer(`uploadFile: Resume succeeded after connection loss`);
                            return; // Success - exit uploadFile
                        } catch (retryError) {
                            logToServer(`uploadFile: Resume failed: ${retryError.message}, falling back to chunked upload`, 'Warning');
                            // Fall through to chunked upload
                        }
                    } else {
                        logToServer(`uploadFile: Streaming upload failed: ${streamError.message}, falling back to chunked upload`, 'Warning');
                    }

                    // Reset method so we can try chunked upload
                    uploadMethod = 'unknown';

                    // Reset transfer method badge
                    setTransfers(prev => prev.map(t =>
                        t.id === transferId
                            ? { ...t, method: null }
                            : t
                    ));
                }
            }

            // If streaming didn't succeed (disabled, failed, or not attempted), use chunked upload
            if (uploadMethod === 'unknown') {
                // Step 1: Initialize chunked upload (POST with action=init)
                logToServer(`uploadFile: Initializing chunked upload...`);
                const initResponse = await window.psweb_fetchWithAuthHandling(
                    '/apps/WebhostFileExplorer/api/v1/files/upload-chunk',
                    {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            action: 'init',
                            fileName: file.name,
                            fileSize: file.size,
                            chunkSize: chunkSize,
                            totalChunks: totalChunks,
                            targetPath: logicalPath,
                            uploadMethod: 'unknown' // Will be updated when method is determined
                        }),
                        signal: abortController.signal
                    }
                );

                if (!initResponse.ok) {
                    throw new Error(`Upload initialization failed: ${initResponse.statusText}`);
                }

                const initResult = await initResponse.json();
                uploadGuid = initResult.data.guid;

                logToServer(`uploadFile: Chunked upload initialized with GUID: ${uploadGuid}`);

                // Save upload to localStorage for resume capability
                const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                const uploadState = {
                    guid: uploadGuid,
                    fileName: file.name,
                    fileSize: file.size,
                    targetPath: logicalPath,
                    chunkSize: chunkSize,
                    totalChunks: totalChunks,
                    uploadMethod: 'unknown', // Will be updated when method is determined
                    startTime: Date.now(),
                    status: 'active'
                };
                localStorage.setItem(storageKey, JSON.stringify(uploadState));
                logToServer(`uploadFile: Upload state saved to localStorage: ${storageKey}`);

                // Store GUID in transfer for cancellation and metadata
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? {
                            ...t,
                            uploadGuid: uploadGuid,
                            metadata: { ...t.metadata, uploadGuid: uploadGuid }
                        }
                        : t
                ));

                // Step 2: Try WebSocket upload (if enabled and supported)
                if (enabledUploadMethods.websocket && window.WebSocket) {
                    try {
                        const pipelineMode = usePipelining ? 'PIPELINED (5 chunks parallel)' : 'SERIAL (one at a time)';
                        logToServer(`uploadFile: WebSocket upload starting - Mode: ${pipelineMode}`);
                        uploadMethod = 'websocket';

                        // Update localStorage with method
                        const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                        const storedData = localStorage.getItem(storageKey);
                        if (storedData) {
                            const uploadState = JSON.parse(storedData);
                            uploadState.uploadMethod = 'websocket';
                            localStorage.setItem(storageKey, JSON.stringify(uploadState));
                        }

                        // Update transfer with method
                        setTransfers(prev => prev.map(t =>
                            t.id === transferId
                                ? { ...t, method: 'websocket' }
                                : t
                        ));

                        await uploadViaWebSocket(file, uploadGuid, transferId, abortController, chunkSize, totalChunks, usePipelining);
                    } catch (wsError) {
                        logToServer(`uploadFile: WebSocket upload failed: ${wsError.message}, falling back to PUT chunks`, 'Warning');

                        // Only fallback to PUT if enabled and not cancelled
                        if (!abortController.signal.aborted && enabledUploadMethods.putChunks) {
                            uploadMethod = 'putChunks';

                            // Update localStorage with fallback method
                            const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                            const storedData = localStorage.getItem(storageKey);
                            if (storedData) {
                                const uploadState = JSON.parse(storedData);
                                uploadState.uploadMethod = 'putChunks';
                                localStorage.setItem(storageKey, JSON.stringify(uploadState));
                            }

                            setTransfers(prev => prev.map(t =>
                                t.id === transferId
                                    ? { ...t, method: 'putChunks' }
                                    : t
                            ));
                            await uploadViaPutChunks(file, uploadGuid, transferId, abortController, chunkSize, totalChunks);
                        } else {
                            throw wsError;
                        }
                    }
                } else if (enabledUploadMethods.putChunks) {
                    // WebSocket disabled or not supported, use PUT chunks
                    const reason = !enabledUploadMethods.websocket ? 'WebSocket disabled in settings' : 'WebSocket not supported';
                    logToServer(`uploadFile: ${reason}, using PUT chunks`);
                    uploadMethod = 'putChunks';

                    // Update localStorage with method
                    const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                    const storedData = localStorage.getItem(storageKey);
                    if (storedData) {
                        const uploadState = JSON.parse(storedData);
                        uploadState.uploadMethod = 'putChunks';
                        localStorage.setItem(storageKey, JSON.stringify(uploadState));
                    }

                    setTransfers(prev => prev.map(t =>
                        t.id === transferId
                            ? { ...t, method: 'putChunks' }
                            : t
                    ));

                    await uploadViaPutChunks(file, uploadGuid, transferId, abortController, chunkSize, totalChunks);
                } else {
                    // No chunked upload methods available
                    const methodStates = `WebSocket: ${enabledUploadMethods.websocket ? 'enabled' : 'disabled'}, PUT chunks: ${enabledUploadMethods.putChunks ? 'enabled' : 'disabled'}`;
                    logToServer(`uploadFile: No chunked upload methods available. ${methodStates}`, 'Error');
                    throw new Error(`No upload methods enabled - cannot proceed with chunked upload. Please enable WebSocket or PUT chunks in settings.`);
                }
            }

            // Upload completed successfully
            logToServer(`uploadFile: Completed ${file.name} via ${uploadMethod}`);

            // Clean up localStorage on successful completion
            const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
            localStorage.removeItem(storageKey);
            logToServer(`uploadFile: Removed upload state from localStorage: ${storageKey}`);

            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, status: 'completed', progress: 100 }
                    : t
            ));
            showToast(`Upload completed: ${file.name} (${uploadMethod})`, 'success');

            // Refresh current folder if upload was to current location
            const currentLogicalPath = extractLogicalPath(selectedTreePath);
            if (logicalPath === currentLogicalPath) {
                loadFolderContents(selectedTreePath);
            }

            // Cleanup AbortController
            delete transferAbortControllers.current[transferId];

        } catch (err) {
            // Check if error is due to abort
            const isCancelled = err.name === 'AbortError' || err.message.includes('cancelled');

            if (isCancelled) {
                logToServer(`uploadFile CANCELLED: ${file.name}`);
                // Call cancel endpoint if GUID was allocated
                if (uploadGuid) {
                    try {
                        await window.psweb_fetchWithAuthHandling(
                            '/apps/WebhostFileExplorer/api/v1/files/upload-chunk',
                            {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({
                                    action: 'cancel',
                                    guid: uploadGuid
                                })
                            }
                        );
                    } catch (cancelErr) {
                        logToServer(`uploadFile: Cancel cleanup failed: ${cancelErr.message}`, 'Warning');
                    }
                }

                // Remove from localStorage on explicit cancellation (user doesn't want to resume)
                const storageKey = `upload_${file.name}_${file.size}_${logicalPath}`;
                localStorage.removeItem(storageKey);
                logToServer(`uploadFile: Removed cancelled upload from localStorage: ${storageKey}`);

                // Status already set to failed by cancelTransfer
            } else {
                logToServer(`uploadFile ERROR: ${err.message}`, 'Error', { fileName: file.name });
                // DO NOT remove from localStorage on error - allows resume
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? { ...t, status: 'failed', error: err.message }
                        : t
                ));
                showToast(`Upload failed: ${file.name} - ${err.message}`, 'error');
            }
        } finally {
            // Always cleanup AbortController
            delete transferAbortControllers.current[transferId];
        }
    }, [selectedTreePath, loadFolderContents, showToast, uploadViaWebSocket, uploadViaPutChunks, enabledUploadMethods, usePipelining, chunkSizeMB, settingsLoaded]);

    /**
     * Extract logical path from full path (local|localhost|LogicalPath)
     */
    const extractLogicalPath = (fullPath) => {
        if (!fullPath) return '';
        const parts = fullPath.split('|');
        return parts.length === 3 ? parts[2] : fullPath;
    };

    /**
     * Download file
     */
    const downloadFile = useCallback(async (file) => {
        const transferId = `download-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

        logToServer(`downloadFile: Starting download of ${file.name}`);

        // Create AbortController for this transfer
        const abortController = new AbortController();
        transferAbortControllers.current[transferId] = abortController;

        // Add transfer to list
        const newTransfer = {
            id: transferId,
            fileName: file.name,
            filePath: file.path, // Store for retry functionality
            fileSize: file.size,
            type: 'download',
            status: 'downloading',
            progress: 0,
            startTime: Date.now()
        };

        setTransfers(prev => [...prev, newTransfer]);
        setDetailsTab('transfers'); // Auto-switch to transfers tab

        try {
            // Extract logical path from full path
            const logicalPath = extractLogicalPath(file.path);
            const url = `/apps/WebhostFileExplorer/api/v1/files/download?path=${encodeURIComponent(logicalPath)}`;

            logToServer(`downloadFile: Requesting ${url}`);

            // Create download link
            const response = await window.psweb_fetchWithAuthHandling(url, { signal: abortController.signal });

            if (!response.ok) {
                throw new Error(`Download failed: ${response.statusText}`);
            }

            // Read response as blob
            const blob = await response.blob();

            // Create download URL
            const downloadUrl = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = downloadUrl;
            a.download = file.name;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(downloadUrl);

            logToServer(`downloadFile: Completed ${file.name}`);
            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, status: 'completed', progress: 100 }
                    : t
            ));
            showToast(`Download completed: ${file.name}`, 'success');
        } catch (err) {
            // Check if error is due to abort
            const isCancelled = err.name === 'AbortError' || err.message.includes('cancelled');

            if (isCancelled) {
                logToServer(`downloadFile CANCELLED: ${file.name}`);
                // Status already set to failed by cancelTransfer
            } else {
                logToServer(`downloadFile ERROR: ${err.message}`, 'Error', { fileName: file.name });
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? { ...t, status: 'failed', error: err.message }
                        : t
                ));
                showToast(`Download failed: ${file.name} - ${err.message}`, 'error');
            }
        } finally {
            // Always cleanup AbortController
            delete transferAbortControllers.current[transferId];
        }
    }, [showToast]);

    /**
     * Cancel transfer
     */
    const cancelTransfer = useCallback((transferId) => {
        logToServer(`cancelTransfer: ${transferId}`);

        // Abort the transfer if it has an AbortController
        const abortController = transferAbortControllers.current[transferId];
        if (abortController) {
            logToServer(`cancelTransfer: Aborting transfer ${transferId}`);
            abortController.abort();
        }

        // Update transfer status
        setTransfers(prev => prev.map(t =>
            t.id === transferId
                ? { ...t, status: 'failed', error: 'Cancelled by user' }
                : t
        ));
    }, []);

    /**
     * Retry transfer
     */
    const retryTransfer = useCallback(async (transferId) => {
        const transfer = transfers.find(t => t.id === transferId);
        if (!transfer) {
            logToServer(`retryTransfer: Transfer ${transferId} not found`);
            return;
        }

        logToServer(`retryTransfer: Retrying ${transfer.type} for ${transfer.fileName}`);

        // Remove failed transfer from list
        setTransfers(prev => prev.filter(t => t.id !== transferId));

        // Restart based on type
        if (transfer.type === 'upload') {
            // For uploads, we can't retry without the original File object
            // Best we can do is prompt user to select the file again
            showToast(`Please re-upload "${transfer.fileName}" using the Upload button`, 'info');
            logToServer(`retryTransfer: Upload retry requires user to re-select file`);
        } else if (transfer.type === 'download') {
            // For downloads, we have the file path and can retry
            if (transfer.filePath) {
                logToServer(`retryTransfer: Restarting download for ${transfer.filePath}`);
                const fileObj = {
                    name: transfer.fileName,
                    path: transfer.filePath,
                    size: transfer.fileSize,
                    type: 'file'
                };
                await downloadFile(fileObj);
            } else {
                showToast(`Cannot retry download: file path not saved`, 'error');
                logToServer(`retryTransfer: No filePath in transfer object`);
            }
        }
    }, [transfers, showToast, downloadFile]);

    /**
     * Pause transfer
     */
    const pauseTransfer = useCallback((transferId) => {
        logToServer(`pauseTransfer: ${transferId}`);

        // Abort the current transfer
        const abortController = transferAbortControllers.current[transferId];
        if (abortController) {
            logToServer(`pauseTransfer: Aborting transfer ${transferId}`);
            abortController.abort();
        }

        // Update transfer status to paused
        setTransfers(prev => prev.map(t =>
            t.id === transferId
                ? { ...t, status: 'paused' }
                : t
        ));

        showToast('Transfer paused. Select a method to resume.', 'info');
    }, [showToast]);

    /**
     * Resume transfer (with optional method switch)
     */
    const resumeTransfer = useCallback(async (transferId, newMethod) => {
        const fnStart = performance.now();

        // Log entry point
        logToServer(`resumeTransfer START: transferId=${transferId}, newMethod=${newMethod}`);

        const transfer = transfers.find(t => t.id === transferId);
        if (!transfer) {
            logToServer(`resumeTransfer ERROR: Transfer ${transferId} not found`, 'Error');
            return;
        }

        // Capture state BEFORE resume
        const stateBefore = {
            transferId: transfer.id,
            fileName: transfer.fileName,
            fileSize: transfer.fileSize,
            status: transfer.status,
            progress: transfer.progress,
            method: transfer.method,
            uploadGuid: transfer.uploadGuid || transfer.metadata?.uploadGuid,
            error: transfer.error,
            bytesTransferred: transfer.bytesTransferred,
            currentChunk: transfer.currentChunk,
            totalChunks: transfer.totalChunks,
            targetPath: transfer.targetPath
        };

        logToServer(`resumeTransfer: State BEFORE resume`, 'Info', { data: stateBefore });

        const oldMethod = transfer.method;
        logToServer(`resumeTransfer: Processing resume - oldMethod=${oldMethod}, newMethod=${newMethod}, uploadGuid=${transfer.uploadGuid}`);

        // Show file reselection modal
        logToServer(`resumeTransfer: Showing file reselection modal`);
        setFileReselectionModal({
            visible: true,
            transfer: transfer,
            onFileSelected: async (file) => {
                logToServer(`resumeTransfer: File selected - ${file.name} (${file.size} bytes)`);

                // Close modal
                setFileReselectionModal({ visible: false, transfer: null, onFileSelected: null, onCancel: null });

                // Update transfer status to 'validating'
                logToServer(`resumeTransfer TRANSITION: Status change paused/failed -> validating`);
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? { ...t, status: 'validating', error: null, statusMessage: 'Validating uploaded data...' }
                        : t
                ));

                // Perform progressive hash validation
                const uploadGuid = transfer.uploadGuid || transfer.metadata?.uploadGuid;
                logToServer(`resumeTransfer: Starting progressive hash validation for uploadGuid=${uploadGuid}`);

                showToast('Validating previously uploaded data...', 'info');

                const validationResult = await performProgressiveHashValidation(file, uploadGuid);

                logToServer(`resumeTransfer: Hash validation complete`, 'Info', {
                    data: {
                        validatedBytes: validationResult.validatedBytes,
                        totalServerBytes: validationResult.totalServerBytes,
                        percentValidated: validationResult.percentValidated,
                        rangeCount: validationResult.validatedRanges.length,
                        error: validationResult.error
                    }
                });

                if (validationResult.error) {
                    // Validation failed
                    logToServer(`resumeTransfer: Validation failed - ${validationResult.error}`, 'Error');
                    setTransfers(prev => prev.map(t =>
                        t.id === transferId
                            ? { ...t, status: 'failed', error: validationResult.error, statusMessage: null }
                            : t
                    ));
                    showToast(`Validation failed: ${validationResult.error}`, 'error');
                    return;
                }

                // Update transfer progress based on validated bytes
                const updatedProgress = Math.round((validationResult.validatedBytes / file.size) * 100);
                const updatedBytesTransferred = validationResult.validatedBytes;

                logToServer(`resumeTransfer: Updating transfer progress to ${updatedProgress}% (${updatedBytesTransferred} bytes)`, 'Info');

                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? {
                            ...t,
                            status: 'uploading',
                            error: null,
                            statusMessage: null,
                            progress: updatedProgress,
                            bytesTransferred: updatedBytesTransferred
                        }
                        : t
                ));

                // Show validation results to user
                if (validationResult.percentValidated > 0) {
                    showToast(
                        `Validated ${validationResult.percentValidated}% of upload - resuming from byte ${updatedBytesTransferred}`,
                        'success'
                    );
                } else {
                    showToast('No valid data found on server - starting fresh upload', 'info');
                }

                // Store resume info for upload
                const resumeInfo = {
                    fileName: transfer.fileName,
                    fileSize: transfer.fileSize,
                    uploadGuid: uploadGuid,
                    method: newMethod || oldMethod,
                    targetPath: transfer.targetPath,
                    transferId: transferId,
                    validatedBytes: validationResult.validatedBytes,
                    validatedRanges: validationResult.validatedRanges
                };

                logToServer(`resumeTransfer: Setting pendingResumeUpload and initiating upload`, 'Info', { data: resumeInfo });
                window.pendingResumeUpload = resumeInfo;

                // Trigger upload with the selected file
                // The upload logic will detect window.pendingResumeUpload and resume accordingly
                await uploadFile(file, transfer.targetPath);

                logToServer(`resumeTransfer END: Completed in ${(performance.now() - fnStart).toFixed(2)}ms`);
            },
            onCancel: () => {
                logToServer(`resumeTransfer: User cancelled file reselection`);
                setFileReselectionModal({ visible: false, transfer: null, onFileSelected: null, onCancel: null });

                // Reset transfer status back to paused
                setTransfers(prev => prev.map(t =>
                    t.id === transferId
                        ? { ...t, status: 'paused' }
                        : t
                ));
            }
        });

        logToServer(`resumeTransfer END: Modal shown (${(performance.now() - fnStart).toFixed(2)}ms)`);
    }, [transfers, showToast]);

    /**
     * Remove transfer from list
     */
    const removeTransfer = useCallback((transferId) => {
        logToServer(`removeTransfer: ${transferId}`);

        // Cleanup AbortController if it exists
        if (transferAbortControllers.current[transferId]) {
            delete transferAbortControllers.current[transferId];
        }

        setTransfers(prev => prev.filter(t => t.id !== transferId));
    }, []);

    /**
     * Compute SHA256 hash of file or range (client-side)
     * @param {File|Blob} file - File or blob to hash
     * @param {number} start - Start byte offset (optional, for range)
     * @param {number} end - End byte offset (optional, for range)
     * @returns {Promise<string>} - Hex string of SHA256 hash
     */
    const computeClientHash = useCallback(async (file, start = null, end = null) => {
        return new Promise((resolve, reject) => {
            const fileReader = new FileReader();

            fileReader.onload = async (e) => {
                try {
                    const arrayBuffer = e.target.result;
                    const hashBuffer = await crypto.subtle.digest('SHA-256', arrayBuffer);
                    const hashArray = Array.from(new Uint8Array(hashBuffer));
                    const hashHex = hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
                    resolve(hashHex);
                } catch (error) {
                    reject(error);
                }
            };

            fileReader.onerror = () => reject(fileReader.error);

            // Read file or range
            if (start !== null && end !== null) {
                const blob = file.slice(start, end + 1);
                fileReader.readAsArrayBuffer(blob);
            } else {
                fileReader.readAsArrayBuffer(file);
            }
        });
    }, []);

    /**
     * Perform progressive hash validation for resumed upload
     * Compares server-side and client-side hashes to determine which ranges are already uploaded
     * @param {File} file - Client-side file to validate
     * @param {string} uploadGuid - Upload GUID
     * @returns {Promise<Object>} - Validation result with validated ranges
     */
    const performProgressiveHashValidation = useCallback(async (file, uploadGuid) => {
        const fnStart = performance.now();
        logToServer(`performProgressiveHashValidation START: file=${file.name}, uploadGuid=${uploadGuid}`);

        try {
            // Request server-side hash data
            const url = `/apps/WebhostFileExplorer/api/v1/files/upload-validate?guid=${encodeURIComponent(uploadGuid)}`;
            logToServer(`performProgressiveHashValidation: Fetching server hashes from ${url}`);

            const response = await window.psweb_fetchWithAuthHandling(url);
            if (!response.ok) {
                throw new Error(`Failed to fetch server hash data: ${response.statusText}`);
            }

            const result = await response.json();
            if (result.status !== 'success') {
                throw new Error(result.message || 'Failed to get hash validation data');
            }

            const serverData = result.data;
            logToServer(`performProgressiveHashValidation: Server data received`, 'Info', {
                data: {
                    fileSize: serverData.fileSize,
                    rangeCount: serverData.rangeHashes.length,
                    rangeInterval: serverData.rangeInterval,
                    hashChunkSize: serverData.hashChunkSize
                }
            });

            // Validate file size matches
            if (serverData.fileSize === 0) {
                logToServer(`performProgressiveHashValidation: Server has no data yet`);
                return {
                    validatedRanges: [],
                    validatedBytes: 0,
                    totalServerBytes: 0,
                    percentValidated: 0
                };
            }

            const HASH_CHUNK_SIZE = serverData.hashChunkSize || 131072; // 128KB
            const RANGE_INTERVAL = serverData.rangeInterval || 10485760; // 10MB

            // Validate first 128KB hash
            logToServer(`performProgressiveHashValidation: Computing client-side first 128KB hash`);
            const firstSize = Math.min(HASH_CHUNK_SIZE, file.size);
            const clientFirstHash = await computeClientHash(file, 0, firstSize - 1);
            const firstHashMatches = clientFirstHash === serverData.firstHash;

            logToServer(`performProgressiveHashValidation: First hash comparison`, 'Info', {
                data: {
                    clientHash: clientFirstHash.substring(0, 16) + '...',
                    serverHash: serverData.firstHash.substring(0, 16) + '...',
                    matches: firstHashMatches
                }
            });

            if (!firstHashMatches) {
                logToServer(`performProgressiveHashValidation: First hash mismatch - files are different`, 'Warning');
                return {
                    validatedRanges: [],
                    validatedBytes: 0,
                    totalServerBytes: serverData.fileSize,
                    percentValidated: 0,
                    error: 'File content mismatch detected (first 128KB hash differs)'
                };
            }

            // Validate last 128KB hash (if file large enough)
            if (file.size > HASH_CHUNK_SIZE) {
                logToServer(`performProgressiveHashValidation: Computing client-side last 128KB hash`);
                const lastOffset = file.size - HASH_CHUNK_SIZE;
                const clientLastHash = await computeClientHash(file, lastOffset, file.size - 1);
                const lastHashMatches = clientLastHash === serverData.lastHash;

                logToServer(`performProgressiveHashValidation: Last hash comparison`, 'Info', {
                    data: {
                        clientHash: clientLastHash.substring(0, 16) + '...',
                        serverHash: serverData.lastHash.substring(0, 16) + '...',
                        matches: lastHashMatches
                    }
                });

                if (!lastHashMatches) {
                    // Last hash mismatch might mean server file is incomplete, not necessarily an error
                    logToServer(`performProgressiveHashValidation: Last hash mismatch - server file may be incomplete`, 'Info');
                }
            }

            // Validate range hashes (first 128KB of every 10MB range)
            const validatedRanges = [];
            let validatedBytes = 0;

            logToServer(`performProgressiveHashValidation: Validating ${serverData.rangeHashes.length} range hashes`);

            for (let i = 0; i < serverData.rangeHashes.length; i++) {
                const rangeInfo = serverData.rangeHashes[i];
                const offset = rangeInfo.offset;
                const size = rangeInfo.size;
                const serverHash = rangeInfo.hash;

                // Compute client-side hash for this range
                const endOffset = offset + size - 1;
                const clientHash = await computeClientHash(file, offset, endOffset);

                const matches = clientHash === serverHash;

                logToServer(`performProgressiveHashValidation: Range ${i + 1}/${serverData.rangeHashes.length}`, 'Debug', {
                    data: {
                        offset: offset,
                        size: size,
                        clientHash: clientHash.substring(0, 16) + '...',
                        serverHash: serverHash.substring(0, 16) + '...',
                        matches: matches
                    }
                });

                if (matches) {
                    // This range is validated
                    // Calculate how much data is validated (full 10MB range or remaining file size)
                    const rangeEnd = Math.min(offset + RANGE_INTERVAL, file.size);
                    const rangeBytes = rangeEnd - offset;

                    validatedRanges.push({
                        offset: offset,
                        size: rangeBytes,
                        hashMatches: true
                    });

                    validatedBytes += rangeBytes;

                    logToServer(`performProgressiveHashValidation: Range validated - offset=${offset}, size=${rangeBytes}`, 'Debug');
                } else {
                    // Hash mismatch - this range needs to be uploaded
                    logToServer(`performProgressiveHashValidation: Range mismatch - offset=${offset}, needs upload`, 'Info');
                    break; // Stop checking further ranges (assume corruption from this point)
                }
            }

            const percentValidated = Math.round((validatedBytes / file.size) * 100);

            logToServer(`performProgressiveHashValidation END: ${validatedBytes} / ${file.size} bytes validated (${percentValidated}%) (${(performance.now() - fnStart).toFixed(2)}ms)`, 'Info');

            return {
                validatedRanges: validatedRanges,
                validatedBytes: validatedBytes,
                totalServerBytes: serverData.fileSize,
                percentValidated: percentValidated,
                firstHashMatches: firstHashMatches
            };

        } catch (err) {
            logToServer(`performProgressiveHashValidation ERROR: ${err.message}`, 'Error');
            return {
                validatedRanges: [],
                validatedBytes: 0,
                totalServerBytes: 0,
                percentValidated: 0,
                error: err.message
            };
        }
    }, [computeClientHash]);

    /**
     * Validate transfer by comparing client and server hashes
     * @param {string} transferId - Transfer ID
     * @param {File} file - Original file
     * @returns {Promise<Object>} - Validation result
     */
    const validateTransfer = useCallback(async (transferId) => {
        const transfer = transfers.find(t => t.id === transferId);
        if (!transfer) {
            logToServer(`validateTransfer: Transfer ${transferId} not found`, 'Error');
            return { success: false, error: 'Transfer not found' };
        }

        logToServer(`validateTransfer: Starting validation for ${transfer.fileName}`);

        try {
            // Update transfer status
            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, validating: true, validationProgress: 0 }
                    : t
            ));

            // Compute client-side hash
            logToServer(`validateTransfer: Computing client-side hash...`);
            const clientHash = await computeClientHash(transfer.file);

            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, validationProgress: 50 }
                    : t
            ));

            logToServer(`validateTransfer: Client hash: ${clientHash}`);

            // Request server-side hash (with retry for file open errors)
            let serverHash = null;
            let retryCount = 0;
            const maxRetries = 3;

            while (retryCount <= maxRetries) {
                try {
                    logToServer(`validateTransfer: Requesting server hash (attempt ${retryCount + 1})...`);

                    const response = await window.psweb_fetchWithAuthHandling(
                        `/apps/WebhostFileExplorer/api/v1/files/validate?guid=${transfer.uploadGuid || transfer.metadata?.uploadGuid}`,
                        {
                            method: 'GET'
                        }
                    );

                    if (response.status === 409) {
                        // File open for writing - retry after delay
                        const errorData = await response.json();
                        const retryAfter = errorData.data?.retryAfter || 5;

                        logToServer(`validateTransfer: File open for writing, retrying in ${retryAfter}s...`, 'Warning');

                        if (retryCount < maxRetries) {
                            await new Promise(resolve => setTimeout(resolve, retryAfter * 1000));
                            retryCount++;
                            continue;
                        } else {
                            throw new Error(`File still open for writing after ${maxRetries} retries`);
                        }
                    }

                    if (!response.ok) {
                        const errorData = await response.json();
                        throw new Error(errorData.message || `Server returned ${response.status}`);
                    }

                    const result = await response.json();
                    serverHash = result.data.sha256;
                    break;  // Success
                }
                catch (error) {
                    if (retryCount >= maxRetries) {
                        throw error;
                    }
                    retryCount++;
                    await new Promise(resolve => setTimeout(resolve, 2000));
                }
            }

            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? { ...t, validationProgress: 100 }
                    : t
            ));

            logToServer(`validateTransfer: Server hash: ${serverHash}`);

            // Compare hashes
            const valid = clientHash === serverHash;

            logToServer(`validateTransfer: Validation ${valid ? 'PASSED' : 'FAILED'}`, valid ? 'Info' : 'Error');

            // Update transfer with validation result
            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? {
                        ...t,
                        validating: false,
                        validated: true,
                        validationPassed: valid,
                        clientHash,
                        serverHash
                    }
                    : t
            ));

            if (valid) {
                showToast(`✓ Validation passed for ${transfer.fileName}`, 'success');
            } else {
                showToast(`✗ Validation failed for ${transfer.fileName} - hashes don't match!`, 'error');
            }

            return {
                success: true,
                valid,
                clientHash,
                serverHash
            };
        }
        catch (error) {
            logToServer(`validateTransfer: Error: ${error.message}`, 'Error');

            setTransfers(prev => prev.map(t =>
                t.id === transferId
                    ? {
                        ...t,
                        validating: false,
                        validated: true,
                        validationPassed: false,
                        validationError: error.message
                    }
                    : t
            ));

            showToast(`Validation error: ${error.message}`, 'error');

            return {
                success: false,
                error: error.message
            };
        }
    }, [transfers, computeClientHash, showToast]);

    /**
     * Validate range of transfer
     * @param {string} transferId - Transfer ID
     * @param {File} file - Original file
     * @param {number} rangeStart - Start byte
     * @param {number} rangeEnd - End byte
     * @returns {Promise<Object>} - Validation result
     */
    const validateTransferRange = useCallback(async (transferId, rangeStart, rangeEnd) => {
        const transfer = transfers.find(t => t.id === transferId);
        if (!transfer) {
            return { success: false, error: 'Transfer not found' };
        }

        logToServer(`validateTransferRange: Validating bytes ${rangeStart}-${rangeEnd} for ${transfer.fileName}`);

        try {
            // Compute client-side hash of range
            const clientHash = await computeClientHash(transfer.file, rangeStart, rangeEnd);
            logToServer(`validateTransferRange: Client hash (range): ${clientHash}`);

            // Request server-side hash of same range
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/WebhostFileExplorer/api/v1/files/validate?guid=${transfer.uploadGuid || transfer.metadata?.uploadGuid}`,
                {
                    method: 'GET',
                    headers: {
                        'Range': `bytes=${rangeStart}-${rangeEnd}`
                    }
                }
            );

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.message || `Server returned ${response.status}`);
            }

            const result = await response.json();
            const serverHash = result.data.sha256;
            logToServer(`validateTransferRange: Server hash (range): ${serverHash}`);

            const valid = clientHash === serverHash;
            logToServer(`validateTransferRange: Range validation ${valid ? 'PASSED' : 'FAILED'}`, valid ? 'Info' : 'Error');

            return {
                success: true,
                valid,
                clientHash,
                serverHash,
                rangeStart,
                rangeEnd
            };
        }
        catch (error) {
            logToServer(`validateTransferRange: Error: ${error.message}`, 'Error');
            return {
                success: false,
                error: error.message
            };
        }
    }, [transfers, computeClientHash]);

    /**
     * Progressive hash validation for resume - narrows down difference location
     * @param {File} file - File to validate
     * @param {string} uploadGuid - Upload GUID for server comparison
     * @param {number} bytesCommitted - Bytes already committed on server
     * @returns {Promise<Object>} - Validation result with difference location
     */
    const progressiveHashValidation = useCallback(async (file, uploadGuid, bytesCommitted) => {
        logToServer(`progressiveHashValidation: Starting for ${file.name}, checking ${bytesCommitted} committed bytes`);

        try {
            // Phase 1: Check every 100MB
            const MB = 1024 * 1024;
            const chunkSize100MB = 100 * MB;
            let differenceStart = null;
            let differenceEnd = null;

            // Calculate how many 100MB chunks to check
            const totalChunks100MB = Math.ceil(bytesCommitted / chunkSize100MB);

            logToServer(`progressiveHashValidation: Phase 1 - Checking ${totalChunks100MB} chunks of 100MB...`);

            for (let i = 0; i < totalChunks100MB; i++) {
                const rangeStart = i * chunkSize100MB;
                const rangeEnd = Math.min((i + 1) * chunkSize100MB - 1, bytesCommitted - 1);

                logToServer(`progressiveHashValidation: Checking 100MB range ${rangeStart}-${rangeEnd}...`);

                // Compute client hash
                const clientHash = await computeClientHash(file, rangeStart, rangeEnd);

                // Request server hash
                const response = await window.psweb_fetchWithAuthHandling(
                    `/apps/WebhostFileExplorer/api/v1/files/validate?guid=${uploadGuid}`,
                    {
                        method: 'GET',
                        headers: {
                            'Range': `bytes=${rangeStart}-${rangeEnd}`
                        }
                    }
                );

                if (!response.ok) {
                    throw new Error(`Server validation failed: ${response.status}`);
                }

                const result = await response.json();
                const serverHash = result.data.sha256;

                if (clientHash !== serverHash) {
                    logToServer(`progressiveHashValidation: Mismatch found in 100MB chunk ${i} (${rangeStart}-${rangeEnd})`, 'Warning');
                    differenceStart = rangeStart;
                    differenceEnd = rangeEnd;
                    break;
                }
            }

            // If all 100MB chunks match, file is valid
            if (differenceStart === null) {
                logToServer(`progressiveHashValidation: All chunks match - file is valid up to ${bytesCommitted} bytes`);
                return {
                    valid: true,
                    bytesValidated: bytesCommitted,
                    message: 'Resume validation passed - all data matches'
                };
            }

            // Phase 2: Narrow down with 10MB chunks
            const chunkSize10MB = 10 * MB;
            logToServer(`progressiveHashValidation: Phase 2 - Narrowing down within ${differenceStart}-${differenceEnd} using 10MB chunks...`);

            const totalChunks10MB = Math.ceil((differenceEnd - differenceStart + 1) / chunkSize10MB);

            for (let i = 0; i < totalChunks10MB; i++) {
                const rangeStart = differenceStart + (i * chunkSize10MB);
                const rangeEnd = Math.min(differenceStart + ((i + 1) * chunkSize10MB) - 1, differenceEnd);

                logToServer(`progressiveHashValidation: Checking 10MB range ${rangeStart}-${rangeEnd}...`);

                const clientHash = await computeClientHash(file, rangeStart, rangeEnd);

                const response = await window.psweb_fetchWithAuthHandling(
                    `/apps/WebhostFileExplorer/api/v1/files/validate?guid=${uploadGuid}`,
                    {
                        method: 'GET',
                        headers: {
                            'Range': `bytes=${rangeStart}-${rangeEnd}`
                        }
                    }
                );

                if (!response.ok) {
                    throw new Error(`Server validation failed: ${response.status}`);
                }

                const result = await response.json();
                const serverHash = result.data.sha256;

                if (clientHash !== serverHash) {
                    logToServer(`progressiveHashValidation: Mismatch found in 10MB chunk ${i} (${rangeStart}-${rangeEnd})`, 'Warning');
                    differenceStart = rangeStart;
                    differenceEnd = rangeEnd;
                    break;
                }
            }

            // Phase 3: Narrow down with 1MB chunks
            const chunkSize1MB = 1 * MB;
            logToServer(`progressiveHashValidation: Phase 3 - Final narrowing within ${differenceStart}-${differenceEnd} using 1MB chunks...`);

            const totalChunks1MB = Math.ceil((differenceEnd - differenceStart + 1) / chunkSize1MB);

            for (let i = 0; i < totalChunks1MB; i++) {
                const rangeStart = differenceStart + (i * chunkSize1MB);
                const rangeEnd = Math.min(differenceStart + ((i + 1) * chunkSize1MB) - 1, differenceEnd);

                logToServer(`progressiveHashValidation: Checking 1MB range ${rangeStart}-${rangeEnd}...`);

                const clientHash = await computeClientHash(file, rangeStart, rangeEnd);

                const response = await window.psweb_fetchWithAuthHandling(
                    `/apps/WebhostFileExplorer/api/v1/files/validate?guid=${uploadGuid}`,
                    {
                        method: 'GET',
                        headers: {
                            'Range': `bytes=${rangeStart}-${rangeEnd}`
                        }
                    }
                );

                if (!response.ok) {
                    throw new Error(`Server validation failed: ${response.status}`);
                }

                const result = await response.json();
                const serverHash = result.data.sha256;

                if (clientHash !== serverHash) {
                    logToServer(`progressiveHashValidation: Mismatch found in 1MB chunk ${i} (${rangeStart}-${rangeEnd})`, 'Warning');
                    differenceStart = rangeStart;
                    differenceEnd = rangeEnd;
                    break;
                }
            }

            // Check if difference is in the first MB
            const isFirstMBDifferent = differenceStart < (1 * MB);

            logToServer(`progressiveHashValidation: Difference located at bytes ${differenceStart}-${differenceEnd}. First MB different: ${isFirstMBDifferent}`, 'Warning');

            return {
                valid: false,
                differenceStart,
                differenceEnd,
                isFirstMBDifferent,
                message: isFirstMBDifferent
                    ? 'Files are different from the beginning - overwrite confirmation needed'
                    : `Data differs starting at byte ${differenceStart}`
            };
        }
        catch (error) {
            logToServer(`progressiveHashValidation: Error: ${error.message}`, 'Error');
            return {
                valid: false,
                error: error.message,
                message: `Validation failed: ${error.message}`
            };
        }
    }, [computeClientHash]);

    /**
     * Handle resizing version info pane
     */
    const handleVersionPaneResize = useCallback((e) => {
        const container = e.target.closest('.pane-center');
        if (!container) return;

        const startY = e.clientY;
        const startHeight = versionPaneHeight;
        const containerHeight = container.offsetHeight;

        const handleMouseMove = (moveEvent) => {
            const deltaY = startY - moveEvent.clientY; // Negative when dragging up
            const newHeight = Math.min(
                Math.max(100, startHeight + deltaY), // Min 100px
                containerHeight * 0.8 // Max 80% of container
            );
            setVersionPaneHeight(newHeight);
        };

        const handleMouseUp = () => {
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);
        };

        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);
    }, [versionPaneHeight]);

    /**
     * Handle column resize - returns a function to be called onMouseDown
     */
    const handleColumnResize = useCallback((columnKey, headerElement) => {
        return (e) => {
            e.stopPropagation();
            const startX = e.clientX;
            const startWidth = headerElement.offsetWidth;

            const handleMouseMove = (moveEvent) => {
                const deltaX = moveEvent.clientX - startX;
                const newWidth = Math.max(50, startWidth + deltaX);  // Min 50px

                setColumnWidths(prev => ({
                    ...prev,
                    [columnKey]: newWidth
                }));
            };

            const handleMouseUp = () => {
                document.removeEventListener('mousemove', handleMouseMove);
                document.removeEventListener('mouseup', handleMouseUp);
            };

            document.addEventListener('mousemove', handleMouseMove);
            document.addEventListener('mouseup', handleMouseUp);
        };
    }, []);

    /**
     * Handle file selection from toolbar upload button
     */
    const handleUploadFilesSelect = useCallback((e) => {
        const files = e.target.files;
        if (files && files.length > 0) {
            logToServer(`handleUploadFilesSelect: ${files.length} files selected`);
            Array.from(files).forEach(file => {
                uploadFile(file, selectedTreePath);
            });
            // Reset input so same file can be uploaded again
            e.target.value = '';
        }
    }, [selectedTreePath, uploadFile]);

    /**
     * Menu/toolbar actions
     */
    /**
     * Perform delete operation
     */
    const performDelete = async (files) => {
        logToServer(`performDelete: Deleting ${files.length} items`);

        try {
            // Send all file paths in a single batch request
            const paths = files.map(f => f.path);

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action: 'delete',
                        paths: paths  // Send array of paths for batch delete
                    })
                }
            );

            if (!response.ok) {
                throw new Error(`Failed to delete files: ${response.statusText}`);
            }

            const result = await response.json();

            // Check if any errors occurred
            if (result.data && result.data.errors && result.data.errors.length > 0) {
                const errorMsg = result.data.errors.map(e => `${e.path}: ${e.error}`).join('\n');
                throw new Error(`Some files failed to delete:\n${errorMsg}`);
            }

            showToast(`Deleted ${result.data.count} item(s)`, 'success');

            // Clear selections and refresh both file list and tree
            handleClearSelections();
            setSelectedFile(null);
            loadFolderContents(selectedTreePath);
            refreshTreeNode(selectedTreePath);

        } catch (err) {
            logToServer(`performDelete ERROR: ${err.message}`, 'Error');
            showToast(`Delete failed: ${err.message}`, 'error');
        } finally {
            setDeleteConfirmDialog({ visible: false, files: [] });
        }
    };

    /**
     * Perform batch rename operation with conflict checking
     */
    const performRename = async (renames, options) => {
        const count = renames.length;
        logToServer(`performRename: Batch renaming ${count} items`);

        try {
            // Prepare batch rename request
            const renameOperations = renames.map(r => ({
                path: r.file.path,
                newName: r.newName
            }));

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action: 'batchRename',
                        renames: renameOperations,
                        checkConflicts: true  // Backend will check for conflicts first
                    })
                }
            );

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.message || `Failed to rename: ${response.statusText}`);
            }

            const result = await response.json();

            // Check for conflicts or errors
            if (result.data && result.data.conflicts && result.data.conflicts.length > 0) {
                // Show conflicts in dialog (keep dialog open)
                const conflictMsg = result.data.conflicts.map(c =>
                    `${c.oldName} → ${c.newName}: ${c.error}`
                ).join('\n');

                setRenameDialog(prev => ({
                    ...prev,
                    error: `Conflicts detected:\n${conflictMsg}`
                }));
                showToast('Some files have conflicts. Please review.', 'warning');
                return; // Don't close dialog
            }

            if (result.data && result.data.errors && result.data.errors.length > 0) {
                // Some renames failed
                const errorMsg = result.data.errors.map(e =>
                    `${e.path}: ${e.error}`
                ).join('\n');

                showToast(`Renamed ${result.data.renamed} of ${count} items. Errors:\n${errorMsg}`, 'warning');
            } else {
                // All succeeded
                showToast(`Renamed ${result.data.renamed} item(s)`, 'success');
            }

            // Clear selections and refresh both file list and tree
            handleClearSelections();
            setSelectedFile(null);
            loadFolderContents(selectedTreePath);
            refreshTreeNode(selectedTreePath);

            // Close dialog on success
            setRenameDialog({
                visible: false,
                files: [],
                pattern: '',
                replacement: '',
                mode: 'wildcard',
                error: null
            });

        } catch (err) {
            logToServer(`performRename ERROR: ${err.message}`, 'Error');

            // Show error in dialog (keep dialog open)
            setRenameDialog(prev => ({
                ...prev,
                error: err.message
            }));
            showToast(`Rename failed: ${err.message}`, 'error');
        }
    };

    /**
     * Create new folder
     */
    const createNewFolder = async (folderName) => {
        logToServer(`createNewFolder: Creating folder "${folderName}" in ${selectedTreePath}`);

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        action: 'createFolder',
                        path: selectedTreePath,
                        name: folderName
                    })
                }
            );

            if (!response.ok) {
                const errorData = await response.json();
                throw new Error(errorData.message || `Failed to create folder: ${response.statusText}`);
            }

            const result = await response.json();
            showToast(`Folder "${folderName}" created successfully`, 'success');

            // Refresh both file list and tree
            loadFolderContents(selectedTreePath);
            refreshTreeNode(selectedTreePath);
        } catch (err) {
            logToServer(`createNewFolder ERROR: ${err.message}`, 'Error');
            showToast(`Failed to create folder: ${err.message}`, 'error');
        }
    };

    /**
     * Toggle upload method preferences
     */
    const toggleUploadMethod = (method) => {
        setEnabledUploadMethods(prev => {
            const newMethods = {
                ...prev,
                [method]: !prev[method]
            };

            // Ensure at least one method is enabled
            if (!newMethods.streaming && !newMethods.websocket && !newMethods.putChunks) {
                showToast('At least one upload method must be enabled', 'warning');
                return prev; // Don't change if this would disable all methods
            }

            localStorage.setItem('fileExplorer_enabledUploadMethods', JSON.stringify(newMethods));
            logToServer(`Upload method ${method} ${!prev[method] ? 'enabled' : 'disabled'}`);
            showToast(`${method.charAt(0).toUpperCase() + method.slice(1)} upload ${!prev[method] ? 'enabled' : 'disabled'}`, 'info');
            return newMethods;
        });
    };

    // Legacy toggle function for backwards compatibility (WebSocket)
    const toggleWebSocket = () => toggleUploadMethod('websocket');

    /**
     * Toggle pipelining preference
     */
    const togglePipelining = () => {
        const newValue = !usePipelining;
        setUsePipelining(newValue);
        localStorage.setItem('fileExplorer_usePipelining', newValue.toString());
        logToServer(`WebSocket pipelining ${newValue ? 'enabled' : 'disabled'}`);
        showToast(`WebSocket pipelining ${newValue ? 'enabled' : 'disabled'}`, 'info');
    };

    /**
     * Update chunk size
     */
    const updateChunkSize = (sizeMB) => {
        const newSize = Math.max(5, Math.min(100, parseInt(sizeMB, 10) || 25)); // Clamp 5-100 MB
        setChunkSizeMB(newSize);
        localStorage.setItem('fileExplorer_chunkSizeMB', newSize.toString());
        logToServer(`Chunk size set to ${newSize}MB`);
        showToast(`Chunk size: ${newSize}MB (larger = faster but more memory)`, 'info');
    };

    const handleAction = (action) => {
        const fnStart = performance.now();
        logToServer(`handleAction START: action=${action}`);

        switch (action) {
            case 'newFolder':
                logToServer(`handleAction: Creating new folder`);
                // Prompt for folder name
                const folderName = prompt('Enter folder name:');
                if (folderName && folderName.trim()) {
                    createNewFolder(folderName.trim());
                }
                break;
            case 'uploadFiles':
                logToServer(`handleAction: Triggering file upload dialog`);
                // Trigger hidden file input click
                if (fileUploadInputRef.current) {
                    fileUploadInputRef.current.click();
                }
                break;
            case 'rename':
                if (selectedFile) {
                    setRenameDialog({ visible: true, file: selectedFile, newName: selectedFile.name });
                } else if (selectedFiles.length === 1) {
                    const file = currentFiles.find(f => f.path === selectedFiles[0]);
                    if (file) {
                        setRenameDialog({ visible: true, file, newName: file.name });
                    }
                } else {
                    showToast('Please select a single file or folder to rename', 'warning');
                }
                break;
            case 'delete':
                if (selectedFiles.length > 0) {
                    const filesToDelete = currentFiles.filter(f => selectedFiles.includes(f.path));
                    setDeleteConfirmDialog({ visible: true, files: filesToDelete });
                } else if (selectedFile) {
                    setDeleteConfirmDialog({ visible: true, files: [selectedFile] });
                } else {
                    showToast('Please select files or folders to delete', 'warning');
                }
                break;
            case 'togglePreview':
                setPreviewVisible(!previewVisible);
                break;
            case 'refresh':
                logToServer(`handleAction: Clearing caches and reloading...`);
                // Clear caches and reload
                fileDetailsCache.clear();
                versionInfoCache.clear();
                loadFolderContents(selectedTreePath);
                showToast('Refreshed', 'success');
                break;
            case 'about':
                showToast('File Explorer v2.0 - Incremental Tree Loading with LRU Caching', 'info');
                break;
            default:
                showToast(`Action not yet implemented: ${action}`, 'info');
        }

        logToServer(`handleAction END (${(performance.now() - fnStart).toFixed(2)}ms)`);
    };

    /**
     * Find node by path in tree
     */
    const findNodeByPath = (nodes, path) => {
        if (!Array.isArray(nodes)) {
            console.warn('[findNodeByPath] nodes is not an array:', nodes);
            return null;
        }
        for (const node of nodes) {
            if (node.path === path) return node;
            if (node.children) {
                const found = findNodeByPath(node.children, path);
                if (found) return found;
            }
        }
        return null;
    };

    /**
     * Refresh tree node by re-fetching its children
     * Used after create/rename/delete operations to update tree
     */
    const refreshTreeNode = async (path) => {
        const fnStart = performance.now();
        logToServer(`refreshTreeNode START: path=${path}`);

        const node = findNodeByPath(treeState.nodes, path);
        if (!node) {
            logToServer(`refreshTreeNode: Node not found in tree, skipping refresh`);
            return;
        }

        // Only refresh if node has been expanded before (has children or was previously loaded)
        if (!node.isExpanded && (!node.children || node.children.length === 0)) {
            logToServer(`refreshTreeNode: Node not expanded, skipping refresh`);
            return;
        }

        try {
            logToServer(`refreshTreeNode: Fetching updated children from server...`);
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/tree',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        treeState: treeState,
                        expandPath: path
                    })
                }
            );

            if (!response.ok) {
                throw new Error(`Failed to refresh tree node: ${response.statusText}`);
            }

            const result = await response.json();
            const expandedNode = result.expandedNode;
            logToServer(`refreshTreeNode: Received ${expandedNode.children.length} children`);

            // Update tree state with refreshed children
            setTreeState(prevState => {
                const updateNode = (nodes) => {
                    if (!Array.isArray(nodes)) {
                        return [];
                    }
                    return nodes.map(n => {
                        if (n.path === path) {
                            return {
                                ...n,
                                children: expandedNode.children
                            };
                        }
                        if (n.children) {
                            return { ...n, children: updateNode(n.children) };
                        }
                        return n;
                    });
                };
                return { ...prevState, nodes: updateNode(prevState.nodes) };
            });

            logToServer(`refreshTreeNode END (success) (${(performance.now() - fnStart).toFixed(2)}ms)`);
        } catch (err) {
            logToServer(`refreshTreeNode ERROR: ${err.message}`, 'Error');
            // Don't show toast - this is a background operation
        }
    };

    // Inline styles
    const styles = `
        .file-explorer-container {
            display: flex;
            flex-direction: column;
            height: 100%;
            width: 100%;
            background: #fff;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            font-size: 13px;
            color: #333;
        }
        .menu-bar {
            display: flex;
            background: #f5f5f5;
            border-bottom: 1px solid #ddd;
            padding: 4px 8px;
            gap: 4px;
        }
        .menu-item { position: relative; }
        .menu-button {
            background: none;
            border: none;
            padding: 6px 12px;
            cursor: pointer;
            font-size: 13px;
            border-radius: 3px;
            transition: background 0.15s;
        }
        .menu-button:hover { background: #e0e0e0; }
        .menu-dropdown {
            position: absolute;
            top: 100%;
            left: 0;
            background: #fff;
            border: 1px solid #ccc;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.15);
            min-width: 200px;
            z-index: 1000;
            margin-top: 2px;
        }
        .menu-dropdown-item {
            display: flex;
            align-items: center;
            padding: 8px 12px;
            cursor: pointer;
            transition: background 0.15s;
        }
        .menu-dropdown-item:hover { background: #f0f0f0; }
        .menu-icon { margin-right: 8px; font-size: 14px; }
        .menu-label { flex: 1; }
        .menu-shortcut { margin-left: 20px; font-size: 11px; color: #999; }
        .icon-toolbar {
            display: flex;
            background: #fafafa;
            border-bottom: 1px solid #ddd;
            padding: 6px 8px;
            gap: 4px;
        }
        .icon-toolbar-button {
            background: none;
            border: 1px solid transparent;
            padding: 6px 10px;
            cursor: pointer;
            font-size: 16px;
            border-radius: 4px;
            transition: all 0.15s;
        }
        .icon-toolbar-button:hover { background: #e8e8e8; border-color: #ccc; }
        .toolbar-settings-container {
            position: relative;
        }
        .settings-dropdown {
            position: absolute;
            top: 100%;
            right: 0;
            background: #fff;
            border: 1px solid #ccc;
            border-radius: 4px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            min-width: 280px;
            z-index: 1000;
            margin-top: 4px;
            padding: 12px;
        }
        .settings-section h4 {
            margin: 0 0 10px 0;
            font-size: 14px;
            font-weight: 600;
            color: #333;
            border-bottom: 1px solid #eee;
            padding-bottom: 6px;
        }
        .settings-description {
            font-size: 12px;
            color: rgba(0, 0, 0, 0.6);
            margin-bottom: 10px;
            line-height: 1.4;
        }
        .settings-checkbox {
            display: block;
            padding: 8px 0;
            cursor: pointer;
            user-select: none;
        }
        .settings-checkbox input[type="checkbox"] {
            margin-right: 8px;
            cursor: pointer;
            width: 16px;
            height: 16px;
            vertical-align: middle;
        }
        .settings-checkbox > span {
            font-size: 14px;
            color: #333;
            vertical-align: middle;
        }
        .method-info {
            display: block;
            font-size: 11px;
            color: rgba(0, 0, 0, 0.5);
            margin-left: 24px;
            margin-top: 2px;
        }
        .settings-sub-checkbox {
            margin-left: 24px;
        }
        .settings-warning {
            background: rgba(255, 152, 0, 0.2);
            border-left: 3px solid #FF9800;
            padding: 8px;
            margin-top: 10px;
            margin-bottom: 10px;
            font-size: 12px;
            color: #E65100;
        }
        .settings-help {
            padding: 6px 0;
            font-size: 12px;
            line-height: 1.4;
        }
        .settings-status {
            display: inline-block;
            padding: 4px 8px;
            border-radius: 3px;
            font-weight: 500;
        }
        .status-enabled {
            background: #e6f7e6;
            color: #2d8e2d;
        }
        .status-disabled {
            background: #fff3e0;
            color: #e67700;
        }
        .status-info {
            background: #e3f2fd;
            color: #1976d2;
        }
        .toast-container {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 10000;
            display: flex;
            flex-direction: column;
            gap: 10px;
            pointer-events: none;
        }
        .toast {
            min-width: 300px;
            max-width: 500px;
            padding: 12px 16px;
            border-radius: 4px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
            font-size: 0.9em;
            pointer-events: all;
            animation: slideInRight 0.3s ease-out;
        }
        @keyframes slideInRight {
            from { transform: translateX(100%); opacity: 0; }
            to { transform: translateX(0); opacity: 1; }
        }
        .toast-error {
            background: #fee;
            border-left: 4px solid #c00;
            color: #c00;
        }
        .toast-info {
            background: #e7f3ff;
            border-left: 4px solid #2196F3;
            color: #1976D2;
        }
        .toast-success {
            background: #e8f5e9;
            border-left: 4px solid #4CAF50;
            color: #2e7d32;
        }
        .file-explorer-content {
            display: flex;
            flex: 1;
            overflow: hidden;
        }
        .pane-tree {
            width: 220px;
            min-width: 150px;
            background: #f9f9f9;
            border-right: 1px solid #ddd;
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }
        .pane-center {
            flex: 1;
            display: flex;
            flex-direction: column;
            overflow: hidden;
        }
        .pane-file-list {
            flex: 1;
            min-height: 0;
            display: flex;
            flex-direction: column;
        }
        .pane-version-info {
            background: #fafafa;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }
        .splitter-horizontal-draggable {
            height: 4px;
            background: #ddd;
            cursor: row-resize;
            transition: background 0.15s;
        }
        .splitter-horizontal-draggable:hover {
            background: #0078d4;
        }
        .pane-preview {
            width: 300px;
            min-width: 200px;
            background: #fff;
            border-left: 1px solid #ddd;
            display: flex;
            flex-direction: column;
        }
        .splitter-vertical { width: 1px; background: #ddd; cursor: col-resize; }
        .splitter-horizontal { height: 1px; background: #ddd; cursor: row-resize; }
        .tree-navigation { display: flex; flex-direction: column; height: 100%; }
        .tree-header {
            padding: 8px 12px;
            font-weight: 600;
            background: #f0f0f0;
            border-bottom: 1px solid #ddd;
        }
        .tree-content { flex: 1; overflow-y: auto; padding: 4px 0; }
        .tree-node { user-select: none; }
        .tree-node-content {
            display: flex;
            align-items: center;
            padding: 4px 8px;
            cursor: pointer;
            transition: background 0.15s;
        }
        .tree-node-content:hover { background: #e8e8e8; }
        .tree-node-content.selected { background: #0078d4; color: #fff; }
        .tree-expand-button {
            background: none;
            border: none;
            cursor: pointer;
            padding: 0;
            margin-right: 4px;
            font-size: 10px;
            width: 16px;
            text-align: center;
        }
        .tree-icon { margin-right: 6px; font-size: 14px; }
        .tree-name { font-size: 13px; }
        .file-list { display: flex; flex-direction: column; height: 100%; background: #fff; }
        .file-list-header {
            display: flex;
            background: #f5f5f5;
            border-bottom: 1px solid #ddd;
            padding: 8px 12px;
            font-weight: 600;
            font-size: 12px;
        }
        .file-list-header-cell { padding: 0 8px; }
        .file-list-body { flex: 1; overflow-y: auto; }
        .file-list-row {
            display: flex;
            align-items: center;
            padding: 6px 12px;
            cursor: pointer;
            border-bottom: 1px solid #f0f0f0;
            transition: background 0.15s;
        }
        .file-list-row:hover { background: #f9f9f9; }
        .file-list-row.selected { background: #e6f2ff; }
        .file-list-cell {
            padding: 0 8px;
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .file-icon { margin-right: 8px; font-size: 16px; }
        .file-name { font-size: 13px; }
        .temp-upload-file {
            background: #fff3cd !important;
            border-left: 3px solid #ff9800;
        }
        .temp-upload-file:hover {
            background: #ffe4a3 !important;
        }
        .temp-file-badge {
            display: inline-block;
            margin-left: 8px;
            padding: 2px 6px;
            background: #ff9800;
            color: #fff;
            font-size: 10px;
            font-weight: 600;
            border-radius: 10px;
            vertical-align: middle;
        }
        .file-list-empty { padding: 40px; text-align: center; color: #999; font-style: italic; }
        .version-info-loading, .version-info-empty {
            padding: 20px;
            text-align: center;
            color: #999;
            font-style: italic;
        }
        .version-info-content { font-size: 12px; }
        .collapsible-section {
            margin-bottom: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            background: #fff;
        }
        .section-header {
            display: flex;
            align-items: center;
            padding: 8px 10px;
            cursor: pointer;
            background: #f8f8f8;
            border-radius: 4px 4px 0 0;
            user-select: none;
            transition: background 0.15s;
        }
        .section-header:hover { background: #f0f0f0; }
        .expand-icon { margin-right: 6px; font-size: 10px; color: #666; }
        .section-title { font-weight: 600; color: #333; }
        .section-summary { margin-left: 8px; color: #666; font-weight: normal; font-style: italic; }
        .section-content { padding: 8px 10px; }
        .section-content .collapsible-section { margin-left: 12px; background: #fafafa; }
        .property-row {
            display: flex;
            padding: 4px 0;
            border-bottom: 1px solid #f0f0f0;
        }
        .property-row:last-child { border-bottom: none; }
        .property-name { min-width: 120px; font-weight: 500; color: #555; }
        .property-value { flex: 1; color: #333; word-break: break-word; }
        .file-preview { display: flex; flex-direction: column; height: 100%; }
        .preview-header {
            display: flex;
            align-items: center;
            justify-content: space-between;
            padding: 8px 12px;
            font-weight: 600;
            background: #f0f0f0;
            border-bottom: 1px solid #ddd;
        }
        .preview-undock-button {
            background: none;
            border: 1px solid #ccc;
            padding: 4px 8px;
            cursor: pointer;
            font-size: 14px;
            border-radius: 3px;
            transition: all 0.15s;
        }
        .preview-undock-button:hover {
            background: #e8e8e8;
            border-color: #999;
        }
        .details-tabs {
            display: flex;
            background: #e8e8e8;
            border-bottom: 1px solid #ddd;
        }
        .details-tab {
            padding: 8px 16px;
            background: none;
            border: none;
            border-bottom: 2px solid transparent;
            cursor: pointer;
            font-size: 13px;
            transition: all 0.15s;
        }
        .details-tab:hover {
            background: #f0f0f0;
        }
        .details-tab.active {
            background: #fafafa;
            border-bottom-color: #0078d4;
            font-weight: 600;
        }
        .details-tab-content {
            flex: 1;
            overflow: auto;
        }
        .transfer-manager {
            display: flex;
            flex-direction: column;
            height: 100%;
            padding: 10px;
        }
        .transfer-drop-zone {
            border: 2px dashed #ccc;
            border-radius: 8px;
            padding: 30px;
            text-align: center;
            background: #f9f9f9;
            transition: all 0.2s;
            margin-bottom: 15px;
        }
        .transfer-drop-zone.dragging {
            border-color: #0078d4;
            background: #e6f2ff;
        }
        .transfer-select-button {
            padding: 10px 20px;
            background: #0078d4;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            transition: background 0.15s;
        }
        .transfer-select-button:hover {
            background: #005a9e;
        }
        .transfer-drop-text {
            margin-top: 10px;
            font-size: 12px;
            color: #666;
        }
        .transfer-list {
            flex: 1;
            overflow-y: auto;
        }
        .transfer-list-empty {
            padding: 30px;
            text-align: center;
            color: #999;
            font-style: italic;
        }
        .transfer-item {
            display: flex;
            align-items: center;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            margin-bottom: 8px;
            background: #fff;
            transition: background 0.15s, border-color 0.15s;
        }
        .transfer-item:hover {
            background: #f5f5f5;
        }
        .transfer-item.selected {
            background: #e3f2fd;
            border-color: #2196F3;
            box-shadow: 0 0 0 1px #2196F3;
        }
        .transfer-icon {
            font-size: 20px;
            margin-right: 10px;
            min-width: 30px;
            text-align: center;
        }
        .transfer-info {
            flex: 1;
            min-width: 0;
        }
        .transfer-name {
            font-weight: 500;
            font-size: 13px;
            display: flex;
            align-items: center;
            gap: 8px;
            white-space: nowrap;
            overflow: hidden;
        }
        .transfer-method-badge {
            display: inline-flex;
            align-items: center;
            gap: 4px;
            padding: 2px 8px;
            border-radius: 12px;
            font-size: 10px;
            font-weight: 600;
            white-space: nowrap;
            flex-shrink: 0;
        }
        .method-streaming {
            background: rgba(76, 175, 80, 0.2);
            color: #4CAF50;
        }
        .method-websocket {
            background: rgba(33, 150, 243, 0.2);
            color: #2196F3;
        }
        .method-putchunks {
            background: rgba(255, 152, 0, 0.2);
            color: #FF9800;
        }
        .transfer-info-button {
            background: none;
            border: none;
            cursor: pointer;
            font-size: 16px;
            padding: 4px;
            opacity: 0.7;
            transition: opacity 0.2s;
        }
        .transfer-info-button:hover {
            opacity: 1;
        }
        .transfer-details {
            display: flex;
            align-items: center;
            gap: 8px;
            margin-top: 4px;
            font-size: 11px;
            color: #666;
        }
        .transfer-progress-bar {
            flex: 1;
            height: 4px;
            background: #e0e0e0;
            border-radius: 2px;
            overflow: hidden;
        }
        .transfer-progress-fill {
            height: 100%;
            background: #0078d4;
            transition: width 0.3s;
        }
        .transfer-progress-text {
            min-width: 40px;
            text-align: right;
        }
        .transfer-progress-text .speed-current {
            color: #2196F3;
            font-weight: 500;
        }
        .transfer-progress-text .speed-average {
            color: #666;
            font-size: 11px;
        }
        .transfer-status {
            text-transform: capitalize;
        }
        .transfer-actions {
            display: flex;
            gap: 5px;
        }
        .transfer-actions button {
            background: none;
            border: 1px solid #ccc;
            padding: 4px 8px;
            cursor: pointer;
            border-radius: 3px;
            font-size: 14px;
            transition: all 0.15s;
        }
        .transfer-actions button:hover {
            background: #f0f0f0;
            border-color: #999;
        }
        .method-switch-select {
            padding: 4px 6px;
            font-size: 11px;
            border: 1px solid #ccc;
            border-radius: 3px;
            background: #fff;
            cursor: pointer;
            transition: all 0.15s;
        }
        .method-switch-select:hover {
            border-color: #999;
            background: #f9f9f9;
        }
        .method-switch-select:focus {
            outline: none;
            border-color: #2196F3;
            box-shadow: 0 0 0 2px rgba(33, 150, 243, 0.1);
        }
        .file-action-button {
            background: none;
            border: 1px solid #ccc;
            padding: 4px 8px;
            cursor: pointer;
            border-radius: 3px;
            font-size: 14px;
            transition: all 0.15s;
        }
        .file-action-button:hover {
            background: #e8e8e8;
            border-color: #999;
        }
        .version-info-panel {
            height: 100%;
            overflow-y: auto;
            padding: 8px;
        }
        .preview-content { flex: 1; overflow: auto; padding: 12px; }
        .preview-placeholder { text-align: center; padding: 40px 20px; color: #666; }
        .preview-empty { text-align: center; padding: 40px 20px; color: #999; font-style: italic; }
        .preview-loading { text-align: center; padding: 40px 20px; color: #666; }
        .preview-error { text-align: center; padding: 40px 20px; color: #f44336; }
        .preview-unsupported { text-align: center; padding: 40px 20px; color: #999; font-style: italic; }

        /* File list checkbox styles */
        .file-list-row.checked {
            background: #e6f2ff;
        }
        .file-list-row.checked:hover {
            background: #cce4ff;
        }

        /* Dialog styles */
        .dialog-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 10000;
        }
        .dialog-box {
            background: white;
            border-radius: 8px;
            box-shadow: 0 4px 20px rgba(0, 0, 0, 0.3);
            min-width: 400px;
            max-width: 600px;
            max-height: 80vh;
            display: flex;
            flex-direction: column;
        }
        .dialog-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 16px 20px;
            border-bottom: 1px solid #e0e0e0;
        }
        .dialog-header h3 {
            margin: 0;
            font-size: 18px;
            font-weight: 600;
        }
        .dialog-close {
            background: none;
            border: none;
            font-size: 24px;
            cursor: pointer;
            color: #666;
            padding: 0;
            width: 30px;
            height: 30px;
            line-height: 1;
        }
        .dialog-close:hover {
            color: #333;
        }
        .dialog-body {
            padding: 20px;
            overflow-y: auto;
            max-height: 60vh;
        }
        .dialog-body p {
            margin: 0 0 12px 0;
        }
        .dialog-body label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
        }
        .dialog-input {
            width: 100%;
            padding: 8px 12px;
            border: 1px solid #ccc;
            border-radius: 4px;
            font-size: 14px;
            margin-top: 4px;
        }
        .dialog-input:focus {
            outline: none;
            border-color: #0078d4;
            box-shadow: 0 0 0 3px rgba(0, 120, 212, 0.1);
        }
        .delete-file-list {
            list-style: none;
            padding: 0;
            margin: 12px 0;
            max-height: 200px;
            overflow-y: auto;
            border: 1px solid #e0e0e0;
            border-radius: 4px;
        }
        .delete-file-list li {
            padding: 8px 12px;
            border-bottom: 1px solid #f0f0f0;
            display: flex;
            align-items: center;
            gap: 8px;
        }
        .delete-file-list li:last-child {
            border-bottom: none;
        }
        .warning-text {
            color: #ff6b00;
            font-weight: 500;
            margin-top: 12px;
        }
        .dialog-footer {
            display: flex;
            justify-content: flex-end;
            gap: 12px;
            padding: 16px 20px;
            border-top: 1px solid #e0e0e0;
        }
        .dialog-button {
            padding: 8px 20px;
            border: none;
            border-radius: 4px;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            transition: all 0.15s;
        }
        .dialog-button:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .dialog-button-primary {
            background: #0078d4;
            color: white;
        }
        .dialog-button-primary:hover:not(:disabled) {
            background: #005a9e;
        }
        .dialog-button-secondary {
            background: #f0f0f0;
            color: #333;
        }
        .dialog-button-secondary:hover {
            background: #e0e0e0;
        }
        .dialog-button-danger {
            background: #d32f2f;
            color: white;
        }
        .dialog-button-danger:hover {
            background: #b71c1c;
        }

        /* Bulk confirmation section */
        .bulk-confirm-section {
            margin-top: 15px;
            padding: 12px;
            background: #fff3e0;
            border: 1px solid #ff9800;
            border-radius: 4px;
        }

        .bulk-confirm-section label {
            display: block;
            margin-bottom: 8px;
            font-weight: 500;
            color: #e65100;
        }

        .bulk-confirm-input {
            width: 100%;
            padding: 8px 12px;
            border: 2px solid #ff9800;
            border-radius: 4px;
            font-size: 14px;
            font-family: inherit;
        }

        .bulk-confirm-input:focus {
            outline: none;
            border-color: #f57c00;
            box-shadow: 0 0 0 3px rgba(255, 152, 0, 0.1);
        }

        /* Transfer Metadata Modal */
        .transfer-metadata-modal {
            min-width: 500px;
            max-width: 700px;
        }

        .metadata-section {
            margin-bottom: 20px;
        }

        .metadata-section:last-child {
            margin-bottom: 0;
        }

        .metadata-section h4 {
            margin: 0 0 12px 0;
            font-size: 14px;
            font-weight: 600;
            color: #333;
            border-bottom: 1px solid #e0e0e0;
            padding-bottom: 8px;
        }

        .metadata-table {
            width: 100%;
            border-collapse: collapse;
        }

        .metadata-table tr {
            border-bottom: 1px solid #f0f0f0;
        }

        .metadata-table tr:last-child {
            border-bottom: none;
        }

        .metadata-table td {
            padding: 8px 12px;
            font-size: 13px;
            line-height: 1.4;
        }

        .metadata-label {
            font-weight: 500;
            color: #666;
            width: 35%;
            vertical-align: top;
        }

        .metadata-value {
            color: #333;
            word-wrap: break-word;
        }

        /* Minimum height for file explorer card */
        .file-explorer-container {
            min-height: 1200px; /* 40 blocks × 30px per block */
        }
    `;

    // Four-pane layout
    // Disabled: Too verbose during uploads
    // logToServer(`=== RENDER START === (total setup time: ${(performance.now() - startTime).toFixed(2)}ms)`);
    // logToServer(`Render state: treeState.nodes.length=${treeState.nodes.length}, currentFiles.length=${currentFiles.length}, selectedTreePath=${selectedTreePath}`);

    return (
        <>
            <style>{styles}</style>
            <div className="file-explorer-container">
                {/* Hidden file input for toolbar upload button */}
                <input
                    ref={fileUploadInputRef}
                    type="file"
                    multiple
                    style={{ display: 'none' }}
                    onChange={handleUploadFilesSelect}
                />

                <MenuBar onAction={handleAction} />
                <IconToolbar
                    onAction={handleAction}
                    previewVisible={previewVisible}
                    enabledUploadMethods={enabledUploadMethods}
                    toggleUploadMethod={toggleUploadMethod}
                    usePipelining={usePipelining}
                    onTogglePipelining={togglePipelining}
                    chunkSizeMB={chunkSizeMB}
                    updateChunkSize={updateChunkSize}
                    showSettings={showSettings}
                    onToggleSettings={() => setShowSettings(!showSettings)}
                />

                {/* Toast notifications */}
                <div className="toast-container">
                    {toasts.map(toast => (
                        <div key={toast.id} className={`toast toast-${toast.type}`}>
                            {toast.message}
                        </div>
                    ))}
                </div>

                {/* Delete Confirmation Dialog */}
                <DeleteConfirmDialog
                    visible={deleteConfirmDialog.visible}
                    files={deleteConfirmDialog.files}
                    onConfirm={performDelete}
                    onCancel={() => setDeleteConfirmDialog({ visible: false, files: [] })}
                />

                {/* Rename Dialog */}
                <RenameDialog
                    visible={renameDialog.visible}
                    file={renameDialog.file}
                    newName={renameDialog.newName}
                    onChange={(newName) => setRenameDialog(prev => ({ ...prev, newName }))}
                    onConfirm={performRename}
                    onCancel={() => setRenameDialog({ visible: false, file: null, newName: '' })}
                />

                {/* Transfer Metadata Modal */}
                <TransferMetadataModal
                    visible={metadataModal.visible}
                    transfer={metadataModal.transfer}
                    onClose={() => setMetadataModal({ visible: false, transfer: null })}
                />

                {/* Temp File Dialog */}
                <TempFileDialog
                    visible={tempFileDialog.visible}
                    file={tempFileDialog.file}
                    uploadGuid={tempFileDialog.uploadGuid}
                    onClose={() => setTempFileDialog({ visible: false, file: null, uploadGuid: null })}
                    onDelete={() => {
                        if (tempFileDialog.file) {
                            performDelete([tempFileDialog.file]);
                        }
                        setTempFileDialog({ visible: false, file: null, uploadGuid: null });
                    }}
                    onViewTransfer={tempFileDialog.activeTransfer ? () => {
                        setSelectedTransfer(tempFileDialog.activeTransfer);
                        setDetailsTab('transfers');
                        setPreviewVisible(true);
                        showToast('Showing active transfer for this temp file', 'info');
                    } : null}
                />

                {/* Resume Upload Dialog */}
                <ResumeDialog
                    visible={resumeDialog.visible}
                    file={resumeDialog.file}
                    resumeData={resumeDialog.resumeData}
                    onResume={resumeDialog.onResume}
                    onStartFresh={resumeDialog.onStartFresh}
                    onCancel={() => setResumeDialog({ visible: false, file: null, resumeData: null, onResume: null, onStartFresh: null })}
                />

                {/* File Action Modal */}
                <FileActionModal
                    visible={fileActionModal.visible}
                    file={fileActionModal.file}
                    onClose={() => setFileActionModal({ visible: false, file: null })}
                    onDownload={(file) => downloadFile(file)}
                    onEditText={(file) => {
                        setFileActionModal({ visible: false, file: null });
                        const logicalPath = extractLogicalPath(file.path);
                        window.openCard(
                            `/apps/WebhostFileExplorer/cards/text-editor?file=${encodeURIComponent(logicalPath)}`,
                            `Edit: ${file.name}`
                        );
                    }}
                    onEditHex={(file) => {
                        setFileActionModal({ visible: false, file: null });
                        const logicalPath = extractLogicalPath(file.path);
                        window.openCard(
                            `/apps/WebhostFileExplorer/cards/hex-editor?file=${encodeURIComponent(logicalPath)}`,
                            `Hex: ${file.name}`
                        );
                    }}
                    onShare={(file) => {
                        // Build logical path for the file
                        const logicalPath = buildTreePath(currentPath.bucket, file.path || file.name);

                        // Open File Sharing Modal in a card
                        window.openCard(
                            `/apps/WebhostFileExplorer/cards/file-sharing-modal?path=${encodeURIComponent(logicalPath)}`,
                            `Share: ${file.name}`
                        );

                        setFileActionModal({ visible: false, file: null });
                    }}
                />

                {/* File Reselection Modal */}
                <FileReselectionModal
                    visible={fileReselectionModal.visible}
                    transfer={fileReselectionModal.transfer}
                    onFileSelected={fileReselectionModal.onFileSelected}
                    onCancel={fileReselectionModal.onCancel}
                />

                <div className="file-explorer-content">
                    {/* Left: Tree Navigation */}
                    <div className="pane-tree">
                        {treeLoading ? (
                            <div className="tree-navigation">
                                <div className="tree-header">Folders</div>
                                <div className="tree-content" style={{ padding: '20px', textAlign: 'center', color: '#999' }}>
                                    Loading file locations...
                                </div>
                            </div>
                        ) : (
                            <TreeNavigation
                                treeState={treeState}
                                onExpand={handleTreeExpand}
                                onSelect={handleTreeSelect}
                                selectedPath={selectedTreePath}
                                expandingPath={expandingPath}
                            />
                        )}
                    </div>

                    <div className="splitter-vertical"></div>

                    {/* Center: File List + VersionInfo */}
                    <div className="pane-center">
                        <div className="pane-file-list" style={{ flex: `1 1 calc(100% - ${versionPaneHeight || 300}px)` }}>
                            <FileList
                                files={currentFiles}
                                selectedFile={selectedFile}
                                selectedFiles={selectedFiles}
                                onSelectFile={handleFileSelect}
                                onToggleSelect={handleToggleSelect}
                                onToggleSelectAll={handleToggleSelectAll}
                                onDoubleClick={handleFileDoubleClick}
                                onDownload={downloadFile}
                                columnWidths={columnWidths}
                                handleColumnResize={handleColumnResize}
                            />
                        </div>
                        <div
                            className="splitter-horizontal-draggable"
                            onMouseDown={handleVersionPaneResize}
                            title="Drag to resize"
                        ></div>
                        <div className="pane-version-info" style={{ height: `${versionPaneHeight || 300}px` }}>
                            {/* Tabs */}
                            <div className="details-tabs">
                                <button
                                    className={`details-tab ${detailsTab === 'info' ? 'active' : ''}`}
                                    onClick={() => setDetailsTab('info')}
                                >
                                    File Info
                                </button>
                                <button
                                    className={`details-tab ${detailsTab === 'transfers' ? 'active' : ''}`}
                                    onClick={() => setDetailsTab('transfers')}
                                >
                                    Transfers {transfers.length > 0 && `(${transfers.length})`}
                                </button>
                            </div>

                            {/* Tab Content */}
                            <div className="details-tab-content">
                                {detailsTab === 'info' ? (
                                    <VersionInfoPanel
                                        versionInfo={versionInfo}
                                        loading={versionInfoLoading}
                                    />
                                ) : (
                                    <TransferManager
                                        transfers={transfers}
                                        onUpload={uploadFile}
                                        onCancel={cancelTransfer}
                                        onRetry={retryTransfer}
                                        onRemove={removeTransfer}
                                        currentPath={selectedTreePath}
                                        onShowMetadata={(transfer) => setMetadataModal({ visible: true, transfer })}
                                        onTransferClick={handleTransferClick}
                                        selectedTransferId={selectedTransfer?.id}
                                        onPause={pauseTransfer}
                                        onResume={resumeTransfer}
                                        onValidate={validateTransfer}
                                    />
                                )}
                            </div>
                        </div>
                    </div>

                    {previewVisible && (
                        <>
                            <div className="splitter-vertical"></div>
                            <div className="pane-preview">
                                {detailsTab === 'transfers' && selectedTransfer ? (
                                    <TransferPreview transfer={selectedTransfer} />
                                ) : (
                                    <FilePreview file={selectedFile} visible={previewVisible} />
                                )}
                            </div>
                        </>
                    )}
                </div>
            </div>
        </>
    );
}

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['file-explorer'] = FileExplorer;
