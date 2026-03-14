// Debug Command Polling Service
// Runs in background for users with debug role
// Polls for commands from server without requiring visible debug console card

(function() {
    'use strict';

    // Only initialize if not already running
    if (window.DebugPollService) {
        console.log('[DebugPollService] Already initialized');
        return;
    }

    console.log('[DebugPollService] Initializing background command polling');

    // Load command library if not already loaded
    if (!window.DebugCommandLibrary) {
        console.log('[DebugPollService] Loading command library...');
        const script = document.createElement('script');
        script.src = '/apps/WebHostDebugExtensions/public/elements/debug-console/commands.js';
        script.async = false; // Load synchronously to ensure availability
        document.head.appendChild(script);

        // Wait a moment for script to load
        const checkLibraryLoaded = setInterval(() => {
            if (window.DebugCommandLibrary) {
                console.log('[DebugPollService] Command library loaded successfully');
                clearInterval(checkLibraryLoaded);
            }
        }, 100);

        // Timeout after 5 seconds
        setTimeout(() => {
            clearInterval(checkLibraryLoaded);
            if (!window.DebugCommandLibrary) {
                console.error('[DebugPollService] Failed to load command library');
            }
        }, 5000);
    } else {
        console.log('[DebugPollService] Command library already loaded');
    }

    const DebugPollService = {
        pollingInterval: null,
        pollFrequency: 3000, // 3 seconds
        isPolling: false,

        // Execute command received from server
        async executeCommand(cmd) {
            const startTime = performance.now();
            let result = null;
            let error = null;

            console.log(`[DebugPollService] Executing command: ${cmd.Command} (${cmd.Type})`);

            try {
                switch (cmd.Type) {
                    case 'eval':
                        result = eval(cmd.Command);
                        // Handle async functions (Promises)
                        if (result && typeof result.then === 'function') {
                            result = await result;
                        }
                        break;

                    case 'predefined':
                        if (window.DebugCommandLibrary && window.DebugCommandLibrary[cmd.Command]) {
                            result = await window.DebugCommandLibrary[cmd.Command](cmd.Params || {});
                        } else {
                            throw new Error(`Unknown predefined command: ${cmd.Command}`);
                        }
                        break;

                    case 'dom':
                        if (window.DebugCommandLibrary && window.DebugCommandLibrary[cmd.Command]) {
                            result = window.DebugCommandLibrary[cmd.Command](cmd.Params || {});
                        } else {
                            throw new Error(`Unknown DOM command: ${cmd.Command}`);
                        }
                        break;

                    default:
                        throw new Error(`Unknown command type: ${cmd.Type}`);
                }

                // Convert result to string if not already
                if (typeof result === 'object' && result !== null) {
                    result = JSON.stringify(result, null, 2);
                } else if (result !== null && result !== undefined) {
                    result = String(result);
                }

            } catch (err) {
                error = err.message;
                console.error(`[DebugPollService] Command execution error:`, err);
            }

            const execTime = Math.round(performance.now() - startTime);

            // Send result back to server
            // Use PUT for disk persistence (unbuffered), POST for in-memory (buffered)
            // Default to PUT for reliability and persistence
            const resultPayload = {
                CommandID: cmd.CommandID,
                Result: result,
                Error: error,
                ExecutionTime: execTime
            };

            const payloadSize = JSON.stringify(resultPayload).length;
            const usePUT = true;  // Always use PUT for direct-to-disk writes

            try {
                const response = await window.psweb_fetchWithAuthHandling(
                    '/apps/WebHostDebugExtensions/api/v1/debug/commands/result',
                    {
                        method: usePUT ? 'PUT' : 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify(resultPayload)
                    }
                );

                if (response.ok) {
                    const responseData = await response.json();
                    const storageMethod = responseData.saved || (usePUT ? 'disk' : 'memory');
                    console.log(`[DebugPollService] Result sent for command ${cmd.CommandID} (${execTime}ms) - saved to ${storageMethod}`);
                } else {
                    console.warn(`[DebugPollService] Result submission returned ${response.status}`);
                }
            } catch (err) {
                console.error(`[DebugPollService] Failed to send result:`, err);
            }
        },

        // Poll for commands from server
        async poll() {
            if (!this.isPolling) return;

            try {
                // Use psweb_fetchWithAuthHandling if available, otherwise fallback to fetch
                const fetchFn = window.psweb_fetchWithAuthHandling || fetch;
                const response = await fetchFn(
                    '/apps/WebHostDebugExtensions/api/v1/debug/commands/poll'
                );

                if (response.status === 204) {
                    // No commands
                    return;
                }

                if (!response.ok) {
                    console.warn(`[DebugPollService] Poll failed: ${response.status}`);
                    return;
                }

                const data = await response.json();

                if (data.commands && data.commands.length > 0) {
                    console.log(`[DebugPollService] Received ${data.commands.length} command(s)`);

                    // Log to server when poll returns content
                    if (window.logToServer) {
                        window.logToServer(
                            `Debug poll received ${data.commands.length} command(s)`,
                            'DebugPoll',
                            'info',
                            {
                                commandCount: data.commands.length,
                                commands: data.commands.map(c => ({
                                    id: c.CommandID,
                                    type: c.Type,
                                    command: c.Command
                                }))
                            }
                        );
                    }

                    for (const cmd of data.commands) {
                        await this.executeCommand(cmd);
                    }
                }
            } catch (error) {
                // Silently fail - polling errors are expected during navigation
                console.debug(`[DebugPollService] Poll error:`, error);
            }
        },

        // Start polling
        start() {
            if (this.isPolling) {
                console.log('[DebugPollService] Already polling');
                return;
            }

            console.log(`[DebugPollService] Starting polling (every ${this.pollFrequency}ms)`);
            this.isPolling = true;

            // Poll immediately
            this.poll();

            // Then poll at interval
            this.pollingInterval = setInterval(() => {
                this.poll();
            }, this.pollFrequency);
        },

        // Stop polling
        stop() {
            if (!this.isPolling) {
                console.log('[DebugPollService] Not polling');
                return;
            }

            console.log('[DebugPollService] Stopping polling');
            this.isPolling = false;

            if (this.pollingInterval) {
                clearInterval(this.pollingInterval);
                this.pollingInterval = null;
            }
        }
    };

    // Expose globally
    window.DebugPollService = DebugPollService;

    // Auto-start polling
    DebugPollService.start();

    // Stop polling on page unload
    window.addEventListener('beforeunload', () => {
        DebugPollService.stop();
    });

    console.log('[DebugPollService] Initialized and polling started');
})();
