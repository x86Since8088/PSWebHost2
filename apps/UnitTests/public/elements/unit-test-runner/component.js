// UnitTestRunner - Browser-based test execution and monitoring
class UnitTestRunner extends React.Component {
    constructor(props) {
        super(props);
        this.state = {
            tests: [],
            selectedTests: new Set(),
            selectAll: false,
            running: false,
            jobId: null,
            results: null,
            coverage: null,
            processData: null,
            history: [],
            activeTab: 'tests', // tests, coverage, history
            error: null,
            elapsedTime: 0
        };
        this.pollInterval = null;
        this.timerInterval = null;
    }

    async componentDidMount() {
        await this.loadTests();
        await this.loadCoverage();
        await this.loadHistory();
    }

    componentWillUnmount() {
        if (this.pollInterval) clearInterval(this.pollInterval);
        if (this.timerInterval) clearInterval(this.timerInterval);
    }

    async loadTests() {
        try {
            const response = await fetch('/apps/unittests/api/v1/tests/list');
            const data = await response.json();
            this.setState({ tests: data.categories || [], error: null });
        } catch (error) {
            this.setState({ error: `Failed to load tests: ${error.message}` });
        }
    }

    async loadCoverage() {
        try {
            const response = await fetch('/apps/unittests/api/v1/coverage');
            const data = await response.json();
            this.setState({ coverage: data, error: null });
        } catch (error) {
            console.error('Failed to load coverage:', error);
        }
    }

    async loadHistory() {
        try {
            const response = await fetch('/apps/unittests/api/v1/tests/results');
            const data = await response.json();
            this.setState({ history: data.history || [] });
        } catch (error) {
            console.error('Failed to load history:', error);
        }
    }

    async loadProcessData() {
        try {
            const response = await fetch('/apps/unittests/api/v1/processes');
            if (response.ok) {
                const data = await response.json();
                this.setState({ processData: data });
            }
        } catch (error) {
            console.error('Failed to load process data:', error);
        }
    }

    toggleTestSelection(testPath) {
        const selected = new Set(this.state.selectedTests);
        if (selected.has(testPath)) {
            selected.delete(testPath);
        } else {
            selected.add(testPath);
        }
        this.setState({ selectedTests: selected });
    }

    toggleSelectAll() {
        const { selectAll, tests } = this.state;
        if (selectAll) {
            this.setState({ selectedTests: new Set(), selectAll: false });
        } else {
            const allTests = new Set();
            tests.forEach(category => {
                category.tests.forEach(test => allTests.add(test.path));
            });
            this.setState({ selectedTests: allTests, selectAll: true });
        }
    }

