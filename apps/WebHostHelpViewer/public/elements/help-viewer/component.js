// Help Viewer Component - Enhanced with Text/Markdown Toggle
// Displays markdown help files with switchable rendering modes

const HelpViewerComponent = ({ url, element, onError }) => {
    const [content, setContent] = React.useState('');
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [helpPath, setHelpPath] = React.useState('');
    const [viewMode, setViewMode] = React.useState('rendered'); // 'rendered' or 'text'
    const [markdownItLoaded, setMarkdownItLoaded] = React.useState(false);

    // Load markdown-it library if not already loaded
    React.useEffect(() => {
        if (typeof markdownit !== 'undefined') {
            setMarkdownItLoaded(true);
        } else {
            // Load markdown-it from CDN or local
            const script = document.createElement('script');
            script.src = '/public/lib/markdown-it.min.js';
            script.onload = () => setMarkdownItLoaded(true);
            script.onerror = () => console.error('Failed to load markdown-it library');
            document.head.appendChild(script);
        }
    }, []);

    React.useEffect(() => {
        // Get the URL from props or element
        const effectiveUrl = url || (element && element.url) || '';

        if (!effectiveUrl) {
            setError('No URL provided for help viewer');
            setLoading(false);
            return;
        }

        // Extract the help file path from URL query parameter
        const urlParts = effectiveUrl.split('?');
        const urlParams = new URLSearchParams(urlParts[1] || '');
        const filePath = urlParams.get('file') || '';
        setHelpPath(filePath);

        if (!filePath) {
            setError('No help file specified in URL');
            setLoading(false);
            return;
        }

        // Fetch the markdown content
        const fetchHelp = async () => {
            try {
                setLoading(true);
                const response = await window.psweb_fetchWithAuthHandling(
                    `/apps/WebHostHelpViewer/cards/help-viewer?file=${encodeURIComponent(filePath)}`
                );

                if (!response.ok) {
                    throw new Error(`Failed to load help file: ${response.status} ${response.statusText}`);
                }

                const data = await response.json();
                setContent(data.content || ''); // Store raw markdown
                setError(null);
            } catch (err) {
                console.error('Error loading help:', err);
                setError(err.message);
            } finally {
                setLoading(false);
            }
        };

        fetchHelp();
    }, [url, element?.url]);

    // Update card title with help path
    React.useEffect(() => {
        if (helpPath && element && element.id) {
            const titleSpan = document.querySelector(
                `[data-card-id="${element.id}"] .card-title, [key="${element.id}"] .card-title`
            );
            if (titleSpan) {
                titleSpan.textContent = `Help: ${helpPath}`;
            }
        }
    }, [helpPath, element?.id]);

    // Render markdown to HTML using markdown-it
    const renderMarkdown = (markdown) => {
        if (!markdownItLoaded || typeof markdownit === 'undefined') {
            return '<p>Markdown renderer loading...</p>';
        }

        const md = markdownit({
            html: true,
            linkify: true,
            typographer: true,
            breaks: true
        });

        return md.render(markdown);
    };

    if (loading) {
        return React.createElement('div', { className: 'help-viewer loading' },
            React.createElement('div', { className: 'spinner' }),
            React.createElement('p', null, 'Loading help...')
        );
    }

    if (error) {
        return React.createElement('div', { className: 'help-viewer error' },
            React.createElement('h3', null, 'Error Loading Help'),
            React.createElement('p', null, error),
            React.createElement('p', { className: 'help-path' }, `Requested: ${helpPath}`)
        );
    }

    return React.createElement('div', {
        className: 'help-viewer',
        style: {
            display: 'flex',
            flexDirection: 'column',
            height: '100%',
            overflow: 'hidden'
        }
    },
        // Toolbar with view mode toggle
        React.createElement('div', {
            className: 'help-viewer-toolbar',
            style: {
                display: 'flex',
                alignItems: 'center',
                padding: '8px 16px',
                background: '#f5f5f5',
                borderBottom: '1px solid #ddd',
                gap: '8px',
                flexShrink: 0
            }
        },
            React.createElement('span', { style: { fontSize: '13px', color: '#666' } }, 'View Mode:'),
            React.createElement('button', {
                className: viewMode === 'rendered' ? 'active' : '',
                onClick: () => setViewMode('rendered'),
                style: {
                    padding: '4px 12px',
                    border: '1px solid #ccc',
                    background: viewMode === 'rendered' ? '#0078d4' : '#fff',
                    color: viewMode === 'rendered' ? '#fff' : '#333',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '13px'
                }
            }, 'Markdown'),
            React.createElement('button', {
                className: viewMode === 'text' ? 'active' : '',
                onClick: () => setViewMode('text'),
                style: {
                    padding: '4px 12px',
                    border: '1px solid #ccc',
                    background: viewMode === 'text' ? '#0078d4' : '#fff',
                    color: viewMode === 'text' ? '#fff' : '#333',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontSize: '13px'
                }
            }, 'Text')
        ),
        // Content area
        React.createElement('div', {
            className: 'help-content',
            style: {
                flex: 1,
                overflow: 'auto',
                padding: '16px',
                backgroundColor: 'var(--bg-color, #fff)',
                color: 'var(--text-color, #333)'
            }
        },
            viewMode === 'rendered'
                ? React.createElement('div', {
                    className: 'markdown-body',
                    dangerouslySetInnerHTML: { __html: renderMarkdown(content) }
                })
                : React.createElement('pre', {
                    style: {
                        whiteSpace: 'pre-wrap',
                        wordBreak: 'break-word',
                        fontFamily: 'Consolas, Monaco, monospace',
                        fontSize: '13px',
                        lineHeight: '1.6',
                        margin: 0
                    }
                }, content)
        )
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['help-viewer'] = HelpViewerComponent;
