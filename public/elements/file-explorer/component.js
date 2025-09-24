const { useState, useEffect } = React;

const FileExplorerCard = ({ onError }) => {
    const [fileTree, setFileTree] = useState(null);

    useEffect(() => {
        let isMounted = true;

        const fetchData = () => {
            psweb_fetchWithAuthHandling('/api/v1/ui/elements/file-explorer')
                .then(res => {
                    if (!res.ok) {
                        if (isMounted) {
                            onError({ message: "Failed to fetch file explorer data", status: res.status, statusText: res.statusText });
                        }
                        throw new Error(`HTTP error! status: ${res.status}`);
                    }
                    return res.text();
                })
                .then(text => {
                    const data = text ? JSON.parse(text) : null;
                    if (isMounted) {
                        setFileTree(data);
                    }
                })
                .catch(err => {
                    if (err.name !== 'Unauthorized' && isMounted) {
                        console.error("FileExplorerCard fetch error:", err);
                        onError({ message: err.message, name: err.name });
                    }
                });
        };

        fetchData();

        return () => {
            isMounted = false;
        };
    }, []); // Intentionally empty to run only once

    const renderNode = (node) => {
        return (
            <li key={node.name} className={node.type}>
                {node.name}
                {node.type === 'folder' && node.children && (
                    <ul>{node.children.map(child => renderNode(child))}</ul>
                )}
            </li>
        );
    };

    const styles = `
        .file-tree { list-style: none; padding-left: 1em; }
        .file-tree .folder { font-weight: bold; }
        .file-tree .file { padding-left: 1em; }
    `;

    return (
        <>
            <style>{styles}</style>
            <div id="file-explorer-content">
                {fileTree ? (
                    <ul className="file-tree">
                        {renderNode(fileTree)}
                    </ul>
                ) : (
                    <p>Loading files...</p>
                )}
            </div>
        </>
    );
};

window.cardComponents['file-explorer'] = FileExplorerCard;
