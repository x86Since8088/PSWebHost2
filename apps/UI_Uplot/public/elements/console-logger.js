/**
 * PSWebHost Console to API Logger
 *
 * Captures browser console events and optionally sends them to backend API
 * Configured via app.yaml ConsoleToAPILoggingLevel setting
 *
 * Levels: verbose, info, warning, error, none
 */

class ConsoleAPILogger {
    constructor(appName, loggingLevel = 'info') {
        this.appName = appName;
        this.loggingLevel = loggingLevel.toLowerCase();
        this.apiEndpoint = `/apps/${appName}/api/v1/logs`;
        this.buffer = [];
        this.maxBufferSize = 100;
        this.flushInterval = 5000; // 5 seconds
        this.enabled = loggingLevel !== 'none';

        // Log levels hierarchy
        this.levels = {
            verbose: 0,
            info: 1,
            warning: 2,
            error: 3,
            none: 999
        };

        this.currentLevelValue = this.levels[this.loggingLevel] || this.levels.info;

        // Store original console methods
        this.originalConsole = {
            log: console.log.bind(console),
            info: console.info.bind(console),
            warn: console.warn.bind(console),
            error: console.error.bind(console),
            debug: console.debug.bind(console)
        };

        if (this.enabled) {
            this.intercept();
            this.startFlushTimer();
        }

        this.log('info', `Console logger initialized: level=${loggingLevel}, app=${appName}`);
    }

    /**
     * Check if message should be logged based on level
     */
    shouldLog(level) {
        const messageLevelValue = this.levels[level] || this.levels.info;
        return messageLevelValue >= this.currentLevelValue;
    }

    /**
     * Log a message at specified level
     */
    log(level, message, ...args) {
        if (!this.enabled || !this.shouldLog(level)) {
            return;
        }

        const logEntry = {
            timestamp: new Date().toISOString(),
            level: level,
            message: this.formatMessage(message, ...args),
            app: this.appName,
            url: window.location.href,
            userAgent: navigator.userAgent,
            stackTrace: this.getStackTrace()
        };

        // Always log to original console
        const consoleMethod = this.originalConsole[level === 'warning' ? 'warn' : level] || this.originalConsole.log;
        consoleMethod(`[${this.appName}]`, message, ...args);

        // Buffer for API logging
        this.buffer.push(logEntry);

        // Flush immediately for errors
        if (level === 'error') {
            this.flush();
        } else if (this.buffer.length >= this.maxBufferSize) {
            this.flush();
        }
    }

    /**
     * Format message and arguments
     */
    formatMessage(message, ...args) {
        let formatted = String(message);
        if (args.length > 0) {
            formatted += ' ' + args.map(arg => {
                if (typeof arg === 'object') {
                    try {
                        return JSON.stringify(arg, null, 2);
                    } catch (e) {
                        return String(arg);
                    }
                }
                return String(arg);
            }).join(' ');
        }
        return formatted;
    }

    /**
     * Get stack trace (if available)
     */
    getStackTrace() {
        try {
            throw new Error();
        } catch (e) {
            // Remove first 3 lines (Error, getStackTrace, log)
            return e.stack.split('\n').slice(3).join('\n');
        }
    }

    /**
     * Intercept console methods
     */
    intercept() {
        const self = this;

        console.log = function(...args) {
            self.log('verbose', ...args);
        };

        console.info = function(...args) {
            self.log('info', ...args);
        };

        console.warn = function(...args) {
            self.log('warning', ...args);
        };

        console.error = function(...args) {
            self.log('error', ...args);
        };

        console.debug = function(...args) {
            self.log('verbose', ...args);
        };

        // Intercept window errors
        window.addEventListener('error', (event) => {
            self.log('error', `Uncaught Error: ${event.message}`, {
                filename: event.filename,
                lineno: event.lineno,
                colno: event.colno,
                error: event.error ? event.error.stack : null
            });
        });

        // Intercept unhandled promise rejections
        window.addEventListener('unhandledrejection', (event) => {
            self.log('error', 'Unhandled Promise Rejection:', event.reason);
        });
    }

    /**
     * Flush buffered logs to API
     */
    async flush() {
        if (this.buffer.length === 0) {
            return;
        }

        const logsToSend = [...this.buffer];
        this.buffer = [];

        try {
            const response = await fetch(this.apiEndpoint, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({
                    logs: logsToSend,
                    session: this.getSessionId()
                })
            });

            if (!response.ok) {
                // Failed to send logs, but don't recurse - use original console
                this.originalConsole.warn('[ConsoleLogger] Failed to send logs to API:', response.status);
            }
        } catch (error) {
            // Network error, use original console
            this.originalConsole.warn('[ConsoleLogger] Network error sending logs:', error.message);
        }
    }

    /**
     * Get session ID from cookie or generate one
     */
    getSessionId() {
        // Try to get PSWebHost session ID
        const cookies = document.cookie.split(';');
        for (let cookie of cookies) {
            const [name, value] = cookie.trim().split('=');
            if (name === 'PSWebSessionID') {
                return value;
            }
        }
        return 'anonymous';
    }

    /**
     * Start periodic flush timer
     */
    startFlushTimer() {
        setInterval(() => {
            this.flush();
        }, this.flushInterval);
    }

    /**
     * Public API methods for manual logging
     */
    verbose(...args) {
        this.log('verbose', ...args);
    }

    info(...args) {
        this.log('info', ...args);
    }

    warning(...args) {
        this.log('warning', ...args);
    }

    error(...args) {
        this.log('error', ...args);
    }

    /**
     * Update logging level dynamically
     */
    setLevel(newLevel) {
        this.loggingLevel = newLevel.toLowerCase();
        this.currentLevelValue = this.levels[this.loggingLevel] || this.levels.info;
        this.enabled = this.loggingLevel !== 'none';
        this.originalConsole.info(`[ConsoleLogger] Level changed to: ${newLevel}`);
    }

    /**
     * Get current statistics
     */
    getStats() {
        return {
            level: this.loggingLevel,
            buffered: this.buffer.length,
            maxBufferSize: this.maxBufferSize,
            flushInterval: this.flushInterval,
            enabled: this.enabled
        };
    }

    /**
     * Cleanup and restore original console
     */
    destroy() {
        console.log = this.originalConsole.log;
        console.info = this.originalConsole.info;
        console.warn = this.originalConsole.warn;
        console.error = this.originalConsole.error;
        console.debug = this.originalConsole.debug;

        this.flush(); // Final flush
        this.originalConsole.info('[ConsoleLogger] Destroyed and console restored');
    }
}

// Export for browser usage
if (typeof window !== 'undefined') {
    window.ConsoleAPILogger = ConsoleAPILogger;
}
