// In-Browser Unit Test Framework
// Simple, effective testing framework for browser-based code
// Provides test organization, assertions, and reporting

class TestFramework {
    constructor(options = {}) {
        this.suites = new Map(); // suite name -> tests
        this.results = new Map(); // suite name -> results
        this.config = {
            stopOnFailure: false,
            verbose: true,
            ...options
        };
        this.currentSuite = null;
        this.stats = {
            total: 0,
            passed: 0,
            failed: 0,
            skipped: 0,
            duration: 0
        };
    }

    // Define a test suite
    describe(name, callback) {
        this.currentSuite = name;
        this.suites.set(name, []);
        callback();
        this.currentSuite = null;
    }

    // Define a test case
    it(description, callback) {
        if (!this.currentSuite) {
            throw new Error('Test must be inside a describe() block');
        }

        const suite = this.suites.get(this.currentSuite);
        suite.push({
            description: description,
            fn: callback,
            skip: false
        });
    }

    // Skip a test
    xit(description, callback) {
        if (!this.currentSuite) {
            throw new Error('Test must be inside a describe() block');
        }

        const suite = this.suites.get(this.currentSuite);
        suite.push({
            description: description,
            fn: callback,
            skip: true
        });
    }

    // Run all tests
    async runAll() {
        console.log('[TestFramework] Running all test suites...\n');
        this.resetStats();
        const startTime = Date.now();

        for (const [suiteName, tests] of this.suites) {
            await this.runSuite(suiteName);
        }

        this.stats.duration = Date.now() - startTime;
        this.printSummary();
        return this.stats;
    }

    // Run a specific suite
    async runSuite(suiteName) {
        const tests = this.suites.get(suiteName);
        if (!tests) {
            console.error(`[TestFramework] Suite not found: ${suiteName}`);
            return;
        }

        console.log(`\n📋 ${suiteName}`);
        const results = [];

        for (const test of tests) {
            const result = await this.runTest(test, suiteName);
            results.push(result);

            if (result.status === 'failed' && this.config.stopOnFailure) {
                console.log('   ⚠️  Stopping due to failure');
                break;
            }
        }

        this.results.set(suiteName, results);
    }

    // Run a single test
    async runTest(test, suiteName) {
        if (test.skip) {
            console.log(`   ⊘ ${test.description} (skipped)`);
            this.stats.skipped++;
            return { status: 'skipped', error: null, duration: 0 };
        }

        const startTime = Date.now();
        const assertions = new Assertions();

        try {
            // Execute test with assertion context
            await test.fn(assertions);

            const duration = Date.now() - startTime;
            console.log(`   ✓ ${test.description} (${duration}ms)`);

            this.stats.passed++;
            this.stats.total++;
            return { status: 'passed', error: null, duration: duration };

        } catch (error) {
            const duration = Date.now() - startTime;
            console.error(`   ✗ ${test.description} (${duration}ms)`);
            console.error(`     ${error.message}`);

            if (this.config.verbose && error.stack) {
                console.error(`     ${error.stack}`);
            }

            this.stats.failed++;
            this.stats.total++;
            return { status: 'failed', error: error, duration: duration };
        }
    }

    // Reset statistics
    resetStats() {
        this.stats = {
            total: 0,
            passed: 0,
            failed: 0,
            skipped: 0,
            duration: 0
        };
    }

    // Print summary
    printSummary() {
        console.log('\n' + '='.repeat(60));
        console.log('Test Summary');
        console.log('='.repeat(60));
        console.log(`Total:    ${this.stats.total}`);
        console.log(`✓ Passed: ${this.stats.passed}`);
        console.log(`✗ Failed: ${this.stats.failed}`);
        console.log(`⊘ Skipped: ${this.stats.skipped}`);
        console.log(`Duration: ${this.stats.duration}ms`);
        console.log('='.repeat(60));

        if (this.stats.failed === 0) {
            console.log('🎉 All tests passed!');
        } else {
            console.log('❌ Some tests failed.');
        }
    }

    // Get results for display
    getResults() {
        const formatted = [];
        for (const [suiteName, results] of this.results) {
            formatted.push({
                suite: suiteName,
                results: results,
                passed: results.filter(r => r.status === 'passed').length,
                failed: results.filter(r => r.status === 'failed').length,
                skipped: results.filter(r => r.status === 'skipped').length,
                total: results.length
            });
        }
        return formatted;
    }

    // Get overall stats
    getStats() {
        return { ...this.stats };
    }

    // Clear all tests
    clear() {
        this.suites.clear();
        this.results.clear();
        this.resetStats();
    }
}

// Assertion library
class Assertions {
    // Assert that value is truthy
    assert(value, message = 'Expected value to be truthy') {
        if (!value) {
            throw new Error(message);
        }
    }

    // Assert equality
    assertEqual(actual, expected, message) {
        if (actual !== expected) {
            const msg = message || `Expected ${JSON.stringify(expected)} but got ${JSON.stringify(actual)}`;
            throw new Error(msg);
        }
    }

    // Assert deep equality for objects/arrays
    assertDeepEqual(actual, expected, message) {
        const actualStr = JSON.stringify(actual);
        const expectedStr = JSON.stringify(expected);

        if (actualStr !== expectedStr) {
            const msg = message || `Expected ${expectedStr} but got ${actualStr}`;
            throw new Error(msg);
        }
    }

    // Assert inequality
    assertNotEqual(actual, expected, message) {
        if (actual === expected) {
            const msg = message || `Expected value not to equal ${JSON.stringify(expected)}`;
            throw new Error(msg);
        }
    }

    // Assert null
    assertNull(value, message) {
        if (value !== null) {
            const msg = message || `Expected null but got ${JSON.stringify(value)}`;
            throw new Error(msg);
        }
    }

