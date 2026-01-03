const { useState, useEffect } = React;

const FileExplorerCard = ({ onError }) => {
    console.log('[FileExplorer] Component initializing...');

    const [fileTree, setFileTree] = useState(null);
    const [currentPath, setCurrentPath] = useState('');
    const [selectedItem, setSelectedItem] = useState(null);
    const [showNewFolderDialog, setShowNewFolderDialog] = useState(false);
    const [showRenameDialog, setShowRenameDialog] = useState(false);
    const [showUploadDialog, setShowUploadDialog] = useState(false);
    const [newName, setNewName] = useState('');
    const [uploadContent, setUploadContent] = useState('');
    const [uploadFilename, setUploadFilename] = useState('');
    const [autoRefresh, setAutoRefresh] = useState(true);
    const [lastUpdate, setLastUpdate] = useState(null);

    console.log('[FileExplorer] Component state initialized');

    useEffect(() => {
        console.log('[FileExplorer] useEffect triggered - setting up auto-refresh');
        let isMounted = true;

        const fetchData = () => {
            if (isMounted) {
                console.log('[FileExplorer] Auto-refresh: loading file tree');
                loadFileTree();
            }
        };

        // Initial load
        fetchData();

        // Set up auto-refresh interval (60 seconds)
        const interval = autoRefresh ? setInterval(fetchData, 60000) : null;
        console.log('[FileExplorer] Auto-refresh interval set', { enabled: autoRefresh, intervalId: interval });

        return () => {
            console.log('[FileExplorer] useEffect cleanup - clearing interval');
            isMounted = false;
            if (interval) clearInterval(interval);
        };
    }, [autoRefresh]);

    const loadFileTree = () => {
        console.log('[FileExplorer] loadFileTree: Starting fetch...');
        let isMounted = true;

        window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/file-explorer')
            .then(res => {
                console.log('[FileExplorer] loadFileTree: Fetch response received', { ok: res.ok, status: res.status });
                if (!res.ok) {
                    if (isMounted) {
                        console.error('[FileExplorer] loadFileTree: Fetch failed', { status: res.status, statusText: res.statusText });
                        onError({ message: "Failed to fetch file explorer data", status: res.status, statusText: res.statusText });
                    }
                    throw new Error(`HTTP error! status: ${res.status}`);
                }
                return res.text();
            })
            .then(text => {
                console.log('[FileExplorer] loadFileTree: Response text received', { length: text?.length, preview: text?.substring(0, 100) });
                const data = text ? JSON.parse(text) : null;
                console.log('[FileExplorer] loadFileTree: Data parsed', { data });
                if (isMounted) {
                    setFileTree(data);
                    setLastUpdate(new Date());
                    console.log('[FileExplorer] loadFileTree: File tree state updated');
                }
            })
            .catch(err => {
                if (isMounted && err.name !== 'Unauthorized') {
                    console.error("[FileExplorer] loadFileTree: Error caught", err);
                    onError({ message: err.message, name: err.name });
                }
            });

        return () => {
            console.log('[FileExplorer] loadFileTree: Cleanup - setting isMounted to false');
            isMounted = false;
        };
    };

    const performAction = (action, data) => {
        console.log('[FileExplorer] performAction: Starting', { action, data });
        return window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/file-explorer', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ action, ...data })
        })
        .then(res => {
            console.log('[FileExplorer] performAction: Response received', { action, status: res.status });
            return res.json();
        })
        .then(result => {
            console.log('[FileExplorer] performAction: Result parsed', { action, result });
            if (result.status === 'success') {
                console.log('[FileExplorer] performAction: Success - reloading file tree');
                loadFileTree();
                return result;
            } else {
                console.error('[FileExplorer] performAction: Operation failed', { action, result });
                throw new Error(result.message || 'Operation failed');
            }
        })
        .catch(err => {
            console.error('[FileExplorer] performAction: Error caught', { action, error: err });
            onError({ message: err.message });
            throw err;
        });
    };

    const handleCreateFolder = () => {
        console.log('[FileExplorer] handleCreateFolder called', { newName, currentPath });
        if (!newName) {
            console.warn('[FileExplorer] handleCreateFolder: No name provided, aborting');
            return;
        }

        performAction('createFolder', {
            path: currentPath,
            name: newName
        }).then(() => {
            console.log('[FileExplorer] handleCreateFolder: Success - closing dialog');
            setShowNewFolderDialog(false);
            setNewName('');
        });
    };

    const handleUploadFile = () => {
        console.log('[FileExplorer] handleUploadFile called', { uploadFilename, contentLength: uploadContent?.length, currentPath });
        if (!uploadFilename || !uploadContent) {
            console.warn('[FileExplorer] handleUploadFile: Missing filename or content, aborting');
            return;
        }

        performAction('uploadFile', {
            path: currentPath,
            name: uploadFilename,
            content: uploadContent
        }).then(() => {
            console.log('[FileExplorer] handleUploadFile: Success - closing dialog');
            setShowUploadDialog(false);
            setUploadFilename('');
            setUploadContent('');
        });
    };

    const handleRename = () => {
        console.log('[FileExplorer] handleRename called', { selectedItem, newName, currentPath });
        if (!selectedItem || !newName) {
            console.warn('[FileExplorer] handleRename: Missing selectedItem or newName, aborting');
            return;
        }

        performAction('rename', {
            path: currentPath,
            oldName: selectedItem.name,
            newName: newName,
            isFolder: selectedItem.type === 'folder'
        }).then(() => {
            console.log('[FileExplorer] handleRename: Success - closing dialog');
            setShowRenameDialog(false);
            setNewName('');
            setSelectedItem(null);
        });
    };

    const handleDelete = (item) => {
        console.log('[FileExplorer] handleDelete called', { item, currentPath });
        if (!confirm(`Delete ${item.name}?`)) {
            console.log('[FileExplorer] handleDelete: User cancelled');
            return;
        }

        performAction('delete', {
            path: currentPath,
            name: item.name,
            isFolder: item.type === 'folder'
        }).then(() => {
            console.log('[FileExplorer] handleDelete: Success - clearing selection');
            setSelectedItem(null);
        });
    };

    const renderNode = (node, path = '') => {
        const nodePath = path ? `${path}/${node.name}` : node.name;
        const isSelected = selectedItem && selectedItem.name === node.name && selectedItem.path === nodePath;

        return (
            <li key={nodePath} className={`${node.type} ${isSelected ? 'selected' : ''}`}>
                <div className="node-item" onClick={() => {
                    console.log('[FileExplorer] Node clicked', { node, nodePath });
                    setSelectedItem({ ...node, path: nodePath });
                }}>
                    <span className="node-icon">{node.type === 'folder' ? '📁' : '📄'}</span>
                    <span className="node-name">{node.name}</span>
                    {node.type === 'file' && node.size && (
                        <span className="node-size">{(node.size / 1024).toFixed(2)} KB</span>
                    )}
                    <div className="node-actions" onClick={(e) => e.stopPropagation()}>
                        <button onClick={() => {
                            console.log('[FileExplorer] Rename button clicked', { node });
                            setSelectedItem({ ...node, path: nodePath });
                            setNewName(node.name);
                            setShowRenameDialog(true);
                        }} title="Rename">✏️</button>
                        <button onClick={() => {
                            console.log('[FileExplorer] Delete button clicked', { node });
                            handleDelete({ ...node, path: nodePath });
                        }} title="Delete">🗑️</button>
                    </div>
                </div>
                {node.type === 'folder' && node.children && node.children.length > 0 && (
                    <ul className="children">{node.children.map(child => renderNode(child, nodePath))}</ul>
                )}
            </li>
        );
    };

    const styles = `
        .file-explorer-container { height: 100%; display: flex; flex-direction: column; }
        .file-explorer-toolbar { display: flex; gap: 8px; padding: 8px; background: var(--title-bar-color); border-radius: 3px; margin-bottom: 10px; }
        .file-explorer-toolbar button { padding: 4px 12px; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color); border-radius: 3px; cursor: pointer; font-size: 0.85em; }
        .file-explorer-toolbar button:hover { background: var(--accent-primary); }
        .file-tree { list-style: none; padding-left: 0; flex: 1; overflow-y: auto; }
        .file-tree ul { list-style: none; padding-left: 20px; }
        .node-item { display: flex; align-items: center; gap: 8px; padding: 4px 8px; cursor: pointer; border-radius: 3px; }
        .node-item:hover { background: var(--title-bar-color); }
        .node-item.selected { background: var(--accent-primary); }
        .node-icon { font-size: 1.2em; }
        .node-name { flex: 1; font-size: 0.9em; }
        .node-size { font-size: 0.75em; color: var(--text-secondary); }
        .node-actions { display: none; gap: 4px; }
        .node-item:hover .node-actions { display: flex; }
        .node-actions button { padding: 2px 6px; font-size: 0.8em; border: none; background: transparent; cursor: pointer; }
        .node-actions button:hover { background: var(--bg-color); border-radius: 2px; }
        .dialog-overlay { position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.5); display: flex; align-items: center; justify-content: center; z-index: 1000; }
        .dialog { background: var(--card-bg-color); padding: 20px; border-radius: 5px; border: 1px solid var(--border-color); min-width: 300px; }
        .dialog h3 { margin-top: 0; }
        .dialog input, .dialog textarea { width: 100%; padding: 8px; margin: 10px 0; border: 1px solid var(--border-color); background: var(--bg-color); color: var(--text-color); border-radius: 3px; }
        .dialog textarea { min-height: 100px; font-family: monospace; }
        .dialog-buttons { display: flex; gap: 8px; justify-content: flex-end; margin-top: 15px; }
        .dialog-buttons button { padding: 6px 16px; }
    `;

    console.log('[FileExplorer] Rendering component', { fileTree, currentPath, selectedItem });

    return (
        <>
            <style>{styles}</style>
            <div className="file-explorer-container">
                <div className="file-explorer-toolbar">
                    <button onClick={() => {
                        console.log('[FileExplorer] New Folder button clicked');
                        setShowNewFolderDialog(true);
                    }}>📁 New Folder</button>
                    <button onClick={() => {
                        console.log('[FileExplorer] Upload File button clicked');
                        setShowUploadDialog(true);
                    }}>📤 Upload File</button>
                    <button onClick={() => {
                        console.log('[FileExplorer] Refresh button clicked');
                        loadFileTree();
                    }}>🔄 Refresh</button>
                    <button onClick={() => {
                        console.log('[FileExplorer] Auto-refresh toggled', { newState: !autoRefresh });
                        setAutoRefresh(!autoRefresh);
                    }}>{autoRefresh ? '⏸ Pause' : '▶ Resume'}</button>
                    {lastUpdate && (
                        <span style={{ fontSize: '0.85em', color: 'var(--text-secondary)', marginLeft: 'auto' }}>
                            Updated: {lastUpdate.toLocaleTimeString()}
                        </span>
                    )}
                </div>

                <div id="file-explorer-content">
                    {fileTree ? (
                        <ul className="file-tree">
                            {renderNode(fileTree)}
                        </ul>
                    ) : (
                        <p>Loading files...</p>
                    )}
                </div>

                {showNewFolderDialog && (
                    <div className="dialog-overlay" onClick={() => setShowNewFolderDialog(false)}>
                        <div className="dialog" onClick={(e) => e.stopPropagation()}>
                            <h3>Create New Folder</h3>
                            <input
                                type="text"
                                placeholder="Folder name"
                                value={newName}
                                onChange={(e) => setNewName(e.target.value)}
                                onKeyPress={(e) => e.key === 'Enter' && handleCreateFolder()}
                            />
                            <div className="dialog-buttons">
                                <button onClick={() => setShowNewFolderDialog(false)}>Cancel</button>
                                <button onClick={handleCreateFolder}>Create</button>
                            </div>
                        </div>
                    </div>
                )}

                {showUploadDialog && (
                    <div className="dialog-overlay" onClick={() => setShowUploadDialog(false)}>
                        <div className="dialog" onClick={(e) => e.stopPropagation()}>
                            <h3>Upload File</h3>
                            <input
                                type="text"
                                placeholder="Filename"
                                value={uploadFilename}
                                onChange={(e) => setUploadFilename(e.target.value)}
                            />
                            <textarea
                                placeholder="File content (text only)"
                                value={uploadContent}
                                onChange={(e) => setUploadContent(e.target.value)}
                            />
                            <div className="dialog-buttons">
                                <button onClick={() => setShowUploadDialog(false)}>Cancel</button>
                                <button onClick={handleUploadFile}>Upload</button>
                            </div>
                        </div>
                    </div>
                )}

                {showRenameDialog && (
                    <div className="dialog-overlay" onClick={() => setShowRenameDialog(false)}>
                        <div className="dialog" onClick={(e) => e.stopPropagation()}>
                            <h3>Rename {selectedItem?.type === 'folder' ? 'Folder' : 'File'}</h3>
                            <input
                                type="text"
                                placeholder="New name"
                                value={newName}
                                onChange={(e) => setNewName(e.target.value)}
                                onKeyPress={(e) => e.key === 'Enter' && handleRename()}
                            />
                            <div className="dialog-buttons">
                                <button onClick={() => setShowRenameDialog(false)}>Cancel</button>
                                <button onClick={handleRename}>Rename</button>
                            </div>
                        </div>
                    </div>
                )}
            </div>
        </>
    );
};

console.log('[FileExplorer] Registering component in window.cardComponents');
window.cardComponents['file-explorer'] = FileExplorerCard;
console.log('[FileExplorer] Component registered successfully', { registered: !!window.cardComponents['file-explorer'] });
