/**
 * Iframe Card Loader - Debug Mode
 *
 * Injected into iframe-based cards when user has debug role.
 * Reports card DOM status back to parent window for validation and QA.
 */

(function() {
    'use strict';

    const LOADER_TAG = '[IframeLoader]';

    console.log(LOADER_TAG, 'Initializing in iframe context');

    // Get card path from iframe src or parent
    const cardPath = window.location.pathname + window.location.search;

    /**
     * Report card DOM status to parent window via logToServer
     */
    window.reportCardDom = function(path, domInfo) {
        const cardInfo = {
            cardPath: path || cardPath,
            location: window.location.href,
            documentReady: document.readyState,
            ...domInfo
        };

        console.log(LOADER_TAG, 'Reporting card DOM:', cardInfo);

        // Use parent's logToServer if available
        if (window.parent && window.parent.logToServer) {
            window.parent.logToServer(
                `Iframe card loaded: ${cardInfo.cardPath}`,
                'IframeCardLoad',
                'Info',
                cardInfo
            );
        }

        // Also log locally
        if (window.logToServer) {
            window.logToServer(
                `Card DOM ready: ${cardInfo.cardPath}`,
                'IframeCardLoad',
                'Info',
                cardInfo
            );
        }

        return cardInfo;
    };

    /**
     * Analyze current DOM state
     */
    function analyzeDom() {
        const analysis = {
            // Basic counts
            totalElements: document.querySelectorAll('*').length,
            totalDivs: document.querySelectorAll('div').length,
            totalScripts: document.querySelectorAll('script').length,
            totalStyles: document.querySelectorAll('style, link[rel="stylesheet"]').length,

            // Content checks
            hasTitle: !!document.title,
            title: document.title,
            bodyHasContent: document.body && document.body.textContent.trim().length > 0,
            bodyTextLength: document.body ? document.body.textContent.trim().length : 0,

            // Error detection
            hasErrorElements: document.querySelectorAll('.error, .error-message, [class*="error"]').length > 0,
            errorElementCount: document.querySelectorAll('.error, .error-message, [class*="error"]').length,
            errorTexts: Array.from(document.querySelectorAll('.error, .error-message, [class*="error"]'))
                .map(el => el.textContent.trim())
                .filter(text => text.length > 0 && text.length < 200)
                .slice(0, 5),

            // Loading indicators
            hasLoadingElements: document.querySelectorAll('.loading, .spinner, [class*="loading"]').length > 0,
            loadingElementCount: document.querySelectorAll('.loading, .spinner, [class*="loading"]').length,

            // React detection
            hasReactRoot: !!document.querySelector('[id*="root"], [id*="app"], [class*="react"]'),
            reactRootIds: Array.from(document.querySelectorAll('[id*="root"], [id*="app"]')).map(el => el.id),

            // Console errors (if available)
            consoleErrors: window.capturedErrors || [],

            // Timing
            loadTime: performance.timing.loadEventEnd - performance.timing.navigationStart,
            domContentLoadedTime: performance.timing.domContentLoadedEventEnd - performance.timing.navigationStart,

            timestamp: new Date().toISOString()
        };

        return analysis;
    }

    /**
     * Wait for DOM to be fully loaded and stable
     */
    function waitForStableDOM(callback, maxWait = 5000) {
        let lastCount = 0;
        let stableCount = 0;
        const checkInterval = 200;
        const requiredStableChecks = 3;
        const startTime = Date.now();

        const check = () => {
            const currentCount = document.querySelectorAll('*').length;
            const loadingElements = document.querySelectorAll('.loading, .spinner, [class*="loading"]').length;

            console.log(LOADER_TAG, `DOM check: ${currentCount} elements, ${loadingElements} loading indicators`);

            // Check if DOM is stable (no new elements added)
            if (currentCount === lastCount && loadingElements === 0) {
                stableCount++;
                if (stableCount >= requiredStableChecks) {
                    console.log(LOADER_TAG, 'DOM is stable');
                    callback();
                    return;
                }
            } else {
                stableCount = 0;
            }

            lastCount = currentCount;

            // Check timeout
            if (Date.now() - startTime > maxWait) {
                console.log(LOADER_TAG, 'Max wait time reached, reporting current state');
                callback();
                return;
            }

            setTimeout(check, checkInterval);
        };

        // Start checking after initial delay
        setTimeout(check, 500);
    }

    /**
     * Capture console errors for reporting
     */
    window.capturedErrors = [];
    const originalConsoleError = console.error;
    console.error = function(...args) {
        window.capturedErrors.push(args.map(arg =>
            typeof arg === 'object' ? JSON.stringify(arg) : String(arg)
        ).join(' '));
        originalConsoleError.apply(console, args);
    };

    /**
     * Initialize when DOM is ready
     */
    function init() {
        console.log(LOADER_TAG, 'DOM ready, waiting for stable state...');

        waitForStableDOM(() => {
            const domAnalysis = analyzeDom();

            console.log(LOADER_TAG, 'DOM analysis complete:', domAnalysis);

            // Report to parent
            window.reportCardDom(cardPath, domAnalysis);

            // Log summary
            const summary = `Iframe loaded: ${domAnalysis.totalElements} elements, ${domAnalysis.errorElementCount} errors, ${domAnalysis.bodyTextLength} chars`;

            if (window.parent && window.parent.logToServer) {
                window.parent.logToServer(
                    summary,
                    'IframeCardLoad',
                    domAnalysis.errorElementCount > 0 ? 'Warning' : 'Info',
                    { path: cardPath, errors: domAnalysis.errorTexts }
                );
            }
        });
    }

    // Start initialization
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        // DOM already loaded
        init();
    }

    console.log(LOADER_TAG, 'Loader script initialized');
})();
