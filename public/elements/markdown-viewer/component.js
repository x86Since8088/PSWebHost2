// Markdown Viewer Component
// Renders markdown with mermaid diagram support
// Supports editing for authorized users via TOAST UI Editor

const MarkdownViewerComponent = ({ url, element, onError }) => {
    const [content, setContent] = React.useState('');
    const [htmlContent, setHtmlContent] = React.useState('');
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [filePath, setFilePath] = React.useState('');
    const [isEditing, setIsEditing] = React.useState(false);
    const [canEdit, setCanEdit] = React.useState(false);
    const [editorLoaded, setEditorLoaded] = React.useState(false);
    const [saving, setSaving] = React.useState(false);
    const editorRef = React.useRef(null);
    const editorInstanceRef = React.useRef(null);
    const containerRef = React.useRef(null);

    // Check if markdown-it is loaded, if not load it
    React.useEffect(() => {
        if (typeof markdownit === 'undefined') {
            const script = document.createElement('script');
            script.src = '/public/lib/markdown-it.min.js';
            script.onload = () => {
                console.log('markdown-it loaded');
            };
            document.head.appendChild(script);
        }
    }, []);

    // Get the file path from URL
    React.useEffect(() => {
        const effectiveUrl = url || (element && element.url) || '';

        if (!effectiveUrl) {
            setError('No URL provided');
            setLoading(false);
            return;
        }

        const urlParts = effectiveUrl.split('?');
        const urlParams = new URLSearchParams(urlParts[1] || '');
        const file = urlParams.get('file') || '';
        setFilePath(file);

        if (!file) {
            setError('No file specified in URL');
            setLoading(false);
            return;
        }

        // Fetch the markdown content
        const fetchContent = async () => {
            try {
                setLoading(true);
                const response = await window.psweb_fetchWithAuthHandling(
                    `/api/v1/ui/elements/markdown-viewer?file=${encodeURIComponent(file)}`
                );

                if (!response.ok) {
                    throw new Error(`Failed to load file: ${response.status} ${response.statusText}`);
                }

                const data = await response.json();
                setContent(data.content || '');
                setCanEdit(data.canEdit || false);
                setError(null);
            } catch (err) {
                console.error('Error loading markdown:', err);
                setError(err.message);
            } finally {
                setLoading(false);
            }
        };

        fetchContent();
    }, [url, element?.url]);

    // Render markdown to HTML when content changes
    React.useEffect(() => {
        if (!content || isEditing) return;

        const renderMarkdown = async () => {
            // Wait for markdown-it to be available
            if (typeof markdownit === 'undefined') {
                setTimeout(renderMarkdown, 100);
                return;
            }

            const md = markdownit({
                html: true,
                linkify: true,
                typographer: true,
                breaks: true
            });

            // Custom renderer for mermaid code blocks
            const defaultFence = md.renderer.rules.fence || function(tokens, idx, options, env, self) {
                return self.renderToken(tokens, idx, options);
            };

            md.renderer.rules.fence = (tokens, idx, options, env, self) => {
                const token = tokens[idx];
                const info = token.info.trim().toLowerCase();

                if (info === 'mermaid') {
                    const code = token.content.trim();
                    const id = `mermaid-${idx}-${Date.now()}`;
                    return `<div class="mermaid-container"><pre class="mermaid" id="${id}">${escapeHtml(code)}</pre></div>`;
                }

                return defaultFence(tokens, idx, options, env, self);
            };

            const rendered = md.render(content);
            setHtmlContent(rendered);
        };

        renderMarkdown();
    }, [content, isEditing]);

    // Initialize mermaid diagrams after HTML is rendered
    React.useEffect(() => {
        if (!htmlContent || isEditing) return;

        const initMermaid = async () => {
            // Check if mermaid is loaded
            if (typeof mermaid === 'undefined') {
                // Load mermaid if not present
                const script = document.createElement('script');
                script.src = '/public/lib/mermaid.min.js';
                script.onload = () => {
                    mermaid.initialize({
                        startOnLoad: false,
                        theme: 'default',
                        securityLevel: 'loose'
                    });
                    renderMermaidDiagrams();
                };
                document.head.appendChild(script);
            } else {
                renderMermaidDiagrams();
            }
        };

        const renderMermaidDiagrams = async () => {
            if (!containerRef.current) return;

            const mermaidElements = containerRef.current.querySelectorAll('.mermaid');
            if (mermaidElements.length === 0) return;

            try {
                await mermaid.run({
                    nodes: mermaidElements
                });
            } catch (err) {
                console.error('Mermaid rendering error:', err);
            }
        };

        // Small delay to ensure DOM is updated
        setTimeout(initMermaid, 50);
    }, [htmlContent, isEditing]);

    // Load TOAST UI Editor when entering edit mode
    const loadEditor = async () => {
        if (editorLoaded) return true;

        return new Promise((resolve) => {
            // Check if already loaded
            if (typeof toastui !== 'undefined' && toastui.Editor) {
                setEditorLoaded(true);
                resolve(true);
                return;
            }

            // Load CSS first
            if (!document.querySelector('link[href*="toastui-editor"]')) {
                const link = document.createElement('link');
                link.rel = 'stylesheet';
                link.href = '/public/lib/toastui-editor.min.css';
                document.head.appendChild(link);
            }

            // Load JS
            const script = document.createElement('script');
            script.src = '/public/lib/toastui-editor.min.js';
            script.onload = () => {
                setEditorLoaded(true);
                resolve(true);
            };
            script.onerror = () => {
                console.error('Failed to load TOAST UI Editor');
                resolve(false);
            };
            document.head.appendChild(script);
        });
    };

    // Initialize editor when entering edit mode
    React.useEffect(() => {
        if (!isEditing || !editorLoaded || !editorRef.current) return;

        // Destroy previous instance if exists
        if (editorInstanceRef.current) {
            try {
                editorInstanceRef.current.destroy();
            } catch (e) {
                console.warn('Error destroying previous editor instance:', e);
            }
        }

        // Create new editor instance
        editorInstanceRef.current = new toastui.Editor({
            el: editorRef.current,
            height: '100%',
            initialEditType: 'markdown',
            previewStyle: 'vertical',
            initialValue: content,
            usageStatistics: false
        });

        return () => {
            if (editorInstanceRef.current) {
                try {
                    editorInstanceRef.current.destroy();
                } catch (e) {
                    console.warn('Error destroying editor in cleanup:', e);
                }
                editorInstanceRef.current = null;
            }
        };
    }, [isEditing, editorLoaded]);

    const handleEdit = async () => {
        const loaded = await loadEditor();
        if (loaded) {
            setIsEditing(true);
        }
    };

    const handleCancel = () => {
        // Destroy editor before changing state to avoid DOM removal issues
        if (editorInstanceRef.current) {
            try {
                editorInstanceRef.current.destroy();
            } catch (e) {
                console.warn('Error destroying editor on cancel:', e);
            }
            editorInstanceRef.current = null;
        }
        setIsEditing(false);
    };

    const handleSave = async () => {
        if (!editorInstanceRef.current) return;

        const newContent = editorInstanceRef.current.getMarkdown();
        setSaving(true);

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/api/v1/ui/elements/markdown-viewer?file=${encodeURIComponent(filePath)}`,
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ content: newContent })
                }
            );

            if (!response.ok) {
                throw new Error(`Failed to save: ${response.status} ${response.statusText}`);
            }

            setContent(newContent);
            setIsEditing(false);
        } catch (err) {
            console.error('Error saving:', err);
            alert(`Save failed: ${err.message}`);
        } finally {
            setSaving(false);
        }
    };

    // Helper function to escape HTML
    const escapeHtml = (text) => {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    };

    if (loading) {
        return React.createElement('div', { className: 'markdown-viewer loading' },
            React.createElement('div', { className: 'spinner' }),
            React.createElement('p', null, 'Loading...')
        );
    }

    if (error) {
        return React.createElement('div', { className: 'markdown-viewer error' },
            React.createElement('h3', null, 'Error'),
            React.createElement('p', null, error),
            React.createElement('p', { className: 'file-path' }, `File: ${filePath}`)
        );
    }

    if (isEditing) {
        return React.createElement('div', {
            className: 'markdown-viewer editing',
            style: { height: '100%', display: 'flex', flexDirection: 'column', backgroundColor: '#fff' }
        },
            React.createElement('div', {
                className: 'editor-toolbar',
                style: {
                    padding: '8px',
                    borderBottom: '1px solid #ddd',
                    backgroundColor: '#f6f8fa',
                    display: 'flex',
                    gap: '8px'
                }
            },
                React.createElement('button', {
                    onClick: handleSave,
                    disabled: saving,
                    style: {
                        padding: '6px 16px',
                        backgroundColor: '#0366d6',
                        color: '#ffffff',
                        border: 'none',
                        borderRadius: '4px',
                        cursor: saving ? 'wait' : 'pointer',
                        fontWeight: '500'
                    }
                }, saving ? 'Saving...' : 'Save'),
                React.createElement('button', {
                    onClick: handleCancel,
                    disabled: saving,
                    style: {
                        padding: '6px 16px',
                        backgroundColor: '#ffffff',
                        color: '#24292e',
                        border: '1px solid #d1d5da',
                        borderRadius: '4px',
                        cursor: 'pointer',
                        fontWeight: '500'
                    }
                }, 'Cancel')
            ),
            React.createElement('div', {
                ref: editorRef,
                style: { flex: 1, overflow: 'hidden', backgroundColor: '#fff' }
            })
        );
    }

    return React.createElement('div', {
        className: 'markdown-viewer',
        style: {
            height: '100%',
            display: 'flex',
            flexDirection: 'column',
            backgroundColor: 'var(--bg-color, #fff)',
            color: 'var(--text-color, #333)'
        }
    },
        canEdit && React.createElement('div', {
            className: 'viewer-toolbar',
            style: {
                padding: '8px',
                borderBottom: '1px solid var(--border-color, #ddd)',
                display: 'flex',
                justifyContent: 'flex-end'
            }
        },
            React.createElement('button', {
                onClick: handleEdit,
                style: {
                    padding: '4px 12px',
                    backgroundColor: 'var(--bg-secondary, #f0f0f0)',
                    color: 'var(--text-color, #333)',
                    border: '1px solid var(--border-color, #ddd)',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '12px'
                }
            }, 'Edit')
        ),
        React.createElement('div', {
            ref: containerRef,
            className: 'markdown-content',
            style: {
                flex: 1,
                padding: '16px',
                overflow: 'auto'
            },
            dangerouslySetInnerHTML: { __html: htmlContent }
        })
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['markdown-viewer'] = MarkdownViewerComponent;
