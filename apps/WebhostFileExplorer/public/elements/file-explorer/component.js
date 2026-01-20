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
 * Extract display name from path
 */
function getDisplayName(path) {
    if (!path) return '';

    // Format: local|localhost|user:me/Documents
    const parts = path.split('|');
    if (parts.length === 3) {
        const logicalPath = parts[2];

        // Handle root buckets
        if (logicalPath === 'User:me') return 'My Files';
        if (logicalPath.startsWith('User:')) return `User: ${logicalPath.split(':')[1]}`;
        if (logicalPath.startsWith('Bucket:')) return `Bucket: ${logicalPath.split(':')[1]}`;
        if (logicalPath.startsWith('Site:')) return 'Site Files';
        if (logicalPath.startsWith('System:')) return `System: ${logicalPath.split(':')[1]}`;

        // Extract last segment for nested paths
        const segments = logicalPath.split('/');
        return segments[segments.length - 1] || logicalPath;
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
const IconToolbar = ({ onAction, previewVisible }) => {
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
                <span className="tree-name">{getDisplayName(node.path)}</span>
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
const FileList = ({ files, selectedFile, onSelectFile, onDoubleClick }) => {
    return (
        <div className="file-list">
            <div className="file-list-header">
                <div className="file-list-header-cell" style={{ flex: 2 }}>Name</div>
                <div className="file-list-header-cell" style={{ flex: 1 }}>Modified</div>
                <div className="file-list-header-cell" style={{ flex: 1 }}>Size</div>
                <div className="file-list-header-cell" style={{ flex: 1 }}>Type</div>
            </div>
            <div className="file-list-body">
                {files.length === 0 && (
                    <div className="file-list-empty">No files in this folder</div>
                )}
                {files.map(file => (
                    <div
                        key={file.path}
                        className={`file-list-row ${selectedFile?.path === file.path ? 'selected' : ''}`}
                        onClick={() => onSelectFile(file)}
                        onDoubleClick={() => onDoubleClick(file)}
                    >
                        <div className="file-list-cell" style={{ flex: 2 }}>
                            <span className="file-icon">{file.type === 'folder' ? '📁' : '📄'}</span>
                            <span className="file-name">{file.name}</span>
                        </div>
                        <div className="file-list-cell" style={{ flex: 1 }}>
                            {formatDate(file.modified)}
                        </div>
                        <div className="file-list-cell" style={{ flex: 1 }}>
                            {formatSize(file.size)}
                        </div>
                        <div className="file-list-cell" style={{ flex: 1 }}>
                            {file.type === 'folder' ? 'Folder' : (file.extension || '-')}
                        </div>
                    </div>
                ))}
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
    if (!visible) return null;

    return (
        <div className="file-preview">
            <div className="preview-header">Preview</div>
            <div className="preview-content">
                {file ? (
                    <div className="preview-placeholder">
                        <div>Preview for: {file.name}</div>
                        <div style={{ marginTop: '10px', fontSize: '12px', color: '#666' }}>
                            Preview functionality coming soon
                        </div>
                    </div>
                ) : (
                    <div className="preview-empty">No file selected</div>
                )}
            </div>
        </div>
    );
};

// ============================================================================
// MAIN COMPONENT
// ============================================================================

function FileExplorer({ cardId, cardInfo }) {
    const isMountedRef = useRef(true);

    // Tree state (incremental loading)
    const [treeState, setTreeState] = useState({
        nodes: [
            {
                path: "local|localhost|User:me",
                name: "My Files",
                isExpanded: false,
                hasContent: true,
                children: []
            }
        ]
    });

    const [expandingPath, setExpandingPath] = useState(null);
    const [selectedTreePath, setSelectedTreePath] = useState("local|localhost|User:me");
    const [currentFiles, setCurrentFiles] = useState([]);
    const [selectedFile, setSelectedFile] = useState(null);
    const [versionInfo, setVersionInfo] = useState(null);
    const [versionInfoLoading, setVersionInfoLoading] = useState(false);
    const [previewVisible, setPreviewVisible] = useState(false);
    const [error, setError] = useState(null);

    // Cleanup on unmount
    useEffect(() => {
        isMountedRef.current = true;
        return () => {
            isMountedRef.current = false;
        };
    }, []);

    // Load initial folder contents
    useEffect(() => {
        loadFolderContents(selectedTreePath);
    }, [selectedTreePath]);

    /**
     * Expand/collapse tree node
     */
    const handleTreeExpand = async (path, collapse = false) => {
        if (collapse) {
            // Collapse: just update isExpanded flag
            setTreeState(prevState => {
                const updateNode = (nodes) => {
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
            return;
        }

        // Expand: fetch children if not already loaded
        const node = findNodeByPath(treeState.nodes, path);
        if (node && node.children && node.children.length > 0) {
            // Already loaded, just expand
            setTreeState(prevState => {
                const updateNode = (nodes) => {
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
            return;
        }

        // Fetch children from server
        setExpandingPath(path);
        try {
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

            if (!isMountedRef.current) return;

            if (!response.ok) {
                throw new Error(`Failed to expand tree: ${response.statusText}`);
            }

            const result = await response.json();
            const expandedNode = result.expandedNode;

            // Update tree state with new children
            setTreeState(prevState => {
                const updateNode = (nodes) => {
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
        } catch (err) {
            console.error('[FileExplorer] Error expanding tree:', err);
            setError(`Failed to expand folder: ${err.message}`);
        } finally {
            if (isMountedRef.current) {
                setExpandingPath(null);
            }
        }
    };

    /**
     * Select tree node
     */
    const handleTreeSelect = (path) => {
        setSelectedTreePath(path);
        setSelectedFile(null);
        setVersionInfo(null);
    };

    /**
     * Load folder contents for center pane
     */
    const loadFolderContents = async (folderPath) => {
        // Check cache first
        const cached = fileDetailsCache.get(folderPath);
        if (cached) {
            console.log(`[FileExplorer] Using cached folder contents for: ${folderPath}`);
            setCurrentFiles(cached.data);
            return;
        }

        try {
            // Extract logical path from full path
            const logicalPath = folderPath.split('|')[2] || folderPath;
            const url = `/apps/WebhostFileExplorer/api/v1/files?path=${encodeURIComponent(logicalPath)}`;

            const response = await window.psweb_fetchWithAuthHandling(url);

            if (!isMountedRef.current) return;

            if (!response.ok) {
                throw new Error(`Failed to load folder: ${response.statusText}`);
            }

            const result = await response.json();
            const files = result.children || [];

            // Cache result
            fileDetailsCache.set(folderPath, files);
            setCurrentFiles(files);
        } catch (err) {
            console.error('[FileExplorer] Error loading folder:', err);
            setError(`Failed to load folder: ${err.message}`);
            setCurrentFiles([]);
        }
    };

    /**
     * Select file in center pane
     */
    const handleFileSelect = async (file) => {
        setSelectedFile(file);

        // Only load VersionInfo for files (not folders)
        if (file.type !== 'file') {
            setVersionInfo(null);
            return;
        }

        // Check cache first
        const cached = versionInfoCache.get(file.path);
        if (cached) {
            console.log(`[FileExplorer] Using cached version info for: ${file.path}`);
            setVersionInfo(cached.data);
            return;
        }

        // Fetch from backend
        setVersionInfoLoading(true);
        try {
            const url = `/apps/WebhostFileExplorer/api/v1/versioninfo?path=${encodeURIComponent(file.path)}`;
            const response = await window.psweb_fetchWithAuthHandling(url);

            if (!isMountedRef.current) return;

            if (!response.ok) {
                throw new Error(`Failed to load version info: ${response.statusText}`);
            }

            const result = await response.json();

            // Cache result
            versionInfoCache.set(file.path, result.versionInfo);
            setVersionInfo(result.versionInfo);
        } catch (err) {
            console.error('[FileExplorer] Error loading version info:', err);
            setVersionInfo(null);
        } finally {
            if (isMountedRef.current) {
                setVersionInfoLoading(false);
            }
        }
    };

    /**
     * Double-click file (expand folder or open file)
     */
    const handleFileDoubleClick = (file) => {
        if (file.type === 'folder') {
            // Navigate into folder
            setSelectedTreePath(file.path);
        } else {
            // TODO: Open file preview or download
            console.log('[FileExplorer] Open file:', file.path);
        }
    };

    /**
     * Menu/toolbar actions
     */
    const handleAction = (action) => {
        console.log('[FileExplorer] Action:', action);

        switch (action) {
            case 'togglePreview':
                setPreviewVisible(!previewVisible);
                break;
            case 'refresh':
                // Clear caches and reload
                fileDetailsCache.clear();
                versionInfoCache.clear();
                loadFolderContents(selectedTreePath);
                break;
            case 'about':
                alert('File Explorer v2.0\nIncremental Tree Loading\nLRU Caching\nVersionInfo Panel');
                break;
            default:
                alert(`Action not yet implemented: ${action}`);
        }
    };

    /**
     * Find node by path in tree
     */
    const findNodeByPath = (nodes, path) => {
        for (const node of nodes) {
            if (node.path === path) return node;
            if (node.children) {
                const found = findNodeByPath(node.children, path);
                if (found) return found;
            }
        }
        return null;
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
        .error-banner {
            background: #fee;
            border-bottom: 1px solid #fcc;
            padding: 8px 12px;
            display: flex;
            align-items: center;
            justify-content: space-between;
            color: #c00;
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
            height: 200px;
            min-height: 100px;
            border-top: 1px solid #ddd;
            background: #fafafa;
            overflow: auto;
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
        .file-list-empty { padding: 40px; text-align: center; color: #999; font-style: italic; }
        .version-info-panel { height: 100%; overflow-y: auto; padding: 8px; }
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
            padding: 8px 12px;
            font-weight: 600;
            background: #f0f0f0;
            border-bottom: 1px solid #ddd;
        }
        .preview-content { flex: 1; overflow: auto; padding: 12px; }
        .preview-placeholder { text-align: center; padding: 40px 20px; color: #666; }
        .preview-empty { text-align: center; padding: 40px 20px; color: #999; font-style: italic; }
    `;

    // Four-pane layout
    return (
        <>
            <style>{styles}</style>
            <div className="file-explorer-container">
                <MenuBar onAction={handleAction} />
                <IconToolbar onAction={handleAction} previewVisible={previewVisible} />

                {error && (
                    <div className="error-banner">
                        {error}
                        <button onClick={() => setError(null)}>✕</button>
                    </div>
                )}

                <div className="file-explorer-content">
                    {/* Left: Tree Navigation */}
                    <div className="pane-tree">
                        <TreeNavigation
                            treeState={treeState}
                            onExpand={handleTreeExpand}
                            onSelect={handleTreeSelect}
                            selectedPath={selectedTreePath}
                            expandingPath={expandingPath}
                        />
                    </div>

                    <div className="splitter-vertical"></div>

                    {/* Center: File List + VersionInfo */}
                    <div className="pane-center">
                        <div className="pane-file-list">
                            <FileList
                                files={currentFiles}
                                selectedFile={selectedFile}
                                onSelectFile={handleFileSelect}
                                onDoubleClick={handleFileDoubleClick}
                            />
                        </div>
                        <div className="splitter-horizontal"></div>
                        <div className="pane-version-info">
                            <VersionInfoPanel
                                versionInfo={versionInfo}
                                loading={versionInfoLoading}
                            />
                        </div>
                    </div>

                    {previewVisible && (
                        <>
                            <div className="splitter-vertical"></div>
                            <div className="pane-preview">
                                <FilePreview file={selectedFile} visible={previewVisible} />
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
