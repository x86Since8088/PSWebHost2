const { useState, useEffect, useCallback, lazy, Suspense, useRef } = React;

// --- Global Helper for Fetching ---
async function psweb_fetchWithAuthHandling(url, options) {
    const response = await fetch(url, options);
    if (response.status === 401) {
        // The caller is responsible for handling 401.
    }
    return response;
}

// --- Global Helper for Client-Side Logging ---
window.logToServer = async function(level, category, message, data) {
    try {
        await fetch('/api/v1/debug/client-log', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                level: level,
                category: category,
                message: message,
                data: data,
                url: window.location.href,
                timestamp: new Date().toISOString()
            })
        });
    } catch (err) {
        console.error('Failed to log to server:', err);
    }
}

// Log client errors automatically
window.addEventListener('error', (event) => {
    window.logToServer('Error', 'GlobalError', event.message, {
        filename: event.filename,
        lineno: event.lineno,
        colno: event.colno,
        error: event.error ? event.error.stack : null
    });
});

// Log unhandled promise rejections
window.addEventListener('unhandledrejection', (event) => {
    window.logToServer('Error', 'UnhandledPromise', event.reason.toString(), {
        reason: event.reason,
        promise: event.promise
    });
});

// --- Global Component Registry ---
window.cardComponents = {};

// --- IFrame Component ---
const IFrameComponent = ({ element }) => {
    return <iframe src={element.url} style={{ width: '100%', height: '100%', border: 'none' }} />;
};
window.cardComponents['iframe-card'] = IFrameComponent;


// --- Modal Component ---
const Modal = ({ isOpen, onClose, src, children, component: Component, componentProps }) => {
    if (!isOpen) return null;
    const modalStyle = { position: 'fixed', top: 0, left: 0, width: '100%', height: '100%', backgroundColor: 'rgba(0, 0, 0, 0.5)', display: 'flex', justifyContent: 'center', alignItems: 'center', zIndex: 1000 };
    const contentStyle = { backgroundColor: '#fff', padding: '20px', borderRadius: '8px', width: 'auto', minWidth: '400px', maxHeight: '80%', display: 'flex', flexDirection: 'column', overflow: 'auto' };
    const iframeStyle = { flexGrow: 1, border: 'none', width: '80vw', height: '80vh' };

    return (
        <div style={modalStyle} onClick={onClose}>
            <div style={contentStyle} onClick={(e) => e.stopPropagation()}>
                <button onClick={onClose} style={{ alignSelf: 'flex-end' }}>Close</button>
                {src && <iframe src={src} style={iframeStyle}></iframe>}
                {Component && <Component {...componentProps} />}
                {children}
            </div>
        </div>
    );
};

const UserCard = ({ element }) => {
    const [userData, setUserData] = useState(null);
    const [error, setError] = useState(null);
    const [loading, setLoading] = useState(true);
    const [isMenuOpen, setIsMenuOpen] = useState(false);

    useEffect(() => {
        let isMounted = true;
        psweb_fetchWithAuthHandling('/api/v1/auth/sessionid')
            .then(response => response.text())
            .then(text => {
                if (isMounted) {
                    try {
                        const data = text ? JSON.parse(text) : null;
                        setUserData(data);
                    } catch (e) {
                        console.error("Failed to parse session data", e);
                        setError(e);
                    }
                    setLoading(false);
                }
            })
            .catch(err => {
                if (isMounted) {
                    setError(err);
                    setLoading(false);
                }
            });
        return () => { isMounted = false; };
    }, []);

    if (loading) return <div>Loading user...</div>;
    if (error) return <div>Error: {error.message}</div>;

    if (!userData || !userData.Roles || !userData.Roles.includes('authenticated')) {
        return <button onClick={() => {
            const authUrl = '/api/v1/auth/getauthtoken?RedirectTo=' + encodeURIComponent(window.location.href);
            window.location.href = authUrl;
        }}>Logon</button>;
    }

    const userIcon = userData.icon || '/public/icon/Tank1_32x32.png';

    return (
        <div className="user-card">
            <img src={userIcon} alt="User" onClick={() => setIsMenuOpen(!isMenuOpen)} style={{cursor: 'pointer', borderRadius: '50%', width: '32px', height: '32px'}} />
            {isMenuOpen && (
                <div className="floating-card">
                    <div className="floating-card-content">
                        <div>Welcome, {userData.UserID}</div>
                        <a href="#" onClick={(e) => { e.preventDefault(); window.openComponentInModal('profile'); }}>Profile</a>
                        <a href="/settings">Settings &#9881;</a>
                        <a href="/api/v1/auth/logoff">Logoff</a>
                    </div>
                </div>
            )}
        </div>
    );
};

