const { useState, useEffect, useCallback, lazy, Suspense, useRef } = React;

// --- Client-Side Cache Manager ---
const CacheManager = {
    prefix: 'psweb_cache_',

    set(key, data, maxAge = 1800) {
        try {
            const item = {
                data: data,
                timestamp: Date.now(),
                maxAge: maxAge * 1000, // Convert to milliseconds
                etag: data.etag || null
            };
            localStorage.setItem(this.prefix + key, JSON.stringify(item));
        } catch (e) {
            console.warn('Failed to cache data:', e);
        }
    },

    get(key) {
        try {
            const item = localStorage.getItem(this.prefix + key);
            if (!item) return null;

            const cached = JSON.parse(item);
            const age = Date.now() - cached.timestamp;

            // Return cached data with freshness info
            return {
                data: cached.data,
                age: age,
                maxAge: cached.maxAge,
                isFresh: age < cached.maxAge,
                isStale: age >= cached.maxAge,
                etag: cached.etag
            };
        } catch (e) {
            console.warn('Failed to read cache:', e);
            return null;
        }
    },

    invalidate(key) {
        try {
            localStorage.removeItem(this.prefix + key);
            // Also store invalidation timestamp to force cache bypass
            localStorage.setItem(this.prefix + 'invalidated_' + key, Date.now().toString());
            console.log(`Cache invalidated for: ${key}`);
        } catch (e) {
            console.warn('Failed to invalidate cache:', e);
        }
    },

    wasRecentlyInvalidated(key, withinMs = 5000) {
        try {
            const invalidatedAt = localStorage.getItem(this.prefix + 'invalidated_' + key);
            if (!invalidatedAt) return false;
            const age = Date.now() - parseInt(invalidatedAt, 10);
            return age < withinMs;
        } catch (e) {
            return false;
        }
    },

    invalidatePattern(pattern) {
        try {
            const regex = new RegExp(pattern);
            const keys = Object.keys(localStorage).filter(k => k.startsWith(this.prefix) && regex.test(k));
            keys.forEach(k => localStorage.removeItem(k));
            console.log(`Invalidated ${keys.length} cache entries matching: ${pattern}`);
        } catch (e) {
            console.warn('Failed to invalidate cache pattern:', e);
        }
    },

    clear() {
        try {
            const keys = Object.keys(localStorage).filter(k => k.startsWith(this.prefix));
            keys.forEach(k => localStorage.removeItem(k));
            console.log(`Cleared ${keys.length} cache entries`);
        } catch (e) {
            console.warn('Failed to clear cache:', e);
        }
    }
};

// Make cache manager globally available
window.CacheManager = CacheManager;

// Expose helpful cache management functions
window.clearAllCache = () => {
    CacheManager.clear();
    console.log('All cache cleared. Reload the page to fetch fresh data.');
};

window.viewCacheStats = () => {
    const keys = Object.keys(localStorage).filter(k => k.startsWith(CacheManager.prefix));
    console.log(`Cache Statistics:`);
    console.log(`Total cached items: ${keys.length}`);

    keys.forEach(key => {
        const cached = CacheManager.get(key.replace(CacheManager.prefix, ''));
        if (cached) {
            const ageMinutes = Math.floor(cached.age / 60000);
            const maxAgeMinutes = Math.floor(cached.maxAge / 60000);
            console.log(`  - ${key.replace(CacheManager.prefix, '')}: ${cached.isFresh ? 'FRESH' : 'STALE'} (age: ${ageMinutes}m / max: ${maxAgeMinutes}m)`);
        }
    });

    return { totalItems: keys.length };
};

// --- Request Throttle Manager ---
// Prevents repeated requests to endpoints that recently returned 4xx/5xx errors
const RequestThrottleManager = {
    throttledRequests: new Map(), // URL -> { timestamp, status, retryAfter }
    throttleDuration: 60000, // 60 seconds

    /**
     * Check if a URL is currently throttled
     * @param {string} url - The request URL
     * @returns {boolean|object} - false if not throttled, or throttle info if throttled
     */
    isThrottled(url) {
        const throttle = this.throttledRequests.get(url);
        if (!throttle) return false;

        const now = Date.now();
        const timeSinceError = now - throttle.timestamp;

        if (timeSinceError < this.throttleDuration) {
            const remainingSeconds = Math.ceil((this.throttleDuration - timeSinceError) / 1000);
            return {
                blocked: true,
                status: throttle.status,
                remainingSeconds,
                message: `Request throttled due to previous ${throttle.status} error. Retry in ${remainingSeconds}s.`
            };
        }

        // Throttle expired, remove it
        this.throttledRequests.delete(url);
        return false;
    },

    /**
     * Record a failed request for throttling
     * @param {string} url - The request URL
     * @param {number} status - HTTP status code
     */
    recordFailure(url, status) {
        this.throttledRequests.set(url, {
            timestamp: Date.now(),
            status
        });
        console.warn(`[RequestThrottle] Throttling ${url} for ${this.throttleDuration/1000}s due to ${status} error`);
    },

    /**
     * Clear throttle for a URL (called on successful requests)
     * @param {string} url - The request URL
     */
    clearThrottle(url) {
        if (this.throttledRequests.has(url)) {
            console.log(`[RequestThrottle] Clearing throttle for ${url}`);
            this.throttledRequests.delete(url);
        }
    }
};

// Make throttle manager globally available for debugging
window.RequestThrottleManager = RequestThrottleManager;

// --- Global Helper for Fetching with Cache Support and Throttling ---
window.psweb_fetchWithAuthHandling = async function(url, options) {
    // Check if request is throttled
    const throttleInfo = RequestThrottleManager.isThrottled(url);
    if (throttleInfo) {
        console.warn(`[RequestThrottle] ${throttleInfo.message}`);
        // Return a fake response object that looks like a 429 Too Many Requests
        return new Response(JSON.stringify({
            status: 'fail',
            message: throttleInfo.message,
            throttled: true,
            retryAfter: throttleInfo.remainingSeconds
        }), {
            status: 429,
            statusText: 'Too Many Requests',
            headers: {
                'Content-Type': 'application/json',
                'Retry-After': throttleInfo.remainingSeconds.toString()
            }
        });
    }

    const response = await fetch(url, options);

    // Check for error responses that should show a modal
    if (!response.ok && response.status >= 400) {
        // Record 4xx and 5xx errors for throttling
        RequestThrottleManager.recordFailure(url, response.status);

        try {
            const contentType = response.headers.get('content-type');
            if (contentType && contentType.includes('application/json')) {
                const errorData = await response.clone().json();

                // If backend instructed to show modal, display it
                if (errorData.showModal) {
                    window.showErrorModal(errorData);
                }
            }
        } catch (parseError) {
            // If we can't parse the error response, that's okay - continue with normal error handling
            console.warn('Could not parse error response for modal:', parseError);
        }
    } else if (response.ok) {
        // Clear throttle on successful request
        RequestThrottleManager.clearThrottle(url);
    }

    if (response.status === 401) {
        // The caller is responsible for handling 401.
    }
    return response;
};

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

// Intercept console.error and console.warn for server-side logging
(function() {
    const originalError = console.error;
    const originalWarn = console.warn;

    console.error = function(...args) {
        originalError.apply(console, args);
        // Forward to server (avoid logging the forward itself to prevent loops)
        try {
            window.logToServer('Error', 'ConsoleError', args.join(' '), { args: args });
        } catch (e) {
            // Silently fail to avoid infinite loops
        }
    };

    console.warn = function(...args) {
        originalWarn.apply(console, args);
        try {
            window.logToServer('Warning', 'ConsoleWarn', args.join(' '), { args: args });
        } catch (e) {
            // Silently fail to avoid infinite loops
        }
    };
})();

