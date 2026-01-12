// Unit Test Runner Component
// UI for running in-browser unit tests
// Accessible to users with debug role

const UnitTestRunnerComponent = ({ element, onError }) => {
    const [testFramework, setTestFramework] = React.useState(null);
    const [results, setResults] = React.useState(null);
    const [stats, setStats] = React.useState(null);
    const [running, setRunning] = React.useState(false);
    const [selectedSuite, setSelectedSuite] = React.useState('all');
    const [view, setView] = React.useState('summary'); // summary, details, console

    // Load test framework and tests
    React.useEffect(() => {
        const loadFramework = async () => {
            try {
                // Load test framework
                if (typeof window.TestFramework === 'undefined') {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/unit-test-framework.js';
                        script.onload = () => {
                            console.log('TestFramework loaded');
                            resolve();
                        };
                        script.onerror = () => reject(new Error('Failed to load TestFramework'));
                        document.head.appendChild(script);
                    });
                }

                // Load test suites
                if (typeof window.loadTestSuites === 'undefined') {
                    await new Promise((resolve, reject) => {
                        const script = document.createElement('script');
                        script.src = '/public/lib/test-suites.js';
                        script.onload = () => {
                            console.log('Test suites loaded');
                            resolve();
                        };
                        script.onerror = () => {
                            console.warn('No test suites file found, using empty suite');
                            resolve();
                        };
                        document.head.appendChild(script);
                    });
                }

                // Create framework instance
                const framework = new window.TestFramework({
                    stopOnFailure: false,
                    verbose: true
                });

                // Load test suites if function exists
                if (typeof window.loadTestSuites === 'function') {
                    window.loadTestSuites(framework);
                }

                setTestFramework(framework);

            } catch (error) {
                console.error('Error loading test framework:', error);
                if (onError) onError(error);
            }
        };

        loadFramework();
    }, []);

    // Run tests
    const runTests = async () => {
        if (!testFramework) return;

        setRunning(true);
        setResults(null);
        setStats(null);

        try {
            let testStats;

            if (selectedSuite === 'all') {
                testStats = await testFramework.runAll();
            } else {
                await testFramework.runSuite(selectedSuite);
                testStats = testFramework.getStats();
            }

            const testResults = testFramework.getResults();
            setResults(testResults);
            setStats(testStats);

        } catch (error) {
            console.error('Error running tests:', error);
            if (onError) onError(error);
        } finally {
            setRunning(false);
        }
    };

    // Get list of test suites
    const getSuites = () => {
        if (!testFramework) return [];
        return Array.from(testFramework.suites.keys());
    };

    // Render summary view
    const renderSummary = () => {
        if (!stats) return null;

        const passRate = stats.total > 0 ? (stats.passed / stats.total * 100).toFixed(1) : 0;
        const overallStatus = stats.failed === 0 ? 'success' : 'failed';

        return React.createElement('div', { className: 'test-summary', style: styles.summary },
            React.createElement('div', {
                className: `status-badge ${overallStatus}`,
                style: overallStatus === 'success' ? styles.successBadge : styles.failedBadge
            }, overallStatus === 'success' ? '✓ ALL TESTS PASSED' : '✗ SOME TESTS FAILED'),

            React.createElement('div', { style: styles.statsGrid },
                React.createElement('div', { style: styles.statCard },
                    React.createElement('div', { style: styles.statValue }, stats.total),
                    React.createElement('div', { style: styles.statLabel }, 'Total Tests')
                ),
                React.createElement('div', { style: { ...styles.statCard, borderLeft: '3px solid #22c55e' } },
                    React.createElement('div', { style: { ...styles.statValue, color: '#22c55e' } }, stats.passed),
                    React.createElement('div', { style: styles.statLabel }, 'Passed')
                ),
                React.createElement('div', { style: { ...styles.statCard, borderLeft: '3px solid #ef4444' } },
                    React.createElement('div', { style: { ...styles.statValue, color: '#ef4444' } }, stats.failed),
                    React.createElement('div', { style: styles.statLabel }, 'Failed')
                ),
                React.createElement('div', { style: { ...styles.statCard, borderLeft: '3px solid #f59e0b' } },
                    React.createElement('div', { style: { ...styles.statValue, color: '#f59e0b' } }, stats.skipped),
                    React.createElement('div', { style: styles.statLabel }, 'Skipped')
                ),
                React.createElement('div', { style: styles.statCard },
                    React.createElement('div', { style: styles.statValue }, `${passRate}%`),
                    React.createElement('div', { style: styles.statLabel }, 'Pass Rate')
                ),
                React.createElement('div', { style: styles.statCard },
                    React.createElement('div', { style: styles.statValue }, `${stats.duration}ms`),
                    React.createElement('div', { style: styles.statLabel }, 'Duration')
                )
            )
        );
    };

    // Render details view
    const renderDetails = () => {
        if (!results) return null;

        return React.createElement('div', { style: styles.details },
            results.map(suite =>
                React.createElement('div', {
                    key: suite.suite,
                    style: styles.suiteCard
                },
                    React.createElement('h3', { style: styles.suiteTitle },
                        suite.suite,
                        React.createElement('span', {
                            style: suite.failed === 0 ? styles.passedBadge : styles.failedBadgeSmall
                        }, `${suite.passed}/${suite.total}`)
                    ),
                    React.createElement('div', { style: styles.testCases },
                        suite.results.map((result, idx) =>
                            React.createElement('div', {
                                key: idx,
                                style: {
                                    ...styles.testCase,
                                    backgroundColor: result.status === 'passed' ? '#f0fdf4' :
                                                    result.status === 'failed' ? '#fef2f2' : '#fafafa'
                                }
                            },
                                React.createElement('span', { style: styles.testIcon },
                                    result.status === 'passed' ? '✓' :
                                    result.status === 'failed' ? '✗' : '⊘'
                                ),
                                React.createElement('span', { style: styles.testDescription },
                                    `Test ${idx + 1}`
                                ),
                                React.createElement('span', { style: styles.testDuration },
                                    `${result.duration}ms`
                                ),
                                result.error && React.createElement('div', { style: styles.errorMessage },
                                    result.error.message
                                )
                            )
                        )
                    )
                )
            )
        );
    };

    if (!testFramework) {
        return React.createElement('div', { style: styles.loading },
            'Loading test framework...'
        );
    }

    const suites = getSuites();

    return React.createElement('div', { style: styles.container },
        // Header
        React.createElement('div', { style: styles.header },
            React.createElement('h2', { style: styles.title }, '🧪 Unit Test Runner'),
            React.createElement('p', { style: styles.subtitle },
                'In-browser testing for PSWebHost components and libraries'
            )
        ),

        // Controls
        React.createElement('div', { style: styles.controls },
            React.createElement('select', {
                value: selectedSuite,
                onChange: (e) => setSelectedSuite(e.target.value),
                style: styles.select,
                disabled: running
            },
                React.createElement('option', { value: 'all' }, 'All Test Suites'),
                suites.map(suite =>
                    React.createElement('option', { key: suite, value: suite }, suite)
                )
            ),

            React.createElement('button', {
                onClick: runTests,
                disabled: running || suites.length === 0,
                style: running ? styles.buttonDisabled : styles.button
            }, running ? 'Running Tests...' : 'Run Tests'),

            React.createElement('button', {
                onClick: () => {
                    setResults(null);
                    setStats(null);
                    testFramework.clear();
                },
                style: styles.buttonSecondary,
                disabled: running
            }, 'Clear Results')
        ),

        // View tabs
        results && React.createElement('div', { style: styles.tabs },
            React.createElement('button', {
                onClick: () => setView('summary'),
                style: view === 'summary' ? styles.tabActive : styles.tab
            }, 'Summary'),
            React.createElement('button', {
                onClick: () => setView('details'),
                style: view === 'details' ? styles.tabActive : styles.tab
            }, 'Details')
        ),

        // Results
        React.createElement('div', { style: styles.results },
            !results && !running && React.createElement('div', { style: styles.emptyState },
                React.createElement('div', { style: styles.emptyIcon }, '📋'),
                React.createElement('p', null, 'No tests have been run yet.'),
                React.createElement('p', { style: styles.emptyHint },
                    `${suites.length} test suite(s) available. Select a suite and click "Run Tests".`
                )
            ),

            running && React.createElement('div', { style: styles.loading },
                React.createElement('div', { style: styles.spinner }),
                'Running tests...'
            ),

            results && view === 'summary' && renderSummary(),
            results && view === 'details' && renderDetails()
        )
    );
};

