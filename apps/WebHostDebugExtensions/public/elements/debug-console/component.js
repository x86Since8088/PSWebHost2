// Debug Console Component - Browser-side debugging with remote command execution
// Implements long-polling to receive commands from server and execute them

const { useState, useEffect, useRef, useCallback } = React;

const DebugConsole = ({ onError }) => {
    const [commandType, setCommandType] = useState('eval');
    const [command, setCommand] = useState('');
    const [predefinedCommand, setPredefinedCommand] = useState('');
    const [commandParams, setCommandParams] = useState('{}');
    const [targetSession, setTargetSession] = useState('current');
    const [history, setHistory] = useState([]);
    const [queueStatus, setQueueStatus] = useState({ pending: 0, position: 0 });
    const [executing, setExecuting] = useState(false);
    const [autoScroll, setAutoScroll] = useState(true);

    const historyEndRef = useRef(null);
    const pollingRef = useRef(null);

    // Polling for commands from server
    useEffect(() => {
        const pollForCommands = async () => {
            try {
                const response = await window.psweb_fetchWithAuthHandling(
                    '/apps/WebHostDebugExtensions/api/v1/debug/commands/poll'
                );

                if (response.status === 204) {
                    // No commands
                    return;
                }

                if (!response.ok) {
                    throw new Error(`Poll failed: ${response.status}`);
                }

                const data = await response.json();

                if (data.commands && data.commands.length > 0) {
                    for (const cmd of data.commands) {
                        await executeCommand(cmd);
                    }
                }
            } catch (error) {
                console.error('Poll error:', error);
                // Don't show error to user - polling errors are expected during navigation
            }
        };

        // Start polling every 3 seconds
        pollingRef.current = setInterval(pollForCommands, 3000);

        return () => {
            if (pollingRef.current) {
                clearInterval(pollingRef.current);
            }
        };
    }, []);

    // Execute command received from server
    const executeCommand = async (cmd) => {
        const startTime = performance.now();
        let result = null;
        let error = null;

        setExecuting(true);

        // Acknowledge receipt before execution
        try {
            await window.psweb_fetchWithAuthHandling(
                '/apps/WebHostDebugExtensions/api/v1/debug/commands/result',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        CommandID: cmd.CommandID,
                        Status: 'received',
                        Result: null,
                        Error: null,
                        ExecutionTimeMs: 0
                    })
                }
            );
        } catch (ackError) {
            console.warn('Failed to acknowledge command receipt:', ackError);
        }

        try {
            switch (cmd.Type) {
                case 'eval':
                    result = eval(cmd.Command);
                    break;

                case 'predefined':
                    if (window.DebugCommandLibrary && window.DebugCommandLibrary[cmd.Command]) {
                        result = window.DebugCommandLibrary[cmd.Command](cmd.Params);
                    } else {
                        throw new Error(`Unknown predefined command: ${cmd.Command}`);
                    }
                    break;

                case 'dom':
                    result = executeDOMCommand(cmd.Command, cmd.Params);
                    break;

                case 'network':
                    result = await executeNetworkCommand(cmd.Command, cmd.Params);
                    break;

                default:
                    throw new Error(`Unknown command type: ${cmd.Type}`);
            }

            // Convert result to string if not already
            if (typeof result === 'object') {
                result = JSON.stringify(result, null, 2);
            } else if (result !== null && result !== undefined) {
                result = String(result);
            }

        } catch (e) {
            error = e.message;
            console.error('Command execution error:', e);
        }

        const executionTime = performance.now() - startTime;

        // Send result back to server
        try {
            await window.psweb_fetchWithAuthHandling(
                '/apps/WebHostDebugExtensions/api/v1/debug/commands/result',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        CommandID: cmd.CommandID,
                        Result: result,
                        Error: error,
                        ExecutionTimeMs: Math.round(executionTime)
                    })
                }
            );
        } catch (submitError) {
            console.error('Failed to submit result:', submitError);
        }

        setExecuting(false);

        // Add to local history
        addToHistory({
            commandID: cmd.CommandID,
            type: cmd.Type,
            command: cmd.Command,
            result: result,
            error: error,
            executionTime: Math.round(executionTime),
            timestamp: new Date().toISOString()
        });
    };

    // DOM command execution
    const executeDOMCommand = (command, params) => {
        switch (command) {
            case 'highlightElement':
                return highlightElement(params.selector);
            case 'inspectElement':
                return inspectElement(params.selector);
            case 'removeElement':
                return removeElement(params.selector);
            default:
                throw new Error(`Unknown DOM command: ${command}`);
        }
    };

    const highlightElement = (selector) => {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => {
            el.style.outline = '3px solid red';
            setTimeout(() => { el.style.outline = ''; }, 3000);
        });
        return `Highlighted ${elements.length} element(s)`;
    };

    const inspectElement = (selector) => {
        const element = document.querySelector(selector);
        if (!element) return 'Element not found';
        return {
            tagName: element.tagName,
            id: element.id,
            className: element.className,
            attributes: Array.from(element.attributes).map(a => ({ name: a.name, value: a.value })),
            textContent: element.textContent.substring(0, 100)
        };
    };

    const removeElement = (selector) => {
        const elements = document.querySelectorAll(selector);
        elements.forEach(el => el.remove());
        return `Removed ${elements.length} element(s)`;
    };

    // Network command execution
    const executeNetworkCommand = async (command, params) => {
        switch (command) {
            case 'testEndpoint':
                return await testEndpoint(params.url, params.method || 'GET');
            case 'measureLatency':
                return await measureLatency(params.url, params.iterations || 5);
            default:
                throw new Error(`Unknown network command: ${command}`);
        }
    };

    const testEndpoint = async (url, method) => {
        const startTime = performance.now();
        try {
            const response = await fetch(url, { method });
            const duration = performance.now() - startTime;
            return {
                status: response.status,
                statusText: response.statusText,
                duration: Math.round(duration) + 'ms',
                headers: Object.fromEntries(response.headers.entries())
            };
        } catch (error) {
            return { error: error.message };
        }
    };

    const measureLatency = async (url, iterations) => {
        const results = [];
        for (let i = 0; i < iterations; i++) {
            const start = performance.now();
            try {
                await fetch(url, { method: 'HEAD' });
                results.push(performance.now() - start);
            } catch (e) {
                results.push(-1);
            }
        }
        const valid = results.filter(r => r > 0);
        return {
            iterations,
            successful: valid.length,
            avg: Math.round(valid.reduce((a, b) => a + b, 0) / valid.length) + 'ms',
            min: Math.round(Math.min(...valid)) + 'ms',
            max: Math.round(Math.max(...valid)) + 'ms'
        };
    };

    // Add entry to history
    const addToHistory = (entry) => {
        setHistory(prev => [...prev, entry]);
    };

    // Auto-scroll to bottom
    useEffect(() => {
        if (autoScroll && historyEndRef.current) {
            historyEndRef.current.scrollIntoView({ behavior: 'smooth' });
        }
    }, [history, autoScroll]);

    // Fetch command history from server
    const fetchHistory = async () => {
        try {
            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebHostDebugExtensions/api/v1/debug/commands/history?limit=100'
            );
            if (!response.ok) throw new Error(`Failed: ${response.status}`);
            const data = await response.json();
            const historyItems = (data.commands || []).map(cmd => ({
                commandID: cmd.CommandID,
                type: cmd.Type || 'unknown',
                command: cmd.Command || '',
                result: cmd.Result,
                error: cmd.Error,
                executionTime: cmd.ExecutionTimeMs,
                timestamp: cmd.CompletedAt
            }));
            setHistory(historyItems);
        } catch (error) {
            console.error('Failed to fetch history:', error);
            if (onError) onError({ message: error.message });
        }
    };

    // Enqueue command to server
    const enqueueCommand = async () => {
        try {
            let cmdPayload = {
                Type: commandType,
                SessionID: targetSession === 'current' ? null : 'all'
            };

            if (commandType === 'eval') {
                cmdPayload.Command = command;
            } else if (commandType === 'predefined') {
                cmdPayload.Command = predefinedCommand;
                try {
                    cmdPayload.Params = JSON.parse(commandParams);
                } catch (e) {
                    throw new Error('Invalid JSON in parameters');
                }
            }

            const response = await window.psweb_fetchWithAuthHandling(
                '/apps/WebHostDebugExtensions/api/v1/debug/commands/enqueue',
                {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(cmdPayload)
                }
            );

            if (!response.ok) throw new Error(`Enqueue failed: ${response.status}`);
            const result = await response.json();

            setQueueStatus({ pending: result.queuePosition, position: result.queuePosition });

            // Clear input
            setCommand('');
            setPredefinedCommand('');
            setCommandParams('{}');

        } catch (error) {
            console.error('Enqueue error:', error);
            if (onError) onError({ message: error.message });
        }
    };

    // Render
    return React.createElement('div', { className: 'debug-console' },
        // Load CSS
        React.createElement('link', { rel: 'stylesheet', href: '/apps/WebHostDebugExtensions/public/elements/debug-console/style.css' }),

        // Header
        React.createElement('div', { className: 'debug-console-header' },
            React.createElement('h3', null, 'Debug Console'),
            React.createElement('div', { className: 'debug-console-status' },
                executing && React.createElement('span', { className: 'status-badge executing' }, 'Executing...'),
                React.createElement('span', { className: 'queue-status' }, `Queue: ${queueStatus.pending}`)
            )
        ),

        // Input area
        React.createElement('div', { className: 'debug-console-input' },
            React.createElement('div', { className: 'command-type-selector' },
                React.createElement('label', null,
                    React.createElement('input', {
                        type: 'radio',
                        value: 'eval',
                        checked: commandType === 'eval',
                        onChange: (e) => setCommandType(e.target.value)
                    }),
                    'JavaScript Eval'
                ),
                React.createElement('label', null,
                    React.createElement('input', {
                        type: 'radio',
                        value: 'predefined',
                        checked: commandType === 'predefined',
                        onChange: (e) => setCommandType(e.target.value)
                    }),
                    'Predefined Command'
                )
            ),

            commandType === 'eval' ?
                React.createElement('textarea', {
                    className: 'command-input',
                    value: command,
                    onChange: (e) => setCommand(e.target.value),
                    placeholder: 'Enter JavaScript code...',
                    rows: 5
                }) :
                React.createElement('div', { className: 'predefined-command-input' },
                    React.createElement('select', {
                        value: predefinedCommand,
                        onChange: (e) => setPredefinedCommand(e.target.value),
                        className: 'command-select'
                    },
                        React.createElement('option', { value: '' }, '-- Select Command --'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ System Info ━━━'),
                        React.createElement('option', { value: 'dumpState' }, 'Dump Application State'),
                        React.createElement('option', { value: 'browserInfo' }, 'Get Browser Info'),
                        React.createElement('option', { value: 'getSession' }, 'Get Session Data'),
                        React.createElement('option', { value: 'listComponents' }, 'List React Components'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ Performance ━━━'),
                        React.createElement('option', { value: 'measurePerformance' }, 'Measure Page Performance'),
                        React.createElement('option', { value: 'testConsole' }, 'Test Console Logging'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ Storage ━━━'),
                        React.createElement('option', { value: 'clearStorage' }, 'Clear Local Storage'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ Card Lifecycle ━━━'),
                        React.createElement('option', { value: 'listCards' }, 'List All Cards'),
                        React.createElement('option', { value: 'openCard' }, 'Open Card'),
                        React.createElement('option', { value: 'closeCard' }, 'Close Card'),
                        React.createElement('option', { value: 'validateCard' }, 'Validate Card'),
                        React.createElement('option', { value: 'getCardMetrics' }, 'Get Card Metrics'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ DOM Query ━━━'),
                        React.createElement('option', { value: 'querySelector' }, 'Query Element (Single)'),
                        React.createElement('option', { value: 'querySelectorAll' }, 'Query Elements (Multiple)'),
                        React.createElement('option', { value: 'getElementProperties' }, 'Get Element Properties'),
                        React.createElement('option', { value: 'getOuterHTML' }, 'Get Element HTML'),
                        React.createElement('option', { value: '', disabled: true }, '━━━ DOM Manipulation ━━━'),
                        React.createElement('option', { value: 'setElementAttribute' }, 'Set Element Attribute'),
                        React.createElement('option', { value: 'setElementHTML' }, 'Set Element HTML'),
                        React.createElement('option', { value: 'setElementStyle' }, 'Set Element Style'),
                        React.createElement('option', { value: 'measureElementPerformance' }, 'Measure Element Performance'),
                        React.createElement('option', { value: 'highlightRegion' }, 'Highlight Element')
                    ),
                    React.createElement('textarea', {
                        className: 'params-input',
                        value: commandParams,
                        onChange: (e) => setCommandParams(e.target.value),
                        placeholder: 'Parameters (JSON)',
                        rows: 3
                    })
                ),

            React.createElement('div', { className: 'command-controls' },
                React.createElement('label', null,
                    React.createElement('input', {
                        type: 'radio',
                        value: 'current',
                        checked: targetSession === 'current',
                        onChange: (e) => setTargetSession(e.target.value)
                    }),
                    'Current Session Only'
                ),
                React.createElement('label', null,
                    React.createElement('input', {
                        type: 'radio',
                        value: 'all',
                        checked: targetSession === 'all',
                        onChange: (e) => setTargetSession(e.target.value)
                    }),
                    'All Sessions'
                ),
                React.createElement('button', {
                    onClick: enqueueCommand,
                    className: 'btn-execute',
                    disabled: executing || (commandType === 'eval' && !command) || (commandType === 'predefined' && !predefinedCommand)
                }, 'Enqueue Command')
            )
        ),

        // History display
        React.createElement('div', { className: 'debug-console-history' },
            React.createElement('div', { className: 'history-header' },
                React.createElement('h4', null, 'Command History'),
                React.createElement('button', { onClick: fetchHistory, className: 'btn-refresh' }, 'Refresh'),
                React.createElement('button', { onClick: () => setHistory([]), className: 'btn-clear' }, 'Clear'),
                React.createElement('label', null,
                    React.createElement('input', {
                        type: 'checkbox',
                        checked: autoScroll,
                        onChange: (e) => setAutoScroll(e.target.checked)
                    }),
                    'Auto-scroll'
                )
            ),
            React.createElement('div', { className: 'history-items' },
                history.map((item, idx) =>
                    React.createElement('div', { key: idx, className: `history-item ${item.error ? 'error' : 'success'}` },
                        React.createElement('div', { className: 'history-item-header' },
                            React.createElement('span', { className: 'command-type-badge' }, item.type),
                            React.createElement('span', { className: 'timestamp' }, new Date(item.timestamp).toLocaleTimeString()),
                            React.createElement('span', { className: 'execution-time' }, `${item.executionTime}ms`)
                        ),
                        React.createElement('div', { className: 'command-text' }, item.command),
                        item.error ?
                            React.createElement('div', { className: 'error-text' }, item.error) :
                            React.createElement('pre', { className: 'result-text' }, item.result)
                    )
                ),
                React.createElement('div', { ref: historyEndRef })
            )
        )
    );
};

// Load command library
if (!window.DebugCommandLibrary) {
    const script = document.createElement('script');
    script.src = '/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js';
    document.head.appendChild(script);
}

// Register the component
window.cardComponents = window.cardComponents || {};
window.cardComponents['debug-console'] = DebugConsole;