// --- Global Error Modal Handler ---
window.showErrorModal = function(errorData) {
    // Create modal container if it doesn't exist
    let modalContainer = document.getElementById('error-modal-container');
    if (!modalContainer) {
        modalContainer = document.createElement('div');
        modalContainer.id = 'error-modal-container';
        document.body.appendChild(modalContainer);
    }

    // Render the modal using React
    const ErrorModal = ({ errorData, onClose }) => {
        const formatErrorContent = () => {
            if (errorData.modalType === 'error-admin') {
                // Admin view - show detailed information in readable format
                return React.createElement('div', { className: 'error-modal-content error-admin' },
                    React.createElement('div', { className: 'error-section' },
                        React.createElement('h3', null, 'Error Details'),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Message: '),
                            React.createElement('span', null, errorData.error.Message)
                        ),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Type: '),
                            React.createElement('code', null, errorData.error.Type)
                        ),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Position: '),
                            React.createElement('pre', null, errorData.error.PositionMessage)
                        )
                    ),
                    React.createElement('div', { className: 'error-section' },
                        React.createElement('h3', null, 'Request Information'),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Method: '),
                            React.createElement('span', null, errorData.request.Method)
                        ),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'URL: '),
                            React.createElement('code', null, errorData.request.URL)
                        ),
                        errorData.request.QueryString && Object.keys(errorData.request.QueryString).length > 0 &&
                            React.createElement('div', { className: 'error-field' },
                                React.createElement('strong', null, 'Query Parameters: '),
                                React.createElement('pre', null, JSON.stringify(errorData.request.QueryString, null, 2))
                            )
                    ),
                    errorData.callStack && errorData.callStack.length > 0 &&
                        React.createElement('div', { className: 'error-section' },
                            React.createElement('h3', null, 'Call Stack'),
                            React.createElement('ol', { className: 'call-stack' },
                                errorData.callStack.map((frame, idx) =>
                                    React.createElement('li', { key: idx },
                                        React.createElement('div', null,
                                            React.createElement('strong', null, frame.Command),
                                            ' at ',
                                            React.createElement('code', null, frame.Location)
                                        )
                                    )
                                )
                            )
                        ),
                    errorData.variables && Object.keys(errorData.variables).length > 0 &&
                        React.createElement('div', { className: 'error-section' },
                            React.createElement('h3', null, 'Variables in Scope'),
                            React.createElement('table', { className: 'variables-table' },
                                React.createElement('thead', null,
                                    React.createElement('tr', null,
                                        React.createElement('th', null, 'Variable'),
                                        React.createElement('th', null, 'Value')
                                    )
                                ),
                                React.createElement('tbody', null,
                                    Object.entries(errorData.variables).map(([key, value]) =>
                                        React.createElement('tr', { key: key },
                                            React.createElement('td', null, React.createElement('code', null, '$' + key)),
                                            React.createElement('td', null, React.createElement('code', null, String(value)))
                                        )
                                    )
                                )
                            )
                        )
                );
            } else if (errorData.modalType === 'error-basic') {
                // Basic view - show error with guidance
                return React.createElement('div', { className: 'error-modal-content error-basic' },
                    React.createElement('div', { className: 'error-section' },
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Error: '),
                            React.createElement('span', null, errorData.error.message)
                        ),
                        React.createElement('div', { className: 'error-field' },
                            React.createElement('strong', null, 'Type: '),
                            React.createElement('code', null, errorData.error.type)
                        ),
                        errorData.error.position &&
                            React.createElement('div', { className: 'error-field' },
                                React.createElement('strong', null, 'Location: '),
                                React.createElement('pre', null, errorData.error.position)
                            )
                    ),
                    errorData.guidance &&
                        React.createElement('div', { className: 'error-section guidance' },
                            React.createElement('p', null, '💡 ', errorData.guidance)
                        )
                );
            } else {
                // Minimal view - just the error message
                return React.createElement('div', { className: 'error-modal-content error-minimal' },
                    React.createElement('div', { className: 'error-section' },
                        React.createElement('p', null, errorData.error),
                        errorData.requestId &&
                            React.createElement('p', { className: 'request-id' },
                                'Request ID: ',
                                React.createElement('code', null, errorData.requestId)
                            )
                    )
                );
            }
        };

        return React.createElement('div', {
            className: 'error-modal-overlay',
            onClick: onClose
        },
            React.createElement('div', {
                className: 'error-modal',
                onClick: (e) => e.stopPropagation()
            },
                React.createElement('div', { className: 'error-modal-header' },
                    React.createElement('h2', null, errorData.modalTitle || 'Error'),
                    React.createElement('button', {
                        className: 'error-modal-close',
                        onClick: onClose,
                        'aria-label': 'Close'
                    }, '×')
                ),
                formatErrorContent(),
                React.createElement('div', { className: 'error-modal-footer' },
                    errorData.timestamp &&
                        React.createElement('span', { className: 'timestamp' },
                            'Occurred at: ', new Date(errorData.timestamp).toLocaleString()
                        ),
                    React.createElement('button', {
                        className: 'btn-primary',
                        onClick: onClose
                    }, 'Close')
                )
            )
        );
    };

    // Render the modal using React 17 API
    ReactDOM.render(
        React.createElement(ErrorModal, {
            errorData,
            onClose: () => {
                ReactDOM.unmountComponentAtNode(modalContainer);
                modalContainer.remove();
            }
        }),
        modalContainer
    );
};

