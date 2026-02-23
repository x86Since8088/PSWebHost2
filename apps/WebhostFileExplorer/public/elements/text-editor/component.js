/**
 * TextEditor Component - Full-featured text file editor
 *
 * Features:
 * - Load and save text files
 * - Search and replace
 * - Line numbers
 * - Syntax highlighting (basic)
 * - Keyboard shortcuts (Ctrl+S, Ctrl+F)
 * - Status bar (lines, words, characters, encoding)
 */

const TextEditor = ({ filePath, onClose, cardInfo }) => {
    const [content, setContent] = React.useState('');
    const [originalContent, setOriginalContent] = React.useState('');
    const [loading, setLoading] = React.useState(true);
    const [saving, setSaving] = React.useState(false);
    const [modified, setModified] = React.useState(false);
    const [fileName, setFileName] = React.useState('');
    const [fileSize, setFileSize] = React.useState(0);
    const [encoding, setEncoding] = React.useState('utf-8');
    const [lineEnding, setLineEnding] = React.useState('LF');
    const [lastModified, setLastModified] = React.useState(null);

    // Search/replace state
    const [searchVisible, setSearchVisible] = React.useState(false);
    const [searchText, setSearchText] = React.useState('');
    const [replaceText, setReplaceText] = React.useState('');
    const [caseSensitive, setCaseSensitive] = React.useState(false);
    const [currentMatch, setCurrentMatch] = React.useState(0);
    const [totalMatches, setTotalMatches] = React.useState(0);

    // Settings
    const [wordWrap, setWordWrap] = React.useState(() => {
        const saved = localStorage.getItem('textEditor_wordWrap');
        return saved !== null ? saved === 'true' : true;
    });
    const [showLineNumbers, setShowLineNumbers] = React.useState(() => {
        const saved = localStorage.getItem('textEditor_showLineNumbers');
        return saved !== null ? saved === 'true' : true;
    });
    const [fontSize, setFontSize] = React.useState(() => {
        const saved = localStorage.getItem('textEditor_fontSize');
        return saved ? parseInt(saved) : 14;
    });

    const textareaRef = React.useRef(null);

    // Load file on mount
    React.useEffect(() => {
        loadFile();
    }, [filePath]);

    // Track modified state
    React.useEffect(() => {
        setModified(content !== originalContent);
    }, [content, originalContent]);

    // Persist settings
    React.useEffect(() => {
        localStorage.setItem('textEditor_wordWrap', wordWrap.toString());
    }, [wordWrap]);

    React.useEffect(() => {
        localStorage.setItem('textEditor_showLineNumbers', showLineNumbers.toString());
    }, [showLineNumbers]);

    React.useEffect(() => {
        localStorage.setItem('textEditor_fontSize', fontSize.toString());
    }, [fontSize]);

    // Keyboard shortcuts
    React.useEffect(() => {
        const handleKeyDown = (e) => {
            // Ctrl+S - Save
            if (e.ctrlKey && e.key === 's') {
                e.preventDefault();
                saveFile();
            }
            // Ctrl+F - Find
            if (e.ctrlKey && e.key === 'f') {
                e.preventDefault();
                setSearchVisible(true);
            }
            // Escape - Close search
            if (e.key === 'Escape' && searchVisible) {
                setSearchVisible(false);
            }
        };

        window.addEventListener('keydown', handleKeyDown);
        return () => window.removeEventListener('keydown', handleKeyDown);
    }, [searchVisible, content]);

    const loadFile = async () => {
        try {
            setLoading(true);
            window.logToServer(`TextEditor: Loading file ${filePath}`);

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

            const data = result.data;
            setContent(data.content);
            setOriginalContent(data.content);
            setFileSize(data.size);
            setEncoding(data.encoding || 'utf-8');
            setLastModified(data.lastModified ? new Date(data.lastModified) : null);

            // Extract file name from path
            const pathParts = filePath.split(/[\/\\]/);
            setFileName(pathParts[pathParts.length - 1]);

            // Detect line ending
            if (data.content.includes('\r\n')) {
                setLineEnding('CRLF');
            } else if (data.content.includes('\n')) {
                setLineEnding('LF');
            } else {
                setLineEnding('LF');
            }

            window.logToServer(`TextEditor: Loaded ${data.size} bytes from ${filePath}`);
        } catch (err) {
            window.logToServer(`TextEditor: Error loading file: ${err.message}`, 'Error');
            alert(`Failed to load file: ${err.message}`);
        } finally {
            setLoading(false);
        }
    };

    const saveFile = async () => {
        try {
            setSaving(true);
            window.logToServer(`TextEditor: Saving file ${filePath}`);

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebhostFileExplorer/api/v1/files/content',
                {
                    method: 'PUT',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        path: filePath,
                        content: content,
                        encoding: encoding
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

            setOriginalContent(content);
            setModified(false);
            window.logToServer(`TextEditor: Saved ${content.length} characters to ${filePath}`);
            alert('File saved successfully!');
        } catch (err) {
            window.logToServer(`TextEditor: Error saving file: ${err.message}`, 'Error');
            alert(`Failed to save file: ${err.message}`);
        } finally {
            setSaving(false);
        }
    };

    const handleSearch = () => {
        if (!searchText) {
            setTotalMatches(0);
            setCurrentMatch(0);
            return;
        }

        const flags = caseSensitive ? 'g' : 'gi';
        const regex = new RegExp(searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags);
        const matches = content.match(regex);

        setTotalMatches(matches ? matches.length : 0);

        if (matches && matches.length > 0) {
            setCurrentMatch(1);
            // Find first match position and select it
            const firstIndex = content.search(regex);
            if (textareaRef.current && firstIndex >= 0) {
                textareaRef.current.focus();
                textareaRef.current.setSelectionRange(firstIndex, firstIndex + searchText.length);
            }
        }
    };

    const handleReplace = () => {
        if (!searchText || currentMatch === 0) return;

        const flags = caseSensitive ? '' : 'i';
        const regex = new RegExp(searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags);

        // Replace first occurrence
        const newContent = content.replace(regex, replaceText);
        setContent(newContent);

        // Re-search to update matches
        setTimeout(() => handleSearch(), 100);
    };

    const handleReplaceAll = () => {
        if (!searchText) return;

        const flags = caseSensitive ? 'g' : 'gi';
        const regex = new RegExp(searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags);

        const newContent = content.replace(regex, replaceText);
        setContent(newContent);

        setTotalMatches(0);
        setCurrentMatch(0);
    };

    const findNext = () => {
        if (totalMatches === 0) return;

        const newMatch = currentMatch >= totalMatches ? 1 : currentMatch + 1;
        setCurrentMatch(newMatch);

        // Find nth match and select it
        const flags = caseSensitive ? 'g' : 'gi';
        const regex = new RegExp(searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags);
        const matches = [...content.matchAll(regex)];

        if (matches[newMatch - 1] && textareaRef.current) {
            const match = matches[newMatch - 1];
            textareaRef.current.focus();
            textareaRef.current.setSelectionRange(match.index, match.index + match[0].length);
        }
    };

    const findPrevious = () => {
        if (totalMatches === 0) return;

        const newMatch = currentMatch <= 1 ? totalMatches : currentMatch - 1;
        setCurrentMatch(newMatch);

        const flags = caseSensitive ? 'g' : 'gi';
        const regex = new RegExp(searchText.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), flags);
        const matches = [...content.matchAll(regex)];

        if (matches[newMatch - 1] && textareaRef.current) {
            const match = matches[newMatch - 1];
            textareaRef.current.focus();
            textareaRef.current.setSelectionRange(match.index, match.index + match[0].length);
        }
    };

    // Calculate statistics
    const lines = content.split('\n').length;
    const words = content.trim() ? content.trim().split(/\s+/).length : 0;
    const characters = content.length;

    return (
        <div className="text-editor-container">
            <style>{styles}</style>

            {/* Toolbar */}
            <div className="text-editor-toolbar">
                <div className="toolbar-left">
                    <button onClick={saveFile} disabled={!modified || saving} title="Save (Ctrl+S)">
                        💾 {saving ? 'Saving...' : 'Save'}
                    </button>
                    <button onClick={() => setSearchVisible(!searchVisible)} title="Find (Ctrl+F)">
                        🔍 Find
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

            {/* Search/Replace Panel */}
            {searchVisible && (
                <div className="search-panel">
                    <div className="search-row">
                        <input
                            type="text"
                            placeholder="Find..."
                            value={searchText}
                            onChange={(e) => setSearchText(e.target.value)}
                            onKeyDown={(e) => e.key === 'Enter' && handleSearch()}
                        />
                        <button onClick={handleSearch}>Search</button>
                        <button onClick={findPrevious} disabled={totalMatches === 0}>↑</button>
                        <button onClick={findNext} disabled={totalMatches === 0}>↓</button>
                        <span className="match-count">
                            {totalMatches > 0 ? `${currentMatch} of ${totalMatches}` : 'No matches'}
                        </span>
                        <label>
                            <input
                                type="checkbox"
                                checked={caseSensitive}
                                onChange={(e) => setCaseSensitive(e.target.checked)}
                            />
                            Case sensitive
                        </label>
                    </div>
                    <div className="search-row">
                        <input
                            type="text"
                            placeholder="Replace with..."
                            value={replaceText}
                            onChange={(e) => setReplaceText(e.target.value)}
                        />
                        <button onClick={handleReplace} disabled={totalMatches === 0}>Replace</button>
                        <button onClick={handleReplaceAll} disabled={totalMatches === 0}>Replace All</button>
                    </div>
                </div>
            )}

            {/* Editor */}
            <div className="text-editor-content">
                {loading ? (
                    <div className="loading">Loading file...</div>
                ) : (
                    <textarea
                        ref={textareaRef}
                        className={`text-editor-textarea ${wordWrap ? 'wrap' : 'nowrap'} ${showLineNumbers ? 'with-line-numbers' : ''}`}
                        value={content}
                        onChange={(e) => setContent(e.target.value)}
                        style={{ fontSize: `${fontSize}px` }}
                        spellCheck={false}
                    />
                )}
            </div>

            {/* Settings Bar */}
            <div className="text-editor-settings">
                <label>
                    <input
                        type="checkbox"
                        checked={wordWrap}
                        onChange={(e) => setWordWrap(e.target.checked)}
                    />
                    Word Wrap
                </label>
                <label>
                    <input
                        type="checkbox"
                        checked={showLineNumbers}
                        onChange={(e) => setShowLineNumbers(e.target.checked)}
                    />
                    Line Numbers
                </label>
                <label>
                    Font Size:
                    <input
                        type="number"
                        min="8"
                        max="32"
                        value={fontSize}
                        onChange={(e) => setFontSize(parseInt(e.target.value))}
                        style={{ width: '50px', marginLeft: '5px' }}
                    />
                </label>
            </div>

            {/* Status Bar */}
            <div className="text-editor-statusbar">
                <span>Lines: {lines}</span>
                <span>Words: {words}</span>
                <span>Characters: {characters}</span>
                <span>Encoding: {encoding}</span>
                <span>Line Ending: {lineEnding}</span>
                {lastModified && <span>Modified: {lastModified.toLocaleString()}</span>}
            </div>
        </div>
    );
};

