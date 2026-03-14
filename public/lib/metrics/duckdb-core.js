/**
 * DuckDB Core - Initialization and connection management for DuckDB-WASM
 *
 * Provides centralized DuckDB-WASM setup with:
 * - Bundle loading with retry logic
 * - Connection management
 * - Resource cleanup
 * - Error handling
 *
 * Usage:
 *   const core = await DuckDBCore.create({ dbName: 'MyMetrics' });
 *   const result = await core.query('SELECT * FROM metrics');
 *   await core.close();
 */

class DuckDBCore {
    constructor(options = {}) {
        this.db = null;
        this.conn = null;
        this.initialized = false;
        this.options = {
            bundleUrls: {
                local: '/public/lib/duckdb-browser.mjs',
                cdn: 'https://cdn.jsdelivr.net/npm/@duckdb/duckdb-wasm@latest/dist/duckdb-browser.mjs'
            },
            wasmUrl: '/public/lib/duckdb-mvp.wasm',
            workerUrl: '/public/lib/duckdb-browser-mvp.worker.js',
            retryDelays: [1000, 2000, 5000, 10000, 30000],
            ...options
        };
        this.DUCKDB = null;
    }

    /**
     * Load DuckDB ES module with retry logic
     * @private
     */
    async _loadDuckDBModule() {
        const urls = [
            this.options.bundleUrls.local,
            this.options.bundleUrls.cdn
        ];
        const delays = this.options.retryDelays;

        for (const url of urls) {
            const isLocal = url.startsWith('/');
            console.log(`[DuckDBCore] Loading DuckDB from ${isLocal ? 'local' : 'CDN'}: ${url}`);

            for (let attempt = 0; attempt < delays.length; attempt++) {
                try {
                    const module = await import(url);
                    console.log(`[DuckDBCore] Successfully loaded DuckDB module`);
                    return module;
                } catch (err) {
                    console.warn(`[DuckDBCore] Attempt ${attempt + 1}/${delays.length} failed: ${err.message}`);
                    if (attempt < delays.length - 1) {
                        await this._sleep(delays[attempt]);
                    }
                }
            }
            console.log(`[DuckDBCore] Trying next URL...`);
        }

        throw new Error('Failed to load DuckDB module from all sources');
    }

    /**
     * Sleep helper
     * @private
     */
    _sleep(ms) {
        return new Promise(resolve => setTimeout(resolve, ms));
    }

    /**
     * Initialize DuckDB-WASM
     * @returns {Promise<void>}
     */
    async initialize() {
        if (this.initialized) {
            console.warn('[DuckDBCore] Already initialized');
            return;
        }

        try {
            // Load DuckDB module
            this.DUCKDB = await this._loadDuckDBModule();

            // Get available bundles
            const bundles = await this.DUCKDB.selectBundle({
                mvp: {
                    mainModule: this.options.wasmUrl,
                    mainWorker: this.options.workerUrl
                }
            });

            // Create worker and logger
            const worker = new Worker(bundles.mainWorker);
            const logger = new this.DUCKDB.ConsoleLogger();

            // Instantiate DuckDB
            this.db = new this.DUCKDB.AsyncDuckDB(logger, worker);
            await this.db.instantiate(bundles.mainModule);

            // Open database (in-memory)
            await this.db.open({ path: ':memory:' });

            // Create connection
            this.conn = await this.db.connect();

            this.initialized = true;
            console.log('[DuckDBCore] DuckDB-WASM initialized successfully');

        } catch (err) {
            console.error('[DuckDBCore] Initialization failed:', err);
            throw err;
        }
    }

    /**
     * Get database connection
     * @returns {Object} DuckDB connection
     */
    getConnection() {
        if (!this.initialized) {
            throw new Error('DuckDBCore not initialized. Call initialize() first.');
        }
        return this.conn;
    }

    /**
     * Execute a query and return results
     * @param {string} sql - SQL query
     * @param {Array} params - Query parameters (optional)
     * @returns {Promise<Array>} Query results as array of objects
     */
    async query(sql, params = []) {
        if (!this.initialized) {
            throw new Error('DuckDBCore not initialized');
        }

        try {
            let result;
            if (params.length > 0) {
                const stmt = await this.conn.prepare(sql);
                result = await stmt.query(...params);
                await stmt.close();
            } else {
                result = await this.conn.query(sql);
            }

            // Convert Arrow table to JS array
            return result.toArray().map(row => row.toJSON());
        } catch (err) {
            console.error('[DuckDBCore] Query error:', err, 'SQL:', sql);
            throw err;
        }
    }

    /**
     * Execute a statement without returning results
     * @param {string} sql - SQL statement
     * @returns {Promise<void>}
     */
    async exec(sql) {
        if (!this.initialized) {
            throw new Error('DuckDBCore not initialized');
        }

        try {
            await this.conn.query(sql);
        } catch (err) {
            console.error('[DuckDBCore] Exec error:', err, 'SQL:', sql);
            throw err;
        }
    }

    /**
     * Execute multiple statements in a transaction
     * @param {Function} fn - Function receiving connection, should return Promise
     * @returns {Promise<any>} Result of fn
     */
    async transaction(fn) {
        if (!this.initialized) {
            throw new Error('DuckDBCore not initialized');
        }

        await this.conn.query('BEGIN TRANSACTION');
        try {
            const result = await fn(this.conn);
            await this.conn.query('COMMIT');
            return result;
        } catch (err) {
            await this.conn.query('ROLLBACK');
            throw err;
        }
    }

    /**
     * Close database and cleanup resources
     * @returns {Promise<void>}
     */
    async close() {
        if (!this.initialized) {
            return;
        }

        try {
            if (this.conn) {
                await this.conn.close();
                this.conn = null;
            }
            if (this.db) {
                await this.db.terminate();
                this.db = null;
            }
            this.initialized = false;
            console.log('[DuckDBCore] Database closed');
        } catch (err) {
            console.error('[DuckDBCore] Error closing database:', err);
            throw err;
        }
    }

    /**
     * Check if initialized
     * @returns {boolean}
     */
    isInitialized() {
        return this.initialized;
    }

    /**
     * Static factory method
     * @param {Object} options - Configuration options
     * @returns {Promise<DuckDBCore>}
     */
    static async create(options = {}) {
        const core = new DuckDBCore(options);
        await core.initialize();
        return core;
    }
}

// Export for ES modules and global
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { DuckDBCore };
}
if (typeof window !== 'undefined') {
    window.DuckDBCore = DuckDBCore;
}
