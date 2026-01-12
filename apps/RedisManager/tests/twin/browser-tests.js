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
const RedisManagerBrowserTests = {
    suiteName: 'RedisManager Browser Tests',
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
        const testElement = document.createElement('redismanager-home');
        document.body.appendChild(testElement);

        // Wait for component to initialize
        await new Promise(resolve => setTimeout(resolve, 100));

        const initialized = testElement.shadowRoot || testElement.innerHTML;

        if (!initialized) {
            throw new Error('Component did not initialize');
        }

        // Cleanup
        testElement.remove();

        return 'Component loaded successfully';
    },

    // Test: API Endpoint Availability
    async testAPIEndpoint() {
        const response = await fetch('/apps/RedisManager/api/v1/status');

        if (!response.ok) {
            throw new Error(`Status endpoint returned ${response.status}`);
        }

        const data = await response.json();

        if (!data.app || !data.version) {
            throw new Error('Status endpoint missing required fields');
        }

        return `API endpoint responding correctly (v${data.version})`;
    },

    // Test: UI Element Rendering
    async testUIElementRendering() {
        const response = await fetch('/apps/RedisManager/api/v1/ui/elements/RedisManager-home');

        if (!response.ok) {
            throw new Error(`UI endpoint returned ${response.status}`);
        }

        const html = await response.text();

        if (!html.includes('<redismanager-home')) {
            throw new Error('UI endpoint does not contain expected component');
        }

        return 'UI element renders correctly';
    },

    // Test: Data Operations (CRUD)
    async testDataOperations() {
        // Example: Create
        const createData = { name: 'Test Item', value: 42 };
        const created = await this.apiCall('/apps/RedisManager/api/v1/data', {
            method: 'POST',
            body: createData
        });

        if (!created.id) {
            throw new Error('Create operation failed');
        }

        // Example: Read
        const read = await this.apiCall(`/apps/RedisManager/api/v1/data/${created.id}`);

        if (read.name !== createData.name) {
            throw new Error('Read operation returned incorrect data');
        }

        // Example: Update
        const updateData = { ...createData, value: 84 };
        const updated = await this.apiCall(`/apps/RedisManager/api/v1/data/${created.id}`, {
            method: 'PUT',
            body: updateData
        });

        if (updated.value !== 84) {
            throw new Error('Update operation failed');
        }

        // Example: Delete
        await this.apiCall(`/apps/RedisManager/api/v1/data/${created.id}`, {
            method: 'DELETE'
        });

        // Verify deletion
        try {
            await this.apiCall(`/apps/RedisManager/api/v1/data/${created.id}`);
            throw new Error('Delete operation failed - item still exists');
        } catch (err) {
            // Expected to fail (404)
            if (!err.message.includes('404')) {
                throw err;
            }
        }

        return 'CRUD operations completed successfully';
    },

    // Test: Event Handling
    async testEventHandling() {
        const testElement = document.createElement('redismanager-home');
        document.body.appendChild(testElement);

        let eventFired = false;

        testElement.addEventListener('custom-event', () => {
            eventFired = true;
        });

        // Trigger event
        testElement.dispatchEvent(new CustomEvent('custom-event', {
            detail: { test: true }
        }));

        if (!eventFired) {
            throw new Error('Event was not triggered');
        }

        // Cleanup
        testElement.remove();

        return 'Event handling works correctly';
    },

    // Test: Local Storage
    async testLocalStorage() {
        const testKey = 'RedisManager_test';
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
            await this.apiCall('/apps/RedisManager/api/v1/nonexistent');
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
    window.TestSuites.register(RedisManagerBrowserTests);
    console.log(`[TestSuite] Registered: ${RedisManagerBrowserTests.suiteName}`);
} else {
    console.warn('[TestSuite] UnitTests framework not found. Run tests manually.');
}

// Export for standalone usage
if (typeof module !== 'undefined' && module.exports) {
    module.exports = RedisManagerBrowserTests;
}