// Add CSS for error modal
if (!document.getElementById('error-modal-styles')) {
    const style = document.createElement('style');
    style.id = 'error-modal-styles';
    style.textContent = `
        .error-modal-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.7);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 10000;
            animation: fadeIn 0.2s ease-in;
        }

        @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
        }

        .error-modal {
            background: white;
            border-radius: 8px;
            max-width: 900px;
            max-height: 90vh;
            width: 90%;
            display: flex;
            flex-direction: column;
            box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
            animation: slideIn 0.3s ease-out;
        }

        @keyframes slideIn {
            from { transform: translateY(-50px); opacity: 0; }
            to { transform: translateY(0); opacity: 1; }
        }

        .error-modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 20px 24px;
            border-bottom: 1px solid #e0e0e0;
            background: #f44336;
            color: white;
            border-radius: 8px 8px 0 0;
        }

        .error-modal-header h2 {
            margin: 0;
            font-size: 20px;
            font-weight: 600;
        }

        .error-modal-close {
            background: transparent;
            border: none;
            color: white;
            font-size: 32px;
            cursor: pointer;
            padding: 0;
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 4px;
            transition: background 0.2s;
        }

        .error-modal-close:hover {
            background: rgba(255, 255, 255, 0.2);
        }

        .error-modal-content {
            padding: 24px;
            overflow-y: auto;
            flex: 1;
            color: #000;
        }

        .error-section {
            margin-bottom: 24px;
        }

        .error-section h3 {
            margin: 0 0 12px 0;
            font-size: 16px;
            font-weight: 600;
            color: #000;
            border-bottom: 2px solid #f44336;
            padding-bottom: 8px;
        }

        .error-field {
            margin-bottom: 12px;
            line-height: 1.6;
            color: #000;
        }

        .error-field strong {
            color: #000;
            font-weight: 700;
        }

        .error-field code,
        .error-field pre {
            background: #f5f5f5;
            padding: 4px 8px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            color: #000;
        }

        .error-field pre {
            display: block;
            margin: 8px 0;
            padding: 12px;
            overflow-x: auto;
            border-left: 3px solid #f44336;
        }

        .call-stack {
            margin: 0;
            padding-left: 24px;
        }

        .call-stack li {
            margin-bottom: 8px;
            font-family: 'Courier New', monospace;
            font-size: 13px;
            color: #000;
        }

        .variables-table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }

        .variables-table th {
            background: #f5f5f5;
            padding: 8px 12px;
            text-align: left;
            font-weight: 600;
            border-bottom: 2px solid #ddd;
            color: #000;
        }

        .variables-table td {
            padding: 8px 12px;
            border-bottom: 1px solid #eee;
            color: #000;
        }

        .variables-table tr:hover {
            background: #fafafa;
        }

        .guidance {
            background: #e3f2fd;
            padding: 16px;
            border-radius: 4px;
            border-left: 4px solid #2196f3;
        }

        .guidance p {
            margin: 0;
            color: #0d47a1;
            font-weight: 500;
        }

        .request-id {
            color: #333;
            font-size: 12px;
            margin-top: 8px;
            font-weight: 500;
        }

        .error-modal-footer {
            padding: 16px 24px;
            border-top: 1px solid #e0e0e0;
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: #fafafa;
            border-radius: 0 0 8px 8px;
        }

        .timestamp {
            font-size: 12px;
            color: #333;
            font-weight: 500;
        }

        .btn-primary {
            background: #f44336;
            color: white;
            border: none;
            padding: 8px 24px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            font-weight: 500;
            transition: background 0.2s;
        }

        .btn-primary:hover {
            background: #d32f2f;
        }
    `;
    document.head.appendChild(style);
}

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
        window.psweb_fetchWithAuthHandling('/api/v1/auth/sessionid')
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
    const displayName = userData.Email || userData.UserID;
    const userRoles = userData.Roles || [];

    const handleRefreshToken = async (e) => {
        e.preventDefault();
        try {
            const response = await fetch('/api/v1/auth/getaccesstoken');
            if (response.ok) {
                alert('Access token refreshed successfully!');
                window.location.reload();
            } else {
                alert('Failed to refresh token');
            }
        } catch (error) {
            alert('Error refreshing token: ' + error.message);
        }
    };

    const handleLogoff = async (e) => {
        e.preventDefault();
        try {
            const response = await fetch('/api/v1/auth/logoff');
            if (response.ok) {
                window.location.reload();
            } else {
                alert('Failed to log off');
            }
        } catch (error) {
            alert('Error logging off: ' + error.message);
        }
    };

    return (
        <div className="user-card">
            <img src={userIcon} alt="User" onClick={() => setIsMenuOpen(!isMenuOpen)} style={{cursor: 'pointer', borderRadius: '50%', width: '32px', height: '32px'}} />
            {isMenuOpen && (
                <div className="floating-card">
                    <div className="floating-card-content">
                        <div style={{fontWeight: 'bold', marginBottom: '8px', borderBottom: '1px solid #ddd', paddingBottom: '8px'}}>
                            Welcome, {displayName}
                        </div>
                        {userRoles.length > 0 && (
                            <div style={{fontSize: '12px', color: '#666', marginBottom: '12px'}}>
                                <div style={{fontWeight: '500', marginBottom: '4px'}}>Roles:</div>
                                {userRoles.map((role, idx) => (
                                    <span key={idx} style={{
                                        display: 'inline-block',
                                        background: '#e3f2fd',
                                        color: '#1976d2',
                                        padding: '2px 8px',
                                        borderRadius: '12px',
                                        fontSize: '11px',
                                        marginRight: '4px',
                                        marginBottom: '4px'
                                    }}>
                                        {role}
                                    </span>
                                ))}
                            </div>
                        )}
                        <a href="#" onClick={(e) => { e.preventDefault(); window.openComponentInModal('profile'); }}>Profile</a>
                        <a href="#" onClick={handleRefreshToken}>Refresh Token &#8635;</a>
                        <a href="/settings">Settings &#9881;</a>
                        <a href="#" onClick={handleLogoff}>Logoff</a>
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
    const [isFullscreen, setIsFullscreen] = useState(false);
    const [isHighContrast, setIsHighContrast] = useState(false);
    const [isPaused, setIsPaused] = useState(false);
    const [contrastFixCount, setContrastFixCount] = useState(0);
    const contentRef = useRef(null);
    const cardRef = useRef(null);
    const pauseStateRef = useRef({ paused: false });

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
                    // Log timeout to server for diagnostics
                    window.logToServer('Warning', 'ComponentTimeout',
                        `Component ${elementId} failed to load after ${maxAttempts * 50}ms`,
                        { componentName: elementId, attempts: attempts });
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

    // Update pause state ref when isPaused changes
    useEffect(() => {
        pauseStateRef.current.paused = isPaused;
    }, [isPaused]);

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

    const handleToggleHighContrast = () => {
        const newState = !isHighContrast;
        setIsHighContrast(newState);

        if (newState && contentRef.current) {
            // Apply contrast fixes when enabling high contrast
            setTimeout(() => applyContrastFixes(contentRef.current), 100);
        }
    };

    // Helper: Convert hex/rgb to RGB values
    const parseColor = (color) => {
        if (!color || color === 'transparent') return null;

        // Handle hex colors
        if (color.startsWith('#')) {
            const hex = color.replace('#', '');
            if (hex.length === 3) {
                return {
                    r: parseInt(hex[0] + hex[0], 16),
                    g: parseInt(hex[1] + hex[1], 16),
                    b: parseInt(hex[2] + hex[2], 16)
                };
            }
            return {
                r: parseInt(hex.substr(0, 2), 16),
                g: parseInt(hex.substr(2, 2), 16),
                b: parseInt(hex.substr(4, 2), 16)
            };
        }

        // Handle rgb/rgba colors
        const match = color.match(/rgba?\((\d+),\s*(\d+),\s*(\d+)/);
        if (match) {
            return {
                r: parseInt(match[1]),
                g: parseInt(match[2]),
                b: parseInt(match[3])
            };
        }

        return null;
    };

    // Calculate relative luminance (WCAG formula)
    const getLuminance = (rgb) => {
        if (!rgb) return null;

        const rsRGB = rgb.r / 255;
        const gsRGB = rgb.g / 255;
        const bsRGB = rgb.b / 255;

        const r = rsRGB <= 0.03928 ? rsRGB / 12.92 : Math.pow((rsRGB + 0.055) / 1.055, 2.4);
        const g = gsRGB <= 0.03928 ? gsRGB / 12.92 : Math.pow((gsRGB + 0.055) / 1.055, 2.4);
        const b = bsRGB <= 0.03928 ? bsRGB / 12.92 : Math.pow((bsRGB + 0.055) / 1.055, 2.4);

        return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    };

    // Calculate contrast ratio (WCAG formula)
    const getContrastRatio = (lum1, lum2) => {
        if (lum1 === null || lum2 === null) return null;
        const lighter = Math.max(lum1, lum2);
        const darker = Math.min(lum1, lum2);
        return (lighter + 0.05) / (darker + 0.05);
    };

    // Get computed background color (traverse up DOM tree)
    const getBackgroundColor = (element) => {
        let el = element;
        while (el) {
            const bg = window.getComputedStyle(el).backgroundColor;
            const parsed = parseColor(bg);
            if (parsed && !(parsed.r === 0 && parsed.g === 0 && parsed.b === 0 && bg.includes('rgba'))) {
                return parsed;
            }
            el = el.parentElement;
        }
        // Default to card background or white
        return parseColor(backgroundColor || '#ffffff');
    };

    // Adjust color for better contrast
    const adjustColorForContrast = (fgColor, bgColor, targetRatio = 4.5) => {
        const bgLum = getLuminance(bgColor);
        if (bgLum === null) return null;

        // Determine if background is dark or light
        const isDarkBg = bgLum < 0.5;

        // For dark backgrounds, make text lighter
        // For light backgrounds, make text darker
        if (isDarkBg) {
            // Start with white and darken if needed
            return { r: 255, g: 255, b: 255 };
        } else {
            // Start with black
            return { r: 0, g: 0, b: 0 };
        }
    };

    // Apply contrast fixes to card content
    const applyContrastFixes = (container) => {
        if (!container) return;

        const elements = container.querySelectorAll('*');
        let fixCount = 0;

        elements.forEach(el => {
            const style = window.getComputedStyle(el);
            const textColor = parseColor(style.color);
            const bgColor = getBackgroundColor(el);

            if (!textColor || !bgColor) return;

            const textLum = getLuminance(textColor);
            const bgLum = getLuminance(bgColor);
            const ratio = getContrastRatio(textLum, bgLum);

            // WCAG AA standard: 4.5:1 for normal text, 3:1 for large text (18pt+)
            const fontSize = parseFloat(style.fontSize);
            const isLargeText = fontSize >= 18 || (fontSize >= 14 && style.fontWeight >= 700);
            const minRatio = isLargeText ? 3.0 : 4.5;

            if (ratio !== null && ratio < minRatio) {
                // Low contrast detected - fix it
                const adjustedColor = adjustColorForContrast(textColor, bgColor, minRatio);
                if (adjustedColor) {
                    el.style.setProperty('color', `rgb(${adjustedColor.r}, ${adjustedColor.g}, ${adjustedColor.b})`, 'important');
                    fixCount++;
                }
            }

            // Check border contrast
            const borderColor = parseColor(style.borderColor);
            if (borderColor && bgColor) {
                const borderLum = getLuminance(borderColor);
                const borderRatio = getContrastRatio(borderLum, bgLum);

                if (borderRatio !== null && borderRatio < 3.0) {
                    const adjustedBorder = adjustColorForContrast(borderColor, bgColor, 3.0);
                    if (adjustedBorder) {
                        el.style.setProperty('border-color', `rgb(${adjustedBorder.r}, ${adjustedBorder.g}, ${adjustedBorder.b})`, 'important');
                        fixCount++;
                    }
                }
            }

            // Check and fix inline style attributes
            const inlineStyle = el.getAttribute('style');
            if (inlineStyle && bgColor) {
                const colorMatch = inlineStyle.match(/color\s*:\s*([^;]+)/i);
                const bgMatch = inlineStyle.match(/background(?:-color)?\s*:\s*([^;]+)/i);

                let updatedStyle = inlineStyle;
                let inlineStyleFixed = false;

                // Check inline text color
                if (colorMatch) {
                    const inlineTextColor = parseColor(colorMatch[1].trim());
                    if (inlineTextColor) {
                        const inlineTextLum = getLuminance(inlineTextColor);
                        const inlineBgLum = bgMatch ? getLuminance(parseColor(bgMatch[1].trim())) || bgLum : bgLum;
                        const inlineRatio = getContrastRatio(inlineTextLum, inlineBgLum);

                        const minRatio = isLargeText ? 3.0 : 4.5;
                        if (inlineRatio !== null && inlineRatio < minRatio) {
                            const useBg = bgMatch ? parseColor(bgMatch[1].trim()) || bgColor : bgColor;
                            const adjustedColor = adjustColorForContrast(inlineTextColor, useBg, minRatio);
                            if (adjustedColor) {
                                const newColorValue = `rgb(${adjustedColor.r}, ${adjustedColor.g}, ${adjustedColor.b}) !important`;
                                updatedStyle = updatedStyle.replace(/color\s*:\s*[^;]+/i, `color: ${newColorValue}`);
                                inlineStyleFixed = true;
                            }
                        }
                    }
                }

                // Check inline background color contrast with parent background
                if (bgMatch) {
                    const inlineBgColor = parseColor(bgMatch[1].trim());
                    if (inlineBgColor) {
                        // Get parent background for comparison
                        const parentBg = getBackgroundColor(el.parentElement);
                        if (parentBg) {
                            const inlineBgLum = getLuminance(inlineBgColor);
                            const parentBgLum = getLuminance(parentBg);
                            const bgRatio = getContrastRatio(inlineBgLum, parentBgLum);

                            // Ensure some contrast between nested backgrounds
                            if (bgRatio !== null && bgRatio < 1.5) {
                                const adjustedBg = adjustColorForContrast(inlineBgColor, parentBg, 1.5);
                                if (adjustedBg) {
                                    const newBgValue = `rgb(${adjustedBg.r}, ${adjustedBg.g}, ${adjustedBg.b}) !important`;
                                    updatedStyle = updatedStyle.replace(/background(?:-color)?\s*:\s*[^;]+/i, `background-color: ${newBgValue}`);
                                    inlineStyleFixed = true;
                                }
                            }
                        }
                    }
                }

                // Apply updated inline style if any fixes were made
                if (inlineStyleFixed) {
                    el.setAttribute('style', updatedStyle);
                    fixCount++;
                }
            }
        });

        if (fixCount > 0) {
            console.log(`[High Contrast] Fixed ${fixCount} low-contrast elements in ${elementId}`);
            setContrastFixCount(fixCount);
        } else {
            setContrastFixCount(0);
        }
    };

    const handleTogglePause = () => {
        setIsPaused(!isPaused);
        console.log(`Card ${elementId} ${!isPaused ? 'paused' : 'resumed'}`);
    };

    const title = element.Title || 'Untitled';

    // Prepare props for component
    const componentProps = {
        element: element,
        onError: handleError,
        isPaused: isPaused,
        pauseStateRef: pauseStateRef  // Pass ref for components to check pause state
    };

    // Render component content
    let cardContent;

    // Check if there's HTML content to inject directly
    if (element.htmlContent) {
        console.log(`Injecting HTML content for ${elementId}`);
        cardContent = (
            <div
                style={{
                    width: '100%',
                    height: '100%',
                    overflow: 'auto',
                    padding: 0,
                    margin: 0
                }}
                dangerouslySetInnerHTML={{ __html: element.htmlContent }}
            />
        );
    }
    // Check if there's a load error from the endpoint
    else if (element.loadError) {
        const error = element.loadError;

        // Get theme-aware error colors
        const getErrorColors = () => {
            // Try to get background from card settings or CSS variables
            let bgColor = backgroundColor;
            if (!bgColor) {
                const rootStyles = getComputedStyle(document.documentElement);
                bgColor = rootStyles.getPropertyValue('--card-bg-color').trim() || '#2a2a2a';
            }

            // Parse and get luminance
            const bgRgb = parseColor(bgColor);
            const isDarkTheme = bgRgb ? getLuminance(bgRgb) < 0.5 : false;

            if (isDarkTheme) {
                // Dark theme: Use amber/orange tones that work on dark backgrounds
                return {
                    containerBg: 'rgba(255, 152, 0, 0.15)',  // Dark amber with transparency
                    containerBorder: '#ff9800',  // Orange
                    headingColor: '#ffb74d',  // Light amber
                    textColor: 'var(--text-color, #f0f0f0)',  // Use theme text color
                    codeBg: 'rgba(0, 0, 0, 0.3)',  // Semi-transparent black
                    codeBorder: 'rgba(255, 152, 0, 0.3)'  // Semi-transparent orange
                };
            } else {
                // Light theme: Use traditional warning colors
                return {
                    containerBg: '#fff3cd',  // Light yellow
                    containerBorder: '#ffc107',  // Amber
                    headingColor: '#856404',  // Dark brown
                    textColor: '#333',  // Dark text
                    codeBg: '#f8f9fa',  // Light gray
                    codeBorder: '#dee2e6'  // Light gray border
                };
            }
        };

        const errorColors = getErrorColors();

        cardContent = (
            <div style={{
                padding: '20px',
                fontFamily: 'monospace',
                backgroundColor: errorColors.containerBg,
                border: `2px solid ${errorColors.containerBorder}`,
                borderRadius: '4px',
                margin: '10px'
            }}>
                <h3 style={{ color: errorColors.headingColor, marginTop: 0 }}>
                    ⚠️ Failed to Load Component
                </h3>
                <div style={{ marginBottom: '10px', color: errorColors.textColor }}>
                    <strong>Status:</strong> {error.status} {error.statusText}
                </div>
                <div style={{ marginBottom: '10px', color: errorColors.textColor }}>
                    <strong>URL:</strong> <code>{error.url}</code>
                </div>
                <div style={{ marginBottom: '10px', color: errorColors.textColor }}>
                    <strong>Message:</strong>
                    <pre style={{
                        backgroundColor: errorColors.codeBg,
                        color: errorColors.textColor,
                        padding: '10px',
                        borderRadius: '4px',
                        overflow: 'auto',
                        whiteSpace: 'pre-wrap',
                        wordWrap: 'break-word',
                        border: `1px solid ${errorColors.codeBorder}`
                    }}>{error.message}</pre>
                </div>
                {error.body && error.body.trim() && (
                    <div style={{ marginTop: '15px' }}>
                        <div style={{ fontWeight: 'bold', marginBottom: '5px', color: errorColors.headingColor }}>
                            Response Body:
                        </div>
                        <pre style={{
                            backgroundColor: errorColors.codeBg,
                            color: errorColors.textColor,
                            padding: '10px',
                            borderRadius: '4px',
                            overflow: 'auto',
                            maxHeight: '400px',
                            whiteSpace: 'pre-wrap',
                            wordWrap: 'break-word',
                            fontSize: '13px',
                            border: `1px solid ${errorColors.codeBorder}`,
                            margin: 0
                        }}>{error.body}</pre>
                    </div>
                )}
            </div>
        );
    } else if (CardComponent && typeof CardComponent === 'function') {
        cardContent = React.createElement(CardComponent, componentProps);
    } else if (CardComponent) {
        cardContent = <div>Error: Invalid component type for {elementId}</div>;
    } else {
        cardContent = <p>Loading component...</p>;
    }

    // Fullscreen handling
    useEffect(() => {
        const handleFullscreenChange = () => {
            setIsFullscreen(!!document.fullscreenElement);
        };

        document.addEventListener('fullscreenchange', handleFullscreenChange);
        return () => document.removeEventListener('fullscreenchange', handleFullscreenChange);
    }, []);

    const handleFullscreen = () => {
        if (!cardRef.current) return;

        if (!document.fullscreenElement) {
            cardRef.current.requestFullscreen().catch(err => {
                console.error('Error attempting to enable fullscreen:', err);
            });
        } else {
            document.exitFullscreen();
        }
    };

    // Helper to open help for this card
    const openHelp = () => {
        const helpFile = element.helpFile || `public/help/${elementId}.md`;
        window.openCard(`/api/v1/ui/elements/help-viewer?file=${encodeURIComponent(helpFile)}`, `Help: ${helpFile}`);
    };

    // Get background color from element properties (from card settings)
    const backgroundColor = element.backgroundColor || undefined;

    // High contrast styles - detect if background is dark or light
    const highContrastStyles = isHighContrast ? (() => {
        let borderColor = '#000';
        let finalBg = backgroundColor;

        // If we have a background color, determine if it's dark or light
        if (backgroundColor) {
            const bgRgb = parseColor(backgroundColor);
            if (bgRgb) {
                const bgLum = getLuminance(bgRgb);
                // Dark background gets white border, light background gets black border
                borderColor = bgLum < 0.5 ? '#fff' : '#000';
            }
        } else {
            // No background set - check CSS variables or default
            const rootStyles = getComputedStyle(document.documentElement);
            const cardBg = rootStyles.getPropertyValue('--card-bg-color').trim() || '#2a2a2a';
            const cardRgb = parseColor(cardBg);
            if (cardRgb) {
                const cardLum = getLuminance(cardRgb);
                borderColor = cardLum < 0.5 ? '#fff' : '#000';
            }
        }

        return {
            filter: 'contrast(1.3) saturate(1.2)',
            border: `3px solid ${borderColor}`,
            backgroundColor: finalBg,
            boxShadow: `0 0 10px ${borderColor}40`
        };
    })() : {
        backgroundColor: backgroundColor
    };

    // Render simplified footer card without header/actions
    if (element.Type === 'footer') {
        return (
            <div
                className="card card-footer-type"
                style={{height: '100%', ...highContrastStyles}}
                ref={cardRef}
            >
                <main className="card-content" ref={contentRef}>
                    {cardContent}
                </main>
            </div>
        );
    }

    return (
        <div
            className={`card ${isMaximized ? 'maximized' : ''} ${isFullscreen ? 'fullscreen' : ''} ${isHighContrast ? 'high-contrast' : ''}`}
            style={{height: '100%', ...highContrastStyles}}
            ref={cardRef}
        >
            <header className="card-header">
                {element.icon && <img src={element.icon} className="card-icon" alt="icon" />}
                <h3 className="card-title">{title}</h3>
                {isPaused && (
                    <span style={{
                        marginLeft: '10px',
                        padding: '2px 8px',
                        backgroundColor: '#ffc107',
                        color: '#000',
                        fontSize: '11px',
                        borderRadius: '3px',
                        fontWeight: 'bold'
                    }}>PAUSED</span>
                )}
                <div className="card-actions">
                    <button
                        className="card-action pause-icon"
                        onClick={handleTogglePause}
                        title={isPaused ? 'Resume Updates' : 'Pause Updates'}
                        aria-label={isPaused ? 'Resume Updates' : 'Pause Updates'}
                        style={{ color: isPaused ? '#ffc107' : 'inherit' }}
                    >
                        {isPaused ? '▶' : '⏸'}
                    </button>
                    <button
                        className="card-action contrast-icon"
                        onClick={handleToggleHighContrast}
                        title={isHighContrast
                            ? (contrastFixCount > 0
                                ? `Normal Contrast (Fixed ${contrastFixCount} elements)`
                                : 'Normal Contrast')
                            : 'High Contrast - Auto-fix low contrast elements'}
                        aria-label={isHighContrast ? 'Normal Contrast' : 'High Contrast'}
                        style={{
                            color: isHighContrast ? '#000' : 'inherit',
                            backgroundColor: isHighContrast ? '#ffeb3b' : 'transparent',
                            fontWeight: isHighContrast ? 'bold' : 'normal',
                            position: 'relative'
                        }}
                    >
                        ◐
                        {isHighContrast && contrastFixCount > 0 && (
                            <span style={{
                                position: 'absolute',
                                top: '-2px',
                                right: '-2px',
                                backgroundColor: '#f44336',
                                color: '#fff',
                                borderRadius: '50%',
                                width: '14px',
                                height: '14px',
                                fontSize: '9px',
                                display: 'flex',
                                alignItems: 'center',
                                justifyContent: 'center',
                                fontWeight: 'bold',
                                lineHeight: '1'
                            }}>
                                {contrastFixCount > 9 ? '9+' : contrastFixCount}
                            </span>
                        )}
                    </button>
                    <button className="card-action help-icon" onClick={openHelp} title="Open Help" aria-label="Open Help">&#10067;</button>
                    <button className="card-action fullscreen-icon" onClick={handleFullscreen} title={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'} aria-label={isFullscreen ? 'Exit Fullscreen' : 'Fullscreen'}>
                        {isFullscreen ? '⛶' : '⛶'}
                    </button>
                    <button className="card-action maximize-icon" onClick={() => onMaximize(element.id)} title={isMaximized ? 'Restore' : 'Maximize'} aria-label={isMaximized ? 'Restore' : 'Maximize'}>
                        {isMaximized ? '🗗' : '🗖'}
                    </button>
                    <button className="card-action settings-icon" onClick={() => onOpenSettings(element.id)} title="Settings" aria-label="Settings">&#9881;</button>
                    <button className="card-action close-icon" onClick={() => onRemove(element.id)} title="Close" aria-label="Close">&times;</button>
                </div>
            </header>
            <main className="card-content" ref={contentRef}>
                {cardContent}
            </main>
            {errorInfo && (
                <footer className="card-footer">
                    {errorInfo.status && <span>{errorInfo.status}: {errorInfo.statusText}</span>}
                    <p>{errorInfo.message}</p>
                </footer>
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
        const { name, value, type } = e.target;
        // For color input, use string value directly. For numbers, parse as int
        const parsedValue = type === 'color' || name === 'backgroundColor' ? value : parseInt(value, 10);
        setLayout({ ...layout, [name]: parsedValue });
    };

    const handleClearColor = () => {
        setLayout({ ...layout, backgroundColor: undefined });
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
                <div style={{ marginBottom: '10px' }}>
                    <label>Background Color Override</label><br/>
                    <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                        <input
                            type="color"
                            name="backgroundColor"
                            value={layout.backgroundColor || '#ffffff'}
                            onChange={handleChange}
                            style={{ width: '60px', height: '32px' }}
                        />
                        <button onClick={handleClearColor} style={{ padding: '4px 8px' }}>
                            Clear (Use Default)
                        </button>
                        {layout.backgroundColor && (
                            <span style={{ fontSize: '0.85em', opacity: 0.7 }}>
                                {layout.backgroundColor}
                            </span>
                        )}
                    </div>
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
            for (let j = 0; j <= cols - w; j++) { // Changed < to <= to handle full-width cards
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

        // If no free spot found, place at bottom
        const maxY = layout.reduce((max, item) => Math.max(max, item.y + item.h), 0);
        return { x: 0, y: maxY };
    }

    const loadLayout = () => {
        fetch('/public/layout.json')
            .then(response => response.json())
            .then(async initialData => {
                const allCardIds = Object.values(initialData.layout).flatMap(pane => Object.values(pane)).flat();
                const uniqueCardIds = [...new Set(allCardIds)];
                const defaultLayout = initialData.gridLayout.find(item => item.i === 'default') || { w: 12, h: 14 };

                const componentPromises = uniqueCardIds
                    .filter(id => id && id !== 'user-card' && id !== 'title')
                    .map(id => {
                        // Get explicit component path from layout.json
                        const element = initialData.elements[id];
                        const componentPath = element?.componentPath;

                        if (!componentPath) {
                            console.error(`❌ No componentPath specified for element: ${id}`);
                            console.error(`   Element definition:`, element);
                            console.error(`   Component paths must be explicitly defined in layout.json`);
                            console.error(`   Example: "componentPath": "/public/elements/${id}/component.js"`);
                            return Promise.resolve(); // Skip this component
                        }

                        console.log(`Loading component for ${id} from: ${componentPath}`);
                        return fetch(componentPath)
                            .then(res => {
                                if (!res.ok) {
                                    throw new Error(`HTTP ${res.status}: ${res.statusText} for ${componentPath}`);
                                }
                                return res.text();
                            })
                            .then(text => {
                                if (text) {
                                    const transformed = Babel.transform(text, { presets: ['react'] }).code;
                                    (new Function(transformed))();
                                }
                            })
                            .catch(err => {
                                console.error(`❌ Failed to load component for ${id}:`, err);
                                console.error(`   Path attempted: ${componentPath}`);
                            });
                    });

                const profilePromise = fetch('/public/elements/profile/component.js').then(res => res.text()).then(text => {
                    if(text) (new Function(Babel.transform(text, { presets: ['react'] }).code))();
                });

                Promise.all([...componentPromises, profilePromise])
                    .then(async () => {
                        // Fetch card settings for each card in mainPane
                        const mainPaneLayoutPromises = initialData.layout.mainPane.content.map(async (id, index) => {
                            const specificLayout = initialData.gridLayout.find(item => item.i === id);

                            // Get element to determine endpoint_guid
                            const element = initialData.elements[id];
                            const endpointGuid = element?.url || id;

                            // Fetch card settings from database
                            const cardSettings = await fetchCardSettings(endpointGuid);

                            // Apply backgroundColor from settings to element
                            if (cardSettings?.backgroundColor) {
                                initialData.elements[id] = {
                                    ...initialData.elements[id],
                                    backgroundColor: cardSettings.backgroundColor
                                };
                            }

                            // Priority: cardSettings (DB) > specificLayout (layout.json) > defaultLayout
                            // This ensures user preferences and DB defaults take precedence over static config
                            return {
                                i: id,
                                x: specificLayout?.x ?? (index % 4) * 3,
                                y: specificLayout?.y ?? Math.floor(index / 4) * 2,
                                w: cardSettings?.w ?? specificLayout?.w ?? defaultLayout.w,
                                h: cardSettings?.h ?? specificLayout?.h ?? defaultLayout.h
                            };
                        });

                        const mainPaneLayout = await Promise.all(mainPaneLayoutPromises);
                        setGridLayout(mainPaneLayout);

                        // Update data with backgroundColor applied to elements
                        setData({ ...initialData, componentsReady: true });
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

    // Helper function to fetch card settings from database with caching
    const fetchCardSettings = async (endpointGuid, skipCache = false) => {
        const cacheKey = `card_settings_${endpointGuid}`;

        // Check if cache was recently invalidated (within 30 minutes to match max cache duration)
        const forceBypassCache = CacheManager.wasRecentlyInvalidated(cacheKey, 1800000); // 30 minutes in ms
        if (forceBypassCache) {
            console.log(`Cache was recently invalidated for ${endpointGuid}, bypassing browser cache`);
            skipCache = true;
        }

        // Check cache first (unless explicitly skipped)
        if (!skipCache) {
            const cached = CacheManager.get(cacheKey);
            if (cached) {
                if (cached.isFresh) {
                    // Fresh cache hit - return immediately
                    console.log(`Cache hit (fresh) for ${endpointGuid}`);
                    return cached.data;
                } else if (cached.isStale) {
                    // Stale cache - return stale data but revalidate in background
                    console.log(`Cache hit (stale) for ${endpointGuid}, revalidating...`);
                    // Start background revalidation (don't await)
                    fetchCardSettings(endpointGuid, true).then(fresh => {
                        // Background update completed
                        console.log(`Background revalidation complete for ${endpointGuid}`);
                    }).catch(() => {
                        // Background update failed - keep using stale
                        console.log(`Background revalidation failed for ${endpointGuid}, using stale data`);
                    });
                    return cached.data;
                }
            }
        }

        // Cache miss or forced fetch - get from server
        try {
            // Add cache-busting parameter if we're bypassing cache
            const url = forceBypassCache
                ? `/spa/card_settings?id=${encodeURIComponent(endpointGuid)}&_=${Date.now()}`
                : `/spa/card_settings?id=${encodeURIComponent(endpointGuid)}`;

            const fetchOptions = forceBypassCache
                ? { headers: { 'Cache-Control': 'no-cache', 'Pragma': 'no-cache' } }
                : {};

            const response = await window.psweb_fetchWithAuthHandling(url, fetchOptions);

            if (response.ok) {
                const settings = await response.json();
                if (settings && settings.data) {
                    const parsedData = JSON.parse(settings.data);

                    // Parse Cache-Control header to determine max-age
                    const cacheControl = response.headers.get('Cache-Control');
                    let maxAge = 1800; // Default 30 minutes
                    if (cacheControl) {
                        const maxAgeMatch = cacheControl.match(/max-age=(\d+)/);
                        if (maxAgeMatch) {
                            maxAge = parseInt(maxAgeMatch[1], 10);
                        }
                    }

                    // Store in cache
                    CacheManager.set(cacheKey, parsedData, maxAge);
                    console.log(`Cached card settings for ${endpointGuid} (max-age: ${maxAge}s)`);

                    return parsedData;
                }
            } else {
                console.warn(`Failed to fetch card settings for ${endpointGuid} (status ${response.status}), using defaults`);
            }
        } catch (err) {
            console.warn(`Error fetching card settings for ${endpointGuid}:`, err);

            // On error, try to use stale cache if available
            const cached = CacheManager.get(cacheKey);
            if (cached) {
                console.log(`Using stale cache due to error for ${endpointGuid}`);
                return cached.data;
            }
        }

        // Fallback to default settings if all else fails
        return { w: 12, h: 14 };
    };

    // Helper function to load component script dynamically
    const loadComponentScript = async (elementId, explicitPath = null, endpointUrl = null) => {
        return new Promise(async (resolve, reject) => {
            // Check if component is already loaded
            if (window.cardComponents[elementId]) {
                resolve({ success: true });
                return;
            }

            console.log(`Loading component script for ${elementId}...`);

            let componentPath = explicitPath;
            let errorInfo = null;
            let contentType = null;
            let htmlContent = null;
            let htmlTitle = null;

            // If no explicit path provided, try to fetch from UI element endpoint
            if (!componentPath) {
                try {
                    // Use provided endpoint URL or construct standard endpoint
                    if (!endpointUrl) {
                        endpointUrl = `/api/v1/ui/elements/${elementId}`;
                    }

                    console.log(`Fetching component metadata from: ${endpointUrl}`);
                    const metadataRes = await fetch(endpointUrl);

                    if (metadataRes.ok) {
                        // Get Content-Type header
                        contentType = metadataRes.headers.get('Content-Type') || 'application/json';
                        console.log(`✓ Endpoint returned Content-Type: ${contentType}`);

                        // Handle HTML responses directly
                        if (contentType.includes('text/html')) {
                            htmlContent = await metadataRes.text();

                            // Extract title from HTML
                            const titleMatch = htmlContent.match(/<title[^>]*>(.*?)<\/title>/i);
                            htmlTitle = titleMatch ? titleMatch[1] : null;

                            console.log(`✓ HTML content loaded, title: ${htmlTitle || 'none'}`);

                            // Log content type observation to server
                            window.logToServer('Info', 'ContentType',
                                `Endpoint ${endpointUrl} returned HTML`,
                                { elementId: elementId, contentType: contentType, hasTitle: !!htmlTitle }
                            );

                            resolve({
                                success: true,
                                type: 'html',
                                contentType: contentType,
                                htmlContent: htmlContent,
                                htmlTitle: htmlTitle
                            });
                            return;
                        }

                        // Handle JSON metadata (standard component pattern)
                        const metadata = await metadataRes.json();

                        // Store metadata title if provided
                        if (metadata.title) {
                            htmlTitle = metadata.title;
                        }

                        if (metadata.scriptPath) {
                            componentPath = metadata.scriptPath;
                            console.log(`✓ Using scriptPath from endpoint: ${componentPath}`);

                            // Log content type observation to server
                            window.logToServer('Info', 'ContentType',
                                `Endpoint ${endpointUrl} returned JSON with scriptPath`,
                                { elementId: elementId, contentType: contentType, scriptPath: componentPath }
                            );
                        }
                    } else {
                        // Capture HTTP error details
                        let errorBody = '';
                        try {
                            errorBody = await metadataRes.text();
                        } catch (e) {
                            // Ignore errors reading response body
                        }

                        errorInfo = {
                            status: metadataRes.status,
                            statusText: metadataRes.statusText,
                            message: `HTTP ${metadataRes.status}: ${metadataRes.statusText}`,
                            body: errorBody,
                            url: endpointUrl
                        };

                        console.error(`❌ Endpoint ${endpointUrl} returned status ${metadataRes.status}:`, errorBody);
                        window.logToServer('Error', 'ComponentLoad',
                            `Endpoint ${endpointUrl} returned ${metadataRes.status}`,
                            { elementId: elementId, status: metadataRes.status, statusText: metadataRes.statusText, body: errorBody }
                        );

                        // Resolve with error info so card can display it
                        resolve({ success: false, error: errorInfo });
                        return;
                    }
                } catch (err) {
                    errorInfo = {
                        status: 0,
                        statusText: 'Network Error',
                        message: err.message || 'Failed to fetch component metadata',
                        url: endpointUrl
                    };

                    console.error(`❌ Network error fetching metadata for ${elementId}:`, err);
                    window.logToServer('Error', 'ComponentLoad',
                        `Network error fetching ${endpointUrl}: ${err.message}`,
                        { elementId: elementId, error: err.toString() }
                    );

                    // Resolve with error info
                    resolve({ success: false, error: errorInfo });
                    return;
                }
            }

            // Require explicit path (but allow direct .html or .js URLs from endpointUrl)
            if (!componentPath) {
                // Check if endpointUrl is a direct .html or .js file
                if (endpointUrl && (endpointUrl.endsWith('.html') || endpointUrl.endsWith('.js'))) {
                    componentPath = endpointUrl;
                    console.log(`✓ Using direct file URL: ${componentPath}`);
                } else {
                    const errorMsg = `No component path found for ${elementId}. Component paths must be explicitly specified via:
  1. componentPath in layout.json, OR
  2. scriptPath in /api/v1/ui/elements/${elementId} endpoint response, OR
  3. Direct URL to .js or .html file`;
                    console.error(`❌ ${errorMsg}`);
                    window.logToServer('Error', 'ComponentLoad', errorMsg, { elementId: elementId });

                    // Return error info
                    resolve({
                        success: false,
                        error: {
                            status: 404,
                            statusText: 'Not Found',
                            message: errorMsg,
                            url: endpointUrl
                        }
                    });
                    return;
                }
            }

            // Determine if this is an HTML file based on extension
            const isHtmlFile = componentPath.endsWith('.html');

            // Fetch and transform component
            fetch(componentPath)
                .then(res => {
                    if (!res.ok) {
                        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
                    }

                    // Capture Content-Type from script/html file response
                    const fileContentType = res.headers.get('Content-Type') || '';

                    // Handle HTML files
                    if (isHtmlFile || fileContentType.includes('text/html')) {
                        return res.text().then(htmlText => {
                            // Extract title from HTML
                            const titleMatch = htmlText.match(/<title[^>]*>(.*?)<\/title>/i);
                            const extractedTitle = titleMatch ? titleMatch[1] : null;

                            console.log(`✓ HTML file loaded: ${componentPath}, title: ${extractedTitle || 'none'}`);

                            // Log content type observation
                            window.logToServer('Info', 'ContentType',
                                `Direct HTML file loaded: ${componentPath}`,
                                { elementId: elementId, contentType: fileContentType, hasTitle: !!extractedTitle }
                            );

                            resolve({
                                success: true,
                                type: 'html',
                                contentType: fileContentType || 'text/html',
                                htmlContent: htmlText,
                                htmlTitle: extractedTitle || htmlTitle
                            });
                        });
                    }

                    return res.text();
                })
                .then(text => {
                    // Skip if we already resolved with HTML content
                    if (!text || typeof text !== 'string') return;

                    console.log(`Transforming ${elementId} with Babel from ${componentPath}...`);
                    const transformed = Babel.transform(text, { presets: ['react'] }).code;
                    (new Function(transformed))();

                    if (window.cardComponents[elementId]) {
                        console.log(`✓ Component ${elementId} loaded and registered`);
                    } else {
                        console.warn(`⚠ Component ${elementId} loaded but not registered in window.cardComponents`);
                        window.logToServer('Warning', 'ComponentLoad', `Component ${elementId} loaded but not registered`, { elementId: elementId, componentPath: componentPath });
                    }

                    // Log content type observation for JS files
                    window.logToServer('Info', 'ContentType',
                        `JavaScript component loaded: ${componentPath}`,
                        { elementId: elementId, contentType: 'application/javascript' }
                    );

                    resolve({ success: true, type: 'component', contentType: 'application/javascript' });
                })
                .catch(err => {
                    console.error(`❌ Failed to load ${elementId} component from ${componentPath}:`, err);
                    window.logToServer('Error', 'ComponentLoad', `Failed to load ${elementId} from ${componentPath}: ${err.message}`, { elementId: elementId, componentPath: componentPath, error: err.toString() });

                    // Return error info
                    resolve({
                        success: false,
                        error: {
                            status: 500,
                            statusText: 'Script Load Error',
                            message: `Failed to load component script: ${err.message}`,
                            url: componentPath
                        }
                    });
                });
        });
    };

    window.openCard = async (url, title) => {
        // Extract element ID from URL if it's an API endpoint
        // e.g., /api/v1/ui/elements/system-log -> system-log
        // e.g., /api/v1/ui/elements/admin/users-management -> admin/users-management
        let elementId = 'iframe-card';
        let elementUrl = url;

        const elementMatch = url.match(/\/api\/v1\/ui\/elements\/(.+?)(?:[?]|$)/);
        if (elementMatch) {
            elementId = elementMatch[1];
            elementUrl = url; // Keep the full URL for fetching
        }

        // Load the component script if needed
        let loadResult = { success: true };
        if (elementId !== 'iframe-card') {
            loadResult = await loadComponentScript(elementId, null, elementUrl);
        }

        // Create the card
        const cardId = elementId + '-' + Date.now();

        // Fetch card settings from database first to get backgroundColor
        const endpointGuid = elementUrl || elementId;
        const cardSettings = await fetchCardSettings(endpointGuid);

        console.log('[openCard] Fetched card settings:', { endpointGuid, cardSettings });

        // Determine final title based on content type and available metadata
        let finalTitle = title;
        if (loadResult.success && loadResult.type === 'html') {
            // For HTML content, use format: "HTML - [title]"
            const htmlTitlePart = loadResult.htmlTitle || title || elementUrl.split('/').pop() || 'Content';
            finalTitle = `HTML - ${htmlTitlePart}`;
        }

        const newElement = {
            Title: finalTitle,
            Element_Id: elementId,
            url: elementUrl,
            id: cardId,
            backgroundColor: cardSettings?.backgroundColor,
            // Include error information if component loading failed
            loadError: loadResult.success ? null : loadResult.error,
            // Include HTML content if returned
            htmlContent: loadResult.htmlContent || null,
            htmlTitle: loadResult.htmlTitle || null,
            contentType: loadResult.contentType || null,
            loadType: loadResult.type || 'component'
        };

        // Add the card to data first
        setData(prevData => {
            const newElements = { ...prevData.elements, [cardId]: newElement };
            const newLayout = JSON.parse(JSON.stringify(prevData.layout));
            newLayout.mainPane.content.push(cardId);
            return { ...prevData, elements: newElements, layout: newLayout };
        });

        // Add card with temporary small size first to allow it to render
        const tempPosition = findNextFreePosition(gridLayout, { w: 2, h: 2 });
        const tempLayoutItem = { w: 2, h: 2, i: cardId, ...tempPosition };

        console.log('[openCard] Adding temporary layout item:', tempLayoutItem);

        setGridLayout(prevGridLayout => [...prevGridLayout, tempLayoutItem]);

        // Wait for the card to render, then apply the actual saved settings
        setTimeout(() => {
            console.log('[openCard] Applying saved card settings:', cardSettings);
            const position = findNextFreePosition(gridLayout, cardSettings);

            console.log('[openCard] Final position found:', position);

            setGridLayout(prevGridLayout => {
                const updatedLayout = prevGridLayout.map(item =>
                    item.i === cardId
                        ? { ...cardSettings, i: cardId, x: position.x, y: position.y }
                        : item
                );
                console.log('[openCard] Updated gridLayout with saved settings:', updatedLayout);
                return updatedLayout;
            });
        }, 100);
    };
    
    const openSettingsModal = (cardId) => {
        setSettingsModal({ isOpen: true, cardId: cardId });
    };

    const closeSettingsModal = () => {
        setSettingsModal({ isOpen: false, cardId: null });
    };

    const handleSaveCardSettings = async (newCardLayout) => {
        const newGridLayout = gridLayout.map(item => item.i === newCardLayout.i ? newCardLayout : item);
        setGridLayout(newGridLayout);

        // Update element with backgroundColor
        if (newCardLayout.backgroundColor !== undefined) {
            setData(prevData => {
                const updatedElements = { ...prevData.elements };
                if (updatedElements[newCardLayout.i]) {
                    updatedElements[newCardLayout.i] = {
                        ...updatedElements[newCardLayout.i],
                        backgroundColor: newCardLayout.backgroundColor
                    };
                }
                return { ...prevData, elements: updatedElements };
            });
        }

        // Save to backend
        try {
            // Extract the element from the card ID
            const element = data.elements[newCardLayout.i];
            if (element) {
                const endpointGuid = element.url || element.Element_Id;

                // Prepare layout data (w, h, x, y, backgroundColor)
                const layoutData = {
                    w: newCardLayout.w,
                    h: newCardLayout.h,
                    x: newCardLayout.x,
                    y: newCardLayout.y
                };

                // Only include backgroundColor if it's defined
                if (newCardLayout.backgroundColor !== undefined) {
                    layoutData.backgroundColor = newCardLayout.backgroundColor;
                }

                const response = await window.psweb_fetchWithAuthHandling('/spa/card_settings', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        id: endpointGuid,
                        layout: layoutData
                    })
                });

                if (response.ok) {
                    // Invalidate cache for this card so fresh data is fetched next time
                    CacheManager.invalidate(`card_settings_${endpointGuid}`);
                    console.log('Card settings saved and cache invalidated');
                } else {
                    console.error('Failed to save card settings');
                    window.logToServer('Error', 'CardSettings', 'Failed to save card settings', {
                        cardId: newCardLayout.i,
                        status: response.status
                    });
                }
            }
        } catch (err) {
            console.error('Error saving card settings:', err);
            window.logToServer('Error', 'CardSettings', 'Error saving card settings', {
                cardId: newCardLayout.i,
                error: err.toString()
            });
        }
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
        console.log('[handleLayoutChange] Called with', layout.length, 'items');
        // Log the last few items to see what's happening
        if (layout.length > 0) {
            const lastItem = layout[layout.length - 1];
            console.log('[handleLayoutChange] Last item in layout:', lastItem);
        }
        setGridLayout(layout);
    };

    const handleResize = (layout, oldItem, newItem, placeholder, e, element) => {
        console.log('handleResize (during resize):', {
            cardId: newItem.i,
            oldSize: { w: oldItem.w, h: oldItem.h },
            newSize: { w: newItem.w, h: newItem.h },
            position: { x: newItem.x, y: newItem.y }
        });
    };

    const handleResizeStart = (layout, oldItem, newItem, placeholder, e, element) => {
        console.log('handleResizeStart:', {
            cardId: oldItem.i,
            startSize: { w: oldItem.w, h: oldItem.h },
            startPosition: { x: oldItem.x, y: oldItem.y }
        });
    };

    const handleDragOrResizeStop = async (layout, oldItem, newItem, placeholder, e, element) => {
        // Save the updated layout for the card that was moved/resized
        if (!newItem) {
            console.warn('handleDragOrResizeStop: newItem is undefined');
            return;
        }

        if (!data.elements[newItem.i]) {
            console.warn(`handleDragOrResizeStop: No element found for card ID: ${newItem.i}`);
            return;
        }

        const cardElement = data.elements[newItem.i];
        const endpointGuid = cardElement.url || cardElement.Element_Id;

        if (!endpointGuid) {
            console.error('handleDragOrResizeStop: Could not determine endpoint_guid', { cardElement });
            return;
        }

        const layoutData = {
            w: newItem.w,
            h: newItem.h,
            x: newItem.x,
            y: newItem.y
        };

        console.log(`Saving card settings for ${endpointGuid}:`, layoutData);

        try {
            const response = await window.psweb_fetchWithAuthHandling('/spa/card_settings', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    id: endpointGuid,
                    layout: layoutData
                })
            });

            if (response.ok) {
                // Invalidate cache for this card
                CacheManager.invalidate(`card_settings_${endpointGuid}`);
                console.log('✓ Card settings saved after drag/resize, cache invalidated');
            } else {
                const errorText = await response.text();
                console.error('Failed to save card settings after drag/resize:', {
                    status: response.status,
                    statusText: response.statusText,
                    error: errorText
                });
            }
        } catch (err) {
            console.error('Error saving card settings after drag/resize:', err);
            console.error('Stack trace:', err.stack);
        }
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
                        draggableHandle=".card-header"
                        onLayoutChange={handleLayoutChange}
                        onResizeStart={handleResizeStart}
                        onResize={handleResize}
                        onResizeStop={handleDragOrResizeStop}
                        onDragStop={handleDragOrResizeStop}
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