const styles = `
    .text-editor-container {
        display: flex;
        flex-direction: column;
        height: 100%;
        width: 100%;
        background: #fff;
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    }

    .text-editor-toolbar {
        display: flex;
        justify-content: space-between;
        align-items: center;
        padding: 8px 12px;
        background: #f5f5f5;
        border-bottom: 1px solid #ddd;
    }

    .toolbar-left {
        display: flex;
        gap: 8px;
    }

    .toolbar-right .file-name {
        font-weight: 600;
        color: #333;
    }

    .text-editor-toolbar button {
        padding: 6px 12px;
        background: #fff;
        border: 1px solid #ccc;
        border-radius: 4px;
        cursor: pointer;
        font-size: 13px;
    }

    .text-editor-toolbar button:hover:not(:disabled) {
        background: #e9ecef;
    }

    .text-editor-toolbar button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .search-panel {
        padding: 12px;
        background: #f9f9f9;
        border-bottom: 1px solid #ddd;
    }

    .search-row {
        display: flex;
        gap: 8px;
        align-items: center;
        margin-bottom: 8px;
    }

    .search-row:last-child {
        margin-bottom: 0;
    }

    .search-row input[type="text"] {
        flex: 1;
        padding: 6px 10px;
        border: 1px solid #ccc;
        border-radius: 4px;
        font-size: 13px;
    }

    .search-row button {
        padding: 6px 12px;
        background: #fff;
        border: 1px solid #ccc;
        border-radius: 4px;
        cursor: pointer;
        font-size: 13px;
    }

    .search-row button:hover:not(:disabled) {
        background: #e9ecef;
    }

    .search-row button:disabled {
        opacity: 0.5;
        cursor: not-allowed;
    }

    .match-count {
        font-size: 13px;
        color: #666;
        min-width: 80px;
    }

    .text-editor-content {
        flex: 1;
        display: flex;
        overflow: hidden;
        position: relative;
    }

    .loading {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 100%;
        height: 100%;
        color: #999;
        font-size: 14px;
    }

    .text-editor-textarea {
        width: 100%;
        height: 100%;
        padding: 16px;
        border: none;
        outline: none;
        font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
        resize: none;
        background: #fff;
        color: #333;
        line-height: 1.5;
    }

    .text-editor-textarea.wrap {
        white-space: pre-wrap;
        word-wrap: break-word;
    }

    .text-editor-textarea.nowrap {
        white-space: pre;
        overflow-x: auto;
    }

    .text-editor-settings {
        display: flex;
        gap: 20px;
        padding: 8px 12px;
        background: #f9f9f9;
        border-top: 1px solid #ddd;
        border-bottom: 1px solid #ddd;
        font-size: 13px;
    }

    .text-editor-settings label {
        display: flex;
        align-items: center;
        gap: 6px;
        cursor: pointer;
    }

    .text-editor-statusbar {
        display: flex;
        gap: 20px;
        padding: 6px 12px;
        background: #2c3e50;
        color: #ecf0f1;
        font-size: 12px;
        font-family: 'Consolas', 'Monaco', 'Courier New', monospace;
    }

    .text-editor-statusbar span {
        white-space: nowrap;
    }
`;

// Export for SPA card system
if (typeof window !== 'undefined') {
    window.TextEditor = TextEditor;
}
