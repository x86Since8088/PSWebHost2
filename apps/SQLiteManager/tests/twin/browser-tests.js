/**
 * Browser Twin Test Template for PSWebHost Apps
 *
 * This template works with the UnitTests app framework (unit-test-framework.js)
 * to provide comprehensive browser-side testing.
 *
 * Usage:
 * 1. Copy this file to apps/[AppName]/tests/twin/browser-tests.js
 * 2. Update the test suite name and tests
 * 3. Register with UnitTests app or run standalone
 */

// Define test suite
const SQLiteManagerBrowserTests = {
    suiteName: 'SQLiteManager Browser Tests',
    version: '1.0.0',
    author: 'PSWebHost',

    // Test setup (runs before all tests)
    async setup() {
        console.log('[Setup] Initializing test environment...');

        // Example: Load required libraries
        // await this.loadScript('/public/lib/yourlib.js');

        // Example: Create test fixtures
        this.testData = {
            sampleId: '123',
            sampleName: 'Test Item'
        };

        console.log('[Setup] Complete');
    },

    // Test teardown (runs after all tests)
    async teardown() {
        console.log('[Teardown] Cleaning up...');

        // Example: Clean up DOM elements
        document.querySelectorAll('.test-fixture').forEach(el => el.remove());

        console.log('[Teardown] Complete');
    },

    // Helper: Load external script
    async loadScript(src) {
        return new Promise((resolve, reject) => {
            const script = document.createElement('script');
            script.src = src;
            script.onload = resolve;
            script.onerror = () => reject(new Error(`Failed to load script: ${src}`));
            document.head.appendChild(script);
        });
    },

    // Helper: Fetch API wrapper
    async apiCall(endpoint, options = {}) {
        const response = await fetch(endpoint, {
            method: options.method || 'GET',
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            body: options.body ? JSON.stringify(options.body) : undefined
        });

        if (!response.ok) {
            throw new Error(`API call failed: ${response.status} ${response.statusText}`);
        }

        return await response.json();
    },

    // Test: Component Loading
    async testComponentLoading() {
        // Check if React card components are available
        if (!window.cardComponents || !window.cardComponents['sqlite-manager']) {
            throw new Error('SQLite Manager component not registered');
        }

        // Verify component is a function/class
        if (typeof window.cardComponents['sqlite-manager'] !== 'function') {
            throw new Error('SQLite Manager component is not a valid React component');
        }

        return 'Component loaded successfully';
    },

    // Test: API Endpoint Availability
    async testAPIEndpoint() {
        const response = await fetch('/apps/SQLiteManager/api/v1/status');

        if (!response.ok) {
            throw new Error(`Status endpoint returned ${response.status}`);
        }

        const data = await response.json();

        if (!data.app || !data.version) {
            throw new Error('Status endpoint missing required fields');
        }

        return `API endpoint responding correctly (v${data.version})`;
    },

    // Test: Card Metadata Loading
    async testCardMetadata() {
        const response = await fetch('/apps/sqlitemanager/cards/sqlite-manager');

        if (!response.ok) {
            throw new Error(`Card endpoint returned ${response.status}`);
        }

        const metadata = await response.json();

        if (!metadata.component || metadata.component !== 'sqlite-manager') {
            throw new Error('Card metadata missing or incorrect component name');
        }

        if (!metadata.scriptPath || !metadata.scriptPath.includes('sqlite-manager/component.js')) {
            throw new Error('Card metadata missing or incorrect script path');
        }

        return 'Card metadata loads correctly';
    },

    // Test: SQLite Query Execution
    async testQueryExecution() {
        // Test SELECT query
        const queryData = { query: "SELECT name FROM sqlite_master WHERE type='table' LIMIT 1" };
        const response = await fetch('/apps/sqlitemanager/api/v1/sqlite/query', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(queryData)
        });

        if (!response.ok) {
            throw new Error(`Query endpoint returned ${response.status}`);
        }

        const result = await response.json();

        if (!result.success) {
            throw new Error(`Query execution failed: ${result.error || 'Unknown error'}`);
        }

        if (result.queryType !== 'SELECT') {
            throw new Error(`Expected queryType SELECT, got ${result.queryType}`);
        }

        if (!Array.isArray(result.rows)) {
            throw new Error('Query result should contain rows array');
        }

        return `Query executed successfully (${result.rows.length} rows in ${result.executionTime}ms)`;
    },

    // Test: Invalid Query Handling
    async testInvalidQueryHandling() {
        // Test with empty query
        const emptyQueryData = { query: "" };
        const response1 = await fetch('/apps/sqlitemanager/api/v1/sqlite/query', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(emptyQueryData)
        });

        if (response1.ok) {
            throw new Error('Empty query should return error status');
        }

        // Test with invalid SQL
        const invalidQueryData = { query: "INVALID SQL SYNTAX HERE" };
        const response2 = await fetch('/apps/sqlitemanager/api/v1/sqlite/query', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify(invalidQueryData)
        });

        const result = await response2.json();

        if (result.success) {
            throw new Error('Invalid SQL should not succeed');
        }

        if (!result.error) {
            throw new Error('Invalid SQL should return error message');
        }

        return 'Error handling works correctly';
    },

    // Test: Local Storage
    async testLocalStorage() {
        const testKey = 'SQLiteManager_test';
        const testValue = { test: true, timestamp: Date.now() };

        // Write
        localStorage.setItem(testKey, JSON.stringify(testValue));

        // Read
        const retrieved = JSON.parse(localStorage.getItem(testKey));

        if (!retrieved || retrieved.test !== true) {
            throw new Error('Local storage read/write failed');
        }

        // Cleanup
        localStorage.removeItem(testKey);

        return 'Local storage operations successful';
    },

    // Test: Async Operations
    async testAsyncOperations() {
        const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

        const start = Date.now();
        await delay(100);
        const elapsed = Date.now() - start;

        if (elapsed < 90 || elapsed > 200) {
            throw new Error(`Async timing off: ${elapsed}ms`);
        }

        return `Async operations working correctly (${elapsed}ms delay)`;
    },

    // Test: Error Handling
    async testErrorHandling() {
        // Test that errors are properly caught and handled
        try {
            await this.apiCall('/apps/SQLiteManager/api/v1/nonexistent');
            throw new Error('Should have thrown an error for non-existent endpoint');
        } catch (err) {
            if (!err.message.includes('404') && !err.message.includes('failed')) {
                throw new Error('Unexpected error type');
            }
        }

        return 'Error handling works correctly';
    }
};

// Register test suite with UnitTests framework if available
if (typeof window.TestSuites !== 'undefined') {
    window.TestSuites.register(SQLiteManagerBrowserTests);
    console.log(`[TestSuite] Registered: ${SQLiteManagerBrowserTests.suiteName}`);
} else {
    console.warn('[TestSuite] UnitTests framework not found. Run tests manually.');
}

// Export for standalone usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = SQLiteManagerBrowserTests;
}

