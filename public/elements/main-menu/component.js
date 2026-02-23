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
                await window.psweb_fetchWithAuthHandling('/cards/main-menu/preferences', {
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
                const response = await window.psweb_fetchWithAuthHandling(`/cards/main-menu?search=${searchTerm}`);
                if (!response.ok) {
                    // Create error with status properties
                    const error = new Error(`HTTP error! status: ${response.status}`);
                    error.status = response.status;
                    error.statusText = response.statusText;
                    throw error;
                }
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
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [searchTerm]); // onError removed - shouldn't trigger re-fetch

    /**
     * Shows card control icons: "+" (open/copy) and "×" (close)
     */
    const CardStatusIndicator = ({ url }) => {
        const [isOpen, setIsOpen] = useState(false);
        const [cardId, setCardId] = useState(null);

        const elementId = React.useMemo(() => {
            const match = url.match(/\/api\/v1\/ui\/elements\/(.+?)(?:[?]|$)/);
            return match ? match[1] : null;
        }, [url]);

        useEffect(() => {
            const checkCardStatus = () => {
                if (elementId && window.findCardsByElementId) {
                    const existingCards = window.findCardsByElementId(elementId);
                    setIsOpen(existingCards.length > 0);
                    setCardId(existingCards[0] || null);
                }
            };

            checkCardStatus();
            const interval = setInterval(checkCardStatus, 500);
            return () => clearInterval(interval);
        }, [elementId]);

        const handlePlusClick = (e) => {
            e.preventDefault();
            e.stopPropagation();

            if (isOpen && window.openCardCopy) {
                // Card is already open, create a copy
                window.openCardCopy(url, elementId);
            } else {
                // Card is not open, open first instance
                window.openCard(url, elementId);
            }
        };

        const handleCloseClick = (e) => {
            e.preventDefault();
            e.stopPropagation();

            if (isOpen && cardId && window.removeCard) {
                window.removeCard(cardId);
            }
        };

        // When card is closed: show only "+"
        // When card is open: show both "+" (for copy) and "×" (for close)
        if (!isOpen) {
            return React.createElement('span', {
                className: 'card-status-icon closed',
                onClick: handlePlusClick,
                title: 'Open card'
            }, '+');
        } else {
            return React.createElement('span', {
                className: 'card-status-icons open'
            }, [
                React.createElement('span', {
                    key: 'copy',
                    className: 'card-status-icon copy',
                    onClick: handlePlusClick,
                    title: 'Open new copy'
                }, '+'),
                React.createElement('span', {
                    key: 'close',
                    className: 'card-status-icon close',
                    onClick: handleCloseClick,
                    title: 'Close card'
                }, '×')
            ]);
        }
    };

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
                    // Extract Element_Id from URL
                    const elementMatch = item.url.match(/\/api\/v1\/ui\/elements\/(.+?)(?:[?]|$)/);
                    const elementId = elementMatch ? elementMatch[1] : null;

                    // Check if card already open
                    if (elementId && window.findCardsByElementId) {
                        const existingCards = window.findCardsByElementId(elementId);

                        if (existingCards.length > 0) {
                            // Scroll to existing card
                            window.scrollToCard(existingCards[0]);
                            return;
                        }
                    }

                    // No existing card - open new one
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
                    {!hasChildren && item.url && item.url.includes('/api/v1/ui/elements/') && (
                        <CardStatusIndicator url={item.url} />
                    )}
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

    // Add CSS styles for card status icons
    useEffect(() => {
        const styleId = 'main-menu-card-status-styles';
        if (!document.getElementById(styleId)) {
            const style = document.createElement('style');
            style.id = styleId;
            style.textContent = `
                .card-status-icon {
                    display: inline-block;
                    margin-left: 8px;
                    width: 18px;
                    height: 18px;
                    line-height: 18px;
                    text-align: center;
                    border-radius: 3px;
                    font-size: 14px;
                    font-weight: bold;
                    transition: all 0.2s;
                    background: transparent;
                    color: #333;
                    border: 1px solid #ccc;
                }
                .card-status-icon:hover {
                    background: #f0f0f0;
                    border-color: #999;
                }
            `;
            document.head.appendChild(style);
        }
    }, []);

    return (
        <div className="main-menu">
            <input type="text" placeholder="Search..." value={searchTerm} onChange={(e) => setSearchTerm(e.target.value)} style={{ width: '100%', boxSizing: 'border-box', marginBottom: '10px' }}/>
            <MainMenu searchTerm={searchTerm} onError={onError} />
        </div>
    );
}

window.cardComponents = window.cardComponents || {};
window.cardComponents['main-menu'] = MainMenuContainer;