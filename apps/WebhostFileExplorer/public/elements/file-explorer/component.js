/**
 * File Explorer Component - Three-Pane Layout
 *
 * Enhanced file management interface with:
 * - Three-pane layout (tree nav, file list, preview)
 * - Menu bar and icon toolbar
 * - Multi-select and drag-and-drop
 * - File preview capabilities
 * - Advanced download/upload with progress tracking
 */

const { useState, useEffect, useRef, useMemo, useCallback } = React;

// ============================================================================
// SUB-COMPONENTS
// ============================================================================

/**
 * MenuBar Component
 * Provides File, Edit, View, Help menus
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
            { label: 'Delete', action: 'delete', icon: '🗑️', shortcut: 'Delete' },
            { label: 'Copy', action: 'copy', icon: '📋', shortcut: 'Ctrl+C' },
            { label: 'Cut', action: 'cut', icon: '✂️', shortcut: 'Ctrl+X' },
            { label: 'Paste', action: 'paste', icon: '📄', shortcut: 'Ctrl+V' }
        ],
        View: [
            { label: 'List View', action: 'viewList', icon: '📄' },
            { label: 'Grid View', action: 'viewGrid', icon: '▦' },
            { label: 'Toggle Preview', action: 'togglePreview', icon: '👁️', shortcut: 'Ctrl+P' }
        ],
        Help: [
            { label: 'Keyboard Shortcuts', action: 'showShortcuts', icon: '⌨️' },
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
 * Quick access buttons for common actions
 */
