// Help Viewer Component
// Displays markdown help files in a card with proper rendering

const HelpViewerComponent = ({ url, element, onError }) => {
    const [content, setContent] = React.useState('');
    const [loading, setLoading] = React.useState(true);
    const [error, setError] = React.useState(null);
    const [helpPath, setHelpPath] = React.useState('');

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
                const response = await window.psweb_fetchWithAuthHandling(`/api/v1/ui/elements/help-viewer?file=${encodeURIComponent(filePath)}`);

                if (!response.ok) {
                    throw new Error(`Failed to load help file: ${response.status} ${response.statusText}`);
                }

                const data = await response.json();
                setContent(data.html || data.content || '');
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
            const titleSpan = document.querySelector(`[data-card-id="${element.id}"] .card-title, [key="${element.id}"] .card-title`);
            if (titleSpan) {
                titleSpan.textContent = `Help: ${helpPath}`;
            }
        }
    }, [helpPath, element?.id]);

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
            padding: '16px',
            overflow: 'auto',
            height: '100%',
            backgroundColor: 'var(--bg-color, #fff)',
            color: 'var(--text-color, #333)'
        }
    },
        React.createElement('div', {
            className: 'help-content markdown-body',
            dangerouslySetInnerHTML: { __html: content }
        })
    );
};

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['help-viewer'] = HelpViewerComponent;