    // Assert not null
    assertNotNull(value, message) {
        if (value === null) {
            const msg = message || 'Expected value to not be null';
            throw new Error(msg);
        }
    }

    // Assert undefined
    assertUndefined(value, message) {
        if (value !== undefined) {
            const msg = message || `Expected undefined but got ${JSON.stringify(value)}`;
            throw new Error(msg);
        }
    }

    // Assert not undefined
    assertNotUndefined(value, message) {
        if (value === undefined) {
            const msg = message || 'Expected value to not be undefined';
            throw new Error(msg);
        }
    }

    // Assert type
    assertType(value, type, message) {
        const actualType = typeof value;
        if (actualType !== type) {
            const msg = message || `Expected type ${type} but got ${actualType}`;
            throw new Error(msg);
        }
    }

    // Assert instance of
    assertInstanceOf(value, constructor, message) {
        if (!(value instanceof constructor)) {
            const msg = message || `Expected instance of ${constructor.name}`;
            throw new Error(msg);
        }
    }

    // Assert array contains
    assertContains(array, value, message) {
        if (!Array.isArray(array) || !array.includes(value)) {
            const msg = message || `Expected array to contain ${JSON.stringify(value)}`;
            throw new Error(msg);
        }
    }

    // Assert array length
    assertLength(array, length, message) {
        if (!Array.isArray(array) || array.length !== length) {
            const msg = message || `Expected length ${length} but got ${array?.length}`;
            throw new Error(msg);
        }
    }

    // Assert object has property
    assertProperty(obj, property, message) {
        if (!obj || !(property in obj)) {
            const msg = message || `Expected object to have property ${property}`;
            throw new Error(msg);
        }
    }

    // Assert throws error
    assertThrows(fn, message) {
        let threw = false;
        try {
            fn();
        } catch (e) {
            threw = true;
        }

        if (!threw) {
            const msg = message || 'Expected function to throw an error';
            throw new Error(msg);
        }
    }

    // Assert async throws error
    async assertThrowsAsync(fn, message) {
        let threw = false;
        try {
            await fn();
        } catch (e) {
            threw = true;
        }

        if (!threw) {
            const msg = message || 'Expected async function to throw an error';
            throw new Error(msg);
        }
    }

    // Assert greater than
    assertGreaterThan(actual, expected, message) {
        if (actual <= expected) {
            const msg = message || `Expected ${actual} to be greater than ${expected}`;
            throw new Error(msg);
        }
    }

    // Assert greater than or equal
    assertGreaterThanOrEqual(actual, expected, message) {
        if (actual < expected) {
            const msg = message || `Expected ${actual} to be greater than or equal to ${expected}`;
            throw new Error(msg);
        }
    }

    // Assert less than
    assertLessThan(actual, expected, message) {
        if (actual >= expected) {
            const msg = message || `Expected ${actual} to be less than ${expected}`;
            throw new Error(msg);
        }
    }

    // Assert matches regex
    assertMatches(string, regex, message) {
        if (!regex.test(string)) {
            const msg = message || `Expected "${string}" to match ${regex}`;
            throw new Error(msg);
        }
    }
}

// Test result formatter for UI display
class TestResultFormatter {
    static toHTML(results) {
        let html = '<div class="test-results">';

        for (const suite of results) {
            const passRate = suite.total > 0 ? (suite.passed / suite.total * 100).toFixed(1) : 0;
            const statusClass = suite.failed === 0 ? 'success' : 'failed';

            html += `
                <div class="test-suite ${statusClass}">
                    <h3>${suite.suite}</h3>
                    <div class="test-stats">
                        <span class="passed">${suite.passed} passed</span>
                        <span class="failed">${suite.failed} failed</span>
                        <span class="skipped">${suite.skipped} skipped</span>
                        <span class="pass-rate">${passRate}%</span>
                    </div>
                    <div class="test-cases">
            `;

            for (let i = 0; i < suite.results.length; i++) {
                const result = suite.results[i];
                const icon = result.status === 'passed' ? '✓' :
                            result.status === 'failed' ? '✗' : '⊘';
                const statusClass = result.status;

                html += `
                    <div class="test-case ${statusClass}">
                        <span class="icon">${icon}</span>
                        <span class="description">${suite.tests?.[i]?.description || 'Test ' + i}</span>
                        <span class="duration">${result.duration}ms</span>
                `;

                if (result.error) {
                    html += `
                        <div class="error-message">${result.error.message}</div>
                    `;
                }

                html += '</div>';
            }

            html += `
                    </div>
                </div>
            `;
        }

        html += '</div>';
        return html;
    }

    static toMarkdown(results) {
        let md = '# Test Results\n\n';

        for (const suite of results) {
            const passRate = suite.total > 0 ? (suite.passed / suite.total * 100).toFixed(1) : 0;
            const status = suite.failed === 0 ? '✅' : '❌';

            md += `## ${status} ${suite.suite}\n\n`;
            md += `- **Passed:** ${suite.passed}\n`;
            md += `- **Failed:** ${suite.failed}\n`;
            md += `- **Skipped:** ${suite.skipped}\n`;
            md += `- **Pass Rate:** ${passRate}%\n\n`;

            for (let i = 0; i < suite.results.length; i++) {
                const result = suite.results[i];
                const icon = result.status === 'passed' ? '✓' :
                            result.status === 'failed' ? '✗' : '⊘';

                md += `- ${icon} Test ${i + 1} (${result.duration}ms)\n`;

                if (result.error) {
                    md += `  - **Error:** ${result.error.message}\n`;
                }
            }

            md += '\n';
        }

        return md;
    }
}

// Export for use
window.TestFramework = TestFramework;
window.Assertions = Assertions;
window.TestResultFormatter = TestResultFormatter;