    async runTests() {
        const { selectedTests } = this.state;
        if (selectedTests.size === 0) {
            this.setState({ error: 'Please select at least one test to run' });
            return;
        }

        this.setState({ running: true, results: null, error: null, elapsedTime: 0, processData: null });

        try {
            const response = await fetch('/apps/unittests/api/v1/tests/run', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    testPaths: Array.from(selectedTests),
                    output: 'Detailed'
                })
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();
            this.setState({ jobId: data.jobId });

            // Start polling for results
            this.startPolling(data.jobId);

            // Start elapsed time counter
            this.timerInterval = setInterval(() => {
                this.setState(prev => ({ elapsedTime: prev.elapsedTime + 1 }));
            }, 1000);

        } catch (error) {
            this.setState({
                error: `Failed to start tests: ${error.message}`,
                running: false
            });
        }
    }

    startPolling(jobId) {
        this.pollInterval = setInterval(async () => {
            try {
                const response = await fetch(`/apps/unittests/api/v1/tests/results?jobId=${jobId}`);
                const data = await response.json();

                if (data.status === 'Completed' || data.status === 'Failed') {
                    clearInterval(this.pollInterval);
                    clearInterval(this.timerInterval);
                    this.setState({
                        running: false,
                        results: data,
                        jobId: null
                    });

                    // Reload coverage and history
                    await this.loadCoverage();
                    await this.loadHistory();
                    await this.loadProcessData();
                }
            } catch (error) {
                console.error('Polling error:', error);
            }
        }, 2000); // Poll every 2 seconds
    }

    formatDuration(seconds) {
        if (!seconds) return '0s';
        if (seconds < 60) return `${seconds.toFixed(1)}s`;
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}m ${secs}s`;
    }

    renderTestTree() {
        const { tests, selectedTests, selectAll } = this.state;

        return React.createElement('div', { className: 'test-tree' },
            React.createElement('div', { className: 'test-tree-header' },
                React.createElement('label', { className: 'test-tree-select-all' },
                    React.createElement('input', {
                        type: 'checkbox',
                        checked: selectAll,
                        onChange: () => this.toggleSelectAll()
                    }),
                    React.createElement('span', null, `Select All (${tests.reduce((sum, cat) => sum + cat.count, 0)} tests)`)
                )
            ),
            tests.map(category =>
                React.createElement('div', { key: category.category, className: 'test-category' },
                    React.createElement('h4', { className: 'category-name' },
                        `${category.category} (${category.count})`
                    ),
                    React.createElement('div', { className: 'test-list' },
                        category.tests.map(test =>
                            React.createElement('label', {
                                key: test.path,
                                className: 'test-item'
                            },
                                React.createElement('input', {
                                    type: 'checkbox',
                                    checked: selectedTests.has(test.path),
                                    onChange: () => this.toggleTestSelection(test.path)
                                }),
                                React.createElement('span', { className: 'test-name', title: test.path },
                                    test.name
                                )
                            )
                        )
                    )
                )
            )
        );
    }

    renderResults() {
        const { results, processData } = this.state;

        if (!results) return null;

        const isSuccess = results.success && results.failed === 0;
        const statusClass = isSuccess ? 'success' : 'failure';

        return React.createElement('div', { className: 'test-results' },
            React.createElement('div', { className: `results-header ${statusClass}` },
                React.createElement('h3', null,
                    isSuccess ? '✅ All Tests Passed!' : `⚠️ ${results.failed} Test(s) Failed`
                )
            ),
            React.createElement('div', { className: 'results-stats' },
                React.createElement('div', { className: 'stat' },
                    React.createElement('span', { className: 'stat-label' }, 'Total'),
                    React.createElement('span', { className: 'stat-value' }, results.totalTests)
                ),
                React.createElement('div', { className: 'stat success' },
                    React.createElement('span', { className: 'stat-label' }, 'Passed'),
                    React.createElement('span', { className: 'stat-value' }, results.passed)
                ),
                React.createElement('div', { className: 'stat failure' },
                    React.createElement('span', { className: 'stat-label' }, 'Failed'),
                    React.createElement('span', { className: 'stat-value' }, results.failed)
                ),
                React.createElement('div', { className: 'stat' },
                    React.createElement('span', { className: 'stat-label' }, 'Skipped'),
                    React.createElement('span', { className: 'stat-value' }, results.skipped)
                ),
                React.createElement('div', { className: 'stat' },
                    React.createElement('span', { className: 'stat-label' }, 'Duration'),
                    React.createElement('span', { className: 'stat-value' }, this.formatDuration(results.duration))
                )
            ),
            processData && processData.summary.leaksDetected &&
                React.createElement('div', { className: 'process-leak-warning' },
                    React.createElement('h4', null, '⚠️ Process Leaks Detected'),
                    React.createElement('p', null,
                        `${processData.summary.newProcesses} orphaned process(es) detected. `,
                        `${processData.summary.cleaned} cleaned, ${processData.summary.failed} failed to clean.`
                    ),
                    processData.testsWithLeaks.length > 0 &&
                        React.createElement('div', { className: 'leak-details' },
                            React.createElement('strong', null, 'Tests with leaks:'),
                            React.createElement('ul', null,
                                processData.testsWithLeaks.map((leak, idx) =>
                                    React.createElement('li', { key: idx },
                                        React.createElement('code', null, `[${leak.pids.join(', ')}]`),
                                        ' ',
                                        leak.testPath
                                    )
                                )
                            )
                        )
                )
        );
    }

    renderCoverage() {
        const { coverage } = this.state;

        if (!coverage) return React.createElement('div', null, 'Loading coverage data...');

        const coverageClass = coverage.coveragePercent >= 80 ? 'excellent' :
                            coverage.coveragePercent >= 60 ? 'good' :
                            coverage.coveragePercent >= 40 ? 'fair' : 'poor';

        return React.createElement('div', { className: 'coverage-report' },
            React.createElement('div', { className: 'coverage-summary' },
                React.createElement('div', { className: `coverage-badge ${coverageClass}` },
                    React.createElement('span', { className: 'coverage-percent' },
                        `${coverage.coveragePercent}%`
                    ),
                    React.createElement('span', { className: 'coverage-label' }, 'Coverage')
                ),
                React.createElement('div', { className: 'coverage-stats' },
                    React.createElement('div', { className: 'stat' },
                        React.createElement('span', { className: 'stat-value' }, coverage.totalRoutes),
                        React.createElement('span', { className: 'stat-label' }, 'Total Routes')
                    ),
                    React.createElement('div', { className: 'stat success' },
                        React.createElement('span', { className: 'stat-value' }, coverage.testedRoutes),
                        React.createElement('span', { className: 'stat-label' }, 'Tested')
                    ),
                    React.createElement('div', { className: 'stat failure' },
                        React.createElement('span', { className: 'stat-value' }, coverage.untestedRoutes),
                        React.createElement('span', { className: 'stat-label' }, 'Untested')
                    )
                )
            ),
            coverage.untestedRoutes > 0 &&
                React.createElement('div', { className: 'untested-routes' },
                    React.createElement('h3', null, `Routes Needing Tests (${coverage.untestedRoutes})`),
                    React.createElement('div', { className: 'untested-by-dir' },
                        coverage.untestedByDirectory.slice(0, 10).map(dir =>
                            React.createElement('div', { key: dir.directory, className: 'dir-group' },
                                React.createElement('h4', null,
                                    `${dir.directory} (${dir.count} untested)`
                                ),
                                React.createElement('ul', { className: 'route-list' },
                                    dir.routes.slice(0, 5).map(route =>
                                        React.createElement('li', { key: `${route.method}-${route.path}` },
                                            React.createElement('span', { className: `method-badge ${route.method.toLowerCase()}` },
                                                route.method
                                            ),
                                            React.createElement('span', { className: 'route-path' }, route.path)
                                        )
                                    ),
                                    dir.routes.length > 5 &&
                                        React.createElement('li', { className: 'more-routes' },
                                            `... and ${dir.routes.length - 5} more`
                                        )
                                )
                            )
                        )
                    )
                )
        );
    }

    renderHistory() {
        const { history } = this.state;

        if (history.length === 0) {
            return React.createElement('div', { className: 'no-history' },
                'No test history available. Run some tests to see history here.'
            );
        }

        return React.createElement('div', { className: 'test-history' },
            React.createElement('h3', null, 'Recent Test Runs'),
            React.createElement('div', { className: 'history-list' },
                history.slice(0, 20).map(entry =>
                    React.createElement('div', {
                        key: entry.jobId,
                        className: `history-entry ${entry.results.success ? 'success' : 'failure'}`
                    },
                        React.createElement('div', { className: 'history-header' },
                            React.createElement('span', { className: 'history-date' },
                                new Date(entry.startTime).toLocaleString()
                            ),
                            React.createElement('span', { className: 'history-user' },
                                entry.userName || 'Unknown'
                            )
                        ),
                        React.createElement('div', { className: 'history-stats' },
                            React.createElement('span', null, `${entry.results.totalTests} tests`),
                            React.createElement('span', { className: 'success' },
                                `${entry.results.passed} passed`
                            ),
                            entry.results.failed > 0 &&
                                React.createElement('span', { className: 'failure' },
                                    `${entry.results.failed} failed`
                                ),
                            React.createElement('span', null, this.formatDuration(entry.results.duration))
                        )
                    )
                )
            )
        );
    }

    render() {
        const { running, error, activeTab, elapsedTime, selectedTests } = this.state;

        return React.createElement('div', { className: 'unit-test-runner' },
            React.createElement('div', { className: 'runner-header' },
                React.createElement('h2', null, '🧪 Unit Test Runner'),
                React.createElement('div', { className: 'runner-actions' },
                    running &&
                        React.createElement('span', { className: 'running-indicator' },
                            `Running... ${this.formatDuration(elapsedTime)}`
                        )
                )
            ),
            error &&
                React.createElement('div', { className: 'error-banner' },
                    React.createElement('strong', null, 'Error: '),
                    error
                ),
            React.createElement('div', { className: 'runner-tabs' },
                React.createElement('button', {
                    className: activeTab === 'tests' ? 'active' : '',
                    onClick: () => this.setState({ activeTab: 'tests' })
                }, 'Tests'),
                React.createElement('button', {
                    className: activeTab === 'coverage' ? 'active' : '',
                    onClick: () => this.setState({ activeTab: 'coverage' })
                }, 'Coverage'),
                React.createElement('button', {
                    className: activeTab === 'history' ? 'active' : '',
                    onClick: () => this.setState({ activeTab: 'history' })
                }, 'History')
            ),
            React.createElement('div', { className: 'runner-content' },
                activeTab === 'tests' &&
                    React.createElement('div', { className: 'tests-view' },
                        React.createElement('div', { className: 'tests-sidebar' },
                            this.renderTestTree(),
                            React.createElement('div', { className: 'sidebar-actions' },
                                React.createElement('button', {
                                    className: 'run-button',
                                    disabled: running || selectedTests.size === 0,
                                    onClick: () => this.runTests()
                                }, running ? 'Running...' : `Run Selected (${selectedTests.size})`)
                            )
                        ),
                        React.createElement('div', { className: 'tests-main' },
                            this.renderResults()
                        )
                    ),
                activeTab === 'coverage' && this.renderCoverage(),
                activeTab === 'history' && this.renderHistory()
            )
        );
    }
}

// Register with card loader
window.customElements.define('unit-test-runner', class extends HTMLElement {
    connectedCallback() {
        ReactDOM.render(
            React.createElement(UnitTestRunner),
            this
        );
    }
});