// Styles
const styles = {
    container: {
        padding: '20px',
        backgroundColor: '#ffffff',
        minHeight: '100%',
        fontFamily: 'system-ui, -apple-system, sans-serif'
    },
    header: {
        marginBottom: '24px',
        borderBottom: '2px solid #e5e7eb',
        paddingBottom: '16px'
    },
    title: {
        margin: 0,
        fontSize: '24px',
        fontWeight: '600',
        color: '#111827'
    },
    subtitle: {
        margin: '8px 0 0 0',
        fontSize: '14px',
        color: '#6b7280'
    },
    controls: {
        display: 'flex',
        gap: '12px',
        marginBottom: '20px',
        alignItems: 'center'
    },
    select: {
        padding: '8px 12px',
        fontSize: '14px',
        border: '1px solid #d1d5db',
        borderRadius: '6px',
        backgroundColor: '#ffffff',
        minWidth: '200px',
        cursor: 'pointer'
    },
    button: {
        padding: '8px 16px',
        fontSize: '14px',
        fontWeight: '600',
        backgroundColor: '#3b82f6',
        color: '#ffffff',
        border: 'none',
        borderRadius: '6px',
        cursor: 'pointer'
    },
    buttonDisabled: {
        padding: '8px 16px',
        fontSize: '14px',
        fontWeight: '600',
        backgroundColor: '#d1d5db',
        color: '#6b7280',
        border: 'none',
        borderRadius: '6px',
        cursor: 'not-allowed'
    },
    buttonSecondary: {
        padding: '8px 16px',
        fontSize: '14px',
        fontWeight: '600',
        backgroundColor: '#ffffff',
        color: '#374151',
        border: '1px solid #d1d5db',
        borderRadius: '6px',
        cursor: 'pointer'
    },
    tabs: {
        display: 'flex',
        gap: '4px',
        marginBottom: '16px',
        borderBottom: '1px solid #e5e7eb'
    },
    tab: {
        padding: '8px 16px',
        fontSize: '14px',
        backgroundColor: 'transparent',
        border: 'none',
        borderBottom: '2px solid transparent',
        cursor: 'pointer',
        color: '#6b7280'
    },
    tabActive: {
        padding: '8px 16px',
        fontSize: '14px',
        backgroundColor: 'transparent',
        border: 'none',
        borderBottom: '2px solid #3b82f6',
        cursor: 'pointer',
        color: '#3b82f6',
        fontWeight: '600'
    },
    results: {
        minHeight: '400px'
    },
    loading: {
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '12px',
        padding: '60px',
        color: '#6b7280',
        fontSize: '14px'
    },
    spinner: {
        width: '20px',
        height: '20px',
        border: '3px solid #e5e7eb',
        borderTop: '3px solid #3b82f6',
        borderRadius: '50%',
        animation: 'spin 1s linear infinite'
    },
    emptyState: {
        textAlign: 'center',
        padding: '60px 20px',
        color: '#6b7280'
    },
    emptyIcon: {
        fontSize: '48px',
        marginBottom: '16px'
    },
    emptyHint: {
        fontSize: '12px',
        color: '#9ca3af'
    },
    summary: {
        padding: '20px'
    },
    successBadge: {
        display: 'inline-block',
        padding: '12px 24px',
        backgroundColor: '#22c55e',
        color: '#ffffff',
        borderRadius: '8px',
        fontWeight: '600',
        fontSize: '16px',
        marginBottom: '24px'
    },
    failedBadge: {
        display: 'inline-block',
        padding: '12px 24px',
        backgroundColor: '#ef4444',
        color: '#ffffff',
        borderRadius: '8px',
        fontWeight: '600',
        fontSize: '16px',
        marginBottom: '24px'
    },
    statsGrid: {
        display: 'grid',
        gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
        gap: '16px'
    },
    statCard: {
        padding: '20px',
        backgroundColor: '#f9fafb',
        borderRadius: '8px',
        borderLeft: '3px solid #3b82f6'
    },
    statValue: {
        fontSize: '32px',
        fontWeight: '700',
        color: '#111827',
        marginBottom: '4px'
    },
    statLabel: {
        fontSize: '12px',
        color: '#6b7280',
        textTransform: 'uppercase',
        fontWeight: '600'
    },
    details: {
        display: 'flex',
        flexDirection: 'column',
        gap: '20px'
    },
    suiteCard: {
        backgroundColor: '#f9fafb',
        borderRadius: '8px',
        padding: '16px',
        border: '1px solid #e5e7eb'
    },
    suiteTitle: {
        margin: '0 0 12px 0',
        fontSize: '18px',
        fontWeight: '600',
        color: '#111827',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center'
    },
    passedBadge: {
        padding: '4px 12px',
        backgroundColor: '#22c55e',
        color: '#ffffff',
        borderRadius: '12px',
        fontSize: '12px',
        fontWeight: '600'
    },
    failedBadgeSmall: {
        padding: '4px 12px',
        backgroundColor: '#ef4444',
        color: '#ffffff',
        borderRadius: '12px',
        fontSize: '12px',
        fontWeight: '600'
    },
    testCases: {
        display: 'flex',
        flexDirection: 'column',
        gap: '8px'
    },
    testCase: {
        padding: '12px',
        backgroundColor: '#ffffff',
        borderRadius: '6px',
        border: '1px solid #e5e7eb',
        display: 'flex',
        alignItems: 'center',
        gap: '12px'
    },
    testIcon: {
        fontSize: '16px',
        fontWeight: '700'
    },
    testDescription: {
        flex: 1,
        fontSize: '14px',
        color: '#374151'
    },
    testDuration: {
        fontSize: '12px',
        color: '#9ca3af'
    },
    errorMessage: {
        width: '100%',
        marginTop: '8px',
        padding: '8px',
        backgroundColor: '#fee2e2',
        color: '#991b1b',
        fontSize: '12px',
        borderRadius: '4px',
        fontFamily: 'monospace'
    }
};

// Register component
window.cardComponents = window.cardComponents || {};
window.cardComponents['unit-test-runner'] = UnitTestRunnerComponent;