const IconToolbar = ({ onAction, viewMode, previewVisible }) => {
    const tools = [
        { action: 'newFolder', icon: '📁', title: 'New Folder (Ctrl+Shift+N)' },
        { action: 'uploadFiles', icon: '📤', title: 'Upload Files (Ctrl+U)' },
        { action: 'downloadSelected', icon: '📥', title: 'Download Selected (Ctrl+D)' },
        { action: 'copy', icon: '📋', title: 'Copy (Ctrl+C)' },
        { action: 'cut', icon: '✂️', title: 'Cut (Ctrl+X)' },
        { action: 'paste', icon: '📄', title: 'Paste (Ctrl+V)' },
        { action: 'delete', icon: '🗑️', title: 'Delete (Delete)' },
        { action: 'rename', icon: '✏️', title: 'Rename (F2)' },
        { action: 'refresh', icon: '🔄', title: 'Refresh (F5)' },
        { action: viewMode === 'list' ? 'viewGrid' : 'viewList', icon: viewMode === 'list' ? '▦' : '📄', title: 'Toggle View' },
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
 * TreeNavigation Component
 * Left pane folder tree with expand/collapse
 */
const TreeNavigation = ({ fileTree, expandedFolders, onToggleFolder, onSelectFolder, selectedPath }) => {
    const renderTreeNode = (node, path = '', depth = 0) => {
        if (!node || node.type !== 'folder') return null;

        const nodePath = path ? `${path}/${node.name}` : node.name;
        const isExpanded = expandedFolders.has(nodePath);
        const isSelected = nodePath === selectedPath;
        const hasChildren = node.children && node.children.some(c => c.type === 'folder');

        return (
            <div key={nodePath} className="tree-node" style={{ paddingLeft: `${depth * 16}px` }}>
                <div
                    className={`tree-node-content ${isSelected ? 'selected' : ''}`}
                    onClick={() => onSelectFolder(nodePath, node)}
                >
                    {hasChildren && (
                        <button
                            className="tree-expand-button"
                            onClick={(e) => {
                                e.stopPropagation();
                                onToggleFolder(nodePath);
                            }}
                        >
                            {isExpanded ? '▼' : '▶'}
                        </button>
                    )}
                    <span className="tree-icon">📁</span>
                    <span className="tree-name">{node.name}</span>
                </div>
                {isExpanded && node.children && (
                    <div className="tree-children">
                        {node.children
                            .filter(c => c.type === 'folder')
                            .map(child => renderTreeNode(child, nodePath, depth + 1))}
                    </div>
                )}
            </div>
        );
    };

    return (
        <div className="tree-navigation">
            <div className="tree-header">Folders</div>
            <div className="tree-content">
                {fileTree ? renderTreeNode(fileTree) : <div className="tree-loading">Loading...</div>}
            </div>
        </div>
    );
};

/**
 * FileListPane Component
 * Center pane with file list and toolbar
 */
const FileListPane = ({
    files,
    selectedItems,
    onSelectItem,
    onDoubleClick,
    viewMode,
    sortBy,
    onSort,
    searchFilter,
    onSearchChange
}) => {
    const formatSize = (bytes) => {
        if (!bytes) return '-';
        const kb = bytes / 1024;
        if (kb < 1024) return `${kb.toFixed(1)} KB`;
        return `${(kb / 1024).toFixed(1)} MB`;
    };

    const formatDate = (dateStr) => {
        if (!dateStr) return '-';
        const date = new Date(dateStr);
        return date.toLocaleString();
    };

    const isSelected = (item) => selectedItems.some(si => si.name === item.name && si.type === item.type);

    const handleItemClick = (item, e) => {
        if (e.ctrlKey || e.metaKey) {
            // Multi-select with Ctrl/Cmd
            onSelectItem(item, 'toggle');
        } else if (e.shiftKey) {
            // Range select with Shift
            onSelectItem(item, 'range');
        } else {
            // Single select
            onSelectItem(item, 'single');
        }
    };

    if (viewMode === 'grid') {
        return (
            <div className="file-list-pane">
                <div className="file-list-toolbar">
                    <input
                        type="text"
                        className="search-input"
                        placeholder="Search files..."
                        value={searchFilter}
                        onChange={(e) => onSearchChange(e.target.value)}
                    />
                    <select className="sort-select" value={sortBy} onChange={(e) => onSort(e.target.value)}>
                        <option value="name">Name</option>
                        <option value="modified">Date Modified</option>
                        <option value="size">Size</option>
                        <option value="type">Type</option>
                    </select>
                </div>
                <div className="file-grid">
                    {files.length === 0 ? (
                        <div className="empty-state">
                            <div className="empty-icon">📂</div>
                            <div>No files in this folder</div>
                        </div>
                    ) : (
                        files.map(item => (
                            <div
                                key={`${item.type}-${item.name}`}
                                className={`file-grid-item ${isSelected(item) ? 'selected' : ''}`}
                                onClick={(e) => handleItemClick(item, e)}
                                onDoubleClick={() => onDoubleClick(item)}
                            >
                                <div className="file-grid-icon">
                                    {item.type === 'folder' ? '📁' : '📄'}
                                </div>
                                <div className="file-grid-name" title={item.name}>{item.name}</div>
                            </div>
                        ))
                    )}
                </div>
            </div>
        );
    }

    // List view
    return (
        <div className="file-list-pane">
            <div className="file-list-toolbar">
                <input
                    type="text"
                    className="search-input"
                    placeholder="Search files..."
                    value={searchFilter}
                    onChange={(e) => onSearchChange(e.target.value)}
                />
            </div>
            <div className="file-list">
                {files.length === 0 ? (
                    <div className="empty-state">
                        <div className="empty-icon">📂</div>
                        <div>No files in this folder</div>
                    </div>
                ) : (
                    <table className="file-table">
                        <thead>
                            <tr>
                                <th onClick={() => onSort('name')} className="sortable">
                                    Name {sortBy === 'name' && '▼'}
                                </th>
                                <th onClick={() => onSort('modified')} className="sortable">
                                    Date Modified {sortBy === 'modified' && '▼'}
                                </th>
                                <th onClick={() => onSort('type')} className="sortable">
                                    Type {sortBy === 'type' && '▼'}
                                </th>
                                <th onClick={() => onSort('size')} className="sortable">
                                    Size {sortBy === 'size' && '▼'}
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            {files.map(item => (
                                <tr
                                    key={`${item.type}-${item.name}`}
                                    className={`file-row ${isSelected(item) ? 'selected' : ''}`}
                                    onClick={(e) => handleItemClick(item, e)}
                                    onDoubleClick={() => onDoubleClick(item)}
                                >
                                    <td className="file-name">
                                        <span className="file-icon">
                                            {item.type === 'folder' ? '📁' : '📄'}
                                        </span>
                                        {item.name}
                                    </td>
                                    <td>{formatDate(item.modified)}</td>
                                    <td>{item.type === 'folder' ? 'Folder' : 'File'}</td>
                                    <td>{formatSize(item.size)}</td>
                                </tr>
                            ))}
                        </tbody>
                    </table>
                )}
            </div>
        </div>
    );
};

/**
 * PreviewPane Component
 * Right pane for file preview with text, image, PDF, audio, video support
 */
const PreviewPane = ({ previewFile, visible, onClose, onUndock, currentPath }) => {
    const [previewContent, setPreviewContent] = useState(null);
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState(null);

    useEffect(() => {
        if (!previewFile || previewFile.type === 'folder') {
            setPreviewContent(null);
            return;
        }

        // Determine file category
        const extension = previewFile.name.substring(previewFile.name.lastIndexOf('.')).toLowerCase();
        const textExtensions = ['.txt', '.md', '.js', '.json', '.xml', '.html', '.css', '.ps1', '.psm1', '.psd1', '.yaml', '.yml'];
        const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.svg', '.webp', '.bmp'];
        const pdfExtensions = ['.pdf'];
        const audioExtensions = ['.mp3', '.wav', '.ogg'];
        const videoExtensions = ['.mp4', '.webm'];

        let category = 'unknown';
        if (textExtensions.includes(extension)) category = 'text';
        else if (imageExtensions.includes(extension)) category = 'image';
        else if (pdfExtensions.includes(extension)) category = 'pdf';
        else if (audioExtensions.includes(extension)) category = 'audio';
        else if (videoExtensions.includes(extension)) category = 'video';

        if (category === 'unknown') {
            setPreviewContent({ category: 'unknown' });
            return;
        }

        // Load preview content
        setLoading(true);
        setError(null);

        const filePath = currentPath ? `${currentPath}/${previewFile.name}` : previewFile.name;
        const previewUrl = `/apps/WebhostFileExplorer/api/v1/files/preview?path=${encodeURIComponent(filePath)}&mode=content`;

        if (category === 'text') {
            // Fetch text content
            window.psweb_fetchWithAuthHandling(previewUrl)
                .then(res => {
                    if (!res.ok) throw new Error(`HTTP ${res.status}`);
                    return res.text();
                })
                .then(text => {
                    setPreviewContent({ category: 'text', text, extension });
                    setLoading(false);
                })
                .catch(err => {
                    setError(err.message);
                    setLoading(false);
                });
        } else {
            // For images, PDFs, audio, video - just set the URL
            setPreviewContent({ category, url: previewUrl });
            setLoading(false);
        }
    }, [previewFile, currentPath]);

    if (!visible) return null;

    const renderPreviewContent = () => {
        if (!previewFile) {
            return (
                <div className="preview-empty">
                    <div className="preview-empty-icon">👁️</div>
                    <div>Select a file to preview</div>
                </div>
            );
        }

        if (previewFile.type === 'folder') {
            return (
                <div className="preview-info">
                    <div className="preview-icon">📁</div>
                    <div className="preview-details">
                        <div className="preview-name">{previewFile.name}</div>
                        <div className="preview-metadata">
                            <div>Type: Folder</div>
                        </div>
                    </div>
                </div>
            );
        }

        if (loading) {
            return (
                <div className="preview-loading">
                    <div className="preview-loading-spinner">⏳</div>
                    <div>Loading preview...</div>
                </div>
            );
        }

        if (error) {
            return (
                <div className="preview-error">
                    <div className="preview-error-icon">⚠️</div>
                    <div>Error loading preview: {error}</div>
                </div>
            );
        }

        if (!previewContent) {
            return (
                <div className="preview-info">
                    <div className="preview-icon">📄</div>
                    <div className="preview-details">
                        <div className="preview-name">{previewFile.name}</div>
                        <div className="preview-metadata">
                            {previewFile.size && <div>Size: {(previewFile.size / 1024).toFixed(1)} KB</div>}
                            {previewFile.modified && <div>Modified: {new Date(previewFile.modified).toLocaleString()}</div>}
                        </div>
                    </div>
                </div>
            );
        }

        // Text preview with syntax highlighting
        if (previewContent.category === 'text') {
            const language = {
                '.js': 'javascript',
                '.json': 'json',
                '.html': 'html',
                '.css': 'css',
                '.xml': 'xml',
                '.ps1': 'powershell',
                '.psm1': 'powershell',
                '.psd1': 'powershell',
                '.md': 'markdown',
                '.yaml': 'yaml',
                '.yml': 'yaml'
            }[previewContent.extension] || 'plaintext';

            return (
                <div className="preview-text">
                    <div className="preview-text-header">
                        <span className="preview-text-lang">{language}</span>
                        <span className="preview-text-lines">{previewContent.text.split('\n').length} lines</span>
                    </div>
                    <pre className="preview-text-content">
                        <code className={`language-${language}`}>{previewContent.text}</code>
                    </pre>
                </div>
            );
        }

        // Image preview
        if (previewContent.category === 'image') {
            return (
                <div className="preview-image">
                    <img
                        src={previewContent.url}
                        alt={previewFile.name}
                        className="preview-image-img"
                        onError={(e) => {
                            e.target.style.display = 'none';
                            e.target.nextSibling.style.display = 'block';
                        }}
                    />
                    <div className="preview-error" style={{ display: 'none' }}>
                        <div className="preview-error-icon">⚠️</div>
                        <div>Failed to load image</div>
                    </div>
                </div>
            );
        }

        // PDF preview
        if (previewContent.category === 'pdf') {
            return (
                <div className="preview-pdf">
                    <iframe
                        src={previewContent.url}
                        className="preview-pdf-iframe"
                        title={previewFile.name}
                    />
                </div>
            );
        }

        // Audio preview
        if (previewContent.category === 'audio') {
            return (
                <div className="preview-audio">
                    <div className="preview-audio-icon">🎵</div>
                    <div className="preview-audio-name">{previewFile.name}</div>
                    <audio controls className="preview-audio-player">
                        <source src={previewContent.url} />
                        Your browser does not support audio playback.
                    </audio>
                </div>
            );
        }

        // Video preview
        if (previewContent.category === 'video') {
            return (
                <div className="preview-video">
                    <video controls className="preview-video-player">
                        <source src={previewContent.url} />
                        Your browser does not support video playback.
                    </video>
                </div>
            );
        }

        // Unknown file type
        return (
            <div className="preview-unknown">
                <div className="preview-unknown-icon">📄</div>
                <div className="preview-unknown-name">{previewFile.name}</div>
                <div className="preview-unknown-message">Preview not available for this file type</div>
            </div>
        );
    };

    // Determine if preview needs no padding (PDF, video)
    const noPadding = previewContent && (previewContent.category === 'pdf' || previewContent.category === 'video');

    return (
        <div className="preview-pane">
            <div className="preview-header">
                <span className="preview-title">Preview</span>
                <div className="preview-actions">
                    <button onClick={onUndock} title="Open in new card">🗗</button>
                    <button onClick={onClose} title="Close preview">✕</button>
                </div>
            </div>
            <div className={`preview-content ${noPadding ? 'no-padding' : ''}`}>
                {renderPreviewContent()}
            </div>
        </div>
    );
};

/**
 * DownloadManager Component
 * Manages download queue with resume capability and progress tracking
 */
const DownloadManager = ({ downloads, onRemove, onRetry, onClear }) => {
    if (downloads.length === 0) return null;

    const formatSize = (bytes) => {
        if (!bytes) return '0 KB';
        const kb = bytes / 1024;
        if (kb < 1024) return `${kb.toFixed(1)} KB`;
        const mb = kb / 1024;
        if (mb < 1024) return `${mb.toFixed(1)} MB`;
        return `${(mb / 1024).toFixed(1)} GB`;
    };

    const formatSpeed = (bytesPerSecond) => {
        return `${formatSize(bytesPerSecond)}/s`;
    };

    const getStatusIcon = (status) => {
        switch (status) {
            case 'downloading': return '⏬';
            case 'completed': return '✅';
            case 'failed': return '❌';
            case 'paused': return '⏸️';
            case 'queued': return '⏳';
            default: return '📥';
        }
    };

    const activeDownloads = downloads.filter(d => d.status === 'downloading' || d.status === 'queued');
    const completedDownloads = downloads.filter(d => d.status === 'completed');
    const failedDownloads = downloads.filter(d => d.status === 'failed');

    return (
        <div className="download-manager">
            <div className="download-manager-header">
                <span className="download-manager-title">
                    Downloads ({activeDownloads.length} active, {completedDownloads.length} completed)
                </span>
                <div className="download-manager-actions">
                    {completedDownloads.length > 0 && (
                        <button onClick={onClear} title="Clear completed">🗑️</button>
                    )}
                </div>
            </div>
            <div className="download-manager-list">
                {downloads.map(download => (
                    <div key={download.id} className={`download-item download-item-${download.status}`}>
                        <div className="download-icon">{getStatusIcon(download.status)}</div>
                        <div className="download-info">
                            <div className="download-name">{download.fileName}</div>
                            <div className="download-details">
                                {download.status === 'downloading' && (
                                    <>
                                        <span>{formatSize(download.downloaded)} / {formatSize(download.total)}</span>
                                        <span className="download-speed">{formatSpeed(download.speed || 0)}</span>
                                        <span>{download.progress}%</span>
                                    </>
                                )}
                                {download.status === 'completed' && (
                                    <span className="download-completed-text">
                                        {formatSize(download.total)} - Completed
                                    </span>
                                )}
                                {download.status === 'failed' && (
                                    <span className="download-error-text">
                                        Failed: {download.error || 'Unknown error'}
                                    </span>
                                )}
                                {download.status === 'queued' && (
                                    <span>Queued...</span>
                                )}
                            </div>
                            {download.status === 'downloading' && (
                                <div className="download-progress-bar">
                                    <div
                                        className="download-progress-fill"
                                        style={{ width: `${download.progress}%` }}
                                    />
                                </div>
                            )}
                        </div>
                        <div className="download-actions">
                            {download.status === 'failed' && (
                                <button onClick={() => onRetry(download.id)} title="Retry">🔄</button>
                            )}
                            <button onClick={() => onRemove(download.id)} title="Remove">✕</button>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
};

/**
 * UploadManager Component
 * Manages file uploads with chunking for large files and drag-and-drop support
 */
const UploadManager = ({ uploads, onRemove, onCancel }) => {
    if (uploads.length === 0) return null;

    const formatSize = (bytes) => {
        if (!bytes) return '0 KB';
        const kb = bytes / 1024;
        if (kb < 1024) return `${kb.toFixed(1)} KB`;
        const mb = kb / 1024;
        if (mb < 1024) return `${mb.toFixed(1)} MB`;
        return `${(mb / 1024).toFixed(1)} GB`;
    };

    const getStatusIcon = (status) => {
        switch (status) {
            case 'uploading': return '⏫';
            case 'completed': return '✅';
            case 'failed': return '❌';
            case 'queued': return '⏳';
            default: return '📤';
        }
    };

    const activeUploads = uploads.filter(u => u.status === 'uploading' || u.status === 'queued');
    const completedUploads = uploads.filter(u => u.status === 'completed');

    return (
        <div className="upload-manager">
            <div className="upload-manager-header">
                <span className="upload-manager-title">
                    Uploads ({activeUploads.length} active, {completedUploads.length} completed)
                </span>
            </div>
            <div className="upload-manager-list">
                {uploads.map(upload => (
                    <div key={upload.id} className={`upload-item upload-item-${upload.status}`}>
                        <div className="upload-icon">{getStatusIcon(upload.status)}</div>
                        <div className="upload-info">
                            <div className="upload-name">{upload.fileName}</div>
                            <div className="upload-details">
                                {upload.status === 'uploading' && (
                                    <>
                                        <span>{formatSize(upload.uploaded)} / {formatSize(upload.total)}</span>
                                        <span>{upload.progress}%</span>
                                        {upload.chunked && <span className="upload-chunked-badge">Chunked</span>}
                                    </>
                                )}
                                {upload.status === 'completed' && (
                                    <span className="upload-completed-text">
                                        {formatSize(upload.total)} - Completed
                                    </span>
                                )}
                                {upload.status === 'failed' && (
                                    <span className="upload-error-text">
                                        Failed: {upload.error || 'Unknown error'}
                                    </span>
                                )}
                                {upload.status === 'queued' && (
                                    <span>Queued...</span>
                                )}
                            </div>
                            {upload.status === 'uploading' && (
                                <div className="upload-progress-bar">
                                    <div
                                        className="upload-progress-fill"
                                        style={{ width: `${upload.progress}%` }}
                                    />
                                </div>
                            )}
                        </div>
                        <div className="upload-actions">
                            {upload.status === 'uploading' && (
                                <button onClick={() => onCancel(upload.id)} title="Cancel">⏸️</button>
                            )}
                            <button onClick={() => onRemove(upload.id)} title="Remove">✕</button>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
};

/**
 * Splitter Component
 * Resizable divider between panes
 */
const Splitter = ({ orientation = 'vertical', onResize }) => {
    const [isDragging, setIsDragging] = useState(false);

    useEffect(() => {
        if (!isDragging) return;

        const handleMouseMove = (e) => {
            onResize(e);
        };

        const handleMouseUp = () => {
            setIsDragging(false);
        };

        document.addEventListener('mousemove', handleMouseMove);
        document.addEventListener('mouseup', handleMouseUp);

        return () => {
            document.removeEventListener('mousemove', handleMouseMove);
            document.removeEventListener('mouseup', handleMouseUp);
        };
    }, [isDragging, onResize]);

    return (
        <div
            className={`splitter splitter-${orientation} ${isDragging ? 'dragging' : ''}`}
            onMouseDown={() => setIsDragging(true)}
        />
    );
};

// ============================================================================
// MAIN COMPONENT
// ============================================================================

const FileExplorerCard = ({ onError }) => {
    console.log('[FileExplorer] Component initializing (enhanced version)...');

    // State management
    const [fileTree, setFileTree] = useState(null);
    const [selectedItems, setSelectedItems] = useState([]);
    const [expandedFolders, setExpandedFolders] = useState(new Set(['root']));
    const [currentPath, setCurrentPath] = useState('');
    const [viewMode, setViewMode] = useState('list');
    const [sortBy, setSortBy] = useState('name');
    const [searchFilter, setSearchFilter] = useState('');
    const [previewFile, setPreviewFile] = useState(null);
    const [previewVisible, setPreviewVisible] = useState(true);
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [lastUpdate, setLastUpdate] = useState(null);

    // Pane sizes
    const [leftPaneWidth, setLeftPaneWidth] = useState(220);
    const [rightPaneWidth, setRightPaneWidth] = useState(300);

    // Dialogs
    const [showNewFolderDialog, setShowNewFolderDialog] = useState(false);
    const [newFolderName, setNewFolderName] = useState('');

    // Load file tree function (defined early to avoid TDZ issues in upload callbacks)
    const loadFileTree = useCallback(() => {
        console.log('[FileExplorer] Loading file tree...');

        window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/files')
            .then(res => {
                if (!res.ok) throw new Error(`HTTP ${res.status}`);
                return res.text();
            })
            .then(text => {
                const data = text ? JSON.parse(text) : null;
                setFileTree(data);
                setLastUpdate(new Date());
                console.log('[FileExplorer] File tree loaded successfully');
            })
            .catch(err => {
                if (err.name !== 'Unauthorized') {
                    console.error('[FileExplorer] Error loading file tree:', err);
                    onError({ message: err.message });
                }
            });
    }, [onError]);

    // Download manager
    const [downloads, setDownloads] = useState([]);
    const downloadQueueRef = useRef([]);
    const activeDownloadsRef = useRef(0);
    const MAX_CONCURRENT_DOWNLOADS = 3;

    // Load downloads from localStorage on mount
    useEffect(() => {
        try {
            const saved = localStorage.getItem('fileExplorerDownloads');
            if (saved) {
                const parsedDownloads = JSON.parse(saved);
                // Filter out completed/failed downloads older than 1 hour
                const oneHourAgo = Date.now() - 3600000;
                const recentDownloads = parsedDownloads.filter(d =>
                    d.status === 'downloading' || d.status === 'queued' ||
                    (d.timestamp && d.timestamp > oneHourAgo)
                );
                setDownloads(recentDownloads);
            }
        } catch (err) {
            console.error('[FileExplorer] Error loading downloads from localStorage:', err);
        }
    }, []);

    // Save downloads to localStorage whenever they change
    useEffect(() => {
        try {
            localStorage.setItem('fileExplorerDownloads', JSON.stringify(downloads));
        } catch (err) {
            console.error('[FileExplorer] Error saving downloads to localStorage:', err);
        }
    }, [downloads]);

    // Process download queue
    useEffect(() => {
        const processQueue = () => {
            if (activeDownloadsRef.current >= MAX_CONCURRENT_DOWNLOADS) return;

            const queuedDownload = downloads.find(d => d.status === 'queued');
            if (!queuedDownload) return;

            startDownload(queuedDownload.id);
        };

        processQueue();
    }, [downloads]);

    // Download functions
    const addDownload = useCallback((file, path) => {
        const downloadId = `download-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const newDownload = {
            id: downloadId,
            fileName: file.name,
            filePath: path ? `${path}/${file.name}` : file.name,
            total: file.size || 0,
            downloaded: 0,
            progress: 0,
            speed: 0,
            status: 'queued',
            error: null,
            retryCount: 0,
            timestamp: Date.now()
        };

        setDownloads(prev => [...prev, newDownload]);
        return downloadId;
    }, []);

    const startDownload = useCallback(async (downloadId) => {
        const download = downloads.find(d => d.id === downloadId);
        if (!download) return;

        activeDownloadsRef.current++;

        setDownloads(prev => prev.map(d =>
            d.id === downloadId ? { ...d, status: 'downloading', error: null } : d
        ));

        const downloadUrl = `/apps/WebhostFileExplorer/api/v1/files/download?path=${encodeURIComponent(download.filePath)}`;

        try {
            const startTime = Date.now();
            let lastUpdateTime = startTime;
            let lastDownloaded = download.downloaded;

            const response = await window.psweb_fetchWithAuthHandling(downloadUrl, {
                headers: download.downloaded > 0 ? {
                    'Range': `bytes=${download.downloaded}-`
                } : {}
            });

            if (!response.ok && response.status !== 206) {
                throw new Error(`HTTP ${response.status}`);
            }

            const contentLength = parseInt(response.headers.get('Content-Length') || '0');
            const totalSize = download.total || contentLength;

            const reader = response.body.getReader();
            const chunks = [];

            while (true) {
                const { done, value } = await reader.read();

                if (done) break;

                chunks.push(value);
                const downloadedBytes = download.downloaded + chunks.reduce((acc, chunk) => acc + chunk.length, 0);
                const progress = totalSize > 0 ? Math.round((downloadedBytes / totalSize) * 100) : 0;

                // Calculate speed
                const now = Date.now();
                const timeDiff = (now - lastUpdateTime) / 1000; // seconds
                const bytesDiff = downloadedBytes - lastDownloaded;
                const speed = timeDiff > 0 ? bytesDiff / timeDiff : 0;

                lastUpdateTime = now;
                lastDownloaded = downloadedBytes;

                setDownloads(prev => prev.map(d =>
                    d.id === downloadId ? {
                        ...d,
                        downloaded: downloadedBytes,
                        total: totalSize,
                        progress,
                        speed
                    } : d
                ));
            }

            // Create blob and download
            const blob = new Blob(chunks);
            const url = window.URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = download.fileName;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            window.URL.revokeObjectURL(url);

            // Mark as completed
            setDownloads(prev => prev.map(d =>
                d.id === downloadId ? { ...d, status: 'completed', progress: 100 } : d
            ));

        } catch (error) {
            console.error('[FileExplorer] Download error:', error);

            // Retry logic
            const retryCount = download.retryCount || 0;
            if (retryCount < 3) {
                setDownloads(prev => prev.map(d =>
                    d.id === downloadId ? {
                        ...d,
                        status: 'queued',
                        retryCount: retryCount + 1,
                        error: `Retrying (${retryCount + 1}/3)...`
                    } : d
                ));
            } else {
                setDownloads(prev => prev.map(d =>
                    d.id === downloadId ? {
                        ...d,
                        status: 'failed',
                        error: error.message || 'Download failed'
                    } : d
                ));
            }
        } finally {
            activeDownloadsRef.current--;
        }
    }, [downloads]);

    const removeDownload = useCallback((downloadId) => {
        setDownloads(prev => prev.filter(d => d.id !== downloadId));
    }, []);

    const retryDownload = useCallback((downloadId) => {
        setDownloads(prev => prev.map(d =>
            d.id === downloadId ? { ...d, status: 'queued', error: null, retryCount: 0 } : d
        ));
    }, []);

    const clearCompletedDownloads = useCallback(() => {
        setDownloads(prev => prev.filter(d => d.status !== 'completed'));
    }, []);

    // Upload manager
    const [uploads, setUploads] = useState([]);
    const [isDragging, setIsDragging] = useState(false);
    const uploadQueueRef = useRef([]);
    const activeUploadsRef = useRef(0);
    const MAX_CONCURRENT_UPLOADS = 2;
    const CHUNK_SIZE = 25 * 1024 * 1024; // 25MB

    // Process upload queue
    useEffect(() => {
        const processQueue = () => {
            if (activeUploadsRef.current >= MAX_CONCURRENT_UPLOADS) return;

            const queuedUpload = uploads.find(u => u.status === 'queued');
            if (!queuedUpload) return;

            startUpload(queuedUpload.id);
        };

        processQueue();
    }, [uploads]);

    // Upload functions
    const addUpload = useCallback((file) => {
        const uploadId = `upload-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
        const newUpload = {
            id: uploadId,
            fileName: file.name,
            file: file,
            total: file.size,
            uploaded: 0,
            progress: 0,
            status: 'queued',
            error: null,
            chunked: file.size > CHUNK_SIZE
        };

        setUploads(prev => [...prev, newUpload]);
        return uploadId;
    }, []);

    const startUpload = useCallback(async (uploadId) => {
        const upload = uploads.find(u => u.id === uploadId);
        if (!upload) return;

        activeUploadsRef.current++;

        setUploads(prev => prev.map(u =>
            u.id === uploadId ? { ...u, status: 'uploading', error: null } : u
        ));

        try {
            if (upload.chunked) {
                // Chunked upload for large files
                await uploadChunked(upload);
            } else {
                // Regular upload for small files
                await uploadRegular(upload);
            }

            // Mark as completed
            setUploads(prev => prev.map(u =>
                u.id === uploadId ? { ...u, status: 'completed', progress: 100 } : u
            ));

            // Refresh file tree
            loadFileTree();

        } catch (error) {
            console.error('[FileExplorer] Upload error:', error);
            setUploads(prev => prev.map(u =>
                u.id === uploadId ? {
                    ...u,
                    status: 'failed',
                    error: error.message || 'Upload failed'
                } : u
            ));
        } finally {
            activeUploadsRef.current--;
        }
    }, [uploads, currentPath, loadFileTree]);

    const uploadRegular = useCallback(async (upload) => {
        // Read file as base64
        const reader = new FileReader();
        const fileData = await new Promise((resolve, reject) => {
            reader.onload = () => resolve(reader.result);
            reader.onerror = reject;
            reader.readAsDataURL(upload.file);
        });

        // Extract base64 content (remove data:...;base64, prefix)
        const base64Content = fileData.split(',')[1];

        const response = await window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/files', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'uploadFile',
                path: currentPath,
                name: upload.fileName,
                content: base64Content,
                encoding: 'base64'
            })
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}`);
        }

        const result = await response.json();
        if (result.status !== 'success') {
            throw new Error(result.message || 'Upload failed');
        }
    }, [currentPath]);

    const uploadChunked = useCallback(async (upload) => {
        const totalChunks = Math.ceil(upload.total / CHUNK_SIZE);
        const uploadIdForChunks = `chunked-${upload.id}`;

        for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
            const start = chunkIndex * CHUNK_SIZE;
            const end = Math.min(start + CHUNK_SIZE, upload.total);
            const chunk = upload.file.slice(start, end);

            // Read chunk as base64
            const reader = new FileReader();
            const chunkData = await new Promise((resolve, reject) => {
                reader.onload = () => resolve(reader.result);
                reader.onerror = reject;
                reader.readAsDataURL(chunk);
            });

            // Extract base64 content
            const base64Chunk = chunkData.split(',')[1];

            const response = await window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/files/upload-chunk', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    uploadId: uploadIdForChunks,
                    fileName: upload.fileName,
                    path: currentPath,
                    chunkIndex: chunkIndex,
                    totalChunks: totalChunks,
                    chunkData: base64Chunk
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}`);
            }

            const result = await response.json();
            if (result.status !== 'success') {
                throw new Error(result.message || 'Chunk upload failed');
            }

            // Update progress
            const uploaded = end;
            const progress = Math.round((uploaded / upload.total) * 100);

            setUploads(prev => prev.map(u =>
                u.id === upload.id ? { ...u, uploaded, progress } : u
            ));
        }
    }, [currentPath]);

    const removeUpload = useCallback((uploadId) => {
        setUploads(prev => prev.filter(u => u.id !== uploadId));
    }, []);

    const cancelUpload = useCallback((uploadId) => {
        setUploads(prev => prev.map(u =>
            u.id === uploadId ? { ...u, status: 'failed', error: 'Cancelled by user' } : u
        ));
    }, []);

    // Drag and drop handlers
    const handleDragEnter = useCallback((e) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(true);
    }, []);

    const handleDragLeave = useCallback((e) => {
        e.preventDefault();
        e.stopPropagation();
        if (e.target === e.currentTarget) {
            setIsDragging(false);
        }
    }, []);

    const handleDragOver = useCallback((e) => {
        e.preventDefault();
        e.stopPropagation();
    }, []);

    const handleDrop = useCallback((e) => {
        e.preventDefault();
        e.stopPropagation();
        setIsDragging(false);

        const files = Array.from(e.dataTransfer.files);
        files.forEach(file => {
            addUpload(file);
        });
    }, [addUpload]);

    // Load file tree
    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            if (isMounted) {
                loadFileTree();
            }
        };

        fetchData();
        const interval = autoRefresh ? setInterval(fetchData, 60000) : null;

        return () => {
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh]);

    // Get current folder contents
    const getCurrentFolderContents = useCallback(() => {
        if (!fileTree) return [];

        let current = fileTree;
        if (currentPath) {
            const parts = currentPath.split('/').filter(p => p);
            for (const part of parts) {
                const found = current.children?.find(c => c.name === part && c.type === 'folder');
                if (!found) return [];
                current = found;
            }
        }

        let items = current.children || [];

        // Apply search filter
        if (searchFilter) {
            items = items.filter(item =>
                item.name.toLowerCase().includes(searchFilter.toLowerCase())
            );
        }

        // Apply sorting
        items = [...items].sort((a, b) => {
            // Folders first
            if (a.type !== b.type) {
                return a.type === 'folder' ? -1 : 1;
            }

            switch (sortBy) {
                case 'name':
                    return a.name.localeCompare(b.name);
                case 'modified':
                    return new Date(b.modified || 0) - new Date(a.modified || 0);
                case 'size':
                    return (b.size || 0) - (a.size || 0);
                case 'type':
                    return a.type.localeCompare(b.type);
                default:
                    return 0;
            }
        });

        return items;
    }, [fileTree, currentPath, searchFilter, sortBy]);

    const files = useMemo(() => getCurrentFolderContents(), [getCurrentFolderContents]);

    // Actions
    const handleMenuAction = useCallback((action) => {
        console.log('[FileExplorer] Menu action:', action);

        switch (action) {
            case 'newFolder':
                setShowNewFolderDialog(true);
                break;
            case 'uploadFiles':
                // Trigger file input
                const fileInput = document.createElement('input');
                fileInput.type = 'file';
                fileInput.multiple = true;
                fileInput.onchange = (e) => {
                    const files = Array.from(e.target.files);
                    files.forEach(file => addUpload(file));
                };
                fileInput.click();
                break;
            case 'downloadSelected':
                if (selectedItems.length > 0) {
                    const files = selectedItems.filter(item => item.type === 'file');
                    if (files.length === 0) {
                        alert('Please select files to download (folders are not supported yet)');
                        return;
                    }
                    files.forEach(file => {
                        addDownload(file, currentPath);
                    });
                } else {
                    alert('Please select files to download');
                }
                break;
            case 'refresh':
                loadFileTree();
                break;
            case 'viewList':
                setViewMode('list');
                break;
            case 'viewGrid':
                setViewMode('grid');
                break;
            case 'togglePreview':
                setPreviewVisible(!previewVisible);
                break;
            case 'rename':
                if (selectedItems.length === 1) {
                    console.log('Rename action - to be implemented');
                }
                break;
            case 'delete':
                if (selectedItems.length > 0) {
                    console.log('Delete action - to be implemented');
                }
                break;
            default:
                console.log('Action not yet implemented:', action);
        }
    }, [selectedItems, previewVisible, loadFileTree, addDownload, addUpload, currentPath]);

    const handleToggleFolder = useCallback((path) => {
        setExpandedFolders(prev => {
            const next = new Set(prev);
            if (next.has(path)) {
                next.delete(path);
            } else {
                next.add(path);
            }
            return next;
        });
    }, []);

    const handleSelectFolder = useCallback((path, node) => {
        setCurrentPath(path);
        setSelectedItems([]);
    }, []);

    const handleSelectItem = useCallback((item, mode) => {
        if (mode === 'single') {
            setSelectedItems([item]);
            setPreviewFile(item);
        } else if (mode === 'toggle') {
            setSelectedItems(prev => {
                const exists = prev.some(si => si.name === item.name && si.type === item.type);
                if (exists) {
                    return prev.filter(si => !(si.name === item.name && si.type === item.type));
                } else {
                    return [...prev, item];
                }
            });
        } else if (mode === 'range') {
            // Range select - simplified for now
            setSelectedItems(prev => [...prev, item]);
        }
    }, []);

    const handleDoubleClick = useCallback((item) => {
        if (item.type === 'folder') {
            const newPath = currentPath ? `${currentPath}/${item.name}` : item.name;
            setCurrentPath(newPath);
            setExpandedFolders(prev => new Set([...prev, newPath]));
        } else {
            console.log('Open file:', item.name);
            // File open action - to be implemented
        }
    }, [currentPath]);

    const handleUndockPreview = useCallback(() => {
        if (!previewFile) return;

        const filePath = currentPath ? `${currentPath}/${previewFile.name}` : previewFile.name;
        const previewUrl = `/apps/WebhostFileExplorer/api/v1/files/preview?path=${encodeURIComponent(filePath)}&mode=content`;

        // Open preview in new window
        const width = 900;
        const height = 700;
        const left = window.screenX + (window.outerWidth - width) / 2;
        const top = window.screenY + (window.outerHeight - height) / 2;

        window.open(
            previewUrl,
            `Preview: ${previewFile.name}`,
            `width=${width},height=${height},left=${left},top=${top},resizable=yes,scrollbars=yes`
        );
    }, [previewFile, currentPath]);

    const handleCreateFolder = useCallback(() => {
        if (!newFolderName) return;

        console.log('[FileExplorer] Creating folder:', newFolderName);

        window.psweb_fetchWithAuthHandling('/apps/WebhostFileExplorer/api/v1/files', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                action: 'createFolder',
                path: currentPath,
                name: newFolderName
            })
        })
        .then(res => res.json())
        .then(result => {
            if (result.status === 'success') {
                loadFileTree();
                setShowNewFolderDialog(false);
                setNewFolderName('');
            } else {
                throw new Error(result.message || 'Operation failed');
            }
        })
        .catch(err => {
            console.error('[FileExplorer] Error creating folder:', err);
            onError({ message: err.message });
        });
    }, [newFolderName, currentPath, loadFileTree, onError]);

    // Styles
    const styles = `
        /* Main container */
        .file-explorer-container {
            height: 100%;
            display: flex;
            flex-direction: column;
            background: var(--bg-color);
            color: var(--text-color);
        }

        /* Menu Bar */
        .menu-bar {
            display: flex;
            background: var(--title-bar-color, #2a2a2a);
            border-bottom: 1px solid var(--border-color);
            padding: 0;
        }

        .menu-item {
            position: relative;
        }

        .menu-button {
            padding: 8px 16px;
            background: transparent;
            border: none;
            color: var(--text-color);
            cursor: pointer;
            font-size: 0.9em;
        }

        .menu-button:hover {
            background: var(--accent-primary, #007acc);
        }

        .menu-dropdown {
            position: absolute;
            top: 100%;
            left: 0;
            background: var(--card-bg-color, #2a2a2a);
            border: 1px solid var(--border-color);
            min-width: 220px;
            box-shadow: 0 4px 8px rgba(0,0,0,0.3);
            z-index: 1000;
        }

        .menu-dropdown-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 8px 16px;
            cursor: pointer;
        }

        .menu-dropdown-item:hover {
            background: var(--accent-primary, #007acc);
        }

        .menu-icon {
            font-size: 1.1em;
        }

        .menu-label {
            flex: 1;
        }

        .menu-shortcut {
            font-size: 0.8em;
            color: var(--text-secondary, #888);
        }

        /* Icon Toolbar */
        .icon-toolbar {
            display: flex;
            gap: 4px;
            padding: 8px;
            background: var(--bg-color);
            border-bottom: 1px solid var(--border-color);
        }

        .icon-toolbar-button {
            padding: 6px 10px;
            background: transparent;
            border: 1px solid transparent;
            border-radius: 3px;
            font-size: 1.2em;
            cursor: pointer;
            color: var(--text-color);
        }

        .icon-toolbar-button:hover {
            background: var(--title-bar-color);
            border-color: var(--border-color);
        }

        /* Three-pane layout */
        .three-pane-layout {
            display: flex;
            flex: 1;
            overflow: hidden;
        }

        /* Tree Navigation */
        .tree-navigation {
            display: flex;
            flex-direction: column;
            background: var(--bg-color);
            border-right: 1px solid var(--border-color);
            overflow: hidden;
        }

        .tree-header {
            padding: 8px 12px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
            font-weight: bold;
            font-size: 0.9em;
        }

        .tree-content {
            flex: 1;
            overflow-y: auto;
            padding: 8px 0;
        }

        .tree-node-content {
            display: flex;
            align-items: center;
            gap: 4px;
            padding: 4px 8px;
            cursor: pointer;
            border-radius: 3px;
            margin: 2px 4px;
        }

        .tree-node-content:hover {
            background: var(--title-bar-color);
        }

        .tree-node-content.selected {
            background: var(--accent-primary);
        }

        .tree-expand-button {
            width: 16px;
            height: 16px;
            padding: 0;
            background: transparent;
            border: none;
            cursor: pointer;
            font-size: 0.7em;
            color: var(--text-color);
        }

        .tree-icon {
            font-size: 1.1em;
        }

        .tree-name {
            font-size: 0.9em;
        }

        /* File List Pane */
        .file-list-pane {
            display: flex;
            flex-direction: column;
            flex: 1;
            overflow: hidden;
        }

        .file-list-toolbar {
            display: flex;
            gap: 8px;
            padding: 8px;
            background: var(--bg-color);
            border-bottom: 1px solid var(--border-color);
        }

        .search-input {
            flex: 1;
            padding: 6px 12px;
            background: var(--card-bg-color);
            border: 1px solid var(--border-color);
            border-radius: 3px;
            color: var(--text-color);
            font-size: 0.9em;
        }

        .sort-select {
            padding: 6px 12px;
            background: var(--card-bg-color);
            border: 1px solid var(--border-color);
            border-radius: 3px;
            color: var(--text-color);
            font-size: 0.9em;
        }

        .file-list {
            flex: 1;
            overflow-y: auto;
        }

        .file-table {
            width: 100%;
            border-collapse: collapse;
        }

        .file-table th {
            text-align: left;
            padding: 8px 12px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
            font-size: 0.85em;
            font-weight: 600;
            cursor: pointer;
        }

        .file-table th.sortable:hover {
            background: var(--accent-primary);
        }

        .file-table td {
            padding: 6px 12px;
            border-bottom: 1px solid var(--border-color);
            font-size: 0.9em;
        }

        .file-row {
            cursor: pointer;
        }

        .file-row:hover {
            background: var(--title-bar-color);
        }

        .file-row.selected {
            background: var(--accent-primary);
        }

        .file-name {
            display: flex;
            align-items: center;
            gap: 8px;
        }

        .file-icon {
            font-size: 1.1em;
        }

        /* Grid view */
        .file-grid {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(120px, 1fr));
            gap: 12px;
            padding: 12px;
            overflow-y: auto;
        }

        .file-grid-item {
            display: flex;
            flex-direction: column;
            align-items: center;
            gap: 8px;
            padding: 12px;
            border: 1px solid transparent;
            border-radius: 4px;
            cursor: pointer;
        }

        .file-grid-item:hover {
            background: var(--title-bar-color);
            border-color: var(--border-color);
        }

        .file-grid-item.selected {
            background: var(--accent-primary);
            border-color: var(--accent-primary);
        }

        .file-grid-icon {
            font-size: 2.5em;
        }

        .file-grid-name {
            font-size: 0.85em;
            text-align: center;
            word-break: break-word;
            max-width: 100%;
        }

        /* Preview Pane */
        .preview-pane {
            display: flex;
            flex-direction: column;
            background: var(--bg-color);
            border-left: 1px solid var(--border-color);
            overflow: hidden;
        }

        .preview-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 8px 12px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
        }

        .preview-title {
            font-weight: bold;
            font-size: 0.9em;
        }

        .preview-actions {
            display: flex;
            gap: 4px;
        }

        .preview-actions button {
            padding: 4px 8px;
            background: transparent;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            cursor: pointer;
            color: var(--text-color);
        }

        .preview-actions button:hover {
            background: var(--accent-primary);
        }

        .preview-content {
            flex: 1;
            overflow-y: auto;
            padding: 16px;
        }

        .preview-content.no-padding {
            padding: 0;
        }

        .preview-info {
            display: flex;
            flex-direction: column;
            gap: 16px;
        }

        .preview-icon {
            font-size: 3em;
            text-align: center;
        }

        .preview-name {
            font-size: 1.1em;
            font-weight: bold;
            word-break: break-word;
        }

        .preview-metadata {
            font-size: 0.85em;
            color: var(--text-secondary);
        }

        .preview-metadata > div {
            margin-bottom: 4px;
        }

        .preview-placeholder {
            margin-top: 20px;
            padding: 20px;
            background: var(--title-bar-color);
            border-radius: 4px;
            text-align: center;
            font-size: 0.9em;
            color: var(--text-secondary);
        }

        .preview-empty {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 100%;
            gap: 12px;
            color: var(--text-secondary);
        }

        .preview-empty-icon {
            font-size: 3em;
            opacity: 0.5;
        }

        /* Preview states */
        .preview-loading,
        .preview-error,
        .preview-unknown {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 200px;
            gap: 12px;
            padding: 20px;
            text-align: center;
        }

        .preview-loading-spinner,
        .preview-error-icon,
        .preview-unknown-icon {
            font-size: 2.5em;
        }

        /* Text preview */
        .preview-text {
            display: flex;
            flex-direction: column;
            height: 100%;
        }

        .preview-text-header {
            display: flex;
            justify-content: space-between;
            padding: 8px 12px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
            font-size: 0.85em;
        }

        .preview-text-lang {
            font-weight: bold;
            text-transform: uppercase;
        }

        .preview-text-lines {
            color: var(--text-secondary);
        }

        .preview-text-content {
            flex: 1;
            margin: 0;
            padding: 12px;
            overflow: auto;
            font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
            font-size: 0.85em;
            line-height: 1.5;
            background: var(--card-bg-color);
            color: var(--text-color);
            white-space: pre-wrap;
            word-wrap: break-word;
        }

        .preview-text-content code {
            font-family: inherit;
            background: transparent;
            padding: 0;
        }

        /* Image preview */
        .preview-image {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            height: 100%;
        }

        .preview-image-img {
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }

        /* PDF preview */
        .preview-pdf {
            height: 100%;
        }

        .preview-pdf-iframe {
            width: 100%;
            height: 100%;
            border: none;
        }

        /* Audio preview */
        .preview-audio {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            gap: 16px;
            padding: 40px 20px;
        }

        .preview-audio-icon {
            font-size: 4em;
        }

        .preview-audio-name {
            font-weight: bold;
            text-align: center;
            word-break: break-word;
        }

        .preview-audio-player {
            width: 100%;
            max-width: 400px;
        }

        /* Video preview */
        .preview-video {
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            height: 100%;
        }

        .preview-video-player {
            max-width: 100%;
            max-height: 100%;
            border-radius: 4px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.2);
        }

        /* Splitter */
        .splitter {
            background: var(--border-color);
            cursor: col-resize;
            flex-shrink: 0;
        }

        .splitter-vertical {
            width: 4px;
        }

        .splitter-horizontal {
            height: 4px;
            cursor: row-resize;
        }

        .splitter.dragging {
            background: var(--accent-primary);
        }

        .splitter:hover {
            background: var(--accent-primary);
        }

        /* Empty state */
        .empty-state {
            display: flex;
            flex-direction: column;
            align-items: center;
            justify-content: center;
            height: 200px;
            gap: 12px;
            color: var(--text-secondary);
        }

        .empty-icon {
            font-size: 3em;
            opacity: 0.5;
        }

        /* Dialog */
        .dialog-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0,0,0,0.5);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 2000;
        }

        .dialog {
            background: var(--card-bg-color);
            padding: 20px;
            border-radius: 5px;
            border: 1px solid var(--border-color);
            min-width: 300px;
        }

        .dialog h3 {
            margin-top: 0;
        }

        .dialog input {
            width: 100%;
            padding: 8px;
            margin: 10px 0;
            border: 1px solid var(--border-color);
            background: var(--bg-color);
            color: var(--text-color);
            border-radius: 3px;
        }

        .dialog-buttons {
            display: flex;
            gap: 8px;
            justify-content: flex-end;
            margin-top: 15px;
        }

        .dialog-buttons button {
            padding: 6px 16px;
            border: 1px solid var(--border-color);
            background: var(--bg-color);
            color: var(--text-color);
            border-radius: 3px;
            cursor: pointer;
        }

        .dialog-buttons button:hover {
            background: var(--accent-primary);
        }

        /* Download Manager */
        .download-manager {
            position: fixed;
            bottom: 20px;
            right: 20px;
            width: 400px;
            max-height: 400px;
            background: var(--card-bg-color);
            border: 1px solid var(--border-color);
            border-radius: 5px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            display: flex;
            flex-direction: column;
            z-index: 1500;
        }

        .download-manager-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
            border-radius: 5px 5px 0 0;
        }

        .download-manager-title {
            font-weight: bold;
            font-size: 0.9em;
        }

        .download-manager-actions button {
            padding: 4px 8px;
            background: transparent;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            cursor: pointer;
            color: var(--text-color);
            font-size: 0.9em;
        }

        .download-manager-actions button:hover {
            background: var(--accent-primary);
        }

        .download-manager-list {
            flex: 1;
            overflow-y: auto;
            max-height: 340px;
        }

        .download-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
        }

        .download-item:last-child {
            border-bottom: none;
        }

        .download-item-downloading {
            background: var(--bg-color);
        }

        .download-item-completed {
            opacity: 0.7;
        }

        .download-item-failed {
            background: rgba(220, 53, 69, 0.1);
        }

        .download-icon {
            font-size: 1.5em;
            flex-shrink: 0;
        }

        .download-info {
            flex: 1;
            min-width: 0;
        }

        .download-name {
            font-weight: 500;
            font-size: 0.9em;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .download-details {
            display: flex;
            gap: 12px;
            margin-top: 4px;
            font-size: 0.75em;
            color: var(--text-secondary);
        }

        .download-speed {
            color: var(--accent-primary);
        }

        .download-completed-text {
            color: #28a745;
        }

        .download-error-text {
            color: #dc3545;
        }

        .download-progress-bar {
            width: 100%;
            height: 4px;
            background: var(--border-color);
            border-radius: 2px;
            margin-top: 6px;
            overflow: hidden;
        }

        .download-progress-fill {
            height: 100%;
            background: var(--accent-primary);
            transition: width 0.3s ease;
        }

        .download-actions {
            display: flex;
            gap: 4px;
            flex-shrink: 0;
        }

        .download-actions button {
            padding: 4px 8px;
            background: transparent;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            cursor: pointer;
            color: var(--text-color);
            font-size: 0.9em;
        }

        .download-actions button:hover {
            background: var(--accent-primary);
        }

        /* Upload Manager */
        .upload-manager {
            position: fixed;
            bottom: 20px;
            left: 20px;
            width: 400px;
            max-height: 400px;
            background: var(--card-bg-color);
            border: 1px solid var(--border-color);
            border-radius: 5px;
            box-shadow: 0 4px 12px rgba(0,0,0,0.3);
            display: flex;
            flex-direction: column;
            z-index: 1500;
        }

        .upload-manager-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 12px 16px;
            background: var(--title-bar-color);
            border-bottom: 1px solid var(--border-color);
            border-radius: 5px 5px 0 0;
        }

        .upload-manager-title {
            font-weight: bold;
            font-size: 0.9em;
        }

        .upload-manager-list {
            flex: 1;
            overflow-y: auto;
            max-height: 340px;
        }

        .upload-item {
            display: flex;
            align-items: center;
            gap: 12px;
            padding: 12px 16px;
            border-bottom: 1px solid var(--border-color);
        }

        .upload-item:last-child {
            border-bottom: none;
        }

        .upload-item-uploading {
            background: var(--bg-color);
        }

        .upload-item-completed {
            opacity: 0.7;
        }

        .upload-item-failed {
            background: rgba(220, 53, 69, 0.1);
        }

        .upload-icon {
            font-size: 1.5em;
            flex-shrink: 0;
        }

        .upload-info {
            flex: 1;
            min-width: 0;
        }

        .upload-name {
            font-weight: 500;
            font-size: 0.9em;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .upload-details {
            display: flex;
            gap: 12px;
            margin-top: 4px;
            font-size: 0.75em;
            color: var(--text-secondary);
            align-items: center;
        }

        .upload-chunked-badge {
            background: var(--accent-primary);
            color: white;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.85em;
        }

        .upload-completed-text {
            color: #28a745;
        }

        .upload-error-text {
            color: #dc3545;
        }

        .upload-progress-bar {
            width: 100%;
            height: 4px;
            background: var(--border-color);
            border-radius: 2px;
            margin-top: 6px;
            overflow: hidden;
        }

        .upload-progress-fill {
            height: 100%;
            background: var(--accent-primary);
            transition: width 0.3s ease;
        }

        .upload-actions {
            display: flex;
            gap: 4px;
            flex-shrink: 0;
        }

        .upload-actions button {
            padding: 4px 8px;
            background: transparent;
            border: 1px solid var(--border-color);
            border-radius: 3px;
            cursor: pointer;
            color: var(--text-color);
            font-size: 0.9em;
        }

        .upload-actions button:hover {
            background: var(--accent-primary);
        }

        /* Drag and Drop Overlay */
        .drag-drop-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 122, 204, 0.9);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 2000;
            pointer-events: none;
        }

        .drag-drop-content {
            text-align: center;
            color: white;
        }

        .drag-drop-icon {
            font-size: 5em;
            margin-bottom: 20px;
        }

        .drag-drop-text {
            font-size: 1.5em;
            font-weight: bold;
        }
    `;

    return (
        <>
            <style>{styles}</style>
            <div
                className="file-explorer-container"
                onDragEnter={handleDragEnter}
                onDragOver={handleDragOver}
                onDragLeave={handleDragLeave}
                onDrop={handleDrop}
            >
                <MenuBar onAction={handleMenuAction} />
                <IconToolbar
                    onAction={handleMenuAction}
                    viewMode={viewMode}
                    previewVisible={previewVisible}
                />
                <div className="three-pane-layout">
                    <div style={{ width: `${leftPaneWidth}px`, minWidth: '140px' }}>
                        <TreeNavigation
                            fileTree={fileTree}
                            expandedFolders={expandedFolders}
                            onToggleFolder={handleToggleFolder}
                            onSelectFolder={handleSelectFolder}
                            selectedPath={currentPath}
                        />
                    </div>
                    <Splitter
                        orientation="vertical"
                        onResize={(e) => {
                            const newWidth = Math.max(140, Math.min(400, e.clientX));
                            setLeftPaneWidth(newWidth);
                        }}
                    />
                    <FileListPane
                        files={files}
                        selectedItems={selectedItems}
                        onSelectItem={handleSelectItem}
                        onDoubleClick={handleDoubleClick}
                        viewMode={viewMode}
                        sortBy={sortBy}
                        onSort={setSortBy}
                        searchFilter={searchFilter}
                        onSearchChange={setSearchFilter}
                    />
                    {previewVisible && (
                        <>
                            <Splitter
                                orientation="vertical"
                                onResize={(e) => {
                                    const containerWidth = document.querySelector('.three-pane-layout').offsetWidth;
                                    const newWidth = Math.max(200, Math.min(600, containerWidth - e.clientX));
                                    setRightPaneWidth(newWidth);
                                }}
                            />
                            <div style={{ width: `${rightPaneWidth}px`, minWidth: '200px' }}>
                                <PreviewPane
                                    previewFile={previewFile}
                                    visible={previewVisible}
                                    currentPath={currentPath}
                                    onClose={() => setPreviewVisible(false)}
                                    onUndock={handleUndockPreview}
                                />
                            </div>
                        </>
                    )}
                </div>

                {/* Upload Manager */}
                <UploadManager
                    uploads={uploads}
                    onRemove={removeUpload}
                    onCancel={cancelUpload}
                />

                {/* Download Manager */}
                <DownloadManager
                    downloads={downloads}
                    onRemove={removeDownload}
                    onRetry={retryDownload}
                    onClear={clearCompletedDownloads}
                />

                {/* Drag and Drop Overlay */}
                {isDragging && (
                    <div className="drag-drop-overlay">
                        <div className="drag-drop-content">
                            <div className="drag-drop-icon">📁</div>
                            <div className="drag-drop-text">Drop files here to upload</div>
                        </div>
                    </div>
                )}

                {/* Dialogs */}
                {showNewFolderDialog && (
                    <div className="dialog-overlay" onClick={() => setShowNewFolderDialog(false)}>
                        <div className="dialog" onClick={(e) => e.stopPropagation()}>
                            <h3>Create New Folder</h3>
                            <input
                                type="text"
                                placeholder="Folder name"
                                value={newFolderName}
                                onChange={(e) => setNewFolderName(e.target.value)}
                                onKeyPress={(e) => e.key === 'Enter' && handleCreateFolder()}
                                autoFocus
                            />
                            <div className="dialog-buttons">
                                <button onClick={() => setShowNewFolderDialog(false)}>Cancel</button>
                                <button onClick={handleCreateFolder}>Create</button>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </>
    );
};

// Register component
console.log('[FileExplorer] Registering enhanced component...');
window.cardComponents = window.cardComponents || {};
window.cardComponents['file-explorer'] = FileExplorerCard;
console.log('[FileExplorer] Enhanced component registered successfully');
