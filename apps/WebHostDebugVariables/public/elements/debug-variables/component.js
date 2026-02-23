// Debug Variables Component - Interactive tree view for browsing global variables
const { useState, useEffect, useRef } = React;

const DebugVariables = ({ onError }) => {
    const [nodes, setNodes] = useState([]);
    const [expandedPaths, setExpandedPaths] = useState(new Set());
    const [loading, setLoading] = useState(true);
    const [searchTerm, setSearchTerm] = useState('');
    const [error, setError] = useState(null);

    // Load root variables on mount
    useEffect(() => {
        loadRootVariables();
    }, []);

    const loadRootVariables = async () => {
        setLoading(true);
        setError(null);

        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebHostDebugVariables/api/v1/debug/variables'
            );

            if (!response.ok) {
                throw new Error(`Failed to load variables: ${response.status}`);
            }

            const data = await response.json();
            setNodes(data);
        } catch (err) {
            setError(err.message);
            if (onError) onError({ message: err.message });
        } finally {
            setLoading(false);
        }
    };

    const loadChildren = async (path) => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                `/apps/WebHostDebugVariables/api/v1/debug/variables?path=${encodeURIComponent(path)}`
            );

            if (!response.ok) {
                throw new Error(`Failed to load children: ${response.status}`);
            }

            return await response.json();
        } catch (err) {
            console.error('Error loading children:', err);
            if (onError) onError({ message: err.message });
            return [];
        }
    };

    const toggleNode = async (node) => {
        if (!node.IsExpandable) return;

        const newExpandedPaths = new Set(expandedPaths);

        if (expandedPaths.has(node.Path)) {
            // Collapse
            newExpandedPaths.delete(node.Path);
            setExpandedPaths(newExpandedPaths);
        } else {
            // Expand
            newExpandedPaths.add(node.Path);
            setExpandedPaths(newExpandedPaths);

            // Load children if not already loaded
            if (!node.children) {
                const children = await loadChildren(node.Path);

                // Update the node with children
                const updateNodeChildren = (nodeList) => {
                    return nodeList.map(n => {
                        if (n.Path === node.Path) {
                            return { ...n, children };
                        }
                        if (n.children) {
                            return { ...n, children: updateNodeChildren(n.children) };
                        }
                        return n;
                    });
                };

                setNodes(updateNodeChildren(nodes));
            }
        }
    };

    const renderNode = (node, depth = 0) => {
        const isExpanded = expandedPaths.has(node.Path);
        const hasChildren = node.children && node.children.length > 0;

        // Filter by search term
        if (searchTerm && !node.Name.toLowerCase().includes(searchTerm.toLowerCase()) &&
            (!node.Value || !node.Value.toLowerCase().includes(searchTerm.toLowerCase()))) {
            return null;
        }

        const typeShort = node.Type ? node.Type.split('.').pop() : 'unknown';

        return React.createElement('div', {
            key: node.Path || node.Name,
            className: 'tree-node',
            style: { marginLeft: `${depth * 20}px` }
        },
            // Node content
            React.createElement('div', {
                className: 'tree-node-content',
                onClick: () => toggleNode(node),
                style: {
                    display: 'flex',
                    alignItems: 'center',
                    padding: '4px 8px',
                    cursor: node.IsExpandable ? 'pointer' : 'default',
                    backgroundColor: '#fff',
                    borderRadius: '4px',
                    marginBottom: '2px',
                    border: '1px solid #e0e0e0'
                }
            },
                // Expand icon
                React.createElement('span', {
                    style: {
                        width: '20px',
                        textAlign: 'center',
                        fontWeight: 'bold',
                        color: '#666',
                        userSelect: 'none'
                    }
                }, node.IsExpandable ? (isExpanded ? '▼' : '▶') : '•'),

                // Name
                React.createElement('span', {
                    style: {
                        fontWeight: 'bold',
                        color: '#1e1e1e',
                        marginRight: '8px',
                        fontFamily: 'monospace'
                    }
                }, node.Name),

                // Type badge
                React.createElement('span', {
                    style: {
                        fontSize: '0.85em',
                        color: '#666',
                        backgroundColor: '#f0f0f0',
                        padding: '2px 6px',
                        borderRadius: '3px',
                        marginRight: '8px',
                        fontFamily: 'monospace'
                    }
                }, `[${typeShort}]`),

                // Value
                node.Value !== undefined && React.createElement('span', {
                    style: {
                        fontStyle: 'italic',
                        color: '#555',
                        fontSize: '0.9em',
                        fontFamily: 'monospace',
                        overflow: 'hidden',
                        textOverflow: 'ellipsis',
                        whiteSpace: 'nowrap',
                        flex: 1
                    }
                }, node.Value)
            ),

            // Children (if expanded)
            isExpanded && hasChildren && React.createElement('div', {
                style: {
                    borderLeft: '1px dotted #ccc',
                    paddingLeft: '8px',
                    marginLeft: '10px',
                    marginTop: '4px'
                }
            }, node.children.map(child => renderNode(child, depth + 1)))
        );
    };

    return React.createElement('div', {
        style: {
            height: '100%',
            display: 'flex',
            flexDirection: 'column',
            backgroundColor: '#f8f8f8',
            fontFamily: 'Segoe UI, Arial, sans-serif'
        }
    },
        // Header
        React.createElement('div', {
            style: {
                padding: '12px 16px',
                backgroundColor: '#1e1e1e',
                color: '#fff',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'space-between',
                borderBottom: '2px solid #00ff00'
            }
        },
            React.createElement('h3', {
                style: {
                    margin: 0,
                    fontSize: '1.2em',
                    color: '#00ff00'
                }
            }, 'Debug Variables'),

            React.createElement('button', {
                onClick: loadRootVariables,
                style: {
                    padding: '6px 12px',
                    backgroundColor: '#00ff00',
                    color: '#000',
                    border: 'none',
                    borderRadius: '4px',
                    cursor: 'pointer',
                    fontWeight: 'bold'
                }
            }, 'Refresh')
        ),

        // Search bar
        React.createElement('div', {
            style: {
                padding: '12px 16px',
                backgroundColor: '#fff',
                borderBottom: '1px solid #e0e0e0'
            }
        },
            React.createElement('input', {
                type: 'text',
                placeholder: 'Search variables...',
                value: searchTerm,
                onChange: (e) => setSearchTerm(e.target.value),
                style: {
                    width: '100%',
                    padding: '8px 12px',
                    border: '1px solid #ccc',
                    borderRadius: '4px',
                    fontSize: '0.95em',
                    fontFamily: 'monospace'
                }
            })
        ),

        // Help text
        React.createElement('div', {
            style: {
                padding: '8px 16px',
                backgroundColor: '#fffbf0',
                borderBottom: '1px solid #e0e0e0',
                fontSize: '0.9em',
                color: '#666'
            }
        }, 'Click expandable nodes (▶) to browse hierarchical data. Arrays, hashtables, and objects can be expanded.'),

        // Tree view
        React.createElement('div', {
            style: {
                flex: 1,
                overflowY: 'auto',
                padding: '16px',
                backgroundColor: '#f8f8f8'
            }
        },
            loading && React.createElement('div', {
                style: {
                    textAlign: 'center',
                    padding: '40px',
                    color: '#888',
                    fontSize: '1.1em'
                }
            }, 'Loading variables...'),

            error && React.createElement('div', {
                style: {
                    padding: '20px',
                    backgroundColor: '#ffe0e0',
                    color: '#c00',
                    borderRadius: '4px',
                    margin: '20px'
                }
            }, `Error: ${error}`),

            !loading && !error && nodes.length === 0 && React.createElement('div', {
                style: {
                    textAlign: 'center',
                    padding: '40px',
                    color: '#888',
                    fontSize: '1.1em'
                }
            }, 'No variables found'),

            !loading && !error && nodes.length > 0 && React.createElement('div', null,
                nodes.map(node => renderNode(node))
            )
        )
    );
};

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['debug-variables'] = DebugVariables;
