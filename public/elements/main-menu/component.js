const { useState, useEffect } = React;

const MainMenu = ({ searchTerm, onError }) => {
    const [menuData, setMenuData] = useState([]);
    const [isLoading, setIsLoading] = useState(true);

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
        return () => { isMounted = false; };
    }, [searchTerm, onError]);

    const PswebMenuItem = ({ item }) => {
        const [isOpen, setIsOpen] = useState(true);
        const hasChildren = item.children && (Array.isArray(item.children) ? item.children.length > 0 : item.children);

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
            if (hasChildren) setIsOpen(!isOpen);
        };

        return (
            <li className={`menu-item ${hasChildren ? 'has-children' : ''} ${isOpen ? 'open' : ''}`}>
                <a href={item.url || '#'} onClick={handleClick} title={item.hover_description}>
                    {hasChildren && <span className="arrow" onClick={(e) => { e.stopPropagation(); setIsOpen(!isOpen); }}>{isOpen ? '▼' : '►'}</span>}
                    {item.text}
                </a>
                {hasChildren && isOpen && <ul className="submenu-list">{
                    (Array.isArray(item.children) ? item.children : [item.children]).map(child => <PswebMenuItem key={child.text} item={child} />)
                }</ul>}
            </li>
        );
    };

    if (isLoading) return <div>Loading menu...</div>;
    if (!menuData || menuData.length === 0) return <div>Menu not available.</div>;

    return (
        <ul className="main-menu-list">{menuData.map(item => <PswebMenuItem key={item.text} item={item} />)}</ul>
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