const Card = ({ element, onRemove, onOpenSettings, onMaximize, onCardResize, isMaximized }) => {
    // Safety check - element must exist
    if (!element) {
        console.error('Card component received undefined element');
        return <div className="card"><div className="card-content">Error: Invalid card configuration</div></div>;
    }

    // Extract element type from Element_Id or parse from id (e.g., "main-menu-123456" -> "main-menu")
    let elementId = element.Element_Id;
    if (!elementId && element.id) {
        // Try to extract element type from id by removing timestamp suffix
        const match = element.id.match(/^(.+?)-\d+$/);
        elementId = match ? match[1] : element.id;
    }

    const initialComponent = window.cardComponents[elementId] || null;
    // IMPORTANT: Wrap in arrow function to prevent React from calling it as an initializer
    const [CardComponent, setCardComponent] = useState(() => initialComponent);
    const [errorInfo, setErrorInfo] = useState(null);
    const contentRef = useRef(null);

    // Monitor for when the component becomes available
    useEffect(() => {
        if (!CardComponent) {
            // Poll every 50ms for up to 5 seconds
            let attempts = 0;
            const maxAttempts = 100; // 5 seconds

            const checkInterval = setInterval(() => {
                attempts++;
                if (window.cardComponents[elementId]) {
                    setCardComponent(window.cardComponents[elementId]);
                    clearInterval(checkInterval);
                } else if (attempts >= maxAttempts) {
                    clearInterval(checkInterval);
                }
            }, 50);

            return () => clearInterval(checkInterval);
        }
    }, [elementId, CardComponent]);

    useEffect(() => {
        if (contentRef.current && CardComponent) {
            const contentHeight = contentRef.current.scrollHeight;
            const contentWidth = contentRef.current.scrollWidth;
            onCardResize(element.id, contentHeight, contentWidth);
        }
    }, [CardComponent]); // Rerun when component changes

    const handleError = (error) => {
        if (error && typeof error === 'object') {
            setErrorInfo({
                message: error.message || 'Unknown error',
                status: error.status,
                statusText: error.statusText
            });
            // Log to server
            window.logToServer('Error', elementId || 'Card', error.message || 'Component error', {
                elementId: elementId,
                status: error.status,
                statusText: error.statusText,
                cardId: element.id
            });
        }
    };

    const title = element.Title || 'Untitled';

    // Prepare props for component
    const componentProps = {
        element: element,
        onError: handleError
    };

    // Render component content
    let cardContent;
    if (CardComponent && typeof CardComponent === 'function') {
        cardContent = React.createElement(CardComponent, componentProps);
    } else if (CardComponent) {
        cardContent = <div>Error: Invalid component type for {elementId}</div>;
    } else {
        cardContent = <p>Loading component...</p>;
    }

    return (
        <div className={`card ${isMaximized ? 'maximized' : ''}`} style={{height: '100%'}}>
            <div className="card-title-bar">
                {element.icon && <img src={element.icon} className="card-icon" alt="icon" />}
                <span>{title}</span>
                <div className="spacer"></div>
                <div className="maximize-icon" onClick={() => onMaximize(element.id)}>
                    {isMaximized ? '🗗' : '🗖'}
                </div>
                <div className="settings-icon" onClick={() => onOpenSettings(element.id)}>&#9881;</div>
                <div className="close-icon" onClick={() => onRemove(element.id)}>&times;</div>
            </div>
            <div className="card-content" ref={contentRef}>
                {cardContent}
            </div>
            {errorInfo && (
                <div className="card-footer">
                    {errorInfo.status && <span>{errorInfo.status}: {errorInfo.statusText}</span>}
                    <p>{errorInfo.message}</p>
                </div>
            )}
        </div>
    );
};

