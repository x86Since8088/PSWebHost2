const { useState, useEffect, useRef, useCallback } = React;

const MainMenu = ({ searchTerm, onError }) => {
    const [menuData, setMenuData] = useState([]);
    const [isLoading, setIsLoading] = useState(true);
    const [menuStates, setMenuStates] = useState({}); // Track open/closed state for all menu items
    const saveTimeoutRef = useRef(null);

    // Debounced save function - saves 500ms after last state change
    const savePreferences = useCallback((states) => {
        if (saveTimeoutRef.current) {
            clearTimeout(saveTimeoutRef.current);
        }

        saveTimeoutRef.current = setTimeout(async () => {
            try {
                await window.psweb_fetchWithAuthHandling('/api/v1/ui/elements/main-menu/preferences', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(states)
                });
            } catch (error) {
                console.error('Failed to save menu preferences:', error);
            }
        }, 500);
    }, []);

    useEffect(() => {
        let isMounted = true;
        const pswebFetchMenu = async () => {
            setIsLoading(true);
            try {
                const response = await window.psweb_fetchWithAuthHandling(`/api/v1/ui/elements/main-menu?search=${searchTerm}`);
                if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
                const data = await response.json();
                if (isMounted) setMenuData(Array.isArray(data) ? data : (data ? [data] : []));
            } catch (error) {
                if (isMounted) {
                    onError({ message: `Failed to load menu: ${error.message}`, status: error.status, statusText: error.statusText });
                    setMenuData([]);
                }
            } finally {
                if (isMounted) setIsLoading(false);
            }
        };
        pswebFetchMenu();
        return () => {
            isMounted = false;
            if (saveTimeoutRef.current) {
                clearTimeout(saveTimeoutRef.current);
            }
        };
    }, [searchTerm, onError]);

    const PswebMenuItem = ({ item, parentPath = '' }) => {
        const hasChildren = item.children && (Array.isArray(item.children) ? item.children.length > 0 : item.children);

        // Build the full path for this menu item (matches backend logic)
        const currentPath = parentPath ? `${parentPath}/${item.text}` : item.text;

        // Use shared menuStates with backend-provided default
        // If user has saved preference, backend already applied it to item.collapsed
        const isOpen = menuStates[currentPath] !== undefined
            ? menuStates[currentPath]
            : (item.collapsed === true ? false : true);

        const toggleMenu = (newState) => {
            const updatedStates = { ...menuStates, [currentPath]: newState };
            setMenuStates(updatedStates);
            savePreferences(updatedStates);
        };

        const handleClick = (e) => {
            e.preventDefault();
            if (item.url) {
                if (item.url.startsWith('action:')) {
                    const action = item.url.split(':')[1];
                    if (action === 'reset-grid') {
                        window.resetGrid();
                    }
                } else if (item.url.startsWith('/api/v1/config/')) {
                    window.openComponentInModal('generic-form', { getConfigUrl: item.url, postConfigUrl: item.url.replace('/get.ps1', '/post.ps1'), title: item.text });
                } else if (!hasChildren) {
                    window.openCard(item.url, item.text);
                }
            }
            if (hasChildren) toggleMenu(!isOpen);
        };

        // Generate a unique key from text and url (or index if needed)
        const getItemKey = (childItem, idx) => {
            const textPart = childItem.text || '';
            const urlPart = childItem.url || '';
            return `${textPart}-${urlPart}-${idx}`;
        };

        return (
            <li className={`menu-item ${hasChildren ? 'has-children' : ''} ${isOpen ? 'open' : ''}`}>
                <a href={item.url || '#'} onClick={handleClick} title={item.hover_description}>
                    {hasChildren && <span className="arrow" onClick={(e) => { e.stopPropagation(); toggleMenu(!isOpen); }}>{isOpen ? '▼' : '►'}</span>}
                    {item.text}
                </a>
                {hasChildren && isOpen && <ul className="submenu-list">{
                    (Array.isArray(item.children) ? item.children : [item.children]).map((child, idx) =>
                        <PswebMenuItem key={getItemKey(child, idx)} item={child} parentPath={currentPath} />
                    )
                }</ul>}
            </li>
        );
    };

    // Generate a unique key from text and url
    const getItemKey = (item, idx) => {
        const textPart = item.text || '';
        const urlPart = item.url || '';
        return `${textPart}-${urlPart}-${idx}`;
    };

    if (isLoading) return <div>Loading menu...</div>;
    if (!menuData || menuData.length === 0) return <div>Menu not available.</div>;

    return (
        <ul className="main-menu-list">{menuData.map((item, idx) => <PswebMenuItem key={getItemKey(item, idx)} item={item} />)}</ul>
    );
};

const MainMenuContainer = ({ element, onError }) => {
    const [searchTerm, setSearchTerm] = useState("");

    return (
        <div className="main-menu">
            <input type="text" placeholder="Search..." value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} style={{ width: '100%', boxSizing: 'border-box', marginBottom: '10px' }}/>
            <MainMenu searchTerm={searchTerm} onError={onError} />
        </div>
    );
}

window.cardComponents['main-menu'] = MainMenuContainer;