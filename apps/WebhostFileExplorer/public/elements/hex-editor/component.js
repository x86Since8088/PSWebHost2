/**
 * HexEditor Component - Hex dump viewer and editor
 *
 * Features:
 * - Hex dump display (16 bytes per row)
 * - ASCII preview column
 * - Byte editing (hex and ASCII)
 * - Search for hex patterns
 * - Jump-to-offset functionality
 * - Read-only and edit modes
 */

const HexEditor = ({ filePath, onClose, cardInfo }) => {
    const [data, setData] = React.useState(new Uint8Array());
    const [originalData, setOriginalData] = React.useState(new Uint8Array());
    const [loading, setLoading] = React.useState(true);
    const [saving, setSaving] = React.useState(false);
    const [modified, setModified] = React.useState(false);
    const [fileName, setFileName] = React.useState('');
    const [fileSize, setFileSize] = React.useState(0);
    const [readOnly, setReadOnly] = React.useState(true);

    // Navigation
    const [currentOffset, setCurrentOffset] = React.useState(0);
    const [bytesPerRow] = React.useState(16);
    const [visibleRows] = React.useState(24); // Rows to display at once

    // Search
    const [searchVisible, setSearchVisible] = React.useState(false);
    const [searchHex, setSearchHex] = React.useState('');
    const [searchResults, setSearchResults] = React.useState([]);
    const [currentSearchIndex, setCurrentSearchIndex] = React.useState(0);

    // Jump to offset
    const [jumpVisible, setJumpVisible] = React.useState(false);
    const [jumpOffset, setJumpOffset] = React.useState('');

    // Load file on mount
    React.useEffect(() => {
        loadFile();
    }, [filePath]);

    // Track modified state
    React.useEffect(() => {
        if (data.length > 0 && originalData.length > 0) {
            const isDifferent = data.some((byte, index) => byte !== originalData[index]);
            setModified(isDifferent);
        }
    }, [data, originalData]);

    // Keyboard shortcuts
    React.useEffect(() => {
        const handleKeyDown = (e) => {
            // Ctrl+S - Save
            if (e.ctrlKey && e.key === 's' && !readOnly) {
                e.preventDefault();
                saveFile();
            }
            // Ctrl+F - Find
            if (e.ctrlKey && e.key === 'f') {
                e.preventDefault();
                setSearchVisible(true);
            }
            // Ctrl+G - Jump to offset
            if (e.ctrlKey && e.key === 'g') {
                e.preventDefault();
                setJumpVisible(true);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [readOnly]);

    const loadFile = async () => {
        try {
            setLoading(true);
            window.logToServer(`HexEditor: Loading file ${filePath}`);

            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/WebhostFileExplorer/api/v1/files/content?path=${encodeURIComponent(filePath)}`
            );

            if (!response.ok) {
                throw new Error(`Failed to load file: ${response.statusText}`);
            }

            const result = await response.json();

            if (result.status !== 'success') {
                throw new Error(result.message || 'Failed to load file');
            }

            // Convert content to Uint8Array
            const content = result.data.content;
            const encoder = new TextEncoder();
            const bytes = encoder.encode(content);

            setData(bytes);
            setOriginalData(bytes);
            setFileSize(bytes.length);

            // Extract file name from path
            const pathParts = filePath.split(/[\/\\]/);
            setFileName(pathParts[pathParts.length - 1]);

            window.logToServer(`HexEditor: Loaded ${bytes.length} bytes from ${filePath}`);
        } catch (err) {
            window.logToServer(`HexEditor: Error loading file: ${err.message}`, 'Error');
            alert(`Failed to load file: ${err.message}`);
        } finally {
            setLoading(false);
        }
    };

    const saveFile = async () => {
        if (readOnly) {
            alert('File is in read-only mode. Click "Edit Mode" to enable editing.');
            return;
        }

        try {
            setSaving(true);
            window.logToServer(`HexEditor: Saving file ${filePath}`);

            // Convert Uint8Array back to string
            const decoder = new TextDecoder();
            const content = decoder.decode(data);

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files/content',
                {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        path: filePath,
                        content: content,
                        encoding: 'utf-8'
                    })
                }
            );

            if (!response.ok) {
                throw new Error(`Failed to save file: ${response.statusText}`);
            }

            const result = await response.json();

            if (result.status !== 'success') {
                throw new Error(result.message || 'Failed to save file');
            }

            setOriginalData(new Uint8Array(data));
            setModified(false);
            window.logToServer(`HexEditor: Saved ${data.length} bytes to ${filePath}`);
            alert('File saved successfully!');
        } catch (err) {
            window.logToServer(`HexEditor: Error saving file: ${err.message}`, 'Error');
            alert(`Failed to save file: ${err.message}`);
        } finally {
            setSaving(false);
        }
    };

    const handleSearch = () => {
        if (!searchHex.trim()) return;

        // Parse hex string (remove spaces, validate)
        const hexPattern = searchHex.replace(/\s+/g, '').toUpperCase();
        if (!/^[0-9A-F]+$/.test(hexPattern) || hexPattern.length % 2 !== 0) {
            alert('Invalid hex pattern. Use pairs of hex digits (e.g., "48 65 6C 6C 6F")');
            return;
        }

        // Convert hex pattern to bytes
        const pattern = [];
        for (let i = 0; i < hexPattern.length; i += 2) {
            pattern.push(parseInt(hexPattern.substr(i, 2), 16));
        }

        // Search for pattern in data
        const results = [];
        for (let i = 0; i <= data.length - pattern.length; i++) {
            let match = true;
            for (let j = 0; j < pattern.length; j++) {
                if (data[i + j] !== pattern[j]) {
                    match = false;
                    break;
                }
            }
            if (match) {
                results.push(i);
            }
        }

        setSearchResults(results);
        setCurrentSearchIndex(0);

        if (results.length > 0) {
            setCurrentOffset(Math.floor(results[0] / bytesPerRow) * bytesPerRow);
        }
    };

    const handleJumpToOffset = () => {
        const offset = parseInt(jumpOffset, jumpOffset.startsWith('0x') ? 16 : 10);
        if (isNaN(offset) || offset < 0 || offset >= data.length) {
            alert('Invalid offset');
            return;
        }

        setCurrentOffset(Math.floor(offset / bytesPerRow) * bytesPerRow);
        setJumpVisible(false);
    };

    const formatHexByte = (byte) => {
        return byte.toString(16).padStart(2, '0').toUpperCase();
    };

    const formatAscii = (byte) => {
        // Printable ASCII: 32-126
        if (byte >= 32 && byte <= 126) {
            return String.fromCharCode(byte);
        }
        return '.';
    };

    const handleByteEdit = (offset, newValue) => {
        if (readOnly) {
            alert('File is in read-only mode');
            return;
        }

        const byte = parseInt(newValue, 16);
        if (isNaN(byte) || byte < 0 || byte > 255) {
            return;
        }

        const newData = new Uint8Array(data);
        newData[offset] = byte;
        setData(newData);
    };

    const renderHexDump = () => {
        const rows = [];
        const endOffset = Math.min(currentOffset + (visibleRows * bytesPerRow), data.length);

        for (let offset = currentOffset; offset < endOffset; offset += bytesPerRow) {
            const rowBytes = [];
            const rowAscii = [];

            for (let i = 0; i < bytesPerRow; i++) {
                const byteOffset = offset + i;
                if (byteOffset < data.length) {
                    const byte = data[byteOffset];
                    const isSearchMatch = searchResults.includes(byteOffset);

                    rowBytes.push(
                        <span
                            key={`byte-${byteOffset}`}
                            className={`hex-byte ${isSearchMatch ? 'search-match' : ''} ${!readOnly ? 'editable' : ''}`}
                            onClick={() => {
                                if (!readOnly) {
                                    const newValue = prompt(`Edit byte at offset 0x${byteOffset.toString(16).toUpperCase()}:`, formatHexByte(byte));
                                    if (newValue) {
                                        handleByteEdit(byteOffset, newValue);
                                    }
                                }
                            }}
                        >
                            {formatHexByte(byte)}
                        </span>
                    );

                    rowAscii.push(
                        <span key={`ascii-${byteOffset}`} className={isSearchMatch ? 'search-match' : ''}>
                            {formatAscii(byte)}
                        </span>
                    );
                } else {
                    rowBytes.push(<span key={`byte-${byteOffset}`} className="hex-byte-empty">  </span>);
                    rowAscii.push(<span key={`ascii-${byteOffset}`}> </span>);
                }
            }

            rows.push(
                <div key={`row-${offset}`} className="hex-row">
                    <div className="hex-offset">{offset.toString(16).padStart(8, '0').toUpperCase()}</div>
                    <div className="hex-bytes">{rowBytes}</div>
                    <div className="hex-ascii">{rowAscii}</div>
                </div>
            );
        }

        return rows;
    };

    return (
        <div className="hex-editor-container">
            <style>{styles}</style>

            {/* Toolbar */}
            <div className="hex-editor-toolbar">
                <div className="toolbar-left">
                    <button onClick={() => setReadOnly(!readOnly)} title={readOnly ? 'Enable editing' : 'Disable editing'}>
                        {readOnly ? '🔒 Read Only' : '✏️ Edit Mode'}
                    </button>
                    <button onClick={saveFile} disabled={readOnly || !modified || saving} title="Save (Ctrl+S)">
                        💾 {saving ? 'Saving...' : 'Save'}
                    </button>
                    <button onClick={() => setSearchVisible(!searchVisible)} title="Find (Ctrl+F)">
                        🔍 Find
                    </button>
                    <button onClick={() => setJumpVisible(!jumpVisible)} title="Jump to Offset (Ctrl+G)">
                        ⚡ Jump
                    </button>
                    <button onClick={loadFile} disabled={loading} title="Reload">
                        🔄 Reload
                    </button>
                    <button onClick={onClose} title="Close">
                        ✕ Close
                    </button>
                </div>
                <div className="toolbar-right">
                    <span className="file-name">{fileName} {modified ? '*' : ''}</span>
                </div>
            </div>

            {/* Search Panel */}
            {searchVisible && (
                <div className="hex-search-panel">
                    <input
                        type="text"
                        placeholder="Hex pattern (e.g., 48 65 6C 6C 6F)"
                        value={searchHex}
                        onChange={(e) => setSearchHex(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
                    />
                    <button onClick={handleSearch}>Search</button>
                    <span className="search-results">
                        {searchResults.length > 0 ? `${currentSearchIndex + 1} of ${searchResults.length} matches` : 'No matches'}
                    </span>
                </div>
            )}

            {/* Jump to Offset Panel */}
            {jumpVisible && (
                <div className="hex-jump-panel">
                    <input
                        type="text"
                        placeholder="Offset (decimal or 0x hex)"
                        value={jumpOffset}
                        onChange={(e) => setJumpOffset(e.target.value)}
                        onKeyDown={(e) => e.key === 'Enter' && handleJumpToOffset()}
                    />
                    <button onClick={handleJumpToOffset}>Jump</button>
                    <button onClick={() => setJumpVisible(false)}>Cancel</button>
                </div>
            )}

            {/* Hex Dump */}
            <div className="hex-editor-content">
                {loading ? (
                    <div className="loading">Loading file...</div>
                ) : (
                    <div className="hex-dump">
                        {renderHexDump()}
                    </div>
                )}
            </div>

            {/* Navigation */}
            <div className="hex-editor-navigation">
                <button onClick={() => setCurrentOffset(Math.max(0, currentOffset - bytesPerRow))} disabled={currentOffset === 0}>
                    ↑ Up
                </button>
                <button onClick={() => setCurrentOffset(Math.min(data.length - bytesPerRow, currentOffset + bytesPerRow))} disabled={currentOffset + (visibleRows * bytesPerRow) >= data.length}>
                    ↓ Down
                </button>
                <button onClick={() => setCurrentOffset(Math.max(0, currentOffset - (visibleRows * bytesPerRow)))}>
                    ⇈ Page Up
                </button>
                <button onClick={() => setCurrentOffset(Math.min(data.length - bytesPerRow, currentOffset + (visibleRows * bytesPerRow)))}>
                    ⇊ Page Down
                </button>
                <button onClick={() => setCurrentOffset(0)}>⇤ Start</button>
                <button onClick={() => setCurrentOffset(Math.floor(data.length / bytesPerRow) * bytesPerRow - (visibleRows * bytesPerRow))}>⇥ End</button>
            </div>

            {/* Status Bar */}
            <div className="hex-editor-statusbar">
                <span>Offset: 0x{currentOffset.toString(16).toUpperCase()}</span>
                <span>Size: {fileSize} bytes (0x{fileSize.toString(16).toUpperCase()})</span>
                <span>Mode: {readOnly ? 'Read Only' : 'Edit'}</span>
                {modified && <span style={{ color: '#f39c12', fontWeight: 'bold' }}>Modified</span>}
            </div>
        </div>
    );
};

const styles = `
    .hex-editor-container {
        display: flex;
        flex-direction: column;
        height: 100%;
        width: 100%;
        background: #1e1e1e;
        color: #d4d4d4;
        font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
    }

    .hex-editor-toolbar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 8px 12px;
        background: #2d2d30;
        border-bottom: 1px solid #3e3e42;
    }

    .toolbar-left {
        display: flex;
        gap: 8px;
    }

    .toolbar-right .file-name {
        font-weight: 600;
        color: #d4d4d4;
    }

    .hex-editor-toolbar button {
        padding: 6px 12px;
        background: #3e3e42;
        border: 1px solid #555;
        border-radius: 4px;
        color: #d4d4d4;
        cursor: pointer;
        font-size: 13px;
    }

    .hex-editor-toolbar button:hover:not(:disabled) {
        background: #505050;
    }

    .hex-editor-toolbar button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .hex-search-panel, .hex-jump-panel {
        padding: 12px;
        background: #252526;
        border-bottom: 1px solid #3e3e42;
        display: flex;
        gap: 8px;
        align-items: center;
    }

    .hex-search-panel input, .hex-jump-panel input {
        flex: 1;
        padding: 6px 10px;
        background: #3c3c3c;
        border: 1px solid #555;
        border-radius: 4px;
        color: #d4d4d4;
        font-size: 13px;
    }

    .hex-search-panel button, .hex-jump-panel button {
        padding: 6px 12px;
        background: #3e3e42;
        border: 1px solid #555;
        border-radius: 4px;
        color: #d4d4d4;
        cursor: pointer;
        font-size: 13px;
    }

    .hex-search-panel button:hover, .hex-jump-panel button:hover {
        background: #505050;
    }

    .search-results {
        font-size: 13px;
        color: #858585;
    }

    .hex-editor-content {
        flex: 1;
        overflow-y: auto;
        background: #1e1e1e;
        padding: 16px;
    }

    .loading {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 100%;
        color: #858585;
        font-size: 14px;
    }

    .hex-dump {
        font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
        font-size: 14px;
        line-height: 1.6;
    }

    .hex-row {
        display: flex;
        gap: 16px;
        margin-bottom: 4px;
    }

    .hex-offset {
        color: #858585;
        width: 80px;
        text-align: right;
    }

    .hex-bytes {
        display: flex;
        gap: 4px;
        flex-wrap: wrap;
        width: 400px;
    }

    .hex-byte {
        cursor: default;
        color: #d4d4d4;
    }

    .hex-byte.editable {
        cursor: pointer;
    }

    .hex-byte.editable:hover {
        background: #3e3e42;
        border-radius: 2px;
    }

    .hex-byte.search-match {
        background: #f39c12;
        color: #000;
        font-weight: bold;
        border-radius: 2px;
        padding: 0 2px;
    }

    .hex-byte-empty {
        color: #3e3e42;
    }

    .hex-ascii {
        color: #858585;
        letter-spacing: 2px;
    }

    .hex-ascii .search-match {
        background: #f39c12;
        color: #000;
        font-weight: bold;
    }

    .hex-editor-navigation {
        display: flex;
        gap: 8px;
        padding: 8px 12px;
        background: #2d2d30;
        border-top: 1px solid #3e3e42;
        border-bottom: 1px solid #3e3e42;
    }

    .hex-editor-navigation button {
        padding: 6px 12px;
        background: #3e3e42;
        border: 1px solid #555;
        border-radius: 4px;
        color: #d4d4d4;
        cursor: pointer;
        font-size: 13px;
    }

    .hex-editor-navigation button:hover:not(:disabled) {
        background: #505050;
    }

    .hex-editor-navigation button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .hex-editor-statusbar {
        display: flex;
        gap: 20px;
        padding: 6px 12px;
        background: #007acc;
        color: #fff;
        font-size: 12px;
    }

    .hex-editor-statusbar span {
        white-space: nowrap;
    }
`;

// Export for SPA card system
if (typeof window !== 'undefined') {
    window.HexEditor = HexEditor;
}