const Pane = ({ zone, cardIds, elements, onRemoveCard, onOpenSettings, onMaximize, onCardResize, maximizedCard }) => {
    if (!cardIds || cardIds.length === 0) return null;

    return (
        <div className={`pane-section ${zone}`}>
            {cardIds.map(id => {
                if (id === 'user-card') return <UserCard key={id} element={{...elements[id], id: id}} />;
                return <Card key={id} element={{...elements[id], id: id}} onRemove={onRemoveCard} onOpenSettings={onOpenSettings} onMaximize={onMaximize} onCardResize={onCardResize} isMaximized={maximizedCard === id} />;
            })}
        </div>
    );
};

const CardSettingsModal = ({ isOpen, onClose, cardLayout, onSave }) => {
    if (!isOpen) return null;

    const [layout, setLayout] = useState(cardLayout);

    useEffect(() => {
        setLayout(cardLayout);
    }, [cardLayout]);

    const handleChange = (e) => {
        setLayout({ ...layout, [e.target.name]: parseInt(e.target.value, 10) });
    };

    const handleSave = () => {
        onSave(layout);
        onClose();
    };

    return (
        <Modal isOpen={isOpen} onClose={onClose}>
            <div style={{ padding: '20px' }}>
                <h3>Card Settings</h3>
                <div style={{ marginBottom: '10px' }}>
                    <label>Width (w)</label><br/>
                    <input type="number" name="w" value={layout.w} onChange={handleChange} />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Height (h)</label><br/>
                    <input type="number" name="h" value={layout.h} onChange={handleChange} />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Column (x)</label><br/>
                    <input type="number" name="x" value={layout.x} onChange={handleChange} />
                </div>
                <div style={{ marginBottom: '10px' }}>
                    <label>Row (y)</label><br/>
                    <input type="number" name="y" value={layout.y} onChange={handleChange} />
                </div>
                <button onClick={handleSave}>Save</button>
            </div>
        </Modal>
    );
};

