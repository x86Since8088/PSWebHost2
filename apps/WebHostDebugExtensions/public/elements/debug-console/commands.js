// Predefined Debug Command Library
window.DebugCommandLibrary = {
    /**
     * Dump current application state
     */
    dumpState: () => {
        return {
            cards: window.findAllCards ? window.findAllCards() : 'Not available',
            appData: window.appData || 'Not available',
            location: window.location.href,
            storage: {
                localStorageKeys: Object.keys(localStorage),
                sessionStorageKeys: Object.keys(sessionStorage),
                localStorageSize: JSON.stringify(localStorage).length
            },
            performance: {
                memory: performance.memory ? {
                    usedJSHeapSize: Math.round(performance.memory.usedJSHeapSize / 1024 / 1024) + ' MB',
                    totalJSHeapSize: Math.round(performance.memory.totalJSHeapSize / 1024 / 1024) + ' MB',
                    limit: Math.round(performance.memory.jsHeapSizeLimit / 1024 / 1024) + ' MB'
                } : 'Not available'
            }
        };
    },

    /**
     * Query React Fiber tree to find components
     * @param {object} params - { componentName, cardId }
     */
    queryReactTree: (params) => {
        const results = {
            found: [],
            totalComponents: 0,
            cardComponents: [],
            timestamp: new Date().toISOString()
        };

        // Helper to traverse React Fiber tree
        function traverseFiber(fiber, depth = 0) {
            if (!fiber || depth > 50) return;

            results.totalComponents++;

            // Get component info
            const componentName = fiber.type?.name || fiber.type?.displayName || fiber.elementType?.name || typeof fiber.type;
            const key = fiber.key;
            const props = fiber.memoizedProps;

            // Check if this matches what we're looking for
            if (params.componentName && componentName.toLowerCase().includes(params.componentName.toLowerCase())) {
                results.found.push({
                    componentName,
                    key,
                    props: props ? Object.keys(props) : [],
                    hasChildren: !!fiber.child,
                    depth
                });
            }

            // Check if this is a card component
            if (props?.id && props.id.includes('-')) {
                results.cardComponents.push({
                    componentName,
                    id: props.id,
                    cardId: props.cardId || props.id,
                    elementId: props.elementId,
                    url: props.url,
                    title: props.title,
                    depth
                });
            }

            // Traverse children
            traverseFiber(fiber.child, depth + 1);
            traverseFiber(fiber.sibling, depth);
        }

        // Find the React root
        const rootElement = document.getElementById('root');
        if (rootElement) {
            // Try to get React Fiber from the root element
            const fiberKey = Object.keys(rootElement).find(key =>
                key.startsWith('__reactInternalInstance') ||
                key.startsWith('__reactFiber') ||
                key.startsWith('_reactRootContainer')
            );

            if (fiberKey) {
                const fiber = rootElement[fiberKey];
                traverseFiber(fiber?.child || fiber);
            } else {
                // Try alternate method - React 18+
                const reactRoot = rootElement._reactRootContainer?._internalRoot?.current ||
                                 rootElement._reactRootContainer?.current;
                if (reactRoot) {
                    traverseFiber(reactRoot.child);
                }
            }
        }

        return results;
    },

    /**
     * Clear local storage
     */
    clearStorage: () => {
        const count = localStorage.length;
        localStorage.clear();
        return `Cleared ${count} items from localStorage`;
    },

    /**
     * Reload a specific card
     */
    reloadCard: (params) => {
        if (!params.cardId) {
            throw new Error('Missing parameter: cardId');
        }
        if (window.reloadCard) {
            window.reloadCard(params.cardId);
            return `Reloaded card: ${params.cardId}`;
        } else {
            throw new Error('reloadCard function not available');
        }
    },

    /**
     * Get all loaded React components and globals
     */
    listComponents: () => {
        const components = [];
        for (const key in window) {
            if (key.endsWith('Card') || key.endsWith('Component') || key.includes('Debug')) {
                components.push(key);
            }
        }
        return components.sort();
    },

    /**
     * Measure page performance
     */
    measurePerformance: () => {
        const perf = performance.getEntriesByType('navigation')[0];
        if (!perf) return 'Navigation timing not available';

        return {
            domContentLoaded: Math.round(perf.domContentLoadedEventEnd - perf.domContentLoadedEventStart) + 'ms',
            loadComplete: Math.round(perf.loadEventEnd - perf.loadEventStart) + 'ms',
            domInteractive: Math.round(perf.domInteractive) + 'ms',
            resourceCount: performance.getEntriesByType('resource').length,
            totalTransferSize: Math.round(performance.getEntriesByType('resource')
                .reduce((sum, r) => sum + (r.transferSize || 0), 0) / 1024) + ' KB'
        };
    },

    /**
     * Test console logging
     */
    testConsole: () => {
        console.log('[DEBUG] Test log message');
        console.warn('[DEBUG] Test warning message');
        console.error('[DEBUG] Test error message');
        return 'Console test messages logged (check browser console)';
    },

    /**
     * Get browser info
     */
    browserInfo: () => {
        return {
            userAgent: navigator.userAgent,
            language: navigator.language,
            languages: navigator.languages,
            platform: navigator.platform,
            cookieEnabled: navigator.cookieEnabled,
            onLine: navigator.onLine,
            hardwareConcurrency: navigator.hardwareConcurrency,
            deviceMemory: navigator.deviceMemory || 'Not available',
            viewport: {
                width: window.innerWidth,
                height: window.innerHeight
            },
            screen: {
                width: screen.width,
                height: screen.height,
                colorDepth: screen.colorDepth
            }
        };
    },

    /**
     * List all cards currently in layout
     */
    listCards: () => {
        if (!window.appData || !window.appData.elements) {
            return 'appData.elements not available';
        }
        return Object.keys(window.appData.elements).map(cardId => ({
            cardId,
            elementId: window.appData.elements[cardId].Element_Id,
            url: window.appData.elements[cardId].url
        }));
    },

    /**
     * Get session data
     */
    getSession: () => {
        return window.sessionData || 'Session data not available';
    },

    // ========================================
    // Card Lifecycle Commands
    // ========================================

    /**
     * Launch a card by URL
     * @param {object} params - { url, title }
     */
    openCard: async (params) => {
        if (!params.url) {
            throw new Error('Missing parameter: url');
        }
        if (!window.openCard) {
            throw new Error('window.openCard function not available');
        }

        const title = params.title || 'Debug Card';
        try {
            const result = await window.openCard(params.url, title);

            // Extract card ID and element ID from the result
            // window.openCard typically adds the card to appData.elements
            const cards = window.appData?.elements || {};
            const cardIds = Object.keys(cards);
            const latestCardId = cardIds[cardIds.length - 1];

            return {
                success: true,
                cardId: latestCardId,
                elementId: cards[latestCardId]?.Element_Id,
                url: params.url,
                title: title,
                timestamp: new Date().toISOString()
            };
        } catch (error) {
            throw new Error(`Failed to open card: ${error.message}`);
        }
    },

    /**
     * Close cards by various criteria
     * @param {object} params - { cardId?, elementId?, all? }
     */
    closeCard: (params) => {
        if (!window.removeCard) {
            throw new Error('window.removeCard function not available');
        }

        const cards = window.appData?.elements || {};
        const closedCards = [];

        if (params.all) {
            // Close all cards
            for (const cardId in cards) {
                try {
                    window.removeCard(cardId);
                    closedCards.push(cardId);
                } catch (error) {
                    console.error(`Failed to close card ${cardId}:`, error);
                }
            }
            return {
                success: true,
                closedCards,
                count: closedCards.length,
                message: `Closed ${closedCards.length} cards`
            };
        } else if (params.cardId) {
            // Close specific card by ID
            try {
                window.removeCard(params.cardId);
                return {
                    success: true,
                    closedCards: [params.cardId],
                    count: 1,
                    message: `Closed card: ${params.cardId}`
                };
            } catch (error) {
                throw new Error(`Failed to close card ${params.cardId}: ${error.message}`);
            }
        } else if (params.elementId) {
            // Close all cards of a specific element type
            for (const cardId in cards) {
                if (cards[cardId].Element_Id === params.elementId) {
                    try {
                        window.removeCard(cardId);
                        closedCards.push(cardId);
                    } catch (error) {
                        console.error(`Failed to close card ${cardId}:`, error);
                    }
                }
            }
            return {
                success: true,
                closedCards,
                count: closedCards.length,
                message: `Closed ${closedCards.length} cards of type: ${params.elementId}`
            };
        } else {
            throw new Error('Must specify cardId, elementId, or all');
        }
    },

    /**
     * Validate card state and existence
     * @param {object} params - { cardId }
     */
    validateCard: (params) => {
        if (!params.cardId) {
            throw new Error('Missing parameter: cardId');
        }

        const cards = window.appData?.elements || {};
        const cardExists = params.cardId in cards;

        if (!cardExists) {
            return {
                exists: false,
                cardId: params.cardId,
                message: 'Card not found in appData'
            };
        }

        const cardData = cards[params.cardId];
        const elementId = cardData.Element_Id;

        // Try multiple methods to find the card element
        let cardElement = document.getElementById(params.cardId);
        let gridItem = null;

        // If not found by ID, search through grid items by title
        if (!cardElement && cardData.title) {
            const gridItems = document.querySelectorAll('.react-grid-item');
            for (const item of gridItems) {
                const cardDiv = item.querySelector('.card');
                const cardTitle = cardDiv?.querySelector('.card-title')?.textContent;

                // Match by title
                if (cardTitle && cardTitle.trim() === cardData.title.trim()) {
                    cardElement = cardDiv;
                    gridItem = item;
                    break;
                }
            }
        }

        // Fallback: search by element ID in content
        if (!cardElement) {
            const gridItems = document.querySelectorAll('.react-grid-item');
            for (const item of gridItems) {
                const cardDiv = item.querySelector('.card');
                if (cardDiv && (
                    cardDiv.querySelector(`[id*="${elementId}"]`) ||
                    cardDiv.querySelector(`[class*="${elementId}"]`)
                )) {
                    cardElement = cardDiv;
                    gridItem = item;
                    break;
                }
            }
        }

        const hasDOM = !!cardElement;
        const hasComponent = !!(window.cardComponents && window.cardComponents[elementId]);

        let hasError = false;
        let domNodeCount = 0;
        let errorElements = [];
        let hasContent = false;

        if (hasDOM) {
            domNodeCount = cardElement.querySelectorAll('*').length;
            errorElements = Array.from(cardElement.querySelectorAll('.error, .error-message, [class*="error"]'));

            // Filter out false positives - only count elements with actual error text
            errorElements = errorElements.filter(el => {
                const text = el.textContent.toLowerCase();
                return text.includes('error') || text.includes('fail') || text.includes('unable');
            });

            hasError = errorElements.length > 0;

            // Check if card has meaningful content (more than just structure)
            hasContent = domNodeCount > 10 || cardElement.textContent.trim().length > 50;
        }

        const validationResult = {
            exists: true,
            cardId: params.cardId,
            elementId: elementId,
            title: cardData.title,
            url: cardData.url,
            hasDOM,
            hasComponent,
            hasError,
            errorCount: errorElements.length,
            domNodeCount,
            hasContent,
            isValid: hasDOM && !hasError,
            foundBy: cardElement ? (gridItem ? 'title-match' : 'getElementById') : 'not-found',
            timestamp: new Date().toISOString()
        };

        // Log validation results to server for QA
        if (window.logToServer) {
            const logLevel = !hasDOM ? 'Warning' : (hasError ? 'Warning' : 'Info');
            const status = validationResult.isValid ? 'VALID' : 'INVALID';

            window.logToServer(
                `Card validation: ${cardData.title || params.cardId} - ${status}`,
                'CardValidation',
                logLevel,
                validationResult
            );
        }

        return validationResult;
    },

    /**
     * Close all currently open cards
     */
    closeAllCards: () => {
        if (!window.removeCard) {
            throw new Error('window.removeCard function not available');
        }

        const cards = window.appData?.elements || {};
        const closedCards = [];

        for (const cardId in cards) {
            try {
                window.removeCard(cardId);
                closedCards.push(cardId);
            } catch (error) {
                console.error(`Failed to close card ${cardId}:`, error);
            }
        }

        return {
            success: true,
            closedCards,
            count: closedCards.length,
            message: `Closed ${closedCards.length} cards`
        };
    },

    /**
     * Get count of currently open cards
     */
    getCardCount: () => {
        const cards = window.appData?.elements || {};
        const cardCount = Object.keys(cards).length;

        return {
            count: cardCount,
            cardIds: Object.keys(cards)
        };
    },

    /**
     * Wait for card to finish loading
     * @param {object} params - { cardId, timeoutMs }
     */
    waitForCardLoad: async (params) => {
        if (!params.cardId) {
            throw new Error('Missing parameter: cardId');
        }

        const timeoutMs = params.timeoutMs || 5000;
        const startTime = Date.now();

        while (Date.now() - startTime < timeoutMs) {
            const cardElement = document.getElementById(params.cardId);

            if (!cardElement) {
                throw new Error(`Card element not found: ${params.cardId}`);
            }

            // Check if card has finished loading (no loading indicators)
            const loadingElements = cardElement.querySelectorAll('.loading, .spinner, [class*="loading"]');
            const hasError = cardElement.querySelector('.error, .error-message, [class*="error"]');
            const hasContent = cardElement.querySelectorAll('*').length > 5; // More than just wrapper

            if (hasError) {
                throw new Error('Card has error elements');
            }

            if (hasContent && loadingElements.length === 0) {
                return {
                    success: true,
                    cardId: params.cardId,
                    loadTimeMs: Date.now() - startTime,
                    hasContent: true
                };
            }

            await new Promise(resolve => setTimeout(resolve, 100));
        }

        throw new Error(`Card did not finish loading within ${timeoutMs}ms`);
    },

    /**
     * Get card performance metrics
     * @param {object} params - { cardId }
     */
    getCardMetrics: (params) => {
        if (!params.cardId) {
            throw new Error('Missing parameter: cardId');
        }

        const cardElement = document.getElementById(params.cardId);
        if (!cardElement) {
            throw new Error(`Card element not found: ${params.cardId}`);
        }

        const cards = window.appData?.elements || {};
        const cardData = cards[params.cardId];

        const domNodeCount = cardElement.querySelectorAll('*').length;
        const errorCount = cardElement.querySelectorAll('.error, .error-message, [class*="error"]').length;
        const scriptCount = cardElement.querySelectorAll('script').length;
        const imageCount = cardElement.querySelectorAll('img').length;
        const inputCount = cardElement.querySelectorAll('input, textarea, select').length;

        const rect = cardElement.getBoundingClientRect();
        const isVisible = rect.width > 0 && rect.height > 0;

        return {
            cardId: params.cardId,
            elementId: cardData?.Element_Id,
            url: cardData?.url,
            domNodeCount,
            errorCount,
            scriptCount,
            imageCount,
            inputCount,
            dimensions: {
                width: Math.round(rect.width),
                height: Math.round(rect.height)
            },
            isVisible,
            timestamp: new Date().toISOString()
        };
    },

    // ========================================
    // DOM Query Commands
    // ========================================

    /**
     * Query single DOM element
     * @param {object} params - { selector, scope? }
     */
    querySelector: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const scope = params.scope ? document.querySelector(params.scope) : document;
        if (!scope) {
            throw new Error(`Scope element not found: ${params.scope}`);
        }

        const element = scope.querySelector(params.selector);

        if (!element) {
            return {
                found: false,
                selector: params.selector,
                scope: params.scope || 'document'
            };
        }

        const rect = element.getBoundingClientRect();

        return {
            found: true,
            selector: params.selector,
            tagName: element.tagName,
            id: element.id || null,
            className: element.className || null,
            text: element.textContent?.substring(0, 200) || null,
            attributes: Array.from(element.attributes).reduce((acc, attr) => {
                acc[attr.name] = attr.value;
                return acc;
            }, {}),
            rect: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
            },
            visible: rect.width > 0 && rect.height > 0
        };
    },

    /**
     * Query multiple DOM elements
     * @param {object} params - { selector, scope?, maxResults? }
     */
    querySelectorAll: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const scope = params.scope ? document.querySelector(params.scope) : document;
        if (!scope) {
            throw new Error(`Scope element not found: ${params.scope}`);
        }

        const elements = scope.querySelectorAll(params.selector);
        const maxResults = params.maxResults || 50;

        const results = Array.from(elements).slice(0, maxResults).map(el => {
            const rect = el.getBoundingClientRect();
            return {
                tagName: el.tagName,
                id: el.id || null,
                className: el.className || null,
                text: el.textContent?.substring(0, 100) || null,
                visible: rect.width > 0 && rect.height > 0
            };
        });

        return {
            selector: params.selector,
            count: elements.length,
            returned: results.length,
            truncated: elements.length > maxResults,
            elements: results
        };
    },

    /**
     * Get detailed element properties
     * @param {object} params - { selector, styleProps? }
     */
    getElementProperties: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const element = document.querySelector(params.selector);
        if (!element) {
            throw new Error(`Element not found: ${params.selector}`);
        }

        const rect = element.getBoundingClientRect();
        const computedStyle = window.getComputedStyle(element);

        const styleProps = params.styleProps || ['display', 'visibility', 'position', 'width', 'height', 'color', 'backgroundColor'];
        const styles = {};
        styleProps.forEach(prop => {
            styles[prop] = computedStyle[prop];
        });

        return {
            selector: params.selector,
            tagName: element.tagName,
            id: element.id || null,
            className: element.className || null,
            attributes: Array.from(element.attributes).reduce((acc, attr) => {
                acc[attr.name] = attr.value;
                return acc;
            }, {}),
            innerHTML: element.innerHTML.substring(0, 500),
            textContent: element.textContent?.substring(0, 200) || null,
            rect: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height),
                top: Math.round(rect.top),
                left: Math.round(rect.left)
            },
            computedStyle: styles,
            visible: rect.width > 0 && rect.height > 0 && computedStyle.visibility !== 'hidden' && computedStyle.display !== 'none'
        };
    },

    /**
     * Get element outerHTML
     * @param {object} params - { selector, maxLength? }
     */
    getOuterHTML: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const element = document.querySelector(params.selector);
        if (!element) {
            throw new Error(`Element not found: ${params.selector}`);
        }

        const maxLength = params.maxLength || 5000;
        const outerHTML = element.outerHTML;

        return {
            selector: params.selector,
            outerHTML: outerHTML.substring(0, maxLength),
            fullLength: outerHTML.length,
            truncated: outerHTML.length > maxLength
        };
    },

    // ========================================
    // DOM Manipulation Commands
    // ========================================

    /**
     * Set element attribute
     * @param {object} params - { selector, attribute, value }
     */
    setElementAttribute: (params) => {
        if (!params.selector || !params.attribute) {
            throw new Error('Missing required parameters: selector, attribute');
        }

        const elements = document.querySelectorAll(params.selector);
        if (elements.length === 0) {
            throw new Error(`No elements found: ${params.selector}`);
        }

        elements.forEach(el => {
            if (params.value !== undefined && params.value !== null) {
                el.setAttribute(params.attribute, params.value);
            } else {
                el.removeAttribute(params.attribute);
            }
        });

        return {
            success: true,
            selector: params.selector,
            attribute: params.attribute,
            value: params.value,
            elementsModified: elements.length
        };
    },

    /**
     * Set element HTML content
     * @param {object} params - { selector, html, mode: 'inner'|'outer'|'append'|'prepend' }
     */
    setElementHTML: (params) => {
        if (!params.selector || params.html === undefined) {
            throw new Error('Missing required parameters: selector, html');
        }

        const element = document.querySelector(params.selector);
        if (!element) {
            throw new Error(`Element not found: ${params.selector}`);
        }

        const mode = params.mode || 'inner';

        switch (mode) {
            case 'inner':
                element.innerHTML = params.html;
                break;
            case 'outer':
                element.outerHTML = params.html;
                break;
            case 'append':
                element.insertAdjacentHTML('beforeend', params.html);
                break;
            case 'prepend':
                element.insertAdjacentHTML('afterbegin', params.html);
                break;
            default:
                throw new Error(`Invalid mode: ${mode}. Must be inner, outer, append, or prepend`);
        }

        return {
            success: true,
            selector: params.selector,
            mode,
            htmlLength: params.html.length
        };
    },

    /**
     * Set element styles
     * @param {object} params - { selector, styles: { prop: value } }
     */
    setElementStyle: (params) => {
        if (!params.selector || !params.styles) {
            throw new Error('Missing required parameters: selector, styles');
        }

        const elements = document.querySelectorAll(params.selector);
        if (elements.length === 0) {
            throw new Error(`No elements found: ${params.selector}`);
        }

        elements.forEach(el => {
            Object.entries(params.styles).forEach(([prop, value]) => {
                el.style[prop] = value;
            });
        });

        return {
            success: true,
            selector: params.selector,
            styles: params.styles,
            elementsModified: elements.length
        };
    },

    /**
     * Measure element performance metrics
     * @param {object} params - { selector }
     */
    measureElementPerformance: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const element = document.querySelector(params.selector);
        if (!element) {
            throw new Error(`Element not found: ${params.selector}`);
        }

        // Measure node count
        const startNodeCount = performance.now();
        const nodeCount = element.querySelectorAll('*').length;
        const nodeCountTime = performance.now() - startNodeCount;

        // Measure clone time
        const startClone = performance.now();
        const clone = element.cloneNode(true);
        const cloneTime = performance.now() - startClone;

        // Measure query time
        const startQuery = performance.now();
        element.querySelectorAll('div');
        const queryTime = performance.now() - startQuery;

        const rect = element.getBoundingClientRect();

        return {
            selector: params.selector,
            nodeCount,
            measurements: {
                nodeCountTimeMs: nodeCountTime.toFixed(3),
                cloneTimeMs: cloneTime.toFixed(3),
                queryTimeMs: queryTime.toFixed(3)
            },
            rect: {
                width: Math.round(rect.width),
                height: Math.round(rect.height)
            },
            htmlSize: element.outerHTML.length
        };
    },

    /**
     * Highlight element with animated border
     * @param {object} params - { selector, duration?, color? }
     */
    highlightRegion: (params) => {
        if (!params.selector) {
            throw new Error('Missing parameter: selector');
        }

        const element = document.querySelector(params.selector);
        if (!element) {
            throw new Error(`Element not found: ${params.selector}`);
        }

        const duration = params.duration || 3000;
        const color = params.color || '#ff0000';

        const originalOutline = element.style.outline;
        const originalOutlineOffset = element.style.outlineOffset;

        element.style.outline = `3px solid ${color}`;
        element.style.outlineOffset = '2px';
        element.style.transition = 'outline 0.3s ease-in-out';

        setTimeout(() => {
            element.style.outline = originalOutline;
            element.style.outlineOffset = originalOutlineOffset;
        }, duration);

        return {
            success: true,
            selector: params.selector,
            duration,
            color,
            message: `Highlighted element for ${duration}ms`
        };
    }
};