const App = () => {
    const [data, setData] = useState({ layout: null, elements: null, componentsReady: false });
    const [gridLayout, setGridLayout] = useState([]);
    const [error, setError] = useState(null);
    const [modal, setModal] = useState({ isOpen: false, src: '', component: null, props: {} });
    const [settingsModal, setSettingsModal] = useState({ isOpen: false, cardId: null });
    const [maximizedCard, setMaximizedCard] = useState(null);
    const [layoutBeforeMaximize, setLayoutBeforeMaximize] = useState(null);
    const [gridWidth, setGridWidth] = useState(1200);
    const gridRef = useRef(null);
    const GridLayout = window.ReactGridLayout;

    const findNextFreePosition = (layout, item) => {
        const { w, h } = item;
        const cols = 12;
        const grid = Array(100).fill(0).map(() => Array(cols).fill(0)); // A large enough grid

        // Mark occupied cells
        layout.forEach(item => {
            for (let i = item.y; i < item.y + item.h; i++) {
                for (let j = item.x; j < item.x + item.w; j++) {
                    if (i < 100 && j < cols) {
                        grid[i][j] = 1;
                    }
                }
            }
        });

        // Find a free spot
        for (let i = 0; i < 100 - h; i++) {
            for (let j = 0; j < cols - w; j++) {
                let isFree = true;
                for (let k = i; k < i + h; k++) {
                    for (let l = j; l < j + w; l++) {
                        if (grid[k][l] === 1) {
                            isFree = false;
                            break;
                        }
                    }
                    if (!isFree) break;
                }
                if (isFree) {
                    return { x: j, y: i };
                }
            }
        }

        return { x: 0, y: Infinity }; // Fallback
    }

    const loadLayout = () => {
        fetch('/public/layout.json')
            .then(response => response.json())
            .then(initialData => {
                const allCardIds = Object.values(initialData.layout).flatMap(pane => Object.values(pane)).flat();
                const uniqueCardIds = [...new Set(allCardIds)];
                const defaultLayout = initialData.gridLayout.find(item => item.i === 'default') || { w: 12, h: 10 };
                
                const componentPromises = uniqueCardIds
                    .filter(id => id && id !== 'user-card' && id !== 'title')
                    .map(id => {
                        return fetch(`/public/elements/${id}/component.js`)
                            .then(res => res.text())
                            .then(text => {
                                if (text) {
                                    const transformed = Babel.transform(text, { presets: ['react'] }).code;
                                    (new Function(transformed))();
                                }
                            });
                    });
                
                const profilePromise = fetch('/public/elements/profile/component.js').then(res => res.text()).then(text => {
                    if(text) (new Function(Babel.transform(text, { presets: ['react'] }).code))();
                });

                Promise.all([...componentPromises, profilePromise])
                    .then(() => {
                        setData({ ...initialData, componentsReady: true });
                        const mainPaneLayout = initialData.layout.mainPane.content.map((id, index) => {
                            const specificLayout = initialData.gridLayout.find(item => item.i === id);
                            return {
                                i: id,
                                x: (index % 4) * 3,
                                y: Math.floor(index / 4) * 2,
                                w: specificLayout ? specificLayout.w : defaultLayout.w,
                                h: specificLayout ? specificLayout.h : defaultLayout.h,
                                ...specificLayout
                            }
                        });
                        setGridLayout(mainPaneLayout);
                    })
                    .catch(setError);
            })
            .catch(setError);
    }

    window.resetGrid = () => {
        loadLayout();
    }

    window.openAuthModal = () => {
        const authUrl = '/api/v1/auth/getauthtoken?RedirectTo=' + encodeURIComponent(window.location.href);
        const authPopup = window.open(authUrl, 'authPopup', 'width=500,height=600');
    };

    window.openComponentInModal = (componentName, props = {}) => {
        setModal({ isOpen: true, src: '', component: window.cardComponents[componentName], props: props });
    };

    // Helper function to load component script dynamically
    const loadComponentScript = (elementId) => {
        return new Promise((resolve, reject) => {
            // Check if component is already loaded
            if (window.cardComponents[elementId]) {
                resolve();
                return;
            }

            console.log(`Loading component script for ${elementId}...`);

            // Fetch and explicitly transform with Babel (same pattern as loadLayout)
            fetch(`/public/elements/${elementId}/component.js`)
                .then(res => {
                    if (!res.ok) {
                        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                    }
                    return res.text();
                })
                .then(text => {
                    if (text) {
                        console.log(`Transforming ${elementId} with Babel...`);
                        const transformed = Babel.transform(text, { presets: ['react'] }).code;
                        (new Function(transformed))();

                        if (window.cardComponents[elementId]) {
                            console.log(`✓ Component ${elementId} loaded and registered`);
                        } else {
                            console.warn(`⚠ Component ${elementId} loaded but not registered in window.cardComponents`);
                            window.logToServer('Warning', 'ComponentLoad', `Component ${elementId} loaded but not registered`, { elementId: elementId });
                        }
                    }
                    resolve();
                })
                .catch(err => {
                    console.log(`Failed to load component.js for ${elementId}, trying element.js fallback...`);
                    window.logToServer('Warning', 'ComponentLoad', `Failed to load ${elementId}/component.js: ${err.message}`, { elementId: elementId, error: err.toString() });

                    // Try loading element.js as fallback (for legacy components)
                    fetch(`/public/elements/${elementId}/element.js`)
                        .then(res => {
                            if (!res.ok) {
                                throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                            }
                            return res.text();
                        })
                        .then(text => {
                            if (text) {
                                console.log(`Transforming ${elementId} (fallback) with Babel...`);
                                const transformed = Babel.transform(text, { presets: ['react'] }).code;
                                (new Function(transformed))();

                                if (window.cardComponents[elementId]) {
                                    console.log(`✓ Component ${elementId} loaded (fallback)`);
                                }
                            }
                            resolve();
                        })
                        .catch(fallbackErr => {
                            console.error(`Failed to load ${elementId} component:`, fallbackErr);
                            resolve(); // Resolve anyway to allow card creation
                        });
                });
        });
    };

    window.openCard = async (url, title) => {
        // Extract element ID from URL if it's an API endpoint
        // e.g., /api/v1/ui/elements/system-log -> system-log
        let elementId = 'iframe-card';
        let elementUrl = url;

        const elementMatch = url.match(/\/api\/v1\/ui\/elements\/([^/?]+)/);
        if (elementMatch) {
            elementId = elementMatch[1];
            elementUrl = url; // Keep the full URL for fetching
        }

        // Load the component script if needed
        if (elementId !== 'iframe-card') {
            await loadComponentScript(elementId);
        }

        // Create the card
        const cardId = elementId + '-' + Date.now();
        const newElement = {
            Title: title,
            Element_Id: elementId,
            url: elementUrl,
            id: cardId
        };

        const defaultLayout = data.gridLayout.find(item => item.i === 'default') || { w: 12, h: 10 };
        const position = findNextFreePosition(gridLayout, defaultLayout);

        setData(prevData => {
            const newElements = { ...prevData.elements, [cardId]: newElement };
            const newLayout = JSON.parse(JSON.stringify(prevData.layout));
            newLayout.mainPane.content.push(cardId);
            return { ...prevData, elements: newElements, layout: newLayout };
        });

        setGridLayout(prevGridLayout => {
            return [...prevGridLayout, { ...defaultLayout, i: cardId, ...position }];
        });
    };
    
    const openSettingsModal = (cardId) => {
        setSettingsModal({ isOpen: true, cardId: cardId });
    };

    const closeSettingsModal = () => {
        setSettingsModal({ isOpen: false, cardId: null });
    };

    const handleSaveCardSettings = (newCardLayout) => {
        const newGridLayout = gridLayout.map(item => item.i === newCardLayout.i ? newCardLayout : item);
        setGridLayout(newGridLayout);
        // TODO: Save to backend
    };

    const handleMaximizeCard = (cardId, event) => {
        if (maximizedCard) {
            // Un-maximize: restore layout
            setGridLayout(layoutBeforeMaximize);
            setMaximizedCard(null);
            setLayoutBeforeMaximize(null);

            // Restore all parent elements' style attributes
            setTimeout(() => {
                if (event && event.target) {
                    let element = event.target;
                    let parentIndex = 0;

                    // Walk up the parent chain and restore styles
                    while (element && element !== document.body && parentIndex < 20) {
                        const savedStyle = element.getAttribute('data-maximized-style-' + parentIndex);
                        if (savedStyle !== null) {
                            if (savedStyle === '') {
                                element.removeAttribute('style');
                            } else {
                                element.setAttribute('style', savedStyle);
                            }
                            element.removeAttribute('data-maximized-style-' + parentIndex);
                        }
                        element = element.parentElement;
                        parentIndex++;
                    }
                }
            }, 0);
        } else {
            // Maximize: save layout
            setLayoutBeforeMaximize(gridLayout);
            setMaximizedCard(cardId);

            const newLayout = gridLayout.map(item => {
                if (item.i === cardId) {
                    // Use a very large height value to ensure vertical maximization
                    // React Grid Layout uses row height, so multiply by a large number
                    return { ...item, x: 0, y: 0, w: 12, h: 50 }; // Much larger height
                }
                return item;
            });
            setGridLayout(newLayout);

            // Strip style attributes from React Grid Layout wrappers as the LAST action
            setTimeout(() => {
                if (event && event.target) {
                    // Find the maximized card
                    let cardElement = event.target;
                    while (cardElement && !cardElement.classList.contains('card')) {
                        cardElement = cardElement.parentElement;
                    }

                    if (cardElement && cardElement.classList.contains('maximized')) {
                        let element = cardElement.parentElement; // Start from card's parent
                        let parentIndex = 0;

                        // Walk up the parent chain, save styles, then strip them
                        // Stop at react-grid-layout or body
                        while (element && element !== document.body && parentIndex < 20) {
                            // Don't strip from the main grid container
                            if (element.classList.contains('react-grid-layout')) {
                                break;
                            }

                            // Save the original style attribute
                            const currentStyle = element.getAttribute('style') || '';
                            element.setAttribute('data-maximized-style-' + parentIndex, currentStyle);

                            // Strip the style attribute to remove React Grid Layout positioning
                            element.removeAttribute('style');

                            element = element.parentElement;
                            parentIndex++;
                        }
                    }
                }
            }, 100); // Increased timeout to ensure this runs after React updates
        }
    };

    const removeCard = (cardIdToRemove) => {
        const newLayout = JSON.parse(JSON.stringify(data.layout));
        for (const pane in newLayout) {
            for (const section in newLayout[pane]) {
                newLayout[pane][section] = newLayout[pane][section].filter(id => id !== cardIdToRemove);
            }
        }
        setData(prevData => ({ ...prevData, layout: newLayout }));
    };

    const handleLayoutChange = (layout) => {
        setGridLayout(layout);
    };

    const handleCardResize = (cardId, contentHeight, contentWidth) => {
        if (!gridRef.current) return;
        const rowHeight = 15;
        const colWidth = gridRef.current.clientWidth / 12;
        const newHeight = Math.ceil(contentHeight / rowHeight);
        const newWidth = Math.ceil(contentWidth / colWidth);

        setGridLayout(prevLayout => {
            return prevLayout.map(item => {
                if (item.i === cardId) {
                    if(item.h !== newHeight || item.w !== newWidth) {
                        return { ...item, h: newHeight, w: newWidth };
                    }
                }
                return item;
            });
        });
    };

    useEffect(() => {
        loadLayout();
        window.addEventListener('message', (event) => {
            if (event.data === 'auth-success') {
                window.location.reload();
            }
        });
    }, []);

    // Responsive grid width observer
    useEffect(() => {
        const updateGridWidth = () => {
            if (gridRef.current) {
                const width = gridRef.current.offsetWidth;
                if (width > 0) {
                    console.log('Grid width updated:', width);
                    setGridWidth(width);
                }
            }
        };

        // Initial width update after a short delay to ensure DOM is ready
        const timeoutId = setTimeout(updateGridWidth, 100);

        if (!gridRef.current) {
            return () => clearTimeout(timeoutId);
        }

        const resizeObserver = new ResizeObserver(entries => {
            for (let entry of entries) {
                const width = entry.contentRect.width;
                if (width > 0) {
                    console.log('ResizeObserver fired, new width:', width);
                    setGridWidth(width);
                }
            }
        });

        resizeObserver.observe(gridRef.current);

        return () => {
            clearTimeout(timeoutId);
            resizeObserver.disconnect();
        };
    }, [data.componentsReady, data.layout]);

    if (error) return <div>Error: {error.message}</div>;
    if (!data.componentsReady) return <div>Loading Components...</div>;
    if (!data.layout) return <div>Loading Layout...</div>;

    const { layout, elements } = data;
    const currentCardLayout = gridLayout.find(item => item.i === settingsModal.cardId);

    return (
        <div className="app-container">
            <Modal isOpen={modal.isOpen} onClose={() => setModal({ isOpen: false, src: '', component: null, props: {} })} {...modal} />
            <CardSettingsModal isOpen={settingsModal.isOpen} onClose={closeSettingsModal} cardLayout={currentCardLayout} onSave={handleSaveCardSettings} />

            <header className="title-pane">
                <Pane zone="title-left" cardIds={layout.title.left} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                <Pane zone="title-content" cardIds={layout.title.content} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                <Pane zone="title-right" cardIds={layout.title.right} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
            </header>
            <div className="center-body">
                <aside className="left-pane" style={{ display: layout.leftPane.top.length === 0 && layout.leftPane.bottom.length === 0 ? 'none' : 'flex' }}>
                    <Pane zone="left-pane-top" cardIds={layout.leftPane.top} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                    <Pane zone="left-pane-bottom" cardIds={layout.leftPane.bottom} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                </aside>
                <main className="main-pane" ref={gridRef}>
                     <GridLayout
                        className="layout"
                        layout={gridLayout}
                        cols={12}
                        rowHeight={15}
                        width={gridWidth}
                        onLayoutChange={handleLayoutChange}
                    >
                        {layout.mainPane.content.map(id => (
                            <div key={id}>
                                <Card element={{...elements[id], id: id}} onRemove={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} isMaximized={maximizedCard === id} />
                            </div>
                        ))}
                    </GridLayout>
                </main>
                <aside className="right-pane" style={{ display: layout.rightPane.content.length === 0 ? 'none' : 'flex' }}>
                    <Pane zone="right-pane-content" cardIds={layout.rightPane.content} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                </aside>
            </div>
            <footer className="footer-pane">
                <Pane zone="footer-left" cardIds={layout.footer.left} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                <Pane zone="footer-center" cardIds={layout.footer.center} elements={elements} onRemoveCard={removeCard} onOpenSettings={openSettingsModal} onMaximize={handleMaximizeCard} onCardResize={handleCardResize} maximizedCard={maximizedCard} />
                <div className="pane-section footer-right" style={{fontSize: '0.85em', color: 'var(--text-secondary)'}}>
                    Grid Width: {gridWidth}px
                </div>
            </footer>
        </div>
    );
};

ReactDOM.render(<App />, document.getElementById('root'));